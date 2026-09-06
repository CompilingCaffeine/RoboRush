class_name CoreIntelligence
extends RuntimeError
## The last floor's boss, and the thing that wrote the other five: it fights by **wearing** them.
##
## Every boss before this one asks the player for one thing. The Scrap King asks them to *notice*,
## Runtime Error to *predict*, Cascade Failure to *keep moving*, the Orchestrator to *be somewhere
## first*, and Executive Override asks for all of Runtime Error's again in a longer order. Six
## floors of the campaign are those five sentences and the rooms that teach them. This fight is the
## claim that one machine has been saying all of them — so it says them again, in order, out of one
## health pool, and then says nothing and simply fights.
##
## ## Masks
##
## The pool is cut into five slices, and each slice is a **mask**: a face, a footprint, a rotation
## of attacks, and in two of them a rule that changes what damage is worth.
##
## 1. **The Scrap King.** Two bodies sharing one pool, four terminals in the corners, and a refund
##    on every hit while any of them stands. The answer is the answer it was on Floor 1: stop
##    shooting the boss and go break a terminal.
## 2. **Runtime Error.** The whole lane and projectile vocabulary in one authored rotation — which
##    is also Executive Override's escalation, since that fight *is* this vocabulary in a longer
##    order. The fifth floor's rematch is a mask worn inside the second floor's.
## 3. **Cascade Failure.** Driven throughput zones: the triad, the aimed-and-lead pincer, and a
##    wall of patches with one door in it. Nothing here is random and nothing here is new — the
##    player read all three colours on Floor 3.
## 4. **The Orchestrator.** It seals, names ground, discharges the floor, and migrates. Damage
##    counts only in the window after it lands, and standing on the ground it wanted denies the
##    migration and holds it open far longer.
## 5. **Core Intelligence.** No mask, no seal, no refund, no terminals: one body, fully damageable,
##    and one attack borrowed from each of the four above coming faster than any of them did.
##
## ## What is borrowed and what is rebuilt
##
## Nothing here reimplements a hazard. The lanes are `CompileLane`, the zones are `ThermalZone`,
## the terminals are `BossTerminal`, the bodies are `BossPart`, and the numbers that give a mask
## its identity are read off the boss it belongs to wherever one exists — `MergeConflict.RED`,
## `Orchestrator.SEALED_TINT`, `CompileLane.AMBER`. A mask that drifted out of step with the fight
## it quotes would be a callback the player cannot recognise, which is the only way this whole
## design fails.
##
## What *is* rebuilt is the arrangement, and only where the original could not be lifted whole.
## The Orchestrator's four plates around a ring become two cells of the arena grid this fight
## already divides itself into, and its floor discharge is painted as compile lanes rather than
## drawn by hand — which means the discharge owns its own clock, warns in the language the player
## has read for five floors, and still resolves if the boss dies after announcing it. That last
## point is the campaign's rule, held here where it costs the most: **committed attacks resolve,
## uncommitted ones never happen** (see `RuntimeError._die`, and `tests/test_post_boss.gd`).
##
## The Scrap King's feigned death is the one signature deliberately left out. It works exactly once
## per player, it worked on Floor 1, and a fight that fakes its own end is the last thing to put in
## front of a player who has to be able to believe the real one — this floor's ending is a trophy
## on the ground (see `Trophy`), and it must not read as a trick.
##
## ## The one number to keep in mind while tuning
##
## The masks are worth a fifth of the pool each and are not equally cheap to spend. The Scrap King
## refunds most of what it takes until four terminals are down, and the Orchestrator discards
## everything outside its landing window; the other three take damage as fast as the player can
## deal it. That is deliberate — the fight should slow down where the player is being asked a
## question and speed up where they are being asked for execution — but it means the pool is a poor
## guide to the fight's length on its own. `tests/test_core_intelligence.gd` measures the masks
## rather than the bar.

const SCRAP_TEXTURE := preload("res://art/bosses/merge_conflict.png")
const RUNTIME_TEXTURE := preload("res://art/bosses/runtime_error.png")
const CASCADE_TEXTURE := preload("res://art/bosses/cascade_node.png")
const ORCHESTRATOR_TEXTURE := preload("res://art/bosses/orchestrator.png")
const CORE_TEXTURE := preload("res://art/bosses/core_intelligence.png")

const TERMINAL_SCENE := preload("res://scenes/bosses/boss_terminal.tscn")

## Its own colour, worn only by the last mask.
const CORE_TINT := Color(0.82, 0.9, 1.2)

## Cascade Failure's mask, in the Data Center's cold status light rather than in the violet its
## zones go to as they fill. A body the same colour as the hazard it is about to paint would be a
## body the player reads as a warning, and this one is not one.
const CASCADE_TINT := Color(0.62, 1.1, 1.2)

## What each mask's body is worth as a target, matched to the boss it is quoting: the Scrap King's
## 14, Runtime Error's 7, a Cascade node's 8, the Orchestrator's 10, and 9 for its own face.
##
## This is the one thing a mask changes that the player feels without being told. A shapeshifter
## that only swapped textures would be a costume; changing the footprint means the King's mask is
## genuinely easier to hit than Runtime Error's, and that the fight asks for a different aim four
## times before it is over. The collision circle and the contact radius move together with it, so
## what the player shoots at stays the size it looks.
## How far the first mask's two bodies are held apart when it goes on. The mirror is taken through
## the centre of the arena, and a body standing *on* that centre mirrors onto itself — which is a
## clone the player cannot see is two things. The Scrap King solved this on Floor 1 by opening
## twenty pixels above centre; this opens further out, because these two bodies are also each
## other's cover.
const CLONE_SEPARATION := 44.0

const SCRAP_RADIUS := 14.0
const RUNTIME_RADIUS := 7.0
const CASCADE_RADIUS := 8.0
const ORCHESTRATOR_RADIUS := 10.0
const CORE_RADIUS := 9.0

## The masks, in the order the campaign taught them. The values are what the HUD announces as a
## phase, so `BossEncounter.phase_banners` has five lines rather than three.
enum Mask {
	SCRAP_KING = 1,
	RUNTIME_ERROR = 2,
	CASCADE = 3,
	ORCHESTRATOR = 4,
	CORE = 5,
}

## Attacks beyond Runtime Error's six, numbered on from its enum rather than declared in one of
## their own. `_execute` and `_needs_windup` take an `Attack`, and GDScript enums are ints, so
## extending the vocabulary is a matter of not colliding with it — which is exactly what the vent
## attack this fight already had has always done.
const ATTACK_VENTS := 6
const ATTACK_AIMED_VENTS := 7
const ATTACK_VENT_WALL := 8
const ATTACK_MARKERS := 9
const ATTACK_MIGRATE := 10

## Which mask is being worn. The state of this fight, and what `boss_phase_changed` reports.
var _mask := Mask.SCRAP_KING

## Seconds this mask still owes before it may be left. Counted down rather than up so the rotation
## it is measured against is computed once, when the mask goes on, instead of on every hit and every
## frame — and so that "is this mask done" is one comparison. See `_damage_this_mask_may_take`,
## where it decides whether a hit may cross a boundary at all.
var _hold_left := 0.0

## The Scrap King's second body, while that mask is worn, and null every other moment of the
## fight. One pool between the two, as it was on Floor 1: `BossPart` is a receiver that forwards
## its hits, so two bodies cost the controller nothing but a second forward.
var _clone: BossPart

## The terminals raised with the first mask. Emptied as they are destroyed rather than filtered
## later, so a terminal cannot go on refunding damage for the frame after the player broke it.
var _terminals: Array[BossTerminal] = []
var _terminals_remaining := 0

## Counts down the announced floor discharge. Positive only between a migration being announced and
## the lanes striking, which is also the only time the attack clock is held.
var _migrate_left := 0.0

## Counts down the window in which damage counts, in the Orchestrator's mask. Zero the rest of that
## mask, and meaningless in the other four — see `is_open`, which is the reader that knows both.
var _open_left := 0.0

## The cell of the arena grid the boss is migrating to, and the second cell left safe alongside it.
## Both are indices into `_cell_rect`; -1 when no migration has been announced yet.
var _target_cell := -1
var _live_cell := -1


## The first mask goes on here rather than in `_ready`, because it raises terminals and a second
## body and both need the arena `begin` is being handed. The base class has already emitted the
## phase change for `_phase`, which is `SINGLE_LANE` — the same number as `Mask.SCRAP_KING`, and
## the reason `_wear` is asked not to announce this one twice.
func begin(arena: Rect2) -> void:
	super.begin(arena)
	_wear(Mask.SCRAP_KING, false)


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		return
	_step_mask_hold(delta)
	_step_open_window(delta)
	_step_migration(delta)


# --- State --------------------------------------------------------------------


func get_mask() -> Mask:
	return _mask


## True when a hit on the body would count. Always true outside the Orchestrator's mask: no other
## mask discards damage, and a fight that reported itself sealed while it was not would be worse
## than one that never reported it at all.
func is_open() -> bool:
	return _mask != Mask.ORCHESTRATOR or _open_left > 0.0


## True while the two copies are still synchronised and damage is partly refunded — which is the
## Scrap King's rule and, like its rule, is a fact about the terminals rather than about the mask.
func is_synchronised() -> bool:
	return _terminals_remaining > 0


func get_terminal_count() -> int:
	return _terminals_remaining


## The second body, or null. The plural of `get_part`, kept separate from it rather than folded
## into a `get_parts` array: everything in this fight that is not the Scrap King's mask has exactly
## one body, and a fight that returned a list would have every caller checking its length.
func get_clone() -> BossPart:
	return _clone if is_instance_valid(_clone) else null


## Both bodies, or the one there usually is, and never a freed instance.
##
## The candidates are deliberately untyped, which is `MergeConflict.get_parts`'s hard-won detail:
## binding a freed instance to a `BossPart` loop variable makes Godot validate it *before* the loop
## body can check it, which spams "attempted to set an invalid (previously freed?) object instance"
## on every call — a message the player must never see, and one that buried real errors in the test
## output until it was found.
func get_bodies() -> Array[BossPart]:
	var bodies: Array[BossPart] = []
	for candidate: Variant in [_part, _clone]:
		if is_instance_valid(candidate):
			bodies.append(candidate as BossPart)
	return bodies


## The arena grid this fight divides itself into: the checkerboard's cells, reused rather than
## restated. It is already the shape the player reads a board in, and the Orchestrator's mask needs
## somewhere to put its plates — so the plates are checkerboard cells, and the two ideas cannot
## drift into two different grids.
func get_cell_count() -> int:
	return maxi(config.checker_cols, 2) * maxi(config.checker_rows, 2)


func get_cell_rect(index: int) -> Rect2:
	var cols := maxi(config.checker_cols, 2)
	var rows := maxi(config.checker_rows, 2)
	var cell := Vector2(_arena.size.x / float(cols), _arena.size.y / float(rows))
	var wrapped := posmod(index, cols * rows)
	return Rect2(
		_arena.position + Vector2(float(wrapped % cols), float(wrapped / cols)) * cell, cell
	)


## The cells a migration has left safe: where the boss is going, and the one other plate that is
## live while the floor discharges. Empty until the first migration is announced.
func get_safe_cells() -> Array[int]:
	if _target_cell < 0:
		return []
	var cells: Array[int] = [_target_cell, _live_cell]
	return cells


# --- Masks --------------------------------------------------------------------


## Replaces the base class's health-derived phase ladder. Runtime Error changes phase at two
## thresholds; this fight changes *fight* at four, and everything a phase used to decide — the
## rotation, the interval, the tint — is decided by the mask instead.
##
## Derived from the health that is left rather than stepped one at a time, exactly as the base class
## does it — though here the derivation can only ever move one rung, because the floor in
## `_damage_this_mask_may_take` stops the pool crossing more than one boundary at a time. A mask
## cannot be skipped, only waited out.
##
## Which is the opposite of Runtime Error's policy, deliberately. That fight has nothing to protect,
## so a build that deletes two thirds of its pool in one shot has simply won that much of it. This
## one is five fights the player is here to be shown.
func _advance_phase() -> void:
	if _hold_left > 0.0:
		return
	var next := _mask_for_ratio(get_health_ratio())
	if next != _mask:
		_wear(next)


## How long a mask is worn for at minimum: one complete rotation of its own attacks, computed from
## the rotation rather than written down, so a mask that gains a command gains the time to show it.
##
## The Orchestrator's mask is the exception, and it has to be. Its migration stops the attack clock
## for the telegraph and the landing window, so a rotation's worth of *interval* is a good deal less
## than a rotation's worth of fight — and a build that emptied the slice during the window this mask
## opens on would be released before the first migration ever resolved, having seen the seal and
## none of what it is for. Those two spans are added on, which makes the mask's minimum one whole
## cycle: seal, discharge, land or be denied, window.
func _hold_seconds() -> float:
	var rotation := float(_attacks_for(_phase).size()) * _interval_for(_phase)
	var tuning := config as CoreIntelligenceConfig
	if _mask != Mask.ORCHESTRATOR or tuning == null:
		return rotation
	return rotation + tuning.migrate_telegraph_seconds + tuning.open_seconds


## Releases the mask once it has been worn for its rotation. Nothing else runs on this clock: the
## boundary was reached long ago in a fast fight, and the mask is simply waiting to be allowed to
## change.
func _step_mask_hold(delta: float) -> void:
	if _hold_left <= 0.0:
		return
	_hold_left = maxf(_hold_left - delta, 0.0)
	if _hold_left <= 0.0:
		_advance_phase()


## The health fraction this mask ends at, and the floor damage is held above until its rotation has
## finished. Zero in the last mask, which is what makes the last mask the one that can be killed in.
func _mask_floor_ratio() -> float:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return 0.0
	match _mask:
		Mask.SCRAP_KING:
			return tuning.runtime_mask_at
		Mask.RUNTIME_ERROR:
			return tuning.cascade_mask_at
		Mask.CASCADE:
			return tuning.orchestrator_mask_at
		Mask.ORCHESTRATOR:
			return tuning.core_mask_at
		_:
			return 0.0


func _mask_for_ratio(ratio: float) -> Mask:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null or ratio > tuning.runtime_mask_at:
		return Mask.SCRAP_KING
	if ratio > tuning.cascade_mask_at:
		return Mask.RUNTIME_ERROR
	if ratio > tuning.orchestrator_mask_at:
		return Mask.CASCADE
	if ratio > tuning.core_mask_at:
		return Mask.ORCHESTRATOR
	return Mask.CORE


## Puts a mask on. Everything the previous one brought is taken away first, so no mask can leave
## furniture standing in another one's fight — a terminal still refunding damage two masks later
## would be the single worst bug this fight could have, and it is prevented by there being one
## place that answers "what is on the floor".
##
## The clock is reset the way `RuntimeError._enter_phase` resets it, and for the same two reasons:
## every mask opens on the first attack of its own rotation rather than halfway through the last
## one's, and a windup the previous mask began is abandoned rather than resolving out of a body
## that is no longer the thing that announced it.
func _wear(mask: Mask, announce := true) -> void:
	_shed()
	_mask = mask
	_phase = _base_phase_for(mask)
	_attack_index = 0
	_telegraph_left = 0.0
	_attack_left = _interval_for(_phase)
	_hold_left = _hold_seconds()
	_wear_face(mask)

	match mask:
		Mask.SCRAP_KING:
			_raise_terminals()
			_build_clone()
		Mask.ORCHESTRATOR:
			# It arrives already landed. Sealing a boss the instant the player earned the mask
			# would charge them a full migration for damage they had already dealt.
			_open_for((config as CoreIntelligenceConfig).open_seconds)
		_:
			pass

	if announce:
		EventBus.boss_phase_changed.emit(int(mask))


## Takes down whatever the mask being left had standing. Uncommitted furniture only: the lanes,
## zones and projectiles a mask painted are committed hazards that belong to the arena now, and
## they resolve on their own clocks whether or not the thing that painted them is still wearing
## the face that did.
func _shed() -> void:
	_clear_terminals()
	_clear_clone()
	_migrate_left = 0.0
	_open_left = 0.0
	_target_cell = -1
	_live_cell = -1
	if is_instance_valid(_part):
		_part.set_shielded(false)


## Which of Runtime Error's phases a mask draws its lane geometry from. Not a second ladder: the
## base class reads `_phase` when it wants a rotation or an interval, both of which are overridden
## here, so this decides nothing except what `get_phase` reports to anything still asking a
## `RuntimeError` question of this boss.
func _base_phase_for(mask: Mask) -> Phase:
	match mask:
		Mask.SCRAP_KING:
			return Phase.SINGLE_LANE
		Mask.RUNTIME_ERROR:
			return Phase.STAGGERED_LANES
		Mask.CASCADE:
			return Phase.SINGLE_LANE
		_:
			return Phase.CHECKERBOARD


## The face, the footprint, and the colour, applied to every body this mask has.
func _wear_face(mask: Mask) -> void:
	var texture := _texture_for(mask)
	var radius := _radius_for(mask)
	for part: BossPart in get_bodies():
		part.get_sprite().texture = texture
		_resize(part, radius)
	_restore_tint()


func _texture_for(mask: Mask) -> Texture2D:
	match mask:
		Mask.SCRAP_KING:
			return SCRAP_TEXTURE
		Mask.RUNTIME_ERROR:
			return RUNTIME_TEXTURE
		Mask.CASCADE:
			return CASCADE_TEXTURE
		Mask.ORCHESTRATOR:
			return ORCHESTRATOR_TEXTURE
		_:
			return CORE_TEXTURE


func _radius_for(mask: Mask) -> float:
	match mask:
		Mask.SCRAP_KING:
			return SCRAP_RADIUS
		Mask.RUNTIME_ERROR:
			return RUNTIME_RADIUS
		Mask.CASCADE:
			return CASCADE_RADIUS
		Mask.ORCHESTRATOR:
			return ORCHESTRATOR_RADIUS
		_:
			return CORE_RADIUS


## Resizes one body to the mask it is wearing: the circle a projectile finds, and the circle that
## hurts to stand in, which are deliberately the same number.
##
## The shape is duplicated before its radius is written, for `Recursion._resize_body`'s reason: a
## `[sub_resource]` in a scene is shared by every instance that scene produces, so writing the
## radius directly would resize the *clone* as well — and, worse, would leave the last mask's
## radius baked into the next boss instantiated from `runtime_error_part.tscn`.
func _resize(part: BossPart, radius: float) -> void:
	part.contact_radius = radius
	var shape := part.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		return
	var circle := shape.shape as CircleShape2D
	if circle == null:
		return
	var own := circle.duplicate() as CircleShape2D
	own.radius = radius
	shape.shape = own


## The mask's colour, and the Orchestrator's two. Read off the bosses being quoted wherever they
## have one to read: a mask the player cannot place is a mask that is not doing its job.
func _restore_tint() -> void:
	var tint := _mask_tint()
	for part: BossPart in get_bodies():
		part.set_tint(tint)


func _mask_tint() -> Color:
	match _mask:
		Mask.SCRAP_KING:
			return MergeConflict.RED
		Mask.RUNTIME_ERROR:
			return BODY_TINT
		Mask.CASCADE:
			return CASCADE_TINT
		Mask.ORCHESTRATOR:
			return Orchestrator.OPEN_TINT if is_open() else Orchestrator.SEALED_TINT
		_:
			return CORE_TINT


# --- Rotations ----------------------------------------------------------------


## Which attacks are in rotation, by mask rather than by the phase the base class passes in. The
## argument is Runtime Error's idea of where the fight is, and this fight derives that from its
## mask rather than the other way round — see `_base_phase_for`.
##
## Every rotation is authored and strictly ordered, which is README's rule and not a stylistic
## preference: random combinations are allowed only once authored ones have proved they cannot
## erase every safe route, and five masks is five times as many chances to prove otherwise.
func _attacks_for(_phase_ignored: Phase) -> Array[int]:
	match _mask:
		Mask.SCRAP_KING:
			# Two bodies firing spreads, markers falling between them, and a ring to move the
			# player off whichever terminal they have settled in front of.
			return [Attack.SPREAD, ATTACK_MARKERS, Attack.RING]
		Mask.RUNTIME_ERROR:
			# The whole Floor 2 vocabulary in one order — which is Executive Override's escalation
			# exactly: "a longer order of familiar commands, not simultaneous random patterns".
			return [
				Attack.LANE,
				Attack.SPREAD,
				Attack.TWIN_LANES,
				Attack.RING,
				Attack.CHECKERBOARD,
				Attack.WALL,
			]
		Mask.CASCADE:
			# The triad, the pincer, the wall. Floor 3's three ways of asking for a turn.
			return [ATTACK_VENTS, ATTACK_AIMED_VENTS, ATTACK_VENT_WALL]
		Mask.ORCHESTRATOR:
			# One migration, then two things to survive while it is sealed again.
			return [ATTACK_MIGRATE, Attack.SPREAD, Attack.RING]
		_:
			# Its own: one command from each mask it has taken off, in the order it wore them,
			# and then the checkerboard it has been building toward since the second floor.
			return [
				ATTACK_MARKERS,
				Attack.TWIN_LANES,
				ATTACK_AIMED_VENTS,
				Attack.RING,
				ATTACK_VENT_WALL,
				Attack.CHECKERBOARD,
			]


func _interval_for(_phase_ignored: Phase) -> float:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return 2.0
	match _mask:
		Mask.SCRAP_KING:
			return tuning.scrap_interval
		Mask.RUNTIME_ERROR:
			return tuning.runtime_interval
		Mask.CASCADE:
			return tuning.cascade_interval
		Mask.ORCHESTRATOR:
			return tuning.orchestrator_interval
		_:
			return tuning.core_interval


## True for the attacks that have no warning of their own, which is the base class's rule applied
## to four more attacks. The thermal patches announce themselves cold-to-violet, and a migration
## paints the floor it is about to discharge — a body windup in front of either would only delay
## the warning the player is meant to read. Falling markers have nothing but the body.
func _needs_windup(attack: Attack) -> bool:
	match int(attack):
		ATTACK_VENTS, ATTACK_AIMED_VENTS, ATTACK_VENT_WALL, ATTACK_MIGRATE:
			return false
		ATTACK_MARKERS:
			return true
		_:
			return super(attack)


## The four attacks this fight adds, and the base class's six underneath. A migration leaves
## through its own door: it seals the body, which is a louder statement than a flash, and it owns
## the attack clock until it has resolved.
func _execute(attack: Attack) -> void:
	if int(attack) == ATTACK_MIGRATE:
		_begin_migration()
		return

	var flash := CompileLane.RED
	match int(attack):
		ATTACK_VENTS:
			_fire_vents()
			flash = ThermalZone.HOT_COLOR
		ATTACK_AIMED_VENTS:
			_fire_aimed_vents()
			flash = ThermalZone.HOT_COLOR
		ATTACK_VENT_WALL:
			_fire_vent_wall()
			flash = ThermalZone.HOT_COLOR
		ATTACK_MARKERS:
			_fire_markers()
		_:
			super(attack)
			return

	_attack_left = _interval_for(_phase)
	_flash_left = STRIKE_FLASH_SECONDS
	if is_instance_valid(_part):
		_part.set_tint(_warning_tint(flash))


## Held while a migration is resolving or a landing window is open, which is the whole of how the
## Orchestrator's mask keeps its shape: the fight during those seconds is the floor and the window,
## and a spread arriving in the middle of them would be a second thing to read at the one moment
## the mask is asking for a single decision.
func _step_attacks(delta: float) -> void:
	if _migrate_left > 0.0 or _open_left > 0.0:
		return
	super(delta)


# --- Damage -------------------------------------------------------------------


## The two rules the masks add to an otherwise unmodified damage path.
##
## Sealed, nothing counts at all — and the player is told so on the body they are shooting rather
## than only by a bar that does not move (`BossPart.set_shielded`). Synchronised, most of it is
## refunded, which is The Scrap King's rule and has The Scrap King's answer: the terminals are
## standing in the corners, and they are what to shoot instead.
##
## Everything else — the pool, the mask ladder, the death — is the base class's, so there is still
## exactly one place this fight can end.
func _on_part_damaged(info: DamageInfo) -> void:
	if _is_dead:
		return
	if not is_open():
		return

	var amount := info.amount
	if is_synchronised():
		amount *= 1.0 - clampf((config as CoreIntelligenceConfig).synchronised_refund, 0.0, 1.0)
	amount = minf(amount, _damage_this_mask_may_take())
	super(DamageInfo.new(amount, info.source, info.direction, info.knockback))


## What is left of this mask's slice of the pool, while the mask still owes the player its rotation,
## and everything otherwise.
##
## This is the one rule in the fight that a good build feels rather than reads, and it is The Scrap
## King's own device: that fight floors damage at each boundary, "because a build strong enough to
## skip a phase would skip the feigned death that is the point of that fight". This fight is five
## fights, and the same argument is five times as strong. Measured against the worst legal build —
## about 9.4 times the damage the enemies are written for — a 300-integrity pool with nothing
## holding it is a finale that is over in seven seconds, having shown the player one of the five
## bosses it exists to bring back.
##
## What it is not is a damage cap, an immunity phase, or a bar that lies. Every point above the
## boundary lands, the bar reports exactly where the pool is, and the mask changes the moment its
## rotation is done — so a player who deleted the slice waits out the rest of one rotation rather
## than being made to fight it. And the last mask has no floor at all, because a fight that is
## ending should end.
func _damage_this_mask_may_take() -> float:
	if _hold_left <= 0.0:
		return INF
	return maxf(_health - config.max_health * _mask_floor_ratio(), 0.0)


## Everything the last mask had standing goes with the fight. What it had already *painted* does
## not: a lane on the floor, a zone filling, and a volley in flight are committed hazards that go
## on to resolve in an arena the player has apparently just won, which is the campaign's rule and
## is held hardest here — this is the arena the trophy is standing in.
func _die() -> void:
	_shed()
	super()


# --- The Scrap King's mask ----------------------------------------------------


## Four terminals, one per corner of the body's own bounds. Corners because they are the furthest
## thing from wherever the boss is, so breaking one always means leaving the fight — `MergeConflict`
## made that choice on Floor 1 and this mask is quoting it, not revisiting it.
func _raise_terminals() -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	var corners: Array[Vector2] = [
		_body_bounds.position,
		Vector2(_body_bounds.end.x, _body_bounds.position.y),
		Vector2(_body_bounds.position.x, _body_bounds.end.y),
		_body_bounds.end,
	]
	for index: int in mini(maxi(tuning.terminal_count, 0), corners.size()):
		var terminal: BossTerminal = TERMINAL_SCENE.instantiate()
		add_child(terminal)
		# After `add_child`, always. See `RuntimeError.begin`, which paid for this lesson second.
		terminal.global_position = corners[index]
		terminal.configure(tuning.terminal_health)
		terminal.destroyed.connect(_on_terminal_destroyed)
		_terminals.append(terminal)
	_terminals_remaining = _terminals.size()


## Dropped from the list the instant it dies rather than left for `is_instance_valid` to notice
## next frame: `queue_free` lands at the end of the frame, and a terminal that went on refunding
## damage after the player destroyed it is a refund they have already paid for.
func _on_terminal_destroyed(terminal: BossTerminal) -> void:
	_terminals.erase(terminal)
	_terminals_remaining = _terminals.size()


func _clear_terminals() -> void:
	for terminal: BossTerminal in _terminals:
		if is_instance_valid(terminal):
			terminal.queue_free()
	_terminals.clear()
	_terminals_remaining = 0


## The second body, mirrored across the centre of the arena from the first. Same scene, same
## forwarding, same pool: `BossPart` exists precisely so that a boss can have two bodies without
## having two health bars.
func _build_clone() -> void:
	if is_instance_valid(_clone) or not is_instance_valid(_part):
		return
	# Lifted off the centre first, so the mirror below lands somewhere other than on top of it.
	var centre := _arena.get_center()
	if _part.global_position.distance_to(centre) < CLONE_SEPARATION:
		_part.global_position = centre + Vector2(0.0, -CLONE_SEPARATION)

	_clone = PART_SCENE.instantiate()
	add_child(_clone)
	_clone.global_position = _mirror_of(_part.global_position)
	_clone.took_damage.connect(_on_part_damaged)
	_clone.get_sprite().texture = _texture_for(_mask)
	_resize(_clone, _radius_for(_mask))
	_clone.set_tint(_mask_tint())


func _clear_clone() -> void:
	if is_instance_valid(_clone):
		_clone.queue_free()
	_clone = null


func _mirror_of(point: Vector2) -> Vector2:
	return _arena.get_center() * 2.0 - point


## Both bodies fire, which is what makes two bodies a different fight rather than a bigger target.
## The clone's spread is aimed from where the clone is, so the two arrive from opposite sides of
## the player — the same geometry the mirror gives the King on Floor 1.
func _fire_spread() -> void:
	super()
	if not is_instance_valid(_clone) or config.shot == null:
		return
	var origin := _clone.global_position
	var aim := _aim_from(origin)
	var arc := deg_to_rad(config.spread_degrees)
	var count := maxi(config.spread_count, 1)
	for index: int in count:
		var offset := 0.0 if count == 1 else -arc * 0.5 + arc * (float(index) / float(count - 1))
		_spawn(origin, aim.rotated(offset))


## Conflict markers dropped from the ceiling across the whole arena, evenly spaced. The Scrap
## King's own attack, and the only thing in this fight that comes from a direction rather than from
## a body — which is why it is the one attack the last mask opens with.
func _fire_markers() -> void:
	var tuning := config as CoreIntelligenceConfig
	var count := maxi(tuning.marker_count if tuning != null else 5, 3)
	for index: int in count:
		var x := _arena.position.x + _arena.size.x * float(index) / float(count - 1)
		_spawn(Vector2(x, _arena.position.y), Vector2.DOWN)


## The bodies move as the base class moves one, plus the mirror — and the Orchestrator's mask does
## not move at all. It sits on the ground it migrated to until it migrates again, which is the
## whole reason that mask's ground means anything.
func _step_drift(delta: float) -> void:
	if _mask == Mask.ORCHESTRATOR:
		return
	super(delta)
	if is_instance_valid(_clone) and is_instance_valid(_part):
		_clone.global_position = _mirror_of(_part.global_position)


# --- Cascade Failure's mask ---------------------------------------------------


## The triad: the player's own square and two orthogonal follow-ups toward the room's open side.
## Announced together, non-overlapping, and leaving most of a 26x12-tile arena untouched.
func _fire_vents() -> void:
	var core_config := config as CoreIntelligenceConfig
	if core_config == null or _player == null:
		return
	var size := Vector2(core_config.vent_size_tiles * Room.TILE_SIZE)
	var centre := _arena.get_center()
	var player_at := _player.global_position
	# Point into the larger half of the arena on each axis. Unlike mirroring, this stays separated
	# when the player is exactly in the centre, so one warning can never resolve as three hits.
	var direction := Vector2(
		1.0 if player_at.x <= centre.x else -1.0, 1.0 if player_at.y <= centre.y else -1.0
	)
	var candidates: Array[Vector2] = [
		player_at,
		player_at + Vector2(6.0 * Room.TILE_SIZE * direction.x, 0.0),
		player_at + Vector2(0.0, 4.0 * Room.TILE_SIZE * direction.y),
	]
	for index: int in mini(core_config.vent_count, candidates.size()):
		_drop_vent(candidates[index])


## Cascade Failure's pincer, both halves at once: one patch where the robot *is*, one where it will
## be in `lead_seconds` if it does not turn.
##
## The pair is the whole idea, and it is why they are fired together here rather than on two clocks
## as the rack fires them. The aimed patch charges for standing still; the lead patch charges for
## holding a heading; the only input that answers both is a turn, and asking for that turn once per
## rotation is the finale's version of a floor that asked for it continuously.
##
## A robot with no velocity leads nowhere, and the two patches land on the same square — which is
## the convergence Floor 3 treats as the point rather than as an edge case: standing still is
## answered by one patch, because standing still is one mistake.
func _fire_aimed_vents() -> void:
	if _player == null:
		return
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	_drop_vent(_player.global_position)
	_drop_vent(_player.global_position + _player_velocity() * tuning.lead_seconds)


## A wall of patches across the arena, filling together, with exactly one door in it.
##
## This is the only thing either this fight or Floor 3's has that denies a **route** rather than a
## square: every patch it drops elsewhere is left by a fifth of a second of walking, so a player
## who keeps drifting is never made to choose. A wall cannot be drifted around. It is crossed while
## it is cold or it is accepted.
##
## **The door is where the boss is**, not where the player is. A door under the player would be a
## wall that asks for nothing; a door at random would be a coin toss. Putting it under the body
## means the way out of the wall is toward the thing firing at you, which is a decision with two
## bad halves — and it is the same shape as the Orchestrator's plate, one mask later, where the
## safe ground is the ground the boss wants.
##
## **It is laid between the robot and the boss**, across whichever axis separates them, so it is
## always a wall across the ground the player wants: the shot they are lining up is on the far side
## of it. A wall laid anywhere else is scenery, and a wall laid *on* the robot is a line they step
## off in whichever direction they were already going.
func _fire_vent_wall() -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null or not is_instance_valid(_part):
		return
	var count := maxi(tuning.vent_wall_count, 3)
	var body := _part.global_position
	var anchor := _player.global_position if _player != null else _arena.get_center()
	# Perpendicular to the way they are separated: a horizontal band when the boss is above or
	# below, a vertical one when it is to one side.
	var is_row := absf(anchor.y - body.y) >= absf(anchor.x - body.x)
	var band := (anchor + body) * 0.5

	var thickness := Vector2(tuning.vent_size_tiles * Room.TILE_SIZE)
	var span := _arena.size.x if is_row else _arena.size.y
	var start := _arena.position.x if is_row else _arena.position.y
	var step := span / float(count)
	var door := clampi(int(((body.x if is_row else body.y) - start) / maxf(step, 1.0)), 0, count - 1)

	for index: int in count:
		if index == door:
			continue
		var along := start + step * float(index)
		var rect := (
			Rect2(Vector2(along, band.y - thickness.y * 0.5), Vector2(step, thickness.y))
			if is_row
			else Rect2(Vector2(band.x - thickness.x * 0.5, along), Vector2(thickness.x, step))
		)
		_spawn_vent(rect)


## One patch, centred on a point and clamped whole into the arena. Clamped rather than cropped for
## `CascadeFailure._drop_vent`'s reason: a robot running at a wall is led into that wall, and what
## meets them there should be a whole patch flush against it rather than half of one outside the
## room.
func _drop_vent(centre: Vector2) -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	var size := Vector2(tuning.vent_size_tiles * Room.TILE_SIZE)
	var wanted := centre - size * 0.5
	_spawn_vent(Rect2(
		Vector2(
			clampf(wanted.x, _arena.position.x, _arena.end.x - size.x),
			clampf(wanted.y, _arena.position.y, _arena.end.y - size.y),
		),
		size,
	))


func _spawn_vent(rect: Rect2) -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	ThermalZone.spawn_vent(self, rect.intersection(_arena), tuning.vent_seconds)


## The robot's current velocity, or zero for anything standing in for it that has none. Typed as
## `Node2D` throughout this fight so it can be fought by a test double, exactly as Floor 3's is.
func _player_velocity() -> Vector2:
	if _player is CharacterBody2D:
		return (_player as CharacterBody2D).velocity
	return Vector2.ZERO


# --- The Orchestrator's mask --------------------------------------------------


## Announces a migration: names the ground it is going to, leaves one other plate live, and paints
## every other cell of the arena with a compile lane.
##
## The Orchestrator's four beats, in this fight's own materials. Its plates are cells of the
## checkerboard grid; its floor discharge is a lane per cell, which means the warning is the
## amber-then-red the player has read since Floor 2 and — far more importantly — that the discharge
## owns its own clock. A boss killed between the announcement and the strike still discharges the
## floor it announced, and a boss killed before announcing anything discharges nothing.
##
## **The destination is the cell furthest from the player**, chosen when the telegraph starts and
## never changed after. Any deterministic rule that ignores the player can be camped; choosing the
## ground they are least able to reach is what makes the run for it a real race, and it quietly
## rewards holding the middle of the arena — from the centre every cell is close, from a corner the
## far side is a sprint the telegraph may not cover.
##
## **The second plate is the nearest cell that is not the one they are standing in.** Somewhere to
## go always exists, and standing still is never the answer: the floor the player is on is part of
## the discharge unless they are already on one of the two plates.
func _begin_migration() -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	var anchor := _player.global_position if _player != null else _arena.get_center()
	_target_cell = _furthest_cell_from(anchor)
	_live_cell = _nearest_cell_from(anchor, _cell_at(anchor))
	_migrate_left = maxf(tuning.migrate_telegraph_seconds, 0.05)
	_seal()

	for index: int in get_cell_count():
		if index == _target_cell or index == _live_cell:
			continue
		CompileLane.spawn(
			self,
			get_cell_rect(index),
			config.lane_damage,
			_migrate_left,
			config.lane_strike_seconds,
		)


func _step_migration(delta: float) -> void:
	if _migrate_left <= 0.0:
		return
	_migrate_left -= delta
	if _migrate_left > 0.0:
		return
	_migrate_left = 0.0
	_resolve_migration()


## The load moves — unless the robot is standing where it was going, in which case it has nowhere
## to put itself and stays.
##
## Denial is the turn on top of the four beats and the reason the destination is worth running for.
## Any plate keeps the player alive; *that* plate holds the boss open for `denial_open_seconds`
## instead of `open_seconds`, which is most of the damage this mask will ever accept.
func _resolve_migration() -> void:
	var tuning := config as CoreIntelligenceConfig
	if tuning == null:
		return
	var standing_on_it := (
		_player != null and get_cell_rect(_target_cell).has_point(_player.global_position)
	)
	if standing_on_it:
		_open_for(tuning.denial_open_seconds)
		return
	if is_instance_valid(_part):
		_part.global_position = get_cell_rect(_target_cell).get_center()
	_open_for(tuning.open_seconds)


## Damage counts again, and every part of the presentation says so at once: the body goes to the
## Orchestrator's open colour and stops pinging shots off dim steel. A player must be able to see
## the window without watching the bar, because the window is the only thing in this mask worth
## watching.
func _open_for(seconds: float) -> void:
	_open_left = maxf(seconds, 0.0)
	# The rotation resumes when the window closes, not while it is open: `_step_attacks` is held
	# for the whole of it, so this clock starts counting on the far side rather than through it.
	_attack_left = _interval_for(_phase)
	if is_instance_valid(_part):
		_part.set_shielded(false)
	_restore_tint()


func _seal() -> void:
	_open_left = 0.0
	if is_instance_valid(_part):
		_part.set_shielded(true)
	_restore_tint()


func _step_open_window(delta: float) -> void:
	if _open_left <= 0.0:
		return
	_open_left -= delta
	if _open_left <= 0.0:
		_open_left = 0.0
		_seal()


# --- Arena cells --------------------------------------------------------------


func _cell_at(point: Vector2) -> int:
	for index: int in get_cell_count():
		if get_cell_rect(index).has_point(point):
			return index
	return -1


func _furthest_cell_from(point: Vector2) -> int:
	var best := 0
	var best_distance := -1.0
	for index: int in get_cell_count():
		var distance := get_cell_rect(index).get_center().distance_to(point)
		if distance > best_distance:
			best_distance = distance
			best = index
	return best


## The nearest cell, skipping one — the one the player is standing in, so that surviving a
## discharge always costs a step. Falls back to the furthest cell when there is nothing to skip,
## which cannot happen in an arena the player is inside and would otherwise be a silent -1.
func _nearest_cell_from(point: Vector2, skip: int) -> int:
	var best := -1
	var best_distance := INF
	for index: int in get_cell_count():
		if index == skip or index == _target_cell:
			continue
		var distance := get_cell_rect(index).get_center().distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best if best >= 0 else _furthest_cell_from(point)
