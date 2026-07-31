class_name Projectile
extends Area2D
## One projectile. Every behaviour it has comes from the ProjectileConfig it is
## handed at spawn — there is no weapon-specific or item-specific branch anywhere in
## this file, and there must never be one. That constraint is what makes spec section
## 13's synergies free: Ricochet Driver raises `bounce_count`, Fork Bomb raises
## `split_count`, and "bounces once then splits" already works.
##
## Movement is stepped manually instead of using a physics body, for one concrete
## reason: wall handling needs a surface *normal*, which a ray query provides and
## which Area2D's body_entered cannot. Bounce and correctly-oriented impact sparks
## both depend on it.
##
## Targets and walls are detected by two different mechanisms on purpose. The Area2D
## mask contains only the opposing team's bodies, so a hit is always a valid target
## and friendly fire is impossible without a runtime check. Walls come from the ray.

## Extra clearance when repositioning after a bounce, so the projectile does not
## re-detect the surface it just left.
const BOUNCE_CLEARANCE := 0.5

var config: ProjectileConfig
var team := Teams.Id.PLAYER

## Who fired this, for damage attribution. May become invalid mid-flight: an enemy can
## die while its shot is still travelling, and a slow projectile easily outlives its
## owner. Always read it through get_shooter().
var shooter: Node

var _direction := Vector2.RIGHT
var _spawn_position := Vector2.ZERO
var _lifetime_left := 0.0
var _pierce_left := 0
var _bounce_left := 0

## Bodies already damaged by this projectile, so a piercing shot cannot hit the same
## enemy repeatedly while overlapping it.
var _hit_bodies: Array[Node] = []

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape
@onready var _trail: Line2D = $Trail


## Must be called before the projectile enters the tree.
func configure(
	projectile_config: ProjectileConfig,
	owning_team: Teams.Id,
	owner_node: Node,
	spawn_position: Vector2,
	direction: Vector2,
) -> void:
	config = projectile_config
	team = owning_team
	shooter = owner_node
	_spawn_position = spawn_position
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT


func _ready() -> void:
	global_position = _spawn_position
	rotation = _direction.angle()

	collision_layer = Teams.projectile_layer(team)
	collision_mask = Teams.opposing_body_layer(team)

	_lifetime_left = config.lifetime
	_pierce_left = config.pierce_count
	_bounce_left = config.bounce_count

	_sprite.texture = config.texture

	var circle := CircleShape2D.new()
	circle.radius = config.radius
	_shape.shape = circle

	# top_level keeps the trail in world space; otherwise it would rotate and
	# translate with the projectile and draw as a stationary stub.
	_trail.top_level = true
	_trail.global_position = Vector2.ZERO
	_trail.rotation = 0.0
	_trail.default_color = config.trail_color
	_trail.width = maxf(config.radius, 1.0)
	_trail.visible = config.trail_length > 0

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		_expire()
		return

	var step := _direction * config.speed * delta
	var wall := _cast_to_wall(step)
	if wall.is_empty():
		global_position += step
	else:
		_handle_wall(wall)

	_update_trail()


## Casts one radius further than the step so impacts land on the wall's face rather
## than a body-length inside it.
func _cast_to_wall(step: Vector2) -> Dictionary:
	var target := global_position + step + _direction * config.radius
	var query := PhysicsRayQueryParameters2D.create(global_position, target, Teams.LAYER_WORLD)
	# Catches the case where a shooter pressed against a wall spawns the muzzle
	# inside geometry: the projectile dies there instead of appearing behind it.
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query)


func _handle_wall(hit: Dictionary) -> void:
	var point: Vector2 = hit["position"]
	var normal: Vector2 = hit["normal"]

	# A zero normal means the ray began inside the wall, where reflecting is
	# meaningless. Expire instead of bouncing to a garbage direction.
	if _bounce_left > 0 and not normal.is_zero_approx():
		_bounce_left -= 1
		global_position = point + normal * (config.radius + BOUNCE_CLEARANCE)
		_direction = _direction.bounce(normal)
		rotation = _direction.angle()
		# A rebounding shot may legitimately re-hit something it already passed
		# through, so clear the exclusion list.
		_hit_bodies.clear()
		EventBus.projectile_bounced.emit(point, normal)
		return

	global_position = point
	_impact(null, point, normal if not normal.is_zero_approx() else -_direction)


func _on_body_entered(body: Node2D) -> void:
	if body in _hit_bodies:
		return
	_hit_bodies.append(body)

	var health := HealthComponent.find_on(body)
	if health != null:
		health.apply_damage(
			DamageInfo.new(config.damage, get_shooter(), _direction, config.knockback)
		)

	_impact(body, global_position, -_direction)


## The shooter, or null if it has been freed since firing. Passing a freed Object into
## DamageInfo raises a type error and the hit silently deals no damage, so every read
## goes through here.
func get_shooter() -> Node:
	return shooter if is_instance_valid(shooter) else null


## `body` is null for wall impacts. Pierce only applies to bodies: a projectile that
## pierces enemies still stops at level geometry.
func _impact(body: Node, point: Vector2, normal: Vector2) -> void:
	EventBus.projectile_hit.emit(self, body, point, normal)
	if body != null and _pierce_left > 0:
		_pierce_left -= 1
		return
	_despawn()


func _expire() -> void:
	EventBus.projectile_expired.emit(self)
	_despawn()


func _despawn() -> void:
	set_physics_process(false)
	queue_free()


func _update_trail() -> void:
	if config.trail_length <= 0:
		return
	_trail.add_point(global_position)
	while _trail.get_point_count() > config.trail_length:
		_trail.remove_point(0)
