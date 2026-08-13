extends Ability
class_name LoadSuspectAbility

## Offered by **officers**: right-clicking a detained suspect walks over, takes them by
## the arm and marches them to the nearest patrol car with a free cell.
##
## It belonged to the patrol car until August 2026, and moving it fixed the same fault
## the paramedic's Collect was moved for: a car only goes where the carriageway goes, so
## the reach had to be stretched to 5.5m purely to bridge the kerb, and anyone standing
## further off the road than that was uncollectable. Feet go where wheels cannot.
##
## Scores 25 and never competes with Apprehend, which only applies while the suspect is
## still resisting -- so an officer right-clicking a struggling suspect arrests them, and
## right-clicking the same person a moment later walks them in.


func id() -> StringName:
	return &"escort"


func label() -> String:
	return "Escort"


func icon() -> StringName:
	return &"shield"


func hotkey() -> Key:
	return KEY_B


func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var suspect := target.incident as Suspect
	if suspect == null or not suspect.active:
		return NOT_APPLICABLE
	if not suspect.is_detained or suspect.is_loaded:
		return NOT_APPLICABLE
	if unit == null or unit.service != Unit.Service.POLICE or unit is Vehicle:
		return NOT_APPLICABLE
	# No patrol car with a free cell anywhere means nowhere to walk them, and an order
	# that would march somebody to a car that does not exist falls back to Move, honestly
	# -- the same rule Collect follows when there is no ambulance.
	if LoadSuspectOrder.nearest_vehicle(unit) == null:
		return NOT_APPLICABLE
	return 25


func make_order(_unit: Unit, target: Target) -> Order:
	return LoadSuspectOrder.new(target.incident as Suspect)
