extends Vehicle
class_name TrafficCar

## Ambient traffic. Drives the road grid junction to junction, keeping right, and
## waits for whatever is already in front of it.
##
## Extends [Vehicle] for the motion model and the autopilot; what it adds is a driver.
## Not selectable and offers no abilities -- it is scenery with a steering wheel.
##
## It navigates by [CityGrid] rather than by picking random points on the navigation
## mesh. The mesh covers the full width of every road, so a car following it would
## wander down the middle and meet oncoming traffic head on. Aiming at lane points
## either side of the centre line gives the district traffic that keeps its side,
## which is also what the kit's double yellow line is telling you it should do.

@export_group("Yielding")
## Distance ahead at which another vehicle makes this one wait.
@export var yield_distance := 9.0
## How far off dead ahead still counts as "in front", as a dot product.
@export var yield_cone := 0.65
## Longest a car waits before easing through whatever is in its way. A backstop: the
## direction test in _vehicle_ahead should stop deadlocks forming, and a junction that
## never clears is worse than a moment of overlap between two cars that cannot
## collide with each other anyway.
@export var yield_timeout := 5.0
## How long it ignores obstructions after giving up waiting, so it clears the
## junction instead of stalling again a metre later.
@export var yield_override := 3.0

## Longest a car stays stopped for *any* reason before it gives up on where it was
## going and picks another street. The backstop for solid traffic: a car that has
## been shoved off its lane, wedged on a kerb or parked in by something it cannot
## pass has no way to nose through, so waiting is not a plan.
@export var stall_timeout := 8.0

@export_group("Junctions")
## How far out a car starts watching the crossroads it is driving into.
@export var junction_watch := 13.0
## Inside this of the junction centre a car is **committed**: it stops giving way
## and clears the box. Deliberately tighter than the stop line (JUNCTION_MARGIN, 6m)
## so a car waiting at the line still gives way -- and so nothing ever stops dead in
## the middle of a crossroads, which is the one place a car must not stop.
@export var junction_commit := 4.0

@export_group("Pulling over")
## A responding emergency vehicle this close makes the car pull to the kerb and stop.
@export var pull_over_radius := 16.0
## Seconds of notice a car gets, which is what actually decides the warning distance --
## `pull_over_radius` is only the floor for a responder crawling. Two seconds is enough to
## reach the kerb from the lane; at full speed that is fifty metres of warning.
@export var pull_over_notice := 2.0
## How far past [member pull_over_radius] the responder has to be before the car
## noses back into its lane. The gap is hysteresis: without it a responder sitting
## right on the boundary flicks the car in and out of the manoeuvre every scan.
@export var pull_over_release := 1.4
## Longest a car will sit at the kerb before rejoining the road regardless.
##
## Without this the tuck has **no way out but distance**, and a player who patrols the
## same streets with the lightbar on is never far enough away: measured, cars pulled
## over went 1, 3, 5, 6, 7 over seventy seconds and never came back, while the number
## still moving fell from 21 to 16. Every car the patrol car passed tucked in and
## stayed tucked, and once they are solid the next one to tuck arrives at an occupied
## kerb and stops at an angle across the lane -- which is the pile-up this was reported
## as. A responder is *passing*, not parking, so a tuck is a manoeuvre with an end.
@export var pull_over_max := 7.0
## After rejoining, this long before the same car will tuck again. Stops a car parked
## beside the kerb thrashing in and out of the manoeuvre for as long as it is there.
@export var pull_over_cooldown := 6.0
## How much further right of the lane the car tucks itself. The lane already sits
## CityGrid.LANE_OFFSET from the centre line; this asks for the kerb itself, and the
## navigation mesh -- inset by the vehicle agent radius -- clamps it to what fits.
@export var kerb_tuck := 2.2
## How far up the road a raised cordon is noticed, short enough that a closure two streets
## away is somebody else's problem.
## Far enough that the turn itself does not carry the car into the cones: deciding at 26m
## and then three-point turning at ten metres a second put it 2.7m from the middle of a
## 6m ring. A third of a block's notice leaves room to slow first.
@export var cordon_watch := 34.0
## And how long before the same car will react to one again, so a car mid-turn does not
## see the cordon it is turning away from and start over.
@export var cordon_patience := 6.0

@export_group("Route")
## Stops this far short of the junction centre, which puts it at the stop line rather
## than in the middle of the crossroads.
@export var junction_margin := CityGrid.JUNCTION_MARGIN
## Where the lane is picked up again on the far side of a junction. A leg is driven as
## two waypoints -- this one, then the stop line at the end of the street -- and the
## first is what holds a car to its own side coming out of a turn.
@export var entry_distance := CityGrid.ENTRY_DISTANCE
## How close counts as having passed the entry waypoint. It is a point to be driven
## through rather than stopped at, so this is generous.
@export var waypoint_switch := 6.0

## True while stopped for traffic. Public so a test can assert the yield rather than
## infer it from a speed that might be zero for some other reason.
var is_yielding := false
## True while tucked in at the kerb for a passing response. Public for the same
## reason is_yielding is.
var is_pulled_over := false
## The arrive radius to put back once the pull-over is done with its tighter one.
var _normal_arrive := 0.0
## Seconds this car has been at the kerb, and how long before it may tuck again.
var _tuck_time := 0.0
var _tuck_cooldown := 0.0

## Junction just left, and the one being driven to.
var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _destination := Vector3.ZERO
## The current leg -- [apex?, entry, stop line] -- and which point is being driven to.
var _route: Array[Vector3] = []
var _waypoint := 0
## Direction the previous leg was driven, for deciding whether the next one starts
## with a left turn. ZERO until the first leg has been driven.
var _last_direction := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _yield_time := 0.0
var _override_time := 0.0
## The closest this car has got to its current waypoint, and how long it has been
## since that improved. Progress, not speed: a wedged car shuffles about forever.
var _closest_yet := INF
var _no_progress := 0.0
## Seconds before this car will heed a cordon again.
var _cordon_cooldown := 0.0


## The paint shop the ambient fleet draws from -- the same alt palettes the parked
## cars use. The pack paints every body off the shared 01_A atlas, which is why an
## untreated street is a procession of blue vans. "" keeps the shipped colour.
const PALETTES: Array[String] = [
	"",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_B_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_C_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_02_A_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_03_A_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_04_A_mat.tres",
]


func _ready() -> void:
	super()
	# Traffic queues rather than overtakes: the give-way rules below are the whole
	# of its road sense, and a taxi swinging into the oncoming lane to get past a
	# bus would be the district driving like an emergency.
	avoids_vehicles = false
	# Its legs are waypoints in all but name -- navigate_to(_destination) is the next
	# junction, not the end of a journey -- so it keeps the strict trigger. A taxi
	# three-point-turning in the middle of a street is not what the district wants.
	turn_round_range = reverse_trigger_distance
	_rng.seed = hash(name) ^ hash(global_position)
	_repaint()
	# Works out its own route from where it was parked, so build_map.gd only has to
	# put it on a road pointing the right way.
	_from = CityGrid.junction_at(global_position)
	_to = _choose_next(_from, _from)
	_begin_leg()


## Folds this car's body surfaces through a seeded palette, at runtime, so the
## district's traffic mixes colours without regenerating the vehicle scenes.
## Taxis keep their livery, and only surfaces wearing the stock 01_A body material
## are touched -- glass, plates and wheels stay themselves.
func _repaint() -> void:
	# Its own generator, deliberately: drawing the colour from the routing RNG
	# shifted every car's route sequence, and a layout the deadlock test had proven
	# clean started stalling. Paint must not steer.
	var paint := RandomNumberGenerator.new()
	paint.seed = hash(name) + 7
	var palette := PALETTES[paint.randi() % PALETTES.size()]
	if palette == "":
		return
	var coat := load(palette) as Material
	if coat == null:
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var body := node as MeshInstance3D
		if body.mesh == null:
			continue
		if "Taxi" in body.mesh.resource_path:
			return
		for i in body.mesh.get_surface_count():
			var active := body.get_active_material(i)
			if active and "PolygonCity_01_A" in active.resource_path:
				body.set_surface_override_material(i, coat)


func is_selectable() -> bool:
	return false


## No verbs, and no seats either (see build_vehicles.gd) -- without both, an officer
## right-clicking a passing taxi would try to get in.
func _build_abilities() -> Array[Ability]:
	return []


func _update_movement(delta: float) -> void:
	_drive()
	super(delta)


func _drive() -> void:
	var delta := get_physics_process_delta_time()
	_override_time = maxf(_override_time - delta, 0.0)

	# Blues coming through outrank everything else the driver is doing: tuck in at
	# the kerb, wait for them to pass, then rejoin the lane.
	if _update_pull_over(delta):
		return

	# **A cordon is an instruction.** An officer putting cones across a scene is telling
	# the traffic to go another way, and until this only the crowd listened -- cars queued
	# into the closure and sat there, because the cones are visual and nothing blocks them.
	# Turning back is the honest response: the street ahead is shut, so take it the other
	# way rather than wait for something that is not going to move.
	_cordon_cooldown = maxf(_cordon_cooldown - delta, 0.0)
	if _cordon_cooldown <= 0.0 and _cordon_ahead() != null:
		_cordon_cooldown = cordon_patience
		_turn_back()
		return

	# Getting nowhere, for any reason at all -- watched as *progress*, not as speed.
	# The yield only knows about cars this one chose to wait for, and a standstill
	# check misses the worst case: a car wedged against scenery shuffles forward and
	# back under the escape manoeuvre forever, never stopped and never arriving.
	var gap := _flat_distance(_destination)
	if gap < _closest_yet - 0.5:
		_closest_yet = gap
		_no_progress = 0.0
	else:
		_no_progress += delta
		if _no_progress >= stall_timeout:
			_reroute()
			return

	var blocked := _override_time <= 0.0 and (_vehicle_ahead() or _junction_taken())
	if blocked:
		_yield_time += delta
		if _yield_time >= yield_timeout:
			# Waited long enough that this is an obstruction rather than a queue.
			# Solid cars cannot nose through one another, so the answer is another
			# street rather than another few seconds.
			_reroute()
			blocked = false
	else:
		_yield_time = 0.0

	if blocked != is_yielding:
		is_yielding = blocked
		# Handing the destination back and forth rather than reaching into the motion
		# model: a Vehicle with nothing to navigate to brakes and parks itself, which
		# is exactly the behaviour wanted here.
		if blocked:
			stop_navigating()
		else:
			navigate_to(_destination)
		return

	if is_yielding:
		return

	# Waypoints before the stop line are driven *through*, not stopped at. Switching
	# early keeps the car rolling, and -- the point of having them at all -- keeps it
	# aiming at something a few metres ahead in its own lane rather than at the far
	# end of the street. Aiming only at the far end, a car leaving a turn wide
	# corrected over thirty metres, which meant driving most of the block on the
	# oncoming side.
	if _waypoint < _route.size() - 1 and _flat_distance(_destination) <= waypoint_switch:
		_waypoint += 1
		_aim()
		return

	if is_navigating():
		return

	# Arrived at the stop line. Turn onto the next leg, preferring not to double back.
	var previous := _from
	_from = _to
	_to = _choose_next(_from, previous)
	_begin_leg()


## Runs the pull-over manoeuvre while a response is passing. Returns true while it
## owns the car -- entering, waiting at the kerb, or until the responder is clear.
func _update_pull_over(delta: float) -> bool:
	_tuck_cooldown = maxf(_tuck_cooldown - delta, 0.0)
	if is_pulled_over:
		_tuck_time += delta
	var responder := _responder_near(
		pull_over_radius * (pull_over_release if is_pulled_over else 1.0))
	# Long enough at the kerb is its own reason to leave. A responder is passing, not
	# parking, and a tuck that only ends on distance never ends for a player who works
	# the same streets -- the cars stack up at the kerb and the district silts up.
	if is_pulled_over and _tuck_time >= pull_over_max:
		_release_tuck()
		return false
	if responder and not is_pulled_over:
		if _tuck_cooldown > 0.0:
			return false
		_tuck_time = 0.0
		is_pulled_over = true
		# Handing back whatever the yield logic was doing: the kerb is the new plan.
		is_yielding = false
		_yield_time = 0.0
		# The usual arrive radius is generous -- right for a stop line, wrong here:
		# stopping 2m from the kerb point is most of the tuck not happening.
		_normal_arrive = arrive_radius
		arrive_radius = 1.0
		_agent.target_desired_distance = 1.0
		var forward := -global_basis.z
		forward.y = 0.0
		if forward.length() > 0.01:
			forward = forward.normalized()
			# Well ahead and to the right, so the car noses in over a car length or
			# two rather than crabbing sideways.
			navigate_to(global_position + forward * 7.0
				+ forward.cross(Vector3.UP) * kerb_tuck)
	elif responder == null and is_pulled_over:
		_release_tuck()
	return is_pulled_over


## Back into the road: the arrive radius the car normally uses, its route re-aimed, and
## a cooldown so a responder still sitting nearby cannot pull it straight back in.
func _release_tuck() -> void:
	if not is_pulled_over:
		return
	is_pulled_over = false
	_tuck_time = 0.0
	_tuck_cooldown = pull_over_cooldown
	arrive_radius = _normal_arrive
	_agent.target_desired_distance = _normal_arrive
	_aim()


## The nearest player emergency vehicle on the move under a response, within
## [param radius] -- or null. Ambient traffic has no service, so nothing here ever
## reads another taxi as a reason to stop.
func _responder_near(radius: float) -> Vehicle:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other is TrafficCar or other.service == Unit.Service.NONE:
			continue
		if not other.is_navigating() or not other.is_responding():
			continue
		var offset := other.global_position - global_position
		offset.y = 0.0
		# **Warning scaled to how fast it is coming.** A flat 16m is two thirds of a
		# second at 25 m/s: the car began tucking when the responder was already on top of
		# it, never cleared the lane in time, and the response spent the pass crawling
		# behind it. Notice is time, not distance.
		var warning := maxf(radius, absf(other.forward_speed) * pull_over_notice)
		if offset.length() > warning:
			continue
		# And only for one that is actually coming *this* way. At 16m the direction hardly
		# mattered; at fifty it decides whether half a street tucks for a response that
		# has already gone by.
		var coming := -other.global_basis.z
		coming.y = 0.0
		if offset.length() > radius and coming.dot(-offset.normalized()) <= 0.2:
			continue
		return other
	return null


## Lays out the waypoints for the current leg: an apex through the crossroads when
## the leg starts with a left turn, back into lane on the far side of the junction
## being left, then the stop line at the junction being driven to. Traffic keeps
## right, so the lane points are offset to the right of the direction of travel.
func _begin_leg() -> void:
	var start := CityGrid.junction(_from)
	var end := CityGrid.junction(_to)
	var direction := (end - start).normalized()
	var lane := direction.cross(Vector3.UP) * CityGrid.LANE_OFFSET
	_route = []
	# The left-turn apex keeps the car on its own side of the crossroads instead of
	# chording across the oncoming lanes -- see CityGrid.turn_apex.
	var apex := CityGrid.turn_apex(start, _last_direction, direction)
	if apex != Vector3.ZERO:
		_route.append(apex)
	_route.append(start + direction * entry_distance + lane)
	_route.append(end - direction * junction_margin + lane)
	_last_direction = direction

	# A car that spawned mid-block is already past the early waypoints, and aiming at
	# one would send it back the way it came.
	_waypoint = 0
	while _waypoint < _route.size() - 1 \
			and (global_position - _route[_waypoint]).dot(direction) > 0.0:
		_waypoint += 1
	_aim()


func _aim() -> void:
	_destination = _route[_waypoint]
	navigate_to(_destination)
	# A new waypoint is a fresh chance to make progress towards.
	_closest_yet = INF
	_no_progress = 0.0


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _choose_next(cell: Vector2i, avoid: Vector2i) -> Vector2i:
	var options := CityGrid.neighbours(cell)
	var onward: Array[Vector2i] = []
	for option in options:
		if option != avoid:
			onward.append(option)
	# Doubling back is allowed only from a dead end, which this grid does not have --
	# but the fallback keeps a car off the map edge from stalling if it ever does.
	var pool := onward if not onward.is_empty() else options
	return pool[_rng.randi() % pool.size()]


## A raised cordon standing on the road ahead, or null.
##
## Only the ones actually in the way: a cordon behind, beside, or further off than
## [member cordon_watch] is not this driver's business, and a district where every car
## reacted to every cordon would empty the streets around a scene rather than divert them.
func _cordon_ahead() -> Cordon:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return null
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	for node in get_tree().get_nodes_in_group(Cordon.GROUP):
		var cordon := node as Cordon
		if cordon == null or not cordon.raised:
			continue
		var offset := cordon.global_position - global_position
		offset.y = 0.0
		var ahead := forward.dot(offset)
		if ahead <= 0.0 or ahead > cordon_watch:
			continue
		if absf(right.dot(offset)) > cordon.radius:
			continue
		return cordon
	return null


## Turns the car round and sends it back the way it came.
##
## Not [method _reroute], which deliberately refuses to double back -- right when a street
## is merely busy, wrong when it is closed, because the only way out of a closure is the
## way in. The motion model does the turn itself: a [TrafficCar] keeps the strict reverse
## trigger, so this is a three-point turn inside the width of the street rather than a
## sweep across it.
func _turn_back() -> void:
	var here := CityGrid.junction_at(global_position)
	var heading := -global_basis.z
	heading.y = 0.0
	var step := CityGrid.street_direction(heading)
	var behind := here - Vector2i(int(signf(step.x)), int(signf(step.z)))
	if step == Vector3.ZERO or behind == here or not CityGrid.in_bounds(behind):
		_reroute()
		return
	is_yielding = false
	_yield_time = 0.0
	_override_time = yield_override
	_from = here
	_to = behind
	_last_direction = Vector3.ZERO
	_begin_leg()


## Gives up on the current street and takes another one.
##
## Re-anchors to the nearest junction first, which is the recovery half: a car that
## has been pushed off its lane -- and with solid traffic they do get pushed -- would
## otherwise keep driving the leg it was on from wherever it ended up.
func _reroute() -> void:
	_yield_time = 0.0
	_override_time = yield_override
	is_yielding = false
	_from = CityGrid.junction_at(global_position)
	_to = _choose_next(_from, _to)
	_last_direction = Vector3.ZERO
	_begin_leg()


## Gives way at the crossroads, which is what makes solid cars survivable: without
## it two cars on crossing streets each ignore the other -- the follow rule below
## deliberately only sees traffic going the *same* way -- and they meet in the box.
##
## The rule is a **strict total order**: give way to any approaching car nearer the
## junction than this one, ties broken by instance id. In any group of cars exactly
## one is nearest, so exactly one is waiting for nobody, and a cycle of "after you"
## cannot form -- which is the deadlock that kept these cars ghosts for months.
## Anything already inside the box has right of way outright, because it is in the
## worst possible place to be asked to stop.
func _junction_taken() -> bool:
	var centre := CityGrid.junction(_to)
	var mine := _flat_distance(centre)
	if mine > junction_watch or mine < junction_commit:
		return false

	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var theirs := Vector2(other.global_position.x - centre.x,
			other.global_position.z - centre.z).length()
		if theirs > junction_watch:
			continue
		# In the box: let them clear it, whichever way they are pointing.
		if theirs < junction_commit:
			return true
		# **One of the player's, anywhere in the watch radius: give way to it.** This
		# scan read `node as TrafficCar` until August 2026, which made the player's
		# vehicles invisible to the give-way rule -- the follow rule beside it had always
		# yielded to them "whatever way they face", and this one silently did not. So at a
		# crossroads neither side gave way: the taxi could not see the patrol car and the
		# patrol car has no give-way of its own, and they met in the middle.
		#
		# Priority rather than the distance ordering used between taxis, because that is
		# what the vehicle is. A car sitting in the box forever cannot lock the district:
		# `yield_timeout` gives up on the wait and takes another street.
		# **Only if it is actually going somewhere.** Giving way to a stopped emergency
		# vehicle achieves nothing -- it is not crossing the junction -- and it deadlocks
		# the box: recorded from play at one crossroads, a fire engine at full throttle
		# and zero speed with two taxis stopped either side of it, both yielding to the
		# engine, the engine blocked by them, and an ambulance queued behind the lot.
		# Priority is for a unit on the move; a stationary one is just an obstacle, and
		# the follow rule already knows how to queue behind an obstacle.
		if not (other is TrafficCar):
			if absf(other.forward_speed) < 0.5:
				continue
			return true
		var towards := centre - other.global_position
		towards.y = 0.0
		var facing := -other.global_basis.z
		facing.y = 0.0
		# Already through and driving away -- not a conflict, and waiting for them
		# to clear the watch radius would stall every junction in the district.
		if facing.dot(towards) <= 0.0:
			continue
		if theirs < mine or (is_equal_approx(theirs, mine)
				and other.get_instance_id() < get_instance_id()):
			return true
	return false


## True if another vehicle is close and roughly in front.
##
## Deliberately a group scan rather than a physics probe. A ray would also catch the
## buildings a car turns towards on the way round a junction, and stopping for those
## would gridlock every corner in the district.
##
## Traffic yields to other traffic only when it is going roughly the *same way*.
## Without that, two cars meeting at a crossroads each hold the other inside a 45
## degree forward cone, both stop, and neither ever moves again -- which fills every
## junction in the district with parked taxis and queues the rest up behind them.
## Queueing behind someone is the case worth handling here; crossing paths is already
## handled by traffic not colliding with traffic.
##
## The player's vehicles are yielded to whatever way they face, so an emergency
## vehicle stopped at a scene is driven around rather than through.
func _vehicle_ahead() -> bool:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	forward = forward.normalized()

	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var offset := other.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > yield_distance or distance < 0.01:
			continue
		if forward.dot(offset / distance) <= yield_cone:
			continue
		if other is TrafficCar:
			var heading := -other.global_basis.z
			heading.y = 0.0
			if heading.length() < 0.01 or forward.dot(heading.normalized()) < 0.5:
				continue
		return true
	return false
