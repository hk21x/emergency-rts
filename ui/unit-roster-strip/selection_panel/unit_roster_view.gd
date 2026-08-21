class_name UnitRosterView
extends RefCounted
## Builds the bottom bar's no-selection state: the whole fleet, browsable.
##
## Three layouts, all selectable, all fitting the same 1100x188 dock:
##   STRIP   — a card per unit, scrolled sideways. Best under ~12 units.
##   GROUPED — columns by status or service. Best for triage.
##   TABLE   — dense rows, most data per unit. Best above ~16 units.

enum Layout { STRIP, GROUPED, TABLE }
enum GroupBy { STATUS, SERVICE }

const ICON := "res://selection_panel/art/icons/icon_%s.svg"
const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)

const SERVICE_COLOR := {
	&"fire": Color("e8734b"), &"police": Color("3f98f2"),
	&"medical": Color("4caf50"), &"support": Color("b6c4d4"),
}
const SERVICE_LABEL := {
	&"fire": "FIRE", &"police": "POLICE", &"medical": "MEDICAL", &"support": "SUPPORT",
}
const STATUS_ORDER := [UnitInstance.Status.ON_SCENE, UnitInstance.Status.EN_ROUTE,
		UnitInstance.Status.AVAILABLE, UnitInstance.Status.RETURNING,
		UnitInstance.Status.OFF_RUN]
const SERVICE_ORDER := [&"fire", &"police", &"medical", &"support"]


static func _flat(c: Color, r: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	return sb


static func _cond_colour(v: float) -> Color:
	return (Color("4caf50") if v >= 0.6 else Color("d8aa33") if v >= 0.35
			else Color("c4442f"))


static func _bar(width: float, value: float, height: int = 5) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, height)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078), 2))
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(value, 0.0, 1.0)
	fill.add_theme_stylebox_override("panel", _flat(_cond_colour(value), 2))
	track.add_child(fill)
	return track


static func _glyph(tex_name: String, size: int, colour: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(ICON % tex_name)
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = colour
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


static func _icon_name(u: UnitInstance) -> String:
	if u.def and u.def.icon:
		return u.def.icon.resource_path.get_file().trim_prefix("icon_").trim_suffix(".svg")
	return "truck"


static func _label(text: String, size: int, colour: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.theme_type_variation = &"ERSTitle"
		l.add_theme_font_size_override("font_size", size)
	return l


# ---------------------------------------------------------------------- API --
static func build(host: Control, units: Array, layout: Layout, group_by: GroupBy,
		on_pick: Callable) -> void:
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	match layout:
		Layout.STRIP:
			host.add_child(_strip(units, on_pick))
		Layout.GROUPED:
			host.add_child(_grouped(units, group_by, on_pick))
		Layout.TABLE:
			host.add_child(_table(units, on_pick))


# -------------------------------------------------------------------- STRIP --
static func _strip(units: Array, on_pick: Callable) -> Control:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	scroll.add_child(row)
	for u in units:
		row.add_child(_card(u, on_pick))
	return scroll


static func _card(u: UnitInstance, on_pick: Callable) -> Control:
	var alert: bool = u.condition < 0.35 or u.status == UnitInstance.Status.OFF_RUN
	var b := Button.new()
	b.theme_type_variation = &"ERSRosterCardAlert" if alert else &"ERSRosterCard"
	b.custom_minimum_size = Vector2(116, 124)
	b.tooltip_text = "%s — %s" % [u.callsign, u.def.display_name if u.def else ""]
	b.pressed.connect(func(): on_pick.call(u))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_top = 4
	col.offset_right = -8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)

	var stripe := Panel.new()
	stripe.custom_minimum_size = Vector2(0, 4)
	stripe.add_theme_stylebox_override("panel", _flat(u.status_color(), 2))
	col.add_child(stripe)

	var port := PanelContainer.new()
	port.theme_type_variation = &"ERSPortraitLarge"
	port.custom_minimum_size = Vector2(0, 44)
	port.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(port)
	port.add_child(_glyph(_icon_name(u), 22, Color("e8735c") if alert else DIM))

	var cs := _label(u.callsign, 15, TEXT, true)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cs)

	var ty := _label(u.def.display_name if u.def else "", 10, DIM)
	ty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ty.clip_text = true
	col.add_child(ty)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	var bar := _bar(60, u.condition)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(bar)
	foot.add_child(_label("%d/%d" % [u.seats_taken(), u.seats_total()], 10, DIM))
	return b


# ------------------------------------------------------------------ GROUPED --
static func _grouped(units: Array, group_by: GroupBy, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var keys: Array = STATUS_ORDER if group_by == GroupBy.STATUS else SERVICE_ORDER
	for key in keys:
		var members: Array = []
		for u in units:
			var k = u.status if group_by == GroupBy.STATUS else (
					u.def.category if u.def else &"support")
			if k == key:
				members.append(u)
		# an empty status column is noise; an empty service column is information
		if members.is_empty() and group_by == GroupBy.STATUS:
			continue
		row.add_child(_column(key, members, group_by, on_pick, keys.size() > 4))
	return row


static func _column(key, members: Array, group_by: GroupBy, on_pick: Callable,
		compact: bool = false) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)

	var colour: Color = (UnitInstance.STATUS_COLOR[key] if group_by == GroupBy.STATUS
			else SERVICE_COLOR.get(key, DIM))
	var label: String = (UnitInstance.STATUS_LABEL[key] if group_by == GroupBy.STATUS
			else SERVICE_LABEL.get(key, "OTHER"))

	var head := PanelContainer.new()
	head.theme_type_variation = &"ERSColumnHeader"
	head.custom_minimum_size = Vector2(0, 24)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	head.add_child(hb)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _flat(colour, 4))
	hb.add_child(dot)
	var l := _label(label, 10, DIM)
	l.theme_type_variation = &"ERSEyebrow"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	hb.add_child(_label(str(members.size()), 10, OFF))
	col.add_child(head)

	## Three slots per column. If there are more, the last slot becomes a
	## count — better than a scrollbar the player has to notice.
	for i in mini(members.size(), 3):
		if i == 2 and members.size() > 3:
			var more := _label("+%d more" % (members.size() - 2), 11, OFF)
			more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			more.custom_minimum_size = Vector2(0, 34)
			more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			col.add_child(more)
			break
		col.add_child(_compact_row(members[i], on_pick, compact))
	return col


static func _compact_row(u: UnitInstance, on_pick: Callable,
		compact: bool = false) -> Control:
	var alert: bool = u.condition < 0.35 or u.status == UnitInstance.Status.OFF_RUN
	var b := Button.new()
	b.theme_type_variation = &"ERSCompactRowAlert" if alert else &"ERSCompactRow"
	b.custom_minimum_size = Vector2(0, 34)
	b.tooltip_text = "%s — %d/%d aboard" % [u.callsign, u.seats_taken(), u.seats_total()]
	b.pressed.connect(func(): on_pick.call(u))

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -8
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)

	var stripe := Panel.new()
	stripe.custom_minimum_size = Vector2(3, 22)
	stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stripe.add_theme_stylebox_override("panel", _flat(u.status_color(), 2))
	h.add_child(stripe)
	h.add_child(_glyph(_icon_name(u), 18, DIM))
	var cs := _label(u.callsign, 13, TEXT, true)
	if compact:
		cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cs)
	## Five status columns leave no room for the type — a half-clipped
	## "Aerial Platf" is worse than no label, and the glyph already says it.
	if not compact:
		var ty := _label(u.def.display_name if u.def else "", 10, DIM)
		ty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ty.clip_text = true
		h.add_child(ty)
	h.add_child(_label("%d/%d" % [u.seats_taken(), u.seats_total()], 10, DIM))
	h.add_child(_bar(44, u.condition))
	return b


# -------------------------------------------------------------------- TABLE --
const COLUMNS := ["CALLSIGN", "TYPE", "STATUS", "CREW", "CONDITION"]
const COL_W := [96, 150, 120, 56, 96]


static func _table(units: Array, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var half := int(ceil(units.size() / 2.0))
	for c in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.add_child(_table_head())
		for i in range(c * half, mini((c + 1) * half, units.size())):
			col.add_child(_table_row(units[i], i % 2 == 1, on_pick))
		row.add_child(col)
	return row


static func _table_head() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ERSTableHeader"
	p.custom_minimum_size = Vector2(0, 24)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	p.add_child(h)
	for i in COLUMNS.size():
		var l := _label(COLUMNS[i], 9, DIM)
		l.theme_type_variation = &"ERSEyebrow"
		l.custom_minimum_size = Vector2(COL_W[i], 0)
		if i == COLUMNS.size() - 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return p


static func _table_row(u: UnitInstance, alt: bool, on_pick: Callable) -> Control:
	var alert: bool = u.condition < 0.35 or u.status == UnitInstance.Status.OFF_RUN
	var b := Button.new()
	b.theme_type_variation = &"ERSCompactRowAlert" if alert else &"ERSCompactRow"
	b.custom_minimum_size = Vector2(0, 25)
	b.flat = not alert
	b.tooltip_text = "%s — click to select" % u.callsign
	b.pressed.connect(func(): on_pick.call(u))

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)

	var name_box := HBoxContainer.new()
	name_box.custom_minimum_size = Vector2(COL_W[0], 0)
	name_box.add_theme_constant_override("separation", 8)
	name_box.add_child(_glyph(_icon_name(u), 15, DIM))
	name_box.add_child(_label(u.callsign, 12, TEXT, true))
	h.add_child(name_box)

	var ty := _label(u.def.display_name if u.def else "", 11, DIM)
	ty.custom_minimum_size = Vector2(COL_W[1], 0)
	ty.clip_text = true
	h.add_child(ty)

	var st := HBoxContainer.new()
	st.custom_minimum_size = Vector2(COL_W[2], 0)
	st.add_theme_constant_override("separation", 7)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _flat(u.status_color(), 4))
	st.add_child(dot)
	st.add_child(_label(u.status_label().capitalize(), 11, u.status_color()))
	h.add_child(st)

	var crew := _label("%d/%d" % [u.seats_taken(), u.seats_total()], 11, DIM)
	crew.custom_minimum_size = Vector2(COL_W[3], 0)
	h.add_child(crew)

	var bar := _bar(COL_W[4], u.condition, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bar)
	return b
