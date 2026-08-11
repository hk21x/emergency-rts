extends Order
class_name StretcherOrder

## Collect a stabilised casualty on foot: fetch the stretcher from a medical vehicle,
## wheel it to where they lie, lift them on, and wheel them back aboard.
##
## This is the paramedic's order, not the ambulance's, and that is the fix for a real
## fault: the vehicle navigation mesh is the carriageway and nothing else, so an
## ambulance sent to collect somebody lying deep on the pavement -- or in the middle
## of a park -- parked as close as the road ran and could never close the last few
## metres. Feet go where wheels cannot; the big wheels wait at the kerb.
##
## Six beats, run as a small state machine because three of them are journeys with
## different destinations: walk to the vehicle, pull the stretcher out, wheel it to
## the casualty, lift them on, wheel them back, hand them over. The vehicle can be
## driven mid-run and the walker follows it; cancelling mid-carry puts the casualty
## down where the stretcher stands, still open, still collectable.

enum Stage { TO_VEHICLE, TAKE_STRETCHER, TO_CASUALTY, LOAD, RETURN, HANDOVER }

## Close enough to reach into the vehicle, which is solid and stood beside.
const VEHICLE_REACH := 3.6
## Close enough to lift somebody on.
const CASUALTY_REACH := 1.8
## Seconds pulling the stretcher out, and lifting the casualty onto it.
const GRAB_TIME := 0.9
const LOAD_TIME := 1.2
## The lift uses the pack's pick-up clip; the grab is quick enough to go without.
const LOAD_CLIP := "PickUp_Table"
## How far the vehicle may drift before the walker re-paths after it.
const RETARGET := 1.5

var casualty: Casualty
var vehicle: Vehicle

var _stage := Stage.TO_VEHICLE
var _work_left := 0.0
var _stretcher: Node3D
var _last_target := Vector3.INF


func _init(target: Casualty) -> void:
	casualty = target


## The nearest medical vehicle with a free stretcher slot. Static so the ability can
## ask the same question when deciding whether Collect applies at all.
static func nearest_vehicle(unit: Unit) -> Vehicle:
	var best: Vehicle = null
	var closest := INF
	for node in unit.get_tree().get_nodes_in_group(Unit.GROUP):
		var candidate := node as Vehicle
		if candidate == null or candidate is TrafficCar:
			continue
		if candidate.service != Unit.Service.MEDICAL:
			continue
		if not candidate.has_stretcher_space():
			continue
		var distance := unit.global_position.distance_to(candidate.global_position)
		if distance < closest:
			closest = distance
			best = candidate
	return best


func start(unit: Unit) -> void:
	# Chosen once: the run belongs to this vehicle. Driving it away mid-run is
	# allowed -- the walker follows -- but the allegiance never switches.
	vehicle = nearest_vehicle(unit)
	if vehicle:
		_head_for(unit, vehicle.global_position)


func tick(unit: Unit, delta: float) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return _abandon(unit)
	# The casualty can stop being worth the trip -- lost from the map, or already
	# aboard something else -- any time before they are on this stretcher.
	if _stage <= Stage.LOAD and not _casualty_wanted():
		return _abandon(unit)

	match _stage:
		Stage.TO_VEHICLE:
			if _arrived(unit, vehicle.global_position, VEHICLE_REACH):
				unit.stop_navigating()
				unit.face_towards(vehicle.global_position)
				vehicle.open_doors()
				_work_left = GRAB_TIME
				_stage = Stage.TAKE_STRETCHER
		Stage.TAKE_STRETCHER:
			_work_left -= delta
			if _work_left <= 0.0:
				_stretcher = _build_stretcher()
				unit.add_child(_stretcher)
				# In front of the walker: the person node's -Z is its travel direction.
				_stretcher.position = Vector3(0.0, 0.0, -1.15)
				_head_for(unit, casualty.global_position)
				_stage = Stage.TO_CASUALTY
		Stage.TO_CASUALTY:
			if _arrived(unit, casualty.global_position, CASUALTY_REACH):
				unit.stop_navigating()
				unit.face_towards(casualty.global_position)
				_set_clip(unit, LOAD_CLIP)
				_work_left = LOAD_TIME
				_stage = Stage.LOAD
		Stage.LOAD:
			_work_left -= delta
			if _work_left <= 0.0:
				_set_clip(unit, "")
				casualty.take_by_stretcher()
				_head_for(unit, vehicle.global_position)
				_stage = Stage.RETURN
		Stage.RETURN:
			_carry(unit)
			if _arrived(unit, vehicle.global_position, VEHICLE_REACH):
				unit.stop_navigating()
				unit.face_towards(vehicle.global_position)
				_stage = Stage.HANDOVER
		Stage.HANDOVER:
			_carry(unit)
			# The last slot may have been taken while this one wheeled back; stand at
			# the doors until one frees rather than failing a run that is all but done.
			if vehicle.load_casualty(casualty):
				casualty.load_into(vehicle)
				_drop_stretcher()
				return true
	return false


func cancel(unit: Unit) -> void:
	_abandon(unit)


func destination() -> Vector3:
	match _stage:
		Stage.TO_CASUALTY, Stage.LOAD:
			return casualty.global_position if is_instance_valid(casualty) \
				else NO_DESTINATION
		_:
			return vehicle.global_position if is_instance_valid(vehicle) \
				else NO_DESTINATION


func describe() -> String:
	match _stage:
		Stage.TO_VEHICLE, Stage.TAKE_STRETCHER: return "Fetching stretcher"
		Stage.TO_CASUALTY: return "Wheeling out"
		Stage.LOAD: return "Loading"
		_: return "Wheeling in"


# --- Internals ---------------------------------------------------------------

func _casualty_wanted() -> bool:
	return is_instance_valid(casualty) and casualty.active \
		and not casualty.is_loaded and not casualty.is_carried


## Arrived within reach, otherwise keeps the walk honest: re-paths when the target
## has moved or the walk petered out short.
func _arrived(unit: Unit, point: Vector3, reach: float) -> bool:
	var offset := point - unit.global_position
	offset.y = 0.0
	if offset.length() <= reach:
		return true
	if _last_target.distance_to(point) > RETARGET or not unit.is_navigating():
		_head_for(unit, point)
	return false


func _head_for(unit: Unit, point: Vector3) -> void:
	_last_target = point
	unit.navigate_to(point)


## The casualty rides the stretcher: same position, same facing, every frame.
func _carry(unit: Unit) -> void:
	if _stretcher == null or not is_instance_valid(casualty):
		return
	casualty.global_position = _stretcher.global_position + Vector3.UP * 0.62
	casualty.global_rotation.y = unit.global_rotation.y


func _abandon(unit: Unit) -> bool:
	if is_instance_valid(casualty) and casualty.is_carried:
		casualty.put_down()
	_drop_stretcher()
	_set_clip(unit, "")
	unit.stop_navigating()
	return true


func _drop_stretcher() -> void:
	if _stretcher and is_instance_valid(_stretcher):
		_stretcher.queue_free()
	_stretcher = null


func _set_clip(unit: Unit, clip: String) -> void:
	var person := unit as Person
	if person == null:
		return
	if clip.is_empty():
		person.clear_action()
	else:
		person.set_action(clip)


## The stretcher itself is a generated prop -- like the siren tone and the lightbar
## beads -- because the pack ships no gurney. A hi-vis bed, two rails, four legs,
## four wheels; read from RTS height it is exactly what it is.
func _build_stretcher() -> Node3D:
	var root := Node3D.new()
	root.name = "Stretcher"
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.75, 0.78, 0.8)
	var bed := StandardMaterial3D.new()
	bed.albedo_color = Color(0.9, 0.33, 0.22)
	_slab(root, Vector3(0.55, 0.05, 1.85), Vector3(0.0, 0.72, 0.0), bed)
	for side in [-1.0, 1.0]:
		_slab(root, Vector3(0.04, 0.04, 1.9), Vector3(0.29 * side, 0.8, 0.0), frame)
		for endz in [-0.8, 0.8]:
			_slab(root, Vector3(0.04, 0.6, 0.04),
				Vector3(0.24 * side, 0.4, endz), frame)
			_wheel(root, Vector3(0.24 * side, 0.09, endz), frame)
	return root


func _slab(parent: Node3D, size: Vector3, at: Vector3,
		material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	parent.add_child(mesh)


func _wheel(parent: Node3D, at: Vector3, material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.09
	ball.height = 0.18
	ball.material = material
	mesh.mesh = ball
	mesh.position = at
	parent.add_child(mesh)
