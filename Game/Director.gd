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
	# **35 and 25 were these weights for as long as the table had seventeen rows.** The
	# depth pass below added five, which would have taken the bread-and-butter call from
	# 14.8% of the mix to 12.4% -- the staple getting rarer as a side effect nobody chose.
	# 42 of 294 is 14.3%, and 29 is 9.9% against fire's old 10.5%, so both hold. `crime`
	# is deliberately *not* bumped: `arson` and `affray` are both police work, so police
	# calls rise in aggregate rather than falling, and topping it up would double-count.
	{"id": &"medical", "weight": 42},
	{"id": &"fire", "weight": 29},
	# `wet_weight` replaces `weight` while the road is wet (rain or snow): collisions
	# climb when the grip goes, which makes the weather a dispatch fact rather than a
	# screen effect. See _kind_weight().
	{"id": &"rtc", "weight": 15, "wet_weight": 30},
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
	# **Gated on owning armed response, on exactly the terms a collapse is gated on owning
	# a doctor.** An armed suspect is not an arrest any officer can make -- Apprehend is
	# not even offered on one -- so a career without an ARV would get a call it could only
	# watch. Rarer than a plain crime call: the answer to it costs £550 and should feel
	# like a decision rather than a default hire.
	{"id": &"armed_suspect", "weight": 7, "needs_arv": true},
	# **The RTC at the size where dispatch order matters.** One ambulance carries two
	# stretchers, so three-plus casualties force the triage question the two-body RTC
	# never asks: who rides first? Sized by the medical roster, gentled per casualty.
	{"id": &"bus_rtc", "weight": 8, "wet_weight": 16},
	# **The one call whose patient is the road.** Nothing burns and nobody is hurt;
	# the street itself is shut until a crew clears it, and the district's own traffic
	# reacts. Ungated: officers and firefighters both carry the verb, and every career
	# owns at least one of one of them.
	{"id": &"shed_load", "weight": 10},
	# **The call the board cannot diagnose.** Half are medical, half are police work,
	# and only a paramedic's assessment tells them apart -- so it is dispatched on the
	# not-knowing, which no other call asks the player to do.
	{"id": &"drunk", "weight": 12},
	# **The call whose marker admits it does not know where the job is.** The marker
	# stands at the last-seen report; the child strolls the walk graph unmarked, and a
	# unit finds them by getting close. The first call the player *searches*.
	{"id": &"missing_child", "weight": 8},

	# --- The depth pass (August 2026) -------------------------------------------
	#
	# Five rows added at once, because an audit found that **seven of the fourteen
	# buyable units had no scene that wanted them in particular**. Every row below is
	# aimed at one purchase. Weights are modest: the point is that these turn up, not
	# that they crowd out the district's ordinary day.

	# **The call the road does not reach.** A collapse well inside a park: the ambulance
	# stops at the kerb and the stretcher goes in and out on foot. An air ambulance lands
	# beside the patient instead, which is the first time owning one is an *answer*
	# rather than a faster way of arriving.
	{"id": &"remote_medical", "weight": 10},
	# **Police work that happens to be a fire.** A bin an officer's own extinguisher can
	# deal with, and the person who lit it still standing over it -- so no engine is
	# wanted, and what is wanted is the second thing an officer does. Every other fire in
	# this table either needs a crew or merely tolerates an officer.
	{"id": &"arson", "weight": 10},
	# **The call that gives Secure something to be for.** A cordon elsewhere in this game
	# is housekeeping around a scene already being dealt with; here it is the
	# intervention, because the paramedic cannot work in the middle of a fight.
	{"id": &"affray", "weight": 10},
	# **The collision at the size where the winch is the whole job.** An ordinary `rtc`
	# grows a wreck only once a career owns a recovery truck; this one is held back until
	# it does, because it is nothing *but* wrecks. Gating a bigger version of a call the
	# player already knows is the pattern BUILDING_SIZE endorses -- gating the only
	# version is the one it warns about.
	{"id": &"pile_up", "weight": 8, "wet_weight": 16, "needs_truck": true},
	# **A hazard with the road shut in front of it.** The cylinder call has a tank and a
	# fire; the shed load has a blocked street. This has both, and somebody down past the
	# blockage -- so the crew are cooling, the road wants clearing, and the ambulance
	# cannot get to the casualty until it is.
	{"id": &"spill", "weight": 8, "needs_fire_service": true},
	# **The only call that needs armed response and medical at once.** `armed_suspect` is
	# police work alone and `collapse` is medical alone; this is the first row that cannot
	# be finished by one service. Gated on the ARV for the same reason `armed_suspect` is:
	# an armed suspect is not offered [ApprehendAbility] by anybody, so without a unit that
	# can disarm them the scene has no ending and the call would sit open until
	# [member overrun_grace] failed it.
	#
	# Rarer than the lone armed suspect, which is already the rarest police row: two
	# weapons on the same pavement should be the shift a player remembers, not a Tuesday.
	{"id": &"armed_robbery", "weight": 5, "needs_arv": true},
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
## What a robbery leaves on the pavement. Ground scatter only, and deliberately so: these
## are laid flat on the pavement at the height everything else in this game stands on, and
## a prefab designed to hang on a wall would float. `SM_Prop_Sign_Money_Bank_01` was named
## in the plan for this call and is left out for exactly that reason -- **none of this is
## visually verified**, because the generators need a window and the suite does not have
## one, so the only safe rule is to place things whose own name says they belong on the
## floor.
const HEIST_PROPS := [
	"res://Assets/Synty/PolygonHeist/Prefab/Items/SM_Item_DuffleBag_Open_Full_01.tscn",
	"res://Assets/Synty/PolygonHeist/Prefab/Props/SM_Prop_Money_Stack_01.tscn",
	"res://Assets/Synty/PolygonHeist/Prefab/Props/SM_Prop_Money_Note_01.tscn",
	"res://Assets/Synty/PolygonHeist/Prefab/Props/SM_Prop_Glass_Shard_01.tscn",
	"res://Assets/Synty/PolygonHeist/Prefab/Props/SM_Prop_Glass_Shard_02.tscn",
]
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
		&"armed_suspect":
			var armed_spot := _pick_pavement(true)
			if armed_spot != Vector3.INF:
				var suspect := _spawn_suspect(armed_spot)
				if suspect:
					suspect.armed = true
					suspect.flavour = "Suspect reported armed"
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
		&"missing_child":
			_spawn_missing_child()
		&"remote_medical":
			_spawn_remote_medical()
		&"arson":
			_spawn_arson()
		&"affray":
			_spawn_affray()
		&"pile_up":
			var pile := _pick_junction()
			if pile.x >= 0:
				_spawn_pile_up(pile)
		&"spill":
			_spawn_spill()
		&"armed_robbery":
			_spawn_armed_robbery()
		_:
			_spawn_medical()
	# A tick with nowhere to put a call simply skips it; the timer has already been
	# rewound, so the next attempt comes at the next interval.


func _pick_kind() -> StringName:
	var wet := _road_is_wet()
	var offered: Array[Dictionary] = []
	var total := 0
	for kind in KINDS:
		if kind.get("needs_fire_service", false) and not _can_fight_buildings():
			continue
		if kind.get("needs_arv", false) and not _has_armed_response():
			continue
		if kind.get("needs_doctor", false) and not _has_doctor():
			continue
		# [method _leaves_a_wreck] is this same question -- can anybody on the books shift
		# a written-off car -- asked as a gate rather than as a tail. A pile-up is nothing
		# *but* wrecks, so for this row the two readings are the same one.
		if kind.get("needs_truck", false) and not _leaves_a_wreck():
			continue
		offered.append(kind)
		total += _kind_weight(kind, wet)
	var roll := _rng.randi_range(1, total)
	for kind in offered:
		roll -= _kind_weight(kind, wet)
		if roll <= 0:
			return kind["id"]
	return &"medical"


## A kind's weight in the current conditions: wet weather -- rain or snow, the sky's
## own [method Daylight.is_wet] -- swaps in the row's `wet_weight` where it carries one.
func _kind_weight(kind: Dictionary, wet: bool) -> int:
	if wet and kind.has("wet_weight"):
		return int(kind["wet_weight"])
	return int(kind["weight"])


func _road_is_wet() -> bool:
	var daylight := get_tree().get_first_node_in_group(Daylight.GROUP) as Daylight
	return daylight != null and daylight.is_wet()


## What a shift may open under. Clear-heavy on purpose: weather is an event, not the
## default, and a district that is usually dry is what makes the wet shift read.
const WEATHER_ROLL := [
	{"weather": Daylight.Weather.CLEAR, "weight": 50},
	{"weather": Daylight.Weather.RAIN, "weight": 24},
	{"weather": Daylight.Weather.FOG, "weight": 14},
	{"weather": Daylight.Weather.SNOW, "weight": 12},
]


## The shift's weather, drawn from the seeded stream so a reproduced shift is rained on
## identically. The director owns the dice and nothing else: the menu owns the policy
## of whether a shift rolls at all, and the sky owns what the answer looks like.
func roll_weather() -> int:
	var total := 0
	for row in WEATHER_ROLL:
		total += int(row["weight"])
	var roll := _rng.randi_range(1, total)
	for row in WEATHER_ROLL:
		roll -= int(row["weight"])
		if roll <= 0:
			return int(row["weather"])
	return Daylight.Weather.CLEAR


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
## Whether the career can finish a casualty that a paramedic cannot.
##
## **A doctor is no longer enough on their own.** They used to be -- a doctor walks, and
## any ambulance on the books could carry the patient once stable -- but the doctor gave up
## [CollectAbility] in August 2026 to stop being a strict superset of the paramedic. So the
## stretcher run now needs a paramedic on the books too, and without this line a
## doctor-only career would be handed a `collapse` that nothing it owns could finish: the
## casualty stabilises and then lies there, and the call closes as failed on
## [member overrun_grace] ninety seconds later. That is the same trap the road collision
## was in, arriving from the other direction.
func _has_doctor() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station != null and station.owns(&"doctor") and station.owns(&"paramedic")


## Whether anybody on the roster can face a weapon. The armed-suspect call is held back
## until they do -- the same rule that holds building fires back until there is an engine.
func _has_armed_response() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station != null and station.owns(&"arv")


func _can_fight_buildings() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station == null:
		return false
	return station.owns(&"engine") and station.owns(&"firefighter")


## Whether a collision should leave a car behind for somebody to winch away.
##
## **Not a gate on the call, and the difference matters.** A [Wreck] can only be cleared by
## a unit with `can_tow`, which is the £700 recovery truck and nothing else -- so a career
## without one used to draw road collisions it could never close, and the only thing that
## ended them was [member overrun_grace] counting them *failed*. The player was being
## punished for a purchase they had not made, on the second-heaviest row in the table.
##
## The fix is not to hide the call. Hiding it would take the game's named set piece away
## from every early career, which is the same mistake [constant BUILDING_SIZE] records
## having shipped once already: *scale the job to the roster, do not withhold it.* It would
## also read oddly, since `bus_rtc` frees its own bus and so would stay available -- the
## bigger collision offered to a career the smaller one was hidden from.
##
## So the collision always happens, and it grows a tail the day the player can answer it.
## That also makes the £700 a purchase they can already picture, which is a better prompt
## than unlocking a call they have never seen.
func _leaves_a_wreck() -> bool:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station != null and station.owns(&"truck")


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
##
## Returns where the crowd was put, or [constant Vector3.INF] if there was nowhere to put
## one -- [method _spawn_affray] needs the centre to lay a casualty in the middle of it,
## and re-picking a kerb of its own would put the two halves of one scene in two streets.
## [param flavour] names the job on the board: [method Call.title] takes the first
## flavoured incident it finds, and the suspects are always the first here.
func _spawn_disorder(flavour := "Public disorder") -> Vector3:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return Vector3.INF
	var spot: Vector3 = kerb["spot"]
	var row := _disorder_size()
	# Fanned along the kerb rather than stacked, or they spawn inside one another and the
	# scene reads as one person with a stutter.
	for i in int(row["start"]):
		var offset := Vector3(1.6 * (float(i) - float(row["start"]) * 0.5), 0.0, 0.0)
		var suspect := _spawn_suspect(spot + offset)
		if suspect == null:
			continue
		suspect.flavour = flavour
		suspect.recruits = true
		suspect.max_group = int(row["max_group"])
	return spot


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
## **A collision leaves something behind, once you can shift it.** Two casualties and --
## for a career that owns a recovery truck -- a written-off car: the bodies are dealt with
## in the first minute and the street stays shut until the winch arrives. Every other call
## in this game finishes when the last casualty is loaded; this is the first with a tail,
## and the reason to own a truck at all. Without one there is no car, because there would
## be no way to move it: see [method _leaves_a_wreck].
func _spawn_rtc(cell: Vector2i) -> void:
	var centre := CityGrid.junction(cell)
	# The car lies down one of the junction's own streets, as if it arrived that way --
	# the same arrangement the bus collision uses, and for the same reason.
	var exits := CityGrid.neighbours(cell)
	var along := Vector3(0.0, 0.0, 1.0)
	if not exits.is_empty():
		var toward: Vector2i = exits[_rng.randi_range(0, exits.size() - 1)]
		along = (CityGrid.junction(toward) - centre).normalized()
	var across := Vector3(-along.z, 0.0, along.x)

	# **Thrown clear, on the far side of the junction from the car.** They were placed
	# 2.2m and 2.5m from the centre, and the wreck sat on the centre with a 5.5m blocker
	# around it -- so the casualties spawned underneath it and could not be reached.
	var away := centre - along * 1.6
	_spawn_casualty(away + across * 1.7, "Road traffic collision")
	_spawn_casualty(away - across * 1.5, "Road traffic collision")
	# **Only if somebody on the books can shift it** -- see [method _leaves_a_wreck].
	if not _leaves_a_wreck():
		return
	var wreck := _spawn("res://Game/Incidents/Wreck.tscn") as Wreck
	if wreck:
		wreck.global_position = centre + along * 3.4
		wreck.flavour = "Vehicle written off, road blocked"


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
		# The air ambulance counts as a pair of medical hands: it carries a stretcher, so
		# it is another casualty off the road. Left out, this table would size a bus crash
		# against a roster it had understated -- which is the one thing a roster-scaling
		# table must not do.
		medics = station.total(&"ambulance") + station.total(&"paramedic") \
			+ station.total(&"rescue_heli")
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


## A child reported missing: a parent standing at the last-seen point, and the child
## themselves strolling the walk graph a genuine walk away. The report carries the
## call, the marker and the flavour; the child wears nothing, which is the game --
## the player searches the nearby streets rather than clicking a dot.
func _spawn_missing_child() -> void:
	var anchor_spot := _pick_pavement()
	if anchor_spot == Vector3.INF:
		return
	var spot := _child_spot(anchor_spot)
	if spot == Vector3.INF:
		return
	var anchor := _spawn("res://Game/Incidents/MissingChild.tscn") as MissingChild
	if anchor == null:
		return
	anchor.global_position = anchor_spot
	anchor.flavour = "Child reported missing"
	var parent := get_node_or_null(incidents_path)
	if parent == null:
		return
	var child := (load("res://Game/Units/Child.tscn") as PackedScene) \
		.instantiate() as ChildWanderer
	# Position and tether set before add_child: a Civilian seeds its stroll and finds
	# its graph tile in _ready, and a child who woke up at the origin would spend its
	# first stroll walking back from a tile it was never on.
	child.position = spot
	child.wander_centre = spot
	parent.add_child(child)
	child.global_position = spot
	anchor.child = child
	# The child leaves with the report -- found, torn down or abandoned. The shed-load
	# truck pattern.
	anchor.tree_exited.connect(func() -> void:
		if is_instance_valid(child):
			child.queue_free())


## A pavement point a genuine journey from the last-seen spot: far enough that the
## search wants the district swept rather than the next street glanced at, near enough
## that the child's roam tether and the call's promise agree. Widened from 25-55 once
## the find became the middle of the job -- with the drive home carrying the weight,
## the search in front of it earns real distance.
func _child_spot(anchor: Vector3) -> Vector3:
	var candidates: Array[Vector3] = []
	for point in CityGrid.pavement_points():
		var offset := point - anchor
		offset.y = 0.0
		if offset.length() >= 45.0 and offset.length() <= 90.0:
			candidates.append(point)
	if candidates.is_empty():
		return Vector3.INF
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## A collapse well inside a park, where no road goes.
##
## **The one medical call the kerb does not reach.** Every other shout in this table opens
## on a pavement a vehicle can pull up to; this one opens at least [constant PARK_DEPTH]
## from the nearest centre line, so the ambulance stops at the road and the paramedic
## walks the stretcher in and back out again. An air ambulance simply lands beside the
## patient, which is the first thing in this game that makes owning one an *answer*
## rather than a faster way of arriving.
##
## Sized against what the district actually affords rather than against a figure that
## sounded right: the deepest tile either park offers stands 22.5m off a road, so a
## threshold above that would ask for ground the map does not have and the call would
## silently never open. It is tight without a helicopter, not impossible -- the same
## bargain [constant BUILDING_SIZE] strikes, and for the same reason.
func _spawn_remote_medical() -> void:
	var spot := _pick_parkland()
	if spot == Vector3.INF:
		return
	var casualty := _spawn_casualty(spot, "Collapse in the park, no vehicle access")
	if casualty == null:
		return
	# Steeper than the street collapse, because here the distance is the difficulty and a
	# casualty declining at the ordinary rate would simply wait out the walk.
	casualty.decline_per_second *= 1.5


## A fire somebody lit, with the person who lit it still standing over it.
##
## **Police work that happens to be a fire.** A bin is a fire the extinguisher in a patrol
## car can honestly deal with, so no engine is wanted; what is wanted is the second thing
## an officer does, and then a car to take the arrest in. Ungated for that reason -- every
## career starts able to answer it, and it is the only call in the table that asks one
## service to do two unrelated jobs at one scene.
func _spawn_arson() -> void:
	var spot := _pick_pavement(true)
	if spot == Vector3.INF:
		return
	var fire := _spawn_fire(spot, Fire.Kind.BIN, 0.35)
	if fire == null:
		return
	# The fire carries the flavour because [method Call.title] takes the first flavoured
	# incident it finds, and this is the one that names the job.
	fire.flavour = "Fire set deliberately, suspect on scene"
	# Far enough not to be standing in the flames, close enough that the board reads one
	# call. Through _beside, so a frontage facing the wrong way cannot put them indoors.
	var watching := _beside(spot, Vector3(3.5, 0.0, 1.5))
	if watching != Vector3.INF:
		_spawn_suspect(watching)


## A disturbance with somebody hurt in the middle of it.
##
## **The call that gives Secure something to be for.** A cordon everywhere else in this
## game is housekeeping -- it keeps the crowd off a scene that is already being dealt
## with, and the job would finish without it. Here it is the intervention: the paramedic
## cannot work in the middle of a fight, so the officers clear the ground first and
## medical follows them into it.
func _spawn_affray() -> void:
	var spot := _spawn_disorder("Affray, person injured")
	if spot == Vector3.INF:
		return
	# In among them rather than off to one side, because being in among them is the whole
	# reason the cordon is the answer. Well inside Call.GROUPING_RADIUS either way, so the
	# board reads one job rather than a disorder and a separate medical.
	var lying := _beside(spot, Vector3(0.0, 0.0, 2.6))
	if lying == Vector3.INF:
		return
	var casualty := _spawn_casualty(lying, "")
	if casualty:
		# Gentled on the trapped call's terms. The pressure here is the fight, not the
		# clock, and running both hard at once makes a scene unreadable rather than hard.
		casualty.decline_per_second *= 0.6


## Two cars written off at one junction, with three people on the road around them.
##
## **The collision at the size where the winch is the entire job.** An ordinary [code]rtc[/code]
## grows a wreck only for a career that owns a recovery truck -- see
## [method _leaves_a_wreck] for why that is a tail rather than a gate. This one is a gate,
## because there is nothing else here to do: take the wrecks away and the street opens.
##
## Everything sits within about 7m of the junction centre. [constant Call.GROUPING_RADIUS]
## is 14m to a centroid that *moves* as each incident is adopted, so a scene laid out any
## wider would arrive on the board as two calls that happen to share a crossroads.
func _spawn_pile_up(cell: Vector2i) -> void:
	var centre := CityGrid.junction(cell)
	# Lying along one of the junction's own streets, as if they arrived down it -- the
	# same arrangement the single collision and the bus use.
	var exits := CityGrid.neighbours(cell)
	var along := Vector3(0.0, 0.0, 1.0)
	if not exits.is_empty():
		var toward: Vector2i = exits[_rng.randi_range(0, exits.size() - 1)]
		along = (CityGrid.junction(toward) - centre).normalized()
	var across := Vector3(-along.z, 0.0, along.x)

	# Nose to tail, 4.5m apart: a shunt rather than two unrelated cars.
	for forward in [2.0, 6.5]:
		var wreck := _spawn("res://Game/Incidents/Wreck.tscn") as Wreck
		if wreck:
			wreck.global_position = centre + along * forward
			wreck.flavour = "Multi-vehicle collision, road blocked"

	# **Thrown clear, and further clear than a single collision throws them.** Wreck.tscn
	# carries a 5.5m blocker; with two of them a casualty has to sit outside both, which
	# the ordinary RTC's 1.6m setback does not manage -- that call learned the same lesson
	# once already, when its casualties spawned underneath its wreck and could not be
	# reached. Nearest pair here is 7.3m. Offsets are (across, along).
	for offset in [Vector2(2.0, -5.0), Vector2(-2.2, -5.0), Vector2(0.5, -7.0)]:
		var casualty := _spawn_casualty(
			centre + across * offset.x + along * offset.y, "")
		if casualty:
			# Three at once against one ambulance's two stretchers: the triage question
			# `bus_rtc` asks, so the gentler decline `bus_rtc` answers it with.
			casualty.decline_per_second *= 0.6


## A tanker down at the kerb, its load across the road, and somebody hurt past it.
##
## **The first hazard with the street shut in front of it.** The gas leak has a cylinder
## and a fire and nobody hurt; the shed load has a blocked carriageway and nothing that
## can go off. This has all three at one kerb: a tank cooking, the load down in the
## carriageway, and somebody hurt further along the same street -- so the crew are
## choosing between the thing that will explode and the thing that is in the way, while
## medical waits on which of them wins.
##
## **The fire is not decoration.** [Hazard] heats only from a [Fire] within its
## `heat_range`, and it finishes only once it has been threatened and then cooled -- so a
## tank with nothing burning near it never resolves *and* never blows, and the call would
## sit on the board until [member overrun_grace] failed it. A spill without a fire in it
## would be a hang, not a gentler call.
func _spawn_spill() -> void:
	var kerb := _pick_kerb()
	if kerb.is_empty():
		return
	var spot: Vector3 = kerb["spot"]
	var hazard := _spawn("res://Game/Incidents/Hazard.tscn") as Hazard
	if hazard == null:
		return
	hazard.global_position = spot
	hazard.flavour = "Tanker spill, road blocked"
	# Cooking it, on the gas leak's geometry: inside heat_range, far enough that the crew
	# can work one without standing in the other. Guarded, because _beside returns INF
	# when it cannot find ground and a fire placed at infinity is worse than no fire --
	# and without a fire this call cannot finish at all, see above.
	var burning := _beside(spot, Vector3(4.0, 0.0, 1.0))
	if burning != Vector3.INF:
		_spawn_fire(burning, Fire.Kind.BIN, 0.45)

	var debris := _spawn("res://Game/Incidents/Debris.tscn") as Debris
	if debris:
		debris.global_position = kerb["centre"]
	var parent := get_node_or_null(incidents_path)
	if parent:
		var truck := (load(SHED_TRUCK) as PackedScene).instantiate() as Node3D
		_strip_collision(truck)
		parent.add_child(truck)
		truck.global_position = spot
		truck.rotation.y = kerb["yaw"]
		# The truck leaves with the tank rather than with the load: the hazard is the
		# incident this scene is named for, and a lorry left parked beside a cleared road
		# reads as a bug.
		hazard.tree_exited.connect(func() -> void:
			if is_instance_valid(truck):
				truck.queue_free())

	# **Down the street from the tank, not across the road from it.** Two things go wrong
	# with the perpendicular: the kerb spot already stands 4m off the centre line, so
	# ten metres across clears the carriageway and lands inside the block opposite --
	# where _beside sweeps a metre and a half around ground that is not standable, finds
	# nothing, and the call opens with no casualty in it at all. And _beside keeps the
	# offset's *length* while turning it, so "ten metres out" is really 8.5 to 11.5 --
	# and 8.5 is inside `Hazard.blast_range` (9.0), where `blast_harm` of 1.2 against a
	# full 1.0 of health kills outright. Along the kerb line the ground is standable by
	# construction and the spread is 10.3m to 12.7m: outside the blast, inside
	# Call.GROUPING_RADIUS, so it presses without punishing.
	var down_street := Vector3(sin(kerb["yaw"]), 0.0, cos(kerb["yaw"]))
	var lying := _beside(spot + down_street * 11.5, Vector3(1.2, 0.0, 0.0))
	if lying != Vector3.INF:
		_spawn_casualty(lying, "")


## A robbery out on the pavement: two armed suspects, somebody hurt, and the takings all
## over the flagstones.
##
## **The only call in the table that no single service can finish.** A building fire wants
## two services and lets either start; this needs armed response *before* the police half
## can happen at all, because an armed suspect is offered [ApprehendAbility] by nobody --
## an ordinary officer right-clicking one gets Move. Disarm first, then the arrest is
## anybody's. The casualty is independent of all that and can be worked from the moment
## anyone arrives.
##
## **What this call is not.** The plan that proposed it called it the first scene where
## *order of arrival* is a safety question rather than a speed one. It is not, and the
## claim is written down here so nobody re-derives it from the docstring: a [Suspect]
## harms only the officer who has hands on them (`fight_harm_per_second`, applied to
## `arresting` alone), so an armed robber standing over a casualty does not endanger the
## paramedic treating them. Making that true would mean giving an armed suspect a threat
## radius, which is a real mechanic and a separate decision. What is true today is the
## gate: two weapons on the pavement is a scene that *cannot end* without the £550 unit.
##
## **The bank interior is deliberately out of scope.** [method CityGrid.standable] returns
## false inside every block footprint, so an interior needs geometry, collision and a
## windowed nav bake -- a second project, not a fallback. The job happens out front, which
## is where this kind of scene happens anyway.
func _spawn_armed_robbery() -> void:
	var spot := _pick_pavement(true)
	if spot == Vector3.INF:
		return
	var placed: Array[Node3D] = []

	# Two of them, either side of the doorway they came out of. Through _beside so a
	# frontage facing the wrong way cannot stand them inside the building.
	for offset in [Vector3(2.2, 0.0, 0.8), Vector3(-2.0, 0.0, 1.1)]:
		var where := _beside(spot, offset)
		if where == Vector3.INF:
			continue
		var robber := _spawn_suspect(where)
		if robber == null:
			continue
		robber.armed = true
		# Only the first carries the flavour: [method Call.title] takes the first it finds,
		# and two identical strings would be one line of luck away from reading oddly.
		if placed.is_empty():
			robber.flavour = "Armed robbery, suspects on scene"
		placed.append(robber)
	# **No suspects means no call.** Every other spawner here tolerates a partial scene,
	# because a fire with no casualty is still a fire -- but a robbery with nobody to
	# disarm is a casualty call wearing a robbery's name, and it would open on a career
	# that was gated into seeing it precisely because it can answer the armed half.
	if placed.is_empty():
		return

	# Somebody caught in it. Ordinary decline: the pressure on this call is the two
	# weapons, and running the clock hard as well would make it unreadable rather than
	# hard -- the same judgement the collapse and the affray make.
	var hurt := _beside(spot, Vector3(0.4, 0.0, 3.2))
	if hurt != Vector3.INF:
		var casualty := _spawn_casualty(hurt, "")
		if casualty:
			placed.append(casualty)

	_scatter_heist_props(spot, placed)


## The takings and the broken glass, laid round [param spot] and freed once every incident
## in [param placed] has left the scene.
##
## Collision-stripped and script-free, exactly as the shed load's truck and the bus
## collision's bus are: these are scenery, and a prop with a body in it would stall a
## patrol car on its way to the arrest. Freed on the *last* incident rather than the first,
## on the bus collision's own reasoning -- a half-worked scene keeps its dressing.
func _scatter_heist_props(spot: Vector3, placed: Array[Node3D]) -> void:
	var parent := get_node_or_null(incidents_path)
	if parent == null or placed.is_empty():
		return
	var dressing: Array[Node3D] = []
	for i in HEIST_PROPS.size():
		# Fanned on a circle rather than randomly, so nothing lands inside anything else
		# and the scatter reads as one dropped bag rather than a pile.
		var angle := TAU * float(i) / float(HEIST_PROPS.size())
		var where := _beside(spot, Vector3(sin(angle), 0.0, cos(angle)) * 1.9)
		if where == Vector3.INF:
			continue
		var prop := (load(str(HEIST_PROPS[i])) as PackedScene).instantiate() as Node3D
		if prop == null:
			continue
		_strip_collision(prop)
		parent.add_child(prop)
		prop.global_position = where
		prop.rotation.y = _rng.randf_range(0.0, TAU)
		dressing.append(prop)
	if dressing.is_empty():
		return
	# The captured Array is scanned by reference -- an int counter would be a copy, which
	# is the trap the bus collision's own lambda records falling into.
	for incident in placed:
		incident.tree_exited.connect(func() -> void:
			for other in placed:
				if is_instance_valid(other) and other.is_inside_tree():
					return
			for prop in dressing:
				if is_instance_valid(prop):
					prop.queue_free())


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
		# Never the child of a missing-child call: taking them frees a body its report
		# is scanning for, and the search would close itself as a job done.
		if civilian is ChildWanderer:
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
	return _road_gap(point) < 8.0


## How far [param point] lies from the nearest road's centre line.
##
## Extracted from [method _roadside] rather than copied into [method _pick_parkland],
## because the two want the same measurement and different thresholds: "against a road"
## and "far enough in that the answer is a walk" are one number read twice.
func _road_gap(point: Vector3) -> float:
	var nearest := INF
	for band in CityGrid.BANDS:
		nearest = minf(nearest, minf(
			absf(point.x - CityGrid.band_centre_x(band)),
			absf(point.z - CityGrid.band_centre_z(band))))
	return nearest


## How deep into a park a call has to open before answering it means walking.
##
## **Set from the map, not from taste.** [method CityGrid.pavement_points] offers every
## tile of a park block, and the deepest either park has stands 22.5m off a road -- so a
## threshold at, say, 25 would ask for ground the district does not contain and
## [method _pick_parkland] would return INF for ever, which is a call that silently never
## opens. 16.0 is two tiles past the ring and leaves both parks with candidates.
const PARK_DEPTH := 16.0


## A pavement tile deep enough inside a park that no vehicle can pull up to it.
##
## The inverse of [method _pick_pavement]'s `roadside` filter rather than a second copy
## of it: same candidate list, same [method _clear] funnel, opposite question -- and a
## different threshold, because "not roadside" is only 8m and a tile one ring in is a
## two-second walk, not a reason to own a helicopter.
func _pick_parkland() -> Vector3:
	var candidates: Array[Vector3] = []
	for point in CityGrid.pavement_points():
		if _road_gap(point) < PARK_DEPTH:
			continue
		if _clear(point):
			candidates.append(point)
	if candidates.is_empty():
		return Vector3.INF
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


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
