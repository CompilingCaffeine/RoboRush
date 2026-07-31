class_name FeedbackConfig
extends Resource
## How loud the game's feedback is, as data.
##
## Spec section 21 lists screen shake, flash intensity, and damage numbers as
## player-facing settings; section 7 requires a damage number toggle. This resource
## is the single place those live, so the milestone 6 settings menu edits this and
## nothing else, and so accessibility-relevant intensity is never hardcoded into an
## effect.

@export_group("Camera")

## Multiplies all screen shake. 0.0 disables it entirely.
@export_range(0.0, 2.0) var screen_shake_scale: float = 1.0

@export_group("Flashes")

## Multiplies hit-flash and invulnerability-flash strength. 0.0 disables.
@export_range(0.0, 2.0) var flash_intensity: float = 1.0

@export_group("Readouts")

@export var damage_numbers_enabled: bool = true

@export_group("Hit pause")

## Spec section 7: "Brief hit pause for major impacts". Applied on kills and on
## player damage, never on ordinary hits — at 4 shots per second an every-hit pause
## would read as stutter, not impact.
@export var hit_pause_enabled: bool = true

## Real-time duration of the pause, independent of time scale.
@export var hit_pause_seconds: float = 0.06

## Time scale held during the pause. Not zero, so effects still creep forward.
@export_range(0.0, 1.0) var hit_pause_time_scale: float = 0.06
