extends Ability
class_name CollectAbility

## Offered by paramedics: right-clicking a stabilised casualty starts the stretcher
## run -- fetch the stretcher from the nearest medical vehicle with space, wheel it
## to the casualty, wheel them back aboard.
##
## This used to be the ambulance's verb, and moving it onto feet fixed a real fault:
## the vehicle navigation mesh is the carriageway and nothing else, so an ambulance
## sent to somebody lying deep on the pavement -- or in a park -- parked as close as
## the road ran and never closed the last metres. See [StretcherOrder].
##
## Scores 25, above Move; it never competes with Treat, which only applies while the
## casualty is still declining.


func id() -> StringName:
	return &"collect"


func label() -> String:
	return "Collect"


func icon() -> StringName:
	return &"stretcher"


func hotkey() -> Key:
	return KEY_B



## Worth starting unasked: a crew member standing over one of these is there to work on it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true

func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var casualty := target.incident as Casualty
	if casualty == null or not casualty.active:
		return NOT_APPLICABLE
	if not casualty.is_stable or casualty.is_loaded or casualty.is_carried:
		return NOT_APPLICABLE
	# No medical vehicle with a free slot anywhere means no stretcher to fetch, and
	# an order that would walk off to collect nothing falls back to Move, honestly.
	if StretcherOrder.nearest_vehicle(unit) == null:
		return NOT_APPLICABLE
	return 25


func make_order(_unit: Unit, target: Target) -> Order:
	return StretcherOrder.new(target.incident as Casualty)
