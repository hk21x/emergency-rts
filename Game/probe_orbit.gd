extends SceneTree

## Dev utility: what does a vehicle do when its aim demands a turn tighter than its own
## steering can describe?
##
##   PROBE_UNIT=engine godot --headless --fixed-fps 60 --path . \
##       --script res://Game/probe_orbit.gd
##
## Built from the black box rather than from a theory. 42 records from real play, run
## through the pure-pursuit capture bound: a fixed point at distance L and bearing a is
## reachable only when **L >= 2R sin(a)**, where R is the vehicle's minimum turning
## radius (wheelbase / tan(33 deg) -- 4.44m for the patrol car, 5.10m the ambulance,
## 6.87m the fire engine). The records cluster exactly where that inequality fails: the
## fire engine owns 17 of the 42, at aim distances of 6-14m and bearings of 37-90 --
## demands for 5-7m arcs from a vehicle that can describe 13.7m at best.
##
## The loop this predicts, and the trails confirm: the car noses at an aim it cannot
## reach, the no-progress state trips nothing (the escape wants near-zero speed, the
## latch wants 115 degrees of heading error to a steer point that sits near the nose),
## eventually it slows enough for the escape, which reverses for a fixed 1.0s -- about
## 4m, not the 10-14m the geometry needs -- and the car drives forward into the same
## impossible turn. Shuffle, repeat.
##
## This stages that state cleanly: a car on open road, no traffic near, aimed at a point
## at a controlled distance and bearing. Reports time to arrive, escapes fired, and the
## worst shuffle (furthest the car got from its start before arriving). One condition
## per process -- the bearing sweep runs in one process because each leg resets fully,
## but A/B against a code change must be two separate runs.

const SCENE := "res://Game/Playground.tscn"
const PATIENCE := 30.0

var _scene: Node3D
var _car: Vehicle
var _escapes := 0
var _was_escaping := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	await process_frame
	var stuck := _scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://probe-stuck-log.txt"
	var station := _scene.get_node("Station")
	station.career_path = "user://probe-orbit-career.cfg"
	station.funds = 999999
	station.owned = {}
	# **The district is emptied first.** The legs run one after another, so any change in
	# one leg's duration shifts the wall-clock phase of every later one -- and with 22
	# ambient cars circulating, that means a different car at the junction on every code
	# change. The first A/B of the shuttle read a 25s regression on the control leg that
	# was actually a taxi arriving at a different moment. The black-box records this probe
	# replicates say "nothing within 14m", so an empty district is the faithful stage, not
	# a convenience.
	for holder in ["Traffic", "Crowd"]:
		var node := _scene.get_node_or_null(holder)
		if node:
			for child in node.get_children():
				child.free()
	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "engine")
	station.purchase(kind)
	_car = station.dispatch(kind) as Vehicle
	if _car == null:
		print("no such unit"); quit(); return
	await _idle(40)

	var radius := _car.wheelbase / tan(deg_to_rad(_car.max_steer_degrees))
	print("\n============ ORBIT PROBE: %s ============" % _car.display_name)
	print("min turn radius %.2fm -- capture of a point at bearing a needs L >= %.1f*sin(a)"
		% [radius, 2.0 * radius])

	# **Staged as the records show it, on real roads.** The first cut of this probe swept
	# abstract bearing/distance pairs from a straight street, and both of its "failures"
	# were the harness: one aim landed beyond the map's southern boundary (the car fought
	# the invisible wall -- nine escapes against an easy target), the other landed inside
	# the block ring. What the 42 records actually describe is a car that **overshot a
	# junction turn**: heading down a street at speed, waypoint captured at 7m, aim now on
	# the cross street at a bearing its radius cannot answer. So that is what is staged --
	# at a real junction, aims on real carriageway.
	var j := CityGrid.junction(Vector2i(1, 1))
	var east := Vector3(1, 0, 0)
	var south := Vector3(0, 0, 1)

	# A bespoke case from the environment, for replaying a black-box record's exact
	# geometry: PROBE_AT="x,z,yaw_deg" PROBE_AIM="x,z". The player's F3 on a wedged
	# engine at the map's east rim is the case this was added for.
	if OS.get_environment("PROBE_AT") != "":
		var at := OS.get_environment("PROBE_AT").split(",")
		var to := OS.get_environment("PROBE_AIM").split(",")
		var here := Vector3(float(at[0]), 0.0, float(at[1]))
		var yaw := deg_to_rad(float(at[2]))
		await _leg("bespoke", here, Vector3(sin(yaw), 0.0, -cos(yaw)) * -1.0,
			Vector3(float(to[0]), 0.0, float(to[1])))
		quit()
		return

	for case: Array in [
			# Overshot the southward turn by 6m: aim 8m down the cross street.
			# Bearing ~127, L ~10 -- the patrol record at junction 3,3 exactly.
			["overshot by 6m", j + east * 6.0, east, j + south * 8.0],
			# Overshot by 12m: the deep version, engine-sized.
			["overshot by 12m", j + east * 12.0, east, j + south * 12.0],
			# Swept past the aim entirely: it is now straight behind. The 174/178-degree
			# ambulance records.
			["aim dead behind", j + east * 10.0, east, j - east * 10.0],
			# Control: an ordinary approach to the same turn, from 20m back. Must arrive
			# quickly with zero escapes, or the stage itself is broken.
			["ordinary turn", j - east * 20.0, east, j + south * 15.0]]:
		await _leg(str(case[0]), case[1] as Vector3, case[2] as Vector3, case[3] as Vector3)
	quit()


func _leg(label: String, start: Vector3, facing: Vector3, aim: Vector3) -> void:
	_car.clear_orders()
	_car.global_position = start + Vector3.UP * 0.2
	_car.velocity = Vector3.ZERO
	_car.look_at(start + facing, Vector3.UP)
	await _idle(10)
	_escapes = 0
	_was_escaping = false
	_car.issue(MoveOrder.new(aim))

	var elapsed := 0.0
	var worst := 0.0
	# How far the car strays from the straight line between start and aim -- the
	# manoeuvre's footprint. A bounded turn works within the street; the old release swept
	# out and looped, which arrival time cannot see (the sweep is often *faster*).
	var line := aim - start
	line.y = 0.0
	var line_dir := line.normalized()
	var stray := 0.0
	for i in 20:
		await physics_frame
		elapsed += 1.0 / 60.0
	var trace := OS.get_environment("PROBE_TRACE") != ""
	var tick := 0
	while elapsed < PATIENCE and _car.is_navigating():
		await physics_frame
		elapsed += 1.0 / 60.0
		tick += 1
		worst = maxf(worst, _car.global_position.distance_to(start))
		var off := _car.global_position - start
		off.y = 0.0
		stray = maxf(stray, (off - line_dir * off.dot(line_dir)).length())
		var escaping := _car.is_escaping()
		if escaping and not _was_escaping:
			_escapes += 1
		_was_escaping = escaping
		# The loop's anatomy, twice a second: which recovery owns the car, what the
		# steering is doing, and how far the aim sits from the nose. `heading to aim` is
		# to `move_target`; the autopilot steers at the steer point, so a large gap
		# between the two columns is itself a finding.
		if trace and tick % 30 == 0:
			var fwd := -_car.global_basis.z
			var to_aim := _car.move_target - _car.global_position
			to_aim.y = 0.0
			var steer_pt := _car._steer_point()
			var to_sp := steer_pt - _car.global_position
			to_sp.y = 0.0
			print("  t=%5.1f spd %5.1f  aim %5.1fm %4.0fdeg  steerpt %4.1fm %4.0fdeg  lock %5.1fdeg  rev:%s esc:%s"
				% [elapsed, _car.forward_speed, to_aim.length(),
					rad_to_deg(fwd.angle_to(to_aim)), to_sp.length(),
					rad_to_deg(fwd.angle_to(to_sp)),
					rad_to_deg(_car._steer_angle),
					_car.is_turning_round(), _car.is_escaping()])

	var gap := Vector2(_car.global_position.x - aim.x,
		_car.global_position.z - aim.z).length()
	print("\n--- %s  (aim %.1fm out)" % [label, start.distance_to(aim)])
	print("  arrived   %s after %.1fs   (%.1fm short)"
		% [not _car.is_navigating(), elapsed, gap])
	print("  escapes fired %d    ranged %.1fm from the start    strayed %.1fm off the line"
		% [_escapes, worst, stray])


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
