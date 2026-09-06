class_name Trophy
extends Area2D
## The prize the last boss in the campaign stands over, and the only thing on any floor that
## ends the run by being touched.
##
## Every other floor pays its boss out in hardware: three stands, one choice, and a decision the
## player makes about the run they are still in. The last floor has no run left to decide about,
## so a choice there is a menu between three things that will never be used — which is what it
## was, and it read as one. What the finale hands over instead is a single object with no effect,
## no price, and no stand: the player walks into it and the campaign is over.
##
## It is a `Pickup` in every respect except the one that matters, which is why it is not one.
## `Pickup` exists to apply a `PickupConfig` to whoever walks into it, and can decline — a repair
## cell on a robot at full integrity stays on the floor. A trophy applies nothing and declines
## nothing, and giving `PickupConfig` a kind that means "does nothing, wins the run" would put the
## end of the campaign inside the resource that describes scrap.
##
## The post-boss danger contract is untouched here, deliberately: see
## `FloorController._on_boss_defeated`. Nothing is cleared and the player is granted no immunity,
## so a shot the boss committed before it fell can still kill them on the walk over — and if it
## does, the loss wins and the trophy is not claimed. The last floor's prize is exactly as
## unclaimable as the five before it.

## Emitted when the player has picked it up. Local rather than on the EventBus because the floor
## is the only thing that acts on it, and it acts by finishing the run — `EventBus.trophy_claimed`
## is what everything *else* hears, and it says the run was won rather than what to do about it.
signal claimed()

const BOB_HEIGHT := 2.0
const BOB_HZ := 1.4

## How far the sprite brightens and dims, and how fast. Slower than the bob so the two never lock
## into one motion, and a brighten rather than a blink: something flashing in a room the player
## has just won reads as a warning.
const SHINE := 0.35
const SHINE_HZ := 0.5

## Seconds before it can be collected. Longer than a pickup's, and for a different reason: a
## pickup is armed against the player standing on the spawn point when it drops, and this is armed
## against a player who was mid-dash through the boss's last position when the boss fell. A run
## should not end inside the same tenth of a second the fight did.
const ARM_DELAY := 0.4

@onready var _sprite: Sprite2D = $Sprite

var _elapsed := 0.0
var _base_y := 0.0

## Set once `ARM_DELAY` has passed. Kept as a flag rather than re-read off `_elapsed` because the
## moment it flips is a moment something happens — see `_process`.
var _armed := false

## Set the moment it is taken. `queue_free` does not take effect until the end of the frame, and
## two bodies can enter in the same one — without this the campaign would be won twice, which is
## two victory sounds, two records, and a second `_finish_floor` on a floor that is already
## finishing.
var _taken := false


func _ready() -> void:
	# On the pickup layer, and deliberately *not* in `Pickup.GROUP`. That group is what Scrap Magnet
	# sweeps, and a trophy dragged across the arena into a player who never walked to it would take
	# the last deliberate act of the campaign away from an item bought three floors earlier.
	collision_layer = Teams.LAYER_PICKUP
	collision_mask = Teams.LAYER_PLAYER
	_base_y = _sprite.position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_elapsed += delta
	_sprite.position.y = _base_y + sin(_elapsed * TAU * BOB_HZ) * BOB_HEIGHT
	# The shine and the sparks are the whole of what says "this is not another repair cell".
	var shine := 1.0 + (sin(_elapsed * TAU * SHINE_HZ) * 0.5 + 0.5) * SHINE
	_sprite.modulate = Color(shine, shine, shine)

	if not _armed and _elapsed >= ARM_DELAY:
		_armed = true
		# The overlap is asked for once, here, rather than only being waited for. `body_entered`
		# fires when a body *arrives*, and a player who was already standing on the reward point
		# when the boss fell never arrives — they were refused by the arming delay on the one
		# overlap they were ever going to get, and the campaign became unfinishable without
		# stepping off the trophy and walking back onto it.
		#
		# Which is exactly where a player is likely to be standing: the reward point is the middle
		# of the arena they have just been fighting in.
		for body: Node2D in get_overlapping_bodies():
			if body is Player:
				claim()
				return


func _on_body_entered(body: Node2D) -> void:
	if _taken or not _armed:
		return
	if not (body is Player):
		return
	claim()


## Hands it over: the run is won, the save is told, and the object is gone. Split from the overlap
## above so that "what claiming does" and "when claiming is allowed" are two things rather than one
## — the guards belong to the collision, and every one of them is about *this* touch rather than
## about the campaign ending.
##
## Public because a suite has to be able to take it without steering a robot into it, and taking it
## by emitting the signals by hand would be a test asserting against its own copy of this method.
func claim() -> void:
	if _taken:
		return
	_taken = true
	EventBus.trophy_claimed.emit(global_position)
	claimed.emit()
	queue_free()
