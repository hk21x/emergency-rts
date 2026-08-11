extends SceneTree

## Dev utility: drive a vehicle around the district and report what goes wrong.
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/diagnose_driving.gd
##
## Written for a specific complaint -- vehicles pathfinding badly, colliding, and
## getting into road blocks they cannot escape, with pedestrians stopping dead against
## them. This measures all of it rather than describing it, because every handling
## fault in this project so far has been misdiagnosed on the first guess.
##
## The passes, in order:
##
##   1. **The tour.** One patrol car driven leg by leg across the whole district,
##      through junctions and corner to corner. Reports per leg: whether it arrived,
##      how long it took, its worst stall, and everything it hit.
##   2. **The blockade**, and then two narrower stagings of the same idea: one car in
##      the road, and a street with no way through at all. These are the "road block it
##      cannot escape" case, staged, so the answer is reproducible rather than
##      anecdotal -- and they are three separate passes because they turn out to be
##      three different questions. One car angled across a lane is passable, three
##      spaced across it are shovable, and only four filling the full width leave no
##      answer but another street.
##   2b. **Someone on foot.** A car parked squarely between an officer and where they
##      are sent. Watching the ambient crowd caught this once in one run and never in
##      another, which is no way to know whether it is fixed.
##   3. **The district.** Sampled throughout: how much ambient traffic is moving, and
##      how many pedestrians are standing still while touching a vehicle.
##
## Passes that share an avenue contaminate each other. The shut-street pass ran on the
## same x=-20 avenue as the blockade and the pinch for its first three runs, by which
## time the ambient fleet had been queuing there for over a minute -- so it was reading
## the leftovers of the previous test. It has its own avenue now.
##
## Nothing here asserts. It prints numbers for a human to judge -- the smoke suite is
## where a fixed behaviour gets pinned.

const SCENE := "res://Game/Playground.tscn"

## No progress toward the current leg for this long counts as a stall.
const STALL_AFTER := 3.0
## Give up on a leg after this long and record it as failed.
const LEG_TIMEOUT := 60.0
## Two vehicle centres closer than this are interpenetrating: the bodies are ~5m long
## and ~2.2m wide, so anything under this is metal inside metal.
const TOO_CLOSE := 2.6
## A civilian within this of a vehicle, and not moving, is being blocked by it.
const PED_CONTACT := 2.2
const PED_STILL_SPEED := 0.05

var _scene: Node3D
var _car: Vehicle
var _station: Station

## Findings, accumulated across the run.
var _stalls: Array[Dictionary] = []
var _hits := {}
var _interpenetrations: Array[Dictionary] = []
var _traffic_samples: Array[float] = []
var _blocked_pedestrians := {}
## Seconds spent at a dead stop during the current leg.
var _frozen := 0.0
## Legs that ended with the car below the world.
var _fell_through: Array[String] = []
## Seconds spent stationary inside a junction box, and seconds spent in one at all.
var _boxed_in := 0.0
## Seconds spent doing another vehicle's speed because it could not get past.
var _held := 0.0
var _junction_frames := 0.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	await process_frame

	_station = _scene.get_node("Station")
	_station.career_path = "user://diagnose-career.cfg"
	_station.funds = 999999
	_station.owned = {}
	_station.purchase(&"patrol")
	_car = _station.dispatch(&"patrol") as Vehicle
	await _idle(40)

	print("\n================ DRIVING DIAGNOSTIC ================")
	print("car: %s   max_speed %.1f   grip_scale %.2f"
		% [_car.display_name, _car.max_speed, _car.grip_scale])

	await _tour()
	await _blockade()
	await _pinch()
	await _shut_street()
	await _on_foot()
	await _jam()
	await _lane_discipline()
	await _uturns()
	_report()
	quit()


# --- Pass 1: the tour ---------------------------------------------------------

## Legs chosen to exercise the things that go wrong: long straights, junction turns in
## both directions, a corner-to-corner crossing, and a return to the yard.
func _tour() -> void:
	print("\n--- 1. TOUR ---------------------------------------")
	# **Junction centres, not hand-picked coordinates.** The first version of this
	# invented round numbers and two of them landed inside city blocks, where there is
	# no navigation mesh at all -- so it reported a pathfinding failure that was really
	# a bad waypoint. Asking CityGrid for the lattice it built guarantees every target
	# is somewhere a car can actually stand.
	var legs: Array[Dictionary] = []
	for hop in [Vector2i(2, 3), Vector2i(4, 3), Vector2i(4, 1),
			Vector2i(1, 1), Vector2i(1, 4), Vector2i(3, 3)]:
		legs.append({"name": "junction %d,%d" % [hop.x, hop.y],
			"to": CityGrid.junction(hop)})
	for leg in legs:
		await _drive(str(leg["name"]), leg["to"])


func _drive(name: String, target: Vector3) -> void:
	_car.clear_orders()
	await _idle(4)
	var start := _car.global_position
	_car.issue(MoveOrder.new(target))

	var frames := 0
	var best := INF
	var since_progress := 0.0
	var worst_stall := 0.0
	var stall_at := Vector3.ZERO
	var top := 0.0
	var arrived := false
	_frozen = 0.0
	var step := 1.0 / 60.0

	while frames < int(LEG_TIMEOUT * 60):
		await physics_frame
		frames += 1
		var here := _car.global_position
		var gap := _flat(here - target)
		top = maxf(top, absf(_car.forward_speed))

		if gap < best - 0.25:
			best = gap
			since_progress = 0.0
		else:
			since_progress += step
			if since_progress > worst_stall:
				worst_stall = since_progress
				stall_at = here

		# Crawling behind somebody is its own fault and needs its own number: the stall
		# measure only sees a car that has stopped, and a unit doing 3 m/s behind a taxi
		# with a 25 m/s ceiling is stuck in every way that matters to a player.
		if _car.held_up_for() > 0.0:
			_held += step
		if absf(_car.forward_speed) < 0.3:
			_frozen += step
			# Stopped **inside a junction box** is its own fault and deserves its own
			# number: it is what a player sees as the car getting caught at a crossroads,
			# and it was invisible in the per-leg stall figure, which counts a wait
			# anywhere on the leg the same way.
			var cell := CityGrid.junction_at(here)
			if _flat(here - CityGrid.junction(cell)) < 9.0:
				_boxed_in += step
		_junction_frames += step if _flat(here
			- CityGrid.junction(CityGrid.junction_at(here))) < 9.0 else 0.0
		_watch_contacts()
		if frames % 30 == 0:
			_sample_district()
		if not _car.has_orders():
			arrived = true
			break

	if worst_stall >= STALL_AFTER:
		_stalls.append({"leg": name, "seconds": worst_stall, "at": stall_at,
			"near": _describe_surroundings(stall_at)})

	var fell := _car.global_position.y < -5.0
	print("  %-20s %s  %5.1fs  %5.1fm travelled  top %4.1f m/s  worst stall %4.1fs" % [
		name, "ARRIVED" if arrived else "FAILED ", frames / 60.0,
		_flat(_car.global_position - start), top, worst_stall])
	print("      %4.0f%% of the leg at a standstill" % (_frozen / (frames / 60.0) * 100.0))
	if fell:
		print("      *** FELL OUT OF THE WORLD *** y = %.0f -- collision pushed it "
			% _car.global_position.y + "through the ground and it has been falling since")
		_fell_through.append(name)
		# Put it back on the road, or every later leg measures a falling car.
		_car.global_position = Vector3(target.x, 0.4, target.z)
		_car.velocity = Vector3.ZERO
		await _idle(20)
	if not arrived:
		print("      gave up %.1fm short, at %s" % [best, str(_car.global_position)])
		print("      surroundings: %s" % _describe_surroundings(_car.global_position))


# --- Pass 2: the staged blockade ----------------------------------------------

## The case the complaint is really about: a street the car cannot get through. Three
## vehicles are parked nose to tail across a carriageway and the car is sent past them.
##
## Two outcomes are interesting and they are very different faults. Either the car finds
## a way round -- fine -- or it wedges, and then the question is whether it *recovers*:
## Vehicle has a stuck timeout and a reverse-out escape, and this is what says whether
## that is enough.
func _blockade() -> void:
	print("\n--- 2. BLOCKADE -----------------------------------")
	var street := Vector3(-20.0, 0.15, 40.0)
	var parked: Array[Vehicle] = []
	for i in 3:
		_station.purchase(&"patrol")
		var blocker := _station.dispatch(&"patrol") as Vehicle
		if blocker == null:
			continue
		blocker.clear_orders()
		# Across the road rather than along it, so the street is genuinely shut --
		# and spaced clear of each other. Parking them 2.4m apart was the first
		# attempt and it is *inside* a 5m body: the physics engine resolved the
		# overlap by flinging the car to y = -58,000. A blockade has to be a legal
		# arrangement of vehicles or the test is measuring the ejection, not the jam.
		blocker.global_position = street + Vector3(0.0, 0.0, float(i) * 6.0 - 6.0)
		blocker.rotation.y = PI * 0.5
		blocker.velocity = Vector3.ZERO
		parked.append(blocker)
	await _idle(30)
	print("  parked %d vehicles across the street at %s" % [parked.size(), str(street)])

	_car.global_position = street + Vector3(30.0, 0.0, 0.0)
	_car.velocity = Vector3.ZERO
	await _idle(20)
	await _drive("through the blockade", street + Vector3(-40.0, 0.0, 0.0))

	# Did the blockade itself survive being driven at, or was it shoved through?
	var moved := 0
	for blocker in parked:
		if _flat(blocker.global_position - street) > 6.0:
			moved += 1
	print("  blockers displaced: %d of %d" % [moved, parked.size()])
	for blocker in parked:
		blocker.queue_free()
	await _idle(10)


# --- Pass 2b: the single car in the road --------------------------------------

## The case from play: **one** stationary vehicle in the street, not a wall of them.
##
## The complaint is that the car reverses, drives back the same way, hits the same car
## and never tries anything else. This counts the oscillation directly -- how many times
## the escape fires -- and reports whether the passing logic ever finds a gap, which is
## the difference between "it cannot get round" and "it will not try".
func _pinch() -> void:
	print("\n--- 2b. ONE CAR IN THE ROAD -----------------------")
	var street := Vector3(-20.0, 0.15, 20.0)
	_station.purchase(&"patrol")
	var blocker := _station.dispatch(&"patrol") as Vehicle
	blocker.clear_orders()
	blocker.global_position = street
	# Angled across the lane, as in the report -- not neatly parked.
	blocker.rotation.y = PI * 0.35
	blocker.velocity = Vector3.ZERO
	await _idle(30)

	_car.global_position = street + Vector3(0.0, 0.0, 26.0)
	# **Facing the blocker.** This said `PI` for its first three runs, which points a car
	# the other way -- so every reading of this pass was a U-turn *and* an obstruction,
	# and the seconds it took to swing round were being read as time spent stuck.
	_car.rotation.y = 0.0
	_car.velocity = Vector3.ZERO
	await _idle(20)
	var target := street + Vector3(0.0, 0.0, -30.0)
	_car.issue(MoveOrder.new(target))

	var escapes := 0
	var was_escaping := false
	var gaps_found := 0
	var frames := 0
	var best := INF
	while frames < 45 * 60:
		await physics_frame
		frames += 1
		var escaping: bool = _car._escape_time > 0.0
		if escaping and not was_escaping:
			escapes += 1
		was_escaping = escaping
		if _car.is_avoiding:
			gaps_found += 1
		best = minf(best, _flat(_car.global_position - target))
		if not _car.has_orders():
			break

	var arrived := not _car.has_orders()
	print("  %s after %.1fs" % ["ARRIVED" if arrived else "NEVER GOT THROUGH",
		frames / 60.0])
	print("  closest approach     %.1fm of %.1fm" % [best, 56.0])
	print("  escape cycles        %d  (reverse-and-retry, each ~1s)" % escapes)
	print("  frames finding a gap %d  (passing line accepted)" % gaps_found)
	print("  blocker moved        %.1fm" % _flat(blocker.global_position - street))
	blocker.queue_free()
	await _idle(10)


# --- Pass 2bb: a street that is genuinely shut --------------------------------

## The case the give-up timer exists for, and the one the two passes above do *not*
## test: a carriageway with no way through at all.
##
## One car angled across a lane turns out to be passable, and three spaced across it are
## shovable -- both of which leave "push harder" as a working answer. Four cars filling
## the full 10m width leave no gap and will not move, so the only way to the far side is
## another street. Either the car finds one or it sits there, and that is the whole
## question.
func _shut_street() -> void:
	print("\n--- 2bb. A STREET WITH NO WAY THROUGH -------------")
	# A different avenue from the blockade and the pinch above, which both sit on x=-20.
	# Run on the same one and the ambient fleet has already been queuing there for over a
	# minute, so the pass measures the leftovers of the previous test rather than its own.
	var a := Vector2i(4, 3)
	var b := Vector2i(4, 2)
	var from := CityGrid.junction(a)
	var to := CityGrid.junction(b)
	var along := (to - from).normalized()
	var across := along.cross(Vector3.UP)
	var mid := (from + to) * 0.5

	var wall: Array[Vehicle] = []
	# 1.95m wide cars at 2.5m centres span 9.4m of a 10m road, which leaves 0.3m at each
	# kerb -- sealed, and still a legal arrangement rather than an overlap the physics
	# engine will resolve by firing something through the floor.
	for offset in [-3.75, -1.25, 1.25, 3.75]:
		_station.purchase(&"patrol")
		var blocker := _station.dispatch(&"patrol") as Vehicle
		if blocker == null:
			continue
		blocker.clear_orders()
		blocker.global_position = mid + across * offset
		blocker.rotation.y = atan2(along.x, along.z) + PI
		blocker.velocity = Vector3.ZERO
		wall.append(blocker)
	await _idle(30)
	print("  %d cars filling the carriageway at %s" % [wall.size(), str(mid)])

	_car.global_position = from + along * 14.0 + across * CityGrid.LANE_OFFSET
	_car.rotation.y = atan2(along.x, along.z) + PI
	_car.velocity = Vector3.ZERO
	await _idle(20)
	await _drive("round the shut street", mid + along * 14.0)

	var shoved := 0
	for blocker in wall:
		if _flat(blocker.global_position - mid) > 5.0:
			shoved += 1
	print("  blockers shoved out of the way: %d of %d" % [shoved, wall.size()])
	# The district uses this street too, and its cars have the same problem. Counting
	# them says whether a failed attempt was the wall or the queue that formed behind it.
	var queued := 0
	for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
		if node is TrafficCar and _flat(node.global_position - mid) < 30.0:
			queued += 1
	print("  ambient cars caught in the same street: %d" % queued)
	for blocker in wall:
		blocker.queue_free()
	await _idle(10)


# --- Pass 2bc: someone on foot meets a parked car -----------------------------

## The pedestrian half of the complaint, staged rather than waited for.
##
## People mask layer 1, which is what the player's vehicles are on; the vehicles mask
## 1|2|64 and cannot see people at all. So a walker who meets a parked patrol car has
## something solid in front of them and nothing that will move out of the way. Watching
## the ambient crowd caught this once in one run and never in another, which is no way
## to know whether it is fixed -- so this puts a car squarely between an officer and
## where they have been told to go, and times them.
func _on_foot() -> void:
	print("\n--- 2bc. SOMEONE ON FOOT MEETS A PARKED CAR -------")
	var here := CityGrid.junction(Vector2i(1, 3)) + Vector3(0.0, 0.0, 18.0)
	_station.purchase(&"patrol")
	var parked := _station.dispatch(&"patrol") as Vehicle
	parked.clear_orders()
	parked.global_position = here
	parked.rotation.y = PI * 0.5
	parked.velocity = Vector3.ZERO

	_station.purchase(&"officer")
	var walker := _station.dispatch(&"officer") as Person
	walker.clear_orders()
	walker.global_position = here + Vector3(0.0, 0.0, 7.0)
	await _idle(30)

	var target := here - Vector3(0.0, 0.0, 7.0)
	walker.issue(MoveOrder.new(target))
	var frames := 0
	var touching := 0
	var still := 0
	while frames < 30 * 60:
		await physics_frame
		frames += 1
		if _flat(walker.global_position - parked.global_position) < PED_CONTACT + 1.5:
			touching += 1
			if Vector2(walker.velocity.x, walker.velocity.z).length() < PED_STILL_SPEED:
				still += 1
		if not walker.has_orders():
			break
	var arrived := not walker.has_orders()
	print("  %s after %.1fs, %.1fm short" % ["ARRIVED" if arrived else "NEVER GOT ROUND IT",
		frames / 60.0, _flat(walker.global_position - target)])
	print("  frames against the car %d, of which stopped dead %d" % [touching, still])
	parked.queue_free()
	walker.queue_free()
	await _idle(10)


# --- Pass 2c: does a jam form, and does it grow? ------------------------------

## The second report from play: a pile-up that "only gets worse" over a minute, with
## ambient cars stopped at angles across both lanes.
##
## The suspicion is the pull-over. Traffic tucks to the kerb for a *responding* vehicle,
## and several cars doing that at once into a space that cannot hold them will stack --
## harmless while they were ghosts, a permanent jam now they are solid. This parks a
## responding car in a street and watches whether the jam grows, shrinks or holds.
func _jam() -> void:
	print("\n--- 2c. DOES A JAM FORM AND GROW? -----------------")
	# A responding car **driving** a busy street, back and forth, which is what a player
	# does and what makes traffic tuck in for it. The first version of this parked the
	# car with its lights on and cleared its orders -- `is_responding()` reads the
	# *current order*, and a car with none is not navigating, so no traffic ever pulled
	# over and the test measured a district going about its business.
	var a := CityGrid.junction(Vector2i(2, 2))
	var b := CityGrid.junction(Vector2i(2, 4))
	_car.global_position = a + Vector3(0.0, 0.15, 0.0)
	_car.velocity = Vector3.ZERO
	_car.siren_on = true
	await _idle(20)

	print("  %6s %8s %10s %10s %12s" % ["t", "moving", "stopped", "touching", "pulled over"])
	var leg := 0
	for tick in 7:
		for i in 60 * 10:
			await physics_frame
			# Keep it driving the street rather than arriving and parking.
			if not _car.has_orders():
				leg += 1
				_car.issue(MoveOrder.new(b if leg % 2 == 1 else a))
		var moving := 0
		var stopped := 0
		var touching := 0
		var tucked := 0
		var cars: Array[TrafficCar] = []
		for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
			var traffic := node as TrafficCar
			if traffic:
				cars.append(traffic)
		for traffic in cars:
			if absf(traffic.forward_speed) > 0.3:
				moving += 1
			else:
				stopped += 1
			if traffic.is_pulled_over:
				tucked += 1
			for other in cars:
				if other != traffic and _flat(
						other.global_position - traffic.global_position) < 4.2:
					touching += 1
					break
		print("  %5ds %8d %10d %10d %12d"
			% [(tick + 1) * 10, moving, stopped, touching, tucked])
	_car.siren_on = false


# --- Pass 2d: which side of the road does a response drive on? ----------------

## The complaint: player vehicles weave onto the wrong side while responding.
##
## The same metre-over-the-line metric the suite uses on a *returning* vehicle, applied
## to one on a shout. Returns are routed junction to junction with a lane offset;
## responses are left to the navigation mesh, which covers the **full width** of every
## road -- so the expectation is that this is much worse, and by how much is the number
## worth having before changing anything.
func _lane_discipline() -> void:
	print("\n--- 2d. WHICH SIDE OF THE ROAD? -------------------")
	var from := CityGrid.junction(Vector2i(1, 1))
	var to := CityGrid.junction(Vector2i(4, 4))
	_car.global_position = from + Vector3(0.0, 0.15, 0.0)
	_car.velocity = Vector3.ZERO
	await _idle(20)
	_car.issue(MoveOrder.new(to))

	var samples := 0
	var wrong := 0
	var worst := 0.0
	var frames := 0
	var on_the_verge := 0
	for i in 60 * 90:
		await physics_frame
		if not _car.has_orders():
			break
		# The vehicle navigation mesh covers the pavement as well as the road, so
		# "how much of a normal drive is spent off the carriageway" is now a number
		# worth watching. It should be nearly all junction boxes and nothing else.
		frames += 1
		if not CityGrid.is_road(_car.global_position):
			on_the_verge += 1
		var across := _lane_offset(_car.global_position)
		if across == Vector3.ZERO:
			continue
		var right := (-_car.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		samples += 1
		var side := across.dot(right.normalized())
		worst = minf(worst, side)
		if side < -1.0:
			wrong += 1
	print("  responding, %d samples on open street" % samples)
	print("  over the centre line  %d  (%.0f%%)"
		% [wrong, 100.0 * wrong / maxi(samples, 1)])
	print("  deepest into the oncoming lane  %.1fm" % -worst)
	print("  (the suite asks a *returning* vehicle for under 10%%; it measures 6%%,")
	print("   and 18%% when left to the navigation mesh)")
	print("  off the carriageway   %d of %d frames  (%.0f%%)"
		% [on_the_verge, frames, 100.0 * on_the_verge / maxi(frames, 1)])


## Offset from the centre line of the road band a point is on, or zero in a junction
## or off the grid. The same measure the suite's lane checks use.
func _lane_offset(point: Vector3) -> Vector3:
	var half := CityGrid.ROAD_WIDTH * CityGrid.TILE * 0.5
	var cx := CityGrid.band_centre_x(CityGrid.band_at_x(point.x))
	var cz := CityGrid.band_centre_z(CityGrid.band_at_z(point.z))
	var in_x: bool = absf(point.x - cx) <= half
	var in_z: bool = absf(point.z - cz) <= half
	if in_x == in_z:
		return Vector3.ZERO
	return Vector3(point.x - cx, 0.0, 0.0) if in_x else Vector3(0.0, 0.0, point.z - cz)


# --- Pass 2e: turning round -----------------------------------------------------

## U-turns, at the ranges a player actually orders them at.
##
## Reported as "turning circles do not work" after lane routing landed. The suspicion is
## the three-point turn: [Vehicle] only reverses when the target is **behind and close**
## (`reverse_trigger_distance`, 16m), and a lane route replaces a nearby target with a
## junction waypoint tens of metres away -- so the latch never arms and the car tries to
## come round in one sweep on a two-lane street it cannot turn in.
func _uturns() -> void:
	print("\n--- 2e. TURNING ROUND -----------------------------")
	# **On an empty street.** The first version measured this with the district's
	# twenty-two ambient cars still driving, and the numbers were dominated by queuing:
	# a ten-metre U-turn "took 22 seconds", which is not a turning circle, it is
	# traffic. A manoeuvre has to be measured on its own.
	for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
		if node is TrafficCar:
			node.queue_free()
	await _idle(20)
	print("  %8s %9s %8s %9s %10s" % ["behind", "arrived", "time", "reversed", "widest"])
	# x = 20 is a north-south street; the car faces north and is sent back south.
	for back in [10.0, 25.0, 45.0, 80.0]:
		_car.clear_orders()
		_car.global_position = Vector3(20.0, 0.15, -back * 0.5)
		_car.rotation.y = 0.0          # forward is -Z, i.e. north
		_car.velocity = Vector3.ZERO
		await _idle(30)
		var target := Vector3(20.0, 0.0, back * 0.5)
		_car.issue(MoveOrder.new(target))

		var reversed := false
		var widest := 0.0
		var frames := 0
		while frames < 60 * 45:
			await physics_frame
			frames += 1
			if _car._reversing or _car._escape_time > 0.0:
				reversed = true
			widest = maxf(widest, absf(_car.global_position.x - 20.0))
			if not _car.has_orders():
				break
		print("  %7.0fm %9s %7.1fs %9s %9.1fm" % [
			back, "yes" if not _car.has_orders() else "NO",
			frames / 60.0, "yes" if reversed else "no", widest])


# --- Watching -----------------------------------------------------------------

## Everything the car is touching this frame, and anything it is inside.
func _watch_contacts() -> void:
	for i in _car.get_slide_collision_count():
		var hit := _car.get_slide_collision(i)
		# The ground is not a collision worth reporting. A CharacterBody3D standing on
		# a road registers one every frame, which buried the real contacts under
		# 25,000 frames of "RoadNS_4" in the first run.
		if hit.get_normal().y > 0.7:
			continue
		_hits[_classify(hit.get_collider())] = \
			int(_hits.get(_classify(hit.get_collider()), 0)) + 1

	for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == _car:
			continue
		var gap := _flat(other.global_position - _car.global_position)
		if gap < TOO_CLOSE:
			_interpenetrations.append({"gap": gap, "with": other.display_name,
				"at": _car.global_position})


## How much of the district is actually moving, and who is stuck against what.
func _sample_district() -> void:
	var moving := 0
	var total := 0
	for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
		var traffic := node as TrafficCar
		if traffic == null:
			continue
		total += 1
		if absf(traffic.forward_speed) > 0.3:
			moving += 1
	if total > 0:
		_traffic_samples.append(float(moving) / float(total))

	# A civilian standing still with a vehicle against them is being blocked by it --
	# people mask the player's vehicles, and the vehicles cannot see people at all.
	# The crowd is not in a group; it lives under a container the map generates.
	var crowd := _scene.get_node_or_null("Crowd")
	if crowd == null:
		return
	for other in crowd.get_children():
		var walker := other as Civilian
		if walker == null or walker.velocity.length() >= PED_STILL_SPEED:
			continue
		for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
			var vehicle := node as Vehicle
			if vehicle == null:
				continue
			if _flat(walker.global_position - vehicle.global_position) <= PED_CONTACT:
				_blocked_pedestrians[walker.get_instance_id()] = vehicle.display_name
				break


func _classify(node: Object) -> String:
	if node is TrafficCar:
		return "ambient traffic"
	if node is Vehicle:
		return "another player vehicle"
	if node is Person:
		return "a person on foot"
	var spatial := node as Node
	return "world/scenery (%s)" % (spatial.name if spatial else "?")


## What is around a point, for explaining a stall.
func _describe_surroundings(point: Vector3) -> String:
	var near: Array[String] = []
	for node in _scene.get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Node3D
		if other == null or other == _car:
			continue
		var gap := _flat(other.global_position - point)
		if gap < 8.0:
			near.append("%s %.1fm" % [(other as Unit).display_name, gap])
	return "nothing within 8m" if near.is_empty() else ", ".join(near)


# --- Report -------------------------------------------------------------------

func _report() -> void:
	print("\n--- 3. FINDINGS -----------------------------------")

	print("\n  contacts while driving:")
	if _hits.is_empty():
		print("    none")
	for kind in _hits:
		print("    %-32s %d frames" % [kind, _hits[kind]])

	print("\n  interpenetration (centres closer than %.1fm):" % TOO_CLOSE)
	if _interpenetrations.is_empty():
		print("    none")
	else:
		var worst: Dictionary = _interpenetrations[0]
		for entry in _interpenetrations:
			if float(entry["gap"]) < float(worst["gap"]):
				worst = entry
		print("    %d frames, closest %.2fm with %s"
			% [_interpenetrations.size(), worst["gap"], worst["with"]])

	print("\n  stalls (no progress for %.0fs+):" % STALL_AFTER)
	if _stalls.is_empty():
		print("    none")
	for stall in _stalls:
		print("    %-22s %5.1fs at %s" % [stall["leg"], stall["seconds"],
			str(stall["at"])])
		print("        near: %s" % stall["near"])

	var mean := 0.0
	for sample in _traffic_samples:
		mean += sample
	if not _traffic_samples.is_empty():
		mean /= float(_traffic_samples.size())
	print("\n  held up behind other vehicles: %.1fs" % _held)
	print("\n  caught at crossroads: %.1fs stationary inside a junction box, of %.1fs "
		% [_boxed_in, _junction_frames] + "spent in one")
	print("\n  ambient traffic moving: %.0f%% on average over %d samples"
		% [mean * 100.0, _traffic_samples.size()])

	print("\n  fell out of the world on %d leg(s): %s"
		% [_fell_through.size(), ", ".join(_fell_through) if _fell_through else "none"])
	print("\n  pedestrians found stopped against a vehicle: %d"
		% _blocked_pedestrians.size())
	print("\n===================================================")


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
