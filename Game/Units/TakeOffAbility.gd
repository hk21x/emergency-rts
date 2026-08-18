extends Ability
class_name TakeOffAbility

## Lift off and hold station.
##
## Instant, and only offered while it is actually on the ground — a tile that does nothing
## because the aircraft is already up is a tile that teaches the player to distrust the
## grid. Flying somewhere takes off on its own, so this is for the case where you want to
## be *ready* rather than somewhere: up, turning, waiting to be sent.


func id() -> StringName:
	return &"takeoff"


func label() -> String:
	return "Take Off"


func icon() -> StringName:
	return &"door_out"


func hotkey() -> Key:
	return KEY_U


func is_instant() -> bool:
	return true


## Never resolved from a right-click: this is a tile and a hotkey only. A helicopter on
## the ground that is right-clicked somewhere should *fly there*, which Move already does.
func score(_unit: Unit, _target: Target) -> int:
	return NOT_APPLICABLE


func execute(unit: Unit) -> void:
	var aircraft := unit as Aircraft
	if aircraft:
		aircraft.take_off()
