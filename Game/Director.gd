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
	{"id": &"gas_leak", "weight": 10, "needs_fire_service": true},
	# **No `needs_fire_service`, and that is the whole point.** Every other fire in this
	# table either wants a crew or merely tolerates an officer; this one the appliance
	# cannot touch at all, so it is the first call that is *police work because it is a
	# fire* rather than in spite of being one.
	{"id": &"electrical", "weight": 12},
	# **Two services in sequence, which nothing else here asks for.** A rescue wants an
	# engine and an ambulance at the same time; this wants the crew to have *finished*
	# before the paramedic can start, so turning up in the wrong order costs real time.
	{"id": &"trapped", "weight": 12, "needs_fire_service": true},
	# **The one call that gets worse for want of units rather than for want of time.**
	# Everything else here spreads on its own schedule; a disorder call spreads only
	# while nobody is standing in it, so turning up is itself the intervention.
	{"id": &"disorder", "weight": 12},
	# **Gated on owning a doctor, on exactly the terms building fires are gated on owning an
	# engine.** A casualty nobody on the roster can stabilise is not a hard call, it is a
	# broken one: paramedics would hold them indefinitely and the call would never close.
	{"id": &"collapse", "weight": 14, "needs_doctor": true},
	# **The RTC at the size where dispatch order matters.** One ambulance carries two
	# stretchers, so three-plus casualties force the triage question the two-body RTC
	# never asks: who rides first? Sized by the medical roster, gentled per casualty.
	{"id": &"bus_rtc", "weight": 8},
	# **The one call whose patient is the road.** Nothing burns and nobody is hurt;
	# the street itself is shut until a crew clears it, and the district's own traffic
	# reacts. Ungated: officers and firefighters both carry the verb, and every career
	# owns at least one of one of them.
	{"id": &"shed_load", "weight": 10},
	# **The call the board cannot diagnose.** Half are medical, half are police work,
	# and only a paramedic's assessment tells them apart -- so it is dispatched on the
	# not-knowing, which no other call asks the player to do.
	{"id": &"drunk", "weight": 12},
]

## What a vehicle fire leaves at the kerb. Plain mesh prefabs straight from the pack:
## no script, no collision, freed with the fire that is consuming them.
const WRECKS := [
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Small_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Medium_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn",
]

## Town-pack bodies for the bigger scenes, named in full: build_map's bare-name
## resolution covers PolygonCity only, and so does everything else that loads by name.
const BUS_WRECKS := [
	"res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_Bus_01.tscn",
	"res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_SchoolBus_01.tscn",
]
const SHED_TRUCK := "res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_Truck_Delivery_01.tscn"
const DRINK_PROPS := [
	"res://Assets/PolygonTown/Prefabs/Items/SM_Item_Alcohol_01.tscn",
	"res://Assets/PolygonTown/Prefabs/Items/SM_Item_Alcohol_02.tscn",
	"res://Assets/PolygonTown/Prefabs/Items/SM_Item_Alcohol_03.tscn",
	"res://Assets/PolygonTown/Prefabs/Items/SM_Item_BeerCup_01.tscn",
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
	# **The open calls fail before the scoring stops.** This used to switch scoring off
	# first and then free the incidents, so every call on the board closed silently -- and
	# since money banks on every `earn()` while the score only banks in `end_shift()`,
	# abandoning a bad shift was strictly better than finishing it: you kept the takings,
	# dropped the score, escaped the lost-casualty penalty and wiped the repair debt.
	#
	# Failing them first costs nothing that was earned -- `best_score` only ever rises --
	# and it produces an honest debrief for a shift that went badly.
	if _mission:
		for call in _board.open_calls():
			call.abandon()
		_mission.end_shift()
		_mission.scoring = false
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		node.queue_free()
	_close_the_books()


## Sweeps outstanding repair bills onto the house account.
##
## Called from **both** exits -- the shift running out and the shift being abandoned -- so
## it reads as when the accounting happens rather than as a penalty for quitting.
func _close_the_books() -> void:
	var house := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if house:
		house.settle_to_house()


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
			_close_the_books()
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
	open_kind(_pick_kind())


## Opens one call of a named kind, through **every guard the rolled path uses**.
##
## Public so a tool can ask for a specific call without waiting on the dice -- see
## [CallSpawner]. Split out rather than reimplemented on purpose: `_clear()` and
## `_pick_pavement()` are the single funnel enforcing that nothing ever opens inside a
## property, so a spawner that placed incidents itself could put a fire in a building and
## show the player a scene that looks like a bug in the game rather than in the tool.
## The only thing overridden here is which row of the table gets used.
func open_kind(kind: StringName) -> void:
	match kind:
		&"fire":
			var spot := _pick_pavement()
			if spot != Vector3.INF:
				# A bin at the kerb: the small job, and the one an officer can deal
				# with on their own without the career owning a fire service yet.
				_spawn_fire(spot, Fire.Kind.BIN)
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
		&"gas_leak":
			_spawn_gas_leak()
		&"trapped":
			_spawn_trapped()
		&"disorder":
			_spawn_disorder()
		&"collapse":
			_spawn_collapse()
		&"electrical":
			var spot := _pick_pavement()
			if spot != Vector3.INF:
				var fire := _spawn_fire(spot, Fire.Kind.ELECTRICAL, 0.4)
				if fire:
					fire.flavour = "Electrical fire, water unsuitable"
		&"bus_rtc":
			var junction := _pick_junction()
			if junction.x >= 0:
				_spawn_bus_rtc(junction)
		&"shed_load":
			_spawn_shed_load()
		&"drunk":
			_spawn_drunk()
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
		if kind.get("needs_doctor", false) and not _has_doctor():
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
## How big a disorder call starts, and how far it can grow, by the officers the career
## owns. Same principle as [constant BUILDING_SIZE] and for the same reason: the job fits
## whoever can be sent, rather than being withheld until the roster is big enough. That
## was tried on building fires, it was miserable, and a one-officer career never seeing
## the interesting police call would be the same mistake in a different uniform.
const DISORDER_SIZE := [
	{"officers": 1, "start": 2, "max_group": 3},
	{"officers": 2, "start": 2, "max_group": 4},
	{"officers": 3, "start": 3, "max_group": 6},
	{"officers": 4, "start": 3, "max_group": 8},
]


const BUILDING_SIZE := [
	{"crew": 1, "max_fires": 2, "spread_interval": 15.0},
	{"crew": 2, "max_fires": 4, "spread_interval": 12.0},
	{"crew": 3, "max_fires": 6, "spread_interval": 10.0},
	{"crew": 4, "max_fires": 8, "spread_interval": 8.0},
]

## How many people a bus collision puts on the road, by the medical hands the career
## owns -- ambulances and paramedics together, since both are what the scene consumes.
## Same principle as the two tables above: the job fits whoever can be sent.
const BUS_SIZE := [
	{"medics": 0, "casualties": 3},
	{"medics": 3, "casualties": 4},
	{"medics": 5, "casualties": 5},
]

## Where the bodies lie around the junction, first N taken. All within a few metres of
## the centre: [constant Call.GROUPING_RADIUS] is 14 and measured to a centroid that
## moves as each one is adopted, and a scene that strays past it splits into two calls.
const BUS_SPOTS := [
	Vector3(-1.8, 0.0, 1.2), Vector3(2.0, 0.0, -1.5), Vector3(-3.2, 0.0, -2.4),
	Vector3(3.4, 0.0, 2.6), Vector3(0.4, 0.0, 3.8),
]


## Whether the career could actually put a building out: an appliance to run the hose
## from, and somebody to hold it. Both, because either alone is no use -- and only one
## of each, because [constant BUILDING_SIZE] makes the fire fit whoever turns up.
## Whether the career can finish a casualty that a paramedic cannot. The doctor alone is
## enough -- unlike a building fire, which needs an appliance to reach it as well, a doctor
## walks and any ambulance on the books can carry the patient once they are stable.
func _has_doctor() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station != null and station.owns(&"doctor")


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


## A collapse in the street: one casualty who is beyond a paramedic.
##
## Built on [method _spawn_medical]'s trick of taking a standing civilian and putting *them*
## on the pavement in their own clothes, because the alternative -- a stranger fading in
## beside the crowd they were not part of a moment ago -- is the thing that trick exists to
## avoid. The decline is left at the ordinary rate: the pressure here is the dispatch, not
## the clock, and doubling both at once would make the call unreadable rather than hard.
func _spawn_collapse() -> void:
	var spot := Vector3.INF
	var worn := ""
	var civilian := _pick_civilian()
	if civilian:
		spot = civilian.global_position
		var body := civilian.get_node_or_null("Character")
		if body:
			worn = body.scene_file_path
		civilian.queue_free()
	else:
		spot = _pick_pavement()
	if spot == Vector3.INF:
		return
	var casualty := _spawn_casualty(spot, "Collapse -- beyond a paramedic", worn)
	if casualty:
		casualty.needs_doctor = true


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
	var fire := _spawn_fire(kerb["spot"], Fire.Kind.VEHICLE)
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
	# Well alight on arrival: this is a job for a crew, not something an officer wanders
	# past and deals with. Everything else -- needing a hose, growing faster than a
	# kerbside fire, being slow enough to knock down that the tank matters -- now comes
	# from the kind rather than being restated here.
	var fire := _spawn_fire(spot, Fire.Kind.BUILDING, 0.55)
	if fire == null:
		return
	fire.flavour = "Building fire"
	# How far it gets to spread is set by how many hands the career can send.
	_size_to_crew(fire)


## A cylinder at the kerb with a fire beside it, and a clock the player can see.
##
## The job the fire service has not had: one where standing still is the right thing to
## do. Every other fire rewards getting on the hose and staying there; this one asks
## whether the crew should be fighting the fire at all, or turning the jet on the thing
## that is about to take the street with it. Both answers work -- cool it, or put the
## fire out and let it cool on its own -- and which is right depends on how far along
## each of them is.
##
## Gated on the fire service like the building and the rescue, and for the same reason:
## nothing but a hose cools a cylinder, so a career without one would be watching a
## countdown it had no way to stop.
func _spawn_gas_leak() -> void:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return
	var spot: Vector3 = kerb["spot"]
	var hazard := _spawn("res://Game/Incidents/Hazard.tscn") as Hazard
	if hazard == null:
		return
	hazard.global_position = spot
	hazard.flavour = "Gas cylinder, fire nearby"

	# Close enough to be cooking it, far enough that the crew can work either without
	# standing in the other. Placed through _beside so a frontage facing the wrong way
	# cannot put the fire inside the building.
	var fire := _spawn_fire(_beside(spot, Vector3(4.0, 0.0, 1.0)), Fire.Kind.BIN, 0.45)
	if fire == null:
		return


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
	var fire := _spawn_fire(spot, Fire.Kind.BUILDING, 0.5)
	if fire == null:
		return
	_size_to_crew(fire)
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
## A fire of a given character. The rates, the plume and whether it spreads all come
## from [enum Fire.Kind] now -- this used to set four fields inline at four call sites,
## and they drifted apart.
func _spawn_fire(spot: Vector3, kind := Fire.Kind.BIN, intensity := 0.3) -> Fire:
	var fire := _spawn("res://Game/Incidents/Fire.tscn") as Fire
	if fire == null:
		return null
	fire.kind = kind
	fire.global_position = spot
	fire.intensity = intensity
	return fire


## A crowd turning: several of them at one kerb, drawing bystanders in until an officer
## stands in it or a cordon goes up.
##
## Sized to the roster on the way in, and capped on the way up, so a career with one
## officer gets a job one officer can finish and a career with four gets one worth four.
func _spawn_disorder() -> void:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return
	var spot: Vector3 = kerb["spot"]
	var row := _disorder_size()
	# Fanned along the kerb rather than stacked, or they spawn inside one another and the
	# scene reads as one person with a stutter.
	for i in int(row["start"]):
		var offset := Vector3(1.6 * (float(i) - float(row["start"]) * 0.5), 0.0, 0.0)
		var suspect := _spawn_suspect(spot + offset)
		if suspect == null:
			continue
		suspect.flavour = "Public disorder"
		suspect.recruits = true
		suspect.max_group = int(row["max_group"])


## The row of [constant DISORDER_SIZE] matching the officers on the books.
func _disorder_size() -> Dictionary:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	var officers := int(station.owned.get(&"officer", 0)) if station else 0
	var row: Dictionary = DISORDER_SIZE[0]
	for candidate: Dictionary in DISORDER_SIZE:
		if officers >= int(candidate["officers"]):
			row = candidate
	return row


## Someone pinned under a fallen load. One casualty, two services, and an order between
## them: the crew cut them loose, then the paramedic can work.
##
## Takes a civilian where it can, exactly as a collapse does -- the person under the pipe
## should be somebody who was walking past, not a stranger conjured for the occasion.
func _spawn_trapped() -> void:
	var spot := _pick_pavement(true)
	if spot == Vector3.INF:
		return
	var casualty := _spawn_casualty(spot, "Person trapped under a load")
	if casualty == null:
		return
	casualty.trapped = true
	# They are declining the whole time they are pinned, and the crew are not treating
	# them -- so this starts gentler than a plain collapse, or the sequencing the call
	# exists to create would just be a way to lose people.
	casualty.decline_per_second *= 0.6


## A collision at a crossroads: two casualties in the road, close enough that the board
## reads them as one job. Police to secure, a paramedic each, an ambulance out.
func _spawn_rtc(cell: Vector2i) -> void:
	var centre := CityGrid.junction(cell)
	_spawn_casualty(centre + Vector3(-1.8, 0.0, 1.2), "Road traffic collision")
	_spawn_casualty(centre + Vector3(2.0, 0.0, -1.5), "Road traffic collision")


## The RTC grown to the size the medical roster can face: a bus on its side of the
## junction and three to five people on the road around it. The depth is triage -- an
## ambulance carries two stretchers, so the player is choosing who rides first -- which
## is why every casualty declines at the trapped call's gentler rate. Pressure, not a
## mass grave.
func _spawn_bus_rtc(cell: Vector2i) -> void:
	var centre := CityGrid.junction(cell)
	# The wreck lies along one of the junction's own streets, like something that
	# arrived down it.
	var exits := CityGrid.neighbours(cell)
	var yaw := 0.0
	if not exits.is_empty():
		var toward: Vector2i = exits[_rng.randi_range(0, exits.size() - 1)]
		var direction := (CityGrid.junction(toward) - centre).normalized()
		yaw = atan2(direction.x, direction.z)
	var wreck: Node3D = null
	var parent := get_node_or_null(incidents_path)
	if parent:
		wreck = (load(str(BUS_WRECKS[_rng.randi_range(0, BUS_WRECKS.size() - 1)])) \
			as PackedScene).instantiate() as Node3D
		_strip_collision(wreck)
		parent.add_child(wreck)
		wreck.global_position = centre + Vector3(sin(yaw), 0.0, cos(yaw)) * 4.0
		wreck.rotation.y = yaw

	var placed: Array[Casualty] = []
	for i in int(_bus_size()["casualties"]):
		var casualty := _spawn_casualty(_beside(centre, BUS_SPOTS[i]),
			"Bus collision, multiple casualties")
		if casualty == null:
			continue
		casualty.decline_per_second *= 0.6
		placed.append(casualty)
	if wreck == null:
		return
	# The wreck leaves with the *last* casualty, so a half-worked scene keeps its bus.
	# The lambda scans the captured Array -- captured by reference, where an int counter
	# would be a copy -- and the departing casualty reads as already out of the tree.
	for casualty in placed:
		casualty.tree_exited.connect(func() -> void:
			if not is_instance_valid(wreck):
				return
			for other in placed:
				if is_instance_valid(other) and other.is_inside_tree():
					return
			wreck.queue_free())


## The row of [constant BUS_SIZE] matching the medical hands on the books.
func _bus_size() -> Dictionary:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	var medics := 0
	if station:
		medics = station.total(&"ambulance") + station.total(&"paramedic")
	var row: Dictionary = BUS_SIZE[0]
	for candidate: Dictionary in BUS_SIZE:
		if medics >= int(candidate["medics"]):
			row = candidate
	return row


## A delivery run gone wrong: the truck at the kerb, its cargo across the carriageway,
## and the street shut until somebody shifts it. The one call whose patient is the road.
func _spawn_shed_load() -> void:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return
	var debris := _spawn("res://Game/Incidents/Debris.tscn") as Debris
	if debris == null:
		return
	debris.global_position = kerb["centre"]
	debris.flavour = "Shed load blocking the road"
	var parent := get_node_or_null(incidents_path)
	if parent == null:
		return
	var truck := (load(SHED_TRUCK) as PackedScene).instantiate() as Node3D
	_strip_collision(truck)
	parent.add_child(truck)
	truck.global_position = kerb["spot"]
	truck.rotation.y = kerb["yaw"]
	debris.tree_exited.connect(func() -> void:
		if is_instance_valid(truck):
			truck.queue_free())


## Somebody flat out with a bottle beside them, and no way to tell from the board which
## call this really is. A paramedic's first working seconds settle it: half are exactly
## what they look like, half stand up swinging and become police work. The roll is made
## here on the shift's own seed and hidden until the assessment surfaces it.
func _spawn_drunk() -> void:
	var spot := Vector3.INF
	var worn := ""
	var civilian := _pick_civilian()
	if civilian:
		spot = civilian.global_position
		var body := civilian.get_node_or_null("Character")
		if body:
			worn = body.scene_file_path
		civilian.queue_free()
	else:
		spot = _pick_pavement()
	if spot == Vector3.INF:
		return
	var casualty := _spawn_casualty(spot, "Person collapsed, drink suspected", worn)
	if casualty == null:
		return
	casualty.needs_assessment = true
	casualty.turns_rowdy = _rng.randf() < 0.5
	# The bottle. Cosmetic, stripped, and a child of the body so it leaves with them
	# whichever way the assessment goes.
	for i in 1 + _rng.randi() % 2:
		var prop := (load(str(DRINK_PROPS[_rng.randi_range(0, DRINK_PROPS.size() - 1)])) \
			as PackedScene).instantiate() as Node3D
		_strip_collision(prop)
		casualty.add_child(prop)
		var angle := _rng.randf() * TAU
		prop.position = Vector3(sin(angle), 0.0, cos(angle)) * 0.6


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
		var along := start.lerp(end, _rng.randf_range(0.35, 0.65))
		var spot := along + direction.cross(Vector3.UP) * side * KERB_OFFSET
		if _clear(spot):
			# "centre" is the same point before the kerb offset -- mid-carriageway, for
			# the one caller that wants the road itself rather than its edge.
			return {"spot": spot, "yaw": atan2(direction.x, direction.z), "centre": along}
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
