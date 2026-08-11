extends Control

## Drag rectangle for box selection. The controller owns the drag; this only draws.

@export var fill := Color(0.3, 1.0, 0.45, 0.12)
@export var border := Color(0.35, 1.0, 0.5, 0.9)
@export var border_width := 1.5

var _rect := Rect2()
var _active := false


func _ready() -> void:
	# Must not eat clicks: the controller reads them from _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Shows the box between two screen points, in either drag direction.
func show_box(from: Vector2, to: Vector2) -> void:
	_rect = Rect2(from, to - from).abs()
	_active = true
	queue_redraw()


func hide_box() -> void:
	if not _active:
		return
	_active = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_rect(_rect, fill, true)
	draw_rect(_rect, border, false, border_width)
