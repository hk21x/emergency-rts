extends SceneTree

## Dev utility: can an engine wedged at a junction ever earn a kerb climb?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_wedge.gd
##
## Reported from play: *"the fire engine keeps getting stuck on junctions as it is not
## mounting the kerbs."*
##
## That is a different gate from the one `probe_kerb.gd` exercises. A car **sent** onto a
## pavement climbs on `_off_road_target` alone, and that path works. A car with an
## ordinary road destination has to earn it:
##
##     if _stuck_time < climb_after or _failed_escapes < climb_escapes: return
##
## and both halves are set by `_update_escape`, which counts on *instantaneous speed*:
## when an escape fires it zeroes `_stuck_time`, and the moment the car exceeds 0.3 m/s
## it zeroes `_failed_escapes` as well. So the suspicion this measures is that a wedged
## engine -- one that can still shuffle a little -- resets its own counters faster than it
## can accumulate them, and is therefore never allowed to climb at all.
##
## Reports the high-water marks of both terms against the thresholds they must clear.

const SCENE := "res://Game/Playground.tscn"
var PATIENCE := 45.0

var _scene: Node3D
var _car: Vehicle
var _climbs := 0


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
	station.career_path = "user://probe-wedge-career.cfg"
	station.funds = 999999
	station.owned = {}
	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "engine")
	station.purchase(kind)
	_car = station.dispatch(kind) as Vehicle
	if _car == null:
		print("no such unit"); quit(); return
	await _idle(40)
	if OS.get_environment("PROBE_PATIENCE") != "":
		PATIENCE = float(OS.get_environment("PROBE_PATIENCE"))
	_car.climbed.connect(func(_who: Vehicle) -> void: _climbs += 1)

	print("\n============ WEDGE PROBE: %s ============" % _car.display_name)
	print("gate: stuck_time >= %.2f AND failed_escapes >= %d"
		% [_car.climb_after, _car.climb_escapes])

	# The turning legs the corner probe uses -- each crosses both a column and a row, so
	# each contains a real right angle for the longest body on the map to get round.
	for hop: Array in [[Vector2i(1, 1), Vector2i(4, 3)], [Vector2i(4, 3), Vector2i(1, 4)],
			[Vector2i(1, 4), Vector2i(3, 1)]]:
		await _leg(hop[0] as Vector2i, hop[1] as Vector2i)
	quit()


func _leg(from: Vector2i, to: Vector2i) -> void:
	var start := CityGrid.junction(from)
	var finish := CityGrid.junction(to)
	_car.clear_orders()
	_car.global_position = start + Vector3.UP * 0.2
	_car.velocity = Vector3.ZERO
	_car.look_at(start + Vector3(finish - start).normalized(), Vector3.UP)
	await _idle(10)
	_climbs = 0
	_car.issue(MoveOrder.new(finish))

	var elapsed := 0.0
	var worst_stuck := 0.0
	var worst_escapes := 0
	var escapes_seen := 0
	var was_escaping := false
	var crawling := 0
	var blocked := 0
	var held := 0
	for i in 20:
		await physics_frame
		elapsed += 1.0 / 60.0
	while elapsed < PATIENCE and _car.is_navigating():
		await physics_frame
		elapsed += 1.0 / 60.0
		worst_stuck = maxf(worst_stuck, _car._stuck_time)
		worst_escapes = maxi(worst_escapes, _car._failed_escapes)
		if absf(_car.forward_speed) < 0.3:
			crawling += 1
			# The physical half of the gate, replicated: is there actually anything in
			# front of this car to climb? `_climb_kerb` requires `test_move` along the
			# nose to report a collision -- if nothing is there, no gate change can ever
			# produce a climb, because there is no step to get up.
			var along := -_car.global_basis.z
			along = Vector3(along.x, 0.0, along.z).normalized() * _car.climb_reach
			if _car.test_move(_car.global_transform, along):
				blocked += 1
			if _car._blocker != null:
				held += 1
		var escaping := _car.is_escaping()
		if escaping and not was_escaping:
			escapes_seen += 1
		was_escaping = escaping

	print("\n--- %d,%d -> %d,%d" % [from.x, from.y, to.x, to.y])
	print("  arrived              %s after %.1fs" % [not _car.is_navigating(), elapsed])
	print("  frames under 0.3 m/s %d" % crawling)
	print("  escapes fired        %d" % escapes_seen)
	print("  highest stuck_time   %.2f  (needs %.2f)" % [worst_stuck, _car.climb_after])
	print("  highest failed_escapes %d  (needs %d)"
		% [worst_escapes, _car.climb_escapes])
	print("  crawling AND something in front  %d of %d frames" % [blocked, crawling])
	print("  crawling AND held behind a car   %d of %d frames" % [held, crawling])
	print("  climbs fired         %d" % _climbs)


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
