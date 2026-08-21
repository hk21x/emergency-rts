extends Control
## Live harness: poke the panel and watch it react.

const ICON := "res://selection_panel/art/icons/icon_%s.svg"

var _unit: UnitInstance
var _fleet: Array[UnitInstance] = []

@onready var _panel: UnitSelectionPanel = %Panel
@onready var _log: Label = %Log


func _ready() -> void:
	_fleet = _build_fleet()
	_panel.show_roster(_fleet)
	_unit = _fleet[0]
	_panel.show_unit(_unit)
	_panel.command_issued.connect(func(a: StringName, u: UnitInstance):
		_log.text = "%s → %s" % [str(a).to_upper(), u.callsign])

	%HealthSlider.value_changed.connect(func(v: float):
		_unit.condition = v / 100.0
		_panel.refresh())
	%LiquidSlider.value_changed.connect(func(v: float):
		_unit.liquid = v / 100.0
		_panel.refresh())
	%UnitPicker.item_selected.connect(_pick_unit)
	%StatusButton.pressed.connect(_cycle_status)
	%AddCasualty.pressed.connect(func(): _add(&"casualty"))
	%AddCrew.pressed.connect(func(): _add(&"firefighter"))
	%RemoveSeat.pressed.connect(func():
		if not _unit.occupants.is_empty():
			_unit.occupants.remove_at(_unit.occupants.size() - 1)
			_panel.refresh())
	%ClearButton.pressed.connect(func():
		_panel.clear()
		_log.text = "Nothing selected — the bar shows the roster instead")
	%LayoutPicker.item_selected.connect(func(i: int):
		match i:
			0: _panel.roster_layout = UnitRosterView.Layout.STRIP
			1:
				_panel.roster_layout = UnitRosterView.Layout.GROUPED
				_panel.roster_group_by = UnitRosterView.GroupBy.STATUS
			2:
				_panel.roster_layout = UnitRosterView.Layout.GROUPED
				_panel.roster_group_by = UnitRosterView.GroupBy.SERVICE
			3: _panel.roster_layout = UnitRosterView.Layout.TABLE
		_panel.clear())
	_panel.unit_selected.connect(func(u: UnitInstance):
		_unit = u
		_log.text = "%s selected from the roster" % u.callsign)
	for label in ["Roster: strip", "Roster: by status", "Roster: by service",
			"Roster: table"]:
		%LayoutPicker.add_item(label)

	for label in ["Fire Engine", "Ambulance", "Patrol Car", "Air Ambulance"]:
		%UnitPicker.add_item(label)


func _build_fleet() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	var spec := [
		["F01", "Fire Engine", &"fire", "truck", 6, true, 1800,
			UnitInstance.Status.EN_ROUTE, 0.94, [&"driver", &"firefighter",
			&"firefighter", &"firefighter", &"firefighter"]],
		["F03", "Aerial Platform", &"fire", "water_jet", 4, true, 1200,
			UnitInstance.Status.EN_ROUTE, 0.90, [&"driver", &"firefighter", &"firefighter"]],
		["A14", "Ambulance", &"medical", "medical", 4, false, 0,
			UnitInstance.Status.ON_SCENE, 0.62, [&"driver", &"paramedic", &"casualty"]],
		["P21", "Patrol Car", &"police", "shield_person", 4, false, 0,
			UnitInstance.Status.ON_SCENE, 0.86, [&"driver", &"officer", &"civilian"]],
		["F04", "Fire Engine", &"fire", "truck", 6, true, 1800,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"firefighter",
			&"firefighter", &"firefighter", &"firefighter"]],
		["A15", "Ambulance", &"medical", "medical", 4, false, 0,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"paramedic"]],
		["H01", "Air Ambulance", &"medical", "helicopter", 5, false, 0,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"paramedic", &"paramedic"]],
		["P22", "Patrol Car", &"police", "shield_person", 4, false, 0,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"officer"]],
		["P23", "Armed Response", &"police", "shield", 5, false, 0,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"officer", &"officer"]],
		["S01", "Welfare Unit", &"support", "home", 8, true, 400,
			UnitInstance.Status.AVAILABLE, 1.0, [&"driver", &"firefighter"]],
		["S02", "Command Unit", &"support", "clipboard", 6, false, 0,
			UnitInstance.Status.RETURNING, 0.95, [&"driver", &"officer", &"firefighter"]],
		["F02", "Fire Engine", &"fire", "truck", 6, true, 1800,
			UnitInstance.Status.OFF_RUN, 0.24, [&"driver"]],
	]
	for row in spec:
		var d := UnitDef.new()
		d.display_name = row[1]
		d.category = row[2]
		d.icon = load(ICON % row[3])
		d.seats = row[4]
		d.carries_liquid = row[5]
		d.liquid_capacity = row[6]
		var u := UnitInstance.new()
		u.def = d
		u.callsign = row[0]
		u.status = row[7]
		u.condition = row[8]
		var occ: Array[StringName] = []
		for r in row[9]:
			occ.append(r)
		u.occupants = occ
		u.liquid = 0.79
		u.task = "Marlowe Street fire" if row[7] == UnitInstance.Status.EN_ROUTE else "Station 1"
		u.order_progress = 0.62 if row[7] == UnitInstance.Status.EN_ROUTE else -1.0
		out.append(u)
	return out


func _add(role: StringName) -> void:
	if _unit.seats_taken() >= _unit.seats_total():
		_log.text = "%s is full (%d seats)" % [_unit.callsign, _unit.seats_total()]
		return
	_unit.occupants.append(role)
	_panel.refresh()


func _cycle_status() -> void:
	_unit.status = ((_unit.status + 1) % UnitInstance.Status.size()) as UnitInstance.Status
	_unit.order_progress = 0.62 if _unit.status == UnitInstance.Status.EN_ROUTE else -1.0
	_panel.refresh()


func _pick_unit(idx: int) -> void:
	var d := UnitDef.new()
	match idx:
		0:
			d.display_name = "Fire Engine"; d.category = &"fire"; d.seats = 6
			d.carries_liquid = true; d.liquid_label = "Water"; d.liquid_capacity = 1800
			d.icon = load(ICON % "truck")
			_unit.callsign = "F01"
			_unit.occupants = [&"driver", &"firefighter", &"firefighter",
					&"firefighter", &"firefighter"] as Array[StringName]
		1:
			d.display_name = "Ambulance"; d.category = &"medical"; d.seats = 4
			d.icon = load(ICON % "medical")
			_unit.callsign = "A14"
			_unit.occupants = [&"driver", &"paramedic", &"casualty"] as Array[StringName]
		2:
			d.display_name = "Patrol Car"; d.category = &"police"; d.seats = 4
			d.icon = load(ICON % "shield_person")
			_unit.callsign = "P21"
			_unit.occupants = [&"driver", &"officer"] as Array[StringName]
		3:
			d.display_name = "Air Ambulance"; d.category = &"medical"; d.seats = 5
			d.icon = load(ICON % "helicopter")
			_unit.callsign = "H01"
			_unit.occupants = [&"driver", &"paramedic", &"paramedic",
					&"casualty"] as Array[StringName]
	_unit.def = d
	_panel.show_unit(_unit)
	_log.text = "%s selected — liquid chip %s" % [_unit.callsign,
			"shown" if d.carries_liquid else "hidden"]
