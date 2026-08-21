extends "res://Game/Tests/AmbientPopulation.gd"

## Autopilot -- 27 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_starting_units_are_clickable() -> void:
	# Run before anything is teleported, so this is the arrangement the map actually
	# ships, seen from the view the game actually opens on.
	#
	# The bug it catches: picking is a camera ray, so a unit parked close to a
	# building simply cannot be selected -- the building is in the way. It is
	# invisible to every other check, because the unit itself works perfectly. The
	# station crew were parked 2m from a 6.8m frontage and none of the four could be
	# clicked at all.
	_camera.stop_following()
	_camera.focus = _opening_focus
	_camera._target_distance = _opening_distance
	await _idle(60)

	var blocked := PackedStringArray()
	for node in _scene.get_node("Units").get_children():
		var unit := node as Unit
		if unit == null or not unit.is_selectable():
			continue
		var aim := unit.global_position + Vector3.UP * 0.9
		if _camera.is_position_behind(aim):
			blocked.append("%s (off screen)" % unit.name)
			continue
		var hit := _controller._raycast(_screen_of(aim)).get("collider") as Node
		if hit != unit:
			blocked.append("%s (ray stops on %s)" % [unit.name, hit])
	_check(blocked.is_empty(),
		"all %d starting units can be clicked from the opening view%s" % [
			_scene.get_node("Units").get_child_count(),
			"" if blocked.is_empty() else " -- blocked: " + ", ".join(blocked)])


## A left turn's chord from stop line to exit lane cuts through the oncoming halves
## of both streets -- the taxi on the wrong side of the yellow line mid-junction.
## CityGrid.turn_apex is the fix; this pins its geometry, then stages the drive.
func _test_left_turns_round_the_apex() -> void:
	var junction := CityGrid.junction(Vector2i(3, 2))
	var east := Vector3(1.0, 0.0, 0.0)
	var north := Vector3(0.0, 0.0, -1.0)
	var south := Vector3(0.0, 0.0, 1.0)
	var apex := CityGrid.turn_apex(junction, east, north)
	_check(apex != Vector3.ZERO and apex.x > junction.x and apex.z > junction.z,
		"a left turn gets an apex on the driver's own quadrant (%s)" % apex)
	_check(CityGrid.turn_apex(junction, east, south) == Vector3.ZERO,
		"a right turn gets none -- it hugs its own corner already")
	_check(CityGrid.turn_apex(junction, east, east) == Vector3.ZERO,
		"and straight on gets none")

	# The drive: a taxi at the stop line, eastbound, staged into the left turn north.
	# Sampled north of the junction's centre line, where the old chord put it a good
	# two metres onto the oncoming side of the avenue it was turning into.
	var packed := load("res://Game/Traffic/Taxi.tscn") as PackedScene
	if packed == null:
		_check(false, "a taxi scene to stage the turn with")
		return
	var taxi := packed.instantiate() as TrafficCar
	_scene.add_child(taxi)
	taxi.global_position = Vector3(14.0, 0.2, -17.5)
	taxi.global_rotation = Vector3(0.0, CityGrid.heading(east), 0.0)
	await _wait(4)
	taxi._from = Vector2i(3, 2)
	taxi._to = Vector2i(3, 1)
	taxi._last_direction = east
	taxi._begin_leg()

	var worst := INF
	for i in 900:
		await physics_frame
		var here := taxi.global_position
		if here.z < -26.0:
			break
		if here.z < junction.z:
			worst = minf(worst, here.x)
	_check(worst != INF and worst > 19.0,
		"turning left it kept east of the exit street's centre line (min x %.1f)"
		% (worst if worst != INF else -1.0))
	taxi.queue_free()
	await _wait(4)


func _test_starts_parked() -> void:
	var start := _car.global_position
	await _wait(60)
	_check(not _car.has_orders(), "starts with no order")
	_check(start.distance_to(_car.global_position) < 0.2,
		"sits still until ordered (drifted %.3fm)" % start.distance_to(_car.global_position))
	_check(absf(_car.global_position.y) < 0.1,
		"rests on the deck (y=%.3f)" % _car.global_position.y)


func _test_drives_to_target() -> void:
	await _place(ROAD)
	# Straight up the same avenue, through one junction.
	var target := Vector3(20.0, 0.0, -14.0)
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(900)
	_check(arrived, "completed the order before the timeout [%s]" % _car_state())
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the target" % _flat_distance(_car.global_position, target))


func _test_stops_on_arrival() -> void:
	# Carries straight on from the previous test's arrival.
	await _wait(60)
	_check(absf(_car.forward_speed) < 0.5,
		"came to rest (%.2f m/s)" % _car.forward_speed)
	_check(not _car.has_orders(), "cleared its order on arrival")


func _test_turns_around_for_a_target_behind() -> void:
	await _place(ROAD)
	# Car faces -Z, so a target at +Z is directly behind it: this is the case that
	# needs the reverse manoeuvre, since a car cannot turn on the spot.
	var target := ROAD + Vector3(0.0, 0.0, 6.0)
	target.y = 0.0
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(900)
	_check(arrived, "reached a target directly behind it")
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the target behind" % _flat_distance(_car.global_position, target))


func _test_crosses_the_map() -> void:
	# Corner to opposite corner of the outer ring road: the better part of half a
	# kilometre of driving, with a turn at every junction it takes on the way.
	await _place(CityGrid.junction(Vector2i(0, 0)) + Vector3(10.0, 0.15, 0.0))
	var target := CityGrid.junction(Vector2i(CityGrid.BANDS - 1, CityGrid.BANDS - 1))
	_car.issue(MoveOrder.new(target))
	# Counted rather than merely timed out on. This is the longest drive in the suite
	# and its budget has twice been the thing that broke -- once at 3600 frames, when
	# the drive itself takes around 3800. A timeout says only "too slow"; the count
	# says how slow, so the next slowdown is legible instead of mysterious.
	var frames := 0
	var arrived := false
	for i in CROSSING_BUDGET:
		if not _car.has_orders():
			arrived = true
			break
		frames = i
		await physics_frame
	_check(arrived, "drove corner to corner of the district in %d of %d frames [%s]"
		% [frames, CROSSING_BUDGET, _car_state()])
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the far corner" % _flat_distance(_car.global_position, target))


func _test_routes_around_a_building() -> void:
	# Straight across the centre block, which is 30m of solid building. The only way
	# there is round it, and the road network is the only thing that offers one.
	await _place(Vector3(20.0, 0.15, 0.0))
	var target := Vector3(-20.0, 0.0, 0.0)
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(1800)
	_check(arrived, "found a way round the centre block [%s]" % _car_state())
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.5,
		"stopped %.2fm the far side" % _flat_distance(_car.global_position, target))


## A route never starts by sending a car the wrong way.
##
## The lattice route begins at the nearest junction, and nearest is often *behind*: two
## thirds of the way along a street, the corner already passed is closer than the one
## ahead. Reported from play as "it immediately turns left and does a 360 degree loop
## before heading right", and measured from the recorded start: bound 185m east, the car
## went up to 25m **west** and turned through **523 degrees** before making any eastward
## ground.
func _test_a_route_does_not_start_behind_the_car() -> void:
	# The position the black box recorded, and a destination far to the east of it.
	var from := Vector3(-58.0, 0.0, 26.0)
	var to := Vector3(126.5, 0.0, -75.0)
	var route := CityGrid.lane_route(from, to)
	_check(route.size() > 2, "a journey across the district is lane routed (%d waypoints)"
		% route.size())
	if route.is_empty():
		return
	var onward := to - from
	onward.y = 0.0
	var first := route[0] - from
	first.y = 0.0
	_check(first.dot(onward) > 0.0,
		"and sets off towards the destination, not away from it (first waypoint %.1f, %.1f)"
		% [route[0].x, route[0].z])


## Shutting a street and asking the lattice for a way round. Pure routing, no driving:
## if this is wrong the behavioural check below cannot be right for the right reason.
func _test_a_shut_street_is_routed_around() -> void:
	var a := Vector2i(2, 3)
	var b := Vector2i(2, 2)
	var direct := CityGrid.route(a, b)
	_check(direct.size() == 2, "two neighbouring junctions are one street apart (%d)"
		% direct.size())

	var shut := {CityGrid.street_key(a, b): true}
	var round_it := CityGrid.route(a, b, shut)
	_check(round_it.size() > direct.size(),
		"with that street shut the way there is longer (%d junctions, was %d)"
		% [round_it.size(), direct.size()])
	var used := false
	for i in range(1, round_it.size()):
		if CityGrid.street_key(round_it[i - 1], round_it[i]) == CityGrid.street_key(a, b):
			used = true
	_check(not used and round_it.size() > 0, "and does not use the shut street")
	# Named the same both ways round, or a driver that gave up going one way would plan
	# straight back down it going the other.
	_check(CityGrid.street_key(a, b) == CityGrid.street_key(b, a),
		"a street has one name whichever way it is driven")


## A street is only written off when something is actually sitting in it.
##
## Getting nowhere and being blocked are different, and confusing them is expensive: a
## car recorded in play reversed out of its own escape manoeuvre with nothing within 14m,
## concluded the street was shut, wrote off two of them, and turned a journey 200m **east**
## into a twenty-waypoint route ending at the far **west** edge of the map.
func _test_a_clear_street_is_not_written_off() -> void:
	await _place(CityGrid.junction(Vector2i(3, 2)) + Vector3(CityGrid.LANE_OFFSET, 0.15, 20.0))
	var order := MoveOrder.new(CityGrid.junction(Vector2i(3, 1)))
	_car.issue(order)
	await _idle(4)
	# Pinned where it stands, so it makes no progress at all -- which is exactly what the
	# give-up timer watches for. Nothing is in its way; the road is not the problem.
	#
	# Held in place rather than frozen: `set_physics_process(false)` also stops the order
	# ticking, so the give-up never runs at all and the check passes with its subject
	# deleted.
	var spot := _car.global_position
	for i in int(MoveOrder.GIVE_UP_AFTER * 60.0) + 180:
		await physics_frame
		_car.global_position = spot
		_car.velocity = Vector3.ZERO
	_check(order._shut.is_empty(),
		"a car going nowhere on an empty street writes none of it off (%d shut)"
		% order._shut.size())
	_car.clear_orders()
	await _idle(6)


## Traffic gets warning proportional to how fast the response is coming.
##
## A flat 16m radius is two thirds of a second at 25 m/s: the car began tucking when the
## responder was already on top of it, never cleared the lane, and the response spent the
## pass crawling behind it. Notice is time, not distance.
func _test_traffic_is_warned_in_time() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	await _idle(4)
	var street := CityGrid.band_centre_z(2)
	taxi.global_position = Vector3(0.0, 0.2, street + CityGrid.LANE_OFFSET)
	taxi.rotation.y = -PI * 0.5

	# A responder 40m back: too far to have registered under the old flat radius.
	await _place_unit(_car, Vector3(-40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	_car.issue(MoveOrder.new(Vector3(60.0, 0.0, street + CityGrid.LANE_OFFSET)))
	await _idle(2)
	# Asked in the same breath as it is set: `_update_movement` recomputes `forward_speed`
	# from the actual velocity on its first line, so a speed assigned between frames is
	# gone before the next one reads it.
	_car.forward_speed = 25.0
	_check(taxi._responder_near(taxi.pull_over_radius) != null,
		"a taxi 40m ahead of a fast response has already been warned")

	# Crawling, the same car at the same distance is not its problem yet.
	_car.clear_orders()
	await _place_unit(_car, Vector3(-40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	await _idle(2)
	_car.forward_speed = 0.0
	_check(taxi._responder_near(taxi.pull_over_radius) == null,
		"and a stationary one 40m back is not")

	# Nor is one that has already gone past, however fast it is going.
	await _place_unit(_car, Vector3(40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	_car.issue(MoveOrder.new(Vector3(90.0, 0.0, street + CityGrid.LANE_OFFSET)))
	await _idle(2)
	_car.forward_speed = 25.0
	_check(taxi._responder_near(taxi.pull_over_radius) == null,
		"nor one that is already past and driving away")

	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


## Being held at somebody else's speed counts as stuck.
##
## The give-up timer watches for **no progress**, and a car crawling behind a taxi is
## making progress — so it reset every frame and a journey could spend its whole length
## doing 3 m/s with a 25 m/s ceiling, which is stuck by any measure a player would use.
func _test_crawling_behind_someone_counts_as_stuck() -> void:
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	# **Two abreast**, because one is passable: with a lane free the car finds a gap, takes
	# it, and is never held at all -- which is the system working and no test of this.
	# One **in the lane** and one **on the passing line**. Placed 2.6m either side of the
	# centre they sat outside the 2.4m corridor the car sweeps, so neither counted as in
	# the way and it drove between them; and with only the first, the car simply passes,
	# which is the system working and no test of this.
	var junction := CityGrid.junction(Vector2i(3, 2))
	var wall: Array[TrafficCar] = []
	for across in [CityGrid.LANE_OFFSET, CityGrid.LANE_OFFSET - 3.4]:
		var blocker := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
			.instantiate() as TrafficCar
		_scene.add_child(blocker)
		blocker.set_physics_process(false)
		blocker.global_position = junction + Vector3(across, 0.2, -8.0)
		wall.append(blocker)
	await _idle(6)

	# Facing the way it is going: forward is -Z, and junction 3,1 lies south of 3,2.
	await _place_unit(_car, junction + lane, 0.0)
	_car.issue(MoveOrder.new(CityGrid.junction(Vector2i(3, 1)) + lane))
	var held := 0.0
	for i in 900:
		await physics_frame
		held = maxf(held, _car.held_up_for())
		if held > 0.5:
			break
	_check(held > 0.0, "a unit stuck behind a slower vehicle knows it (%.1fs)" % held)

	for blocker in wall:
		blocker.queue_free()
	_car.clear_orders()
	# Put it somewhere clear before leaving: this check ends with the car nose-first
	# against a wall of parked cars, and the next one places it and expects it to drive.
	await _idle(6)
	await _place_unit(_car, CityGrid.junction(Vector2i(2, 3)))
	await _idle(6)


## The fault this was built for: a car that sits behind an obstruction for ever.
##
## Four cars fill the full 10m width of a carriageway, which is not shovable and has no
## gap, and the patrol car is sent to the far side of them. Before the give-up timer it
## spent the whole minute pushing at them and finished 18.7m short.
func _test_a_car_gives_up_on_a_blocked_street() -> void:
	var a := CityGrid.junction(Vector2i(4, 3))
	var b := CityGrid.junction(Vector2i(4, 2))
	var along := (b - a).normalized()
	var across := along.cross(Vector3.UP)
	var mid := (a + b) * 0.5

	var wall: Array[Vehicle] = []
	for offset in [-3.75, -1.25, 1.25, 3.75]:
		var blocker := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
			.instantiate() as TrafficCar
		_scene.add_child(blocker)
		blocker.set_physics_process(false)
		blocker.global_position = mid + across * offset
		blocker.rotation.y = atan2(along.x, along.z) + PI
		wall.append(blocker)
	await _idle(10)

	await _place_unit(_car, a + along * 14.0 + across * CityGrid.LANE_OFFSET,
		atan2(along.x, along.z) + PI)
	var target := mid + along * 14.0
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(3600)

	# Only the arrival is asserted. "And it did not shove them out of the way" reads like
	# a useful companion and is not one: with vehicle-on-vehicle collision working it
	# cannot come out any way but zero, and it stayed zero in a run where the car spent
	# the whole minute pushing at the wall. That the wall is solid belongs to
	# _test_vehicles_cannot_drive_through_each_other, which can actually fail.
	_check(arrived, "got to the far side of a street with no way through [%s]"
		% _car_state())
	for blocker in wall:
		blocker.queue_free()
	_car.clear_orders()
	await _idle(6)



## The interface's ink stays legible on the ground it is drawn on.
func _test_the_interface_can_be_read() -> void:
	# **A class of bug, not an instance of it.** Two colours have shipped written by hand
	# at a call site, correct for the scheme at the time and wrong afterwards: a 13% white
	# progress track that was invisible on a white card, and near-black shop wells left
	# over from a dark scheme on a light one. Both were found by eye, months apart. A
	# table of the pairs the interface actually uses catches the next one for free -- and
	# it earned its place immediately, because the August 2026 restyle inverted the whole
	# palette and every one of these pairs had to survive it.
	#
	# **Two tables, because these are two questions.** Ink on a ground has to be *read*,
	# and 3.0 is the bar (rather than WCAG's 4.5 -- this is chrome and large glyphs, not
	# body copy, and a bar too strict to pass is one that gets loosened rather than
	# obeyed). Two adjacent *surfaces* only have to be told apart, which is a much lower
	# bar and the reference does half of it with a border rather than with contrast.
	#
	# Splitting them was not a way to make a failing row pass: the surface row failed at
	# 1.2:1 and the palette was changed to fix it. Folding it into the ink table at 3.0
	# would have meant a tile brighter than the card it sits in.
	# **The chrome is the UI kit's art, and the theme has to still be made of it.**
	# `build_theme.gd` used to bake StyleBoxFlat -- a colour and a corner radius -- and
	# the difference between that and the kit is invisible to every other check here:
	# the sizes are the same, the text is the same, the suite is headless and never
	# looks at a pixel. Re-running an older builder, or one edit that drops back to
	# `_flat()`, would quietly return the game to its old look with everything green.
	# So: the panel a card is drawn with must be a *texture* box, and that texture must
	# come from the kit folder.
	var chrome := _scene.get_node("HUD/Root").theme as Theme
	var card_box := chrome.get_stylebox("panel", "CardPanel") as StyleBoxTexture
	var card_art := card_box.texture.resource_path if card_box and card_box.texture else ""
	_check(card_box != null and card_art.begins_with("res://Game/UI/Kit/"),
		"a card is drawn from the kit's art ('%s')" % card_art)
	# And the kit's faces, which is what actually makes it read as the reference rather
	# than as stock Godot. Checked on the button, because a button label is the one
	# piece of text that is neither body copy nor a heading.
	#
	# **Names the face, not just the folder.** Asking only for something under
	# `Game/UI/Fonts/` had a second, independent payer: the theme's `default_font` is a
	# kit face too, so deleting the button's own font left the check green reading
	# Barlow -- it could not tell "deliberately set in the display face" from "never
	# styled and fell through to body copy". The kit pairs Rajdhani with buttons for a
	# reason, and that is the thing worth pinning.
	var button_font := chrome.get_font("font", "Button")
	var face := button_font.resource_path if button_font else ""
	_check(face.begins_with("res://Game/UI/Fonts/Rajdhani"),
		"and its labels are set in the kit's display face ('%s')" % face)

	var pairs := [
		["text on a card", Palette.TEXT, Palette.CARD],
		["dim text on a card", Palette.TEXT_DIM, Palette.CARD],
		["text on the bar", Palette.TEXT, Palette.BAR],
		["tile ink on an unarmed tile", Palette.TEXT, Palette.WELL],
		["tile ink on an armed tile", Palette.CARD, Palette.MEDICAL],
		["tile ink on a running toggle", Palette.CARD, Palette.POLICE],
		["an alarm label on its wash", Palette.CASUALTY_DEEP, Palette.ALARM_WASH],
		["police ink on its muted fill", Palette.POLICE_DEEP, Palette.POLICE_PALE],
		["medical ink on its muted fill", Palette.MEDICAL_DEEP, Palette.MEDICAL_PALE],
		["fire ink on its muted fill", Palette.FIRE_DEEP, Palette.FIRE_PALE],
		["a progress fill against its track", Palette.GOOD, Palette.WELL],
	]
	var worst := INF
	var worst_pair := ""
	for pair: Array in pairs:
		var ratio: float = Palette.contrast(pair[1] as Color, pair[2] as Color)
		if ratio < worst:
			worst = ratio
			worst_pair = str(pair[0])
	_check(worst >= 3.0,
		"every ink reads on its ground (worst: %s at %.1f:1)" % [worst_pair, worst])

	# **Each pair now names what separates it, because the scheme changed under this
	# check.** The UI kit adopted in August 2026 separates surfaces with a *stroke* and a
	# gradient rather than a step in fill: its raised panel is #18222F -> #0E1620 inside
	# a #212D3C line, and the fills either side of that line are 1.16:1 apart. Held to
	# the old flat 1.3 this row failed on art that is plainly legible on screen.
	#
	# **This is a loosening, and worth saying so.** What stops it being the kind that
	# gets obeyed-by-lowering: a pair with no stroke is still held to 1.3, and a pair
	# that claims one must show that stroke stepping clear of the darker fill. The
	# original failure mode -- a surface the same colour as its ground, with nothing
	# between them -- fails either arm. What is no longer asserted is that two *fills*
	# alone carry the separation, which in this scheme is simply not how it is done.
	var surfaces := [
		["a recessed tile against its card", Palette.WELL, Palette.CARD,
			Palette.EDGE_SOFT],
		["a hovered tile against its card", Palette.HOVER, Palette.CARD, null],
		["a card against the bar", Palette.CARD, Palette.BAR, Palette.EDGE],
	]
	var flattest := INF
	var flattest_pair := ""
	var unlined := ""
	for pair: Array in surfaces:
		var ratio: float = Palette.contrast(pair[1] as Color, pair[2] as Color)
		var stroke: Variant = pair[3]
		if stroke == null:
			# Nothing between them: the fills have to do all of it, at the old bar.
			if ratio < flattest:
				flattest = ratio
				flattest_pair = str(pair[0])
			continue
		# Lined: the fills need only differ, and the line has to clear the darker of
		# the two it sits between.
		var darker: Color = (pair[1] as Color) if Palette.contrast(pair[1] as Color,
			Color.WHITE) > Palette.contrast(pair[2] as Color, Color.WHITE) \
			else (pair[2] as Color)
		var edge: float = Palette.contrast(stroke as Color, darker)
		if ratio < 1.10 or edge < 1.15:
			unlined = "%s (fills %.2f:1, line %.2f:1)" % [pair[0], ratio, edge]
	_check(flattest >= 1.3 and unlined == "",
		"and every surface is told apart from the one behind it (%s)"
		% [unlined if unlined != "" else "worst unlined: %s at %.2f:1"
			% [flattest_pair, flattest]])

	# **A slider's track is drawn from its stylebox's vertical content margin**, so a box
	# built with zero padding -- which is right for a card and meaningless here -- bakes a
	# track zero pixels high. That shipped: the volume grabber floated on nothing, which
	# is worse than the stock control it replaced, and it was found by eye.
	var theme := _scene.get_node_or_null("HUD/Root") as Control
	var track: StyleBoxFlat = theme.theme.get_stylebox("slider", "HSlider") \
		if theme and theme.theme else null
	var height := (track.content_margin_top + track.content_margin_bottom) \
		if track else 0.0
	_check(track != null and height >= 4.0,
		"the volume track has a height to draw (%.0fpx)" % height)


## Every command tile names its verb.
func _test_command_tiles_say_what_they_do() -> void:
	_controller.select([_car])
	await _idle(3)
	var named := 0
	var tiles := 0
	for child in _grid.get_children():
		var tile := child as CommandIcon
		if tile == null or not tile.visible or tile.ability == null:
			continue
		tiles += 1
		# The tile draws the label, so what is asserted is that it *has* one to draw --
		# a verb with an empty label would render a blank strip and read as a bug.
		if not tile.ability.label().strip_edges().is_empty():
			named += 1
	_check(tiles > 0 and named == tiles,
		"every tile has a name to draw (%d of %d)" % [named, tiles])
	_controller.select([])
	await _idle(2)



## Orders you queued are drawn, not just the one being driven at.
func _test_queued_orders_are_drawn() -> void:
	await _clear_calls()
	_controller.select([_car])
	await _idle(3)
	# Three stops, queued. Shift-right-click has queued orders since phase 1 and nothing
	# ever drew them: a player who lined three up had no way to see what they had asked
	# for, or to notice they had queued one by accident.
	var stops := [CityGrid.junction(Vector2i(2, 2)), CityGrid.junction(Vector2i(3, 2)),
		CityGrid.junction(Vector2i(3, 1))]
	_car.clear_orders()
	for i in stops.size():
		_car.issue(MoveOrder.new(stops[i]), i > 0)
	await _idle(6)
	_check(_car.orders.size() == 3, "three orders are queued (%d)" % _car.orders.size())

	var shown: Array[Node3D] = []
	for node in _controller._markers:
		var marker := node as Node3D
		if marker and marker.visible:
			shown.append(marker)
	_check(shown.size() >= 3, "and a marker stands at each (%d)" % shown.size())

	# Every queued destination has a marker on it, so the display is the queue rather
	# than a coincidence of the right count.
	var unmatched := 0
	for order in _car.orders:
		var found := false
		for marker in shown:
			var offset := marker.global_position - order.destination()
			offset.y = 0.0
			if offset.length() < 1.0:
				found = true
		if not found:
			unmatched += 1
	_check(unmatched == 0,
		"each marker sits on an order the unit is actually holding (%d adrift)" % unmatched)

	# The one being driven at is told apart from the ones waiting -- by size, because the
	# marker is a duplicated scene and recolouring would need a material per copy.
	var sizes: Array[float] = []
	for marker in shown:
		sizes.append(marker.scale.x)
	sizes.sort()
	_check(sizes.size() >= 2 and sizes[0] < sizes[sizes.size() - 1] - 0.1,
		"the current order stands taller than the queue (%.2f against %.2f)"
		% [sizes[0], sizes[sizes.size() - 1]])

	_car.clear_orders()
	_controller.select([])
	await _idle(3)



## A group ordered to one point spreads instead of stacking on it.
func _test_a_group_move_spreads_out() -> void:
	await _clear_calls()
	var fleet: Array[Unit] = []
	for car in _cars:
		if car and is_instance_valid(car):
			fleet.append(car)
	if fleet.size() < 3:
		_check(false, "three vehicles to send somewhere together")
		return
	fleet = fleet.slice(0, 3)
	var junction := CityGrid.junction(Vector2i(2, 2))
	var along := CityGrid.junction(Vector2i(2, 3))
	for i in fleet.size():
		# Along the street between two junctions, so every start point is carriageway.
		# Guessed offsets put one of them off the mesh, and it was still falling when a
		# later check picked it up -- "on floor false, -3.7 m/s vertical", two tests away.
		await _place_unit(fleet[i],
			junction.lerp(along, 0.30 + 0.14 * float(i)) + Vector3.UP * 0.2)
	_controller.select(fleet)
	await _idle(4)

	# **The fault, stated.** `MoveAbility.make_order` handed every selected unit the same
	# coordinate, so ten units ordered to a point all navigated to one spot and shoved
	# each other apart. It is the first thing an RTS player notices.
	_controller.order_at_point(junction)
	await _idle(6)
	var aims: Array[Vector3] = []
	for unit in fleet:
		var order := unit.current_order()
		if order and order.has_destination():
			aims.append(order.destination())
	_check(aims.size() == 3, "all three took the order (%d)" % aims.size())
	var closest := INF
	for i in aims.size():
		for j in range(i + 1, aims.size()):
			var offset := aims[i] - aims[j]
			offset.y = 0.0
			closest = minf(closest, offset.length())
	_check(closest > 3.0,
		"and each was sent somewhere of its own (%.1fm apart at the closest)" % closest)

	# Every slot has to be somewhere the unit could actually get to, on **its own**
	# navigation layer -- a car's slot on a pavement is no use to it.
	var unreachable := 0
	for i in fleet.size():
		if not Unit.can_reach(fleet[i], aims[i], 3.0):
			unreachable += 1
	_check(unreachable == 0,
		"every one of them somewhere it can drive to (%d adrift)" % unreachable)

	# **Staged against a frontage on purpose.** In open street every offset is trivially
	# fine and this check would pass without the fallback existing at all -- which is the
	# shape of vacuity this project has shipped twice.
	var block := CityGrid.junction(Vector2i(2, 2)) + Vector3(18.0, 0.0, 18.0)
	_controller.order_at_point(block)
	await _idle(6)
	# The contract is **not** "never aim at a building" -- ordering a unit into a block is
	# a thing the player may do, and the terminal approach already stops it short. It is
	# that a *slot* never makes things worse: each unit is sent either somewhere it could
	# stand, or to the exact point that was ordered, and never to an offset of its own
	# invention that happens to be inside a wall.
	var invented := 0
	for unit in fleet:
		var order := unit.current_order()
		if order == null or not order.has_destination():
			continue
		var aim := order.destination()
		var tile := CityGrid.tile_at(aim)
		if CityGrid.standable(tile.x, tile.y):
			continue
		var drift := aim - block
		drift.y = 0.0
		if drift.length() > 0.5:
			invented += 1
	_check(invented == 0,
		"and against a frontage each falls back to the point rather than inventing an "
		+ "offset inside the wall (%d of %d)" % [invented, fleet.size()])

	# **Reachability, measured on the hard order rather than the easy one.** The first
	# version asserted this only after the junction order, where every ring offset is
	# open carriageway and the answer is trivially yes -- the sabotage agent removed both
	# validity tests and it stayed green. Against a frontage a slot is either somewhere
	# the unit can genuinely path to, or the point it was given; nothing else is allowed.
	var stranded := 0
	for unit in fleet:
		var order := unit.current_order()
		if order == null or not order.has_destination():
			continue
		var aim := order.destination()
		var drift := aim - block
		drift.y = 0.0
		if drift.length() <= 0.5:
			continue
		if not Unit.can_reach(unit, aim, 3.0):
			stranded += 1
	_check(stranded == 0,
		"and no invented slot is one it could not path to (%d stranded)" % stranded)

	for unit in fleet:
		unit.clear_orders()
	_controller.select([])
	# **Put the fleet back.** This test moves the shared patrol cars, and a car left in
	# the middle of a street is a fixture the next check inherits.
	await _park_the_shift()
	await _idle(3)



## Things that answer a click look like they will.
func _test_clickable_things_respond_to_the_pointer() -> void:
	await _clear_calls()
	_controller.select([])
	await _idle(3)
	# Roster chips, call rows, dispatch rows and the CONTROLS chip all stop the mouse and
	# act on a click, and until August 2026 every one looked exactly like the things that
	# do not. A player had to find them by trying.
	var chip := _scene.get_node_or_null(
		"HUD/Root/World/ControlsToggle") as Control
	var subjects: Array[Control] = []
	if chip:
		subjects.append(chip)
	for path in ["HUD/Root/Bar/Row/DispatchBlock/Body/Heading"]:
		var found := _scene.get_node_or_null(path) as Control
		if found:
			subjects.append(found)
	_check(subjects.size() >= 2,
		"there are clickable controls to test (%d)" % subjects.size())

	# **Counted separately.** A single tally cannot tell "never brightened" from "never
	# went back", and both sabotages printed the same 0 of 2 -- so a future failure would
	# say something broke without saying which half, which is most of the debugging the
	# check exists to save.
	var lifted := 0
	var settled := 0
	for control in subjects:
		var before := control.modulate
		control.mouse_entered.emit()
		await _idle(2)
		if control.modulate != before:
			lifted += 1
		control.mouse_exited.emit()
		await _idle(2)
		# It must go back, or the first thing the pointer touches stays lit for ever.
		if control.modulate == before:
			settled += 1
	_check(lifted == subjects.size() and settled == subjects.size(),
		"each brightens under the pointer and settles again (%d lit, %d settled, of %d)"
		% [lifted, settled, subjects.size()])

	# **Brightness, not a stylebox.** Half of these are bare containers with no panel, and
	# giving one a panel changes its size -- which in the bar makes the bar taller, which
	# covers whatever floats above it. Six incidents deep, that is not a trade worth
	# making for a hover effect, so the hover must not move anything.
	var bar_before := _command_panel.get_global_rect().size.y
	if chip:
		chip.mouse_entered.emit()
	await _idle(3)
	_check(absf(_command_panel.get_global_rect().size.y - bar_before) < 0.5,
		"and none of it moves the panels (%.0f from %.0f)"
		% [_command_panel.get_global_rect().size.y, bar_before])
	if chip:
		chip.mouse_exited.emit()
	await _idle(2)


## The black box files a record when a unit stops getting anywhere.
##
## Worth a check because it is the only instrument for the faults that matter most --
## the ones a staged test does not reproduce -- and an instrument that has quietly
## stopped recording is worse than none, since its silence reads as "no fault".
func _test_a_stuck_unit_is_written_down() -> void:
	var log := _scene.get_node_or_null("StuckLog") as StuckLog
	if log == null:
		_check(false, "the map carries a StuckLog")
		return
	_check(log.log_path != "user://stuck-log.txt",
		"the suite is not writing into the player's own log (%s)" % log.log_path)
	# No cooldown for the staging. It exists so a car wedged for a minute does not write
	# fifteen copies of the same block, and it had already swallowed this record: the same
	# car files during earlier checks, and twenty seconds had not passed.
	log.quiet_for = 0.0
	var before := log.records()

	# **Held still under orders**, rather than walled in. Three stagings of a trap were
	# tried -- four cars across the carriageway, a short order with no route to give up
	# on, a long one -- and the car got round every time, which is the game working and
	# no test at all. What is being checked here is the instrument: a unit that is trying
	# to go somewhere and not closing on it gets written down.
	await _place_unit(_car, CityGrid.junction(Vector2i(3, 2))
		+ Vector3(CityGrid.LANE_OFFSET, 0.15, 20.0))
	_car.issue(MoveOrder.new(CityGrid.junction(Vector2i(3, 1))))
	await _idle(4)
	_car.set_physics_process(false)
	# A neighbour at a **known bearing**, so the record can be asked whether it says
	# where things are and not merely how far. Placed off the car's own basis rather
	# than a world axis, because which way it ended up facing is the staging's business.
	await _place_unit(_ambulance,
		_car.global_position - _car.global_basis.x * 6.0 + Vector3.UP * 0.15)
	for i in int(log.report_after * 60.0) + 120:
		await physics_frame
		if log.records() > before:
			break
	_car.set_physics_process(true)

	_check(log.records() > before,
		"a unit that stopped getting anywhere was written down (%d records, was %d)"
		% [log.records(), before])

	# **What the record says, not just that there is one.** Three August 2026 stalls read
	# "on a road, full throttle, zero speed, nothing in front" and could not be told
	# apart -- wedged against a car, wedged against scenery, or trouble entirely of the
	# car's own making. Range without bearing cannot be staged from, and the old record
	# had no line at all for what the car was in contact with.
	var text := _last_record(log)
	_check("touching:" in text,
		"and the record says what it is in contact with")
	# **Scanned over the neighbour lines only.** The first cut searched the whole record
	# for "behind", which every record already contains in `holding behind: nothing` --
	# so the check passed with `_bearing_note` stubbed out to return nothing at all. The
	# fault reached the measurement perfectly well; the assertion was simply looking at
	# more text than the mechanism writes.
	var neighbours: Array[String] = []
	var bearings := 0
	for line in text.split("\n"):
		if not line.begins_with("    ") or not ("speed" in line):
			continue
		neighbours.append(line)
		if "°" in line or "dead ahead" in line or "behind" in line:
			bearings += 1
	_check(not neighbours.is_empty() and bearings == neighbours.size(),
		"and where its neighbours are, not just how far (%d of %d carry a bearing)"
		% [bearings, neighbours.size()])
	# The ambulance was put on the car's left, so a record that reads "right" has the
	# sign inverted -- which would send the next investigation looking the wrong way.
	var ambulance_line := ""
	for line in text.split("\n"):
		if _ambulance.name in line:
			ambulance_line = line
	_check("left" in ambulance_line,
		"with the side it is actually on (%s)" % ambulance_line.strip_edges())

	_car.clear_orders()
	await _idle(6)


## An order can only ever be given to somewhere on the map.
##
## The fault this pins came out of the black box rather than out of a staged test: a
## patrol car was found aiming at **z = 402 on a 260m map**, 270m outside the district.
## Off-map destinations do not fail loudly -- the navigation agent clamps one to the
## nearest point it can reach, which may be the far side of the city, so the unit drives
## off in the wrong direction and tours the perimeter with nothing to say it went wrong.
func _test_an_order_cannot_leave_the_map() -> void:
	var minimap := _scene.get_node_or_null(
		"HUD/Root/World/MinimapCard/Minimap") as Control
	if minimap == null:
		_check(false, "the HUD carries a minimap")
		return

	# `_gui_input` keeps delivering events to a control while a drag is in progress,
	# wherever the pointer has got to, so a position outside the card is not a
	# hypothetical.
	var beyond: Vector3 = minimap._to_world(minimap.size * 2.5)
	var short: Vector3 = minimap._to_world(-minimap.size)
	_check(absf(beyond.x) <= CityGrid.MAP_HALF and absf(beyond.z) <= CityGrid.MAP_HALF,
		"a click past the far corner of the minimap still lands on the map (%.0f, %.0f)"
		% [beyond.x, beyond.z])
	_check(absf(short.x) <= CityGrid.MAP_HALF and absf(short.z) <= CityGrid.MAP_HALF,
		"and so does one past the near corner (%.0f, %.0f)" % [short.x, short.z])

	# And the funnel itself refuses one, whatever hands it over.
	await _place(Vector3(20.0, 0.15, 0.0))
	_controller.selection = [_car] as Array[Unit]
	_car.clear_orders()
	_controller.order_at_point(Vector3(0.0, 0.0, CityGrid.MAP_HALF * 3.0))
	_check(not _car.has_orders(), "and an order off the map is refused outright")
	_controller.order_at_point(CityGrid.junction(Vector2i(2, 2)))
	_check(_car.has_orders(), "while one on it is still taken")
	_car.clear_orders()
	await _idle(4)


## Hitting something costs money, and costs it in proportion.
##
## The career only ever went up before this: calls paid, and nothing took anything back.
## Damage is the sink, and it is **money and nothing else** -- a dented car steers, brakes
## and answers exactly as it did new. Taking a unit off the board for a scrape would
## punish the same mistake twice.
func _test_a_knock_costs_money() -> void:
	var wall := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(wall)
	wall.set_physics_process(false)
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	wall.global_position = Vector3(20.0, 0.2, -20.0) + lane
	wall.rotation.y = PI * 0.5
	await _idle(10)

	# **Two different run-ups**, not two forced speeds. Setting `forward_speed` between
	# frames does nothing: `_update_movement` recomputes it from the actual velocity on
	# its first line, so both trials collided at the autopilot's own approach speed and
	# billed the identical £117.
	#
	# **And pointed at the wall, which it was not until August 2026.** Started yawed 180
	# the car spent its run-up turning round: the long trial billed 54.8m from the wall,
	# 7.4m from where it began, having scraped something mid-manoeuvre and never reached
	# the obstacle at all. Both trials therefore hit at the same 9 m/s and the ordering
	# came down to which scrape happened to be worse -- it passed on luck, and any change
	# to the steering flipped it. Facing the wall, the trials land 3.7m from it at 10 and
	# 25 m/s, which is the thing this check has always claimed to measure.
	var bills: Array[int] = []
	var speeds: Array[float] = []
	for run_up in [7.0, 60.0]:
		_car.repair_bill = 0
		await _place_unit(_car, Vector3(20.0, 0.15, -20.0 + run_up) + lane, 0.0)
		_car.avoids_vehicles = false
		_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -32.0) + lane))
		var fastest := 0.0
		for i in 600:
			await physics_frame
			fastest = maxf(fastest, absf(_car.forward_speed))
			if _car.repair_bill > 0:
				break
		bills.append(_car.repair_bill)
		speeds.append(fastest)
		_car.clear_orders()
		_car.avoids_vehicles = true
		await _idle(4)

	_check(bills[0] > 0 and bills[1] > 0,
		"driving into something bills for the damage (£%d at %.0f m/s, £%d at %.0f)"
		% [bills[0], speeds[0], bills[1], speeds[1]])
	_check(bills[1] > bills[0],
		"and a harder knock costs more than a gentle one (£%d against £%d)"
		% [bills[1], bills[0]])
	_check(_car.max_speed > 0.0 and _car.is_selectable(),
		"a damaged unit is still a working unit")
	wall.queue_free()
	_car.repair_bill = 0
	await _idle(4)


## Bringing a unit home is what settles its bill.
func _test_the_station_repairs_what_comes_home() -> void:
	_station.funds = 500
	_station.repairs_paid = 0
	_car.repair_bill = 120
	_check(_station.outstanding_repairs() >= 120,
		"the fleet's outstanding damage is visible before it is paid (£%d)"
		% _station.outstanding_repairs())

	_station.accept(_car)
	_check(_car.repair_bill == 0, "booking in puts the vehicle right (£%d left)"
		% _car.repair_bill)
	_check(_station.funds == 380, "and the purse paid for it (£%d)" % _station.funds)
	_check(_station.repairs_paid == 120,
		"the shift's repair tally follows it (£%d)" % _station.repairs_paid)

	# A career that cannot afford its repairs should feel poor, not stop working.
	_station.funds = 50
	_car.repair_bill = 200
	_station.accept(_car)
	_check(_station.funds == 0 and _car.repair_bill == 150,
		"an empty purse pays what it can and the rest stays owed (£%d left, £%d owed)"
		% [_station.funds, _car.repair_bill])
	_car.repair_bill = 0
	_station.funds = 99999
	await _idle(4)


func _test_vehicles_slow_for_corners() -> void:
	# A long approach up the avenue, then a left at the junction.
	#
	# The check is physical rather than cosmetic. Grip caps the tightest circle a car
	# can hold at v^2/max_lateral_accel, and a junction is 10m across -- so arriving at
	# the corner much above 10 m/s means the turn simply cannot be made, and the car
	# swings wide into the oncoming lane and whatever is on the far side of it.
	#
	# Before the autopilot looked ahead it arrived at 17.8 m/s, wanting a 23m circle.
	var speed := await _corner_apex()

	_check(not _car.has_orders(), "drove a route with a junction turn in it [%s]" % _car_state())
	_check(speed > 1.0, "and was actually cornering when measured (%.1f m/s)" % speed)
	var radius := speed * speed / _car.max_lateral_accel
	_check(radius < 9.0,
		"took the corner at %.1f m/s, needing a %.1fm circle inside a 10m junction"
		% [speed, radius])


## Rain, and the reason it is worth having at all: it is not a filter over the screen.
##
## The autopilot already plans corner entry from the grip available to hold the turn,
## so scaling grip changes how the whole district drives -- the player's units and the
## ambient fleet alike -- without a line anywhere asking whether it is raining. This
## measures that: the *same* corner, driven dry and then wet, and the wet one has to be
## slower. Anything less and the weather is a screen effect wearing a physics label.
func _test_rain_makes_the_road_slippery() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district knows what the weather is doing")
		return
	var kept := daylight.weather

	daylight.set_weather(Daylight.Weather.CLEAR)
	_check(is_equal_approx(_car.grip_scale, 1.0),
		"a dry road is full grip (%.2f)" % _car.grip_scale)
	var dry := await _corner_apex()

	daylight.set_weather(Daylight.Weather.RAIN)
	_check(_car.grip_scale < 1.0,
		"rain takes grip off every vehicle on the map (%.2f)" % _car.grip_scale)
	var wet := await _corner_apex()

	# Grip enters the corner planner under a square root -- the tightest circle is
	# sqrt(max_lateral_accel * grip_scale * radius) -- so 0.72 grip is about 0.85 of the
	# dry apex speed, roughly 7.5 m/s against 8.9. The margin below is well inside that
	# and well outside frame-to-frame noise.
	_check(wet < dry * 0.94,
		"and the same corner is taken slower in the wet (%.1f m/s vs %.1f dry)"
		% [wet, dry])
	# Slower, but still *possible*. A grip figure low enough to make an ordinary
	# junction turn unmakeable would send the car wide and get it re-routed the long
	# way round, which reads as a broken car rather than as weather.
	_check(wet > 0.0 and not _car.has_orders(),
		"and the turn is still makeable rather than re-routed [%s]" % _car_state())

	# The watcher, same as the headlamps: something bought mid-downpour is wet too.
	var kept_funds := _station.funds
	var kept_owned: Dictionary = _station.owned.duplicate()
	_station.funds += _station.price(&"patrol")
	_station.purchase(&"patrol")
	var bought := _station.dispatch(&"patrol")
	if bought == null:
		_check(false, "a patrol car could be bought to test the wet fitting")
	else:
		await _idle(4)
		_check((bought as Vehicle).grip_scale < 1.0,
			"a car bought in the rain drives on a wet road from its first metre (%.2f)"
			% (bought as Vehicle).grip_scale)
		bought.queue_free()
		await _idle(2)
	_station.funds = kept_funds
	_station.owned = kept_owned

	daylight.set_weather(kept)
	_check(is_equal_approx(_car.grip_scale, daylight.road_grip()),
		"and the road dries out again (%.2f)" % _car.grip_scale)


## Fog and snow, the other two skies. Each is rain's shape -- one grip number and an
## air treatment composed over the hour -- so this asserts exactly those two halves,
## plus the visual that separates snow from rain: flakes, not streaks.
func _test_fog_and_snow_are_weather_too() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	var world := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if daylight == null or world == null:
		_check(false, "the district has a sky to weather")
		return
	var air := world.environment
	daylight.set_weather(Daylight.Weather.CLEAR)
	var clear_fog := air.fog_density

	daylight.set_weather(Daylight.Weather.FOG)
	# **The switch, not just the number.** The map ships with fog_enabled off in depth
	# mode, and two earlier cuts of this treatment wrote densities into that disabled
	# path -- the checks measured the values moving and a player pressing FOG saw
	# nothing. Weather must turn the fog on, in the mode where density means density.
	_check(air.fog_enabled and air.fog_mode == Environment.FOG_MODE_EXPONENTIAL,
		"fog switches the air on, exponentially (enabled %s, mode %d)"
		% [air.fog_enabled, air.fog_mode])
	_check(air.fog_density >= 0.019,
		"and thick enough to read at RTS distance (%.4f from %.4f)"
		% [air.fog_density, clear_fog])
	_check(is_equal_approx(_car.grip_scale, 0.88),
		"and takes a little grip -- caution, not a surface (%.2f)" % _car.grip_scale)
	_check(not daylight.is_wet(), "but the road under fog is not wet")
	# What real fog does to a real city: the lights come on at noon. Street lamps and
	# every vehicle's headlamps, through the same lights_on() the hours use.
	var street := _scene.get_node_or_null("StreetLights") as Node3D
	var beams := _car.get_node_or_null("Headlights") as Node3D
	_check(street != null and street.visible,
		"fog turns the street lights on at noon")
	_check(beams != null and beams.visible,
		"and every vehicle runs its headlamps")

	daylight.set_weather(Daylight.Weather.SNOW)
	_check(is_equal_approx(_car.grip_scale, 0.62),
		"snow grips below rain (%.2f)" % _car.grip_scale)
	_check(daylight.is_wet(), "and counts as water on the road")
	var flakes := daylight.get_node_or_null("Snow") as GPUParticles3D
	var streaks := daylight.get_node_or_null("Rain") as GPUParticles3D
	_check(flakes != null and flakes.visible and flakes.emitting,
		"snow falls as its own particles")
	_check(streaks == null or not streaks.visible,
		"and the rain stays off while it does")

	daylight.set_weather(Daylight.Weather.CLEAR)
	_check(is_equal_approx(air.fog_density, clear_fog)
			and not air.fog_enabled
			and is_equal_approx(_car.grip_scale, 1.0),
		"and the sky clears back to the hour's own air, switch and all (%.4f)"
		% air.fog_density)
	_check(street != null and not street.visible
			and beams != null and not beams.visible,
		"with the lights back out -- noon is noon again")


func _test_vehicles_keep_out_of_the_buildings() -> void:
	# The whole point of baking the vehicle mesh from road surfaces alone. Ordered into
	# the middle of a block -- 30m of building, no navigation mesh anywhere near it --
	# the car must come to rest short of it rather than driving at a wall or refusing
	# the order.
	#
	# **It used to have to stop on the road, and that stopped being right.** Measured
	# along this block: the building is the middle 0-9m, the pavement ring is 10-14m,
	# and the carriageway starts at 15m. Once a car could climb a kerb on an order sent
	# somewhere off-road -- which is a verb the player asked for -- a car aimed at the
	# block centre correctly mounts the pavement and stops at the building line. It now
	# comes to rest around 12.8m, which the old bar read as failure and which is exactly
	# what should happen.
	#
	# So the assertion moved to the guarantee that actually matters and has not changed:
	# it never gets *inside*. `CityGrid.standable` is the line -- true on road and
	# pavement, false on a building footprint -- and it is the same test that keeps
	# fires and casualties out of people's houses.
	await _place(Vector3(20.0, 0.15, 0.0))
	_car.issue(MoveOrder.new(Vector3.ZERO))
	await _await_arrival(1800)
	var here := _car.global_position
	var tile := CityGrid.tile_at(here)
	_check(CityGrid.standable(tile.x, tile.y),
		"stopped somewhere it may stand at (%.1f, %.1f), not inside the block"
		% [here.x, here.z])
	_check(_flat_distance(here, Vector3.ZERO) > 10.0,
		"which is %.1fm out, clear of the building it was aimed into"
		% _flat_distance(here, Vector3.ZERO))


# --- Selection and orders ----------------------------------------------------
