extends Node
class_name TutorialDirector

## The tutorial's whole script: a shout at a time.
##
## When the player first lifts the title card, a short beat passes and **one** job
## opens -- a collapsed person. Deal with it and, after another beat, the next one
## comes: a bin fire. Both at once was the first cut and it taught nothing; a player
## still learning to select a unit had two markers, two services and a fire growing
## while they read the first row. One job at a time is what a first shift is.
##
## Everything else already exists. [Mission] and [CallBoard] are passive watchers, so
## the calls appear on the board unasked, and clearing the last stage drives the
## scripted win path to the SHOUT COMPLETE card. The freeplay Director never runs
## here -- its placement funnels speak lattice, and this town has none.
##
## The one thing the staging needs from elsewhere is [member Mission.more_to_come]:
## the scripted win rule declares victory on a clear map, and a staged shout is
## briefly clear between its stages.

## Where each stage opens. Chosen from a reachability sweep of the baked meshes:
## walkable to the centimetre, and **beside** the carriageway rather than on it --
## four or five metres off, so the ambulance pulls up at the kerb and the crew walk
## the last few steps. The first pair sat in the middle of a junction, which read as
## odd and put the casualty on top of a manhole the ambulance then ground against
## for forty seconds. The 0.45 is the town's ground height, measured off the mesh.
@export var casualty_spot := Vector3(-25.0, 0.45, -35.0)
## Moved north-east in August 2026, from (-25, 25). The two jobs were 60m apart on the
## same street, which read as one incident happening twice; they are now 74m apart in
## different parts of town, and the drive out is something the player watches rather
## than a repeat of the last one. Found by the same reachability sweep as the first
## spot -- on the walking mesh, 6m off the carriageway, 54m from the station.
##
## The sweep has to ask the **regions**, not the map: both navigation meshes live on the
## world's default map and are told apart by `navigation_layers`, so
## `map_get_closest_point` answers off the union of the two and every pavement point
## reports as being on the road as well. `region_get_closest_point` is the one that can
## tell a kerb from a carriageway.
@export var fire_spot := Vector3(0.0, 0.45, 35.0)

## The pause between the card lifting and the first tone. Long enough to take in the
## town, short enough that nobody wonders whether the game has started.
@export var first_call_delay := 4.0

## The breather between a job finishing and the next one coming in. The district's
## own director takes one for the same reason: back-to-back calls read as a system
## with no sense of pace.
@export var between_calls := 6.0

## How often the teaching line is re-read from the world. Four times a second: the
## prompts follow what the player has actually done, so they are a *reading* of the
## game rather than a script of it, and a reading has to be taken again.
const TEACH_EVERY := 0.25

## Which stage is open: -1 before the player has started, then 0 and 1.
var _stage := -1
var _gap_left := 0.0
var _opened := false
var _teach_left := 0.0
var _line: Label
var _spotlight: Spotlight

## What the open job still needs **bought**, and what it needs **sent out**, as
## [constant Station.TYPES] ids.
##
## Written by [method _lesson] and read by [method _teach] a moment later, so the prompt
## and the glowing control are two renderings of one reading. The alternative -- working
## the answer out twice -- is how a tutorial ends up telling you to buy an ambulance while
## pointing at the fire engine.
var _to_buy: Array[StringName] = []
var _to_send: Array[StringName] = []


func _ready() -> void:
	_hook.call_deferred()


func _hook() -> void:
	var menu := get_node_or_null("../HUD/Root/Menu") as GameMenu
	if menu and not menu.played.is_connected(_on_played):
		menu.played.connect(_on_played)


func _process(delta: float) -> void:
	_teach_left -= delta
	if _teach_left <= 0.0:
		_teach_left = TEACH_EVERY
		_teach()

	# Only between stages, and only while there is a next one to open.
	if _stage < 0 or _stage >= _stages().size() - 1:
		return
	if _active_incidents() > 0:
		_gap_left = between_calls
		return
	_gap_left -= delta
	if _gap_left <= 0.0:
		_open_stage(_stage + 1)


func _on_played() -> void:
	if _opened:
		return
	_opened = true
	# A pausable timer on purpose: a player who opens the pause card before the tone
	# should not find the shout already old when they come back.
	await get_tree().create_timer(first_call_delay).timeout
	if not is_inside_tree():
		return
	_open_stage(0)


## The teaching line: what to do next, read off the world rather than scripted.
##
## Every prompt is a *state* the player is in, not a step they have been counted
## through -- so a player who buys the engine early, or treats before the ambulance
## has parked, is never told to undo it, and one who reloads mid-lesson picks up
## where the town actually is. It says nothing before the shift starts (the title
## card is talking) and nothing once the shout is complete (the banner is).
##
## It borrows the HUD's own mid-screen line, which the district uses for "Buy your
## first units" and a freeplay debrief. Neither runs here: `_refresh_hint` needs a
## Director and this town has none, and no shift is ever scored.
func _teach() -> void:
	if _line == null:
		_line = get_node_or_null("../HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
		if _line == null:
			return
	var say := _lesson()
	_line.text = say
	_line.visible = say != ""
	_point_at_the_next_thing()


## Glows whichever control the prompt is talking about.
##
## The order matches the words exactly: while anything is unbought the way in is the cart
## (or, once the storefront is open, the cards for the units named); once everything is
## bought the way on is the standby chip in the roster. Nothing glows during the parts of
## the lesson that are about the world rather than the interface -- treating a casualty is
## a right-click out in the street, and a glowing panel would be pointing the wrong way.
func _point_at_the_next_thing() -> void:
	if _spotlight == null:
		_spotlight = get_node_or_null("../HUD/Spotlight") as Spotlight
		if _spotlight == null:
			return
	var targets: Array[Control] = []
	var shop := get_node_or_null("../HUD/Root/Shop") as RequisitionPanel

	if not _to_buy.is_empty():
		if shop and shop.visible:
			for id in _to_buy:
				targets.append(shop.card_button(id))
		else:
			# The corner buy button was retired when the sidebar gained REQUEST UNITS;
			# the tutorial points at whichever door actually exists.
			var panel := get_node_or_null(
				"../HUD/Root/Bar/Row/RosterBlock/Body/Roster") as RosterSidebar
			targets.append(panel.request_button() if panel else null)
	elif not _to_send.is_empty():
		var roster := get_node_or_null(
			"../HUD/Root/Bar/Row/RosterBlock/Body/Roster") as RosterSidebar
		if roster:
			for id in _to_send:
				targets.append(roster.standby_chip(id))

	_spotlight.point_at(targets)


func _lesson() -> String:
	_to_buy = []
	_to_send = []
	if not _opened:
		return ""
	var mission := get_node_or_null("../Mission") as Mission
	if mission and mission.state != Mission.State.RUNNING:
		return ""
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station == null:
		return ""

	var casualty: Casualty = null
	var fire: Fire = null
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident == null or not incident.active:
			continue
		if casualty == null and incident is Casualty:
			casualty = incident
		if fire == null and incident is Fire:
			fire = incident

	if casualty:
		# The medical lesson, in the order the job actually happens.
		_note_what_is_missing(station, [&"ambulance", &"paramedic"])
		if station.total(&"ambulance") < 1 or station.total(&"paramedic") < 1:
			return "Press the  CART  button and buy an Ambulance and a Paramedic"
		if _on_the_map(&"ambulance") == 0 or _on_the_map(&"paramedic") == 0:
			return "Send them out: click their dimmed chips in  UNITS"
		if casualty.is_loaded:
			return "Drive the ambulance back to the station to hand them over"
		if casualty.is_carried:
			return "Wheel them to the ambulance"
		if casualty.is_stable:
			return "Right-click the casualty with the paramedic to carry them"
		return "Select the paramedic, then right-click the casualty to treat them"

	if fire:
		_note_what_is_missing(station, [&"engine", &"firefighter"])
		if station.total(&"engine") < 1 or station.total(&"firefighter") < 1:
			return "Press the  CART  button and buy a Fire Engine and a Firefighter"
		if _on_the_map(&"engine") == 0 or _on_the_map(&"firefighter") == 0:
			return "Send them out: click their dimmed chips in  UNITS"
		return "Select the firefighter, then right-click the fire to put it out"

	if _stage < 0:
		return "Stand by -- the first call is on its way"
	return "Stand by for the next call"


## Records which of [param ids] are still to buy and which are bought but still parked.
##
## Split into two lists rather than one, because they want pointing at different things:
## something unbought means "press the cart", something parked means "press its chip".
func _note_what_is_missing(station: Station, ids: Array[StringName]) -> void:
	for id in ids:
		if station.total(id) < 1:
			_to_buy.append(id)
		elif _on_the_map(id) == 0:
			_to_send.append(id)


## How many of [param id] are out on the map rather than sitting on the books.
func _on_the_map(id: StringName) -> int:
	return maxi(0, _station_total(id) - _station_available(id))


func _station_total(id: StringName) -> int:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station.total(id) if station else 0


func _station_available(id: StringName) -> int:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	return station.available(id) if station else 0


## The shout, in order. Built here rather than as a constant so the spots stay
## exported and tunable without a second table to keep in step.
func _stages() -> Array[Dictionary]:
	return [
		{"scene": "res://Game/Incidents/Casualty.tscn", "spot": casualty_spot,
			"flavour": "Person collapsed"},
		{"scene": "res://Game/Incidents/Fire.tscn", "spot": fire_spot,
			"flavour": "Bin fire"},
	]


func _open_stage(index: int) -> void:
	var stages := _stages()
	if index < 0 or index >= stages.size():
		return
	_stage = index
	_gap_left = between_calls
	# Told before the incident exists, so the mission is never briefly convinced the
	# shift is over while the next stage is still being built.
	var mission := get_node_or_null("../Mission") as Mission
	if mission:
		mission.more_to_come = index < stages.size() - 1
	var stage := stages[index]
	var node := _spawn(str(stage["scene"]), stage["spot"], str(stage["flavour"]))
	var fire := node as Fire
	if fire:
		fire.intensity = 0.3


## How much is still outstanding. The mission's own question, asked the same way:
## `active` is cleared before the node is freed, so a job resolved this frame is
## already out of the count.
func _active_incidents() -> int:
	var live := 0
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident and incident.active:
			live += 1
	return live


func _spawn(scene_path: String, spot: Vector3, flavour: String) -> Node3D:
	var parent := get_node_or_null("../Incidents")
	if parent == null:
		push_error("tutorial has no Incidents node to open a shout into")
		return null
	var node := (load(scene_path) as PackedScene).instantiate() as Node3D
	parent.add_child(node)
	node.global_position = spot
	var incident := node as Incident
	if incident:
		incident.flavour = flavour
	return node
