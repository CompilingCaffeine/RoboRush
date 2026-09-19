class_name MenuButtons
extends RefCounted
## Shared construction for menu buttons with consistent focus and mouse behaviour.

static func add(
	container: Container, label: String, pressed: Callable, focused: Callable, unfocused: Callable
) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(pressed)
	button.focus_entered.connect(focused.bind(button, label))
	button.focus_exited.connect(unfocused.bind(button, label))
	button.mouse_entered.connect(button.grab_focus)
	container.add_child(button)
	return button
