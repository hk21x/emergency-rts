extends RefCounted
class_name CityGrid

## The district's layout, in one place.
##
## `build_map.gd` lays the city out from these numbers, and the ambient traffic and
## pedestrians navigate by them. Sharing them is the whole point: a civilian's idea of
## where the pavement is comes from the same constants that put the pavement there,
## and a traffic car's idea of where a junction is comes from the same constants that
## laid the road. Neither can drift from the map the way a hand-written waypoint list
## would.
##
## Everything here is static. There is one district and it is a rectilinear grid, so a
## table of nodes would be strictly more to keep in sync than these tables.

## Whether the loaded map actually IS the district these tables describe. True for
## the generated Playground; the hand-authored tutorial town sets it false on entry
## (and restores it on exit) via its TutorialSetup node. Every consumer whose answer
## would be a confident lie on a foreign map guards on this -- the tables themselves
## never change, so the suite's ~200 pins on them are untouched.
static var lattice_fits := true

const TILE := 5.0
## Tiles per side. 52 x 5m = a 260m square.
const GRID := 52
## Width of a road band, in tiles. Two tiles is one lane each way.
const ROAD_WIDTH := 2

## First tile of each road band, per axis. **Deliberately irregular**: the spacing is
## what makes blocks 30m in one place and 50m in another, so the district reads as a
## city that grew rather than a grid that was stamped. Both tables start at 0 and end
## at GRID - ROAD_WIDTH, which is what keeps a road on all four map edges.
##
## Everything below derives from these two tables. Change a number here and the roads,
## the blocks, the junction lattice, the addresses, the traffic and the strolling
## crowd all move together.
const X_BANDS: Array[int] = [0, 9, 21, 29, 38, 50]
const Z_BANDS: Array[int] = [0, 10, 21, 29, 40, 50]

## Road bands per axis. Both tables are the same length on purpose -- the routing
## lattice is square even though the spacing is not.
const BANDS := 6
## Blocks per axis: one fewer than the bands that separate them.
const BLOCKS := BANDS - 1
## World x/z of tile 0's near corner. Centres the grid on the origin.
const ORIGIN := -GRID * TILE * 0.5
const MAP_HALF := GRID * TILE * 0.5

## Blocks laid out as public parks: grass, paths, trees, benches. Their interiors are
## walkable and belong in [method pavement_points], so the crowd strolls through them
## and a freeplay medical call can open on the lawn.
const PARKS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 3)]

## Shortest journey worth routing junction to junction rather than driving straight at.
##
## Just above the range a car turns round in on the spot (Vehicle's
## `reverse_trigger_distance`, 16m), and the two have to meet: between them lies a band
## where a vehicle neither three-point-turns nor routes via a crossroads, and it does
## not merely take longer there -- it *sweeps*. Measured at 25m behind with this set to
## 40, a U-turn swung **25 metres off a 10m street** and took longer than the same turn
## at 45m. Below this the mesh's straight line is right, and it is also what the player
## clicked: an 8m nudge routed round a junction is a detour, not tidier driving.
const LANE_ROUTE_MIN := 40.0

## Centre of one lane, out from its road band's centre line. Bands are two tiles
## wide, so this sits a car in the middle of its own half of the road.
const LANE_OFFSET := 2.5
## Stop this far short of a junction centre, which puts a car at the stop line rather
## than in the middle of the crossroads.
const JUNCTION_MARGIN := 6.0
## Where the lane is picked up again on the far side of a junction. A street is driven
## as two waypoints -- this one, then the stop line at the end -- and the first is what
## holds a car to its own side coming out of a turn.
const ENTRY_DISTANCE := 9.0

## The four grid steps, typed so iterating them does not fall back to Variant.
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## True if a tile column falls inside a north-south road band (an avenue).
static func is_road_x(index: int) -> bool:
	for start in X_BANDS:
		if index >= start and index < start + ROAD_WIDTH:
			return true
	return false


## True if a tile row falls inside an east-west road band (a street).
static func is_road_z(index: int) -> bool:
	for start in Z_BANDS:
		if index >= start and index < start + ROAD_WIDTH:
			return true
	return false


## Whether a world position is on the carriageway rather than the pavement.
##
## Asked of the **grid**, not of the navigation mesh. The mesh cannot answer it: both
## regions live on the same navigation map, and `map_get_closest_point` takes no layer
## filter, so it hands back a pavement point as readily as a road one -- 0.00m away, when
## measured. Code that used it to mean "still on the road" was getting a yes for anywhere
## a person could stand, and had been since the pavements were first baked.
static func is_road(point: Vector3) -> bool:
	var tile := tile_at(point)
	return is_road_x(tile.x) or is_road_z(tile.y)


## Centre of a grid tile, in world space.
static func tile_centre(col: int, row: int) -> Vector3:
	return Vector3(ORIGIN + TILE * (col + 0.5), 0.0, ORIGIN + TILE * (row + 0.5))


## Which grid tile a world position falls in. The inverse of [method tile_centre], and
## the thing to ask before [method walkable] about somewhere a person might step.
static func tile_at(point: Vector3) -> Vector2i:
	return Vector2i(int(floorf((point.x - ORIGIN) / TILE)),
		int(floorf((point.z - ORIGIN) / TILE)))


## Centre line of avenue [param band], in world x.
static func band_centre_x(band: int) -> float:
	return ORIGIN + TILE * (X_BANDS[band] + ROAD_WIDTH * 0.5)


## Centre line of street [param band], in world z.
static func band_centre_z(band: int) -> float:
	return ORIGIN + TILE * (Z_BANDS[band] + ROAD_WIDTH * 0.5)


## Which avenue a world x is nearest. Nearest, not containing: most points are in the
## middle of a block, and "which avenue" is how an address answers that.
static func band_at_x(value: float) -> int:
	return _nearest(value, X_BANDS)


static func band_at_z(value: float) -> int:
	return _nearest(value, Z_BANDS)


static func _nearest(value: float, bands: Array[int]) -> int:
	var best := 0
	var closest := INF
	for i in bands.size():
		var centre := ORIGIN + TILE * (bands[i] + ROAD_WIDTH * 0.5)
		if absf(value - centre) < closest:
			closest = absf(value - centre)
			best = i
	return best


## First block tile of block column [param bx] / row [param bz].
static func block_base_x(bx: int) -> int:
	return X_BANDS[bx] + ROAD_WIDTH


static func block_base_z(bz: int) -> int:
	return Z_BANDS[bz] + ROAD_WIDTH


## Tiles across block column [param bx]. Varies from 6 to 10 -- see X_BANDS.
static func block_span_x(bx: int) -> int:
	return X_BANDS[bx + 1] - X_BANDS[bx] - ROAD_WIDTH


static func block_span_z(bz: int) -> int:
	return Z_BANDS[bz + 1] - Z_BANDS[bz] - ROAD_WIDTH


## Centre of a block, in world space.
static func block_centre(bx: int, bz: int) -> Vector3:
	return Vector3(
		ORIGIN + TILE * (block_base_x(bx) + block_span_x(bx) * 0.5), 0.0,
		ORIGIN + TILE * (block_base_z(bz) + block_span_z(bz) * 0.5))


## Centre of the crossroads where avenue [param cell].x meets street [param cell].y.
static func junction(cell: Vector2i) -> Vector3:
	return Vector3(band_centre_x(cell.x), 0.0, band_centre_z(cell.y))


## Nearest junction to a world position, as lattice indices.
static func junction_at(point: Vector3) -> Vector2i:
	return Vector2i(band_at_x(point.x), band_at_z(point.z))


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < BANDS and cell.y >= 0 and cell.y < BANDS


## The up-to-four junctions one block away.
static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for step in STEPS:
		var next := cell + step
		if in_bounds(next):
			found.append(next)
	return found


## Names the street between two neighbouring junctions, the same way round whichever
## way it is driven. A blockage is a property of the road, not of the direction someone
## met it in, so the low end always comes first -- otherwise a driver that gave up going
## north would happily plan straight back down the same street going south.
static func street_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		return Vector4i(b.x, b.y, a.x, a.y)
	return Vector4i(a.x, a.y, b.x, b.y)


## Shortest way through the street grid, as junctions, including both ends.
##
## Breadth-first over the 6x6 lattice, which is small enough that anything cleverer
## would be showing off. Returns empty if either end is off the grid.
##
## This is what lets a car be routed *along the streets* rather than left to the
## navigation mesh, which covers the full width of every road and so has no opinion
## about which side of it to drive on.
##
## [param shut] names streets the caller has decided it cannot use -- a driver that has
## sat behind something immovable and given up on that block. Keys are [method street_key]
## edges, and only the key matters; the value is ignored. The search simply refuses to
## cross them, so it comes back with a way *round* rather than the same way again.
static func route(from: Vector2i, to: Vector2i, shut := {}) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not in_bounds(from) or not in_bounds(to):
		return path
	if from == to:
		path.append(from)
		return path

	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == to:
			break
		for next in neighbours(cell):
			if came.has(next):
				continue
			if shut.has(street_key(cell, next)):
				continue
			came[next] = cell
			queue.append(next)

	if not came.has(to):
		return path
	var walk := to
	while walk != from:
		path.append(walk)
		walk = came[walk]
	path.append(from)
	path.reverse()
	return path


## Tile centres of everywhere people on foot belong: every block's sidewalk ring, plus
## the whole interior of each park. Computed rather than stored so it stays true if
## the band tables above change.
static func pavement_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for bz in BLOCKS:
		for bx in BLOCKS:
			var base_col := block_base_x(bx)
			var base_row := block_base_z(bz)
			var span_x := block_span_x(bx)
			var span_z := block_span_z(bz)
			var park := PARKS.has(Vector2i(bx, bz))
			for bc in span_x:
				for br in span_z:
					var ring := bc == 0 or bc == span_x - 1 \
						or br == 0 or br == span_z - 1
					if ring or park:
						points.append(tile_centre(base_col + bc, base_row + br))
	return points


# --- The pedestrian graph ----------------------------------------------------
#
# People on foot get the same discipline traffic has: the navigation mesh covers the
# roads, but where a pedestrian *belongs* is the pavement, and the only way across a
# road is the painted crossing. These helpers are that rule, in tile space, so the
# crowd and the map can never disagree about where the zebras are.

## Which block a tile belongs to, or (-1, -1) for a road tile.
static func block_of(col: int, row: int) -> Vector2i:
	if col < 0 or col >= GRID or row < 0 or row >= GRID \
			or is_road_x(col) or is_road_z(row):
		return Vector2i(-1, -1)
	var bx := -1
	for i in BLOCKS:
		if col >= block_base_x(i) and col < block_base_x(i) + block_span_x(i):
			bx = i
			break
	var bz := -1
	for i in BLOCKS:
		if row >= block_base_z(i) and row < block_base_z(i) + block_span_z(i):
			bz = i
			break
	return Vector2i(bx, bz)


## True if avenue tiles in row [param row] carry the zebra paint -- the road tile
## rows flanking each junction, exactly where build_map lays the crossing pieces.
static func crossing_row(row: int) -> bool:
	return not is_road_z(row) and (is_road_z(row - 1) or is_road_z(row + 1))


static func crossing_col(col: int) -> bool:
	return not is_road_x(col) and (is_road_x(col - 1) or is_road_x(col + 1))


## True if [param col],[param row] is a tile a pedestrian may stand on: any block
## tile, or a road tile carrying a crossing. The inside of a junction is nobody's.
## Whether anyone could actually stand on a tile: the carriageway, a block's pavement
## ring, or a park's lawn — but **not inside a building**.
##
## Not to be confused with [method walkable], which is the pedestrian *graph's* question
## and means only "not in the middle of the road". That one says yes to a building's
## footprint, which is exactly the wrong answer for anything asking whether a place can be
## reached: a fire placed on a `walkable` tile can be inside a warehouse.
static func standable(col: int, row: int) -> bool:
	if is_road_x(col) or is_road_z(row):
		return true
	var block := block_of(col, row)
	if not in_bounds(block):
		return false
	if PARKS.has(block):
		return true
	# The outermost ring of tiles is the pavement; everything within it is the building.
	var base_x := block_base_x(block.x)
	var base_z := block_base_z(block.y)
	return col == base_x or col == base_x + block_span_x(block.x) - 1 \
		or row == base_z or row == base_z + block_span_z(block.y) - 1


static func walkable(col: int, row: int) -> bool:
	var road_x := is_road_x(col)
	var road_z := is_road_z(row)
	if not road_x and not road_z:
		return true
	if road_x and road_z:
		return false
	return crossing_row(row) if road_x else crossing_col(col)


## Legal pedestrian moves from a walkable block tile: the adjacent tiles of the same
## block's sidewalk ring (anywhere inside it for a park), plus -- where the flanking
## road carries a crossing -- the facing kerb tile across the road. One hop over a
## crossing is a single move, so nobody loiters in the carriageway.
static func walk_moves(col: int, row: int) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var here := block_of(col, row)
	if here.x < 0:
		return moves
	var park := PARKS.has(here)
	for step in STEPS:
		var next := Vector2i(col + step.x, row + step.y)
		if block_of(next.x, next.y) != here:
			continue
		if park or _on_ring(next.x, next.y, here):
			moves.append(next)
	if crossing_row(row):
		for direction in [-1, 1]:
			if is_road_x(col + direction):
				var far := Vector2i(col + direction * (ROAD_WIDTH + 1), row)
				if block_of(far.x, far.y).x >= 0:
					moves.append(far)
	if crossing_col(col):
		for direction in [-1, 1]:
			if is_road_z(row + direction):
				var far := Vector2i(col, row + direction * (ROAD_WIDTH + 1))
				if block_of(far.x, far.y).x >= 0:
					moves.append(far)
	return moves


static func _on_ring(col: int, row: int, block: Vector2i) -> bool:
	var bc := col - block_base_x(block.x)
	var br := row - block_base_z(block.y)
	return bc == 0 or bc == block_span_x(block.x) - 1 \
		or br == 0 or br == block_span_z(block.y) - 1


## Where a car turning at a crossroads should pass through it, or ZERO when no
## extra waypoint is needed.
##
## A **left** turn is the problem case: the chord from the stop line to the exit
## lane cuts diagonally across the oncoming halves of both streets, which is what a
## taxi on the wrong side of the yellow line mid-junction looks like. The apex pulls
## the path to the driver's own side of the junction centre -- right of the incoming
## direction *and* right of the outgoing one -- so the car goes around the middle of
## the crossroads rather than across it. A right turn already hugs its own corner,
## and straight-on has no corner at all: both return ZERO.
static func turn_apex(junction_point: Vector3, incoming: Vector3,
		outgoing: Vector3) -> Vector3:
	# Seen from above, a left turn's outgoing direction is a quarter-turn
	# anticlockwise from its incoming one, which the cross product's y signs.
	if incoming.cross(outgoing).y < 0.5:
		return Vector3.ZERO
	var pull := LANE_OFFSET * 0.8
	return junction_point \
		+ incoming.cross(Vector3.UP).normalized() * pull \
		+ outgoing.cross(Vector3.UP).normalized() * pull


## Yaw that points a unit's forward (-Z) along [param direction].
static func heading(direction: Vector3) -> float:
	return atan2(direction.x, direction.z) + PI


# --- Addresses ---------------------------------------------------------------
#
# Six road bands per axis, so the district has six avenues and six streets and every
# point in it has an address. That is the difference between a call reading
# "Casualty -- 2nd & Oak" and one reading "Casualty at (18, 0, -37)".
#
# Avenues run north-south (they vary in x); streets run east-west (they vary in z).

## Indexed by x band.
const AVENUES := ["1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave", "6th Ave"]
## Indexed by z band.
const STREETS := ["Elm St", "Oak St", "Pine St", "Cedar St", "Maple St", "Birch St"]


## Nearest crossroads to a point, as a street address.
##
## Nearest rather than exact on purpose: most things happen partway down a block, and
## "2nd & Oak" is how anyone would actually describe that over a radio.
static func place_name(point: Vector3) -> String:
	var cell := junction_at(point)
	return "%s & %s" % [AVENUES[cell.x], STREETS[cell.y]]


## A route between two points that **keeps to its own side of the road**, as waypoints.
##
## The navigation mesh covers the full width of every street, so a vehicle left to it
## drives down the middle and cuts the corners off junctions. This routes junction to
## junction instead -- two waypoints per street, offset right of the direction of
## travel, with an apex through any crossroads the leg turns left at.
##
## Lifted here out of [ReturnOrder], which had it first and had it alone: for a long
## time only a vehicle *going home* drove in lane, and anything on a shout was left to
## the mesh. Measured on a response, that was **37% of samples over the centre line and
## up to 3.9m into the oncoming lane** -- worse than the 18% the mesh gives a slower
## car, because a responder carries more speed into every swing. Lane discipline is a
## property of driving on a road, not of the errand, so it belongs to the layout.
##
## Returns an empty array when there is no sensible lattice route -- a hop across a
## forecourt, or two points on the same stretch of street -- and the caller should just
## navigate straight there.
static func lane_route(from: Vector3, to: Vector3, shut := {}) -> Array[Vector3]:
	var points: Array[Vector3] = []
	# Short hops go straight there. Lane discipline is about *streets*, and a journey
	# shorter than one is better served by the mesh's direct line: routing an 8m nudge
	# round the lattice sends the car twenty metres to a corner it did not need, which
	# is not tidier driving, it is a detour. Below this, the straight line is also what
	# the player clicked, and a right-click that quietly aims somewhere else is worse
	# than a wide turn.
	#
	# Unless a street has been written off. Then the straight line is the thing that did
	# not work, and a short hop round the corner is no longer a detour -- it is the only
	# way left. Without this exception a car that gave up within sight of its destination
	# got an empty route and went straight back to pushing at the obstruction.
	if shut.is_empty() and Vector2(to.x - from.x, to.z - from.z).length() < LANE_ROUTE_MIN:
		return points
	var cells := route(junction_at(from), junction_at(to), shut)
	if cells.is_empty():
		return points

	# Getting to the *first* junction is a leg in its own right. The route starts from
	# the nearest one, which is often behind the car -- parked halfway down a street it
	# has to drive back to the corner first, and without a waypoint for that it does it
	# down the middle of the road.
	# **Unless the car is already past it.** The route starts at the nearest junction, and
	# nearest is often *behind*: starting two thirds of the way along a street, the corner
	# already passed is closer than the one ahead. Sending the car back to it means driving
	# away from the destination and then turning 180 degrees, which the reverse latch will
	# not do at a waypoint 48m off -- so it loops away instead, and from the player's chair
	# it clicked east and drove west. Recorded from play, with the trail to prove it:
	# started at (-58,26) bound for x=+126, went to (-74,17) and then away to (-83,0).
	#
	# Narrow on purpose. Only the approach *waypoint* is dropped, and only when the car has
	# demonstrably passed that junction along the first leg. Redirecting the whole search
	# to the junction ahead was tried instead and cost the lane discipline this approach
	# leg quietly provides: 9% of a response over the centre line became 21%.
	var approach := street_direction(junction(cells[0]) - from)
	var already_past := cells.size() > 1 and (from - junction(cells[0])).dot(
		junction(cells[1]) - junction(cells[0])) > 0.0
	if approach != Vector3.ZERO and not already_past:
		points.append(junction(cells[0]) - approach * JUNCTION_MARGIN
			+ approach.cross(Vector3.UP) * LANE_OFFSET)

	var previous := approach
	for i in range(1, cells.size()):
		var start := junction(cells[i - 1])
		var end := junction(cells[i])
		var direction := (end - start).normalized()
		# Right of the direction of travel, the same side the ambient traffic keeps and
		# the side the kit's double yellow line is asking for.
		var lane := direction.cross(Vector3.UP) * LANE_OFFSET
		var apex := turn_apex(start, previous, direction)
		var entry := start + direction * ENTRY_DISTANCE + lane
		# On the first street the car may already be most of the way down it, and
		# aiming at the early points would send it back the way it came. Later legs
		# are always ahead, so only this one needs asking.
		if apex != Vector3.ZERO and (i > 1 or (apex - from).dot(direction) > 0.0):
			points.append(apex)
		if i > 1 or (entry - from).dot(direction) > 0.0:
			points.append(entry)
		points.append(end - direction * JUNCTION_MARGIN + lane)
		previous = direction

	# And off the grid again at the other end. A destination is rarely a junction, so
	# the last stretch runs along whichever street passes it -- without this waypoint
	# the navigation mesh cuts diagonally off the junction and across the oncoming lane
	# to reach it. Turning onto that street rounds the apex like any other leg.
	var last := junction(cells[cells.size() - 1])
	var gate := street_direction(to - last)
	if gate != Vector3.ZERO:
		var gate_apex := turn_apex(last, previous, gate)
		if gate_apex != Vector3.ZERO:
			points.append(gate_apex)
		points.append(last + gate * ENTRY_DISTANCE
			+ gate.cross(Vector3.UP) * LANE_OFFSET)
	return points


## [param offset] snapped to whichever street axis it mostly runs along, as a unit
## vector. Streets are a grid, so a point between two junctions is on one axis or the
## other and the diagonal is only ever the sum of what it has left to do.
##
## Zero if there is barely any distance to cover, in which case there is no leg here.
static func street_direction(offset: Vector3) -> Vector3:
	offset.y = 0.0
	if Vector2(offset.x, offset.z).length() < JUNCTION_MARGIN:
		return Vector3.ZERO
	if absf(offset.x) > absf(offset.z):
		return Vector3(signf(offset.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(offset.z))
