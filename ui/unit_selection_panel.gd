class_name UnitSelectionPanel
extends PanelContainer
## Bottom-docked selection window: health, occupancy by role, carried liquid,
## current order and the command grid.
##
##   panel.show_units([unit])          # detail
##   panel.show_units(selected_units)  # group view, switches on its own
##   panel.clear()

signal command_issued(action: StringName, units: Array)
signal unit_focused(unit: UnitInstance)

const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)
const ACCENT := Color(0.2902, 0.6118, 0.9412)

## action id, icon, label, categories that can obey it ([] = anyone)
const COMMANDS := [
	[&"move", "move", "Move", []],
	[&"extinguish", "water_jet", "Extinguish", [&"fire"]],
	[&"treat", "medical", "Treat", [&"medical"]],
	[&"rescue", "hand", "Rescue", [&"fire", &"medical"]],
	[&"secure", "cone", "Secure scene", [&"police"]],
	[&"resupply", "fuel", "Resupply", []],
	[&"return", "home", "Return to station", []],
	[&"hold", "stop", "Hold position", []],
]

var units: Array[UnitInstance] = []
var primary: UnitInstance
var active_command: StringName = &""

var _cmd_buttons: Dictionary = {}

@onready var _status: Label = %StatusLabel
@onready var _status_dot: Panel = %StatusDot
@onready var _count: Label = %CountLabel
@onready var _detail: HBoxContainer = %Detail
@onready var _group: VBoxContainer = %Group
@onready var _empty: VBoxContainer = %Empty
@onready var _body: HBoxContainer = %Body
@onready var _portrait: PanelContainer = %Portrait
@onready var _glyph: TextureRect = %Glyph
@onready var _callsign: Label = %Callsign
@onready var _type: Label = %TypeLabel
@onready var _health_fill: Panel = %HealthFill
@onready var _health_pct: Label = %HealthPct
@onready var _liquid: PanelContainer = %LiquidChip
@onready var _liquid_label: Label = %LiquidLabel
@onready var _liquid_value: Label = %LiquidValue
@onready var _liquid_fill: Panel = %LiquidFill
@onready var _slots: HBoxContainer = %Slots
@onready var _group_fill: Panel = %GroupFill
@onready var _group_pct: Label = %GroupPct
@onready var _group_note: Label = %GroupNote
@onready var _seats: GridContainer = %Seats
@onready var _seat_count: Label = %SeatCount
@onready var _tally: VBoxContainer = %Tally
@onready var _grid: GridContainer = %CommandGrid
@onready var _order_icon: TextureRect = %OrderIcon
@onready var _order_title: Label = %OrderTitle
@onready var _order_detail: Label = %OrderDetail
@onready var _order_track: Panel = %OrderTrack
@onready var _order_fill: Panel = %OrderFill
@onready var _order_left: Label = %OrderLeft
@onready var _order_right: Label = %OrderRight
@onready var _order_head: Label = %OrderHead


func _ready() -> void:
	custom_minimum_size = Vector2(1100, 188)
	_build_commands()
	clear()


func _flat(c: Color, r: int = 3, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	return sb


func _icon(n: String) -> Texture2D:
	return load("res://ui/art/icons/icon_%s.svg" % n)


# ------------------------------------------------------------------- public --
func show_units(list: Array) -> void:
	units.clear()
	for u in list:
		units.append(u)
	primary = units[0] if not units.is_empty() else null
	_refresh()


func clear() -> void:
	units.clear()
	primary = null
	_refresh()


# ----------------------------------------------------------------- commands --
func _build_commands() -> void:
	for c in COMMANDS:
		var b := Button.new()
		b.theme_type_variation = &"ERSCommand"
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = c[2]
		b.pressed.connect(_on_command.bind(c[0]))
		var t := TextureRect.new()
		t.texture = _icon(c[1])
		t.custom_minimum_size = Vector2(22, 22)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
		b.set_meta(&"glyph", t)
		_grid.add_child(b)
		_cmd_buttons[c[0]] = b


func _allowed(action: StringName) -> bool:
	if units.is_empty():
		return false
	for c in COMMANDS:
		if c[0] != action:
			continue
		var cats: Array = c[3]
		if cats.is_empty():
			return true
		# every selected unit must be able to obey, or the order is ambiguous
		for u in units:
			if u.def == null or not cats.has(u.def.category):
				return false
		return true
	return false


func _on_command(action: StringName) -> void:
	active_command = action
	command_issued.emit(action, units.duplicate())
	_refresh_commands()


func _refresh_commands() -> void:
	for c in COMMANDS:
		var b: Button = _cmd_buttons[c[0]]
		var ok := _allowed(c[0])
		b.disabled = not ok
		b.theme_type_variation = (&"ERSCommandActive" if ok and c[0] == active_command
				else &"ERSCommand")
		var g: TextureRect = b.get_meta(&"glyph")
		## Chunky glyphs still read as live at OFF, so unavailable orders lose
		## alpha too — colour alone made the same state look like two states.
		g.modulate = (Color.WHITE if ok and c[0] == active_command
				else TEXT if ok else Color(0.30, 0.35, 0.41, 0.5))


# ------------------------------------------------------------------ refresh --
func _refresh() -> void:
	var n := units.size()
	_empty.visible = n == 0
	_body.visible = n > 0
	_detail.visible = n == 1
	_group.visible = n > 1

	if n == 0:
		_count.text = ""
		_status.text = ""
		_status_dot.visible = false
		_clear(_seats)
		_clear(_tally)
		_seat_count.text = ""
		_refresh_commands()
		return

	_status_dot.visible = n == 1
	if n == 1:
		_count.text = ""
		_status.text = primary.status_label()
		_status.add_theme_color_override("font_color", primary.status_color())
		_status_dot.add_theme_stylebox_override("panel", _flat(primary.status_color(), 4))
		_fill_detail()
	else:
		_count.text = "%d SELECTED" % n
		_status.text = ""
		_fill_group()
	_fill_occupancy()
	_refresh_commands()


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _cond_colour(v: float) -> Color:
	return (Color("4caf50") if v >= 0.6 else Color("d8aa33") if v >= 0.35
			else Color("c4442f"))


func _fill_detail() -> void:
	var u := primary
	_glyph.texture = u.def.icon if u.def else null
	# **Untinted.** This washed the portrait in the service colour -- fire red, everything
	# else grey -- which is right for the kit's monochrome SVG icons and wrong for a
	# photograph: it put a red overlay across the actual render of the appliance. The
	# service is already carried by the status word, the stripe and the callsign prefix.
	_glyph.modulate = Color.WHITE
	_portrait.theme_type_variation = &"ERSPortraitLargeSelected"
	_callsign.text = u.callsign
	_type.text = u.def.display_name.to_upper() if u.def else ""
	_health_fill.anchor_right = clampf(u.condition, 0.0, 1.0)
	_health_fill.add_theme_stylebox_override("panel", _flat(_cond_colour(u.condition)))
	_health_pct.text = "%d%%" % roundi(u.condition * 100)

	# the liquid chip only exists for units that actually carry something
	var carries: bool = u.def != null and u.def.carries_liquid
	_liquid.visible = carries
	if carries:
		_liquid_label.text = u.def.liquid_label.to_upper()
		_liquid_value.text = "%s L" % _thousands(u.liquid_litres())
		_liquid_fill.anchor_right = clampf(u.liquid, 0.0, 1.0)
		_liquid_fill.add_theme_stylebox_override("panel", _flat(Color("3f98f2")))

	_order_head.text = "CURRENT ORDER"
	_order_icon.visible = true
	_order_icon.texture = _icon("move")
	_order_icon.modulate = u.status_color()
	_order_title.text = u.status_label().capitalize()
	_order_detail.text = u.task
	# **The real figure.** This drew a hardcoded 0.62 and printed the string "62%" for any
	# unit that happened to be EN ROUTE -- a bar that looked live, never moved, and said the
	# same thing about every journey. The order reports its own progress now: a cordon fills
	# as the cones go out, a fire empties as it is put out, a drive fills as it is driven.
	var done := u.progress
	_order_track.visible = done >= 0.0
	if done >= 0.0:
		_order_fill.anchor_right = clampf(done, 0.0, 1.0)
		_order_fill.add_theme_stylebox_override("panel", _flat(u.status_color()))
	_order_left.text = "IN PROGRESS" if done >= 0.0 else ""
	_order_left.add_theme_color_override("font_color", u.status_color())
	_order_right.text = "%d%%" % roundi(clampf(done, 0.0, 1.0) * 100.0) if done >= 0.0 else ""


## What the CURRENT ORDER bar is drawing right now: whether the track is up at all, the
## fill as a 0..1 fraction, and the caption printed beside it.
##
## **Exposed rather than reached for.** These nodes belong to this scene, and a check that
## walked `%OrderFill` by path would be coupled to the kit's node names instead of to the
## behaviour. It is here because the bar had no witness of any kind: it drew a hardcoded
## 0.62 and printed "62%" for every unit that happened to be EN ROUTE, which looked live
## on screen and was the same lie about every journey.
func order_readout() -> Dictionary:
	return {
		"shown": _order_track.visible,
		"fill": _order_fill.anchor_right,
		"caption": _order_right.text,
	}


func _fill_group() -> void:
	_clear(_slots)
	for u in units:
		_slots.add_child(_slot(u))

	var sum := 0.0
	var worst: UnitInstance = units[0]
	for u in units:
		sum += u.condition
		if u.condition < worst.condition:
			worst = u
	var avg := sum / units.size()
	_group_fill.anchor_right = clampf(avg, 0.0, 1.0)
	_group_fill.add_theme_stylebox_override("panel", _flat(_cond_colour(avg)))
	_group_pct.text = "%d%%" % roundi(avg * 100)
	_group_note.text = "%s lowest at %d%%" % [worst.callsign, roundi(worst.condition * 100)]
	_group_note.add_theme_color_override("font_color", _cond_colour(worst.condition))

	_order_head.text = "ORDERS"
	_order_icon.visible = false
	var distinct := {}
	for u in units:
		distinct[u.status] = true
	_order_title.text = "Mixed" if distinct.size() > 1 else units[0].status_label().capitalize()
	_order_detail.text = "%d distinct order%s" % [distinct.size(),
			"" if distinct.size() == 1 else "s"]
	_order_track.visible = false
	_order_left.text = ""
	_order_right.text = ""


# --------------------------------------------------------------- occupancy --
func _fill_occupancy() -> void:
	_clear(_seats)
	_clear(_tally)

	var occ: Array[StringName] = []
	var total := 0
	for u in units:
		total += u.seats_total()
		for r in u.occupants:
			occ.append(r)

	_seat_count.text = "%d / %d" % [occ.size(), total]
	_seats.columns = 6 if units.size() == 1 else 7

	## Cap the strip so a big multi-select can't blow the panel height. Anything
	## past the cap is still counted in the tally below.
	var cap: int = _seats.columns * 2
	var shown: int = mini(total, cap)
	for i in shown:
		_seats.add_child(_seat(occ[i] if i < occ.size() else &""))
	if total > cap:
		var more := Label.new()
		more.text = "+%d" % (total - cap)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", OFF)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_seats.add_child(more)

	var tally := {}
	for r in occ:
		tally[r] = int(tally.get(r, 0)) + 1

	if units.size() == 1:
		## One unit has few roles, so spell them out.
		for role in tally:
			_tally.add_child(_tally_row(role, tally[role]))
	else:
		## A mixed group can carry five or six roles; full-width rows would push
		## the panel taller than its dock, so pack them three to a line.
		var row: HBoxContainer = null
		var i := 0
		for role in tally:
			if i % 3 == 0:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 12)
				_tally.add_child(row)
			row.add_child(_tally_chip(role, tally[role]))
			i += 1


func _seat(role: StringName) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(24, 24)
	if role == &"":
		p.add_theme_stylebox_override("panel",
				_flat(Color(0.047, 0.071, 0.106), 4, Color(0.094, 0.133, 0.180), 1))
		var dot := Panel.new()
		dot.set_anchors_preset(Control.PRESET_CENTER)
		dot.offset_left = -3
		dot.offset_top = -3
		dot.offset_right = 3
		dot.offset_bottom = 3
		dot.add_theme_stylebox_override("panel", _flat(Color(0.333, 0.388, 0.435, 0.5), 3))
		p.add_child(dot)
		p.tooltip_text = "Empty seat"
		return p

	var col: Color = UnitInstance.ROLE_COLOR.get(role, DIM)
	p.add_theme_stylebox_override("panel", _flat(Color(0.067, 0.098, 0.145), 4, col, 2))
	var t := TextureRect.new()
	t.texture = _icon("occ_%s" % role)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 4
	t.offset_top = 4
	t.offset_right = -4
	t.offset_bottom = -4
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = col
	p.add_child(t)
	p.tooltip_text = UnitInstance.ROLE_LABEL.get(role, "Crew")
	return p


func _tally_row(role: StringName, n: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var col: Color = UnitInstance.ROLE_COLOR.get(role, DIM)
	var t := TextureRect.new()
	t.texture = _icon("occ_%s" % role)
	t.custom_minimum_size = Vector2(16, 16)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = col
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var l := Label.new()
	l.text = "%d × %s" % [n, UnitInstance.ROLE_LABEL.get(role, "Crew")]
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	return h


func _tally_chip(role: StringName, n: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.tooltip_text = "%d × %s" % [n, UnitInstance.ROLE_LABEL.get(role, "Crew")]
	var col: Color = UnitInstance.ROLE_COLOR.get(role, DIM)
	var t := TextureRect.new()
	t.texture = _icon("occ_%s" % role)
	t.custom_minimum_size = Vector2(15, 15)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = col
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var l := Label.new()
	l.text = str(n)
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	return h


func _slot(u: UnitInstance) -> Control:
	var b := Button.new()
	b.theme_type_variation = (&"ERSSelectSlotActive" if u == primary else &"ERSSelectSlot")
	b.custom_minimum_size = Vector2(52, 58)
	b.tooltip_text = "%s — %d/%d aboard" % [u.callsign, u.seats_taken(), u.seats_total()]
	b.pressed.connect(func():
		primary = u
		unit_focused.emit(u)
		_refresh())

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)

	var t := TextureRect.new()
	t.texture = u.def.icon if u.def else null
	t.custom_minimum_size = Vector2(0, 24)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = ACCENT if u == primary else DIM
	col.add_child(t)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 5)
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078), 2))
	col.add_child(track)
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(u.condition, 0.0, 1.0)
	fill.add_theme_stylebox_override("panel", _flat(_cond_colour(u.condition), 2))
	track.add_child(fill)

	var l := Label.new()
	l.text = u.callsign
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", TEXT if u == primary else DIM)
	col.add_child(l)
	return b


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
