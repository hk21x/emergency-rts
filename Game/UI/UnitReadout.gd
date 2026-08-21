extends RefCounted
class_name UnitReadout

## What a unit is, is doing, and is carrying — in the words two different panels both need.
##
## **Extracted because two panels reading the same unit must not disagree about it.** The
## roster sidebar down the left and the selection panel along the bottom both show a
## callsign, a status and a task line for the same vehicle, and a player looking at "F01
## EN ROUTE" in one place and "Fire Engine, standing by" in the other would be right to
## call it a bug. This is the single answer both of them ask for.
##
## Static throughout: it holds no state and owns no nodes. The callsign is the one
## exception that needs care — see [method callsign].

## Order-script name to the two or three words a row has space for. Deliberately short of
## exhaustive: anything unlisted falls back to the order's own name with the spaces put
## back, which reads acceptably for a verb nobody has taught it yet.
const TASKS := {
	"Extinguish": "Fighting fire", "Treat": "Treating", "Apprehend": "Arresting",
	"Stretcher": "Stretcher run", "Cool": "Cooling", "Free": "Freeing",
	"Clear": "Clearing", "Disarm": "Talking them down", "Connect": "On the hydrant",
	"LoadSuspect": "Walking them in", "Secure": "Setting a cordon",
	"Board": "Boarding", "Return": "Returning", "Move": "En route",
	"TakeOff": "Lifting off", "Land": "Landing",
}

## Below this a person is reported as hurt rather than as whatever they were doing, because
## it is the more urgent fact about them.
const HURT_BELOW := 0.35

## What a vehicle's repair bill has to reach before its condition bar reads empty.
##
## **A vehicle has no health**, and that is a deliberate distinction the roster asserts and
## a check guards: people carry `health`, vehicles carry a bill in pounds. But a panel that
## draws a bar for one and a blank for the other reads as a missing feature rather than as
## a difference, so the bill is shown *as* a condition here — scaled against this, which is
## five of `Vehicle.damage_cap`'s single-incident maximum. A vehicle at 0% is not wrecked;
## it is expensive.
const BILL_SCALE := 200.0


## The callsign a unit should be known by, everywhere.
##
## **Issued by counting, so it has to be issued in one pass over the whole roster** — the
## nth police vehicle is P0n, and asking for one unit's callsign in isolation cannot know
## what n is. Callers hand in the same `issued` tally they are walking with; the selection
## panel borrows the roster's answer rather than starting its own count, or the same engine
## would be F01 in one corner of the screen and F03 in another.
static func callsign(service: int, issued: Dictionary) -> String:
	var prefix: String = UnitSidebar.PREFIX.get(
		ShopCatalogue.CATEGORY.get(service, &"support"), "U")
	var next: int = int(issued.get(prefix, 0)) + 1
	issued[prefix] = next
	return "%s%02d" % [prefix, next]


## What the unit is actually doing.
##
## Read off the order it is carrying out rather than stored, so it cannot fall out of step
## with the unit.
static func task_of(unit: Unit) -> String:
	if unit == null:
		return ""
	var person := unit as Person
	if person and person.health < HURT_BELOW:
		return "Hurt"
	if not unit.has_orders():
		return "Standing by"
	var order := unit.current_order()
	if order == null:
		return "Standing by"
	var kind: String = order.get_script().resource_path.get_file().trim_suffix("Order.gd")
	if TASKS.has(kind):
		return String(TASKS[kind])
	var spaced := ""
	for i in kind.length():
		var ch: String = kind[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			spaced += " " + ch.to_lower()
		else:
			spaced += ch
	return spaced


## EN_ROUTE while it is driving to something, ON_SCENE while it is working, RETURNING on
## the way home, AVAILABLE when it is standing about with nothing to do.
static func status_of(unit: Unit) -> UnitInstance.Status:
	if unit == null or not unit.has_orders():
		return UnitInstance.Status.AVAILABLE
	var order := unit.current_order()
	if order == null:
		return UnitInstance.Status.AVAILABLE
	var kind: String = order.get_script().resource_path.get_file()
	if kind.begins_with("Return"):
		return UnitInstance.Status.RETURNING
	if kind.begins_with("Move"):
		return UnitInstance.Status.EN_ROUTE
	return UnitInstance.Status.ON_SCENE


## 0..1 for the condition bar, or -1 for a unit that has no condition to draw.
##
## People report health. Vehicles report their repair bill against [constant BILL_SCALE],
## because "a bill, not health" is a true distinction that still wants drawing. An aircraft
## is neither and reports -1.
static func condition_of(unit: Unit) -> float:
	var person := unit as Person
	if person:
		return clampf(person.health, 0.0, 1.0)
	var vehicle := unit as Vehicle
	if vehicle:
		return clampf(1.0 - float(vehicle.repair_bill) / BILL_SCALE, 0.0, 1.0)
	return -1.0


## What the condition row should be called for this unit — the number means two different
## things and the label is what says which.
static func condition_label(unit: Unit) -> String:
	return "HEALTH" if unit is Person else "CONDITION"


## Everyone aboard, one [constant UnitInstance.ROLE_LABEL] key per occupied seat, in seat
## order: the crew riding along, then anybody in the back.
##
## **This is the readout the selection panel exists for.** A fire engine with four
## firefighters aboard and one with an empty cab look identical from outside, and until now
## the interface said nothing about either.
##
## **No driver.** One was drawn at the front for a while, on the reasoning that a moving
## vehicle with every seat empty reads as unmanned. It was removed because it is a fiction:
## there is no driver [Person] in this model, so the pip stood for nobody, could not be
## clicked, and inflated every count by one -- a patrol car carrying a single officer
## reported 2 / 5. The strip now counts only people the player actually put there.
static func occupants_of(unit: Unit) -> Array[StringName]:
	var out: Array[StringName] = []
	if unit == null:
		return out
	# **Crew and casualties come off the [Unit].** They moved up there when the aircraft
	# gained a crew, and this went on gating the whole readout behind `unit as Vehicle` --
	# so a helicopter with four people aboard reported an empty cabin, on a bar whose only
	# job is saying who is inside. Cells stayed on Vehicle; a helicopter has no cage.
	for person in unit.crew:
		if is_instance_valid(person):
			out.append(role_of(person))
	for casualty in unit.casualties:
		if is_instance_valid(casualty):
			out.append(&"casualty")
	var vehicle := unit as Vehicle
	if vehicle:
		for suspect in vehicle.suspects:
			if is_instance_valid(suspect):
				out.append(&"prisoner")
	return out


## Which seat colour a crew member takes, from their service.
static func role_of(person: Person) -> StringName:
	if person == null:
		return &"civilian"
	match person.service:
		Unit.Service.FIRE:
			return &"firefighter"
		Unit.Service.MEDICAL:
			return &"paramedic"
		Unit.Service.POLICE:
			return &"officer"
		_:
			return &"civilian"


## How many seats the panel should draw for this unit.
##
## Summed rather than taken from `seats` alone, because a vehicle's capacity is three
## separate numbers and a player fills all three: an ambulance's two stretchers are seats,
## and a van's six cells are the whole reason to buy one. No driver's seat among them --
## see [method occupants_of].
static func seats_of(unit: Unit) -> int:
	if unit == null:
		return 0
	# **Asked of the [Unit], not of a [Vehicle].** Seats and stretchers moved up to Unit
	# when the aircraft gained a crew, so casting to Vehicle here reported `0 / 0` for a
	# helicopter that had just been given two seats and a stretcher. Cells stayed on
	# Vehicle -- a helicopter has no cage.
	var vehicle := unit as Vehicle
	return unit.seats + unit.stretchers + (vehicle.cells if vehicle else 0)
