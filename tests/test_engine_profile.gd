extends TestCase
## Everything the game ships loads on the engine running the suite.
##
## The Web build runs on an engine compiled for this game (tools/engine/), with every module and
## node type the game does not use switched off. That is most of why the download is small, and it
## has one way to go wrong: the game starts using a class the profile took out. Nothing shows it in
## the editor, which has every class, so it surfaces in a browser as a scene that will not load or a
## script that will not compile — wherever that code is first reached, which can be a long way from
## the main menu the smoke test looks at.
##
## So this walks the project the way an export does and loads all of it: every script must
## compile, every resource must load, every scene must instantiate. On the editor that shows the
## walk itself works. On the stripped native engine, which tools/ci/build_web.sh and
## tools/release.sh also run the suite on, it shows the profile still has everything the game needs.
##
## Left out, because no exported game loads them: directories the export presets exclude,
## directories Godot itself ignores (a .gdignore), and the editor plugin script each add-on's
## plugin.cfg names, which extends EditorPlugin and so exists only in the editor.

## Excluded from every preset by export_presets.cfg.
const UNSHIPPED_DIRECTORIES: Array[String] = ["res://tests", "res://tools"]

const LOADABLE_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "scn", "res"]


func run() -> void:
	var paths: Array[String] = []
	_walk("res://", paths)
	var editor_only := _editor_plugin_scripts()

	var scripts := paths.filter(func(path: String) -> bool: return path.get_extension() == "gd")
	var scenes := paths.filter(func(path: String) -> bool: return path.get_extension() == "tscn")
	# A walk that found nothing would pass every check it made. These floors are far below what the
	# game has, and only there to make that impossible.
	check(scripts.size() > 100, "the walk finds the game's scripts (%d)" % scripts.size())
	check(scenes.size() > 20, "the walk finds the game's scenes (%d)" % scenes.size())
	check(not editor_only.is_empty(), "the Wavedash add-on's editor plugin is recognised as editor-only")

	for path: String in paths:
		if not editor_only.has(path):
			_test_loads(path)


## Every script compiles, every resource loads, every scene instantiates.
func _test_loads(path: String) -> void:
	var resource := ResourceLoader.load(path)
	if resource == null:
		fail("%s loads on this engine" % path)
	elif resource is Script:
		check((resource as Script).can_instantiate(), "%s compiles on this engine" % path)
	elif resource is PackedScene:
		var scene := resource as PackedScene
		# Checked by name before instantiating, because instantiating does not fail: a node whose
		# class the engine lacks becomes a placeholder, with an error in the log and the scene
		# otherwise intact, so a check on what instantiate() returns passes a scene with a missing
		# RichTextLabel in it.
		var state := scene.get_state()
		for index: int in state.get_node_count():
			var type := state.get_node_type(index)
			# Empty for a node that comes from an instanced or inherited scene, which is checked
			# as a scene of its own.
			if type != &"":
				check(ClassDB.class_exists(type), "%s: %s exists on this engine" % [path, type])
		var node := scene.instantiate()
		check(node != null, "%s instantiates on this engine" % path)
		if node != null:
			node.free()
	else:
		check(true, "%s loads on this engine" % path)


# --- Helpers ------------------------------------------------------------------


func _walk(directory: String, out: Array[String]) -> void:
	if UNSHIPPED_DIRECTORIES.has(directory.trim_suffix("/")):
		return
	if FileAccess.file_exists(directory.path_join(".gdignore")):
		return
	for entry: String in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			if not entry.begins_with("."):
				_walk(directory.path_join(entry.trim_suffix("/")), out)
		elif entry.get_extension() in LOADABLE_EXTENSIONS:
			out.append(directory.path_join(entry))


## The script each add-on's plugin.cfg names. Godot runs it in the editor only, so it is never
## loaded by the game, and it extends EditorPlugin, which an exported engine does not have at all.
func _editor_plugin_scripts() -> Array[String]:
	var scripts: Array[String] = []
	for addon: String in DirAccess.get_directories_at("res://addons"):
		var manifest := ConfigFile.new()
		if manifest.load("res://addons".path_join(addon).path_join("plugin.cfg")) != OK:
			continue
		var script := str(manifest.get_value("plugin", "script", ""))
		if not script.is_empty():
			scripts.append("res://addons".path_join(addon).path_join(script))
	return scripts
