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
