class_name ThermalZone
extends Node2D
## Floor 3's signature mechanic: a patch of floor that heats up under sustained load and vents.
##
## The Data Center's throughput zones are the floor's one new idea, and the idea is **stop
## camping**. A zone gains heat while the player stands inside it firing, loses heat the moment
## they move or stop, and when it fills it vents — a flash and one point of integrity to whoever
## is still standing there. Nothing about it is random and nothing about it is hidden: the zone is
## drawn on the floor, its heat is its colour, and the vent is telegraphed by the colour having
## been climbing for two and a half seconds.
##
## **Why load and not time.** The obvious version of this mechanic charges a zone for being stood
## in, or for shots fired in it. Both are worse, and for the same reason: they tax the build. Heat
## per shot makes a fast weapon heat a zone faster, so `fire_rate_scale` items — Cooling Fan,
## Unsafe Overclock — quietly become liabilities on this floor, and an item that is a liability on
## one floor of six is an item nobody picks. Charging for occupancy alone punishes a player for
## being in the room. Charging *stationary firing* taxes a habit instead, and habits are what a
## floor is allowed to teach: keep moving and this floor costs you nothing at all, at any fire
## rate.
##
## The one real tension is deliberate and worth naming: an item with `fire_requires_stillness` is
## genuinely harder to use here, because the thing it asks for is the thing this floor charges for.
## That is a trade-off a player accepts when they take it, which is what a trade-off is supposed
## to be — unlike a fire-rate tax, which they would be paying without having chosen anything.
##
## Built from `RoomTemplate.thermal_zones` rather than from the floor number, so a Data Center
## template carries its own zones and a Help Desk template has none, without a single
## `if floor_number == 3` anywhere. That is the rule Floor 4 is meant to prove; it costs nothing
## to have followed it from the first floor that needed it.
##
## Follows `CompileLane`'s conventions throughout — physics-timed because it decides real damage,
## the player found directly rather than through `Targeting`, the player's radius grown onto the
## rect so a body and not a centre point decides who is inside. What it does *not* share is
## lifetime: a lane is spawned into the session and outlives the enemy that painted it, while a
## zone is part of a room's furniture and is built with it.

## Seconds of stationary firing inside a zone before it vents.
##
## Long enough that the colour climbing through amber is a warning a player can act on, short
## enough that standing still is never the right answer. Two and a half seconds is about four
## shots of the starting weapon: the first is free, the last is a choice.
const SECONDS_TO_VENT := 2.5

## Seconds from full heat back to cold, once the zone is no longer being loaded. Faster than it
## heats, so leaving a zone is always a complete answer rather than a partial one — a player who
## has been driven off a hot zone can come back to it.
const COOL_SECONDS := 1.5

## What a vent costs. One point, matching an ordinary enemy hit against the player's six: the floor
## teaches by being expensive to ignore, not by being lethal on first contact.
const VENT_DAMAGE := 1.0

## Seconds after a vent during which the zone cannot heat again. The window in which leaving is
## guaranteed to work — without it, a player standing in a zone at full heat would be hit
## repeatedly before they could cross its edge.
const VENT_COOLDOWN := 1.0

## How long after a shot the player still counts as firing. Covers the gap between shots so a slow
## weapon does not make heat stutter, and is short enough that stopping is felt immediately.
const FIRING_MEMORY := 0.35

## The player's collision radius, from player.tscn. Duplicated for the reason `CompileLane` and
## `FirewallNode` both duplicate it: the zone must be able to ask who is inside it without
## depending on how the player scene is assembled.
const PLAYER_RADIUS := 5.0

## Cold, loaded, and venting. The zone is drawn as a lerp between the first two by heat, so the
## player reads a number they are never shown.
const COOL_COLOR := Color(0.24, 0.62, 0.68)
const HOT_COLOR := Color(0.95, 0.36, 0.30)
const VENT_COLOR := Color(1.0, 0.93, 0.82)

## Alpha at zero heat and at full heat. The zone is always visible — a hazard that appears only
## once it is dangerous is a trap, and this floor is not built out of traps.
const COLD_ALPHA := 0.16
const HOT_ALPHA := 0.5

var _size := Vector2.ZERO

## Zero to one. The whole mechanic is this number and what is allowed to change it.
var _heat := 0.0

var _vent_flash_left := 0.0
var _cooldown_left := 0.0

## Seconds since the player last fired, counted from `EventBus.shot_fired` rather than read off the
## weapon. The zone has no business knowing what a weapon is, and the bus already says.
var _since_shot := FIRING_MEMORY


## Spawns a zone covering `rect` as a child of `parent`. A room builds its own from its template;
## nothing else should need this, but it takes a plain `Rect2` so a test can place one anywhere.
static func spawn(parent: Node, rect: Rect2) -> ThermalZone:
	var zone := ThermalZone.new()
	zone.global_position = rect.position
	zone._size = rect.size
	parent.add_child(zone)
	return zone


func _ready() -> void:
	EventBus.shot_fired.connect(_on_shot_fired)


## How hot the zone is, zero to one. For the suite and for a debug overlay; nothing in the game
## reads it, because the colour is how the player is told.
func get_heat() -> float:
	return _heat


func is_venting() -> bool:
	return _vent_flash_left > 0.0


func _on_shot_fired(team: int, _muzzle: Vector2, _direction: Vector2) -> void:
	if team == Teams.Id.PLAYER:
		_since_shot = 0.0


func _physics_process(delta: float) -> void:
	_since_shot += delta
	_vent_flash_left = maxf(_vent_flash_left - delta, 0.0)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	var previous := _heat
	if _is_being_loaded():
		_heat = minf(_heat + delta / SECONDS_TO_VENT, 1.0)
		if _heat >= 1.0:
			_vent()
	else:
		_heat = maxf(_heat - delta / COOL_SECONDS, 0.0)

	# Redrawn only when the colour would actually differ, which for a room full of zones sitting
	# cold is the difference between a redraw per zone per frame and none at all.
	if not is_equal_approx(previous, _heat) or _vent_flash_left > 0.0:
		queue_redraw()


## Whether the zone is gaining heat: a player inside it, firing, and not moving.
##
## All three, and the third is the mechanic. `Player.STILLNESS_SPEED` is the same threshold the
## robot's own stillness bonus uses, read from there rather than restated, so "standing still"
## cannot come to mean two different speeds in the same game.
func _is_being_loaded() -> bool:
	if _cooldown_left > 0.0 or _since_shot > FIRING_MEMORY:
		return false
	var player := _find_player()
	if player == null or not _contains(player.global_position):
		return false
	return player.velocity.length() <= Player.STILLNESS_SPEED


func _vent() -> void:
	_heat = 0.0
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
	return Rect2(Vector2.ZERO, _size).grow(PLAYER_RADIUS).has_point(to_local(point))


func _find_player() -> Player:
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Player


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	if _vent_flash_left > 0.0:
		draw_rect(rect, Color(VENT_COLOR.r, VENT_COLOR.g, VENT_COLOR.b, 0.7))
		return

	var tint := COOL_COLOR.lerp(HOT_COLOR, _heat)
	draw_rect(rect, Color(tint.r, tint.g, tint.b, lerpf(COLD_ALPHA, HOT_ALPHA, _heat)))

	# An edge, so the zone's boundary is exactly readable. A hazard whose extent is a soft gradient
	# is a hazard the player has to learn by being hurt by it.
	draw_rect(rect, Color(tint.r, tint.g, tint.b, minf(HOT_ALPHA + 0.2, 1.0)), false, 1.0)
