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


func _ready() -> void:
	assert(config != null, "Player.config is unset: assign a PlayerConfig resource.")
	collision_layer = Teams.body_layer(Teams.Id.PLAYER)
	collision_mask = Teams.LAYER_WORLD

	_input.setup(config)
	_motion.setup(config)
	_dash.setup(config)
	_weapon.setup(_weapon.config, Teams.Id.PLAYER)

	# Integrity comes from PlayerConfig rather than the component's own default, so
	# all player tuning stays in one resource.
	_health.configure(config.max_integrity, config.damage_invulnerability)

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
		velocity = _dash.direction * _dash.get_speed()
	else:
		velocity = _motion.step(velocity, _input.move_vector, delta)

	# move_and_slide with a circular shape slides along walls rather than sticking to
	# them, which covers spec section 6.6 (never trap the player in geometry).
	move_and_slide()

	_weapon.step(delta)
	if _input.is_firing():
		_weapon.try_fire(global_position, _input.aim_direction)

	_visuals.update_visuals(_input.aim_direction, _is_invulnerable(), delta)


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
	_health.set_max_health(config.max_integrity + _items.get_max_integrity_delta())


func _on_item_added(item: ItemConfig) -> void:
	# Before the heal: Reinforced Chassis raises the ceiling and then repairs into it, so
	# the two points it grants are not clipped off by the old maximum.
	_apply_item_stats()

	if item.heal_on_pickup > 0.0:
		_health.heal(item.heal_on_pickup)
	if item.dash_charges_delta > 0:
		_dash.add_charges(item.dash_charges_delta)
	if item.accent_color.a > 0.0:
		_visuals.set_accent(item.accent_color)

	EventBus.item_collected.emit(item)


## Either source of immunity flashes the robot, so the player never has to work out
## which kind of invulnerability they currently have.
func _is_invulnerable() -> bool:
	return _dash.is_invulnerable() or _health.is_invulnerable()


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


func _on_shot_fired(muzzle: Vector2, direction: Vector2) -> void:
	_visuals.play_muzzle_flash()
	EventBus.shot_fired.emit(Teams.Id.PLAYER, muzzle, direction)


func _on_damaged(info: DamageInfo, remaining: float) -> void:
	EventBus.player_damaged.emit(info, remaining)


func _on_died() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	_input.clear()
	_visuals.play_death()
	_camera.clear_shake()
	EventBus.player_died.emit()
