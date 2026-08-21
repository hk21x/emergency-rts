class_name UnitInstance
extends Resource
## A unit that exists in the world, as opposed to UnitDef which is the
## catalogue entry it was bought from.

enum Status { AVAILABLE, EN_ROUTE, ON_SCENE, RETURNING, OFF_RUN }

const STATUS_LABEL := {
	Status.AVAILABLE: "AVAILABLE", Status.EN_ROUTE: "EN ROUTE",
	Status.ON_SCENE: "ON SCENE", Status.RETURNING: "RETURNING",
	Status.OFF_RUN: "OFF RUN",
}
const STATUS_COLOR := {
	Status.AVAILABLE: Color("6ed07e"), Status.EN_ROUTE: Color("7fb8f5"),
	Status.ON_SCENE: Color("f0c860"), Status.RETURNING: Color("8fa0b2"),
	Status.OFF_RUN: Color("e8735c"),
}
## Order the sidebar groups statuses in — most urgent first.
const GROUP_ORDER := [Status.ON_SCENE, Status.EN_ROUTE, Status.AVAILABLE,
		Status.RETURNING, Status.OFF_RUN]

@export var callsign: String = "U01"
@export var def: UnitDef
## 0.0 to 1.0. Below 0.35 the row flags itself for attention.
@export var condition: float = 1.0
@export var status: Status = Status.AVAILABLE
## Free text on the right of the row: "ETA 0:42", "Treating", "Station 2".
@export var task: String = ""

## Who is aboard, one entry per occupied seat. Order is seat order.
@export var occupants: Array[StringName] = []
## Fraction of liquid capacity remaining, 0.0 to 1.0. Ignored unless the def
## says the unit carries something.
@export var liquid: float = 1.0

## What this unit owes in repairs, in pounds. 0 for anything undamaged, and for anything
## that cannot be damaged.
##
## **Added because a red border with no number is not a readout.** A vehicle's condition
## here *is* its repair bill, and a card that went red without saying why was asked about
## twice before anyone worked out it meant "this one needs paying for".
@export var owed: int = 0

## How far through its current order this unit is, 0 to 1 -- or -1 when the order has no
## meaningful answer, in which case the bar is not drawn at all.
@export var progress: float = -1.0

const ROLE_COLOR := {
	&"driver": Color("8fa0b2"), &"firefighter": Color("e8734b"),
	&"paramedic": Color("4caf50"), &"officer": Color("3f98f2"),
	&"casualty": Color("f0c860"), &"civilian": Color("b6c4d4"),
	## Added for this game: a police van's six cells are the reason to own one, and
	## the back of it reads very differently from the front.
	&"prisoner": Color("c4442f"),
}
const ROLE_LABEL := {
	&"driver": "Driver", &"firefighter": "Firefighter", &"paramedic": "Paramedic",
	&"officer": "Officer", &"casualty": "Casualty", &"civilian": "Civilian",
	&"prisoner": "In custody",
}


func seats_taken() -> int:
	return occupants.size()


func seats_total() -> int:
	return def.seats if def else 0


func liquid_litres() -> int:
	if def == null or not def.carries_liquid:
		return 0
	return roundi(def.liquid_capacity * clampf(liquid, 0.0, 1.0))


func role_tally() -> Dictionary:
	var out := {}
	for r in occupants:
		out[r] = int(out.get(r, 0)) + 1
	return out


## **A negative condition means the unit has none, not that it is wrecked.** Vehicles in
## this game carry a repair bill in pounds rather than health, so their condition is set
## below zero to keep the bar off the row -- and this read that as critically damaged, so
## every vehicle on the map wore the red alert styling for ever while reporting itself
## AVAILABLE beside it. A sentinel is only safe while every reader knows it is one.
func needs_attention() -> bool:
	if status == Status.OFF_RUN:
		return true
	return condition >= 0.0 and condition < 0.35


func status_color() -> Color:
	return STATUS_COLOR[status]


func status_label() -> String:
	return STATUS_LABEL[status]
