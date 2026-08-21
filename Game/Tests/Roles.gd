extends "res://Game/Tests/Incidents.gd"

## Roles -- 3 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## The phase's whole claim: sending the wrong unit is a wasted trip, not a slower one.

## A doctor stabilises; a paramedic moves the patient.
##
## **These two used to be the same unit.** The MEDICAL arm of `Person._build_abilities()`
## did not branch on speciality at all, so the £600 doctor offered exactly the £250
## paramedic's six verbs plus advanced care -- a strict superset, which left the
## paramedic's only distinguishing feature being that they are cheaper. Taking
## [CollectAbility] off the doctor is what makes the pair a division of labour instead of
## a price list.
##
## Both directions, through `resolve()` rather than by reading the ability list: the point
## is what a right-click on a stable casualty *means* to each of them.

## An officer can get into a landed helicopter, and cannot get into a flying one.
##
## **Two £1,800 units advertised seats nothing could fill.** [Aircraft] extends [Unit]
## directly -- no lightbar, no siren, no repair bill -- and the crew contract lived on
## [Vehicle], so `BoardAbility`'s `target.unit as Vehicle` returned null for a helicopter
## and the ladder fell through to Move. `Aircraft.seats` was declared, read by nothing, and
## dead. The contract is Unit's now.
##
## **Asserted on `resolve()` before anything watches the crew count.** A check that only
## waited for `crew.size()` to move would pass with the cast still broken, because the
## suite can call `take_aboard()` itself -- which is exactly how the fault survived being
## looked at.

## The air ambulance is a stretcher, and it keeps its fire-service colours.
##
## **Two £1,800 airframes were the same unit but for a name and a paint job.** Air Rescue
## carries one stretcher now, which is the whole difference: it takes a casualty to hospital
## over traffic a road ambulance has to sit in.
##
## It stays in the FIRE tree it was bought from. `StretcherOrder.nearest_vehicle()` used to
## ask for `service == MEDICAL`, and satisfying that would have meant moving the unit out of
## the tree the player found it in; it asks for a **stretcher** instead. That test was unsafe
## until August 2026 -- `stretchers` defaulted to 1, so a fire engine and a taxi both
## qualified as ambulances -- and became safe when the default went to 0 and every scene
## stated its own number.
func _test_the_air_ambulance_is_a_second_stretcher() -> void:
	await _clear_calls()
	_buy(&"rescue_heli", 1)
	var chopper := _station.dispatch(&"rescue_heli") as Aircraft
	if chopper == null:
		_check(false, "an air rescue to send")
		return
	_check(chopper.service == Unit.Service.FIRE,
		"the air ambulance still flies for the fire service (%d)" % chopper.service)
	_check(chopper.stretchers == 1 and chopper.has_stretcher_space(),
		"and carries a stretcher (%d)" % chopper.stretchers)

	# **Asked of the lookup a paramedic actually uses**, not of the flag directly.
	await _place_unit(_paramedic, chopper.global_position + Vector3(4.0, 0.0, 0.0))
	_check(StretcherOrder.nearest_vehicle(_paramedic) == chopper,
		"a paramedic beside it finds it as the nearest stretcher (%s)"
		% StretcherOrder.nearest_vehicle(_paramedic))

	# In the air it is not a stretcher: nothing is loaded into a hovering aircraft.
	chopper.take_off()
	var flying := false
	for i in 900:
		await physics_frame
		if chopper.is_airborne():
			flying = true
			break
	_check(flying, "it lifts off (phase %d)" % chopper.phase)
	_check(StretcherOrder.nearest_vehicle(_paramedic) != chopper,
		"and once airborne it is not offered as one (%s)"
		% StretcherOrder.nearest_vehicle(_paramedic))

	_dissolve(chopper, &"rescue_heli")
	await _idle(4)
	await _clear_calls()


func _test_an_officer_can_board_a_landed_helicopter() -> void:
	await _clear_calls()
	_buy(&"helicopter", 1)
	var chopper := _station.dispatch(&"helicopter") as Aircraft
	if chopper == null:
		_check(false, "a helicopter to send")
		return
	_check(chopper.seats > 0,
		"the helicopter has seats at all (%d)" % chopper.seats)
	_check(not chopper.is_airborne(), "and starts on the ground")

	await _place_unit(_officer, chopper.global_position + Vector3(3.0, 0.0, 0.0))
	var target := Target.new()
	target.position = chopper.global_position
	target.unit = chopper
	_check(_resolved_id(_officer, target) == &"board",
		"a right-click on it means Board (%s)" % _resolved_id(_officer, target))

	_officer.issue(_officer.resolve(target).make_order(_officer, target))
	var aboard := false
	for i in 900:
		await physics_frame
		if chopper.crew.has(_officer):
			aboard = true
			break
	_check(aboard, "and the officer gets in (%d aboard)" % chopper.crew.size())

	# **And the bar says so.** `occupants_of` gated the whole readout behind `unit as
	# Vehicle`, which is null for an [Aircraft] -- so a helicopter with people aboard
	# reported an empty cabin on the one panel whose job is saying who is inside. It read
	# correctly for every car, which is exactly why it went unnoticed.
	var riding := UnitReadout.occupants_of(chopper)
	_check(riding.size() == chopper.crew.size() and riding.has(&"officer"),
		"the occupancy readout shows them aboard (%s)" % str(riding))
	_check(UnitReadout.seats_of(chopper) == chopper.seats,
		"and counts the seats it has (%d of %d)"
		% [UnitReadout.seats_of(chopper), chopper.seats])

	# **In the air it is not an option.** Without this the tile is offered at cruising
	# height and a crew steps out from 24 metres up.
	chopper.take_off()
	var flying := false
	for i in 900:
		await physics_frame
		if chopper.is_airborne():
			flying = true
			break
	_check(flying, "the helicopter lifts off (phase %d)" % chopper.phase)
	var self_target := Target.new()
	self_target.position = chopper.global_position
	self_target.unit = chopper
	# **Gated on there being a crew to turn out**, for the same reason the hover leg below
	# is. Without it this printed "nothing" in both the healthy and the sabotaged tree
	# under a boarding fault -- it cannot tell "correctly retained" from "never boarded",
	# and an empty cabin satisfies "will not unload" trivially. This is the safety rule
	# that stops a crew stepping out at 24 metres, so it should not be satisfiable by
	# having nobody up there.
	_check(chopper.crew.size() > 0
			and _resolved_id(chopper, self_target) != &"unload",
		"a flying helicopter will not turn its crew out (%d aboard, %s)"
		% [chopper.crew.size(), _resolved_id(chopper, self_target)])
	# **A hover with an empty cabin proves nothing.** This compared the crew count to
	# itself, so under the boarding fault -- the `as Vehicle` cast that is the whole
	# reason this check exists -- it read `0 of 0` and stayed green. Degenerately true
	# under precisely the bug being tested, and invisible unless you read the ok lines
	# around the reds rather than the reds alone. Somebody has to be aboard for "nobody
	# fell out" to be a claim at all.
	var still := chopper.crew.size()
	await _idle(20)
	_check(still > 0 and chopper.crew.size() == still,
		"and nobody falls out while it hovers (%d of %d)"
		% [chopper.crew.size(), still])

	chopper.unload()
	_dissolve(chopper, &"helicopter")
	await _idle(4)
	await _clear_calls()


func _test_a_doctor_cannot_run_the_stretcher() -> void:
	await _clear_calls()
	_buy(&"doctor", 1)
	var doctor := _station.dispatch(&"doctor") as Person
	if doctor == null:
		_check(false, "a doctor to send")
		return
	_check(doctor.speciality == Person.DOCTOR,
		"the doctor carries the doctor speciality ('%s')" % doctor.speciality)

	var casualty := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
		.instantiate() as Casualty
	_incidents.add_child(casualty)
	casualty.global_position = _ambulance.global_position + Vector3(3.0, 0.2, 0.0)
	# **Stable, not merely treated.** Setting `treatment` alone leaves `is_stable` false,
	# and Treat (30) then outscores Collect (25) for *everybody* -- so both legs below
	# read `treat` and the doctor's leg passes without proving anything. The check caught
	# that on its first run, which is the argument for asserting both sides rather than
	# only the one the change was about.
	casualty.is_stable = true
	await _idle(4)

	var target := Target.new()
	target.position = casualty.global_position
	target.incident = casualty
	_check(_resolved_id(doctor, target) != &"collect",
		"a right-click on a stable casualty is not the doctor's stretcher run (%s)"
		% _resolved_id(doctor, target))
	_check(_resolved_id(_paramedic, target) == &"collect",
		"-- it is the paramedic's (%s)" % _resolved_id(_paramedic, target))

	# And the doctor has not simply been stripped of everything: treating is still theirs,
	# which is what stops this passing on a unit that lost its whole verb list.
	casualty.is_stable = false
	casualty.needs_doctor = true
	await _idle(2)
	_check(_resolved_id(doctor, target) == &"treat",
		"the doctor still treats (%s)" % _resolved_id(doctor, target))

	casualty._finish(true)
	_dissolve(doctor, &"doctor")
	await _idle(4)
	await _clear_calls()


## No two units in the catalogue are the same unit.
##
## **A standing guard against the whole class of problem a fleet audit found**: seven of
## the fourteen purchasable units had no capability that distinguished them from another,
## and nothing in the suite would ever have said so. The interceptor was a patrol car with
## two more metres per second; the doctor's verbs were the paramedic's exactly.
##
## Fingerprinted on the verbs *and* the carrying numbers, because both are ways a unit can
## be different: the van is the patrol car's verb list with six seats and six cells, and
## that is a real difference. Each unit is added to the tree first -- abilities are built
## in `_ready`, and a bare `instantiate()` returns an empty list, which would fingerprint
## every unit identically and pass nothing.
func _test_no_two_purchasable_units_are_the_same_unit() -> void:
	var prints := {}
	var clashes := PackedStringArray()
	var swept := 0
	for config: Dictionary in Station.TYPES:
		var packed := load(String(config["scene"])) as PackedScene
		if packed == null:
			continue
		var unit := packed.instantiate() as Unit
		if unit == null:
			continue
		_scene.add_child(unit)
		await _idle(1)
		swept += 1
		var verbs := PackedStringArray()
		for ability in unit.abilities():
			verbs.append(String(ability.id()))
		verbs.sort()
		var vehicle := unit as Vehicle
		var shape := "%s|%d" % [", ".join(verbs), unit.service]
		if vehicle:
			shape += "|s%d c%d st%d tow%s water%s" % [vehicle.seats, vehicle.cells,
				vehicle.stretchers, vehicle.can_tow, vehicle.carries_water]
		var id: StringName = config["id"]
		if prints.has(shape):
			clashes.append("%s is %s" % [id, prints[shape]])
		prints[shape] = id
		unit.queue_free()
		await _idle(1)

	_check(swept == Station.TYPES.size(),
		"all %d purchasable units were read (%d)" % [Station.TYPES.size(), swept])
	_check(clashes.is_empty(),
		"and no two of them are the same unit (%s)"
		% ("all distinct" if clashes.is_empty() else "; ".join(clashes)))


## A held prop lands in the hand, and turns with it.
##
## **The three things about this that can be judged headlessly**, which is not the same as
## the three things that matter. Whether a pistol looks *held* is a human's call in a
## window -- that is what `Game/HandCalibration.tscn` is for, and no assertion here
## replaces it. What a check can hold is that the prop exists, that it is on the hand
## rather than somewhere else in the district, and that it is placed off the **wrist**
## rather than the body.
##
## That last one is the whole mechanism change and the one that would regress in silence:
## the shipped code took the hand bone's *origin* and the *body's* yaw, so a prop tracked
## the torso and sat wrong the moment a clip turned the hand. Nothing looked broken from
## the outside -- the weapon was visible, in roughly the right place, and every existing
## check about it stayed green.
func _test_a_held_prop_sits_in_the_hand() -> void:
	# **Every calibrated path resolves.** A typo here is not an error anywhere -- `load`
	# returns null, the caller clears `weapon_scene`, and the officer is quietly unarmed.
	var missing := PackedStringArray()
	for path: String in HeldItem.OFFSETS:
		if load(path) as PackedScene == null:
			missing.append(path.get_file())
	_check(missing.is_empty(),
		"every calibrated prop resolves (%s)"
		% ("clear" if missing.is_empty() else ", ".join(missing)))

	# **Every body the tool offers actually has the bone the tool assumes.** Read off
	# HandCalibration's own list rather than a second copy: a rig retargeted without a
	# `RightHand` shows in the harness as a prop floating beside a character and in the
	# game as a weapon that never appears.
	var boneless := PackedStringArray()
	for path: String in HandCalibration.BODIES:
		var packed := load(path) as PackedScene
		if packed == null:
			boneless.append(path.get_file())
			continue
		var body := packed.instantiate() as Node3D
		if body == null:
			boneless.append(path.get_file())
			continue
		# In the tree, because a Skeleton3D outside one has no global pose to read.
		_scene.add_child(body)
		var rig: Skeleton3D = null
		for node in body.find_children("*", "Skeleton3D", true, false):
			rig = node as Skeleton3D
			break
		if rig == null or rig.find_bone(HeldItem.HAND_BONE) < 0:
			boneless.append(path.get_file())
		body.queue_free()
	_check(boneless.is_empty(),
		"every character the calibration tool offers has a %s (%s)"
		% [HeldItem.HAND_BONE,
			"clear" if boneless.is_empty() else ", ".join(boneless)])

	_buy(&"arv", 1)
	var arv := _station.dispatch(&"arv") as Person
	if arv == null:
		_check(false, "an ARV to send")
		return
	await _idle(8)
	var pistol := arv.get_node_or_null("HeldWeapon") as Node3D
	var rig := HeldItem.skeleton_of(arv)
	var bone := rig.find_bone(HeldItem.HAND_BONE) if rig else -1
	if pistol == null or rig == null or bone < 0:
		_check(false, "the ARV is carrying something off a rig (%s / %s / %d)"
			% [pistol, rig, bone])
		_dissolve(arv, &"arv")
		return
	var hand := rig.global_transform * rig.get_bone_global_pose(bone)
	var gap := pistol.global_position.distance_to(hand.origin)
	# A hand's width, not a tolerance: this catches the class of fault where a prop is
	# left at the world origin or drifts off with its carrier. This project has had a
	# held prop travel 19m in six seconds.
	#
	# **It witnesses nothing about the composition, and should not be read as if it does.**
	# It printed exactly `0.000m` through all three sabotages of `place()` -- basis
	# discarded, correction discarded, table key corrupted -- because every shipped offset
	# is zero, so the prop sits on the bone origin whatever the code does with the rest.
	# The legs below are what hold the composition; this one holds the drift class alone.
	_check(gap < 0.30,
		"the sidearm is in the hand rather than near it (%.3fm)" % gap)

	# **It turns with the wrist.** Posed directly rather than through a clip so the
	# animation cannot overwrite it mid-assertion, and about the bone's own origin so the
	# *position* does not move -- which is what makes this a test of the basis alone.
	# Under the shipped code the prop took `global_rotation` from the body, so this rotates
	# the hand through a right angle and the pistol does not move at all.
	var before := pistol.global_transform.basis
	rig.set_bone_pose_rotation(bone, Quaternion(Vector3.UP, PI * 0.5))
	HeldItem.place(pistol, rig, arv.weapon_scene)
	var after := pistol.global_transform.basis
	_check(not before.is_equal_approx(after),
		"and turns with the hand rather than with the body")
	rig.reset_bone_pose(bone)
	await _idle(2)

	# **The correction is applied at all.** Every shipped row is zero today, so a `place()`
	# that ignored the table outright would put every prop in exactly the right spot and
	# nothing here would notice -- the gap leg above would still read 0.000m. Measured
	# against a known correction instead, so this keeps its teeth however the table is
	# later tuned, and stays honest about the fact that the *shipped* numbers are a human's
	# judgement in a window rather than anything a check can hold.
	var probe := {"pos": Vector3(0.0, 0.11, 0.0), "rot": Vector3.ZERO, "scale": 1.0}
	HeldItem.place(pistol, rig, arv.weapon_scene, probe)
	var moved := pistol.global_position.distance_to(
		(rig.global_transform * rig.get_bone_global_pose(bone)).origin)
	_check(absf(moved - 0.11) < 0.005,
		"and an offset moves it by exactly that much (%.3fm for 0.110m asked)" % moved)

	_dissolve(arv, &"arv")
	await _idle(4)


func _test_services_gate_their_verbs() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	var fire := _spawn_fire(Vector3(20.0, 0.0, 20.0), 0.5)

	var treat := TreatAbility.new()
	var extinguish := ExtinguishAbility.new()
	_check(treat.score(_officer, _target_for(casualty)) != Ability.NOT_APPLICABLE,
		"Treat itself would apply to a casualty for anybody")
	_check(_find_ability(_officer, &"treat") == null,
		"but an officer is not offered it at all")
	_check(_find_ability(_paramedic, &"extinguish") == null,
		"and a paramedic is not offered Extinguish")
	_check(_find_ability(_paramedic, &"secure") == null,
		"nor Secure, which is a police job")

	# The consequence, through the resolution the player actually uses.
	var officer_verb := _officer.resolve(_target_for(casualty))
	_check(officer_verb != null and officer_verb.id() == &"move",
		"right-clicking a casualty with an officer means Move (got '%s')"
			% ("none" if officer_verb == null else officer_verb.id()))
	var medic_verb := _paramedic.resolve(_target_for(fire))
	_check(medic_verb != null and medic_verb.id() == &"move",
		"and a fire with a paramedic means Move (got '%s')"
			% ("none" if medic_verb == null else medic_verb.id()))

	# Collect follows the service, and now the feet: the paramedic runs the
	# stretcher, and the ambulance -- which cannot leave the road -- no longer
	# pretends it can drive to a casualty.
	_check(_find_ability(_paramedic, &"collect") != null,
		"the paramedic is offered Collect")
	_check(_find_ability(_ambulance, &"collect") == null,
		"the ambulance is not -- the stretcher does the collecting")
	_check(_find_ability(_car, &"collect") == null,
		"nor the patrol car")
	_check(_ambulance.service == Unit.Service.MEDICAL
			and _paramedic.service == Unit.Service.MEDICAL,
		"the ambulance and the paramedic are the same service")
	await _clear_incidents()


## Secure declines every right-click on purpose -- it applies to any patch of ground,
## so left to score it would swallow Move and an officer could never be sent anywhere.
## It has to be armed, which is what can_target() exists for.
func _test_an_officer_secures_a_scene() -> void:
	await _clear_incidents()
	var ability := _find_ability(_officer, &"secure")
	if ability == null:
		_check(false, "the officer offers Secure")
		return

	var spot := Vector3(20.0, 0.0, 10.0)
	var target := Target.new()
	target.position = spot
	_check(ability.score(_officer, target) == Ability.NOT_APPLICABLE,
		"Secure declines a right-click on open ground")
	_check(ability.can_target(_officer, target),
		"but accepts it once armed")

	await _place_unit(_officer, Vector3(26.0, 0.1, 10.0))
	_controller.select([_officer])
	_controller.activate(ability)
	_check(_controller.armed_ability != null
			and _controller.armed_ability.id() == &"secure",
		"the tile armed it (%s)" % _armed_id())
	_controller._fire_armed(target)
	_check(_officer.has_orders(), "and clicking the ground issued the order")

	var raised: Cordon = null
	for i in 1500:
		await physics_frame
		for node in get_nodes_in_group(Cordon.GROUP):
			var cordon := node as Cordon
			if cordon and cordon.raised:
				raised = cordon
				break
		if raised:
			break
	_check(raised != null, "the officer walked over and set the cordon out")
	if raised:
		_check(_flat_distance(raised.global_position, spot) < 1.0,
			"where it was clicked (%.1fm away)"
				% _flat_distance(raised.global_position, spot))
		_check(raised.get_child_count() >= raised.cone_count,
			"with its cones out (%d)" % raised.get_child_count())
	await _clear_cordons()


## The cordon is not a wall -- it has no collision, because one across the road would
## trap the ambulance the officer put it there to make room for. Keeping the public out
## is a decision the crowd makes.
func _test_a_cordon_clears_the_public() -> void:
	await _clear_cordons()
	var spot := Vector3(20.0, 0.0, -20.0)
	var cordon := Cordon.new()
	_scene.add_child(cordon)
	cordon.global_position = spot

	# The crowd was cleared long ago, so put one back -- a check that the public leaves
	# a cordon proves nothing with no public to leave it.
	var shopper := (load(CIVILIAN_SCENE) as PackedScene).instantiate() as Civilian
	_scene.add_child(shopper)
	shopper.global_position = spot + Vector3(1.5, 0.2, 0.0)
	await _wait(40)
	_check(not shopper.is_fleeing,
		"a civilian ignores a cordon that has not been set out yet")

	cordon.raise_cordon()
	_check(cordon.contains(shopper.global_position),
		"the shopper is inside the ring once it is up")
	await _wait(40)
	_check(shopper.is_fleeing, "raising it sends them out")

	var left := false
	for i in 900:
		await physics_frame
		if not cordon.contains(shopper.global_position):
			left = true
			break
	_check(left, "and they clear it (%.1fm from the middle)"
		% _flat_distance(shopper.global_position, spot))

	shopper.queue_free()
	await _clear_cordons()


# --- Dispatch ----------------------------------------------------------------
