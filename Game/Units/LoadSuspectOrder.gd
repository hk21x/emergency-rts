extends Order
class_name LoadSuspectOrder

## Walk a detained suspect to a patrol car and put them in the back.
##
## **This is the officer's order, not the car's.** Until August 2026 a patrol car drove
## to a cuffed suspect and they appeared inside it — the arrest was on foot and the
## loading was a teleport, which read as the car swallowing them from five metres away.
## Worse, it made the *car* the thing that had to reach the scene, and a car only goes
## where the carriageway goes: the reach had to be stretched to 5.5m purely to bridge the
## kerb, and that only worked because the director opens crime calls against a kerb on
## purpose. A suspect anywhere else was uncollectable.
##
## So it is now the same shape as the paramedic's [StretcherOrder], which solved the
## identical problem for casualties: feet go where wheels cannot, and the big wheels wait
## at the kerb. Four beats rather than six, because there is no stretcher to fetch — walk
## to them, take hold, walk them back, hand them over.
##
## The car may be driven away mid-walk and the officer re-paths after it. Cancelling
## halfway lets the suspect go where they stand: still detained, still collectable, which
## matters because a player who changes their mind should not lose an arrest.

enum Stage { TO_SUSPECT, TAKE, TO_VEHICLE, HANDOVER }

## Close enough to take somebody by the arm.
const SUSPECT_REACH := 1.8
## Close enough to put them in the back. The car is solid and stood beside.
const VEHICLE_REACH := 3.6
## Seconds spent taking hold. Short — this is a hand on an elbow, not a procedure.
const TAKE_TIME := 0.8
## How far the car may drift before the walker re-paths after it.
const RETARGET := 1.5

var suspect: Suspect
var vehicle: Vehicle

var _stage := Stage.TO_SUSPECT
var _work_left := 0.0
var _last_target := Vector3.INF


func _init(target: Suspect) -> void:
	suspect = target


## The nearest police vehicle with a free cell. Static so [LoadSuspectAbility] can ask
## the same question when deciding whether Escort applies at all — an order that would
## walk somebody to a car that does not exist should never be offered.
static func nearest_vehicle(unit: Unit) -> Vehicle:
	var best: Vehicle = null
	var closest := INF
	for node in unit.get_tree().get_nodes_in_group(Unit.GROUP):
		var candidate := node as Vehicle
		if candidate == null or candidate is TrafficCar:
			continue
		if candidate.service != Unit.Service.POLICE:
			continue
		if not candidate.has_cell_space():
			continue
		var distance := unit.global_position.distance_to(candidate.global_position)
		if distance < closest:
			closest = distance
			best = candidate
	return best


func describe() -> String:
	match _stage:
		Stage.TO_SUSPECT, Stage.TAKE:
			return "Escorting"
		_:
			return "Taking them in"


func destination() -> Vector3:
	if _stage == Stage.TO_VEHICLE or _stage == Stage.HANDOVER:
		return vehicle.global_position if is_instance_valid(vehicle) else Vector3.INF
	return suspect.global_position if is_instance_valid(suspect) else Vector3.INF


func start(unit: Unit) -> void:
	_aim(unit)


func cancel(unit: Unit) -> void:
	unit.stop_navigating()
	if is_instance_valid(suspect):
		suspect.let_go()
	var person := unit as Person
	if person:
		person.clear_action()


func tick(unit: Unit, delta: float) -> bool:
	if not is_instance_valid(suspect) or not suspect.active or suspect.is_loaded:
		cancel(unit)
		return true

	match _stage:
		Stage.TO_SUSPECT:
			if _within(unit, suspect.global_position, SUSPECT_REACH):
				unit.stop_navigating()
				unit.face_towards(suspect.global_position)
				_stage = Stage.TAKE
				_work_left = TAKE_TIME
			else:
				_chase(unit, suspect.global_position)
		Stage.TAKE:
			_work_left -= delta
			if _work_left <= 0.0:
				# The car is chosen now rather than at the start, because the roster can
				# change while an officer walks: a car may have driven off, filled up, or
				# arrived since the order was given.
				vehicle = nearest_vehicle(unit)
				if vehicle == null:
					cancel(unit)
					return true
				suspect.walk_with(unit)
				_stage = Stage.TO_VEHICLE
				_last_target = Vector3.INF
		Stage.TO_VEHICLE:
			if not is_instance_valid(vehicle) or not vehicle.has_cell_space():
				# Somebody else filled the last cell while this one walked. Let them go
				# where they stand rather than stranding them on a dead order.
				cancel(unit)
				return true
			if _within(unit, vehicle.global_position, VEHICLE_REACH):
				unit.stop_navigating()
				unit.face_towards(vehicle.global_position)
				_stage = Stage.HANDOVER
			else:
				_chase(unit, vehicle.global_position)
		Stage.HANDOVER:
			# **They go in the back because they were brought there.** Without this the
			# walk is decorative: the sabotage agent deleted `walk_with()` entirely and
			# every loading check stayed green, because HANDOVER put the suspect in the
			# car from wherever they happened to be standing -- which is the teleport
			# this order was written to get rid of, still there under a longer animation.
			if suspect.escorted_by != unit:
				cancel(unit)
				return true
			suspect.let_go()
			if vehicle.load_suspect(suspect):
				suspect.load_into(vehicle)
			var person := unit as Person
			if person:
				person.clear_action()
			unit.stop_navigating()
			return true
	return false


## Walks toward a point, re-pathing only when it has actually moved — a fresh path every
## frame at a car that is standing still would restart the agent for ever.
func _chase(unit: Unit, point: Vector3) -> void:
	if _last_target == Vector3.INF or _last_target.distance_to(point) > RETARGET \
			or not unit.is_navigating():
		_last_target = point
		unit.navigate_to(point)


func _within(unit: Unit, point: Vector3, reach: float) -> bool:
	var offset := point - unit.global_position
	offset.y = 0.0
	return offset.length() <= reach


func _aim(unit: Unit) -> void:
	if is_instance_valid(suspect):
		_chase(unit, suspect.global_position)
