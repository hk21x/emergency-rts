extends "res://Game/Tests/Dispatch.gd"

## Freeplay: the director and the score -- 82 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_the_director_sleeps_until_started() -> void:
	await _clear_calls()
	if _director == null:
		_check(false, "the map ships a Director")
		return
	_check(not _director.active, "the director sleeps until a shift is opened")

	# Wound right down, so if the gate were broken this would catch it inside the
	# window rather than passing because the default first call is 10 seconds out.
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.3
	_director.call_interval_max = 0.3
	await _wait(90)
	_check(get_nodes_in_group(Incident.GROUP).is_empty(),
		"and opens nothing on its own (%d incidents)"
		% get_nodes_in_group(Incident.GROUP).size())


## The navigation overlay ships off, and draws nothing until it is switched on.
##
## Same rule the director lives by: a diagnostic that starts on is a diagnostic that
## ships on, and this one draws over the whole district. Checking `showing` alone would
## pass on an overlay that is invisible but still rebuilding a mesh from every vehicle
## every frame, so the node's own visibility is checked too.
func _test_the_navigation_overlay_is_off_until_asked() -> void:
	var overlay := _scene.get_node_or_null("NavDebug") as Node3D
	_check(overlay != null, "the district carries a navigation overlay")
	if overlay == null:
		return
	_check(not overlay.get("showing"), "which is off on a district nobody has asked")
	_check(not overlay.visible, "and draws nothing while it is")


func _test_the_director_opens_calls_where_they_belong() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 7
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.5
	_director.call_interval_min = 1.5
	_director.call_interval_max = 1.5
	_director.max_open_calls = 4
	_director.breather = 0.5
	_director.begin_shift()
	_check(_director.active, "begin_shift opens the shift")
	_check(_mission.scoring, "and the mission starts scoring")

	# Capped at 5 game-seconds on purpose: by 8 a fire would be established enough to
	# spread, and a spread body lands 5m from its parent -- inside the clearance this
	# test is asserting.
	var titles := {}
	for i in 300:
		await physics_frame
		for call in _board.open_calls():
			titles[call.title()] = true
		if _board.open_calls().size() >= 3:
			break
	var open := _board.open_calls()
	_check(open.size() >= 3,
		"the district produced %d simultaneous calls" % open.size())

	var clear := true
	for node in get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident == null:
			continue
		if _flat_distance(incident.global_position, _station.global_position) \
					< Director.CLEAR_OF_FORECOURTS \
				or _flat_distance(incident.global_position, _hospital.global_position) \
					< Director.CLEAR_OF_FORECOURTS:
			clear = false
	_check(clear, "every call keeps clear of the station and hospital forecourts")

	# Not measured off the live calls, deliberately: the board already refuses to open
	# a second call within GROUPING_RADIUS, so a distance check on open calls passes
	# whatever the director does. The invariant that actually matters is that the
	# director's spacing clears the board's grouping -- shrink it below and a "new"
	# call would silently join the scene it was meant to be distinct from.
	_check(Director.CLEAR_OF_OTHER_CALLS > Call.GROUPING_RADIUS,
		"a new call is kept further from an open one than the board would group (%0.f > %0.f)"
		% [Director.CLEAR_OF_OTHER_CALLS, Call.GROUPING_RADIUS])

	var known := true
	for title in titles:
		if title not in ["Medical emergency", "Fire", "Road traffic collision",
				"Disturbance", "Vehicle fire", "Electrical fire, water unsuitable",
				"Bus collision, multiple casualties", "Shed load blocking the road",
				"Person collapsed, drink suspected", "Child reported missing"]:
			known = false
	_check(known and titles.size() >= 2,
		"the mix drew %d kinds, all of them answerable by the roster (%s)"
		% [titles.size(), ", ".join(titles.keys())])
	await _end_freeplay()


func _test_the_director_caps_simultaneous_calls() -> void:
	_director.shift_seed = 11
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.4
	_director.call_interval_max = 0.4
	_director.max_open_calls = 2
	_director.breather = 0.2
	_director.begin_shift()

	# Interval far below the cap: left ungoverned this would be a call every 0.4s.
	var worst := 0
	for i in 300:
		await physics_frame
		worst = maxi(worst, _board.open_calls().size())
	_check(worst > 0, "calls opened under the cap test (%d)" % worst)
	_check(worst <= 2, "and never more than the cap of 2 at once (worst %d)" % worst)
	await _end_freeplay()


func _test_the_director_breathes_after_a_close() -> void:
	_director.shift_seed = 3
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.2
	_director.call_interval_max = 0.2
	_director.max_open_calls = 1
	_director.breather = 4.0
	_director.begin_shift()

	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to close for the breather test")
		await _end_freeplay()
		return
	var first := _board.open_calls()[0]
	_resolve_call(first)
	await _idle(6)
	_check(not first.is_open(), "dealing with the scene closed its call")

	# Two seconds of the four-second breather: nothing new may open in it.
	var quiet := true
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			quiet = false
	_check(quiet, "the district gets its breather before the next call")

	var next := false
	for i in 360:
		await physics_frame
		if not _board.open_calls().is_empty():
			next = true
			break
	_check(next, "and the next call comes once it has passed")
	await _end_freeplay()


## The set-piece call. Two casualties in the same crossroads have to read as one job
## with a name, not as a pair of unrelated collapses.
func _test_an_rtc_reads_as_one_call() -> void:
	await _clear_calls()
	var cell := Vector2i(2, 1)
	_director._spawn_rtc(cell)
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(bodies == 2, "an RTC puts two casualties in the road (%d)" % bodies)
	var open := _board.open_calls()
	_check(open.size() == 1, "grouped as a single call (%d)" % open.size())
	if not open.is_empty():
		_check(open[0].title() == "Road traffic collision",
			"titled by what happened, not what it left behind ('%s')" % open[0].title())
		_check(_flat_distance(open[0].position, CityGrid.junction(cell)) < 5.0,
			"and placed at the crossroads (%.1fm out)"
			% _flat_distance(open[0].position, CityGrid.junction(cell)))
	await _clear_calls()


## The RTC grown into a mass-casualty scene: sized by the medical roster, gentled so it
## reads as triage rather than a massacre, wearing a bus, and still one call.
func _test_a_bus_collision_scales_to_the_medical_roster() -> void:
	await _clear_calls()
	# A bare medical roster for the bottom BUS_SIZE row. The fixture fleet owns three
	# medical hands (an ambulance and two paramedics), which is already the middle row.
	var kept_ambulances := int(_station.owned.get(&"ambulance", 0))
	var kept_paramedics := int(_station.owned.get(&"paramedic", 0))
	_station.owned[&"ambulance"] = 0
	_station.owned[&"paramedic"] = 0
	_director._rng.seed = 5
	_director._spawn_bus_rtc(Vector2i(2, 1))
	_station.owned[&"ambulance"] = kept_ambulances
	_station.owned[&"paramedic"] = kept_paramedics
	await _idle(6)

	var bodies: Array[Casualty] = []
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		bodies.append(node as Casualty)
	_check(bodies.size() == 3,
		"a bus collision on a bare roster is three casualties (%d)" % bodies.size())
	var open := _board.open_calls()
	_check(open.size() == 1, "grouped as a single call (%d)" % open.size())
	if not open.is_empty():
		_check(open[0].title() == "Bus collision, multiple casualties",
			"titled by what happened ('%s')" % open[0].title())
	var gentled := not bodies.is_empty()
	for body in bodies:
		if body.decline_per_second > 0.011:
			gentled = false
	_check(gentled, "every casualty declines at the gentled rate")

	# The bus itself: a stripped Town-pack prop among the bodies, not an incident.
	var wreck: Node3D = null
	for child in _incidents.get_children():
		if not (child is Incident) and str(child.scene_file_path).contains("Bus"):
			wreck = child
	_check(wreck != null, "and a bus lies at the junction")

	# Resolve the whole scene from code: the wreck leaves with the *last* casualty.
	# **The flag is latched before the delivery, not read after it.** A freed object
	# compares equal to null, so `wreck != null` after the free is false and the check
	# would fail on exactly the behaviour it exists to confirm.
	var had_wreck := wreck != null
	for body in bodies:
		body.treat(1.0)
		body.deliver()
	await _idle(6)
	_check(had_wreck and not is_instance_valid(wreck),
		"the bus goes with the last of them")
	await _clear_calls()


## The same scene against fatter rosters: more medical hands, more patients.
func _test_a_bus_collision_grows_with_the_roster() -> void:
	await _clear_calls()
	# The fixture fleet's three medical hands are the middle BUS_SIZE row.
	_director._rng.seed = 9
	_director._spawn_bus_rtc(Vector2i(3, 2))
	await _idle(6)
	var middle := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(middle == 4,
		"a bus collision on the fixture roster is four casualties (%d)" % middle)
	await _clear_calls()

	# Four extra paramedics on the books -- bought, never dispatched -- takes the
	# medical hands to seven, the top row.
	_buy(&"paramedic", 4)
	_director._rng.seed = 9
	_director._spawn_bus_rtc(Vector2i(3, 2))
	await _idle(6)
	var full := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(full == 5,
		"and five against a full medical roster (%d)" % full)
	_station.owned[&"paramedic"] = int(_station.owned.get(&"paramedic", 0)) - 4
	_station._save_career()
	_station.roster_changed.emit()
	await _clear_calls()


## The pacing constants are not flat: the district gets busier as the shift wears
## on. Pure arithmetic on the director, asserted at the three points that matter.
func _test_the_director_escalates_late_in_the_shift() -> void:
	_director.shift_length = 100.0
	_director.max_open_calls = 3
	_director.clock = 0.0
	_check(_director.current_cap() == 3,
		"the shift opens at the flat cap (%d)" % _director.current_cap())
	_check(absf(_director.interval_scale() - 1.0) < 0.01,
		"with the intervals unscaled (x%.2f)" % _director.interval_scale())

	_director.clock = 70.0
	_check(_director.current_cap() == 4,
		"the late surge takes one extra call at once (%d)" % _director.current_cap())
	_check(_director.interval_scale() < 0.75,
		"with calls arriving faster (x%.2f)" % _director.interval_scale())

	_director.clock = 100.0
	_check(_director.interval_scale() <= _director.late_interval_scale + 0.01,
		"sliding to the floor by the final bell (x%.2f)" % _director.interval_scale())
	_director.clock = 0.0
	_director.shift_length = 300.0


## A car alight at the kerb: parked against the edge of a street, wearing a wreck,
## named for what it is -- and the wreck goes when the fire does.
func _test_a_vehicle_fire_burns_at_the_kerb() -> void:
	await _clear_calls()
	_director._rng.seed = 42
	_director._spawn_vehicle_fire()
	await _idle(6)

	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	if fires.size() != 1:
		_check(false, "a vehicle fire on the map (%d fires)" % fires.size())
		return
	var fire := fires[0] as Fire
	_check(fire.flavour == "Vehicle fire",
		"the fire knows what it is ('%s')" % fire.flavour)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Vehicle fire",
		"and the board names the job ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	# At the kerb of a street: on a road band along exactly one axis -- between
	# junctions, off the blocks -- and pulled to the carriageway's edge.
	var spot := fire.global_position
	_check(_in_band_x(spot.x) != _in_band_z(spot.z),
		"it burns on a street, not a junction or a block (%.1f, %.1f)"
		% [spot.x, spot.z])
	var off_centre := INF
	for band in CityGrid.BANDS:
		off_centre = minf(off_centre, minf(
			absf(spot.x - CityGrid.band_centre_x(band)),
			absf(spot.z - CityGrid.band_centre_z(band))))
	_check(absf(off_centre - Director.KERB_OFFSET) < 0.6,
		"parked against the kerb (%.1fm off the centre line)" % off_centre)

	var wreck := _wrecks()
	_check(wreck.size() == 1, "with a wreck under the flames (%d)" % wreck.size())

	# The bug this check exists for: Fire._spread() clones itself with duplicate(),
	# which copies children -- so a wreck parented to the fire bred a new car on the
	# street with every spread. It is a sibling now, and spreading must not multiply
	# it. Wound right down so the spread happens inside the window.
	fire.intensity = 0.95
	fire.spread_interval = 0.2
	var spread := false
	for i in 240:
		await physics_frame
		if get_nodes_in_group(Fire.FIRE_GROUP).size() > 1:
			spread = true
			break
	_check(spread, "the fire spread (%d fires)"
		% get_nodes_in_group(Fire.FIRE_GROUP).size())
	_check(_wrecks().size() == 1,
		"and one burning car stayed one burning car (%d wrecks)" % _wrecks().size())

	for node in get_nodes_in_group(Fire.FIRE_GROUP):
		(node as Fire).douse(5.0)
	await _idle(8)
	_check(_board.open_calls().is_empty(), "dousing it clears the call")
	_check(_wrecks().is_empty(), "and the wreck went with the fire")
	await _clear_calls()


## Before the law arrives a disturbance is somebody, not a statue: animated from
## the first frame (the first suspect shipped in a T-pose -- the clip name it
## trusted was not on the rig), pacing a few metres about the scene along the
## pedestrian graph, and never leaving it.
func _test_a_disturbance_lives_before_the_law() -> void:
	await _clear_calls()
	_director._rng.seed = 21
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerbside spot for the disturbance")
		return
	var suspect := _director._spawn_suspect(spot)
	await _wait(20)
	var player := suspect.get_node("Character/AnimationPlayer") as AnimationPlayer
	_check(player.current_animation != "",
		"a fresh suspect is animated, not a T-pose ('%s')" % player.current_animation)

	var moved := 0.0
	var legal := true
	for i in 600:
		await physics_frame
		if not is_instance_valid(suspect):
			break
		var away := _flat_distance(suspect.global_position, spot)
		moved = maxf(moved, away)
		if away > 0.5 and not _pedestrian_legal(suspect.global_position):
			legal = false
	_check(moved > 0.8,
		"they pace about the scene (peaked %.1fm from the spot)" % moved)

	# The moonwalk again, in a second costume: Person.tscn yaws its visual 180 and
	# the whole project steers on that assumption, but Suspect.tscn shipped without
	# it and the first disturbance paced about backwards. Nothing in code reads the
	# model's orientation, so only an explicit check catches it.
	var was := suspect.global_position
	var backwards := 0
	var sampled := 0
	for i in 600:
		await physics_frame
		if not is_instance_valid(suspect):
			break
		var travel := suspect.global_position - was
		was = suspect.global_position
		travel.y = 0.0
		if travel.length() < 0.01:
			continue
		sampled += 1
		var face: Node3D = suspect.get_node("Character")
		if face.global_basis.z.normalized().dot(travel.normalized()) < 0.8:
			backwards += 1
	_check(sampled > 20, "sampled the pacing %d times" % sampled)
	_check(backwards == 0,
		"and they walk forwards, not backwards (%d of %d steps moonwalked)"
		% [backwards, sampled])
	_check(moved <= suspect.wander_radius + 1.5,
		"without leaving it (radius %.1f)" % suspect.wander_radius)
	_check(legal, "and keep to the pedestrian graph")

	# **Cuffed, they stand still.** They used to trudge back to the spot the call opened
	# on, because that kerb was where the patrol car's reach was measured from -- the car
	# came to them. Since the escort moved onto the officer's feet in August 2026 nothing
	# needs them at a particular place, and walking off on their own would mean an officer
	# sent to collect somebody arrives to find them somewhere else.
	#
	# Caught mid-pace, or the check proves nothing: a suspect who happened to be standing
	# still anyway would pass it without the detained branch existing at all.
	var away_now := 0.0
	for i in 600:
		await physics_frame
		away_now = _flat_distance(suspect.global_position, spot)
		if away_now > 1.2:
			break
	if away_now <= 1.2:
		_check(false, "caught the suspect mid-pace to cuff them")
	else:
		suspect.detain(1.0)
		var cuffed_at := suspect.global_position
		var drifted := 0.0
		for i in 600:
			await physics_frame
			drifted = maxf(drifted, _flat_distance(suspect.global_position, cuffed_at))
		_check(drifted < 0.5,
			"cuffed, they stand where they are rather than wandering (%.2fm)" % drifted)
	await _clear_calls()


## The fire service, end to end. Its shape is the point: one verb done properly, a
## rate that depends on standing near your own appliance, and a kind of fire nobody
## else can touch.
## The appliance raises its ladder while its hose is being worked, and lowers it after.
##
## This is what the fire engine does instead of swinging rear doors. The van it replaced
## had them as separate meshes and the real appliance has none, so the flourish moved
## from the back of the vehicle to the top of it -- and it is wired to something true
## rather than to a timer: `ExtinguishOrder` asks for it every frame it draws from this
## appliance's tank, so an engine parked doing nothing keeps its ladder stowed and one
## actually supplying a hose puts it up.
## A fire's visuals answer to its intensity, sub-emitters included.
##
## Nothing pinned the fire's appearance at all until August 2026, in either direction:
## the flame was a cone and two hand-built quad emitters, and a regression in any of it
## would have gone unnoticed. That mattered when they were replaced by the particle
## pack's, whose fire is not one emitter but three -- flame, embers and a ground spread
## -- because `amount_ratio` does not inherit, and a fire barely alight would otherwise
## still throw a full complement of embers.
## Fires of different kinds behave differently, and a car fire costs you to park by.
##
## A fire was one thing with four fields the director set inline, and the only difference
## it expressed was whether a hose was needed. Three kinds now carry their own rates,
## plume and spread, and the table is the only place they are written down -- which is
## worth pinning, because a table that drifts back into agreement is a table that stopped
## doing anything.
## A cylinder heats beside a fire, cools under a hose, and takes the street with it if
## nobody deals with it.
##
## The first thing in the district that acts rather than waits. Everything else here gets
## worse and eventually fails; this one damages what is parked near it, hurts whoever is
## standing near it and throws fires of its own -- so it is worth pinning that it can be
## beaten, and that the blast lands where a blast may land.
func _test_a_cylinder_cooks_off() -> void:
	await _clear_incidents()
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	await _idle(30)
	_check(is_zero_approx(hazard.heat),
		"a cylinder with nothing burning near it is cold (%.2f)" % hazard.heat)

	var fire := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 1.0)
	fire.growth_per_second = 0.0
	await _idle(120)
	var warmed := hazard.heat
	_check(warmed > 0.0, "a fire beside it starts cooking it (%.2f after 2s)" % warmed)

	# Put the fire out and it sheds heat on its own -- which is what makes "deal with the
	# fire first" a real answer rather than a race that is always lost.
	fire.douse(2.0)
	await _idle(120)
	_check(hazard.heat < warmed,
		"and it cools once the fire is out (%.2f from %.2f)" % [hazard.heat, warmed])
	await _clear_incidents()


## The blast, staged rather than waited for: what it costs, and where it puts its fires.
func _test_a_cylinder_going_off_takes_the_street() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	if engine == null:
		_check(false, "an engine to park beside it")
		return
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	await _place_unit(engine, spot + Vector3(4.0, 0.2, 0.0))
	engine.repair_bill = 0
	await _idle(4)

	# **The hazard is gone by the time this is read**, because `_finish()` frees it, so
	# the outcome is taken off the signal rather than off the object. The first cut read
	# `hazard.active` after the blast, which raises a runtime error -- and a runtime error
	# in this suite does not fail a check, it silently abandons the rest of the test. All
	# four checks below vanished and the run still reported green; only the count said so.
	# An Array box rather than a captured bool: GDScript lambdas capture by value.
	# Somebody standing in it, so the blast has a person to hurt. Without one the outfit
	# check below reads "0 bodiless of 0" and proves nothing -- which is how it first
	# went red, and a fair warning about staging a blast in an empty street.
	var bystander := _nearest_civilian(spot)
	if bystander:
		await _place_unit(bystander, spot + Vector3(2.0, 0.0, 0.0))
		await _idle(4)
	var outcome: Array = []
	hazard.resolved.connect(func(_incident: Incident, success: bool) -> void:
		outcome.append(success))
	hazard.heat = 1.0
	await _idle(10)
	_check(outcome == [false],
		"a cylinder at full heat goes off, and the call is lost (%s)" % [outcome])
	_check(engine.repair_bill > 0,
		"and bills what was parked beside it (£%d)" % engine.repair_bill)

	var lit := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(lit.size() > 0, "throwing fires of its own (%d)" % lit.size())
	# The same rule every placement in this game funnels through. A blast that lit the
	# inside of a building would be a call nobody could answer.
	var indoors := 0
	for node in lit:
		var tile := CityGrid.tile_at((node as Node3D).global_position)
		if not CityGrid.standable(tile.x, tile.y):
			indoors += 1
	_check(indoors == 0,
		"and none of them inside a building (%d of %d)" % [indoors, lit.size()])

	# **And the people it hurt have bodies.** `_hurt_people` dresses a new casualty in
	# the civilian's outfit, and it had the same one-directory bug that made a recruited
	# suspect invisible in play: `scene_file_path` is the *unit* scene, not the outfit,
	# and `ResourceLoader.exists()` accepts both. That twin was uncovered when the first
	# was found -- so this is here to stop the identical fault shipping twice.
	var bodiless := 0
	var hurt := 0
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty == null:
			continue
		hurt += 1
		var body := casualty.get_node_or_null("Character") as Node3D
		if body == null or not (body.scene_file_path in Incident.OUTFITS):
			bodiless += 1
	_check(hurt > 0 and bodiless == 0,
		"and whoever it hurt is wearing a real outfit (%d bodiless of %d)"
		% [bodiless, hurt])

	await _clear_incidents()
	_dissolve(engine, &"engine")
	await _idle(4)



## The stream is a readout, not a flourish: it shows up exactly where water is landing.
func _test_water_shows_where_it_is_landing() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"officer", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	var officer := _station.dispatch(&"officer") as Person
	if engine == null or crew == null or officer == null:
		_check(false, "an engine, a crew and an officer to send")
		return
	# Away from (20, -20), where the fire-service tests stage their own appliance.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	await _idle(4)

	_check(_jet_of(crew) == null, "a firefighter walking about carries no jet")

	crew.issue(ExtinguishOrder.new(fire))
	await _idle(30)
	var jet := _jet_of(crew)
	_check(jet != null and jet.emitting, "and on the job the water is running")
	if jet != null:
		# The stream has to leave the person and travel to the fire. Both halves matter:
		# a jet aimed correctly but emitted from the middle of the body reads as a
		# firefighter steaming rather than hosing.
		var chest := crew.global_position + Vector3.UP * Person.NOZZLE_HEIGHT
		_check(jet.global_position.distance_to(chest) > 0.2,
			"out of a nozzle in front of them (%.2fm)"
			% jet.global_position.distance_to(chest))
		# -Z is where a GPUParticles3D fires, so this is the aim itself rather than a
		# proxy for it.
		var aim := -jet.global_transform.basis.z.normalized()
		var at_fire := (fire.global_position - jet.global_position).normalized()
		_check(aim.dot(at_fire) > 0.98,
			"and pointed at the fire (%.3f of 1.0)" % aim.dot(at_fire))

	# The nozzle: the appliance's own, held in the hand the skeleton says is there.
	var nozzle := crew.get_node_or_null("HeldNozzle") as Node3D
	_check(nozzle != null and nozzle.visible, "a firefighter is holding a nozzle")
	if nozzle != null and jet != null:
		# In the hand, not floating at the middle of the body. Measured against the
		# skeleton rather than against a guessed height, because the hand is what the
		# code reads and a check on a constant would agree with itself.
		var skel := crew.get_node_or_null(
			"Character/Armature/GeneralSkeleton") as Skeleton3D
		var bone := skel.find_bone(Person.HAND_BONE) if skel else -1
		if bone >= 0:
			var hand: Vector3 = skel.global_transform \
				* skel.get_bone_global_pose(bone).origin
			_check(nozzle.global_position.distance_to(hand) < 0.05,
				"in the hand the skeleton reports (%.3fm off)"
				% nozzle.global_position.distance_to(hand))
		else:
			_check(false, "a RightHand bone to hold it in")
		# And the water leaves the muzzle rather than the grip, or the first half-metre
		# of the stream is inside the tool making it.
		var barrel := jet.global_position.distance_to(nozzle.global_position)
		_check(absf(barrel - Person.NOZZLE_LENGTH) < 0.02,
			"with the water leaving its muzzle (%.2fm down a %.2fm barrel)"
			% [barrel, Person.NOZZLE_LENGTH])

	# It expires on its own. Nothing tells it to stop -- the order simply stops asking,
	# and the ask times out.
	#
	# The fire is put **out** rather than the order cleared, which the first cut of this
	# did and which failed: a firefighter left standing beside a live fire with no orders
	# auto-engages and picks it straight back up, so the water quite correctly kept
	# running. That is the game working; the check was wrong.
	fire.douse(5.0)
	await _idle(45)
	jet = _jet_of(crew)
	_check(jet != null and not jet.emitting, "it stops when the work does")
	var stowed := crew.get_node_or_null("HeldNozzle") as Node3D
	_check(stowed != null and not stowed.visible, "and the nozzle goes away with it")

	# **The design pin.** A building fire yields to nothing but a hose, and an officer
	# in front of one achieves precisely nothing -- so they must not appear to be doing
	# something. The jet is driven by water delivered, not by an order being run, and
	# this is the check that says so.
	var building := _spawn_fire(spot + Vector3(0.0, 0.0, 8.0), 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	await _place_unit(officer, spot + Vector3(2.0, 0.0, 8.0))
	await _idle(4)
	officer.issue(ExtinguishOrder.new(building))
	await _idle(45)
	var officer_jet := _jet_of(officer)
	_check(officer_jet == null or not officer_jet.emitting,
		"and an officer achieving nothing on a building fire shows no water")
	# Not a vacuous pairing: the same officer on a fire they *can* fight does spray, so
	# the check above is about this fire and not about officers.
	officer.clear_orders()
	var bin := _spawn_fire(spot + Vector3(0.0, 0.0, 16.0), 0.6)
	bin.kind = Fire.Kind.BIN
	bin.growth_per_second = 0.0
	await _place_unit(officer, spot + Vector3(2.0, 0.0, 16.0))
	await _idle(4)
	officer.issue(ExtinguishOrder.new(bin))
	await _idle(30)
	officer_jet = _jet_of(officer)
	_check(officer_jet != null and officer_jet.emitting,
		"though the same officer on a bin fire does")
	# **No pack has a fire extinguisher** -- 516 props and not one, so an officer works
	# an implied tool rather than being handed the appliance's hose nozzle, which would
	# say the wrong thing about what a patrol car carries.
	_check(officer.get_node_or_null("HeldNozzle") == null,
		"and carries no hose nozzle, which is the appliance's")

	officer.clear_orders()
	crew.clear_orders()
	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	_dissolve(officer, &"officer")
	await _idle(4)


## Different fires want different things put on them, and the wrong thing does nothing.
func _test_a_fire_wants_the_right_stuff_on_it() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"officer", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	var officer := _station.dispatch(&"officer") as Person
	if engine == null or crew == null or officer == null:
		_check(false, "an engine, a crew and an officer to send")
		return
	# Away from (20, -20), which the fire-service tests stage their own appliance at.
	var spot := Vector3(-60.0, 0.0, 60.0)
	_check(engine.carries_foam, "the appliance carries foam as well as water")

	# A car burns fuel, so it costs foam -- and only foam.
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	var car := _spawn_fire(spot, 0.9)
	car.kind = Fire.Kind.VEHICLE
	car.growth_per_second = 0.0
	engine.water = 1.0
	engine.foam = 1.0
	crew.issue(ExtinguishOrder.new(car))
	await _wait(60)
	_check(engine.foam < 1.0 and is_equal_approx(engine.water, 1.0),
		"a car fire drains the foam and not the water (foam %.3f, water %.3f)"
		% [engine.foam, engine.water])
	# The foam has to be visibly foam, or the rule is a memory test. A separate scene,
	# not the water jet in another colour -- see FoamJet.tscn.
	var foam_jet := crew.get_node_or_null("FoamJet") as GPUParticles3D
	# Reads the node, so what it pins is that a **separate emitter** is built and
	# running -- not that the pixels look like foam, which no check can judge. That
	# distinction is the whole reason FoamJet.tscn is a second scene rather than the
	# water jet recoloured, so it is worth pinning even in this weaker form.
	_check(foam_jet != null and foam_jet.emitting,
		"and it comes out of its own emitter, not the water one")
	crew.clear_orders()

	# **Out of foam, with a full water tank.** This is the decision the second tank
	# exists to create: the crew are not dry, they are simply out of the only thing
	# that touches this, and a hydrant will not help them.
	engine.foam = 0.0
	engine.water = 1.0
	car.intensity = 0.9
	crew.issue(ExtinguishOrder.new(car))
	var before := car.intensity
	await _wait(90)
	_check(is_equal_approx(car.intensity, before),
		"out of foam the hose does nothing to a car (%.2f -> %.2f)"
		% [before, car.intensity])
	crew.clear_orders()

	# An officer's dry powder is genuinely multi-class, so they keep the fires they
	# always had. Without this the change would have quietly taken work away from police.
	await _place_unit(officer, spot + Vector3(-2.0, 0.0, 0.0))
	officer.issue(ExtinguishOrder.new(car))
	before = car.intensity
	await _wait(90)
	_check(car.intensity < before - 0.01,
		"but an officer's powder still takes it (%.2f -> %.2f)"
		% [before, car.intensity])
	# On a fire that *wants* foam, an officer still sprays the powder they carry -- the
	# jet follows the tool, not the target.
	_check(officer.get_node_or_null("FoamJet") == null,
		"and it is still powder, on a fire that wanted foam")
	officer.clear_orders()

	# The inversion: the one fire the appliance cannot fight and the patrol car can.
	var elec := _spawn_fire(spot + Vector3(0.0, 0.0, 14.0), 0.7)
	elec.kind = Fire.Kind.ELECTRICAL
	elec.growth_per_second = 0.0
	engine.water = 1.0
	engine.foam = 1.0
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 14.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 14.0))
	crew.issue(ExtinguishOrder.new(elec))
	before = elec.intensity
	await _wait(90)
	# **Guarded, because a fire that goes out frees itself.** Reading `.intensity` on a
	# freed incident raises, and a runtime error in this suite does not fail a check --
	# it abandons the rest of the test. A sabotage run proved it: five checks stopped
	# running and the suite reported green at 698. Being freed is itself the failure
	# here, so it is folded into the assertion rather than guarded around.
	var still_burning := is_instance_valid(elec)
	_check(still_burning and is_equal_approx(elec.intensity, before),
		"a full appliance does nothing to live electrics (%.2f -> %s)"
		% [before, "%.2f" % elec.intensity if still_burning else "put out"])
	crew.clear_orders()

	await _place_unit(officer, spot + Vector3(-2.0, 0.0, 14.0))
	officer.issue(ExtinguishOrder.new(elec))
	before = elec.intensity
	await _wait(90)
	# Out entirely is the best possible version of "took it", so a freed fire passes.
	var left := elec.intensity if is_instance_valid(elec) else 0.0
	_check(left < before - 0.01,
		"and the patrol car is the right answer to it (%.2f -> %.2f)" % [before, left])
	# **What comes out of the nozzle belongs to whoever is holding it.** Powder borrowed
	# the water jet at first, so an officer on an electrical fire was drawn spraying the
	# one substance the call exists to rule out. And the agent passed to the jet was the
	# fire's rather than the unit's, so an officer on a bin fire hosed water they do not
	# carry -- pinned below, because that one is silent rather than absurd.
	var powder := officer.get_node_or_null("PowderJet") as GPUParticles3D
	_check(powder != null and powder.emitting,
		"and it is powder coming out of the officer, not water")
	officer.clear_orders()

	# Said out loud on the call row, or none of the above is discoverable.
	_check("foam" in car.describe_state() and "powder" in elec.describe_state(),
		"the board says what each wants (%s / %s)"
		% [car.describe_state(), elec.describe_state()])

	# **A hydrant is a water main.** Water comes back at the kerb; foam only at home,
	# which is what makes a shift of car fires a reason to drive back.
	var hydrant := get_nodes_in_group(Hydrant.GROUP).front() as Node3D
	if hydrant != null:
		engine.water = 0.2
		engine.foam = 0.2
		await _place_unit(engine, hydrant.global_position + Vector3(1.5, 0.2, 0.0))
		engine.velocity = Vector3.ZERO
		await _wait(90)
		_check(engine.water > 0.25, "a hydrant puts water back (%.2f)" % engine.water)
		_check(is_equal_approx(engine.foam, 0.2),
			"and no foam at all (%.2f)" % engine.foam)
	else:
		_check(false, "a hydrant on the map to park beside")

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	_dissolve(officer, &"officer")
	await _idle(4)



## Someone pinned needs two services, and in an order.
func _test_a_trapped_casualty_needs_cutting_free_first() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"paramedic", 1)
	_buy(&"ambulance", 1)
	var crew := _station.dispatch(&"firefighter") as Person
	var medic := _station.dispatch(&"paramedic") as Person
	var ambulance := _station.dispatch(&"ambulance") as Vehicle
	if crew == null or medic == null or ambulance == null:
		_check(false, "a crew, a paramedic and an ambulance to send")
		return
	# Away from (20, -20), which the fire-service tests stage their own appliance at.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var casualty := _spawn_casualty(spot)
	casualty.trapped = true
	casualty.decline_per_second = 0.0
	await _place_unit(ambulance, spot + Vector3(8.0, 0.2, 0.0))
	await _place_unit(medic, spot + Vector3(2.0, 0.0, 0.0))
	await _place_unit(crew, spot + Vector3(-2.0, 0.0, 0.0))
	await _idle(6)

	# **Where it is, not merely that it exists.** The first version asserted only that a
	# Pin node had been created, and was perfectly happy with a four-metre pipe whose
	# origin is at one end -- which laid the whole length beside the casualty with one
	# end on their shins. A prop lying *next to* someone satisfies "there is something
	# lying on them" if nobody checks the geometry.
	var pin := casualty.get_node_or_null("Pin") as Node3D
	var over := INF
	if pin:
		var mesh := _first_mesh(pin)
		if mesh and mesh.mesh:
			var centre: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_center()
			var offset := centre - casualty.global_position
			offset.y = 0.0
			over = offset.length()
	_check(pin != null and over < 0.6,
		"there is something visibly lying on them (%.2fm off centre)" % over)
	_check(_find_ability(crew, &"free") != null
			and _find_ability(medic, &"free") == null,
		"a firefighter is offered Free and a paramedic is not")
	# **The gate that makes it a sequence.** A paramedic can treat them where they lie --
	# that is the whole reason arriving first is not wasted -- but nothing can lift them.
	casualty.treat(1.0)
	await _idle(4)
	_check(casualty.is_stable, "a paramedic can still treat someone who is pinned")
	var at_them := Target.new()
	at_them.position = casualty.global_position
	at_them.collider = casualty
	at_them.incident = casualty
	_check(_find_ability(medic, &"collect") != null
			and _find_ability(medic, &"collect").score(medic, at_them)
				== Ability.NOT_APPLICABLE,
		"but Collect declines a trapped casualty, so a right-click is a Move")

	# The crew do their half.
	crew.issue(FreeOrder.new(casualty))
	var before := casualty.release
	await _wait(120)
	_check(casualty.release > before, "a firefighter shifts the weight (%.2f from %.2f)"
		% [casualty.release, before])
	for i in 30:
		await _wait(20)
		if not casualty.trapped:
			break
	_check(not casualty.trapped, "and gets them out (release %.2f)" % casualty.release)
	_check(casualty.get_node_or_null("Pin") == null, "the load comes off with them")
	crew.clear_orders()

	# And only then is the ambulance any use.
	await _idle(6)
	_check(_find_ability(medic, &"collect").score(medic, at_them) > 0,
		"now the stretcher run is on")

	await _clear_incidents()
	_dissolve(crew, &"firefighter")
	_dissolve(medic, &"paramedic")
	_dissolve(ambulance, &"ambulance")
	_dissolve(_station.dispatch(&"engine") as Unit, &"engine")
	await _idle(4)


## The shed load shuts the street three ways, and each has its own witness: the board
## reads it as a scene hazard, the traffic-facing cordon stands raised without cones,
## and a vehicle's own road_is_blocked sees it -- which is what buys the reroute.
## A collision leaves a written-off car, and only the recovery truck can shift it.
##
## **The first incident that outlives its casualties.** Every other call in this game ends
## when the last body leaves; this one keeps the street shut afterwards, which is the
## whole reason to own a truck. So the check is in three parts: the RTC leaves a wreck,
## the wreck is offered to the winch and refused to everything else, and clearing it
## actually resolves.
## Armed response: the first unit whose verbs come from its speciality, not its service.
##
## **Driven entirely through `resolve()`.** Every check written for the wreck earlier today
## built its ability by hand and passed while the feature did not work at all -- the unit
## did not carry the verb, so a right-click meant Move. So this asks the officers what a
## right-click actually resolves to, which is the only question the player asks.
func _test_armed_response_disarms_before_anyone_arrests() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_buy(&"arv", 1)
	var arv := _station.dispatch(&"arv") as Person
	if arv == null:
		_check(false, "an armed response officer to send")
		_stand_to()
		return
	_check(arv.service == Unit.Service.POLICE and arv.speciality == Person.ARMED,
		"the ARV is police with an 'armed' speciality (%d/'%s')"
		% [arv.service, arv.speciality])

	# **Dressed.** The SWAT materials live on the pack's prefabs, not in the FBX this
	# character is built from, so inheriting them got nothing and the officer turned out
	# plain white. Asked of the mesh rather than the file, because the file looked fine.
	var dressed := 0
	var meshes := 0
	for node in arv.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		meshes += 1
		if mesh.get_active_material(0) != null:
			dressed += 1
	_check(meshes > 0 and dressed == meshes,
		"and is wearing something (%d of %d meshes have a material)" % [dressed, meshes])

	# **Stands still.** The weapon prefabs ship wrapped in a StaticBody3D, and a collider
	# parented inside the officer and teleported onto the hand each frame shoves its own
	# carrier: this drifted 19m in six seconds with zero velocity and no orders.
	await _idle(6)
	var stood := arv.global_position
	await _idle(120)
	_check(arv.global_position.distance_to(stood) < 0.25,
		"and stands still when idle (%.2fm in two seconds)"
		% arv.global_position.distance_to(stood))

	_director._rng.seed = 7
	_director.open_kind(&"armed_suspect")
	await _idle(10)
	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	if suspects.is_empty():
		_check(false, "an armed suspect on the map")
		_dissolve(arv, &"arv")
		_stand_to()
		return
	var suspect := suspects[0] as Suspect
	_check(suspect.armed, "the call puts a weapon in their hands")
	await _idle(6)
	var pistol := suspect.get_node_or_null("HeldWeapon") as Node3D
	_check(pistol != null and pistol.visible,
		"and the weapon is visible on them -- which is how the player tells them apart")

	var target := Target.new()
	target.position = suspect.global_position
	target.incident = suspect
	# **Both sides.** An ARV that is never offered Disarm and an ordinary officer who is
	# offered an arrest are equally wrong, and checking one would pass on a verb that
	# answered the same way to everybody.
	_check(_officer.resolve(target) is not ApprehendAbility,
		"an ordinary officer is not offered the arrest (%s)"
		% _resolved_id(_officer, target))
	_check(arv.resolve(target) is DisarmAbility,
		"armed response is offered Disarm (%s)" % _resolved_id(arv, target))
	# **And an ordinary officer cannot disarm them either**, which is the leg the two above
	# leave open. Drop `Person.ARMED` from `DisarmAbility.score()` and a constable resolves
	# to Disarm: the arrest leg still reads "not an arrest", both legs stay green, and the
	# speciality gate -- the entire reason this unit exists -- is unguarded. What the
	# right-click has to mean is Move, which is `ApprehendAbility`'s own documented claim
	# and was equally unwatched.
	_check(_officer.resolve(target) is MoveAbility,
		"and for them a right-click means Move, not Disarm (%s)"
		% _resolved_id(_officer, target))

	# Talk them down, then the arrest is anybody's -- which is the point of the unit.
	await _place_unit(arv, suspect.global_position + Vector3(3.0, 0.0, 0.0))
	arv.issue(arv.resolve(target).make_order(arv, target))
	var down := false
	# **Sampled while the work is happening, not after it.** The pose belongs to the order,
	# so it is gone the moment the order finishes -- reading it afterwards finds `Idle` and
	# says nothing about what the player saw.
	var posed := ""
	var player := arv.get_node_or_null("Character/AnimationPlayer") as AnimationPlayer
	for i in 600:
		await physics_frame
		if suspect.disarmed > 0.0 and posed.is_empty() and player:
			posed = str(player.current_animation)
		if not suspect.armed:
			down = true
			break
	_check(down, "and talks the weapon down (%.2f)" % suspect.disarmed)
	# **The pose while they work.** The library has six pistol clips and no rifle ones,
	# which is why the ARV carries a pistol: the walk in is the ordinary locomotion with
	# the gun in hand, and `Pistol_Idle` is the one pose drawn for standing off somebody
	# with a weapon up. It used to hold the extinguisher's torch pose instead.
	_check(posed == "Pistol_Idle",
		"holding the weapon on them while they do it ('%s')" % posed)
	await _idle(6)
	_check(pistol == null or not pistol.visible,
		"the weapon leaves their hand when they give it up")
	_check(arv.get_node_or_null("HeldWeapon") != null,
		"and armed response is carrying one of its own")
	_check(_officer.resolve(target) is ApprehendAbility,
		"after which an ordinary officer can make the arrest (%s)"
		% _resolved_id(_officer, target))

	_dissolve(arv, &"arv")
	await _idle(2)
	await _clear_calls()
	_stand_to()


## A collision reads as a road job for as long as the road is shut.
##
## Two faults, both from [Wreck] having been added last and having been given no arm in
## either place. `Call._recentre()` branched on Fire / Hazard / Debris / Casualty /
## Suspect / MissingChild, so once the casualties had been delivered and only the car was
## left the call **retyped itself MEDICAL and wore a cross** -- over a vehicle nobody was
## hurt in. And `Call.describe()` counted every incident class except this one, so at a
## mixed scene the board's second column said nothing about the lane being shut.
##
## The `_recentre` half is the [Debris] lesson for the third time; the comment on that arm
## records it having shipped twice already.
func _test_a_collision_reads_as_a_road_job_to_the_end() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_buy(&"truck", 1)
	_director._rng.seed = 21
	_director._spawn_rtc(Vector2i(2, 2))
	await _idle(8)

	var calls := get_nodes_in_group(Call.GROUP)
	var job: Call = null
	for node in calls:
		var candidate := node as Call
		if candidate and candidate.is_open():
			job = candidate
	if job == null:
		_check(false, "the collision opened a call (%d)" % calls.size())
		_stand_to()
		return

	# The board, while the casualties and the car are all still there.
	var said := job.describe()
	_check("blocked lane" in said, "the board says the lane is shut (\"%s\")" % said)

	# Now work the bodies away and leave only the car, which is the state that used to
	# retype the whole job. Finished directly rather than driven: the journey is proved
	# elsewhere and what is under test here is what the call calls itself afterwards.
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty:
			casualty._finish(true)
	await _idle(10)

	var wrecks := get_nodes_in_group(Wreck.WRECK_GROUP).size()
	_check(wrecks == 1 and job.is_open(),
		"the car is still there and the call is still open (%d wrecks, open %s)"
		% [wrecks, job.is_open()])
	_check(job.kind != Call.Kind.MEDICAL,
		"and it has not turned into a medical job (%d)" % job.kind)
	_check(job.kind == Call.Kind.FIRE,
		"-- it reads as a scene hazard, the way a shed load does (%d)" % job.kind)

	for node in get_nodes_in_group(Wreck.WRECK_GROUP):
		var leftover := node as Wreck
		if leftover:
			leftover._finish(true)
	await _idle(4)
	_station.owned[&"truck"] = maxi(0, int(_station.owned.get(&"truck", 0)) - 1)
	_station._save_career()
	_station.roster_changed.emit()
	await _clear_calls()
	_stand_to()


## Every gate the director filters on has something to say on the spawner's button.
##
## **The file it guards claimed this was already impossible.** `CallSpawner._build()` used
## to carry a hand-written `if`/`elif` over two gate keys under a comment promising that a
## third "cannot be added there and quietly forgotten here" -- and `needs_arv` had been
## added to [constant Director.KINDS] and forgotten there, so the armed-suspect button
## printed no note. A promise in a comment is not a mechanism.
##
## The keys are read off `KINDS` itself. A hand-written second list here would compare two
## lists to each other and nothing to the code, which is the shape this check exists to
## replace.
func _test_every_call_gate_has_a_caption() -> void:
	var keys := {}
	for row: Dictionary in Director.KINDS:
		for key in row:
			if String(key).begins_with("needs_"):
				keys[key] = true
	var missing := PackedStringArray()
	for key in keys:
		if not CallSpawner.GATE_CAPTIONS.has(key):
			missing.append(String(key))
	# Two-sided: a key-matching bug that finds nothing would pass an empty comparison.
	_check(keys.size() >= 3,
		"%d gate keys are in use across the call table (%s)"
		% [keys.size(), ", ".join(PackedStringArray(keys.keys()))])
	_check(missing.is_empty(),
		"and every one of them has a caption on the spawner (%s)"
		% ("none missing" if missing.is_empty() else ", ".join(missing)))


## A career with no winch is not handed a car it cannot move.
##
## **The collision used to be a trap.** `rtc` is ungated at weight 15 -- 30 in the rain,
## the second-heaviest row in the table -- and it always dropped a [Wreck], which only a
## unit with `can_tow` can clear. That is the £700 recovery truck and nothing else. So a
## career that had not bought one drew collisions it could never close, and the only thing
## that ended them was [member Director.overrun_grace] counting them **failed** ninety
## seconds later. The player was being punished for a purchase they had not made.
##
## Two-sided, and the second half is the one that earns it: asserting "no wreck" alone
## passes just as well on a spawner that returned early and put out no casualties either,
## which would be a worse bug than the one being fixed.
func _test_a_career_with_no_truck_gets_no_wreck() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_check(not _station.owns(&"truck"),
		"the fixture career owns no recovery truck (%d)"
		% int(_station.owned.get(&"truck", 0)))

	_director._rng.seed = 21
	_director._spawn_rtc(Vector2i(2, 2))
	await _idle(6)
	var wrecks := get_nodes_in_group(Wreck.WRECK_GROUP).size()
	var hurt := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(wrecks == 0, "no car is left in the road for it to fail to move (%d)" % wrecks)
	_check(hurt == 2,
		"but the collision still happens -- two casualties are down (%d)" % hurt)

	# And the other half of the rule, so this cannot pass on a spawner that simply stopped
	# making wrecks at all.
	await _clear_calls()
	_buy(&"truck", 1)
	_director._rng.seed = 21
	_director._spawn_rtc(Vector2i(2, 2))
	await _idle(6)
	var after := get_nodes_in_group(Wreck.WRECK_GROUP).size()
	_check(after == 1, "buying the winch brings the car back (%d)" % after)

	_station.owned[&"truck"] = maxi(0, int(_station.owned.get(&"truck", 0)) - 1)
	_station._save_career()
	_station.roster_changed.emit()
	await _clear_calls()
	_stand_to()


func _test_a_collision_leaves_a_wreck_for_the_truck() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	# **Bought before the collision, not after.** A career with no winch is no longer given
	# a car it cannot move (`Director._leaves_a_wreck`), so the purchase has to precede the
	# spawn or there is nothing here to test. The truckless half of that rule is asserted
	# separately, in `_test_a_career_with_no_truck_gets_no_wreck`.
	_buy(&"truck", 1)
	_director._rng.seed = 21
	_director._spawn_rtc(Vector2i(2, 2))
	await _idle(6)

	var wrecks := get_nodes_in_group(Wreck.WRECK_GROUP)
	if wrecks.size() != 1:
		_check(false, "a wreck left at the collision (%d)" % wrecks.size())
		_stand_to()
		return
	var wreck := wrecks[0] as Wreck
	# **Nobody is under the car.** Reported from play: the casualties were placed 2.2m and
	# 2.5m from the junction centre and the wreck sat on the centre inside a 5.5m blocker,
	# so they spawned beneath it and could not be reached. Asserted against the wreck's own
	# published clearance rather than a number copied here, so moving one moves both.
	var trapped := PackedStringArray()
	var nearest := 999.0
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty == null:
			continue
		var gap := _flat_distance(casualty.global_position, wreck.global_position)
		nearest = minf(nearest, gap)
		if gap < Wreck.CLEAR_RADIUS:
			trapped.append("%.1fm" % gap)
	_check(trapped.is_empty(),
		"no casualty is trapped under the car (nearest %.1fm, needs %.1f)"
		% [nearest, Wreck.CLEAR_RADIUS])

	var cordon := wreck.get_node_or_null("Cordon") as Cordon
	_check(cordon != null and cordon.raised,
		"a raised cordon turns the traffic away from it")
	_check(wreck.get_node_or_null("Blocker") != null,
		"and something solid is actually in the road")

	# **The winch is the gate.** Both sides asserted: a truck that is never offered the
	# job and a patrol car that is offered it are equally wrong, and only checking one
	# would pass on an ability that answered the same way to everybody.
	var target := Target.new()
	target.position = wreck.global_position
	target.incident = wreck
	var truck := _station.dispatch(&"truck") as Vehicle
	if truck == null:
		_check(false, "a recovery truck to send")
		_stand_to()
		return
	_check(truck.can_tow, "the recovery truck carries a winch")

	# **Asked of the truck's own verbs, not of a hand-built ability.** Every check here
	# used to construct `ClearAbility.new()` and score it -- which passed while the truck
	# did not carry the verb at all, so a right-click on a wreck resolved to Move and it
	# drove over and lifted nothing. Reported from play, invisible to the suite.
	var clear: Ability = null
	for ability in truck.abilities():
		if ability is ClearAbility:
			clear = ability
	_check(clear != null, "and the verb to use it with (%d verbs)" % truck.abilities().size())
	_check(truck.resolve(target) is ClearAbility,
		"so right-clicking a wreck means Clear, not Move (%s)"
		% _resolved_id(truck, target))
	var car_clear := false
	for ability in _car.abilities():
		if ability is ClearAbility:
			car_clear = true
	_check(not car_clear, "a patrol car has no winch, so it is never offered the job")

	# **The truck actually drives there and winches it.** The first cut of this called
	# `wreck.clear(1.0)` directly and passed -- while the feature did not work at all: the
	# truck did not carry the ability, so a right-click resolved to Move and it drove over,
	# stopped, and lifted nothing. A check that reaches past the interface tests the
	# incident and vouches for the game.
	#
	# Started 20m out rather than from the forecourt, because the point here is the last
	# few metres and the approach -- a 55m drive would cost the suite twenty seconds to
	# re-prove the autopilot.
	truck.global_position = wreck.global_position + Vector3(0.0, 0.0, 20.0)
	truck.velocity = Vector3.ZERO
	await _idle(20)
	truck.issue(truck.resolve(target).make_order(truck, target))
	await _idle(2)

	# **Where the order aims, not where the truck ends up.** Sabotaging
	# `WorkOrder.VEHICLE_STANDOFF` to 0 -- reinstating the shipped bug in full -- left every
	# other leg of this check green: aimed at the centre the truck wedges against the
	# blocker at 5.36m, which is still inside `ClearOrder.VEHICLE_REACH` (8.0), so it
	# winches anyway and marginally sooner. The standoff and the reach are competing
	# satisfiers for "ends up in working range", and only the reach was being measured.
	# Note the direction: zeroing the standoff moves the truck *closer*, so no bound on the
	# resting distance can catch it. The aim point is the only place the fault is visible.
	var blocker := wreck.get_node_or_null("Blocker/BlockerShape") as CollisionShape3D
	var box := blocker.shape as BoxShape3D if blocker else null
	# The inscribed radius of a square blocker: the least distance that is certainly
	# outside it. The blocker is 5.5m square, so this is 2.75 -- and the standoff is 3.4,
	# which clears it on an axis-aligned approach and *would not* on a perfect diagonal
	# (the corner is 3.89 out). Harmless today because the road grid is axis-aligned and
	# the truck arrives along a street, but it is the constant to revisit if a wreck is
	# ever laid on a junction diagonal.
	var clearance: float = minf(box.size.x, box.size.z) * 0.5 if box else 2.75
	var aim := truck.move_target
	aim.y = wreck.global_position.y
	var aimed := aim.distance_to(wreck.global_position)
	_check(aimed >= clearance,
		"the order aims the truck outside the blocker, not at the wreck (%.2fm, needs %.2f)"
		% [aimed, clearance])

	# **What the job is worth, captured before it is done.** Asserted as a *delta* rather
	# than against an absolute: the tallies carry state from every check that ran earlier,
	# and pinning a total would redden this the next time anything else scored.
	var cleared_before := _mission.wrecks_cleared
	var worth_before := _mission.shout_score()

	var towed := false
	for i in 900:
		await physics_frame
		if not is_instance_valid(wreck):
			towed = true
			break
	_check(towed, "the truck drives to it and winches it away")
	_check(get_nodes_in_group(Wreck.WRECK_GROUP).is_empty(),
		"and nothing of it is left in the road")

	# **And it pays.** This scored and banked nothing at all until August 2026 -- the
	# chain in `Mission._on_resolved` tests `is Debris`, and a [Wreck] extends [Incident]
	# directly, so it matched no arm and fell out of the scoring silently. The one job the
	# £700 truck exists for was unpaid, which is a poor argument for buying one.
	_check(_mission.wrecks_cleared == cleared_before + 1,
		"the recovery is counted (%d, was %d)"
		% [_mission.wrecks_cleared, cleared_before])
	_check(_mission.shout_score() == worth_before + Mission.WRECK_POINTS,
		"and worth %d points (%d, was %d)"
		% [Mission.WRECK_POINTS, _mission.shout_score(), worth_before])

	_dissolve(truck, &"truck")
	await _idle(2)
	await _clear_calls()
	_stand_to()


func _test_a_shed_load_shuts_the_street() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 13
	_director._spawn_shed_load()
	await _idle(6)

	var piles := get_nodes_in_group(Debris.DEBRIS_GROUP)
	if piles.size() != 1:
		_check(false, "a shed load on the map (%d)" % piles.size())
		_stand_to()
		return
	var debris := piles[0] as Debris
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].kind == Call.Kind.FIRE,
		"the board reads it as a scene hazard, not a medical call")
	_check(not open.is_empty() and open[0].title() == "Shed load blocking the road",
		"and names the job ('%s')" % (open[0].title() if not open.is_empty() else "no call"))
	var cordon := debris.get_node_or_null("Cordon") as Cordon
	_check(cordon != null and cordon.raised and cordon.get_child_count() == 0,
		"a raised cordon turns the traffic, with no cones -- the boxes are the visual")

	# The player's own routing sees it too. Pure cone math, so the street's axis does
	# not matter: the car sits 10m one side of the pile, the aim 10m past the other.
	var spot := debris.global_position
	await _place_unit(_car, spot + Vector3(10.0, 0.2, 0.0))
	var aim := spot - Vector3(10.0, 0.0, 0.0)
	_check(_car.road_is_blocked(aim), "a vehicle aimed past it reads the street as blocked")
	debris.clear(2.0)
	await _idle(6)
	_check(not _car.road_is_blocked(aim), "and clear again once the load is shifted")
	_stand_to()
	await _clear_calls()


## The Clear verb: both boots-on-the-ground services carry it, the medical service does
## not, and working it reopens the street and pays like a disaster prevented.
func _test_a_crew_clears_a_shed_load() -> void:
	await _clear_calls()
	await _park_the_shift()
	_buy(&"firefighter", 1)
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to send")
		return
	_mission.begin_scoring()
	_director._rng.seed = 21
	_director._spawn_shed_load()
	await _idle(6)

	var piles := get_nodes_in_group(Debris.DEBRIS_GROUP)
	if piles.size() != 1:
		_check(false, "a shed load on the map (%d)" % piles.size())
		_dissolve(crew, &"firefighter")
		await _end_freeplay()
		return
	var debris := piles[0] as Debris
	var target := _target_for(debris)
	_check(_find_ability(_officer, &"clear") != null
			and _find_ability(_officer, &"clear").score(_officer, target) > 0,
		"an officer is offered Clear on a shed load")
	_check(_find_ability(crew, &"clear") != null
			and _find_ability(crew, &"clear").score(crew, target) > 0,
		"and so is a firefighter -- box-lugging is not specialist work")
	_check(_find_ability(_paramedic, &"clear") == null,
		"a paramedic is not")
	var verb := _officer.resolve(target)
	_check(verb != null and verb.id() == &"clear",
		"right-clicking the load with an officer means Clear (got '%s')"
		% ("none" if verb == null else verb.id()))
	if verb == null:
		_dissolve(crew, &"firefighter")
		await _end_freeplay()
		return

	# The work. Sped up so the check measures the loop, not seven seconds of lugging.
	debris.clear_per_second = 0.9
	await _place_unit(_officer, debris.global_position + Vector3(4.0, 0.0, 0.0))
	_officer.issue(verb.make_order(_officer, target))
	var opened := false
	for i in 600:
		await physics_frame
		if not is_instance_valid(debris) or not debris.active:
			opened = true
			break
	_check(opened, "the officer works the load off the road")
	await _idle(8)
	_check(_board.open_calls().is_empty(), "the call closes with the street")
	_check(_mission.lanes_cleared == 1,
		"the debrief counts it (%d)" % _mission.lanes_cleared)
	# **Exact, not a floor.** The response bonus alone is 100, so a `>= 60` bound stayed
	# green with the whole Debris scoring arm deleted -- measured, via the sabotage run.
	# The disturbance test's equality is the precedent: scoring began at zero, the
	# officer is standing at the scene, so the sum is deterministic.
	_check(_mission.score == Mission.DEBRIS_POINTS + Mission.RESPONSE_BONUS,
		"scored like a disaster prevented plus the response bonus (%d, expected %d)"
		% [_mission.score, Mission.DEBRIS_POINTS + Mission.RESPONSE_BONUS])
	# A consistency assertion: deleting score and pay together keeps it green by
	# construction (both sides move). Its sabotage is dropping `_pay` alone, which
	# reddened it in isolation.
	_check(_mission.earned == _mission.score,
		"an obstruction pays what it scores (£%d)" % _mission.earned)
	_dissolve(crew, &"firefighter")
	await _end_freeplay()


## The dev call spawner: inert until asked, and it asks the director rather than placing
## anything itself.
func _test_calls_can_be_spawned_on_demand() -> void:
	await _clear_incidents()
	var spawner := _scene.get_node_or_null("CallSpawner") as CallSpawner
	if spawner == null:
		_check(false, "the map carries a call spawner")
		return
	_check(true, "the map carries a call spawner")
	# **Inert until a key is pressed.** The map ships quiet on purpose and a director that
	# could start on its own breaks dozens of checks at once; this builds nothing, watches
	# nothing and spawns nothing until asked.
	var built := 0
	for child in spawner.get_children():
		if child is CanvasLayer:
			built += 1
	_check(built == 0, "and has built nothing before it is opened")

	await _press_key(KEY_F5)
	await _idle(4)
	var layer: CanvasLayer = null
	for child in spawner.get_children():
		if child is CanvasLayer:
			layer = child
	_check(layer != null and layer.visible, "F5 opens it")
	# Built from the director's own table, so a call kind added there cannot go missing
	# from the tool because somebody forgot to list it twice. The +4 is the weather
	# preview strip, counted separately below.
	var buttons := 0
	var weather_row: HBoxContainer = null
	for node in _descendants(layer):
		if node is Button:
			buttons += 1
		if node.name == "WeatherRow":
			weather_row = node
	_check(buttons == _director.KINDS.size() + 4,
		"with a row for every call the director knows (%d of %d + 4 weather)"
		% [buttons, _director.KINDS.size()])
	_check(weather_row != null and weather_row.get_child_count() == 4,
		"and a weather preview strip with all four skies")

	# The preview drives the sky directly and leaves the settings card's stored choice
	# alone -- a dev tool must not rewrite what the player chose.
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	var kept_choice := _menu.wet_weather
	spawner.preview_weather(Daylight.Weather.FOG)
	_check(daylight != null and daylight.weather == Daylight.Weather.FOG,
		"pressing a sky previews it on the district")
	_check(_menu.wet_weather == kept_choice,
		"without touching the settings card's own choice")
	spawner.preview_weather(Daylight.Weather.CLEAR)
	_check(daylight != null and daylight.weather == Daylight.Weather.CLEAR,
		"and CLEAR puts the map back as generated")

	await _press_key(KEY_F5)
	await _idle(2)

	# And it actually opens one. Asked for by name, through the director.
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	spawner.spawn_call(&"trapped")
	await _idle(8)
	var pinned := 0
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty and casualty.trapped:
			pinned += 1
	_check(pinned > 0, "and asking for a trapped casualty produces one (%d)" % pinned)

	await _clear_incidents()
	await _idle(4)


## A cylinder made safe closes its call. This is the check that was missing.
func _test_a_cylinder_made_safe_finishes_the_job() -> void:
	await _clear_incidents()
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	var fire := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 0.8)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	var outcome: Array = []
	hazard.resolved.connect(func(_incident: Incident, success: bool) -> void:
		outcome.append(success))
	await _wait(60)
	_check(hazard.active and hazard.heat > 0.0,
		"a cylinder beside a fire is a live job (%.2f)" % hazard.heat)

	# Put the fire out and take the heat off: the two ways it is beaten, together.
	fire.douse(5.0)
	hazard.cool(2.0)
	await _wait(60)
	# **The exit that did not exist.** `_finish(false)` on the blast was the only way out
	# of this incident until August 2026, so a gas leak beaten perfectly stayed on the
	# board for ever, the shift could not end, and HAZARD_POINTS was unreachable. Three
	# checks covered the hazard and every one tested a mechanism -- heats, cools, goes
	# bang -- and none asked whether the job could be finished.
	_check(outcome == [true],
		"cooled, with the fire out, it counts as made safe (%s)" % [outcome])
	_check(not is_instance_valid(hazard) or not hazard.active,
		"and the job is closed")
	await _clear_incidents()
	await _idle(4)


## A crowd turns unless somebody stands in it.
func _test_a_disorder_call_grows_until_it_is_contained() -> void:
	await _clear_incidents()
	_buy(&"officer", 1)
	var officer := _station.dispatch(&"officer") as Person
	if officer == null:
		_check(false, "an officer to send")
		return
	var spot := Vector3(-60.0, 0.0, 60.0)
	# Parked far enough away that the officer is not containing it by accident.
	await _place_unit(officer, spot + Vector3(40.0, 0.0, 0.0))

	var ringleader := _spawn_suspect(spot)
	ringleader.recruits = true
	# **Room to grow throughout.** The first cut capped this at 3, and the group hit the
	# cap during the first phase -- after which `_update_recruiting` returns at
	# `_group_size() >= max_group` *before* it ever asks `_is_contained()`. Both
	# containment checks then passed no matter what containment did, because the count
	# they watch could not move either way. The assertions were sound; the scenario was
	# saturated, which is a third way for a check to be worthless and the hardest to see.
	ringleader.max_group = 12
	ringleader.recruit_interval = 0.5
	ringleader.recruit_distance = 8.0
	# A bystander to draw in. Taken from the crowd rather than conjured, which is what
	# the mechanism itself does -- the person who joins in is somebody who was there.
	var bystander := _nearest_civilian(spot)
	if bystander == null:
		_check(false, "a bystander on the pavement to draw in")
		return
	await _place_unit(bystander, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(4)

	var before := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(90)
	var after := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	_check(after > before, "left alone it draws a bystander in (%d from %d)"
		% [after, before])

	# **And they have a body.** A civilian's `scene_file_path` is the *unit* scene, one
	# directory away from the outfit -- and `ResourceLoader.exists()` says yes to both,
	# so passing the wrong one silently gave the recruit a whole Civilian as its body,
	# script and all, which promptly walked off. The suspect was invisible; reported from
	# play, because nothing here looked at what the new arrival was wearing.
	var bodiless := 0
	var checked := 0
	for node in get_nodes_in_group(Suspect.SUSPECT_GROUP):
		var joined := node as Suspect
		if joined == null or joined == ringleader:
			continue
		checked += 1
		var body := joined.get_node_or_null("Character") as Node3D
		if body == null or not (body.scene_file_path in Incident.OUTFITS):
			bodiless += 1
	_check(checked > 0 and bodiless == 0,
		"and each of them is wearing a real outfit (%d bodiless of %d)"
		% [bodiless, checked])

	# **Containment, and the reason Secure now matters.** An officer standing in it takes
	# the heat out; so does a cordon, which until this call had no job in the game at all.
	await _place_unit(officer, spot + Vector3(3.0, 0.0, 0.0))
	await _idle(4)
	var held := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(120)
	var now := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	# The headroom is asserted alongside the result, so this can never again pass because
	# the group had simply run out of room to grow.
	_check(now == held and held < ringleader.max_group,
		"an officer standing in it stops the spread (%d, was %d, cap %d)"
		% [now, held, ringleader.max_group])

	# And the cordon does it with nobody there.
	await _place_unit(officer, spot + Vector3(40.0, 0.0, 0.0))
	var cordon := Cordon.new()
	_scene.get_node("Incidents").add_child(cordon)
	cordon.global_position = spot
	cordon.raise_cordon()
	var another := _nearest_civilian(spot)
	if another:
		await _place_unit(another, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(4)
	held = get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(120)
	now = get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	_check(now == held and held < ringleader.max_group,
		"and a cordon does it with nobody standing there (%d, was %d, cap %d)"
		% [now, held, ringleader.max_group])
	cordon.queue_free()

	# The job fits the roster rather than being withheld from it -- BUILDING_SIZE's rule.
	var sizes: Array = Director.DISORDER_SIZE
	var one: Dictionary = sizes[0]
	var many: Dictionary = sizes[sizes.size() - 1]
	_check(int(many["max_group"]) > int(one["max_group"]),
		"a bigger force gets a bigger job (%d against %d)"
		% [int(many["max_group"]), int(one["max_group"])])

	await _clear_incidents()
	_dissolve(officer, &"officer")
	await _idle(4)


## Two in the back of a patrol car, walked there one at a time.
func _test_a_patrol_car_takes_two_prisoners() -> void:
	await _clear_incidents()
	# **A kerb the director itself would open a call on**, rather than a convenient-looking
	# coordinate. The first cut of this staged at (-60, 60) -- fine for the earlier tests
	# there, which only ever needed people to *stand* -- and the officer fell through the
	# world on the first step, reaching y = -11012 while the order patiently reported
	# "Escorting". Anything that has to walk needs ground the game vouches for.
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerb to stage an arrest on")
		return
	_check(_car.cells == 2, "a patrol car has two cells (%d)" % _car.cells)
	await _place_unit(_car, spot + Vector3(10.0, 0.2, 0.0))
	await _place_unit(_officer, spot + Vector3(3.0, 0.0, 0.0))

	var first := _spawn_suspect(spot)
	var second := _spawn_suspect(spot + Vector3(2.0, 0.0, 0.0))
	first.detain(1.0)
	second.detain(1.0)
	await _idle(6)

	# One at a time, because an officer has one pair of hands. The point of the check is
	# the *second* one: with a single cell the car was full after the first, and a scene
	# with two arrests needed two cars -- which the disorder call made the normal case.
	for suspect: Suspect in [first, second]:
		var verb := _officer.resolve(_target_for(suspect))
		if verb == null or verb.id() != &"escort":
			_check(false, "an officer offered Escort for each of them (got '%s')"
				% ("none" if verb == null else verb.id()))
			return
		_officer.issue(verb.make_order(_officer, _target_for(suspect)))
		for i in 900:
			await physics_frame
			if suspect.is_loaded:
				break
	_check(first.is_loaded and second.is_loaded,
		"both are walked in and both get in (%s, %s)"
		% [first.is_loaded, second.is_loaded])
	_check(_car.suspects.size() == 2, "the car is carrying two (%d)" % _car.suspects.size())

	# And it stops at two. With nowhere left to put anybody, Escort declines and a
	# right-click falls back to Move rather than starting a walk that cannot finish.
	#
	# **Every car, not just this one.** The first cut asserted a third was declined once
	# `_car` was full, and it was offered Escort anyway -- correctly, because the suite
	# owns more than one patrol car and `nearest_vehicle` found the other one. That is
	# the game working; the check had quietly assumed a one-car world.
	_check(not _car.has_cell_space(), "and is full")
	var spare: Array[Vehicle] = []
	for node in get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other and other != _car and not (other is TrafficCar) \
				and other.service == Unit.Service.POLICE and other.cells > 0:
			spare.append(other)
			other.cells = 0
	var third := _spawn_suspect(spot + Vector3(4.0, 0.0, 0.0))
	third.detain(1.0)
	await _idle(6)
	var declined := _officer.resolve(_target_for(third))
	_check(declined != null and declined.id() == &"move",
		"with every cell full a third is declined (got '%s', %d spare cars emptied)"
		% [("none" if declined == null else declined.id()), spare.size()])
	for other in spare:
		other.cells = 2

	_officer.clear_orders()
	await _clear_incidents()
	_car.suspects.clear()
	await _idle(4)



## Your own people can be hurt, and losing one costs the career a unit.
func _test_a_crew_member_can_be_lost() -> void:
	await _clear_incidents()
	# **Two, so the count has somewhere to fall.** `available()` reads the live roster; if
	# the career owned exactly one firefighter and it went down, the count would be 0
	# before and 0 after and the check would pass without the feature existing.
	_buy(&"firefighter", 2)
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to put in harm's way")
		return
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerb to stage this on")
		return
	await _place_unit(crew, spot)
	await _idle(4)
	var owned_before := _station.total(&"firefighter")
	var spare_before := _station.available(&"firefighter")

	# A blast they are standing in.
	var hazard := _spawn_hazard(spot + Vector3(1.5, 0.0, 0.0))
	hazard.heat = 1.0
	await _idle(12)
	_check(crew.health < 1.0, "a blast hurts the crew standing in it (%.2f)" % crew.health)
	_check(crew.is_down and not crew.is_selectable(),
		"enough of it puts them down and out of the selection")
	var fallen: Casualty = null
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty and casualty.crew == crew:
			fallen = casualty
	_check(fallen != null, "and files a casualty where they fell")
	if fallen == null:
		return
	# In their own kit -- the `Civilians/` vs `Characters/` path trap, which has bitten
	# twice and is silent both times.
	var body := _first_mesh_scene(fallen)
	_check(body == crew.outfit_scene(),
		"wearing their own kit, not a stranger's (%s)" % body.get_file())
	# The unit is still on the books while they lie there, so the player cannot simply
	# dispatch a replacement -- `Station._alive()` counts group membership, and that is
	# the reason the person is not freed.
	_check(_station.available(&"firefighter") == spare_before,
		"they still count against the roster while down (%d, was %d)"
		% [_station.available(&"firefighter"), spare_before])

	# Losing them takes the unit off the books. Read everything *before* the free.
	var outcome: Array = []
	fallen.resolved.connect(func(_incident: Incident, ok: bool) -> void:
		outcome.append(ok))
	fallen.health = 0.0
	await _idle(10)
	_check(outcome == [false], "letting them die closes it as a loss (%s)" % [outcome])
	_check(_station.total(&"firefighter") == owned_before - 1,
		"and writes the unit off the books (%d, was %d)"
		% [_station.total(&"firefighter"), owned_before])
	_check(_mission.crew_lost >= 1, "the debrief counts it (%d)" % _mission.crew_lost)

	await _clear_incidents()
	await _idle(4)


## A crew member riding in a vehicle is not standing in the street.
func _test_a_passenger_is_not_caught_by_a_blast() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew to ride in it")
		return
	var spot := Vector3(-60.0, 0.0, 60.0)
	await _place_unit(engine, spot)
	crew.board(engine)
	await _idle(6)
	# An aboard person rides at the carrier's position, so without the guard a blast
	# beside the appliance would take out the crew sitting safely inside it.
	var hazard := _spawn_hazard(spot + Vector3(1.0, 0.0, 0.0))
	hazard.heat = 1.0
	await _idle(12)
	_check(is_equal_approx(crew.health, 1.0) and not crew.is_down,
		"riding in the appliance keeps them out of it (%.2f)" % crew.health)
	crew.disembark(spot + Vector3(4.0, 0.0, 0.0))
	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


## A firefighter with a hose beats it; one without cannot.
func _test_a_hose_beats_a_cylinder() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew to send")
		return
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	# **A fire burns beside it for both halves of this test.** Without one the first half
	# was vacuous: the assertion is only "cooler than it was", and the hazard's own
	# ambient shed satisfies that on its own -- the sabotage agent stubbed `cool()` out
	# entirely and the check stayed green, because two different things could satisfy it
	# and nothing distinguished them. Against a fire the cylinder is gaining heat every
	# frame, so it can only get cooler if water is landing on it.
	var cooker := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 1.0)
	cooker.growth_per_second = 0.0
	cooker.spread_threshold = 2.0
	hazard.heat = 0.6
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(10)

	_check(_find_ability(crew, &"cool") != null,
		"a firefighter is offered Cool")
	crew.issue(CoolOrder.new(hazard))
	var before := hazard.heat
	await _idle(120)
	_check(hazard.heat < before,
		"and on the hose the cylinder cools (%.2f from %.2f)" % [hazard.heat, before])

	# Away from the appliance there is no hose, and an extinguisher against a pressure
	# vessel is not a slower answer -- it is not an answer. Same fire, still cooking it.
	crew.clear_orders()
	await _place_unit(engine, spot + Vector3(60.0, 0.2, 0.0))
	hazard.heat = 0.4
	await _idle(10)
	var stranded := hazard.heat
	crew.issue(CoolOrder.new(hazard))
	await _idle(120)
	_check(hazard.heat > stranded,
		"but off it the cylinder keeps heating anyway (%.2f from %.2f)"
		% [hazard.heat, stranded])

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


func _test_fires_have_character() -> void:
	await _clear_incidents()
	var bin := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.5)
	bin.kind = Fire.Kind.BIN
	var building := _spawn_fire(Vector3(-20.0, 0.0, 20.0), 0.5)
	building.kind = Fire.Kind.BUILDING
	await _idle(4)

	_check(not bin.needs_hose and building.needs_hose,
		"a bin fire yields to anyone and a building fire does not")
	_check(bin.douse_per_second > building.douse_per_second,
		"a bin goes out faster than a building (%.2f against %.2f)"
		% [bin.douse_per_second, building.douse_per_second])
	# The threshold is put out of reach rather than a second flag being added, so this
	# reads the consequence: a bin fire can never arm its spread timer.
	_check(bin.spread_threshold > 1.0 and building.spread_threshold <= 1.0,
		"and a bin never spreads while a building does (%.1f against %.1f)"
		% [bin.spread_threshold, building.spread_threshold])
	# Different plumes, not one rescaled: the pack ships three and the small one has no
	# ground-spread emitter at all.
	var bin_fx := bin.get_node("Flames").scene_file_path
	var building_fx := building.get_node("Flames").scene_file_path
	_check(bin_fx != building_fx and "Small" in bin_fx and "Large" in building_fx,
		"each wearing its own plume (%s, %s)"
		% [bin_fx.get_file(), building_fx.get_file()])
	await _clear_incidents()


## A burning car bills what is parked beside it.
##
## The economy for this already existed -- `repair_bill`, the debrief row, the station's
## books -- and all that was missing was something other than a collision to charge for.
## What it buys is that where the appliance stops is a decision: nose-in beside a burning
## car is the convenient place to park and the expensive one.
func _test_a_car_fire_scorches_what_is_near_it() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	if engine == null:
		_check(false, "an engine to park beside it")
		return
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(2.0, 0.2, 0.0))
	engine.repair_bill = 0
	var fire := _spawn_fire(spot, 1.0)
	fire.kind = Fire.Kind.VEHICLE
	fire.growth_per_second = 0.0
	await _idle(180)
	var close := engine.repair_bill
	_check(close > 0, "parking in a car fire costs money (£%d after 3s)" % close)

	# Out of reach, and the same three seconds. Distance is the whole mechanic: a bill
	# that applied across the district would just be a tax on attending at all.
	await _place_unit(engine, spot + Vector3(14.0, 0.2, 0.0))
	engine.repair_bill = 0
	await _idle(180)
	_check(engine.repair_bill == 0,
		"and standing off it costs nothing (£%d)" % engine.repair_bill)

	await _clear_incidents()
	_dissolve(engine, &"engine")
	await _idle(4)


func _test_a_fire_looks_like_its_intensity() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 1.0)
	fire.growth_per_second = 0.0
	await _idle(4)

	# **Counted off the scene, not off `_particles`.** Reading the list the code under
	# test iterates makes "all N of N" true by construction: the sabotage pass deleted
	# the sub-emitter collection entirely and this check still passed, reading 2 of 2.
	# Walking the tree is what lets it see an emitter that `_update_flame` never reached.
	var emitters: Array[Node] = fire.find_children("*", "GPUParticles3D", true, false)
	_check(emitters.size() >= 3,
		"a fire runs the pack's emitters, sub-emitters and all (%d)" % emitters.size())
	var lit := 0
	for e in emitters:
		if (e as GPUParticles3D).emitting:
			lit += 1
	_check(lit == emitters.size(), "all of them alight (%d of %d)" % [lit, emitters.size()])

	# Read off the plume itself. There was an orange cone under these particles to be the
	# readable silhouette at RTS zoom, and this measured that; the pack's fire made it
	# redundant and it was removed, so the size of the fire is now the size of the fire.
	var big: float = (fire.get_node("Flames") as Node3D).scale.x
	fire.intensity = 0.15
	fire.call("_update_flame")
	await _idle(2)
	var small: float = (fire.get_node("Flames") as Node3D).scale.x
	_check(small < big, "a dying fire is a smaller one (%.2f against %.2f)" % [small, big])
	# Scale lives on the roots alone, because a child inherits it: setting it on both
	# squares it, and a fire at full intensity threw embers at 5.8x rather than 2.4x.
	var embers := fire.get_node_or_null("Flames/FX_Fire_Embers_01") as Node3D
	_check(embers == null or is_equal_approx(embers.scale.x, 1.0),
		"and its sub-emitters ride the root's scale rather than squaring it (%.2f)"
		% (embers.scale.x if embers else 1.0))
	var thinned := 0
	for e in emitters:
		if (e as GPUParticles3D).amount_ratio < 0.9:
			thinned += 1
	_check(thinned == emitters.size(),
		"and every emitter thins with it, not just the parent (%d of %d)"
		% [thinned, emitters.size()])

	await _clear_incidents()


func _test_the_appliance_raises_its_ladder() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a firefighter to send")
		return
	await _idle(4)

	var ladder := engine.get_node_or_null(engine.ladder_path) as Node3D
	_check(ladder != null, "the appliance carries a ladder it can raise")
	if ladder == null:
		_dissolve(engine, &"engine")
		_dissolve(crew, &"firefighter")
		return

	# Measured as the height of the ladder's far end in the vehicle's own frame, so this
	# says nothing about which axis the prefab happened to author it on.
	var tip := func() -> float:
		var box: AABB = (ladder as MeshInstance3D).get_aabb()
		var far := box.position + Vector3(box.size.x * 0.5, box.size.y * 0.5, box.size.z)
		return engine.to_local(ladder.to_global(far)).y

	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	await _idle(10)
	var stowed: float = tip.call()
	_check(engine.get("_ladder_raise") == 0.0,
		"which is stowed on an appliance doing nothing")

	var fire := _spawn_fire(spot, 0.9)
	fire.growth_per_second = 0.0
	crew.issue(ExtinguishOrder.new(fire))
	await _idle(150)
	var raised: float = tip.call()
	_check(raised > stowed + 1.0,
		"and goes up while the crew work off its tank (%.1fm to %.1fm)" % [stowed, raised])

	crew.clear_orders()
	await _idle(240)
	_check(tip.call() < stowed + 0.2,
		"and comes back down when they stop (%.1fm)" % tip.call())

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


## Fire hurts whoever stands in it — and never the crew who are fighting it.
##
## **The second assertion is the one that matters.** `ExtinguishOrder` holds a firefighter
## at `REACH` (5.0) precisely so the fire service stays playable; a harm radius at or above
## that would make every building fire a war of attrition against your own crew. So this
## does not merely check that the radius is smaller — it stands a firefighter at working
## range and watches them not be hurt, which is the property, and would fail if either
## number moved toward the other.
func _test_a_fire_burns_what_stands_in_it() -> void:
	await _clear_calls()
	var spot := ROAD + Vector3(0.0, 0.0, 26.0)
	var fire := _spawn_fire(spot, 0.9)
	await _idle(4)

	# Two firefighters bought for this, and given back at the end: the fleet the rest of
	# the suite was handed has to survive a check that stands people in a fire.
	_buy(&"firefighter", 2)
	# On the hose: at the range the order actually works from.
	var working := _dispatch_to(&"firefighter",
		spot + Vector3(ExtinguishOrder.REACH, 0.0, 0.0)) as Person
	# Standing in it: well inside the singe radius.
	var inside := _dispatch_to(&"firefighter", spot + Vector3(1.0, 0.0, 0.0)) as Person
	if working == null or inside == null:
		_check(false, "two crew to stand near the fire")
		fire.queue_free()
		await _clear_calls()
		return
	var working_health := working.health
	var inside_health := inside.health
	await _wait(90)

	_check(inside.health < inside_health - 0.05,
		"standing in a fire hurts (%.2f -> %.2f)" % [inside_health, inside.health])
	_check(is_equal_approx(working.health, working_health),
		"and a firefighter at working range is never singed (%.2f at %.1fm, radius %.1f)"
		% [working.health, ExtinguishOrder.REACH, fire.singe_range])
	_check(fire.singe_range < ExtinguishOrder.REACH,
		"the singe radius stays inside the work range (%.1f against %.1f)"
		% [fire.singe_range, ExtinguishOrder.REACH])

	_dissolve(working, &"firefighter")
	_dissolve(inside, &"firefighter")
	fire.queue_free()
	await _clear_calls()


## A fire that has got away catches an onlooker, and leaves the child alone.
func _test_a_spreading_fire_catches_an_onlooker() -> void:
	await _clear_calls()
	var spot := ROAD + Vector3(0.0, 0.0, 32.0)
	var fire := _spawn_fire(spot, 0.95)
	var shopper := (load(CIVILIAN_SCENE) as PackedScene).instantiate() as Civilian
	_scene.add_child(shopper)
	shopper.global_position = spot + Vector3(1.2, 0.0, 0.0)
	await _idle(4)
	await _wait(40)

	# **Counted as casualties at the fire, not as incidents anywhere.** The first cut
	# asserted the shopper had vanished and that the incident tally had risen; the first
	# half can be true for reasons that have nothing to do with fire (the crowd despawns,
	# something else frees them) and the second counts the fire itself, so a conversion
	# and an unrelated resolution cancel out. Neither said what this check is named for.
	var caught := 0
	for node in get_nodes_in_group(Incident.GROUP):
		var casualty := node as Casualty
		if casualty and _flat_distance(casualty.global_position, spot) < 4.0:
			caught += 1
	_check(not is_instance_valid(shopper) or shopper.is_queued_for_deletion(),
		"a bystander inside a fire that has got away is caught")
	_check(caught >= 1, "and becomes a casualty at the fire (%d found)" % caught)

	for node in get_nodes_in_group(Incident.GROUP):
		node.free()
	await _clear_calls()


## Connecting to a hydrant: the tank stops draining, and driving off takes the line with it.
##
## **Asserted on the tank, not on the flag.** `is_on_main()` returning true proves the
## appliance thinks it is connected; only watching `draw_water` fail to bite proves the
## connection is worth having. The second half matters as much: a line that survived the
## engine driving away would be an infinite tank with extra steps.
## The helicopter: it climbs, it flies straight over everything, and it will not be put
## down on a building.
##
## **The landing rule is the assertion that matters.** "Clear land, not properties" is
## `CityGrid.standable()` — the same line the crowd walks on — so this checks the verb
## refuses a point inside a block *and* accepts one on the road, because a rule that
## refuses everything would pass a one-sided check.
## Only the vehicles meant to carry prisoners have anywhere to put one.
##
## **A cell arrived by default and nobody noticed.** `build_vehicles` set
## `root.cells = int(config.get("cells", 1))`, so a catalogue row that simply did not
## mention cells got one -- and because a `.tscn` stores only what differs from the
## script's own default, the resulting scene file *looked* correct by saying nothing. The
## ambulance, the fire engine and the recovery truck each carried a phantom cell. Two were
## inert, since [LoadSuspectAbility] gates on POLICE service, but the recovery truck is
## police: a prisoner could be put in a tow truck.
##
## It survived because every arrest check in this suite uses a patrol car or a van, which
## declare their own cell counts and were therefore always right. **A default is only
## exercised by the cases that say nothing**, and those are the ones nobody writes a check
## for. Found by mapping the catalogue onto a new shop UI, which printed "1 cells" beside
## a tow truck.
##
## Asserted as a table rather than a rule, because both directions matter: a van that
## quietly lost its six cells is as wrong as a truck that gained one.
func _test_only_prisoner_carriers_have_cells() -> void:
	# The interceptor gave up a cell for its speed in August 2026: a pursuit car that also
	# held as many prisoners as the £600 patrol car was strictly better than it, which is
	# not a choice the player gets to make.
	const EXPECTED := {
		&"patrol": 2, &"van": 6, &"interceptor": 1, &"truck": 0,
		&"ambulance": 0, &"doctor_car": 0, &"engine": 0,
	}
	var wrong := PackedStringArray()
	var seen := 0
	for config: Dictionary in Station.TYPES:
		var id: StringName = config["id"]
		if not EXPECTED.has(id):
			continue
		var packed := load(String(config["scene"])) as PackedScene
		if packed == null:
			continue
		var unit := packed.instantiate()
		var vehicle := unit as Vehicle
		if vehicle != null:
			seen += 1
			if vehicle.cells != int(EXPECTED[id]):
				wrong.append("%s has %d, wants %d"
					% [id, vehicle.cells, int(EXPECTED[id])])
		unit.free()
	_check(seen == EXPECTED.size(),
		"all %d of the catalogue's cell-bearing bodies were read (%d)"
		% [EXPECTED.size(), seen])
	_check(wrong.is_empty(),
		"and each has exactly the cells it should (%s)"
		% ("all correct" if wrong.is_empty() else "; ".join(wrong)))


## The air rescue helicopter is actually wearing the rescue livery.
##
## **Because a palette that does not apply is silent.** Both generators decided whether to
## repaint a mesh by asking whether its material path contained `"PolygonCity_01_A"` -- the
## City pack's body material and nothing else. A Heist-pack vehicle declaring a palette was
## therefore accepted and ignored: the config read as applied, the build printed no warning,
## and the scene came out identical to the unpainted one. It happened in `build_vehicles.gd`
## and then again, separately, in `build_portraits.gd`, where the only thing that caught it
## was somebody looking at the rendered PNG.
##
## Three-sided on purpose. The livery is present on the rescue machine; it is *absent* on
## the police one, so a repaint that fired on everything would fail; and the glass is
## untouched, because the obvious over-broad fix (`"_01_A" in path`) also matches
## `PolygonHeist_01_A_Glass_mat` and gives the aircraft an opaque cockpit.
func _test_the_rescue_helicopter_wears_the_rescue_livery() -> void:
	var rescue := _materials_in("res://Game/Vehicles/RescueHelicopter.tscn")
	var police := _materials_in("res://Game/Vehicles/Helicopter.tscn")
	_check(rescue.has("res://Game/Materials/RescueLivery.tres"),
		"the rescue helicopter carries the rescue livery (%s)" % ", ".join(rescue))
	_check(not police.has("res://Game/Materials/RescueLivery.tres"),
		"and the police one does not, so the repaint is selective")
	var glass := "res://Assets/Synty/PolygonHeist/Materials/PolygonHeist_01_A_Glass_mat.tres"
	_check(rescue.has(glass),
		"and its glass kept the pack's own material rather than the bodywork atlas")


## Every emergency vehicle scene on disk is something the player can actually buy.
##
## **Written because one was not.** The recovery truck was generated, given a portrait and
## a lightbar, and never added to `Station.TYPES` -- so the scene, the portrait and the
## bodywork all existed and nothing in the game could reach any of it. It was found by a
## player asking how to get one, which is the worst way to find it: everything about the
## unit looked finished from the inside, including this suite, because every check that
## touched vehicles walked the *catalogue* and the truck was not in it.
##
## So this walks the other direction -- from the scenes to the catalogue -- which is the
## only direction that can see a unit nobody sells. Civilian traffic is [Unit.Service.NONE]
## and is meant to be unbuyable, so service is the filter.
func _test_every_emergency_vehicle_is_purchasable() -> void:
	var sold := {}
	for config: Dictionary in Station.TYPES:
		sold[String(config["scene"])] = true
	var unreachable := PackedStringArray()
	var reachable := PackedStringArray()
	var dir := DirAccess.open("res://Game/Vehicles")
	if dir == null:
		_check(false, "the vehicle folder can be read")
		return
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var path := "res://Game/Vehicles/%s" % file
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var unit := packed.instantiate()
		var as_unit := unit as Unit
		if as_unit != null and as_unit.service != Unit.Service.NONE:
			if sold.has(path):
				reachable.append(file)
			else:
				unreachable.append(file)
		unit.free()
	# Two-sided: a folder that read as empty would give an empty `unreachable` and pass.
	_check(reachable.size() >= 6,
		"%d emergency vehicle scenes are on the forecourt (%s)"
		% [reachable.size(), ", ".join(reachable)])
	_check(unreachable.is_empty(),
		"and none is built but unsellable (stranded: %s)"
		% ("none" if unreachable.is_empty() else ", ".join(unreachable)))


## Every vehicle the player can buy and send to a call carries a lightbar.
##
## **Written because two of them did not.** The police van shipped without a `siren` key
## in `build_vehicles.gd`, and the omission leaves no trace: the generator simply builds
## no lightbar, so the van sat correct on the forecourt and responded to every call dark
## and silent. The recovery truck had the same gap, found by this check rather than by
## anyone noticing. One key drives both halves -- [Vehicle] only creates its
## `AudioStreamPlayer3D` when `siren_path` resolves -- so a missing lightbar is a missing
## siren too, which is why the mistake is worth a check rather than a memo.
##
## Runs over the catalogue rather than a list of scenes, so a unit added later is covered
## the day it is added. Aircraft are exempt by falling out of the `as Vehicle` cast.
func _test_every_responding_vehicle_has_a_lightbar() -> void:
	var dark := PackedStringArray()
	var lit := PackedStringArray()
	for config: Dictionary in Station.TYPES:
		if not bool(config["vehicle"]):
			continue
		var packed := load(String(config["scene"])) as PackedScene
		if packed == null:
			continue
		var unit := packed.instantiate()
		var vehicle := unit as Vehicle
		if vehicle != null:
			if vehicle.siren_path.is_empty() \
					or vehicle.get_node_or_null(vehicle.siren_path) == null:
				dark.append(String(config["id"]))
			else:
				lit.append(String(config["id"]))
		unit.free()
	# Both sides: a catalogue that failed to load would give an empty `dark` and pass.
	#
	# **Counts the whole catalogue, not the lit half.** Written as `lit.size() >= 5` this
	# was coupled to the very fault its partner exists to catch -- `lit` and `dark`
	# partition one set, so darkening a single vehicle dropped the count to 4 and reddened
	# the guard as well. A guard that cannot survive its partner's fault is not a guard.
	_check(lit.size() + dark.size() >= 5,
		"the catalogue offers %d road vehicles to check (%s)"
		% [lit.size() + dark.size(), ", ".join(lit)])
	_check(dark.is_empty(),
		"and every one of them has a lightbar and siren (dark: %s)"
		% ("none" if dark.is_empty() else ", ".join(dark)))


func _test_the_helicopter_flies_and_lands_on_open_ground() -> void:
	_buy(&"helicopter", 1)
	var chopper := _station.dispatch(&"helicopter") as Aircraft
	if chopper == null:
		_check(false, "a helicopter to fly")
		return
	chopper.global_position = Vector3(ROAD.x, 0.45, ROAD.z)
	await _idle(4)
	_check(not chopper.is_airborne(), "it starts on the ground")
	# Read by path rather than through the aircraft, so a regeneration that renames the
	# part reddens this check instead of silently leaving the blades still.
	var main_rotor := chopper.get_node_or_null(
		"%s/%s" % [Aircraft.BLADE_PARENT, Aircraft.MAIN_ROTOR]) as Node3D
	var tail_rotor := chopper.get_node_or_null(
		"%s/%s" % [Aircraft.BLADE_PARENT, Aircraft.TAIL_ROTOR]) as Node3D
	_check(main_rotor != null and tail_rotor != null, "both rotors are on the airframe")
	var parked_main := main_rotor.rotation.y if main_rotor else 0.0
	await _wait(20)
	_check(main_rotor != null and is_equal_approx(main_rotor.rotation.y, parked_main),
		"and its rotors are still while it is parked")

	# Straight up first, and nowhere until it is up: climbing out from between buildings
	# while also moving is how an aircraft ends up inside one.
	chopper.take_off()
	var ground_y := chopper.global_position.y
	# **Sampled at 1.5s, which is deliberately mid-spool.** `rotor_spool` is 4.0s, so the
	# blades are turning and not yet at full speed: 0.213 rad here against 1.47 once it is
	# flying. The band below excludes a dead rotor at one end and a full-speed one at the
	# other, which is what makes it a statement about *winding up* rather than about
	# turning.
	#
	# This comment used to describe an altitude ramp and quote a 1.4s spool, and both had
	# stopped being true -- rotor speed is phase-driven now and the spool is 4.0s. The
	# check still passed throughout, which is the point: **a stale comment on a green
	# check is invisible**, and this one was caught by a sabotage agent reading it rather
	# than by anything the suite could do.
	#
	# 2 frames, not more: at full song the main rotor turns 1.47 rad in that time, and a
	# longer sample passes a whole revolution and aliases back to a meaningless number.
	await _wait(90)
	var low_from := main_rotor.rotation.y if main_rotor else 0.0
	await _wait(2)
	var low_rate := absf(angle_difference(
		main_rotor.rotation.y if main_rotor else 0.0, low_from))
	_check(low_rate > 0.05 and low_rate < 0.6,
		"the rotors are winding up on the pad (%.3f rad in 2 frames)" % low_rate)
	# **The order of the two, which is the whole of what was reported.** At a second and a
	# half the blades are turning and the aircraft has not moved: it used to lift first and
	# spin up afterwards, so it appeared to be raised by something other than its rotors.
	# A tolerance of 5cm rather than equality, because this is a float that other systems
	# are free to nudge.
	_check(chopper.global_position.y <= ground_y + 0.05,
		"and it has not left the ground while they do (%.2fm up)"
		% (chopper.global_position.y - ground_y))
	_check(not chopper.is_airborne(), "so it does not count as airborne yet")
	# Past the 4s spool and a good way into the climb. The arithmetic matters and has been
	# wrong here twice: the spool ends at 4.0s, this line is reached at 1.53s, so 300 more
	# frames puts it 2.5s into a 7 m/s climb -- about 17m, comfortably past the 6m asserted
	# and comfortably short of the 24m ceiling.
	await _wait(300)
	_check(chopper.global_position.y > ground_y + 6.0,
		"take off climbs (%.1fm up)" % (chopper.global_position.y - ground_y))
	_check(chopper.is_airborne(), "and it is airborne")

	# **Flies over a block, not around it.** The straight line between these two points
	# crosses ground no vehicle could drive, which is the whole of what an aircraft buys.
	var over := Vector3(ROAD.x, 0.45, ROAD.z) + Vector3(0.0, 0.0, -60.0)
	chopper.navigate_to(over)
	# Climb to 24m at 7 m/s is 3.4s before it travels at all, then 60m at 26 m/s. Ten
	# seconds is comfortably past both.
	await _wait(600)
	_check(_flat_distance(chopper.global_position, over) < 6.0,
		"and flies to a point across the district (%.1fm short)"
		% _flat_distance(chopper.global_position, over))

	# **Turning, both of them.** The blades are the only moving part on the airframe, and
	# a helicopter hovering with a frozen disc reads as a bug in the game rather than a
	# missing flourish. Sampled over 20 frames rather than one, because a single frame of
	# a fast spin can alias back to where it started.
	var flying_main := main_rotor.rotation.y if main_rotor else 0.0
	var flying_tail := tail_rotor.rotation.x if tail_rotor else 0.0
	await _wait(2)
	var cruise_rate := absf(angle_difference(
		main_rotor.rotation.y if main_rotor else 0.0, flying_main))
	_check(main_rotor != null and not is_equal_approx(main_rotor.rotation.y, flying_main),
		"the main rotor turns in flight")
	_check(tail_rotor != null and not is_equal_approx(tail_rotor.rotation.x, flying_tail),
		"and so does the tail rotor")
	# The far end of the spool, stated as a relationship rather than a bare magnitude.
	#
	# **Reworded once the mechanism changed.** This began life measuring an altitude ramp
	# and its name said so -- "full song at cruise height", against a reading taken "low
	# down". Rotor speed is phase-driven now, so the two samples differ because the first
	# is mid-spool, not because one is higher than the other. The numbers were identical
	# either way, which is exactly how a check ends up describing a mechanism the game no
	# longer has.
	_check(cruise_rate > 1.0 and cruise_rate > low_rate * 4.0,
		"and they reach full song by the time it is flying (%.2f rad against %.3f mid-spool)"
		% [cruise_rate, low_rate])

	# **A right-click makes it fly, not land -- and this shipped the wrong way round.**
	# Land scored 12 against Move's 0, so every right-click on open ground put the
	# aircraft down. The only ground it will land on is the only ground you would send it
	# to, which made hovering unreachable: order it anywhere and it landed there.
	#
	# Two-sided on purpose. The first half alone would pass if landing had simply been
	# broken; the second proves the verb still applies to that exact point and it is the
	# ladder, not the rule, that changed.
	var open_ground := Target.new()
	open_ground.position = ROAD
	var chosen := chopper.resolve(open_ground)
	_check(chosen is MoveAbility,
		"a right-click on open ground flies it there (%s)" % chosen)
	_check(LandAbility.new().can_target(chopper, open_ground),
		"though landing still accepts that same point once armed")
	chopper.issue(chosen.make_order(chopper, open_ground))
	# **It flies round, it does not pivot.** The bearing back to ROAD is behind it -- it
	# has just flown 60m the other way -- so this is close to the worst case the turn rate
	# has to serve, and a snap would show up as the full swing inside two frames.
	var heading := chopper.global_rotation.y
	var back := ROAD - chopper.global_position
	var bearing := atan2(-back.x, -back.z)
	_check(absf(angle_difference(heading, bearing)) > 2.0,
		"the way home is behind it, so this is a real turn (%.2f rad)"
		% absf(angle_difference(heading, bearing)))
	await _wait(2)
	# **A band, not a ceiling.** Written as `< 0.2` this asserted only that the nose does
	# not come round *too fast*, which an aircraft that never turns at all satisfies for
	# free -- sabotage measured exactly that, 0.00 rad, and the check stayed green. The
	# floor is what makes it a statement about turning rather than about not snapping.
	# 1.6 rad/s over two frames is 0.053, so the band holds either bound at arm's length.
	var turned := absf(angle_difference(chopper.global_rotation.y, heading))
	_check(turned > 0.01 and turned < 0.2,
		"and the nose comes round at a rate rather than snapping (%.2f rad in 2 frames)"
		% turned)
	# **Long enough to have landed, had it decided to.** The first cut waited 120 ticks,
	# and sabotage showed that half of this pair could not see the bug at all: from 60m
	# out at cruise height the aircraft needs ~1.8s to cross and 3.4s to come down, so at
	# 2s it is still airborne whichever verb it chose. A check that the fault cannot
	# reach is not a check. 400 clears both, and matches the deliberate landing below.
	await _wait(400)
	_check(chopper.is_airborne(), "so it is still in the air after carrying that out")
	# Against the bearing captured at the order, not one recomputed here: it is standing on
	# ROAD by now, and the bearing to where you already are is meaningless.
	_check(absf(angle_difference(chopper.global_rotation.y, bearing)) < 0.35,
		"and by the end it is facing the way it went (%.2f rad off)"
		% absf(angle_difference(chopper.global_rotation.y, bearing)))

	# The rule: inside a block is a building, and a building is not a landing site.
	var block_middle := CityGrid.tile_centre(
		CityGrid.block_base_x(1) + 2, CityGrid.block_base_z(1) + 2)
	_check(not Aircraft.can_land_at(block_middle),
		"it refuses to land on a building (%s)" % str(block_middle))
	_check(Aircraft.can_land_at(ROAD),
		"and accepts open ground, so the rule is not simply 'no'")

	# Put it down for real, and confirm it reaches the floor rather than reporting done
	# while still overhead.
	chopper.land_at(ROAD)
	# **Still at full song on the way down**, the other half of what was reported. Sampled
	# a third of the way into the descent: 24m at 7 m/s is 3.4s, so 100 frames is about
	# 12m up with plenty of descent left to be wrong in.
	await _wait(100)
	_check(chopper.phase == Aircraft.Phase.DESCENDING,
		"it is descending when sampled (phase %d)" % chopper.phase)
	var descent_from := main_rotor.rotation.y if main_rotor else 0.0
	await _wait(2)
	var descent_rate := absf(angle_difference(
		main_rotor.rotation.y if main_rotor else 0.0, descent_from))
	_check(descent_rate > 1.0,
		"and its rotors are still turning at full speed as it comes down (%.2f rad against %.2f at cruise)"
		% [descent_rate, cruise_rate])
	await _wait(400)
	# **Altitude, not just the phase it claims.** The first cut asserted only
	# `not is_airborne() and not is_navigating()` -- the aircraft's own account of itself --
	# and sabotage proved a helicopter that jumps to GROUNDED without descending passes it
	# while the message prints `y 24.45`. A check named "not overhead" has to measure the
	# height. The datum is where it was flying from, so this holds on any ground level.
	_check(not chopper.is_airborne() and not chopper.is_navigating(),
		"landing reports finished (phase %d)" % chopper.phase)
	# **Measured against the ground it took off from, not against where it is now.** The
	# first repair captured the datum immediately before landing -- at cruise height -- so
	# `y < datum + 1` was trivially true and the broken descent still passed. `ground_y`
	# is from before the take-off, which is the only height that means "down".
	_check(chopper.global_position.y < ground_y + 1.0,
		"and it is actually on the ground, not overhead (y %.2f against ground %.2f)"
		% [chopper.global_position.y, ground_y])

	_dissolve(chopper, &"helicopter")
	await _idle(2)


func _test_an_appliance_can_work_off_a_hydrant() -> void:
	await _clear_calls()
	_buy(&"engine", 1)
	var engine := _dispatch_to(&"engine", ROAD) as Vehicle
	if engine == null:
		_check(false, "an appliance to connect")
		return
	var hydrant := Hydrant.nearest(_scene, engine.global_position, 400.0)
	if hydrant == null:
		_check(false, "a hydrant on the map to connect to")
		return

	# Parked at the hydrant, by hand: the drive itself is other checks' business.
	engine.clear_orders()
	engine.global_position = hydrant.global_position + Vector3(3.0, 0.0, 0.0)
	engine.velocity = Vector3.ZERO
	engine.forward_speed = 0.0
	await _idle(6)

	_check(not engine.is_on_main(), "an appliance beside a hydrant is not yet connected")
	engine.connect_to_main(hydrant)
	await _idle(3)
	_check(engine.is_on_main(), "and connects when told to")

	# **Drawn against the tank's real size, not against the gauge.** `draw_water` takes
	# litres and divides by `tank_capacity`, which is 20 on the appliance — so the first
	# cut of this check drew 0.3 and moved the gauge by 0.015, passing on a margin far too
	# small to mean anything. Half a tank is unmistakable in either direction.
	var half_tank := engine.tank_capacity * 0.5
	engine.water = 1.0
	engine.draw_water(half_tank)
	_check(is_equal_approx(engine.water, 1.0),
		"the tank does not drain while it is on the main (%.2f after half a tank drawn)"
		% engine.water)
	# **Emptied first, and that is the whole assertion.** Written with a full tank this
	# line was vacuous: `has_water()` is `water > 0.0 or is_on_main()`, so a full tank
	# satisfied it and the main-supply branch was never reached. Sabotage proved it --
	# deleting `or is_on_main()` outright left the *entire suite* green. An empty tank on
	# the main is the only state that tells the two guards apart.
	engine.water = 0.0
	_check(engine.has_water(),
		"and a dry tank on the main still has water")

	# Drive off: the line comes with it.
	engine.forward_speed = 3.0
	await _idle(4)
	_check(not engine.is_on_main(), "driving away takes it off the main")

	# **Parked well clear of the hydrant for the dry test.** Standing beside one tops the
	# tank up on its own -- correct behaviour, and it crept to 0.01 and failed this the
	# first time. The same appliance that had water a moment ago has none once it is both
	# off the main and away from the supply, which is the other half of the same guard.
	engine.global_position = hydrant.global_position + Vector3(40.0, 0.0, 0.0)
	engine.forward_speed = 0.0
	engine.hydrant = null
	engine.water = 0.0
	await _idle(3)
	_check(not engine.has_water(),
		"and a dry tank away from one does not (%.2f)" % engine.water)
	engine.water = 1.0
	engine.draw_water(half_tank)
	_check(engine.water < 0.6,
		"and the tank starts paying again (%.2f after the same draw)" % engine.water)

	engine.forward_speed = 0.0
	engine.water = 1.0
	engine.hydrant = null
	# Back to the fleet the rest of the suite was handed.
	_dissolve(engine, &"engine")
	await _clear_calls()


func _test_the_fire_service_fights_fires() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a firefighter to send")
		return
	await _idle(4)

	_check(engine.service == Unit.Service.FIRE
			and crew.service == Unit.Service.FIRE,
		"both belong to the fire service")
	_check(engine.seats >= 4, "the appliance carries a crew (%d seats)" % engine.seats)
	_check(_find_ability(crew, &"extinguish") != null,
		"a firefighter is offered Extinguish")
	_check(_find_ability(crew, &"treat") == null
			and _find_ability(crew, &"apprehend") == null
			and _find_ability(crew, &"secure") == null,
		"and nothing else -- no treating, no arrests, no cordons")

	# On the hose: the engine parked at the scene. Rate is measured rather than
	# asserted from the constants, because the constants are not what the player sees.
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	# **Staged as a water fire on purpose.** This measures the water economy -- the hose
	# rate, the tank price, a dry engine -- and the default kind is VEHICLE, which since
	# August 2026 burns fuel and draws the foam tank instead. A check that leaned on the
	# default was measuring whichever agent the table happened to name.
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	var order := ExtinguishOrder.new(fire)
	crew.issue(order)
	var before := fire.intensity
	await _wait(60)
	var on_hose := before - fire.intensity
	_check(on_hose > 0.0, "on the hose, the fire goes down (%.3f/s)" % on_hose)
	# And goes down *faster than the fire's own baseline rate*, which is the whole
	# point of the appliance being there. The hose ran at exactly 1.0 of that baseline
	# until August 2026, which put a building fire at eleven seconds a node -- and
	# buildings spread, so a real building call was a minute of holding a hose still.
	# Measured against douse_per_second rather than against a fixed number, so it keeps
	# meaning the same thing if a fire's own rate is ever retuned.
	_check(on_hose > fire.douse_per_second * 1.2,
		"and faster than the fire's own rate -- the hose is a multiplier, not the "
		+ "ceiling (%.3f/s vs %.3f/s)" % [on_hose, fire.douse_per_second])
	crew.clear_orders()

	# Off the hose: the same firefighter, the same fire, the engine driven away.
	fire.intensity = 0.9
	await _place_unit(engine, Vector3(20.0, 0.2, 60.0))
	await _idle(4)
	crew.issue(ExtinguishOrder.new(fire))
	before = fire.intensity
	await _wait(60)
	var off_hose := before - fire.intensity
	crew.clear_orders()
	_check(off_hose > 0.0 and off_hose < on_hose * 0.6,
		"away from the appliance they have only what they carry (%.3f vs %.3f)"
		% [off_hose, on_hose])

	# A building yields to the hose and to nothing else.
	fire.queue_free()
	await _idle(4)
	var building := _spawn_fire(spot, 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	await _place_unit(_officer, spot + Vector3(2.0, 0.0, 0.0))
	_officer.issue(ExtinguishOrder.new(building))
	before = building.intensity
	await _wait(90)
	_check(is_equal_approx(building.intensity, before),
		"a building fire does not yield to a patrol car's extinguisher (%.3f -> %.3f)"
		% [before, building.intensity])
	_officer.clear_orders()

	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	crew.issue(ExtinguishOrder.new(building))
	var out := false
	for i in 900:
		await physics_frame
		# **A freed incident is the success, not an error.** An extinguished fire frees
		# itself, so reading `active` on it throws -- and a runtime error inside a check
		# silently abandons the rest of that check, which is why the assertion below and
		# the cleanup after it had not run in a long time while the suite read green.
		if not is_instance_valid(building) or not building.active:
			out = true
			break
	_check(out, "and a crew on the hose puts it out")

	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _clear_incidents()


## The people in an incident come out of the crowd's wardrobe, not the Starter
## pack's grey mannequin -- which is what a suspect and a casualty shipped wearing,
## and which reads as a placeholder standing in a city full of dressed pedestrians.
func _test_incident_figures_are_dressed() -> void:
	await _clear_incidents()
	var suspect := _director._spawn_suspect(Vector3(20.0, 0.0, -20.0))
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -26.0))
	await _idle(6)

	for figure: Node in [suspect, casualty]:
		var body := figure.get_node_or_null("Character") as Node3D
		_check(body != null and body.scene_file_path in Incident.OUTFITS,
			"%s wears one of the crowd's outfits ('%s')"
			% [figure.name, "none" if body == null else body.scene_file_path])
		_check(body != null and body.get_node_or_null("AnimationPlayer") != null,
			"and keeps an animation player after the swap")
	# The swap must not undo the 180 yaw that stops them moonwalking.
	var worn := suspect.get_node("Character") as Node3D
	_check(worn.transform.basis.z.z < -0.9,
		"with the visual still yawed to face travel (%.2f)" % worn.transform.basis.z.z)

	# A collapse takes a specific shopper, so the body wears what they were wearing.
	await _clear_incidents()
	var crowd := _civilians()
	if crowd.is_empty():
		# Silently skipping this is how a check quietly stops meaning anything: it
		# runs in the crowd section for exactly this reason.
		_check(false, "a crowd to take a collapse from")
	else:
		_director._rng.seed = 5
		var before := {}
		for civilian in crowd:
			var dress := civilian.get_node_or_null("Character")
			if dress:
				before[civilian.get_instance_id()] = dress.scene_file_path
		_director._spawn_medical()
		await _idle(6)

		# *Which* shopper went, not merely "some outfit the crowd owns": with seven
		# outfits across sixty people, every one of them is in the crowd somewhere,
		# so matching the set proves nothing. The one that vanished is the test.
		var still_here := {}
		for civilian in _civilians():
			still_here[civilian.get_instance_id()] = true
		var lost := ""
		for id in before:
			if not still_here.has(id):
				lost = str(before[id])
		var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
		if bodies.size() == 1 and lost != "":
			var taken: String = (bodies[0] as Node3D).get_node("Character").scene_file_path
			_check(taken == lost,
				"the collapsed shopper keeps their own clothes (wore '%s', body wears '%s')"
				% [lost.get_file(), taken.get_file()])
		else:
			_check(false, "exactly one shopper became exactly one casualty")
	await _clear_incidents()


## How often the district calls is a setting, because the first thing said after a
## full shift was that they came too fast.
func _test_the_call_rate_is_a_setting() -> void:
	var kept := _menu.call_pace
	var kept_pace := _director.pace

	_menu.set_call_pace(2)
	_check(is_equal_approx(_director.pace, 1.0),
		"BUSY is the pace the game shipped with (%.2f)" % _director.pace)
	_menu.set_call_pace(0)
	_check(_director.pace > 1.9,
		"QUIET stretches the gaps between calls (%.2f)" % _director.pace)

	# And it reaches the roll itself, not just the readout.
	_director.shift_length = 9999.0
	_director.call_interval_min = 2.0
	_director.call_interval_max = 2.0
	_director.clock = 0.0
	_check(_director.interval_scale() > 0.99,
		"with the shift's own escalation still at its start (%.2f)"
		% _director.interval_scale())

	_menu.call_pace = kept
	_menu._save_settings()
	_menu.call_pace = 9
	_menu._load_settings()
	_check(_menu.call_pace == kept,
		"the choice survives a reload (%d)" % _menu.call_pace)
	_director.pace = kept_pace


## What hour the district works at, and everything that has to follow from it.
##
## The lighting is the one system in the project with no behaviour to observe -- it is
## only ever seen -- so these checks watch the *consequences* instead: which lights are
## on, whether the fleet has beams, and whether coming back to day restores what the
## generator wrote. That last one is the important one. Day is not a preset; it is the
## captured baseline, and if a round trip through night does not return it exactly then
## every check written against the shipped map is quietly measuring something else.
func _test_the_hour_is_a_setting() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	_check(daylight != null, "the district knows what hour it is working at")
	if daylight == null:
		return
	var kept := daylight.time_of_day
	var street := _scene.get_node_or_null("StreetLights") as Node3D

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var noon_rotation := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	var noon_fog := (_scene.get_node("WorldEnvironment") as WorldEnvironment) \
		.environment.fog_density
	_check(not daylight.is_dark(), "day is not dark")
	_check(street != null and not street.visible, "and the street lights are out")

	daylight.set_time_of_day(Daylight.Mode.NIGHT)
	var night_rotation := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	_check(daylight.is_dark(), "night is dark")
	_check(street != null and street.visible, "and the district turns its lights on")
	_check(not noon_rotation.is_equal_approx(night_rotation),
		"the sun has moved (%.0f deg elevation to %.0f)"
		% [rad_to_deg(noon_rotation.x), rad_to_deg(night_rotation.x)])

	# Dusk is lit too: LIT_BELOW is one threshold, so nothing can disagree about it.
	daylight.set_time_of_day(Daylight.Mode.DUSK)
	_check(daylight.is_dark() and street.visible,
		"dusk is lit as well -- one threshold decides, not a flag per system")

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var back := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	var back_fog := (_scene.get_node("WorldEnvironment") as WorldEnvironment) \
		.environment.fog_density
	_check(back.is_equal_approx(noon_rotation) and is_equal_approx(back_fog, noon_fog),
		"and coming back to day restores the map as generated, exactly")

	# The setting itself, the same round trip the call rate takes.
	var kept_choice := _menu.time_of_day
	_menu.set_time_of_day(Daylight.Mode.NIGHT)
	_check(daylight.time_of_day == Daylight.Mode.NIGHT,
		"the settings card drives the district, not a copy of it")
	_menu._save_settings()
	_menu.time_of_day = 0
	_menu._load_settings()
	_check(_menu.time_of_day == Daylight.Mode.NIGHT,
		"and the hour survives a reload")

	_menu.time_of_day = kept_choice
	_menu._save_settings()
	daylight.set_time_of_day(kept)


## SHIFT'S OWN: the last weather button is a policy, not a sky. The director draws from
## its seeded stream when the shift opens, so every shift has its own weather and a
## reproduced seed is rained on identically. Two properties, each its own witness: a
## fixed choice never rolls, and the roll both happens and reproduces.
func _test_the_shift_rolls_its_own_weather() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district has a sky to roll")
		return
	await _clear_calls()
	await _park_the_shift()

	# Policy off: a fixed CLEAR choice stays CLEAR through a shift opening.
	_menu.set_weather(Daylight.Weather.CLEAR)
	_director.shift_seed = 23
	_director.begin_shift()
	await _idle(2)
	_check(daylight.weather == Daylight.Weather.CLEAR,
		"a fixed weather choice never rolls (%d)" % daylight.weather)
	await _end_freeplay()

	# Policy on. **Hunted, not assumed**: half the table is CLEAR, and a broken roll
	# that never fires also leaves CLEAR -- so the check walks seeds until it sees a
	# weather actually land, which is what proves the wiring, then re-runs that seed
	# for the reproduction.
	_menu.set_weather(GameMenu.SHIFT_WEATHER)
	var rolled_seed := 0
	var rolled: int = Daylight.Weather.CLEAR
	for seed_try in range(1, 21):
		_director.shift_seed = seed_try
		_director.begin_shift()
		await _idle(2)
		var drawn := daylight.weather
		await _end_freeplay()
		if drawn != Daylight.Weather.CLEAR:
			rolled_seed = seed_try
			rolled = drawn
			break
	_check(rolled_seed != 0,
		"the shift's own policy actually rolls weather (seed %d drew %d)"
		% [rolled_seed, rolled])
	if rolled_seed != 0:
		daylight.set_weather(Daylight.Weather.CLEAR)
		_director.shift_seed = rolled_seed
		_director.begin_shift()
		await _idle(2)
		_check(daylight.weather == rolled,
			"and the same seed draws the same sky (%d)" % daylight.weather)
		await _end_freeplay()

	_menu.set_weather(Daylight.Weather.CLEAR)
	_director.shift_seed = 0


## Wet weather is a dispatch fact, not a screen effect: the collision kinds carry a
## wet_weight and the picker consults the sky. Asserted at the weight level (the
## mechanism) and the distribution level (the outcome), both seeded.
func _test_wet_weather_loads_the_table_with_collisions() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district has a sky to consult")
		return
	var rtc_row: Dictionary
	for kind: Dictionary in Director.KINDS:
		if kind["id"] == &"rtc":
			rtc_row = kind
	_check(not rtc_row.is_empty()
			and _director._kind_weight(rtc_row, true)
				== 2 * _director._kind_weight(rtc_row, false),
		"a wet road doubles the collision weight (%d from %d)"
		% [_director._kind_weight(rtc_row, true), _director._kind_weight(rtc_row, false)])

	daylight.set_weather(Daylight.Weather.RAIN)
	_director._rng.seed = 77
	var wet_hits := 0
	for i in 400:
		var kind := _director._pick_kind()
		if kind == &"rtc" or kind == &"bus_rtc":
			wet_hits += 1
	daylight.set_weather(Daylight.Weather.CLEAR)
	_director._rng.seed = 77
	var dry_hits := 0
	for i in 400:
		var kind := _director._pick_kind()
		if kind == &"rtc" or kind == &"bus_rtc":
			dry_hits += 1
	_check(wet_hits > dry_hits,
		"and a wet shift draws more collisions (%d wet vs %d dry in 400)"
		% [wet_hits, dry_hits])


## Headlamps, and the reason [Daylight] is a passive watcher rather than something the
## station has to remember to call: a vehicle bought at midnight needs lights, and the
## station knows nothing about the hour.
func _test_vehicles_light_up_after_dark() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district knows what hour it is working at")
		return
	var kept := daylight.time_of_day

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var beams := _car.get_node_or_null("Headlights") as Node3D
	_check(beams != null, "a vehicle carries headlamps")
	if beams == null:
		daylight.set_time_of_day(kept)
		return
	_check(beams.get_child_count() == 2,
		"two of them (%d)" % beams.get_child_count())
	# Measured off the vehicle's own collider, so they sit at the nose rather than at
	# whatever a hard-coded offset assumed. -Z is forward.
	var lamp := beams.get_child(0) as SpotLight3D
	_check(lamp != null and lamp.position.z < 0.0,
		"on the nose, not the boot (z %.2f)" % (lamp.position.z if lamp else 0.0))
	_check(not beams.visible, "and off in daylight")

	daylight.set_time_of_day(Daylight.Mode.NIGHT)
	_check(beams.visible, "and lit after dark")

	# The watcher: something that arrives *while* it is dark is fitted too. The
	# fixtures already have every owned patrol standing on the map, so this buys one
	# more and puts the career back afterwards -- the career checks at the end of the
	# suite are counting.
	var kept_funds := _station.funds
	var kept_owned: Dictionary = _station.owned.duplicate()
	_station.funds += _station.price(&"patrol")
	_station.purchase(&"patrol")
	var bought := _station.dispatch(&"patrol")
	if bought == null:
		_check(false, "a patrol car could be bought to test the night fitting")
	else:
		await _idle(4)
		var late := bought.get_node_or_null("Headlights") as Node3D
		_check(late != null and late.visible,
			"a vehicle bought at midnight turns up with its lights on")
		bought.queue_free()
		await _idle(2)
	_station.funds = kept_funds
	_station.owned = kept_owned

	daylight.set_time_of_day(kept)


## The display setting: it stores, it persists, and it does not touch a headless window.
##
## The behaviour worth pinning here is the **guard**, not the mode change -- there is no
## window in a headless run to put into fullscreen, and a call that ignored that would
## either warn on every suite run or resize the viewport the whole suite measures against.
## So this asserts the setting round-trips and that `root.size` is exactly where the suite
## pinned it afterwards.
func _test_the_display_setting_is_headless_safe() -> void:
	if _menu == null:
		_check(false, "a menu to carry the setting")
		return
	var kept := _menu.fullscreen
	var before: Vector2i = root.size
	_menu.set_fullscreen(true)
	await _idle(3)
	_check(_menu.fullscreen, "the display setting stores fullscreen")
	# **Asserted on the guard's decision, not on the viewport.** The first cut checked
	# that `root.size` had not moved, and sabotage showed that cannot fail: headless Godot
	# has no window, so `window_set_mode` neither warns nor resizes and the assertion was
	# true whether the guard existed or not. `_apply_fullscreen` reports whether it
	# reached the display server, which is the thing the guard actually decides.
	# **A settings load must never take fullscreen away.** Asserted on the flag rather than
	# on the window, because the headless display server has no window to inspect: a player
	# who filled the screen with the window manager still has `fullscreen=false` on disk,
	# and pressing PLAY used to change scene, load that stale false, and drag them out.
	# Nothing had asked it to.
	# **A settings load must never take fullscreen away.** A player who fills the screen
	# with the window manager still has `fullscreen=false` on disk -- so pressing PLAY
	# changed scene, the district's menu loaded that stale false, and the game dragged them
	# back into a window. Nothing had asked it to.
	#
	# Asserted on the decision rather than on the window, for the same reason the check
	# below exists: headless has no window, so `window_set_mode` cannot be seen to do
	# anything, but a wrong decision can.
	_check(GameMenu.window_action(false, true, false) == GameMenu.Action.ADOPT,
		"a settings load finds the screen filled and keeps it that way")
	_check(GameMenu.window_action(false, true, true) == GameMenu.Action.SET,
		"but pressing WINDOWED does put the window back")
	_check(GameMenu.window_action(true, false, false) == GameMenu.Action.SET,
		"and a saved fullscreen still fills the screen on load")
	_check(GameMenu.window_action(true, true, false) == GameMenu.Action.LEAVE
			and GameMenu.window_action(false, false, true) == GameMenu.Action.LEAVE,
		"and a window already in the right mode is left alone")

	_check(not _menu._apply_fullscreen(),
		"and asks the display server for nothing when there is no screen")
	_check(root.size == before,
		"leaving the viewport the suite measures against (%s)" % str(root.size))
	_menu.set_fullscreen(false)
	await _idle(2)
	_check(not _menu.fullscreen, "and windowed puts it back")
	_menu.set_fullscreen(kept)


## The interface's own click, driven through a real press.
##
## Asserted on the player **actually running** after a synthesised click on a real
## control, not on the signal being connected: a connection proves the watcher found the
## button, and proves nothing about whether a sound comes out of it. The two failure modes
## that matter here are both silent -- an OGG that did not import, and a click wired to a
## player whose stream is null -- and neither shows up anywhere but the speakers.
##
## The rollover is checked the same way, and separately, because it is the one that gets
## broken by accident: it is rate-limited, so a bug in the gate silences it while the
## click keeps working.
func _test_the_interface_clicks() -> void:
	var clicks := _scene.get_node_or_null("HUD/ClickSounds") as ClickSounds
	if clicks == null:
		_check(false, "the HUD ships a click watcher")
		return
	_check(clicks._click != null and clicks._click.stream != null,
		"the click sound is loaded")
	_check(clicks._rollover != null and clicks._rollover.stream != null,
		"and so is the rollover")
	if clicks._click == null or clicks._rollover == null:
		return
	_check(clicks._click.bus == AudioBuses.UI,
		"on the UI bus (%s)" % clicks._click.bus)

	# A real control, clicked where it is: the sidebar's REQUEST UNITS button, which the
	# watcher had to have found on its own -- nothing tells it that button exists. It was
	# the corner buy button until that was retired in favour of this one.
	var panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	var buy := panel.request_button() if panel else null
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as RequisitionPanel
	if buy == null:
		_check(false, "a button to press")
		return
	clicks._click.stop()
	await _idle(2)
	# **Read between the press and the release, not after the gesture.** This called
	# `_click()`, which pushes press *and* release and then waits -- so it could only ever
	# say a sound eventually fired, never when. Both wirings pass that: with the sound on
	# `Button.pressed` (a button-*up* signal, which is what shipped) the click arrived at
	# the end of the gesture and the interface sounded like it lagged the hand, and this
	# leg stayed green throughout. Measured on both trees: after the press, `playing` is
	# true wired to `button_down` and false wired to `pressed`; after the release both are
	# true. So the press is the only moment that tells them apart.
	_dismiss_any_modal()
	var where := buy.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = where
	press.global_position = where
	root.push_input(press)
	await _idle(2)
	_check(clicks._click.playing,
		"a button makes its click on the press, not on the release")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = where
	release.global_position = where
	root.push_input(release)
	await _idle(2)
	if shop:
		shop.close_shop()
		await _idle(2)

	# The rollover, off its own gate rather than a click.
	clicks._rollover.stop()
	clicks._last_rollover = -999.0
	await _idle(2)
	buy.mouse_entered.emit()
	# **Read immediately, with no frames in between, and that is the fix not the shortcut.**
	# `emit()` calls `_play_rollover` synchronously, so `playing` is true the instant it
	# returns -- the two frames that used to sit here bought nothing and cost correctness.
	# `rollover2.ogg` runs 0.0573s and two fixed-step frames are 0.0333s of *simulated*
	# time, but the audio server plays in real time whatever `--fixed-fps` says, so on a
	# loaded machine the sample could finish inside the wait and the check would read false
	# with nothing wrong. A sabotage pass found it flapping; it was never a real red.
	_check(clicks._rollover.playing, "and the pointer crossing one makes a tick")

	# The gate: a second crossing inside the window must not stack a second tick.
	clicks._rollover.stop()
	await _idle(1)
	buy.mouse_entered.emit()
	_check(not clicks._rollover.playing,
		"a second crossing straight after is swallowed rather than rattling")

	# **Pressing a button while the interface is being torn down.** QUIT TO TITLE changes
	# scene, which frees the HUD and this watcher, and the `pressed` that ordered it can
	# still arrive afterwards -- Godot answers `play()` on a detached player with an error
	# in the console. Staged by detaching the player rather than by changing scene, which
	# in the suite would tear the district out from under every check after this one.
	#
	# **Last in this check, deliberately.** It sat before the gate assertion above and
	# broke it: detaching and reattaching costs four frames, the gate is 60ms -- about
	# 3.6 frames -- so the window had expired by the time the gate was measured and the
	# tick it expected to be swallowed played instead.
	var parent := clicks._click.get_parent()
	parent.remove_child(clicks._click)
	clicks._play_click()
	clicks._play_rollover()
	# **This leg asserts its own staging, and cannot do better from inside the process.**
	# It reads back the detachment it just performed; `_play_click()` is called above but
	# nothing about its behaviour is read, so the leg would stay green with the in-tree
	# guard in `ClickSounds._play_click` deleted outright. That is not fixable here: the
	# guard exists to stop Godot printing "Playback can only happen when a node is inside
	# the scene tree", and a detached player reports `playing == false` whether the guard
	# ran or not -- the error is the only difference and it is not visible to GDScript.
	# **The witness is the run log, not this check**: grep a run for that string. Kept
	# because the staging is worth pinning, labelled so nobody counts it as coverage of
	# the guard.
	_check(not clicks._click.is_inside_tree(),
		"a click arriving after the HUD is gone is swallowed, not an error")
	parent.add_child(clicks._click)
	await _idle(2)


## Every sound is wired and loaded. Audio fails *silently* -- a missing file, an
## unimported one, a player nobody called play() on all look identical from the
## code, and none of them makes a noise. So this asserts the streams exist, are
## attached, and are running.
func _test_the_district_makes_a_noise() -> void:
	var soundscape := _scene.get_node_or_null("HUD/Soundscape") as Soundscape
	if soundscape == null:
		_check(false, "the HUD ships a soundscape")
		return
	_check(soundscape._ambience != null and soundscape._ambience.playing,
		"the city bed is playing under everything")
	_check(soundscape._radio != null and soundscape._radio.stream != null,
		"and the dispatch radio is loaded")

	# **The music bed.** Same reasoning as everything else in this check, and then some:
	# `Soundscape._player` casts what it loads to `AudioStreamWAV`, so a music file in any
	# other format comes back null and the bed is simply absent -- no error, no warning,
	# and nothing on screen to notice. It also has to be on its own bus, or the settings
	# card's music slider moves the sirens with it.
	_check(soundscape._music != null and soundscape._music.stream != null
			and soundscape.music_playing(),
		"the ambient bed is playing")
	_check(soundscape._music != null and soundscape._music.bus == AudioBuses.MUSIC,
		"on the music bus, so it can be balanced against the game (%s)"
		% (soundscape._music.bus if soundscape._music else "no player"))
	var music_bus := AudioServer.get_bus_index(AudioBuses.MUSIC)
	_check(music_bus > 0, "and that bus exists (%d)" % music_bus)

	# **Everything the world makes is on the effects bus.** The point of the bus is that
	# one slider can quieten the district without touching the music, and that only works
	# if nothing was left behind on Master. Asserted per player, because "most of them"
	# is the failure mode: a siren still on Master is a siren the slider cannot reach, and
	# nothing on screen would say so.
	var strays := PackedStringArray()
	for entry: Array in [["city bed", soundscape._ambience],
			["dispatch radio", soundscape._radio]]:
		var player := entry[1] as AudioStreamPlayer
		if player and player.bus != AudioBuses.SFX:
			strays.append("%s on %s" % [entry[0], player.bus])
	var siren := _car.get_node_or_null("SirenAudio") as AudioStreamPlayer3D
	var revs := _car.get_node_or_null("EngineAudio") as AudioStreamPlayer3D
	if siren and siren.bus != AudioBuses.SFX:
		strays.append("siren on %s" % siren.bus)
	if revs and revs.bus != AudioBuses.SFX:
		strays.append("engine on %s" % revs.bus)
	_check(strays.is_empty(), "every world sound is on the effects bus (%s)"
		% ("clear" if strays.is_empty() else ", ".join(strays)))

	# And the slider reaches it. Asserted on the bus moving, not on the setting storing:
	# a value written to a variable that never reaches `AudioServer` is silent in exactly
	# the way the music default was.
	var sfx_bus := AudioServer.get_bus_index(AudioBuses.SFX)
	if sfx_bus > 0 and _menu:
		var kept_sfx := _menu.sfx_volume
		_menu.set_sfx_volume(0.25)
		var quiet := AudioServer.get_bus_volume_db(sfx_bus)
		_menu.set_sfx_volume(1.0)
		var loud := AudioServer.get_bus_volume_db(sfx_bus)
		_check(quiet < loud - 6.0,
			"and the effects slider moves it (%.1fdB against %.1fdB)" % [quiet, loud])
		_menu.set_sfx_volume(kept_sfx)

	# **The shipped default is a bed, and applying it works.** Reported as too loud on
	# first listen, and the cause was half arithmetic: the settings slider steps in 0.05,
	# so a default of -18 dB (0.126 linear) rounded *up* to 0.15 and played louder than
	# the constant said.
	#
	# Asserted by *applying* the default and reading the bus back, rather than by
	# measuring the bus as it stands. The live bus reflects whatever the player last chose
	# and a player is entitled to turn the music up -- the first cut of this check read it
	# directly and failed on a stale 0.15 left in the settings file, which is a fact about
	# a save rather than about the game. This form tests the plumbing and the default at
	# once and depends on neither.
	if music_bus > 0:
		var kept_db := AudioServer.get_bus_volume_db(music_bus)
		AudioBuses.set_music_volume(db_to_linear(AudioBuses.MUSIC_DEFAULT_DB))
		var gap: float = AudioServer.get_bus_volume_db(0) \
			- AudioServer.get_bus_volume_db(music_bus)
		_check(gap >= 24.0,
			"the default level sits %.1fdB under master, so it stays a bed" % gap)
		AudioServer.set_bus_volume_db(music_bus, kept_db)

	# The radio answers the board rather than being told: opening a call chirps.
	await _clear_calls()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -20.0))
	await _idle(6)
	_check(soundscape._radio.playing, "a new call puts a tone over the radio")
	casualty.queue_free()
	await _clear_calls()

	# The engine note: every emergency vehicle runs one, pitched by speed.
	var note := _car.get_node_or_null("EngineAudio") as AudioStreamPlayer3D
	_check(note != null and note.stream != null and note.playing,
		"a vehicle runs an engine note")
	if note:
		await _place(ROAD)
		await _idle(4)
		var idle_pitch := note.pitch_scale
		_car.issue(MoveOrder.new(ROAD + Vector3(0.0, 0.0, -40.0)))
		await _wait(45)
		_check(note.pitch_scale > idle_pitch + 0.1,
			"which rises with the revs (%.2f -> %.2f)" % [idle_pitch, note.pitch_scale])
		_car.clear_orders()

	# And fires burn audibly, louder for being bigger.
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.9)
	await _idle(6)
	var crackle := fire.get_node_or_null("Crackle") as AudioStreamPlayer3D
	_check(crackle != null and crackle.playing, "a fire crackles")
	if crackle:
		var loud := crackle.volume_db
		fire.douse(0.6)
		await _idle(4)
		_check(crackle.volume_db < loud - 5.0,
			"and quietens as it is knocked down (%.0f -> %.0f dB)"
			% [loud, crackle.volume_db])
	await _clear_incidents()


## The appliance carries water, and running dry is a real failure rather than a
## slower one: a building grows faster than a crew with only what they carry.
func _test_the_appliance_runs_on_water() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew for the water test")
		return
	_check(engine.carries_water, "the appliance carries a tank")
	_check(not _car.carries_water and not _ambulance.carries_water,
		"and nothing else does")

	# A scene with no hydrant within reach of where the engine parks -- found rather
	# than assumed. There are 41 of them on the kerbs, and the first spot picked for
	# this test happened to be beside one: the tank refilled as fast as the hose drew
	# it down and the drain looked broken.
	var spot := Vector3.INF
	for candidate in CityGrid.pavement_points():
		if Hydrant.nearest(_scene, candidate + Vector3(6.0, 0.0, 0.0),
				engine.hydrant_reach + 4.0) == null:
			spot = candidate
			break
	if spot == Vector3.INF:
		_check(false, "a scene out of reach of every hydrant")
		return

	# Hosing draws the tank down.
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	# **Staged as a water fire on purpose.** This measures the water economy -- the hose
	# rate, the tank price, a dry engine -- and the default kind is VEHICLE, which since
	# August 2026 burns fuel and draws the foam tank instead. A check that leaned on the
	# default was measuring whichever agent the table happened to name.
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	engine.water = 1.0
	crew.issue(ExtinguishOrder.new(fire))
	await _wait(60)
	# One second of hosing, against what the model says it should cost. Pinning the
	# arithmetic rather than a magic threshold, because all three terms have now moved
	# under this check: the hose rate, the per-douse price, and the tank's capacity.
	# The old form asserted `water < 0.99` and went red the moment the tank grew 20x --
	# correctly complaining, but about the threshold rather than about the model.
	var drained := 1.0 - engine.water
	var expected := ExtinguishOrder.water_cost(
		fire.douse_per_second * ExtinguishOrder.HOSE_RATE) / engine.tank_capacity
	_check(drained > 0.0, "working the hose empties it (%.4f of a tank a second)"
		% drained)
	_check(absf(drained - expected) < expected * 0.3,
		"at the rate the tank's own capacity says it should (%.4f, expected %.4f)"
		% [drained, expected])
	crew.clear_orders()

	# Dry: a building stops going down at all.
	fire.queue_free()
	await _idle(4)
	var building := _spawn_fire(spot, 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	engine.water = 0.0
	crew.issue(ExtinguishOrder.new(building))
	var before := building.intensity
	await _wait(90)
	_check(is_equal_approx(building.intensity, before),
		"a dry appliance is no supply at all (%.2f -> %.2f)"
		% [before, building.intensity])
	crew.clear_orders()

	# A hydrant refills it -- parked, because an engine that filled up while driving
	# past would make the tank a formality.
	var hydrant := get_nodes_in_group(Hydrant.GROUP)
	_check(hydrant.size() > 10,
		"the district has hydrants to refill at (%d)" % hydrant.size())
	if hydrant.is_empty():
		return
	var tap := hydrant[0] as Node3D
	await _place_unit(engine, tap.global_position + Vector3(3.0, 0.2, 0.0))
	await _wait(60)
	_check(engine.water > 0.0 and engine.is_refilling,
		"parked beside one, it fills (%.2f)" % engine.water)

	# And away from any supply it does not. Incidents cleared first: a crew that can see a
	# fire will hose it off this engine's tank, and the water going down is then the crew
	# working rather than a hydrant that will not stop giving.
	await _clear_incidents()
	engine.water = 0.2
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _wait(60)
	_check(is_equal_approx(engine.water, 0.2) and not engine.is_refilling,
		"away from one it does not (%.2f)" % engine.water)

	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _clear_incidents()


## The set piece: one scene that no single service can finish.
func _test_a_rescue_needs_every_service() -> void:
	await _clear_calls()
	_director._rng.seed = 12
	_director._spawn_rescue()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"a building fire with casualties is one call, not three (%d)" % open.size())
	if open.is_empty():
		return
	var call := open[0]
	_check(call.kind == Call.Kind.RESCUE,
		"the board reads it as a rescue (%d)" % call.kind)
	_check("casualties" in call.title(),
		"and says so ('%s')" % call.title())
	_check(get_nodes_in_group(Casualty.CASUALTY_GROUP).size() == 2,
		"two casualties are out in front of it (%d)"
		% get_nodes_in_group(Casualty.CASUALTY_GROUP).size())
	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(fires.size() == 1 and (fires[0] as Fire).needs_hose,
		"with a fire only a hose will touch")

	# The casualties are clear of the flames but inside the board's grouping radius:
	# one job, and a paramedic who is not standing in it.
	var fire := fires[0] as Fire
	var reachable := true
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var away := _flat_distance((node as Node3D).global_position,
			fire.global_position)
		if away < 3.0 or away > Call.GROUPING_RADIUS:
			reachable = false
	_check(reachable, "placed out of the fire but inside the same call")
	await _clear_calls()


## The director has always refused to open a call the roster cannot answer -- which
## is why building fires did not exist while there was no fire service to buy. Now
## the same rule is a career gate rather than a permanent ban.
func _test_building_fires_wait_for_a_fire_service() -> void:
	await _clear_calls()
	var kept := _station.owned.duplicate()

	_station.owned = {&"patrol": 2, &"ambulance": 1}
	_check(not _director._can_fight_buildings(),
		"a career with no fire service cannot fight buildings")
	var offered := {}
	_director._rng.seed = 3
	for i in 200:
		offered[_director._pick_kind()] = true
	_check(not offered.has(&"building"),
		"so the director never draws one (%s)" % str(offered.keys()))

	_station.owned = {&"engine": 1, &"firefighter": 1}
	_check(_director._can_fight_buildings(),
		"buying an engine and a firefighter changes that")
	offered = {}
	for i in 200:
		offered[_director._pick_kind()] = true
	_check(offered.has(&"building"), "and the call kind unlocks")

	# An engine with nobody to crew it is not a fire service.
	_station.owned = {&"engine": 1}
	_check(not _director._can_fight_buildings(),
		"an appliance with no crew does not count")

	# The fire is sized to the crew that will have to fight it, rather than withheld
	# until the crew is big enough. Gating on a full crew of four was tried first and
	# worked, but it meant a one- or two-firefighter career never saw the most
	# interesting call in the game.
	var sizes := {}
	for hands in [1, 2, 3, 4]:
		_station.owned = {&"engine": 1, &"firefighter": hands}
		var sized := Fire.new()
		_director._size_to_crew(sized)
		sizes[hands] = {"nodes": sized.max_fires, "interval": sized.spread_interval}
		sized.free()
	_check(sizes[1]["nodes"] < sizes[4]["nodes"],
		"a lone firefighter is sent a smaller fire than a full crew (%d nodes vs %d)"
		% [sizes[1]["nodes"], sizes[4]["nodes"]])
	_check(sizes[1]["interval"] > sizes[4]["interval"],
		"and one that spreads more slowly (%.0fs vs %.0fs)"
		% [sizes[1]["interval"], sizes[4]["interval"]])
	var climbs := true
	for hands in [2, 3, 4]:
		if int(sizes[hands]["nodes"]) < int(sizes[hands - 1]["nodes"]):
			climbs = false
	_check(climbs, "and the job grows with every firefighter hired (%d/%d/%d/%d nodes)"
		% [sizes[1]["nodes"], sizes[2]["nodes"], sizes[3]["nodes"], sizes[4]["nodes"]])
	# Past a full appliance it stops growing: a fire that outran four would just be
	# the unwinnable scene again, wearing a bigger number.
	_station.owned = {&"engine": 1, &"firefighter": 9}
	var capped := Fire.new()
	_director._size_to_crew(capped)
	_check(capped.max_fires == int(sizes[4]["nodes"]),
		"and stops growing past a full appliance (%d)" % capped.max_fires)
	capped.free()

	_station.owned = kept
	_station._save_career()
	_director._spawn_building_fire()
	await _idle(6)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Building fire",
		"a building fire reads as one on the board ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))
	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(fires.size() == 1 and (fires[0] as Fire).needs_hose,
		"and it is flagged as needing a hose")
	await _clear_calls()


# --- The depth pass: five call kinds, each aimed at one purchase -------------------
#
# Every check below asserts the same three things, and the third is the one that earns
# it. That a call opens, that it opens as *one* call, and then **which unit resolves to
# which verb** on the incident that defines the kind. The first two would stay green if
# the scene were placed where nobody could work it; only the third says the call is
# answerable, and by the unit it was built for.
#
# `resolve()`, never a hand-built ability -- the recovery truck shipped broken three
# times behind checks that constructed `ClearAbility.new()` and scored it.


## A collapse deep in a park: the call the road does not reach.
func _test_a_park_collapse_is_out_of_reach_of_the_road() -> void:
	await _clear_calls()
	_director._rng.seed = 41
	_director._spawn_remote_medical()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"a collapse in the park is one call (%d)" % open.size())
	if open.is_empty():
		return
	_check("no vehicle access" in open[0].title(),
		"and the board says why it is awkward ('%s')" % open[0].title())

	var down := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(down.size() == 1, "one person is down (%d)" % down.size())
	if down.is_empty():
		await _clear_calls()
		return
	var casualty := down[0] as Casualty

	# **The distance is the whole feature.** Without this the call is an ordinary medical
	# shout wearing a different name, and every other leg here would still pass.
	var gap := _director._road_gap(casualty.global_position)
	_check(gap >= Director.PARK_DEPTH,
		"lying %.1fm off the nearest road, past the %.1fm a vehicle can reach"
		% [gap, Director.PARK_DEPTH])
	_check(not _director._roadside(casualty.global_position),
		"which is well past the kerbside a car could pull up to")

	# Somewhere a helicopter could put down, which is the answer this call is built to
	# make worth £1,800 -- park tiles are standable, building footprints are not.
	var tile := CityGrid.tile_at(casualty.global_position)
	_check(CityGrid.standable(tile.x, tile.y),
		"on ground something could land on")

	# **And it is still answerable on foot.** A call only a purchase can close is the
	# mistake `_leaves_a_wreck` was written to undo; this is meant to be tight, not shut.
	_check(_paramedic.resolve(_target_for(casualty)) is TreatAbility,
		"a paramedic who walks in can still work (%s)"
		% _resolved_id(_paramedic, _target_for(casualty)))
	# Against the scene's own default rather than the script's -- Casualty.tscn may
	# override the exported figure, and comparing to `Casualty.new()` would quietly
	# measure the wrong baseline.
	var plain := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
		.instantiate() as Casualty
	var baseline := plain.decline_per_second
	plain.free()
	_check(casualty.decline_per_second > baseline * 1.4,
		"declining faster than a street collapse, so the walk costs (%.4f vs %.4f)"
		% [casualty.decline_per_second, baseline])
	await _clear_calls()


## A fire somebody lit, with the arsonist still standing over it.
func _test_arson_is_a_fire_and_an_arrest() -> void:
	await _clear_calls()
	_director._rng.seed = 17
	_director._spawn_arson()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"a fire and the person who lit it are one call, not two (%d)" % open.size())
	if open.is_empty():
		return
	_check("deliberately" in open[0].title(),
		"named by the fire rather than by the suspect ('%s')" % open[0].title())

	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	_check(fires.size() == 1, "one fire (%d)" % fires.size())
	_check(suspects.size() == 1, "one suspect (%d)" % suspects.size())
	# **The two halves are guarded separately, and that is deliberate.** They shared one
	# `if fires.is_empty() or suspects.is_empty(): return` until a sabotage pass showed
	# what that costs: suppressing the suspect reddened "one suspect (0)" and then
	# silently dropped the three *fire* legs behind the same guard, so a bug in the arrest
	# half took the fire half's coverage down with it. Neither half is evidence for the
	# other; neither should be able to hide the other.
	if not fires.is_empty():
		var fire := fires[0] as Fire
		# **No engine wanted, and that is the point of the row.** Every other fire in the
		# table either needs a hose or merely tolerates an officer; this one is sized for
		# what a patrol car already carries.
		_check(not fire.needs_hose,
			"a bin an officer's own extinguisher will put out")
		_check(_officer.resolve(_target_for(fire)) is ExtinguishAbility,
			"so the officer is offered Extinguish (%s)"
			% _resolved_id(_officer, _target_for(fire)))
	if not suspects.is_empty():
		var suspect := suspects[0] as Suspect
		_check(_officer.resolve(_target_for(suspect)) is ApprehendAbility,
			"and Apprehend on the person who lit it (%s)"
			% _resolved_id(_officer, _target_for(suspect)))
		_check(not suspect.armed,
			"who is not armed, so this is not the ARV's call")
	await _clear_calls()


## A disturbance with somebody hurt in the middle of it: the call Secure is for.
func _test_an_affray_puts_a_casualty_inside_the_cordon() -> void:
	await _clear_calls()
	_director._rng.seed = 23
	_director._spawn_affray()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"the fight and the injured person are one call (%d)" % open.size())
	if open.is_empty():
		return
	_check("injured" in open[0].title(),
		"and the board says somebody is hurt ('%s')" % open[0].title())

	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	var down := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(suspects.size() >= 2,
		"several of them are kicking off (%d)" % suspects.size())
	_check(down.size() == 1, "with one casualty among them (%d)" % down.size())
	if suspects.is_empty() or down.is_empty():
		await _clear_calls()
		return
	var casualty := down[0] as Casualty

	# **In among them, not off to one side.** Placed clear of the fight this is a
	# disorder call and a medical call that happen to share a street, and the cordon
	# stops being the answer -- which is the entire reason the kind exists.
	var nearest := INF
	for node in suspects:
		nearest = minf(nearest,
			_flat_distance((node as Node3D).global_position, casualty.global_position))
	_check(nearest <= 6.0,
		"lying within reach of the crowd (%.1fm)" % nearest)

	_check(_officer.resolve(_target_for(suspects[0] as Suspect)) is ApprehendAbility,
		"an officer arrests (%s)"
		% _resolved_id(_officer, _target_for(suspects[0] as Suspect)))
	_check(_paramedic.resolve(_target_for(casualty)) is TreatAbility,
		"a paramedic treats (%s)" % _resolved_id(_paramedic, _target_for(casualty)))
	_check(_find_ability(_officer, &"secure") != null,
		"and the officer carries the cordon that buys the medic room")
	await _clear_calls()


## Two written-off cars and three casualties -- and the call is withheld until somebody
## on the books owns a winch, which is the opposite of how `rtc` handles the same unit.
func _test_a_pile_up_waits_for_a_recovery_truck() -> void:
	await _clear_calls()
	var kept := _station.owned.duplicate()

	# **The gate, over a couple of thousand rolls rather than one.** A single draw that
	# missed `pile_up` would pass with no gate at all -- it is 8 of 294.
	_station.owned = {&"patrol": 2, &"ambulance": 1}
	var offered := {}
	_director._rng.seed = 5
	for i in 2000:
		offered[_director._pick_kind()] = true
	_check(not offered.has(&"pile_up"),
		"a career with no recovery truck is never dealt one (%d kinds drawn)"
		% offered.size())
	_check(offered.has(&"rtc"),
		"while the ordinary collision it grew out of still comes round")

	_station.owned = {&"patrol": 2, &"ambulance": 1, &"truck": 1}
	offered = {}
	for i in 2000:
		offered[_director._pick_kind()] = true
	_check(offered.has(&"pile_up"), "buying the truck unlocks it")

	_station.owned = kept
	_station._save_career()

	# **The scene itself.** 14m is Call.GROUPING_RADIUS, to a centroid that moves as each
	# incident is adopted -- so a layout any wider arrives as two calls sharing a
	# crossroads, and the "one call" leg below is what watches for that.
	_director._rng.seed = 61
	var junction := _director._pick_junction()
	if junction.x < 0:
		_check(false, "a junction to put it at")
		return
	_director._spawn_pile_up(junction)
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"two wrecks and three casualties are one call (%d)" % open.size())
	if open.is_empty():
		return
	_check("Multi-vehicle" in open[0].title(),
		"named by the wrecks ('%s')" % open[0].title())

	# **The group, not `_wrecks()`.** That helper matches children named `SM_Veh_*` --
	# the loose car *bodies* a vehicle fire leaves at the kerb. A `Wreck` is an incident
	# named `Wreck` that carries its car as a child, so the helper found none and this
	# check failed on a scene that was in fact correct.
	var wrecks := get_nodes_in_group(Wreck.WRECK_GROUP)
	var down := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(wrecks.size() == 2, "two cars written off (%d)" % wrecks.size())
	_check(down.size() == 3,
		"three casualties, against one ambulance's two stretchers (%d)" % down.size())
	if wrecks.size() < 2 or down.size() < 3:
		await _clear_calls()
		return

	# **Nobody is under a car.** The single collision shipped with its casualties inside
	# the wreck's 5.5m blocker and unreachable; with two wrecks the setback that fixed
	# that one is not enough, so this asserts the clearance rather than assuming it.
	var closest := INF
	for wreck in wrecks:
		for node in down:
			closest = minf(closest, _flat_distance(
				(wreck as Node3D).global_position, (node as Node3D).global_position))
	_check(closest > Wreck.CLEAR_RADIUS,
		"every casualty is outside both blockers (nearest %.1fm, needs %.1f)"
		% [closest, Wreck.CLEAR_RADIUS])

	_buy(&"truck", 1)
	var truck := _station.dispatch(&"truck") as Vehicle
	if truck == null:
		_check(false, "a recovery truck to send")
		await _clear_calls()
		return
	var wreck_target := _target_for(wrecks[0] as Wreck)
	_check(truck.resolve(wreck_target) is ClearAbility,
		"the truck is offered the winch (%s)" % _resolved_id(truck, wreck_target))
	_check(_paramedic.resolve(_target_for(down[0] as Casualty)) is TreatAbility,
		"and medical still has three people to get to (%s)"
		% _resolved_id(_paramedic, _target_for(down[0] as Casualty)))
	_dissolve(truck, &"truck")
	await _clear_calls()


## A tanker down at the kerb: a hazard, a fire cooking it, the road shut, and somebody
## hurt past the blockage.
func _test_a_spill_shuts_the_road_around_a_hazard() -> void:
	await _clear_calls()
	_director._rng.seed = 29
	_director._spawn_spill()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"the tank, the load and the casualty are one call (%d)" % open.size())
	if open.is_empty():
		return
	_check("Tanker spill" in open[0].title(),
		"named by the tank ('%s')" % open[0].title())

	var hazards := get_nodes_in_group(Hazard.HAZARD_GROUP)
	var debris := get_nodes_in_group(Debris.DEBRIS_GROUP)
	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	var down := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(hazards.size() == 1, "one tank (%d)" % hazards.size())
	_check(debris.size() == 1, "one load across the road (%d)" % debris.size())
	_check(down.size() == 1, "one casualty (%d)" % down.size())
	if hazards.is_empty() or down.is_empty():
		await _clear_calls()
		return
	var hazard := hazards[0] as Hazard
	var casualty := down[0] as Casualty

	# **The fire is load-bearing, not scenery.** Hazard heats only from a Fire inside
	# `heat_range` and finishes only once it has been threatened *and* cooled -- so a
	# tank with nothing burning near it neither resolves nor blows, and the call would
	# sit on the board until overrun_grace failed it. This is that hang, asserted.
	_check(fires.size() == 1, "with something burning beside it (%d)" % fires.size())
	if not fires.is_empty():
		var heat_gap := _flat_distance(
			(fires[0] as Node3D).global_position, hazard.global_position)
		_check(heat_gap < hazard.heat_range,
			"close enough to actually cook it (%.1fm, range %.1f)"
			% [heat_gap, hazard.heat_range])

	# **Outside the blast, inside the call.** A casualty within blast_range dies to one
	# slow minute -- blast_harm is 1.2 against 1.0 of health -- which would make this a
	# call that punishes rather than one that presses.
	var blast_gap := _flat_distance(casualty.global_position, hazard.global_position)
	_check(blast_gap > hazard.blast_range,
		"the casualty lies outside the blast radius (%.1fm, radius %.1f)"
		% [blast_gap, hazard.blast_range])
	_check(blast_gap <= Call.GROUPING_RADIUS,
		"but inside the grouping radius, so it stays one job (%.1fm)" % blast_gap)

	_buy(&"firefighter", 1)
	var firefighter := _station.dispatch(&"firefighter") as Person
	if firefighter == null:
		_check(false, "a firefighter to send")
		await _clear_calls()
		return
	firefighter.global_position = hazard.global_position + Vector3(0.0, 0.0, 6.0)
	_check(firefighter.resolve(_target_for(hazard)) is CoolAbility,
		"a firefighter is offered the hose on the tank (%s)"
		% _resolved_id(firefighter, _target_for(hazard)))
	_check(_paramedic.resolve(_target_for(casualty)) is TreatAbility,
		"and a paramedic the person past it (%s)"
		% _resolved_id(_paramedic, _target_for(casualty)))
	_dissolve(firefighter, &"firefighter")
	await _clear_calls()


## A robbery on the pavement: the one call no single service can finish.
##
## Three claims, and the third is the one that earns the kind. That it opens as one call
## with two armed suspects and a casualty; that the ARV gate holds both ways; and that the
## **disarm ladder is asked of three different units** -- an ordinary officer gets Move on
## an armed robber, armed response gets Disarm, and a paramedic gets Treat on the casualty
## regardless of either. Without that third part this is a `crime` call with a bigger
## number of suspects.
func _test_an_armed_robbery_needs_the_arv_and_a_paramedic() -> void:
	await _clear_calls()
	var kept := _station.owned.duplicate()

	# **The gate, over a couple of thousand rolls rather than one.** A single draw that
	# missed it would pass with no gate at all -- it is 5 of 299, the rarest row here.
	_station.owned = {&"patrol": 2, &"ambulance": 1}
	var offered := {}
	_director._rng.seed = 11
	for i in 2000:
		offered[_director._pick_kind()] = true
	_check(not offered.has(&"armed_robbery"),
		"a career with no armed response is never dealt one (%d kinds drawn)"
		% offered.size())
	_check(offered.has(&"crime"),
		"while the ordinary crime call still comes round")

	_station.owned = {&"patrol": 2, &"ambulance": 1, &"arv": 1}
	offered = {}
	for i in 2000:
		offered[_director._pick_kind()] = true
	_check(offered.has(&"armed_robbery"), "buying armed response unlocks it")

	_station.owned = kept
	_station._save_career()

	_director._rng.seed = 31
	_director.open_kind(&"armed_robbery")
	await _idle(10)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"two robbers and a casualty are one call (%d)" % open.size())
	if open.is_empty():
		return
	_check("Armed robbery" in open[0].title(),
		"named by the robbers ('%s')" % open[0].title())

	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	var down := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(suspects.size() == 2, "two of them came out (%d)" % suspects.size())
	_check(down.size() == 1, "with one person hurt (%d)" % down.size())
	if suspects.size() < 2 or down.is_empty():
		await _clear_calls()
		return
	var armed := 0
	for node in suspects:
		if (node as Suspect).armed:
			armed += 1
	_check(armed == 2, "both carrying (%d of %d)" % [armed, suspects.size()])

	# **The scene is dressed, and the dressing cannot stall a car.** A Heist prop ships
	# wrapped in a StaticBody3D; left in, it would stop the patrol car sent to take the
	# arrest away, which is the same trap the shed load's truck and the ARV's own pistol
	# both had to be stripped for.
	var props := 0
	var solid := 0
	for child in _incidents.get_children():
		if not ("Money" in str(child.name) or "Duffle" in str(child.name)
				or "Shard" in str(child.name)):
			continue
		props += 1
		for node in _descendants(child):
			if node is StaticBody3D or node is CollisionShape3D:
				solid += 1
	_check(props > 0, "the takings are on the pavement (%d props)" % props)
	_check(solid == 0,
		"and none of them can stall a car (%d bodies)" % solid)

	# **The ladder, asked of three units.** Both sides of the ARV gate, plus the medical
	# half that is deliberately independent of it -- a paramedic does not wait for the
	# scene to be made safe, because nothing in this model makes an armed suspect dangerous
	# to a bystander. See _spawn_armed_robbery for why that is stated rather than assumed.
	var robber := _target_for(suspects[0] as Suspect)
	_buy(&"arv", 1)
	var arv := _station.dispatch(&"arv") as Person
	if arv == null:
		_check(false, "an ARV to send")
		await _clear_calls()
		return
	_check(_officer.resolve(robber) is MoveAbility,
		"an ordinary officer right-clicking an armed robber gets Move (%s)"
		% _resolved_id(_officer, robber))
	_check(arv.resolve(robber) is DisarmAbility,
		"armed response is offered Disarm (%s)" % _resolved_id(arv, robber))
	_check(_paramedic.resolve(_target_for(down[0] as Casualty)) is TreatAbility,
		"and the paramedic can work without waiting for either (%s)"
		% _resolved_id(_paramedic, _target_for(down[0] as Casualty)))

	# **Disarmed, the arrest is anybody's** -- which is the whole point of the £550, and
	# the leg that says the gate is a *sequence* rather than a permanent lockout.
	# **The transition, not the post-state.** This asserted only `not armed` after the call
	# to `disarm()`, which is trivially true of a suspect who was never armed: under the
	# sabotage that set `armed = false` at spawn it stayed green while the leg five above
	# it printed `both carrying (0 of 2)` in the same run. It would pass with `disarm()`
	# deleted outright. The leg below inherits the weakness -- an unarmed suspect was
	# always arrestable -- so the two were inert together, and naming the before-state is
	# what gives both of them something to stand on.
	var target_robber := suspects[0] as Suspect
	var was_armed := target_robber.armed
	target_robber.disarm(1.0)
	await _idle(4)
	_check(was_armed and not target_robber.armed,
		"talking one down takes the weapon away (carrying %s, then %s)"
		% [was_armed, target_robber.armed])
	_check(_officer.resolve(robber) is ApprehendAbility,
		"and then an ordinary officer can make the arrest (%s)"
		% _resolved_id(_officer, robber))

	_dissolve(arv, &"arv")
	await _clear_calls()


## The police half of the casualty loop, end to end: a suspect on the board as a
## Disturbance, an officer's Apprehend, a patrol car's Escort, and the drive back to
## the station booking them in -- with the medical service locked out of all of it.
func _test_a_disturbance_is_arrested_and_delivered() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	var spot := Vector3(20.0, 0.0, -20.0)
	var suspect := _director._spawn_suspect(spot)
	await _idle(6)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Disturbance"
			and open[0].kind == Call.Kind.CRIME,
		"a suspect opens a crime call ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	_check(_find_ability(_officer, &"apprehend") != null,
		"an officer is offered Apprehend")
	_check(_find_ability(_paramedic, &"apprehend") == null,
		"a paramedic is not")
	# Escort moved from the patrol car to the officer in August 2026: an arrest is made
	# on foot and the walk to the car is too, exactly as the stretcher run is the
	# paramedic's rather than the ambulance's.
	_check(_find_ability(_officer, &"escort") != null,
		"an officer is offered Escort")
	_check(_find_ability(_car, &"escort") == null,
		"and the patrol car is not -- it no longer collects anybody")
	_check(_find_ability(_paramedic, &"escort") == null,
		"nor a paramedic")
	var medic_verb := _paramedic.resolve(_target_for(suspect))
	_check(medic_verb != null and medic_verb.id() == &"move",
		"right-clicking the suspect with a paramedic means Move (got '%s')"
		% ("none" if medic_verb == null else medic_verb.id()))

	# The arrest. Sped up so the check measures the loop, not the scuffle.
	suspect.detain_per_second = 2.0
	await _place_unit(_officer, spot + Vector3(4.0, 0.0, 0.0))
	var verb := _officer.resolve(_target_for(suspect))
	_check(verb != null and verb.id() == &"apprehend",
		"and with an officer it means Apprehend (got '%s')"
		% ("none" if verb == null else verb.id()))
	if verb == null:
		await _clear_calls()
		return
	_officer.issue(verb.make_order(_officer, _target_for(suspect)))
	var detained := false
	var fought := false
	var swung := false
	var squared_up := 0
	var swings := 0
	var player := suspect.get_node("Character/AnimationPlayer") as AnimationPlayer
	var face: Node3D = suspect.get_node("Character")
	for i in 600:
		await physics_frame
		if suspect.is_fighting:
			fought = true
			if player.current_animation in ["Punch_Jab", "Punch_Cross"]:
				swung = true
				# Punching *at* the officer, not at the air beside them.
				var towards := _officer.global_position - suspect.global_position
				towards.y = 0.0
				if towards.length() > 0.05:
					swings += 1
					if face.global_basis.z.normalized().dot(towards.normalized()) > 0.8:
						squared_up += 1
		if suspect.is_detained:
			detained = true
			break
	_check(detained, "the officer takes them into custody")
	_check(fought and swung,
		"and they fought it, swinging, until the cuffs went on (fought %s, swung %s)"
		% [fought, swung])
	_check(swings > 0 and squared_up == swings,
		"squared up to the officer rather than punching the air (%d of %d swings on target)"
		% [squared_up, swings])
	await _wait(90)
	_check(not suspect.is_fighting
			and player.current_animation not in ["Punch_Jab", "Punch_Cross"],
		"the fight ends with the arrest ('%s')" % player.current_animation)
	_check(not _board.open_calls().is_empty(),
		"the call stays open until they are booked in")

	# The walk in, to a car parked a short way off. The car stays put: it is the officer
	# who covers the ground now, which is the whole point of the move.
	await _place_unit(_car, spot + Vector3(14.0, 0.0, 0.0), PI * 0.5)
	var escort := _officer.resolve(_target_for(suspect))
	_check(escort != null and escort.id() == &"escort",
		"right-clicking a detained suspect with an officer means Escort (got '%s')"
		% ("none" if escort == null else escort.id()))
	if escort != null:
		_officer.issue(escort.make_order(_officer, _target_for(suspect)))
	# **Walked, not teleported.** Catch them in hand partway there: the old order put
	# the suspect inside the car from five metres away, and a check that only looked at
	# the end state could not tell the two apart.
	var walked := false
	var loaded := false
	for i in 900:
		await physics_frame
		if suspect.escorted_by == _officer:
			walked = true
		if suspect.is_loaded:
			loaded = true
			break
	_check(walked, "the officer takes them in hand and walks them")
	_check(loaded, "the suspect gets in the back")

	# The drive home. Placed rather than driven -- the route home has its own tests.
	await _place_unit(_car, _station.global_position + Vector3(0.0, 0.0, -2.0))
	var booked := false
	for i in 120:
		await physics_frame
		if _board.open_calls().is_empty():
			booked = true
			break
	_check(booked, "driving into the station books them in and clears the call")
	_check(_mission.arrests == 1, "the arrest is tallied (%d)" % _mission.arrests)
	_check(_mission.score == Mission.ARREST_POINTS + Mission.RESPONSE_BONUS,
		"and scored with the response bonus (%d, expected %d)"
		% [_mission.score, Mission.ARREST_POINTS + Mission.RESPONSE_BONUS])
	_check(_mission.earned == _mission.score,
		"an arrest pays what it scores (£%d)" % _mission.earned)

	# Crime stays kerbside. The escort reach bridges road edge to pavement tile but
	# no further, so every spot the picker offers must stand against a road -- a
	# suspect in a park interior would be one no patrol car could ever collect.
	_director._rng.seed = 9
	var kerbside := true
	var offered := 0
	for i in 30:
		var pick := _director._pick_pavement(true)
		if pick == Vector3.INF:
			continue
		offered += 1
		if not _director._roadside(pick):
			kerbside = false
	_check(offered > 0 and kerbside,
		"every crime spot stands against a road (%d sampled)" % offered)

	_mission.scoring = false
	_reset_mission()
	await _clear_calls()


## A collapse with a bottle beside it, and the assessment comes back medical: the call
## carries on exactly as any other casualty, and the not-knowing is all it cost.
func _test_a_drunk_call_can_be_just_a_collapse() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 31
	_director._spawn_drunk()
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	if bodies.size() != 1:
		_check(false, "a drunk call is one casualty (%d)" % bodies.size())
		_stand_to()
		return
	var casualty := bodies[0] as Casualty
	_check(casualty.needs_assessment, "flagged as needing assessment")
	var propped := false
	for child in casualty.get_children():
		if str(child.scene_file_path).contains("SM_Item_"):
			propped = true
	_check(propped, "with the drink lying beside them")
	_check(casualty.describe_state() == "unresponsive -- cause unknown",
		"the readout commits to nothing ('%s')" % casualty.describe_state())
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Person collapsed, drink suspected",
		"and the board says only what was called in")

	# Force the roll medical, then work past the assessment threshold.
	casualty.turns_rowdy = false
	casualty.treat(0.5)
	await _idle(4)
	_check(is_instance_valid(casualty) and casualty.active
			and not casualty.needs_assessment,
		"the assessment comes back medical and the casualty stays a casualty")
	_check(get_nodes_in_group(Suspect.SUSPECT_GROUP).is_empty(),
		"nobody stood up swinging")
	casualty.treat(1.0)
	_check(casualty.is_stable, "and they stabilise like anyone else")
	_stand_to()
	await _clear_calls()


## The other half of the roll: they were never hurt at all. The suspect stands up in the
## casualty's own clothes, the *same* call flips to crime rather than closing, and
## nobody is paid or penalised for a patient that never existed.
func _test_a_drunk_call_can_turn_into_an_arrest() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 37
	_director._spawn_drunk()
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	if bodies.size() != 1:
		_check(false, "a drunk call is one casualty (%d)" % bodies.size())
		_stand_to()
		return
	var casualty := bodies[0] as Casualty
	var call: Call = null
	if not _board.open_calls().is_empty():
		call = _board.open_calls()[0]
	var worn := str(casualty.get_node("Character").scene_file_path)
	var spot := casualty.global_position
	var saved_before := _mission.casualties_saved
	var lost_before := _mission.casualties_lost
	var arrests_before := _mission.arrests

	casualty.turns_rowdy = true
	casualty.treat(0.5)
	await _idle(8)

	_check(not is_instance_valid(casualty),
		"the casualty is gone -- there was never a patient")
	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	if suspects.size() != 1:
		_check(false, "one suspect stood up (%d)" % suspects.size())
		_stand_to()
		await _clear_calls()
		return
	var suspect := suspects[0] as Suspect
	_check(_flat_distance(suspect.global_position, spot) < 1.0,
		"where the casualty lay (%.1fm off)"
		% _flat_distance(suspect.global_position, spot))
	_check(str(suspect.get_node("Character").scene_file_path) == worn,
		"wearing the same clothes")
	# **The call survives the swap.** The deferred-adopt trap pinned: the suspect must
	# be in the call's list before the casualty leaves it, or the list empties and the
	# call closes RESOLVED -- banking a cleared call and a response bonus for a job
	# nobody did. Sabotage map: reddened by re-staging the swap retire-first (suspect
	# spawned frames after the free); deleting only the frame-wait keeps it green,
	# because the add-before-retire ordering alone holds the list non-empty -- the
	# wait is margin, not the mechanism.
	var held := call != null and is_instance_valid(call) and call.is_open()
	_check(held, "the same call is still open")
	_check(held and call.kind == Call.Kind.CRIME, "and now reads as crime")
	_check(held and call.title() == "Drunk and disorderly",
		"under its new name ('%s')" % (call.title() if held else "?"))
	_check(_mission.casualties_saved == saved_before
			and _mission.casualties_lost == lost_before,
		"and the medical ledger never moved")

	# Book them in from code -- the walk and the drive have their own tests.
	suspect.detain(1.0)
	suspect.deliver()
	await _idle(6)
	_check(_board.open_calls().is_empty(), "the arrest closes the call")
	_check(_mission.arrests == arrests_before + 1,
		"and is tallied (%d)" % _mission.arrests)
	_stand_to()
	await _clear_calls()


## The first call the player searches: a marked report where the child was last seen,
## and an unmarked child strolling the walk graph a genuine walk away. The marker's
## honesty is the whole design -- it points at what is known, not at the answer.
func _test_a_missing_child_call_stages_a_search() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 41
	_director._spawn_missing_child()
	await _idle(6)

	var reports: Array[Node] = []
	for node in get_nodes_in_group(Incident.GROUP):
		if node is MissingChild:
			reports.append(node)
	if reports.size() != 1:
		_check(false, "a missing-child call is one report (%d)" % reports.size())
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].kind == Call.Kind.CRIME,
		"a missing person is police work on the board")
	_check(not open.is_empty() and open[0].title() == "Child reported missing",
		"named for the report ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	var child := report.child
	if child == null or not is_instance_valid(child):
		_check(false, "a child to search for")
		_stand_to()
		await _clear_calls()
		return
	var gap := _flat_distance(child.global_position, report.global_position)
	_check(gap >= 40.0, "the child is a genuine journey from the report (%.0fm)" % gap)
	# The marker's honesty: the call sits on the report, never on the child.
	_check(not open.is_empty()
			and _flat_distance(open[0].position, report.global_position) < 5.0,
		"the call's marker stands at the last-seen point")
	_check(not child.is_selectable(), "the child cannot be selected")
	_check(child.collision_layer == 128,
		"and lives on the crowd layer the picking ray ignores (%d)"
		% child.collision_layer)
	_check(not child.is_in_group(Incident.GROUP),
		"and is not an incident -- nothing on the board points at them")
	var body := child.get_node_or_null("Character") as Node3D
	_check(body != null and body.scale.x < 0.8,
		"a small figure reads as a child (scale %.2f)"
		% (body.scale.x if body else 0.0))

	# Teardown wiring: the child leaves with the report.
	await _clear_calls()
	_check(not is_instance_valid(child), "the child leaves with the report")
	_stand_to()


## The three beats: a person finds the child (vehicles driving past do not), the
## child walks at heel and climbs into a *police* car (an ambulance is refused), and
## the call closes only when that car pulls up back at the parent -- with the score
## landing on the reunion, not the find.
func _test_a_found_child_closes_the_call() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_mission.begin_scoring()
	_director._rng.seed = 43
	_director._spawn_missing_child()
	await _idle(6)

	var reports := get_nodes_in_group(Incident.GROUP).filter(
		func(node: Node) -> bool: return node is MissingChild)
	if reports.size() != 1:
		_check(false, "a missing-child call to work (%d)" % reports.size())
		await _end_freeplay()
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var child := report.child
	# Captured now, because every later dereference of `report` is guarded: a fault
	# that closes the call early frees it, and an unguarded read converts the red
	# assertions below into a SCRIPT ERROR that silently skips them -- measured, by
	# the sabotage run that came back green-looking with eleven checks missing.
	var home_spot := report.global_position

	# Attend the report first, so the response clock stops at once and the score
	# below is the deterministic sum -- the tightened-equality lesson from the
	# shed-load check.
	await _place_unit(_officer, home_spot + Vector3(2.0, 0.0, 0.0))
	await _idle(8)

	# A vehicle beside the child is not a find: the scan asks people only. Parked
	# outside board_reach so this stages only the question it asks.
	await _place_unit(_car, child.global_position + Vector3(5.5, 0.2, 0.0))
	await _wait(30)
	_check(is_instance_valid(report) and report.active and not report.found,
		"a patrol car driving up does not find a child")
	await _place_unit(_car, _station.global_position + Vector3(-6.0, 0.2, -2.5))

	# The find is the middle of the job, not the end.
	await _place_unit(_officer, child.global_position + Vector3(1.5, 0.0, 0.0))
	var taken := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(report) or not report.active:
			break
		if report.found:
			taken = true
			break
	_check(taken and is_instance_valid(child) and child.following == _officer,
		"an officer reaching the child takes them in hand")
	_check(is_instance_valid(report) and report.active
			and not _board.open_calls().is_empty(),
		"and finding them is not the end of the job -- the call stays open")
	if not is_instance_valid(report) or not is_instance_valid(child):
		# The reds above have already said what broke; bailing keeps a freed report
		# from converting the rest of this check into a silent skip.
		await _end_freeplay()
		_stand_to()
		return

	# A child is driven home in a patrol car, not stretchered home in an ambulance.
	await _place_unit(_ambulance, child.global_position + Vector3(2.0, 0.2, 0.0))
	await _wait(45)
	_check(child.riding == null,
		"an ambulance alongside them is not their ride")
	await _place_unit(_ambulance, _station.global_position + Vector3(6.0, 0.2, -2.5))

	await _place_unit(_car, child.global_position + Vector3(2.0, 0.2, 0.0))
	var aboard := false
	for i in 120:
		await physics_frame
		if child.riding == _car:
			aboard = true
			break
	_check(aboard, "a patrol car alongside them is")
	_check(not child.visible, "and they are riding, not walking beside it")
	# The child is 45m+ from home here, so a call that closes now has confused
	# boarding with arriving -- the reunion is at the parent, not at the kerb where
	# they were picked up.
	await _wait(30)
	_check(is_instance_valid(report) and report.active,
		"aboard is not home -- the call holds until the car gets there")

	# The drive home. Placed rather than driven -- the route has its own tests. The
	# destination is the captured spot, not a read of the possibly-freed report.
	await _place_unit(_car, home_spot + Vector3(4.0, 0.2, 0.0))
	var home := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(report) or not report.active:
			home = true
			break
	_check(home, "pulling up at the parent ends the job")
	await _idle(8)
	_check(_board.open_calls().is_empty(), "the reunion closes the call")
	_check(_mission.children_found == 1,
		"the debrief counts it (%d)" % _mission.children_found)
	_check(_mission.score == Mission.MISSING_POINTS + Mission.RESPONSE_BONUS,
		"scored like a person recovered plus the response bonus (%d, expected %d)"
		% [_mission.score, Mission.MISSING_POINTS + Mission.RESPONSE_BONUS])
	_check(_mission.earned == _mission.score,
		"a reunion pays what it scores (£%d)" % _mission.earned)
	await _end_freeplay()
	_stand_to()


## The child is a civilian by construction, and three systems consume civilians: a
## medical call takes one, a disturbance recruits one, a blast converts one. Each
## taking the child would free the body its report is scanning for -- and the report
## then retires silently, closing the call for a job nobody did. All three exclusions
## in one staging: the child is parked in a quiet corner and each consumer is offered
## them directly.
func _test_the_missing_child_stays_out_of_other_calls() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 47
	_director._spawn_missing_child()
	await _idle(6)

	var reports := get_nodes_in_group(Incident.GROUP).filter(
		func(node: Node) -> bool: return node is MissingChild)
	if reports.size() != 1:
		_check(false, "a missing-child call to stage against (%d)" % reports.size())
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var child := report.child
	# Parked well clear of the report's own call, so the director's clearance rules
	# would offer them to a medical call but for the class exclusion.
	var corner := report.global_position
	for point in CityGrid.pavement_points():
		if _flat_distance(point, report.global_position) > 60.0:
			corner = point
			break
	child.global_position = corner
	child.wander_centre = corner
	await _idle(4)

	# **One civilian parked somewhere provably eligible, first.**
	#
	# The second half of this check reads the *pool*, and the pool is every civilian
	# standing clear of every open call. By this point in the suite the board is busy
	# and the crowd has wandered, so on some runs the pool is empty and the check fails
	# on a picker that is working perfectly -- it went red in a Stop gate having passed
	# on the re-run before it, which is the worst way for a suite to behave.
	#
	# Staging a stand-in makes the assertion about the thing it is named for: the child
	# is excluded *and* somebody else is not. The point is chosen the same way the
	# child's corner was, and asked of the director's own clearance rule rather than a
	# distance guessed here.
	var stand_in: Civilian = null
	# The suite *is* the SceneTree, so groups are read off it directly.
	for node in get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian and not (civilian is ChildWanderer):
			stand_in = civilian
			break
	if stand_in:
		for point in CityGrid.pavement_points():
			if _flat_distance(point, corner) > 40.0 and _director._clear(point):
				# Position only: `wander_centre` belongs to the child's wanderer, not to
				# an ordinary civilian, and assigning it here threw -- which abandoned
				# the rest of this check and cost four more without a FAIL line.
				stand_in.global_position = point
				stand_in.is_fleeing = false
				break
		await _idle(4)
	_check(stand_in != null and _director._clear(stand_in.global_position),
		"a civilian stood somewhere a medical call could take them")

	# The medical call's picker. Two hundred seeded draws: none may be the child, and
	# at least one must be somebody -- a picker that returns nothing proves nothing.
	_director._rng.seed = 3
	var drew_child := false
	var drew_anyone := false
	for i in 200:
		var pick := _director._pick_civilian()
		if pick is ChildWanderer:
			drew_child = true
		elif pick != null:
			drew_anyone = true
	_check(not drew_child and drew_anyone,
		"a medical call never takes the child (200 draws, someone else %s)"
		% drew_anyone)

	# The disturbance's recruiter, offered the child at point-blank range. The clock
	# is lowered the way the disorder test lowers it -- the recruit interval latches
	# at a full 9s in _ready, and a 4s window against that never reaches the
	# exclusion at all. Measured: the first cut of this line stayed green with the
	# exclusion deleted, because _draw_one_in had never once run.
	var suspect := _spawn_suspect(corner + Vector3(2.0, 0.0, 0.0))
	suspect.recruits = true
	suspect.max_group = 8
	suspect.recruit_interval = 0.5
	await _wait(240)
	_check(is_instance_valid(child) and child is ChildWanderer,
		"a disturbance never recruits the child")

	# The blast, applied to the child's own doorstep.
	var hazard := (load("res://Game/Incidents/Hazard.tscn") as PackedScene) \
		.instantiate() as Hazard
	if hazard:
		_incidents.add_child(hazard)
		hazard.global_position = corner + Vector3(3.0, 0.0, 0.0)
		await _idle(4)
		hazard._hurt_people(child.global_position)
		await _idle(4)
	_check(is_instance_valid(child) and child is ChildWanderer,
		"a blast never converts the child")
	_check(is_instance_valid(report) and report.active,
		"and through all three the search stays open")

	await _clear_calls()
	_stand_to()


func _test_scoring_rewards_a_fast_response() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	# The officer is already standing at the scene when it opens, which is as fast as
	# a response can be: the bonus should not lose a point of its 100.
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
	var fire := _spawn_fire(spot, 0.5)
	await _idle(6)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to score")
		return
	_check(open[0].response_age >= 0.0,
		"the call recorded when it was first attended (%.1fs)" % open[0].response_age)

	var purse := _station.funds
	fire.douse(5.0)
	await _idle(6)
	_check(_mission.calls_cleared == 1,
		"the cleared call was counted (%d)" % _mission.calls_cleared)
	var expected := Mission.FIRE_POINTS + Mission.RESPONSE_BONUS
	_check(_mission.score == expected,
		"a fast attendance earns fire points plus the full bonus (%d, expected %d)"
		% [_mission.score, expected])
	_check(_station.funds - purse == expected and _mission.earned == expected,
		"and the same number lands in the purse as pounds (£%d banked)"
		% (_station.funds - purse))


func _test_a_slow_response_scores_at_the_floor() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	var spot := Vector3(20.0, 0.0, -20.0)
	var fire := _spawn_fire(spot, 0.5)
	await _idle(6)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to keep waiting")
		return
	# Nobody comes for 80 seconds -- said rather than sat through.
	open[0].age = 80.0
	await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
	await _idle(6)
	_check(open[0].response_age >= 60.0,
		"the wait went on the record (%.1fs)" % open[0].response_age)

	var purse := _station.funds
	fire.douse(5.0)
	await _idle(6)
	var expected := Mission.FIRE_POINTS \
		+ roundi(Mission.RESPONSE_BONUS * Mission.RESPONSE_FLOOR)
	_check(_mission.score == expected,
		"a response that slow earns only the floor of the bonus (%d, expected %d)"
		% [_mission.score, expected])
	_check(_station.funds - purse == expected,
		"the multiplier squeezes the pay the same way (£%d)"
		% (_station.funds - purse))


func _test_a_lost_casualty_costs_points_not_the_shift() -> void:
	await _clear_calls()
	_mission.begin_scoring()
	var purse := _station.funds

	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -20.0))
	casualty.health = 0.05
	casualty.decline_per_second = 0.5
	await _wait(30)
	_check(_mission.state == Mission.State.RUNNING,
		"freeplay survives a lost casualty -- the shift goes on (%d)" % _mission.state)
	_check(_mission.score == -Mission.LOST_PENALTY,
		"the loss is charged to the score (%d)" % _mission.score)
	_check(_mission.calls_failed == 1,
		"and the call goes down as failed (%d)" % _mission.calls_failed)
	_check(_station.funds == purse,
		"but never to the purse -- a struggling career is not fined into the ground")
	await _clear_calls()


func _test_the_shift_ends_with_a_summary() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 5
	_director.shift_length = 1.5
	_director.first_call_delay = 0.3
	_director.call_interval_min = 5.0
	_director.call_interval_max = 5.0
	_director.max_open_calls = 1
	_director.breather = 0.2
	_director.begin_shift()

	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to finish the shift on")
		await _end_freeplay()
		return
	# Past the end of the shift with the call still open: it must not end early.
	await _wait(90)
	_check(_mission.state == Mission.State.RUNNING,
		"time running out does not end a shift with a job on the board (%d)"
		% _mission.state)

	# **Every open call, not just the first.** A collision leaves a written-off car behind
	# it now, so one incident on the board can outlive the casualties that opened it --
	# which is the point of the wreck. Clearing one job and expecting the shift to end was
	# an assumption that only held while every call finished in one go.
	for call in _board.open_calls().duplicate():
		_resolve_call(call)
	var over := false
	for i in 120:
		await physics_frame
		if _mission.state == Mission.State.OVER:
			over = true
			break
	_check(over, "the shift ends once the last call clears (%d)" % _mission.state)
	_check(not _director.active, "and the director stands down")

	# The card carries its own heading, so the banner and the one-line debrief both
	# stand down at the end of a shift rather than repeating above a table that says
	# the same thing at length. Both used to be the debrief; this asserts they are not
	# still showing under it.
	var banner := _scene.get_node_or_null("HUD/Root/World/Banner") as Label
	var debrief := _scene.get_node_or_null("HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	_check(card != null and card.visible, "the debrief card is what announces the end")
	_check(banner != null and not banner.visible
			and debrief != null and not debrief.visible,
		"and the banner and the old one-line debrief stand down under it")
	# The shift's actual record reached the card, not just a card.
	var shown := PackedStringArray()
	if card:
		for line in card.get_child(0).get_child(0).get_child(0).get_children():
			for cell in line.get_children():
				var text := cell as Label
				if text:
					shown.append(text.text)
	var joined := " ".join(shown)
	_check("Calls cleared" in joined and "1" in joined,
		"carrying the shift's own record ('%s')" % joined)
	# Deliberately not resetting the mission here: the next test starts a new shift
	# over this debrief and has to clear it, exactly as a player would see it.


func _test_freeplay_key_starts_the_shift() -> void:
	# Parked out of the way so the new shift opens no calls while it is under test.
	_director.first_call_delay = 999.0
	_director.shift_length = 9999.0
	await _press_key(KEY_F2)
	await _idle(4)
	_check(_director.active, "F2 opens a shift")
	_check(_mission.scoring and _mission.state == Mission.State.RUNNING,
		"scoring is live (%s, state %d)" % [_mission.scoring, _mission.state])

	var banner := _scene.get_node_or_null("HUD/Root/World/Banner") as Label
	_check(banner != null and not banner.visible,
		"and starting a new shift clears the last debrief")

	var before: float = _director.clock
	await _press_key(KEY_F2)
	await _idle(4)
	_check(_director.active and _director.clock >= before,
		"a second press does not restart the shift (%.2f -> %.2f)"
		% [before, _director.clock])
	await _end_freeplay()


## The debrief score outlives the window: the best shift is banked to disk and every
## later one is measured against it. This is the project's only save-shaped code, so
## the reload is exercised too.
func _test_the_best_score_survives() -> void:
	await _clear_calls()
	_mission.begin_scoring()
	_mission.score = 9999
	_mission.end_shift()
	_check(_mission.is_new_best and _mission.best_score == 9999,
		"a record shift becomes the new best (%d)" % _mission.best_score)
	_check("NEW BEST" in _mission.summary(),
		"and the debrief says so ('%s')" % _mission.summary())

	# The next session: a fresh load finds the banked record.
	_mission.best_score = 0
	_mission._load_records()
	_check(_mission.best_score == 9999,
		"the record survives a reload (%d)" % _mission.best_score)

	_mission.begin_scoring()
	_mission.score = 120
	_mission.end_shift()
	_check(not _mission.is_new_best and _mission.best_score == 9999,
		"an ordinary shift does not disturb it (best still %d)" % _mission.best_score)
	_check("BEST 9999" in _mission.summary(),
		"and its debrief shows the bar to clear")
	_mission.scoring = false
	_reset_mission()


## The end-of-shift debrief as a table, and the average response inside it.
##
## The average is the part worth checking, because it is the one number on the card the
## mission has to *accumulate* rather than count -- everything else is a tally that was
## already there. It is fed from the same figure the response bonus is paid on, which
## the shift had been using and throwing away.
func _test_the_debrief_reads_as_a_table() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	_check(_mission.average_response() < 0.0,
		"a shift that has cleared nothing has no average response to give (%.1f)"
		% _mission.average_response())

	# Two calls attended at different speeds, so the mean is a mean of something.
	#
	# **Both waits are substantial, and that is the point.** The first version used a
	# near-instant arrival (~0.1s) against a slow one, and was vacuous: with one sample
	# contributing almost nothing, a `=` instead of a `+=` moved the mean by 0.05s --
	# invisible inside any sane tolerance -- and a missing divide landed at 3.2 against
	# a range whose upper edge was 3.6. It passed against both of the faults its own
	# comment named. Two comparable waits make the arithmetic discriminating: 2s and 6s
	# mean the true average is 4.0, last-value-wins gives 3.0, and a missing divide
	# gives 8.0.
	var waits := []
	for run in [{"at": Vector3(20.0, 0.0, -20.0), "wait": 120}, \
			{"at": Vector3(-24.0, 0.0, 24.0), "wait": 360}]:
		var spot: Vector3 = run["at"]
		var fire := _spawn_fire(spot, 0.5)
		await _idle(6)
		# The slow one is left alone for a while before anybody arrives.
		await _idle(int(run["wait"]))
		await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
		await _idle(10)
		var open := _board.open_calls()
		if not open.is_empty():
			waits.append(open[0].response_age)
		fire.douse(5.0)
		await _idle(8)

	_check(_mission.calls_cleared == 2,
		"two calls cleared at different speeds (%d)" % _mission.calls_cleared)
	var mean := _mission.average_response()
	_check(mean > 0.0, "the shift has an average response (%.1fs)" % mean)
	# Against the arithmetic mean itself, not against a range containing it. "Between
	# the two" is far too weak a claim: a sum that never divided, and a total that kept
	# only the last call, both sit inside that range for these numbers.
	if waits.size() == 2:
		var low: float = minf(waits[0], waits[1])
		var high: float = maxf(waits[0], waits[1])
		var expected := (low + high) * 0.5
		_check(absf(mean - expected) < 0.5,
			"and it is the mean of the two it averaged (%.1f, expected %.1f from "
			% [mean, expected] + "%.1f and %.1f)" % [low, high])
		_check(high - low > 2.0,
			"which were far enough apart to tell a mean from either (%.1fs apart)"
			% (high - low))

	# The card itself: rows, not a sentence.
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	_check(card != null, "the interface carries a debrief card")
	if card != null:
		var rows := _mission.debrief_rows()
		_check(rows.size() >= 5, "the debrief has rows to lay out (%d)" % rows.size())
		var labels := PackedStringArray()
		for row in rows:
			labels.append(str(row["label"]))
		var joined := " | ".join(labels)
		_check("Average response" in joined,
			"including the average response (%s)" % joined)
		card.show_shift(_mission)
		_check(card.visible, "and the card shows when a shift ends")
		# Every row reached the screen, plus the heading.
		var body := card.get_child(0).get_child(0).get_child(0) as VBoxContainer
		_check(body != null and body.get_child_count() == rows.size() + 1,
			"with every row drawn (%d children for %d rows and a heading)"
			% [body.get_child_count() if body else -1, rows.size()])
		card.hide_card()

	_mission.scoring = false
	_reset_mission()
	await _clear_incidents()
	await _clear_calls()


## A shift has to be able to *end*, even when one of its calls cannot be finished.
##
## Time running out deliberately does not end a shift -- you finish what you started,
## and the debrief waits for the board to clear. That rule assumed every open call can
## be cleared, and it cannot: a career with a paramedic and no ambulance treats a
## casualty to stable and then owns nothing that can collect them, so the call stays
## open for ever. Measured before the fix, a four-second shift was still running forty
## seconds later, and five played sessions in a row wrote no best-score record because
## not one of them ever reached a debrief. The overrun is the deadline that ends it.
func _test_a_shift_ends_even_with_an_unanswerable_call() -> void:
	await _clear_calls()
	await _park_the_shift()

	var kept_length := _director.shift_length
	var kept_grace := _director.overrun_grace
	var kept_delay := _director.first_call_delay
	# No rolled calls; this stages the one call it cares about.
	_director.first_call_delay = 99999.0
	_director.shift_length = 1.0
	_director.overrun_grace = 3.0
	_director.begin_shift()
	await _idle(4)

	# A casualty treated to stable, with nothing on the map that can carry them. The
	# ambulance is parked but its Collect is the paramedic's stretcher run, so simply
	# not ordering it leaves the call genuinely outstanding.
	var spot := Vector3(26.0, 0.0, 26.0)
	var casualty := _spawn_casualty(spot)
	await _idle(6)
	casualty.treat(2.0)
	await _idle(8)
	_check(casualty.is_stable and not casualty.is_loaded,
		"a stabilised casualty nothing has collected")
	_check(_board.open_calls().size() == 1,
		"holds its call open (%d)" % _board.open_calls().size())

	# Well past the shift *and* its overrun.
	var ended := false
	for i in 60 * 8:
		await physics_frame
		if not _director.active:
			ended = true
			break
	_check(ended, "the shift stands down anyway at the overrun deadline (%.1fs of %.1f)"
		% [_director.clock, _director.shift_length + _director.overrun_grace])
	_check(_board.open_calls().is_empty(),
		"with the outstanding call closed (%d left)" % _board.open_calls().size())
	_check(_mission.calls_failed >= 1,
		"counted as failed rather than quietly forgotten (%d)" % _mission.calls_failed)
	_check(_mission.state == Mission.State.OVER,
		"and the mission reaches its debrief (%d)" % _mission.state)

	_director.shift_length = kept_length
	_director.overrun_grace = kept_grace
	_director.first_call_delay = kept_delay
	_mission.scoring = false
	_reset_mission()
	await _clear_incidents()
	await _clear_calls()


## Escape freezes the district: one flag, and everything PAUSABLE -- vehicles, fires,
## clocks, call ages -- stops together. The menu runs ALWAYS, which is what lets Escape
## also thaw it.
##
## Was `P` until August 2026. The key moved because Escape is where every other game puts
## it; what the move cost is that Escape already meant "cancel" twice over, which
## `_test_escape_cancels_before_it_pauses` is the check for.
func _test_pause_freezes_the_district() -> void:
	await _place(ROAD)
	_car.navigate_to(ROAD + Vector3(0.0, 0.0, -60.0))
	await _wait(30)
	_check(absf(_car.forward_speed) > 1.0,
		"a car is on the move (%.1f m/s)" % _car.forward_speed)

	await _press_key(KEY_ESCAPE)
	_check(_menu.visible and _menu.screen == GameMenu.Screen.PAUSE
			and paused,
		"Escape pauses the game and shows the menu")
	var held := _car.global_position
	await _wait(60)
	_check(_car.global_position.distance_to(held) < 0.05,
		"the district is frozen (%.2fm drift over a second)"
		% _car.global_position.distance_to(held))

	await _press_key(KEY_ESCAPE)
	_check(not _menu.visible and not paused, "Escape again resumes")
	await _wait(30)
	_check(_car.global_position.distance_to(held) > 1.0, "and the car drives on")
	_car.stop_navigating()


## Escape unwinds the innermost thing first: the shop closes, and the pause menu stays
## shut.
##
## The armed-ability half of this rule is checked where the ability is armed, in
## `_test_command_hotkeys_run_abilities`. This is the other claimant, and it is the one
## the tree order would get wrong on its own -- `GameMenu._input` runs *before*
## `RequisitionPanel._input`, so without the guard the pause card would open over an
## open shop.
func _test_escape_closes_the_shop_before_it_pauses() -> void:
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as RequisitionPanel
	if shop == null or _menu == null:
		_check(false, "a shop and a menu to arbitrate between")
		return
	# **The entry state, carried into the verdict below.** Found by sabotage: when the
	# guard is broken, the checks *before* this one leave the tree paused and the menu
	# already in PAUSE -- so this check's Escape *resumes* instead of pausing, and
	# "the pause menu was left alone" reads true on the very fault it exists to catch.
	# A probe in a clean tree confirmed the fault does reach it; the suite was simply
	# too contaminated by then for the reading to mean anything. Requiring a fit tree
	# turns that false green into an honest red.
	var was_clear: bool = _menu.screen == GameMenu.Screen.HIDDEN and not paused
	_check(was_clear, "the menu is down before the shop opens")

	shop.open_shop()
	await _idle(3)
	_check(shop.visible, "the shop is open")

	await _press_key(KEY_ESCAPE)
	_check(not shop.visible, "Escape closed the shop")
	_check(was_clear and not paused and _menu.screen != GameMenu.Screen.PAUSE,
		"and left the pause menu alone")

	# And with nothing to cancel, the same key does pause -- otherwise the guard above
	# could be an Escape handler that never fires at all.
	await _press_key(KEY_ESCAPE)
	_check(paused and _menu.screen == GameMenu.Screen.PAUSE,
		"with nothing open, Escape pauses")
	await _press_key(KEY_ESCAPE)
	await _idle(2)


## The speed buttons: the district genuinely runs faster, and normal puts it back.
##
## **Asserted on the shift clock, not on `Engine.time_scale`.** Reading back the property
## the button just set proves the button is wired to that property and nothing else --
## `Mission.elapsed` accumulates `delta`, so it can only double if the frames the rest of
## the game sees doubled too. The clock is also the flattest thing here to measure: a car
## would carry acceleration and steering into the number.
func _test_the_speed_buttons_run_the_district_faster() -> void:
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	if strip == null or _mission == null or _menu == null:
		_check(false, "a strip, a mission and a menu")
		return
	var speeds: Array[Button] = []
	for node in strip.find_children("*", "Button", true, false):
		var button := node as Button
		if button and button.toggle_mode:
			speeds.append(button)
	_check(speeds.size() == GameMenu.SPEEDS.size(),
		"the strip offers %d speeds (%d)" % [GameMenu.SPEEDS.size(), speeds.size()])
	if speeds.size() < GameMenu.SPEEDS.size():
		return

	var kept_state := _mission.state
	_mission.state = Mission.State.RUNNING

	speeds[0].pressed.emit()
	await _idle(2)
	var mark := _mission.elapsed
	await _idle(30)
	var normal: float = _mission.elapsed - mark

	speeds[2].pressed.emit()
	await _idle(2)
	mark = _mission.elapsed
	await _idle(30)
	var doubled: float = _mission.elapsed - mark

	_check(normal > 0.0 and doubled > normal * 1.7 and doubled < normal * 2.3,
		"2x runs the shift clock about twice as fast (%.2fs against %.2fs, 30 frames)"
		% [doubled, normal])

	# **Put the engine back, and check that putting it back works.** `Engine.time_scale`
	# is global and outlives a scene, so a suite that left here at 2x would hand every
	# later check a district running at double speed -- and the failures would land
	# anywhere but here.
	_menu.reset_speed()
	await _idle(2)
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"and normal speed puts the engine back (%.2f)" % Engine.time_scale)
	_mission.state = kept_state


## A designed shift, end to end: the picker offers it, the timeline opens its waves in
## order, the win is held back until the last one, and the debrief says what it came to
## against par.
##
## Driven through the menu rather than by making a ScenarioDirector by hand, because
## the wiring *is* the feature -- the node is created at runtime precisely so the
## generated district needs no new node in it, and a check that built one itself would
## never notice that path breaking.
## Losing a scenario offers another go instead of a word on the screen.
##
## **This was the campaign's live bug.** [member Mission.fail_on_casualty_lost] defaults
## true and no scenario overrode it, so one casualty dying ended a designed shift on a
## bare red banner -- no debrief, no par time, no retry -- in the one mode whose whole
## point is being replayed until it is beaten.
##
## Driven through the real card and the real runner: the loss is caused by killing a
## casualty and letting `_evaluate` reach its own verdict, and the retry is the button's
## own `pressed` signal, not a direct call to `restart()`. A check that set the state by
## hand and called `restart()` itself would pass with the HUD showing nothing at all.
func _test_a_lost_scenario_offers_another_go() -> void:
	await _clear_incidents()
	_reset_mission()
	_director.abandon_shift()
	await _idle(2)

	var index := -1
	for i in Scenarios.ALL.size():
		if Scenarios.ALL[i]["id"] == &"night_shift":
			index = i
	if index < 0:
		_check(false, "the night shift is on the card")
		return
	_menu.start_scenario(index)
	await _idle(3)
	var runner := _scene.get_node_or_null("ScenarioDirector") as ScenarioDirector
	if runner == null:
		_check(false, "picking one puts a runner in the district")
		return
	_check(_mission.fail_on_casualty_lost,
		"this scenario is one a death ends (%s)" % _mission.fail_on_casualty_lost)

	# Lose it the way a player would: somebody dies while the shout is running.
	var casualty := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
		.instantiate() as Casualty
	_incidents.add_child(casualty)
	casualty.global_position = _station.global_position + Vector3(0.0, 0.2, 14.0)
	await _idle(4)
	casualty._finish(false)
	await _idle(6)
	_check(_mission.state == Mission.State.LOST,
		"a death ends it (state %d)" % _mission.state)

	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	if card == null:
		_check(false, "the HUD carries a debrief card")
		return
	_check(card.visible, "and the card comes up rather than a bare banner")
	var again := card.find_child("Retry", true, false) as Button
	_check(again != null, "with a RETRY on it")
	if again == null:
		return

	# Through the button, not through `restart()`.
	runner.elapsed = 99.0
	again.pressed.emit()
	await _idle(6)
	_check(not card.visible, "pressing it puts the card away")
	_check(_mission.state == Mission.State.RUNNING,
		"and the shout is live again (state %d)" % _mission.state)
	_check(runner.elapsed < 1.0,
		"from the top -- the timeline is back at zero (%.1fs)" % runner.elapsed)

	runner.queue_free()
	await _idle(2)
	await _clear_incidents()
	_reset_mission()


func _test_a_scenario_plays_its_timeline() -> void:
	await _clear_incidents()
	_reset_mission()
	_director.abandon_shift()
	await _idle(2)

	# A scenario the suite's fleet can actually field. The police one: the suite buys
	# patrols and officers, and asserting on a scenario whose units nobody owns would
	# be asserting on the picker's refusal instead.
	var index := -1
	for i in Scenarios.ALL.size():
		if Scenarios.ALL[i]["id"] == &"night_shift":
			index = i
	_check(index >= 0, "the night shift is on the card")
	if index < 0:
		return
	var scenario: Dictionary = Scenarios.by_index(index)
	_check(Scenarios.missing_for(scenario, _station).is_empty(),
		"and this career can field it (%s)"
		% ", ".join(PackedStringArray(Scenarios.missing_for(scenario, _station))))

	_menu.open_scenarios()
	await _idle(2)
	_check(_menu.screen == GameMenu.Screen.SCENARIOS,
		"the picker opens (screen %d)" % _menu.screen)

	_menu.start_scenario(index)
	await _idle(2)
	var runner := _scene.get_node_or_null("ScenarioDirector") as ScenarioDirector
	_check(runner != null, "picking one puts a runner in the district")
	if runner == null:
		return
	_check(not _menu.visible and _mission.par_seconds == scenario["par"],
		"the card lifts and the mission takes its par (%.0fs)" % _mission.par_seconds)
	# The freeplay director must stay stood down: a scenario is a shout, not a shift,
	# and a scoring mission would switch the scripted win rule off entirely.
	_check(not _director.active and not _mission.scoring,
		"with freeplay left alone (active %s, scoring %s)"
		% [_director.active, _mission.scoring])

	# Hurried along rather than waited out: the real timeline is 55 seconds and this
	# is checking the order, not the arithmetic of a clock.
	#
	# On the runner's own **copy**. `Scenarios.ALL` is a const, and a const's nested
	# dictionaries are read-only at runtime -- writing to one throws, and a throw
	# inside a check silently abandons the rest of it. That is exactly what happened
	# here: six checks stopped running and the suite still called itself green apart
	# from the count. See the working notes in NEXT.md.
	var hurried := scenario.duplicate(true)
	for wave: Dictionary in hurried["waves"]:
		wave["at"] = 0.0
	runner.scenario = hurried
	await _idle(30)
	var opened := get_nodes_in_group(Incident.GROUP).size()
	_check(opened > 0, "the timeline opens its calls (%d on the map)" % opened)
	_check(not _mission.more_to_come,
		"and lets go of the win once the last wave is out")

	# Clearing everything wins it, and the modal says so with a score of its own --
	# `scoring` is off, so Mission.score is zero throughout and shout_score is what
	# the card has to be reading.
	for node in get_nodes_in_group(Incident.GROUP):
		(node as Incident)._finish(true)
	await _idle(8)
	_check(_mission.state == Mission.State.WON,
		"clearing the last of it wins the scenario (%d)" % _mission.state)
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	var shown := PackedStringArray()
	if card and card.visible:
		for line in card.get_child(0).get_child(0).get_child(0).get_children():
			for cell in line.get_children():
				var text := cell as Label
				if text:
					shown.append(text.text)
	var joined := " ".join(shown)
	_check(card != null and card.visible and "Par" in joined,
		"and the debrief reports it against par ('%s')" % joined)

	runner.queue_free()
	await _clear_incidents()
	_reset_mission()
	_mission.par_seconds = 0.0
	await _idle(2)


func _test_the_menu_restarts_a_shift() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 4
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 5.0
	_director.call_interval_max = 5.0
	_director.max_open_calls = 2
	_director.breather = 0.2
	_director.begin_shift()
	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to restart away")
		await _end_freeplay()
		return
	_mission.score = 500

	_menu.open_pause()
	await _idle(2)
	await _menu.restart_shift()
	await _idle(8)
	_check(_director.active and _director.clock < 2.0,
		"restart opens a fresh shift (clock %.1f)" % _director.clock)
	_check(_board.open_calls().is_empty(), "with a clear board")
	_check(_mission.scoring and _mission.score == 0 and _mission.calls_cleared == 0,
		"and a zeroed score (%d, %d cleared)"
		% [_mission.score, _mission.calls_cleared])
	_check(not paused, "unpaused and playing")
	await _end_freeplay()


func _test_settings_shape_the_shift_and_survive() -> void:
	_menu.set_shift_minutes(10)
	_check(absf(_director.shift_length - 600.0) < 0.1,
		"a 10-minute shift reaches the director (%.0fs)" % _director.shift_length)
	_menu.set_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.1,
		"the volume slider drives the master bus (%.1f dB)"
		% AudioServer.get_bus_volume_db(0))

	# The next session: wipe the in-memory values and read the file back.
	_menu.shift_minutes = 5
	_menu.master_volume = 1.0
	_menu._load_settings()
	_check(_menu.shift_minutes == 10 and absf(_menu.master_volume - 0.5) < 0.01,
		"settings survive a reload (%d min, %.2f)"
		% [_menu.shift_minutes, _menu.master_volume])

	_menu.set_shift_minutes(5)
	_menu.set_volume(1.0)


## Every menu card fits the screen, and the settings card is one section tall.
##
## **The check that did not exist while the settings card grew to 770 of 900.** Overflow
## here is silent and total: `_card()` centres the panel with no clipping, so an over-tall
## card draws off both the top and the bottom and its rows stop being clickable -- the
## same fault the shop had at 964. Nothing measured any of it.
##
## Two traps decided the shape. The `CenterContainer` around each card is full-rect, so
## its rect is *always* the viewport and a check pointed at it passes for ever; the named
## `PanelContainer` inside is the node with a height. And a hidden `Control` has a zero
## rect, so a card must be **open** when it is measured -- which is why this drives the
## real openers rather than reading the cards off the tree.
func _test_every_menu_card_fits_the_screen() -> void:
	if _menu == null:
		_check(false, "a menu to measure")
		return
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var kept_screen := _menu.screen
	var too_tall := PackedStringArray()
	var spilled := PackedStringArray()

	for entry: Array in [["TitleCard", _menu.show_title],
			["PauseCard", _menu.open_pause], ["SettingsCard", _menu.open_settings],
			["ScenariosCard", _menu.open_scenarios],
			["ConfirmCard", _menu.ask_reset_career]]:
		(entry[1] as Callable).call()
		await _idle(3)
		var card := _menu.find_child(str(entry[0]), true, false) as Control
		# The title card is a full-rect page with a column in it rather than a centred
		# panel, and it is measured by its own check; skip it if it has no named panel.
		if card == null:
			continue
		var rect := card.get_global_rect()
		if not screen.encloses(rect):
			too_tall.append("%s %dx%d" % [entry[0], rect.size.x, rect.size.y])
		# **Contained is not the same as reachable.** A panel that fits while its contents
		# hang out of it is exactly the shape of the bug, which is why the shop's own fit
		# check walks its BUY buttons rather than its frame.
		for node in _descendants(card):
			var control := node as Control
			if control == null or not control.visible:
				continue
			if not (control is Button or control is HSlider):
				continue
			if not screen.encloses(control.get_global_rect()):
				spilled.append("%s/%s" % [entry[0], control.name])
	_check(too_tall.is_empty(), "every menu card fits the %dx%d viewport (%s)"
		% [screen.size.x, screen.size.y,
			"clear" if too_tall.is_empty() else ", ".join(too_tall)])
	_check(spilled.is_empty(), "and every control on them is reachable (%s)"
		% ("clear" if spilled.is_empty() else ", ".join(spilled)))

	# Each tab in turn, naming the tallest -- the number that decides how much room is
	# left for the settings still to come.
	_menu.open_settings()
	await _idle(3)
	var card_panel := _menu.find_child("SettingsCard", true, false) as Control
	var worst := 0.0
	var worst_tab := ""
	var slightest := INF
	for i in _menu._tab_buttons.size():
		_menu._tab_buttons[i].pressed.emit()
		await _idle(3)
		var tall: float = card_panel.get_global_rect().size.y
		slightest = minf(slightest, tall)
		if tall > worst:
			worst = tall
			worst_tab = str(GameMenu.SETTINGS_SECTIONS[i]["tab"])
		if not screen.encloses(card_panel.get_global_rect()):
			too_tall.append(str(GameMenu.SETTINGS_SECTIONS[i]["tab"]))
	_check(too_tall.is_empty() and worst > 0.0,
		"the tallest settings tab is %s at %.0f of %.0f" % [worst_tab, worst, screen.size.y])

	# **The structural one, and it took two attempts to find an honest form.** The checks
	# above describe a symptom and would go green again if somebody shrank a font. The
	# first attempt compared the card's height against the sections stacked minus the
	# tallest -- and failed on a correct card, because the card's fixed chrome (banner,
	# tab strip, two buttons: 241px) happened to equal the two smaller sections combined.
	# Any assertion mixing chrome with content needs to know the chrome, and this check
	# cannot.
	#
	# What it can see without knowing any of that: **a tabbed card's height follows the
	# tab shown**, and a flattened one's does not. Every page visible at once, or every
	# setting collapsed into a single page, gives the same height on every tab.
	_check(worst > slightest,
		"and the card's height follows the tab shown, so the sections are not all stacked (%.0f to %.0f)"
		% [slightest, worst])
	var empty := 0
	for page in _menu._settings_pages:
		if (page as Control).get_combined_minimum_size().y < 1.0:
			empty += 1
	_check(empty == 0 and _menu._settings_pages.size() >= 2,
		"across %d sections, none of them empty (%d empty)"
		% [_menu._settings_pages.size(), empty])

	# Every setting is on exactly one tab, counted off the table rather than off child
	# indices -- so "fix the overflow by dropping a setting" fails here.
	var declared := 0
	for section: Dictionary in GameMenu.SETTINGS_SECTIONS:
		declared += int(section["groups"])
	var built := 0
	for page in _menu._settings_pages:
		for node in _descendants(page):
			var label := node as Label
			if label and label.theme_type_variation == &"HeaderLabel":
				built += 1
	_check(built == declared,
		"every setting the table declares is on a tab (%d built, %d declared)"
		% [built, declared])

	_menu.resume()
	paused = false
	_menu._switch(kept_screen)
	await _idle(2)


## BACK goes where SETTINGS was opened from, even after switching tabs.
##
## The one bug the tab design can produce: a tab button that called `open_settings()`
## would re-record `_settings_from`, and pause -> settings -> switch tab -> back would
## land on the title screen with the district still frozen behind it.
func _test_settings_back_returns_where_it_came_from() -> void:
	if _menu == null:
		_check(false, "a menu to navigate")
		return
	_menu.open_pause()
	await _idle(2)
	_menu.open_settings()
	await _idle(2)
	_menu._tab_buttons[_menu._tab_buttons.size() - 1].pressed.emit()
	await _idle(2)
	_check(_menu.screen == GameMenu.Screen.SETTINGS,
		"switching tabs stays on the settings card (screen %d)" % _menu.screen)
	_menu.close_settings()
	await _idle(2)
	_check(_menu.screen == GameMenu.Screen.PAUSE and paused,
		"and BACK returns to the pause card it was opened from (screen %d, paused %s)"
		% [_menu.screen, paused])
	_menu.resume()
	paused = false
	await _idle(2)


## RESET CAREER asks first, and Escape says no.
##
## Deliberately never presses the confirm's own RESET: the real wipe is exercised by
## `_test_reset_career_starts_over`, which runs dead last for that reason.
func _test_reset_career_asks_first() -> void:
	if _menu == null or _station == null:
		_check(false, "a menu and a station")
		return
	var kept_funds := _station.funds
	var kept_fleet: Dictionary = _station.owned.duplicate()
	_menu.open_settings()
	await _idle(2)
	# **Pressed, not called.** The first cut called `ask_reset_career()` directly, and
	# sabotage showed that cannot fail: pointing the card's button straight at the wipe
	# left the check green, because nothing in the suite ever traversed the button's
	# connection. The whole risk here is a mis-wired button, so the button is what must be
	# pressed.
	var reset_button: Button = null
	var card := _menu.find_child("SettingsCard", true, false)
	for node in _descendants(card) if card else []:
		var button := node as Button
		if button and button.text == "RESET CAREER":
			reset_button = button
			break
	if reset_button == null:
		_check(false, "the settings card carries a RESET CAREER button")
		return
	reset_button.pressed.emit()
	await _idle(2)
	_check(_menu.screen == GameMenu.Screen.CONFIRM,
		"pressing RESET CAREER opens a confirmation (screen %d)" % _menu.screen)
	_check(_station.funds == kept_funds and _station.owned == kept_fleet,
		"and takes nothing until it is answered (£%d, %d types)"
		% [_station.funds, _station.owned.size()])
	await _press_key(KEY_ESCAPE)
	_check(_menu.screen == GameMenu.Screen.SETTINGS,
		"Escape declines it, back to settings (screen %d)" % _menu.screen)
	_check(_station.funds == kept_funds and _station.owned == kept_fleet,
		"with the career still intact")
	_menu.close_settings()
	_menu.resume()
	paused = false
	await _idle(2)


func _test_quit_to_title_stands_the_shift_down() -> void:
	await _clear_calls()
	_director.shift_length = 9999.0
	_director.first_call_delay = 999.0
	_director.begin_shift()
	_check(_director.active, "a shift is running to walk out on")
	_menu.open_pause()
	await _idle(2)
	# **`stand_down()`, not `quit_to_title()`.** Since the title became its own scene
	# the full call ends in `change_scene_to_file`, which would tear this district out
	# from under every check that follows -- it did, once, and took three unrelated
	# checks and a script error with it. This is the half that belongs to the district;
	# the half that leaves is a one-line scene change to a constant.
	_menu.stand_down()
	# The suite *is* the SceneTree, so this is its own property rather than a call.
	paused = false
	await _idle(6)
	_check(not paused, "quit-to-title leaves a district that idles on, unpaused")
	_check(not _director.active and not _mission.scoring,
		"with the shift stood down")
	# **The boot scene is the menu, and the launcher wears the game's own icon.** Both
	# live in `project.godot`, both are written by `setup_project.gd`, and both have been
	# silently wrong: the icon was the Synty vendor logo for the whole life of the
	# project, and re-running that script in August 2026 put the boot scene back to the
	# district because its constant predated the menu existing.
	_check(ProjectSettings.get_setting("application/run/main_scene", "")
			== "res://Game/MainMenu.tscn",
		"the game boots into the main menu (%s)"
		% ProjectSettings.get_setting("application/run/main_scene", "none"))
	var icon: String = ProjectSettings.get_setting("application/config/icon", "")
	_check(icon.begins_with("res://") and not icon.contains("Synty")
			and ResourceLoader.exists(icon),
		"and the launcher icon is the game's own, on disk (%s)" % icon)

	_check(GameMenu.MENU_SCENE == "res://Game/MainMenu.tscn"
			and ResourceLoader.exists(GameMenu.MENU_SCENE),
		"and a main menu on disk to go back to (%s)" % GameMenu.MENU_SCENE)
	_menu.show_title()
	await _idle(2)
	await _press_key(KEY_ENTER)
	_check(not _menu.visible, "and ENTER goes again")
	_reset_mission()



## A shift you walk out on still costs you. Until August 2026 it did not.
func _test_a_bad_shift_cannot_be_quit_away() -> void:
	await _clear_calls()
	var funds_before := _station.funds
	_station.debt = 0
	_car.repair_bill = 0

	# **The exploit, stated.** Money banks on every `earn()`; the score only banks in
	# `end_shift()`; and `repair_bill` lived on the vehicle and was never serialised. So
	# abandoning at 90% kept the takings, dropped the score, escaped the lost-casualty
	# penalty and wiped the damage. Quitting a bad shift beat finishing it.
	_director.shift_length = 9999.0
	_director.first_call_delay = 999.0
	_director.begin_shift()
	_car.repair_bill = 200
	var spot := _director._pick_pavement(true)
	if spot != Vector3.INF:
		_spawn_fire(spot, 0.5)
	await _idle(10)
	var open_before := _board.open_calls().size()
	var failed_before := _mission.calls_failed

	_director.abandon_shift()
	await _idle(8)
	_check(_station.debt >= 200 and _car.repair_bill == 0,
		"walking out sweeps the damage onto the house (£%d owed, £%d on the car)"
		% [_station.debt, _car.repair_bill])
	_check(open_before == 0 or _mission.calls_failed > failed_before,
		"and the calls you left behind are failed, not forgotten (%d from %d, %d open)"
		% [_mission.calls_failed, failed_before, open_before])
	# The debrief already reads `outstanding_repairs()`, so the house figure reaches the
	# player with no interface change at all.
	_check(_station.outstanding_repairs() >= 200,
		"the readout counts what the house is owed (£%d)"
		% _station.outstanding_repairs())

	# Debt comes off the top of earnings -- the sink the career has never had.
	_station.debt = 100
	var purse := _station.funds
	_station.earn(100)
	_check(_station.debt == 0 and _station.funds == purse,
		"earnings pay the debt down before they reach the purse (£%d debt, £%d purse)"
		% [_station.debt, _station.funds])
	_station.earn(100)
	_check(_station.funds == purse + 100,
		"and reach it once the debt is clear (£%d)" % _station.funds)

	# It survives the process, which is the whole point.
	_station.debt = 175
	_station._save_career()
	_station.debt = 0
	_station._load_career()
	_check(_station.debt == 175, "the house account survives a reload (£%d)" % _station.debt)

	_station.debt = 0
	_station.funds = funds_before
	_car.repair_bill = 0
	_station._save_career()
	_reset_mission()


## The settings card's hard reset: fleet dissolved, purse back to the starter
## budget. Destructive by design, which is why it runs dead last.
func _test_reset_career_starts_over() -> void:
	_check(_station.funds != Station.STARTING_FUNDS
			or _station.total(&"patrol") > 0,
		"there is a career to wipe")
	_menu.reset_career()
	await _idle(6)
	_check(_station.funds == Station.STARTING_FUNDS,
		"reset refills the purse to the starter budget (£%d)" % _station.funds)
	_check(_station.total(&"patrol") == 0 and _station.total(&"paramedic") == 0,
		"and takes the fleet off the books")
	var alive := 0
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.service != Unit.Service.NONE:
			alive += 1
	_check(alive == 0, "and off the map (%d left standing)" % alive)


## The shop: a storefront with the portrait and the job description, not a
## fingernail chip on the bar. Opened from the DISPATCH heading, sells through its
## BUY buttons, and swallows the keyboard while it is up.
func _test_the_shop_previews_and_sells() -> void:
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as RequisitionPanel
	if shop == null:
		_check(false, "the HUD ships a shop")
		return
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()
	_check(not shop.visible, "the shop ships closed")

	# **The corner buy button is the front door.** Clicked through the real interface
	# rather than by calling `open_shop()`, because a button wired to nothing looks
	# identical to a button wired correctly from everywhere except a click.
	# **The bar's button, not the roster's.** The roster sidebar was retired in August 2026
	# once the bottom bar carried the fleet; its REQUEST UNITS button went with it, and this
	# clicks by screen position, so a hidden panel has no rectangle to aim at.
	var door_panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	var corner_buy := door_panel.request_button() if door_panel else null
	if corner_buy == null:
		_check(false, "the bar carries a REQUEST UNITS button")
		return
	_station.funds = 10000
	_station.roster_changed.emit()
	await _click(MOUSE_BUTTON_LEFT, corner_buy.get_global_rect().get_center())
	_check(shop.visible, "clicking REQUEST UNITS opens the shop")
	# The icon is loaded behind a `ResourceLoader.exists()` guard, so a glyph that never
	# imported costs the picture and not the button -- right behaviour, and completely
	# invisible. It happened the day the cart was drawn.
	_check(corner_buy.text.contains("REQUEST"), "and it says what it does (%s)"
		% corner_buy.text)

	# Every unit in the catalogue has a card, and every card carries its rendered
	# portrait -- the preview is the point of a shop.
	var cards := shop.cards()
	var missing := 0
	for id: StringName in cards:
		var card := cards[id] as UnitCard
		if card == null or card.unit == null or card.unit.icon == null:
			missing += 1
	_check(cards.size() == Station.TYPES.size() and missing == 0,
		"every card shows the unit's rendered portrait (%d missing of %d, catalogue %d)"
		% [missing, cards.size(), Station.TYPES.size()])

	# **And every one of them is reachable.** Reported from play when the catalogue reached
	# eight and a single row ran off the side of the screen: an overflowing container clips
	# rather than wrapping, so the cards past the edge could not be clicked at all.
	#
	# **Asked of a scrolling list, which is what the requisition modal uses.** The first cut
	# of this simply demanded every card sit inside the viewport, and five of thirteen
	# failed -- correctly, because a scroller shows a window onto its content and the rest
	# is below the fold *by design*. That assertion could only ever have passed for a
	# catalogue small enough not to need scrolling, which is the very case it was written
	# to stop mattering.
	#
	# So the surviving question is the one the original bug was actually about: nothing
	# escapes **sideways**, where there is no scrollbar to rescue it, and the scroller can
	# actually reach the bottom of the grid.
	# **Measured against the panel, not against the card's own parent, and the difference
	# is the whole check.** The first cut compared each card to the `ScrollContainer`
	# holding it -- and that container has no fixed width, so it stretches to whatever the
	# cards demand. Sabotage forcing every card 900px wide blew the catalogue out to 1822px
	# inside a 1600px modal, dragging 7 of 13 cards clean off it, and this still reported
	# `0 of 13`: **the reference frame moved with the fault**, so nothing could ever escape
	# it. Vacuous, and not fixable by provoking harder -- the comparison was self-referential.
	#
	# The panel is viewport-sized and fixed, which is what the question needs. Horizontal
	# only, deliberately: below the fold is where a scrolling list is *supposed* to put
	# things, but there is no scrollbar sideways and a card off that edge is unreachable.
	var catalogue := cards[&"patrol"].get_parent().get_parent() as ScrollContainer
	var panel := shop.get_global_rect()
	var overflowing: Array[String] = []
	for id: StringName in cards:
		var card := cards[id] as Control
		if not card.visible:
			continue
		var rect := card.get_global_rect()
		if rect.position.x < panel.position.x - 1.0 or rect.end.x > panel.end.x + 1.0:
			overflowing.append(String(id))
	_check(catalogue != null and overflowing.is_empty(),
		"no card hangs off the side of the panel (%d of %d%s)"
			% [overflowing.size(), cards.size(),
				"" if overflowing.is_empty() else ": " + ", ".join(overflowing)])
	var grid := cards[&"patrol"].get_parent() as Control
	_check(catalogue != null and grid != null
			and catalogue.get_v_scroll_bar().max_value >= grid.size.y - 1.0,
		"and the list scrolls far enough to reach the last of them (%.0f of %.0fpx)"
			% [0.0 if catalogue == null else catalogue.get_v_scroll_bar().max_value,
				0.0 if grid == null else grid.size.y])

	# **Grouping is by tab now, not by shelf.** The old storefront laid the catalogue out in
	# per-service shelves and this checked each shelf's population; the requisition modal
	# filters one grid instead. Same property, asked of the new shape: there is a tab for
	# ALL and one for each service that actually has units, and picking one leaves only that
	# service's cards on screen.
	var tabs := shop.tab_buttons()
	_check(tabs.size() == ShopCatalogue.categories().size() + 1,
		"the shop offers a tab for ALL and one per service (%d)" % tabs.size())
	var fire_tab: Button = null
	for tab in tabs:
		if tab.get_meta(&"cat", &"") == &"fire":
			fire_tab = tab as Button
	if fire_tab != null:
		await _click(MOUSE_BUTTON_LEFT, fire_tab.get_global_rect().get_center())
		await _idle(2)
		var strays: Array[String] = []
		var shown := 0
		for id: StringName in cards:
			var card := cards[id] as UnitCard
			if not card.visible:
				continue
			shown += 1
			if card.unit.category != &"fire":
				strays.append(String(id))
		_check(shown > 0 and strays.is_empty(),
			"and choosing FIRE shows only fire units (%d shown, strays: %s)"
			% [shown, "none" if strays.is_empty() else ", ".join(strays)])
	# Back to ALL so the rest of this check sees the whole catalogue.
	for tab in tabs:
		if tab.get_meta(&"cat", &"") == &"all":
			await _click(MOUSE_BUTTON_LEFT, (tab as Button).get_global_rect().get_center())
	await _idle(2)

	# **Buying is a cart now**, which is the one behaviour that genuinely changed: the old
	# storefront charged on the card's BUY, this one collects an order and charges once on
	# DEPLOY. Both steps are clicked, because a deploy button that never fires looks exactly
	# like a card that never added.
	var funds_before := _station.funds
	var owned_before := _station.total(&"patrol")
	# **Driven through the card's own `pressed`, not a synthetic click, and that is a
	# weakness worth naming.** `UnitCard` does `pressed.connect(func(): add_requested.emit(
	# unit))`, so this is the path a real press takes and everything downstream of the
	# button is genuinely exercised. What it does *not* prove is that a mouse click reaches
	# the card -- pushed input lands on the tabs and the DEPLOY button, both outside the
	# scroller, and was measured not to land on a card inside it. Rather than assert a
	# weaker thing quietly, this says so: the click path into the scrolling grid is
	# unverified, and the corner button and DEPLOY below are still clicked for real.
	var patrol_card := cards[&"patrol"] as UnitCard
	patrol_card.pressed.emit()
	await _idle(2)
	var deploy := shop.deploy_button()
	_check(deploy != null and not deploy.disabled,
		"adding a unit arms the DEPLOY button")
	await _click(MOUSE_BUTTON_LEFT, deploy.get_global_rect().get_center())
	await _idle(2)
	_check(_station.funds == funds_before - _station.price(&"patrol")
			and _station.total(&"patrol") == owned_before + 1,
		"and deploying buys exactly what was in the order (£%d -> £%d, %d -> %d patrols)"
		% [funds_before, _station.funds, owned_before, _station.total(&"patrol")])
	_check(not shop.visible, "and the shop closes once the order is placed")

	# **The dialog is the same size with a full cart as with an empty one.**
	#
	# Reported from play: three units in the order and the modal had stretched to the
	# height of the screen. Two [TextureRect]s were sizing themselves to a 192x192
	# portrait -- the same `EXPAND_KEEP_SIZE` default that had already wrecked the cards --
	# so each cart row was about 192px instead of 52, and the modal sizes itself around
	# its contents.
	#
	# Measured on the panel rather than on a row, because the fault is not "rows are tall",
	# it is "the window moves when you shop". Six is past the point the reported case broke
	# at, and the order count is asserted alongside so this cannot pass by adding nothing.
	shop.open_shop()
	await _idle(4)
	var shell := (shop.get_child(0) as Control).find_child("Shell", true, false) as Control
	var empty_size := shell.size
	var wanted := 6
	var loaded := 0
	for id: StringName in cards:
		if loaded >= wanted:
			break
		(cards[id] as UnitCard).pressed.emit()
		loaded += 1
	await _idle(6)
	_check(loaded == wanted and shop.deploy_button() != null
			and not shop.deploy_button().disabled,
		"%d units go into the cart" % loaded)
	_check(shell.size.is_equal_approx(empty_size),
		"and the dialog is the same size full as empty (%s against %s)"
		% [str(shell.size), str(empty_size)])
	shop.close_shop()
	await _idle(2)

	# **An order it cannot pay for is refused at the card.** The modal is told the purse
	# when it opens, so the funds are set first and the shop reopened -- a budget set behind
	# an open modal is a stale number and would prove nothing.
	_station.funds = 10
	_station.roster_changed.emit()
	shop.open_shop()
	await _idle(2)
	_check((cards[&"patrol"] as UnitCard).disabled,
		"an unaffordable unit cannot be added to the order")

	# The keyboard has no business reaching the game underneath.
	await _press_key(KEY_F2)
	await _idle(2)
	_check(not _director.active, "F2 does not open a shift under the shop")
	await _press_key(KEY_ESCAPE)
	await _idle(2)
	_check(not shop.visible, "Esc closes it")

	# Books back to canonical -- the bought patrol never materialised on the map.
	_station.funds = kept_funds
	_station.owned = kept_owned
	_station._save_career()
	_station.roster_changed.emit()


## Buys [param count] of a type, topping the purse up first: tests that use this are
## about dispatch and driving, not affordability, which has its own checks.
## The main menu's picture is dressed at run time, and has to actually be dressed.
##
## `MenuBackdrop` turns a parked tableau into an incident: lightbars and headlights on
## the two emergency vehicles, a line of cones across the police car's nose, a crew out
## and a few onlookers. All of it is placed in code against a scene the user keeps
## editing, so every part of it can silently stop happening -- a renamed vehicle node
## and the lights go, a moved prefab and the cones go. None of that would show on a
## boot, which is clean either way.
##
## Asserted on the **result** rather than on the attempt, which is the lesson of the
## tutorial pre-warm: that one checked a request had been made, was green for weeks,
## and the work behind it failed every time.
func _test_the_menu_backdrop_is_dressed() -> void:
	var menu := (load("res://Game/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	# Deferred dressing, so it lands a frame after the scene is up.
	for i in 12:
		await physics_frame

	var backdrop := menu.get_node_or_null("Backdrop")
	var lit := 0
	for name in ["SM_Veh_Car_Police_01", "SM_Veh_Firetruck_01"]:
		var vehicle := backdrop.get_node_or_null(name) as Node3D if backdrop else null
		if vehicle == null:
			continue
		var beams := vehicle.get_node_or_null("Headlights")
		var bar := vehicle.get_node_or_null("Lightbar")
		# Exactly two each: a surviving run-time builder would double them.
		if beams and beams.get_child_count() == 2 and bar and bar.get_child_count() == 2:
			lit += 1
	_check(lit == 2,
		"both emergency vehicles have headlights and a lightbar (%d of 2)" % lit)

	# **Authored into the scene, so the editor shows them** -- which means this counts
	# lamps hung on the poles themselves rather than on a runtime circuit. It also
	# guards the other half of that move: the run-time builder was deleted when the
	# lights were authored, and had it been left in there would now be two of
	# everything, which renders as a slightly brighter scene and nothing else.
	var poles := backdrop.find_children("SM_Prop_LightPole*", "", true, false) \
		if backdrop else []
	var lamps := 0
	for pole in poles:
		for child in pole.get_children():
			if child is OmniLight3D:
				lamps += 1
	_check(poles.size() > 0 and lamps == poles.size(),
		"every light pole carries exactly one lamp (%d lamps, %d poles)"
		% [lamps, poles.size()])

	var dressing := menu.get_node_or_null("Dressing")
	var cones := 0
	var people := 0
	var animated := 0
	var floating := 0
	for child in dressing.get_children() if dressing else []:
		var here: Vector3 = (child as Node3D).global_position
		# Everything is placed on the ground plane; a cone at head height is a
		# placement bug that only a screenshot would otherwise catch.
		if absf(here.y) > 1.0:
			floating += 1
		# Told apart by what they are, not by what they are called: only the first
		# instance of a scene keeps its name and the rest come back as
		# `@MeshInstance3D@82`, which a name test reads as one cone and eleven people.
		var player := child.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player == null:
			cones += 1
			continue
		people += 1
		# **Animating, not merely present.** The first cut asked for `Idle_Loop`, which
		# the retarget renames to `Idle`, so `has_animation` said no and `_idle`
		# returned quietly -- seven people placed perfectly and every one of them stood
		# in the rig's rest pose. Counting bodies would still have passed.
		if player.current_animation != "":
			animated += 1
	# Five: two officers, two firefighters, and the member of the public one of them is
	# talking to. It was seven until three scattered bystanders were cut for reading as
	# people who had wandered into shot.
	_check(cones >= 5 and people >= 5 and floating == 0,
		"the scene is dressed: %d cones, %d people, %d off the ground"
		% [cones, people, floating])
	_check(people > 0 and animated == people,
		"and every one of them is animating rather than stood in rest pose (%d of %d)"
		% [animated, people])
	menu.free()


## Every character wears the same 43 clips, and must do it by reference.
##
## This is a performance fact with a correctness-shaped guard. `build_character`
## saves the animation library to disk and hands the same in-memory object to all
## eleven scenes -- but `ResourceSaver.save` leaves that object pathless, and
## `PackedScene.pack()` inlines any resource it cannot point at. For months the
## library sat on disk referenced by nothing while every character embedded its own
## 3MB copy: 315ms to parse, eleven times over, which is what made the tutorial take
## five seconds to open and every casualty spawn cost two thirds of a second. The
## fix is one `take_over_path` call, and nothing about the game looks any different
## when it is missing -- it just gets slow again, quietly, on the next rebuild.
## So: the sharing itself is the assertion.
func _test_the_characters_share_one_animation_library() -> void:
	var libraries := {}
	var paths := {}
	var counted := 0
	var directory := DirAccess.open("res://Game/Characters")
	for file in directory.get_files() if directory else PackedStringArray():
		var name := str(file).trim_suffix(".remap")
		if not name.ends_with(".tscn"):
			continue
		var character := (load("res://Game/Characters/" + name)
			as PackedScene).instantiate()
		var player := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player:
			var library := player.get_animation_library("")
			libraries[library.get_instance_id()] = true
			paths[library.resource_path] = true
			counted += 1
		character.free()

	_check(counted >= 11 and libraries.size() == 1,
		"all %d character scenes share one animation library instance (%d distinct)"
		% [counted, libraries.size()])
	# An embedded copy has no path of its own, so this catches the same regression
	# from the other side -- and pins the binary file, which loads in 7ms where the
	# text one took 313ms.
	_check(paths.has("res://Game/Rigs/ual_standard.res"),
		"and it is the one on disk (%s)" % ", ".join(PackedStringArray(paths.keys())))


## The tutorial town, structurally. Runs before the district loads (see _run) and
## frees everything it touched. Headless cannot judge how the town looks -- that is
## the windowed pass -- but it can pin every wiring fact the migration relies on.
func _test_the_tutorial_town_boots() -> void:
	var town := (load("res://Game/Tutorial.tscn") as PackedScene).instantiate()
	# **Before `add_child`, because the town starts running the moment it is in the tree.**
	# The district's recorder is repointed in `_run` before a single check goes off, and
	# the comment there explains why; this is the *second* scene the suite builds and it
	# carries its own [StuckLog], which kept the default. So every suite run that got this
	# far filed the fixture's driving into `user://stuck-log.txt` under the name
	# "Ambulance 2" -- indistinguishable from play, and duly read back as a live defect in
	# the tutorial. Twice.
	#
	# The line twenty below pins this town's `career_path` for exactly the same reason. The
	# career trap was remembered here and the black-box one was not, which is the argument
	# for the check underneath rather than for being more careful.
	var town_log := town.get_node_or_null("StuckLog") as StuckLog
	if town_log:
		town_log.log_path = "user://smoke-tutorial-stuck.txt"
	root.add_child(town)
	_check(town_log != null and town_log.log_path != "user://stuck-log.txt",
		"the tutorial fixture is not writing into the player's own black box (%s)"
		% ("absent" if town_log == null else town_log.log_path))
	# The navigation map ingests its regions asynchronously -- measured at ~30
	# frames; queries against a half-synced map answer confidently and wrongly.
	for i in 45:
		await physics_frame

	_check(CityGrid.lattice_fits == false,
		"the town switches the lattice machinery off while it is loaded")

	var station := town.get_node_or_null("Station") as Station
	var spawn := Vector3(-47.5, 0.45, 10.0)
	_check(station != null and station.global_position.is_equal_approx(spawn),
		"the station stands on the parking quarter")
	var faced := Basis(Vector3.UP, deg_to_rad(0.0)).z
	_check(station != null and station.global_basis.z.dot(faced) > 0.99,
		"facing out of the quarter toward the street")
	_check(station != null and station.slot_count == 1,
		"with a single dispatch slot on the spot")
	_check(station != null and station.career_path == "user://tutorial-career.cfg",
		"and its own career book -- practice never touches the district's")

	var hospital := town.get_node_or_null("Hospital") as Area3D
	_check(hospital != null and hospital.global_position.is_equal_approx(spawn),
		"the drop-off shares the spawn point, as designed")
	var pad := town.get_node_or_null("Hospital/Pad") as Node3D
	_check(pad != null and not pad.visible,
		"and wears no red pad -- the overlap needs no advertisement")

	for absent in ["Traffic", "Director", "CallSpawner"]:
		_check(town.get_node_or_null(absent) == null,
			"the town ships no %s -- lattice natives stay in the district" % absent)

	# The crowd is not shipped in the scene either -- it is put down at load from
	# the person mesh's own vertices, so nobody ever stands somewhere this town
	# cannot be stood on.
	var crowd := town.get_node_or_null("Crowd")
	var walkers := crowd.get_child_count() if crowd else 0
	_check(walkers >= TutorialMap.CROWD_SIZE,
		"the streets are populated (%d walking)" % walkers)
	var on_mesh := 0
	var off_forecourt := 0
	if crowd:
		for node in crowd.get_children():
			var walker := node as Civilian
			if walker == null:
				continue
			if Unit.can_reach(walker, walker.global_position, 1.5):
				on_mesh += 1
			if _flat_distance(walker.global_position, spawn) \
					>= TutorialMap.CROWD_CLEAR_OF_STATION - 1.0:
				off_forecourt += 1
	_check(walkers > 0 and on_mesh == walkers,
		"every one of them stands where the mesh allows (%d of %d)"
		% [on_mesh, walkers])
	_check(walkers > 0 and off_forecourt == walkers,
		"and clear of the forecourt the vehicles land on (%d of %d)"
		% [off_forecourt, walkers])

	var roads := town.get_node_or_null("VehicleNavigation") as NavigationRegion3D
	var paths := town.get_node_or_null("PersonNavigation") as NavigationRegion3D
	# Bounded on BOTH sides, and the upper bound is the one with a story. The kerbs
	# carving this mesh is half the driving fix, and with that pass off the bake still
	# produced 452 polygons -- a wrong mesh merged over the pavements, not a small one,
	# which a bare `> 100` slept through. But the carve alone then bakes the lifted
	# pavement tops as a second sheet, and *that* read as 695: a bigger number for a
	# worse mesh. The carriageway alone is 117. A count that can only grow is not a
	# measure of a road network.
	var road_polygons := roads.navigation_mesh.get_polygon_count() if roads else 0
	_check(roads != null and road_polygons > 80 and road_polygons < 200,
		"the carriageway mesh is the streets, not the pavements too (%d polygons)"
		% road_polygons)
	# **The property the polygon count cannot see.** Six black-box records of an
	# ambulance shuffling away from a shout were one fault: the lifted pavements baked
	# as their own sheet, a car beside a kerbside casualty snapped onto it, and its way
	# home was on the other one -- `reachable: false`, on a road collider, with nothing
	# in its way. Measured then: four components, two map-spanning and interleaved.
	# So this asks the question the fault asked. Every point a car can actually stand
	# on has to be able to reach the station, or the mesh has somewhere to strand.
	var station_spot := Vector3(-47.5, 0.45, 10.0)
	var road_map := roads.get_navigation_map() if roads else RID()
	var standing := 0
	var stranded := 0
	for x in range(-60, 60, 4):
		for z in range(-60, 40, 4):
			var here := Vector3(float(x), 0.45, float(z))
			var route := NavigationServer3D.map_get_path(road_map, here, station_spot,
				true, 1)
			if route.size() <= 1:
				continue
			# Points out in the gardens snap to the nearest road and would otherwise
			# flatter the count; only samples that really sit on the mesh are asked.
			if Vector2(route[0].x - here.x, route[0].z - here.z).length() > 2.0:
				continue
			standing += 1
			var arrival := route[route.size() - 1]
			if Vector2(arrival.x - station_spot.x,
					arrival.z - station_spot.z).length() > 2.0:
				stranded += 1
	_check(standing > 100 and stranded == 0,
		"and every drivable point on it can reach the station (%d of %d stranded)"
		% [stranded, standing])
	# Flat road furniture must not be solid: a manhole's mesh collider sat exactly
	# where the tutorial's casualty lay and an ambulance ground against it for the
	# whole forty seconds a probe would give it.
	# **Subjects named literally, not read from the constant under test.** Drawing
	# them from TutorialMap.FLAT_FURNITURE made the check self-referential: empty
	# that array and the check reddens on an empty subject list rather than on
	# solid manholes -- a red for the wrong reason, which is worse than a green.
	var flat := 0
	var solid_flat := 0
	for node in _descendants(town.get_node("Map")):
		var furniture := node as StaticBody3D
		if furniture == null:
			continue
		if not str(furniture.get_parent().name).begins_with("SM_Prop_Manhole"):
			continue
		flat += 1
		if furniture.collision_layer != 0:
			solid_flat += 1
	_check(flat > 0 and solid_flat == 0,
		"and the manholes are flat, not walls (%d solid of %d)" % [solid_flat, flat])
	# Tight, not merely non-zero: the walkable ground is pavements *and* gardens
	# and measures 386 polygons. A loose `> 100` bound slept through a rebuild that
	# halved it to 198 by dropping every buried-lawn rule -- measured, in sabotage.
	_check(paths != null and paths.navigation_mesh.get_polygon_count() > 300,
		"and the pavement mesh baked (%d polygons)"
		% (paths.navigation_mesh.get_polygon_count() if paths else 0))
	_check(get_nodes_in_group("road_surface").size() > 200,
		"the runtime stamper marked the road slabs (%d)"
		% get_nodes_in_group("road_surface").size())

	# The proving shout's geography: drivable to within a kerb's width, walkable to
	# the centimetre. This is the check that catches a re-authored town whose roads
	# no longer reach the shout -- and the driveway-islet trap, where the network
	# looked baked but the station's clamp sat on a two-polygon stub of drive.
	var tutor := town.get_node_or_null("TutorialDirector") as TutorialDirector
	_check(tutor != null, "the town carries its scripted director")
	if tutor and station:
		var map: RID = station.get_world_3d().navigation_map
		for spot: Vector3 in [tutor.casualty_spot, tutor.fire_spot]:
			var drive := NavigationServer3D.map_get_path(
				map, station.global_position, spot, true, 1)
			var drive_end := drive[drive.size() - 1] if not drive.is_empty() \
				else Vector3.INF
			_check(not drive.is_empty() and Vector2(drive_end.x - spot.x,
					drive_end.z - spot.z).length() < 8.0,
				"the road network reaches the shout at %s" % spot)
			var walk := NavigationServer3D.map_get_path(
				map, station.global_position, spot, true, 2)
			var walk_end := walk[walk.size() - 1] if not walk.is_empty() \
				else Vector3.INF
			_check(not walk.is_empty() and Vector2(walk_end.x - spot.x,
					walk_end.z - spot.z).length() < 0.5,
				"and the pavements deliver a walker onto it")

	# **The gardens walk.** The town lays grass under everything, so the first two
	# cuts of this mesh either stacked two walkable surfaces (and the navigation map
	# answered nothing at all) or dropped the lawns outright and left a walker
	# confined to the pavements. Measured across a 5m sweep of the whole town: a
	# walker should reach the great majority of it, including the gaps between
	# houses -- and still not the inside of a house.
	if station:
		var map: RID = station.get_world_3d().navigation_map
		var here := station.global_position
		var open := 0
		var sampled := 0
		for x in range(-60, 91, 10):
			for z in range(-95, 56, 10):
				var spot := Vector3(x, 0.45, z)
				sampled += 1
				var walk := NavigationServer3D.map_get_path(map, here, spot, true, 2)
				if walk.is_empty():
					continue
				var end := walk[walk.size() - 1]
				if Vector2(end.x - spot.x, end.z - spot.z).length() < 0.6:
					open += 1
		_check(sampled > 0 and float(open) / float(sampled) > 0.8,
			"a walker reaches the gardens and the gaps between houses (%d of %d)"
			% [open, sampled])
		# The other half of the same rule: grass under a house is not a floor.
		# **The point matters.** The first one chosen sat over a driveway, which is
		# excluded ground for its own reasons -- so it read as blocked whatever the
		# burial rule did, and a sabotage that skipped burial entirely left it
		# green. This one has a house collider and a grass tile overhead and
		# nothing else: measured 5.25m short healthy, 0.00m with burial skipped.
		var indoors := Vector3(-35.0, 0.45, -45.0)
		var into := NavigationServer3D.map_get_path(map, here, indoors, true, 2)
		var stopped := INF
		if not into.is_empty():
			var end := into[into.size() - 1]
			stopped = Vector2(end.x - indoors.x, end.z - indoors.z).length()
		_check(stopped > 2.0,
			"but not through the living rooms (stopped %.1fm short)" % stopped)

	var menu := town.get_node_or_null("HUD/Root/Menu") as GameMenu
	_check(menu != null and menu.in_tutorial,
		"the menu knows it is the tutorial's")

	# The shout comes a job at a time, and the mission is told so -- the scripted
	# win rule reads a clear map as a job done, and a staged shout is clear between
	# its stages.
	var tutor_stage := town.get_node_or_null("TutorialDirector") as TutorialDirector
	var mission := town.get_node_or_null("Mission") as Mission
	_check(tutor_stage != null and tutor_stage._stages().size() == 2,
		"the tutorial opens in two stages")
	_check(mission != null and not mission.more_to_come,
		"and holds nothing back before the player has started")
	if tutor_stage and mission:
		# Shortened before the first stage opens: the breather is set when a stage
		# opens, so lowering it afterwards leaves the old one already counting.
		tutor_stage.between_calls = 0.2
		tutor_stage._open_stage(0)
		await _idle(4)
		var first := get_nodes_in_group(Incident.GROUP).size()
		_check(first == 1, "the first stage opens one job, not two (%d)" % first)
		_check(mission.more_to_come,
			"with the mission told there is more coming")
		# Clear it, and the win must NOT be declared -- this is the trap the flag
		# exists for. The next stage arrives on its own after the breather.
		for node in get_nodes_in_group(Incident.GROUP):
			(node as Incident)._finish(true)
		await _idle(6)
		_check(mission.state == Mission.State.RUNNING,
			"clearing it does not end the tutorial (%d)" % mission.state)
		var second := 0
		for i in 120:
			await physics_frame
			second = get_nodes_in_group(Incident.GROUP).size()
			if second > 0:
				break
		_check(second == 1, "the second stage follows on its own (%d)" % second)
		_check(not mission.more_to_come,
			"and the mission is told it is the last")
		for node in get_nodes_in_group(Incident.GROUP):
			(node as Incident)._finish(true)
		await _idle(6)
		_check(mission.state == Mission.State.WON,
			"clearing the last one wins the shout (%d)" % mission.state)

		# What the player is left looking at. A banner could only say the job was
		# done; the card says what it came to, and takes the mouse until it is
		# dismissed so the district underneath cannot be ordered around behind it.
		var banner := town.get_node_or_null("HUD/Root/World/Banner") as Label
		var card := town.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
		_check(card != null and card.visible and banner != null and not banner.visible,
			"and the modal is what says so, not the banner")
		_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_STOP,
			"it holds the mouse while it is up (filter %d)"
			% (card.mouse_filter if card else -1))
		# The figures reached it -- and are the shout's own, which is the part that
		# `scoring` being off would otherwise have made zero.
		#
		# Redrawn first, deliberately. The automatic card is a snapshot taken the
		# instant the shout was won, and a call's response bonus lands a beat later
		# when the board closes it -- so the number on screen is a moment older than
		# the mission's own. That is right for the player and useless to compare
		# against, and it failed here as 250 against 350 before this line existed.
		# The redraw runs the same show_shout -> shout_rows -> shout_score path.
		card.show_shout(mission)
		var shown := PackedStringArray()
		if card:
			for line in card.get_child(0).get_child(0).get_child(0).get_children():
				for cell in line.get_children():
					var text := cell as Label
					if text:
						shown.append(text.text)
		var joined := " ".join(shown)
		_check("Score" in joined and str(mission.shout_score()) in joined
				and mission.shout_score() > 0,
			"carrying a score the shout actually earned (%d in '%s')"
			% [mission.shout_score(), joined])
		# Dismissing it gives the district back. Pressed rather than hidden directly:
		# the button is the only way a player has, so it is the thing worth testing.
		var dismiss: Button = null
		if card:
			for node in card.get_child(0).get_child(0).get_child(0).get_children():
				if node is Button:
					dismiss = node as Button
		_check(dismiss != null, "the modal offers a way out of itself")
		if dismiss:
			dismiss.pressed.emit()
		await _idle(2)
		_check(card != null and not card.visible
				and card.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"and CONTINUE puts it away and hands the mouse back")

	# **The drive the black box caught**, run for real. Coming home from the shout,
	# an ambulance used to jam against a sidewalk corner whose kerb face stood
	# inside the drivable mesh: full throttle, zero speed, fifteen metres short,
	# escaping and re-approaching for ever. Measured before the fix: never arrived,
	# twelve escapes, 27% of frames going nowhere. After: 12s, no escapes.
	#
	# Driven rather than inspected because the fix is a *bake*, and the geometry
	# checks above cannot tell a right mesh from a wrong one of similar size --
	# proven, by a sabotage that broke the bake and reddened nothing.
	if station:
		var kept_fleet: Dictionary = station.owned.duplicate()
		station.funds = 99999
		station.purchase(&"ambulance")
		var runner := station.dispatch(&"ambulance") as Vehicle
		if runner == null:
			_check(false, "an ambulance to drive home")
		else:
			# Started where an ambulance actually parks: the drivable point nearest
			# the shout, asked of the mesh rather than guessed. Started *on* the
			# pavement instead, the agent reports its path finished before a wheel
			# turns -- the trap written up in Vehicle._drive -- and the order
			# completes on the spot, which reads as a 50m failure that is really a
			# broken fixture.
			var to_shout := NavigationServer3D.map_get_path(
				station.get_world_3d().navigation_map, station.global_position,
				tutor_stage.casualty_spot if tutor_stage else spawn, true, 1)
			var kerb := to_shout[to_shout.size() - 1] if not to_shout.is_empty() \
				else spawn
			runner.global_position = Vector3(kerb.x, 0.45, kerb.z)
			runner.velocity = Vector3.ZERO
			runner.look_at(runner.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
			await _idle(8)
			runner.issue(MoveOrder.new(station.global_position))
			# **Pre-roll before watching.** A freshly dispatched agent has no path
			# on its first frame and reports itself finished, which Vehicle reads as
			# an arrival -- so a watch that starts immediately sees the order end on
			# the spot, 54m from home, and calls the game broken. Measured, from the
			# diagnostic that caught it.
			await _wait(25)
			var short := INF
			for i in 1500:
				await physics_frame
				short = _flat_distance(runner.global_position,
					station.global_position)
				if short < 4.0:
					break
				if not runner.is_navigating() and i > 60:
					break
			_check(short < 4.0,
				"an ambulance drives home from the shout without jamming (%.1fm)"
				% short)
			runner.free()

		# **And from where the player actually leaves it**, which is a different
		# question and the one that was failing. The check above teleports the
		# ambulance onto the drivable point nearest the shout, zeroes its velocity and
		# faces it down +Z -- an ideal start that passed throughout the months the black
		# box was filing records about this drive. Started at a position taken from those
		# records, it drove to within 15m of the station and then oscillated: forward to
		# the same sidewalk corner, dead stop, reverse 7.5m, forward again, for as long
		# as anyone watched. Nothing in front of it and the mesh saying the ground was
		# fine; `climb_escapes` was simply unreachable, because an escape moves the car
		# and movement used to forgive the escape tally.
		station.purchase(&"ambulance")
		var wedged := station.dispatch(&"ambulance") as Vehicle
		if wedged == null:
			_check(false, "a second ambulance for the awkward start")
		else:
			wedged.global_position = Vector3(-21.0, 0.6, -33.0)
			wedged.velocity = Vector3.ZERO
			wedged.rotation = Vector3.ZERO
			await _idle(30)
			wedged.issue(MoveOrder.new(station.global_position))
			await _wait(25)
			var awkward := INF
			for i in 2400:
				await physics_frame
				awkward = _flat_distance(wedged.global_position,
					station.global_position)
				if awkward < 5.0:
					break
			_check(awkward < 5.0,
				"and from the awkward parking the black box recorded (%.1fm)"
				% awkward)
			wedged.free()
		station.owned = kept_fleet
		await _idle(2)

	# The teaching line: a reading of the world, not a script of it. Each prompt is
	# asserted from the state that should produce it, in the order the job happens.
	if tutor_stage and mission and station:
		mission.state = Mission.State.RUNNING
		for node in get_nodes_in_group(Incident.GROUP):
			node.free()
		tutor_stage._opened = false
		await _idle(2)
		_check(tutor_stage._lesson() == "",
			"the tutorial says nothing before the player has started")

		tutor_stage._opened = true
		var lesson := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
			.instantiate() as Casualty
		town.get_node("Incidents").add_child(lesson)
		lesson.global_position = tutor_stage.casualty_spot
		var kept_owned: Dictionary = station.owned.duplicate()
		station.owned = {}
		await _idle(4)
		_check(tutor_stage._lesson().contains("CART"),
			"an empty roster is sent to the shop ('%s')" % tutor_stage._lesson())

		# **The words and the glow are one reading.** A prompt naming a unit is thin help
		# when the storefront holds eight cards, so the tutorial also points at the control
		# it is talking about -- and the failure worth catching is not "nothing glows" but
		# "the wrong thing glows", which is why this asserts *which* control it is.
		var spotlight := town.get_node_or_null("HUD/Spotlight") as Spotlight
		var tutor_bar := town.get_node_or_null(
			"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
		var cart: Control = tutor_bar.request_button() if tutor_bar else null
		# **Long enough for a teaching tick.** The prompt -- and with it the spotlight --
		# is re-read four times a second, so the four frames that suffice for a direct
		# `_lesson()` call are a sixteenth of what the glow needs.
		await _idle(20)
		_check(spotlight != null and spotlight._targets.size() == 1
				and spotlight._targets[0] == cart,
			"and the cart button is the thing lit up (%d lit)"
			% (spotlight._targets.size() if spotlight else -1))

		# **And it is pointing at something the player can actually see.** This leg was
		# missing, and its absence cost the whole cue: when both doors moved to the bottom
		# bar, `RosterBlock` was left in the scene `visible = false` rather than deleted,
		# so the tutorial's old lookups went on succeeding, returned real controls, and the
		# spotlight pulsed them where nobody could see them. Identity was asserted;
		# visibility never was; the check stayed green through a tutorial that had stopped
		# pointing at anything. No error, no missing node, no failing check.
		var unseen := PackedStringArray()
		for lit: Control in (spotlight._targets if spotlight else [] as Array[Control]):
			if not lit.is_visible_in_tree():
				unseen.append(lit.name)
		_check(unseen.is_empty(),
			"and every lit control is on screen (%s)"
			% ("clear" if unseen.is_empty() else ", ".join(unseen)))

		# Open the storefront and the target moves from the door to the two cards named.
		var tutor_shop := town.get_node_or_null("HUD/Root/Shop") as RequisitionPanel
		if tutor_shop:
			tutor_shop.open_shop()
			await _idle(20)
			var lit: Array[StringName] = []
			for id: StringName in [&"ambulance", &"paramedic", &"engine",
					&"firefighter", &"patrol", &"officer"]:
				if spotlight and spotlight._targets.has(tutor_shop.card_button(id)):
					lit.append(id)
			_check(lit.size() == 2 and lit.has(&"ambulance") and lit.has(&"paramedic"),
				"with the shop open it lights the two cards the prompt named (%s)"
				% str(lit))
			tutor_shop.close_shop()
			await _idle(3)

		station.funds = 99999
		station.purchase(&"ambulance")
		station.purchase(&"paramedic")
		_check(tutor_stage._lesson().contains("Send them out"),
			"units on the books but not on the map are sent out ('%s')"
			% tutor_stage._lesson())

		# Bought but parked: the glow follows the words onto the bar's standby card.
		var med_tab: Button = tutor_bar.filter_tabs().get(&"medical") if tutor_bar else null
		if med_tab:
			med_tab.pressed.emit()
		await _idle(20)
		var chip := tutor_bar.standby_card(&"ambulance") if tutor_bar else null
		_check(chip != null and spotlight != null and spotlight._targets.has(chip),
			"and once bought, the standby card on the bar is what is lit")

		# **When the card is on a tab the player is not looking at, the tab is lit.** The
		# strip shows one service at a time, which is new since this lesson was written:
		# a player told to send the ambulance while POL is up is looking at a strip with no
		# ambulance in it, and a cue that pointed at the card alone would point at nothing.
		var pol_tab: Button = tutor_bar.filter_tabs().get(&"police") if tutor_bar else null
		if pol_tab and tutor_bar:
			pol_tab.pressed.emit()
			await _idle(20)
			_check(spotlight != null
					and spotlight._targets.has(tutor_bar.tab_for(&"ambulance")),
				"and when its card is on another tab, the tab is lit instead")
			if med_tab:
				med_tab.pressed.emit()
				await _idle(20)

		var bus := station.dispatch(&"ambulance") as Vehicle
		var medic := station.dispatch(&"paramedic") as Person
		await _idle(4)
		_check(tutor_stage._lesson().contains("treat"),
			"a crew on the map is told to treat ('%s')" % tutor_stage._lesson())

		lesson.treat(1.0)
		_check(tutor_stage._lesson().contains("carry"),
			"a stable casualty is told to be carried ('%s')" % tutor_stage._lesson())
		lesson.take_by_stretcher()
		_check(tutor_stage._lesson().contains("Wheel"),
			"and one on the stretcher, wheeled ('%s')" % tutor_stage._lesson())
		if bus:
			lesson.load_into(bus)
			_check(tutor_stage._lesson().contains("station"),
				"aboard, the lesson is the drive home ('%s')" % tutor_stage._lesson())

		# The fire half, from the same reading.
		lesson.free()
		var blaze := (load("res://Game/Incidents/Fire.tscn") as PackedScene) \
			.instantiate() as Fire
		town.get_node("Incidents").add_child(blaze)
		blaze.global_position = tutor_stage.fire_spot
		await _idle(4)
		_check(tutor_stage._lesson().contains("Fire Engine"),
			"a fire with no engine on the books is sent to the shop ('%s')"
			% tutor_stage._lesson())

		mission.state = Mission.State.WON
		_check(tutor_stage._lesson() == "",
			"and it falls silent once the shout is complete")
		station.owned = kept_owned
		if bus:
			bus.free()
		if medic:
			medic.free()
	# The card must survive the minimap's own _ready, which loads the DISTRICT's
	# photograph: a first-frame call was silently overwritten by it, and the player
	# navigated the tutorial by a picture of the wrong town. Now the town has its
	# own baked photograph, the assertion is that THAT one is up, framed on the
	# town's centre rather than the district's origin.
	var minimap := town.get_node_or_null("HUD/Root/World/MinimapCard/Minimap")
	var shown := ""
	if minimap and minimap._base != null:
		shown = str(minimap._base.resource_path)
	_check(shown.ends_with("TutorialMinimapBase.png")
			and minimap.world_centre.is_equal_approx(TutorialMap.MINIMAP_CENTRE)
			and is_equal_approx(minimap.world_extent, TutorialMap.MINIMAP_EXTENT),
		"the minimap shows this town's own photograph, framed on it ('%s')" % shown)

	town.free()
	await process_frame
	_check(CityGrid.lattice_fits == true,
		"and leaving the town hands the district its lattice back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		"user://tutorial-career.cfg"))
