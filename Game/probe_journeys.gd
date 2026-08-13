extends SceneTree

## Dev utility: does the fleet actually get where it is sent?
##
##   PROBE_UNIT=engine godot --headless --fixed-fps 60 --path . \
##       --script res://Game/probe_journeys.gd
##
## Written because the fault this measures **cannot be staged from a single record**.
## `probe_stall.gd` replays a black-box stall exactly -- same start, heading and
## destination -- and the car arrives every time. What the log describes is not a trap
## the car falls into from a standing start; it is a loop it enters some fraction of the
## time, from some approach, on some corner. One journey can only ever say "this one was
## fine".
##
## So this measures the aggregate instead: many seeded journeys across the district, and
## the three numbers that separate a fleet that drives from a fleet that shuffles --
## **how many arrive**, how long they take, and how often the stuck escape fires. The
## last is the direct reading: the escape backs a car out of trouble, and a car that
## needs backing out repeatedly on an empty road is the fault itself, counted.
##
## Seeded, so a change can be compared against a previous run rather than against a mood.

const SCENE := "res://Game/Playground.tscn"

## How many point-to-point trips. Enough that a fault firing on a minority of corners
## still shows up as a difference rather than as noise.
const JOURNEYS := 24

## Long enough for the longest diagonal at the slowest unit's speed, several times over.
## A journey that has not finished by here has not failed to be quick, it has failed.
## Overridable, because the first cut of this probe treated 45s as the line between
## "arrived" and "failed" without ever checking what an honest journey costs. At a
## corner-limited ~7 m/s across a 260m district, plenty of perfectly good journeys take
## longer than that -- so the arrival count was measuring the budget, not the fleet.
static func _patience() -> float:
	var given := OS.get_environment("PROBE_PATIENCE")
	return float(given) if given != "" else 45.0

var _scene: Node3D
var _car: Vehicle
var _escapes := 0
var _was_escaping := false
## Fastest this unit ever got, over every journey. The failure snapshots all read
## 6.6-6.7 m/s with the aim straight ahead, which is not a stall -- it is a crawl, and a
## crawl needs a different number to prove it than an arrival count does.
var _top_speed := 0.0


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
	station.career_path = "user://probe-journeys-career.cfg"
	station.funds = 999999
	station.owned = {}

	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "patrol")
	station.purchase(kind)
	_car = station.dispatch(kind) as Vehicle
	if _car == null:
		print("no such unit: %s" % kind)
		quit()
		return
	# Swept from outside rather than edited into the source: the bounded-lookahead fix
	# shipped at 6.0, and its documented cost is that a near aim keeps `turn_factor`
	# reading heading error as a reason not to accelerate. Whether that is capping the
	# whole fleet is a question one env var can answer.
	var look := OS.get_environment("PROBE_LOOKAHEAD")
	if look != "":
		_car.steer_lookahead_min = float(look)
	print("steer_lookahead_min %.1f" % _car.steer_lookahead_min)
	await _idle(40)

	# Seeded, never `randi()`: a probe whose route list changes between runs cannot
	# compare anything to anything.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260812

	print("\n============ JOURNEY PROBE: %s ============" % _car.display_name)
	print("%d journeys, %.0fs patience each" % [JOURNEYS, _patience()])

	var arrived := 0
	var total_time := 0.0
	var worst := 0.0
	var failures: Array[String] = []
	for i in JOURNEYS:
		var from := _cell(rng)
		var to := _cell(rng)
		# A journey has to cross both a column and a row, or it is a straight run with
		# no corner in it -- and corners are the whole subject. The corner probe learned
		# this the hard way, measuring three straight legs identically to the byte.
		while to.x == from.x or to.y == from.y:
			to = _cell(rng)
		var result := await _journey(from, to)
		total_time += result["time"]
		worst = maxf(worst, result["time"])
		if result["arrived"]:
			arrived += 1
		else:
			failures.append("    %d,%d -> %d,%d  stopped %.0fm short"
				% [from.x, from.y, to.x, to.y, result["short"]])

	print("\n  arrived           %d of %d" % [arrived, JOURNEYS])
	print("  mean time         %.1fs" % (total_time / float(JOURNEYS)))
	print("  worst journey     %.1fs" % worst)
	print("  escapes fired     %d  (reversals out of trouble on an empty road)" % _escapes)
	print("  top speed seen    %.1f of %.1f m/s" % [_top_speed, _car.max_speed])
	if not failures.is_empty():
		print("  did not arrive:")
		for line in failures:
			print(line)
	quit()


## One trip, reported rather than asserted.
func _journey(from: Vector2i, to: Vector2i) -> Dictionary:
	var start := CityGrid.junction(from)
	var finish := CityGrid.junction(to)
	_car.clear_orders()
	_car.global_position = start + Vector3.UP * 0.2
	_car.velocity = Vector3.ZERO
	_car.look_at(start + Vector3(finish - start).normalized(), Vector3.UP)
	await _idle(8)
	_car.issue(MoveOrder.new(finish))
	var elapsed := 0.0
	while elapsed < _patience():
		await process_frame
		elapsed += root.get_process_delta_time()
		# Counted on the rising edge, so a single escape is one event and not sixty.
		var escaping := _car.is_escaping()
		if escaping and not _was_escaping:
			_escapes += 1
		_was_escaping = escaping
		_top_speed = maxf(_top_speed, _car.forward_speed)
		if not _car.is_navigating() and elapsed > 0.5:
			return {"arrived": true, "time": elapsed, "short": 0.0}
	var offset := _car.global_position - finish
	offset.y = 0.0
	# **A snapshot at the moment of failure.** The aggregate says how many journeys die;
	# only this says what they die of, and two theories have already been wrong without
	# it -- the reverse latch was blamed for a distance gate it was never failing, and an
	# escalation built on that measured as a byte-for-byte no-op.
	var aim := _car.move_target - _car.global_position
	aim.y = 0.0
	var nose := -_car.global_basis.z
	nose.y = 0.0
	print("      speed %5.1f  aim %5.1fm at %4.0f°  escaping %s  turning %s  order %s"
		% [_car.forward_speed, aim.length(),
			rad_to_deg(nose.signed_angle_to(aim, Vector3.UP)),
			_car.is_escaping(), _car.is_turning_round(),
			_car.current_order().describe() if _car.current_order() else "none"])
	return {"arrived": false, "time": elapsed, "short": offset.length()}


func _cell(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(0, CityGrid.X_BANDS.size() - 2),
		rng.randi_range(0, CityGrid.Z_BANDS.size() - 2))


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
