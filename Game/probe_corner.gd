extends SceneTree

## Dev utility: how wide does a car actually take a corner?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_corner.gd
##
## Written for "the turns seem to corner too wide, almost as if the vehicles are
## oversteering". The arithmetic behind that complaint is in `_corner_speed_limit`: its
## anti-creep floor is a fraction of *top speed*, while the speed a corner can actually
## be held at comes from *geometry* -- wheelbase, steering lock and the lateral
## acceleration the tyres deliver. The two are unrelated, so on a fast enough vehicle the
## floor overtakes the physics, the planner refuses to slow down enough for the bend, and
## the yaw cap in `_apply_yaw` then clamps the turn rate. The car is at full lock and
## still running wide, which is exactly what oversteer looks like from above.
##
## Reports the two numbers that settle it: how far into the oncoming lane the car got,
## and how long the leg took -- because the failure mode of any fix here is trading a
## wide corner for a creeping one.
##
## **One leg per process.** Passes in this project contaminate each other; the kerb probe
## measured its own harness for three runs before that was spotted.

const SCENE := "res://Game/Playground.tscn"

## How close to the corner counts as being *in* the turn, for the arc fit. Wide enough
## to catch a junction turn's entry and exit, tight enough that the straights either
## side do not flatten the circle being fitted to it.
const CORNER_ZONE := 16.0

var _scene: Node3D
var _station: Node
var _car: Vehicle


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	await process_frame
	# **Redirect the black box before anything drives.** [StuckLog] lives in the map scene
	# and defaults to the player's own `user://stuck-log.txt`, so a probe that loads
	# Playground.tscn quietly appends its fixtures to the file the player's real faults
	# are read from -- 149 records of staged driving in one session, indistinguishable
	# afterwards from play. The suite learned this the hard way and redirects for the same
	# reason; a probe drives far more than the suite does.
	var stuck := _scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://probe-stuck-log.txt"
	_station = _scene.get_node("Station")
	_station.career_path = "user://probe-corner-career.cfg"
	_station.funds = 999999
	_station.owned = {}
	# Which unit to drive. The appliance is the reason this exists in a second form: it
	# is the longest body on the map, and turn radius is wheelbase over tan(steer), so
	# it corners widest by construction rather than by accident.
	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "patrol")
	_station.purchase(kind)
	_car = _station.dispatch(kind) as Vehicle
	if _car == null:
		print("no such unit: %s" % kind)
		quit()
		return
	# Swept from outside rather than edited into the source: `corner_window` is how far
	# past a vertex the outgoing direction is sampled, so too long a window reads a right
	# angle as a gentler bend than it is, and the planner books a speed for the bend it
	# thinks it saw.
	var window := OS.get_environment("CORNER_WINDOW")
	if window != "":
		_car.corner_window = float(window)
	await _idle(40)
	print("corner_window %.1f" % _car.corner_window)

	var radius: float = _car.wheelbase / tan(deg_to_rad(_car.max_steer_degrees))
	var tightest: float = sqrt(_car.max_lateral_accel * _car.grip_scale * radius)
	print("\n============ CORNER PROBE ============")
	print("%s  max_speed %.1f" % [_car.display_name, _car.max_speed])
	print("  right-angle turn holdable at %.2f m/s, planner floor %.2f m/s"
		% [tightest, _car.max_speed * _car.corner_speed_ratio])

	# **Legs that actually turn.** The first version of this used (1,1)->(1,3),
	# (1,3)->(4,3) and (4,3)->(4,1), every one of which shares a column or a row -- three
	# straight runs with no corner in them, which is why they measured identically to the
	# byte before and after a change to the corner planner. A leg has to cross both a
	# column and a row before the route contains a right angle at all.
	for hop: Array in [[Vector2i(1, 1), Vector2i(4, 3)], [Vector2i(4, 3), Vector2i(1, 4)],
			[Vector2i(1, 4), Vector2i(3, 1)]]:
		await _turn(hop[0], hop[1])
	quit()


func _turn(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var from := CityGrid.junction(from_cell)
	var to := CityGrid.junction(to_cell)
	_car.clear_orders()
	_car.global_position = from + Vector3(0.0, 0.15, 0.0)
	_car.velocity = Vector3.ZERO
	_car.forward_speed = 0.0
	await _idle(30)

	# **Where the corner actually is**, found from the route's own geometry rather than
	# from the planner -- the planner's opinion of a corner is one of the things under
	# investigation, so it cannot also be the yardstick.
	var corner := _sharpest_corner(from, to)

	_car.issue(MoveOrder.new(to))
	var frames := 0
	var worst := 0.0
	var off := 0
	var top := 0.0
	# Step 0: samples taken *inside* the turn, which is the thing every earlier metric
	# here was blind to. `_lane_offset` returns zero in a junction box -- see its own
	# `in_x == in_z` test -- so "deepest into the oncoming lane" has only ever measured
	# the *exit* from a corner, never the corner. A leg reading 0.00m was not a clean
	# turn, it was an unmeasured one.
	var arc: Array[Vector3] = []
	# Step 1: the five readings at the apex, taken together on the one frame of closest
	# approach, so they can be compared against each other rather than across runs.
	var nearest := INF
	var apex := {}
	# What the corner planner actually asks for, sampled rather than assumed. The first
	# theory here was that its anti-creep floor was too high; lowering that floor changed
	# the trajectory by not one byte, which only makes sense if the planner never proposes
	# anything near the floor in the first place.
	var slowest_plan := INF
	var slowest_lock := INF
	for i in 60 * 60:
		await physics_frame
		if not _car.has_orders():
			break
		frames += 1
		top = maxf(top, _car.forward_speed)
		slowest_plan = minf(slowest_plan, _car.call("_corner_speed_limit"))
		slowest_lock = minf(slowest_lock, absf(_car.get("_steer_angle")))
		if corner != Vector3.INF:
			var gap := _flat(_car.global_position - corner)
			if gap <= CORNER_ZONE:
				arc.append(_car.global_position)
			if gap < nearest:
				nearest = gap
				apex = _apex_reading(corner)
		if OS.get_environment("CORNER_TRACE") == "1" and frames % 12 == 0:
			_trace()
		if not CityGrid.is_road(_car.global_position):
			off += 1
		# Distance into the oncoming half of the carriageway. The same measure the suite's
		# lane checks and `diagnose_driving.gd` use, so the numbers are comparable.
		var across := _lane_offset(_car.global_position)
		if across == Vector3.ZERO:
			continue
		var right := (-_car.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		worst = minf(worst, across.dot(right.normalized()))

	print("\n  %s -> %s" % [from_cell, to_cell])
	print("    arrived %s in %.1fs, top speed %.1f m/s"
		% [not _car.has_orders(), frames / 60.0, top])
	print("    deepest into the oncoming lane  %.2fm  (blind inside the junction box)"
		% -worst)
	print("    frames off the carriageway      %d of %d" % [off, frames])

	# --- Step 0: the arc the car actually described -------------------------
	if corner == Vector3.INF:
		print("    no corner found in the route -- nothing to measure")
		return
	var geometric: float = _car.wheelbase / tan(deg_to_rad(_car.max_steer_degrees))
	var fit := _fit_circle(arc)
	if fit.is_empty():
		print("    turn radius                     -- too few samples (%d)" % arc.size())
	else:
		print("    TURN RADIUS DESCRIBED           %.2fm over %d samples"
			% [fit["radius"], arc.size()])
		print("      against %.2fm the steering can describe, and %.2fm the yaw cap"
			% [geometric, _car.max_speed * 0.0 + _cap_radius(apex.get("speed", 0.0))])
		print("      widest the car swung from the corner  %.2fm" % _widest(arc, corner))

	# --- Step 1: the five readings at the apex ------------------------------
	if apex.is_empty():
		return
	print("    AT THE APEX (%.1fm from the corner):" % nearest)
	print("      1 speed %.2f m/s   planner asked for %.2f   %s"
		% [apex["speed"], apex["planned"],
			"OBEYING" if apex["speed"] <= apex["planned"] + 1.0 else "*** OVER ***"])
	print("      2 steer %.1f°   of %.1f° available   %s"
		% [rad_to_deg(apex["steer"]), rad_to_deg(apex["lock"]),
			"*** AT LOCK ***" if apex["steer"] >= apex["lock"] - 0.02 else "not at lock"])
	print("      3 yaw wanted %.2f rad/s   cap %.2f   %s"
		% [apex["yaw_want"], apex["yaw_cap"],
			"*** CAPPED ***" if apex["yaw_want"] > apex["yaw_cap"] else "not capped"])
	print("      4 aiming %.1fm ahead, %.0f° off the nose"
		% [apex["aim_range"], rad_to_deg(apex["aim_bearing"])])
	print("      5 aim point is %s the corner   %s"
		% ["PAST" if apex["aim_past"] else "short of",
			"*** STEERING THROUGH THE TURN ***" if apex["aim_past"] else ""])
	print("    slowest the planner ever asked  %.2f m/s  (floor %.2f, holdable %.2f)"
		% [slowest_plan, minf(_car.max_speed * _car.corner_speed_ratio,
			_car.call("_turn_speed", PI * 0.5)), _car.call("_turn_speed", PI * 0.5)])


## Replays `_corner_speed_limit`'s own loop and prints its terms, so the question "why
## does it never ask for less than 11 m/s" gets an answer instead of another theory.
##
## Replayed here rather than instrumented into `Vehicle.gd` so the probe reports on the
## shipped code, not on a version that only exists while being measured.
func _trace() -> void:
	var agent := _car.get_node("NavigationAgent") as NavigationAgent3D
	var path := agent.get_current_navigation_path()
	var index := agent.get_current_navigation_path_index()
	if path.size() < 2 or index >= path.size():
		return
	var travelled := 0.0
	var previous := _car.global_position
	var seen: Array[String] = []
	for i in range(index, path.size() - 1):
		var point: Vector3 = path[i]
		var incoming := point - previous
		travelled += _flat(incoming)
		previous = point
		if travelled > _car.corner_lookahead:
			break
		var turn: float = _car.call("_flat_angle", incoming,
			_car.call("_direction_after", path, i))
		if turn < deg_to_rad(_car.corner_min_degrees):
			continue
		var through: float = _car.call("_turn_speed", turn)
		var allows: float = sqrt(through * through + 2.0 * _car.brake_deceleration
			* _car.corner_brake_ratio * travelled)
		seen.append("[v%d %.0f° at %.0fm -> hold %.1f, allows %.1f]"
			% [i, rad_to_deg(turn), travelled, through, allows])
	print("    idx %d/%d  spd %.1f  %s"
		% [index, path.size(), _car.forward_speed,
			" ".join(seen) if seen.size() > 0 else "NO CORNER SEEN"])


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


## The sharpest bend in the lane route between two points, or INF if the route is
## straight. Taken from `CityGrid.lane_route` -- the route the order will actually
## follow -- and measured with plain geometry, because the planner's own opinion of
## where a corner is and how sharp it is is the thing under investigation and cannot
## also be the yardstick.
func _sharpest_corner(from: Vector3, to: Vector3) -> Vector3:
	var points := CityGrid.lane_route(from, to)
	if points.size() < 2:
		return Vector3.INF
	var best := Vector3.INF
	var sharpest := 0.0
	var previous := from
	for i in points.size():
		var here: Vector3 = points[i]
		var onward: Vector3 = points[i + 1] if i + 1 < points.size() else to
		var a := Vector2(here.x - previous.x, here.z - previous.z)
		var b := Vector2(onward.x - here.x, onward.z - here.z)
		previous = here
		if a.length() < 0.5 or b.length() < 0.5:
			continue
		var turn := absf(a.angle_to(b))
		if turn > sharpest:
			sharpest = turn
			best = here
	return best if sharpest > deg_to_rad(30.0) else Vector3.INF


## Everything worth knowing about one frame, captured together.
##
## Together is the point. Each of these has been looked at on its own across this
## investigation and each time the answer was "that one looks fine"; what has never been
## available is all five on the *same frame*, where they can be read against each other
## -- a car at full lock and still running wide means something quite different from a
## car that never reached lock.
func _apex_reading(corner: Vector3) -> Dictionary:
	var speed: float = _car.forward_speed
	var ratio := clampf(absf(speed) / _car.max_speed, 0.0, 1.0)
	var lock: float = deg_to_rad(_car.max_steer_degrees) \
		* lerpf(1.0, 1.0 - _car.speed_steer_falloff, ratio)
	var steer: float = absf(_car.get("_steer_angle"))
	var agent := _car.get_node("NavigationAgent") as NavigationAgent3D
	var aim: Vector3 = agent.get_next_path_position()
	var to_aim := aim - _car.global_position
	to_aim.y = 0.0
	var nose := -_car.global_basis.z
	nose.y = 0.0
	# "Past the corner" means beyond it along the way the route leaves it -- a steer
	# point on the far side of a bend is one the car drives straight through the bend to
	# reach, whatever speed it arrives at.
	var onward := _car.move_target - corner
	onward.y = 0.0
	var beyond := false
	if onward.length() > 0.5:
		beyond = (aim - corner).dot(onward.normalized()) > 0.0
	return {
		"speed": speed,
		"planned": _car.call("_corner_speed_limit"),
		"steer": steer,
		"lock": lock,
		"yaw_want": absf(speed / _car.wheelbase * tan(steer)),
		"yaw_cap": _car.max_lateral_accel * _car.grip_scale / maxf(absf(speed), 1.0),
		"aim_range": _flat(to_aim),
		"aim_bearing": absf(Vector2(nose.x, nose.z).angle_to(Vector2(to_aim.x, to_aim.z))),
		"aim_past": beyond,
	}


## The tightest circle the yaw cap permits at [param speed]: the cap is an angular rate
## of `lateral_accel / v`, and radius is `v / rate`, so it grows as the square of speed.
func _cap_radius(speed: float) -> float:
	var rate: float = _car.max_lateral_accel * _car.grip_scale / maxf(absf(speed), 1.0)
	return absf(speed) / maxf(rate, 0.001)


## Radius of the arc through [param points], by algebraic least squares (Kåsa). Fitting
## a circle rather than reporting a peak deviation because there is something to compare
## it with: the steering describes a known circle and the yaw cap permits another, so a
## measured radius says immediately which of the two the car is actually limited by.
func _fit_circle(points: Array[Vector3]) -> Dictionary:
	if points.size() < 8:
		return {}
	var n := float(points.size())
	var mx := 0.0
	var mz := 0.0
	for p in points:
		mx += p.x
		mz += p.z
	mx /= n
	mz /= n
	var suu := 0.0
	var svv := 0.0
	var suv := 0.0
	var suuu := 0.0
	var svvv := 0.0
	var suvv := 0.0
	var svuu := 0.0
	for p in points:
		var u := p.x - mx
		var v := p.z - mz
		suu += u * u
		svv += v * v
		suv += u * v
		suuu += u * u * u
		svvv += v * v * v
		suvv += u * v * v
		svuu += v * u * u
	var det := suu * svv - suv * suv
	if absf(det) < 0.0001:
		return {}
	var a := (0.5 * (suuu + suvv) * svv - 0.5 * (svvv + svuu) * suv) / det
	var b := (0.5 * (svvv + svuu) * suu - 0.5 * (suuu + suvv) * suv) / det
	return {"radius": sqrt(a * a + b * b + (suu + svv) / n),
		"centre": Vector3(mx + a, 0.0, mz + b)}


## How far the car's arc swung from the corner it was rounding. A wide turn stands off;
## a tight one hugs it.
func _widest(points: Array[Vector3], corner: Vector3) -> float:
	var furthest := 0.0
	for p in points:
		furthest = maxf(furthest, _flat(p - corner))
	return furthest


## Offset from the centre line of the road band a point is on, or zero in a junction box.
func _lane_offset(point: Vector3) -> Vector3:
	var half := CityGrid.ROAD_WIDTH * CityGrid.TILE * 0.5
	var cx := CityGrid.band_centre_x(CityGrid.band_at_x(point.x))
	var cz := CityGrid.band_centre_z(CityGrid.band_at_z(point.z))
	var in_x: bool = absf(point.x - cx) <= half
	var in_z: bool = absf(point.z - cz) <= half
	if in_x == in_z:
		return Vector3.ZERO
	return Vector3(point.x - cx, 0.0, 0.0) if in_x else Vector3(0.0, 0.0, point.z - cz)


func _idle(frames: int) -> void:
	for i in frames:
		await physics_frame
