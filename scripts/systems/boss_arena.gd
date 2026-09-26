class_name BossArena
extends Node
## One floor's boss fight, from the player walking in to the prize being claimed.
##
## Floor-local, and parented inside the floor's session for that reason: it lives exactly as long as
## the floor it guards, and everything it has to undo when the floor ends early — the defeat handler
## on the EventBus, a boss summoned but not yet added — it undoes in `_exit_tree`, which the session
## leaving the tree triggers. Nothing outside has to remember to release it.
##
## What it does not decide is what happens to the *run*. When the fight is over it says so
## (`finished`) and `FloorController` chooses between winning and descending; when the boss falls it
## says so (`defeated`) and the floor opens the arena. That split is the one this class exists for:
## the controller owns the floor's lifecycle, and this owns one room's fight inside it.
##
## **Nothing is made safe when the boss dies, and that is deliberate.** No projectile is cleared, no
## compile lane is cancelled, and the player is granted no immunity. An attack that was fired or
## painted before the boss died goes on to resolve, and it can damage or kill the player while the
## reward is standing there — the fight is over when the arena is, not when the health bar empties.
## A player who empties the pool and walks into the prize through their own last volley has earned
## the death.
##
## The reason to say this out loud is that it looks exactly like a bug from the outside, and the
## obvious fix — sweep the hazards when `boss_defeated` fires — is one line and would be silently
## accepted by every test in this project that predates `tests/test_post_boss.gd`. That suite
## exists to make the removal fail loudly. What a dead boss must not do is start anything *new*;
## the bosses enforce that themselves by refusing to run their attack clock once dead.
## `FloorController._finish_floor` is where the other half lives: the hazards stay live, but if one
## of them kills the player first, the loss wins.

## Emitted once the boss is summoned, carrying what the HUD needs to name the fight. `is_final` says
## what the fight leaves behind rather than who is in it: the last floor's boss stands over a trophy
## and every other floor's over three items to choose between.
signal encountered(
	display_name: String, defeat_banner: String, phase_banners: Array[String], is_final: bool
)

## Emitted the moment the boss falls, before any prize goes up, with the arena's room id. The floor
## marks the arena cleared and opens its doors in answer.
signal defeated(room_id: int)

## Emitted when the fight is over for good: the prize was claimed, or there was none to claim. The
## floor decides what that means for the run.
signal finished()

const SHOP_ROOM_SCENE := preload("res://scenes/shop/shop_room.tscn")
const TROPHY_SCENE := preload("res://scenes/pickups/trophy.tscn")

## How far apart the boss's reward stands are. Wide enough for the stands' labels, which is the only
## thing that decides it: at the 56 pixels this used to be, three item names written above three
## stands 56 pixels apart overlapped into something unreadable, and the reward the fight is for was
## the one choice in the run the player could not read. `ShopStand.LABEL_WIDTH` plus a gutter, and
## tests/test_shop.gd holds the two together.
const REWARD_SPACING := 128.0

var _room: Room
var _encounter: BossEncounter
var _shop_config: ShopConfig
var _is_final := false
var _floor_number := 0

## Draws the three items for the stands and spends them from the run. The floor's, because the draw
## reads the floor's reward stream and writes the run's ledger — see
## `FloorController._draw_boss_reward`.
var _draw_reward := Callable()

## The boss, once the player has walked into its arena. Null until then — a boss that existed from
## the moment the floor was built would be a boss firing at an empty room.
var _boss: Boss

## The boss's choice of three, while it stands unclaimed. Null before the boss dies and again once
## the choice is taken, which is exactly the window a checkpoint has to be able to describe — see
## `pending_reward_ids`.
var _reward: ShopRoom

## The campaign's trophy, while it stands unclaimed in the last floor's arena, and null on every
## floor before it. The counterpart of `_reward`, and held for the same reason: it is what a
## checkpoint taken in that window has to be able to describe — see `restore_prize`.
var _trophy: Trophy


## `room` is the arena itself, `encounter` the boss drawn for this floor (null when the floor could
## not be given one), and `is_final` whether this is the floor the campaign ends on.
func setup(
	room: Room,
	encounter: BossEncounter,
	shop_config: ShopConfig,
	is_final: bool,
	draw_reward: Callable,
	floor_number: int,
) -> void:
	_room = room
	_encounter = encounter
	_shop_config = shop_config
	_is_final = is_final
	_draw_reward = draw_reward
	_floor_number = floor_number


func get_room() -> Room:
	return _room


## The boss, once summoned; null before the player walks in, and after the floor ends.
func get_boss() -> Boss:
	return _boss


## The trophy standing in the last arena, or null.
func get_trophy() -> Trophy:
	return _trophy


## Wakes the boss when the player walks in. The arena it is handed is the room's interior, so the
## boss lays out its terminals and clamps its own movement without ever asking what room it is in.
##
## Once per floor: a boss already summoned is not summoned again. Whether the arena still needs a
## fight at all — it does not, once cleared — is the room loop's question, and it asks it first.
func summon() -> void:
	if _boss != null:
		return
	if _encounter == null or not _encounter.is_valid():
		push_error("FloorController: floor %d has no usable boss." % _floor_number)
		return
	_boss = _encounter.scene.instantiate()
	encountered.emit(
		_encounter.display_name, _encounter.defeat_banner, _encounter.phase_banners, _is_final
	)
	# One-shot: a boss is defeated exactly once per floor. A floor abandoned with its boss alive — a
	# restart, a death, a campaign edit — is taken back down in `_exit_tree`.
	EventBus.boss_defeated.connect(_on_boss_defeated, CONNECT_ONE_SHOT)
	# Deferred, for the fourth time in this project and the same reason every time: rooms are
	# entered through an Area2D trigger, and registering the boss's collision bodies while the
	# physics server is flushing queries is refused outright.
	_add_boss.call_deferred()


## A boss walked into on the same frame a floor is released would otherwise be added to a room from
## the floor being left — and the boss is the one deferred spawn whose arrival is loud, since it
## brings a health bar and an arena with it. The instance is freed rather than dropped: it was
## created in `summon` and, unparented, nothing else would ever free it.
func _add_boss() -> void:
	if not is_instance_valid(_boss):
		return
	var session := FloorSession.owning(self)
	if (
		not is_inside_tree()
		or session == null
		or not session.is_open()
		or not is_instance_valid(_room)
		or not _room.is_inside_tree()
	):
		_boss.queue_free()
		_boss = null
		return
	# Before the boss, so the ground is already drawn on the frame the fight starts rather than
	# appearing under a player who has begun moving. See `BossEncounter.arena_thermal_zones` for why
	# a hazard can belong to the fight rather than to the room, and `Room.add_thermal_zones` for what
	# happens when the arena had already authored the same ground itself.
	_room.add_thermal_zones(_encounter.arena_thermal_zones)
	_room.add_child(_boss)
	_boss.begin(_room.get_interior_rect())


func _on_boss_defeated(_boss_node: Node) -> void:
	resolve_defeat()


## Spec section 16's reward: three rare items on stands, and taking one closes the others. Winning
## the run waits on that choice rather than on the killing blow, so the player is never shown a
## victory screen with an unclaimed prize behind it. See the class notes for why nothing is made
## safe here.
func resolve_defeat() -> void:
	defeated.emit(_room.plan.id)

	# The last floor pays out in a trophy instead, and takes nothing out of the item pool to do it. A
	# choice of three is a decision about the rest of the run, and on this floor there is no rest of
	# the run: whichever stand the player read, weighed and pressed E on, the next thing that happened
	# was the victory screen. See `Trophy`.
	if _is_final:
		_place_trophy()
		return

	var items: Array[ItemConfig] = _draw_reward.call()
	if items.is_empty():
		# Nothing left in the pool to offer. Winning must not depend on there being a prize: an empty
		# choice creates zero stands, `choice_taken` never fires, and the run would sit in a cleared
		# arena with a dead boss and no victory — which is exactly how this was reported. The boss is
		# dead and the floor is done, so the fight is finished.
		#
		# What finishing then does is deferred by the floor, for the sixth time in this project and the
		# same reason every time: this runs inside the boss's damage callback, and winning pauses the
		# tree. Pausing the scene tree while the physics server is flushing leaked nineteen objects and
		# four audio streams — measured, by taking this path with a deliberately emptied pool.
		push_warning("FloorController: no items left for the boss reward; winning without one.")
		finished.emit()
		return

	_place_reward(items)


## Takes the boss's choice: the floor is finishing, and there is no offer left to record.
func claim_reward(_item: ItemConfig) -> void:
	_reward = null
	finished.emit()


## Stands the boss's prize back up in a resumed floor's arena, if the run was saved with one
## unclaimed. Nothing to do for every other checkpoint, which is nearly all of them: that window is
## the seconds between the killing blow and the claim.
##
## Two prizes, decided by which floor this is. Every floor but the last puts back the three items
## the checkpoint names, resolved against `pool` rather than drawn — they were struck off the run's
## pool when they were first offered, and the run is still carrying that. The last puts back the
## trophy, which needs no names.
##
## Only into an arena the checkpoint says is cleared (`arena_cleared`). An offer standing over a
## *live* boss is not a state this game can produce, so a file describing one has been edited, and
## the honest answer to a state that cannot happen is to build the floor as though it did not say so
## — the player then fights the boss and is offered a reward by the ordinary path.
func restore_prize(ids: Array[StringName], pool: Array[ItemConfig], arena_cleared: bool) -> void:
	# The last floor's prize is not in the checkpoint, because there is nothing about it to record:
	# every trophy is the same object, and a cleared arena on the final floor can only mean one is
	# standing in it — the one thing that takes it also ends the run, and ending a run clears the
	# checkpoint. So the arena being cleared *is* the saved state, and it is enough to put it back.
	#
	# Without this the finale had the failure the item stands were given `floor_boss_reward_ids` to
	# fix, in its worst form: a run saved between the last killing blow and the trophy came back to
	# an empty arena on the last floor of the campaign, with the boss gone and no way left to win.
	if _is_final:
		if arena_cleared:
			_place_trophy()
		return

	if ids.is_empty():
		return

	if not arena_cleared:
		push_warning(
			"FloorController: the saved run left a boss reward on floor %d, whose arena is not "
			% _floor_number
			+ "recorded as cleared; the offer has been dropped."
		)
		return

	var catalogue: Dictionary[StringName, ItemConfig] = {}
	for item: ItemConfig in pool:
		if item != null:
			catalogue[item.id] = item

	var items: Array[ItemConfig] = []
	for id: StringName in ids:
		var item: ItemConfig = catalogue.get(id)
		if item != null:
			items.append(item)
	_place_reward(items)


## What the boss's offer is holding, for a checkpoint taken while it is standing unclaimed. Empty
## whenever there is nothing to put back: before the boss dies, and after the choice is taken.
##
## This is the second half of what `ShopStock` does for the floor's shop, and it exists for a
## sharper reason than a leak. The boss room is marked cleared the instant the boss falls, so a
## resumed floor rebuilds it with no boss in it — and the stands died with the session that owned
## them. Nothing else can descend a floor: the floor finishes from a claimed prize and from nothing
## else. A run saved in the seconds between the killing blow and taking the prize therefore came
## back to a cleared arena with nothing in it and no way off the floor, for the rest of the run.
##
## Always empty on the last floor, where the prize is a trophy rather than a choice and there is
## nothing about it to write down — `restore_prize` says what puts that one back.
func pending_reward_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _reward == null or not is_instance_valid(_reward):
		return ids
	for stand: ShopStand in _reward.get_stands():
		if not stand.is_sold and stand.item != null:
			ids.append(stand.item.id)
	return ids


## Stands the offer up in the arena. Split from the draw because a resumed floor has to put back a
## choice that was already drawn: the items are spent out of the run's pool the moment they are
## offered, so drawing a second set would both cost the run three more items and hand the player a
## different prize than the one they walked away from.
func _place_reward(items: Array[ItemConfig]) -> void:
	if items.is_empty():
		return
	var reward: ShopRoom = SHOP_ROOM_SCENE.instantiate()
	_room.add_child(reward)
	reward.choice_taken.connect(claim_reward)
	reward.stock_choice(_shop_config, items, _reward_positions())
	_reward = reward


## Stands the campaign's prize in the last arena. Reached twice: when the final boss falls, and when
## a run saved in the window between that and picking it up is resumed.
##
## Nothing is spent, nothing is drawn, and nothing is recorded against the run. That is the point of
## it: the trophy is the same object for every player and every seed, so unlike the three stands it
## replaces there is no state a checkpoint has to carry to put it back.
func _place_trophy() -> void:
	var trophy: Trophy = TROPHY_SCENE.instantiate()
	trophy.position = _room.to_local(_room.get_reward_position())
	trophy.claimed.connect(_on_trophy_claimed)
	_room.add_child(trophy)
	_trophy = trophy


## Picking it up is what wins the campaign, and it goes through the floor rather than calling
## `GameManager.win_run` itself. That is deliberate: the last floor must lose the same races every
## other floor loses. A compile lane that was already painted when the boss fell can kill the player
## on their walk to the trophy, and `FloorController._finish_floor` is the one place that knows a
## run which has already ended does not then win.
func _on_trophy_claimed() -> void:
	_trophy = null
	finished.emit()


func _reward_positions() -> Array[Vector2]:
	var centre := _room.get_reward_position()
	var positions: Array[Vector2] = []
	for index: int in BossRewardDraw.COUNT:
		var offset := (float(index) - float(BossRewardDraw.COUNT - 1) * 0.5) * REWARD_SPACING
		positions.append(centre + Vector2(offset, 0.0))
	return positions


## Leaving the tree is the floor ending: the session this lives in is taken out before it is freed.
## A boss that is still alive leaves the defeat handler connected, and one summoned in the frame
## the floor ended is owned by nothing until it is added — so both are taken down here.
##
## Here rather than left to freeing, which would get to both only at the end of the frame: a descent
## builds the next floor in the same call that ends this one, and the old floor's fight has always
## been gone before the new one starts. `tests/test_floor.gd` checks it in that same frame.
func _exit_tree() -> void:
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.disconnect(_on_boss_defeated)
	if is_instance_valid(_boss) and _boss.get_parent() == null:
		_boss.queue_free()
	_boss = null
	_reward = null
	_trophy = null
