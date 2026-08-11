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
	var vehicle := target.unit as Vehicle
	if vehicle == null or not vehicle.has_free_seat():
		return NOT_APPLICABLE
	return 10


func make_order(_unit: Unit, target: Target) -> Order:
	return BoardOrder.new(target.unit as Vehicle)
