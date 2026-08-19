extends Ability
class_name DisarmAbility

## Talk an armed suspect into giving up their weapon.
##
## **The first verb any speciality has ever gated.** [Person.speciality] shipped with a
## note saying it deliberately added no verbs until a specialist actually needed one --
## a hook with no caller being the sort of thing this project has had to delete before.
## Armed response is that specialist: only a unit whose speciality is [constant
## Person.ARMED] carries this tile at all.
##
## It scores above Apprehend on purpose. Standing in front of somebody holding a weapon,
## the thing to do first is get the weapon down; the arrest is the same arrest afterwards,
## and any officer can make it.


func id() -> StringName:
	return &"disarm"


func label() -> String:
	return "Disarm"


func icon() -> StringName:
	return &"shield"


## `I` for intercept. **The sixteen command keys were all taken** -- Z X C V B N M G H J
## K L P T U Y -- so this is the first addition to that set since it was written down,
## and CLAUDE.md's list needs it.
func hotkey() -> Key:
	return KEY_I


## Walking up to an armed suspect is the whole job; there is nothing to arm and click.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true


## Above Apprehend's 30: with a weapon in the picture, disarming comes first.
func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var person := unit as Person
	if person == null or person.speciality != Person.ARMED:
		return NOT_APPLICABLE
	var suspect := target.incident as Suspect
	if suspect == null or not suspect.active or not suspect.armed:
		return NOT_APPLICABLE
	return 34


func make_order(_unit: Unit, target: Target) -> Order:
	return DisarmOrder.new(target.incident as Suspect)
