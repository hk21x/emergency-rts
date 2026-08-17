extends RefCounted
class_name Scenarios

## The designed shifts, as data.
##
## Freeplay produces *rolled* shifts: the director picks a kind by weight, places it
## where the lattice allows, and the shape of an evening is whatever the dice did. A
## scenario is the other thing -- a shift somebody wrote down. Three of them here, each
## a timeline of calls with a par time to beat.
##
## They are deliberately thin. Every call kind already knows how to place itself
## sensibly on the district ([method Director.open_kind], sixteen of them), the mission
## already scores a scripted shout and declares it won when the map goes clear, and the
## debrief modal already exists to say what it came to. A scenario is a list of times
## and kinds; the machinery underneath it is the game.
##
## Adding one is adding a dictionary. `waves` is read in order and the times are
## absolute seconds from the start, so a scenario that wants two calls at once gives
## them the same `at`.

## What a scenario can insist the career already owns before it will start. A building
## fire nobody can fight is not a hard scenario, it is a broken one -- the same
## argument the freeplay director's `needs_fire_service` gating makes, made once at the
## door instead of on every roll.
const NEEDS_FIRE := [&"engine", &"firefighter"]
const NEEDS_MEDICAL := [&"ambulance", &"paramedic"]
const NEEDS_POLICE := [&"patrol", &"officer"]

const ALL := [
	{
		"id": &"night_shift",
		"name": "SATURDAY NIGHT",
		"brief": "A disturbance outside the pub, a drunk nobody can diagnose from "
			+ "the pavement, and a runner. Police work, start to finish.",
		"par": 180.0,
		"requires": NEEDS_POLICE,
		"waves": [
			{"at": 3.0, "kinds": [&"disorder"]},
			{"at": 25.0, "kinds": [&"drunk"]},
			{"at": 55.0, "kinds": [&"crime"]},
		],
	},
	{
		"id": &"ring_road",
		"name": "RING ROAD PILE-UP",
		"brief": "A bus and a car at the junction, a load down across the "
			+ "carriageway behind it, and a second collision while you are still "
			+ "triaging the first.",
		"par": 240.0,
		"requires": NEEDS_MEDICAL,
		"waves": [
			{"at": 3.0, "kinds": [&"bus_rtc"]},
			{"at": 20.0, "kinds": [&"shed_load"]},
			{"at": 65.0, "kinds": [&"rtc"]},
		],
	},
	{
		"id": &"warehouse",
		"name": "WAREHOUSE ALIGHT",
		"brief": "A building well alight with people still inside. The crew cut them "
			+ "out, the paramedics take them on -- and the fire does not wait for "
			+ "either of you.",
		"par": 300.0,
		# Both services: the trapped call is the one that wants the crew to have
		# *finished* before a paramedic can start, so it needs each of them.
		"requires": NEEDS_FIRE + NEEDS_MEDICAL,
		"waves": [
			{"at": 3.0, "kinds": [&"building"]},
			{"at": 30.0, "kinds": [&"trapped"]},
			{"at": 75.0, "kinds": [&"medical"]},
		],
	},
]


static func by_index(index: int) -> Dictionary:
	return ALL[index] if index >= 0 and index < ALL.size() else {}


## Which of a scenario's requirements the career cannot field, as roster labels. Empty
## means it can be played. Read from the station rather than from the units on the map,
## because a unit out on a job is still owned.
static func missing_for(scenario: Dictionary, station: Station) -> Array[String]:
	var short: Array[String] = []
	if station == null:
		return short
	for id: StringName in scenario.get("requires", []):
		if station.owns(id):
			continue
		for config in Station.TYPES:
			if config["id"] == id:
				short.append(str(config["label"]))
	return short
