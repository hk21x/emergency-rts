extends Order
class_name BoardOrder

## Walk to a vehicle and get in.
##
## Re-paths if the vehicle drives off, so ordering someone into a moving car has them
## chase it rather than trudge to where it used to be.

## Close enough to climb in.
const BOARD_DISTANCE := 3.2
## How far the vehicle must move before the walker bothers re-pathing.
const RETARGET_DISTANCE := 1.5

var vehicle: Unit

var _last_target := Vector3.INF


func _init(target_vehicle: Unit) -> void:
	vehicle = target_vehicle


func start(unit: Unit) -> void:
	_retarget(unit)


func tick(unit: Unit, _delta: float) -> bool:
	if not is_instance_valid(vehicle):
		unit.stop_navigating()
		return true

	var person := unit as Person
	if person == null:
		return true

	if unit.global_position.distance_to(vehicle.global_position) <= BOARD_DISTANCE:
		unit.stop_navigating()
		# Someone else may have taken the last seat while this one was walking.
		if vehicle.take_aboard(person):
			person.board(vehicle)
		return true

	if _last_target.distance_to(vehicle.global_position) > RETARGET_DISTANCE \
			or not unit.is_navigating():
		_retarget(unit)
	return false


func cancel(unit: Unit) -> void:
	unit.stop_navigating()


func destination() -> Vector3:
	return vehicle.global_position if is_instance_valid(vehicle) else NO_DESTINATION


func describe() -> String:
	return "Board"


func _retarget(unit: Unit) -> void:
	_last_target = vehicle.global_position
	unit.navigate_to(_last_target)
