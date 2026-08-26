class_name ThermalZone
extends Node2D
## Floor 3's signature mechanic: a patch of floor that heats up under sustained load and vents.
##
## The Data Center's throughput zones are the floor's one new idea, and the idea is **stop
## camping**. A zone gains heat while the player stands inside it firing, loses heat the moment
## they move or stop, and when it fills it vents — a flash and one point of integrity to whoever
## is still standing there. Nothing about it is random and nothing about it is hidden: the zone is
## drawn on the floor as a grille of louvre bars, its heat is their colour, and the vent is
## telegraphed by that colour having been climbing for two and a half seconds.
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
## rect so a body and not a centre point decides who is inside.
##
## **Two lifetimes, and two causes.** A room's zones are furniture: built with the room, switched
## off with it, and heated by nothing but the player's own stationary fire. A *driven* zone — see
## `spawn_vent` — is a hazard the Cascade Failure boss puts on the floor, on its own clock, and it
## follows `CompileLane`'s lifetime instead: parented into the session so a vent already climbing
## still costs something after the thing that started it is dead.
##
## What does not differ between them is the only thing the player reads. The colour means how close
## this ground is to venting, in a room's zone and in a boss's alike. Nine rooms of the Data Center
## teach that ramp with the player as its cause; the boss keeps the sentence and changes the
## subject. A boss's vents are deliberately given no look of their own for that reason — see
## `COOL_COLOR` for what the look is, and which floor above it is being told apart from.

## Seconds of stationary firing inside a zone before it vents.
##
## Long enough that the colour climbing off teal is a warning a player can act on, short
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
##
## **The hot end is violet rather than red, and that is a deliberate separation from the floor
## above.** Development's hazard language is `CompileLane`'s amber-then-red, and it is a good
## language: the Compiler enemy teaches it and Runtime Error's whole fight is written in it. The
## trouble was that this floor's ramp also ended in red, so two floors' worth of unrelated hazards
## resolved to the same colour a beat before they bit — and the second of them was the one the
## player met at speed. A ramp is only worth reading if it is the only thing that looks like it.
##
## Violet also happens to be what the fiction wanted. Amber-to-red is fire, and nothing here is on
## fire; a rack that has run out of thermal headroom arcs. Teal through indigo to a hard magenta is
## a machine going somewhere it was not built to go, and it reads against the Data Center's cold
## steel in a way another warm colour on a cold floor never quite did.
const COOL_COLOR := Color(0.24, 0.62, 0.68)
const HOT_COLOR := Color(0.80, 0.24, 0.98)
const VENT_COLOR := Color(0.97, 0.90, 1.0)

## Alpha at zero heat and at full heat. The zone is always visible — a hazard that appears only
## once it is dangerous is a trap, and this floor is not built out of traps.
const COLD_ALPHA := 0.16
const HOT_ALPHA := 0.5

## Pixels between the louvre bars the zone is drawn as, and how thick each one is.
##
## The second half of the separation from `CompileLane`, and the half that survives a colourblind
## player and a badly calibrated screen. A lane is a flat filled rectangle; this is a grille — thin
## bars over a dim wash, which is what the face of a rack unit actually looks like and is nothing a
## lane has ever looked like. Two hazards that mean different things now differ in shape as well as
## in hue, so neither reading has to carry the distinction on its own.
##
## Four pixels at a 480x270 render is a bar and a gap the player can resolve, and every zone is a
## whole number of 16-pixel tiles, so the pattern never ends on a half bar.
const LOUVRE_SPACING := 4.0
const LOUVRE_THICKNESS := 1.0

## What the wash behind the louvres keeps of the zone's alpha. The bars carry the reading; the wash
## is only there so the extent of the zone stays obvious on the ground between them.
const WASH_ALPHA_SCALE := 0.45

var _size := Vector2.ZERO

## Zero to one. The whole mechanic is this number and what is allowed to change it.
var _heat := 0.0

var _vent_flash_left := 0.0
var _cooldown_left := 0.0

## Seconds this zone takes to fill on its own, ignoring the player entirely. Zero for a room's own
## zones, which is every zone on the floor: those fill only under stationary fire, and a floor whose
## furniture heated by itself would be charging the player for arriving rather than for a habit.
## Positive only for a zone from `spawn_vent`.
var _drive_seconds := 0.0

## Set once a driven zone has spent its one vent. It frees itself as soon as the flash is finished,
## so the arena recovers on its own and the boss cannot pave it.
var _spent := false

## Seconds since the player last fired, counted from `EventBus.shot_fired` rather than read off the
## weapon. The zone has no business knowing what a weapon is, and the bus already says.
var _since_shot := FIRING_MEMORY


## Spawns a zone covering `rect` as a child of `parent`. A room builds its own from its template;
## nothing else should need this, but it takes a plain `Rect2` so a test can place one anywhere.
##
## **`add_child` first, then the position**, and the ordering is the whole of a bug that shipped with
## this floor. `global_position` on a node with no parent is only its local position — there is no
## parent transform to measure against — so assigning it before parenting silently wrote a *global*
## rect into a *local* slot. `Room._build_thermal_zones` passes global coordinates from
## `get_tile_block_rect`, and the room's zones hang off a node inside the room, so every zone landed
## at the room's own position twice over: a room at (896, 224) put its floor patches at (1808, 464),
## most of a screen away, in whatever room happened to be sitting there.
##
## It was invisible from both directions, which is why it lasted. Every arena in the suite builds its
## room at the origin, where adding zero twice is still zero and the zones land exactly right. And in
## a real run the misplaced patches were still *drawn* — just in the wrong rooms — so the floor
## looked like it had zones in it. What it did not have was zones in the rooms authored to teach
## them, which is the whole of what the Data Center is for. `tests/test_thermal.gd` now builds a room
## somewhere other than the origin, which is the only version of that check worth having.
##
## The same lesson `MergeConflict._spawn_part` and `CascadeFailure.begin` both paid for already.
static func spawn(parent: Node, rect: Rect2) -> ThermalZone:
	var zone := ThermalZone.new()
	zone._size = rect.size
	parent.add_child(zone)
	zone.global_position = rect.position
	return zone


## Spawns a zone that fills on its own clock over `seconds`, vents once, and frees itself.
##
## Parented the way `CompileLane` parents itself and for its reason, not the way a room's zone is:
## into the floor's session, so a vent already climbing when the boss that started it dies goes on
## to fill and to cost the player a point in an arena they have apparently just won. A warning
## already given should still be worth reading. `tests/test_post_boss.gd` asserts that outcome
## rather than this parenting, so the promise survives somebody tidying the mechanism.
##
## `spawner` is used only to find the container, and falls back to the current scene when there is
## none — the same fallback `CompileLane` and `ProjectileFactory` both make, so a test arena with no
## floor in it still works.
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
	# After `add_child`, for the reason `spawn` above gives at length. This path happened to be
	# correct while the container sat at the origin, which is not the same as being right.
	zone.global_position = rect.position
	return zone


func _ready() -> void:
	# A driven zone has no interest in who is shooting: its clock is its own. Skipped rather than
	# connected and ignored, because a boss puts a great many of these on the floor over one fight.
	if not is_driven():
		EventBus.shot_fired.connect(_on_shot_fired)


## How hot the zone is, zero to one. For the suite and for a debug overlay; nothing in the game
## reads it, because the colour is how the player is told.
func get_heat() -> float:
	return _heat


func is_venting() -> bool:
	return _vent_flash_left > 0.0


## The ground this zone covers, in global coordinates — the same rect `thermal_zone_vented` carries
## and the same one `_contains` measures against, so nothing has to reconstruct it from a position
## and a size that are not both public.
func get_rect() -> Rect2:
	return Rect2(global_position, _size)


## Whether this zone fills on its own clock rather than under the player's fire. False for every
## zone a room builds.
func is_driven() -> bool:
	return _drive_seconds > 0.0


func _on_shot_fired(team: int, _muzzle: Vector2, _direction: Vector2) -> void:
	if team == Teams.Id.PLAYER:
		_since_shot = 0.0


func _physics_process(delta: float) -> void:
	_since_shot += delta
	_vent_flash_left = maxf(_vent_flash_left - delta, 0.0)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if is_driven():
		_step_driven(delta)
		return

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


## A driven zone's whole life: climb, vent once, and go. It never cools, because nothing the player
## does is what filled it — there is no habit to stop, only ground to leave.
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


## A grille rather than a filled rectangle. See `LOUVRE_SPACING` for why the shape carries as much
## of the reading as the colour does.
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	if _vent_flash_left > 0.0:
		draw_rect(rect, Color(VENT_COLOR.r, VENT_COLOR.g, VENT_COLOR.b, 0.7))
		return

	var tint := COOL_COLOR.lerp(HOT_COLOR, _heat)
	var alpha := lerpf(COLD_ALPHA, HOT_ALPHA, _heat)
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
