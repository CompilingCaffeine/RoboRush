class_name Player
extends CharacterBody2D
## The obsolete maintenance robot.
##
## Deliberately thin: it reads intent from PlayerInput, asks MotionController or
## DashController for a velocity, moves the body, fires the WeaponController, and
## hands presentation state to PlayerVisuals. Behaviour that could belong to a
## component goes in one, so item hooks and integrity changes can arrive in later
## milestones without this file growing into a manager.
##
## Actor scripts live beside their scene (scenes/player/) while reusable components
## live in scripts/components/ — a scene owns its root script, and scripts/ holds the
## pieces that scenes compose.

const DRONE_SCENE := preload("res://scenes/player/player_drone.tscn")

## How close the robot must be to use something. Generous: the frustration of a shop stand
## that will not take your money is worse than the risk of buying the wrong one, and the
## stands are far enough apart that the nearest is never ambiguous.
const INTERACT_RANGE := 26.0

## Speed at or below which the robot counts as standing still, for Blocking I/O. See
## `_can_fire_while_moving` for why this is not zero.
const STILLNESS_SPEED := 8.0

@export var config: PlayerConfig

@onready var _input: PlayerInput = %Input
@onready var _motion: MotionController = %Motion
@onready var _dash: DashController = %Dash
@onready var _weapon: WeaponController = %Weapon
@onready var _health: HealthComponent = %Health
@onready var _items: ItemInventory = %Items
@onready var _visuals: PlayerVisuals = %Visuals
@onready var _camera: ShakeCamera = %Camera

var _is_dead := false

## Decaying shove from taking damage. Kept out of `velocity` deliberately — see
## `_apply_knockback`.
var _knockback := Vector2.ZERO

## Debug Drone's escort. Owned here rather than by ItemEffects because a drone is a child
## of the robot — it orbits and travels with it, and parenting is the whole mechanism.
var _drones: Array[PlayerDrone] = []

## Faraday Cage's charges, refilled on entering a room. Held here rather than on the run, unlike the
## death save's debt, because it is *meant* to reset — a shield the player earns back by walking
## through a door is a rhythm; one that has to be tracked across a run is a resource.
var _shields_left := 0

## Seconds the robot has been standing still, for Mutex Lock. Counted rather than sampled because
## the item pays for having stopped, not for the frame it stopped on.
var _still_seconds := 0.0

## True until the first shot after entering a room, which is what Cache Warmer multiplies.
var _room_opening_shot := true

func _ready() -> void:
	assert(config != null, "Player.config is unset: assign a PlayerConfig resource.")
	collision_layer = Teams.body_layer(Teams.Id.PLAYER)
	collision_mask = Teams.body_mask()

	_input.setup(config)
	_motion.setup(config)
	_dash.setup(config)
	_weapon.setup(_weapon.config, Teams.Id.PLAYER)

	# Integrity comes from PlayerConfig rather than the component's own default, so
	# all player tuning stays in one resource.
	_health.configure(config.max_integrity, config.damage_invulnerability)

	# Spec section 6.4's dash immunity, made real. The dash window lives on DashController
	# and the health component asks it, rather than being handed a copy — one window, so
	# the flash the player sees and the damage they take cannot disagree.
	_health.add_immunity_source(_dash.is_invulnerable)

	# The one thing standing between a lethal hit and the summary screen, when the build has bought
	# it. Set here rather than when a failover item is collected, because the guard reads the
	# inventory every time it is consulted — an item picked up mid-fight is armed immediately, and
	# there is no wiring to remember to undo.
	_health.death_guard = _survive_lethal_hit
	# The robot is a target too: an enemy's homing shot asks the same registry the player's does.
	HostileRegistry.register(self, Teams.Id.PLAYER, _health)
	# The shield is asked before every hit lands, so a charge collected mid-fight is live at once.
	_health.damage_absorber = _absorb_with_shield
	EventBus.room_entered.connect(_on_room_entered)

	_dash.dash_started.connect(_on_dash_started)
	_dash.dash_ended.connect(_on_dash_ended)
	_weapon.shot_fired.connect(_on_shot_fired)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_items.item_added.connect(_on_item_added)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_input.poll(delta)

	_dash.step(delta)
	if _input.has_dash_request() and _dash.can_dash():
		_input.consume_dash_request()
		_dash.try_start(_resolve_dash_direction())

	if _dash.is_dashing:
		velocity = _dash.get_frame_velocity(delta)
	else:
		velocity = _motion.step(velocity, _input.move_vector, delta)

	# move_and_slide with a circular shape slides along walls rather than sticking to
	# them, which covers spec section 6.6 (never trap the player in geometry).
	move_and_slide()
	_apply_knockback(delta)

	_step_conditional_fire_rate(delta)
	_weapon.step(delta)
	if _input.is_firing() and _can_fire_while_moving():
		# Cache Warmer rides the weapon's existing damage multiplier rather than adding a field
		# beside it: raised for the attempt and put back after, so a shot the cooldown refuses does
		# not spend the room's opening bonus.
		var restore := _weapon.damage_multiplier
		_weapon.damage_multiplier = restore * opening_shot_damage_scale()
		if _weapon.try_fire(global_position, _input.aim_direction):
			_room_opening_shot = false
		_weapon.damage_multiplier = restore

	if _input.has_interact_request():
		_input.consume_interact_request()
		use_nearest_interactable()

	_visuals.update_visuals(_input.aim_direction, should_flash(), delta)


## Pins the camera to exactly one room's view rectangle.
##
## `view` is viewport-sized, which is the trick: camera limits clamp the *view* inside the
## given region, so a region the same size as the viewport leaves the camera nowhere to move.
## The result is a fixed frame per room with no code following anything — and screen shake
## still works, because Camera2D.offset is applied after limits rather than being clamped by
## them.
##
## Pass `snap` on the first frame of a run so the camera starts framed instead of easing in
## from the origin; leave it false between rooms so the camera pans across the doorway.
func frame_room(view: Rect2i, snap: bool) -> void:
	_camera.limit_left = view.position.x
	_camera.limit_top = view.position.y
	_camera.limit_right = view.end.x
	_camera.limit_bottom = view.end.y
	if snap:
		_camera.reset_smoothing()


func get_camera() -> ShakeCamera:
	return _camera


## Read-only component access, used by the HUD and debug overlay. Gameplay systems
## should prefer signals over reaching in here.
func get_dash_controller() -> DashController:
	return _dash


func get_input_component() -> PlayerInput:
	return _input


func get_health_component() -> HealthComponent:
	return _health


## Blocking I/O. False only while that item is held and the robot is actually moving.
##
## Measured against real velocity rather than against input, so a robot shoved by knockback
## or still coasting to a halt is genuinely blocked — the item's promise is "you cannot
## shoot on the move", and reading the stick instead would let the player fire mid-slide by
## letting go a frame early.
##
## The threshold is not zero. Deceleration is 600 px/s² from a top speed of 160, so the tail
## end of every stop is several frames of drifting under a pixel per frame; requiring exact
## stillness would make the item read as "your weapon is broken" rather than as a rule.
func _can_fire_while_moving() -> bool:
	if not _items.requires_stillness_to_fire():
		return true
	return velocity.length() <= STILLNESS_SPEED


func get_weapon_controller() -> WeaponController:
	return _weapon


func get_item_inventory() -> ItemInventory:
	return _items


func is_dead() -> bool:
	return _is_dead


## Everything an item changes about the robot, recomputed from the whole inventory rather
## than adjusted by the new item alone. Recomputing is what makes the result independent
## of pickup order and leaves no path where an effect outlives the item that granted it.
##
## The one-shot parts of an item — the heal, the dash charge, the accent — are applied by
## the handler below, because they are events rather than state.
func _apply_item_stats() -> void:
	_weapon.modifiers = _items.build_modifier_stack()
	_weapon.fire_rate_multiplier = _items.get_fire_rate_multiplier()
	# The run's integrity penalty is subtracted last, after the base and the items, which is what
	# makes a spent death save something the player can rebuild out of rather than a permanent cap:
	# a +2 ceiling item found afterwards raises the maximum from one point to three. See
	# `RunManager.max_integrity_penalty`. `set_max_health` floors the result at one point.
	_health.set_max_health(
		config.max_integrity + _items.get_max_integrity_delta() - RunManager.max_integrity_penalty
	)
	_dash.set_bonus_charges(_items.get_dash_charges_delta())
	_dash.set_cooldown_scale(_items.get_dash_cooldown_multiplier())
	_sync_drones()


## Faraday Cage. Spends a charge to swallow a hit whole, and reports that it did — see
## `HealthComponent.damage_absorber`, which asks before anything is taken off.
##
## The blow is not reduced, it is refused: a shield that turned a three-point hit into a one-point
## hit would be a worse `max_integrity_delta`, and the reason to hold one is knowing the next hit
## costs nothing whatever it was.
func _absorb_with_shield(_info: DamageInfo) -> bool:
	if _shields_left <= 0:
		return false
	_shields_left -= 1
	EventBus.player_shield_absorbed.emit(global_position, _shields_left)
	return true


## A new room refills the shield, re-arms the opening shot, and buys the player a moment to look at
## what they have walked into. The first two are floor-local rhythms rather than run state, which is
## the whole difference between Faraday Cage and Failover.
##
## The grace window is granted rather than set, so it can only ever lengthen an immunity the player
## already had — walking through a door immediately after being hit must not cut the hit's own
## window short. See `PlayerConfig.room_entry_grace` for the length and the reason for it.
##
## Granted *quietly*, which is the other half of the same complaint: the flash means "you were hit",
## and a robot that flashes on every doorway is telling the player they took a shot they did not
## take. The mercy is meant to be invisible — a hit that never happens has nothing to report.
func _on_room_entered(_type: int, _room_id: int) -> void:
	_shields_left = _items.get_shield_charges_per_room()
	_room_opening_shot = true
	_health.grant_quiet_invulnerability(config.room_entry_grace)


## Mutex Lock and Adrenal Loop: fire rate that depends on what the robot is *doing* rather than on
## what it is carrying. Recomputed every frame from the inventory's base, so the moment a condition
## ends the bonus does too — and so neither item can leave a multiplier behind on a build that later
## drops out of the condition.
##
## Early-out first, because a build holding neither must not pay for two aggregate walks a frame.
func _step_conditional_fire_rate(delta: float) -> void:
	var still_bonus := _items.get_stillness_fire_rate_scale()
	var hurt_bonus := _items.get_low_integrity_fire_rate_scale()
	if is_equal_approx(still_bonus, 1.0) and is_equal_approx(hurt_bonus, 1.0):
		_still_seconds = 0.0
		return

	# The same threshold Blocking I/O reads. Two numbers for "is the robot standing still" is
	# two answers to one question, and the day they disagree an item fires while another refuses.
	if velocity.length() <= STILLNESS_SPEED:
		_still_seconds += delta
	else:
		_still_seconds = 0.0

	# The raw product, because the two conditional bonuses belong inside the curve rather than on
	# top of it: softening the held items and then multiplying by 1.5 would let a build stand still
	# to buy back exactly what the curve just took off it.
	var scale := _items.get_raw_fire_rate_multiplier()
	if still_bonus > 1.0 and _still_seconds >= _items.get_stillness_seconds():
		scale *= still_bonus
	if hurt_bonus > 1.0 and _health.current <= _items.get_low_integrity_points():
		scale *= hurt_bonus
	_weapon.fire_rate_multiplier = DiminishingReturns.soften(scale)


## What the next shot is multiplied by, which is Cache Warmer's bonus until the room's first shot
## has actually left the barrel and 1.0 forever after.
##
## A function rather than an expression inlined above, so the rule can be read — and checked —
## without driving a whole frame of input to observe it.
func opening_shot_damage_scale() -> float:
	return _items.get_first_shot_damage_scale() if _room_opening_shot else 1.0


## How many hits the shield can still take this room. For the HUD and for the suite.
func get_shield_charges() -> int:
	return _shields_left


## Rebuilds the drone escort to match the inventory, and re-hands every drone the things
## that make its shots the player's shots — the modifier stack, the shared shot counter,
## and the fire rate. Re-handed on every item change rather than only on creation, because
## picking up Cooling Fan after a drone must speed the drone up too.
func _sync_drones() -> void:
	var wanted := _items.get_drone_count()
	while _drones.size() > wanted:
		var retired: PlayerDrone = _drones.pop_back()
		retired.queue_free()
	while _drones.size() < wanted:
		var drone: PlayerDrone = DRONE_SCENE.instantiate()
		add_child(drone)
		_drones.append(drone)

	for index: int in _drones.size():
		_drones[index].set_orbit_phase(index, _drones.size())
		_drones[index].adopt(
			_weapon.modifiers, _weapon.shots, _weapon.fire_rate_multiplier, self
		)


func _on_item_added(item: ItemConfig) -> void:
	# Before the heal: Reinforced Chassis raises the ceiling and then repairs into it, so
	# the two points it grants are not clipped off by the old maximum.
	_apply_item_stats()

	if item.heal_on_pickup > 0.0:
		_health.heal(item.heal_on_pickup)
	# Dash charges are no longer applied here. They are an aggregate like every other one,
	# and `_apply_item_stats` above has already recomputed them from the whole inventory —
	# which is what lets an item take a charge away as well as grant one.
	if item.accent_color.a > 0.0:
		_visuals.set_accent(item.accent_color)

	EventBus.item_collected.emit(item)


## Puts the robot back the way a saved run left it: the build it had, and the integrity it had
## left. Called once, by `main.gd`, when a run is resumed from a checkpoint.
##
## Order is the whole of it. The items go in first so `_apply_item_stats` can recompute the
## ceiling from the whole inventory — and from the run's integrity penalty, which
## `RunManager.restore_run` has already put back — and only then is the saved integrity written
## into that ceiling. Restoring integrity first would clamp it to whatever the robot's unmodified
## pool happens to be, so a build carrying two Reinforced Chassis would come back on four points
## instead of eight.
##
## Nothing here emits a pickup. See `ItemInventory.restore`: a resumed run has already collected
## these items, and collecting them again would repair the robot and double every item in the
## run's statistics.
func restore_build(items: Array[ItemConfig], integrity: float) -> void:
	_items.restore(items)
	_apply_item_stats()

	# Last accent wins, exactly as it would have during play: `_on_item_added` sets it per pickup,
	# so the colour the robot ends up wearing is the last coloured item it took.
	for item: ItemConfig in items:
		if item.accent_color.a > 0.0:
			_visuals.set_accent(item.accent_color)

	_health.restore(integrity)


## Uses the closest thing in reach, if anything is in reach at all.
##
## The robot goes looking rather than being told, so a shop stand is a plain object in a
## group with an `interact` method and nothing has to register itself with the player. The
## press is consumed either way: a press aimed at nothing must not buy the next thing the
## player walks past.
func use_nearest_interactable() -> bool:
	var best: Node = null
	var best_distance := INTERACT_RANGE
	for node: Node in get_tree().get_nodes_in_group(ShopStand.GROUP):
		var target := node as Node2D
		if target == null or not target.has_method(&"interact"):
			continue
		var distance := target.global_position.distance_to(global_position)
		if distance <= best_distance:
			best_distance = distance
			best = target

	return best != null and best.call(&"interact", self)


## Whether the invulnerability the robot currently has is worth showing.
##
## Not every immune moment is. A flash is a warning with a deadline — *this is about to run out* —
## and it earns its place after a hit, when the player has to decide what to do with the window
## they were given. The window a doorway grants is not that: the player did nothing to earn it,
## there is nothing to spend it on, and it arrives on entering every room in the game. Twelve
## cycles a second for six tenths of a second, forty rooms a run, is a strobe attached to walking.
##
## So the window is kept and the flash is dropped, which is the split the two things actually want.
## `HealthComponent` owns that split, because it owns the timers: a doorway grant goes in quietly
## and everything else — a hit's own window, a dash — still speaks. Asking it here rather than
## keeping a second timer beside it means the flash is driven by the same object that decides
## whether a hit lands, rather than by a parallel expression that happened to agree.
##
## Public for the reason `opening_shot_damage_scale` is: the rule can then be read — and checked —
## without driving a frame of input and looking at a sprite to find out what it decided.
func should_flash() -> bool:
	return _health.is_visibly_invulnerable()


## Dash follows the held movement direction so it never fights the player's intent;
## with no movement held it follows the aim, letting a stationary player reposition
## deliberately (spec section 6.3 and 6.4).
func _resolve_dash_direction() -> Vector2:
	if not _input.move_vector.is_zero_approx():
		return _input.move_vector.normalized()
	return _input.aim_direction


func _on_dash_started(direction: Vector2) -> void:
	_visuals.play_dash_squash()
	EventBus.player_dash_started.emit(direction)


func _on_dash_ended() -> void:
	# Dash speed is far above move_speed; without this the robot coasts out of every
	# dash and control feels mushy on landing.
	velocity = velocity.limit_length(config.move_speed)
	EventBus.player_dash_ended.emit()


## The drones fire from the same signal that flashes the muzzle, which is what makes
## "fires when the player fires" exactly true. They deliberately do not announce their own
## shots on the EventBus: one trigger pull should be one firing sound, not three.
func _on_shot_fired(muzzle: Vector2, direction: Vector2) -> void:
	_visuals.play_muzzle_flash()
	for drone: PlayerDrone in _drones:
		drone.fire(direction)
	EventBus.shot_fired.emit(Teams.Id.PLAYER, muzzle, direction)


## Contact damage, Firewall Node beams, and the boss's charge all state a knockback and a
## direction, and until now the player threw all three away — this function only re-emitted the
## event. Being shoved is the clearest signal in the game that something touched you, and it was
## authored, tuned, and invisible.
##
## It could not have worked by simply adding to `velocity` either: `_physics_process` overwrites
## velocity outright every frame from either the dash or the motion controller, so an impulse
## stored there would be gone before it moved anything.
func _on_damaged(info: DamageInfo, remaining: float) -> void:
	if info.knockback > 0.0 and not info.direction.is_zero_approx():
		_knockback += info.direction.normalized() * info.knockback
	EventBus.player_damaged.emit(info, remaining)


## The same model the enemies use: a decaying shove moved as its own motion, so it is never
## fed back into the acceleration model. See Enemy._apply_knockback for why adding it to
## `velocity` is wrong rather than merely different.
func _apply_knockback(delta: float) -> void:
	if _knockback.is_zero_approx():
		return
	move_and_collide(_knockback * delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, config.knockback_decay * delta)


## Spends a failover charge to survive a blow that would have ended the run, and charges what
## surviving costs: maximum integrity collapses to a single point for the rest of the run.
##
## Consulted by the health component the instant a hit takes integrity to zero, before anything has
## been told the player died — see `HealthComponent.death_guard`. Changing nothing is how the guard
## declines, which is what every build without a failover item does.
##
## The order below *is* the mechanic:
##
## 1. **Charge the debt** against the ceiling as it stands right now, so a second save later costs
##    only what the player had rebuilt since the first.
## 2. **Recompute the stats**, which is what actually lowers the maximum. The penalty is subtracted
##    inside `_apply_item_stats`, which is the one place the ceiling is ever decided — writing it
##    onto the component here would be undone by the next item collected.
## 3. **Refill**, into a pool that is now one point deep. The robot survives at full integrity, and
##    full is one.
## 4. **Grant grace**, because the shot that nearly killed the player is rarely travelling alone.
##
## What this deliberately does not do is make the rest of the run safe. A one-point ceiling means
## every subsequent hit is lethal, repair cells and pickup heals top up a pool that is already full,
## and the only way back is the handful of items that raise maximum integrity. That is the trade the
## item is offered on.
func _survive_lethal_hit() -> void:
	if RunManager.death_saves_spent >= _items.get_death_save_charges():
		return

	var grace := _items.get_death_save_grace_seconds()
	RunManager.spend_death_save(_health.max_health, HealthComponent.MINIMUM_MAX_HEALTH)
	_apply_item_stats()
	_health.heal(_health.max_health)
	_health.grant_invulnerability(grace)
	EventBus.player_death_averted.emit(global_position)


func _on_died() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	# Or the wreck keeps sliding for a fifth of a second after it stops being a robot.
	_knockback = Vector2.ZERO
	_input.clear()
	_visuals.play_death()
	_camera.clear_shake()
	EventBus.player_died.emit()


## Registered with `HostileRegistry` so homing, blasts and chains can find this body without walking
## the whole enemy group to do it. The notification hook is what keeps the registry honest about
## sleep: a room deactivating its enemies delivers `PAUSED` to each of them.
func _notification(what: int) -> void:
	HostileRegistry.note(what, self)
