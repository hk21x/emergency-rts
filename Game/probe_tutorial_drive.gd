extends SceneTree

## Dev utility: how does a vehicle drive on the tutorial town?
##
##   godot --headless --fixed-fps 60 --path . \
##       --script res://Game/probe_tutorial_drive.gd
##
## The district's driving is measured by probe_orbit and its siblings, all of which
## load Playground and lean on the lattice. This town has none: its streets are one
## 5m tile wide where the district's are two, the corner planner has no route to
## annotate, and the bounded turn validates its legs against map bounds and physics
## alone. Play produced four black-box records here in one session -- an ambulance
## oscillating within sight of the forecourt with nothing inside 14m -- and this is
## the harness that reproduces them.
##
## Legs are the recorded geometries first, then the journeys the tutorial actually
## asks for. Reports arrival, time, escapes, and the shuffle: how much of the run
## was spent going nowhere.

const SCENE := "res://Game/Tutorial.tscn"
const PATIENCE := 40.0

## The forecourt, from build_tutorial.
const STATION_SPOT := Vector3(-47.5, 0.45, -3.0 + 13.0)

var _scene: Node3D
var _car: Vehicle
var _escapes := 0
var _was_escaping := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	# The navigation map ingests its regions asynchronously -- measured at ~30
	# frames. Queries before that answer confidently and wrongly.
	await _idle(50)
	var stuck := _scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://probe-tutorial-stuck.txt"
	var station := _scene.get_node("Station") as Station
	station.career_path = "user://probe-tutorial-career.cfg"
	station.funds = 999999
	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "ambulance")
	station.purchase(kind)
	_car = station.dispatch(kind) as Vehicle
	if _car == null:
		print("no such unit: %s" % kind)
		quit()
		return
	# The crowd is not what is being measured, and a walker under the wheels is a
	# different report. Emptied, exactly as probe_orbit empties the district.
	var crowd := _scene.get_node_or_null("Crowd")
	if crowd:
		for child in crowd.get_children():
			child.free()
	await _idle(20)

	print("\n=========== TUTORIAL DRIVING: %s ===========" % _car.display_name)
	var radius := _car.wheelbase / tan(deg_to_rad(_car.max_steer_degrees))
	print("min turn radius %.2fm, half-width %.2fm, streets are 5m wide"
		% [radius, _car.width * 0.5 if "width" in _car else 1.1])

	for case: Array in [
			# The black box, 16 August: an ambulance reversing toward the forecourt
			# with nothing within 14m, oscillating between (-33,9) and (-25,8).
			["record: approach to the forecourt", Vector3(-32.1, 0.45, 8.7),
				Vector3(-1, 0, 0), Vector3(-47.5, 0.45, 10.0)],
			# And the second: mid-turn-round 11m short, just past the quarter.
			["record: turning at the quarter", Vector3(-51.4, 0.45, 2.5),
				Vector3(0, 0, 1), Vector3(-43.8, 0.45, 10.4)],
			# The journeys the tutorial actually asks for.
			["forecourt to the casualty", STATION_SPOT, Vector3(0, 0, -1),
				Vector3(-25.0, 0.45, -35.0)],
			["casualty back to the forecourt", Vector3(-25.0, 0.45, -35.0),
				Vector3(0, 0, 1), STATION_SPOT],
			["forecourt to the fire", STATION_SPOT, Vector3(1, 0, 0),
				Vector3(-25.0, 0.45, 25.0)]]:
		await _leg(str(case[0]), case[1] as Vector3, case[2] as Vector3,
			case[3] as Vector3)
	quit()


func _leg(label: String, start: Vector3, facing: Vector3, aim: Vector3) -> void:
	_car.clear_orders()
	_car.global_position = start
	_car.velocity = Vector3.ZERO
	_car.look_at(start + facing, Vector3.UP)
	await _idle(10)
	_escapes = 0
	_was_escaping = false
	_car.issue(MoveOrder.new(aim))

	var elapsed := 0.0
	var crawling := 0
	var frames := 0
	var reversals := 0
	var was_forward := true
	var closest := INF
	for i in 20:
		await physics_frame
		elapsed += 1.0 / 60.0
	var trace := OS.get_environment("PROBE_TRACE") != ""
	while elapsed < PATIENCE and _car.is_navigating():
		await physics_frame
		elapsed += 1.0 / 60.0
		frames += 1
		if trace and frames % 60 == 0:
			var agent := _car.get_node("NavigationAgent") as NavigationAgent3D
			print("    t=%4.1f at (%6.1f,%6.1f) spd %5.1f  aim %5.1fm  "
				% [elapsed, _car.global_position.x, _car.global_position.z,
					_car.forward_speed, _flat(_car.move_target - _car.global_position)]
				+ "path %d pts  finished %s  esc %s  turn %s"
				% [agent.get_current_navigation_path().size(),
					agent.is_navigation_finished(), _car.is_escaping(),
					_car.is_turning_round()])
		if absf(_car.forward_speed) < 0.5:
			crawling += 1
		var forward := _car.forward_speed >= 0.0
		if forward != was_forward:
			reversals += 1
			was_forward = forward
		closest = minf(closest, _flat(_car.global_position - aim))
		var escaping := _car.is_escaping()
		if escaping and not _was_escaping:
			_escapes += 1
		_was_escaping = escaping

	var gap := _flat(_car.global_position - aim)
	print("\n--- %s  (%.0fm out)" % [label, _flat(aim - start)])
	print("  arrived %s after %.1fs, %.1fm away (closest %.1fm)"
		% [not _car.is_navigating(), elapsed, gap, closest])
	print("  escapes %d, direction changes %d, %d of %d frames going nowhere (%.0f%%)"
		% [_escapes, reversals, crawling, frames,
			100.0 * float(crawling) / maxf(float(frames), 1.0)])


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _idle(frames: int) -> void:
	for i in frames:
		await physics_frame
