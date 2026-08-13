extends Node
class_name Call

## One job: everything at one place that needs dealing with, as the player thinks of it.
##
## An [Incident] is a body on the ground or a thing on fire. A call is the *shout* --
## a kind, an address, an age, and a state. It groups the incidents at a scene so a fire
## that spreads into four bodies stays one row on the board rather than four, which is
## the whole reason it exists.
##
## Deliberately thin. It owns no behaviour of its own: the fire still spreads, the
## casualty still declines, and the call only watches. That keeps every incident test
## true and means the board cannot be the thing that breaks a shout.

signal changed(call: Call)
signal closed(call: Call, success: bool)

const GROUP := &"calls"

## Two incidents within this of each other are one job. A fire spreads 5m at a time and
## a casualty lies beside the thing that hurt them, so this has to comfortably cover a
## scene -- but not so much that a shout on the next block gets swallowed into it.
const GROUPING_RADIUS := 14.0
## A commanded unit this close counts as attending.
const ON_SCENE_RADIUS := 15.0

enum Kind {
	## Someone hurt, and nothing burning.
	MEDICAL,
	## Fire, and nobody hurt.
	FIRE,
	## Both. The one that actually needs two services.
	RESCUE,
	## Somebody causing trouble. A police job start to finish.
	CRIME,
}

enum Status { WAITING, ON_SCENE, RESOLVED, FAILED }

var kind: Kind = Kind.MEDICAL
var status: Status = Status.WAITING
## Street address, from CityGrid.
var place := ""
## Where to send the camera. The centre of the scene, not of any one incident.
var position := Vector3.ZERO
## Seconds since the call opened, counted in game frames rather than wall clock so a
## headless run -- which processes frames far faster than 60 a second -- measures the
## same thing a played one does.
var age := 0.0
## The age at which a unit first arrived, or -1 while nobody has. This is what the
## response is scored on: the gap between the call opening and someone reaching it,
## not whether it was eventually dealt with.
var response_age := -1.0

var incidents: Array[Incident] = []

## Whether anything was ever added. Distinguishes "the scene is clear" from "this call
## has not been given its incident yet", which are the same empty list.
var _adopted := false


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if not is_open():
		return
	age += delta
	_prune()

	# An incident that is freed rather than resolved -- the map being cleared, a scene
	# being torn down -- emits nothing, so without this the call it belonged to would
	# sit on the board forever holding a list of dangling references.
	if _adopted and incidents.is_empty():
		_finish(Status.RESOLVED, true)
		return

	var wanted := Status.ON_SCENE if _attended() else Status.WAITING
	if wanted != status:
		status = wanted
		if status == Status.ON_SCENE and response_age < 0.0:
			response_age = age
		changed.emit(self)


## Takes an incident into this call and re-reads the scene from what it now holds.
func adopt(incident: Incident) -> void:
	if incident == null or incidents.has(incident):
		return
	incidents.append(incident)
	_adopted = true
	incident.resolved.connect(_on_resolved)
	_recentre()
	changed.emit(self)


## True while there is still something here to deal with.
func is_open() -> bool:
	return status == Status.WAITING or status == Status.ON_SCENE


## Whether [param point] belongs to this call rather than to a new one.
func covers(point: Vector3) -> bool:
	return is_open() and _flat(position - point) < GROUPING_RADIUS


func title() -> String:
	# An incident that knows what happened names the job -- "Road traffic collision"
	# rather than the "Medical emergency" its casualties would otherwise read as.
	for incident in incidents:
		if is_instance_valid(incident) and incident.flavour != "":
			return incident.flavour
	match kind:
		Kind.FIRE: return "Fire"
		Kind.RESCUE: return "Fire, casualty reported"
		Kind.CRIME: return "Disturbance"
		_: return "Medical emergency"


## What is at the scene, for the board's second column.
##
## One incident says how it is doing ("well alight"); several are counted by kind
## ("3 fires, 1 casualty"). It used to join every incident's own state, so a fire
## that had spread six times read as six percentages in a row -- unreadable, and
## the reason [method progress] and its bar exist.
func describe() -> String:
	if status == Status.RESOLVED:
		return "clear"
	if status == Status.FAILED:
		return "casualty lost"

	var live: Array[Incident] = []
	var fires := 0
	var hurt := 0
	var rowdy := 0
	var cylinders := 0
	for incident in incidents:
		if not is_instance_valid(incident) or not incident.active:
			continue
		live.append(incident)
		if incident is Fire:
			fires += 1
		elif incident is Casualty:
			hurt += 1
		elif incident is Hazard:
			cylinders += 1
		elif incident is Suspect:
			rowdy += 1

	if live.size() == 1:
		return live[0].describe_state()
	var parts := PackedStringArray()
	if fires > 0:
		parts.append("%d fire%s" % [fires, "" if fires == 1 else "s"])
	if hurt > 0:
		parts.append("%d casualt%s" % [hurt, "y" if hurt == 1 else "ies"])
	if rowdy > 0:
		parts.append("%d suspect%s" % [rowdy, "" if rowdy == 1 else "s"])
	if cylinders > 0:
		parts.append("%d cylinder%s" % [cylinders, "" if cylinders == 1 else "s"])
	return ", ".join(parts)


## How far through the whole scene the crews are, 0 to 1 -- the mean of what each
## incident reports. This is the number the board draws as a bar.
func progress() -> float:
	var total := 0.0
	var live := 0
	for incident in incidents:
		if not is_instance_valid(incident) or not incident.active:
			continue
		total += incident.progress()
		live += 1
	return total / live if live > 0 else 0.0


func age_text() -> String:
	var seconds := roundi(age)
	return "%d:%02d" % [seconds / 60, seconds % 60]


# --- Watching ----------------------------------------------------------------

## A call closes when the last of its incidents does, and it closes *failed* if any of
## them was lost. Getting three of four casualties out is not a job well done.
func _on_resolved(_incident: Incident, success: bool) -> void:
	if not success:
		_finish(Status.FAILED, false)
		return
	# Deferred: Incident clears its own `active` flag before emitting, but the node is
	# freed at the end of the frame, so a sibling resolving in the same frame would
	# otherwise still read as outstanding.
	_check_finished.call_deferred()


func _check_finished() -> void:
	if not is_open():
		return
	_prune()
	for incident in incidents:
		if incident.active:
			return
	_finish(Status.RESOLVED, true)


## Closes this call as unfinished, because the shift ran out of time to do it.
##
## Not a resolution and not a lost casualty: the job was simply still there when the
## clock stopped, which is what the director calls at its overrun deadline. Public
## because the decision is the shift's, not the call's -- nothing here can tell whether
## a job is merely slow or genuinely impossible.
func abandon() -> void:
	_finish(Status.FAILED, false)


func _finish(final: Status, success: bool) -> void:
	if not is_open():
		return
	status = final
	closed.emit(self, success)


## Drops incidents that have been freed, so nothing here holds a dangling reference.
func _prune() -> void:
	var alive: Array[Incident] = []
	for incident in incidents:
		if is_instance_valid(incident):
			alive.append(incident)
	incidents = alive


## Kind and position both come from what is actually at the scene, so a medical call
## that catches fire becomes a rescue without anyone having to say so.
func _recentre() -> void:
	var centre := Vector3.ZERO
	var burning := false
	var hurt := false
	var rowdy := false
	for incident in incidents:
		centre += incident.global_position
		if incident is Fire:
			burning = true
		elif incident is Hazard:
			# A cylinder counts as burning for triage. Put the fire out and leave the
			# cylinder still hot and the call is emphatically not a medical one, which
			# is where it fell through to before this line existed.
			burning = true
		elif incident is Casualty:
			hurt = true
		elif incident is Suspect:
			rowdy = true
	if not incidents.is_empty():
		position = centre / incidents.size()
		place = CityGrid.place_name(position)

	# A disturbance only names the job while it is the whole job: anything burning or
	# bleeding at the same scene outranks it, the way triage would rank them.
	if burning and hurt:
		kind = Kind.RESCUE
	elif burning:
		kind = Kind.FIRE
	elif hurt:
		kind = Kind.MEDICAL
	elif rowdy:
		kind = Kind.CRIME
	else:
		kind = Kind.MEDICAL


## True if any unit the player commands is at the scene. Ambient traffic and the crowd
## carry no service, so a taxi driving past does not count as a response.
func _attended() -> bool:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit == null or unit.service == Unit.Service.NONE:
			continue
		if _flat(unit.global_position - position) < ON_SCENE_RADIUS:
			return true
	return false


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
