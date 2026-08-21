extends "res://Game/Tests/Harness.gd"

## Ambient population -- 25 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_civilians_are_not_commandable() -> void:
	var civilian := _first_civilian()
	if civilian == null:
		_check(false, "the map has a crowd on it")
		return
	_check(not civilian.is_selectable(), "a civilian is not selectable")
	_check(civilian.abilities().is_empty(),
		"and offers no abilities (%d)" % civilian.abilities().size())

	_controller.clear_selection()
	_camera.stop_following()

	# A civilian must not stop the picking ray, or one wandering between the camera and
	# an officer makes that officer unclickable. Checked against a full-mask query
	# first, so "the picking ray missed them" cannot pass by the camera simply being
	# aimed somewhere else.
	#
	# Which civilian is found by looking rather than assumed: the crowd is scattered
	# over the pavements, and whoever happens to be first may be stood against a wall
	# with a lamp post between them and the camera. Any one of them proves the point.
	var screen := Vector2.ZERO
	var aimed: Civilian = null
	for candidate in _civilians():
		_camera.focus = Vector3(
			candidate.global_position.x, 0.0, candidate.global_position.z)
		_camera._target_distance = 16.0
		await _idle(12)
		var at := _screen_of(candidate.global_position + Vector3.UP * 1.0)
		var from := _camera.project_ray_origin(at)
		var query := PhysicsRayQueryParameters3D.create(
			from, from + _camera.project_ray_normal(at) * 400.0)
		query.collide_with_areas = false
		if _scene.get_world_3d().direct_space_state.intersect_ray(query)\
				.get("collider") == candidate:
			aimed = candidate
			screen = at
			break

	_check(aimed != null, "found a civilian the camera has a clear line to")
	if aimed == null:
		return
	civilian = aimed
	_check(_controller._raycast(screen).get("collider") != civilian,
		"but the picking ray passes straight through them")

	await _click(MOUSE_BUTTON_LEFT, screen)
	_check(_controller.selection.is_empty(),
		"clicking a civilian selects nothing (%d selected)" % _controller.selection.size())


func _test_civilians_stroll() -> void:
	var crowd := _ambient("Crowd")
	if crowd.is_empty():
		_check(false, "the map has a crowd on it")
		return
	var before: Array[Vector3] = []
	for node in crowd:
		before.append((node as Node3D).global_position)

	await _wait(420)

	var moved := 0
	for i in crowd.size():
		if (crowd[i] as Node3D).global_position.distance_to(before[i]) > 1.0:
			moved += 1
	# Not all of them: strolling includes standing still for a few seconds, and some
	# of the crowd will be mid-pause for the whole sample.
	_check(moved >= crowd.size() / 2,
		"%d of %d civilians walked somewhere" % [moved, crowd.size()])


## Pedestrians belong on the pavement, and the only way across a road is the zebra.
## The graph is asserted directly, then the live crowd is sampled against it.
func _test_the_crowd_keeps_to_the_pavements() -> void:
	# A kerb tile beside a junction offers both painted crossings...
	var corner := Vector2i(23, 23)
	var moves := CityGrid.walk_moves(corner.x, corner.y)
	_check(moves.has(Vector2i(20, 23)) and moves.has(Vector2i(23, 20)),
		"a kerb tile by the junction offers both zebra crossings (%s)" % [moves])
	# ...and a kerb tile mid-block offers the ring and nothing over the road.
	var mid := CityGrid.walk_moves(23, 25)
	var jaywalk := false
	for move in mid:
		if CityGrid.block_of(move.x, move.y) != CityGrid.block_of(23, 25):
			jaywalk = true
	_check(not mid.is_empty() and not jaywalk,
		"a mid-block kerb offers the ring only -- jaywalking is not on the menu (%s)"
		% [mid])

	var crowd := _civilians()
	if crowd.is_empty():
		_check(false, "a crowd to watch")
		return
	var samples := 0
	var offside := 0
	for sweep in 120:
		await _wait(5)
		for civilian in crowd:
			if not is_instance_valid(civilian):
				continue
			samples += 1
			if not _pedestrian_legal(civilian.global_position):
				offside += 1
	_check(samples > 1000 and offside == 0,
		"the crowd kept to pavements and crossings (%d of %d samples offside)"
		% [offside, samples])


func _test_civilians_flee_a_fire() -> void:
	var civilian := _first_civilian()
	if civilian == null:
		_check(false, "the map has a crowd on it")
		return
	var spot := civilian.global_position
	var fire := _spawn_fire(spot + Vector3(4.0, 0.0, 0.0), 0.6)
	var start := _flat_distance(spot, fire.global_position)

	# Sampled while they are still running. Left any longer this reads false, because
	# by then they are clear of flee_radius and have gone back to strolling -- which
	# is correct behaviour and a misleading thing to assert on.
	await _wait(45)
	_check(civilian.is_fleeing, "a civilian beside a fire is running from it")

	# Fleeing follows the same pavement graph strolling does -- sampled while they
	# run, because a shopper sprinting through the carriageway has swapped one
	# incident for another.
	var offside := 0
	for i in 180:
		await physics_frame
		if is_instance_valid(civilian) \
				and not _pedestrian_legal(civilian.global_position):
			offside += 1
	_check(offside == 0,
		"they fled along the pavement, not through the road (%d frames offside)"
		% offside)
	# **Guarded, like the loop above already was.** Since fire began converting bystanders
	# to casualties, a civilian this check is holding can be freed under it -- and reading
	# a freed object raises, which does not fail the check, it *abandons the rest of it*
	# and takes the two assertions below out of the count silently. Found by a sabotage
	# that widened the harm radius; it cannot happen at the shipped radius, and the
	# inconsistency was worth closing anyway.
	if not is_instance_valid(civilian):
		_check(false, "the fleeing civilian survived to be measured")
		await _clear_incidents()
		return
	var now := _flat_distance(civilian.global_position, fire.global_position)
	_check(now > start + 4.0,
		"and put %.1fm between them, up from %.1fm" % [now, start])

	await _clear_incidents()
	await _wait(40)
	_check(is_instance_valid(civilian) and not civilian.is_fleeing,
		"and settles once the fire is out")


## Panic: they run, they scatter — and they never leave the pavement doing it.
##
## **The last assertion is the whole design.** The crowd has always fled along the
## pedestrian graph, crossing at the zebras even at a run, because a shopper who sprints
## into the carriageway has swapped one incident for another — and traffic cannot see
## pedestrians, so a panicking civilian in the road would be run over by a car that never
## braked. Panic changes *how* they move, never *where* they may go.
##
## **This check is the only witness for that, and the 7,200-sample sweep is not.** That
## sweep runs with nothing burning, so nobody panics and the panicking branch is never
## entered — sabotage confirmed it does not move at all when panic is made to leave the
## pavement, while this check reports 21 frames offside and the flee-legality check 165.
## An unweakened sweep is not the same as a covering one.
##
## The offside count is also asserted to have been *taken*: gated on `is_panicking`, it
## counts zero samples and passes by default if nobody panics, which is this project's
## "the post-condition is the default state" trap exactly.
func _test_panic_stays_on_the_pavement() -> void:
	await _clear_incidents()
	var civilian := _first_civilian()
	if civilian == null:
		_check(false, "a civilian to frighten")
		return
	var spot := civilian.global_position
	# Inside `panic_radius` (7.0) but outside the fire's own singe radius (3.2), so this
	# frightens them rather than converting them to a casualty mid-check.
	var fire := _spawn_fire(spot + Vector3(4.5, 0.0, 0.0), 0.95)
	await _wait(20)

	_check(civilian.is_fleeing and civilian.is_panicking,
		"a fire at arm's length panics them (fleeing %s, panicking %s)"
		% [civilian.is_fleeing, civilian.is_panicking])
	_check(civilian.hurry, "and they run rather than walk away from it")

	var offside := 0
	var sampled := 0
	for i in 150:
		await physics_frame
		if not is_instance_valid(civilian):
			break
		if not civilian.is_panicking:
			continue
		sampled += 1
		if not _pedestrian_legal(civilian.global_position):
			offside += 1
	_check(sampled > 20,
		"panic lasted long enough to measure (%d frames sampled)" % sampled)
	_check(offside == 0,
		"and panicking never puts them in the road (%d offside of %d)"
		% [offside, sampled])

	fire.queue_free()
	await _clear_incidents()
	await _wait(30)
	if is_instance_valid(civilian):
		_check(not civilian.is_panicking and not civilian.hurry,
			"panic passes on its own once the fire is gone")


## The street dressing draws on the pack rather than on a handful of favourites.
##
## Reported from play as the district looking bland and reusing the same assets, and the
## count agreed: the generator named **22 of the 174 props the pack ships**, so the same
## bench and the same bin appeared down every street. Buildings were never the problem --
## those were already at 51 of 75 -- it was the street furniture, which is what a player
## actually looks at from the RTS camera.
##
## Counted off the **built scene**, not off the generator's tables, so it measures what was
## placed rather than what was listed. A name in a table that never survives a placement
## rule is exactly the sort of thing that would make a table-reading check lie.
func _test_the_district_is_dressed_from_a_wide_vocabulary() -> void:
	var props := {}
	for node in _scene.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		var path := batch.multimesh.mesh.resource_path
		if "SM_Prop_" in path:
			props[path] = true
	# 22 before the widening, 45 after. A floor between the two, nearer the new figure, so
	# this fails if the vocabulary is narrowed again without failing on one prop moving.
	_check(props.size() >= 35,
		"the district places a wide spread of props (%d distinct)" % props.size())


## And the terraces are not all one height per kind.
##
## The other half of "too much of a grid". Every block of a kind used to stand at exactly
## its kit's height -- twenty-one terraces sharing **three** silhouettes, in rows -- which
## reads as a lattice from above however irregular the block spacing is.
##
## Measured off the colliders rather than the facades on purpose: the collider is the thing
## that must agree with what was built, and reading it here means this check also fails if
## the two ever drift apart. The two blocks with a forecourt are excluded from the variation
## at source and stay at kit height, because raising the station wall put it between the
## opening camera and every unit parked on its own apron.
func _test_terraces_do_not_all_stand_the_same_height() -> void:
	var heights := {}
	var buildings := _scene.get_node_or_null("World/Buildings")
	if buildings == null:
		_check(false, "the map has a Buildings node to measure")
		return
	for node in buildings.get_children():
		if not String(node.name).begins_with("Block_"):
			continue
		var body := node as StaticBody3D
		var shape := body.get_node_or_null("Shape") as CollisionShape3D
		var box := shape.shape as BoxShape3D if shape else null
		if box == null:
			continue
		heights[snappedf(box.size.y, 0.01)] = true
	# Two of the twenty-one blocks are round towers on a CylinderShape3D and are skipped
	# here by construction. Note for anyone sabotaging this: flattening the colliders also
	# reddens the prisoner-loading scenario, which walks suspects through that geometry --
	# that is a real consequence of moving thirteen building walls, not a check reaching
	# too far. Collapsing only the singleton heights isolates it if you want one red.
	_check(heights.size() >= 6,
		"terraces stand at a spread of heights (%d distinct across %d blocks)"
			% [heights.size(), buildings.get_child_count()])


## The district's cars are not all blue. The pack paints every body off one atlas
## palette; the generator folds parked cars through the alt palettes -- each colour
## its own batch -- and the ambient fleet repaints itself at spawn.
func _test_parked_cars_wear_different_paints() -> void:
	var paints := {}
	var car_batches := 0
	for node in _scene.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		if "Veh_Car" not in batch.multimesh.mesh.resource_path:
			continue
		car_batches += 1
		if batch.material_override:
			paints[batch.material_override.resource_path] = true
	_check(car_batches > 0, "the lots hold batched parked cars (%d batches)" % car_batches)
	var alts := 0
	for path in paints:
		if "Alts/" in str(path):
			alts += 1
	_check(paints.size() >= 3 and alts >= 2,
		"parked in %d paints, %d off the alt palettes -- not a wall of blue"
		% [paints.size(), alts])


## The appliance is the van, not the patrol car it used to borrow.
##
## Measured off the generated scene rather than read off the config, because the map
## bakes each instanced vehicle's properties -- regenerating build_vehicles.gd alone
## has silently changed nothing before, and the file on disk looked right the whole
## time. Wheelbase is the sharpest single number: 4.46 on the appliance against 2.88 on
## the patrol car.
##
## This checked for the *van's rear doors* until August 2026, which was the right proof
## while the appliance was a van in orange paint. The real appliance has no separate
## doors, so that assertion had to go with the placeholder it pinned -- and what
## replaces it is the thing a fire engine has that nothing else on the map does.
func _test_the_appliance_is_a_real_appliance() -> void:
	var engine := (load("res://Game/Vehicles/FireEngine.tscn") as PackedScene).instantiate()
	var patrol := (load("res://Game/Vehicles/PoliceCar.tscn") as PackedScene).instantiate()
	var engine_base := (engine as Vehicle).wheelbase
	var patrol_base := (patrol as Vehicle).wheelbase
	_check(engine_base > patrol_base + 0.3,
		"the appliance rides a longer wheelbase than a patrol car (%.2f vs %.2f)"
		% [engine_base, patrol_base])
	# A ladder, which is proof of the body underneath in a way no dimension is: no other
	# prefab in any pack on disk has one, so this fails the moment `prefab` points
	# somewhere else.
	var ladder := 0
	for part in engine.find_children("*Ladder*", "Node3D", true, false):
		ladder += 1
	_check(ladder >= 2, "and carries a ladder, which no other body on the map has (%d parts)"
		% ladder)
	# Bulk, from the collider the generator sized off the hull. The appliance is the
	# largest thing the player drives and it should not be quietly swapped for a car.
	var box := (engine.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	var car := (patrol.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	_check(box.size.z > car.size.z * 1.4 and box.size.y > car.size.y * 1.4,
		"and is a size no car is (%.1f x %.1f against %.1f x %.1f)"
		% [box.size.z, box.size.y, car.size.z, car.size.y])
	# **Crew get out behind it, not inside it.** `dismount_back` was a fixed 3.2 that
	# suited a 5m van, and on an 8.8m body it put four firefighters a metre inside the
	# truck. Nothing caught it: a vehicle is a CharacterBody3D, so it is absent from the
	# baked navigation the dismount point snaps to, and the crew simply appeared in the
	# bodywork. It is derived from the hull now, and this is the number that says so.
	var shape := engine.get_node("Collision") as CollisionShape3D
	var tail: float = box.size.z * 0.5 + shape.position.z
	_check(engine.dismount_back > tail + 0.5,
		"and turns its crew out behind itself, not inside it (%.1fm back, tail at %.1fm)"
		% [engine.dismount_back, tail])
	engine.free()
	patrol.free()


## The **repainted** half of the fire service reads warm.
##
## The check that would have caught the two colour bugs this project has shipped. An
## alt palette is a texture atlas, not a colour: a mesh's UVs choose the swatch, so
## naming a material proves nothing about what comes out. 04_A is genuinely orange on
## the patrol car's hull, charcoal on the van's, and olive on the crew -- the appliance
## shipped black and the fire crew shipped green, and every existing check passed.
##
## **The appliance left this test in August 2026 when it stopped being a repaint.** It is
## now a purpose-built fire engine wearing its own texture, and this measure cannot say
## anything useful about it: averaged over its own UVs a red-and-white livery reads
## +0.03, under the bar, while a yellow taxi reads warmer than either. Averages are the
## wrong question for two-tone bodywork. What guards the appliance instead is
## `_test_the_appliance_is_a_real_appliance`, which pins the body itself rather than its
## colour. The firefighter is still a repainted police model, so the fault this was
## written for is still live for them, and here it stays.
func _test_the_fire_service_paint_is_warm() -> void:
	for subject in [
		{"scene": "res://Game/Firefighter.tscn", "what": "firefighter"},
	]:
		var node := (load(str(subject["scene"])) as PackedScene).instantiate()
		var mesh := _body_mesh(node)
		if mesh == null:
			_check(false, "%s has a body mesh to sample" % subject["what"])
			node.free()
			continue
		var warmth := _paint_warmth(mesh)
		# Red has to lead **both** other channels, which is what separates a warm coat
		# from the two things that have actually shipped here. Red-minus-blue alone
		# does not: the olive crew scored +0.09 on it, a hair under the charcoal van's
		# failing -0.01 and a hair over nothing. Against min(r-g, r-b) the same three
		# read -0.02 charcoal, 0.00 olive, and +0.08 / +0.14 for the palette in use --
		# a gap wide enough to put a threshold in the middle of.
		_check(warmth > 0.05,
			"the %s's paint reads warm, not charcoal or olive (min(r-g,r-b) %+.2f)"
			% [subject["what"], warmth])
		node.free()


## The doctor's car wears its own paint and cannot do the ambulance's job.
##
## **Sampled off the built scene, never taken from the palette name.** An alt palette is a
## texture atlas rather than a colour, so the same swatch is orange on this hull, flat
## charcoal on the van and olive on a person -- picking by name once shipped a black fire
## engine and dressed the firefighter in green for months. The only honest test is to read
## the pixels the mesh's own UVs land on, which is what [method _paint_warmth] does.
##
## The second half is a design constraint rather than a cosmetic one, and it is the more
## important of the two: give this car a stretcher and it quietly becomes a second
## ambulance, the patient never waits, and the bottleneck the doctor exists to be is gone.
func _test_the_doctors_car_is_orange_and_carries_nobody() -> void:
	var car := (load("res://Game/Vehicles/DoctorCar.tscn") as PackedScene).instantiate()
	var mesh := _body_mesh(car)
	if mesh == null:
		_check(false, "the doctor's car has a body mesh to sample")
		car.free()
		return
	var warmth := _paint_warmth(mesh)
	# The same bar the fire service's paint clears, and set in the same place: measured,
	# charcoal reads -0.02 and olive 0.00 on this scale, so 0.05 sits clear of both.
	_check(warmth > 0.05,
		"the doctor's car is painted warm, not the patrol car's blue (min(r-g,r-b) %+.2f)"
			% warmth)

	var vehicle := car as Vehicle
	_check(vehicle != null and vehicle.service == Unit.Service.MEDICAL,
		"it is a medical vehicle")
	_check(vehicle != null and vehicle.stretchers == 0,
		"and carries no stretcher, so it cannot do the ambulance's job (%d)"
			% (vehicle.stretchers if vehicle else -1))
	_check(vehicle != null and not vehicle.has_stretcher_space(),
		"which Collect reads straight off, so it is never offered one")
	# Faster than the ambulance, which is the entire point of a response car.
	var ambulance := (load("res://Game/Vehicles/Ambulance.tscn") as PackedScene).instantiate()
	_check(vehicle != null and vehicle.max_speed > (ambulance as Vehicle).max_speed,
		"and gets there quicker than the ambulance (%.0f vs %.0f)"
			% [vehicle.max_speed if vehicle else 0.0, (ambulance as Vehicle).max_speed])
	ambulance.free()
	car.free()


## The street lighting ships **dark**.
##
## Same rule the director follows: the map is quiet until asked. A hundred omni lights
## burning at midday washes the pavements out, and Daylight.gd owns the switch -- so
## the container is what must be off, not each lamp.
func _test_the_street_lights_ship_off() -> void:
	var lights := _scene.get_node_or_null("StreetLights") as Node3D
	_check(lights != null, "the district ships street lighting")
	if lights == null:
		return
	var lamps := lights.find_children("*", "OmniLight3D", true, false)
	_check(lamps.size() >= 20,
		"one light under every lamp standard the kerb draw put down (%d)" % lamps.size())
	_check(not lights.visible, "and it ships off, so noon is not lit by streetlight")


func _test_traffic_wears_different_paints() -> void:
	var paints := {}
	for node in _ambient("Traffic"):
		var car := node as TrafficCar
		if car == null:
			continue
		var coat := "stock"
		for part in car.find_children("*", "MeshInstance3D", true, false):
			var body := part as MeshInstance3D
			if body.mesh == null:
				continue
			for i in body.mesh.get_surface_count():
				var override := body.get_surface_override_material(i)
				if override and "Alts/" in override.resource_path:
					coat = override.resource_path
		paints[coat] = true
	_check(paints.size() >= 3,
		"the ambient fleet drives %d different paint jobs" % paints.size())


## A body on the pavement draws a crowd. Nearby civilians walk the pavement graph in
## and stand at a respectful distance -- close enough to gawp, never on top of the
## scene -- and go back to their day once it is cleared away.
func _test_civilians_gather_at_a_collapse() -> void:
	var crowd := _civilians()
	if crowd.is_empty():
		_check(false, "the map has a crowd on it")
		return

	# A pavement point with several civilians in gawping range but none already on
	# top of it, so the gather has to be walked rather than inherited.
	var spot := Vector3.INF
	var most := 0
	for point in CityGrid.pavement_points():
		var near := 0
		var clear := true
		for civilian in crowd:
			var away := _flat_distance(civilian.global_position, point)
			if away < 8.0:
				clear = false
			elif away < civilian.watch_radius - 1.0:
				near += 1
		if clear and near > most:
			most = near
			spot = point
	if spot == Vector3.INF:
		_check(false, "a pavement point with civilians in range")
		return

	var casualty := _spawn_casualty(spot)
	var came_over := false
	var legal := true
	for i in 900:
		await physics_frame
		for civilian in crowd:
			if not is_instance_valid(civilian) or not civilian.is_watching:
				continue
			if not _pedestrian_legal(civilian.global_position):
				legal = false
			if _flat_distance(civilian.global_position, spot) \
					<= civilian.watch_near + 2.0:
				came_over = true
		if came_over:
			break
	_check(came_over, "a civilian came over to watch the collapse")
	_check(legal, "every onlooker stayed on the pedestrian graph")

	# Let the gathering settle before measuring the standoff, or a crowd still
	# converging is measured mid-stride.
	await _wait(60)
	var on_top := false
	for civilian in crowd:
		if is_instance_valid(civilian) and civilian.is_watching \
				and _flat_distance(civilian.global_position, spot) < 1.5:
			on_top = true
	_check(not on_top, "and nobody is standing on the casualty")

	casualty.queue_free()
	await _wait(40)
	var still_watching := false
	for civilian in crowd:
		if is_instance_valid(civilian) and civilian.is_watching:
			still_watching = true
	_check(not still_watching, "the crowd disperses once the scene is cleared")
	await _clear_calls()


## A freeplay medical call takes a *civilian*: the director swaps a crowd member for
## a casualty where they stood, so the collapse is somebody who was just there --
## and only falls back to thin air when nobody qualifies.
## The district refills as it empties.
##
## Every medical call takes a shopper permanently, and nothing replaced them until August
## 2026: a long career quietly emptied the pavements, and once empty the call had nobody
## left to take and fell back to conjuring a casualty from thin air -- the very thing
## taking a civilian exists to avoid.
func _test_the_crowd_comes_back() -> void:
	var refill := _scene.get_node_or_null("CrowdRefill") as CrowdRefill
	if refill == null:
		_check(false, "the map carries a CrowdRefill")
		return
	_check(refill.target > 0, "it knows how many people the district holds (%d)"
		% refill.target)
	_check(not refill._outfits.is_empty(),
		"and what they are dressed in (%d outfits)" % refill._outfits.size())

	# Take a dozen off the pavements, the way a run of medical calls would.
	var crowd := _civilians()
	var taken := mini(12, crowd.size())
	for i in taken:
		crowd[i].queue_free()
	await _idle(4)
	var thinned := _civilians().size()
	_check(thinned == crowd.size() - taken,
		"a run of calls thins the crowd (%d -> %d)" % [crowd.size(), thinned])

	# Hurried along, because the arrival gap is half a minute of real play.
	refill.every = 0.05
	var before := refill.arrivals
	await _wait(120)
	_check(refill.arrivals > before,
		"and people come back to it (%d arrivals)" % [refill.arrivals - before])
	_check(_civilians().size() > thinned,
		"so the pavements refill (%d -> %d)" % [thinned, _civilians().size()])
	# Never past what the district was built to hold.
	_check(_civilians().size() <= refill.target,
		"and never past what it was built to hold (%d of %d)"
		% [_civilians().size(), refill.target])
	refill.every = 30.0
	await _idle(4)


func _test_a_medical_call_takes_a_civilian() -> void:
	await _clear_calls()
	var before := _civilians()
	if before.is_empty():
		_check(false, "a crowd for the director to draw on")
		return
	var stood_at: Array[Vector3] = []
	for civilian in before:
		stood_at.append(civilian.global_position)

	_director._spawn_medical()
	await _idle(6)
	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(bodies.size() == 1, "the call put one casualty on the map (%d)" % bodies.size())
	var after := _civilians().size()
	_check(after == before.size() - 1,
		"and the crowd is one lighter (%d -> %d)" % [before.size(), after])
	if bodies.size() == 1:
		var body := bodies[0] as Casualty
		var matched := false
		for point in stood_at:
			if _flat_distance(point, body.global_position) < 0.5:
				matched = true
		_check(matched, "the body lies where the civilian stood")
	await _clear_calls()

	# Nobody eligible -- everybody mid-flight -- and the call must still open.
	for civilian in _civilians():
		civilian.is_fleeing = true
	_director._spawn_medical()
	await _idle(6)
	var fallback := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	var untouched := _civilians().size()
	_check(fallback == 1 and untouched == after,
		"with nobody eligible it falls back to the pavement (%d body, crowd %d)"
		% [fallback, untouched])
	for civilian in _civilians():
		civilian.is_fleeing = false
	await _clear_calls()


func _test_traffic_drives_the_roads() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return
	var before: Array[Vector3] = []
	for node in traffic:
		before.append((node as Node3D).global_position)

	await _wait(300)

	var moved := 0
	var on_road := 0
	# **Say which ones, and why.** A bare count tells you two cars did not get going and
	# nothing else, which is a poor thing to hand whoever has to find out why -- and this
	# check has failed at exactly 20 of 22 while every neighbouring one passed. Naming
	# them, with how far they got and whether they were waiting for somebody, costs a
	# string and turns a shrug into a lead.
	var stalled: Array[String] = []
	var gaps: Array[float] = []
	for i in traffic.size():
		var car := traffic[i] as Vehicle
		var here: Vector3 = car.global_position
		var gap := here.distance_to(before[i])
		gaps.append(gap)
		if gap > 3.0:
			moved += 1
		else:
			stalled.append("%s %.1fm at (%.0f,%.0f) held=%.1fs speed=%.1f yielding=%s"
				% [car.name, gap, here.x, here.z, car.held_up_for(), car.forward_speed,
					car.get("is_yielding")])
		if _on_a_road(here):
			on_road += 1
	# The three shortest hops, always -- not only when it fails. The bar is 3m of net
	# displacement in five seconds, and knowing whether the fleet clears it by a metre or
	# by twenty is the difference between a real stall and a threshold sitting on a cliff.
	gaps.sort()
	var tightest := ""
	for i in mini(3, gaps.size()):
		tightest += "%s%.1f" % ["" if i == 0 else "/", gaps[i]]
	_check(moved >= traffic.size() - 1,
		"%d of %d traffic cars drove off (shortest hops %s)%s"
		% [moved, traffic.size(), tightest,
			"" if stalled.is_empty() else " -- " + "; ".join(stalled)])
	# The whole point of routing them by CityGrid rather than by random navigation
	# mesh points: they keep to the streets and to their own side of them.
	_check(on_road == traffic.size(),
		"%d of %d were still on a road" % [on_road, traffic.size()])


func _test_traffic_does_not_deadlock() -> void:
	# Long enough for every car to have reached a junction and turned. The failure
	# this catches is silent and total: two cars meeting at a crossroads each held the
	# other in their forward cone, both stopped, and the whole district's traffic
	# queued up behind them and never moved again. Sampled over the *second* half of
	# the run, because a car briefly stopped at a junction is fine.
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return

	await _wait(900)
	var before: Array[Vector3] = []
	for node in traffic:
		before.append((node as Node3D).global_position)
	await _wait(600)

	var stuck := PackedStringArray()
	for i in traffic.size():
		var car := traffic[i] as TrafficCar
		if car.global_position.distance_to(before[i]) < 2.0:
			stuck.append("%s (yielding=%s)" % [car.name, car.is_yielding])
	_check(stuck.is_empty(), "all %d cars were still moving after 25s%s" % [
		traffic.size(),
		"" if stuck.is_empty() else " -- stalled: " + ", ".join(stuck)])


## Vehicles are solid to one another. Measured rather than assumed, because the
## failure is invisible from the code: two cars sharing a point look like one car
## until you watch the centres. Before they were given collision the closest pair
## in a 15-second sample was 0.16m -- one car inside another.
func _test_traffic_does_not_drive_through_itself() -> void:
	var traffic := _ambient("Traffic")
	if traffic.size() < 6:
		_check(false, "a fleet to watch (%d)" % traffic.size())
		return

	var worst := INF
	var sunk := PackedStringArray()
	for frame in 600:
		await physics_frame
		for a in traffic.size():
			var one := traffic[a] as Node3D
			if one.global_position.y < -2.0 and sunk.find(one.name) < 0:
				sunk.append(one.name)
			for b in range(a + 1, traffic.size()):
				var two := traffic[b] as Node3D
				worst = minf(worst, _flat_distance(one.global_position,
					two.global_position))
	# A body is 1.9m wide and up to 5.6m long, so centres this close are
	# interpenetrating whatever the relative heading.
	_check(worst > 2.2,
		"no two cars ever shared the same space (closest pair %.2fm)" % worst)
	# The other half of solid: two cars laid down inside each other are flung apart
	# by the physics engine, and one of them left the world at 600 metres down.
	_check(sunk.is_empty(), "and none was ejected out of the world%s"
		% ("" if sunk.is_empty() else " -- lost: " + ", ".join(sunk)))


## Traffic gives way at the crossroads, and does it in a **strict order**: of two
## cars converging on the same junction, the nearer takes it and the farther waits.
## The follow rule cannot do this -- it deliberately only sees traffic going the same
## way -- so without this the two would drive into each other now they are solid, and
## a rule where both waited would lock the district instead.
##
## Staged with two cars of its own at a junction the ambient fleet is nowhere near,
## because the property being asserted is about exactly two cars.
func _test_traffic_gives_way_at_junctions() -> void:
	# An interior junction -- both approach streets have to exist -- that the ambient
	# fleet is nowhere near, so the only two cars in the rule are the staged ones.
	var cell := Vector2i(-1, -1)
	for x in range(1, CityGrid.BANDS - 1):
		for z in range(1, CityGrid.BANDS - 1):
			if cell.x >= 0:
				break
			var centre := CityGrid.junction(Vector2i(x, z))
			var quiet := true
			for node in _ambient("Traffic"):
				if _flat_distance((node as Node3D).global_position, centre) < 26.0:
					quiet = false
			if quiet:
				cell = Vector2i(x, z)
	if cell.x < 0:
		_check(false, "a junction with no ambient traffic near it")
		return

	var centre := CityGrid.junction(cell)
	var packed := load("res://Game/Traffic/Sedan.tscn") as PackedScene
	var near := packed.instantiate() as TrafficCar
	var far := packed.instantiate() as TrafficCar
	_scene.add_child(near)
	_scene.add_child(far)
	# Converging: one from the west 7m out, one from the south 12m out. Each is
	# re-anchored onto the leg it is driving -- a TrafficCar picks its route in
	# _ready, at whatever position it had then, which is the origin here.
	near.global_position = centre + Vector3(-7.0, 0.2, CityGrid.LANE_OFFSET)
	near.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	near._from = Vector2i(cell.x - 1, cell.y)
	near._to = cell
	near._begin_leg()
	far.global_position = centre + Vector3(-CityGrid.LANE_OFFSET, 0.2, 12.0)
	far.global_rotation = Vector3(0.0, PI, 0.0)
	far._from = Vector2i(cell.x, cell.y + 1)
	far._to = cell
	far._begin_leg()
	await _idle(4)

	_check(not near._junction_taken(),
		"the car nearest the crossroads takes it")
	_check(far._junction_taken(),
		"and the one further out gives way rather than meeting it in the middle")

	# Both must eventually get through: a rule where each waited for the other is
	# the deadlock that kept these cars intangible for months.
	var closest := INF
	for i in 900:
		await physics_frame
		closest = minf(closest, _flat_distance(near.global_position,
			far.global_position))
	_check(closest > 2.2,
		"and they never met in the box (closest %.1fm)" % closest)
	_check(_flat_distance(near.global_position, centre) > 9.0
			and _flat_distance(far.global_position, centre) > 9.0,
		"with both clear of the junction afterwards")

	near.queue_free()
	far.queue_free()
	await _idle(4)


func _test_traffic_keeps_right() -> void:
	# Sampled repeatedly rather than once, because the failure being watched for is a
	# car swinging wide through the oncoming lane mid-turn -- which a single snapshot
	# would almost always miss. Cars inside a junction are skipped: there is no lane
	# there, which is the whole reason a junction is a junction.
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return

	var wrong_side := 0
	var samples := 0
	for sweep in 24:
		await _wait(25)
		for node in traffic:
			var car := node as TrafficCar
			var here := car.global_position
			var across := _lane_offset(here)
			if across == Vector3.ZERO:
				continue  # in a junction, or off the grid
			var right := (-car.global_basis.z).cross(Vector3.UP)
			right.y = 0.0
			if right.length() < 0.01:
				continue
			samples += 1
			# A car is 2.2m wide and a lane 5m, so a metre the wrong side of the line
			# is a wheel over it rather than a car in the oncoming lane.
			if across.dot(right.normalized()) < -1.0:
				wrong_side += 1
	_check(samples > 100, "sampled traffic on open road %d times" % samples)
	_check(wrong_side * 20 < samples,
		"traffic held its own side of the road: %d of %d samples over the line"
		% [wrong_side, samples])


func _test_traffic_yields() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return
	var car := traffic[0] as TrafficCar
	# The rest of the traffic is removed first, so the only thing that can be in front
	# of this one is the car the test puts there. Otherwise it depends on where nine
	# independently-driving cars happen to be, which is not a property worth asserting.
	for i in range(1, traffic.size()):
		traffic[i].queue_free()
	await _wait(10)
	_check(not car.is_yielding, "traffic with a clear road ahead is not yielding")

	# Park the patrol car directly in its path. Traffic does not physically block the
	# player, so this has to be caught by the driver rather than by a collision.
	await _place_unit(_car, car.global_position - car.global_basis.z * 5.0)
	await _wait(20)
	_check(car.is_yielding, "and waits for a vehicle stopped in front of it")

	await _place_unit(_car, ROAD)
	await _wait(30)
	_check(not car.is_yielding, "then moves off once the road is clear")


## Blues coming through: a driving response makes traffic tuck in at the kerb and
## stop, then rejoin the lane once it has passed. The yield test above already
## thinned the traffic to one car, which is exactly what this needs.
## Traffic waits behind one of ours, and turns back when police close the road.
##
## Two halves of the same complaint. A car queued behind a stopped unit should wait — it
## already does — but a car queued into a **cordon** is waiting for something that will
## never move, and the cones are visual, so nothing stopped it driving in and sitting
## there. An officer closing a street is an instruction, and until now only the crowd
## listened to it.
func _test_traffic_turns_back_at_a_cordon() -> void:
	await _clear_incidents()
	var lane := CityGrid.LANE_OFFSET
	var street := CityGrid.band_centre_z(2)
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	await _idle(4)

	# Heading east down an open street: it keeps going.
	taxi.global_position = Vector3(-40.0, 0.2, street + lane)
	taxi.rotation.y = -PI * 0.5
	taxi._cordon_cooldown = 0.0
	await _idle(30)
	var open_start := taxi.global_position.x
	await _wait(180)
	_check(taxi.global_position.x > open_start + 4.0,
		"traffic drives on down an open street (%.1fm)"
		% (taxi.global_position.x - open_start))

	# Now close it in front of them.
	# Built in code, not from a scene: SecureOrder makes one the same way, and there is no
	# Cordon.tscn to load.
	var cordon := Cordon.new()
	_scene.add_child(cordon)
	cordon.global_position = Vector3(taxi.global_position.x + 40.0, 0.0, street)
	cordon.raise_cordon()
	taxi._cordon_cooldown = 0.0
	var was_east := -taxi.global_basis.z
	# **Does it leave, and does it stay out?** Not "how far past the cones did it get":
	# the car can pass the cordon, turn, and be back near it inside one sampling window,
	# and an assertion on a single distance reads that as driving into the closure. What
	# matters is that it turns away and is not still sitting there.
	var nearest_after := INF
	var last_gap := 0.0
	for sweep in 420:
		await physics_frame
		last_gap = _flat_distance(taxi.global_position, cordon.global_position)
		nearest_after = minf(nearest_after, last_gap)
	var now_facing := -taxi.global_basis.z
	_check(now_facing.dot(was_east) < 0.3,
		"a raised cordon turns it round (heading dot %.2f)" % now_facing.dot(was_east))
	_check(nearest_after > cordon.radius,
		"without driving into the cones (closest %.1fm, ring is %.1fm)"
		% [nearest_after, cordon.radius])
	_check(last_gap > cordon.radius * 2.0,
		"and it has left rather than queued at them (%.1fm away)" % last_gap)
	_check(_on_a_road(taxi.global_position),
		"and it is still on the road afterwards (%.1f, %.1f)"
		% [taxi.global_position.x, taxi.global_position.z])

	cordon.queue_free()
	taxi.queue_free()
	await _clear_incidents()
	await _idle(6)


## A car with no district left in front of it declines the tuck rather than aiming past
## the edge of the world.
##
## Reported from play, once, as a warning with a stack trace: `Traffic3 was sent off the map,
## to (-86.2, 0.0, -131.0)` on a district that ends at 130. The tuck aims seven metres ahead
## plus a couple across, and near an edge that lands outside. `Vehicle.navigate_to` caught it
## and clamped -- which is that guard doing exactly its job -- but clamping aims the car at
## the boundary rather than at a kerb, so it performs a tuck towards nothing.
##
## **The second half is the important half.** Asserting only that an edge car does not pull
## over would pass just as happily if the manoeuvre were broken everywhere, which is the
## commonest way a check here turns out to be worth nothing. So the same car, at the same
## moment, with the same responder, is then moved into open district and must pull over.
func _test_traffic_at_the_map_edge_does_not_pull_over_off_it() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "a traffic car to place at the edge")
		return
	var car := traffic[0] as TrafficCar
	car._tuck_cooldown = 0.0

	# Nose to the southern boundary with less than a tuck's length in front of it. The
	# manoeuvre reaches 7m ahead and 2.2m across, so 3m of district cannot contain it.
	var edge := CityGrid.MAP_HALF
	var outward := Vector3(0.0, 0.0, -1.0)
	var facing := atan2(-outward.x, -outward.z)
	await _place_unit(car, Vector3(-86.0, 0.1, -(edge - 3.0)), facing)
	await _place_unit(_car, car.global_position - outward * 6.0, facing)
	_car.lights_on = true
	await _wait(20)

	_check(not car.is_pulled_over,
		"a car three metres from the boundary does not pull over")
	var aim := car.move_target
	_check(absf(aim.x) <= edge and absf(aim.z) <= edge,
		"and is not aiming off the map (%.0f, %.0f of +/-%.0f)" % [aim.x, aim.z, edge])

	# The control: same car, same responder, room to do it. Without this the two checks
	# above would be green on a pull-over that never fires at all.
	var from := Vector2i(2, 2)
	var to := Vector2i(2, 3)
	var start := CityGrid.junction(from)
	var finish := CityGrid.junction(to)
	var direction := start.direction_to(finish)
	var lane := direction.cross(Vector3.UP) * CityGrid.LANE_OFFSET
	car._tuck_cooldown = 0.0
	await _place_unit(car, start.lerp(finish, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	await _place_unit(_car, start.lerp(finish, 0.15) + lane,
		atan2(-direction.x, -direction.z))
	_car.navigate_to(finish + direction * 25.0)
	var tucked := false
	for i in 600:
		await physics_frame
		if car.is_pulled_over:
			tucked = true
			break
	_check(tucked, "but the same car in open district still pulls over")
	# **Put back everything this disturbed, and `clear_orders` is not enough.** Two things
	# leaked out of the first cut of this check and cost thirteen reds in unrelated places:
	# `navigate_to` is not an order, so `clear_orders()` leaves the car still driving at a
	# point 25m past a junction and the next navigation check finds it already under way;
	# and the manual lightbar switch thrown above stays thrown, so every later check that
	# asserts a dark bar reads a lit one. The suite has no teardown -- what a check touches,
	# it hands back.
	_car.stop_navigating()
	_car.clear_orders()
	_car.lights_on = false
	car._release_tuck()
	car._tuck_cooldown = 0.0
	await _park_the_shift()


func _test_traffic_pulls_over_for_a_response() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "a traffic car to pull over")
		return
	var car := traffic[0] as TrafficCar

	# Stage a long straight leg: the taxi ahead in lane, the patrol car well behind
	# it -- outside the pull-over radius, so the manoeuvre is provoked by the
	# approach rather than by the placement.
	var from := Vector2i(2, 2)
	var to := Vector2i(2, 3)
	var start := CityGrid.junction(from)
	var end := CityGrid.junction(to)
	var direction := (start.direction_to(end))
	var lane := direction.cross(Vector3.UP) * CityGrid.LANE_OFFSET
	var centre_x := start.x

	await _place_unit(car, start.lerp(end, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	# Parked *inside* the pull-over radius first: proximity alone must not do it --
	# an emergency vehicle stood at a scene is driven around, not parked behind.
	await _place_unit(_car, start.lerp(end, 0.40) + lane,
		atan2(-direction.x, -direction.z))
	await _wait(10)
	_check(not car.is_pulled_over,
		"a parked patrol car is not a reason to pull over")
	await _place_unit(_car, start.lerp(end, 0.15) + lane,
		atan2(-direction.x, -direction.z))
	await _wait(4)

	# Sent well past the far junction, so the response is still driving -- and the
	# taxi still held at the kerb -- for long enough to be seen stopped there.
	_car.navigate_to(end + direction * 25.0)
	var tucked := false
	var widest := 0.0
	var stopped := false
	# How long it actually spends at the kerb, timed from the tuck. Timing from after
	# the release instead was inert: this loop already breaks on the release, so the
	# clock started once it had happened and read 0.0s whichever branch let the car go.
	var at_kerb := 0.0
	for i in 600:
		await physics_frame
		if car.is_pulled_over:
			tucked = true
			at_kerb += 1.0 / 60.0
			widest = maxf(widest, absf(car.global_position.x - centre_x))
			if absf(car.forward_speed) < 0.4:
				stopped = true
		if stopped and not car.is_pulled_over:
			break
	_check(tucked, "the taxi pulled over for the approaching response")
	_check(widest > CityGrid.LANE_OFFSET + 0.6,
		"tucked in past its own lane (%.1fm off the centre line)" % widest)
	_check(stopped, "and waited at the kerb")

	var resumed := false
	for i in 600:
		await physics_frame
		if not car.is_pulled_over and car.is_navigating():
			resumed = true
			break
	# It left the kerb *before the cap could have fired*, which is what makes this the
	# distance release rather than the timeout added later. There are two independent
	# ways out of the tuck and this check names one of them, so it has to exclude the
	# other or it is green whichever fired.
	_check(resumed and at_kerb < car.pull_over_max,
		"then rejoined the lane once the response had passed (%.1fs at the kerb, "
		% at_kerb + "cap is %.0fs)" % car.pull_over_max)

	# And it rejoins even when the response *never* passes.
	#
	# The tuck used to end only on distance, so a player working the same streets with
	# the lightbar on was never far enough away and the cars never came back: measured
	# over seventy seconds, pulled-over cars went 1, 3, 5, 6, 7 while the number still
	# moving fell from 21 to 16. They are solid, so each new arrival tucked into an
	# already-tucked car and stopped at an angle across the lane -- a pile-up that only
	# grew. A responder is passing, not parking, so the manoeuvre has to have an end of
	# its own.
	await _place_unit(car, start.lerp(end, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	car._tuck_cooldown = 0.0
	# The responder sitting on top of it and **still navigating**, for longer than the
	# cap. Keeping it navigating is the whole trick: `_responder_near` gates on
	# `is_navigating()`, so a car that reaches its target stops counting as a responder
	# and the tuck ends by *distance* within a frame. The first version of this hopped
	# the responder two metres, and the check passed at "after 0s" -- measuring the
	# distance release while claiming to measure the cap.
	await _place_unit(_car, start.lerp(end, 0.55) + lane,
		atan2(-direction.x, -direction.z))
	# Navigating to somewhere it can never reach, and pinned where it is. A responder
	# that *arrives* stops being one -- `_responder_near` gates on `is_navigating()` --
	# and re-issuing the order each frame still leaves a frame's gap in which the tuck
	# releases on distance. This never arrives, so the only way out of the kerb is the
	# cap, which is the thing under test.
	var post := start.lerp(end, 0.55) + lane
	var facing := atan2(-direction.x, -direction.z)
	# **Unreachable, but on the map.** 400m along the street lands at z 402 on a district
	# that ends at 130, so this tripped `navigate_to`'s off-map guard on every single run --
	# a warning with a full stack trace, fired by design, in a suite whose whole value is
	# that its output means something. It very nearly buried a real one: the guard caught a
	# genuine off-map pull-over reported from play, and this was the noise it was sitting in.
	# The distance was never load-bearing anyway -- `pin` below holds the car still every
	# frame, so it cannot arrive at anything, however close.
	var far := post + direction * 400.0
	var edge := CityGrid.MAP_HALF
	_car.navigate_to(Vector3(clampf(far.x, -edge, edge), far.y, clampf(far.z, -edge, edge)))
	var pin := func() -> void:
		_car.global_position = post
		_car.rotation.y = facing
		_car.velocity = Vector3.ZERO
	var held := false
	for i in 300:
		await physics_frame
		pin.call()
		if car.is_pulled_over:
			held = true
			break
	_check(held, "a car tucks in for a response sitting on top of it")
	var let_go := false
	var waited := 0.0
	for i in int((car.pull_over_max + 4.0) * 60.0):
		await physics_frame
		waited += 1.0 / 60.0
		pin.call()
		if car.is_pulled_over:
			continue
		let_go = true
		break
	# The lower bound is what makes this the *cap* rather than the distance release.
	# A release at 0s means the responder stopped being one, which proves nothing about
	# a car that has been sat at the kerb too long.
	_check(let_go and waited > 1.0,
		"and rejoins the road anyway after %.1fs rather than silting up the street "
		% waited + "(cap is %.0fs)" % car.pull_over_max)
	_car.stop_navigating()


# --- Autopilot ---------------------------------------------------------------
