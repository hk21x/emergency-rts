extends HFlowContainer
class_name Roster

## Every unit under command, as a strip of avatars in the middle of the bar.
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
## Chips are pooled rather than freed. `queue_free` does not take effect until the end
## of the frame, so a rebuild that frees and adds in the same frame briefly shows both
## sets -- which is what made the old command bar flicker when the selection changed
## twice in quick succession.

## Wired from a setter, not from _ready. Godot readies children before their parent, so
## by the time the HUD hands this panel its controller the panel's own _ready has long
## since run -- reading the reference there finds null and the strip stays empty.
var controller: RTSController: set = _set_controller

var _chips: Array[UnitChip] = []
## Units currently on the strip, so a rebuild only happens when the roster really
## changed rather than every time the selection moves.
var _listed: Array[Unit] = []


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
	if units != _listed:
		_listed = units
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


func _rebuild() -> void:
	while _chips.size() < _listed.size():
		var chip := UnitChip.new()
		chip.clicked.connect(_on_clicked)
		chip.focused.connect(_on_focused)
		_chips.append(chip)
		add_child(chip)

	for i in _chips.size():
		var chip := _chips[i]
		chip.visible = i < _listed.size()
		# Dropped, or the chip keeps a reference to a unit that may be freed.
		chip.unit = _listed[i] if chip.visible else null


func _mark_selection() -> void:
	var lead := controller.primary()
	for i in _listed.size():
		var chip := _chips[i]
		chip.set_selected(_listed[i].is_selected, _listed[i] == lead)


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
