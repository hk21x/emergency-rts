class_name UnitSidebar
extends PanelContainer
## Left-docked roster. Groups by status, filters by service, collapses to a rail.
##
##   sidebar.add_unit(unit_def)            # auto-assigns the next callsign
##   sidebar.unit_selected.connect(...)
##   sidebar.focus_requested.connect(...)  # double-click

signal unit_selected(unit: UnitInstance)
signal focus_requested(unit: UnitInstance)
signal request_units_pressed

const FILTERS := [[&"all", "ALL"], [&"fire", "FIRE"], [&"police", "POL"],
		[&"medical", "MED"], [&"support", "SUP"]]
## Callsign prefixes by service, so units read like real ones.
const PREFIX := {&"fire": "F", &"police": "P", &"medical": "A", &"support": "S"}

var units: Array[UnitInstance] = []
var selected: UnitInstance
var collapsed: bool = false

var _filter: StringName = &"all"
var _rows: Array[UnitRow] = []
var _counters: Dictionary = {}

@onready var _chips: HBoxContainer = %Chips
@onready var _list: VBoxContainer = %List
@onready var _count: Label = %CountValue
@onready var _empty: Label = %EmptyHint
@onready var _collapse: Button = %CollapseButton
@onready var _body: VBoxContainer = %Body
@onready var _footer: PanelContainer = %Footer


func _ready() -> void:
	custom_minimum_size.x = 300
	_build_chips()
	_collapse.pressed.connect(toggle_collapsed)
	%RequestButton.pressed.connect(func(): request_units_pressed.emit())
	_rebuild()


# ------------------------------------------------------------------ roster --
func add_unit(def: UnitDef, callsign: String = "") -> UnitInstance:
	var u := UnitInstance.new()
	u.def = def
	u.callsign = callsign if callsign else _next_callsign(def)
	u.status = UnitInstance.Status.AVAILABLE
	u.task = "Station 1"
	units.append(u)
	_rebuild()
	return u


func _next_callsign(def: UnitDef) -> String:
	## Skips anything already on the roster, so auto-assigned callsigns can't
	## collide with ones you set by hand.
	var p: String = PREFIX.get(def.category, "U")
	var taken := {}
	for u in units:
		taken[u.callsign] = true
	var i := int(_counters.get(p, 0))
	var candidate := ""
	while true:
		i += 1
		candidate = "%s%02d" % [p, i]
		if not taken.has(candidate):
			break
	_counters[p] = i
	return candidate


func remove_unit(u: UnitInstance) -> void:
	units.erase(u)
	if selected == u:
		selected = null
	_rebuild()


func select(u: UnitInstance) -> void:
	selected = u
	for r in _rows:
		r.set_selected(r.unit == u)
	unit_selected.emit(u)


# ------------------------------------------------------------------ layout --
func _build_chips() -> void:
	for f in FILTERS:
		var b := Button.new()
		b.text = f[1]
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = &"ERSChipActive" if f[0] == _filter else &"ERSChip"
		b.set_meta(&"cat", f[0])
		b.pressed.connect(_on_filter.bind(f[0]))
		_chips.add_child(b)


func _on_filter(cat: StringName) -> void:
	_filter = cat
	for b in _chips.get_children():
		b.theme_type_variation = (&"ERSChipActive" if b.get_meta(&"cat") == cat
				else &"ERSChip")
	_rebuild()


func toggle_collapsed() -> void:
	collapsed = not collapsed
	custom_minimum_size.x = 56 if collapsed else 300
	_body.visible = not collapsed
	_footer.visible = not collapsed
	_collapse.text = "›" if collapsed else "‹"


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()

	var shown: Array[UnitInstance] = []
	for u in units:
		if _filter == &"all" or (u.def and u.def.category == _filter):
			shown.append(u)
	_count.text = str(shown.size())
	_empty.visible = shown.is_empty()

	for status in UnitInstance.GROUP_ORDER:
		var group: Array[UnitInstance] = []
		for u in shown:
			if u.status == status:
				group.append(u)
		if group.is_empty():
			continue
		_list.add_child(_group_header(status, group.size()))
		for u in group:
			var row := UnitRow.new()
			_list.add_child(row)
			row.setup(u)
			row.set_selected(u == selected)
			row.selected.connect(select)
			row.focus_requested.connect(func(x): focus_requested.emit(x))
			_rows.append(row)


func _group_header(status: int, n: int) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ERSGroupHeader"
	p.custom_minimum_size = Vector2(0, 26)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UnitInstance.STATUS_COLOR[status]
	sb.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", sb)
	h.add_child(dot)

	var l := Label.new()
	l.text = UnitInstance.STATUS_LABEL[status]
	l.theme_type_variation = &"ERSEyebrow"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)

	var c := Label.new()
	c.text = str(n)
	c.theme_type_variation = &"ERSEyebrow"
	c.add_theme_color_override("font_color", Color(0.333, 0.388, 0.435))
	h.add_child(c)
	return p
