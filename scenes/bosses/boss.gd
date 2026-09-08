class_name Boss
extends Node2D
## What every floor's boss controller has in common: the one call `FloorController` makes once
## the player is sealed in the boss room, and the handful of members all five bosses turned out
## to need in order to answer it.
##
## It was thinner than this, deliberately, and the note here used to say so: with one boss in the
## game there was nothing to share, and `FloorController` only ever needed to hold `_boss` as one
## type. Five bosses later, four of them had independently grown the same pool, the same cached
## player lookup, and the same two accessors over them — `get_health_ratio` was byte-identical in
## all four — which is the arrangement `Enemy`'s own docstring warns about: four copies of a
## lifecycle is four places for it to drift apart, invisibly. It had already started. Three
## copies of `_find_player` cached the result and `Orchestrator`'s did not, so the one boss that
## asks for the player every physics frame was the one paying a scene-tree walk for it.
##
## What is *not* here is anything about how a boss fights. Phases, attacks, parts, arenas and
## tuning stay in each boss's own script and its own config resource, which is why `config` is
## not pulled up: the four configs are unrelated resources that happen to share `max_health`, and
## `get_max_health` exists so this file can read that one number without claiming to know the
## shape of the rest.

## The boss's remaining pool. Written by each fight's own damage handling — how a boss takes
## damage is the fight's business, not this file's — and read back through `get_health` and
## `get_health_ratio` so nothing outside has to know the field exists.
var _health := 0.0

var _is_dead := false

## The player, cached once found. Re-resolved if it is freed, so a restart does not leave a boss
## tracking a corpse. Same contract as `Enemy._player` and for the same reason.
var _player: Node2D


## Called once, when the player enters the boss room. `arena` is the room's interior rect.
func begin(_arena: Rect2) -> void:
	push_error("%s: begin() not implemented" % get_script().get_global_name())


## The pool this boss started with. Overridden by each fight to return its own config's
## `max_health`, because the four boss configs are separate resources rather than one hierarchy —
## see the note at the top of this file.
func get_max_health() -> float:
	push_error("%s: get_max_health() not implemented" % get_script().get_global_name())
	return 0.0


func get_health() -> float:
	return _health


## The real pool as a fraction, floored so a config with no health set cannot divide by zero.
##
## Honest for every boss that uses it directly: it falls once, monotonically, and reaching zero
## means the fight is over. `MergeConflict` is the exception and says so in its own
## `get_phase_health_ratio` — its bar deliberately lies, and it overrides what it announces
## rather than what this returns.
func get_health_ratio() -> float:
	return _health / maxf(get_max_health(), 0.001)


## Tells the HUD where the pool now stands. Virtual because what a boss *announces* and what it
## *has* are not always the same number — see `MergeConflict`.
func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
