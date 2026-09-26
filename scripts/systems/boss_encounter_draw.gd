class_name BossEncounterDraw
extends RefCounted
## Picks a floor's boss from its pool. Never one the run has already fought — unless it is this
## floor's own, already drawn, and being taken back.
##
## A policy and nothing else, like `BossRewardDraw`: it is handed the pool, what the run has fought,
## which boss this floor already drew, and the floor's boss stream, and it answers with an entry. It
## records nothing. `FloorController` credits the run with the boss it is handed, because the run's
## ledger is the floor's to write and because keeping it out of here is what lets the policy be
## checked without building a floor.
##
## The campaign policy is one distinct boss per floor, so a repeat is not a degraded outcome to
## fall back on — it is a content error, and this is where it becomes visible instead of silent.
##
## **A re-opened floor takes its boss back.** A floor is opened once per *visit*, and a resume is a
## second visit to a floor the run has already been standing on: the boundary checkpoint is written
## just after the floor opens, so by the time it is saved this floor's boss is already in
## `fought_boss_ids`. Drawing again would therefore skip past the run's own boss — to a different
## one on a floor whose pool holds two, and to *nothing* on a floor whose pool holds one, which is
## every floor of a campaign that gives each floor a boss of its own. A boss room with no boss still
## seals behind the player (see `FloorController._needs_clearing`) and nothing in it can ever clear
## it, so what the second draw actually produced was an empty locked room for the rest of the run.
## Asking the run which boss this floor already drew is what makes a resumed floor the same floor.
##
## **An exhausted pool draws a repeat rather than nothing.** This used to refuse, on the reasoning
## that `CampaignValidator` proves every floor can be given a boss of its own before the run starts,
## so an empty draw could only mean an unvalidated campaign and could not reach a player. The
## paragraph above is how it reached one anyway — and the cost of being wrong is asymmetric in a way
## the old reasoning did not weigh. A repeated fight is a run that continues and a loud error in the
## log; no boss at all is a sealed room, a lost run, and the same error. The refusal is kept as the
## error, not as the behaviour.


## The boss for a floor, or null only when its pool holds no usable entry at all.
##
## `already_drawn` is the id this floor drew on an earlier visit, or empty. `floor_label` names the
## floor in the error an exhausted pool reports, and is used for nothing else.
##
## The order `rng` is consumed in is part of the contract: one draw, and only when the floor is not
## taking its own boss back.
static func draw(
	boss_pool: Array[BossEncounter],
	fought_ids: Array[StringName],
	already_drawn: StringName,
	rng: RandomNumberGenerator,
	floor_label := "(unnamed)",
) -> BossEncounter:
	var pool: Array[BossEncounter] = []
	for entry: BossEncounter in boss_pool:
		if entry != null and entry.is_valid():
			pool.append(entry)

	# Before the draw: this floor has already had its turn.
	for entry: BossEncounter in pool:
		if entry.id == already_drawn:
			return entry

	var unfought: Array[BossEncounter] = []
	for entry: BossEncounter in pool:
		if entry.id not in fought_ids:
			unfought.append(entry)

	if unfought.is_empty():
		push_error(
			("FloorController: floor %s has no boss the run has not already fought. "
			+ "The campaign must give every floor a boss of its own — see CampaignValidator.")
			% floor_label
		)
		if pool.is_empty():
			return null
		return pool[rng.randi_range(0, pool.size() - 1)]

	return unfought[rng.randi_range(0, unfought.size() - 1)]
