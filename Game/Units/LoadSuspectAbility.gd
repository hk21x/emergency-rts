extends Ability
class_name LoadSuspectAbility

## Offered by police vehicles: right-clicking a detained suspect with a patrol car
## selected sends it to pick them up. The police mirror of the old ambulance Collect --
## scores 25, never competes with Apprehend because that one only applies while the
## suspect is still resisting.


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
	var vehicle := unit as Vehicle
	if vehicle == null or not vehicle.has_cell_space():
		return NOT_APPLICABLE
	return 25


func make_order(_unit: Unit, target: Target) -> Order:
	return LoadSuspectOrder.new(target.incident as Suspect)
