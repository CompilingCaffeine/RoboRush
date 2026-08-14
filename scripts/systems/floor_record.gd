class_name FloorRecord
extends RefCounted
## What one floor of a run cost and how it ended.
##
## A run's statistics were a single set of totals: rooms cleared, damage taken, duration. That was
## the right shape for one ten-room floor and stops being it for six. "The run took eleven minutes"
## does not say whether floor 5 took four of them, and "the run ended in failure" does not say which
## floor ended it — which are the two questions a six-floor campaign's pacing is tuned against, and
## the two a bug report needs to be reproducible at all.
##
## One record per floor *entered*, including the one being played. The open record is the run's
## current floor, and it is closed by whatever ends the floor: descending, winning, dying, or
## walking out to the menu. A run therefore reads as a list of floors with an outcome each, and the
## last record is where it stopped.
##
## The numbers are deltas against the run's cumulative counters, computed at close rather than
## counted here. This node listens to nothing: `RunManager` already translates the EventBus into
## totals, and a second listener incrementing its own copy would be a second thing to keep in step
## with the first — the failure mode being two numbers that disagree and no way to tell which is
## wrong.

## How a floor ended. `IN_PROGRESS` is the floor being played; every other value is terminal for
## that floor, and only `DESCENDED` is followed by another record.
enum Outcome {
	## Still being played. The last record of a live run.
	IN_PROGRESS,
	## The boss died, the reward was claimed, and the run went down to the next floor.
	DESCENDED,
	## The last floor's reward was claimed. Only the campaign's final floor can hold this.
	WON,
	## The player was destroyed here.
	LOST,
	## The player left for the title screen from here.
	ABANDONED,
}

var floor_number: int = 0
var floor_id: StringName = &""

## The seed this floor was generated from — derived, so it is reproducible from the run seed and
## this floor's id alone (see `RunRng.floor_seed`). Recorded per floor anyway, because a bug report
## about floor 4 should not require the reader to re-derive it correctly.
var seed_value: int = 0

## Which boss guarded it, filled in when the floor draws one. Empty for a floor whose boss was
## never drawn — a test arena, or a campaign whose content could not supply one.
var boss_id: StringName = &""

var outcome: Outcome = Outcome.IN_PROGRESS

## Seconds of play spent on this floor, and rooms cleared on it. Both zero while the floor is open:
## they are the difference between the run's totals at close and at open, so they only exist once
## there is a close.
var duration: float = 0.0
var rooms_cleared: int = 0

## The run's cumulative counters at the moment this floor was entered. Private because they are
## bookkeeping for the two fields above rather than anything a reader of a finished run wants.
var _duration_at_open: float = 0.0
var _rooms_cleared_at_open: int = 0


## Opens a record for a floor being entered. `elapsed` and `rooms` are the run's totals *now*, which
## is what makes this floor's own numbers derivable later.
static func opened(
	number: int, id: StringName, floor_seed: int, elapsed: float, rooms: int
) -> FloorRecord:
	var record := FloorRecord.new()
	record.floor_number = number
	record.floor_id = id
	record.seed_value = floor_seed
	record._duration_at_open = elapsed
	record._rooms_cleared_at_open = rooms
	return record


func is_open() -> bool:
	return outcome == Outcome.IN_PROGRESS


## Closes the record with how the floor ended. Ignored if it is already closed, because the events
## that end a floor are not exclusive: a lingering hazard can kill the player in the same frame the
## boss reward is claimed (see `FloorController._finish_floor`), and the first outcome to arrive is
## the one that happened.
func close(final_outcome: Outcome, elapsed: float, rooms: int) -> void:
	if not is_open():
		return
	outcome = final_outcome
	duration = maxf(elapsed - _duration_at_open, 0.0)
	rooms_cleared = maxi(rooms - _rooms_cleared_at_open, 0)


## What a checkpoint has to carry for this record to keep working after a restore.
##
## The two private counters go in as well as the public numbers, which is the part that is easy to
## leave out: a record restored while still open is closed later by subtracting them from the run's
## totals, so a record that came back without them would report the *whole run's* duration as having
## been spent on the floor it was resumed onto.
func to_dict() -> Dictionary:
	return {
		"floor_number": floor_number,
		"floor_id": String(floor_id),
		"seed": seed_value,
		"boss_id": String(boss_id),
		"outcome": int(outcome),
		"duration": duration,
		"rooms_cleared": rooms_cleared,
		"duration_at_open": _duration_at_open,
		"rooms_at_open": _rooms_cleared_at_open,
	}


## Rebuilds a record from `to_dict`. Anything malformed comes back as the field's default rather
## than as a failure: a checkpoint is refused by `RunCheckpoint.validate`, which reads the values
## this produces, so the reader's job is to produce values rather than to judge them.
static func from_dict(data: Dictionary) -> FloorRecord:
	var record := FloorRecord.new()
	record.floor_number = RunStats.read_int(data, "floor_number")
	record.floor_id = RunStats.read_name(data, "floor_id")
	record.seed_value = RunStats.read_int(data, "seed")
	record.boss_id = RunStats.read_name(data, "boss_id")
	record.duration = RunStats.read_float(data, "duration")
	record.rooms_cleared = RunStats.read_int(data, "rooms_cleared")
	record._duration_at_open = RunStats.read_float(data, "duration_at_open")
	record._rooms_cleared_at_open = RunStats.read_int(data, "rooms_at_open")

	# Clamped rather than trusted: an out-of-range enum read straight into `outcome` would index
	# `Outcome.keys()` out of bounds the first time anything described the run.
	var raw_outcome := RunStats.read_int(data, "outcome")
	record.outcome = (
		raw_outcome as Outcome if raw_outcome >= 0 and raw_outcome < Outcome.size()
		else Outcome.IN_PROGRESS
	)
	return record


## One line, for a log or a test failure message. Compact on purpose: six of these is the whole
## shape of a run, and it should fit in a terminal without wrapping.
func describe() -> String:
	return "floor %d '%s' seed %d boss '%s' %s %s %d rooms" % [
		floor_number,
		floor_id,
		seed_value,
		boss_id,
		Outcome.keys()[outcome].to_lower(),
		RunStats.format_duration(duration),
		rooms_cleared,
	]
