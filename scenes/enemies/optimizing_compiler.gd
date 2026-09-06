class_name OptimizingCompiler
extends Compiler
## A Compiler that does not stop at one pass. It paints its lane, and the moment that lane strikes
## it paints the **perpendicular** one through wherever the player is now, on a shorter telegraph.
##
## The floors that ship this have already taught the Compiler, and the habit the Compiler teaches is
## incomplete: leave the stripe. A player who has learned that leaves it in whichever direction is
## nearest and *stops*, because the room has just become safe again — the whole shape of the enemy
## is a burst followed by nothing. This one charges for the stop. The second pass lands on the
## column the player stepped into, so the answer is no longer "leave the lane" but "leave the lane
## and keep going", and the direction that answers both is along the lane that has already struck.
##
## **Only one lane is ever live.** The second pass is painted as the first one strikes, so this is
## never a pattern to solve — it is one lane, answered, and then one more lane in the direction the
## answer went. That is what keeps a doubled Compiler fair while making it twice the enemy: the
## player is asked the same question twice in a row rather than two questions at once.
##
## Perpendicular is what guarantees the second answer exists. The step out of a row is along a
## column, which is the line the pass that has just struck left clear behind it — so the way out of
## the second lane is always the direction the first one came from. Two *parallel* lanes cannot
## promise that, which is why `RuntimeError` holds its staggered pair `MIN_LANE_SLOT_SEPARATION`
## slots apart by hand.
##
## It is one enemy with one extra idea rather than a second enemy: the clock, the room lookup, the
## draw, the colours and the damage are the Compiler's, inherited unchanged. What is added is a
## second lane and the seconds it waits before painting it.

## Where the second pass will go, and how long until it is painted. `_pending_is_row` is the
## orientation of the *second* lane, so it is already the opposite of the one that was painted.
var _pending_left := 0.0
var _pending_is_row := false


func _act(delta: float) -> Vector2:
	_step_second_pass(delta)
	return super(delta)


## The second lane is aimed when it is *painted*, not when the first one was. That is the whole
## mechanic: it wants the player's answer to the first lane, so it has to ask after they have given
## it. Aiming both at once would produce a cross the player could step out of before either lane
## lit, which is a pattern with one answer instead of two.
func _step_second_pass(delta: float) -> void:
	if _pending_left <= 0.0:
		return
	_pending_left -= delta
	if _pending_left > 0.0:
		return
	_pending_left = 0.0

	var room := find_room()
	if room == null:
		return
	spawn_lane(room, _pending_is_row, _player_slot(room, _pending_is_row),
		_tuning.second_pass_telegraph_seconds)


## Scheduled to arrive as the first lane strikes: the delay is that lane's own telegraph, plus
## whatever `second_pass_delay` adds on top of it. Read off the tuning rather than hardcoded, so a
## Compiler tuned to warn for longer is answered by a second pass that still waits for it.
func _on_lane_painted(_room: Room, is_row: bool, _slot: int) -> void:
	_pending_is_row = not is_row
	_pending_left = maxf(
		_tuning.lane_telegraph_seconds + maxf(_tuning.second_pass_delay, 0.0), 0.001
	)


## The slot the player is standing in, in the given orientation, clamped into the room. Falls back
## to the middle of the room with nobody to aim at, which is what every other aimed hazard in the
## game does with no player: it still happens, and it happens somewhere legal.
func _player_slot(room: Room, is_row: bool) -> int:
	var slots := Room.INTERIOR_TILES.y if is_row else Room.INTERIOR_TILES.x
	if _player == null:
		return slots / 2
	var interior := room.get_interior_rect()
	var offset := (
		_player.global_position.y - interior.position.y
		if is_row
		else _player.global_position.x - interior.position.x
	)
	return clampi(int(offset / float(Room.TILE_SIZE)), 0, slots - 1)
