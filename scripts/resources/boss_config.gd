class_name BossConfig
extends Resource
## Tuning for The Scrap King, spec section 16's Floor 1 boss.
##
## One resource for a fight with three phases, because the phases are the same machine at
## different settings — the same two projectile colours, the same arena, the same health
## pool. What changes between them is which attacks are in rotation and how fast they come,
## and both of those are here.

## Stable identifier, used by the save file to record that this boss has been beaten. Kept
## separate from `display_name` for the same reason `ItemConfig` does: the name on screen is
## allowed to change without invalidating everyone's save.
##
## That is not hypothetical any more — this boss was called the Merge Conflict and is now The Scrap
## King, and the id is the one part of it that did not change. Renaming it would have made every save
## that has beaten the boss report that it has not.
@export var id: StringName = &"merge_conflict"

## The name the player reads. CombatHUD.BOSS_NAME is the same name in the HUD's own casing, and
## tests/test_boss.gd asserts the two agree.
@export var display_name: String = "The Scrap King"

@export_group("Durability")

## One pool for the whole fight, including phase two's two bodies. Spec section 16 describes
## the boss *duplicating*, not doubling: two versions of one thing share what it has left.
@export var max_health: float = 60.0

## Health fraction at which the boss duplicates. Spec section 16: 70 percent.
@export_range(0.0, 1.0) var duplicate_at: float = 0.7

## Health fraction at which the two versions merge. Spec section 16: 35 percent.
@export_range(0.0, 1.0) var merge_at: float = 0.35

## Seconds the boss spends playing dead at the end of each phase, with an empty bar and nothing
## to shoot at. Two seconds because the music has to actually go quiet for the trick to land, and
## AudioManager.MUSIC_FADE_SECONDS is 1.2 — a shorter beat is a boss that stumbles rather than a
## boss that dies. Longer than about three and the player stops waiting and starts leaving.
@export var feigned_death_seconds: float = 2.0

## Fraction of damage refunded while the versions are still synchronised. This is spec
## section 16's "damage to one partially heals the other", and destroying a terminal is how
## the player turns it off.
##
## Raised from 0.6 to 0.75 by milestone 6's balance audit. At 0.6 the arithmetic said that
## breaking all four terminals saved two seconds out of thirteen — an eighteen percent return
## for crossing the arena four times under fire, which made the boss's central mechanic very
## nearly a trap. At 0.75 ignoring the terminals costs roughly twice as long, so the puzzle
## is worth solving. See tests/test_balance.gd, which now asserts that margin.
@export_range(0.0, 1.0) var desync_heal_fraction: float = 0.75

## Fraction of each hit that lands once the two versions have merged. Below one because the
## thresholds alone make phase three the shortest phase of the fight rather than its climax:
## phases two and three own the same 35 percent of the pool, but phase two also charges the
## player four terminals at six health each, so its real cost is 21 + 24 damage against phase
## three's 21. Scaling incoming damage is the one lever that closes that gap without moving
## spec section 16's 70 and 35 percent thresholds, which the fight's structure is written to.
##
## 0.47 puts the merged form at 45 damage — the same 45 phase two costs a player who breaks the
## terminals. The player is never shown the number, and the bar reports the phase rather than the
## pool (see MergeConflict.get_phase_health_ratio), so a phase that takes twice as long to empty
## simply reads as a phase with twice the health, which is what it is.
@export_range(0.01, 1.0) var merged_damage_scale: float = 0.47

@export_group("Terminals")

## Spec section 16: four destructible synchronization terminals.
@export var terminal_count: int = 4

@export var terminal_health: float = 6.0

@export_group("Attacks")

## The two incompatible versions, as projectiles. Everything the boss fires is one of these.
@export var red_shot: ProjectileConfig
@export var green_shot: ProjectileConfig

## Seconds between attacks, per phase. Phase three is fastest because it is the last one.
@export var phase_one_interval: float = 1.9
@export var phase_two_interval: float = 2.2
@export var phase_three_interval: float = 1.5

## Seconds of visible windup before an attack lands. The boss is readable or it is unfair.
@export var telegraph_seconds: float = 0.5

## Projectiles in a radial ring.
@export var ring_count: int = 12

## Projectiles in an aimed spread, and how wide it opens.
@export var spread_count: int = 5
@export var spread_degrees: float = 46.0

## Projectiles in a wall, and how many adjacent ones are missing to make the gap the player
## runs through. A wall with no gap is a wall the player cannot answer.
@export var wall_count: int = 13
@export var wall_gap: int = 3

@export_group("Charge")

@export var charge_speed: float = 240.0
@export var charge_seconds: float = 0.75
@export var charge_damage: float = 1.0
@export var charge_radius: float = 20.0

@export_group("Movement")

## Drift speed while not charging. The boss repositions slowly; it is an arena hazard, not
## a chaser.
@export var move_speed: float = 34.0
