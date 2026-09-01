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
## ## Three places heat comes from
##
## The rack vents where its bodies are. It also **aims** — a patch centred on wherever the robot is
## standing, every `aimed_vent_interval` — and it **scatters**, a patch at a random point in the
## arena every `scatter_vent_interval`.
##
## The first of those is what makes the fight's own sentence true. "Keep moving" was the floor's
## lesson and the boss's stated job, and the boss was not actually asking it: heat only ever landed
## on the ring, so a player who found a spot the ring did not sweep could stand in it and shoot. The
## aimed vent removes standing still as an option anywhere in the room, and it removes it the way
## this floor removes things — by painting the ground and counting down, never by landing a hit the
## player could not have walked out of.
##
## The second closes the corners. A 416x192 room has ground the ellipse cannot reach, and heat that
## only ever appears where the boss is or where the player is leaves that ground safe by
## construction. The scatter is weather: it is aimed at nobody, it is read the same way as
## everything else, and it means the answer to this fight is a route rather than a spot.
##
## **Neither of them is divided by load**, and that is deliberate. The whole escalation of this
## fight is the rack concentrating what it already had; two sources that quadrupled alongside it
## would make the last phase a different, worse fight — four times the aimed heat on a player with
## one body left to shoot. So the rack's own heat concentrates and these two stay flat, which keeps
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
## it, and *keep moving* would stop being a rhythm and become the only input. The scatter stays
## flat throughout: it is weather, and weather does not care which node just went.
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

## Seconds until the rack aims at the player again, and until it scatters again. One clock each for
## the whole rack rather than one per node, because neither is a thing a *node* does — they are the
## room being run too hot, and they go on at the same rate whether four bodies are doing it or one.
var _aimed_left := 0.0
var _scatter_left := 0.0


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

	# A full interval before the first aimed vent and half of one before the first scatter, so the
	# opening seconds of the fight are the rack introducing itself. A patch appearing under the
	# player on the frame they walked in would be the fight's fairest mechanic read as its cheapest.
	_aimed_left = config.aimed_vent_interval
	_scatter_left = config.scatter_vent_interval * 0.5

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
func _step_runaway(delta: float, living: Array[int]) -> void:
	if living.is_empty() or _player == null:
		return
	var node := _nodes[living[0]]
	node.global_position = node.global_position.move_toward(
		_player.global_position, config.runaway_speed * node.get_status_speed_scale() * delta
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


## The three sources, in the order the player learns them: the bodies, then themselves, then the
## room. See the class doc for why only the first is scaled by load.
func _step_vents(delta: float) -> void:
	_step_node_vents(delta)
	_step_aimed_vent(delta)
	_step_scatter_vent(delta)


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
func _step_aimed_vent(delta: float) -> void:
	_aimed_left -= delta
	if _aimed_left > 0.0:
		return
	_aimed_left = get_aimed_vent_interval()
	if _player != null:
		_drop_vent(_player.global_position)


## Heat somewhere in the arena, chosen uniformly and aimed at nobody.
##
## Drawn from `_body_bounds` rather than from the whole arena so a scattered patch is a whole patch
## with room around it, the same inset the nodes themselves keep — `_drop_vent` would clamp one at
## the wall anyway, and a clamp is how a uniform draw quietly becomes a pile-up along the edges.
func _step_scatter_vent(delta: float) -> void:
	_scatter_left -= delta
	if _scatter_left > 0.0:
		return
	_scatter_left = maxf(config.scatter_vent_interval, 0.05)
	_drop_vent(Vector2(
		randf_range(_body_bounds.position.x, _body_bounds.end.x),
		randf_range(_body_bounds.position.y, _body_bounds.end.y),
	))


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
