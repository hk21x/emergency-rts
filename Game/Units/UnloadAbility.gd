extends Ability
class_name UnloadAbility

## Turn the crew out of a vehicle.
##
## Instant, and it answers a right-click on **its own vehicle**: driven to a scene with a
## crew aboard, the obvious gesture is to click the appliance and have them get out, and
## before this the only way was the command tile or M. It declines every other target, so
## right-clicking one vehicle never empties a different one.


func id() -> StringName:
	return &"unload"


func label() -> String:
	return "Unload"


func icon() -> StringName:
	return &"door_out"


func hotkey() -> Key:
	return KEY_M


func is_instant() -> bool:
	return true


## Above [MoveAbility]'s zero, and it only ever applies to the one vehicle the click
## landed on, so nothing else is competing for it.
func score(unit: Unit, target: Target) -> int:
	if target == null or target.unit != unit:
		return NOT_APPLICABLE
	var vehicle := unit as Vehicle
	if vehicle == null or vehicle.crew.is_empty():
		return NOT_APPLICABLE
	return 12


func execute(unit: Unit) -> void:
	var vehicle := unit as Vehicle
	if vehicle:
		vehicle.unload()
