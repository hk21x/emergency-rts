@tool
class_name UnitInstance
extends Resource
## A unit in the world. If your project already defines UnitInstance, delete
## this file — the panel only reads the properties below.

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
const ROLE_COLOR := {
	&"driver": Color("8fa0b2"), &"firefighter": Color("e8734b"),
	&"paramedic": Color("4caf50"), &"officer": Color("3f98f2"),
	&"casualty": Color("f0c860"), &"civilian": Color("b6c4d4"),
}
const ROLE_LABEL := {
	&"driver": "Driver", &"firefighter": "Firefighter", &"paramedic": "Paramedic",
	&"officer": "Officer", &"casualty": "Casualty", &"civilian": "Civilian",
}

@export var callsign: String = "F01"
@export var def: UnitDef
## 0.0 to 1.0
@export var condition: float = 1.0
@export var status: Status = Status.AVAILABLE
## Free text under the order title: "Marlowe Street fire", "Station 1".
@export var task: String = ""
## Optional 0.0 to 1.0. Leave negative to hide the order progress bar.
@export var order_progress: float = -1.0

## One entry per occupied seat, in seat order.
@export var occupants: Array[StringName] = []
## Fraction of liquid remaining. Ignored unless the def carries something.
@export var liquid: float = 1.0


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


func status_color() -> Color:
	return STATUS_COLOR[status]


func status_label() -> String:
	return STATUS_LABEL[status]
