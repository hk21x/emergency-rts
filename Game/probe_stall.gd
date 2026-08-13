extends SceneTree

## Dev utility: replays a black-box record and asks whether the car ever gets out of it.
##
##   STALL_CASE=0 godot --headless --fixed-fps 60 --path . --script res://Game/probe_stall.gd
##
## Written for the August 2026 stragglers. Every one of the three records replayed here
## reads the same way: on a road, on the floor, **full throttle, zero speed, nothing in
## front**, and `turning round: false`. Two mechanisms should rescue such a car and
## neither can:
##
## - `_update_reverse_latch` arms on `distance < turn_round_range`, and that distance is
##   to the **final destination**, not to the point being steered at. All three cars were
##   45.6m, 46.0m and 124.9m out, so the latch was structurally unable to fire.
## - `_update_escape` counts a car as stuck on `absf(forward_speed) < 0.3`, and a car
##   shuffling back and forth is never stationary, so `_stuck_time` resets for ever. The
##   black box already knows better -- it measures progress toward the aim, and says so
##   in its own comment -- which is how these records exist at all.
##
## So this reports the two things that separate "slow" from "never": whether the order
## ever completes, and how many times the car reverses direction while trying.
##
## **One case per process.** Passes in this project contaminate each other.

const SCENE := "res://Game/Playground.tscn"

## Long enough that a car which is merely slow still arrives: the longest leg here is
## 125m, which at a 26 m/s ceiling is a handful of seconds even driven badly.
const PATIENCE := 70.0

## Replays of the three records. `from` and `facing` are read off the record's own trail
## -- the last two crumbs give the heading the car actually had.
const CASES := [
	{"unit": &"patrol", "from": Vector3(-0.4, 0.0, 23.9),
		"facing": Vector3(5.0, 0.0, 0.0), "to": Vector3(117.4, 0.0, -17.8),
		"note": "Patrol 1, oscillating over 8m at (-0,24); destination 124.9m out"},
	{"unit": &"engine", "from": Vector3(-91.9, 0.0, 75.8),
		"facing": Vector3(-5.0, 0.0, 0.0), "to": Vector3(-80.4, 0.0, 119.9),
		"note": "Fire Engine 1, stopped dead with its waypoint 12.5m behind it"},
	{"unit": &"patrol", "from": Vector3(-81.5, 0.0, 21.2),
		"facing": Vector3(3.0, 0.0, -1.0), "to": Vector3(-55.6, 0.0, -16.9),
		"note": "Patrol 1, circling inside junction 1,3; destination 46.0m out"},
]

var _scene: Node3D
var _car: Vehicle


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	await process_frame
	# Redirect the black box, or a probe's staged driving lands in the file the player's
	# real faults are read from -- 149 records of fixtures got in that way once.
	var stuck := _scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://probe-stuck-log.txt"
	var station := _scene.get_node("Station")
	station.career_path = "user://probe-stall-career.cfg"
	station.funds = 999999
	station.owned = {}

	var index := int(OS.get_environment("STALL_CASE"))
	var case: Dictionary = CASES[clampi(index, 0, CASES.size() - 1)]
	station.purchase(case["unit"])
	_car = station.dispatch(case["unit"]) as Vehicle
	if _car == null:
		print("no such unit"); quit(); return
	await _idle(40)

	var from: Vector3 = case["from"]
	_car.global_position = from + Vector3.UP * 0.2
	_car.look_at(from + (case["facing"] as Vector3), Vector3.UP)
	_car.velocity = Vector3.ZERO
	await _idle(10)

	print("\n============ STALL PROBE: case %d ============" % index)
	print(case["note"])
	print("%s from (%.1f, %.1f) to (%.1f, %.1f), %.1fm"
		% [_car.display_name, from.x, from.z, (case["to"] as Vector3).x,
			(case["to"] as Vector3).z, _flat(from - (case["to"] as Vector3))])
	print("  turn_round_range %.1f -- the latch cannot arm beyond this"
		% _car.turn_round_range)

	_car.issue(MoveOrder.new(case["to"]))
	var elapsed := 0.0
	var closest := INF
	var reversals := 0
	var latched := 0
	var escaped := 0
	var last_sign := 0
	var arrived := false
	while elapsed < PATIENCE:
		await process_frame
		var delta := root.get_process_delta_time()
		elapsed += delta
		closest = minf(closest, _flat(_car.global_position - (case["to"] as Vector3)))
		if _car.is_turning_round():
			latched += 1
		if _car.throttle_input < 0.0 and absf(_car.forward_speed) < 0.5:
			escaped += 1
		var sign := signi(int(signf(_car.forward_speed)))
		if sign != 0 and last_sign != 0 and sign != last_sign:
			reversals += 1
		if sign != 0:
			last_sign = sign
		if not _car.is_navigating() and elapsed > 1.0:
			arrived = true
			break

	print("\n  arrived            %s after %.1fs" % ["YES" if arrived else "NO ", elapsed])
	print("  closest approach   %.1fm" % closest)
	print("  direction changes  %d" % reversals)
	print("  frames latched     %d  (turning round)" % latched)
	print("  ended at           (%.1f, %.1f), speed %.1f"
		% [_car.global_position.x, _car.global_position.z, _car.forward_speed])
	quit()


func _flat(offset: Vector3) -> float:
	offset.y = 0.0
	return offset.length()


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
