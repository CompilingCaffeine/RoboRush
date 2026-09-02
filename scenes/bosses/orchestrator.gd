class_name Orchestrator
extends Boss
## Cloud Operations' boss: one instance that will not stay in one place, and is only vulnerable in
## the moment after it lands.
##
## Named for the thing that decides where a workload runs, not for what it does — the move it makes
## is a failover, and the game already has an *item* called Failover (a death save). Two things with
## one name would collide in a run's records and put the same word in the HUD for a boss banner and
## a pickup banner, which is the specific confusion `BossEncounter` was created to stop.
##
## The three bosses before this ask the player to **notice** (The Scrap King), to **predict**
## (Runtime Error), and to **keep moving** (Cascade Failure). This one asks them to **be somewhere
## first** — which is the only thing Cloud Operations has been teaching since its start room, and it
## asks in the floor's own words. The boss migrates. That is the same verb the player has spent nine
## rooms performing on the pads, done by the thing they are fighting.
##
## ## The cycle
##
## Four beats, and the fight is nothing but these four on repeat.
##
## 1. **Sealed.** It sits on a plate and fires. Shots land on it and do nothing at all.
## 2. **Telegraph.** It names the plate it is migrating to and lights it, and the floor starts to
##    go. Every *live* plate brightens; every dark one stays dark; everything that is not a plate
##    ramps toward the discharge colour for `telegraph_seconds`.
## 3. **Resolve.** The load moves, and the floor discharges. **Anything standing off a live plate
##    takes a point.** That is the demand, and it is the whole of the demand: be on a plate.
## 4. **Open.** It lands, holds fire, and is damageable for `cold_start_seconds`. This is the only
##    time in the fight that shooting it means anything.
##
## And one turn on top of the four. **Stand on the plate it is migrating to and the migration is
## denied** — the load has nowhere to go, so the boss stays where it is and is open for
## `denial_open_seconds` instead, which is substantially longer. Any plate keeps you alive; *that*
## plate is worth running for.
##
## ## Why the damage is gated
##
## The worst legal build in this game does about 9.4 times the damage per second the enemies are
## written for (`DiminishingReturns`). Every boss before this one is, in the end, a health bar, and a
## build near that ceiling deletes them — a fine reward for a good run and a poor final exam. Gating
## the damage to a window makes this the one boss whose length is set partly by the player's reading
## of it, and it does that with an honest bar and an honest pool: there is no damage cap, no
## immunity phase that comes and goes on a hidden timer, and no number anywhere that lies.
##
## What it costs is that shots fired at a sealed boss are wasted, so the fight has to say so loudly
## and in three places at once: the body sits in `SEALED_TINT` and goes to `OPEN_TINT` the instant it
## lands, the bar does not move, and a hit while sealed pings dim steel instead of flashing white
## (`BossPart.set_shielded`). The encounter's opening banner states the rule in words before the
## first migration, because this is still the only fight in the game whose answer is not "shoot it".
##
## **This replaced a version that could not be killed by damage at all.** That fight scored itself in
## denials: damage filled a pool, a full pool forced a migration, and only a denial was progress. It
## had two faults that between them made it unplayable. The destination was `(current + 1)` and a
## denial did not move the boss, so standing on the next plate round the ring denied every migration
## from a standstill and the race the whole design rested on never had to happen once. And a player
## who did not find that stood in a room where damage moved nothing visible, nothing happened unless
## they shot, and no clock ran — so there was no fight to read at all. The plates, the migration and
## the denial survive here; what they are worth has changed.
##
## ## Why the destination is the furthest live plate
##
## It is chosen when the telegraph starts, from the live plates, as **the one furthest from the
## player** — and it never changes after it is announced.
##
## Furthest is what makes the race real. Any deterministic rule that ignores the player can be
## camped, which is exactly how the previous fight died: whatever plate the boss would name next, the
## player could already be standing on it. Choosing the plate the player is least able to reach means
## the denial always has to be earned from wherever they happen to be, and it means the fight quietly
## rewards holding the middle of the arena — from the centre every plate is close, and from a corner
## the far side is a sprint the telegraph may not cover. That is a real positional decision, made
## with a rule the player can state.
##
## Locking it at announcement is the other half. A boss that re-picked on resolution would make the
## run across the room pointless and would do it invisibly, which is the one failure mode nobody
## could report. `tests/test_orchestrator.gd` pins it.
##
## ## Why plates go dark
##
## The escalation is spent on the arena, not on the boss. Its damage, its fire rate and the time it
## gives you never move; what moves is how much ground answers a migration —
## `live_plates_by_phase` takes it from five islands to three to two. The last phase is a room with
## two safe squares in it, one of which is the destination, and the player choosing between
## surviving and denying is the fight's closing argument.
##
## The live set never includes the plate the boss is standing on, so "every plate but the one it is
## on" is the opening rule and the shrink is a departure from something already learned. It rotates
## each cycle so the answer is read rather than memorised, and it is fixed the moment the boss lands
## — a whole open window and a whole dwell before the telegraph that spends it, so nothing ever goes
## dark under a player's feet.
##
## ## Not a floor-number conditional anywhere
##
## Worth saying because it is the gate this floor exists to pass. This boss is listed in a
## `boss_pool` like the other three, drawn by the same `_draw_boss_encounter`, and it is eligible on
## every floor — a run can meet it on the Help Desk. It reads nothing about which floor it is on. Its
## plates are its own, drawn by this script rather than taken from the room, so it does not require
## the arena to have pads in it and does not break in an arena that has none.

const PART_SCENE := preload("res://scenes/bosses/orchestrator_core.tscn")

## Keeps the body and the plates off the walls, so neither is ever half outside the arena.
const ARENA_INSET := 26.0

## The player's chassis radius, for deciding whether they are standing on a plate. The same five
## pixels `ThermalZone` uses, and — unlike `MigrationPad`, which deliberately does not add it — it
## *is* added here. A pad is a route and should not move a robot that has not committed; a plate is
## shelter, and shelter should be granted to a robot that is clearly on it.
const PLAYER_RADIUS := 5.0

## The plate colours: a live plate, and a plate that has gone dark.
##
## The live one is the same spring green `MigrationPad` draws itself in, because it is the same idea
## and the player has been reading it all floor. The dark one is deliberately not a dimmer green —
## a plate that is off is not a plate that is quieter, it is a different thing, and a player glancing
## at the floor mid-sprint has to be able to tell them apart without comparing brightnesses.
const PLATE_COLOR := Color(0.35, 0.92, 0.58)
const PLATE_DARK_COLOR := Color(0.44, 0.47, 0.52)

## A live plate at rest, and a live plate under a telegraph. It climbs, because by the language of
## three floors a brightening rectangle is a countdown — and here what it is counting down to is the
## moment this square is the only ground worth being on.
const PLATE_IDLE_ALPHA := 0.22
const PLATE_SAFE_ALPHA := 0.62

## A dark plate. Visible, because the player needs to see that it is there and off rather than
## wonder whether they have miscounted, and dim, because it is not an offer.
const PLATE_DARK_ALPHA := 0.16

## How bright the plate the boss is standing on sits. Between the two live values, so "this is where
## it is" and "this is where it is going" are never confusable at a glance.
const PLATE_LIVE_ALPHA := 0.42

## Where the destination plate's ramp starts, and it is above `PLATE_SAFE_ALPHA` on purpose: the
## plate a migration is heading for has to be the brightest thing on the floor from the frame it is
## named, not from the frame it happens to overtake the others.
const PLATE_TARGET_MIN_ALPHA := 0.70
const PLATE_HOT_ALPHA := 1.0

## The floor between the plates while a migration is coming, and what it reaches at the discharge.
##
## A red the game does not otherwise use, and it carries its meaning by *shape* rather than by hue —
## this is the whole arena at once, which is nothing a compile lane or a thermal zone has ever
## looked like. That matters because this boss is eligible on every floor: a wash borrowing
## Development's amber or the Data Center's violet would be claiming to be a hazard the player
## already knows how to answer, and the answer to this one is different.
const FLOOR_COLOR := Color(0.94, 0.28, 0.31)
const FLOOR_HOT_ALPHA := 0.26
const BLAST_ALPHA := 0.5

## How long the discharge stays painted. The same 0.18 seconds a thermal zone's vent flash lasts, so
## two things that both mean "this ground just cost you" last the same time.
const BLAST_FLASH_SECONDS := 0.18

## The body sealed, and the body open.
##
## `modulate` multiplies, so the sealed colour genuinely darkens and cools the sprite — which is the
## correct read for a machine that is closed, and is the one time in this project a boss is allowed
## to go dim. The open colour runs past one in red so that landing is a visible *brightening* rather
## than a hue change, which is what has to survive being seen out of the corner of an eye by a player
## who is still running.
const SEALED_TINT := Color(0.58, 0.68, 0.82, 1.0)
const OPEN_TINT := Color(1.4, 0.92, 0.45, 1.0)

## Numbered from one, like every other boss in this game, because two systems index off the
## number rather than off the enum: `CombatHUD._on_boss_phase_changed` shows
## `phase_banners[phase - 1]`, and `FeedbackDirector._on_boss_phase_changed` treats `phase > 1`
## as "not the opening beat" — the sting, the shake, and the boss music coming back.
enum Phase { NOMINAL = 1, DEGRADED = 2, LAST_INSTANCE = 3 }

@export var config: OrchestratorConfig

## The live body. One, always. Freed only on death.
var _part: BossPart

var _health := 0.0
var _is_dead := false
var _phase := Phase.NOMINAL

## Whether `begin` has run. The cycle must not turn before it has.
##
## A boss is added to the arena and *then* told where it is fighting, so there are physics frames in
## between — one in this project's own harness, and however many a floor takes to finish building a
## room. Without this the dwell clock, which starts at zero, expires on the first of them and the
## fight announces a migration to a plate that does not exist yet: `_plates` is empty, `_next_plate`
## falls back to the plate it is standing on, and `begin` then sets the arena up underneath a
## telegraph already in progress. The result is a first migration that targets the boss's own square
## and can be neither sheltered from nor denied.
##
## The other three bosses survive the same gap by accident rather than by design — Cascade Failure's
## ring steps over an empty node array, Runtime Error's lanes need a rect they have not got — which
## is why this is a flag and not a convention.
var _begun := false

## Which plate the boss is standing on, and which one it is migrating to. `-1` for no target, which
## is also how "not currently telegraphing" is expressed — there is no separate flag, because two
## pieces of state saying the same thing is two pieces of state that can disagree.
var _plate := 0
var _target := -1

## The plates that count as shelter this cycle. Never contains `_plate`; see the class doc.
var _live: PackedInt32Array = PackedInt32Array()

## Advances every cycle, so which plates are live rotates around the ring rather than being the same
## squares every time. The pattern is fixed and the members are not, which is the difference between
## a fight that is read and a fight that is memorised.
var _live_offset := 0

## The three clocks, exactly one of which is running at a time. Sealed is the state with no clock of
## its own — it is `_dwell_left` counting down with no target named yet.
var _open_left := 0.0
var _dwell_left := 0.0
var _telegraph_left := 0.0

var _blast_left := 0.0
var _volley_left := 0.0

var _arena: Rect2
var _body_bounds: Rect2
var _plates: Array[Vector2] = []
var _player: Node2D


func _ready() -> void:
	assert(config != null, "Orchestrator.config is unset: assign an OrchestratorConfig.")
	_health = config.max_health


func begin(arena: Rect2) -> void:
	_arena = arena
	_body_bounds = arena.grow(-ARENA_INSET)
	_plates = _plate_positions()

	_part = PART_SCENE.instantiate()
	add_child(_part)
	# After `add_child`, always. `global_position` on a parentless node is only its local position,
	# which would put the body at that offset from this controller instead of in the arena — the
	# lesson `MergeConflict._spawn_part` paid for and `ThermalZone.spawn` paid for again.
	_part.global_position = _plates[_plate]
	_part.took_damage.connect(_on_part_damaged)

	_refresh_live_plates()
	_seal()
	_begun = true
	# A full dwell before the first migration, so the opening beat of the fight is the boss standing
	# there being looked at with the live plates already lit. Every boss in this game gets that beat,
	# and this one needs it most: the player has to see what a live plate looks like before they are
	# asked to find one.
	EventBus.boss_phase_changed.emit(int(_phase))
	_announce_health()


func _physics_process(delta: float) -> void:
	if _is_dead or not _begun:
		return
	_player = _find_player()
	_blast_left = maxf(_blast_left - delta, 0.0)

	# Every frame rather than on each transition, for the reason `RuntimeError` also re-tints per
	# frame: `BossPart.set_tint` declines while the hurt flash is up, so a tint written on the frame
	# damage landed is precisely the one that gets dropped.
	_refresh_tint()

	if _open_left > 0.0:
		# Open: holding fire, taking damage. Nothing else in the fight runs.
		_open_left -= delta
		if _open_left <= 0.0:
			_open_left = 0.0
			_seal()
	elif is_telegraphing():
		_step_telegraph(delta)
		_step_volleys(delta)
	else:
		_dwell_left -= delta
		if _dwell_left <= 0.0:
			_begin_migration()
		_step_volleys(delta)

	queue_redraw()


# --- State --------------------------------------------------------------------


func get_phase() -> Phase:
	return _phase


func get_health() -> float:
	return _health


## Honest, like `RuntimeError`'s and `CascadeFailure`'s: it falls once, monotonically, and reaching
## zero means the fight is over.
##
## The version of this fight that shipped first reported *generations left* here, because damage
## could not kill it — and before that it folded a damage pool into the segment between generations,
## which drained a third of the bar under fire and put it straight back on a missed failover. A bar
## that refills under damage is the universal sign for a heal, and it was reported in exactly those
## words. There is nothing left for a bar to lie about: this is the pool, it only goes down, and the
## only thing gating it is a window the body's own colour announces.
func get_health_ratio() -> float:
	return _health / maxf(config.max_health, 0.001)


## Whether damage lands right now. The whole of the fight's damage protocol is this one flag.
func is_open() -> bool:
	return _open_left > 0.0


func is_telegraphing() -> bool:
	return _target >= 0


## Which plate the boss is standing on.
func get_plate() -> int:
	return _plate


## Which plate it is migrating to, or -1 when it is not migrating.
func get_target_plate() -> int:
	return _target


## The plates that count as shelter when the next migration resolves. Never includes `get_plate()`.
func get_live_plates() -> PackedInt32Array:
	return _live.duplicate()


func is_plate_live(index: int) -> bool:
	return _live.has(index)


## How many plates stay live in `phase`, from the config, clamped to something the ring can actually
## supply. One is the floor rather than zero: a migration with no shelter anywhere is a hit the
## player cannot avoid, which is the one thing this fight must never produce.
func get_live_count_for(phase: int) -> int:
	var wanted := 1
	var index := phase - 1
	if index >= 0 and index < config.live_plates_by_phase.size():
		wanted = config.live_plates_by_phase[index]
	return clampi(wanted, 1, maxi(_plates.size() - 1, 1))


## Where each plate is, in global coordinates. For the suite and for anything that wants to draw one.
func get_plate_positions() -> Array[Vector2]:
	return _plates.duplicate()


## The square a plate covers, in global coordinates.
func get_plate_rect(index: int) -> Rect2:
	if index < 0 or index >= _plates.size():
		return Rect2()
	var side := config.plate_size
	return Rect2(_plates[index] - Vector2(side, side) * 0.5, Vector2(side, side))


## Whether a robot at `where` is standing on ground that survives a discharge.
##
## Public because it is the fight's one rule, and a rule the suite should be able to ask about
## directly rather than infer from who took damage.
func is_on_safe_ground(where: Vector2) -> bool:
	for index: int in _live:
		if get_plate_rect(index).grow(PLAYER_RADIUS).has_point(where):
			return true
	return false


func get_parts() -> Array[BossPart]:
	var out: Array[BossPart] = []
	if is_instance_valid(_part):
		out.append(_part)
	return out


# --- Damage -------------------------------------------------------------------


## Damage lands only while it is open, and is discarded outright otherwise.
##
## Discarded rather than banked: a shot fired at a sealed boss is gone, which is what the body's
## colour, the still bar and the steel-coloured ping all say it is. Banking it would make every one
## of those three tells a lie, and would quietly restore the fight this one replaced — damage that
## does something eventually, at a moment the player cannot see coming.
func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead or not is_open():
		return

	_health = maxf(_health - info.amount, 0.0)
	EventBus.enemy_damaged.emit(self, DamageInfo.new(info.amount, info.source), _health)
	_announce_health()

	if _health <= 0.0:
		_die()
		return
	_advance_phase()


## Moves the phase to match the pool, and re-reads the floor if it changed.
##
## Refreshing the live set here is safe for one reason worth stating, because it is the reason it is
## allowed at all: damage only lands while the boss is open, and the boss is only open immediately
## after it lands — a whole open window and a whole dwell before the next telegraph. So a plate can
## never go dark during a telegraph, and never under the feet of a player who has already committed
## to it. `_refresh_live_plates` is called from exactly two places, and both are before a telegraph
## rather than inside one.
func _advance_phase() -> void:
	var ratio := get_health_ratio()
	var next := Phase.NOMINAL
	if ratio <= config.phase_three_at:
		next = Phase.LAST_INSTANCE
	elif ratio <= config.phase_two_at:
		next = Phase.DEGRADED
	if next == _phase:
		return
	_phase = next
	_refresh_live_plates()
	EventBus.boss_phase_changed.emit(int(_phase))


func _die() -> void:
	_is_dead = true
	_target = -1
	_open_left = 0.0
	var where := _body_bounds.get_center()
	if is_instance_valid(_part):
		where = _part.global_position
		_part.queue_free()
	_part = null
	# `_physics_process` returns on `_is_dead`, so without this the last lit plate and the last of
	# the floor wash would stay painted on an arena with no boss in it — the same reason
	# `CascadeFailure._die` redraws.
	queue_redraw()
	EventBus.enemy_killed.emit(self, where)
	EventBus.boss_defeated.emit(self)


# --- The cycle ----------------------------------------------------------------


## Closes the boss and starts the dwell. The state the fight spends most of its time in.
func _seal() -> void:
	_dwell_left = config.dwell_seconds
	_volley_left = config.volley_interval
	if is_instance_valid(_part):
		_part.set_shielded(true)


## Opens it for `seconds`, and re-reads the floor for the cycle that follows.
##
## The live set is chosen here — at the *start* of the open window — rather than when the telegraph
## begins, which gives the player the whole window and the whole dwell to see which plates they have
## before anything asks them to be on one.
func _open_for(seconds: float) -> void:
	_open_left = seconds
	_live_offset += 1
	_refresh_live_plates()
	if is_instance_valid(_part):
		_part.set_shielded(false)


func _begin_migration() -> void:
	_dwell_left = 0.0
	_target = _next_plate()
	_telegraph_left = config.telegraph_seconds
	# Faster fire from the moment it is announced, so crossing the room costs something.
	_volley_left = minf(_volley_left, config.telegraph_volley_interval)


func _step_telegraph(delta: float) -> void:
	_telegraph_left -= delta
	if _telegraph_left > 0.0:
		return
	_resolve_migration()


## The load moves and the floor discharges.
##
## The order matters and is the fight's fairness in three lines. The discharge is measured against
## the live set *before* the boss moves, because that is the set the player has been looking at for
## the whole telegraph. And the denial is decided from the same frame's positions, so a player on
## the destination is by definition on a live plate — a denied migration can never also cost them a
## point, which would be the fight punishing its own best outcome.
func _resolve_migration() -> void:
	var plate := _target
	var denied := _player != null and _player_is_on(plate)
	_target = -1
	_telegraph_left = 0.0
	_blast_left = BLAST_FLASH_SECONDS

	_discharge_floor()

	if denied:
		_deny()
	else:
		_land_on(plate)


## One point to anything standing off every live plate. The demand, and the whole of the demand.
func _discharge_floor() -> void:
	if _player == null or is_on_safe_ground(_player.global_position):
		return
	var health := HealthComponent.find_on(_player)
	if health == null:
		return
	# Away from the body, so the shove reads as coming from the thing that did it. No knockback
	# figure is passed: the discharge is the whole floor at once and has no direction to throw a
	# robot in, and being shoved off the plate you were sprinting for would be the fight taking the
	# point twice.
	var origin := _part.global_position if is_instance_valid(_part) else _body_bounds.get_center()
	var offset := _player.global_position - origin
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
	health.apply_damage(DamageInfo.new(config.off_plate_damage, self, direction))


## The player was standing on the destination. The load has nowhere to go, so it stays where it is.
func _deny() -> void:
	_open_for(config.denial_open_seconds)
	AudioManager.play_sfx(&"boss_phase")


## Nobody was there. It arrives, and opens.
func _land_on(plate_index: int) -> void:
	_plate = plate_index
	if is_instance_valid(_part):
		_part.global_position = _plates[_plate]
	_open_for(config.cold_start_seconds)
	AudioManager.play_sfx(&"migrate", 0.04)


## Which plate to migrate to: the live one furthest from the player.
##
## See the class doc for why furthest, and why it is decided here — at the start of the telegraph —
## rather than when the telegraph ends. `_live` never contains `_plate`, so this can never name the
## plate the boss is already on.
func _next_plate() -> int:
	if _live.is_empty():
		return _plate
	if _player == null:
		return _live[0]
	var best := _live[0]
	var best_distance := -1.0
	for index: int in _live:
		var distance := _player.global_position.distance_squared_to(_plates[index])
		if distance > best_distance:
			best_distance = distance
			best = index
	return best


## Picks this cycle's shelter: `get_live_count_for` plates, spread as evenly as the ring allows,
## drawn from every plate *except* the one the boss is on and rotated by `_live_offset`.
##
## Spread evenly rather than taken consecutively, and that is what keeps the last phase answerable.
## Two live plates chosen at random could both land on the same side of a 416x192 room, which is a
## migration a player in the far corner cannot reach. Striding through the candidates puts them
## roughly opposite instead, so the worst point in the arena is 225 pixels from shelter rather than
## most of the room's width. `tests/test_orchestrator.gd` recomputes that figure over every boss
## plate and every rotation rather than trusting this comment.
func _refresh_live_plates() -> void:
	var count := _plates.size()
	_live = PackedInt32Array()
	if count <= 1:
		return

	# Every plate but the boss's, in ring order starting from the one after it.
	var candidates: PackedInt32Array = PackedInt32Array()
	for step: int in count - 1:
		candidates.append((_plate + 1 + step) % count)

	var span := candidates.size()
	var wanted := clampi(get_live_count_for(int(_phase)), 1, span)
	for slot: int in wanted:
		_live.append(candidates[(_live_offset + slot * span / wanted) % span])


func _player_is_on(plate_index: int) -> bool:
	if _player == null:
		return false
	return get_plate_rect(plate_index).grow(PLAYER_RADIUS).has_point(_player.global_position)


# --- Attacks ------------------------------------------------------------------


func _step_volleys(delta: float) -> void:
	_volley_left -= delta
	if _volley_left > 0.0:
		return
	_volley_left = config.telegraph_volley_interval if is_telegraphing() else config.volley_interval
	_fire_spread()


func _fire_spread() -> void:
	if _player == null or config.shot == null or not is_instance_valid(_part):
		return
	var origin := _part.global_position
	var aim := (_player.global_position - origin).normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT

	var count := maxi(config.spread_count, 1)
	var spread := deg_to_rad(config.spread_degrees)
	var step := spread / float(count) if count > 1 else 0.0
	var start := -spread * 0.5 + step * 0.5
	for index: int in count:
		_spawn(origin, aim.rotated(start + step * float(index)))


func _spawn(origin: Vector2, direction: Vector2) -> void:
	# Deferred, the call every spawner in this project makes: registering a body while the physics
	# server is flushing queries is refused outright.
	ProjectileFactory.spawn_configured(
		self, config.shot.spawn_copy(), direction, origin, Teams.Id.ENEMY, self, [], true
	)


# --- Geometry -----------------------------------------------------------------


## The plates, spread evenly around the arena's centre.
##
## Laid out on an ellipse matched to the arena's own proportions rather than a circle, because a
## 416x192 room is more than twice as wide as it is tall and a circle inside it wastes the width —
## which is the width the player has to cross. `CascadeFailure` places its ring the same way for the
## same reason.
##
## The first plate is at the top, so the layout is the same every fight and a returning player knows
## where all six of them are before the first one lights.
func _plate_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var centre := _body_bounds.get_center()
	var radius := _body_bounds.size * 0.5 * config.plate_radius
	var count := maxi(config.plate_count, 1)
	for index: int in count:
		var angle := -PI * 0.5 + TAU * float(index) / float(count)
		out.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return out


## The body carries the one piece of state the player has to act on: whether shooting it works.
func _refresh_tint() -> void:
	if is_instance_valid(_part):
		_part.set_tint(OPEN_TINT if is_open() else SEALED_TINT)


func _announce_health() -> void:
	EventBus.boss_health_changed.emit(get_health_ratio())


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D


func _draw() -> void:
	# Dead first, and not only for tidiness. `_physics_process` returns on `_is_dead`, so nothing
	# decays `_blast_left` after the fight ends — a boss killed inside the 0.18 seconds its discharge
	# is painted would leave a red wash over an arena the player has just won, permanently. The
	# plates go with it because they are the boss's own rather than the room's.
	if _is_dead or _plates.is_empty():
		return
	_draw_floor()
	for index: int in _plates.size():
		_draw_plate(index)


## The ground between the plates, going hostile.
##
## Drawn under the plates because a CanvasItem draws in call order, so the islands stay legible as
## islands rather than being washed over by the thing they are islands in. Skipped entirely at zero
## alpha, which is most of the fight — the floor is only worth painting while it is about to matter.
func _draw_floor() -> void:
	var alpha := 0.0
	if _blast_left > 0.0:
		alpha = BLAST_ALPHA * (_blast_left / BLAST_FLASH_SECONDS)
	elif is_telegraphing():
		var progress := 1.0 - clampf(
			_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0
		)
		alpha = FLOOR_HOT_ALPHA * progress
	if alpha <= 0.002:
		return
	# Local space: this node sits at the arena's origin only by accident of the scene it was added
	# to, so the arena rect is converted rather than assumed.
	var local := Rect2(_arena.position - global_position, _arena.size)
	draw_rect(local, Color(FLOOR_COLOR.r, FLOOR_COLOR.g, FLOOR_COLOR.b, alpha))


func _draw_plate(index: int) -> void:
	var rect := get_plate_rect(index)
	var local := Rect2(rect.position - global_position, rect.size)

	var colour := PLATE_COLOR
	var alpha := PLATE_IDLE_ALPHA
	# Thicker on the destination, so which plate is being named survives a glance taken while the
	# player is already running and reading the room rather than the rectangle.
	var border := 1.0

	if index == _target:
		# The countdown. Ramps to hot across the telegraph, so the plate is brightest on the frame
		# the migration lands — the same direction of travel as a thermal zone filling, which is the
		# language this floor's player already reads.
		var progress := 1.0 - clampf(
			_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0
		)
		alpha = lerpf(PLATE_TARGET_MIN_ALPHA, PLATE_HOT_ALPHA, progress)
		border = 2.0
	elif not is_plate_live(index):
		# Off. Grey rather than a dim green, because a plate that is off is a different thing rather
		# than a quieter one.
		colour = PLATE_DARK_COLOR
		alpha = PLATE_DARK_ALPHA
	elif index == _plate:
		alpha = PLATE_LIVE_ALPHA
	elif is_telegraphing():
		# The other shelter, brightening alongside the floor it is about to be the only alternative
		# to. Live plates announce themselves during a telegraph for the same reason the destination
		# does: this is the moment the player has to find one.
		var progress := 1.0 - clampf(
			_telegraph_left / maxf(config.telegraph_seconds, 0.001), 0.0, 1.0
		)
		alpha = lerpf(PLATE_IDLE_ALPHA, PLATE_SAFE_ALPHA, progress)

	draw_rect(local, Color(colour.r, colour.g, colour.b, alpha * 0.5))
	draw_rect(local, Color(colour.r, colour.g, colour.b, alpha), false, border)
