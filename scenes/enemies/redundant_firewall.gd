class_name RedundantFirewall
extends FirewallNode
## A Firewall Node with a standby: every time something else in its room goes down, it **picks up
## that load** — one more beam, and a slightly faster sweep — up to a cap it announces by reaching.
##
## The Firewall Node asks "where are you allowed to stand", and the honest answer a player learns is
## "anywhere outside its reach, so kill it last". Nothing in a room has ever charged for that
## ordering. This does: every other body cleared makes the node that is still standing harder to
## stand near, so the room now has a *kill order* and the node is at the front of it. That is the
## Recursion's question — when do I kill this, not can I — asked by something that never moves.
##
## **Its twin dying is the case worth naming, and it is only a case.** Two of these in one room are
## a genuine pair: break one and the other takes its share, so they have to come down close
## together or the survivor is worth two. But the rule is the room's load rather than the pair's,
## which is what stops the tier from being an ordinary Firewall Node whenever the generator happens
## to draw one of it — and it is why this is failover rather than a link.
##
## Everything else is inherited untouched: the beams stop at walls, one cooldown covers the whole
## fan, and what damages the player is measured against the line that is drawn. A failover adds a
## `Line2D` and nothing else — `_update_beams` re-spaces the fan from its own size every frame, so
## the beam that arrives is spaced by the same arithmetic as the ones that were there at the start.
##
## The config is never written to. `beam_rotation_speed` lives on a resource shared by every node in
## the run, so the speed-up is held here and applied through `rotation_speed`; writing it into the
## `.tres` would spin up every Firewall Node on the floor, including the ones that have taken over
## nothing. That is the trap `Recursion._become_fragment` documents, met on a different field.

## What one colour of the sprite goes to for `FAILOVER_FLASH_SECONDS` when load is picked up. The
## hostile screen red the whole game paints on things that have just become more dangerous — the
## fan gaining a spoke is the real tell, and this is what makes the player look at it in time to
## count.
const FAILOVER_TINT := Color(1.0, 0.42, 0.42)
const FAILOVER_FLASH_SECONDS := 0.35

## How many times this node has taken over. Counted rather than derived from the beam count so the
## rotation speed-up has something honest to compound against, and so a node at its beam cap stops
## escalating entirely rather than quietly continuing to spin faster.
var _failovers := 0

var _flash_left := 0.0


func _on_ready() -> void:
	super()
	# Room-scoped by the parent check in `_on_enemy_killed` rather than by a room reference held
	# here: a room does not exist yet for an enemy being placed by `Room.populate`, and the
	# container this node is a child of is the room's enemy list either way.
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _act(delta: float) -> Vector2:
	_step_flash(delta)
	return super(delta)


## How many times it has picked up load. What a test asks, and what the fan is showing.
func get_failover_count() -> int:
	return _failovers


## True once it can take on no more. The cap is on beams rather than on failovers because beams are
## what the player is standing in.
func is_saturated() -> bool:
	return get_beam_count() >= maxi(_tuning.failover_max_beams, 1)


func rotation_speed() -> float:
	return super() * pow(maxf(_tuning.failover_rotation_scale, 1.0), float(_failovers))


## Something died in this room. Anything but this node, and anything but a body in another room —
## which cannot happen while the floor freezes every room the player is not in, but is checked
## anyway, because `enemy_killed` is a global signal and the cost of being wrong about that is a
## node spinning up for a kill on the other side of the floor.
func _on_enemy_killed(enemy: Node, _at: Vector2) -> void:
	if enemy == self or is_dead() or is_saturated():
		return
	if enemy == null or enemy.get_parent() != get_parent():
		return
	_fail_over()


func _fail_over() -> void:
	var cap := maxi(_tuning.failover_max_beams, 1)
	for _index: int in maxi(_tuning.failover_beams, 1):
		if get_beam_count() >= cap:
			break
		add_beam()
	_failovers += 1
	_flash_left = FAILOVER_FLASH_SECONDS
	tint_toward(FAILOVER_TINT, 1.0)


## Returns the sprite to its resting colour once the flash is spent. The beam it gained does not go
## anywhere; this is only the moment that says one arrived.
func _step_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		tint_toward(FAILOVER_TINT, 0.0)
