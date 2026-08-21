extends "res://Game/Tests/Autopilot.gd"

## Selection and orders -- 7 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## Vehicles are solid to one another, proved by staging rather than by watching the
## district and hoping: "no two cars happened to overlap in this window" is not the
## same claim as "no two cars can". With the steering avoidance switched off, a car
## driven straight at a parked one has to stop against it.
func _test_vehicles_cannot_drive_through_each_other() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	taxi.set_physics_process(false)
	# **In the lane the car will actually drive**, not on the centre line. Since
	# MoveOrder routes vehicles junction to junction in their own lane, a car heading
	# south down this street sits LANE_OFFSET to its right -- so a taxi parked on the
	# centre gets passed at 2.4m rather than hit, and this check quietly stopped
	# staging a collision at all. The car was not wrong; the staging was.
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	taxi.global_position = Vector3(20.0, 0.2, -20.0) + lane

	await _place_unit(_car, Vector3(20.0, 0.15, 4.0) + lane)
	# The point is the collision, not the manoeuvre -- the swerve has its own check.
	_car.avoids_vehicles = false
	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -45.0)))

	var closest := INF
	var through := false
	for i in 900:
		await physics_frame
		closest = minf(closest, _flat_distance(_car.global_position,
			taxi.global_position))
		if _car.global_position.z < taxi.global_position.z - 1.5:
			through = true
			break
		if not _car.has_orders():
			break
	_check(not through, "a car driven at a parked one cannot pass through it")
	_check(closest > 3.0,
		"it is stopped by the other car's body (closest %.1fm)" % closest)

	_car.avoids_vehicles = true
	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


## A vehicle thrown off the world comes back, and can carry on.
##
## Two CharacterBody3Ds have no solver between them: on a deep overlap `move_and_slide`
## depenetrates along the shortest exit axis, and for a box well inside another box that
## axis can be **downward, through the road**. Measured by driving one at three parked
## cars -- the patrol car reached **y = -58,356**, which is free-fall for the sixty
## seconds it was watched, and it never came back. Neither the stuck escape nor the
## navigation agent noticed: the escape only armed on a *stationary* car, and a falling
## one is moving.
##
## This is the net rather than a cure for the depenetration, which belongs to the
## engine. What matters is that a unit the player paid for cannot be lost to it.
func _test_a_vehicle_thrown_off_the_map_comes_back() -> void:
	await _place(Vector3(-20.0, 0.15, 0.0), 0.0)
	# Settled on the road for a moment, which is what the guard remembers.
	await _idle(40)
	var good := _car.global_position
	_check(good.y > Vehicle.FLOOR_FLOOR, "the car starts on the road (y %.2f)" % good.y)

	# Straight under the world, exactly where depenetration puts it.
	_car.global_position = Vector3(good.x, -50.0, good.z)
	_car.velocity = Vector3(0.0, -30.0, 0.0)
	await _idle(10)

	_check(_car.global_position.y > Vehicle.FLOOR_FLOOR,
		"and is put back on it rather than falling for ever (y %.2f)"
		% _car.global_position.y)
	# **Full 3D distance, not flat.** Measuring only x/z was vacuous against the fault
	# this test exists for: a car in free-fall directly beneath its start scores a
	# perfect 0.0m, and it read 0.0 whether the guard ran or was disabled entirely. The
	# vertical term is the whole difference between "back on the road" and "still on its
	# way to the centre of the earth".
	_check(_car.global_position.distance_to(good) < 6.0,
		"on the road under where it fell, not teleported across the district (%.1fm)"
		% _car.global_position.distance_to(good))
	# Settled, rather than "velocity is zero on the very next frame". The guard puts the
	# car down a few centimetres clear of the road so it is not inside the collider, so
	# gravity is still doing its job for the moment it takes to land -- which is the
	# difference between a car dropping onto a road and a car falling through one.
	await _idle(40)
	_check(_car.is_on_floor() and absf(_car.velocity.y) < 1.0,
		"and settles on it (on floor %s, %.1f m/s vertical)"
		% [_car.is_on_floor(), _car.velocity.y])

	# And it is a working vehicle afterwards, not a recovered wreck.
	#
	# "Is it moving" is not enough, and asserting only that was vacuous: a car falling
	# through the void still spins its wheels up to forward speed, and this passed with
	# the car sixty-seven metres under the district. What makes it a working vehicle is
	# being **on the road** and **closing on its target** -- neither of which a falling
	# one manages.
	var away := Vector3(-20.0, 0.0, 30.0)
	var opening := _flat_distance(_car.global_position, away)
	_car.issue(MoveOrder.new(away))
	var moved := false
	for i in 300:
		await physics_frame
		if _car.is_on_floor() and absf(_car.forward_speed) > 3.0 \
				and _flat_distance(_car.global_position, away) < opening - 4.0:
			moved = true
			break
	_check(moved, "and drives away from it under orders, on the road [%s]" % _car_state())
	_car.clear_orders()
	await _idle(4)


## Solid vehicles need somewhere to go. The player's autopilot steers around what is
## in its way instead of driving into it -- the other half of giving traffic mass,
## and the reason the two were kept intangible for so long.
func _test_a_vehicle_drives_around_what_is_in_its_way() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	# Parked, not driving: this measures the patrol car's manoeuvre, not a chase.
	taxi.set_physics_process(false)
	var lane := Vector3(20.0, 0.2, -20.0)
	taxi.global_position = lane

	await _place_unit(_car, Vector3(20.0, 0.15, 8.0))
	await _idle(6)
	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -48.0)))

	var closest := INF
	var swerved := false
	var arrived := false
	for i in 1800:
		await physics_frame
		closest = minf(closest, _flat_distance(_car.global_position,
			taxi.global_position))
		if _car.is_avoiding:
			swerved = true
		if not _car.has_orders():
			arrived = true
			break
	_check(swerved, "the patrol car went round the parked taxi rather than at it")
	_check(closest > 2.2,
		"never driving through it (closest approach %.1fm)" % closest)
	_check(arrived, "and still got where it was sent")

	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


func _test_left_click_selects() -> void:
	await _place(ROAD)
	_focus_camera_on_car()
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	_check(_controller.primary() == _car, "left-clicking the car selects it")
	_check(_ring != null and _ring.visible, "selection ring is shown")

	# **The bracket, not the torus the scene ships.** The shape is swapped in at load by
	# `Unit._tint_ring`, so the placeholder in each of the six scenes that carry a ring
	# never has to be edited again -- and a swap that silently did not happen leaves a
	# perfectly visible ring of the wrong design, which is the sort of thing only a
	# screenshot catches. Asserted on the mesh's own geometry: an ArrayMesh of flat
	# triangles, sized to this unit rather than to whatever the scene author chose.
	var ring_mesh := _ring as MeshInstance3D
	_check(ring_mesh != null and ring_mesh.mesh is ArrayMesh,
		"and it is the bracket built at load, not the scene's torus (%s)"
		% (ring_mesh.mesh.get_class() if ring_mesh and ring_mesh.mesh else "none"))
	if ring_mesh and ring_mesh.mesh:
		var span: Vector3 = ring_mesh.mesh.get_aabb().size
		# A patrol car is about 4.5m long, so its bracket should be metres across --
		# not the fixed 1m a shared placeholder would give every unit alike.
		_check(span.x > 1.5 and span.z > 1.5 and span.y < 0.01,
			"sized to the car and flat on the ground (%.1f x %.1f x %.2f)"
			% [span.x, span.z, span.y])
		# The tint is what tells a police unit from a medical one at a glance, and it is
		# applied to a *duplicated* material -- shared, it would repaint every officer.
		var ink := (ring_mesh.material_override as StandardMaterial3D).albedo_color
		var police := Palette.service(Unit.Service.POLICE)[0]
		_check(absf(ink.r - police.r) < 0.02 and absf(ink.g - police.g) < 0.02,
			"and still wearing its service colour")
		_check(_faces_down(ring_mesh.mesh as ArrayMesh) == 0,
			"and wound face-up rather than into the ground (%d of %d triangles down)"
			% [_faces_down(ring_mesh.mesh as ArrayMesh),
				_triangles(ring_mesh.mesh as ArrayMesh)])


func _test_clicking_ground_deselects() -> void:
	# A point on the deck well clear of the car.
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3(9.0, 0.0, 0.0)))
	_check(_controller.selection.is_empty(), "clicking the ground clears the selection")
	_check(_ring != null and not _ring.visible, "selection ring is hidden")


func _test_right_click_issues_order() -> void:
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	if _controller.primary() != _car:
		_check(false, "car is selected before ordering")
		return

	# Along the avenue, so the clicked point is somewhere the car can actually go.
	var aim := _car.global_position + Vector3(0.0, 0.0, -11.0)
	aim.y = 0.0
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(aim))
	_check(_car.has_orders(), "right click issued a move order")
	_check(_flat_distance(_car.move_target, aim) < 2.5,
		"order landed %.2fm from where it was clicked" % _flat_distance(_car.move_target, aim))
	_check(_marker != null and _marker.visible, "destination marker is shown")

	var arrived := await _await_arrival(900)
	_check(arrived, "carried out the clicked order")
	await _wait(5)
	_check(_marker != null and not _marker.visible, "marker cleared once the car arrived")


func _test_order_ignored_with_no_selection() -> void:
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3(9.0, 0.0, 0.0)))
	if not _controller.selection.is_empty():
		_check(false, "selection was cleared before this check")
		return
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(_car.global_position + Vector3(-9.0, 0.0, 0.0)))
	_check(not _car.has_orders(), "right click does nothing with no selection")


# --- Order queue -------------------------------------------------------------
