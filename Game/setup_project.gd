extends SceneTree

## One-shot project configuration: registers the driving input actions, sets the
## display scaling, and points the project at the playground scene. Written through
## ProjectSettings rather than by hand-editing project.godot, so the InputEvent
## serialisation is always valid.
##
##   godot --headless --path . --script res://Game/setup_project.gd
##
## Safe to re-run; it overwrites the same keys.

const MAIN_SCENE := "res://Game/Playground.tscn"

## The resolution the interface is laid out for. Every offset in HUD.tscn -- the 148px
## bar, the 210px minimap card -- is in these units.
const BASE_WIDTH := 1600
const BASE_HEIGHT := 900


func _init() -> void:
	var previous: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if previous != "" and previous != MAIN_SCENE:
		print("previous main scene was: ", previous)

	# The car is driven by its autopilot now, so the old direct-driving actions are
	# gone. Setting a key to null erases it from project.godot.
	for stale in ["car_accelerate", "car_brake", "car_steer_left", "car_steer_right",
			"car_handbrake", "cam_cycle"]:
		ProjectSettings.set_setting("input/" + stale, null)

	# Physical keycodes, so the layout still works on AZERTY/QWERTZ keyboards.
	_action("cam_pan_forward", [_key(KEY_W), _key(KEY_UP)])
	_action("cam_pan_back", [_key(KEY_S), _key(KEY_DOWN)])
	_action("cam_pan_left", [_key(KEY_A), _key(KEY_LEFT)])
	_action("cam_pan_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_action("cam_rotate_left", [_key(KEY_Q)])
	_action("cam_rotate_right", [_key(KEY_E)])
	_action("cam_fast", [_key(KEY_SHIFT)])
	_action("cam_focus", [_key(KEY_F)])
	_action("car_reset", [_key(KEY_R)])

	ProjectSettings.set_setting("application/run/main_scene", MAIN_SCENE)
	_display()

	var err := ProjectSettings.save()
	if err != OK:
		push_error("could not save project.godot: %d" % err)
		quit(1)
		return
	print("input actions registered; main scene set to ", MAIN_SCENE)
	quit()


## Makes the interface scale with the window instead of staying a fixed number of
## pixels.
##
## Without this the HUD is laid out in raw screen pixels, which is fine at the default
## 1152x648 and unusable anywhere else: on a 3440-wide display the command bar is a
## 148px sliver along the bottom and the labels are unreadable. The 3D view was the
## only thing that got bigger.
##
## `canvas_items` scales the 2D coordinate system while the 3D world still renders at
## the display's real resolution, so the city stays sharp and the interface grows with
## it. Input and `unproject_position` both work in the scaled space, so picking needs
## no change -- but anything measuring the interface must ask the *viewport* for its
## size, not the window, because the two are no longer the same number.
##
## `expand` rather than `keep`: on a wider-than-16:9 display the extra width becomes
## more city rather than pillarboxing, which is the right trade for an RTS.
func _display() -> void:
	ProjectSettings.set_setting("display/window/size/viewport_width", BASE_WIDTH)
	ProjectSettings.set_setting("display/window/size/viewport_height", BASE_HEIGHT)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")


func _action(action_name: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action_name, {
		"deadzone": 0.2,
		"events": events,
	})


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event
