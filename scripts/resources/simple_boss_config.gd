class_name SimpleBossConfig
extends Resource
## Tuning for a single-phase greybox boss — one body, one attack, no terminals, no feint.
##
## Deliberately not `BossConfig`: that resource is shaped specifically for Merge Conflict's
## split/merge phases (duplicate/merge thresholds, terminal fields, charge fields, wall
## fields), none of which a placeholder needs. A finished multi-phase Floor 2 boss should
## get its own config shaped for its own gimmick, the same way Merge Conflict got its own
## rather than reusing a generic one.

## Stable identifier the save file records as "beaten" — see `BossConfig.id`'s own doc
## comment for why this is kept separate from `display_name` rather than derived from it.
@export var id: StringName = &"unnamed_boss"

@export var display_name: String = "Unnamed Boss"

@export var max_health: float = 30.0

## Drift speed while repositioning. Same role as `BossConfig.move_speed`.
@export var move_speed: float = 26.0

## Seconds between attacks.
@export var attack_interval: float = 1.8

## Seconds of visible windup before an attack lands.
@export var telegraph_seconds: float = 0.5

## What the boss fires — an aimed spread, spec-equivalent to `MergeConflict._fire_spread`.
@export var shot: ProjectileConfig
@export var spread_count: int = 5
@export var spread_degrees: float = 50.0
