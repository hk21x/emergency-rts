extends Ability
class_name ExtinguishAbility

## Score well above MoveAbility's 0, so right-clicking a fire means "put that out"
## rather than "walk into it".


func id() -> StringName:
	return &"extinguish"


func label() -> String:
	return "Extinguish"


func icon() -> StringName:
	return &"droplet"


func hotkey() -> Key:
	return KEY_V



## Worth starting unasked: a crew member standing over one of these is there to work on it.
## A fire that only yields to a hose is the fire service's, and nobody else's.
##
## The score does not gate on this and does not need to: ordered at a building fire, an
## officer walks over and achieves nothing, which is a lesson the player learns once.
## Choosing it *unasked* is different — an idle officer would lock itself into futile work
## and stop being available — so the gate lives here, where the unit is choosing for
## itself.
func auto_engages(unit: Unit, target: Target) -> bool:
	var fire := target.incident as Fire if target else null
	if fire and fire.needs_hose:
		return unit != null and unit.service == Unit.Service.FIRE
	return true

func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var fire := target.incident as Fire
	if fire == null or not fire.active:
		return NOT_APPLICABLE
	return 20


func make_order(_unit: Unit, target: Target) -> Order:
	return ExtinguishOrder.new(target.incident as Fire)
