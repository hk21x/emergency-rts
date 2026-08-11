extends Node
class_name Director

## Freeplay: opens calls on a timer at plausible places, and says when the shift is over.
##
## Does nothing until [method begin_shift] -- the map ships quiet, most of the test
## suite is written against it staying that way, and a director that started firing
## on its own would break all of it at once for no reason.
##
## Escalation is deliberately not this node's job. Fire._spread() and Casualty decline
## already run on their own, so the director's work is closer to *stopping* things than
## starting them: a cap on how many jobs may be open at once, and a breather after one
## closes before the next opens.
##
## It never opens a call the roster cannot answer. That began as "no building fires,
## ever" -- there was no appliance and no firefighter to buy -- and is now a career
## gate: buildings and rescues enter the draw only once the station owns both an
## engine and a crew. Generating a fire that is impossible to put out would be the
## game lying about what it can be asked to do.

signal shift_started
signal shift_ended

@export var call_board_path: NodePath
@export var mission_path: NodePath
## Where spawned incidents are parented -- the same node the scripted shout lives under,
## so everything downstream (board, mission, tests) sees them the same way.
@export var incidents_path: NodePath
## Kept clear, so a shout never opens on the forecourt it is answered from -- or on the
## one the casualty is driven to.
@export var station_path: NodePath
@export var hospital_path: NodePath

@export_group("Pacing")
## Game-seconds in which new calls open. The shift itself ends only when the last open
## call closes, so time running out with a job on the board means finishing the job.
@export var shift_length := 300.0
@export var first_call_delay := 10.0
@export var call_interval_min := 20.0
@export var call_interval_max := 40.0
## Jobs open at once. The roster is finite; more than this and the district is asking
## for units that do not exist.
@export var max_open_calls := 3
## After any call closes, at least this long before the next opens.
@export var breather := 8.0
## Multiplier on every interval, from the settings card: above 1 the district calls
## less often. The escalation below still narrows the gap across a shift -- this sets
## how busy the whole thing is, not whether it gets busier.
@export var pace := 1.0
## 0 seeds from the clock, so every shift is different. Set it for a reproducible run.
@export var shift_seed := 0

@export_group("Escalation")
## The rolled call interval is scaled from 1.0 at the start of the shift down to this
## by the end, so the district gets busier as the clock runs.
@export var late_interval_scale := 0.55
## Fraction of the shift after which one extra simultaneous call is allowed. The flat
## opening teaches the pace; the last stretch breaks it.
@export var late_surge_at := 0.65

## How long past the end of a shift the district will wait for the jobs already on the
## board, before standing down anyway and counting what is left as failed.
##
## Time running out is deliberately not the end of a shift -- you finish what you
## started, and the debrief waits. That rule was written assuming every open call *can*
## be finished, and it cannot: a career with a paramedic and no ambulance treats a
## casualty to stable and then has nothing that can collect them, so the call stays open
## for ever and the shift never ends. Measured before this existed: a four-second shift
## was still running forty seconds later, and five played sessions in a row wrote no
## best-score record because not one of them ever reached a debrief.
##
## 90 seconds is a generous allowance for a job genuinely in progress -- a casualty run
## across the district is well under a minute -- so this only ever fires on a call that
## was not going to finish.
@export var overrun_grace := 90.0

@export_group("Placement")
## No call opens within this of the station, the hospital, or another open call. Wider
## than Call.GROUPING_RADIUS so two jobs are never argued over by the board.
const CLEAR_OF_FORECOURTS := 22.0
const CLEAR_OF_OTHER_CALLS := 25.0
## How far off the road's centre line a burning car is parked: past the lane the
## traffic drives (CityGrid.LANE_OFFSET) and against the kerb.
const KERB_OFFSET := CityGrid.LANE_OFFSET + 1.5

## The mix, as weights. Medical is the bread and butter; an RTC is the set piece.
##
## A building fire is drawn only once the career owns a fire crew -- see
## [method _can_fight_buildings]. That is the same rule this node has honoured since
## it was written: never set the district a job the roster cannot answer. It used to
## mean "no building fires, ever", because there was no fire service to buy.
const KINDS := [
	{"id": &"medical", "weight": 35},
	{"id": &"fire", "weight": 25},
	{"id": &"rtc", "weight": 15},
	{"id": &"crime", "weight": 15},
	{"id": &"vehicle_fire", "weight": 10},
	{"id": &"building", "weight": 20, "needs_fire_service": true},
	{"id": &"rescue", "weight": 12, "needs_fire_service": true},
]

## What a vehicle fire leaves at the kerb. Plain mesh prefabs straight from the pack:
## no script, no collision, freed with the fire that is consuming them.
const WRECKS := [
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Small_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Medium_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn",
]

var active := false
## Game-seconds since the shift began.
var clock := 0.0

var _rng := RandomNumberGenerator.new()
var _next_in := 0.0
var _breather_left := 0.0
var _board: CallBoard
var _mission: Mission


func _ready() -> void:
	_board = get_node_or_null(call_board_path) as CallBoard
	_mission = get_node_or_null(mission_path) as Mission
	if _board:
		_board.call_closed.connect(_on_call_closed)


## Opens the shift. Idempotent: a second press mid-shift changes nothing.
func begin_shift() -> void:
	if active:
		return
	active = true
	clock = 0.0
	_next_in = first_call_delay * pace
	_breather_left = 0.0
	_rng.seed = shift_seed if shift_seed != 0 else randi()
	if _mission:
		_mission.begin_scoring()
	shift_started.emit()


## Stands a running shift down without a debrief -- the menu's restart and
## quit-to-title. Scoring is switched off *before* the scenes are freed, so the
## calls they leave behind close silently instead of counting as cleared. Nothing
## here starts the next shift; callers begin_shift() again once the board settles.
func abandon_shift() -> void:
	if not active:
		return
	active = false
	if _mission:
		_mission.scoring = false
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		node.queue_free()


func shift_remaining() -> float:
	return maxf(shift_length - clock, 0.0)


func remaining_text() -> String:
	var seconds := int(ceilf(shift_remaining()))
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _process(delta: float) -> void:
	if not active or _board == null:
		return
	clock += delta
	_breather_left = maxf(_breather_left - delta, 0.0)

	if clock >= shift_length:
		# No new calls; the shift ends the moment the board is clear -- or when the
		# overrun runs out, whichever comes first. Without that deadline a single call
		# the career cannot answer holds the shift open for ever.
		var outstanding := _board.open_calls()
		if not outstanding.is_empty() and clock >= shift_length + overrun_grace:
			for call in outstanding:
				call.abandon()
			outstanding = _board.open_calls()
		if outstanding.is_empty():
			active = false
			if _mission:
				_mission.end_shift()
			shift_ended.emit()
		return

	# The countdown to the next call only runs while the district could take one:
	# below the cap, and past the breather. Held, not skipped, so a busy spell does
	# not bank up a burst of calls for the moment it clears.
	if _breather_left > 0.0 or _board.open_calls().size() >= current_cap():
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_next_in = _rng.randf_range(call_interval_min, call_interval_max) \
			* interval_scale() * pace
		_open_call()


## The cap on simultaneous calls right now: flat for most of the shift, one higher in
## the late surge.
func current_cap() -> int:
	if shift_length > 0.0 and clock >= shift_length * late_surge_at:
		return max_open_calls + 1
	return max_open_calls


## Multiplier on the rolled call interval: 1.0 at the start of the shift, easing down
## to [member late_interval_scale] by the end.
func interval_scale() -> float:
	if shift_length <= 0.0:
		return 1.0
	return lerpf(1.0, late_interval_scale, clampf(clock / shift_length, 0.0, 1.0))


func _on_call_closed(_call: Call, _success: bool) -> void:
	if active:
		_breather_left = breather


# --- Opening a call ----------------------------------------------------------

func _open_call() -> void:
	match _pick_kind():
		&"fire":
			var spot := _pick_pavement()
			if spot != Vector3.INF:
				_spawn_fire(spot)
		&"rtc":
			var junction := _pick_junction()
			if junction.x >= 0:
				_spawn_rtc(junction)
		&"crime":
			# Kerbside only: the escorting patrol car has to be able to pull up
			# within reach, and a car cannot follow a suspect into a park.
			var spot := _pick_pavement(true)
			if spot != Vector3.INF:
				_spawn_suspect(spot)
		&"vehicle_fire":
			_spawn_vehicle_fire()
		&"building":
			_spawn_building_fire()
		&"rescue":
			_spawn_rescue()
		_:
			_spawn_medical()
	# A tick with nowhere to put a call simply skips it; the timer has already been
	# rewound, so the next attempt comes at the next interval.


func _pick_kind() -> StringName:
	var offered: Array[Dictionary] = []
	var total := 0
	for kind in KINDS:
		if kind.get("needs_fire_service", false) and not _can_fight_buildings():
			continue
		offered.append(kind)
		total += int(kind["weight"])
	var roll := _rng.randi_range(1, total)
	for kind in offered:
		roll -= int(kind["weight"])
		if roll <= 0:
			return kind["id"]
	return &"medical"


## How big a building fire is, by how many firefighters the career has to send.
##
## **The size of the job scales with the crew, rather than the job being withheld until
## the crew is big enough.** Both were tried. Gating it on a full crew of four worked
## and was miserable: a career with one or two firefighters simply never saw a building
## fire, so the most interesting call in the game was invisible for as long as it took
## to afford four of the same unit.
##
## What makes a building hard is not its rate -- measured, one crew loses at more than
## double the hose rate -- and not the tank, which ends every run above half. It is that
## it **spreads while the crew drive to it**, and one worker can only be at one node. So
## the lever is the spread: how many nodes it can reach, and how often it tries.
##
## Each row is sized so that crew can actually finish it, measured against a 40-second
## response, and so the shape of the job still grows with the service: one firefighter
## gets a fire in two places that they can beat, four get the eight-node scene that was
## always the design. Beyond four it does not grow further -- the appliance seats four,
## and a fire that outran a full crew would just be the old problem again.
const BUILDING_SIZE := [
	{"crew": 1, "max_fires": 2, "spread_interval": 15.0},
	{"crew": 2, "max_fires": 4, "spread_interval": 12.0},
	{"crew": 3, "max_fires": 6, "spread_interval": 10.0},
	{"crew": 4, "max_fires": 8, "spread_interval": 8.0},
]


## Whether the career could actually put a building out: an appliance to run the hose
## from, and somebody to hold it. Both, because either alone is no use -- and only one
## of each, because [constant BUILDING_SIZE] makes the fire fit whoever turns up.
func _can_fight_buildings() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station == null:
		return false
	return station.owns(&"engine") and station.owns(&"firefighter")


## How many firefighters the career owns, for sizing a fire it is about to open.
func _fire_crew() -> int:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return 0 if station == null else station.total(&"firefighter")


## Sizes [param fire] to the crew that will have to fight it. Applied to every building
## fire the director opens -- the plain one and the rescue -- so neither can hand out a
## scene the roster cannot finish.
func _size_to_crew(fire: Fire) -> void:
	var crew := _fire_crew()
	var row: Dictionary = BUILDING_SIZE[0]
	for entry in BUILDING_SIZE:
		if crew >= int(entry["crew"]):
			row = entry
	fire.max_fires = int(row["max_fires"])
	fire.spread_interval = float(row["spread_interval"])


## Someone taken ill on the pavement. Needs a paramedic, then an ambulance.
##
## When the crowd can supply one, the someone is a *civilian*: a shopper is swapped
## for a casualty where they stand, so the call begins with one fewer person on the
## pavement rather than a body from nowhere. The fallback -- an empty district, or
## nobody standing anywhere a call may open -- spawns on the pavement as before.
func _spawn_medical() -> void:
	var civilian := _pick_civilian()
	if civilian:
		var spot := civilian.global_position
		# Their own clothes: the body on the pavement is the shopper who was
		# standing there, which is the whole point of taking one rather than
		# spawning a stranger.
		var worn := ""
		var body := civilian.get_node_or_null("Character")
		if body:
			worn = body.scene_file_path
		civilian.queue_free()
		_spawn_casualty(spot, "", worn)
		return
	var fallback := _pick_pavement()
	if fallback != Vector3.INF:
		_spawn_casualty(fallback, "")


func _spawn_casualty(spot: Vector3, flavour: String, outfit := "") -> Casualty:
	var casualty := _spawn("res://Game/Incidents/Casualty.tscn", outfit) as Casualty
	if casualty:
		casualty.global_position = spot
		casualty.flavour = flavour
	return casualty


## Somebody kicking off on the pavement. Needs an officer, then a patrol car.
func _spawn_suspect(spot: Vector3) -> Suspect:
	var suspect := _spawn("res://Game/Incidents/Suspect.tscn") as Suspect
	if suspect:
		suspect.global_position = spot
	return suspect


## A car alight at the kerb. Still a fire the extinguisher can honestly deal with --
## it is a car burning, not a building -- but it reads differently on the board and
## in the street.
##
## The wreck is a **sibling** of the fire, not a child of it. [method Fire._spread]
## clones itself with `duplicate()`, which copies children too, so a wreck parented
## to the fire put a fresh car on the street with every spread -- a burning car that
## bred. It is tied to the fire's life through `tree_exited` instead.
func _spawn_vehicle_fire() -> void:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return
	var fire := _spawn_fire(kerb["spot"])
	if fire == null:
		return
	fire.flavour = "Vehicle fire"

	var parent := get_node_or_null(incidents_path)
	if parent == null:
		return
	var wreck := (load(WRECKS[_rng.randi_range(0, WRECKS.size() - 1)]) \
		as PackedScene).instantiate() as Node3D
	# The shipped prefabs wrap their meshes in StaticBody3D nodes. Left in, a
	# burning car would physically trap the crew sent to deal with it -- the same
	# reason the cordon's cones are stripped.
	_strip_collision(wreck)
	parent.add_child(wreck)
	wreck.global_position = kerb["spot"]
	wreck.rotation.y = kerb["yaw"]
	fire.tree_exited.connect(func() -> void:
		if is_instance_valid(wreck):
			wreck.queue_free())


## A building alight: the marquee call, and the one the district could not answer
## until there was a fire service to buy. Bigger than a bin from the start, and it
## only goes down to a hose -- see [member Fire.needs_hose].
##
## Placed against a block's frontage rather than on it: the pavement ring is where a
## crew can actually stand, and a fire inside the footprint would be unreachable.
func _spawn_building_fire() -> void:
	var spot := _pick_pavement(true)
	if spot == Vector3.INF:
		return
	var fire := _spawn_fire(spot)
	if fire == null:
		return
	fire.flavour = "Building fire"
	fire.needs_hose = true
	# How far it gets to spread is set by how many hands the career can send.
	_size_to_crew(fire)
	# Well alight on arrival, and it grows faster than a kerbside one: this is a job
	# for a crew, not something an officer wanders past and deals with.
	fire.intensity = 0.55
	fire.growth_per_second = 0.07
	# Slower to knock down than a bin, which is what gives the tank something to do:
	# at the full hose rate this is about eleven seconds and two thirds of a tank,
	# and a crew off the hose loses to it outright.
	fire.douse_per_second = 0.12


## The set piece: a building alight with people hurt outside it. The first call the
## district produces that no single service can finish -- an engine and a crew to
## fight it, a paramedic and an ambulance for the casualties, and both at once,
## because the fire is spreading while the treating is happening.
##
## Everything it needs already existed. The board has grouped incidents at one scene
## into a single call since phase 12, and its RESCUE kind (burning *and* hurt) has
## been derivable since then; what was missing was anything that deliberately
## composed one. This is that, and nothing else had to change.
func _spawn_rescue() -> void:
	var spot := _pick_pavement(true)
	if spot == Vector3.INF:
		return
	var fire := _spawn_fire(spot)
	if fire == null:
		return
	fire.needs_hose = true
	_size_to_crew(fire)
	fire.intensity = 0.5
	fire.growth_per_second = 0.07
	fire.douse_per_second = 0.12
	# The flavour is carried by the fire because Call.title() takes the first one it
	# finds, and this is the incident that names the job.
	fire.flavour = "Building fire, casualties reported"

	# Out on the pavement in front of it: clear of the flames, inside the board's
	# grouping radius, so this reads as one job rather than three.
	for offset in [Vector3(4.5, 0.0, 1.5), Vector3(-3.5, 0.0, 2.5)]:
		var lying := _beside(spot, offset)
		if lying != Vector3.INF:
			_spawn_casualty(lying, "")


func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_collision(child)


## A kerbside fire -- a bin, a skip, a parked car. Sized for the extinguisher a patrol
## car actually carries, and it will still spread if it is left to.
func _spawn_fire(spot: Vector3) -> Fire:
	var fire := _spawn("res://Game/Incidents/Fire.tscn") as Fire
	if fire:
		fire.global_position = spot
		fire.intensity = 0.3
	return fire


## A collision at a crossroads: two casualties in the road, close enough that the board
## reads them as one job. Police to secure, a paramedic each, an ambulance out.
func _spawn_rtc(cell: Vector2i) -> void:
	var centre := CityGrid.junction(cell)
	_spawn_casualty(centre + Vector3(-1.8, 0.0, 1.2), "Road traffic collision")
	_spawn_casualty(centre + Vector3(2.0, 0.0, -1.5), "Road traffic collision")


func _spawn(scene_path: String, outfit := "") -> Node3D:
	var parent := get_node_or_null(incidents_path)
	if parent == null:
		push_error("director has no Incidents node to spawn into")
		return null
	var node := (load(scene_path) as PackedScene).instantiate() as Node3D
	# Set before add_child: the incident dresses itself in _ready, and _ready runs
	# the moment it enters the tree.
	var incident := node as Incident
	if incident:
		incident.outfit = outfit
	parent.add_child(node)
	return node


# --- Placement ---------------------------------------------------------------

## A crowd member a medical call could plausibly take: on their feet, going about
## their day, and standing somewhere a call is allowed to open.
func _pick_civilian() -> Civilian:
	var candidates: Array[Civilian] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian == null or civilian.is_fleeing:
			continue
		if _clear(civilian.global_position):
			candidates.append(civilian)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## A spot against the kerb of a street: partway along a leg between two junctions,
## pulled to the edge of the carriageway, under the usual clearance rules. Returns an
## empty dictionary when nowhere qualifies, otherwise {"spot": ..., "yaw": ...} with
## the yaw lying along the street, the way a parked car would.
func _pick_kerb() -> Dictionary:
	var legs: Array[Dictionary] = []
	for x in CityGrid.BANDS:
		for z in CityGrid.BANDS:
			var cell := Vector2i(x, z)
			for next in CityGrid.neighbours(cell):
				# Each undirected leg once.
				if next.x > cell.x or next.y > cell.y:
					legs.append({"a": cell, "b": next})
	while not legs.is_empty():
		var leg: Dictionary = legs.pop_at(_rng.randi_range(0, legs.size() - 1))
		var start := CityGrid.junction(leg["a"])
		var end := CityGrid.junction(leg["b"])
		var direction := (end - start).normalized()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var spot := start.lerp(end, _rng.randf_range(0.35, 0.65)) \
			+ direction.cross(Vector3.UP) * side * KERB_OFFSET
		if _clear(spot):
			return {"spot": spot, "yaw": atan2(direction.x, direction.z)}
	return {}


## A pavement tile the district could plausibly produce a shout on: away from both
## forecourts, and not on top of a job already on the board. [param roadside]
## restricts it to the block rings -- points stood against a road -- for the calls a
## vehicle has to be able to pull up beside; the default also offers park interiors,
## which only feet can serve.
func _pick_pavement(roadside := false) -> Vector3:
	var candidates: Array[Vector3] = []
	for point in CityGrid.pavement_points():
		if roadside and not _roadside(point):
			continue
		if _clear(point):
			candidates.append(point)
	if candidates.is_empty():
		return Vector3.INF
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## Whether a pavement point stands against a road. A ring tile's centre sits 7.5m
## from the centre line of the road it faces (5m of half-road, 2.5m of half-tile);
## anything deeper into a block -- a park interior -- reads well past 8.
func _roadside(point: Vector3) -> bool:
	var nearest := INF
	for band in CityGrid.BANDS:
		nearest = minf(nearest, minf(
			absf(point.x - CityGrid.band_centre_x(band)),
			absf(point.z - CityGrid.band_centre_z(band))))
	return nearest < 8.0


## A junction, under the same rules. Returns (-1, -1) when nowhere qualifies.
func _pick_junction() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for x in CityGrid.BANDS:
		for z in CityGrid.BANDS:
			var cell := Vector2i(x, z)
			if _clear(CityGrid.junction(cell)):
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _clear(point: Vector3) -> bool:
	# **Nothing happens inside a property.** Every picker funnels through here, so this is
	# the one place to say it: a scene nobody can walk to is a call that cannot be
	# answered, and it burns or bleeds until it fails.
	if not _standable(point):
		return false
	for path in [station_path, hospital_path]:
		var landmark := get_node_or_null(path) as Node3D
		if landmark and _flat(landmark.global_position - point) < CLEAR_OF_FORECOURTS:
			return false
	if _board:
		for call in _board.open_calls():
			if _flat(call.position - point) < CLEAR_OF_OTHER_CALLS:
				return false
	return true


## Whether anybody could stand where a call is about to open. [method CityGrid.standable],
## not `walkable` -- the latter is the pedestrian graph's question and answers yes for a
## building's footprint, which is how an incident ends up inside one.
func _standable(point: Vector3) -> bool:
	var tile := CityGrid.tile_at(point)
	return CityGrid.standable(tile.x, tile.y)


## A spot the given distance from [param spot] that somebody could be standing on.
##
## The rescue placed its casualties at **fixed offsets** from the fire, which is the
## pavement on a frontage facing one way and the inside of the building on a frontage
## facing the other -- reported from play as casualties in properties. The offset's
## distance is kept and its direction swept until the ground is real.
func _beside(spot: Vector3, offset: Vector3) -> Vector3:
	for turn in 12:
		var candidate := spot + offset.rotated(Vector3.UP, TAU * float(turn) / 12.0)
		if _standable(candidate):
			return candidate
	return Vector3.INF


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
