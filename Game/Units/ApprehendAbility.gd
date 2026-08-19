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
	# **Nobody walks up to a weapon.** An armed suspect is not an arrest until armed
	# response has talked them down -- [DisarmAbility] is the only verb offered on one, and
	# it is offered to exactly one kind of unit. Declining here rather than letting the
	# order fail is what teaches the player they need the ARV: the tile simply is not
	# there, and the right-click means Move instead.
	if suspect.armed:
		return NOT_APPLICABLE
	return 30


func make_order(_unit: Unit, target: Target) -> Order:
	return ApprehendOrder.new(target.incident as Suspect)
