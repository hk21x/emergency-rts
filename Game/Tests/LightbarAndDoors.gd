extends "res://Game/Tests/Calls.gd"

## Lightbar and doors -- 11 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## A car told to go somewhere off the road gets up onto it.
##
## Two things have to hold at once and only one of them is obvious. The car has to
## *set off* -- an order aimed off the navigation mesh used to complete on its first
## frame, because the agent clamps the destination and reports itself finished, so the
## player saw a car that ignored the click entirely. And it has to *get up*, which a box
## collider against a 7cm vertical face does not do on its own.
##
## The kerb is found by sweeping off the centre of a road band rather than named as a
## coordinate: the band tables are deliberately irregular, and a hand-picked number
## lands inside a building often enough to turn this into a test of the waypoint.
func _test_a_car_sent_off_the_road_climbs_the_kerb() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)

	var across := Vector3.ZERO
	var edge := Vector3.ZERO
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		for step in 40:
			var here: Vector3 = _car.global_position + direction * (0.25 * step)
			if not CityGrid.is_road(here):
				edge = here
				across = direction
				break
		if across != Vector3.ZERO:
			break
	if across == Vector3.ZERO:
		_check(false, "the district still has a kerb to drive at")
		return

	# Put down square to the kerb it just found, rather than left wherever `ROAD` is.
	# Sent from an arbitrary spot the car reached the pavement having climbed *nothing*
	# -- it had simply driven round to a junction box, which is also not a road tile.
	# "Off the carriageway" is too weak a claim on its own; the height is the evidence.
	await _place(edge - across * 8.0)
	await _idle(20)
	var target := edge + across * 4.0
	_check(CityGrid.is_road(_car.global_position) and not CityGrid.is_road(target),
		"the car starts on the road and is sent off it")

	# Connected **before** the order. Connecting it after a settling wait was the first
	# version and it could only ever undercount.
	# **A one-element array, not an int.** GDScript lambdas capture by *value*, so a
	# captured `var climbs := 0` is incremented on a copy and the outer one stays zero
	# for ever. This read "0 climbs, rose 0.22m" -- and 0.22 is exactly `climb_height`,
	# so the climb had plainly happened and only the tally had not. An array is a
	# reference, so mutating through it is visible outside the lambda.
	var climbs := [0]
	_car.climbed.connect(func(_v: Vehicle) -> void: climbs[0] += 1)
	var floor_y := _car.global_position.y
	_car.issue(MoveOrder.new(target))
	await _idle(20)
	_check(_car.has_orders() and _car.is_navigating(),
		"the order survives being aimed off the navigation mesh")

	var highest := floor_y
	var crawling := 0
	for i in 60 * 25:
		await _idle(1)
		highest = maxf(highest, _car.global_position.y)
		# Frames spent barely moving *before* it is up. Reported from play: the car drove
		# to the kerb and sat there grinding against it until it had slowed enough to be
		# allowed over, which is what happens when the lift waits on the stuck timer.
		if absf(_car.forward_speed) < 0.3:
			crawling += 1
		if not CityGrid.is_road(_car.global_position):
			break
	_check(not CityGrid.is_road(_car.global_position),
		"and the car gets up onto the pavement")
	_check(int(climbs[0]) > 0 and highest > floor_y + 0.05,
		"by climbing the kerb, not driving round it (%d climbs, rose %.2fm)"
			% [climbs[0], highest - floor_y])
	# Half a second of it is the stuck timer; anything approaching that means the lift is
	# waiting for the car to stop rather than carrying it over at speed.
	_check(crawling < 15,
		"and without stopping dead at the face first (%d frames under 0.3 m/s)" % crawling)
	_car.clear_orders()
	await _idle(5)


## An appliance on a shout takes the pavement past a shut street -- **and comes back down.**
##
## The check above is the *ordered* climb: the player right-clicks a verge and the car goes
## there. This is the earned one, and the two halves matter equally. Going up was built
## first and on its own it is a trap: measured, an appliance that mounted successfully then
## spent 555 frames off the carriageway, 161 of them *turning round*, because from up on the
## pavement the navigation agent's nearest reachable point is the carriageway it just left,
## on the **near** side of the obstruction. It drove back, met the wall, and mounted again.
## A 33.3s journey did not finish in sixty seconds. So the assertion that matters most here
## is the last one: the appliance ends up **on the road**.
##
## **What each assertion is worth, from the sabotage pass -- read this before adding more.**
## Disabling the mount reddens all four, with no collateral. Disabling *only* the recovery
## reddens exactly one: "steers itself back down". "Finishes the journey" stays green,
## because the navigation agent also gets the car off the pavement eventually in this
## fixture -- it is over-determined with respect to the recovery, and only goes red when
## every route back down is removed. It is kept because it is the end-to-end statement and
## it does go red when the mount is disabled, but **it is not evidence about the recovery**.
## A third assertion, "ending on the carriageway", was written here and deleted: it
## snapshotted `CityGrid.is_road()` on whichever frame the sample loop happened to exit and
## read true under every sabotage, including one where the car was demonstrably stranded 23m
## short. Bounding the off-road frame count instead does not discriminate either -- a
## healthy run spends *more* frames up there (296) than a sabotaged one (201), because the
## steered recovery is a deliberate excursion and the broken version simply mills about. The
## count is printed for the reader and asserted on by nothing.
##
## **Three abreast, an appliance, and a short hop -- all three load-bearing.**
## [method Vehicle._passing_line] finds a way round one vehicle every time and should; two
## made the result flap between 0 and 21 mounting frames on a decimetre of spacing. A patrol
## car is small enough to squeeze through the same wall (33.3s, mounting nothing), so the
## mover has to be an appliance and the fixture has to buy one. And the destination is kept
## under [constant CityGrid.LANE_ROUTE_MIN], because past that the order plans a lane route,
## writes the shut street off after four seconds and drives round the block instead -- which
## is a perfectly good answer, and not the one under test.
func _test_a_shut_street_is_passed_over_the_pavement() -> void:
	_controller.clear_selection()
	# A straight street between two junctions on the same row: one heading throughout, so
	# nothing in the result is a cornering artefact, and well clear of a junction mouth,
	# which the feature requires and the check after this one is about.
	var start := CityGrid.junction(Vector2i(1, 1))
	var along := (CityGrid.junction(Vector2i(3, 1)) - start).normalized()
	var across := along.cross(Vector3.UP)
	var yaw := atan2(-along.x, -along.z)
	var goal := start + along * 40.0

	_station.purchase(&"engine")
	var engine := _dispatch_to(&"engine", start + along * 6.0) as Vehicle
	var wall: Array[Vehicle] = [_cars[1]]
	for i in 2:
		_station.purchase(&"patrol")
		wall.append(_dispatch_to(&"patrol", start + along * 24.0) as Vehicle)
	if engine == null or wall.has(null):
		_check(false, "the fixture can put an appliance behind a shut street")
		return
	for i in wall.size():
		await _place_unit(wall[i], start + along * 24.0 + across * (float(i) - 1.0) * 2.6,
			yaw)
	# The two left-over fixture units parked well clear, so nothing an earlier check left
	# lying in this street gets to decide the answer.
	await _place_unit(_ambulance, start - along * 14.0, yaw)
	await _place_unit(_car, start - along * 20.0, yaw)
	await _place_unit(engine, start + along * 6.0, yaw)
	await _idle(20)

	# An array, not an int: GDScript lambdas capture by value and a captured int stays at
	# zero for ever. Written up at length over the ordered-climb check above.
	var climbs := [0]
	engine.climbed.connect(func(_v: Vehicle) -> void: climbs[0] += 1)
	var mounted := false
	var came_back := false
	var off_road := 0
	# The licence's own terms, reported whatever happens. A bare "it did not mount" sent this
	# check round the houses twice; the peak against the bar says at a glance whether the
	# manoeuvre was refused or simply never came due.
	var peak := 0.0
	var crawling := 0
	var blocked_frames := 0
	engine.issue(MoveOrder.new(goal))
	for i in 60 * 45:
		await _idle(1)
		if engine.is_mounting():
			mounted = true
		if engine.is_returning():
			came_back = true
		if not CityGrid.is_road(engine.global_position):
			off_road += 1
		peak = maxf(peak, engine._blocked_time)
		if engine.forward_speed < engine.mount_crawl:
			crawling += 1
			if engine.road_is_blocked(engine.move_target):
				blocked_frames += 1
		if not engine.is_navigating():
			break

	_check(mounted,
		"an appliance on a shout takes the pavement when the street is shut (blocked peaked at %.2f of %.2f, %d of %d crawling frames with the street shut)"
			% [peak, engine.mount_after, blocked_frames, crawling])
	_check(int(climbs[0]) > 0,
		"and gets up there over the kerb rather than round it (%d climbs)" % climbs[0])
	_check(came_back,
		"and steers itself back down off the pavement afterwards (%d frames off the road)"
			% off_road)
	_check(engine.global_position.distance_to(goal) < 8.0,
		"and finishes the journey (%.0fm short of a target %.0fm past the wall)"
			% [engine.global_position.distance_to(goal), 16.0])
	_station.write_off(engine)
	for i in range(1, wall.size()):
		_station.write_off(wall[i])
	await _park_the_shift()


## And an appliance merely queueing at a junction does **not**.
##
## The other half of the same behaviour, and the more important half. A kerb runs along a
## street; a junction is a crossing, and the ground at its mouth is off the vehicle
## navigation mesh without having any step on it -- so a car that mounts there drives onto
## flat tarmac, off its route, and has to find its way back. Measured with the junction
## exclusion removed, a 76.7s journey became one the car had not finished in 150 seconds.
## Nothing in the check above would have caught that.
##
## Walled in by the **same three abreast**, so the only difference between the two scenarios
## is where the appliance is standing. A weaker wall here would make this a negative control
## that proves nothing: of course a car that was never provoked did not mount.
func _test_a_junction_queue_does_not_earn_the_pavement() -> void:
	_controller.clear_selection()
	var box := CityGrid.junction(Vector2i(1, 1))
	var out := (CityGrid.junction(Vector2i(3, 1)) - box).normalized()
	var across := out.cross(Vector3.UP)
	var yaw := atan2(-out.x, -out.z)

	_station.purchase(&"engine")
	var engine := _dispatch_to(&"engine", box + out * 1.0) as Vehicle
	var wall: Array[Vehicle] = [_cars[1]]
	for i in 2:
		_station.purchase(&"patrol")
		wall.append(_dispatch_to(&"patrol", box + out * 7.0) as Vehicle)
	if engine == null or wall.has(null):
		_check(false, "the fixture can put an appliance in a junction")
		return
	for i in wall.size():
		await _place_unit(wall[i], box + out * 7.0 + across * (float(i) - 1.0) * 2.6, yaw)
	await _place_unit(_ambulance, box - out * 14.0, yaw)
	await _place_unit(_car, box - out * 20.0, yaw)
	await _place_unit(engine, box + out * 1.0, yaw)
	await _idle(20)

	var mounted := false
	engine.issue(MoveOrder.new(box + out * 40.0))
	for i in 60 * 12:
		await _idle(1)
		if engine.is_mounting():
			mounted = true
	_check(not mounted,
		"an appliance queueing in a junction does not take the pavement")
	_station.write_off(engine)
	for i in range(1, wall.size()):
		_station.write_off(wall[i])
	await _park_the_shift()


## A car sent to a point dead behind it, on a street, turns round and arrives.
##
## The navigation block already proves "reached a target directly behind it" -- on the
## station forecourt, which is open ground where a single full-lock loop fits. A street
## is the case that spent a year broken: the carriageway is narrower than the turning
## circle, so the manoeuvre must be a multi-point turn, and the machinery for that used
## to be a latch that released into arcs that did not fit the road plus a blind timed
## escape -- eight escapes in thirty seconds on this stage, never arriving. The bounded
## turn (Vehicle._begin_turn / _plan_turn_leg) plans each leg against the road instead.
##
## **What this can and cannot guard, established by two rounds of sabotage.** It cannot
## see the *quality* of the manoeuvre: the year-old faulty release was restored under it
## and the whole suite stayed green -- on a lightly-trafficked street that fault arrives
## *faster*, by sweeping, and excursion measured identical (4.4m) under both. Quality
## lives in the probes: `probe_orbit.gd` (zero escapes on every staged case) and
## `probe_journeys.gd` (fleet escapes 75 -> 31). What it does guard, with the redundancy
## mapped by measurement rather than assumed:
##
## - "starts a turn-round" reds only when **both** arming paths die -- the latch and the
##   escape-conversion each arm this stage alone (killing just the latch left it green
##   while two *other* driving checks went red). It guards the class, not one path.
## - "by the designed release" is the line with teeth: the turn has one designed exit
##   (a rolling forward leg inside the exit angle, which leaves Vehicle._turn_rest at
##   zero) and two fallbacks (abandon, plan-failure), both of which arm the rest.
##   Killing the designed release alone still arrives -- the plan-failure exit frees the
##   car within a second of when the release would -- but it arrives *resting*, which is
##   what this asserts against. Killing all three exits strands the car outright
##   (18.1m off, 30s) and takes nine other driving checks with it.
func _test_a_narrow_street_u_turn_completes() -> void:
	_controller.clear_selection()
	var j := CityGrid.junction(Vector2i(1, 1))
	var east := Vector3(1, 0, 0)
	await _place(j + east * 10.0, atan2(-east.x, -east.z))
	await _idle(10)
	var aim := j - east * 10.0

	var turned := false
	var elapsed := 0.0
	_car.issue(MoveOrder.new(aim))
	for i in 60 * 30:
		await _idle(1)
		elapsed += 1.0 / 60.0
		if _car.is_turning_round():
			turned = true
		if not _car.is_navigating():
			break

	var gap := Vector2(_car.global_position.x - aim.x,
		_car.global_position.z - aim.z).length()
	_check(turned, "a dead-behind order on a street starts a turn-round")
	_check(gap < 4.0 and elapsed < 29.0 and is_zero_approx(_car._turn_rest),
		"and it arrives by the designed release, not a fallback (%.1fm off, %.1fs, rest %.1f)"
			% [gap, elapsed, _car._turn_rest])
	_car.clear_orders()
	_car.stop_navigating()
	await _park_the_shift()


## A car on a lane route slows for the junction turn before it gets there.
##
## The junction overshoot two F3s from play pinned on the fast cars, fixed at the root:
## the corner planner used to read corners off the agent path, and with
## junction-to-junction waypoints that path **ends at the junction** -- the turn onto the
## next street does not exist in it until the 7m waypoint switch, far too late to brake
## from 26 m/s. Every apparent corner it did read was the car's own off-line position
## swinging the measured vector. The route now annotates its aim with the turn's exact
## angle ([member Vehicle.turn_at_aim], set in MoveOrder._aim from the lattice), and the
## turn's cap holds while the car is in the box ([member Vehicle.turn_here]).
##
## The bar is generous -- holdable for this car is 7.9 m/s and unfixed entries measured
## 14-20 -- so ambient traffic slowing the car further can only make it pass. Arrival is
## asserted so a car that never reaches the corner cannot pass by absence.
func _test_a_routed_car_brakes_for_the_junction_turn() -> void:
	_controller.clear_selection()
	var a := CityGrid.junction(Vector2i(1, 1))
	var b := CityGrid.junction(Vector2i(3, 1))
	var east := (b - a).normalized()
	# South off junction b, far enough that the route must turn there.
	var goal := b + Vector3(0, 0, 1) * 35.0
	await _place(a + east * 6.0, atan2(-east.x, -east.z))
	await _idle(10)

	# **Measured on both worlds before the bar was set** (tmp probe, since deleted, same
	# stage, empty district): fixed, the braked car corner-cuts and never appears within
	# 5m of the box centre at all; sabotaged (annotation zeroed), it barrels through the
	# middle at 13.3 m/s while overshooting the turn line. An 8m ring was tried first and
	# was arithmetic-blind: the fix's own braking curve legitimately crosses it at 14-16,
	# so the check failed on the healthy tree. The 5m/10.0 pair separates cleanly, and a
	# car forced through the middle *slowly* by traffic still passes, as it should.
	var centre_peak := 0.0
	var reached := false
	_car.issue(MoveOrder.new(goal))
	for i in 60 * 40:
		await _idle(1)
		var gap := Vector2(_car.global_position.x - b.x,
			_car.global_position.z - b.z).length()
		if gap < 8.0:
			reached = true
		if gap < 5.0:
			centre_peak = maxf(centre_peak, absf(_car.forward_speed))
		if not _car.is_navigating():
			break
	_check(reached, "the routed car reaches the turning junction")
	_check(reached and centre_peak < 10.0,
		"and is never at speed through the middle of the box (fastest within 5m: %.1f m/s; the unbraked world reads 13+)"
			% centre_peak)
	_car.clear_orders()
	_car.stop_navigating()
	await _park_the_shift()


func _test_siren_runs_while_responding() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)
	var siren := _car.get_node("Lean/Chassis/Siren") as Node3D
	# The bar and the noise run off one condition, so they are checked as a pair at
	# each of the three moments -- parked, under way, arrived. Checking only the bar
	# is how the two drifted apart in the first place: the light was automatic from
	# Phase 17 and the audio stayed manual for a year without anything noticing.
	var speaker := _car.get_node_or_null("SirenAudio") as AudioStreamPlayer3D
	_check(not siren.visible, "the lightbar is dark while parked")
	_check(speaker != null and not speaker.playing, "and the siren is silent with it")

	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -20.0)))
	await _idle(15)
	_check(siren.visible, "and lit once the car is on its way")
	_check(speaker != null and speaker.playing,
		"and the siren sounds the moment it is sent, without anyone throwing a switch")

	# Both beads are sampled over a couple of cycles. A lamp that is simply switched
	# on is not a siren, and would sail through a bare visibility check.
	var left := siren.get_node("Left") as Node3D
	var right := siren.get_node("Right") as Node3D
	var left_lit := 0
	var right_lit := 0
	var together := 0
	for i in 150:
		await _idle(1)
		if left.visible:
			left_lit += 1
		if right.visible:
			right_lit += 1
		if left.visible and right.visible:
			together += 1
	_check(left_lit > 10 and left_lit < 140, "the red bead flashes (lit %d of 150)" % left_lit)
	_check(right_lit > 10 and right_lit < 140, "the blue bead flashes (lit %d of 150)" % right_lit)
	_check(together == 0, "and the two alternate (%d frames with both lit)" % together)

	await _await_arrival(900)
	await _idle(10)
	_check(not siren.visible, "the lightbar goes out once it arrives")
	_check(speaker != null and not speaker.playing, "and the siren stops with it")


func _test_lights_switch_on_by_hand() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)
	var bar := _car.get_node("Lean/Chassis/Siren") as Node3D
	_check(not bar.visible, "the lightbar is dark parked with no orders")

	var lights := _find_ability(_car, &"lights")
	if lights == null:
		_check(false, "the car offers a Lights switch")
		return
	lights.execute(_car)
	await _idle(6)
	_check(_car.lights_on and bar.visible,
		"the switch lights the bar with the car standing still")

	# Sampled, not just visible: a lamp burning steady is not a lightbar. Same rule as
	# the responding test -- the beads must never both be lit at once.
	var left := bar.get_node("Left") as Node3D
	var right := bar.get_node("Right") as Node3D
	var lit := 0
	var together := 0
	for i in 90:
		await _idle(1)
		if left.visible or right.visible:
			lit += 1
		if left.visible and right.visible:
			together += 1
	_check(lit > 0 and together == 0,
		"and it flashes rather than burns (%d lit, %d together)" % [lit, together])

	lights.execute(_car)
	await _idle(6)
	_check(not _car.lights_on and not bar.visible, "a second press puts it out")


func _test_siren_is_the_audio_and_separate() -> void:
	var siren := _find_ability(_car, &"siren")
	if siren == null:
		_check(false, "the car offers a Siren switch")
		return
	var speaker := _car.get_node_or_null("SirenAudio") as AudioStreamPlayer3D
	_check(speaker != null and speaker.stream != null,
		"the car carries a siren speaker with a sound loaded")
	# The recording runs under three seconds, so a siren that does not loop falls
	# silent partway through the first street -- and every check above this one still
	# passes, because the speaker did start. Looping is a different property in every
	# container, which is exactly how a format swap loses it.
	_check(speaker != null and Vehicle.loops(speaker.stream),
		"and the sound loops rather than running out mid-call")

	var bar := _car.get_node("Lean/Chassis/Siren") as Node3D
	siren.execute(_car)
	await _idle(6)
	_check(_car.siren_on, "the switch turns the siren on")
	_check(speaker != null and speaker.playing, "and the speaker is playing")
	_check(not _car.lights_on and not bar.visible,
		"without touching the lights -- the two switches are separate")

	siren.execute(_car)
	await _idle(6)
	_check(not _car.siren_on and (speaker == null or not speaker.playing),
		"a second press silences it")


func _test_lights_and_siren_are_crew_switches() -> void:
	var officer_ids: Array[StringName] = []
	for ability in _officer.abilities():
		officer_ids.append(ability.id())
	_check(not officer_ids.has(&"lights") and not officer_ids.has(&"siren"),
		"someone on foot has no lightbar or siren to switch")

	_controller.select([_car])
	await _idle(3)
	var verbs := _tile_ids()
	_check(verbs.has(&"lights") and verbs.has(&"siren"),
		"a vehicle's grid offers both switches (%s)" % str(verbs))

	await _press_key(KEY_J)
	await _idle(3)
	_check(_car.lights_on, "J throws the lights on")
	_check(_active_tiles().has(&"lights"),
		"and the tile shows it running (%s)" % str(_active_tiles()))

	await _press_key(KEY_K)
	await _idle(3)
	_check(_car.siren_on, "K the siren")

	await _press_key(KEY_J)
	await _press_key(KEY_K)
	await _idle(3)
	_check(not _car.lights_on and not _car.siren_on and _active_tiles().is_empty(),
		"pressing again switches both off and the tiles go quiet (%s)"
		% str(_active_tiles()))
	_controller.clear_selection()


func _test_ambulance_doors_open_for_boarding() -> void:
	var door := _ambulance.get_node_or_null("Lean/Chassis/DoorL") as Node3D
	if door == null:
		_check(false, "the ambulance has separate rear door meshes")
		return
	var full := deg_to_rad(_ambulance.door_open_degrees)
	_ambulance.crew.clear()
	await _idle(180)
	_check(absf(door.rotation.y) < 0.02, "the ambulance's rear doors start shut")

	_ambulance.take_aboard(_officer)
	await _idle(8)
	var early := absf(door.rotation.y)
	_check(early > 0.005 and early < full * 0.5,
		"they swing rather than snap open (%.0f of %.0f degrees after 0.13s)"
		% [rad_to_deg(early), _ambulance.door_open_degrees])

	_check(await _await_door(door, full * 0.9, true, 3000),
		"and reach full travel (%.0f degrees)" % rad_to_deg(absf(door.rotation.y)))
	_check(await _await_door(door, 0.05, false, 6000),
		"then shut again afterwards (%.0f degrees)" % rad_to_deg(absf(door.rotation.y)))
	_ambulance.crew.clear()


func _test_vehicles_without_doors_cope() -> void:
	# The patrol car's doors are part of its hull, so there is nothing to swing. The
	# call still has to be safe, because the boarding code does not know the difference.
	_check(_car.get_node_or_null("Lean/Chassis/DoorL") == null,
		"a patrol car ships no separate door meshes")
	_car.open_doors()
	await _idle(5)
	_check(true, "and opening doors it has not got is a no-op")


# --- Incidents ---------------------------------------------------------------
