extends Ability
class_name TreatAbility

## Outscores Extinguish, so a casualty beside a fire gets the paramedic's attention
## first. People before property.


func id() -> StringName:
	return &"treat"


func label() -> String:
	return "Treat"


func icon() -> StringName:
	return &"cross"


func hotkey() -> Key:
	return KEY_C



## Worth starting unasked: a unit standing over one of these is there to work on it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true

func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var casualty := target.incident as Casualty
	if casualty == null or not casualty.active or casualty.is_stable:
		return NOT_APPLICABLE
	return 30


func make_order(_unit: Unit, target: Target) -> Order:
	return TreatOrder.new(target.incident as Casualty)
