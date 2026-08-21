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
	if unit == null or unit.crew.is_empty():
		return NOT_APPLICABLE
	# **Not while it is in the air.** The crew contract is [Unit]'s now, so this applies to
	# an [Aircraft] as well as a car -- and without this line "turn everybody out" at
	# cruising height puts four firefighters on the ground from 24 metres up. The tile is
	# simply absent while airborne, which is the ladder's usual way of saying no.
	var aircraft := unit as Aircraft
	if aircraft and aircraft.is_airborne():
		return NOT_APPLICABLE
	return 12


func execute(unit: Unit) -> void:
	if unit:
		unit.unload()
