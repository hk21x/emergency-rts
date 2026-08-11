extends SceneTree

## Dev utility: does a stuck car get over a kerb, and does the district still contain
## a car that is not stuck?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_kerb.gd
##
## Two passes, because this feature has two ways to be wrong and they pull against
## each other. Making a kerb climbable is easy; making it climbable *only* when it
## should be is the whole problem, and the two attempts before this one both shipped
## the first and lost the second.
##
##   1. **The wedge.** A car aimed squarely at a kerb with somewhere to be on the far
##      side. Before any of this it halted 2.8m short and oscillated there forever.
##   2. **The corner.** The turn into junction 1,3 -- the case that killed the bevel,
##      measured the same way so the numbers are comparable with the ones in
##      PROGRESS.md: time, frames off the carriageway, furthest off the drivable mesh.
##      The bevel read 30.6s / 328 of 1836 / 4.9m; without it, 17.1s / 0 / 0.4m.
##
## Nothing here asserts -- it prints numbers for a human to judge. The suite is where a
## fixed behaviour gets pinned.

const SCENE := "res://Game/Playground.tscn"

var _scene: Node3D
var _station: Node
var _car: Vehicle
var _climbs := 0
## Forward speed at the moment of each lift. The complaint this pass exists to settle is
## about *when* the climb fires, not whether it does: a car that has to stop dead against
## the kerb first reads as broken however reliably it gets up afterwards.
var _climb_speeds: Array[float] = []


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
	_station.career_path = "user://probe-kerb-career.cfg"
	_station.funds = 999999
	_station.owned = {}
	_station.purchase(&"patrol")
	_car = _station.dispatch(&"patrol") as Vehicle
	_car.climbed.connect(func(_v: Vehicle) -> void:
		_climbs += 1
		_climb_speeds.append(_car.forward_speed))
	await _idle(40)

	print("\n================ KERB PROBE ================")
	print("climb_height %.2f  climb_reach %.2f  climb_after %.2f  stuck_timeout %.2f"
		% [_car.climb_height, _car.climb_reach, _car.climb_after, _car.stuck_timeout])

	# **One condition per process.** Running both in one process is what the first
	# version did, and it measured the harness rather than the feature: whichever
	# condition ran *second* failed, and swapping the order swapped which one failed --
	# 11.4s and 30.0s, exactly reversed, with the climb firing zero times in the run
	# that supposedly proved it harmful. The wedge leaves the district changed enough
	# that the next pass is not the same experiment. Fresh process, fresh scene, one
	# number each.
	var climbing := OS.get_environment("KERB_CLIMB") == "1"
	var which := OS.get_environment("KERB_PASS")
	print("condition: climbing %s, pass %s" % ["ON" if climbing else "OFF", which])
	if which == "wedge":
		await _wedge(climbing)
	elif which == "sent":
		await _sent_off_road(climbing)
	elif which == "bench":
		await _bench(climbing)
	else:
		await _corner(climbing)
	quit()


# --- Pass 4: sent off the road ------------------------------------------------

## The player's case: right-click a pavement and expect the car to get up onto it.
##
## This is what "still can't get on kerbs" actually meant, and it is a different
## question from every other pass here -- those all ask whether a *stuck* car can climb
## out, which is a fault being worked around. This one asks whether a car told to go
## somewhere off the road obeys, which is a verb the player has.
func _sent_off_road(climbing: bool) -> void:
	print("\n--- 4. SENT OFF THE ROAD --------------------------")
	var kerb := _find_a_kerb()
	if kerb.is_empty():
		print("  no kerb found -- the district's road edges have moved")
		return
	var edge: Vector3 = kerb["edge"]
	var across: Vector3 = kerb["across"]

	_car.clear_orders()
	_set_climbing(climbing)
	_car.global_position = edge - across * 8.0 + Vector3(0.0, 0.15, 0.0)
	_car.velocity = Vector3.ZERO
	_car.forward_speed = 0.0
	await _idle(20)

	# Four metres onto the pavement: clear of the kerb line, so arriving means the car
	# genuinely got up rather than stopping with its nose against the face.
	var target := edge + across * 4.0
	var started := _car.global_position
	_climbs = 0
	_climb_speeds.clear()
	var bill_before := _car.repair_bill
	_car.issue(MoveOrder.new(target))

	var frames := 0
	var arrived := false
	var highest := _car.global_position.y
	var got_up := false
	var stalled := 0
	var up_at := -1
	for i in 60 * 25:
		await physics_frame
		frames += 1
		highest = maxf(highest, _car.global_position.y)
		# Frames spent crawling before the car is up. This is the complaint: a car that
		# waits at the face until it has slowed enough to be allowed over.
		if not got_up and absf(_car.forward_speed) < 0.3:
			stalled += 1
		if not CityGrid.is_road(_car.global_position):
			if not got_up:
				up_at = frames
			got_up = true
		if not _car.has_orders():
			arrived = true
			break

	print("  sent from %s to %s, %.1fm onto the pavement"
		% [_str(started), _str(target), 4.0])
	print("  order finished       %s  (after %.1fs)" % [arrived, frames / 60.0])
	print("  got up onto it       %s  (%.1fs in)" % [got_up, up_at / 60.0])
	print("  crawling before that %d frames (%.1fs) under 0.3 m/s"
		% [stalled, stalled / 60.0])
	print("  speed at each climb  %s" % [_climb_speeds])
	print("  repair bill          £%d  (kerb struck at speed bills as a collision)"
		% (_car.repair_bill - bill_before))
	print("  climbs fired         %d" % _climbs)
	print("  highest y            %.2f  (kerb is 0.07)" % highest)
	print("  ended %.1fm from the target, %s"
		% [_flat(_car.global_position - target),
			"on the pavement" if not CityGrid.is_road(_car.global_position) else "on the road"])


# --- Pass 3: the bench test ---------------------------------------------------

## Does the lift work at all, put squarely in front of a kerb?
##
## Every staged *scenario* leaves the car nowhere near a kerb -- it queues seven metres
## short of a blockade, threads a single obstruction without touching the verge, and an
## order aimed past a kerb completes on the first frame because the agent clamps an
## off-mesh destination. So this stops staging traffic and asks the mechanism directly:
## nose against the kerb, the stuck tally held where a genuinely wedged car's would be,
## and a straight answer about whether the car gets up.
func _bench(climbing: bool) -> void:
	print("\n--- 3. THE BENCH TEST -----------------------------")
	var kerb := _find_a_kerb()
	if kerb.is_empty():
		print("  no kerb found -- the district's road edges have moved")
		return
	var edge: Vector3 = kerb["edge"]
	var across: Vector3 = kerb["across"]
	var along := Vector3(across.z, 0.0, across.x)

	_car.clear_orders()
	_set_climbing(climbing)
	_car.global_position = edge - across * 2.4 + Vector3(0.0, 0.15, 0.0)
	_car.look_at(edge + across * 10.0, Vector3.UP)
	_car.velocity = Vector3.ZERO
	_car.forward_speed = 0.0
	await _idle(20)

	# **The lift called directly, not driven into.** Letting the autopilot do it does not
	# work and cannot be made to: aimed past the kerb the order completes on frame one,
	# and aimed along the road the car simply steers away -- measured, it drove 18.7m up
	# the street instead. The autopilot will not drive into a kerb, which is the whole
	# reason this had to be asked of the mechanism rather than of a scenario.
	var started_y := _car.global_position.y
	_climbs = 0
	_car.set("_failed_escapes", 9)
	_car.set("_stuck_time", 5.0)
	var blocked_before := _car.test_move(_car.global_transform, -_car.global_basis.z * 1.2)
	_car.call("_climb_kerb")
	var risen := _car.global_position.y - started_y

	print("  nose against the kerb at %s" % _str(edge))
	print("  road ahead blocked   %s   (if false, the car is not against anything)"
		% blocked_before)
	print("  climbs fired         %d" % _climbs)
	print("  rose                 %.2fm  (climb_height %.2f)" % [risen, _car.climb_height])

	# Which of the three gates said no. Replicated here rather than instrumented into
	# Vehicle.gd, so the probe reports on the shipped code rather than on a version of
	# it that only exists while being measured.
	var lift := Vector3.UP * _car.climb_height
	var ahead := -_car.global_basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z).normalized() * _car.climb_reach
	print("  gate 1 blocked ahead     %s  (want true)"
		% _car.test_move(_car.global_transform, ahead))
	print("  gate 2 headroom to rise  %s  (want true)"
		% not _car.test_move(_car.global_transform, lift))
	print("  gate 3 clear once risen  %s  (want true)"
		% not _car.test_move(_car.global_transform.translated(lift), ahead))
	var landing := _car.global_position + ahead
	var map := _car.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, _car.global_position, landing, true, 1)
	var reach := 999.0
	if not path.is_empty():
		var last := path[path.size() - 1]
		reach = _flat(last - landing)
	print("  gate 4 landing drivable  %s  (path ends %.2fm from it, allowed %.2f)"
		% [reach <= _car.climb_landing, reach, _car.climb_landing])


## Turns the climb on or off by moving its trigger out of reach, so both runs are the
## same code path with one number changed.
func _set_climbing(on: bool) -> void:
	_car.climb_after = 0.5 if on else 9999.0


# --- Pass 1: the wedge --------------------------------------------------------

## Aims the car at a kerb from three metres out and watches whether it gets over.
func _wedge(climbing: bool) -> void:
	print("\n--- 1. THE WEDGE ----------------------------------")
	var kerb := _find_a_kerb()
	if kerb.is_empty():
		print("  no kerb found -- the district's road edges have moved")
		return
	var edge: Vector3 = kerb["edge"]
	var across: Vector3 = kerb["across"]

	# **Driven at the kerb by a blocker, not by its target.** Aiming an order at a point
	# on the pavement does nothing at all: the agent clamps an off-mesh destination to
	# the nearest reachable point, `is_navigation_finished()` goes true on the first
	# frame and the order completes without the car turning a wheel. That is worth
	# knowing on its own -- a car is never *routed* over a kerb. The only thing that
	# drives one into a kerb is `_passing_line`, which deliberately aims wide of the
	# carriageway to get round an obstruction and relies on the kerb as a rail. So the
	# staging is a car parked in the lane, which is the real mechanism.
	_car.clear_orders()
	_set_climbing(climbing)
	var along := Vector3(across.z, 0.0, across.x)
	var lane := edge - across * 2.0
	# **A street genuinely shut, not one car in it.** One car parked in the lane is
	# passable in 3.6s without ever touching a kerb, and angling it across the lane
	# changed nothing -- both measured, both identical to the metre with the climb on
	# and off. The carriageway is simply wide enough. Only a rank of cars filling its
	# full width leaves the passing line nowhere to go but over the kerb, which is the
	# same finding the blockade pass in `diagnose_driving.gd` records.
	# Five, spanning the carriageway from the kerb outward. Three left a gap: the car
	# threaded it in 11.4s without touching a kerb, identical with the climb on and off.
	# The documented shape of "no way through" is a rank filling the full width.
	var blockers: Array[Vehicle] = []
	for i in 5:
		var spot := edge - across * (1.0 + float(i) * 2.6) + along * 18.0
		blockers.append(_blocker_at(spot, along))
	_car.global_position = lane + Vector3(0.0, 0.15, 0.0)
	_car.look_at(lane + along * 10.0, Vector3.UP)
	_car.velocity = Vector3.ZERO
	_car.forward_speed = 0.0
	await _idle(20)

	var started := _car.global_position
	_climbs = 0
	_car.issue(MoveOrder.new(lane + along * 40.0))

	var frames := 0
	var off_carriageway := 0
	var highest := _car.global_position.y
	var arrived := false
	for i in 60 * 30:
		await physics_frame
		frames += 1
		highest = maxf(highest, _car.global_position.y)
		if not CityGrid.is_road(_car.global_position):
			off_carriageway += 1
		if not _car.has_orders():
			arrived = true
			break

	var standing := 0
	for one in blockers:
		if is_instance_valid(one):
			standing += 1
	print("  %d cars across the street 18m ahead; ours sent 40m up it" % standing)
	print("  got past it:               %s  (in %.1fs)" % [arrived, frames / 60.0])
	print("  travelled                  %.1fm" % _flat(_car.global_position - started))
	print("  climbs fired               %d" % _climbs)
	print("  frames up on the pavement  %d of %d" % [off_carriageway, frames])
	print("  highest y                  %.2f" % highest)
	for one in blockers:
		if is_instance_valid(one):
			one.queue_free()
	await _idle(10)


## Parks a second vehicle in the lane, facing along it, as an obstruction.
func _blocker_at(spot: Vector3, facing: Vector3) -> Vehicle:
	_station.purchase(&"patrol")
	var blocker := _station.dispatch(&"patrol") as Vehicle
	if blocker == null:
		return null
	blocker.clear_orders()
	blocker.global_position = spot + Vector3(0.0, 0.15, 0.0)
	blocker.look_at(spot + facing * 10.0, Vector3.UP)
	blocker.velocity = Vector3.ZERO
	return blocker


## A point on the carriageway edge and the direction across it onto the pavement.
##
## Found by walking sideways off the centre of a road band until [method
## CityGrid.is_road] stops being true, rather than by naming coordinates: the band
## tables are deliberately irregular and a hand-picked number lands in a building often
## enough that the first version of a probe like this reported a pathfinding fault that
## was really a bad waypoint.
func _find_a_kerb() -> Dictionary:
	var start := CityGrid.junction(Vector2i(2, 2))
	for direction: Vector3 in [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
		# Step along the road first, so the sweep is not measuring a junction box.
		var along := Vector3(direction.z, 0.0, direction.x)
		var base := start + along * 14.0
		if not CityGrid.is_road(base):
			continue
		for step in 40:
			var here := base + direction * (0.25 * step)
			if not CityGrid.is_road(here):
				return {"edge": here, "across": direction}
	return {}


# --- Pass 2: the corner -------------------------------------------------------

## The turn the bevel died on. Same measures as PROGRESS.md records for it.
func _corner(climbing: bool) -> void:
	print("\n--- 2. THE CORNER (into junction 1,3) -------------")
	var from := CityGrid.junction(Vector2i(1, 1))
	var to := CityGrid.junction(Vector2i(1, 3))
	_car.clear_orders()
	_set_climbing(climbing)
	_car.global_position = from + Vector3(0.0, 0.15, 0.0)
	_car.velocity = Vector3.ZERO
	_car.forward_speed = 0.0
	await _idle(30)

	_climbs = 0
	_car.issue(MoveOrder.new(to))
	var frames := 0
	var off_carriageway := 0
	var worst_off_mesh := 0.0
	var map := _car.get_world_3d().navigation_map
	for i in 60 * 60:
		await physics_frame
		if not _car.has_orders():
			break
		frames += 1
		if not CityGrid.is_road(_car.global_position):
			off_carriageway += 1
		var nearest := NavigationServer3D.map_get_closest_point(map, _car.global_position)
		worst_off_mesh = maxf(worst_off_mesh, _flat(nearest - _car.global_position))

	print("  arrived: %s" % (not _car.has_orders()))
	print("  time                       %.1fs   (bevel 30.6s, no bevel 17.1s)" % (frames / 60.0))
	print("  frames off the carriageway %d of %d   (bevel 328 of 1836, no bevel 0)"
		% [off_carriageway, frames])
	print("  furthest off the mesh      %.1fm   (bevel 4.9m, no bevel 0.4m)" % worst_off_mesh)
	print("  climbs fired               %d   (want 0 -- a clean corner needs none)" % _climbs)


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _str(point: Vector3) -> String:
	return "(%.0f, %.0f)" % [point.x, point.z]


func _idle(frames: int) -> void:
	for i in frames:
		await physics_frame
