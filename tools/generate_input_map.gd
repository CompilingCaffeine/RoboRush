## Prints the [input] section for project.godot.
##
## Input events are painful and error prone to hand-write in the .godot INI
## format, so we build them as real InputEvent objects and let the engine
## serialise them with var_to_str(). Run from the project root:
##
##     godot --headless --script res://tools/generate_input_map.gd
##
## then paste the output over the [input] section of project.godot. Keeping this
## as a print-and-paste step (rather than ProjectSettings.save()) means the
## explanatory comments in project.godot survive regeneration.
extends SceneTree

## Stick and trigger deadzones. Keyboard/mouse events ignore these.
const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.5


func _initialize() -> void:
	var actions := {
		# --- Movement (WASD + left stick) ---
		"move_up": _action([_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)], STICK_DEADZONE),
		"move_down": _action([_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)], STICK_DEADZONE),
		"move_left": _action([_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)], STICK_DEADZONE),
		"move_right": _action([_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)], STICK_DEADZONE),

		# --- Aiming (right stick only; mouse aim is read from the cursor) ---
		"aim_up": _action([_axis(JOY_AXIS_RIGHT_Y, -1.0)], STICK_DEADZONE),
		"aim_down": _action([_axis(JOY_AXIS_RIGHT_Y, 1.0)], STICK_DEADZONE),
		"aim_left": _action([_axis(JOY_AXIS_RIGHT_X, -1.0)], STICK_DEADZONE),
		"aim_right": _action([_axis(JOY_AXIS_RIGHT_X, 1.0)], STICK_DEADZONE),

		# --- Combat (unused in milestone 1, declared so scenes can bind early) ---
		"fire_primary": _action(
			[_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], TRIGGER_DEADZONE
		),
		"use_active_item": _action(
			[_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], TRIGGER_DEADZONE
		),

		# --- Verbs ---
		"dash": _action([_key(KEY_SPACE), _button(JOY_BUTTON_A)], STICK_DEADZONE),
		"interact": _action([_key(KEY_E), _button(JOY_BUTTON_X)], STICK_DEADZONE),
		"run_stats": _action([_key(KEY_TAB)], STICK_DEADZONE),
		"pause": _action([_key(KEY_ESCAPE), _button(JOY_BUTTON_START)], STICK_DEADZONE),

		# --- Debug ---
		"debug_toggle_hud": _action([_key(KEY_F1)], STICK_DEADZONE),
	}

	print("[input]\n")
	for name: String in actions:
		var config: Dictionary = actions[name]
		var serialised: PackedStringArray = []
		for event: InputEvent in config["events"]:
			serialised.append(var_to_str(event))
		print("%s={\n\"deadzone\": %s,\n\"events\": [%s]\n}\n" % [
			name, config["deadzone"], ", ".join(serialised)
		])

	quit()


func _action(events: Array[InputEvent], deadzone: float) -> Dictionary:
	return {"deadzone": deadzone, "events": events}


## Physical keycodes so the bindings follow key position, not keyboard layout.
func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
