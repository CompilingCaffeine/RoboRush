class_name Projectile
extends Area2D
## One projectile. Every behaviour it has comes from the ProjectileConfig it is
## handed at spawn — there is no weapon-specific or item-specific branch anywhere in
## this file, and there must never be one. That constraint is what makes spec section
## 13's synergies free: Ricochet Driver raises `bounce_count`, Fork Bomb raises
## `split_count`, and "bounces once then splits" already works.
##
## The flight behaviours from roadmap SYS-2 — orbiting, pausing to re-aim, ramping speed and
## damage, growing, auras, trail hazards, criticals, copies on a kill, a last shot on expiry — are
## the same kind of thing: fields on the config, each neutral at its default, read here and nowhere
## else. None of them knows which item asked for it or which of the others it is flying with.
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

## Pixels of travel over which `radius_over_distance` arrives: a little over half a room's width, so
## a growing shot is at its full size by the time it reaches the far side of a fight.
const GROWTH_DISTANCE := 240.0

## Seconds between an aura's hits. Quarter-second ticks read as a shot that hurts to be near rather
## than as a stream of separate hits, and keep the damage numbers legible.
const AURA_TICK_SECONDS := 0.25

## Damage tag an aura's hits carry, so a resistance can tell them from a direct hit.
const AURA_TAG := &"aura"

## How far a pause or an expiry looks for something to re-aim at. Further than any room is wide,
## because the room is the real bound: `_room_bounds` is passed with every search.
const RETARGET_RADIUS := 480.0

## Total arc the copies of a killing shot fan across. Narrow, because they are the same shot carrying
## on, not a burst.
const DUPLICATE_SPREAD_DEGREES := 16.0

var config: ProjectileConfig
var team := Teams.Id.PLAYER

## Who fired this, for damage attribution. May become invalid mid-flight: an enemy can
## die while its shot is still travelling, and a slow projectile easily outlives its
## owner. Always read it through get_shooter().
var shooter: Node

var _direction := Vector2.RIGHT
var _spawn_position := Vector2.ZERO

## The room this shot was fired in, as a global rect, or an empty rect for a shot fired outside
## every room — a test arena, or something standing in the corridor between two rooms.
##
## A shot belongs to the room it was fired in and dies at its edge. Doors already said this for a
## room being fought in — they sit on the world layer while locked, so a sealed room cannot be
## shot out of — but a *cleared* room has its doors open, and through that opening the player
## could stand outside a room they had never entered and kill its enemies one by one while nothing
## in it was awake to shoot back. Shots crossing the other way were worse still: a rivet fired at
## a doorway would find a wall two rooms over and come back out of a room the player was not in.
##
## Fixed here rather than by closing the doorway, because the doorway is not the only way out and
## a room is not the only thing on the other side of it. What is wrong is the shot outliving the
## room it was fired in, and that is a fact about the shot.
var _room_bounds := Rect2()

var _lifetime_left := 0.0
var _pierce_left := 0
var _bounce_left := 0
var _has_returned := false

## Seconds spent in flight — not circling, not paused. What the over-life ramps read.
var _age := 0.0

## Pixels flown, for `radius_over_distance`.
var _travelled := 0.0

## The collision radius now, which `radius_over_distance` grows from `config.radius`.
var _radius := 0.0

## Radians of orbit still owed, and where on the circle the shot is.
var _orbit_left := 0.0
var _orbit_angle := 0.0

## Whether the one pause is still to come, and how much of it is left once it has begun.
var _pause_pending := false
var _pause_left := 0.0

## Whether the shot has struck a body, which is what decides whether its expiry is a miss.
var _has_hit := false

## Seconds to the next aura tick and the next hazard patch.
var _aura_left := 0.0
var _hazard_left := 0.0

## Set the moment the projectile is used up. `queue_free` does not take effect until the
## end of the frame, so a spent projectile keeps receiving `body_entered` for every other
## body it is already overlapping — two enemies standing on each other took a rivet each
## from one shot, and with items on, a full set of splits, chains, and explosions each.
var _is_spent := false

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
	_radius = config.radius
	_orbit_left = maxf(config.orbit_turns, 0.0) * TAU
	_orbit_angle = _direction.angle()
	_pause_pending = config.pause_and_retarget_seconds > 0.0
	_hazard_left = config.trail_hazard_interval

	# Asked for here rather than passed in, so every way a projectile comes into the world gets it
	# for nothing: a weapon's shot, a split child fanning off an impact, a boss's ring. All any of
	# them has to be right about is where the shot starts, which they already are.
	var room := Room.containing(self, _spawn_position)
	if room != null:
		_room_bounds = Rect2(room.get_outer_rect())

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


## Three states, one at a time: circling the shooter, stopped to re-aim, or in flight. Only flight
## ages the shot and spends its lifetime — the other two are a wind-up and a held breath, and
## neither should cost the shot its range.
func _physics_process(delta: float) -> void:
	if _orbit_left > 0.0:
		_step_orbit(delta)
	elif _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_retarget()
	else:
		_lifetime_left -= delta
		if _lifetime_left <= 0.0:
			_expire()
			return
		_age += delta
		if _pause_pending and _age >= config.pause_after_seconds:
			_pause_pending = false
			_pause_left = config.pause_and_retarget_seconds
		else:
			_fly(delta)

	if _is_spent:
		return

	if _has_left_its_room():
		# Not `_expire`: that offers Return Protocol another lap, and a shot that has left the room
		# is not a shot the player is owed anything more from. The boundary is the end of it.
		EventBus.projectile_expired.emit(self)
		_despawn()
		return

	_step_aura(delta)
	_step_trail_hazard(delta)
	_update_trail()


## One frame of ordinary flight: steer, move, and meet whatever wall is in the way.
func _fly(delta: float) -> void:
	_apply_homing(delta)

	var step := _direction * _current_speed() * delta
	# A shot that has slowed to a halt goes nowhere, so there is no wall for it to meet. Casting
	# anyway would cost a ray every frame it waits, and a homing mine turning to face a wall beside
	# it would meet one it never moved into.
	if step.is_zero_approx():
		return

	var wall := _cast_to_wall(step)
	if wall.is_empty():
		global_position += step
		_grow(step.length())
	else:
		_handle_wall(wall)


## Circles the shooter, at the shot's own speed along the circle, until the turns are spent. A
## shooter that has gone — a dead enemy, a freed drone — releases it at once, the way it was facing.
##
## Walls are not met while circling. The robot is inside the room, the circle is a couple of tiles
## across, and a shot that bounced or died against the wall the player was standing beside would
## make the item worse the closer the fight got.
func _step_orbit(delta: float) -> void:
	var centre := get_shooter() as Node2D
	if centre == null or not centre.is_inside_tree():
		_release_orbit()
		return

	var circle := maxf(config.orbit_radius, 1.0)
	var turn := minf(_current_speed() / circle * delta, _orbit_left)
	_orbit_left -= turn
	_orbit_angle += turn
	var outward := Vector2.from_angle(_orbit_angle)
	global_position = centre.global_position + outward * circle
	rotation = _orbit_angle + PI * 0.5
	if _orbit_left <= 0.0:
		_release_orbit()


## Sends the shot straight out from the centre of its circle. After whole turns that is the line it
## was aimed down.
func _release_orbit() -> void:
	_orbit_left = 0.0
	_direction = Vector2.from_angle(_orbit_angle)
	rotation = _direction.angle()


## Turns the shot toward the nearest enemy in its room, or leaves it as it was if there is none.
func _retarget() -> void:
	var target := Targeting.nearest_hostile(
		self, global_position, RETARGET_RADIUS, team, _hit_bodies, _room_bounds
	)
	if target == null:
		return
	var offset := target.global_position - global_position
	if offset.is_zero_approx():
		return
	_direction = offset.normalized()
	rotation = _direction.angle()


func _current_speed() -> float:
	return config.speed * _over_life(config.speed_over_life)


## The shot's damage now: its own, along its over-life ramp. What a hit, a blast and a chain are all
## worked out from, so an accelerating shot's explosion hits as hard as the shot does.
func _current_damage() -> float:
	return config.damage * _over_life(config.damage_over_life)


## Where along the line from 1.0 to `end` the shot is, by the time it has spent in flight.
func _over_life(end: float) -> float:
	if is_equal_approx(end, 1.0):
		return 1.0
	var span := config.over_life_seconds if config.over_life_seconds > 0.0 else config.lifetime
	return lerpf(1.0, end, clampf(_age / maxf(span, 0.001), 0.0, 1.0))


## Grows the shot by the distance it just flew, up to `radius_over_distance` times its own radius.
## The collision circle, the sprite and the trail grow together, so what the player sees is what
## hits.
func _grow(distance: float) -> void:
	if is_equal_approx(config.radius_over_distance, 1.0):
		return
	_travelled += distance
	var growth := lerpf(
		1.0, config.radius_over_distance, clampf(_travelled / GROWTH_DISTANCE, 0.0, 1.0)
	)
	_radius = maxf(config.radius * growth, 0.1)
	(_shape.shape as CircleShape2D).radius = _radius
	_sprite.scale = Vector2.ONE * growth
	_trail.width = maxf(_radius, 1.0)


## Hurts every enemy near the shot, every `AURA_TICK_SECONDS`, including the first frame it flies.
func _step_aura(delta: float) -> void:
	if config.aura_damage_scale <= 0.0 or config.aura_radius <= 0.0:
		return
	_aura_left -= delta
	if _aura_left > 0.0:
		return
	_aura_left += AURA_TICK_SECONDS

	var amount := _current_damage() * config.aura_damage_scale
	for body: Node2D in Targeting.hostiles_near(
		self, global_position, config.aura_radius, team, [], _room_bounds
	):
		var health := HealthComponent.find_on(body)
		if health == null:
			continue
		var away := body.global_position - global_position
		health.apply_damage(DamageInfo.new(
			amount,
			get_shooter(),
			away.normalized() if not away.is_zero_approx() else _direction,
			0.0,
			false,
			[AURA_TAG] as Array[StringName],
		))


## Leaves a hazard patch behind the shot every `trail_hazard_interval`, starting one interval out of
## the muzzle rather than on it.
func _step_trail_hazard(delta: float) -> void:
	if config.trail_hazard_interval <= 0.0 or config.trail_hazard_effect.is_empty():
		return
	_hazard_left -= delta
	if _hazard_left > 0.0:
		return
	_hazard_left += config.trail_hazard_interval
	HazardPatch.drop(
		self,
		global_position,
		config.trail_hazard_radius,
		config.trail_hazard_seconds,
		config.trail_hazard_effect,
		team,
		_room_bounds,
	)


## Steers toward the nearest hostile body, by at most `homing_strength` radians this
## frame. A turn *rate* rather than a snap is what makes Magnetic Guidance read as a
## curve the player can watch instead of a homing missile they cannot dodge — and it is
## also what keeps the item from trivialising aim, since a fast projectile can only bend
## so far before it leaves the room.
func _apply_homing(delta: float) -> void:
	if config.homing_strength <= 0.0:
		return

	# Bounded by the room for the same reason the shot itself is: an enemy through a doorway is
	# not a target this shot can ever reach, and a magnetic rivet bending toward one would spend
	# its flight curving into the wall between them.
	var target := Targeting.nearest_hostile(
		self, global_position, config.homing_radius, team, _hit_bodies, _room_bounds
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


## Whether the shot has crossed out of the room it was fired in. Always false for a shot with no
## room to be fired in, which is every shot in a test arena. Asked only of a shot still in flight:
## a wall handled a moment ago may already have spent it, and a spent projectile that announced
## its own expiry a second time would be counted twice by anything listening.
##
## The whole footprint, walls included, rather than the interior: a shot that has bounced off the
## inside face of a wall is momentarily a hair inside that wall, and a room a shot could be killed
## by touching would make Ricochet Driver a liability at exactly the moment it fired.
func _has_left_its_room() -> bool:
	return _room_bounds.has_area() and not _room_bounds.has_point(global_position)


## Casts one radius further than the step so impacts land on the wall's face rather
## than a body-length inside it.
func _cast_to_wall(step: Vector2) -> Dictionary:
	var target := global_position + step + _direction * _radius
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
		global_position = point + normal * (_radius + BOUNCE_CLEARANCE)
		_direction = _direction.bounce(normal)
		rotation = _direction.angle()
		# A rebounding shot may legitimately re-hit something it already passed
		# through, so clear the exclusion list.
		_hit_bodies.clear()
		EventBus.projectile_bounced.emit(point, normal)
		return

	# Bounces are spent, so this wall is where the shot has definitively missed — which is the
	# moment Return Protocol exists for. Checked after the bounce branch so Ricochet Driver plus
	# Return Protocol reads as "bounce off the first wall, come back off the second" rather than
	# the two items fighting over the same collision.
	if config.return_enabled and not _has_returned and not normal.is_zero_approx():
		global_position = point + normal * (_radius + BOUNCE_CLEARANCE)
		_reverse()
		return

	global_position = point
	_impact(null, point, normal if not normal.is_zero_approx() else -_direction)


func _on_body_entered(body: Node2D) -> void:
	if _is_spent or body in _hit_bodies:
		return
	_hit_bodies.append(body)
	_has_hit = true

	var health := HealthComponent.find_on(body)
	if health != null:
		var was_alive := health.is_alive()
		health.apply_damage(_hit_on(body))
		_execute_if_broken(health)
		if was_alive and not health.is_alive():
			_continue_as_copies()

	_apply_status_effects(body)
	_impact(body, global_position, -_direction)


## The damage a direct hit on `body` deals: the shot's own now, raised against a target already
## carrying a status, and then perhaps critical. The status is read before this shot applies its own
## — see `_apply_status_effects`, which runs after — so a shot never pays itself the bonus.
func _hit_on(body: Node) -> DamageInfo:
	var amount := _current_damage()
	if config.bonus_vs_status > 0.0:
		var status := StatusEffectController.find_on(body)
		if status != null and status.has_any_effect():
			amount *= 1.0 + config.bonus_vs_status
	# Rolled only when there is a chance to roll, so a shot that cannot crit never draws a number.
	var critical := config.crit_chance > 0.0 and randf() < config.crit_chance
	if critical:
		amount *= config.crit_scale
	return DamageInfo.new(amount, get_shooter(), _direction, config.knockback, critical)


## Duplicate on kill. The copies are this shot carrying on from the kill: what it had left of its
## lifetime, its pierces and bounces, and whether it still owes a return or a pause. They never
## duplicate again, and they begin already past everything this shot has struck.
func _continue_as_copies() -> void:
	var count := mini(config.split_on_kill_count, CombatCaps.active().max_children_per_impact)
	if count <= 0:
		return

	var arc := deg_to_rad(DUPLICATE_SPREAD_DEGREES)
	for index: int in count:
		var offset := 0.0
		if count > 1:
			offset = -arc * 0.5 + arc * (float(index) / float(count - 1))

		var copy := config.spawn_copy()
		copy.split_on_kill_count = 0
		copy.orbit_turns = 0.0
		copy.lifetime = maxf(_lifetime_left, 0.05)
		copy.pierce_count = _pierce_left
		copy.bounce_count = _bounce_left
		copy.return_enabled = config.return_enabled and not _has_returned
		if not _pause_pending:
			copy.pause_and_retarget_seconds = 0.0

		# Deferred, like splits: this runs inside a physics callback.
		ProjectileFactory.spawn_configured(
			self,
			copy,
			_direction.rotated(offset),
			global_position,
			team,
			get_shooter(),
			_hit_bodies,
			true,
		)


## Finishes a target the hit left under this shot's execute threshold.
##
## A second `apply_damage` rather than a `kill()` on the component, so the death travels the ordinary
## path: the same `damaged` and `died` signals fire, the run's statistics count the damage, the kill
## is attributed to whoever fired, and anything hanging off an enemy's death — Volatile Kernel, the
## room's clear check — sees exactly what it sees for any other kill. A private killing path would be
## a second way to die for every one of those to get wrong.
##
## Ratio rather than remaining points, because the threshold has to mean the same thing on floor one
## and on a floor where every enemy carries four times the integrity it was tuned with.
func _execute_if_broken(health: HealthComponent) -> void:
	if config.execute_threshold <= 0.0 or not health.is_alive():
		return
	if health.get_ratio() > config.execute_threshold:
		return
	health.apply_damage(
		DamageInfo.new(health.current, get_shooter(), _direction, 0.0)
	)


## Applies whatever statuses this shot is carrying to the body it hit.
##
## Separate from the damage above and not gated on it: a status is a consequence of being
## hit, not of losing integrity, so a shot that lands on something already at zero still
## chills it. Bodies with no controller — walls, and any enemy scene not given one — simply
## have nothing to apply to, which is how they opt out without a check here naming them.
func _apply_status_effects(body: Node) -> void:
	if config.status_effects.is_empty():
		return
	var status := StatusEffectController.find_on(body)
	if status == null:
		return
	for id: StringName in config.status_effects:
		status.apply(id)


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

	# Everything below that reaches past the point of impact is handed the shot's room, so a blast
	# or a chain set off against the wall beside a doorway stops where the shot itself would have.

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
			_current_damage() * config.explosion_damage_scale,
			team,
			get_shooter(),
			struck,
			_room_bounds,
		)

	if body != null and config.chain_count > 0:
		ChainLightning.strike(
			self,
			point,
			config.chain_count,
			config.chain_radius,
			_current_damage() * config.chain_damage_scale,
			team,
			get_shooter(),
			struck,
			_room_bounds,
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
		_reverse()
		return

	EventBus.projectile_expired.emit(self)
	if config.expire_retarget_shot and not _has_hit:
		_fire_at_nearest()
	_despawn()


## A missed shot's last word: this shot again, fresh, straight at the nearest enemy in its room. It
## does not do this a second time, and it does not circle — it is fired from where the miss ended,
## not from the robot.
##
## Not deferred: an expiry happens in `_physics_process`, where a weapon's own shots are added too,
## rather than inside a physics callback.
func _fire_at_nearest() -> void:
	var target := Targeting.nearest_hostile(
		self, global_position, RETARGET_RADIUS, team, [], _room_bounds
	)
	if target == null:
		return
	var offset := target.global_position - global_position
	if offset.is_zero_approx():
		return

	var shot := config.spawn_copy()
	shot.expire_retarget_shot = false
	shot.orbit_turns = 0.0
	ProjectileFactory.spawn_configured(
		self, shot, offset.normalized(), global_position, team, get_shooter()
	)


## Turns the projectile around. Reached either because it flew its `return_after_distance` or
## because its lifetime ran out with a return still owed.
func _reverse() -> void:
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


## Fans `split_count` weaker children out from the point of impact.
##
## Children split again only while `split_depth` has generations left, and never past
## `CombatCaps.max_split_depth`: one generation is the default and what every shipped item gives.
## A child that could always split again would cascade without bound the moment Fork Bomb met a
## wall, and "the room fills with projectiles until the frame rate dies" is not a synergy. Each
## generation is weaker and shorter-lived than the last, which is what makes a deeper split read as
## a burst rather than a second volley.
func _spawn_splits(origin: Vector2, base_direction: Vector2, excluded: Array[Node]) -> void:
	if config.split_count <= 0 or base_direction.is_zero_approx():
		return

	var caps := CombatCaps.active()
	var count := mini(config.split_count, caps.max_children_per_impact)
	var depth := mini(config.split_depth, caps.max_split_depth)
	if depth <= 0:
		return
	var arc := deg_to_rad(config.split_spread_degrees)

	for index: int in count:
		var offset := 0.0
		if count > 1:
			offset = -arc * 0.5 + arc * (float(index) / float(count - 1))

		var child := config.spawn_copy()
		child.damage *= config.split_damage_scale
		child.split_depth = depth - 1
		if child.split_depth <= 0:
			child.split_count = 0
		child.pierce_count = 0
		child.return_enabled = false
		# A child is born at the point of impact, a room away from the robot; circling back to it
		# would be a teleport.
		child.orbit_turns = 0.0
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


## Removes the projectile without anything it would normally do on the way out: no split, no
## return, no expiry. `ProjectileFactory` calls it when the live-shot cap needs the room — see
## `CombatCaps.max_player_projectiles`. Safe on a projectile that has not reached the tree yet.
func retire() -> void:
	_despawn()


## Whether the projectile has been used up and is only waiting for the end of the frame to go.
func is_spent() -> bool:
	return _is_spent


## Marks the projectile spent before freeing it. The flag, not `queue_free`, is what stops
## a second hit: the free does not happen until the end of the frame, and every remaining
## overlap is reported before then.
func _despawn() -> void:
	if _is_spent:
		return
	_is_spent = true
	set_physics_process(false)
	queue_free()


func _update_trail() -> void:
	if config.trail_length <= 0:
		return
	_trail.add_point(global_position)
	while _trail.get_point_count() > config.trail_length:
		_trail.remove_point(0)
