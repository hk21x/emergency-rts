extends "res://Game/Tests/Interface.gd"

## Calls -- 26 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## Every symbol key the game uses must resolve to a texture from the icon pack --
## otherwise a tile quietly falls back to the plainer drawn primitive and nobody
## notices until it looks wrong in a screenshot.
func _test_the_interface_wears_the_icon_pack() -> void:
	var wanted: Array[StringName] = [&"arrow", &"halt", &"cross", &"droplet",
		&"stretcher", &"door_in", &"door_out", &"cone", &"station", &"flame",
		&"car", &"ambulance", &"person", &"beacon", &"horn", &"unknown"]
	var missing := PackedStringArray()
	for key in wanted:
		if Glyph._texture(key) == null:
			missing.append(key)
	_check(missing.is_empty(),
		"every glyph key has its icon from the pack%s"
		% ("" if missing.is_empty() else " -- missing: " + ", ".join(missing)))


func _test_streets_have_names() -> void:
	# Six road bands per axis are the district's avenues and streets, so every point
	# in it has an address. The corners of the outer ring pin the two ends of both
	# tables; the mid-block point pins "nearest crossroads", not "containing".
	var north_west := CityGrid.place_name(CityGrid.junction(Vector2i(0, 0)))
	_check(north_west == "1st Ave & Elm St",
		"the north-west junction is 1st & Elm ('%s')" % north_west)
	var south_east := CityGrid.place_name(
		CityGrid.junction(Vector2i(CityGrid.BANDS - 1, CityGrid.BANDS - 1)))
	_check(south_east == "6th Ave & Birch St",
		"and the south-east one is 6th & Birch ('%s')" % south_east)
	# Partway down a block still has to answer, and answer with the nearest crossroads.
	var near := CityGrid.place_name(Vector3(18.0, 0.0, -55.0))
	_check(near == "4th Ave & Oak St",
		"a point mid-block takes the nearest junction ('%s')" % near)


func _test_an_incident_opens_a_call() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.5)
	await _idle(4)

	var open := _board.open_calls()
	_check(open.size() == 1, "one fire opens one call (%d)" % open.size())
	if open.is_empty():
		return
	_check(open[0].kind == Call.Kind.FIRE,
		"and it is a fire call ('%s')" % open[0].title())
	_check(open[0].place == CityGrid.place_name(fire.global_position),
		"addressed to the nearest junction ('%s')" % open[0].place)
	_check(open[0].status == Call.Status.WAITING,
		"and starts unattended (%d)" % open[0].status)


## The reason calls exist. A fire left alone becomes eight bodies, and eight rows on the
## board would be eight jobs when it is plainly still one.
func _test_a_spreading_fire_stays_one_call() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.95)
	await _idle(4)
	_check(_board.open_calls().size() == 1, "starting from one call")

	# Let it throw off children of its own rather than placing them by hand, so this
	# measures the real spread and not a staged one. Fire.spread_interval is 8s, so a
	# second body takes about 480 physics frames to appear.
	var spread := 0
	for i in 900:
		await physics_frame
		spread = get_nodes_in_group(Fire.FIRE_GROUP).size()
		if spread >= 2:
			break
	await _idle(4)

	_check(spread >= 2, "the fire spread to %d bodies" % spread)
	var open := _board.open_calls()
	_check(open.size() == 1,
		"and they are still one call (%d calls for %d fires)" % [open.size(), spread])
	if not open.is_empty():
		_check(open[0].incidents.size() == spread,
			"which holds all %d of them (%d)" % [spread, open[0].incidents.size()])


func _test_a_call_upgrades_when_the_scene_changes() -> void:
	await _clear_calls()
	var spot := Vector3(20.0, 0.0, 20.0)
	_spawn_fire(spot, 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.size() != 1:
		_check(false, "a fire call to upgrade (%d)" % open.size())
		return
	_check(open[0].kind == Call.Kind.FIRE, "a fire, on its own")

	# Someone hurt at the same scene makes it the job that needs two services, and the
	# call has to say so without anyone telling it.
	_spawn_casualty(spot + Vector3(3.0, 0.0, 0.0))
	await _idle(4)
	_check(open[0].kind == Call.Kind.RESCUE,
		"a casualty at the same scene upgrades it to a rescue ('%s')" % open[0].title())
	_check(_board.open_calls().size() == 1,
		"and it is still one call (%d)" % _board.open_calls().size())


## The board reports a scene in words and draws the number as a bar. It used to
## print one percentage per incident, so a fire that had spread six times read as
## six numbers in a row.
func _test_the_board_draws_progress_as_a_bar() -> void:
	await _clear_calls()
	var spot := Vector3(20.0, 0.0, -20.0)
	# **A hose fire**, so the capability gate is real: an officer carries an extinguisher
	# and can fight a bin, which is why the first version of this check passed while the
	# officer was busily extinguishing.
	var fire := _spawn_fire(spot, 0.6)
	await _idle(8)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to read")
		return
	var call := open[0]
	_check(not ("%" in call.describe()),
		"the board says what a scene is doing in words, not percentages ('%s')"
		% call.describe())
	_check(absf(call.progress() - 0.4) < 0.12,
		"a fire well alight reads as barely started (%.2f done)" % call.progress())

	var rows := _visible_call_rows()
	if rows.is_empty():
		_check(false, "a row on screen to read it off")
		return
	# **Found, not counted to.** This read `get_child(3)` until the UI kit's status dot
	# was added at the head of the row and shifted every column by one. A positional
	# index into a layout is a check that breaks the next time the layout gains a
	# column -- which is a fact about the *test*, not about the game.
	var bar: ProgressStrip = null
	for cell in rows[0].get_child(0).get_children():
		if cell is ProgressStrip:
			bar = cell as ProgressStrip
	if bar == null:
		_check(false, "the row carries a progress bar")
		return
	_check(absf(bar.value - call.progress()) < 0.02,
		"and the row draws that as a bar (%.2f)" % bar.value)

	fire.douse(0.45)
	await _idle(6)
	_check(bar.value > 0.7, "knocking the fire down fills it (%.2f)" % bar.value)

	# Two more fires at the same scene: one line that counts them, not three
	# numbers side by side.
	_spawn_fire(spot + Vector3(3.5, 0.0, 0.0), 0.5)
	_spawn_fire(spot + Vector3(-3.5, 0.0, 0.0), 0.5)
	await _idle(8)
	_check(call.describe() == "3 fires",
		"several incidents are counted, not listed ('%s')" % call.describe())
	await _clear_calls()


func _test_a_call_notices_a_unit_arriving() -> void:
	await _clear_calls()
	# Well away from ROAD, where the rest of the suite parks the patrol car -- 47m,
	# against the 15m that counts as being at a scene. Put the call next to it instead
	# and it opens already attended, which is a check that proves nothing.
	var spot := Vector3(-20.0, 0.0, -20.0)
	await _place(ROAD)
	_spawn_fire(spot, 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to attend")
		return

	_check(_board.waiting_count() == 1,
		"the board counts it unattended (%d)" % _board.waiting_count())
	await _place(spot + Vector3(0.0, 0.0, 6.0))
	await _idle(4)
	_check(open[0].status == Call.Status.ON_SCENE,
		"a patrol car pulling up marks it attended (%d)" % open[0].status)
	_check(_board.waiting_count() == 0,
		"and it stops counting as waiting (%d)" % _board.waiting_count())

	# Ambient traffic carries no service, so a taxi driving past is not a response.
	await _place(ROAD)
	await _idle(4)
	_check(open[0].status == Call.Status.WAITING,
		"driving away leaves it unattended again (%d)" % open[0].status)


## Triage: the board says who is dying, not just how many are hurt.
##
## **Asserted on the tiers moving with the state that decides them**, not on the words. A
## severity that is merely *present* is worth nothing -- the failure that matters is a
## casualty who is running out of time reading the same as one who is fine, which is what
## "4 casualties" said for the whole life of the bus RTC.
func _test_the_board_triages_casualties() -> void:
	await _clear_calls()
	var spot := ROAD + Vector3(0.0, 0.0, 18.0)
	var fine := _spawn_casualty(spot)
	var dying := _spawn_casualty(spot + Vector3(2.0, 0.0, 0.0))
	await _idle(6)

	_check(fine.severity() == Casualty.Severity.SERIOUS,
		"a fresh casualty is serious (%d)" % fine.severity())
	dying.health = 0.2
	_check(dying.severity() == Casualty.Severity.CRITICAL,
		"and one running out of time is critical (%d)" % dying.severity())

	# The tier a paramedic cannot resolve, whatever the health bar says.
	var held := _spawn_casualty(spot + Vector3(4.0, 0.0, 0.0))
	held.needs_doctor = true
	held.health = 0.9
	_check(held.severity() == Casualty.Severity.CRITICAL,
		"one needing a doctor is critical however healthy (%.2f, %d)"
		% [held.health, held.severity()])

	# Stabilised drops off the list even though the health never moved.
	fine.treat(1.0)
	await _idle(3)
	_check(fine.severity() == Casualty.Severity.STABLE,
		"and a stabilised one stops being urgent (%d)" % fine.severity())

	await _idle(6)
	var board_says := ""
	for call_row in _board.open_calls():
		if call_row.describe().contains("casualt"):
			board_says = call_row.describe()
	# **The number, not the word.** `contains("critical")` was the first cut and sabotage
	# showed it is carried by a single casualty: dropping the `needs_doctor` term took the
	# count from 2 to 1 and the assertion never noticed, because one critical is enough to
	# put the word on the row. A triage line that under-counts by all but one would have
	# shipped green. Two of the three staged casualties are critical here -- the dying one
	# and the one waiting on a doctor -- so the row has to say so.
	_check(board_says.contains("2 critical"),
		"the call row names how many are critical ('%s')" % board_says)

	for node in get_nodes_in_group(Incident.GROUP):
		node.free()
	await _clear_calls()


func _test_a_call_closes_when_its_incidents_do() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to close")
		return
	var closed: Array = []
	open[0].closed.connect(func(_call: Call, ok: bool) -> void: closed.append(ok))

	fire.douse(2.0)
	await _idle(4)
	_check(closed.size() == 1 and closed[0] == true,
		"putting the fire out closes its call successfully (%s)" % str(closed))
	_check(_board.open_calls().is_empty(),
		"and it leaves the board (%d still open)" % _board.open_calls().size())


## Getting three of four casualties out is not a job well done, so any loss fails the
## whole call rather than the rest of it quietly succeeding.
func _test_a_lost_casualty_fails_its_call() -> void:
	await _clear_calls()
	var casualty := _spawn_casualty(Vector3(-20.0, 0.0, 20.0))
	casualty.decline_per_second = 4.0
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to fail")
		return
	var call := open[0]
	_check(call.kind == Call.Kind.MEDICAL, "a medical call ('%s')" % call.title())

	for i in 200:
		await physics_frame
		if not call.is_open():
			break
	_check(call.status == Call.Status.FAILED,
		"losing the casualty fails the call (%d)" % call.status)
	_check(_board.open_calls().is_empty(),
		"and closes it (%d still open)" % _board.open_calls().size())


func _test_clicking_a_call_moves_the_camera() -> void:
	await _clear_calls()
	var spot := Vector3(-20.0, 0.0, -20.0)
	_spawn_fire(spot, 0.4)
	await _idle(6)

	_camera.stop_following()
	_camera.focus = Vector3(40.0, 0.0, 40.0)
	await _idle(6)
	var rows := _visible_call_rows()
	if rows.is_empty():
		_check(false, "a call row to click (%d open)" % _board.open_calls().size())
		return

	await _click(MOUSE_BUTTON_LEFT, rows[0].get_global_rect().get_center())
	_check(_flat_distance(_camera.focus, spot) < 2.0,
		"clicking the row put the camera on the call (%.1fm away)"
			% _flat_distance(_camera.focus, spot))
	await _clear_calls()


## Dispatch traffic. The district is 260m and the camera sees about a fifth of it, so
## the log's job is telling the player about the four fifths they cannot see.
##
## The interesting half of this check is the *repeat suppression*. The board emits
## `call_changed` on every tick a call's state moves, so a crew standing at a scene
## would announce its arrival for as long as it stood there -- once a frame, until the
## log was nothing but one unit saying it had arrived. A readout nobody can read is
## worse than no readout: it costs the same corner of the screen and teaches the player
## to ignore it.
func _test_the_radio_reports_what_happens() -> void:
	await _clear_calls()
	var radio := _scene.get_node_or_null("HUD/Root/World/RadioLog") as RadioLog
	_check(radio != null, "the interface carries a radio log")
	if radio == null:
		return
	for line in radio.get_children():
		line.free()

	# A job opening is the first thing worth hearing.
	var fire := _spawn_fire(Vector3(28.0, 0.0, 28.0), 0.4)
	await _idle(6)
	_check(radio.get_child_count() >= 1,
		"a call opening puts a line on it (%d)" % radio.get_child_count())
	# Across the whole log rather than off the end of it: if a unit happens to be
	# standing within the on-scene radius when the call opens -- which is entirely
	# possible, since nothing moves the fleet away between tests -- the call opens and
	# goes ON SCENE in the same breath, and the newest line is the arrival.
	var opened := _radio_text(radio, true)
	_check("CONTROL" in opened, "which says who is speaking ('%s')" % opened)

	# A crew arriving says so exactly once, however long it stands there.
	#
	# Counted by **content**, not by how many lines are on the log. Comparing the child
	# count before and after was the first attempt and it was vacuous: say() trims to
	# MAX_LINES, so the number it measured was pinned at 4 by the very thing under test,
	# and a log reading "ON SCENE | ON SCENE | ON SCENE | ON SCENE" passed it happily.
	# A flood and silence are indistinguishable once the log is full; only the text
	# tells them apart.
	await _place_unit(_officer, Vector3(30.0, 0.05, 28.0))
	await _idle(60)
	await _idle(120)
	# Counted off the same reader the other log checks use, rather than reaching for a
	# Label directly -- a log line is a framed row with the words inside it now.
	var arrivals := 0
	for line in _radio_text(radio, true).split(" | "):
		if "ON SCENE" in line:
			arrivals += 1
	_check(arrivals == 1,
		"a crew standing on scene announces itself once, not once a frame (%d of %d "
		% [arrivals, radio.get_child_count()]
		+ "lines say it: %s)" % _radio_text(radio, true))

	# The outcome, per incident rather than per call.
	var before := radio.get_child_count()
	fire.douse(2.0)
	await _idle(6)
	_check(radio.get_child_count() > before,
		"putting the fire out is worth a line too (%d -> %d)"
		% [before, radio.get_child_count()])
	_check("FIRE" in _radio_text(radio), "naming the service ('%s')" % _radio_text(radio))

	# And it does not grow without bound.
	for i in 12:
		radio.say("filler %d" % i)
	_check(radio.get_child_count() <= RadioLog.MAX_LINES,
		"the log keeps only the last %d lines (%d)"
		% [RadioLog.MAX_LINES, radio.get_child_count()])

	_officer.clear_orders()
	await _clear_incidents()
	await _clear_calls()


## The destination reticle: the other half of the in-world pass.
##
## Asserted on the mesh the controller swapped in and on the queue still being drawn from
## it, because the marker is *duplicated* per queued order -- a shape built in the wrong
## place would give the first order a reticle and every queued one a torus.
func _test_the_move_marker_is_a_reticle() -> void:
	var marker := _scene.get_node_or_null("MoveMarker") as MeshInstance3D
	if marker == null:
		_check(false, "the map carries a move marker")
		return
	_check(marker.mesh is ArrayMesh,
		"the move marker is the reticle built at load (%s)"
		% (marker.mesh.get_class() if marker.mesh else "none"))
	var span: Vector3 = marker.mesh.get_aabb().size if marker.mesh else Vector3.ZERO
	_check(span.x > 1.0 and span.y < 0.01,
		"flat on the ground and about a metre across (%.1f x %.2f)" % [span.x, span.y])
	_check(_faces_down(marker.mesh as ArrayMesh) == 0,
		"and wound face-up (%d of %d triangles down)"
		% [_faces_down(marker.mesh as ArrayMesh), _triangles(marker.mesh as ArrayMesh)])

	# Queue two orders and confirm the copies carry the same shape.
	_controller.select([_car])
	await _idle(3)
	# Both destinations measured off where the car actually is. `ROAD` is a fixture
	# position the car is often already standing on, and an order that is satisfied on
	# the frame it is issued leaves one marker rather than two -- which is how this check
	# failed twice before the staging was the problem rather than the code.
	var from := _car.global_position
	_car.issue(MoveOrder.new(from + Vector3(0.0, 0.0, -30.0)))
	# `queue` true, or the second order replaces the first.
	_car.issue(MoveOrder.new(from + Vector3(0.0, 0.0, -60.0)), true)
	await _idle(6)
	_check(_car.orders.size() == 2,
		"two orders are queued to draw (%d)" % _car.orders.size())
	var drawn := 0
	var wrong := 0
	for node in _controller._markers:
		if not node.visible:
			continue
		drawn += 1
		if (node as MeshInstance3D).mesh != marker.mesh:
			wrong += 1
	_check(drawn >= 2 and wrong == 0,
		"and a queued order's copy carries it too (%d drawn, %d wrong)" % [drawn, wrong])
	_car.clear_orders()
	_controller.clear_selection()
	await _idle(3)


func _test_the_map_zoom_buttons_work() -> void:
	var controls := _scene.get_node_or_null(
		"HUD/Root/World/MapControls") as MapControls
	if controls == null or controls.get_child_count() < 2:
		_check(false, "the minimap carries its zoom buttons")
		return
	_check(controls.camera != null, "the zoom buttons are wired to the camera")
	if controls.camera == null:
		return
	# Away from either stop, or a clamp hides the result.
	controls.camera._target_distance = (controls.camera.min_distance
		+ controls.camera.max_distance) * 0.5
	var start: float = controls.camera._target_distance
	(controls.get_child(0) as Button).pressed.emit()
	var pulled_in: float = controls.camera._target_distance
	(controls.get_child(1) as Button).pressed.emit()
	(controls.get_child(1) as Button).pressed.emit()
	var pushed_out: float = controls.camera._target_distance
	_check(pulled_in < start and pushed_out > pulled_in,
		"+ pulls the view in and - pushes it out (%.0f -> %.0f -> %.0f)"
		% [start, pulled_in, pushed_out])


## The top-right strip: the fleet count it advertises, and the only on-screen way into
## the pause card.
##
## **The count is asserted on a change, not on a match.** Reading the label once and
## comparing it to the station's own total passes just as happily when the strip is a
## dead label that happened to be built with the right number in it -- which is the exact
## shape of the two features this suite has caught doing nothing. Buying a unit and
## watching the label follow is the cheapest thing that cannot pass while disconnected.
##
## The button is asserted on the *tree freezing*, for the same reason: a button that
## opens a card but leaves the district running is not a pause button.
func _test_the_score_strip_reads_and_pauses() -> void:
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	if strip == null or _station == null:
		_check(false, "the HUD carries a score strip")
		return

	var kept_funds := _station.funds
	var before := _strip_units(strip)
	_station.funds = maxi(_station.funds, 10000)
	var bought := _station.purchase(&"patrol")
	await _idle(2)
	var after := _strip_units(strip)
	_check(bought and after == before + 1,
		"buying a unit moves the strip's UNITS count (%d -> %d)" % [before, after])

	# Back to the books the rest of the suite was handed: this runs mid-session and
	# several later checks count the fleet and the purse.
	_station.owned[&"patrol"] = int(_station.owned.get(&"patrol", 0)) - 1
	_station.funds = kept_funds
	_station.roster_changed.emit()
	await _idle(2)

	var buttons: Array[Button] = []
	for node in strip.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	if buttons.size() < 2:
		_check(false, "the strip carries its pause and settings buttons")
		return

	buttons[0].pressed.emit()
	await _idle(2)
	var froze: bool = _menu.visible and _menu.screen == GameMenu.Screen.PAUSE and paused
	_check(froze, "its pause button opens the pause card and freezes the district")
	_menu.resume()
	await _idle(2)
	# **The transition, not the reading.** `not paused` on its own is trivially true when
	# the button never paused anything -- a sabotage that gutted `_open()` left this line
	# green while the check above went red. Carrying `froze` in makes it say what it means:
	# the district was frozen by that button and thawed again.
	_check(froze and not paused, "and resuming thaws it again")


func _test_the_minimap_commands_camera_and_shift() -> void:
	var minimap := _scene.get_node_or_null(
		"HUD/Root/World/MinimapCard/Minimap") as Minimap
	if minimap == null:
		_check(false, "the HUD carries a minimap")
		return

	_camera.stop_following()
	_camera.focus = Vector3.ZERO
	await _idle(4)
	var spot := Vector3(60.0, 0.0, 60.0)
	var pixel: Vector2 = minimap.get_global_rect().position + minimap._to_map(spot)
	await _click(MOUSE_BUTTON_LEFT, pixel)
	_check(_flat_distance(_camera.focus, spot) < 6.0,
		"left-clicking the map looked there (%.1fm off)"
		% _flat_distance(_camera.focus, spot))

	# The view quad: centred on the focus, wider at its far edge than its near one --
	# a tilted camera's footprint is a trapezoid -- and *capped*: the honest frustum
	# reaches the best part of 100m towards the skyline, which turned the marker into
	# half the map.
	await _idle(4)
	var centre := _camera.ground_point(Vector2(0.5, 0.5))
	_check(_flat_distance(centre, _camera.focus) < 8.0,
		"the view footprint centres on the camera focus (%.1fm off)"
		% _flat_distance(centre, _camera.focus))
	var footprint := minimap.view_footprint()
	if footprint.size() != 4:
		_check(false, "the minimap shapes a four-corner view footprint")
		return
	var near_width := footprint[0].distance_to(footprint[1])
	var far_width := footprint[3].distance_to(footprint[2])
	_check(far_width > near_width and near_width > 0.0,
		"and is wider at its far edge (%.0fm far, %.0fm near)"
		% [far_width, near_width])
	var eye := _camera.global_position
	var eye_ground := Vector3(eye.x, 0.0, eye.z)
	var reach: float = (eye - _camera.focus).length() * Minimap.VIEW_REACH
	var longest := 0.0
	for point in footprint:
		longest = maxf(longest, (point - eye_ground).length())
	_check(longest <= reach + 0.5,
		"and its far sweep is capped, so the marker stays a marker (%.0fm of %.0fm)"
		% [longest, reach])

	# Right-click: the same meaning it has out in the world -- an order.
	await _place(ROAD)
	_controller.select([_car])
	await _idle(3)
	var order_spot := Vector3(20.0, 0.0, -45.0)
	await _click(MOUSE_BUTTON_RIGHT,
		minimap.get_global_rect().position + minimap._to_map(order_spot))
	var destination := _car.current_order().destination() \
		if _car.current_order() else Vector3.INF
	_check(_car.has_orders()
			and _flat_distance(destination, order_spot) < 6.0,
		"right-clicking the map sent the selection there (%.1fm off)"
		% (_flat_distance(destination, order_spot) if _car.has_orders() else -1.0))
	_car.clear_orders()
	_controller.clear_selection()


func _test_person_walks() -> void:
	# Off the junction and onto the pavement of the centre block: a route that only
	# exists on the person navigation mesh, since it ends where no car can go.
	await _place_unit(_officer, Vector3(18.0, 0.1, 24.0))
	var target := Vector3(12.0, 0.0, 12.0)
	_officer.issue(MoveOrder.new(target))
	var arrived := await _await_orders_done(_officer, 1800)
	_check(arrived, "the officer walked to the target")
	_check(_flat_distance(_officer.global_position, target) < _officer.arrive_radius + 0.8,
		"stopped %.2fm away" % _flat_distance(_officer.global_position, target))
	_check(absf(_officer.global_position.y) < 0.2,
		"stayed on the deck (y=%.2f)" % _officer.global_position.y)


## People collide with the player's vehicles; no vehicle can see a person at all. So
## nothing gets out of anybody's way, and a walker who meets a parked car used to stand
## against it indefinitely -- measured at 1,716 stationary frames out of 1,747, never
## arriving. They have to find their own way round.
func _test_a_person_gets_round_a_parked_car() -> void:
	var here := CityGrid.junction(Vector2i(1, 3)) + Vector3(0.0, 0.0, 18.0)
	# **A player vehicle, not a traffic one.** The first version of this parked a Sedan
	# from Game/Traffic, and an officer masks layer 1 while ambient traffic sits on 64 --
	# so the officer walked clean through it and the check passed with the whole sidestep
	# deleted. A zero reading and an obstacle that was never there look identical from
	# the outside, which is why the contact is asserted below rather than assumed.
	#
	# Its own car rather than one of the fixture's, because this one gets freed. Borrowing
	# `_cars[1]` and parking it back on the forecourt afterwards was tried and it took a
	# slot a later dispatch check wanted, landing two paramedics on the same spot.
	var parked := (load("res://Game/Vehicles/PoliceCar.tscn") as PackedScene) \
		.instantiate() as Vehicle
	_scene.add_child(parked)
	parked.set_physics_process(false)
	parked.global_position = here
	parked.rotation.y = PI * 0.5
	await _idle(6)

	# Squarely between the officer and where they are sent, on a street wide enough that
	# there is a way round: this asks whether they take it, not whether one exists.
	await _place_unit(_officer, here + Vector3(0.0, 0.0, 7.0))
	var target := here - Vector3(0.0, 0.0, 7.0)
	_officer.issue(MoveOrder.new(target))

	var stopped_dead := 0
	var arrived := false
	for i in 1800:
		await physics_frame
		if _flat_distance(_officer.global_position, parked.global_position) < 3.0 \
				and Vector2(_officer.velocity.x, _officer.velocity.z).length() < 0.05:
			stopped_dead += 1
		if not _officer.has_orders():
			arrived = true
			break
	_check(stopped_dead > 0,
		"the officer really did meet the parked car (%d frames held up by it)"
		% stopped_dead)
	_check(arrived, "the officer got round a car parked in the way [%.1fm short]"
		% _flat_distance(_officer.global_position, target))
	_check(stopped_dead < 120,
		"without standing against it (%d frames stationary at the panel)" % stopped_dead)

	# Take the car away again. Left standing it is a solid layer-1 obstacle in the middle
	# of a street two tests before the officer is sent 9m up that same street -- which
	# timed out with the walk clip still playing, a failure that read as an animation
	# fault and was a piece of scenery this test forgot to tidy away.
	parked.queue_free()
	_officer.clear_orders()
	await _idle(6)


## The crowd gets the same sidestep, but not the same freedom. An officer may cut across
## a road to get past something; a passer-by doing that is walking down the middle of the
## carriageway, which is the one thing the district's pedestrians never do.
func _test_the_crowd_sidesteps_onto_pavement_only() -> void:
	# One of its own, rather than one off the map: by the time the person checks run the
	# ambient crowd has been exercised and cleared away, and a parked civilian would
	# swallow the clicks the later checks depend on anyway.
	var civilian := (load("res://Game/Civilians/Male_Jacket.tscn") as PackedScene) \
		.instantiate() as Civilian
	_scene.add_child(civilian)
	civilian.set_physics_process(false)
	await _idle(2)
	# The middle of a junction box: on the vehicle mesh, on nobody's pavement.
	var road := CityGrid.junction(Vector2i(2, 2))
	var pavement := CityGrid.tile_centre(23, 25)
	_check(not civilian._may_step_to(road) and civilian._may_step_to(pavement),
		"a civilian will step onto a pavement tile but not into the road")
	_check(_officer._may_step_to(road) and _officer._may_step_to(pavement),
		"an officer under orders may step either way")
	civilian.queue_free()
	await _idle(2)


func _test_person_animates() -> void:
	var player: AnimationPlayer = _officer.get_node("Character/AnimationPlayer")
	await _wait(30)
	_check(player.current_animation == "Idle",
		"idles when standing still (playing '%s')" % player.current_animation)

	_officer.issue(MoveOrder.new(_officer.global_position + Vector3(0.0, 0.0, 9.0)))
	await _wait(45)
	var moving := player.current_animation
	_check(moving == "Walk" or moving == "Jog_Fwd",
		"plays a locomotion clip while travelling (playing '%s')" % moving)
	await _await_orders_done(_officer, 1200)
	await _wait(45)
	_check(player.current_animation == "Idle",
		"returns to idle on arrival (playing '%s')" % player.current_animation)


func _test_person_faces_travel() -> void:
	# The character mesh faces +Z while Godot's forward is -Z, so Person.tscn yaws the
	# visual 180. Get that wrong and the officer moonwalks: steering is correct and
	# every other check still passes, because nothing in code reads the model's
	# orientation. Only an explicit check catches it.
	await _place_unit(_officer, Vector3(20.0, 0.1, 20.0))
	_officer.issue(MoveOrder.new(Vector3(20.0, 0.0, 8.0)))
	await _wait(60)

	var travel := Vector3(_officer.velocity.x, 0.0, _officer.velocity.z)
	if travel.length() < 0.3:
		_check(false, "the officer is walking when facing is sampled (%.2f m/s)"
			% travel.length())
		_officer.clear_orders()
		return

	# The mesh's face points along the visual node's +Z, so that is what must line up
	# with the direction of travel.
	var character: Node3D = _officer.get_node("Character")
	var alignment := character.global_basis.z.normalized().dot(travel.normalized())
	_check(alignment > 0.8,
		"the officer faces the way they walk (alignment %.2f, -1 means moonwalking)"
		% alignment)
	_officer.clear_orders()
	await _wait(20)


func _test_person_navmesh_is_tighter() -> void:
	# Query the two layers directly rather than inferring the difference from where
	# units happen to stop. The two meshes are baked from different geometry, not just
	# at different radii.
	#
	# So a target on the pavement outside the centre block is reachable on one layer and
	# roughly a road's half-width short on the other.
	var map := _officer.get_world_3d().navigation_map
	var from := Vector3(0.0, 0.0, -20.0)
	var target := Vector3(0.0, 0.0, -12.5)

	var vehicle_path := NavigationServer3D.map_get_path(map, from, target, true, 1)
	var person_path := NavigationServer3D.map_get_path(map, from, target, true, 2)
	if vehicle_path.is_empty() or person_path.is_empty():
		_check(false, "both navigation layers return a path (vehicle=%d person=%d)"
			% [vehicle_path.size(), person_path.size()])
		return

	var vehicle_gap := _flat_distance(vehicle_path[vehicle_path.size() - 1], target)
	var person_gap := _flat_distance(person_path[person_path.size() - 1], target)
	_check(person_gap < vehicle_gap - 2.0,
		"person layer reaches %.2fm from the pavement, vehicle layer %.2fm"
		% [person_gap, vehicle_gap])


func _test_clicking_a_person_selects() -> void:
	# People are on collision layer 4 and are a much smaller target than a car, so
	# picking them deserves its own check rather than being assumed from the cars.
	_controller.clear_selection()
	await _place_unit(_officer, Vector3(20.0, 0.1, 20.0))
	_camera.focus = Vector3(20.0, 0.0, 20.0)
	_camera._target_distance = 18.0
	await _idle(40)

	var aim := _officer.global_position + Vector3.UP * 1.0
	var hit := _controller._raycast(_screen_of(aim))
	_check(hit.get("collider") == _officer,
		"a ray at the officer hits them (hit '%s')" % hit.get("collider"))

	await _click(MOUSE_BUTTON_LEFT, _screen_of(aim))
	_check(_controller.primary() == _officer, "left-clicking an officer selects them")

	var board := _find_ability(_officer, &"board")
	_check(board != null, "an officer offers a Board ability for the command bar")


func _test_boarding() -> void:
	# Right-clicking a car with an officer selected should mean "get in", not "walk
	# to that spot": BoardAbility scores 10 against MoveAbility's 0.
	await _place_unit(_car, Vector3(20.0, 0.15, 4.0))
	await _place_unit(_officer, Vector3(20.0, 0.1, 12.0))
	_car.crew.clear()

	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	var ability := _officer.resolve(target)
	_check(ability != null and ability.id() == &"board",
		"right-clicking a car resolves to Board (got '%s')"
		% ("none" if ability == null else ability.id()))

	_officer.issue(ability.make_order(_officer, target))
	var done := await _await_orders_done(_officer, 1800)
	_check(done, "the officer finished the boarding order")
	_check(_officer.is_aboard, "the officer is aboard")
	_check(_car.crew.size() == 1, "the car reports 1 crew (%d)" % _car.crew.size())
	_check(not _officer.visible, "an aboard officer is hidden")
	_check(not _officer.is_selectable(), "an aboard officer cannot be selected")


func _test_unload() -> void:
	if not _officer.is_aboard:
		_check(false, "officer was aboard before unloading")
		return
	var unload := _find_ability(_car, &"unload")
	if unload == null:
		_check(false, "the car offers an Unload ability")
		return

	_controller.select([_car])
	_controller.activate(unload)
	await _wait(20)
	_check(not _officer.is_aboard, "the officer is back on foot")
	_check(_car.crew.is_empty(), "the car reports no crew")
	_check(_officer.visible, "the officer is visible again")
	_check(_officer.global_position.distance_to(_car.global_position) < 8.0,
		"dismounted beside the car (%.1fm away)"
		% _officer.global_position.distance_to(_car.global_position))
	_check(absf(_officer.global_position.y) < 1.0,
		"dismounted onto the deck (y=%.2f)" % _officer.global_position.y)


func _test_seats_are_limited() -> void:
	# Fill every seat, then check the ability declines rather than overfilling.
	_car.crew.clear()
	for i in _car.seats:
		_car.crew.append(_officer)
	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	_check(not _car.has_free_seat(), "a full car reports no free seat")
	var ability := _officer.resolve(target)
	_check(ability != null and ability.id() == &"move",
		"a full car falls back to Move (got '%s')"
		% ("none" if ability == null else ability.id()))
	_car.crew.clear()


# --- Lightbar and doors ------------------------------------------------------
