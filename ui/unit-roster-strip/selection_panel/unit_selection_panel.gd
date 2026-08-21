@tool
class_name UnitSelectionPanel
extends PanelContainer
## Bottom-docked selection window for one unit: health, occupancy by role,
## carried liquid, current order and the command grid.
##
##   panel.show_unit(my_unit)
##   panel.clear()
##   panel.command_issued.connect(func(action, unit): issue_order(action, unit))
##
## Call refresh() after mutating the unit in place — the panel doesn't poll.

signal command_issued(action: StringName, unit: UnitInstance)
## Fired when the player picks a unit out of the roster view.
signal unit_selected(unit: UnitInstance)
## Fired when they back out of a unit to the roster.
signal selection_cleared

const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)

## action id, icon, label, categories that may obey it ([] = anyone)
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

const ICON_PATH := "res://selection_panel/art/icons/icon_%s.svg"

## Seats are drawn in a grid this wide; a taller unit spills to a second row.
@export var seat_columns: int = 6
## Which roster view fills the bar when nothing is selected.
@export var roster_layout: UnitRosterView.Layout = UnitRosterView.Layout.STRIP:
	set(v):
		roster_layout = v
		if is_node_ready():
			refresh()
@export var roster_group_by: UnitRosterView.GroupBy = UnitRosterView.GroupBy.STATUS:
	set(v):
		roster_group_by = v
		if is_node_ready():
			refresh()
## Shows sample data in the editor so you can lay the HUD out without running.
@export var preview_in_editor: bool = true:
	set(v):
		preview_in_editor = v
		if is_inside_tree():
			_apply_preview()

var unit: UnitInstance
var active_command: StringName = &""
## Everything selectable. Shown when `unit` is null.
var roster: Array[UnitInstance] = []
var _strip_instance: UnitRosterStrip
var filter: StringName = &"all"

var _cmd_buttons: Dictionary = {}

@onready var _status: Label = %StatusLabel
@onready var _status_dot: Panel = %StatusDot
@onready var _body: HBoxContainer = %Body
@onready var _empty: VBoxContainer = %Empty
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
@onready var _seats: GridContainer = %Seats
@onready var _seat_count: Label = %SeatCount
@onready var _tally: VBoxContainer = %Tally
@onready var _grid: GridContainer = %CommandGrid
@onready var _roster: MarginContainer = %Roster
@onready var _chips: HBoxContainer = %Chips
@onready var _back: Button = %BackButton
@onready var _order_icon: TextureRect = %OrderIcon
@onready var _order_title: Label = %OrderTitle
@onready var _order_detail: Label = %OrderDetail
@onready var _order_track: Panel = %OrderTrack
@onready var _order_fill: Panel = %OrderFill
@onready var _order_left: Label = %OrderLeft
@onready var _order_right: Label = %OrderRight


const FILTERS := [[&"all", "ALL"], [&"fire", "FIRE"], [&"police", "POL"],
		[&"medical", "MED"], [&"support", "SUP"]]


func _ready() -> void:
	custom_minimum_size = Vector2(1100, 188)
	_build_commands()
	_build_chips()
	_back.pressed.connect(clear)
	_apply_preview()


func _build_chips() -> void:
	if _chips.get_child_count() > 0:
		return
	for f in FILTERS:
		var b := Button.new()
		b.text = f[1]
		b.custom_minimum_size = Vector2(62, 26)
		b.theme_type_variation = &"ERSChipActive" if f[0] == filter else &"ERSChip"
		b.set_meta(&"cat", f[0])
		b.pressed.connect(_on_filter.bind(f[0]))
		_chips.add_child(b)


func _on_filter(cat: StringName) -> void:
	filter = cat
	for b in _chips.get_children():
		b.theme_type_variation = (&"ERSChipActive" if b.get_meta(&"cat") == cat
				else &"ERSChip")
	refresh()


## STRIP is a scene rather than a code-built layout, so it keeps its scroll
## position and selection across filter changes instead of rebuilding wholesale.
func _build_strip() -> void:
	if _strip_instance == null or not is_instance_valid(_strip_instance):
		for c in _roster.get_children():
			_roster.remove_child(c)
			c.queue_free()
		_strip_instance = preload(
				"res://selection_panel/unit_roster_strip.tscn").instantiate()
		_strip_instance.preview_in_editor = false
		_roster.add_child(_strip_instance)
		_strip_instance.unit_picked.connect(show_unit)
	_strip_instance.set_units(_filtered())


func _filtered() -> Array:
	if filter == &"all":
		return roster
	var out: Array = []
	for u in roster:
		if u.def and u.def.category == filter:
			out.append(u)
	return out


## Hand the panel everything selectable. It shows the roster whenever no unit
## is picked, so the bar is never dead space.
func show_roster(units: Array) -> void:
	roster.clear()
	for u in units:
		roster.append(u)
	refresh()


func _apply_preview() -> void:
	if unit == null and Engine.is_editor_hint() and preview_in_editor:
		show_unit(sample_unit())
	else:
		refresh()


# ------------------------------------------------------------------- public --
func show_unit(u: UnitInstance) -> void:
	unit = u
	active_command = &""
	refresh()
	if u != null:
		unit_selected.emit(u)


func clear() -> void:
	unit = null
	active_command = &""
	refresh()
	selection_cleared.emit()


## Sample data, also used for the editor preview.
static func sample_unit() -> UnitInstance:
	var d := UnitDef.new()
	d.id = &"pump"
	d.display_name = "Fire Engine"
	d.category = &"fire"
	d.seats = 6
	d.carries_liquid = true
	d.liquid_label = "Water"
	d.liquid_capacity = 1800
	d.icon = load(ICON_PATH % "truck")
	var u := UnitInstance.new()
	u.def = d
	u.callsign = "F01"
	u.condition = 0.94
	u.liquid = 0.79
	u.status = UnitInstance.Status.EN_ROUTE
	u.task = "Marlowe Street fire"
	u.order_progress = 0.62
	u.occupants = [&"driver", &"firefighter", &"firefighter", &"firefighter",
			&"firefighter"] as Array[StringName]
	return u


# ----------------------------------------------------------------- commands --
func _build_commands() -> void:
	if not _cmd_buttons.is_empty():
		return
	for c in COMMANDS:
		var b := Button.new()
		b.theme_type_variation = &"ERSCommand"
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = c[2]
		b.pressed.connect(_on_command.bind(c[0]))
		var t := TextureRect.new()
		t.texture = load(ICON_PATH % c[1])
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.offset_left = 11
		t.offset_top = 11
		t.offset_right = -11
		t.offset_bottom = -11
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
		b.set_meta(&"glyph", t)
		_grid.add_child(b)
		_cmd_buttons[c[0]] = b


func can_issue(action: StringName) -> bool:
	if unit == null or unit.def == null:
		return false
	for c in COMMANDS:
		if c[0] == action:
			var cats: Array = c[3]
			return cats.is_empty() or cats.has(unit.def.category)
	return false


func _on_command(action: StringName) -> void:
	active_command = action
	command_issued.emit(action, unit)
	_refresh_commands()


func _refresh_commands() -> void:
	for c in COMMANDS:
		var b: Button = _cmd_buttons.get(c[0])
		if b == null:
			continue
		var ok := can_issue(c[0])
		b.disabled = not ok
		b.theme_type_variation = (&"ERSCommandActive" if ok and c[0] == active_command
				else &"ERSCommand")
		var g: TextureRect = b.get_meta(&"glyph")
		## Unavailable orders lose alpha as well as colour — at OFF alone, chunky
		## glyphs still read as live while thin ones read as dead.
		g.modulate = (Color.WHITE if ok and c[0] == active_command
				else TEXT if ok else Color(0.30, 0.35, 0.41, 0.5))


# ------------------------------------------------------------------ refresh --
func refresh() -> void:
	if not is_node_ready():
		return
	var live := unit != null
	var has_roster := not roster.is_empty()
	_body.visible = live
	_roster.visible = not live and has_roster
	_empty.visible = not live and not has_roster
	_status_dot.visible = live
	_back.visible = live and has_roster
	_chips.visible = not live and has_roster

	if not live:
		_status.text = ""
		_clear(_seats)
		_clear(_tally)
		_seat_count.text = ""
		_refresh_commands()
		if has_roster:
			if roster_layout == UnitRosterView.Layout.STRIP:
				_build_strip()
			else:
				_strip_instance = null
				UnitRosterView.build(_roster, _filtered(), roster_layout,
						roster_group_by, show_unit)
		return

	_status.text = unit.status_label()
	_status.add_theme_color_override("font_color", unit.status_color())
	_status_dot.add_theme_stylebox_override("panel", _flat(unit.status_color(), 4))

	_fill_identity()
	_fill_occupancy()
	_fill_order()
	_refresh_commands()


func _flat(c: Color, r: int = 3, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	return sb


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _cond_colour(v: float) -> Color:
	return (Color("4caf50") if v >= 0.6 else Color("d8aa33") if v >= 0.35
			else Color("c4442f"))


func _fill_identity() -> void:
	_glyph.texture = unit.def.icon if unit.def else null
	_glyph.modulate = (Color("c4442f") if unit.def and unit.def.category == &"fire"
			else DIM)
	_portrait.theme_type_variation = &"ERSPortraitLargeSelected"
	_callsign.text = unit.callsign
	_type.text = unit.def.display_name.to_upper() if unit.def else ""
	_health_fill.anchor_right = clampf(unit.condition, 0.0, 1.0)
	_health_fill.add_theme_stylebox_override("panel", _flat(_cond_colour(unit.condition)))
	_health_pct.text = "%d%%" % roundi(unit.condition * 100)

	## The chip is absent, not empty, for units that carry nothing.
	var carries: bool = unit.def != null and unit.def.carries_liquid
	_liquid.visible = carries
	if carries:
		_liquid_label.text = unit.def.liquid_label.to_upper()
		_liquid_value.text = "%s L" % thousands(unit.liquid_litres())
		_liquid_fill.anchor_right = clampf(unit.liquid, 0.0, 1.0)
		_liquid_fill.add_theme_stylebox_override("panel", _flat(Color("3f98f2")))


func _fill_occupancy() -> void:
	_clear(_seats)
	_clear(_tally)
	var taken := unit.seats_taken()
	var total := unit.seats_total()
	_seat_count.text = "%d / %d" % [taken, total]
	_seats.columns = maxi(seat_columns, 1)

	## Two rows max; anything beyond spills into a +N so a bus-sized unit can't
	## stretch the panel past its dock.
	var cap: int = _seats.columns * 2
	for i in mini(total, cap):
		_seats.add_child(_seat(unit.occupants[i] if i < taken else &""))
	if total > cap:
		var more := Label.new()
		more.text = "+%d" % (total - cap)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", OFF)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_seats.add_child(more)

	var tally := unit.role_tally()
	for role in tally:
		_tally.add_child(_tally_row(role, tally[role]))


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
	t.texture = load(ICON_PATH % ("occ_%s" % role))
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
	t.texture = load(ICON_PATH % ("occ_%s" % role))
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


func _fill_order() -> void:
	_order_icon.texture = load(ICON_PATH % "move")
	_order_icon.modulate = unit.status_color()
	_order_title.text = unit.status_label().capitalize()
	_order_detail.text = unit.task
	var p := unit.order_progress
	_order_track.visible = p >= 0.0
	if p >= 0.0:
		_order_fill.anchor_right = clampf(p, 0.0, 1.0)
		_order_fill.add_theme_stylebox_override("panel", _flat(unit.status_color()))
		_order_left.text = "IN PROGRESS"
		_order_left.add_theme_color_override("font_color", unit.status_color())
		_order_right.text = "%d%%" % roundi(p * 100)
	else:
		_order_left.text = ""
		_order_right.text = ""


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
