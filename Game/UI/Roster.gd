extends VBoxContainer
class_name Roster

## Every unit under command, as rows of avatars down the left-hand column.
##
## The whole roster, not just what happens to be selected. That is the difference
## between a readout and a control: you can send the parked ambulance from here without
## first finding it in the street, and one glance says how much of the shift is already
## committed -- pale avatars are standing by, solid ones are working.
##
## Membership is "every unit with a service", which is exactly the set the player
## commands. Civilians and ambient traffic are `Service.NONE` and never appear, so the
## roster cannot fill up with shoppers.
##
## **And every unit still in the station**, as a dimmed chip at the end of its row --
## click one to send it out. That closes the gap between what this file has always
## claimed ("pale avatars are standing by") and what it could actually show, since a unit
## in the house is not in the scene tree. It also makes this the only place units are
## dispatched from: the DISPATCH block that used to list Patrol / Ambulance / ... as rows
## was removed in August 2026 at the user's ask, and `Station.dispatch()` had no other
## caller in the interface.
##
## **One row per service**, since August 2026. It was a single flow of chips that wrapped
## wherever it ran out of width, so a patrol car and an ambulance shared a line and the
## next ambulance started a new one -- an arrangement that changes shape every time a unit
## is bought, and which reads as no arrangement at all. Now police are on one line,
## medical on the next, fire on the next, and the strip only changes when the *fleet*
## does. A service with more units than the column is wide still wraps within its own
## row; it never mixes with another service.
##
## Chips are pooled rather than freed. `queue_free` does not take effect until the end
## of the frame, so a rebuild that frees and adds in the same frame briefly shows both
## sets -- which is what made the old command bar flicker when the selection changed
## twice in quick succession. Pooling across *rows* means a chip is reparented rather
## than replaced when the fleet changes shape.

## The order the rows sit in, top to bottom. Fixed rather than "whichever service turned
## up first", so the ambulance row does not move because a patrol car was sold.
const SERVICES := [Unit.Service.POLICE, Unit.Service.MEDICAL, Unit.Service.FIRE]

## Wired from a setter, not from _ready. Godot readies children before their parent, so
## by the time the HUD hands this panel its controller the panel's own _ready has long
## since run -- reading the reference there finds null and the strip stays empty.
var controller: RTSController: set = _set_controller
## The books, for the standby half of the strip. Without it the roster still works and
## simply shows nothing in the station.
var station: Station

var _chips: Array[UnitChip] = []
## Units currently on the strip, so a rebuild only happens when the roster really
## changed rather than every time the selection moves.
var _listed: Array[Unit] = []
## One [constant Station.TYPES] entry per unit sitting in the house.
var _standby: Array[Dictionary] = []
## `service -> HFlowContainer`. Built once and kept; a row with nothing in it is hidden
## rather than freed, so the rows never have to be rebuilt in the right order.
var _rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	for service: int in SERVICES:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		add_child(row)
		_rows[service] = row


func _set_controller(value: RTSController) -> void:
	controller = value
	if controller == null:
		return
	controller.selection_changed.connect(_on_selection_changed)
	_refresh()


## Scanned every frame rather than driven by a signal. Units appear and disappear on
## dispatch, and a roster that lagged half a second behind the button that filled it
## would read as a broken button. Forty-odd nodes filtered by an integer compare is
## nothing next to what it buys.
func _process(_delta: float) -> void:
	if controller:
		_refresh()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_refresh()


func _refresh() -> void:
	var units := _commanded()
	var waiting := _in_the_house()
	if units != _listed or waiting != _standby:
		_listed = units
		_standby = waiting
		_rebuild()
	_mark_selection()


## Every unit the player commands, in the order the map spawned them.
func _commanded() -> Array[Unit]:
	var found: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit != null and unit.service != Unit.Service.NONE:
			found.append(unit)
	return found


## One entry per unit owned but not on the map, in [constant Station.TYPES] order.
##
## Per *unit*, not per type: the strip is one chip per unit everywhere else, and a type
## with three in the house showing as one chip would make the roster disagree with the
## fleet count in the top bar.
func _in_the_house() -> Array[Dictionary]:
	var waiting: Array[Dictionary] = []
	if station == null:
		return waiting
	for config: Dictionary in Station.TYPES:
		for i in station.available(config["id"]):
			waiting.append(config)
	return waiting


func _rebuild() -> void:
	var wanted := _listed.size() + _standby.size()
	while _chips.size() < wanted:
		var chip := UnitChip.new()
		chip.clicked.connect(_on_clicked)
		chip.focused.connect(_on_focused)
		chip.dispatch_requested.connect(_on_dispatch_requested)
		_chips.append(chip)
		# Parented properly by the pass below; a row is needed now only so the chip is
		# inside the tree and runs its `_ready`.
		(_rows[SERVICES[0]] as Control).add_child(chip)

	# Deal the pool out service by service: everything of that service on the map first,
	# then everything of it still in the station.
	var next := 0
	for service: int in SERVICES:
		var row := _rows[service] as HFlowContainer
		var placed := 0
		for unit in _listed:
			if unit.service != service:
				continue
			_place(_chips[next], row, placed, unit, {})
			next += 1
			placed += 1
		for config in _standby:
			if int(config["service"]) != service:
				continue
			_place(_chips[next], row, placed, null, config)
			next += 1
			placed += 1
		# A service the career owns nothing of contributes no row at all, rather than an
		# empty band of card between two that have units in them.
		row.visible = placed > 0

	for i in range(next, _chips.size()):
		_chips[i].visible = false
		# Dropped, or the chip keeps a reference to a unit that may be freed.
		_chips[i].unit = null
		_chips[i].standby = {}


## Puts [param chip] at [param index] in [param row], showing either a unit or a type.
func _place(chip: UnitChip, row: HFlowContainer, index: int,
		unit: Unit, standby: Dictionary) -> void:
	if chip.get_parent() != row:
		chip.reparent(row, false)
	row.move_child(chip, index)
	chip.visible = true
	# Order matters: clearing the unit first means a chip recycled from the on-map half
	# into the standby half never draws a stale portrait for a frame.
	chip.unit = unit
	chip.standby = standby


## Rings whichever chips are selected.
##
## Walks the chips rather than indexing them against `_listed`, because grouping by
## service means chip *i* is no longer unit *i* -- an assumption that survived the
## regroup would have rung the wrong avatars.
func _mark_selection() -> void:
	var lead := controller.primary()
	for chip in _chips:
		if chip.unit == null:
			continue
		chip.set_selected(chip.unit.is_selected, chip.unit == lead)


## The chip standing for a unit of [param id] waiting in the station, or null.
##
## Public because two other things need to point at exactly this control -- the tutorial's
## spotlight and the suite's click -- and both were reaching into `_chips` to do it. A
## pool is an implementation detail; which chip means "an ambulance in the house" is not.
func standby_chip(id: StringName) -> UnitChip:
	for chip in _chips:
		if chip.visible and not chip.standby.is_empty() \
				and chip.standby.get("id", &"") == id:
			return chip
	return null


func _on_clicked(unit: Unit, additive: bool) -> void:
	# An officer riding in a car is still listed -- greyed -- but selecting them would
	# only have the controller drop them again on the next frame.
	if controller == null or not unit.is_selectable():
		return
	if additive:
		controller.toggle(unit)
	else:
		controller.select([unit])


func _on_focused(unit: Unit) -> void:
	if controller and unit.is_selectable():
		controller.follow(unit)


## Sends one of [param id] out of the house, and selects it.
##
## Selected on arrival because the reason anyone pressed this was to send it somewhere,
## and hunting the forecourt for whichever one is new is a chore. Carried over verbatim
## from the dispatch rows this replaced.
func _on_dispatch_requested(id: StringName) -> void:
	if station == null:
		return
	var unit := station.dispatch(id)
	if unit and controller:
		controller.select([unit])
