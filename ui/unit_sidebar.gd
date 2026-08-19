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
## Every row and header ever made, kept for reuse. See [method _rebuild].
## Panel width open and shut. The expanded figure was set in two places that disagreed --
## `_ready` widened it to carry the vehicle tiles and collapsing put back the kit's
## original, so the panel shrank slightly the first time it was opened and closed.
const EXPANDED_WIDTH := 320
## A quarter of the open width. `custom_minimum_size` alone does not shrink this panel --
## it is a *minimum*, and the HUD block it sits in stretches it back out -- so collapsing
## also has to stop it expanding, and the host has to shrink with it.
const COLLAPSED_WIDTH := 80

var _rail: VBoxContainer
var _rail_tiles: Array[Control] = []
var _pool: Array[UnitRow] = []
var _headers: Array[Control] = []
var _counters: Dictionary = {}

@onready var _chips: HBoxContainer = %Chips
@onready var _list: VBoxContainer = %List
@onready var _count: Label = %CountValue
@onready var _empty: Label = %EmptyHint
@onready var _collapse: Button = %CollapseButton
@onready var _body: VBoxContainer = %Body
@onready var _footer: PanelContainer = %Footer


func _ready() -> void:
	custom_minimum_size.x = EXPANDED_WIDTH
	_rail = VBoxContainer.new()
	_rail.name = "Rail"
	_rail.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rail.add_theme_constant_override("separation", 8)
	_rail.visible = false
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.get_parent().add_child(_rail)
	_build_chips()
	_collapse.pressed.connect(toggle_collapsed)
	%RequestButton.pressed.connect(func(): request_units_pressed.emit())
	_rebuild()


## The row currently standing for [param instance], or null if it is filtered out.
##
## Exposed for the host: the tutorial pulses the row for a named unit, and reaching into
## `_rows` from outside would tie that caller to this file's private shape.
func row_for(instance: UnitInstance) -> UnitRow:
	for row in _rows:
		# `queue_free` is deferred, so `_rows` can still hold rows that are on their way out.
		if is_instance_valid(row) and row.unit == instance:
			return row
	return null


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


## Collapses to a rail listing each service and how many units it has.
##
## **Collapsed used to show nothing at all** -- the panel narrowed and the body was
## hidden, leaving a blank column with an arrow on it. A rail that still answers "how many
## police, how many fire" is the point of collapsing rather than closing: it gives the map
## back its width without giving up the count.
func toggle_collapsed() -> void:
	collapsed = not collapsed
	custom_minimum_size.x = COLLAPSED_WIDTH if collapsed else EXPANDED_WIDTH
	size_flags_horizontal = (Control.SIZE_SHRINK_BEGIN if collapsed
			else Control.SIZE_EXPAND_FILL)
	var host := get_parent() as Control
	if host:
		host.custom_minimum_size.x = custom_minimum_size.x
		host.size_flags_horizontal = size_flags_horizontal
	_body.visible = not collapsed
	_footer.visible = not collapsed
	_rail.visible = collapsed
	# **The header keeps the panel wide on its own.** Its title, glyph and count badge have
	# minimum widths that no amount of shrinking the panel can overrule -- collapsing left
	# it at 186px against the 80 asked for. Folding them away leaves just the arrow.
	for path in ["Rows/Header/Row/Glyph", "Rows/Header/Row/Title",
			"Rows/Header/Row/CountBadge"]:
		var node := get_node_or_null(path) as Control
		if node:
			node.visible = not collapsed
	_collapse.text = "›" if collapsed else "‹"
	if collapsed:
		_refresh_rail()


## One tile per service that has units, showing its letter and its count.
##
## Rebuilt in place like the rows are, for the same reason: nothing in this panel is
## destroyed while the game is running.
func _refresh_rail() -> void:
	var tally := {}
	for u in units:
		var key: StringName = u.def.category if u.def else &"support"
		tally[key] = int(tally.get(key, 0)) + 1
	var slot := 0
	for entry in FILTERS:
		var key: StringName = entry[0]
		if key == &"all" or not tally.has(key):
			continue
		var tile := _rail_tile(slot)
		slot += 1
		tile.visible = true
		(tile.get_node("Box/Letter") as Label).text = PREFIX.get(key, "U")
		(tile.get_node("Box/Count") as Label).text = str(tally[key])
		_rail.move_child(tile, slot - 1)
	for i in range(slot, _rail_tiles.size()):
		_rail_tiles[i].visible = false


func _rail_tile(index: int) -> Control:
	while _rail_tiles.size() <= index:
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"ERSPortraitSmall"
		tile.custom_minimum_size = Vector2(40, 44)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := VBoxContainer.new()
		box.name = "Box"
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(box)
		var letter := Label.new()
		letter.name = "Letter"
		letter.theme_type_variation = &"ERSTitle"
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(letter)
		var count := Label.new()
		count.name = "Count"
		count.theme_type_variation = &"ERSEyebrow"
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(count)
		_rail.add_child(tile)
		_rail_tiles.append(tile)
	return _rail_tiles[index]


## Lays the list out again, **reusing the rows rather than freeing them**.
##
## The kit's original freed every child and built new ones on each rebuild. Rows are
## focusable [Button]s carrying input handlers, and this list regroups on any status
## change -- so a unit being sent somewhere destroyed the row under the player's mouse,
## repeatedly. Three unreproducible hard crashes arrived with this panel and stopped the
## moment it was swapped out for the strip it replaced, which is what pointed here.
##
## Nodes are now pooled: they are re-pointed at a different unit, moved into place and
## hidden when spare. Nothing in the list is ever destroyed while the game is running.
func _rebuild() -> void:
	var shown: Array[UnitInstance] = []
	for u in units:
		if _filter == &"all" or (u.def and u.def.category == _filter):
			shown.append(u)
	_count.text = str(shown.size())
	if collapsed:
		_refresh_rail()
	_empty.visible = shown.is_empty()

	_rows.clear()
	var slot := 0
	var used_headers := 0
	for status in UnitInstance.GROUP_ORDER:
		var group: Array[UnitInstance] = []
		for u in shown:
			if u.status == status:
				group.append(u)
		if group.is_empty():
			continue
		var header := _header_at(used_headers)
		used_headers += 1
		_dress_header(header, status, group.size())
		header.visible = true
		_list.move_child(header, slot)
		slot += 1
		for u in group:
			var row := _row_at(_rows.size())
			row.rebind(u)
			row.set_selected(u == selected)
			row.visible = true
			_list.move_child(row, slot)
			slot += 1
			_rows.append(row)
	# Anything the pools did not need this time is parked, not destroyed.
	for i in range(used_headers, _headers.size()):
		_headers[i].visible = false
	for i in range(_rows.size(), _pool.size()):
		_pool[i].visible = false


## The pooled row at [param index], made on first use and kept thereafter.
func _row_at(index: int) -> UnitRow:
	while _pool.size() <= index:
		var row := UnitRow.new()
		_list.add_child(row)
		row.setup(units[0] if not units.is_empty() else UnitInstance.new())
		row.selected.connect(select)
		row.focus_requested.connect(func(x): focus_requested.emit(x))
		_pool.append(row)
	return _pool[index]


func _header_at(index: int) -> Control:
	while _headers.size() <= index:
		var header := _make_header()
		_list.add_child(header)
		_headers.append(header)
	return _headers[index]


## An empty group header. Split from [method _dress_header] so headers can be pooled and
## re-lettered rather than rebuilt, for the reason given on [method _rebuild].
func _make_header() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ERSGroupHeader"
	p.custom_minimum_size = Vector2(0, 26)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var dot := Panel.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)

	var l := Label.new()
	l.name = "Title"
	l.theme_type_variation = &"ERSEyebrow"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)

	var c := Label.new()
	c.name = "Count"
	c.theme_type_variation = &"ERSEyebrow"
	c.add_theme_color_override("font_color", Color(0.333, 0.388, 0.435))
	h.add_child(c)
	return p


## Points a pooled header at [param status] with [param n] units under it.
func _dress_header(header: Control, status: int, n: int) -> void:
	var row := header.get_child(0)
	var dot := row.get_node_or_null("Dot") as Panel
	if dot:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UnitInstance.STATUS_COLOR[status]
		sb.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", sb)
	var title := row.get_node_or_null("Title") as Label
	if title:
		title.text = UnitInstance.STATUS_LABEL[status]
	var count := row.get_node_or_null("Count") as Label
	if count:
		count.text = str(n)
