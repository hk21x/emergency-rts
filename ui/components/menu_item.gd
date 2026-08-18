@tool
class_name ERSMenuItem
extends Button
## A main-menu row: glyph on the left, label beside it.
## Children are internal, so they never end up saved in your scene file.

@export var label_text: String = "SINGLE PLAYER":
	set(v):
		label_text = v
		if _label: _label.text = v
@export var glyph: Texture2D:
	set(v):
		glyph = v
		if _glyph: _glyph.texture = v
@export var glyph_size: int = 20:
	set(v):
		glyph_size = v
		if _glyph: _glyph.custom_minimum_size = Vector2(v, v)

var _row: HBoxContainer
var _glyph: TextureRect
var _label: Label


func _init() -> void:
	theme_type_variation = &"ERSMenuItem"
	custom_minimum_size = Vector2(200, 42)
	focus_mode = Control.FOCUS_ALL
	text = ""


func _ready() -> void:
	_build()
	_tint()
	for s in [mouse_entered, mouse_exited, focus_entered, focus_exited,
			button_down, button_up]:
		s.connect(_tint)


func _build() -> void:
	if _row: return
	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", 14)
	_row.offset_left = 14
	_row.offset_right = -12
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row, false, Node.INTERNAL_MODE_FRONT)

	_glyph = TextureRect.new()
	_glyph.custom_minimum_size = Vector2(glyph_size, glyph_size)
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyph.texture = glyph
	_row.add_child(_glyph)

	_label = Label.new()
	_label.text = label_text
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", 15)
	_row.add_child(_label)


func _tint() -> void:
	if not _label: return
	var lit := is_hovered() or has_focus() or button_pressed
	var col := Color(1, 1, 1) if lit else Color(0.8745, 0.9059, 0.9412)
	if disabled:
		col = Color(0.3333, 0.3882, 0.4353)
	_label.add_theme_color_override("font_color", col)
	_glyph.modulate = col
