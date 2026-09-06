class_name CoreIntelligenceConfig
extends RuntimeErrorConfig
## Finale tuning: Runtime Error's lane and projectile vocabulary, plus the four numbers-worth of
## every other boss in the campaign, because the finale wears all of them.
##
## Core Intelligence fights in **masks** (see `CoreIntelligence`), and a mask is a slice of one
## health pool rather than a fight of its own. So what is added here is one boundary and one attack
## interval per mask, then the handful of numbers each borrowed idea needs that Runtime Error's own
## tuning never had to carry — terminals, a lead time, a migration window.
##
## Two of the inherited fields are deliberately dead here and are not written into
## `core_intelligence.tres`: `phase_two_at` and `phase_three_at` describe Runtime Error's
## three-phase ladder, and this boss has five masks instead. `CoreIntelligence._advance_phase`
## overrides the method that reads them, so leaving them at their defaults changes nothing — and
## writing them into the finale's resource would put two ladders in one file, only one of which the
## fight is using. The same goes for `phase_one_interval` and its two siblings, superseded by the
## five mask intervals below.

@export_group("Masks")

## Health fractions the masks change at, read as "at or below this, the next mask is worn". Five
## even-ish slices of one pool rather than the escalating thirds Runtime Error uses: each mask is a
## different *fight* rather than the same fight faster, so no slice should be worth noticeably more
## of the player's time than the one before it.
##
## The last boundary is where the masks run out. Below `core_mask_at` the boss is finally itself,
## and that slice is deliberately the shortest thing in the fight — see `CoreIntelligence`.
@export_range(0.0, 1.0) var runtime_mask_at: float = 0.80
@export_range(0.0, 1.0) var cascade_mask_at: float = 0.60
@export_range(0.0, 1.0) var orchestrator_mask_at: float = 0.40
@export_range(0.0, 1.0) var core_mask_at: float = 0.20

## Seconds between attacks in each mask. They tighten by a tenth or so per mask and then drop hard
## for the last one, which is the only place in the fight where the pressure comes from the clock
## rather than from a new idea: by then the player has seen everything the boss has, so the last
## mask can only ask them to do it faster.
@export var scrap_interval: float = 2.2
@export var runtime_interval: float = 2.05
@export var cascade_interval: float = 1.95
@export var orchestrator_interval: float = 1.85
@export var core_interval: float = 1.45

@export_group("The Scrap King's mask")

## Terminals raised with the first mask, one per corner. The Scrap King's count, because this is
## the Scrap King's puzzle: while any of them stands, the two copies are still synchronised and
## most of the damage the player deals is undone.
@export var terminal_count: int = 4

## What one terminal costs to break. Above the King's six, because the player arriving here has a
## sixth floor's build — and below anything that would make four of them the whole mask.
@export var terminal_health: float = 8.0

## The fraction of each hit that is refunded while any terminal stands. The King's number
## (`BossConfig.desync_heal_fraction`), for the same reason the count is: a player who solved this
## once on Floor 1 should find that the answer they learned there is still the answer.
@export_range(0.0, 1.0) var synchronised_refund: float = 0.75

## Conflict markers dropped from the ceiling in one volley, evenly spaced across the arena. Fewer
## than the projectile wall's, because these fall through a room that already has two bodies firing
## spreads in it.
@export var marker_count: int = 7

@export_group("Cascade Failure's mask")

## How far ahead of the robot the lead vent aims, in seconds of its current velocity. The Data
## Center's own number: the aimed patch charges for standing still, the lead patch charges for
## holding a heading, and the only input that answers both is a turn.
@export var lead_seconds: float = 0.55

## Patches in a vent wall, laid across the arena on one frame and filling together. One of them is
## left out — see `CoreIntelligence._fire_vent_wall` for where the door goes and why.
@export var vent_wall_count: int = 6

@export_group("The Orchestrator's mask")

## How long the floor takes to discharge once a migration is announced. The Orchestrator's own
## telegraph, and the number that decides whether denying a migration is possible: a robot crosses
## about three hundred pixels in this time, so the far side of a 416-pixel arena is a sprint that
## may not arrive and the middle of it is comfortably in reach.
@export var migrate_telegraph_seconds: float = 1.9

## How long the boss is damageable after it lands. Sealed the rest of the time, which is the whole
## of what this mask changes: the only fight in the campaign whose length is set partly by the
## player's reading of it.
@export var open_seconds: float = 2.2

## How long it is damageable when the migration is *denied* — when the robot is standing on the
## ground it wanted. Substantially longer than landing normally, because the denial is the thing
## the mask is asking for and a reward the player cannot feel is not a reward.
@export var denial_open_seconds: float = 3.6

@export_group("Driven throughput")

## A little longer than a room zone's occupancy ramp. The player has already learned the colour,
## but a boss-placed zone appears under pressure and deserves a complete readable rise.
@export var vent_seconds: float = 1.7

## Large enough to dislodge a firing position, small enough that three never erase the arena.
@export var vent_size_tiles := Vector2i(4, 3)

## The player's current position and two orthogonal follow-ups toward the room's open side. All are
## announced together and leave most of the 26x12-tile arena untouched.
@export var vent_count: int = 3
