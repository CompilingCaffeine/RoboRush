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

## How much of the parent's lifetime a split child gets. Children are a bonus, not a
## second volley, and full-lifetime children would spend most of it wandering the room.
const SPLIT_LIFETIME_SCALE := 0.6

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
var _has_returned := false

## Bodies already damaged by this projectile, so a piercing shot cannot hit the same
## enemy repeatedly while overlapping it. Split children are seeded with whatever their
## parent just struck: a child spawned already overlapping that enemy would otherwise
## register an entry on its first frame and let Fork Bomb double-dip on a single target.
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
	excluded_bodies: Array[Node] = [],
) -> void:
	config = projectile_config
	team = owning_team
	shooter = owner_node
	_spawn_position = spawn_position
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	_hit_bodies = excluded_bodies.duplicate()


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

	_apply_homing(delta)

	var step := _direction * config.speed * delta
	var wall := _cast_to_wall(step)
	if wall.is_empty():
		global_position += step
	else:
		_handle_wall(wall)

	_update_trail()


## Steers toward the nearest hostile body, by at most `homing_strength` radians this
## frame. A turn *rate* rather than a snap is what makes Magnetic Guidance read as a
## curve the player can watch instead of a homing missile they cannot dodge — and it is
## also what keeps the item from trivialising aim, since a fast projectile can only bend
## so far before it leaves the room.
func _apply_homing(delta: float) -> void:
	if config.homing_strength <= 0.0:
		return

	var target := Targeting.nearest_hostile(
		self, global_position, config.homing_radius, team, _hit_bodies
	)
	if target == null:
		return

	var offset := target.global_position - global_position
	if offset.is_zero_approx():
		return

	var turn := clampf(
		_direction.angle_to(offset), -config.homing_strength * delta, config.homing_strength * delta
	)
	_direction = _direction.rotated(turn).normalized()
	rotation = _direction.angle()


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
##
## Explosions and chains fire on every impact, because both are "when this hits
## something" effects and a piercing shot legitimately hits several things. Splitting
## fires only when the projectile is actually consumed — spec section 12 describes the
## parent breaking apart, and a piercing splitter would otherwise shed a fresh pair at
## every enemy it passed through.
func _impact(body: Node, point: Vector2, normal: Vector2) -> void:
	EventBus.projectile_hit.emit(self, body, point, normal)

	# Whatever was struck directly, as a typed list the area effects can exclude. A shot
	# that hits an enemy must not also catch that same enemy in its own blast.
	var struck: Array[Node] = []
	if body != null:
		struck.append(body)

	if config.explosion_radius > 0.0:
		Explosion.detonate(
			self,
			point,
			config.explosion_radius,
			config.damage * config.explosion_damage_scale,
			team,
			get_shooter(),
			struck,
		)

	if body != null and config.chain_count > 0:
		ChainLightning.strike(
			self,
			point,
			config.chain_count,
			config.chain_radius,
			config.damage * config.chain_damage_scale,
			team,
			get_shooter(),
			struck,
		)

	if body != null and _pierce_left > 0:
		_pierce_left -= 1
		return

	# A wall impact fans its children back out along the surface normal; a body impact
	# fans them around the direction of travel, which is where the enemy's neighbours are.
	_spawn_splits(point, _direction if body != null else normal, struck)
	_despawn()


## Reverses once at the end of its life if Return Protocol is held, then expires normally
## the second time around.
##
## Handled by turning this projectile around rather than spawning a new one, so a
## returning shot keeps its remaining bounces and its identity — and so nothing has to
## decide who owns a projectile that outlived its own spawn.
func _expire() -> void:
	if config.return_enabled and not _has_returned:
		_has_returned = true
		_direction = -_direction
		rotation = _direction.angle()
		_lifetime_left = config.lifetime
		# The way back is a fresh pass: whatever it flew through on the way out is a
		# legitimate target again.
		_hit_bodies.clear()
		# Reported as a bounce because it is the same event to the player and to the
		# effects that draw it: the shot changed direction at a point.
		EventBus.projectile_bounced.emit(global_position, _direction)
		return

	EventBus.projectile_expired.emit(self)
	_despawn()


## Fans `split_count` weaker children out from the point of impact.
##
## Children are one generation only. A child that could split again would cascade without
## bound the moment Fork Bomb met a wall, and "the room fills with projectiles until the
## frame rate dies" is not a synergy.
func _spawn_splits(origin: Vector2, base_direction: Vector2, excluded: Array[Node]) -> void:
	if config.split_count <= 0 or base_direction.is_zero_approx():
		return

	var count := config.split_count
	var arc := deg_to_rad(config.split_spread_degrees)

	for index: int in count:
		var offset := 0.0
		if count > 1:
			offset = -arc * 0.5 + arc * (float(index) / float(count - 1))

		var child := config.spawn_copy()
		child.damage *= config.split_damage_scale
		child.split_count = 0
		child.pierce_count = 0
		child.return_enabled = false
		# Ricochet Driver plus Fork Bomb: children inherit whatever bounces the parent had
		# left, so "bounces once, then splits" carries on bouncing if it can.
		child.bounce_count = _bounce_left
		child.lifetime = config.lifetime * SPLIT_LIFETIME_SCALE

		# Deferred: splitting happens inside an Area2D callback, and registering a new
		# body's shape while the physics server is flushing queries is refused outright —
		# the same reason loot drops are deferred.
		ProjectileFactory.spawn_configured(
			self,
			child,
			base_direction.rotated(offset),
			origin,
			team,
			get_shooter(),
			excluded,
			true,
		)


func _despawn() -> void:
	set_physics_process(false)
	queue_free()


func _update_trail() -> void:
	if config.trail_length <= 0:
		return
	_trail.add_point(global_position)
	while _trail.get_point_count() > config.trail_length:
		_trail.remove_point(0)
