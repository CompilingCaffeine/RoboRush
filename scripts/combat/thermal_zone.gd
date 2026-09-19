class_name ThermalZone
extends Node2D

const PLAYER_RADIUS := Player.BODY_RADIUS

## Floor 3's signature hazard. Room zones heat while occupied, cool when vacated, and vent at full
## heat. Ignition makes the first occupied frame visible without changing when the zone vents.
##
## Room-owned zones follow room activation. Boss-driven zones use the floor session and resolve
## their announced vent even after their source has died. Both use the same visual language.

## Occupancy time before a room zone vents. Crossing stays affordable; holding position does not.
const SECONDS_TO_VENT := 1.5

## Time to cool fully after a room zone is vacated.
const COOL_SECONDS := 0.9

## Damage from one vent, matching a normal enemy hit.
const VENT_DAMAGE := 1.0

## A post-vent window that prevents repeated hits before the player can leave.
const VENT_COOLDOWN := 1.0

## Display-only heat floor while occupied; real heat still starts at zero.
const IGNITION_HEAT := 0.4

## Fade-out time for the display-only ignition floor.
const IGNITION_FADE := 0.25

## Teal-to-violet ramp, distinct from CompileLane's amber-to-red warning language.
const COOL_COLOR := Color(0.24, 0.62, 0.68)
const HOT_COLOR := Color(0.80, 0.24, 0.98)
const VENT_COLOR := Color(0.97, 0.90, 1.0)

## The zone remains visible at zero heat.
const COLD_ALPHA := 0.16
const HOT_ALPHA := 0.5

## Louvre bars distinguish this zone from a solid compile lane.
const LOUVRE_SPACING := 4.0
const LOUVRE_THICKNESS := 1.0

## Dim wash that keeps the zone's extent visible between bars.
const WASH_ALPHA_SCALE := 0.45

var _size := Vector2.ZERO

## Real heat, from zero to one.
var _heat := 0.0

var _vent_flash_left := 0.0
var _cooldown_left := 0.0

## Display-only occupancy feedback; damage uses `_heat`.
var _ignition := 0.0

## Positive only for a boss-driven zone from `spawn_vent`.
var _drive_seconds := 0.0

## A driven zone frees itself after its single vent.
var _spent := false

## Creates a room-owned zone. Parent before setting global position so its rect stays in world space.
static func spawn(parent: Node, rect: Rect2) -> ThermalZone:
	var zone := ThermalZone.new()
	zone._size = rect.size
	parent.add_child(zone)
	zone.global_position = rect.position
	return zone


## Creates a session-owned zone that heats on its own clock, vents once, and frees itself.
static func spawn_vent(spawner: Node, rect: Rect2, seconds: float) -> ThermalZone:
	if not spawner.is_inside_tree():
		return null
	var tree := spawner.get_tree()
	var container := tree.get_first_node_in_group(ProjectileFactory.CONTAINER_GROUP)
	if container == null:
		container = tree.current_scene

	var zone := ThermalZone.new()
	zone._size = rect.size
	zone._drive_seconds = maxf(seconds, 0.001)
	container.add_child(zone)
	# Parent before setting the world position.
	zone.global_position = rect.position
	return zone


## Actual heat, from zero to one.
func get_heat() -> float:
	return _heat



## Visual heat, with an ignition floor while the room zone is occupied.
func get_display_heat() -> float:
	return maxf(_heat, IGNITION_HEAT * _ignition)


## The zone's world-space bounds.
func get_rect() -> Rect2:
	return Rect2(global_position, _size)


## Whether this zone fills independently of player occupancy.
func is_driven() -> bool:
	return _drive_seconds > 0.0


func _physics_process(delta: float) -> void:
	_vent_flash_left = maxf(_vent_flash_left - delta, 0.0)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if is_driven():
		_step_driven(delta)
		return

	var previous := get_display_heat()
	if _is_being_loaded():
		# Set before the heat rather than after it, so the frame a zone starts taking load is
		# already the frame it looks like it. Waiting a step to light up would put the change one
		# frame behind the cause, which is the whole thing this is here to fix.
		_ignition = 1.0
		_heat = minf(_heat + delta / SECONDS_TO_VENT, 1.0)
		if _heat >= 1.0:
			_vent()
	else:
		_ignition = maxf(_ignition - delta / IGNITION_FADE, 0.0)
		_heat = maxf(_heat - delta / COOL_SECONDS, 0.0)

	# Redrawn only when the colour would actually differ, which for a room full of zones sitting
	# cold is the difference between a redraw per zone per frame and none at all. Measured on the
	# displayed heat rather than the real one: they part company at both ends of a load, and it is
	# the displayed one that decides whether the zone looks different.
	if not is_equal_approx(previous, get_display_heat()) or _vent_flash_left > 0.0:
		queue_redraw()


## Whether the zone is gaining heat: a player standing on it, and its vent cooldown spent.
##
## Two conditions, and the second is only the grace period after a vent — so in every state the
## player can actually be in, this is the question "is the robot on the grille". It asked two more
## things than that once, and the class doc records at length why it no longer does. Anything added
## back here is a condition the player has to infer from a colour, so the bar for adding one is
## that the floor is unreadable without it.
func _is_being_loaded() -> bool:
	if _cooldown_left > 0.0:
		return false
	var player := _find_player()
	return player != null and _contains(player.global_position)


## A driven zone's whole life: climb, vent once, and go. It never cools, because nothing the player
## does is what filled it — leaving stops it costing them, but it does not stop it filling.
##
## It never ignites either, and that is the one place the two kinds of zone are deliberately drawn
## differently. `IGNITION_HEAT` exists to answer "what did I just start", and a boss's vent is not
## something the player started: it is dropped on the floor cold and the ramp from cold *is* the
## warning. Flooring it would throw away the first four tenths of the only telegraph the player
## gets. `_ignition` is left at zero here, so `get_display_heat` returns the real heat.
##
## The heat is *not* clamped short of one and left there: it reaches full and vents on the same frame
## the colour finishes, so the ramp the player has been reading all floor means exactly what it meant
## in every room before this one.
func _step_driven(delta: float) -> void:
	if _spent:
		if _vent_flash_left <= 0.0:
			queue_free()
		return

	_heat = minf(_heat + delta / _drive_seconds, 1.0)
	queue_redraw()
	if _heat >= 1.0:
		_spent = true
		_vent()


func _vent() -> void:
	_heat = 0.0
	# Dropped rather than faded. A vented zone cannot heat again until its cooldown is up, and a
	# zone still glowing as though it were taking load would be saying the opposite of that to a
	# player deciding whether it is safe to stand there. The flash covers the frame it goes out on.
	_ignition = 0.0
	_vent_flash_left = 0.18
	_cooldown_left = VENT_COOLDOWN
	queue_redraw()

	# Announced whether or not it hit anybody, the same call `CompileLane` makes: presentation
	# should not have to ask what the outcome was to play the effect for the event.
	EventBus.thermal_zone_vented.emit(Rect2(global_position, _size))

	var player := _find_player()
	if player == null or not _contains(player.global_position):
		return
	var health := HealthComponent.find_on(player)
	if health == null:
		return
	var offset := player.global_position - (global_position + _size * 0.5)
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	health.apply_damage(DamageInfo.new(VENT_DAMAGE, self, direction))


## The player's body overlapping this zone, not their centre point. Same convention, and same
## reason, as the rect `CompileLane` grows before it checks.
func _contains(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, _size).grow(Player.BODY_RADIUS).has_point(to_local(point))


func _find_player() -> Player:
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Player


## A grille rather than a filled rectangle. See `LOUVRE_SPACING` for why the shape carries as much
## of the reading as the colour does.
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	if _vent_flash_left > 0.0:
		draw_rect(rect, Color(VENT_COLOR.r, VENT_COLOR.g, VENT_COLOR.b, 0.7))
		return

	# The displayed heat, not the real one: a zone under load reads as hot from the first frame even
	# though it has barely taken any. See `IGNITION_HEAT`.
	var shown := get_display_heat()
	var tint := COOL_COLOR.lerp(HOT_COLOR, shown)
	var alpha := lerpf(COLD_ALPHA, HOT_ALPHA, shown)
	draw_rect(rect, Color(tint.r, tint.g, tint.b, alpha * WASH_ALPHA_SCALE))

	# The bars, brightening with the heat. Started half a spacing in, so the pattern sits inside the
	# zone rather than flush against its top edge where it would read as a second border.
	var bar := Color(tint.r, tint.g, tint.b, minf(alpha + 0.32, 1.0))
	var y := LOUVRE_SPACING * 0.5
	while y + LOUVRE_THICKNESS <= _size.y:
		draw_rect(Rect2(Vector2(0.0, y), Vector2(_size.x, LOUVRE_THICKNESS)), bar)
		y += LOUVRE_SPACING

	# An edge, so the zone's boundary is exactly readable. A hazard whose extent is a soft gradient
	# is a hazard the player has to learn by being hurt by it.
	draw_rect(rect, Color(tint.r, tint.g, tint.b, minf(HOT_ALPHA + 0.2, 1.0)), false, 1.0)
