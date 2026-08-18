extends VBoxContainer
class_name DispatchPanel

## Sending owned units out of the house, in the right-hand block of the bar: a row
## per type with what is waiting, and the purse in the block's heading.
##
## Buying does NOT live here any more. It started as per-row chips and the feedback
## was immediate: too small to find, too small to mean anything. The heading --
## "DISPATCH · £1,250 · BUY" -- opens the [RequisitionPanel], a proper storefront with the
## unit's portrait and what it is for; clicking a row that owns nothing opens it
## too, because the only sensible reading of that click is "I want one".
##
## Rows are built once and refreshed, because the roster's *shape* never changes:
## only the numbers on it do. They stay flat, not pills -- the block growing is how
## the bar has three times quietly eaten the controls above it.

var station: Station: set = _set_station
var controller: RTSController
## The storefront this panel opens. Wired by the HUD.
var shop: RequisitionPanel

## One column, since August 2026, when this block moved out of the bottom bar and into
## the left-hand strip under the roster.
##
## It was two for years, and the reason is worth keeping because it **inverted**: in a
## docked bar, height was the scarce thing (six types stacked in one column made the bar
## 185px tall and ate the CONTROLS chip -- four separate times) and width was free. In a
## 180px column it is exactly the other way round. Two columns of 126px rows simply do
## not fit, and there is room to spare below.
const COLUMNS := 1

var _rows: Array[HBoxContainer] = []
var _heading: Label
var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 3)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	# The block's heading label doubles as the purse readout and the shop door.
	_heading = get_parent().get_node_or_null("Heading") as Label
	if _heading:
		_heading.mouse_filter = Control.MOUSE_FILTER_STOP
		Hover.attach(_heading)
		_heading.gui_input.connect(_on_heading_input)
		_heading.tooltip_text = "Open the unit shop"


func _set_station(value: Station) -> void:
	station = value
	if station == null:
		return
	station.roster_changed.connect(_refresh)
	_build()
	_refresh()


func _build() -> void:
	for config in Station.TYPES:
		_rows.append(_build_row(config))


func _build_row(config: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	Hover.attach(row)
	row.custom_minimum_size = Vector2(126.0, 0.0)
	row.set_meta(&"id", config["id"])
	row.gui_input.connect(_on_row_input.bind(row))
	_grid.add_child(row)

	var mark := ServiceMark.new()
	mark.custom_minimum_size = Vector2(16.0, 16.0)
	mark.service = int(config["service"])
	mark.symbol = &"car" if config["vehicle"] else &"person"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.text = str(config["label"])
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var count := Label.new()
	count.theme_type_variation = &"HeaderLabel"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count)
	return row


func _refresh() -> void:
	if station == null:
		return
	if _heading:
		# The outstanding bill sits beside the purse, because it is money the player has
		# already spent and not yet been asked for -- a fleet that has been driven into
		# things is poorer than the funds line says, and finding that out at the debrief
		# is finding out too late to do anything about it.
		var owed := station.outstanding_repairs()
		# **The purse, and no longer the word BUY.** Buying moved to its own icon button
		# in the bottom-right corner; this label went back to being what it always
		# mostly was, a readout of what is in the till. It still opens the shop when
		# clicked -- money is a sensible thing to click when you want to spend it -- but
		# it no longer advertises itself as the only door.
		_heading.text = "£%d" % station.funds if owed <= 0 \
			else "£%d   ·   £%d damage" % [station.funds, owed]
	for row in _rows:
		var id: StringName = row.get_meta(&"id")
		var in_house := station.available(id)
		var kept := station.total(id)
		(row.get_child(2) as Label).text = "%d / %d" % [in_house, kept]
		# The whole row fades when the house is empty, so "none to send" reads
		# without being read -- but it still answers clicks (see _on_row_input).
		row.modulate = Color(1, 1, 1, 1) if in_house > 0 else Color(1, 1, 1, 0.4)
		row.tooltip_text = ("Send one out (%d in the house)" % in_house) \
			if in_house > 0 else ("All %d out on the district" % kept
				if kept > 0 else "None owned -- click to buy")


func _on_heading_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_heading.accept_event()
	if shop:
		shop.open_shop()


func _on_row_input(event: InputEvent, row: HBoxContainer) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT or station == null:
		return
	row.accept_event()
	var id: StringName = row.get_meta(&"id")
	# A click on a type with nothing owned means "I want one": open the shop.
	if station.total(id) == 0 and shop:
		shop.open_shop()
		return
	var unit := station.dispatch(id)
	# Selected on arrival, because the reason anyone pressed this was to send it
	# somewhere -- and hunting the forecourt for whichever one is new is a chore.
	if unit and controller:
		controller.select([unit])
