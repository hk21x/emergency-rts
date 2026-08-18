class_name UnitRow
extends Button
## One line in the unit sidebar. Click selects; double-click asks the game to
## put the camera on it.

signal selected(unit: UnitInstance)
signal focus_requested(unit: UnitInstance)

const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)
const ACCENT := Color(0.2902, 0.6118, 0.9412)

var unit: UnitInstance
var is_selected: bool = false

var _stripe: Panel
var _portrait: PanelContainer
var _glyph: TextureRect
var _bar_fill: Panel
var _callsign: Label
var _type: Label
var _dot: Panel
var _alert: TextureRect
var _status: Label
var _task: Label


func setup(u: UnitInstance) -> void:
	unit = u
	custom_minimum_size = Vector2(284, 62)
	focus_mode = Control.FOCUS_ALL
	text = ""
	_build()
	pressed.connect(func(): selected.emit(unit))
	gui_input.connect(_on_gui_input)
	refresh()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.double_click 			and event.button_index == MOUSE_BUTTON_LEFT:
		focus_requested.emit(unit)


func _flat(colour: Color, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(radius)
	return sb


func _build() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad, false, Node.INTERNAL_MODE_FRONT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	_stripe = Panel.new()
	_stripe.custom_minimum_size = Vector2(4, 0)
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_stripe)

	# portrait with a condition bar tucked underneath
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 3)
	pcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pcol)

	_portrait = PanelContainer.new()
	_portrait.theme_type_variation = &"ERSPortraitSmall"
	_portrait.custom_minimum_size = Vector2(40, 34)
	pcol.add_child(_portrait)

	_glyph = TextureRect.new()
	_glyph.texture = unit.def.icon if unit.def else null
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.custom_minimum_size = Vector2(20, 20)
	_portrait.add_child(_glyph)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(40, 5)
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078)))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcol.add_child(track)

	_bar_fill = Panel.new()
	_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar_fill)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	_callsign = Label.new()
	_callsign.text = unit.callsign
	_callsign.theme_type_variation = &"ERSTitle"
	_callsign.add_theme_font_size_override("font_size", 16)
	mid.add_child(_callsign)

	_type = Label.new()
	_type.text = unit.def.display_name if unit.def else ""
	_type.theme_type_variation = &"ERSBody"
	_type.add_theme_font_size_override("font_size", 11)
	_type.clip_text = true
	mid.add_child(_type)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 3)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_END
	srow.add_theme_constant_override("separation", 6)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(srow)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(7, 7)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(_dot)

	_alert = TextureRect.new()
	_alert.texture = load("res://ui/art/icons/icon_alert.svg")
	_alert.custom_minimum_size = Vector2(13, 13)
	_alert.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_alert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_alert.visible = false
	srow.add_child(_alert)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	srow.add_child(_status)

	_task = Label.new()
	_task.theme_type_variation = &"ERSBody"
	_task.add_theme_font_size_override("font_size", 11)
	_task.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_task)


func refresh() -> void:
	var col := unit.status_color()
	var attention := unit.needs_attention()
	var dead := unit.status == UnitInstance.Status.OFF_RUN

	if is_selected:
		theme_type_variation = &"ERSUnitRowSelected"
	elif attention:
		theme_type_variation = &"ERSUnitRowAlert"
	elif dead:
		theme_type_variation = &"ERSUnitRowOffline"
	else:
		theme_type_variation = &"ERSUnitRow"

	_stripe.add_theme_stylebox_override("panel", _flat(col))
	_portrait.theme_type_variation = (&"ERSPortraitSmallSelected" if is_selected
			else &"ERSPortraitSmall")
	_glyph.modulate = ACCENT if is_selected else (OFF if dead else DIM)

	var bar := (Color("4caf50") if unit.condition >= 0.6
			else Color("d8aa33") if unit.condition >= 0.35 else Color("c4442f"))
	_bar_fill.add_theme_stylebox_override("panel", _flat(bar))
	_bar_fill.anchor_right = clampf(unit.condition, 0.0, 1.0)

	_callsign.add_theme_color_override("font_color", OFF if dead and not attention else TEXT)
	_type.add_theme_color_override("font_color", OFF if dead else DIM)
	_dot.add_theme_stylebox_override("panel", _flat(col, 4))
	_dot.visible = not attention
	_alert.visible = attention
	_alert.modulate = col
	_status.text = unit.status_label()
	_status.add_theme_color_override("font_color", col)
	_task.text = unit.task
	tooltip_text = "%s — %s\nCondition %d%%" % [unit.callsign,
			unit.def.display_name if unit.def else "", roundi(unit.condition * 100)]


func set_selected(v: bool) -> void:
	is_selected = v
	refresh()
