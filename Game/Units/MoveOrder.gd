extends Order
class_name MoveOrder

## Drive or walk to a point. Delegates to the unit's navigation, so the same order
## works for anything that can move.
##
## A **vehicle** does not go straight there. The navigation mesh covers the full width
## of every street, so a car left to it drives down the middle and swings across the
## centre line on every bend -- measured on a response, 37% of samples over the line
## and up to 3.9m into the oncoming lane, which is a whole car on the wrong side. So a
## vehicle is routed junction to junction in its own lane, exactly as a returning one
## has been since phase 10; being on a shout is a reason to go *faster*, not a reason
## to drive on the wrong side.
##
## People are unaffected. Pavements are their road rules, and sending someone on foot
## round the lattice would walk them three sides of a block to reach a door opposite.

var point: Vector3

## The lane waypoints, and which one is being driven to. Empty for anything on foot,
## and for a hop too short to be worth routing -- crossing a forecourt, or a target on
## the same stretch of street -- where the mesh's straight line is already the right
## answer and a lattice detour would be absurd.
var _route: Array[Vector3] = []
var _at := 0

## How close counts as having reached a waypoint. Generous: these are points to be
## driven *through*, and braking to a halt at each one would make every journey a
## series of stops.
const WAYPOINT_SWITCH := 7.0

## Streets this journey has given up on, as [method CityGrid.street_key] edges.
var _shut := {}
## Nearest this car has been to what it is currently aiming at, and how long it has
## been no nearer.
var _closest := INF
var _no_progress := 0.0
## Set for one aim after a give-up, so the car is allowed to swing its nose round at a
## waypoint it would normally be made to drive round to.
var _turn_round_next_aim := false

## How long standing still counts as an obstruction rather than a queue.
##
## The ambient fleet has had this since phase 12 and the player's cars never got it, so
## a jam ahead was a jam for the player too: measured driving at a single stationary car
## in a 10m street, the patrol car reversed and retried the same line **nine times in 45
## seconds** and never got past. Six seconds is long enough to sit out a car pulling
## away and short enough that the player sees a decision rather than a stuck unit.
const GIVE_UP_AFTER := 6.0

## Progress is watched as *distance closed*, not as speed -- the same lesson
## [TrafficCar] learned. A car shuffling forward and back under the escape manoeuvre is
## never stationary and never arriving, and a standstill test misses it completely.
const PROGRESS_STEP := 0.5

## How many streets one journey may write off. Enough to go round a block; short of the
## number where a car would tour the district rather than admit it cannot get there.
const MAX_GIVE_UPS := 3

## How long doing another vehicle's speed before this street is worth giving up on.
##
## Shorter than [constant GIVE_UP_AFTER], because being held is unambiguous in a way that
## no-progress is not: a car that cannot get past has already tried and failed to find a
## gap, every frame, for this long.
const HELD_UP_AFTER := 4.0


func _init(target_point: Vector3) -> void:
	point = target_point


func start(unit: Unit) -> void:
	_at = 0
	_route = []
	_shut = {}
	# Lane discipline is about *travelling*; turning round is its own manoeuvre and the
	# motion model already does it well -- a three-point turn, on the spot, inside the
	# width of the street. Routing a U-turn round the lattice instead measured a **25m
	# sweep off a 10m street** where driving straight at it managed 2.6m. So a
	# destination behind the car is driven at, and the car turns round the way a car
	# does.
	if unit is Vehicle and not _turning_round(unit):
		_route = CityGrid.lane_route(unit.global_position, point)
	_aim(unit)


func tick(unit: Unit, _delta: float) -> bool:
	if unit is Vehicle and _watch_progress(unit, _delta):
		return false

	if _route.is_empty():
		# The unit reports its own arrival, including the case where the destination
		# was off the navigation mesh and got clamped to the nearest reachable point.
		return not unit.is_navigating()

	if _at < _route.size() \
			and _flat(unit.global_position - _route[_at]) <= WAYPOINT_SWITCH:
		_at += 1
		_aim(unit)
		return false
	# Out of waypoints and arrived at the last of them: the destination itself.
	if not unit.is_navigating():
		if _at >= _route.size():
			return true
		_at = _route.size()
		_aim(unit)
	return false


func cancel(unit: Unit) -> void:
	unit.stop_navigating()


func destination() -> Vector3:
	return point


func describe() -> String:
	return "Move"


## Watches the car actually closing on whatever it is aiming at, and writes the street
## off when it stops. Returns true if the route was rebuilt this frame, in which case
## the rest of the tick belongs to the old route and should be skipped.
##
## Only vehicles get this. Someone on foot who cannot reach a doorway is standing in a
## crowd, not sitting behind a lorry, and sending them round the block would be daft.
func _watch_progress(unit: Unit, delta: float) -> bool:
	# Swinging the nose round is a manoeuvre, not a stall. The distance to the target
	# *grows* through a three-point turn, so without this a car sent somewhere behind it
	# wrote off the street it was standing on before it had finished setting off.
	# Reset, and it has to be. Swinging the nose round is a manoeuvre rather than a stall,
	# so it must not count towards giving up on the street -- a journey that *begins* with
	# a turn-round would otherwise burn its give-ups before it had set off.
	#
	# The cost is known and unfixed: a car wedged against something it cannot pass escapes
	# roughly once a second, and each escape wipes the tally, so it never gives up at all
	# -- measured at twenty seconds behind two cars abreast with nothing written off and
	# 1.5m of ground lost. Holding the tally instead fixes that and breaks the setting-off
	# case; every cooling rate between the two was tried and none satisfies both, because
	# the two situations look identical from here. It needs a different signal, not a
	# better number. See NEXT.md.
	if (unit as Vehicle).is_turning_round():
		_no_progress = 0.0
		return false
	var aim := point if _at >= _route.size() else _route[_at]
	var gap := _flat(unit.global_position - aim)
	if gap < _closest - PROGRESS_STEP:
		_closest = gap
		_no_progress = 0.0
		return false
	# **Held counts as stuck, not just stopped.** A car crawling behind a taxi is making
	# progress by this measure and always will, so a journey could spend its whole length
	# doing somebody else's speed with the give-up timer resetting every frame. Being held
	# below cruising speed for a while is the same problem wearing a different face.
	if (unit as Vehicle).held_up_for() >= HELD_UP_AFTER:
		_no_progress = 0.0
		return _give_up_on_this_street(unit, aim)
	_no_progress += delta
	if _no_progress < GIVE_UP_AFTER:
		return false
	_no_progress = 0.0
	return _give_up_on_this_street(unit, aim)


## Marks the street the car is sitting on as shut and plans again without it.
##
## The street is named by the two junctions either end -- where the car is, and where
## what it is aiming at lies. Aiming at something on the car's own block says nothing
## about which way is blocked, so the next distinct junction along the route is asked
## instead; a straight drive with no route left has nothing to name and simply carries
## on, which is the old behaviour and no worse than it was.
func _give_up_on_this_street(unit: Unit, aim: Vector3) -> bool:
	# **Only if something is actually in the way.** Getting nowhere and being blocked are
	# not the same thing, and writing off a clear street is far worse than doing nothing:
	# the replan has to go round an obstruction that was never there, and the detours
	# compound. Recorded from play -- a car reversing out of its own escape manoeuvre with
	# `holding behind: nothing` and nothing within 14m wrote off two streets, and its
	# route to a destination 200m **east** became twenty waypoints ending at the far
	# **west** edge of the map. Whatever was wrong with that car, the road was not it.
	if not (unit as Vehicle).road_is_blocked(aim):
		return false
	if _shut.size() >= MAX_GIVE_UPS:
		return false
	var here := CityGrid.junction_at(unit.global_position)
	var ahead := CityGrid.junction_at(aim)
	if ahead == here:
		ahead = _next_junction_along(here)
	if ahead == here or not CityGrid.neighbours(here).has(ahead):
		return false

	_shut[CityGrid.street_key(here, ahead)] = true
	var replanned := CityGrid.lane_route(unit.global_position, point, _shut)
	if replanned.is_empty():
		# Nowhere else to go: unshut it rather than leave the car planning round a
		# street it is going to have to use anyway.
		_shut.erase(CityGrid.street_key(here, ahead))
		return false
	_route = replanned
	_at = 0
	_closest = INF
	# The new route almost always starts back the way the car came, and a car nose-first
	# against an obstruction has no room to come round on the steering alone. Without
	# this it reversed a metre, drove back into the wall and repeated: **0.6m travelled
	# in 60 seconds** with a perfectly good route round the block sitting unused.
	_turn_round_next_aim = true
	_aim(unit)
	return true


## The first junction on the remaining route that is not the one the car is standing at.
func _next_junction_along(here: Vector2i) -> Vector2i:
	for i in range(_at, _route.size()):
		var cell := CityGrid.junction_at(_route[i])
		if cell != here:
			return cell
	# Nothing left on the route, which includes the short hops that never had one. Ask
	# the lattice which way it would set off from here and write that street off, so a
	# car stuck on an unrouted drive gets the same second chance as one on a routed leg.
	var cells := CityGrid.route(here, CityGrid.junction_at(point), _shut)
	return cells[1] if cells.size() > 1 else here


func _aim(unit: Unit) -> void:
	# `final` means "there is no route -- this is a straight drive at the destination",
	# not "the last waypoint of one". A routed journey has already decided which way to
	# go, so the strict waypoint trigger applies the whole way along it including the
	# last leg: giving that leg the generous range let the latch re-arm on the approach
	# and the car weave, and line-keeping went from 9% over the centre back to 36%.
	# A fresh thing to aim at is a fresh chance to make progress towards, so the
	# give-up timer starts again rather than carrying a corner's worth of standstill
	# into the next leg.
	_closest = INF
	_no_progress = 0.0
	var may_turn := _turn_round_next_aim
	_turn_round_next_aim = false
	# People run MoveOrders too -- the vehicle-only corner annotation below must not
	# touch them. Left unguarded it was a Nil write on every officer sent walking, and
	# a runtime error inside a check silently truncates it: seven checks were quietly
	# abandoned while the suite read green, caught only by the SCRIPT ERROR sweep.
	var vehicle := unit as Vehicle
	if _at >= _route.size():
		unit.navigate_to(point, may_turn or _route.is_empty())
		if vehicle:
			vehicle.turn_at_aim = 0.0
	else:
		unit.navigate_to(_route[_at], may_turn)
		if vehicle == null:
			return
		# **Tell the vehicle how hard the route turns at this waypoint.** The corner
		# planner's only other source is the agent's path, which ends at the junction:
		# the turn onto the next street lives in the next waypoint's path and appears
		# only at the 7m switch -- far too late to brake from speed, which is the
		# junction overshoot two F3s from play pinned on the fast cars. The route knows
		# its own geometry exactly, so the angle is computed here, once, from the legs
		# either side of the aim.
		# The turn at the waypoint just passed keeps constraining until the car is
		# through it -- see [member Vehicle.turn_here].
		if _at > 0:
			vehicle.turn_here = vehicle.turn_at_aim
			vehicle.turn_here_at = _route[_at - 1]
		var here := _route[_at - 1] if _at > 0 else unit.global_position
		var beyond := _route[_at + 1] if _at + 1 < _route.size() else point
		var incoming := _route[_at] - here
		var onward := beyond - _route[_at]
		incoming.y = 0.0
		onward.y = 0.0
		var turn := 0.0
		if incoming.length() > 0.5 and onward.length() > 0.5:
			turn = absf(Vector2(incoming.x, incoming.z)
				.angle_to(Vector2(onward.x, onward.z)))
		vehicle.turn_at_aim = turn


## Whether this order is mostly a **turn round** rather than a journey.
##
## Behind the car, and near enough that swinging the nose is most of the work. A long
## drive that merely *begins* behind is still a drive and still wants lane discipline:
## bounding this was not optional -- without the range test a corner-to-corner response
## that happened to start facing the wrong way lost its lane routing for all 250m of
## it, and line-keeping went from 9% over the centre to 58%.
const TURN_ROUND_RANGE := 60.0

func _turning_round(unit: Unit) -> bool:
	var to_point := point - unit.global_position
	to_point.y = 0.0
	var gap := to_point.length()
	if gap < 0.5 or gap > TURN_ROUND_RANGE:
		return false
	return (-unit.global_basis.z).dot(to_point.normalized()) < 0.0


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
