class_name CascadeFailure
extends Boss
## The Data Center's boss: four server nodes wired into one rack, running too hot.
##
## The Scrap King asks the player to **notice**. Runtime Error asks them to **predict**. This one
## asks them to **keep moving**, which is the only thing Floor 3 has been teaching since its first
## room — and it asks in the floor's own words. Every hazard it puts on the ground is a
## `ThermalZone`, the same class the Data Center's rooms are built from, so the teal-to-violet ramp
## the player has been reading for nine rooms means here exactly what it meant there: this ground
## is about to vent. What changes is who is heating it. On the floor, the player is; in this room,
## the rack is.
##
## **Load is the whole fight.** The rack carries a fixed amount of it, split between the nodes
## still standing, so `load` is `node_count / nodes_alive`: one at the start, four at the end. It
## drives how fast the ring turns, how fast the packets run, and how often each node vents. Almost
## nothing else escalates, and almost nothing needs to — one number the player can see the
## consequences of is worth more than three curves nobody can separate. The single exception is the
## clock that aims at the player, which counts nodes lost rather than following load and moves by a
## fraction of what load would have moved it; see below.
##
## The vent rate is the part worth stating out loud, because it is what keeps the last phase
## survivable. Per node it is `vent_interval / load`, so four nodes venting every three seconds and
## one node venting every 0.75 put the *same* heat per second onto the floor. The boss does not
## out-scale the arena as it escalates; it **concentrates**, from a ring of patches into a trail
## behind one body. That is a climax rather than an unwinnable room, and it is arithmetic rather
## than tuning.
##
## ## Four places heat comes from
##
## The rack vents where its bodies are. It also **aims** — a patch centred on wherever the robot is
## standing, every `aimed_vent_interval` — and it **leads**, a patch centred on where the robot will
## be in `lead_seconds` if it does not turn, every `lead_vent_interval`. And every
## `line_vent_interval` it lays a **wall**: a chain of patches down the whole of one of its own
## wires, filling together, with a door in it where the packet was riding.
##
## The first of those is what makes the fight's own sentence true. "Keep moving" was the floor's
## lesson and the boss's stated job, and the boss was not actually asking it: heat only ever landed
## on the ring, so a player who found a spot the ring did not sweep could stand in it and shoot. The
## aimed vent removes standing still as an option anywhere in the room, and it removes it the way
## this floor removes things — by painting the ground and counting down, never by landing a hit the
## player could not have walked out of.
##
## The second removes the *other* free answer, which the aimed vent leaves open and which is easier
## to find. Heat centred on the robot is always behind a robot that is moving, so a player who
## simply picks a heading and holds it never meets any of it — "keep moving" is satisfied by a
## straight line, and a straight line takes no reading at all. The lead vent is the front of the
## pincer. The aimed patch charges for stopping, the lead patch charges for holding a heading, and
## the only input that answers both is a turn.
##
## This is where the fight used to **scatter** instead, a patch at a uniformly random point in the
## arena, and the argument for it was the corners: a 416x192 room has ground the ellipse cannot
## reach, and heat that only appears on the ring or under the robot leaves that ground safe by
## construction. The lead vent inherits that argument and improves on it. A player walking out wide
## to a cold corner has a heading pointed at that corner, so the patch that leads them is already
## there when they arrive — the corners close because the player went to them, rather than because
## a die roll covered enough of the room to eventually include them. Nothing in the fight is now
## random, which is the property the rest of it already had.
##
## The third is the only one that denies a **route** rather than a square, and until it existed
## nothing here did. Both patch clocks are answered by a fifth of a second of walking, so the fight
## was a room of islands a player stepped between: the pincer above is a real sentence, but it is
## one a player satisfies by drifting, and they can drift at range for the whole fight without ever
## being made to choose between two bad options. A wall cannot be drifted around. It is crossed
## while it is cold or it is accepted, and the door in it — see `_drop_line_vent` — is what makes
## that a question rather than a coin toss.
##
## Its escalation is the fight's own arithmetic rather than a curve of its own. Four nodes make four
## short chords near the rim; two make one wire straight through the middle; one makes none, and the
## trail behind the runaway node is the only wall a room with one body in it can have. **How nearly
## the two-node wall cuts the arena in half is decided by which two nodes the player left standing**
## — the geometry choice the shared pool hands them, which until now paid out only in how far the
## packets travelled.
##
## **None of the three is divided by load**, and that is deliberate. The whole escalation of this
## fight is the rack concentrating what it already had; sources that quadrupled alongside it would
## make the last phase a different, worse fight — four times the aimed heat on a player with one
## body left to shoot. So the rack's own heat concentrates and these three stay flat, which keeps
## the arithmetic in the paragraph above true of the *arena* rather than only of the nodes.
##
## **The aimed vent does step up, and it is the only thing here that escalates on anything other
## than load.** It walks from `aimed_vent_interval` to `aimed_vent_interval_runaway` by one even
## step per node lost — three seconds, 2.67, 2.33, two — which is `get_aimed_vent_interval`, and
## the step is taken the moment the node blows out rather than at the next vent. A failure is the
## loudest event in this fight and it used to change nothing about the pressure on the player's own
## feet: the ring came in faster and smaller, and the clock aiming at the robot ran on exactly as
## it had, so each phase the player earned arrived with the same private rhythm underneath it.
##
## The size of the step is the whole of what keeps it fair. A third off the interval is a pace the
## player can feel; the factor of four that load would have applied is a different fight. And the
## floor under it is `vent_seconds` — the gap between the aimed clock and the fill is how long the
## ground the robot is standing on is cold, so an interval at or under the fill would leave none of
## it, and *keep moving* would stop being a rhythm and become the only input. The lead clock stays
## flat throughout: it is a rule about the robot's heading, and a heading does not know which node
## just went.
##
## **The rack breathes.** The ring contracts to `ring_inhale` of its radius and opens out again on
## a seven-second sine. Without it the middle of the arena is permanently safe, and a boss with a
## safe centre, on the floor about not standing still, would be a boss arguing with the room it is
## standing in. Breathing also makes the fiction do the work: this is cooling equipment, and the
## thing cooling equipment does is move air.
##
## **There is not one projectile in it**, which is deliberate and is the fight's identity. Both
## bosses before it are answered by dodging bullets. This floor's mechanic is positional, so its
## boss is positional: heat on the ground, load running along the lines between the nodes, and the
## nodes themselves, which cost a point to stand inside like every other body in the game
## (`BossPart._step_contact_damage`). Everything that can hurt the player here is a place.
##
## **The last node leads.** It walks at where the robot is going rather than at where it is, on the
## same `lead_seconds` the lead vent uses, which is what stops the fight's climax from being its
## safest phase — see `_step_runaway`.
##
## ## Why the nodes do not have health of their own
##
## They visibly can be shot and they visibly fail one at a time, so per-node pools are the obvious
## build, and they are wrong. Damage would then be the player's to allocate, and allocating it
## optimally means spreading it evenly — which holds the fight at load one for three quarters of
## its length and then collapses phases two and three into a few seconds each. A boss whose best
## line skips its own last act is a boss that has been designed twice and shipped once.
##
## So the pool is shared and a node blows out at each even fraction of it: with four nodes, at 75%,
## 50% and 25%. Every player sees all three phases and sees them at the same length. What the
## player *does* choose is **which** node fails — the one that has taken the most damage since the
## last failure goes — so they decide the shape of the ring they are left fighting, without
## deciding how long they fight it. Two nodes left on opposite slots is a line that sweeps the
## whole arena; two on adjacent slots is a short one near the wall. That is a real decision, and it
## is about geometry rather than about pacing, which is the half of it worth giving away.
##
## ## What survives its death
##
## The same line every fight in this game draws: **committed hazards resolve, uncommitted ones
## never happen.**
##
## A vent already on the floor is committed. It was put there, it is visibly climbing, and it goes
## on to fill and to cost a point in an arena the player has apparently just won — `spawn_vent`
## parents it into the session for exactly that reason, the same place `CompileLane` puts itself.
## A packet is not committed and stops existing the moment the rack does: a packet *is* load moving
## between two nodes, and there are no nodes. Nothing has to cancel it, because it was never a
## thing on the floor — it is drawn and resolved from this controller's own `_physics_process`, and
## `_is_dead` stops that on the frame the fight ends.
##
## `tests/test_post_boss.gd` asserts both outcomes rather than either mechanism.

const NODE_SCENE := preload("res://scenes/bosses/cascade_node.tscn")

## How far inside the arena walls a node may travel. The vents it drops are clamped to the arena
## itself rather than to this, so a node at the edge still puts heat right up against the wall —
## a strip of permanently cold floor around the outside is the one thing this fight cannot afford.
const ARENA_INSET := 26.0

## What the vent colours are multiplied by before being used as a node's `modulate`.
##
## `modulate` multiplies, so a colour at or below full value can only ever darken the sprite it is
## applied to — a node "heating up" would visibly go dim. The same correction `RuntimeError` makes
## for the compile lane's amber, for the same reason. See `_load_tint`.
const TINT_GAIN := 2.1

## The most patches one line vent may lay, however long the wire is.
##
## A ceiling rather than a tuning knob: at the shipped footprint the longest wire the ring can
## stretch needs six, so this never binds on a fight anybody plays. It exists so that a config with
## a one-tile footprint and a wide ring cannot ask the arena for two hundred zones on one frame.
const MAX_LINE_VENTS := 12

## The player's collision radius, from player.tscn. Duplicated for the reason `CompileLane`,
## `FirewallNode` and `ThermalZone` all duplicate it: a hazard has to be able to ask who it caught
## without depending on how the player scene is assembled.
const PLAYER_RADIUS := 5.0

## Where the breath starts: fully exhaled, so the fight opens with the rack at its widest and the
## first thing it does is close in. A ring that started contracted would put four nodes on top of
## the player in the first second of a fight they have not been shown yet.
const START_BREATH_PHASE := PI * 0.5

enum Phase {
	## The whole rack standing. Four slots, four lines, heat spread around the ring.
	NOMINAL = 1,
	## Nodes are failing and the survivors are taking the slack. Two or three left.
	REROUTING = 2,
	## One node carrying all of it. No lines left to move load along, so it comes to the player.
	RUNAWAY = 3,
}

@export var config: CascadeFailureConfig

var _health := 0.0
var _is_dead := false

## One entry per slot, null where a node has already blown out. Indexed by slot rather than packed,
## because a slot's *position on the ring* is what the player is choosing between when they decide
## which node to push, and compacting the array would lose it.
var _nodes: Array[BossPart] = []

## Damage credited to each slot since the last failure, and the whole of how the fight decides
## which node goes. Reset on every failure, so "the one you were pushing" means the one you were
## pushing lately rather than the one you happened to shoot first.
var _damage_by_slot: PackedFloat32Array = []

## Seconds until each slot vents again. Per slot rather than one clock for the rack, so four nodes
## do not vent on the same frame — which would read as one enormous hazard rather than four.
var _vent_left: PackedFloat32Array = []

## How far along its line each packet has travelled, zero to one. Indexed by position in the living
## list rather than by slot, because a line is between two *living* nodes and there are fewer lines
## than slots as soon as one fails.
var _packet_progress: PackedFloat32Array = []

var _phase := Phase.NOMINAL

## The room interior. Vents are clamped to this; nodes are clamped to `_body_bounds`.
var _arena: Rect2
var _body_bounds: Rect2

var _player: Node2D
var _spin := 0.0
var _breath := START_BREATH_PHASE
var _packet_cooldown := 0.0

## Seconds until the rack aims at the player again, and until it leads them again. One clock each
## for the whole rack rather than one per node, because neither is a thing a *node* does — they are
## the room being run too hot, and they go on at the same rate whether four bodies are doing it or
## one.
var _aimed_left := 0.0
var _lead_left := 0.0

## Seconds until the rack lays a wall along one of its own wires. One clock for the rack for the
## same reason as the two above, and flat for the same reason: a wall is the room being cut, and a
## room does not know how many bodies are left standing in it.
var _line_left := 0.0

## Seconds of wall left on the floor, and for exactly that long the two clocks that follow the robot
## are **held** — see `_step_aimed_vent`.
var _wall_left := 0.0


func _ready() -> void:
	assert(config != null, "CascadeFailure.config is unset: assign a CascadeFailureConfig.")
	_health = config.max_health
	var slots := _slot_count()
	_nodes.resize(slots)
	_damage_by_slot.resize(slots)
	_vent_left.resize(slots)
	_packet_progress.resize(slots)


## Called by the floor once the rack is in the arena it will fight in.
func begin(arena: Rect2) -> void:
	_arena = arena
	_body_bounds = arena.grow(-ARENA_INSET)

	for slot: int in _slot_count():
		var node: BossPart = NODE_SCENE.instantiate()
		add_child(node)
		# After add_child, always: `global_position` on a parentless node is only its local
		# position, which would put the whole rack at those offsets from this controller rather
		# than in the arena. The lesson `MergeConflict._spawn_part` paid for first.
		node.global_position = _slot_position(slot)
		node.set_tint(_load_tint())
		node.took_damage.connect(_on_node_damaged.bind(slot))
		_nodes[slot] = node

		# Staggered across the vent interval rather than started together, so the rack's first
		# four vents arrive one at a time and the player meets the mechanic once before they meet
		# it four times. Firewall Node spreads its starting angle for the same reason.
		_vent_left[slot] = config.vent_interval * (float(slot) + 1.0) / float(_slot_count())
		# Packets likewise: evenly spread around the ring so the lines read as a circulating
		# current rather than as four things flashing in unison.
		_packet_progress[slot] = float(slot) / float(_slot_count())

	# A full interval before the first aimed vent and half of one before the first lead vent, so the
	# opening seconds of the fight are the rack introducing itself. A patch appearing under the
	# player on the frame they walked in would be the fight's fairest mechanic read as its cheapest.
	#
	# Offset from each other rather than started together, so the player meets the two clocks one at
	# a time and can tell them apart. Two patches arriving on the same frame — one under the robot,
	# one ahead of it — is the pincer stated before either half of it has been learned.
	_aimed_left = config.aimed_vent_interval
	_lead_left = config.lead_vent_interval * 0.5
	# Last of the three, and by a clear margin. The wall is the loudest thing the rack does and the
	# only one that asks the player to go somewhere rather than to leave somewhere; meeting it
	# before the two patch clocks have been seen once would be the fight opening on its hardest
	# sentence.
	_line_left = config.line_vent_interval

	EventBus.boss_phase_changed.emit(int(_phase))
	_announce_health()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_player = _find_player()
	_packet_cooldown = maxf(_packet_cooldown - delta, 0.0)
	_step_motion(delta)
	_step_vents(delta)
	_step_packets(delta)
	queue_redraw()


# --- State --------------------------------------------------------------------


func get_phase() -> Phase:
	return _phase


func get_health() -> float:
	return _health


## The real pool, and what the bar is given. Honest, like `RuntimeError`'s and unlike The Scrap
## King's: it falls once, monotonically, and reaching zero means the fight is over. There is no
## trick in this fight for a lying bar to protect.
func get_health_ratio() -> float:
	return _health / maxf(config.max_health, 0.001)


## How many nodes are still standing, derived from the pool rather than counted from the array.
##
## Derived is what makes the failures land at the same fractions for every player, whatever order
## they shot things in — and it means a single enormous hit that crosses two thresholds blows out
## two nodes, which is the honest outcome. `_reconcile_nodes` is what makes the array agree.
func get_nodes_alive() -> int:
	if _health <= 0.0:
		return 0
	return clampi(ceili(get_health_ratio() * float(_slot_count())), 1, _slot_count())


## `node_count / nodes_alive`: one while the rack is whole, `node_count` when one node is left.
## Every rate in the fight is this number times its resting value.
func get_load() -> float:
	return float(_slot_count()) / float(maxi(get_nodes_alive(), 1))


## Seconds between aimed vents right now: `aimed_vent_interval` with the rack whole, tightening one
## even step per node lost until it is `aimed_vent_interval_runaway` with a single node left.
##
## Interpolated on nodes *lost* rather than on load, which is what makes the steps even. Load is
## `4, 2, 1.33, 1` between the same four states — it does most of its moving in the last failure,
## and a clock following it would sit near its resting pace for three quarters of the fight and
## then lurch. The player is being paid for a node, so each node should pay the same.
func get_aimed_vent_interval() -> float:
	var lost := float(_slot_count() - get_nodes_alive())
	var span := float(maxi(_slot_count() - 1, 1))
	var interval := lerpf(
		config.aimed_vent_interval,
		config.aimed_vent_interval_runaway,
		clampf(lost / span, 0.0, 1.0),
	)
	return maxf(interval, 0.05)


## Every node still standing. Plural, like The Scrap King's and unlike Runtime Error's, because this
## boss genuinely has several bodies at once — and anything that wants to reach the fight through a
## body (a test, a targeting sweep) should not have to know which slots are empty.
func get_parts() -> Array[BossPart]:
	var parts: Array[BossPart] = []
	for slot: int in _nodes.size():
		var node := get_node_at(slot)
		if node != null:
			parts.append(node)
	return parts


## The node in `slot`, or null if it has blown out or the fight has not begun.
func get_node_at(slot: int) -> BossPart:
	if slot < 0 or slot >= _nodes.size():
		return null
	var node := _nodes[slot]
	return node if is_instance_valid(node) else null


## Where each packet currently is, in global coordinates. Empty once there are fewer than two nodes
## left. For the suite, and for anything that wants to draw them somewhere other than here.
func get_packet_positions() -> Array[Vector2]:
	var packets: Array[Vector2] = []
	var living := _living_slots()
	for index: int in _edge_count(living.size()):
		var from := _nodes[living[index]].global_position
		var to := _nodes[living[(index + 1) % living.size()]].global_position
		packets.append(from.lerp(to, _packet_progress[index]))
	return packets


# --- Damage -------------------------------------------------------------------


## Every hit arrives here, whichever node took it, and the pool is the rack's. The slot is credited
## separately: it decides *which* node fails next and nothing else.
func _on_node_damaged(info: DamageInfo, slot: int) -> void:
	if _is_dead:
		return

	_health = maxf(_health - info.amount, 0.0)
	if slot >= 0 and slot < _damage_by_slot.size():
		_damage_by_slot[slot] += info.amount
	EventBus.enemy_damaged.emit(self, DamageInfo.new(info.amount, info.source), _health)
	_announce_health()

	if _health <= 0.0:
		_die()
		return
	_reconcile_nodes()


## Blows out as many nodes as the pool now says are gone, and moves the phase to match.
##
## A loop rather than a single failure, so a hit large enough to cross two thresholds costs two
## nodes. The Scrap King floors damage at each boundary instead, because a build strong enough to
## skip a phase would skip the feigned death that fight is built on; this one has nothing to
## protect, and a player who has deleted half the rack in one shot has simply earned that half.
func _reconcile_nodes() -> void:
	var living := _living_slots().size()
	var wanted := get_nodes_alive()
	if living <= wanted:
		# The overwhelmingly common case: a hit that cost the rack integrity and no bodies. Returning
		# here rather than falling through is what keeps a re-tint and a phase comparison off every
		# rivet that lands.
		return

	while living > wanted:
		_fail_node(_weakest_slot())
		living -= 1

	var next := _phase_for(living)
	if next != _phase:
		_phase = next
		EventBus.boss_phase_changed.emit(int(_phase))

	# The tighter clock starts at the failure rather than at the next vent. A clock left running on
	# the interval the previous phase set would spend one whole vent pretending the rack still had
	# the node the player has just taken off it, which is the moment the step exists to be felt in.
	_aimed_left = minf(_aimed_left, get_aimed_vent_interval())

	# The survivors are carrying more, and they say so. Applied to every node rather than only to
	# the ones that changed, because they all did — load is a property of the rack.
	var tint := _load_tint()
	for slot: int in _slot_count():
		var node := get_node_at(slot)
		if node != null:
			node.set_tint(tint)


## Takes one node out of the rack, and leaves its heat behind.
##
## The vent is not decoration. A node failing is the only moment in the fight when the player is
## rewarded for standing somewhere in particular — right in front of the thing they were pushing —
## and the floor charging them for staying there is the whole idea of the floor. It also means the
## cascade is visible as a thing that happened *to the room* rather than as a sprite disappearing.
func _fail_node(slot: int) -> void:
	var node := get_node_at(slot)
	if node == null:
		return
	var where := node.global_position
	_nodes[slot] = null
	node.queue_free()

	_drop_vent(where)
	for index: int in _damage_by_slot.size():
		_damage_by_slot[index] = 0.0


## Which node goes next: the one that has absorbed the most damage since the last failure.
##
## Ties break to the lowest living slot, which is only reachable by a player spreading damage
## exactly evenly — at which point they have expressed no preference and any answer is the right
## one. Never returns a dead slot: the caller has already established that one node too many is
## standing.
func _weakest_slot() -> int:
	var living := _living_slots()
	var best := living[0]
	for slot: int in living:
		if _damage_by_slot[slot] > _damage_by_slot[best]:
			best = slot
	return best


## Nothing is scheduled once this returns. `_is_dead` stops `_physics_process` before the ring, the
## vent clocks and the packets can run at all, which takes every *uncommitted* hazard with it — see
## the class doc for why the vents already on the floor are deliberately not among them.
func _die() -> void:
	_is_dead = true

	var where := _body_bounds.get_center()
	var living := _living_slots()
	if not living.is_empty():
		where = _nodes[living[0]].global_position
	for slot: int in living:
		_nodes[slot].queue_free()
		_nodes[slot] = null

	# `_physics_process` returns on `_is_dead` and will never ask for another frame, so without
	# this the last picture of the rack — its lines and the packets on them — would stay painted
	# on an arena that no longer has a boss in it.
	queue_redraw()

	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


# --- The ring -----------------------------------------------------------------


## Turns the ring, breathes it, and walks each node toward the slot it belongs in — or, with one
## node left, drops all of that and sends it after the player.
func _step_motion(delta: float) -> void:
	var living := _living_slots()
	if living.size() <= 1:
		_step_runaway(delta, living)
		return

	var load := get_load()
	_spin = fposmod(_spin + config.ring_spin_speed * load * delta, TAU)
	_breath = fposmod(_breath + config.ring_breath_speed * delta, TAU)

	for slot: int in living:
		var node := _nodes[slot]
		# Moved toward its slot at a capped speed rather than assigned to it, so a status on one
		# node shows: a chilled node falls behind the formation and stretches the lines it carries.
		node.global_position = node.global_position.move_toward(
			_slot_position(slot),
			config.slot_track_speed * node.get_status_speed_scale() * delta,
		)


## The last phase. The node leaves the ring, which is what "there is nothing left to route load to"
## looks like, and walks at the player at a speed the robot beats comfortably.
##
## It is not meant to catch them. It vents on its own clock while it walks, so what it is really
## doing is drawing a line of hot ground through the arena behind wherever the player has been —
## and the arena is 416x192, so a player running from it is a player about to cross their own
## trail. The floor's last word, and the same one it opened with.
##
## **It walks at the lead point rather than at the robot**, on `lead_seconds`, which is the same
## rule and the same number the lead vent states. Chasing the robot's current position made this
## the safest phase in the fight: a pursuer 55 px/s slower than its target and aimed at where that
## target already is falls behind on every frame the player turns, so the trail it was drawing
## stayed permanently behind them and the climax of the fight was a walk. Aiming where the robot is
## *going* means it cuts the corner instead, and a player circling the arena — which is what
## running from it looks like in a room this size — finds it inside their own circle and their own
## trail across the front of it.
##
## Leading was the fix rather than speed, and the difference is the fight's whole character. A node
## at 135 would be a chase the player can lose by holding a direction; a node at 105 that leads is
## a chase they lose by holding a *turn*, which is the thing this floor has spent ten rooms and
## three vent clocks asking for. It also keeps the config's promise that the last node cannot
## outrun the robot, so the phase remains one the player wins on foot.
func _step_runaway(delta: float, living: Array[int]) -> void:
	if living.is_empty() or _player == null:
		return
	var node := _nodes[living[0]]
	var target := _player.global_position + _player_velocity() * config.lead_seconds
	node.global_position = node.global_position.move_toward(
		target, config.runaway_speed * node.get_status_speed_scale() * delta
	)
	node.global_position = node.global_position.clamp(_body_bounds.position, _body_bounds.end)


## Where a slot sits this frame: its fixed share of the ring, turned by the spin and scaled by the
## breath. Clamped into `_body_bounds`, which only bites at full extension against a short arena —
## and flattening the ellipse against the wall is the right failure, because a node inside the wall
## is a node half of whose sprite the player cannot shoot.
func _slot_position(slot: int) -> Vector2:
	var angle := _spin + TAU * float(slot) / float(_slot_count())
	var extension := lerpf(config.ring_inhale, 1.0, 0.5 + 0.5 * sin(_breath))
	var offset := Vector2(
		cos(angle) * config.ring_radius.x, sin(angle) * config.ring_radius.y
	) * extension
	return (_body_bounds.get_center() + offset).clamp(_body_bounds.position, _body_bounds.end)


# --- Vents --------------------------------------------------------------------


## The four sources, in the order the player learns them: the bodies, then where the robot is, then
## where it is going, then the wires between the bodies. See the class doc for why only the first is
## scaled by load.
func _step_vents(delta: float) -> void:
	_wall_left = maxf(_wall_left - delta, 0.0)
	_step_node_vents(delta)
	_step_aimed_vent(delta)
	_step_lead_vent(delta)
	_step_line_vent(delta)


func _step_node_vents(delta: float) -> void:
	var interval := config.vent_interval / get_load()
	for slot: int in _living_slots():
		_vent_left[slot] -= delta
		if _vent_left[slot] > 0.0:
			continue
		_vent_left[slot] = maxf(interval, 0.05)
		_drop_vent(_nodes[slot].global_position)


## Heat centred on the robot, on the one clock in the fight that counts nodes rather than load.
##
## The clock runs whether or not there is a player to aim at, and the drop is skipped rather than
## deferred when there is not. Holding the vent until a player appears would make the first thing a
## returning robot met a patch that had been waiting for it, which is the one kind of hazard this
## floor does not have.
##
## **It stops while a wall is filling**, along with the lead clock, and the clock is *held* rather
## than allowed to run down and skip — so the rhythm the player was reading resumes where it left
## off instead of arriving late by a random fraction. The rack does one thing at a time.
##
## That is a fairness rule as much as a legibility one. A wall is the only hazard here that asks the
## player to go somewhere rather than to leave somewhere, and it is answerable because it has a door
## in it (`_drop_line_vent`). A patch dropped on that door while the wall was still cold would close
## the one answer the wall offered, after the player had already committed to it — the single way
## this fight could put damage somewhere the telegraph did not warn about. Holding the two clocks
## that chase the robot is what makes that impossible rather than merely unlikely.
func _step_aimed_vent(delta: float) -> void:
	if _wall_left > 0.0:
		return
	_aimed_left -= delta
	if _aimed_left > 0.0:
		return
	_aimed_left = get_aimed_vent_interval()
	if _player != null:
		_drop_vent(_player.global_position)


## Heat where the robot is heading, on the same kind of clock that does not care how the fight is
## going.
##
## The lead is taken off the player's own `velocity` rather than off their input, for the reason
## `ThermalZone` measures stillness the same way: a robot shoved by knockback or carried by a
## migration pad is going somewhere it did not ask to go, and the rack is reading the room rather
## than the controller. A robot with no velocity leads nowhere and the patch lands on it, which is
## the same square the aimed clock would have chosen — see `CascadeFailureConfig.lead_seconds` for
## why that convergence is the point rather than an edge case.
##
## The lead point is *not* clamped here. `_drop_vent` clamps the finished rect into the arena, which
## is the correct place for it: a robot running at a wall is led into that wall, and the patch that
## meets them there is a whole patch flush against it rather than half of one outside the room.
func _step_lead_vent(delta: float) -> void:
	if _wall_left > 0.0:
		return
	_lead_left -= delta
	if _lead_left > 0.0:
		return
	_lead_left = maxf(config.lead_vent_interval, 0.05)
	if _player == null:
		return
	_drop_vent(_player.global_position + _player_velocity() * config.lead_seconds)


## The robot's current velocity, or zero when whatever is standing in for it does not have one.
##
## Typed as `Node2D` throughout this file rather than as `Player`, so the boss can be fought by a
## test double — and a double without a `velocity` must lead to a vent under the target rather than
## to a crash.
func _player_velocity() -> Vector2:
	if _player is CharacterBody2D:
		return (_player as CharacterBody2D).velocity
	return Vector2.ZERO


## Heat along one of the rack's own wires: a chain of patches from one living node to its
## neighbour, dropped on a single frame and filling together, which makes it a **wall** rather than
## a patch.
##
## This is the only thing in the fight that denies a *route* instead of a square, and the fight
## needed one. Everything else it lays down is a patch the robot leaves in a fifth of a second, so
## a player circling at range was never once asked to choose between two bad options — they
## sidestepped, for the whole length of the fight. A wall cannot be sidestepped. It is crossed
## while it is cold, or it is accepted, and either answer has to be chosen inside `vent_seconds`.
##
## **The wire is chosen, not rolled** — nothing in this fight is random — and it picks the one
## nearest the player. That is the only choice that makes the mechanic mean anything: a wall laid
## across the far side of the arena is scenery, and the wall that is worth reading is the one across
## the ground the robot is actually standing on. Distance is how the rack says so without a die.
##
## The clock runs whether or not there is a wire to lay a wall on, and the drop is skipped rather
## than deferred when the rack is down to one node — `_step_aimed_vent`'s convention, for its
## reason. The last phase therefore has no walls in it at all, which is correct twice over: there is
## nothing left to route load along, and the trail behind the runaway node is already the only wall
## a room with one body in it can have.
func _step_line_vent(delta: float) -> void:
	_line_left -= delta
	if _line_left > 0.0:
		return
	_line_left = maxf(config.line_vent_interval, 0.05)

	var living := _living_slots()
	if _edge_count(living.size()) == 0:
		return
	# The two clocks that chase the robot are held until this wall has finished filling — but only
	# if a wall was actually laid. A wire too short to carry one lays nothing, and holding them for
	# a wall that does not exist would quietly buy the player a second of calm the fight never
	# charged for.
	if _drop_line_vent(_nearest_edge(living), living):
		_wall_left = config.vent_seconds


## Which wire the wall goes on: the one whose *segment* passes closest to the robot, not the one
## whose midpoint does. A chord the player is standing near the end of is a chord that cuts them
## off, and measuring to the midpoint would hand that wall to a wire on the other side of the room.
##
## Falls back to the first wire when there is nobody to measure against, so a fight running without
## a player still lays walls for a test to inspect.
func _nearest_edge(living: Array[int]) -> int:
	if _player == null:
		return 0
	var at := _player.global_position
	var best := 0
	var best_distance := INF
	for index: int in _edge_count(living.size()):
		var from := _nodes[living[index]].global_position
		var to := _nodes[living[(index + 1) % living.size()]].global_position
		var distance := Geometry2D.get_closest_point_to_segment(at, from, to).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## Lays the wall along wire `index`, leaves a door in it, and reports whether there was enough wire
## to lay one at all.
##
## Spaced by the vent's own width so consecutive patches meet at their edges rather than leaving
## gaps between them. That is what `CascadeFailureConfig.vent_tiles` is four tiles for: a chain of
## islands is four sidesteps, and only a continuous shape is a wall.
##
## **The door is where the packet is**, and it is the half of this mechanic that keeps it fair. A
## solid wall across a 416x192 room is one the player can be on the wrong side of through no
## decision of their own, and the fight would have nothing to offer them; a wall with a gap is a
## route, and finding it inside `vent_seconds` is the question the mechanic exists to ask.
##
## Putting that gap under the packet makes it the load's doing rather than a mercy the fight hands
## out. The one stretch of wire that did not overheat is the stretch the load was occupying, which
## is the fiction the packets have been drawing since the first frame — and the first thing in this
## fight they have ever been *for*. It also moves the door between one wall and the next without a
## die, because the packet has moved.
##
## The chain is laid at the nodes' positions on the frame it is dropped and does not follow them
## afterwards. That is correct rather than a shortcut: the wire is where the heat came from and the
## ground is where the heat *is*, and ground does not orbit. A wall that tracked the spinning ring
## would be a hazard whose final position the player could not have read while it was still cold,
## which is the one thing nothing in this fight is allowed to be.
func _drop_line_vent(index: int, living: Array[int]) -> bool:
	var from := _nodes[living[index]].global_position
	var to := _nodes[living[(index + 1) % living.size()]].global_position
	var width := float(maxi(config.vent_tiles.x, 1) * Room.TILE_SIZE)
	var length := from.distance_to(to)
	if length < width * 2.0:
		# Not enough wire to make a wall out of. The rack has inhaled, or two nodes have drifted
		# together, and what a chain would come to here is a patch or two with no room for a door
		# between them — a hazard the player cannot pass rather than a wall they must find their way
		# through. Two footprints of wire is the shortest that yields three patches, which is the
		# shortest thing that is still a wall once the door is taken out of it.
		#
		# The clock is spent either way, and that is what quietly hands the pacing to the breath:
		# the rack lays walls while it is open and lays none while it is drawn in. It is the right
		# fiction — a rack with its nodes clustered has no long wire to overheat — and it is the
		# right rhythm, because the wall then arrives on the beat the player is already watching.
		return false

	# Spaced by exactly one footprint from the first node, rather than by the wire divided into
	# equal parts. Even division is the tempting arithmetic and it is what makes the door
	# unprovable: it puts consecutive patches anywhere from half a footprint to a whole one apart
	# depending on how long the wire happens to be, and at the near end of that range a single
	# missing patch leaves a gap narrower than the patches either side of it grow by, which is a
	# door the robot does not fit through. A fixed stride means every door this leaves is the same
	# door — a full footprint of clear wire, at every length of wire the ring can stretch.
	#
	# The cost is a stub of up to one footprint of unheated wire at the far end, where the stride
	# does not divide the wire evenly. That is a second door rather than a defect, it is never wider
	# than the one the packet leaves, and it moves as the ring breathes.
	var count := clampi(floori(length / width) + 1, 3, MAX_LINE_VENTS)
	var door := clampi(roundi(_packet_progress[index] * length / width), 0, count - 1)
	for step: int in count:
		if step == door:
			continue
		_drop_vent(from.lerp(to, width * float(step) / length))
	return true


## Puts one zone on the floor under `at`.
##
## **Every vent starts cold**, and that is the fight's fairness rule stated in one line. Wherever a
## patch lands — under a node, under the robot, in an empty corner — it fills from nothing over
## `vent_seconds` and bites only at the end, so the player who was standing exactly on it has the
## whole warning to walk out.
##
## That is the rule because it is the only one that survives the boss aiming. The version this file
## used to state — *nothing it puts on the floor is aimed at the player* — was a stronger promise
## and a worse fight: it meant a player who found ground the ring did not sweep had nothing to do
## but stand on it, in the fight whose entire subject is not standing still. The telegraph was
## always what made the hazard fair; "nowhere near you" was doing no work that `vent_seconds` was
## not already doing, and it was quietly buying the player a place to stop.
##
## `NullPointer` is the enemy that chooses the player's feet, and it is fair for exactly this
## reason: the telegraph comes first. `tests/test_cascade_failure.gd` measures the telegraph rather
## than the aim, which is the half that must never be weakened.
##
## Sized and clamped through the arena rect so a vent at the edge is a whole vent against the wall
## rather than half of one outside the room.
func _drop_vent(at: Vector2) -> void:
	var size := Vector2(
		maxi(config.vent_tiles.x, 1) * Room.TILE_SIZE, maxi(config.vent_tiles.y, 1) * Room.TILE_SIZE
	)
	var top_left := (at - size * 0.5).clamp(_arena.position, _arena.end - size)
	ThermalZone.spawn_vent(self, Rect2(top_left, size), config.vent_seconds)


# --- Load packets -------------------------------------------------------------


## Advances one packet along each line and checks whether any of them caught the player.
##
## Progress is kept as a fraction rather than as a distance, so a line that grows — because the
## ring is breathing, or because a chilled node has fallen behind it — carries its packet faster
## rather than leaving it stranded partway along a line that has moved out from under it.
func _step_packets(delta: float) -> void:
	var living := _living_slots()
	var edges := _edge_count(living.size())
	if edges == 0:
		return

	var speed := config.packet_speed * get_load()
	for index: int in edges:
		var from := _nodes[living[index]].global_position
		var to := _nodes[living[(index + 1) % living.size()]].global_position
		var span := maxf(from.distance_to(to), 1.0)
		_packet_progress[index] = fposmod(_packet_progress[index] + speed * delta / span, 1.0)
		_strike_player(from.lerp(to, _packet_progress[index]))


## One cooldown for the whole rack, so the point where two lines meet is one hit rather than two —
## Firewall Node's rule about the centre of its fan, and the same reason.
func _strike_player(packet: Vector2) -> void:
	if _player == null or _packet_cooldown > 0.0:
		return
	if _player.global_position.distance_to(packet) > config.packet_radius + PLAYER_RADIUS:
		return

	var health := HealthComponent.find_on(_player)
	if health == null:
		return
	var offset := _player.global_position - packet
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	if health.apply_damage(DamageInfo.new(config.packet_damage, self, direction)):
		_packet_cooldown = config.packet_interval


# --- Helpers ------------------------------------------------------------------


func _slot_count() -> int:
	return maxi(config.node_count, 2)


func _living_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot: int in _nodes.size():
		if get_node_at(slot) != null:
			slots.append(slot)
	return slots


## How many lines the rack has, for a given number of living nodes.
##
## Three or more close into a polygon and every node has two neighbours, so there are as many lines
## as nodes. Two have exactly one line between them — a closed polygon of two would be the same
## line counted twice — and one has nowhere to send load at all, which is what makes the last phase
## look and play like a different fight without a single rule being added for it.
func _edge_count(living: int) -> int:
	if living >= 3:
		return living
	return 1 if living == 2 else 0


func _phase_for(living: int) -> Phase:
	if living >= _slot_count():
		return Phase.NOMINAL
	return Phase.REROUTING if living > 1 else Phase.RUNAWAY


## `ThermalZone`'s own two colours, scaled to survive being used as a `modulate`, interpolated by
## how much load the rack is under.
##
## Taken from that class rather than restated, exactly as `RuntimeError` takes the compile lane's
## amber and red. A node under full load is the colour of ground about to vent, because it means
## the same thing — and if the zones are ever recoloured, the boss follows without anybody
## remembering that it should.
func _load_tint() -> Color:
	var heat := 0.0
	if _slot_count() > 1:
		heat = clampf((get_load() - 1.0) / float(_slot_count() - 1), 0.0, 1.0)
	var base := ThermalZone.COOL_COLOR.lerp(ThermalZone.HOT_COLOR, heat)
	# Alpha pinned rather than scaled with the rest: multiplying it too would push the sprite past
	# opaque, which is not brighter, only unpredictable.
	return Color(base.r * TINT_GAIN, base.g * TINT_GAIN, base.b * TINT_GAIN, 1.0)


func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D


## The lines and the packets on them. Drawn from this controller rather than as nodes because both
## are recomputed every frame from positions that are already here — a `Line2D` per edge would be a
## second copy of the ring's geometry, free to disagree with the one that decides damage.
##
## A CanvasItem draws itself before its children, so this lands under the nodes: the bodies stay
## readable as the things to shoot rather than being crossed out by their own wiring.
func _draw() -> void:
	if _is_dead:
		return
	var living := _living_slots()
	var edges := _edge_count(living.size())
	for index: int in edges:
		var from := to_local(_nodes[living[index]].global_position)
		var to := to_local(_nodes[living[(index + 1) % living.size()]].global_position)
		draw_line(from, to, config.line_color, 1.0)
		draw_circle(
			from.lerp(to, _packet_progress[index]), config.packet_radius, config.packet_color
		)
