extends Node2D
## Milestone 4 entry point.
##
## Composition only: it starts a run, builds the floor, and hands the HUDs and the feedback
## director the references they need. Nothing here knows how movement, shooting, damage, or
## room generation work — this file exists so no scene has to reach across the tree to find
## its collaborators.
##
## The floor seed comes from the system clock unless FLOOR_SEED_OVERRIDE is set, so a run is
## different every time but any specific layout can be reproduced when something goes wrong
## in it. Milestone 5's RunManager takes over seeding when a run spans several floors.

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
	var seed_value := _resolve_seed()
	# Order matters: the state must be playing before anything reads it, and the run's
	# clock only ticks while it is.
	GameManager.start_run()
	RunManager.begin_run(seed_value)

	_feedback.setup(_player.get_camera())
	_item_effects.bind_player(_player)
	_combat_hud.bind_player(_player)
	_debug_hud.bind_player(_player)
	_floor.boss_encountered.connect(_combat_hud.bind_boss)

	_apply_dev_floor_override()
	if not _floor.build(_player, seed_value):
		# Generation failing is a content bug, not something to hide from the player behind a
		# blank screen (spec section 31.10 forbids placeholder error messages reaching them).
		push_error("Main: floor generation failed for seed %d." % seed_value)
		return

	_minimap.bind_floor(_floor)
	_debug_hud.bind_floor(_floor)
	_floor.floor_advanced.connect(_on_floor_advanced)
	_combat_hud.announce_floor(_floor.config.floor_number)


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


## Developer-only: `godot -- --floor=2` starts the run on floor 2 instead of floor 1, so a
## later floor can be reached and iterated on without clearing everything before it. Reads
## `_floor.config.next_floor` rather than any separate floor registry — there is only ever
## the one chain, and this walks the same links `FloorController._finish_floor` does.
func _apply_dev_floor_override() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument != "--floor=2":
			continue
		if _floor.config.next_floor == null:
			push_warning("Main: --floor=2 requested but floor 1 has no next_floor configured.")
			return
		_floor.config = _floor.config.next_floor
		return


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
