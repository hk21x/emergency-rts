extends Control
## Sidebar and purchase modal working together: request units, they land in the
## roster, selection and status changes flow back out.

@onready var _sidebar: UnitSidebar = %Sidebar
@onready var _modal: UnitPurchaseModal = %Modal
@onready var _readout: Label = %Readout
@onready var _selection: UnitSelectionPanel = %Selection

var _catalogue: Array[UnitDef] = []


func _ready() -> void:
	_catalogue = UnitCatalog.default_units()
	_modal.visible = false
	_sidebar.request_units_pressed.connect(func(): _modal.open(12450))
	_modal.confirmed.connect(_on_confirmed)
	_sidebar.unit_selected.connect(_on_selected)
	_selection.command_issued.connect(_on_command)
	_selection.unit_focused.connect(_on_focus)
	_sidebar.focus_requested.connect(_on_focus)
	_seed()


func _on_selected(u: UnitInstance) -> void:
	_readout.text = "%s selected — %s" % [u.callsign, u.status_label().to_lower()]
	_selection.show_units([u])


func _on_command(action: StringName, list: Array) -> void:
	var names := []
	for u in list:
		names.append(u.callsign)
	_readout.text = "%s → %s" % [str(action).to_upper(), ", ".join(names)]


func _on_focus(u: UnitInstance) -> void:
	_readout.text = "Centring camera on %s" % u.callsign


func _by_id(id: StringName) -> UnitDef:
	for u in _catalogue:
		if u.id == id:
			return u
	return null


func _on_confirmed(order: Dictionary, total: int) -> void:
	var n := 0
	for id in order:
		for i in int(order[id]):
			_sidebar.add_unit(_by_id(id))
			n += 1
	_readout.text = "Dispatched %d units for £%s" % [n, UnitCard._thousands(total)]


func _seed() -> void:
	## A few units mid-incident so the grouping and alert states are visible.
	var seed: Array = [
		[&"patrol", "P21", UnitInstance.Status.ON_SCENE, 0.86, "Securing"],
		[&"dsu", "A14", UnitInstance.Status.ON_SCENE, 0.62, "Treating"],
		[&"pump", "F01", UnitInstance.Status.EN_ROUTE, 1.0, "ETA 0:42"],
		[&"aerial", "F03", UnitInstance.Status.EN_ROUTE, 0.94, "ETA 1:18"],
		[&"patrol", "P22", UnitInstance.Status.AVAILABLE, 1.0, "Station 2"],
		[&"welfare", "S01", UnitInstance.Status.AVAILABLE, 1.0, "Station 2"],
		[&"pump", "F02", UnitInstance.Status.OFF_RUN, 0.24, "Damaged"],
	]
	## occupants beyond the default crew: casualties picked up, officers riding along
	var extra := {
		"A14": [&"casualty"],
		"P21": [&"officer"],
		"F02": [],
	}
	for row in seed:
		var u: UnitInstance = _sidebar.add_unit(_by_id(row[0]), str(row[1]))
		u.status = row[2]
		u.condition = row[3]
		u.task = row[4]
		if extra.has(u.callsign):
			for r in extra[u.callsign]:
				u.occupants.append(r)
		if u.callsign == "F01":
			u.liquid = 0.79
		elif u.callsign == "F02":
			u.occupants = [&"driver"] as Array[StringName]
			u.liquid = 0.1
	_sidebar._rebuild()
	_sidebar.select(_sidebar.units[2])
	_selection.show_units([_sidebar.units[2]])
