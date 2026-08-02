class_name Enemy
extends CharacterBody2D
## What every enemy has in common, so that each enemy script is only its one behaviour.
##
## This is the project's one actor base class, and it is deliberate. Spec section 15 asks
## for enemies that differ in exactly one thing — *how they create a movement problem* —
## and everything else about them is identical: the same collision layers, the same
## HealthComponent, the same knockback model, the same death announcement. Four copies of
## that lifecycle is four places for them to drift apart, and the drift would be invisible
## until one enemy quietly stopped emitting `enemy_killed` and rooms stopped clearing.
##
## Components are still where behaviour lives — `HealthComponent`, `WeaponController`, and
## `HurtFlash` are shared with the player and are not inherited from anything. What is
## inherited here is only the wiring between them, which is the part that has no business
## differing per enemy.
##
## A subclass implements `_act` and nothing else is required of it.

## Optional. Enemies that do not shoot simply omit the node.
const WEAPON_PATH := "%Weapon"

@export var config: EnemyConfig

@onready var _health: HealthComponent = %Health
@onready var _sprite: Sprite2D = %Sprite
@onready var _hurt_flash: HurtFlash = %HurtFlash
@onready var _weapon: WeaponController = get_node_or_null(WEAPON_PATH)

## The player, cached once found. Re-resolved if it is freed, so a restart does not leave
## every enemy chasing a corpse.
var _player: Node2D

## Decaying impulse from being shot, added on top of the enemy's own movement so
## knockback reads as a shove rather than teleportation.
var _knockback := Vector2.ZERO

var _is_dead := false

## Seconds until this enemy may deal contact damage again. Enemies that do not touch the
## player never use it.
var _contact_cooldown := 0.0


func _ready() -> void:
	assert(config != null, "%s.config is unset: assign an EnemyConfig resource." % name)
	collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	collision_mask = Teams.LAYER_WORLD

	_health.configure(config.max_health, 0.0)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

	if _weapon != null:
		_weapon.setup(config.weapon, Teams.Id.ENEMY)
		_weapon.shot_fired.connect(_on_shot_fired)

	_on_ready()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_player = find_player()
	if _weapon != null:
		_weapon.step(delta)

	var desired := _act(delta)
	var rate := config.acceleration if not desired.is_zero_approx() else config.deceleration
	velocity = velocity.move_toward(desired, rate * delta)

	move_and_slide()
	_apply_knockback(delta)

	_step_contact_damage(delta)


# --- Subclass hooks -----------------------------------------------------------


## Moves the body by the decaying shove from being shot, as a motion of its own rather than
## as an addition to `velocity`.
##
## It used to be `velocity += _knockback`, which looks equivalent and is not. `velocity`
## persists across frames, so a single impulse was re-added on every frame it took to decay:
## a 55 px/s rivet peaked at 90 px/s three frames later, *growing* before it fell away, and
## the enemy's own steering had to fight the leftovers. Keeping `velocity` purely the enemy's
## own steering means the acceleration model never sees the shove at all.
##
## `move_and_collide` rather than folding it into `move_and_slide`: an enemy shoved into a wall
## should stop against it, not slide along it as though it were walking.
func _apply_knockback(delta: float) -> void:
	if _knockback.is_zero_approx():
		return
	move_and_collide(_knockback * delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, config.deceleration * delta)


## Called at the end of _ready, once every shared component is wired.
func _on_ready() -> void:
	pass


## The velocity this enemy wants this frame. Returning zero means "stand still", which is
## a perfectly good movement problem — the Firewall Node's entire answer is zero.
func _act(_delta: float) -> Vector2:
	return Vector2.ZERO


# --- Shared services for subclasses -------------------------------------------


func get_health_component() -> HealthComponent:
	return _health


func get_weapon_controller() -> WeaponController:
	return _weapon


func is_dead() -> bool:
	return _is_dead


func find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D


## Refuses to act through walls. Without this an enemy plinks away at a player it cannot
## see, which reads as a bug rather than as difficulty.
func has_line_of_sight(target: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target, Teams.LAYER_WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## The room this enemy was spawned into, or null when it was placed directly in a test
## arena. Walked up the tree rather than injected, because an enemy is added to a room's
## container by the room and nothing hands it a reference on the way in.
func find_room() -> Room:
	var node := get_parent()
	while node != null:
		if node is Room:
			return node as Room
		node = node.get_parent()
	return null


## Tints the sprite toward a colour by `amount`, unless the hurt flash currently owns it.
## Every enemy telegraphs by brightening, and two systems writing `modulate` in the same
## frame is how a telegraph ends up invisible.
func tint_toward(color: Color, amount: float) -> void:
	if _hurt_flash.is_flashing():
		return
	_sprite.modulate = Color.WHITE.lerp(color, clampf(amount, 0.0, 1.0))


# --- Shared behaviour ---------------------------------------------------------


## Damage dealt by touching the player. Driven by `contact_damage` rather than by which
## enemy this is, so the Memory Leech needs no code here and a future charger needs none
## either.
##
## Resolved by distance rather than by an extra Area2D: both bodies are circles, the
## radii are known, and an enemy that already runs at the player every frame does not need
## the physics server's help to notice it has arrived.
func _step_contact_damage(delta: float) -> void:
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	if config.contact_damage <= 0.0 or _player == null or _contact_cooldown > 0.0:
		return

	var offset := _player.global_position - global_position
	if offset.length() > config.contact_radius:
		return

	var health := HealthComponent.find_on(_player)
	if health == null:
		return

	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	if health.apply_damage(
		DamageInfo.new(config.contact_damage, self, direction, config.contact_knockback)
	):
		_contact_cooldown = config.contact_interval


func _on_shot_fired(muzzle: Vector2, direction: Vector2) -> void:
	EventBus.shot_fired.emit(Teams.Id.ENEMY, muzzle, direction)


func _on_damaged(info: DamageInfo, remaining: float) -> void:
	_hurt_flash.flash()
	if not info.direction.is_zero_approx():
		var resistance := 1.0 - config.knockback_resistance
		_knockback += info.direction.normalized() * info.knockback * resistance
	EventBus.enemy_damaged.emit(self, info, remaining)


func _on_died() -> void:
	_is_dead = true
	# Position is emitted separately because this node is gone by the time anything
	# reacts to the signal.
	EventBus.enemy_killed.emit(self, global_position)
	queue_free()
