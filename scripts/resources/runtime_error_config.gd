class_name RuntimeErrorConfig
extends Resource
## Tuning for Runtime Error, README's Floor 2 boss.
##
## Its own resource, following the rule `SimpleBossConfig` wrote down rather than breaking it:
## a boss's config is shaped for that boss's gimmick. `BossConfig` is shaped for The Scrap
## King's terminals, damage refunds, and feigned deaths, none of which exist in this fight —
## and what this fight needs that no existing config carries is *lane geometry*: how thick a
## compile lane is, how far apart two of them are staggered, and how the checkerboard divides
## the arena.
##
## The lane timings deliberately mirror `CompilerConfig`'s, because README requires the boss to
## speak the Compiler's warning language: "The boss must use the same amber-then-red warning
## language as the Compiler." They are separate fields rather than a shared resource so the
## boss can tighten its own windows as the fight escalates without making every Compiler on the
## floor harder at the same time.

## Stable identifier the save file records as "beaten". Unchanged from the greybox this
## replaces: it is the same boss, finished, and every save that recorded a placeholder defeat
## should keep it. See `BossConfig.id` for the general rule.
@export var id: StringName = &"runtime_error"

## The name the player reads. `FloorConfig.boss_display_name` is the same name in the HUD's own
## casing, and tests/test_runtime_error.gd asserts the two agree — the same guard test_boss.gd
## puts on the Scrap King, for the same reason: two copies of a name is the arrangement that
## ends with a boss bar labelled with the name the boss used to have.
@export var display_name: String = "Runtime Error"

@export_group("Durability")

## One pool for the whole fight. There is no refund and no damage scaling anywhere in it —
## README: "Runtime Error is a pattern fight, not a second terminal puzzle. It remains
## damageable through all three phases." What the player is asked for here is reading the
## arena, not working out why their shots are not counting.
##
## 150 against the starting weapon's 4 damage per second is 37.5 seconds of perfect fire,
## which is the same order as The Scrap King's ~31s measured the same way (tests/test_balance.gd
## does that arithmetic for both). The player reaching this boss has had a whole extra floor of
## items, so the fight they actually get is shorter than that — matching the first boss on
## *starting* damage is what keeps the second one from being over in ten seconds.
@export var max_health: float = 150.0

## Health fractions the phases change at. Thirds rather than the Scrap King's 70/35, because
## its thresholds are weighted for phases that cost wildly different amounts (four terminals in
## one, a damage reduction in another) and these three phases cost exactly what their share of
## the pool says they do.
@export_range(0.0, 1.0) var phase_two_at: float = 0.66
@export_range(0.0, 1.0) var phase_three_at: float = 0.33

@export_group("Attacks")

## Everything the boss fires. One projectile rather than the Scrap King's two, because this
## fight's colour language is already spoken for: amber warns, red executes (README's
## Development palette), and a second projectile colour would be a third meaning competing with
## those two.
@export var shot: ProjectileConfig

## Seconds between attacks, per phase.
@export var phase_one_interval: float = 2.0
@export var phase_two_interval: float = 1.8
@export var phase_three_interval: float = 1.6

## Seconds of visible windup before a *projectile* attack lands. The lane attacks do not use
## this — a compile lane is already a telegraph, and putting a body windup in front of one
## would telegraph the telegraph. See `RuntimeError._needs_windup`.
@export var telegraph_seconds: float = 0.5

## Projectiles in an aimed spread, and how wide it opens.
@export var spread_count: int = 5
@export var spread_degrees: float = 50.0

## Projectiles in a ring, and how many adjacent ones are left out to make the gap. README asks
## for "projectile rings that have visible gaps"; a ring with no gap is a ring with no answer.
@export var ring_count: int = 14
@export var ring_gap: int = 3

## Projectiles in a wall, and the size of its traversable opening. Spaced closer together than
## the player is wide, so the opening is the only way through — see `RuntimeError._fire_wall`.
@export var wall_count: int = 13
@export var wall_gap: int = 3

@export_group("Compile lanes")

## How long a lane telegraphs (amber, growing) before it strikes. Tighter than the Compiler's
## 1.1s because the player meets this boss having already learned to read lanes, but still far
## above what the answer costs: at the player's 160 pixels per second this is 144 pixels of
## travel, against the ~37 pixels it takes to step out of the thickest pattern in the fight.
@export var lane_telegraph_seconds: float = 0.9

## How long the strike stays lit after it lands. Damage is checked once, at the moment the
## strike opens; this is purely how long the player sees it. Matches `CompilerConfig`.
@export var lane_strike_seconds: float = 0.25

@export var lane_damage: float = 1.0

## Lane thickness, in tiles. Two where the Compiler uses one: the same language spoken by
## something bigger. Also what divides the arena into whole lane slots — the 26x12-tile
## interior gives exactly 13 column slots and 6 row slots at this thickness, so no strip of
## floor is permanently safe because it fell off the end of the division.
@export var lane_thickness_tiles: int = 2

## Seconds between phase two's first lane being painted and its second. The whole of what
## "staggered" means: at anything above zero the two lanes strike on different frames, so the
## answer is always "leave the first, then leave the second" rather than one position that has
## to survive both at once.
@export var lane_stagger_seconds: float = 0.55

## How phase three divides the arena into checkerboard cells. Twelve cells over the 416x192
## interior is 104x64 each — comfortably larger than the player, and small enough that the
## nearest safe cell is always a short step away.
@export var checker_cols: int = 4
@export var checker_rows: int = 3

@export_group("Movement")

## Drift speed. Slow, for the same reason The Scrap King's is: it is the arena that threatens
## the player in this fight, and a boss that chased them would be competing with its own lanes
## for their attention.
@export var move_speed: float = 30.0
