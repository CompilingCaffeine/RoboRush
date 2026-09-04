class_name CascadeFailureConfig
extends Resource
## Tuning for the Data Center's boss, Cascade Failure.
##
## Its own resource rather than an extension of `BossConfig`, for the reason
## `RuntimeErrorConfig` is one: `BossConfig` describes The Scrap King — terminals, a feigned
## death, a duplicate that merges — and none of those words mean anything here. A boss's tuning
## is a description of *that* fight, and two fights that share nothing should not share a shape.
##
## Almost everything below is scaled at runtime by **load**, which is `node_count / nodes_alive`:
## one while the whole rack is standing, four when a single node is carrying all of it. The
## numbers here are therefore the fight at rest, and the fight at the end is the same numbers
## multiplied by four. See `CascadeFailure.get_load`.
##
## The one escalation that is not load is `aimed_vent_interval`, which ramps toward
## `aimed_vent_interval_runaway` a step per node lost. It has its own note below, and the note is
## mostly about why it is a step rather than a factor.
##
## Three clocks are deliberately left flat — `aimed_vent_interval` in the sense of not being
## multiplied, `lead_vent_interval`, and `line_vent_interval`. Each has the same argument under it:
## load is the *rack* concentrating what it already had, and a hazard aimed at the player or laid
## across the room is not the rack, it is the room. Quadrupling those alongside the nodes would
## make the last phase a different and worse fight rather than a louder one.

@export var id: StringName = &"cascade_failure"
@export var display_name: String = "Cascade Failure"

@export_group("The rack")

## The shared pool. Nodes do not have health of their own — see `CascadeFailure` for why not —
## so this is the whole fight.
@export var max_health: float = 144.0

## How many nodes the rack is built from. Also how many times the fight can escalate, because a
## node blows out at each even fraction of the pool: with four, at 75%, 50% and 25%.
##
## Changing it changes the fight's whole arithmetic — the load ceiling, the failure thresholds,
## and how many lines the ring has — which is the point of it being one number.
@export var node_count: int = 4

@export_group("Motion")

## The ellipse the ring rides at full extension, measured from the arena's centre. Elliptical
## rather than circular because the arena is 416x192 and a circle wide enough to matter does not
## fit in it — the same measurement that made `RuntimeError` sway instead of orbit.
@export var ring_radius := Vector2(150.0, 62.0)

## The smallest fraction of `ring_radius` the ring contracts to.
##
## The breathing is what stops the middle of the arena being a place to stand. A ring at fixed
## radius has a permanently safe centre, and a boss with a safe centre on the floor about not
## standing still would be a boss arguing with its own floor. At 0.35 the four nodes converge to
## a cluster around the middle and open out again, so the safe ground is an annulus that moves.
@export_range(0.05, 1.0) var ring_inhale: float = 0.35

## Radians per second of the breath. Slow: a full inhale and exhale takes about seven seconds,
## which is long enough to watch coming and short enough to happen several times a phase.
@export var ring_breath_speed: float = 0.9

## Radians per second the ring turns, at load one. Multiplied by load, so two nodes turn twice as
## fast as four did.
@export var ring_spin_speed: float = 0.45

## The most a node may travel to keep its slot, in pixels per second, scaled by any status on it.
##
## Generous enough that an unaffected node sits exactly on its slot. It exists for the affected
## ones: a chilled node falls behind the formation and visibly stretches the lines it is carrying,
## which is Cold Cache doing something you can see in the fight you bought it for.
@export var slot_track_speed: float = 400.0

## Pixels per second the last node moves once it leaves the ring and comes for the player.
##
## Deliberately below the robot's 160: the last phase is not a fight the player can lose by being
## caught, it is one they lose by being herded onto ground they made hot two seconds ago.
##
## It stays below 160 and the node still catches nobody, but it no longer walks at where the robot
## *is* — it walks at where the robot is going, on `lead_seconds`, the same rule the lead vent
## states. See `CascadeFailure._step_runaway` for why leading at 105 is worth more than chasing
## faster would be.
@export var runaway_speed: float = 105.0

@export_group("Vents")

## Seconds between one node's vents, at load one. Divided by load.
##
## The division is why the fight stays fair as it escalates. Four nodes venting every three
## seconds and one node venting every 0.75 put the *same* amount of heat on the floor per second;
## what changes is that it stops being spread around the ring and starts being a trail behind one
## body. The boss concentrates rather than out-scaling the arena, which is the difference between
## a climax and an unwinnable room.
@export var vent_interval: float = 3.0

## Seconds a dropped zone takes to fill before it vents. The player's whole warning, and it is the
## same warning the floor has been giving them for nine rooms: a patch of ground going from teal
## to violet. See `ThermalZone.spawn_vent`.
##
## **A fifth quicker than the floor's own `ThermalZone.SECONDS_TO_VENT`**, which is 1.5, and the
## divergence is deliberate rather than drift. The colour means here exactly what it means out
## there — this ground is about to vent — and the warning is still enormous next to what answering
## it costs: a patch centred on the robot is left in 37 pixels, which is under a quarter of a
## second at the robot's 160. What the shorter fill buys is that the arena *recovers* faster, and
## that is what lets the rack put more ground down at once without paving the room. The rooms teach
## the ramp at a walking pace; the boss speaks the same sentence faster.
@export var vent_seconds: float = 1.2

## The footprint of one vent, in tiles. Read against `Room.TILE_SIZE`, so a vent lines up with the
## floor it is painted on exactly as a room's own zones do. The same footprint for all four vent
## sources below: four patches of ground that mean the same thing should be the same size.
##
## Four rather than three, and the reason is not the escape margin. A 3x3 patch centred on the
## robot was left in 29 pixels and a 4x4 is left in 37 — a fifth of a second either way against a
## 1.2-second fill, and nowhere near enough to be the thing that makes a patch worth respecting.
## Sizing one patch has never been what makes this fight hard.
##
## What the fourth tile buys is that neighbouring patches **join**. At three tiles the rack laid a
## room of islands and the answer to every one of them was a sidestep; at four the arc of vents the
## ring leaves behind it closes into a band, and the chain a line vent lays becomes a continuous
## wall rather than a dashed one. The difference between stepping around a patch and pathing around
## a shape is the whole of it, and `line_vent_interval` is a wall or it is nothing.
@export var vent_tiles := Vector2i(4, 4)

## Seconds between the vents the rack aims at the player, wherever they are standing, while the
## whole rack is still up. `aimed_vent_interval_runaway` is the same clock with one node left, and
## the fight walks from this number to that one a step at a time.
##
## **Not divided by load**, unlike `vent_interval`, and the difference between that and the ramp
## below is the whole of how this stays fair. Load quadruples; this goes from three seconds to two.
## The rack's own vents concentrate as it fails, and underneath them the pressure on the player's
## own feet rises by a step they can feel rather than by a factor that would make the last phase a
## different fight — four times the aimed heat on a player with one body left to shoot.
## `CascadeFailure.get_aimed_vent_interval` is where the ramp lives, and
## `tests/test_cascade_failure.gd` measures the total rate at both extremes.
##
## Three seconds against `vent_seconds`'s 1.2 means the ground under the player is cold well over
## half the time — enough that standing still is never a strategy and moving is never frantic.
@export var aimed_vent_interval: float = 3.0

## The same clock with one node left: the aimed vent at its fastest, and this fight's pacing knob.
##
## A node blowing out is the loudest thing that happens here, and it used to change nothing about
## the pressure on the player's own feet — the ring got faster and smaller, and the clock aiming at
## the robot ran on exactly as it had, so the phase the player had just earned arrived with the
## same private rhythm underneath it. Each failure now tightens this by an even step: with four
## nodes, three seconds, then 2.67, then 2.33, then two.
##
## **It has to stay longer than `vent_seconds`.** The gap between the two is how long the ground
## the player is standing on is cold, and a clock that aims faster than a patch fills leaves none
## of it — which is a treadmill rather than a rhythm, and the one unfairness the telegraph cannot
## carry. At two seconds against a 1.2-second fill the last phase still hands the player the moment
## they can stop in; it just makes that moment worth a great deal less.
@export var aimed_vent_interval_runaway: float = 2.0

## Seconds between the vents it drops where the player is *going*. Not divided by load, for the
## reason above.
##
## The half of the pressure the aimed vent cannot supply on its own. Aimed heat lands where the
## robot is standing, so the complete answer to it is to walk in a straight line: the patch is
## always behind you and never in front. This one is the front. Together they are a pincer with
## exactly one counter — the aimed vent charges for stopping, the lead vent charges for holding a
## heading, and the only thing that answers both is to turn.
##
## This used to scatter, dropping a patch at a uniformly random point in the arena, and the reason
## given was that a 416x192 room has corners the ellipse cannot reach: heat that only appears on
## the ring or under the robot leaves those corners permanently cold, and a permanently cold corner
## on the floor about not standing still is a place to stand. A lead vent closes them better than a
## die roll did, and closes them for a reason rather than by covering enough of the room to include
## them. A player walking out wide to a cold corner is a player whose heading is *toward that
## corner*, and the vent that leads them arrives there before they do.
##
## See `CascadeFailure._step_lead_vent` for how far ahead, and `lead_seconds` for why that distance
## is not simply `vent_seconds`.
@export var lead_vent_interval: float = 3.0

## How many seconds ahead of the robot the lead vent aims, at the robot's current velocity.
##
## **Not `vent_seconds`**, which is the tempting number and the wrong one. Leading by the full fill
## time puts the patch 256 pixels ahead at the player's 160 px/s — more than five vent widths, and
## far enough that in a 416-pixel-wide room it clamps into the far wall on most headings. What the
## player would read is not a boss predicting them but a boss painting the edges of the arena.
##
## Six tenths puts it about 96 pixels out, two vent widths ahead of the chassis: near enough to be
## visibly *about* the robot, far enough that continuing forward walks into it. A player who turns
## on sight has the whole of `vent_seconds` to be somewhere else, which is the same warning every
## other patch on this floor gives.
##
## A robot standing still has no velocity to lead, so the vent lands exactly where it is standing
## and the two clocks converge on the same square. That is the correct punishment rather than a
## degenerate case: standing still is the one habit this floor exists to charge for, and it is the
## one state in which the fight stops offering a choice of which vent to answer.
##
## The last node steers by this number too — see `CascadeFailure._step_runaway`. One lead for both
## is deliberate: a player who has learned to turn away from the patch in front of them has learned
## the thing the last phase asks, and meeting it twice in one fight is a rule being confirmed
## rather than a second rule being introduced.
@export var lead_seconds: float = 0.6

@export_group("The line vent")

## Seconds between the vents the rack lays **along one of its own wires**: a chain of patches from
## one living node to its neighbour, dropped together, filling together, and becoming a wall across
## the room.
##
## This is the only thing the rack does that denies a *route* rather than a square, and the fight
## needed one. Everything else it puts down is a patch the robot leaves in a fifth of a second, so
## a player circling at range was never once asked to choose between two bad options — they
## sidestepped, forever, for the length of the fight. A wall cannot be sidestepped. It has to be
## crossed before it fills, or accepted, and either answer has to be chosen while it is still cold.
##
## It is drawn on geometry the player has been reading since the first second of the fight. The
## lines between the nodes are already on screen, already dim, already the thing that says where a
## packet can appear; the wall arrives on one of them, so the telegraph is not only the colour ramp
## but the wire it is painted along. Nothing new has to be learned to see it coming.
##
## **Not divided by load**, for `aimed_vent_interval`'s reason, and it does not need to be — the
## mechanic escalates on its own and does it out of the fight's own arithmetic. Four nodes make
## four short chords near the rim. Two make a single wire straight through the middle, and how
## nearly that wire cuts the room in half is decided by *which* two nodes the player chose to leave
## standing. One node makes no wires at all, and the wall the last phase has instead is the trail
## behind the node itself. The fight's loudest hazard is the one the player picked the shape of.
##
## Five seconds is about seven walls across a fight at the starting weapon's damage — often enough
## to be the rhythm the phases are counted in, rare enough that the room is open most of the time.
@export var line_vent_interval: float = 5.0

@export_group("Load packets")

## Pixels per second a packet travels along the line between two nodes, at load one. Multiplied by
## load.
@export var packet_speed: float = 150.0

@export var packet_damage: float = 1.0

## How close the player's centre must come to a packet to be hit, before the robot's own radius is
## added. Matched to the dot that is drawn, so what hurts is what is visible — Firewall Node's
## rule, and for its reason.
@export var packet_radius: float = 4.0

## Seconds before any packet may hit the player again. One cooldown for the whole rack rather than
## one per line, so crossing the point where two lines meet is one hit and not two.
@export var packet_interval: float = 0.9

@export_group("Presentation")

## The lines between living nodes: visible always, harmless in themselves. They are geometry the
## player needs in order to read where a packet can appear, so they are drawn dim rather than not
## at all.
@export var line_color: Color = Color(0.42, 0.52, 0.60, 0.55)

## The packet itself. Near-white, like every other thing on this floor that is not heat: the
## teal-to-violet ramp belongs to the vents, and a hazard borrowing a colour off that ramp would be
## claiming to be something the player already knows how to read.
@export var packet_color: Color = Color(0.94, 0.97, 1.0, 0.95)
