extends SceneTree

## Dev utility: does an appliance on a shout get past a **blocked street** by taking the
## pavement?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_mount.gd
##   PROBE_UNIT=patrol PROBE_SHORT=1 PROBE_WALL=2 PROBE_WALL_SHIFT=3.2 PROBE_PATIENCE=90 \
##     godot --headless --fixed-fps 60 --path . --script res://Game/probe_mount.gd
##
## `probe_wedge.gd` measured the scenario the *report* described -- an engine stuck turning
## a junction -- and answered it thoroughly: the car is queued behind traffic rather than
## against a kerb, and at a junction mouth the ground five metres to the side is off the
## navigation mesh but has no step on it at all. So a car aimed there drives over freely,
## and mounting changes nothing, because there is nothing to mount. Measured on the one leg
## of that probe that is a clean comparison, 76.7s became 76.2s.
##
## That makes the junction legs the **wrong fixture** for it rather than a verdict on it.
## What a mount is for is a *street* that is shut: a real kerb along both sides, a wall of
## stopped vehicles across the carriageway, and somewhere to be on the other side. This
## builds exactly that.
##
## **The pavement-mount behaviour itself is not in the tree** -- built, measured and
## reverted in August 2026, written up in full in NEXT.md under "Working notes". What
## survives is this fixture, which is the hard part and the only thing here that shuts a
## street. It reports the baseline: how an appliance copes with a blocked carriageway using
## nothing but the ordinary machinery. Re-add the instrumentation (`is_mounting()`,
## `_blocked_time`, `mount_after`) alongside the feature if it is picked up again -- and
## note `PROBE_SHORT`, which is the fixture that killed it: a hop under
## `CityGrid.LANE_ROUTE_MIN` cannot write the street off and re-route round the block, so
## the car has to deal with the wall in front of it.
##
## The blockers are ordinary player vehicles parked across the road and never given an
## order, so they sit there: [method Vehicle._vehicle_in_the_way] and
## [method Vehicle._lane_occupied] both scan the unit group, which is what makes them a
## wall rather than scenery.

const SCENE := "res://Game/Playground.tscn"

var _scene: Node3D
var _car: Vehicle
var _climbs := 0
var _patience := 60.0


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
	station.career_path = "user://probe-mount-career.cfg"
	station.funds = 999999
	station.owned = {}

	var kind := StringName(OS.get_environment("PROBE_UNIT") if
		OS.get_environment("PROBE_UNIT") != "" else "engine")
	station.purchase(kind)
	_car = station.dispatch(kind) as Vehicle
	if _car == null:
		print("no engine"); quit(); return

	# The wall. Three across the carriageway is what makes it a shut street rather than
	# something to overtake -- `_passing_line` finds a gap round one car every time.
	var wall: Array[Vehicle] = []
	var wall_size := int(OS.get_environment("PROBE_WALL")) if \
		OS.get_environment("PROBE_WALL") != "" else 3
	for i in wall_size:
		station.purchase(&"patrol")
		var one := station.dispatch(&"patrol") as Vehicle
		if one:
			wall.append(one)
	await _idle(40)

	if OS.get_environment("PROBE_MOUNT_AFTER") != "":
		# Absurdly high is the honest "off" switch: every other term stays as it is and the
		# licence simply never comes due.
		_car.mount_after = float(OS.get_environment("PROBE_MOUNT_AFTER"))
	if OS.get_environment("PROBE_NO_RETURN") != "":
		# The honest off-switch for the way back down, using the export rather than surgery:
		# a negative window means every recovery expires on the frame it starts.
		_car.return_window = -1.0
	if OS.get_environment("PROBE_PATIENCE") != "":
		_patience = float(OS.get_environment("PROBE_PATIENCE"))
	_car.climbed.connect(func(_who: Vehicle) -> void: _climbs += 1)

	print("\n============ SHUT-STREET PROBE: %s ============" % _car.display_name)

	# A straight street: two junctions on the same row, so the whole run is one heading and
	# nothing in the result is a cornering artefact.
	var start := CityGrid.junction(Vector2i(1, 1))
	var finish := CityGrid.junction(Vector2i(3, 1))
	var along := (finish - start).normalized()
	var across := along.cross(Vector3.UP)

	_car.clear_orders()
	_car.global_position = start + along * 6.0 + Vector3.UP * 0.2
	_car.velocity = Vector3.ZERO
	_car.look_at(_car.global_position + along, Vector3.UP)

	# Parked across the road 18m up, one in each lane and one straddling, so there is no
	# line through and the only way past is over the kerb.
	for i in wall.size():
		var one := wall[i]
		one.clear_orders()
		var spread := float(OS.get_environment("PROBE_WALL_SHIFT")) if \
			OS.get_environment("PROBE_WALL_SHIFT") != "" else 2.6
		one.global_position = (start + along * 24.0
			+ across * (float(i) - float(wall.size() - 1) * 0.5) * spread
			+ Vector3.UP * 0.2)
		one.velocity = Vector3.ZERO
		one.look_at(one.global_position + along, Vector3.UP)
	await _idle(20)

	print("  wall at %.0fm, target at %.0fm"
		% [24.0 - 6.0, _car.global_position.distance_to(finish)])
	# Where the kerb actually is, measured rather than assumed. `mount_shift` has to clear
	# both the carriageway *and* `off_road_margin`, and land short of the buildings.
	print("  cross-section from the car, right-hand side:")
	for metres: float in [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]:
		var spot := _car.global_position + across * metres
		var t := CityGrid.tile_at(spot)
		print("       %+5.1fm  standable=%-5s walkable=%-5s off_carriageway=%s"
			% [metres, CityGrid.standable(t.x, t.y), CityGrid.walkable(t.x, t.y),
				_car._is_off_road(spot)])

	var street_start := start
	# A short hop just past the wall, when asked for: under `CityGrid.LANE_ROUTE_MIN` the
	# order drives straight at the point instead of planning a lane route, so it cannot
	# write the street off and go round the block -- which is the other answer the game
	# already has to a shut street, and it beats the mount to it on a long journey.
	var goal := finish
	if OS.get_environment("PROBE_SHORT") != "":
		goal = start + along * 40.0
	_car.issue(MoveOrder.new(goal))
	var elapsed := 0.0
	var crawling := 0
	var off_mesh := 0
	var mounting := 0
	# What the car is *doing* on the frames it is off the carriageway. A count of those
	# frames says it is stuck up there; it does not say why, and the difference between
	# "cannot steer down" and "is not trying to" wants different code.
	var up := {}
	var up_speed := 0.0
	var up_gap := 0.0
	for i in 20:
		await physics_frame
		elapsed += 1.0 / 60.0
	while elapsed < _patience and _car.is_navigating():
		await physics_frame
		elapsed += 1.0 / 60.0
		if _car.is_mounting():
			mounting += 1
		if absf(_car.forward_speed) < 0.3:
			crawling += 1
		# Time actually spent up on the pavement, which is the thing a player would see and
		# the thing that goes wrong if this is tuned loosely: a car that lives up there is
		# far worse than one that queues.
		if _car.global_position.y > 0.08:
			off_mesh += 1
			var doing := "steering for the road"
			if _car.is_mounting():
				doing = "still mounting"
			elif _car.is_returning():
				doing = "coming back down"
			elif _car.is_escaping():
				doing = "escaping (reversing out)"
			elif _car.is_turning_round():
				doing = "turning round"
			elif not _car.is_navigating():
				doing = "not navigating at all"
			up[doing] = int(up.get(doing, 0)) + 1
			up_speed += _car.forward_speed
			up_gap += _car.global_position.distance_to(goal)

	var got_past := _car.global_position.distance_to(start) > 30.0
	print("\n  arrived            %s after %.1fs" % [not _car.is_navigating(), elapsed])
	print("  got past the wall  %s" % got_past)
	print("  frames under 0.3 m/s %d" % crawling)
	print("  frames mounting    %d" % mounting)
	print("  frames up on the kerb %d" % off_mesh)
	for doing: String in up:
		print("      %-26s %d" % [doing, up[doing]])
	if off_mesh > 0:
		print("      mean speed up there %.2f m/s, mean distance to goal %.1fm"
			% [up_speed / off_mesh, up_gap / off_mesh])
	print("  climbs fired       %d" % _climbs)
	quit()


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
