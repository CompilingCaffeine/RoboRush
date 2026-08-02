class_name GameSettings
extends RefCounted
## The eight player-facing settings from spec section 21, as plain data.
##
## Exactly the eight the spec lists — screen shake, flash intensity, CRT filter, damage
## numbers, master volume, music volume, effects volume, fullscreen — and nothing else. A
## settings screen is a promise that every switch on it does something, so a switch is added
## here only once something reads it.
##
## Deliberately not a Resource. Settings are saved as JSON (spec section 24) rather than as a
## `.tres`, because the save file is versioned and hand-inspectable and a Resource is neither.
## `FeedbackConfig` stays a Resource because it is *authored* content with editor defaults;
## this is the player's overlay on top of it, and the two are kept apart so that reinstalling
## the game restores the designed defaults instead of whatever the last player chose.
##
## Every field survives a garbage save. `from_dict` reads each key independently and falls
## back to the default, so a truncated file, a hand-edited typo, or a field added in a later
## version costs the player one setting rather than all of them (spec section 24: "handle
## missing or outdated fields gracefully").

## Volume sliders are stored linear in 0..1 because that is what a slider is. Decibels are a
## rendering detail of the mixer and are converted at the point of use.
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0

## Intensity sliders share the range `FeedbackConfig` exports, so "1.0" means the same thing
## on the settings screen as it does in the editor.
const INTENSITY_MIN := 0.0
const INTENSITY_MAX := 2.0

## Below this a volume slider is treated as off and the bus is muted outright. A linear 1%
## is still audible on headphones, and a slider dragged to the bottom must mean silence.
const SILENCE_THRESHOLD := 0.001

var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.9

var fullscreen: bool = false

## Multiplies every screen shake in the game. 0.0 disables it, which is an accessibility
## floor rather than a taste preference — motion sensitivity is a real reason to need it.
var screen_shake: float = 1.0

## Multiplies hit flashes and the damage vignette. Same reasoning as above.
var flash_intensity: float = 1.0

## Spec section 21: "CRT effects should be subtle and optional." Off by default, because the
## first thing a new player sees should be the game rather than an effect over it.
var crt_enabled: bool = false

var damage_numbers: bool = true


## Converts a 0..1 slider to a bus volume in decibels, with the bottom of the slider being
## actual silence rather than a very quiet sound.
static func volume_to_db(linear: float) -> float:
	if linear <= SILENCE_THRESHOLD:
		return -80.0
	return linear_to_db(clampf(linear, VOLUME_MIN, VOLUME_MAX))


func to_dict() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"screen_shake": screen_shake,
		"flash_intensity": flash_intensity,
		"crt_enabled": crt_enabled,
		"damage_numbers": damage_numbers,
	}


## Reads what it recognises and ignores the rest. A key that is missing, null, or the wrong
## type leaves that one setting at its default.
static func from_dict(data: Dictionary) -> GameSettings:
	var settings := GameSettings.new()
	settings.master_volume = _read_float(data, "master_volume", settings.master_volume, VOLUME_MAX)
	settings.music_volume = _read_float(data, "music_volume", settings.music_volume, VOLUME_MAX)
	settings.sfx_volume = _read_float(data, "sfx_volume", settings.sfx_volume, VOLUME_MAX)
	settings.screen_shake = _read_float(data, "screen_shake", settings.screen_shake, INTENSITY_MAX)
	settings.flash_intensity = _read_float(
		data, "flash_intensity", settings.flash_intensity, INTENSITY_MAX
	)
	settings.fullscreen = _read_bool(data, "fullscreen", settings.fullscreen)
	settings.crt_enabled = _read_bool(data, "crt_enabled", settings.crt_enabled)
	settings.damage_numbers = _read_bool(data, "damage_numbers", settings.damage_numbers)
	return settings


## Clamped as well as type-checked. JSON is a text file a player can edit, and a screen shake
## of 400 should be a very shaky screen, not a way to break the game.
static func _read_float(data: Dictionary, key: String, fallback: float, maximum: float) -> float:
	var value: Variant = data.get(key)
	if not (value is float or value is int):
		return fallback
	return clampf(float(value), 0.0, maximum)


static func _read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key)
	return value if value is bool else fallback
