class_name ThermalZone
extends Node2D
## Floor 3's signature mechanic: a patch of floor that heats up under sustained load and vents.
##
## The Data Center's throughput zones are the floor's one new idea, and the idea is **this ground
## costs you**. A zone gains heat while the player is standing on it, loses it the moment they step
## off, and when it fills it vents — a flash and one point of integrity to whoever is still standing
## there. Nothing about it is random and nothing about it is hidden: the zone is drawn on the floor
## as a grille of louvre bars, its heat is their colour, and the vent is telegraphed by that colour
## having been climbing for a second and a half.
##
## **The ramp used to be slower and it used to start invisibly, and both were the same bug.** It was
## reported the way a mechanic that does not exist is always reported: the zones "never did anything
## or changed" across a whole playthrough. They were working exactly as written. What they were not
## doing was ever getting *read* — the first half-second of load moved the colour a few percent off
## cold, which is nothing at the size these are drawn, so a player standing in a heating zone had no
## way to connect the thing they were doing to the thing the floor was about to charge them for.
## They would move for some unrelated reason, the heat would drain, and the floor would teach
## nothing. A hazard nobody can catch heating is a hazard that only ever arrives as a surprise.
##
## The fix is two numbers and it is deliberately both of them. `SECONDS_TO_VENT` is shorter, so
## standing on a zone is a decision with a deadline the player can feel; `IGNITION_HEAT` makes the
## first *frame* of load a visible change, so the deadline is one they can see start. Either alone
## would have been worse than neither: a faster ramp nobody can see is just a hazard that bites
## sooner, and a visible ramp with three seconds of slack in it is a warning nobody has to answer.
##
## **Why occupancy, and not the player's habits.** A zone charges for the ground it covers and for
## nothing else: stand on it and it heats, whatever the player happens to be doing while they stand
## there.
##
## It used to ask for more. Heat accrued only while the player was inside a zone *and* firing *and*
## holding still, which named the habit the floor meant to tax far more precisely and was much
## worse to play. A hazard with three conditions on it is a hazard nobody can state, and a rule
## nobody can state is a rule nobody learns: the player would watch a zone climb, step off, come
## back, hold a firing position a little slower or a little faster than last time, and see nothing
## happen. Ground that is simply hot to stand on is a sentence the floor gets to say once, in
## colour, and never has to say again — and it is the sentence the grille was always drawing.
##
## What has to stay out of it is the *weapon*. Heat per shot would make a fast weapon heat a zone
## faster, so `fire_rate_scale` items — Cooling Fan, Unsafe Overclock — would quietly become
## liabilities on this floor, and an item that is a liability on one floor of six is an item nobody
## picks. Occupancy taxes a *position*, and every build pays for a position identically: keep off
## the grilles and this floor costs you nothing at all, at any fire rate, holding anything.
##
## It also stops the floor quarrelling with `fire_requires_stillness`. Under the old rule an item
## that asked the player to hold still was asking for precisely the thing the floor charged for, so
## the two were at war on every zone in ten rooms. Now the zone charges for *where* and the item
## asks about *how*, and a player can answer both at once by standing still somewhere else.
##
## The floor still teaches movement, and teaches it to everyone rather than only to the players
## who had stopped to shoot. `SECONDS_TO_VENT` is set against the robot's walking speed, not
## against its fire rate — see there — so crossing a zone is always affordable and stopping on one
## never is.
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
## off with it, and heated by nothing but the player standing on them. A *driven* zone — see
## `spawn_vent` — is a hazard the Cascade Failure boss puts on the floor, on its own clock, and it
## follows `CompileLane`'s lifetime instead: parented into the session so a vent already climbing
## still costs something after the thing that started it is dead.
##
## What does not differ between them is the only thing the player reads. The colour means how close
## this ground is to venting, in a room's zone and in a boss's alike. Nine rooms of the Data Center
## teach that ramp with the player as its cause; the boss keeps the sentence and changes the
## subject. A boss's vents are deliberately given no look of their own for that reason — see
## `COOL_COLOR` for what the look is, and which floor above it is being told apart from.

## Seconds spent standing inside a zone before it vents.
##
## Long enough that the colour climbing off teal is a warning a player can act on, short enough
## that stopping on a zone is never the right answer. The number to measure it against is the
## robot's walking speed rather than its fire rate: a second and a half at `move_speed` is 240
## pixels, wider than any zone the Data Center authors, so a player who walks across the widest
## grille on the floor spends well under half the ramp and leaves with the rest of it in hand.
## Crossing is free. Stopping is the thing being charged for, and the ramp is sized so that it is
## the *only* thing being charged for.
##
## It was two and a half, which was long enough that a player could hold a position through most of
## a zone's ramp and leave for reasons of their own before it ever resolved — see the class doc for
## how that reads from the outside, which is as a floor whose hazards do nothing at all.
##
## Landing within a tenth of `CascadeFailureConfig.vent_seconds` is worth keeping. The boss's vents
## fill on their own clock rather than under the player's feet, but they are the same zone drawn the
## same way, and a ramp that means "about a second and a half" in nine rooms and something else in
## the tenth is a ramp the player has to learn twice.
const SECONDS_TO_VENT := 1.5

## Seconds from full heat back to cold, once the zone is no longer being loaded. Faster than it
## heats, so leaving a zone is always a complete answer rather than a partial one — a player who
## has been driven off a hot zone can come back to it. Kept at the same six-tenths of
## `SECONDS_TO_VENT` it has always been, so shortening the ramp did not quietly also make walking
## away a worse answer than it was.
const COOL_SECONDS := 0.9

## What a vent costs. One point, matching an ordinary enemy hit against the player's six: the floor
## teaches by being expensive to ignore, not by being lethal on first contact.
const VENT_DAMAGE := 1.0

## Seconds after a vent during which the zone cannot heat again. The window in which leaving is
## guaranteed to work — without it, a player standing in a zone at full heat would be hit
## repeatedly before they could cross its edge.
const VENT_COOLDOWN := 1.0

## What a zone is *drawn* as the instant it starts taking load, before it has taken any.
##
## The zone's real heat still starts at zero and still climbs at one rate — this changes nothing
## about when it vents or what it costs. What it changes is that the change is *visible on the
## first frame*: a loaded zone jumps most of the way up the teal-to-violet ramp and then walks the
## rest of it, instead of spending its first half-second at a colour nobody can tell from cold.
##
## This is the whole of the reported bug. A hazard that answers to what the player is doing has to
## show them it is answering, on the frame they step onto it, or the thing they did is not what
## they will think caused it.
##
## Four tenths, because it has to clear the noise floor of a 480x270 render — the wash is drawn at
## `COLD_ALPHA` and a few percent of hue on top of that is nothing — while leaving most of the ramp
## above it. A zone that snapped to full violet the moment it was loaded would be legible and
## useless: it would say "hot" for a second and a half without ever saying "hotter".
const IGNITION_HEAT := 0.4

## Seconds the ignition floor takes to fade once a zone stops being loaded.
##
## Fading rather than snapping, and short rather than gentle. Snapping would strobe: a player
## fighting along a zone's edge crosses it several times a second, and a zone that jumped a third
## of the way up its ramp and back on every one of those would be unreadable. A quarter-second is
## under that flicker and still fast enough that stepping off a zone reads as stepping off it.
const IGNITION_FADE := 0.25

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

## One while the zone is being loaded, decaying to zero over `IGNITION_FADE` once it is not.
## Purely a display term — see `IGNITION_HEAT`. Nothing that decides damage reads it.
var _ignition := 0.0

## Seconds this zone takes to fill on its own, ignoring the player entirely. Zero for a room's own
## zones, which is every zone on the floor: those fill only while the player is standing on them,
## and a floor whose furniture heated by itself would be charging the player for being in the room
## rather than for the ground they chose to stand on.
## Positive only for a zone from `spawn_vent`.
var _drive_seconds := 0.0

## Set once a driven zone has spent its one vent. It frees itself as soon as the flash is finished,
## so the arena recovers on its own and the boss cannot pave it.
var _spent := false

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


## How hot the zone is, zero to one. For the suite and for a debug overlay; nothing in the game
## reads it, because the colour is how the player is told.
func get_heat() -> float:
	return _heat


func is_venting() -> bool:
	return _vent_flash_left > 0.0


## What the zone is drawn as, which is not quite what it is: the real heat, floored at
## `IGNITION_HEAT` while the zone is under load. The player reads this; `_vent` reads `get_heat`.
##
## Public because it is the half of the mechanic that was missing, and a thing that was once
## invisible in the game should not also be invisible to the suite. Nothing in the game calls it —
## `_draw` is the only reader, and the colour is how the player is told.
func get_display_heat() -> float:
	return maxf(_heat, IGNITION_HEAT * _ignition)


## The ground this zone covers, in global coordinates — the same rect `thermal_zone_vented` carries
## and the same one `_contains` measures against, so nothing has to reconstruct it from a position
## and a size that are not both public.
func get_rect() -> Rect2:
	return Rect2(global_position, _size)


## Whether this zone fills on its own clock rather than under the player's fire. False for every
## zone a room builds.
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
