extends Order
class_name ReturnOrder

## Go back to the station and stand down.
##
## The other half of a finite roster. Without it a shift is a one-way ration: everything
## the station holds ends up scattered across the district and dispatch runs dry with
## six units standing about doing nothing.
##
## A vehicle going home **drives it properly**. It is not on a shout any more, so it
## keeps to its own lane, takes the junctions rather than cutting them, holds a legal
## speed and runs dark. Left to the navigation mesh it would do none of that: the mesh
## covers the full width of every road, so a car following it straight-lines down the
## middle and meets oncoming traffic head on -- fine at 90km/h on blues, plain wrong on
## the way back to the yard.
##
## People on foot just walk. Their navigation mesh is the pavements, which is already
## the rule that applies to them.
##
## Not a [WorkOrder] -- there is nothing to work on, and the station is not a target
## that can be lost.

## How close counts as having passed a waypoint. They are driven *through* rather than
## stopped at, so this is generous: braking to a halt at every junction on the way home
## would take all afternoon.
const WAYPOINT_SWITCH := 6.0

var station: Station

var _route: Array[Vector3] = []
var _at := 0
## Guards against handing the same unit back twice. accept() frees it, but the free
## lands at the end of the frame and tick() runs again before then.
var _handed_over := false


func _init(home: Station) -> void:
	station = home


## Never a response, which is what turns the lightbar off and drops the vehicle to a
## legal speed. See [method Order.is_emergency].
func is_emergency() -> bool:
	return false


func start(unit: Unit) -> void:
	if not is_instance_valid(station):
		return
	_route = _build_route(unit)
	_aim(unit)


func tick(unit: Unit, _delta: float) -> bool:
	if not is_instance_valid(station) or _handed_over:
		return true
	if station.is_home(unit.global_position):
		_handed_over = true
		unit.stop_navigating()
		station.accept(unit)
		return true

	# Waypoints before the last are passed through, so the car keeps rolling and --
	# the point of having them -- keeps aiming at something in its own lane a few
	# metres ahead rather than at the station across the district.
	var last := _at >= _route.size() - 1
	if not last and _flat(unit.global_position - _route[_at]) <= WAYPOINT_SWITCH:
		_at += 1
		_aim(unit)
		return false

	# Stopped short: either it reached a waypoint exactly, or it gave up. Either way
	# the next one is where it should be heading.
	if not unit.is_navigating():
		if not last:
			_at += 1
		_aim(unit)
	return false


func cancel(unit: Unit) -> void:
	unit.stop_navigating()


func destination() -> Vector3:
	return station.global_position if is_instance_valid(station) else NO_DESTINATION


func describe() -> String:
	return "Returning to station"


func _aim(unit: Unit) -> void:
	if _route.is_empty():
		unit.navigate_to(station.global_position)
		return
	# Always a waypoint as far as the turn-round rule is concerned: the way home is a
	# route from the first metre, so the strict trigger applies along all of it.
	unit.navigate_to(_route[mini(_at, _route.size() - 1)], false)


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


## The lane route to the station, plus the forecourt itself.
##
## The routing is [method CityGrid.lane_route], which every vehicle now shares -- it
## lived here first and lived here alone, which is why anything on a shout used to
## drive down the middle of the road. What is left here is the two things that are
## specific to going home: somebody on foot gets the station and nothing else, because
## pavements are their road rules and routing them junction to junction would walk them
## round three sides of a block to reach a door they could have crossed to; and the
## forecourt is the last waypoint, since it is not on a street.
func _build_route(unit: Unit) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not (unit is Vehicle) or not CityGrid.lattice_fits:
		# On foot -- or on a map the lattice does not describe -- the mesh's own
		# straight line is the honest route home.
		points.append(station.global_position)
		return points
	points = CityGrid.lane_route(unit.global_position, station.global_position)
	points.append(station.global_position)
	return points


