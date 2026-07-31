class_name TicketBot
extends CharacterBody2D
## Spec section 15: "Moves toward the player and fires slow single shots."
##
## Its purpose is basic pressure and teaching the player to read a telegraph, so its
## one behaviour is range-keeping. It closes to `preferred_range` and holds there,
## which is what stops a shooting enemy from simply walking into the player's face and
## turning a ranged threat into a melee one.
##
## Uses the same WeaponController and HealthComponent as the player. Nothing here
## knows how projectiles work.

@export var config: EnemyConfig

@onready var _health: HealthComponent = %Health
@onready var _weapon: WeaponController = %Weapon
@onready var _sprite: Sprite2D = %Sprite
@onready var _hurt_flash: HurtFlash = %HurtFlash

var _player: Node2D

## Decaying impulse from being shot, added on top of the enemy's own movement so
## knockback reads as a shove rather than teleportation.
var _knockback := Vector2.ZERO

var _telegraph_left := 0.0
var _is_dead := false


func _ready() -> void:
	assert(config != null, "TicketBot.config is unset: assign an EnemyConfig resource.")
	collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	collision_mask = Teams.LAYER_WORLD

	_health.configure(config.max_health, 0.0)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

	_weapon.setup(config.weapon, Teams.Id.ENEMY)
	_weapon.shot_fired.connect(_on_shot_fired)
	_telegraph_left = config.telegraph_seconds


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_player = _find_player()
	_weapon.step(delta)

	var desired := _desired_velocity()
	var rate := config.acceleration if not desired.is_zero_approx() else config.deceleration
	velocity = velocity.move_toward(desired, rate * delta)

	# Knockback is applied outside the acceleration model so it is not instantly
	# cancelled by the enemy's own steering.
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, config.deceleration * delta)

	move_and_slide()

	_update_attack(delta)
	_update_tint()


func get_health_component() -> HealthComponent:
	return _health


## Advance when too far, back off when too close, hold inside the tolerance band.
func _desired_velocity() -> Vector2:
	if _player == null:
		return Vector2.ZERO

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	if is_zero_approx(distance):
		return Vector2.ZERO

	var heading := to_player / distance
	if distance > config.preferred_range + config.range_tolerance:
		return heading * config.move_speed
	if distance < config.preferred_range - config.range_tolerance:
		return -heading * config.move_speed
	return Vector2.ZERO


## The telegraph only runs while the weapon is actually off cooldown, so the windup
## the player learns to read is always immediately followed by a shot.
func _update_attack(delta: float) -> void:
	if _player == null or not _has_line_of_sight(_player.global_position):
		_telegraph_left = config.telegraph_seconds
		return

	if not _weapon.can_fire():
		_telegraph_left = config.telegraph_seconds
		return

	_telegraph_left -= delta
	if _telegraph_left > 0.0:
		return

	var aim := (_player.global_position - global_position).normalized()
	_weapon.try_fire(global_position, aim)
	_telegraph_left = config.telegraph_seconds


## Refuses to shoot through walls. Without this the enemy plinks away at a player it
## cannot see, which reads as a bug rather than as difficulty.
func _has_line_of_sight(target: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target, Teams.LAYER_WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Brightens toward its screen colour as the shot charges. Skipped while the hurt
## flash owns the sprite, so the two never fight over modulate.
func _update_tint() -> void:
	if _hurt_flash.is_flashing():
		return
	var charge := 1.0 - clampf(_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0)
	_sprite.modulate = Color.WHITE.lerp(Color(1.8, 1.1, 1.1), charge * 0.8)


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(&"player") as Node2D


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
