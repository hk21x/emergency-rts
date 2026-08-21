extends "res://Game/Tests/LightbarAndDoors.gd"

## Incidents -- 15 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## An idle unit standing near something it can deal with gets on with it.
##
## Three things have to be true at once, and the third is what makes it safe: the right
## unit engages, the wrong one does not, and **an order the player gave is never
## countermanded** by a unit noticing something on the way past.
func _test_idle_units_get_on_with_it() -> void:
	await _clear_incidents()
	_stand_to()

	# A firefighter put down beside a fire starts fighting it, unasked.
	var spot := CityGrid.junction(Vector2i(2, 2)) + Vector3(0.0, 0.0, 12.0)
	# **A hose fire**, so the capability gate is real: an officer carries an extinguisher
	# and can fight a bin perfectly well, which is why the first version of this check
	# passed while the officer was busily extinguishing.
	var fire := _spawn_fire(spot, 0.6)
	fire.needs_hose = true
	# Dispatched rather than borrowed: the fixtures carry no firefighter, and the other
	# checks that need one buy their own the same way.
	_station.purchase(&"firefighter")
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to try it with")
		return
	crew.clear_orders()
	await _place_unit(crew, spot + Vector3(6.0, 0.0, 0.0))
	await _wait(90)
	_check(crew.has_orders(), "a firefighter beside a fire starts on it unasked")
	if crew.has_orders():
		_check(crew.current_order() is ExtinguishOrder,
			"and it is work rather than a walk (%s)" % crew.current_order().describe())

	# An officer beside the same fire does not: the capability gate is hard, and standing
	# next to something does not grant an ability the unit has not got.
	_officer.clear_orders()
	await _place_unit(_officer, spot + Vector3(-6.0, 0.0, 0.0))
	await _wait(90)
	# Asked by type, not by the label: `describe()` reads "Extinguishing <flavour>", so a
	# comparison against "Extinguish" is never equal and the check could not fail.
	var wrong: Order = _officer.current_order()
	_check(not (wrong is ExtinguishOrder),
		"an officer beside a hose fire does not fight it (%s)"
		% ["idle" if wrong == null else wrong.describe()])

	# And a unit already under orders is left alone, whatever it walks past.
	# **Standing right next to it**, or the guard is never asked: parked thirty metres off
	# the fire is out of range and the unit would have kept its order regardless, which is
	# a check that cannot fail.
	crew.clear_orders()
	await _place_unit(crew, spot + Vector3(5.0, 0.0, 0.0))
	var away := spot + Vector3(60.0, 0.0, 0.0)
	crew.issue(MoveOrder.new(away))
	await _wait(60)
	var kept: Order = crew.current_order()
	_check(kept != null and kept.describe() == "Move",
		"a unit under orders is not diverted by what it passes (%s)"
		% ["idle" if kept == null else kept.describe()])

	crew.clear_orders()
	crew.queue_free()
	_officer.clear_orders()
	await _clear_incidents()
	await _idle(6)


func _test_fire_grows_and_spreads() -> void:
	await _clear_incidents()
	# **Genuinely unattended.** Idle units now start work on an incident they are standing
	# near, so "nobody is fighting it" has to be arranged rather than assumed — this fire
	# was being put out by a passing officer and the check read it as one that would not
	# grow.
	_stand_down()
	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.3)
	var before := fire.intensity
	await _wait(120)
	_check(fire.intensity > before + 0.05,
		"an unattended fire grew (%.2f -> %.2f)" % [before, fire.intensity])

	# Established, and impatient, so the test does not sit through the real interval.
	fire.intensity = 0.9
	fire.spread_interval = 1.0
	var count_before: int = get_nodes_in_group(&"fires").size()
	await _wait(90)
	var count_after: int = get_nodes_in_group(&"fires").size()
	_check(count_after > count_before,
		"an established fire spread (%d -> %d fires)" % [count_before, count_after])
	await _clear_incidents()

	_stand_to()


func _test_fire_resolves_to_extinguish() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.5)
	var ability := _officer.resolve(_target_for(fire))
	_check(ability != null and ability.id() == &"extinguish",
		"right-clicking a fire resolves to Extinguish (got '%s')"
		% ("none" if ability == null else ability.id()))

	# People before property: with a unit that can do both, a casualty outranks a fire.
	# Nobody has both any more -- gating is hard -- so this asks the ladder directly
	# rather than through a unit, which is where the ordering actually lives.
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 12.0))
	var treat := TreatAbility.new()
	var extinguish := ExtinguishAbility.new()
	_check(treat.score(_paramedic, _target_for(casualty))
			> extinguish.score(_officer, _target_for(fire)),
		"Treat still outranks Extinguish (%d vs %d)" % [
			treat.score(_paramedic, _target_for(casualty)),
			extinguish.score(_officer, _target_for(fire))])

	var medical := _paramedic.resolve(_target_for(casualty))
	_check(medical != null and medical.id() == &"treat",
		"a casualty resolves to Treat for a paramedic (got '%s')"
		% ("none" if medical == null else medical.id()))
	await _clear_incidents()


## A fire never spreads somewhere a crew cannot reach.
##
## The spread angle does not care what it lands on, and a fire against a block's frontage
## spreading five metres inward lands **inside the building** — unreachable, undousable,
## and burning until the call fails. Reported from play.
## Nothing opens inside a property.
##
## Reported from play as casualties inside buildings. The rescue set piece placed its two
## casualties at **fixed offsets** from the fire, which is pavement on a frontage facing
## one way and the inside of the building on a frontage facing the other.
func _test_no_call_opens_inside_a_property() -> void:
	await _clear_incidents()
	await _clear_calls()
	# The grid's own answer first, since everything else leans on it.
	var indoors := CityGrid.block_centre(2, 2)
	var tile := CityGrid.tile_at(indoors)
	_check(not CityGrid.standable(tile.x, tile.y),
		"the middle of a block is nowhere to stand (%.1f, %.1f)" % [indoors.x, indoors.z])
	var lawn := CityGrid.block_centre(CityGrid.PARKS[1].x, CityGrid.PARKS[1].y)
	var lawn_tile := CityGrid.tile_at(lawn)
	_check(CityGrid.standable(lawn_tile.x, lawn_tile.y),
		"a park's lawn is somewhere to stand")

	# Then the director, over enough draws that a fixed offset would show up.
	var placed := 0
	var inside := 0
	for run in 12:
		_director._spawn_rescue()
		_director._spawn_building_fire()
		_director._spawn_medical()
		await _idle(2)
		for group in [Fire.FIRE_GROUP, Casualty.CASUALTY_GROUP]:
			for node in get_nodes_in_group(group):
				var thing := node as Node3D
				if thing == null:
					continue
				placed += 1
				if _inside_a_building(thing.global_position):
					inside += 1
		await _clear_incidents()
	_check(placed > 20, "the director placed plenty to judge (%d)" % placed)
	_check(inside == 0, "and none of it inside a property (%d of %d)" % [inside, placed])
	await _clear_incidents()
	await _clear_calls()


## Return takes a loaded unit to its drop-off rather than home.
func _test_return_delivers_before_going_home() -> void:
	await _clear_incidents()
	var hospital := get_first_node_in_group(Hospital.GROUP) as Node3D
	if hospital == null:
		_check(false, "the map carries a hospital")
		return

	await _place_unit(_ambulance, CityGrid.junction(Vector2i(2, 2)))
	var ability: Ability = null
	for candidate in _ambulance.abilities():
		if candidate.id() == &"return":
			ability = candidate
	if ability == null:
		_check(false, "the ambulance offers Return")
		return

	# Empty, it goes home.
	_ambulance.casualties.clear()
	_ambulance.clear_orders()
	ability.execute(_ambulance)
	await _idle(4)
	var home := _ambulance.current_order()
	_check(home != null and home.describe() != "Move",
		"an empty unit is sent home (%s)" % ["none" if home == null else home.describe()])

	# Carrying somebody, it goes to the hospital instead.
	var casualty := _spawn_casualty(_ambulance.global_position + Vector3(2.0, 0.0, 0.0))
	_ambulance.casualties.append(casualty)
	_ambulance.clear_orders()
	ability.execute(_ambulance)
	await _idle(4)
	var order := _ambulance.current_order()
	_check(order != null, "a loaded one is sent somewhere")
	if order:
		_check(_flat_distance(order.destination(), hospital.global_position) < 2.0,
			"and that somewhere is the hospital (%.1fm off)"
			% _flat_distance(order.destination(), hospital.global_position))
	_ambulance.casualties.clear()
	_ambulance.clear_orders()
	# Off the crossroads before leaving: the next check but one parks the patrol car on
	# this exact junction and clicks it, and two vehicles on one spot means the ray picks
	# whichever it reaches first.
	await _place_unit(_ambulance, CityGrid.junction(Vector2i(1, 1)))
	await _clear_incidents()
	await _idle(4)


func _test_fire_spreads_only_where_a_crew_can_reach() -> void:
	await _clear_incidents()
	# Hard against a frontage, so most of the circle around it is building.
	var block := CityGrid.block_centre(2, 2)
	# **Hard against the wall**, at the inner edge of the ring rather than its centre: from
	# the middle of the pavement tile most of the spread circle still lands on pavement or
	# road, and the check passed with reachability deleted.
	var frontage := block + Vector3(0.0, 0.0, CityGrid.block_span_z(2) * CityGrid.TILE
		* 0.5 - CityGrid.TILE)
	var fire := _spawn_fire(frontage, 1.0)
	_check(not _inside_a_building(fire.global_position),
		"the fire starts somewhere reachable (%.1f, %.1f)"
		% [fire.global_position.x, fire.global_position.z])

	fire.spread_interval = 0.05
	fire.min_spacing = 0.5
	# **Every child, not the first one.** Stopping at the first spread checked a single
	# golden angle, which happened to land safely — the check passed with reachability
	# deleted. A fire against a frontage has most of its circle inside the building, so it
	# is the later angles that matter.
	var indoors := 0
	var spread := 0
	for sweep in 900:
		await physics_frame
		spread = 0
		indoors = 0
		for node in get_nodes_in_group(Fire.FIRE_GROUP):
			var other := node as Fire
			if other == null or other == fire:
				continue
			spread += 1
			if _inside_a_building(other.global_position):
				indoors += 1
		if spread >= 4:
			break
	_check(spread >= 4, "and it spreads repeatedly (%d children)" % spread)
	_check(indoors == 0, "with none of it inside a building (%d of %d)" % [indoors, spread])
	await _clear_incidents()


## Right-clicking a crewed vehicle turns the crew out of it.
func _test_right_clicking_a_crewed_vehicle_unloads_it() -> void:
	await _place_unit(_car, CityGrid.junction(Vector2i(2, 2)))
	await _place_unit(_officer, _car.global_position + Vector3(3.0, 0.0, 0.0))
	# Both halves: the vehicle takes the seat, the person goes aboard. `Person.board` only
	# does the second, and a crew list that never grew is a vehicle with nothing to unload.
	_car.take_aboard(_officer)
	_officer.board(_car)
	await _idle(6)
	_check(_car.crew.size() == 1 and _officer.is_aboard,
		"the officer is aboard to begin with (%d crew)" % _car.crew.size())

	# **The actual gesture**, not a synthesised target: selected units are normally
	# excluded from the pick so a click near one's own feet reaches the ground, and a
	# crewed vehicle has to be exempt from that or the click never lands on it. Resolving
	# a hand-built Target skips exactly the half worth testing.
	_focus_camera_on_car()
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	_check(_controller.primary() == _car, "with the vehicle selected")
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	await _idle(10)
	_check(_car.crew.is_empty() and not _officer.is_aboard,
		"right-clicking it turns the crew out (%d aboard)" % _car.crew.size())

	# An empty vehicle offers nothing, so a right-click on one still means "drive there".
	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	var empty := _car.resolve(target)
	_check(empty == null or empty.id() != &"unload",
		"an empty vehicle does not offer it (%s)"
		% ["none" if empty == null else empty.id()])
	# Unconditionally, whatever the checks above found: an officer left aboard is hidden
	# with its collision disabled, and every later check that needs one on foot fails.
	_car.unload()
	await _idle(6)
	# Put the officer back where the next check expects to find them: on their feet, clear
	# of the car, with nothing outstanding.
	_officer.clear_orders()
	await _place_unit(_officer, CityGrid.junction(Vector2i(2, 2)) + Vector3(8.0, 0.0, 0.0))
	await _idle(4)


func _test_officer_extinguishes_a_fire() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(20.0, 0.0, 14.0), 0.5)
	fire.spread_interval = 9999.0
	await _place_unit(_officer, Vector3(28.0, 0.1, 14.0))
	_officer.issue(ExtinguishOrder.new(fire))

	# The order has to close the distance before any work happens.
	await _wait(20)
	_check(_officer.is_navigating(), "walks to the fire before starting work")

	var in_range := false
	for i in 900:
		if _officer.global_position.distance_to(fire.global_position) <= ExtinguishOrder.REACH:
			in_range = true
			break
		await physics_frame
	_check(in_range, "reached hose range")
	await _wait(10)
	_check(_officer.action_clip == ExtinguishOrder.CLIP,
		"plays the work clip while working (got '%s')" % _officer.action_clip)

	var done := await _await_orders_done(_officer, 3000)
	_check(done, "finished the extinguish order")
	_check(not is_instance_valid(fire) or not fire.active, "the fire is out")
	_check(_officer.action_clip.is_empty(), "stopped playing the work clip afterwards")
	await _clear_incidents()


func _test_casualty_is_prone() -> void:
	# A casualty standing up looks like nothing is wrong, and no behavioural check
	# would notice: this asserts the pose itself.
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	await _wait(10)

	# Assert the pose, not the player state: current_animation clears when a one-shot
	# finishes, even though the final frame is still held.
	var player: AnimationPlayer = casualty.get_node("Character/AnimationPlayer")
	var skeleton: Skeleton3D = casualty.get_node("Character/Armature/GeneralSkeleton")
	var hips := skeleton.find_bone("Hips")
	var height := (skeleton.global_transform * skeleton.get_bone_global_pose(hips)).origin.y
	# Standing puts the hips near 0.95m; prone is under a third of that.
	_check(height < 0.4,
		"is lying down, not standing (hips at %.2fm, held at %.2fs)"
		% [height, player.current_animation_position])
	await _clear_incidents()


func _test_casualty_declines() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	var before := casualty.health
	await _wait(150)
	_check(casualty.health < before - 0.01,
		"an untreated casualty declined (%.3f -> %.3f)" % [before, casualty.health])
	_check(not casualty.is_stable, "and is not stable")
	await _clear_incidents()


## A paramedic, not an officer. Gating is hard, so an officer has no Treat to issue --
## and this check would pass anyway if it kept using one, because it hands the order
## over directly rather than resolving it. Only the caller changed; that is the point.
func _test_paramedic_treats_a_casualty() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	await _place_unit(_paramedic, Vector3(26.0, 0.1, 14.0))
	_paramedic.issue(TreatOrder.new(casualty))

	var done := await _await_orders_done(_paramedic, 3000)
	_check(done, "finished the treat order")
	_check(not is_instance_valid(casualty) or casualty.is_stable,
		"the casualty was stabilised")
	await _clear_incidents()


## A paramedic sent to a casualty beyond them **holds** them and never finishes.
##
## Both halves matter and they fail in opposite directions. Without the hold this is a unit
## standing uselessly over someone who dies anyway, and the player learns to leave; without
## the refusal there is no specialist and the doctor is decoration. The interesting state is
## the one in between -- alive, and going nowhere -- because that is the state the player has
## to answer by dispatching somebody else.
##
## **Long enough to have finished twice over.** `treat_per_second` is 0.2, so an ordinary
## casualty stabilises in five seconds; ten proves the refusal rather than a slow rate.
func _test_a_paramedic_holds_a_doctors_case_but_cannot_finish_it() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	casualty.needs_doctor = true
	await _place_unit(_paramedic, Vector3(21.2, 0.1, 14.0))
	await _idle(10)

	# **Read before the work, and read the health rather than the clock.** A casualty that
	# was already stable, or already dead, would make every assertion below vacuous.
	_check(not casualty.is_stable and casualty.health > 0.5,
		"the casualty starts alive and unstable (health %.2f)" % casualty.health)
	var opening := casualty.health
	_paramedic.issue(TreatOrder.new(casualty))
	for i in 60 * 10:
		await _idle(1)
		if not is_instance_valid(casualty) or casualty.is_stable:
			break

	_check(is_instance_valid(casualty) and not casualty.is_stable,
		"a paramedic cannot stabilise a casualty who needs a doctor")
	# The decline is 0.012/sec, so ten unheld seconds costs 0.12 -- an order of magnitude
	# more than the rounding this allows for.
	_check(is_instance_valid(casualty) and casualty.health > opening - 0.02,
		"but holds them steady while they work (health %.2f, from %.2f)"
			% [casualty.health if is_instance_valid(casualty) else 0.0, opening])
	_check(is_instance_valid(casualty)
			and casualty.describe_state().contains("doctor"),
		"and the panel says what is needed ('%s')"
			% (casualty.describe_state() if is_instance_valid(casualty) else "gone"))
	_paramedic.clear_orders()
	await _clear_incidents()


## And a doctor finishes it. The same fixture, one unit swapped -- which is the claim.
func _test_a_doctor_stabilises_what_a_paramedic_cannot() -> void:
	await _clear_incidents()
	_station.purchase(&"doctor")
	var doctor := _dispatch_to(&"doctor", Vector3(26.0, 0.1, 14.0)) as Person
	if doctor == null:
		_check(false, "the career can buy a doctor")
		return
	_check(doctor.has_advanced_care(), "a doctor has advanced care")
	_check(not _paramedic.has_advanced_care(), "and a paramedic does not")
	# Same service, so the specialist is expressed *within* it rather than as a fourth
	# emergency service -- which is the whole point of `speciality`.
	_check(doctor.service == _paramedic.service,
		"both are the same service (%d vs %d)" % [doctor.service, _paramedic.service])

	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	casualty.needs_doctor = true
	await _place_unit(doctor, Vector3(21.2, 0.1, 14.0))
	await _idle(10)
	doctor.issue(TreatOrder.new(casualty))
	for i in 60 * 10:
		await _idle(1)
		if not is_instance_valid(casualty) or casualty.is_stable:
			break
	_check(is_instance_valid(casualty) and casualty.is_stable,
		"a doctor stabilises the case a paramedic could only hold")

	# And the rest of the chain is untouched: stable means liftable, which is what makes
	# the doctor a bottleneck in an existing loop rather than a separate one.
	_check(CollectAbility.new().score(_paramedic, _target_for(casualty))
			!= Ability.NOT_APPLICABLE,
		"and the paramedic can now lift them onto the stretcher")
	doctor.clear_orders()
	_station.write_off(doctor)
	await _clear_incidents()


## Two unit types in the same service stay told apart on the books.
##
## The check for a bug that cost an afternoon and whose symptoms point nowhere near it.
## [method Station.type_of] used to identify a unit by (service, vehicle), which is exact
## only while each service has exactly one kind of person. The doctor made MEDICAL-and-not-a-
## vehicle match two catalogue entries, the scan returned the first, and so writing off a
## doctor decremented the **paramedic** count while `_alive` counted every doctor as a
## paramedic -- the dispatch panel then offered paramedics that did not exist and refused
## doctors that did. Every specialist added from here on would have re-broken it identically,
## which is why this is a check and not a comment.
func _test_two_specialists_in_one_service_stay_told_apart() -> void:
	var medics := _station.total(&"paramedic")
	_station.purchase(&"doctor")
	var doctor := _dispatch_to(&"doctor", Vector3(30.0, 0.1, 20.0)) as Person
	if doctor == null:
		_check(false, "the career can buy a doctor")
		return
	# **Stated as a difference, not as two identities.** Written as a pair of `== &"doctor"` /
	# `== &"paramedic"` assertions, the second is inert: the bug returns `paramedic` for both,
	# so it is green either way and cannot see the fault it is here for.
	_check(Station.type_of(doctor) != Station.type_of(_paramedic),
		"a doctor and a paramedic in one service are told apart ('%s' vs '%s')"
			% [Station.type_of(doctor), Station.type_of(_paramedic)])
	_check(Station.type_of(doctor) == &"doctor",
		"and the doctor is identified as a doctor (got '%s')" % Station.type_of(doctor))
	# **Not `available()`.** That is `owned - alive`, so one bought and one dispatched is
	# correctly **zero**, and an assertion of `>= 1` here passed only while `_alive`
	# miscounted the live doctor as a paramedic -- green under the bug, red once fixed. The
	# sabotage pass caught it; it is the exact inversion this project keeps finding.
	_check(_station.total(&"doctor") == 1 and _station.available(&"doctor") == 0,
		"one bought and one out means none spare (%d owned, %d spare)"
			% [_station.total(&"doctor"), _station.available(&"doctor")])

	_station.write_off(doctor)
	await _idle(2)
	_check(_station.total(&"paramedic") == medics,
		"and writing the doctor off leaves the paramedics alone (%d, was %d)"
			% [_station.total(&"paramedic"), medics])
	_check(_station.total(&"doctor") == 0,
		"while the doctor comes off the books (%d)" % _station.total(&"doctor"))
	# **Put the books back whatever happened above.** This test buys and writes off, and if
	# its own assertions fail it fails *because* the roster ended up wrong -- so leaving it
	# wrong contaminates everything downstream. Sabotaged, that cost four further reds and
	# nine checks that never ran, none of them about specialists. The collapse test below
	# cleans up after itself for the same reason.
	_station.owned.erase(&"doctor")
	_station.owned[&"paramedic"] = medics
	await _clear_incidents()


## The director never sets a collapse to a career with no doctor on the books.
##
## Same rule as building fires and an engine, and for the same reason: paramedics would hold
## the casualty indefinitely, the call would never close, and it would read as a bug rather
## than as a hard call. Rolled rather than reasoned about, because the gate lives in the
## weighting and a check that read the table would pass with the filter deleted.
func _test_a_collapse_is_only_offered_with_a_doctor_on_the_books() -> void:
	var before := _station.owns(&"doctor")
	_check(not before, "the fixture career owns no doctor to begin with")
	var without := 0
	for i in 400:
		if _director._pick_kind() == &"collapse":
			without += 1
	_check(without == 0,
		"a career with no doctor is never set a collapse (%d of 400 rolls)" % without)

	_station.purchase(&"doctor")
	var with_one := 0
	for i in 400:
		if _director._pick_kind() == &"collapse":
			with_one += 1
	# Weight 14 of roughly 190 offered: about 7%, so 400 rolls missing it entirely is a
	# one-in-10^12 event. A zero here means the kind is unreachable, not unlucky.
	_check(with_one > 0,
		"and one that owns a doctor is (%d of 400 rolls)" % with_one)

	# **And a doctor on their own is not enough.** The doctor gave up [CollectAbility] in
	# August 2026 so as to stop being a strict superset of the paramedic -- which means a
	# career holding a doctor and nobody to run the stretcher can stabilise a casualty and
	# then owns nothing that can move them. The call would stay open until `overrun_grace`
	# closed it as failed: the road-collision trap, arriving from the other direction.
	#
	# This is the case the leg above cannot see. The fixture career already owns paramedics,
	# so both of its rolls read the same whether or not `_has_doctor` requires one -- the
	# term was live and completely unprotected, which a sabotage run is what established.
	var medics: int = int(_station.owned.get(&"paramedic", 0))
	_station.owned.erase(&"paramedic")
	var alone := 0
	for i in 400:
		if _director._pick_kind() == &"collapse":
			alone += 1
	_check(alone == 0,
		"a doctor with no paramedic behind them is not set one either (%d of 400 rolls)"
		% alone)
	_station.owned[&"paramedic"] = medics

	# Bought but never dispatched, so there is no unit for `write_off` to take -- put the
	# count back by hand rather than leave a doctor on the books for every later check.
	_station.owned.erase(&"doctor")


# --- Roles -------------------------------------------------------------------
