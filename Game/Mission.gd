extends Node
class_name Mission

## Watches the incidents and decides whether the shout is going well.
##
## Deliberately passive: it reads the world and reports, rather than being told. Any
## incident that appears later -- a fire spreading, a new casualty -- is picked up
## automatically, so nothing has to remember to register with it.
##
## Two modes. Incident play outside a shift is judged on incidents: won when the map
## is clear, lost the moment a casualty dies -- rules that today only the test suite
## exercises, since the shipped map is quiet. A freeplay shift is judged on **calls**
## -- this is where the board stops being a view and becomes what the game is scored
## on. Points per call resolved, weighted by how fast someone reached it; a penalty
## per casualty lost, which costs the score rather than the shift.

enum State { RUNNING, WON, LOST, OVER }

signal state_changed(state: State)
## Emitted whenever a tally moves, so the HUD can redraw without polling every frame.
signal progress_changed

## Losing anyone ends the shout. Freeplay turns this off: there, a loss is points.
@export var fail_on_casualty_lost := true
## Where the calls are scored from. Optional -- a map without a board still runs the
## scripted win/lose rules; it just cannot run a scored shift.
@export var call_board_path: NodePath

## Where the best shift is banked between sessions -- the project's first save-shaped
## thing (the menu's settings file is the second). A var rather than a const so the
## test suite can point it at a disposable file instead of writing records the player
## then has to beat.
var records_path := "user://records.cfg"

## Points per fire put out and per casualty delivered, tallied as they resolve.
const FIRE_POINTS := 50
const CASUALTY_POINTS := 100
## Per suspect booked in at the station. Between the two: more than property, and
## a disturbance cannot be lost, so it never carries a casualty's stakes.
const ARREST_POINTS := 75
## Per gas cylinder cooled before it went off. Between a fire and an arrest: it is a
## disaster prevented rather than a job finished, and the reward for preventing it is
## mostly that the disaster did not happen.
const HAZARD_POINTS := 60
## Per shed load cleared off the carriageway. The cylinder's number and the cylinder's
## reasoning: an obstruction removed is a disaster prevented, not a job finished.
const DEBRIS_POINTS := 60
## Per missing child found. Between an arrest and a delivered casualty: a person
## recovered, without the ambulance run that makes a delivery the dearer job.
const MISSING_POINTS := 90
## Per wreck winched off the road.
##
## **This paid nothing at all until August 2026**, and nobody noticed because the arm was
## simply missing: the chain below tests `is Debris`, and [Wreck] extends [Incident]
## directly rather than extending Debris, so it matched no branch and fell out of the
## scoring entirely. The one job the £700 recovery truck exists to do earned neither a
## point nor a penny -- which compounded the other half of the same bug, since the truck
## was also the only way to close the collision that demanded it.
##
## Dearer than a shed load's 60: that is two pairs of hands for about five seconds, while
## this is ten seconds of winching from a unit that had to be bought first. It sits with
## the missing child, which is the other "one specialist, one long job" number.
const WRECK_POINTS := 90
## What a lost casualty costs. More than a delivery earns, so a shift that loses one
## for every save is running at a loss.
const LOST_PENALTY := 150
## On top, each call cleared earns a response bonus scaled by how long it waited for
## the first unit: full inside the grace, sliding down to the floor.
const RESPONSE_BONUS := 100
const RESPONSE_GRACE := 10.0
const RESPONSE_DECAY := 90.0
const RESPONSE_FLOOR := 0.25

var state: State = State.RUNNING
var fires_out := 0
var casualties_saved := 0
var casualties_lost := 0
var arrests := 0
var hazards_made_safe := 0
var lanes_cleared := 0
## Wrecks winched off the road. See [constant WRECK_POINTS].
var wrecks_cleared := 0
var children_found := 0
var elapsed := 0.0

## Freeplay. While true the incident-based win/lose rules are off: nothing is won by
## an empty map between calls, and a loss is charged to the score instead.
var scoring := false
var score := 0
var calls_cleared := 0
var calls_failed := 0
## Crew of the player's own hurt badly enough to go down, and how they ended up.
var crew_lost := 0
var crew_recovered := 0
## Seconds each cleared call waited before a crew reached it, summed. The debrief
## divides it by [member calls_cleared] for the shift's average response.
##
## Free to collect: the call has recorded the age at which its status first turned
## ON_SCENE since the response bonus was written, and that bonus is already paid off
## exactly this number. It was simply being used and thrown away.
var response_total := 0.0
## The response bonus those cleared calls were worth, summed. Freeplay pays it into
## [member score] as each call closes; a scripted shout has no purse and no records,
## but it still wants to say that turning out fast was worth something -- so the same
## number is banked here for [method shout_score] and simply ignored by the shift.
var response_earned := 0
## Money banked this shift. Every positive scoring event pays the same number in
## pounds into the station's purse -- one table, two readouts. Losses cost score
## only: fining a struggling career into bankruptcy would spiral, and having
## nothing left to buy units with is already the punishment.
var earned := 0

var _station: Station
## The record to beat, read from [member records_path] at start. 0 until a shift
## has ever been banked.
var best_score := 0
## True when the shift that just ended set the record, so the debrief can say so.
var is_new_best := false

## Guards against declaring victory on an empty map before anything has spawned.
var _seen_incident := false

## Set by a scripted shout that opens in stages: the map goes clear between them,
## and the scripted win rule reads a clear map as a job done. Without this the
## tutorial congratulated the player halfway through the lesson. Freeplay never
## touches it -- there the Director owns the shift and `scoring` short-circuits the
## whole rule.
var more_to_come := false

## The time a designed scenario is meant to be beaten in, in seconds. Zero for
## everything else, and the debrief simply leaves the row out -- freeplay is judged on
## a clock it already shows, and the tutorial is not a race.
var par_seconds := 0.0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		_watch(node)
	var board := get_node_or_null(call_board_path) as CallBoard
	if board:
		board.call_closed.connect(_on_call_closed)
	_load_records()


func _process(delta: float) -> void:
	if state == State.RUNNING:
		elapsed += delta


func fires_remaining() -> int:
	return _count_active(&"fires")


func casualties_remaining() -> int:
	return _count_active(&"casualties")


## "04:31" for the HUD.
func elapsed_text() -> String:
	return _clock_text(elapsed)


## Any number of seconds as mm:ss. The debrief's par row says two of them.
static func _clock_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


# --- Freeplay ----------------------------------------------------------------

## Starts a scored shift: tallies to zero, the incident win/lose rules off. Called by
## the Director when the shift opens.
## Everything a fresh start zeroes, without deciding what kind of start it is.
##
## Pulled out of [method begin_scoring] so a scripted scenario can open on a clean
## sheet too: it wants the tallies reset and the scoring left off, which was exactly
## the half of that function it could not have.
func reset_tallies() -> void:
	score = 0
	calls_cleared = 0
	calls_failed = 0
	crew_lost = 0
	crew_recovered = 0
	response_total = 0.0
	response_earned = 0
	fires_out = 0
	casualties_saved = 0
	casualties_lost = 0
	arrests = 0
	hazards_made_safe = 0
	lanes_cleared = 0
	wrecks_cleared = 0
	children_found = 0
	earned = 0
	elapsed = 0.0
	is_new_best = false
	# The repair tally belongs to the run, and the station keeps it -- the mission only
	# reports it. Zeroed here so a debrief never charges for a previous one.
	if _found_station():
		_station.repairs_paid = 0
	# The guard against declaring victory on a map nothing has spawned on yet. It has
	# to go back with the tallies, or a second scenario opens with the first one's
	# memory of having seen an incident and can be won by an empty district.
	_seen_incident = false


func begin_scoring() -> void:
	scoring = true
	reset_tallies()
	# A shift is not run against a designed par, and one left over from a scenario the
	# player tried earlier would put a row on the debrief that means nothing.
	par_seconds = 0.0
	# Also clears the banner from a finished scripted shout, via the state change.
	_set_state(State.RUNNING)
	progress_changed.emit()


## The shift is over. Only the Director knows when that is -- the map being clear
## means nothing here, because it is clear between every pair of calls.
##
## The record is settled before the state change, because the state change is what
## makes the HUD read [method summary].
func end_shift() -> void:
	if not scoring:
		return
	is_new_best = score > best_score
	if is_new_best:
		best_score = score
		_save_records()
	_set_state(State.OVER)


## The debrief line under the banner.
func summary() -> String:
	var parts := PackedStringArray()
	parts.append("SCORE %d" % score)
	parts.append("NEW BEST" if is_new_best else "BEST %d" % best_score)
	parts.append("£%d earned" % earned)
	parts.append("%d call%s cleared, %d failed"
		% [calls_cleared, "" if calls_cleared == 1 else "s", calls_failed])
	parts.append("%d delivered, %d lost, %d fire%s out"
		% [casualties_saved, casualties_lost, fires_out, "" if fires_out == 1 else "s"])
	# Only a shift that made one mentions arrests; most debriefs have nothing to say.
	if arrests > 0:
		parts.append("%d arrest%s" % [arrests, "" if arrests == 1 else "s"])
	if hazards_made_safe > 0:
		parts.append("%d cylinder%s cooled"
			% [hazards_made_safe, "" if hazards_made_safe == 1 else "s"])
	if lanes_cleared > 0:
		parts.append("%d shed load%s cleared"
			% [lanes_cleared, "" if lanes_cleared == 1 else "s"])
	if wrecks_cleared > 0:
		parts.append("%d wreck%s recovered"
			% [wrecks_cleared, "" if wrecks_cleared == 1 else "s"])
	if children_found > 0:
		parts.append("%d child%s found"
			% [children_found, "" if children_found == 1 else "ren"])
	return "   ·   ".join(parts)


## Mean seconds a cleared call waited before a crew reached it, or -1 when the shift
## cleared nothing and the question has no answer.
func average_response() -> float:
	return -1.0 if calls_cleared <= 0 else response_total / float(calls_cleared)


## The debrief, as label/value rows for the card to lay out.
##
## Separate from [method summary] rather than replacing it: the one-line form is what a
## scripted shout's banner uses and what the tests read, and it is a perfectly good
## sentence. This is the same shift said at length, which is what an end-of-shift screen
## is for -- a player who has just spent five to fifteen minutes on it will read a table
## and will not read a run-on sentence.
##
## Rows carry a `muted` flag for the ones that are only interesting when non-zero: a
## clean shift should not shout about the nothing it lost.
## Finds the station if it has not already, and says whether there is one. The mission is
## a passive watcher, so nothing hands it the station; it goes looking the first time it
## needs it.
func _found_station() -> bool:
	if _station == null or not is_instance_valid(_station):
		_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	return _station != null


## What a scripted shout came to, in freeplay's own currency.
##
## A shout runs with `scoring` off -- no purse, no records, no shift clock -- so
## [member score] stays at zero throughout and would be a lie on a card. This adds the
## same table up from the tallies instead, response bonus included, so the number a
## player is shown for clearing a job means the same thing whichever mode they were in.
## Nothing is paid and no record is set: it is a mark, not a wage.
func shout_score() -> int:
	var total := fires_out * FIRE_POINTS \
		+ casualties_saved * CASUALTY_POINTS \
		+ arrests * ARREST_POINTS \
		+ hazards_made_safe * HAZARD_POINTS \
		+ lanes_cleared * DEBRIS_POINTS \
		+ wrecks_cleared * WRECK_POINTS \
		+ children_found * MISSING_POINTS \
		+ response_earned \
		- casualties_lost * LOST_PENALTY
	# A shout that went badly enough to owe points owes nothing: the lesson is the
	# casualty they lost, and it is named on its own row directly underneath.
	return maxi(total, 0)


## The end of a scripted shout, as rows for the card.
##
## Deliberately shorter than [method debrief_rows]. A shift is a career event and reads
## its money, its record and its repairs; a shout is one job, and the only questions it
## answers are what it was worth, how long it took, and what was actually done. Rows for
## work nobody did are left out rather than shown as zero -- the tutorial's two-stage
## shout would otherwise be four fifths a list of things that never happened.
func shout_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append({"label": "Score", "value": str(shout_score())})
	rows.append({"label": "Time", "value": elapsed_text()})
	# Only a designed scenario carries a par, and only then is the row worth a line.
	# Said as a margin rather than as the target: "1:12 under" is the thing the player
	# wants to know, and "beat par 4:00" makes them do the subtraction.
	if par_seconds > 0.0:
		var margin := par_seconds - elapsed
		rows.append({"label": "Par %s" % _clock_text(par_seconds),
			"value": "%s %s" % [_clock_text(absf(margin)),
				"under" if margin >= 0.0 else "over"],
			"muted": margin < 0.0})
	var mean := average_response()
	rows.append({"label": "Average response",
		"value": "—" if mean < 0.0 else "%.0fs" % mean})
	if casualties_saved > 0 or casualties_lost > 0:
		rows.append({"label": "Casualties delivered", "value": str(casualties_saved),
			"note": "" if casualties_lost == 0 else "%d lost" % casualties_lost,
			"muted": casualties_lost == 0})
	if fires_out > 0:
		rows.append({"label": "Fires out", "value": str(fires_out)})
	if arrests > 0:
		rows.append({"label": "Arrests", "value": str(arrests)})
	if hazards_made_safe > 0:
		rows.append({"label": "Cylinders cooled", "value": str(hazards_made_safe)})
	if lanes_cleared > 0:
		rows.append({"label": "Shed loads cleared", "value": str(lanes_cleared)})
	if wrecks_cleared > 0:
		rows.append({"label": "Wrecks recovered", "value": str(wrecks_cleared)})
	if children_found > 0:
		rows.append({"label": "Children found", "value": str(children_found)})
	# The same argument the shift card makes: crew hurt is a cost that would otherwise
	# only show up as a short roster later.
	if crew_lost > 0 or crew_recovered > 0:
		rows.append({"label": "Crew down", "value": str(crew_lost + crew_recovered),
			"note": "" if crew_lost == 0 else "%d lost" % crew_lost,
			"muted": crew_lost == 0})
	return rows


func debrief_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append({"label": "Score", "value": str(score),
		"note": "new best" if is_new_best else "best %d" % best_score})
	rows.append({"label": "Earned", "value": "£%d" % earned})
	rows.append({"label": "Calls cleared", "value": str(calls_cleared),
		"note": "" if calls_failed == 0 else "%d failed" % calls_failed,
		"muted": calls_failed == 0})
	var mean := average_response()
	rows.append({"label": "Average response",
		"value": "—" if mean < 0.0 else "%.0fs" % mean})
	rows.append({"label": "Casualties delivered", "value": str(casualties_saved),
		"note": "" if casualties_lost == 0 else "%d lost" % casualties_lost,
		"muted": casualties_lost == 0})
	# Repairs sit directly under what the shift earned, because that is the comparison
	# worth making: a shift can be busy, well scored and still cost more than it brought
	# in if it was driven badly.
	if _found_station() and _station.repairs_paid > 0:
		var owed := _station.outstanding_repairs()
		rows.append({"label": "Repairs", "value": "-£%d" % _station.repairs_paid,
			"note": "" if owed <= 0 else "£%d still owed" % owed, "muted": owed <= 0})
	# Where losing your own people is said out loud. Not scored -- see `_on_resolved` --
	# so if the debrief did not name it, the cost would be invisible until the player
	# noticed the roster was short.
	if crew_lost > 0 or crew_recovered > 0:
		rows.append({"label": "Crew down", "value": str(crew_lost + crew_recovered),
			"note": "" if crew_lost == 0 else "%d lost" % crew_lost,
			"muted": crew_lost == 0})
	if fires_out > 0:
		rows.append({"label": "Fires out", "value": str(fires_out)})
	if arrests > 0:
		rows.append({"label": "Arrests", "value": str(arrests)})
	if hazards_made_safe > 0:
		rows.append({"label": "Cylinders cooled", "value": str(hazards_made_safe)})
	if lanes_cleared > 0:
		rows.append({"label": "Shed loads cleared", "value": str(lanes_cleared)})
	if wrecks_cleared > 0:
		rows.append({"label": "Wrecks recovered", "value": str(wrecks_cleared)})
	if children_found > 0:
		rows.append({"label": "Children found", "value": str(children_found)})
	return rows


## The best shift survives the window closing. ConfigFile rather than anything
## fancier: one section, one key, human-readable on disk.
func _load_records() -> void:
	var records := ConfigFile.new()
	if records.load(records_path) == OK:
		best_score = int(records.get_value("freeplay", "best_score", 0))


func _save_records() -> void:
	var records := ConfigFile.new()
	records.set_value("freeplay", "best_score", best_score)
	records.save(records_path)


## Counted whether or not the shift is scored, and paid only when it is.
##
## The tallies used to sit behind the `scoring` gate with the money, which left a
## scripted shout unable to say how long anyone waited for it -- the figures existed
## and were thrown away. They are facts about the mission rather than facts about the
## shift, and [method begin_scoring] zeroes every one of them, so freeplay still opens
## on a clean sheet.
func _on_call_closed(call: Call, success: bool) -> void:
	if success:
		calls_cleared += 1
		response_total += call.response_age if call.response_age >= 0.0 else call.age
		response_earned += _response_bonus(call)
	else:
		calls_failed += 1
	if scoring and success:
		var bonus := _response_bonus(call)
		score += bonus
		_pay(bonus)
	progress_changed.emit()


## Money follows the points, into the station's purse. The station is found by group
## rather than by an exported path because the Playground scene is generated, and a
## lazy lookup spares the generator learning a new wire.
func _pay(amount: int) -> void:
	earned += amount
	if _found_station():
		_station.earn(amount)


## Full marks for reaching the scene inside the grace, sliding to the floor for a call
## that sat waiting. A call that closed without ever being attended -- which only a
## failure can -- scores off its whole age, which lands on the floor where it belongs.
func _response_bonus(call: Call) -> int:
	var waited := call.response_age if call.response_age >= 0.0 else call.age
	var weight := clampf(
		1.0 - maxf(waited - RESPONSE_GRACE, 0.0) / RESPONSE_DECAY,
		RESPONSE_FLOOR, 1.0)
	return roundi(RESPONSE_BONUS * weight)


# --- Watching ----------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	_watch(node)


func _watch(node: Node) -> void:
	var incident := node as Incident
	if incident == null or incident.resolved.is_connected(_on_resolved):
		return
	_seen_incident = true
	incident.resolved.connect(_on_resolved)
	progress_changed.emit()


func _on_resolved(incident: Incident, success: bool) -> void:
	if incident is Fire:
		if success:
			fires_out += 1
			if scoring:
				score += FIRE_POINTS
				_pay(FIRE_POINTS)
	elif incident is Casualty:
		# **One of the player's own is scored differently: not at all.** Delivering a
		# firefighter you got hurt should not pay £100 for the privilege, and losing one
		# should not be fined on top of losing a unit the career paid for. The punishment
		# is the write-off, and it is legible in the debrief. Same argument the Hazard
		# arm below makes about not charging twice for one mistake.
		var own := (incident as Casualty).was_crew
		if success:
			if own:
				crew_recovered += 1
			else:
				casualties_saved += 1
				if scoring:
					score += CASUALTY_POINTS
					_pay(CASUALTY_POINTS)
		elif own:
			crew_lost += 1
		else:
			casualties_lost += 1
			if scoring:
				score -= LOST_PENALTY
	elif incident is Suspect:
		# There is no failure arm: a disturbance cannot be lost, only left standing.
		if success:
			arrests += 1
			if scoring:
				score += ARREST_POINTS
				_pay(ARREST_POINTS)
	elif incident is Hazard:
		# No failure arm on purpose. A cylinder that goes off costs the player through
		# everything it does -- the call fails, the casualties it makes cost 150 each,
		# and the fires it throws still have to be put out. Charging again here would be
		# fining them twice for one mistake.
		if success:
			hazards_made_safe += 1
			score += HAZARD_POINTS
			_pay(HAZARD_POINTS)
	elif incident is Debris:
		# No failure arm because there is no failure: a shed load cannot be lost, only
		# left sitting there with the street shut around it.
		if success:
			lanes_cleared += 1
			if scoring:
				score += DEBRIS_POINTS
				_pay(DEBRIS_POINTS)
	elif incident is Wreck:
		# Debris's shape, and it needs an arm of its own: [Wreck] extends [Incident],
		# not Debris, so the branch above never caught it and the winch went unpaid.
		if success:
			wrecks_cleared += 1
			if scoring:
				score += WRECK_POINTS
				_pay(WRECK_POINTS)
	elif incident is MissingChild:
		# The suspect's shape: no failure arm, because in this game a missing child is
		# never *lost* -- only still missing when the clock runs out, which the failed
		# call already counts.
		if success:
			children_found += 1
			if scoring:
				score += MISSING_POINTS
				_pay(MISSING_POINTS)

	progress_changed.emit()
	_evaluate()


func _evaluate() -> void:
	if state != State.RUNNING:
		return
	# A scored shift is judged on calls by the Director, not on the map being clear --
	# which it is between every pair of calls.
	if scoring:
		return
	if fail_on_casualty_lost and casualties_lost > 0:
		_set_state(State.LOST)
		return
	# Incident._finish() clears `active` before it emits, so the one that just
	# resolved is already excluded from this count.
	if _seen_incident and not more_to_come and _count_active(Incident.GROUP) == 0:
		_set_state(State.WON)


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(state)


func _count_active(group: StringName) -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(group):
		var incident := node as Incident
		if incident and incident.active:
			total += 1
	return total
