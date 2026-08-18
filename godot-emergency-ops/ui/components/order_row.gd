class_name OrderRow
extends PanelContainer
## A line in the order panel: unit, stepper, line total.

signal changed(unit: UnitDef, delta: int)

var unit: UnitDef
var quantity: int = 0

var _qty: Label
var _total: Label
var _plus: Button


func setup(u: UnitDef, qty: int, can_add: bool) -> void:
	unit = u
	quantity = qty
	custom_minimum_size = Vector2(0, 52)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var tile := PanelContainer.new()
	tile.theme_type_variation = &"ERSInset"
	tile.custom_minimum_size = Vector2(34, 34)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tile)
	var g := TextureRect.new()
	g.texture = u.icon
	g.custom_minimum_size = Vector2(18, 18)
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.modulate = UnitCard.DIM
	tile.add_child(g)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	var nm := Label.new()
	nm.text = u.display_name
	nm.add_theme_font_size_override("font_size", 13)
	col.add_child(nm)

	_total = Label.new()
	_total.add_theme_font_size_override("font_size", 12)
	_total.add_theme_color_override("font_color", UnitCard.ACCENT)
	col.add_child(_total)

	var step := HBoxContainer.new()
	step.add_theme_constant_override("separation", 4)
	step.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(step)

	var minus := Button.new()
	minus.theme_type_variation = &"ERSSmall"
	minus.text = "−"
	minus.custom_minimum_size = Vector2(28, 28)
	minus.pressed.connect(func(): changed.emit(unit, -1))
	step.add_child(minus)

	_qty = Label.new()
	_qty.custom_minimum_size = Vector2(30, 0)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty.add_theme_font_size_override("font_size", 15)
	step.add_child(_qty)

	_plus = Button.new()
	_plus.theme_type_variation = &"ERSSmall"
	_plus.text = "+"
	_plus.custom_minimum_size = Vector2(28, 28)
	_plus.pressed.connect(func(): changed.emit(unit, 1))
	step.add_child(_plus)

	refresh(qty, can_add)


func refresh(qty: int, can_add: bool) -> void:
	quantity = qty
	_qty.text = str(qty)
	_total.text = "£ %s" % UnitCard._thousands(unit.cost * qty)
	_plus.disabled = not can_add
