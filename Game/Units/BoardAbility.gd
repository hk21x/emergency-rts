extends Ability
class_name BoardAbility

## Get into a vehicle that has a free seat.
##
## Scores well above [MoveAbility]'s 0, so right-clicking a car with people selected
## means "get in" rather than "walk to that spot".


func id() -> StringName:
	return &"board"


func label() -> String:
	return "Board"


func icon() -> StringName:
	return &"door_in"


func hotkey() -> Key:
	return KEY_N


func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	# **A [Unit], not a [Vehicle].** This cast was the reason a helicopter could not be
	# boarded: [Aircraft] extends Unit directly, so `as Vehicle` returned null for one and
	# the ladder fell through to Move. Its two seats were declared and unreachable.
	#
	# `seats > 0` is what keeps the widening honest -- without it every person in the game
	# is a candidate carrier, and a paramedic would offer to take passengers.
	var carrier := target.unit as Unit
	if carrier == null or carrier.seats <= 0 or not carrier.has_free_seat():
		return NOT_APPLICABLE
	# Nobody climbs into something that is in the air.
	var aircraft := carrier as Aircraft
	if aircraft and aircraft.is_airborne():
		return NOT_APPLICABLE
	return 10


func make_order(_unit: Unit, target: Target) -> Order:
	return BoardOrder.new(target.unit as Unit)
