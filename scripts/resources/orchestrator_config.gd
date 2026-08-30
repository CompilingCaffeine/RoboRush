class_name OrchestratorConfig
extends Resource
## Cloud Operations' boss, as data. See `Orchestrator` for the fight.

## Stable identifier, for the reason `ItemConfig.id` must not change once it ships.
@export var id: StringName = &"orchestrator"

@export var display_name: String = "Orchestrator"

@export_group("Plates")

## How many plates the arena has.
##
## Six, doubled from the three this fight shipped with, and the doubling is what makes the rest of
## the design possible rather than being more dots on the floor. Three plates could not go *dark*:
## take one away and the two survivors may sit on the same side of a 416x192 room, which is a
## migration nobody can shelter from. Six can lose half of itself and still leave shelter within
## reach of every corner — see `live_plates_by_phase`, and `Orchestrator._plate_positions` for the
## ellipse they sit on.
@export var plate_count: int = 6

## How far out from the arena's centre the plates sit, as a fraction of the arena's half-extent.
## Under one so the plates stay clear of the walls, and high enough that crossing between them is a
## real distance in a 416x192 room.
@export_range(0.1, 1.0) var plate_radius: float = 0.72

## The side of a plate's square, in pixels. Matched to the two-tile plates the floor's rooms use, so
## a player who has learned what a pad looks like recognises one here.
@export var plate_size: float = 32.0

## How many plates stay live in each phase, indexed by phase number minus one.
##
## **Five, three, two** — and never all six, because the plate the boss is standing on is never one
## of them. "Every plate but the one it is on" is the opening rule, and it is a rule the player can
## state after one migration.
##
## This is the fight's whole escalation, and it is spent on the arena rather than on the boss. The
## boss's own numbers — how hard it hits, how fast it fires, how long it gives you — never move. The
## floor does: the ground that answers a migration shrinks from five islands to three to two, so the
## same telegraph that was a stroll in the first third is a committed sprint in the last.
##
## The values are load-bearing and `tests/test_orchestrator.gd` measures them rather than trusting
## them. With two live plates chosen from the five the boss is not on, the worst point in the arena
## is 225 pixels from shelter — 1.41 seconds at the robot's 160 px/s, against a 1.9-second
## telegraph. Take it to one and that becomes a migration a player in the wrong corner cannot
## answer, which is the one thing this fight must never be.
@export var live_plates_by_phase: PackedInt32Array = PackedInt32Array([5, 3, 2])

@export_group("Durability")

## What it takes to kill it.
##
## **This number is not comparable to the other three bosses' and must not be "corrected" to match
## them.** Runtime Error's 110 and Cascade Failure's 144 are pools a player can pour damage into for
## the whole fight. This one is only open for `cold_start_seconds` out of every cycle — about a
## third of the clock, or nearer a half when denials are being won — so what a continuous-fire
## comparison would have to weigh 68 against is roughly 200, which is more than any boss in the
## game. See `Orchestrator` for why the fight is gated rather than pooled.
##
## The corollary is the good half: playing well shortens it honestly. A denial buys
## `denial_open_seconds` instead of `cold_start_seconds`, so a player who wins every race spends
## about 46% of the fight doing damage against about 34% for a player who wins none — the same boss,
## a third shorter, with no number anywhere changing.
@export var max_health: float = 68.0

## Health fractions at which the second and third phases begin. The same shape `RuntimeError` uses,
## and read the same way: what changes at each is how much of the floor is left to stand on.
@export_range(0.0, 1.0) var phase_two_at: float = 0.66
@export_range(0.0, 1.0) var phase_three_at: float = 0.33

@export_group("Cycle")

## Seconds it sits sealed on a plate, firing, before it announces the next migration.
##
## The player's time to reposition and to read which plates are live. Short enough that the fight is
## a rhythm rather than a wait, long enough that arriving from a denial on the far side of the room
## is not immediately followed by another sprint back.
@export var dwell_seconds: float = 2.4

## How long it telegraphs a migration before it resolves.
##
## The single most important number in the fight, because it is the player's entire budget for
## reaching ground that will still exist. Measured against the worst case rather than guessed at: in
## the last phase the furthest any point in the arena sits from the nearest live plate is 225 pixels,
## 1.41 seconds at the robot's walking speed, so 1.9 leaves about half a second and a dash of margin.
## `tests/test_orchestrator.gd` recomputes that from the shipped geometry, so a change to
## `plate_radius`, `plate_count` or `live_plates_by_phase` that quietly makes a migration
## unanswerable fails there rather than in somebody's run.
@export var telegraph_seconds: float = 1.9

## Seconds it is open to damage after it lands. The only window in the fight where shooting it does
## anything at all — see `Orchestrator._on_part_damaged`.
##
## It holds fire for the whole of it, which is what makes the window a window rather than a trade.
@export var cold_start_seconds: float = 2.2

## Seconds it is open after a *denied* migration. Longer than `cold_start_seconds`, and the gap is
## the entire reward for the run across the room.
##
## Deliberately a bigger window rather than bonus damage: a multiplier would be a number the player
## has to be told, and this is a number they can see, because they can see how long they get to keep
## shooting.
@export var denial_open_seconds: float = 3.6

## What being off every live plate costs when a migration resolves. One point, the same as an
## ordinary enemy hit against the player's six, and the same as a thermal vent: the fight teaches by
## being expensive to ignore rather than by being lethal the first time.
@export var off_plate_damage: float = 1.0

@export_group("Attacks")

## The spread the live instance fires at the player.
@export var shot: ProjectileConfig

## Seconds between volleys while the boss is sealed on a plate.
@export var volley_interval: float = 1.5

## Seconds between volleys while a migration is telegraphing.
##
## Faster than `volley_interval`, deliberately: the telegraph is the window the player has to cross
## the room, so crossing it has to cost something. A boss that went quiet while announcing the one
## event the player can turn to their advantage would be handing the fight over.
@export var telegraph_volley_interval: float = 0.7

@export var spread_count: int = 3
@export var spread_degrees: float = 34.0
