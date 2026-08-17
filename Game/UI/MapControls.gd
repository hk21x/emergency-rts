extends VBoxContainer
class_name MapControls

## The zoom buttons down the right-hand edge of the minimap.
##
## The wheel has always zoomed the camera; this is the same thing for anyone who does
## not know that, which on a map card is most people the first time they see one. Two
## buttons, because two is what was asked for -- the kit ships plates for centre and
## follow as well if they earn their place later.
##
## **Beside the map, not on it.** The first cut put them inside the card, over the
## render's right edge, which is where the reference draws them -- and over a map that
## is a photograph of a city they read as two tiles dropped on the district rather than
## as controls. Out here they are next to the thing they control, and they cannot
## intercept a click meant for the map.
##
## Positioned by `HUD.tscn` rather than by this script: it is a panel among panels now,
## and the suite's overlap invariant measures it with the rest.

## One wheel notch per press, so the button and the wheel agree about what a step is.
const STEP := 1.0

var camera: RTSCamera


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_button("plus", func() -> void: _zoom(-STEP))
	_button("minus", func() -> void: _zoom(STEP))


func _button(icon: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"MapControl"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(38.0, 34.0)
	var path := "res://Game/UI/Kit/icons/icon_%s.svg" % icon
	if ResourceLoader.exists(path):
		button.icon = load(path) as Texture2D
	# Icon-only, so both alignments have to be centred -- see the note in `HUD.gd`.
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	add_child(button)
	return button


## Steps the camera the way a wheel notch does. Negative pulls in.
##
## Written against `_target_distance` rather than `_distance` so the button feeds the
## same eased approach the wheel does -- setting the distance directly would snap the
## view and read as a different control entirely.
func _zoom(notches: float) -> void:
	if camera == null:
		return
	camera._target_distance = clampf(
		camera._target_distance + notches * camera.zoom_step,
		camera.min_distance, camera.max_distance)
