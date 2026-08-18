class_name UnitCard
extends Button
## Catalogue tile. Click adds one; the modal owns quantity and affordability and
## pushes them back in via set_state().

signal add_requested(unit: UnitDef)

const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)
const ACCENT := Color(0.2902, 0.6118, 0.9412)
const DANGER := Color(0.9412, 0.7059, 0.6667)

var unit: UnitDef
var quantity: int = 0
var affordable: bool = true

var _portrait: PanelContainer
var _glyph: TextureRect
var _name: Label
var _role: Label
var _cost_pill: PanelContainer
var _cost: Label
var _badge: Panel
var _badge_label: Label
var _chips: HBoxContainer


func setup(u: UnitDef) -> void:
	unit = u
	custom_minimum_size = Vector2(340, 132)
	theme_type_variation = &"ERSUnitCard"
	focus_mode = Control.FOCUS_ALL
	text = ""
	_build()
	pressed.connect(func(): add_requested.emit(unit))
	set_state(0, true)


func _build() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad, false, Node.INTERNAL_MODE_FRONT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	_portrait = PanelContainer.new()
	_portrait.theme_type_variation = &"ERSPortrait"
	_portrait.custom_minimum_size = Vector2(72, 72)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)

	_glyph = TextureRect.new()
	_glyph.texture = unit.icon
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# **`EXPAND_IGNORE_SIZE`, or the picture sets the card's width.** A [TextureRect]
	# defaults to `EXPAND_KEEP_SIZE`, so its minimum size is the *texture's* size and
	# `custom_minimum_size` is only a floor. The kit was drawn against 24x24 icons; this
	# game feeds it 192x192 rendered portraits, which blew the 72px portrait panel out to
	# 192px inside a 340px card and left about 48px for the text -- every unit name
	# truncated ("POLICE '", "RECOVERY 1", "AMBULA"), every price pill clipped.
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Larger than the kit's 34 because these are rendered vehicles rather than line
	# glyphs, and a lorry at 34px is a smudge. Still inside the 72px panel.
	_glyph.custom_minimum_size = Vector2(58, 58)
	_portrait.add_child(_glyph)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	_name = Label.new()
	_name.text = unit.display_name.to_upper()
	_name.theme_type_variation = &"ERSTitle"
	_name.add_theme_font_size_override("font_size", 15)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.clip_text = true
	top.add_child(_name)

	_cost_pill = PanelContainer.new()
	_cost_pill.theme_type_variation = &"ERSCostPill"
	# Trimmed from 90: these prices are three and four figures, not the kit's five, and
	# the 12px reclaimed goes to the name beside it.
	_cost_pill.custom_minimum_size = Vector2(78, 26)
	_cost_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_cost_pill)

	_cost = Label.new()
	_cost.text = "£ %s" % _thousands(unit.cost)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.add_theme_font_size_override("font_size", 13)
	_cost_pill.add_child(_cost)

	_role = Label.new()
	_role.text = unit.locked_reason if unit.locked_reason else unit.role
	_role.theme_type_variation = &"ERSBody"
	_role.add_theme_font_size_override("font_size", 12)
	# **Wrapped rather than clipped, and bounded to two lines.** Left alone, this label's
	# own minimum width pushed the card out -- two of thirteen came out 155-159px wide
	# against the others' 138, a ragged grid. Clipping evened them up but then genuinely
	# cut two descriptions off mid-phrase. Wrapping fixes both: an autowrapped label's
	# minimum width is its longest *word*, so it cannot widen the card, and the card has
	# the vertical room for a second line.
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_role.max_lines_visible = 2
	col.add_child(_role)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_chips)
	_chips.add_child(_chip(load("res://ui/art/icons/icon_group.svg"), str(unit.crew)))
	if unit.trait_text != "":
		_chips.add_child(_chip(unit.trait_icon, unit.trait_text))

	# quantity badge, pinned bottom-right
	_badge = Panel.new()
	_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_badge.offset_left = -39
	_badge.offset_top = -39
	_badge.offset_right = -13
	_badge.offset_bottom = -13
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	add_child(_badge, false, Node.INTERNAL_MODE_BACK)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1176, 0.4235, 0.7529)
	sb.border_color = Color(0.2902, 0.6118, 0.9412)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	_badge.add_theme_stylebox_override("panel", sb)

	_badge_label = Label.new()
	_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_label.add_theme_font_size_override("font_size", 14)
	_badge.add_child(_badge_label)


func _chip(tex: Texture2D, value: String) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ERSInset"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	if tex:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = Vector2(15, 15)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.modulate = DIM
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	return p


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


func set_state(qty: int, can_afford: bool) -> void:
	quantity = qty
	affordable = can_afford
	var locked := unit.locked_reason != ""
	var capped := unit.stock > 0 and qty >= unit.stock
	disabled = locked or (not can_afford and qty == 0)

	if locked:
		theme_type_variation = &"ERSUnitCardLocked"
	elif qty > 0:
		theme_type_variation = &"ERSUnitCardSelected"
	else:
		theme_type_variation = &"ERSUnitCard"

	if capped and not locked:
		disabled = true

	var live := not locked and (can_afford or qty > 0)
	_name.add_theme_color_override("font_color", TEXT if live else OFF)
	_role.add_theme_color_override("font_color", DIM if live else OFF)
	_glyph.modulate = ACCENT if qty > 0 else (DIM if live else OFF)
	_portrait.theme_type_variation = &"ERSPortraitSelected" if qty > 0 else &"ERSPortrait"
	_chips.modulate.a = 1.0 if live else 0.5

	_cost_pill.theme_type_variation = (&"ERSCostPill" if (can_afford or qty > 0)
			else &"ERSCostPillOver")
	_cost.add_theme_color_override("font_color",
			TEXT if live else (DANGER if not can_afford and not locked else OFF))

	_badge.visible = qty > 0
	_badge_label.text = str(qty)

	if locked:
		tooltip_text = unit.locked_reason
	elif capped:
		tooltip_text = "Only %d available" % unit.stock
	elif not can_afford:
		tooltip_text = "Not enough budget"
	else:
		tooltip_text = "%s — click to request" % unit.display_name
