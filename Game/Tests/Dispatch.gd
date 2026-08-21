extends "res://Game/Tests/Roles.gd"

## Dispatch -- 16 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## The roster is finite, and the units already parked on the forecourt are part of it.
## Miss that and the station hands out four more patrol cars than exist.
## The career: money in, fleet out. Run against a pocket career on the side so the
## suite's own fixture fleet -- which is also a career -- is not disturbed.
func _test_a_career_buys_its_fleet() -> void:
	if _station == null:
		_check(false, "the map has a station")
		return
	_check(_shipped_units == 0,
		"the map ships no player units -- the career buys them (%d shipped)"
		% _shipped_units)

	# The hint only speaks between shifts with the mission at rest; earlier tests
	# may have left it WON.
	_reset_mission()
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()
	_station.owned = {}
	_station.funds = Station.STARTING_FUNDS

	# The screen tells a fresh career what to do first.
	_station.roster_changed.emit()
	await _idle(3)
	var hint := _scene.get_node_or_null("HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
	_check(hint != null and hint.visible and "Buy your first units" in hint.text,
		"an empty career is told to buy, not to press F2 ('%s')"
		% (hint.text if hint else "no hint"))

	_check(_station.total(&"patrol") == 0 and _station.total(&"officer") == 0,
		"a fresh career owns nothing")
	var kit_price := _station.price(&"patrol") + _station.price(&"officer") \
		+ _station.price(&"ambulance") + _station.price(&"paramedic")
	_check(kit_price <= Station.STARTING_FUNDS,
		"the starter purse covers a minimal mixed crew (£%d of £%d)"
		% [kit_price, Station.STARTING_FUNDS])

	for id in [&"patrol", &"officer", &"ambulance", &"paramedic"]:
		_station.purchase(id)
	_check(_station.total(&"patrol") == 1 and _station.total(&"paramedic") == 1
			and _station.funds == Station.STARTING_FUNDS - kit_price,
		"buying the kit moves money into fleet (£%d left)" % _station.funds)

	# Broke, **stated rather than inherited**. This used to lean on the leftover after the
	# starter kit happening to be smaller than an officer, which was true at a £2,000 purse
	# and stopped being true the moment it went to £3,200 for the doctor: £1,250 remained,
	# the officer was affordable, the purchase went through, and two checks went red for a
	# reason that had nothing to do with affordability. A check about being broke should say
	# how broke, not depend on a constant three screens away.
	_station.funds = _station.price(&"officer") - 1
	var before := _station.funds
	_check(not _station.purchase(&"officer"),
		"an unaffordable purchase is refused (£%d for a £%d unit)"
			% [before, _station.price(&"officer")])
	_check(_station.funds == before and _station.total(&"officer") == 1,
		"and neither purse nor fleet moved (£%d, %d officers)"
		% [_station.funds, _station.total(&"officer")])

	_station.owned = kept_owned
	_station.funds = kept_funds
	_station._save_career()
	_station.roster_changed.emit()
	await _idle(3)
	_check(hint != null and "Press  F2" in hint.text,
		"with a fleet owned the advice moves on to F2")

	# Type is derived from what a unit is, not from a tag, so any unit on the map
	# and one still in the house have to look the same to the station.
	_check(Station.type_of(_ambulance) == &"ambulance"
			and Station.type_of(_car) == &"patrol"
			and Station.type_of(_paramedic) == &"paramedic"
			and Station.type_of(_officer) == &"officer",
		"the station recognises all four types of unit on the map")


## The career survives the window closing: funds and fleet come back off disk.
func _test_the_career_survives_reload() -> void:
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()

	_station.funds = 1234
	_station.owned = {&"patrol": 5, &"paramedic": 3}
	_station._save_career()
	_station.funds = 0
	_station.owned = {}
	_station._load_career()
	_check(_station.funds == 1234 and _station.total(&"patrol") == 5
			and _station.total(&"paramedic") == 3,
		"the career survives a reload (£%d, %d patrols, %d paramedics)"
		% [_station.funds, _station.total(&"patrol"), _station.total(&"paramedic")])

	_station.funds = kept_funds
	_station.owned = kept_owned
	_station._save_career()


func _test_dispatch_puts_a_unit_on_the_forecourt() -> void:
	# **The purse lives in the top bar** since August 2026, when the dispatch block that
	# used to carry it was hidden. Asserted on the number *tracking the books* rather than
	# on the label being non-empty: a readout wired to nothing still reads "£0", which is
	# a plausible balance and therefore an invisible failure.
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	var purse: Label = null
	if strip:
		var entry: Dictionary = strip._blocks.get(&"funds", {})
		purse = entry.get("value") as Label if not entry.is_empty() else null
	var before_funds := _station.funds
	_station.funds = before_funds + 4321
	await _idle(3)
	_check(purse != null and purse.text.contains(str(before_funds + 4321)),
		"the top bar's purse follows the books ('%s' for £%d)"
		% [purse.text if purse else "no purse", before_funds + 4321])
	_station.funds = before_funds

	# Everything owned is already standing on the map, so buy the two this test
	# sends out.
	_buy(&"paramedic", 2)
	var before := _station.available(&"paramedic")
	_check(before == 2, "the bought pair wait in the house (%d)" % before)
	var unit := _station.dispatch(&"paramedic")
	_check(unit != null, "dispatching a paramedic produced a unit")
	if unit == null:
		return
	await _idle(4)

	_check(_station.available(&"paramedic") == before - 1,
		"and took one off the roster (%d -> %d)"
			% [before, _station.available(&"paramedic")])
	_check(unit.service == Unit.Service.MEDICAL,
		"it is a medical unit (%d)" % unit.service)
	_check(_find_ability(unit, &"treat") != null
			and _find_ability(unit, &"extinguish") == null,
		"with a paramedic's verbs, not an officer's")
	_check(_station.is_home(unit.global_position),
		"standing on the station forecourt (%.1fm out)"
			% _flat_distance(unit.global_position, _station.global_position))

	# The forecourt already has seven units on it, so a slot has to be picked rather
	# than assumed -- two dispatched into the same spot would shove each other across it.
	var second := _station.dispatch(&"paramedic")
	await _idle(4)
	_check(second != null and _flat_distance(
			unit.global_position, second.global_position) > 2.0,
		"a second one lands clear of the first (%.1fm apart)" % (
			0.0 if second == null else _flat_distance(
				unit.global_position, second.global_position)))
	_check(second != null and second.display_name != unit.display_name,
		"and is named separately ('%s' vs '%s')" % [
			unit.display_name, "none" if second == null else second.display_name])

	# The regression that hid the first career's fleet: the slots used to sit on
	# the building side of the yard, and from the opening view the station's own
	# roof swallowed every dispatched unit -- bought, alive, selected, invisible.
	# Both rows now stand street-side, and the pick ray must reach them.
	_camera.stop_following()
	_camera.focus = _opening_focus
	_camera._target_distance = _opening_distance
	await _idle(40)
	var seen := 0
	for candidate: Unit in [unit, second]:
		if candidate == null:
			continue
		var aim: Vector3 = candidate.global_position + Vector3.UP * 0.9
		if not _camera.is_position_behind(aim) \
				and _controller._raycast(_screen_of(aim)).get("collider") == candidate:
			seen += 1
	_check(seen == 2,
		"both dispatched units are visible and clickable from the opening view (%d of 2)"
		% seen)

	# And the click path itself: the row is the only door the player has, and it
	# went untested while the hidden slots were burying its results.
	_buy(&"paramedic", 1)
	# **The panel rebuilds its rows off a signal, not inline.** Asking for the row in the
	# same frame as the purchase got null, and `get_global_rect()` on null threw -- which
	# abandoned the rest of this check silently, so everything below here had not run in a
	# long time while the suite reported green. Waiting is the fix; asserting the row
	# exists is what stops the same thing being silent if it ever returns.
	await _idle(4)
	var units_node := _scene.get_node("Units")
	var before_click := units_node.get_child_count()
	var row := _dispatch_row(&"paramedic")
	_check(row != null, "the roster offers a standby chip for a paramedic just bought")
	var clicked: Unit = null
	if row != null:
		# Through the row's signal, for the reason given on the selection check above.
		(row as UnitRow).selected.emit((row as UnitRow).unit)
		await _idle(4)
		_check(units_node.get_child_count() == before_click + 1
				and _station.available(&"paramedic") == 0,
			"clicking the standby chip sends one out through the real interface")
		clicked = units_node.get_child(units_node.get_child_count() - 1) as Unit

	# The spares go, and the books with them, so the fleet stays the canonical seven.
	_dissolve(unit, &"paramedic")
	_dissolve(second, &"paramedic")
	if clicked != null:
		_dissolve(clicked, &"paramedic")
	await _idle(4)


func _test_dispatch_stops_when_the_yard_is_empty() -> void:
	_buy(&"patrol", 3)
	var sent: Array[Unit] = []
	for i in 20:
		var unit := _station.dispatch(&"patrol")
		if unit == null:
			break
		sent.append(unit)
	await _idle(4)

	_check(_station.available(&"patrol") == 0,
		"emptying the house leaves nothing to send (%d)"
			% _station.available(&"patrol"))
	_check(sent.size() == 3,
		"it handed out exactly the three that were bought (%d)" % sent.size())
	_check(_station.dispatch(&"patrol") == null,
		"and refuses the next one rather than conjuring it")

	# Taking them back *parks* them: they are still on the map, still owned, so the
	# house stays empty -- parked is not un-owned.
	for unit in sent:
		_station.accept(unit)
	await _idle(4)
	_check(_station.available(&"patrol") == 0,
		"accepting them home parks them without refilling the house (%d)"
		% _station.available(&"patrol"))
	for unit in sent:
		_dissolve(unit, &"patrol")
	await _idle(4)


## The other half of the career: a unit sent home is an asset parking, not a token
## vanishing back into a counter. It stays on the map, selectable, ready to go again.
func _test_returning_parks_on_the_forecourt() -> void:
	_buy(&"officer", 1)
	var unit := _station.dispatch(&"officer")
	if unit == null:
		_check(false, "an officer to send home")
		return
	await _idle(4)

	# Put them across the district first, so this measures the walk home and not a
	# unit that was already standing on the doorstep.
	await _place_unit(unit, Vector3(20.0, 0.1, 0.0))
	_check(not _station.is_home(unit.global_position),
		"the officer starts well away from the station")

	var ability := _find_ability(unit, &"return")
	_check(ability != null and ability.is_instant(),
		"Return is offered, and needs no target")
	if ability == null:
		return
	ability.execute(unit)
	_check(unit.has_orders(), "pressing it sent them home")

	var home := false
	for i in 3000:
		await physics_frame
		if not is_instance_valid(unit):
			break
		if _station.is_home(unit.global_position) and not unit.has_orders():
			home = true
			break
	_check(home, "they reached the station and parked")
	_check(is_instance_valid(unit) and unit.visible and unit.is_selectable(),
		"still on the map, visible and selectable -- property, not a token")
	_check(_station.available(&"officer") == 0,
		"and the house is no fuller for it (%d in it)"
		% _station.available(&"officer"))
	if is_instance_valid(unit):
		_controller.select([unit])
		_check(unit.is_selected, "the parked officer can be picked straight up")
		_controller.select([])
	_dissolve(unit, &"officer")
	await _idle(4)


## Going home is not a shout: lightbar off, and the limit applies.
##
## These use a spare car bought for the test rather than a fixture, then dissolve it
## afterwards, so the canonical seven-unit fleet the rest of the suite leans on is
## never disturbed.
func _test_a_returning_vehicle_runs_dark_and_legal() -> void:
	await _clear_ambient()
	_buy(&"patrol", 1)
	var car := _station.dispatch(&"patrol") as Vehicle
	if car == null:
		_check(false, "a spare patrol car to send home")
		return
	await _idle(4)
	await _place_unit(car, ROAD)

	# On a shout first, so this measures the difference and not just a dark vehicle.
	car.issue(MoveOrder.new(Vector3(20.0, 0.0, -40.0)))
	await _wait(60)
	var siren := car.get_node_or_null(car.siren_path) as Node3D
	_check(car.is_responding(), "answering a call counts as responding")
	_check(siren != null and siren.visible, "and the lightbar is on")

	car.clear_orders()
	car.issue(ReturnOrder.new(_station))
	await _wait(60)
	_check(not car.is_responding(), "going home does not")
	_check(siren != null and not siren.visible, "and the lightbar goes dark")

	# Held to the limit rather than the vehicle's own top speed.
	var limit := car.legal_speed
	var top := car.max_speed
	var fastest := 0.0
	for i in 900:
		await physics_frame
		if not is_instance_valid(car) or not car.has_orders():
			break
		fastest = maxf(fastest, car.forward_speed)
	_check(fastest <= limit + 1.0,
		"and it holds the limit going back (peaked at %.1f, limit %.1f, flat out %.1f)"
			% [fastest, limit, top])
	_check(fastest > 4.0, "while still actually driving (%.1f m/s)" % fastest)
	_dissolve(car, &"patrol")
	await _idle(4)


## The navigation mesh covers the full width of every road, so a car left to it
## straight-lines down the middle and meets oncoming traffic head on. A unit that is no
## longer on a shout has no business doing that.
## A vehicle **on a shout** keeps its side of the road too.
##
## Being on a shout is a reason to go faster, not a reason to drive on the wrong side.
## For a long time only a returning vehicle drove in lane: responses were left to the
## navigation mesh, which covers the full width of every street, so the car tracked the
## middle and swung across the centre line on every bend. Measured on a response before
## this: **37% of samples over the line and 3.9m into the oncoming lane** -- a whole car
## on the wrong side, and worse than the 18% the mesh gives a slower vehicle, because a
## responder carries more speed into every swing. Routed in lane it measures 9%.
## A U-turn is turned round, not routed round.
##
## Lane discipline is about travelling; reversing direction is its own manoeuvre, and
## the motion model already does it well -- a three-point turn inside the width of the
## street. Sending a U-turn round the junction lattice instead measured a **25m sweep
## off a 10m street**, which is what "turning circles do not work" looked like. The
## exemption is bounded: a long drive that merely *begins* facing the wrong way is still
## a drive and still wants its lane, and without the range test a corner-to-corner
## response that started backwards lost lane discipline for all of it -- 9% over the
## centre line became 58%.
func _test_a_u_turn_is_turned_not_routed() -> void:
	# On a north-south street, facing north, sent back south -- far enough that the old
	# threshold would have routed it, near enough that turning round is the whole job.
	#
	# Offset a lane's width rather than *exactly* 180 degrees behind. At a dead 180 the
	# heading error is ill-conditioned -- signed_angle_to can return either sign, so the
	# opposite lock flips every frame, the nose never swings, and the car reverses the
	# whole way at max_reverse_speed instead of turning. That is a real edge in the
	# motion model (noted in NEXT.md); it is not what this check is about, and a player
	# right-clicking the road behind them practically never lands on it.
	var here := Vector3(20.0, 0.15, -22.0)
	var target := Vector3(20.0 + CityGrid.LANE_OFFSET, 0.0, 22.0)
	await _place_unit(_car, here, 0.0)
	var order := MoveOrder.new(target)
	_car.issue(order)
	await _idle(4)
	_check(order._route.is_empty(),
		"a U-turn is driven at directly rather than routed (%d waypoints)"
		% order._route.size())

	# Watched for long enough to complete the manoeuvre and set off, which is what this
	# is measuring. **Arrival is deliberately not asserted here.** On the live district
	# this drive queues behind whatever the earlier tests left standing, and it took
	# more than ninety seconds while still closing -- a fact about the traffic, not about
	# turning. `Game/diagnose_driving.gd` measures the same turn on a cleared street and
	# gets 7.9s; asserting a time here would only ever be measuring the neighbours.
	var widest := 0.0
	for i in 900:
		await physics_frame
		widest = maxf(widest, absf(_car.global_position.x - 20.0))
		if not _car.has_orders():
			break
	_check(_car.global_position.z > here.z + 6.0,
		"and comes round to head back the way it came (%.1fm along)"
		% (_car.global_position.z - here.z))
	# The street is two lanes -- ten metres. Anything much past that is the car leaving
	# the road to come round, which is the sweep this exists to forbid. Measured 2.7m
	# turning, 25.4m routed.
	_check(widest < 10.0,
		"turning round inside the street rather than sweeping out of it (%.1fm)"
		% widest)

	# And at **25m**, which is the range that was actually broken. It sat in a band too
	# far for the motion model to turn round in (the strict waypoint trigger, 16m) and
	# too near to lane-route (40m), so it did neither and swept: measured 27m off a 10m
	# street, worse than the same turn at 45m and slower than one twice as long. The
	# generous `turn_round_range` covers it now, and only applies to a straight drive at
	# a destination -- giving it to the last leg of a *routed* journey let the latch
	# re-arm on the approach and took line-keeping from 9% back to 36%.
	var near_here := Vector3(20.0, 0.15, -12.0)
	await _place_unit(_car, near_here, 0.0)
	_car.issue(MoveOrder.new(Vector3(20.0 + CityGrid.LANE_OFFSET, 0.0, 13.0)))
	var near_widest := 0.0
	for i in 900:
		await physics_frame
		near_widest = maxf(near_widest, absf(_car.global_position.x - 20.0))
		if not _car.has_orders():
			break
	_check(near_widest < 10.0,
		"and at 25m too, which is the range that used to sweep (%.1fm)" % near_widest)
	_car.clear_orders()
	await _idle(4)

	# And a long drive that starts facing the wrong way is still routed, or the
	# exemption would swallow lane discipline whole.
	var far := MoveOrder.new(CityGrid.junction(Vector2i(4, 4)))
	await _place_unit(_car, CityGrid.junction(Vector2i(1, 1)), 0.0)
	_car.issue(far)
	await _idle(4)
	_check(not far._route.is_empty(),
		"but a long journey keeps its lane route even so (%d waypoints)"
		% far._route.size())
	_car.clear_orders()
	await _idle(4)


func _test_a_responding_vehicle_keeps_its_lane() -> void:
	# Corner to corner, so the drive is several streets and turns rather than one run.
	var from := CityGrid.junction(Vector2i(1, 1))
	var to := CityGrid.junction(Vector2i(4, 4))
	await _place_unit(_car, from + Vector3(0.0, 0.15, 0.0))
	_car.issue(MoveOrder.new(to))
	_check(_car.is_responding(), "the car is on a shout, not going home")

	var samples := 0
	var wrong := 0
	for i in 5400:
		await physics_frame
		if not _car.has_orders():
			break
		if not _on_open_street(_car.global_position):
			continue
		var across := _lane_offset(_car.global_position)
		var right := (-_car.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		samples += 1
		# A metre the wrong side is a wheel over the line rather than a car in the
		# oncoming lane -- the same tolerance the return and the traffic use.
		if across.dot(right.normalized()) < -1.0:
			wrong += 1

	_check(samples > 100, "sampled the response %d times" % samples)
	# Turn arcs reach past the junction box and are counted, so this is not zero: a car
	# coming round a corner is over the line by definition. Sabotaging the lane route
	# in *this* scenario measures **69%** -- and the drive takes four times as long --
	# so the margin is wide. (The standalone diagnostic measures 37% on its own shorter
	# route; the number that matters here is the one this check itself moves by.)
	_check(wrong * 5 < samples,
		"and it kept its side of the road on the way (%d of %d over the line, %.0f%%)"
			% [wrong, samples, 100.0 * wrong / maxi(samples, 1)])
	_car.clear_orders()
	await _idle(4)


func _test_a_returning_vehicle_keeps_its_lane() -> void:
	_buy(&"ambulance", 1)
	var van := _station.dispatch(&"ambulance") as Vehicle
	if van == null:
		_check(false, "a spare ambulance to send home")
		return
	await _idle(4)
	# Well across the district, so the route home is several streets and turns rather
	# than one straight run. Faced towards its first junction, as the old start was by
	# accident of the old grid: opening with a three-point turn would fill the sample
	# with the manoeuvre and measure that instead of the driving.
	await _place_unit(van, Vector3(20.0, 0.15, -45.0), PI)
	van.issue(ReturnOrder.new(_station))

	var samples := 0
	var wrong := 0
	for i in 3000:
		await physics_frame
		if not is_instance_valid(van) or not van.has_orders():
			break
		if not _on_open_street(van.global_position):
			continue
		var across := _lane_offset(van.global_position)
		var right := (-van.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		samples += 1
		# A metre the wrong side is a wheel over the line rather than a vehicle in the
		# oncoming lane, which is the tolerance traffic is measured against too.
		if across.dot(right.normalized()) < -1.0:
			wrong += 1

	_check(samples > 40, "sampled the drive home %d times" % samples)
	# Tight, because it measures **zero**: since the routing moved to
	# CityGrid.lane_route the drive home does not put a wheel over the line at all, and
	# a bar of "under a tenth" would have passed at ninety-six bad samples out of a
	# thousand. The old 6%-with / 18%-without figures predate the shared route and no
	# longer describe this scenario.
	_check(wrong * 30 < samples,
		"and it kept its side of the road (%d of %d over the line, %.0f%%)"
			% [wrong, samples, 100.0 * wrong / maxi(samples, 1)])
	_check(is_instance_valid(van) and _station.is_home(van.global_position),
		"arriving home and parking on the forecourt")
	_dissolve(van, &"ambulance")
	await _idle(4)


## The route itself, rather than a statistic about driving it. Sampling a drive can
## only ever say "mostly" -- a car swings wide, brakes late, gets nudged. The waypoints
## are exact, and every one of them on a street should be in the right-hand lane.
func _test_the_route_home_is_laid_out_in_lane() -> void:
	_buy(&"ambulance", 1)
	var van := _station.dispatch(&"ambulance") as Vehicle
	if van == null:
		_check(false, "a spare ambulance to route home")
		return
	await _idle(4)
	await _place_unit(van, Vector3(20.0, 0.15, -45.0))

	var order := ReturnOrder.new(_station)
	var route: Array[Vector3] = order._build_route(van)
	_check(route.size() >= 6,
		"the way home is laid out as %d waypoints, not one" % route.size())

	var checked := 0
	var offside := 0
	for i in range(route.size() - 1):
		var here := _lane_offset(route[i])
		var next := _lane_offset(route[i + 1])
		# Both ends on the same street. A pair that crosses a junction has a diagonal
		# between them and no single side to be on.
		if here == Vector3.ZERO or next == Vector3.ZERO:
			continue
		if is_zero_approx(here.x) != is_zero_approx(next.x):
			continue
		var direction := route[i + 1] - route[i]
		direction.y = 0.0
		if direction.length() < 1.0:
			continue
		checked += 1
		if here.dot(direction.normalized().cross(Vector3.UP)) < 1.0:
			offside += 1

	_check(checked >= 3, "%d of those waypoints sit on an open street" % checked)
	_check(offside == 0,
		"and every one is in the right-hand lane (%d were not)" % offside)
	_dissolve(van, &"ambulance")
	await _idle(4)


## The route home is exact, so the left-turn fix can be asserted on the waypoint
## itself rather than a statistic: a leg that starts with a left turn must carry a
## point inside the junction box, on the driver's own quadrant.
func _test_the_route_home_rounds_left_turns() -> void:
	await _place_unit(_ambulance, Vector3(20.0, 0.15, -45.0), PI)
	var order := ReturnOrder.new(_station)
	var route := order._build_route(_ambulance)

	# The BFS route from here runs west, west, then south to the station -- so the
	# turn at the junction two avenues over is a left, and must be rounded.
	var turn := CityGrid.junction(Vector2i(1, 2))
	var apex := Vector3.ZERO
	for point in route:
		if _flat_distance(point, turn) < 4.0:
			apex = point
	_check(apex != Vector3.ZERO,
		"the route home carries a waypoint inside the left-turn junction box")
	_check(apex != Vector3.ZERO and apex.x < turn.x and apex.z < turn.z,
		"on the driver's own quadrant of it (%s)" % apex)
	_ambulance.clear_orders()


func _test_work_order_survives_target_loss() -> void:
	await _clear_incidents()
	# Far enough that the officer is still walking when the target disappears, which
	# is the case most likely to strand an order mid-approach.
	var fire := _spawn_fire(Vector3(10.0, 0.0, 14.0), 0.5)
	await _place_unit(_officer, Vector3(27.0, 0.1, 14.0))
	_officer.issue(ExtinguishOrder.new(fire))
	await _wait(25)
	_check(_officer.has_orders(), "the order is running before the target is lost")

	fire.queue_free()
	await _wait(20)
	_check(not _officer.has_orders(), "the order ended when the fire vanished")
	_check(not _officer.is_navigating(), "and the officer stopped walking")
	_check(_officer.action_clip.is_empty(), "and dropped the work clip")
	await _clear_incidents()


func _test_transport_to_hospital() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(18.0, 0.0, -12.0))
	# Pre-treated: this test is about the ride, not the treatment.
	casualty.treat(1.0)
	_check(casualty.is_stable, "the casualty is stable before collection")
	_check(casualty.active,
		"and the incident is still open -- stabilising is not saving them")

	# Collect is the paramedic's verb: the stretcher run. The ambulance itself waits
	# at the kerb -- its navigation mesh is the road and a casualty usually is not.
	var patrol_verb := _car.resolve(_target_for(casualty))
	_check(patrol_verb != null and patrol_verb.id() == &"move",
		"a patrol car means Move (got '%s')"
		% ("none" if patrol_verb == null else patrol_verb.id()))
	var wheels_verb := _ambulance.resolve(_target_for(casualty))
	_check(wheels_verb != null and wheels_verb.id() == &"move",
		"and so does the ambulance -- the stretcher does the collecting (got '%s')"
		% ("none" if wheels_verb == null else wheels_verb.id()))
	var officer_verb := _officer.resolve(_target_for(casualty))
	_check(officer_verb != null and officer_verb.id() == &"move",
		"and an officer, who has no stretcher to fetch (got '%s')"
		% ("none" if officer_verb == null else officer_verb.id()))
	var ability := _paramedic.resolve(_target_for(casualty))
	_check(ability != null and ability.id() == &"collect",
		"a stable casualty resolves to Collect for a paramedic (got '%s')"
		% ("none" if ability == null else ability.id()))
	if ability == null:
		return

	await _place_unit(_ambulance, Vector3(20.0, 0.2, -2.0))
	await _place_unit(_paramedic, Vector3(20.0, 0.0, -8.0))
	_paramedic.issue(ability.make_order(_paramedic, _target_for(casualty)))
	var wheeled := await _await_orders_done(_paramedic, 3000)
	_check(wheeled, "the paramedic ran the stretcher round trip")
	_check(casualty.is_loaded, "the casualty is aboard")
	_check(_ambulance.casualties.size() == 1,
		"the ambulance reports 1 aboard (%d)" % _ambulance.casualties.size())
	_check(not casualty.visible, "and is hidden while riding")
	_check(_paramedic.get_node_or_null("Stretcher") == null,
		"the stretcher went back with the handover")

	_ambulance.issue(MoveOrder.new(_hospital.global_position))
	await _await_orders_done(_ambulance, 3600)
	_check(not is_instance_valid(casualty) or not casualty.active,
		"driving into the hospital delivered them")
	_check(_ambulance.casualties.is_empty(), "the ambulance is empty again")
	await _clear_incidents()


## The regression that forced the stretcher: a casualty in the middle of a park,
## where no vehicle mesh runs. The old vehicle Collect parked as close as the road
## ran and never closed the gap; the paramedic closes it on foot.
func _test_a_stretcher_reaches_where_wheels_cannot() -> void:
	await _clear_incidents()
	var park := CityGrid.block_centre(1, 0)
	var casualty := _spawn_casualty(park)
	casualty.treat(1.0)

	var road_gap := INF
	for band in CityGrid.BANDS:
		road_gap = minf(road_gap, minf(
			absf(park.x - CityGrid.band_centre_x(band)),
			absf(park.z - CityGrid.band_centre_z(band))))
	_check(road_gap > 9.0,
		"the park centre is genuinely off the road network (%.1fm)" % road_gap)

	# The ambulance parks at the nearest crossroads; the paramedic starts beside it.
	var kerb := CityGrid.junction(Vector2i(2, 1))
	await _place_unit(_ambulance, kerb)
	await _place_unit(_paramedic, kerb + Vector3(3.0, 0.0, 0.0))
	var ability := _paramedic.resolve(_target_for(casualty))
	if ability == null or ability.id() != &"collect":
		_check(false, "the park casualty resolves to Collect")
		await _clear_incidents()
		return
	_paramedic.issue(ability.make_order(_paramedic, _target_for(casualty)))
	var wheeled := await _await_orders_done(_paramedic, 6000)
	_check(wheeled and casualty.is_loaded and _ambulance.casualties.size() == 1,
		"wheeled aboard from the middle of a park (done %s, aboard %s)"
		% [wheeled, casualty.is_loaded])
	_ambulance.casualties.clear()
	casualty.queue_free()
	await _clear_incidents()
	_reset_mission()


func _test_mission_wins_when_everything_is_clear() -> void:
	# Earlier tests resolve incidents of their own, so the tallies are reset here
	# rather than assumed. This is about the win rule, not the running total.
	await _clear_incidents()
	_reset_mission()

	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.4)
	await _wait(6)
	_check(_mission.fires_remaining() == 1,
		"the mission sees 1 fire burning (%d)" % _mission.fires_remaining())
	_check(_mission.state == Mission.State.RUNNING, "and is still running")

	fire.douse(5.0)
	await _wait(10)
	_check(_mission.fires_out == 1, "counted the fire as out (%d)" % _mission.fires_out)
	_check(_mission.state == Mission.State.WON, "won once nothing was left burning")
	# The win puts a modal over the district and it stays there until dismissed, which
	# is the point of it -- so this test clears up after itself rather than leaving the
	# rest of the suite clicking through a card it cannot see.
	_reset_mission()


func _test_mission_is_lost_when_a_casualty_dies() -> void:
	await _clear_incidents()
	_reset_mission()

	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	# On the edge, and declining fast, so the test does not sit through 80 seconds.
	casualty.health = 0.05
	casualty.decline_per_second = 1.0
	await _wait(30)
	_check(_mission.casualties_lost == 1,
		"counted the casualty as lost (%d)" % _mission.casualties_lost)
	_check(_mission.state == Mission.State.LOST, "and the shout is lost")

	await _clear_incidents()
	_reset_mission()


# --- Freeplay: the director and the score ------------------------------------
