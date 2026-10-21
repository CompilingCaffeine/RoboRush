extends SceneTree
## Writes every track of `MusicScore` as a WAV, for listening to outside the game.
##
##     godot --headless --path . --script tools/render_music.gd -- build/music
##
## The game renders its music itself, the first time each track is needed, and ships no audio files
## for it. This is the same synthesis written to disk: what comes out is exactly what the game
## plays, for the times a loop is easier to judge in an audio editor than in a run.

const DEFAULT_DIRECTORY := "build/music"


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var directory: String = arguments[0] if not arguments.is_empty() else DEFAULT_DIRECTORY
	var made := DirAccess.make_dir_recursive_absolute(directory)
	if made != OK:
		printerr("render_music: could not create %s (%s)" % [directory, error_string(made)])
		quit(1)
		return
	for id: StringName in MusicScore.TRACK_IDS:
		var track := MusicScore.track(id)
		var problems := MusicSynth.problems(track)
		if not problems.is_empty():
			printerr("render_music: %s: %s" % [id, "; ".join(problems)])
			quit(1)
			return
		var path := directory.path_join("%s.wav" % id)
		var wav := MusicSynth.render(track)
		var saved := wav.save_to_wav(path)
		if saved != OK:
			printerr("render_music: could not write %s (%s)" % [path, error_string(saved)])
			quit(1)
			return
		print("wrote %s (%.1f s)" % [path, wav.get_length()])
	quit()
