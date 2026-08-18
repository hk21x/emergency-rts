extends Order
class_name LandOrder

## Fly to a spot and put down on it.
##
## Thin, because [Aircraft] owns the vertical states: this hands over the destination and
## then waits for the aircraft to say it has finished, which it does not do until it is
## actually on the ground rather than merely overhead.

var _spot: Vector3


func _init(spot: Vector3) -> void:
	_spot = spot


func start(unit: Unit) -> void:
	var aircraft := unit as Aircraft
	if aircraft:
		aircraft.land_at(_spot)


func tick(unit: Unit, _delta: float) -> bool:
	var aircraft := unit as Aircraft
	if aircraft == null:
		return true
	return not aircraft.is_navigating()


func destination() -> Vector3:
	return _spot


func has_destination() -> bool:
	return true


func describe() -> String:
	return "Landing"
