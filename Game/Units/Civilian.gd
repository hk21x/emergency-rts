extends Person
class_name Civilian

## A member of the public. Strolls the pavements, runs from a fire, and is otherwise
## scenery that happens to move.
##
## Extends [Person] rather than reimplementing anything: a civilian walks, turns and
## animates exactly as an officer does, and gets the person navigation mesh for free.
## What it does not have is a player. It offers no abilities and
## [method is_selectable] is false, which is what keeps it out of box select, the
## minimap and the command bar.
##
## Destinations come from [CityGrid], not from a hand-placed waypoint list, so the
## crowd walks wherever the pavement actually is.

@export_group("Strolling")
@export var pause_min := 1.5
@export var pause_max := 6.0

## How far a stroll carries on a map with no pedestrian lattice -- roughly the
## tile-to-tile hop the graph gives, so the two look the same from the camera.
const OFF_LATTICE_STEP_MIN := 5.0
const OFF_LATTICE_STEP_MAX := 14.0

## How much noise a panicking civilian's hop choice carries. Comparable to a tile, so a
## near-best hop frequently beats the best one and a fleeing crowd scatters instead of
## filing away in a column.
const PANIC_JITTER := 4.0

@export_group("Fleeing")
## A fire closer than this sends them the other way.
@export var flee_radius := 14.0
## How often the surroundings are checked. Cheap, but there is no reason to do it
## every frame -- a fire does not appear between one step and the next.
@export var scan_interval := 0.4
## Inside this of something genuinely dangerous, a civilian stops fleeing tidily.
##
## **Panic is bounded by construction: it never leaves the pedestrian graph.** It changes
## *how* they move -- running rather than walking, scattering rather than filing down the
## single best line -- and never *where* they may go. That is deliberate and it is the
## bound the suite's 7,200-sample legality check keeps asserting, unweakened: a shopper who
## sprints into the carriageway has swapped one incident for another, and traffic cannot
## see pedestrians, so a panicking civilian in the road would be run over by a car that
## never braked.
@export var panic_radius := 7.0

## Heat at which a cylinder reads as dangerous as a fire. Below this it is a prop; at this
## it is about to go, and the crowd has always had the right reaction and never been told
## to have it.
@export var primed_heat := 0.75

@export_group("Gathering")
## A body on the pavement or somebody kicking off draws a crowd from this far.
@export var watch_radius := 18.0
## How close an onlooker gets before stopping to watch. Outside a working
## paramedic's elbows, inside a good view.
@export var watch_near := 7.0

## True while running from something. Public so a test can assert the reaction rather
## than infer it from which way they happen to be walking.
var is_fleeing := false
## True while fleeing something close enough to panic about. Public so a check can assert
## the carve-out's bounds rather than infer them from a gait.
var is_panicking := false
## True while stood (or on the way to stand) gawping at a scene. Public for the same
## reason [member is_fleeing] is.
var is_watching := false

var _pause_left := 0.0
var _scan_left := 0.0
var _rng := RandomNumberGenerator.new()
## The pavement tile this civilian is on (or heading to). Movement is a walk of the
## pedestrian graph -- ring tile to ring tile, crossings at the zebras -- rather than
## a point anywhere on the navigation mesh, which covers the roads too and would
## happily path a shopper diagonally across a carriageway.
var _tile := Vector2i.ZERO
## Where they stepped from, so a stroll wanders rather than dithering back and forth.
var _came_from := Vector2i(-1, -1)


func _ready() -> void:
	super()
	# Seeded per civilian rather than randomized, so a build is repeatable and two
	# neighbours still do not move in lockstep.
	_rng.seed = hash(name) ^ hash(global_position)
	# Staggered, or every civilian on the map scans on the same frame.
	_scan_left = _rng.randf_range(0.0, scan_interval)
	_tile = _nearest_walk_tile(global_position)


## Never selectable. A civilian is not a unit the player has.
func is_selectable() -> bool:
	return false


## No verbs. Right-clicking one therefore resolves to nothing, and the officer that
## was ordered falls through to Move -- which is what "walk over there" should mean.
func _build_abilities() -> Array[Ability]:
	return []


func _update_movement(delta: float) -> void:
	_think(delta)
	super(delta)


func _think(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		# A cordon is checked first: an officer has explicitly said "not here", and a
		# civilian standing inside one should leave whether or not anything is burning.
		var keep_out := _cordon_at(global_position)
		var away := keep_out.global_position if keep_out else Vector3.ZERO
		if keep_out == null:
			var threat := _nearest_threat()
			away = threat if threat != Vector3.INF else Vector3.ZERO
			if threat == Vector3.INF:
				is_fleeing = false
				is_panicking = false
				hurry = false
				_update_watching()
				return

		# Aimed once on the way out, and again only on arriving somewhere that is
		# still too close. Re-rolling the destination on every scan -- which is
		# what this did first -- leaves them changing their mind five times a
		# second and dithering on the spot while the fire burns beside them.
		# Panic is a *reading of the distance*, not a state with a timer: step far enough
		# away and it passes on its own, which is why it can never leak.
		is_panicking = away != Vector3.ZERO \
			and _flat_distance(away) < panic_radius
		hurry = is_panicking
		if not is_fleeing or not is_navigating():
			_flee_from(away)
		is_fleeing = true
		is_watching = false
		return

	if is_fleeing or is_watching or is_navigating():
		return

	_pause_left -= delta
	if _pause_left <= 0.0:
		_stroll()


## The raised cordon covering [param point], or null.
##
## Only a raised one counts. While an officer is still setting it out there is nothing
## there yet, and the crowd scattering from a cone that has not been put down would be
## them reacting to an intention.
func _cordon_at(point: Vector3) -> Cordon:
	for node in get_tree().get_nodes_in_group(Cordon.GROUP):
		var cordon := node as Cordon
		if cordon and cordon.contains(point):
			return cordon
	return null


## Gawping. With nothing to run from, a scene worth a look pulls this civilian along
## the pavement graph until they are stood at a respectful distance, facing it.
func _update_watching() -> void:
	var scene := _nearest_gathering()
	if scene == null:
		is_watching = false
		return
	is_watching = true
	if is_navigating():
		return
	if _flat_distance(scene.global_position) > watch_near:
		_approach(scene.global_position)
	else:
		face_towards(scene.global_position)


## The nearest thing worth a look: a body on the pavement, somebody kicking off.
## Fires are deliberately not in it -- a fire is for fleeing, and a gather radius
## outside the flee radius would have the same crowd walking in and running out.
func _nearest_gathering() -> Incident:
	var closest: Incident = null
	var best := watch_radius
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident == null or not incident.active:
			continue
		var casualty := incident as Casualty
		var suspect := incident as Suspect
		if casualty == null and suspect == null:
			continue
		# Nobody gathers round the back of the ambulance that just took them away.
		if (casualty and casualty.is_loaded) or (suspect and suspect.is_loaded):
			continue
		var distance := _flat_distance(incident.global_position)
		if distance < best:
			best = distance
			closest = incident
	return closest


## One graph hop toward the scene -- the mirror of _flee_from, under the same rule
## that every step is a legal pedestrian move. A hop is only taken when it actually
## helps, never lands on the scene itself, and never crosses an officer's cordon;
## a graph with no closer tile leaves them watching from where the pavement runs out.
func _approach(point: Vector3) -> void:
	if not CityGrid.lattice_fits:
		# Off the lattice the mesh is the only map there is: walk straight at the
		# scene and stop the respectful distance short, which is what the graph
		# hops were arranging the long way round.
		var towards := global_position - point
		towards.y = 0.0
		if towards.length() < 0.5:
			return
		_walk_to(point + towards.normalized() * watch_near)
		return
	var moves := _moves_here()
	if moves.is_empty():
		return
	var current := _flat_distance(point)
	var best := moves[0]
	var best_distance := INF
	for move in moves:
		var spot := CityGrid.tile_centre(move.x, move.y)
		if _cordon_at(spot):
			continue
		var distance := Vector2(spot.x - point.x, spot.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = move
	# The floor is a tile's width, because _step_to scatters within the tile: a
	# tighter one lets the jitter put an onlooker onto the body itself.
	if best_distance < current - 0.5 and best_distance > 4.0:
		_step_to(best)


## The nearest fire worth running from, or null. Casualties are deliberately not
## included: a body on the pavement is a reason to gather, not to flee, and making
## the crowd scatter from one would read as them running from the ambulance.
## Where the nearest thing worth running from is, or `Vector3.INF`.
##
## **A cylinder about to go now counts.** The crowd has fled fires since phase 16 and stood
## placidly beside a hazard at 0.9 heat the whole time -- the one place the existing panic
## would have done the right thing if simply told. `Hazard` carries the heat; this reads it.
func _nearest_threat() -> Vector3:
	var fire := _nearest_fire()
	var best := _flat_distance(fire.global_position) if fire else INF
	var spot := fire.global_position if fire else Vector3.INF
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var hazard := node as Hazard
		if hazard == null or not hazard.active or hazard.heat < primed_heat:
			continue
		var gap := _flat_distance(hazard.global_position)
		if gap < best and gap < flee_radius:
			best = gap
			spot = hazard.global_position
	return spot


func _nearest_fire() -> Fire:
	var closest: Fire = null
	var best := flee_radius
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var fire := node as Fire
		if fire == null or not fire.active:
			continue
		var distance := _flat_distance(fire.global_position)
		if distance < best:
			best = distance
			closest = fire
	return closest


## Runs along the pavement, one graph hop at a time, taking whichever legal step puts
## the most distance between them and the trouble. Fleeing follows the same graph
## strolling does -- across at the zebras, never through the carriageway -- because a
## panicking shopper who sprints into the road has swapped one incident for another.
## The scan loop re-aims on each arrival, which is what chains the hops.
func _flee_from(point: Vector3) -> void:
	if not CityGrid.lattice_fits:
		# Straight away from the trouble, as far as the mesh will take them.
		var away := global_position - point
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
				_rng.randf_range(-1.0, 1.0))
		_walk_to(global_position + away.normalized() * OFF_LATTICE_STEP_MAX)
		return
	var moves := _moves_here()
	if moves.is_empty():
		return
	# **Panicking widens the jitter rather than changing the rule.** Calm, the walk takes
	# whichever legal hop puts the most distance between them and the trouble, so a crowd
	# files away down one line like a queue. Frightened, the tie-break noise is large
	# enough that a near-best hop often wins, and the same crowd comes apart. Both are
	# choices *among legal moves*: panic cannot put anyone somewhere a stroll could not.
	var jitter := PANIC_JITTER if is_panicking else 0.5
	var best := moves[0]
	var best_score := -INF
	for move in moves:
		var spot := CityGrid.tile_centre(move.x, move.y)
		var score := Vector2(spot.x - point.x, spot.z - point.z).length() \
			+ _rng.randf_range(0.0, jitter)
		if score > best_score:
			best_score = score
			best = move
	_step_to(best)


## One hop along the pedestrian graph: the next ring tile along, the park lawn, or --
## from a kerb tile facing a zebra -- straight over the crossing.
func _stroll() -> void:
	_pause_left = _rng.randf_range(pause_min, pause_max)
	if not CityGrid.lattice_fits:
		_stroll_off_lattice()
		return
	var moves := _moves_here()
	if moves.is_empty():
		return
	# Prefer not to double straight back, so a stroll goes somewhere. A dead end --
	# which this graph does not have -- would fall through to the full list.
	var onward: Array[Vector2i] = []
	for move in moves:
		if move != _came_from:
			onward.append(move)
	var pool := onward if not onward.is_empty() else moves
	_step_to(pool[_rng.randi() % pool.size()])


## The crowd may only sidestep onto the pavement graph. An officer told to get somewhere
## can cut across a road to get round a parked car; a passer-by doing the same would be
## in the middle of the carriageway, which is the one thing the district's pedestrians
## are never allowed to do.
func _may_step_to(point: Vector3) -> bool:
	# Off the lattice there is no table saying where a pavement is; the person mesh
	# already refuses to path anywhere a pedestrian may not stand.
	if not CityGrid.lattice_fits:
		return true
	var tile := CityGrid.tile_at(point)
	return CityGrid.walkable(tile.x, tile.y)


## Walks at [param point] on the navigation mesh, settling for wherever the mesh
## actually reaches. The lattice-free counterpart of [method _step_to]: on a map
## [CityGrid] does not describe, the person mesh is the only honest statement of
## where a pedestrian may stand -- and it is a better one, because it was baked
## from that map's own ground.
func _walk_to(point: Vector3) -> void:
	var agent := get_node_or_null("NavigationAgent") as NavigationAgent3D
	if agent == null:
		return
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map,
		global_position, point, true, agent.navigation_layers)
	if path.is_empty():
		return
	navigate_to(path[path.size() - 1])


## A stroll with no lattice to stroll along: somewhere nearby the mesh can reach.
## Tries a handful of directions rather than one, so a civilian in a corner is not
## stuck waiting for the dice.
func _stroll_off_lattice() -> void:
	for attempt in 6:
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(OFF_LATTICE_STEP_MIN, OFF_LATTICE_STEP_MAX)
		var candidate := global_position \
			+ Vector3(sin(angle), 0.0, cos(angle)) * reach
		if _cordon_at(candidate):
			continue
		if Unit.can_reach(self, candidate, 1.5):
			_walk_to(candidate)
			return


func _step_to(tile: Vector2i) -> void:
	_came_from = _tile
	_tile = tile
	# Scattered within the tile so the crowd does not march down one line -- but only
	# a little, so a crossing hop stays on the zebra's own five metres.
	navigate_to(CityGrid.tile_centre(tile.x, tile.y) + Vector3(
		_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.2, 1.2)))


func _moves_here() -> Array[Vector2i]:
	var moves := CityGrid.walk_moves(_tile.x, _tile.y)
	if moves.is_empty():
		# Off the graph -- shoved, or spawned somewhere odd. Snap back onto it.
		_tile = _nearest_walk_tile(global_position)
		_came_from = Vector2i(-1, -1)
		moves = CityGrid.walk_moves(_tile.x, _tile.y)
	return moves


## The nearest tile the pedestrian graph knows: the containing tile if it has moves,
## otherwise the closest nearby tile that does.
func _nearest_walk_tile(point: Vector3) -> Vector2i:
	var col := int(floorf((point.x - CityGrid.ORIGIN) / CityGrid.TILE))
	var row := int(floorf((point.z - CityGrid.ORIGIN) / CityGrid.TILE))
	if not CityGrid.walk_moves(col, row).is_empty():
		return Vector2i(col, row)
	var best := Vector2i(col, row)
	var closest := INF
	for dc in range(-2, 3):
		for dr in range(-2, 3):
			var candidate := Vector2i(col + dc, row + dr)
			if CityGrid.walk_moves(candidate.x, candidate.y).is_empty():
				continue
			var spot := CityGrid.tile_centre(candidate.x, candidate.y)
			var distance := Vector2(spot.x - point.x, spot.z - point.z).length()
			if distance < closest:
				closest = distance
				best = candidate
	return best


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()
