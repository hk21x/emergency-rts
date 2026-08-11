extends Node3D
class_name Station

## The station: the career's home. Where money is banked, units are bought, and
## where they come back to.
##
## One station covers the whole district. Emergency 4 has a house per service, but
## this map has one forecourt with everything parked on it, and splitting the roster
## across two buildings would buy nothing except a longer walk.
##
## The fleet is **owned, not issued**. A new career starts with money and no units:
## everything on the map was bought with earnings from completed calls, and a unit
## sent home *parks on the forecourt* -- it is an asset, not a consumable, and
## freeing it (which is what accept() used to do) read as the game repossessing what
## the player had paid for. "Available" is therefore derived: what is owned minus
## what is already standing somewhere on the map.
##
## Funds and the owned fleet persist in [member career_path] -- the third and last
## save-shaped file, after the mission's records and the menu's settings. A fire
## service later is one more row in TYPES with a price on it.

signal roster_changed
## A vehicle drove in with suspects in the back and handed them over.
signal booked_in(vehicle: Vehicle, count: int)

## Emitted when a vehicle's damage is settled, with what it cost.
signal repaired(vehicle: Vehicle, cost: int)

const GROUP := &"stations"

## A fresh career's purse. Deliberately tight: it buys roughly one patrol car, one
## officer, one ambulance and one paramedic, with change for nothing.
const STARTING_FUNDS := 2000

## Where the crew portraits live; vehicles carry theirs in their own scenes.
const PORTRAITS := "res://Game/UI/Portraits/"

## What can be bought, in the order the dispatch panel lists it. `portrait` names
## the rendered preview in Game/UI/Portraits/ (vehicles also carry theirs baked
## into their scenes); `blurb` is what the shop says the unit is for.
const TYPES := [
	{
		"id": &"patrol", "label": "Patrol", "scene": "res://Game/Vehicles/PoliceCar.tscn",
		"service": Unit.Service.POLICE, "vehicle": true, "price": 600,
		"portrait": "SM_Veh_Car_Police_01",
		"blurb": ["Fast response car, seats 2 crew.",
			"Takes a detained suspect in the back."],
	},
	{
		"id": &"ambulance", "label": "Ambulance",
		"scene": "res://Game/Vehicles/Ambulance.tscn",
		"service": Unit.Service.MEDICAL, "vehicle": true, "price": 900,
		"portrait": "SM_Veh_Car_Ambo_01",
		"blurb": ["Carries a casualty to hospital.",
			"The stretcher lives in the back. Seats 2."],
	},
	{
		"id": &"engine", "label": "Fire Engine",
		"scene": "res://Game/Vehicles/FireEngine.tscn",
		"service": Unit.Service.FIRE, "vehicle": true, "price": 1400,
		"portrait": "FireEngine",
		"blurb": ["Carries four crew, and the hose they work from.",
			"Park it at the scene: reach is 18m.",
			"Buildings scale up as the crew grows."],
	},
	{
		"id": &"officer", "label": "Officer", "scene": "res://Game/Person.tscn",
		"service": Unit.Service.POLICE, "vehicle": false, "price": 200,
		"portrait": "Character_Male_Police",
		"blurb": ["Apprehends suspects, fights small fires,",
			"secures scenes with a cordon."],
	},
	{
		"id": &"firefighter", "label": "Firefighter",
		"scene": "res://Game/Firefighter.tscn",
		"service": Unit.Service.FIRE, "vehicle": false, "price": 300,
		"portrait": "Firefighter",
		"blurb": ["Puts fires out properly, and is the only",
			"unit a burning building yields to.",
			"Every one hired makes buildings bigger."],
	},
	{
		"id": &"paramedic", "label": "Paramedic", "scene": "res://Game/Paramedic.tscn",
		"service": Unit.Service.MEDICAL, "vehicle": false, "price": 250,
		"portrait": "Character_Female_Police",
		"blurb": ["Treats casualties where they lie,",
			"then wheels them to the ambulance."],
	},
]

## Where a dispatched or returning unit stands. Two rows of four: the fleet can now
## grow, and a yard that only held four would stack a fifth on top of the first.
@export var slot_count := 8
@export var slot_pitch := 5.2
## Towards the STREET, away from the building. Measured, not chosen: from the
## opening camera the station's own roof swallows everything on the building side
## of the apron centre (a pick ray at z >= +0.5 hits the block, not the unit), and
## the first unit a career ever bought spawned there -- alive, selected, and
## invisible. Both rows now stand on the street side, where the ray reaches them.
@export var slot_depth := 4.2
@export var slot_row_pitch := 2.8
## A slot with a unit this close is taken.
@export var slot_clearance := 3.6
## How close a returning unit has to get before it stands down. The forecourt is 20m
## across and 10m deep, so this covers the whole yard: anywhere a unit can park is
## home, and a vehicle that stops short of the middle has still arrived.
@export var return_radius := 11.0

## Node the dispatched units are parented to, so they land beside the rest of the
## fleet rather than under the station.
@export var units_path: NodePath

## The purse and the fleet. Persisted; see career_path.
var funds := STARTING_FUNDS
## Spent on repairs since the shift opened. The debrief reports it; nothing else reads it.
var repairs_paid := 0
var owned := {}
## A var rather than a const so the test suite can point the career at a disposable
## file -- the same contract records_path and settings_path honour.
var career_path := "user://career.cfg"

## Running count per type, so a second patrol car is Patrol 2 and not Patrol 1 again.
var _issued := {}


func _ready() -> void:
	add_to_group(GROUP)
	_load_career()


## The custody door. Like the hospital, delivery is automatic on arrival: driving a
## suspect into the yard is the player saying what they mean. Polled against the same
## radius the returns use rather than hung on an Area3D, because the forecourt is
## generated geometry and the yard *is* that circle.
func _physics_process(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.suspects.is_empty():
			continue
		if is_home(vehicle.global_position):
			var count := vehicle.deliver_suspects()
			if count > 0:
				booked_in.emit(vehicle, count)


# --- The career ---------------------------------------------------------------

func price(id: StringName) -> int:
	var config := _config(id)
	return 0 if config.is_empty() else int(config["price"])


## Buys one of [param id] into the house. False when the purse cannot cover it --
## the panel greys the chip out, but the money is the authority, not the interface.
func purchase(id: StringName) -> bool:
	var cost := price(id)
	if _config(id).is_empty() or funds < cost:
		return false
	funds -= cost
	owned[id] = int(owned.get(id, 0)) + 1
	_save_career()
	roster_changed.emit()
	return true


## Banks earnings from a completed call. The mission decides the amounts; this is
## only the purse.
func earn(amount: int) -> void:
	if amount <= 0:
		return
	funds += amount
	_save_career()
	roster_changed.emit()


## Back to a fresh career: the fleet on the map is dissolved, the purse refilled.
func reset_career() -> void:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.service != Unit.Service.NONE:
			unit.queue_free()
	owned = {}
	funds = STARTING_FUNDS
	_issued = {}
	_save_career()
	roster_changed.emit()


func _load_career() -> void:
	var career := ConfigFile.new()
	if career.load(career_path) != OK:
		return
	funds = int(career.get_value("career", "funds", STARTING_FUNDS))
	var stored: Dictionary = career.get_value("career", "owned", {})
	owned = {}
	for config in TYPES:
		var id: StringName = config["id"]
		# Keys come back from disk as plain Strings; re-key against the table.
		owned[id] = int(stored.get(String(id), stored.get(id, 0)))


func _save_career() -> void:
	var career := ConfigFile.new()
	career.set_value("career", "funds", funds)
	var stored := {}
	for id in owned:
		stored[String(id)] = int(owned[id])
	career.set_value("career", "owned", stored)
	career.save(career_path)


# --- The roster ----------------------------------------------------------------

## How many of [param id] are in the house: owned but not standing on the map.
func available(id: StringName) -> int:
	return maxi(0, int(owned.get(id, 0)) - _alive(id))


func total(id: StringName) -> int:
	return int(owned.get(id, 0))


## Sends one out, or returns null when everything owned is already on the map.
## Nothing else in the game creates a unit, so the fleet is a hard cap.
func dispatch(id: StringName) -> Unit:
	if available(id) <= 0:
		return null
	var config := _config(id)
	var parent := get_node_or_null(units_path)
	if parent == null:
		push_error("station has no Units node to spawn into")
		return null

	var packed := load(str(config["scene"])) as PackedScene
	if packed == null:
		push_error("missing scene for %s: %s" % [id, config["scene"]])
		return null
	var unit := packed.instantiate() as Unit
	if unit == null:
		push_error("%s is not a Unit" % config["scene"])
		return null

	_issued[id] = int(_issued.get(id, 0)) + 1
	unit.name = "%s%d" % [config["label"], _issued[id]]
	unit.display_name = "%s %d" % [config["label"], _issued[id]]
	# Crew portraits are assigned here -- the map no longer ships pre-placed units,
	# so nobody else is left to do it. Vehicles carry theirs in their own scenes.
	if config.has("portrait"):
		var portrait := PORTRAITS + str(config["portrait"]) + ".png"
		if ResourceLoader.exists(portrait):
			unit.portrait = load(portrait)
	parent.add_child(unit)
	unit.global_position = _free_slot()
	# Facing the street, the way everything else on the forecourt is parked.
	unit.global_rotation = global_rotation
	# _ready ran at the origin; respawn should mean this slot, not (0, 0, 0).
	unit.mark_spawn()

	roster_changed.emit()
	return unit


## Takes a returning unit back -- and *parks* it. The unit stays on the map, visible
## and selectable: it is the player's property standing in the yard, not a token to
## swallow back into a counter. Called by [ReturnOrder] once it has actually got here.
func accept(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.clear_orders()
	unit.global_position = _free_slot()
	unit.global_rotation = global_rotation
	var vehicle := unit as Vehicle
	if vehicle:
		vehicle.velocity = Vector3.ZERO
		vehicle.forward_speed = 0.0
		repair(vehicle)
	roster_changed.emit()


## Settles a vehicle's damage and puts it right.
##
## Booking in is the moment because it is already the moment a unit comes home, and it
## makes the bill a **decision** rather than a tax: a dented car keeps working, so the
## player chooses between keeping it out on the shout and bringing it in to be paid for.
##
## The purse can be emptied but not overdrawn. What it cannot cover stays on the vehicle
## as outstanding, to be settled next time it comes home with money in the bank -- a
## career that cannot afford its repairs should feel poor, not stop working, which is the
## same reason damage never takes a unit off the board.
func repair(vehicle: Vehicle) -> int:
	if vehicle == null or vehicle.repair_bill <= 0:
		return 0
	var paid := mini(vehicle.repair_bill, funds)
	if paid <= 0:
		return 0
	funds -= paid
	vehicle.repair_bill -= paid
	repairs_paid += paid
	_save_career()
	repaired.emit(vehicle, paid)
	roster_changed.emit()
	return paid


## What the whole fleet still owes. The dispatch panel reads it so a player can see the
## bill coming before it lands.
func outstanding_repairs() -> int:
	var total_owed := 0
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		if vehicle and not (vehicle is TrafficCar):
			total_owed += vehicle.repair_bill
	return total_owed


func is_home(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() < return_radius


## Whether the career owns anything of [param id] at all -- bought, wherever it is.
## The freeplay director asks before opening a call only that kind can answer.
func owns(id: StringName) -> bool:
	return int(owned.get(id, 0)) > 0


## Which of the types a unit is. Derived from what it *is* rather than from a tag,
## so a unit standing in the yard and one out on a call are the same thing here.
static func type_of(unit: Unit) -> StringName:
	if unit == null or unit.service == Unit.Service.NONE:
		return &""
	var vehicle := unit is Vehicle
	for config in TYPES:
		if config["service"] == unit.service and config["vehicle"] == vehicle:
			return config["id"]
	return &""


func _config(id: StringName) -> Dictionary:
	for config in TYPES:
		if config["id"] == id:
			return config
	return {}


## Units of this type standing anywhere on the map. Counted live rather than kept as
## a counter, so there is no bookkeeping to drift -- a freed unit stops counting the
## frame it goes.
func _alive(id: StringName) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and not unit.is_queued_for_deletion() and type_of(unit) == id:
			count += 1
	return count


## The first slot with nothing standing in it. Everything is checked because two
## units dispatched in the same breath would otherwise be handed the same spot and
## shove each other across the forecourt.
func _free_slot() -> Vector3:
	var taken: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.service != Unit.Service.NONE:
			taken.append(unit.global_position)

	var fallback := _slot(0)
	for i in slot_count:
		var spot := _slot(i)
		var clear := true
		for other in taken:
			if Vector2(other.x - spot.x, other.z - spot.z).length() < slot_clearance:
				clear = false
				break
		if clear:
			return spot
	# Every slot occupied: put it on the first one anyway rather than refusing. A brief
	# overlap sorts itself out; a dispatch button that silently does nothing does not.
	return fallback


## Slots wrap into rows of four: the front rank nearest the street, the second
## behind it -- both on the visible side of the yard (see slot_depth).
func _slot(index: int) -> Vector3:
	var row := index / 4
	var across := ((index % 4) - 1.5) * slot_pitch
	# Local -Z is towards the street, which is the side the camera can see.
	return global_position + global_basis \
		* Vector3(across, 0.2, -slot_depth + row * slot_row_pitch)
