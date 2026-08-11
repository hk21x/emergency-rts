extends Ability
class_name ApprehendAbility

## Police only, offered by officers on foot. Outscores everything else on a suspect
## for the same reason Treat does on a casualty: the person *is* the job.
##
## Deliberately on the same key Treat uses. No unit carries both -- the gating is by
## service -- so C is simply "work the person in front of you", whichever service is
## holding the keyboard.


func id() -> StringName:
	return &"apprehend"


func label() -> String:
	return "Apprehend"


func icon() -> StringName:
	return &"shield"


func hotkey() -> Key:
	return KEY_C



## Worth starting unasked: a unit standing over one of these is there to work on it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true

func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var suspect := target.incident as Suspect
	if suspect == null or not suspect.active or suspect.is_detained:
		return NOT_APPLICABLE
	return 30


func make_order(_unit: Unit, target: Target) -> Order:
	return ApprehendOrder.new(target.incident as Suspect)
