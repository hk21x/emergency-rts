class_name ERSNotificationLayer
extends Control
## Stacked in-game notifications. Call push() from anywhere.
##
##   $NotificationLayer.push("Objective completed", ERSNotificationLayer.Kind.SUCCESS)

enum Kind { INFO, SUCCESS, WARNING, DANGER }

const ACCENT := {
	Kind.INFO:    Color("2a7fe0"),
	Kind.SUCCESS: Color("3e9b4f"),
	Kind.WARNING: Color("c79a2a"),
	Kind.DANGER:  Color("b2382a"),
}
const GLYPH := {
	Kind.INFO:    "res://ui/art/icons/icon_info.svg",
	Kind.SUCCESS: "res://ui/art/icons/icon_check.svg",
	Kind.WARNING: "res://ui/art/icons/icon_warning.svg",
	Kind.DANGER:  "res://ui/art/icons/icon_flame.svg",
}

@export var lifetime: float = 4.0
@export var max_visible: int = 5

var _stack: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.offset_left = -376
	_stack.offset_top = 16
	_stack.offset_right = -16
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)


func push(message: String, kind: Kind = Kind.INFO) -> void:
	while _stack.get_child_count() >= max_visible:
		_stack.get_child(0).queue_free()
		await get_tree().process_frame

	var row := PanelContainer.new()
	row.theme_type_variation = &"ERSInset"
	row.custom_minimum_size = Vector2(360, 34)
	row.modulate.a = 0.0

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var tab := ColorRect.new()
	tab.color = ACCENT[kind]
	tab.custom_minimum_size = Vector2(32, 0)
	box.add_child(tab)

	var icon := TextureRect.new()
	icon.texture = load(GLYPH[kind])
	icon.custom_minimum_size = Vector2(20, 20)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.position = Vector2(6, 7)
	tab.add_child(icon)

	var label := Label.new()
	label.text = message
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)

	var close := Button.new()
	close.text = "\u00d7"
	close.flat = true
	close.custom_minimum_size = Vector2(28, 0)
	close.pressed.connect(func(): _dismiss(row))
	box.add_child(close)

	_stack.add_child(row)

	var t := create_tween()
	t.tween_property(row, "modulate:a", 1.0, 0.18)
	t.tween_interval(lifetime)
	t.tween_callback(_dismiss.bind(row))


func _dismiss(row: Control) -> void:
	if not is_instance_valid(row) or row.is_queued_for_deletion():
		return
	var t := create_tween()
	t.tween_property(row, "modulate:a", 0.0, 0.16)
	t.tween_callback(row.queue_free)
