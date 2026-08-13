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


func _ready() -> void:
	# Before anything else, and before the run is started: a campaign with a broken floor in it
	# fails here, where the diagnostics name the floor and the field, rather than at the moment
	# the player descends into it — by which time the floor they were on has been torn down and
	# the only thing left to show them is an empty world.
	var campaign := _floor.campaign
	if not _campaign_is_playable(campaign):
		return

	var run_seed := _resolve_seed()
	var floor_index := _resolve_start_floor(campaign)
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
	RunManager.begin_run(run_seed, campaign)

	_feedback.setup(_player.get_camera())
	_item_effects.bind_player(_player)
	_combat_hud.bind_player(_player)
	_debug_hud.bind_player(_player)
	_floor.boss_encountered.connect(_combat_hud.bind_boss)

	# The campaign is the floor order, so the opening floor comes from it too rather than from
	# whatever `floor.tscn` happens to have in its `config` slot. One authority, including for
	# the floor that would have been right by accident.
	_floor.config = campaign.load_floor(floor_index)
	# Connected before the build, because the floor announces its theme from inside it — see
	# `FloorController.floor_theme_changed` for why that has to happen before the player is
	# placed. One connection covers both the opening floor and every descent.
	_floor.floor_theme_changed.connect(_feedback.set_floor_theme)
	if not _floor.build(_player, floor_seed):
		# Generation failing is a content bug, not something to hide from the player behind a
		# blank screen (spec section 31.10 forbids placeholder error messages reaching them).
		push_error("Main: floor generation failed for seed %d." % floor_seed)
		return

	_minimap.bind_floor(_floor)
	_debug_hud.bind_floor(_floor)
	_floor.floor_advanced.connect(_on_floor_advanced)
	_combat_hud.announce_floor(_floor.config.floor_number)


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
