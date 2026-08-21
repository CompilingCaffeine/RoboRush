class_name MigrationPad
extends Node2D
## A patch of floor that is also a different patch of floor. Step on one end of a link and the
## robot is standing on the other.
##
## **Cloud Operations' signature mechanic, and the first thing in the game that moves the player.**
## Everything up to this floor answers the question "where are you standing" by changing what the
## ground costs: a `CompileLane` denies a stripe of it, a `ThermalZone` charges for staying still on
## it, a `CableDuct` decides which way round it you may go. All three are things done *to* the
## floor. A pad changes what the floor *is connected to*, which is the one property the room could
## not previously say anything about — and it is the player who says it, by choosing to step on one.
##
## **Why it does not tax the build.** The lesson `ThermalZone` writes down at length is that a
## mechanic charging the player for their damage output is a mechanic that drowns a weak build and
## is invisible to a strong one. A pad charges nothing at all. It is not a hazard, it never damages
## anybody, and no item interacts with it: what it costs is a decision about position, which is the
## one currency every build has exactly as much of as every other.
##
## **Why the destination is never a surprise.** A teleport is the easiest mechanic in games to make
## unreadable, and the usual reason is that the far end is somewhere the player cannot see. That
## cannot happen here, and not because of anything this script does: every room in Robo Rush is one
## screen with no scrolling — `Room`'s own doc calls that load-bearing for combat legibility — so
## both ends of a link are on screen, in view, at the moment the player decides. The pips do the
## rest. Which pad goes where is a thing the player reads, not a thing they learn by being moved
## somewhere they did not expect.
##
## **Why the player and nothing else.** No enemy migrates, and that is the mechanic rather than a
## simplification. A room split by ducts and joined by pads is a room the player can leave and a
## *walking* fight cannot follow them out of — the Load Balancer keeps its plate pointed at ground
## nobody is standing on, the Stale Replica walks a route that no longer has anybody on it. Letting
## enemies use pads would collapse that into an ordinary doorway with extra steps, and it would make
## the one thing a mobility mechanic must never be: a way for a room to put something behind the
## player without warning.
##
## The exception is the point rather than a hole in it. `PopUpDrone` gets somewhere else by its own
## means — it teleports to a room's edge, and has since the first floor — so it is the one thing in
## the game that can answer the player's trick with the same trick. Floor 3 left it off its roster
## for exactly that reason, that nothing a player learns about holding ground applies to it. This
## floor lists it deliberately: a mobility floor should have one enemy that is also mobile, and it
## should be the one the player already knows the telegraph for. Note what it still cannot do — it
## picks points on the room's inset perimeter, so a sealed interior like `cloud_blast_radius`'s vault
## stays sealed against it, and a pad is still the only way in.

## The plate, and the pips that say which plate it is paired with.
##
## Green, and specifically not the colour of anything that bites. Development's hazard language is
## amber into red and the Data Center's is teal into violet, and both mean *this ground will cost
## you something*. A pad is the only piece of floor in the game that is purely an offer, so it is
## the only one drawn in a colour no hazard has ever used. A player who has come through two floors
## of warm and violet floor patches has learned to read a tinted rectangle as a warning, and this
## one has to say the opposite at a glance.
const PAD_COLOR := Color(0.35, 0.92, 0.58)

## Alpha of the plate's wash, its border, and its pips. The wash is faint because the pad is
## permanent furniture the player walks over all fight; the border is what makes its extent exact,
## for the reason `ThermalZone` gives about hazards with soft edges.
const WASH_ALPHA := 0.16
const BORDER_ALPHA := 0.62
const PIP_ALPHA := 0.92

## One frame of white when the pad is used, and how long it lasts. Confirmation that the thing the
## player just did was the thing they meant to do — a teleport with no acknowledgement at either end
## reads as a glitch the first time it happens.
const FLASH_SECONDS := 0.16

## Pip geometry, in pixels. Pips are stacked down the middle of the plate.
const PIP_SIZE := Vector2(6.0, 2.0)
const PIP_GAP := 2.0

## The other end. Set by `Room._build_pads` when the pair is created, and never null on a pad the
## room built — `MigrationLink` makes a half link unauthorable, so there is no legal arrangement of
## the data that produces a partnerless pad.
var partner: MigrationPad

## Which link on the template this pad belongs to, from zero. Drawn as that many pips plus one, and
## that is the *primary* way a player tells two links apart — a count, not a hue.
##
## Deliberately shape rather than colour, which is the lesson `ThermalZone`'s louvre bars record
## after this project shipped two floors whose hazards resolved to the same red: a distinction
## carried only by hue is a distinction a colourblind player and a badly calibrated screen do not
## get. Both ends of a link draw the same number of pips, so pairing them is counting.
var pair_index := 0

var _size := Vector2.ZERO

## Whether stepping on this pad would do anything right now.
##
## False for exactly as long as the player is standing on a pad they *arrived* on, which is what
## stops a link bouncing the robot back and forth for as long as they hold still. There is no timer
## here and no cooldown constant, which is the point: the rule is "a pad you were put on does not
## fire until you leave it", and that is a fact about where the player is rather than about how long
## ago something happened. A duration would need a number, and any number would be wrong for
## somebody's frame rate.
var _armed := true

var _flash_left := 0.0


## Spawns one end of a link covering `rect`, as a child of `parent`.
##
## `add_child` before `global_position`, and the ordering is not a style choice — see
## `ThermalZone.spawn`, which documents at length the bug this ordering exists to avoid. Assigning
## `global_position` to a node with no parent writes a global coordinate into a local slot, and the
## rooms this floor is made of are not at the origin.
static func spawn(parent: Node, rect: Rect2, index: int) -> MigrationPad:
	var pad := MigrationPad.new()
	pad._size = rect.size
	pad.pair_index = index
	parent.add_child(pad)
	pad.global_position = rect.position
	return pad


## Joins two pads into a link. Called once per `MigrationLink`, with both ends already spawned.
static func link(first: MigrationPad, second: MigrationPad) -> void:
	first.partner = second
	second.partner = first


func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left > 0.0:
		queue_redraw()

	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
	if player == null:
		# Nobody to arm against. Re-armed rather than left as it was, so a pad cannot remember an
		# occupancy from a run that has since ended — a floor is rebuilt on resume and the player
		# is a different node.
		_armed = true
		return

	# The robot's *centre*, with no chassis radius added — unlike `ThermalZone`, which grows its
	# rect by `PLAYER_RADIUS` before asking. The asymmetry is deliberate and runs the way it should:
	# a hazard ought to catch a robot that is only partly inside one, and a route ought not to move
	# a robot that has not driven onto it. Brushing the corner of a pad does nothing.
	if not get_rect().has_point(player.global_position):
		_armed = true
		return

	if not _armed or partner == null:
		return

	_migrate(player)


## The ground this pad covers, in global coordinates. Public for the same reason
## `ThermalZone.get_rect` is: nothing should have to rebuild it from a position and a size that are
## not both readable.
func get_rect() -> Rect2:
	return Rect2(global_position, _size)


## Where a robot arriving here is put: the middle of the plate.
##
## The centre rather than the matching offset within the pad, which would be the clever version and
## is worse. A player entering a 2x2 plate at its top-left corner would arrive at the far pad's
## top-left corner, one pixel from ground the pad does not cover, and on a plate authored beside a
## wall that is an arrival half inside it. The middle of a pad is the one point on it that is
## guaranteed to be as clear as the pad is.
func get_arrival_point() -> Vector2:
	return global_position + _size * 0.5


## Whether stepping on this pad would currently move the player. For the suite; the game reads it
## nowhere, because a pad that looked different while disarmed would be a pad telling the player
## about a rule they cannot act on.
func is_armed() -> bool:
	return _armed


func _migrate(player: Node2D) -> void:
	# The far pad is disarmed *before* the player is moved, not after. Ordering matters: the two
	# pads' `_physics_process` calls run in tree order, and if the partner's ran later in the same
	# frame it would find the player standing on an armed pad and send them straight back.
	partner._armed = false
	partner._flash_left = FLASH_SECONDS
	partner.queue_redraw()

	_armed = false
	_flash_left = FLASH_SECONDS
	queue_redraw()

	player.global_position = partner.get_arrival_point()
	AudioManager.play_sfx(&"migrate", 0.04)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	if _flash_left > 0.0:
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.7))
		return

	draw_rect(rect, Color(PAD_COLOR.r, PAD_COLOR.g, PAD_COLOR.b, WASH_ALPHA))
	draw_rect(rect, Color(PAD_COLOR.r, PAD_COLOR.g, PAD_COLOR.b, BORDER_ALPHA), false, 1.0)

	# The pips, centred as a block so a two-pip pad and a three-pip pad share a midpoint and read as
	# the same kind of marking rather than as two different ones.
	var pips := pair_index + 1
	var block_height := pips * PIP_SIZE.y + maxi(pips - 1, 0) * PIP_GAP
	var top := (_size.y - block_height) * 0.5
	var left := (_size.x - PIP_SIZE.x) * 0.5
	for pip: int in pips:
		draw_rect(
			Rect2(Vector2(left, top + pip * (PIP_SIZE.y + PIP_GAP)), PIP_SIZE),
			Color(PAD_COLOR.r, PAD_COLOR.g, PAD_COLOR.b, PIP_ALPHA),
		)
