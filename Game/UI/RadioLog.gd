extends VBoxContainer
class_name RadioLog

## Dispatch traffic: the last few things that happened, fading out.
##
## The district is 260m and the camera sees about a fifth of it, so most of what a shift
## does happens where the player is not looking. The call list already shows every open
## job's *state* -- but reading it is polling, and with three calls open at once the
## player is polling constantly. This is the other half: **events, as they happen**, so
## a fire going out across town or a casualty reaching hospital arrives rather than
## having to be noticed.
##
## Deliberately **short on what earns a line.** Everything here is either a job opening,
## a crew reaching one, or a job finishing; nothing narrates a unit's journey. A log that
## announced every order would be scrolling noise inside a minute, and a readout nobody
## reads is worse than no readout -- it costs the same screen space and teaches the
## player to ignore that corner.
##
## Passive, like [Mission] and [CallBoard]: it hooks the board's signals and watches
## `SceneTree.node_added` for incidents, so nothing on the map has to know it exists.

## Lines kept on screen. Four is about what can be read at a glance during a busy
## moment; more and the oldest are gone before they are read anyway.
const MAX_LINES := 4
## Seconds a line stays at full strength, then how long it takes to fade out.
const HOLD := 7.0
const FADE := 2.5

var board: CallBoard: set = _set_board
var director: Director: set = _set_director
var station: Station: set = _set_station

## Which calls have already had their "on scene" line, by instance id.
##
## A **second** guard, and deliberately kept as one: [method Call.refresh] only emits
## `changed` when the status actually transitions, so in the shipped system this never
## fires twice anyway. It is here because the board's emit policy is not this node's to
## rely on -- one day something will emit `changed` on every tick for a good reason, and
## the failure mode is a log that reads "ON SCENE | ON SCENE | ON SCENE | ON SCENE"
## until the shift ends.
var _announced := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		_watch_incident(node)


## Puts one line on the log. Public, so anything worth announcing can say so without
## this node having to know about it first.
func say(text: String, tone := &"NotifyInfo") -> void:
	# **A framed row now, not bare text over the city.** The log used to rely on an
	# outline to stay legible against a lit street; the kit's notification frame does
	# that job properly and colours its left tab by what the line is about.
	var line := PanelContainer.new()
	line.theme_type_variation = tone
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(line)

	var words := Label.new()
	words.text = text
	words.theme_type_variation = &"PillLabel"
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)

	while get_child_count() > MAX_LINES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	# Fades on its own and takes itself away. PROCESS_MODE_PAUSABLE by inheritance, so
	# a paused game holds the last few lines on screen rather than clearing them.
	var fade := create_tween()
	fade.tween_interval(HOLD)
	fade.tween_property(line, "modulate:a", 0.0, FADE)
	fade.tween_callback(line.queue_free)


func _set_board(value: CallBoard) -> void:
	board = value
	if board == null:
		return
	if not board.call_opened.is_connected(_on_call_opened):
		board.call_opened.connect(_on_call_opened)
	if not board.call_changed.is_connected(_on_call_changed):
		board.call_changed.connect(_on_call_changed)


func _set_director(value: Director) -> void:
	director = value
	if director == null:
		return
	if not director.shift_started.is_connected(_on_shift_started):
		director.shift_started.connect(_on_shift_started)
	if not director.shift_ended.is_connected(_on_shift_ended):
		director.shift_ended.connect(_on_shift_ended)


func _set_station(value: Station) -> void:
	station = value
	if station and not station.booked_in.is_connected(_on_booked_in):
		station.booked_in.connect(_on_booked_in)


func _on_shift_started() -> void:
	say("CONTROL — shift begins", &"NotifyInfo")


func _on_shift_ended() -> void:
	say("CONTROL — all units stand down", &"NotifyInfo")


func _on_call_opened(call: Call) -> void:
	say("CONTROL — %s, %s" % [call.title(), call.place], &"NotifyWarning")


## The one line that is about a *crew* rather than a job, and the reason the log exists
## at all: until now nothing confirmed that an order had actually landed.
func _on_call_changed(call: Call) -> void:
	if call.status != Call.Status.ON_SCENE:
		return
	var id := call.get_instance_id()
	if _announced.has(id):
		return
	_announced[id] = true
	say("ON SCENE — %s" % call.place, &"NotifyInfo")


func _on_booked_in(_vehicle: Vehicle, count: int) -> void:
	say("STATION — %d booked in" % count, &"NotifySuccess")


func _on_node_added(node: Node) -> void:
	if node is Incident:
		_watch_incident(node)


func _watch_incident(node: Node) -> void:
	var incident := node as Incident
	if incident and not incident.resolved.is_connected(_on_incident_resolved):
		incident.resolved.connect(_on_incident_resolved)


## Outcomes, per incident rather than per call. A call closing is not announced
## separately: for a one-incident job the outcome *is* the closure, and for a spreading
## fire one line per node put out is the thing worth hearing.
func _on_incident_resolved(incident: Incident, success: bool) -> void:
	_announced.erase(incident.get_instance_id())
	if incident is Fire:
		if success:
			say("FIRE — knocked down", &"NotifySuccess")
	elif incident is Casualty:
		say("MEDICAL — casualty delivered" if success else "MEDICAL — casualty lost",
			&"NotifySuccess" if success else &"NotifyDanger")
	elif incident is Suspect and success:
		say("POLICE — suspect in custody", &"NotifySuccess")
	elif incident is Hazard:
		# The failure is worth saying out loud, unlike a fire's. A cylinder going off is
		# the one outcome here that happens *to* the player rather than being something
		# they failed to finish, and it is going to be followed by fires and casualties
		# they did not ask for.
		say("FIRE — cylinder made safe" if success else "FIRE — CYLINDER EXPLODED",
			&"NotifySuccess" if success else &"NotifyDanger")
