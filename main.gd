extends Node2D
## Milestone 4 entry point.
##
## Composition only: it starts a run, builds the floor, and hands the HUDs and the feedback
## director the references they need. Nothing here knows how movement, shooting, damage, or
## room generation work — this file exists so no scene has to reach across the tree to find
## its collaborators.
##
## The run seed comes from the system clock unless FLOOR_SEED_OVERRIDE is set, so a run is
## different every time but any specific one can be reproduced when something goes wrong in it.
## Each floor's own seed is derived from it by `RunDefinition.floor_seed_for`, from the run seed and
## the floor's stable id, so one seed reproduces the whole run rather than only the floor it opened
## on — and reproduces any single floor of it on its own.

## Set to a non-zero value to force one specific layout. Left at zero for normal play.
const FLOOR_SEED_OVERRIDE := 0

@onready var _floor: FloorController = %Floor
@onready var _player: Player = %Player
@onready var _feedback: FeedbackDirector = %FeedbackDirector
@onready var _item_effects: ItemEffects = %ItemEffects
@onready var _combat_hud: CombatHUD = %CombatHUD
@onready var _minimap: Minimap = %Minimap
@onready var _debug_hud: DebugHUD = %DebugHUD
@onready var _pause_menu: PauseMenu = %PauseMenu

## Set when this scene has decided not to build anything and has asked to be replaced by the
## title screen. The scene change is deferred — it cannot happen inside `_ready` — so there is a
## stretch of this function that must not go on assembling a run that is about to be thrown away.
var _returning_to_menu := false


func _ready() -> void:
	# Before anything else, and before the run is started: a campaign with a broken floor in it
	# fails here, where the diagnostics name the floor and the field, rather than at the moment
	# the player descends into it — by which time the floor they were on has been torn down and
	# the only thing left to show them is an empty world.
	var campaign := _floor.campaign
	if not _campaign_is_playable(campaign):
		return

	# A resumed run takes its seed and its floor from the checkpoint rather than from the clock and
	# the command line, and takes them *before* anything else is decided: everything below derives
	# from those two values, so a resume that reached this point having already rolled a fresh seed
	# would be a new run wearing an old run's inventory.
	var checkpoint := _resolve_checkpoint(campaign)
	if _returning_to_menu:
		# A refused checkpoint leaves nothing to build. Returning here rather than starting a fresh
		# run is the point: `RunManager.begin_run` files a run started, and the trip back to the
		# title screen would then file it finished, so a player who lost a checkpoint would also
		# find a phantom loss in their records.
		return

	var run_seed := checkpoint.run_seed if checkpoint != null else _resolve_seed()
	var floor_index := (
		campaign.index_of(checkpoint.floor_id) if checkpoint != null
		else _resolve_start_floor(campaign)
	)
	var floor_seed := campaign.floor_seed_for(run_seed, floor_index)

	# Said out loud, always, and this is the one line of boot logging worth its noise: it is what a
	# bug report has to carry for the run to be reproducible at all. The seed alone is not enough —
	# the same seed builds a different floor 3 once floor 3 is edited — so the campaign and its
	# content version go with it. `--manifest` prints what those three actually resolve to.
	print("Main: run seed %d (campaign '%s' content version %d)."
		% [run_seed, campaign.id, campaign.content_version])
	if _wants_manifest():
		print(RunManifest.describe(campaign, run_seed))

	# Order matters: the state must be playing before anything reads it, and the run's
	# clock only ticks while it is.
	GameManager.start_run()
	if checkpoint != null:
		RunManager.restore_run(checkpoint, campaign)
	else:
		RunManager.begin_run(run_seed, campaign)

	_feedback.setup(_player.get_camera())
	_item_effects.bind_player(_player)
	# Before the HUD is bound and before the floor is built. The HUD counts out one integrity pip
	# per point of the ceiling when it binds, and the ceiling is not known until the saved build is
	# back on the robot — bound first, a resumed run would show four pips for an eight-point robot
	# until the next item moved it.
	if checkpoint != null:
		_restore_player(checkpoint, campaign)
	_combat_hud.bind_player(_player)
	_debug_hud.bind_player(_player)
	_floor.boss_encountered.connect(_combat_hud.bind_boss)
	# The pause menu asks; the floor is the only thing that can answer, because a save taken in the
	# middle of a floor has to record which of its rooms are already done. Wired here rather than in
	# either of them, for the same reason as everything else in this file.
	_pause_menu.save_requested.connect(_on_save_requested)

	# The campaign is the floor order, so the opening floor comes from it too rather than from
	# whatever `floor.tscn` happens to have in its `config` slot. One authority, including for
	# the floor that would have been right by accident.
	_floor.config = campaign.load_floor(floor_index)
	# Connected before the build, because the floor announces its theme from inside it — see
	# `FloorController.floor_theme_changed` for why that has to happen before the player is
	# placed. One connection covers both the opening floor and every descent.
	_floor.floor_theme_changed.connect(_feedback.set_floor_theme)
	# Before the build, because the build is what instantiates the rooms and a room that was already
	# cleared has to be built empty rather than emptied afterwards. The room lists are empty for a
	# checkpoint written at a floor boundary, which is every checkpoint written by anything other
	# than the pause menu; the shop's shelf is not, because a floor stocks its shop before the player
	# has taken a step on it (see `ShopStock`).
	if checkpoint != null:
		_floor.resume_floor_progress(
			checkpoint.floor_cleared_room_ids,
			checkpoint.floor_visited_room_ids,
			checkpoint.floor_clears,
			checkpoint.floor_shop,
		)
	if not _floor.build(_player, floor_seed):
		# Generation failing is a content bug, not something to hide from the player behind a
		# blank screen (spec section 31.10 forbids placeholder error messages reaching them).
		push_error("Main: floor generation failed for seed %d." % floor_seed)
		return

	_minimap.bind_floor(_floor)
	_debug_hud.bind_floor(_floor)
	_floor.floor_advanced.connect(_on_floor_advanced)
	_combat_hud.announce_floor(_floor.config.floor_number)


## The saved run this scene was asked to continue, or null to start a fresh one.
##
## Two gates, and both are needed. The router's flag says the player asked to continue rather than
## to start — a checkpoint sitting in the save file is not a request to resume it. `validate` then
## says whether the file can actually be played against the campaign that is loaded now, which is
## the question the title screen cannot answer: it has no campaign, and inventing a second
## reference to one would be exactly the split authority `RunDefinition` exists to remove.
##
## A refused checkpoint is cleared and the player is put back on the title screen. It is the
## honest outcome of the two things that reach here — a hand-edited file, and a run saved against
## content that has since been edited — because neither can be continued and neither should
## silently become a *new* run under a player who asked for their old one.
func _resolve_checkpoint(campaign: RunDefinition) -> RunCheckpoint:
	if not SceneRouter.consume_resume_request():
		return null

	var checkpoint := SaveManager.get_checkpoint()
	if checkpoint == null:
		push_warning("Main: asked to continue a run, but there is no checkpoint to continue from.")
		return null

	var problems := checkpoint.validate(campaign)
	if problems.is_empty():
		print("Main: continuing the saved run on floor %d (seed %d)."
			% [checkpoint.floor_number, checkpoint.run_seed])
		return checkpoint

	# Loud, and every reason rather than the first: a checkpoint refused for one reason is usually
	# refused for several, and the list is the only thing that says whether this was corruption or
	# a content version that moved.
	push_error("Main: the saved run cannot be continued, so it has been discarded.")
	for problem: String in problems:
		push_error("  checkpoint: %s" % problem)
	SaveManager.clear_checkpoint()
	_returning_to_menu = true
	# Only when this scene is the one the player is looking at. A game scene instantiated somewhere
	# else — by a suite, by a tool — replacing the *current* scene would be replacing something that
	# has nothing to do with it, and the run it refused to build was never on screen to leave.
	if get_tree().current_scene == self:
		SceneRouter.go_to_main_menu.call_deferred()
	return null


## Puts the robot back: the build the saved run was carrying, and the integrity it had left.
##
## Split from `RunManager.restore_run`, which has already run by the time this is called, because
## they restore two different things. The run's own state — scrap, seeds, what has been offered,
## what has been fought — belongs to `RunManager`; integrity and the build belong to the robot,
## and the robot is this scene's to assemble.
## The pause menu's SAVE GAME, answered by the floor and reported back to the button.
func _on_save_requested() -> void:
	_pause_menu.report_saved(_floor.save_run_now())


func _restore_player(checkpoint: RunCheckpoint, campaign: RunDefinition) -> void:
	var floor_config := campaign.load_floor_by_id(checkpoint.floor_id)
	if floor_config == null:
		# Unreachable: `validate` has already loaded this floor and refused the checkpoint if it
		# would not load. Guarded anyway, because the alternative to a guard here is the run
		# continuing with an empty inventory and no way to tell that it had.
		push_error("Main: floor '%s' would not load; the saved build cannot be restored."
			% checkpoint.floor_id)
		return
	_player.restore_build(checkpoint.resolve_items(floor_config), checkpoint.integrity)


## Whether the run may start. Warnings are reported and played through; errors are reported and
## stop the run before `GameManager.start_run`, because every one of them is content that cannot
## be played and the alternative is discovering that three floors in.
func _campaign_is_playable(campaign: RunDefinition) -> bool:
	if campaign == null:
		push_error("Main: no campaign is assigned to the floor; nothing says what a run is made of.")
		return false

	var report := CampaignValidator.validate(campaign)
	for warning: String in report.warnings:
		push_warning("Campaign '%s': %s" % [campaign.id, warning])
	if report.is_valid():
		return true

	for problem: String in report.errors:
		push_error("Campaign '%s': %s" % [campaign.id, problem])
	return false


## Seed precedence: command line, then the compiled-in override, then the clock.
##
## The command-line form exists so a layout can be reproduced from the seed the debug overlay
## prints. That is the difference between "a floor generated wrong once" and a bug someone can
## actually sit down and fix:
##
##     godot -- --seed=971330958
func _resolve_seed() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--seed="):
			continue
		var value := argument.trim_prefix("--seed=")
		if value.is_valid_int():
			return absi(value.to_int())
		push_warning("Main: ignoring non-numeric seed '%s'." % value)
	if FLOOR_SEED_OVERRIDE != 0:
		return FLOOR_SEED_OVERRIDE
	return absi(int(Time.get_unix_time_from_system() * 1000.0)) % 0x7FFFFFFF


## Whether `godot -- --manifest` was passed, asking for the campaign's content manifest.
##
##     godot -- --seed=971330958 --manifest
##
## What it prints is every floor's derived seed and a fingerprint of the content that seed will be
## spent on (see `RunManifest`). That is what turns "floor 3 does not generate the way it did in
## that report" into either "the seed is wrong" or "the content changed, here is which floor" —
## which nothing could answer while a seed's only companion was a hand-maintained version number.
##
## Behind a flag rather than always, because it loads all six floors to describe them and a boot
## should not pay for a debugging tool nobody asked for.
func _wants_manifest() -> bool:
	return "--manifest" in OS.get_cmdline_user_args()


## Developer-only: `godot -- --floor=4` starts the run on floor 4, so a later floor can be reached
## and iterated on without clearing everything before it. Returns an index into the campaign,
## counted from zero; floor 1 unless asked otherwise.
##
##     godot -- --seed=971330958 --floor=4
##
## The floor is *named by the campaign*, which is what makes this more than a shortcut. Paired
## with `RunDefinition.floor_seed_for`, starting directly on floor 4 builds the same floor 4 a
## run that fought its way there would have built, from the same run seed. A debug jump that
## produced a different floor than the one reported would only be useful for floors nobody
## reports bugs about.
##
## What it cannot reproduce is the *run* — the items, the scrap, the integrity, and the bosses
## already fought that a real arrival brings with it. This starts a fresh run on a later floor.
func _resolve_start_floor(campaign: RunDefinition) -> int:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--floor="):
			continue
		var value := argument.trim_prefix("--floor=")
		if not value.is_valid_int():
			push_warning("Main: ignoring non-numeric floor '%s'." % value)
			return 0

		var index := value.to_int() - 1
		if not campaign.has_floor(index):
			push_warning("Main: --floor=%s requested but campaign '%s' has %d floors."
				% [value, campaign.id, campaign.size()])
			return 0

		# Said out loud, because the failure this shortcut has is silent: a jump that quietly did
		# not happen looks exactly like a floor that does not differ as much as expected.
		print("Main: starting on floor %d of %d ('%s')."
			% [index + 1, campaign.size(), campaign.floor_id_at(index)])
		return index
	return 0


## The floor rebuilds itself in place rather than reloading the scene, so the HUDs that were
## wired to it once at startup need to be pointed at it again. Minimap in particular caches the
## floor's layout at bind time rather than reading it live, so without this it would keep
## drawing the floor the player just left.
##
## The level is announced here as well as at startup, and those are the only two ways a floor
## ever begins — a run either opens on one or descends into the next.
func _on_floor_advanced(config: FloorConfig) -> void:
	_minimap.bind_floor(_floor)
	_debug_hud.bind_floor(_floor)
	_combat_hud.announce_floor(config.floor_number)
