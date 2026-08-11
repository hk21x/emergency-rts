extends Node
class_name CallBoard

## Turns incidents appearing on the map into calls the player can work from.
##
## Passive, exactly like [Mission]: it watches `SceneTree.node_added` rather than being
## told, so a fire that spreads or a casualty spawned by a later phase is picked up
## without anything having to register with it. Nothing on the map knows this exists.
##
## Grouping is the point. One fire left alone becomes eight, and eight rows on the board
## would be eight jobs when it is plainly still one. An incident joins the nearest open
## call it is close enough to, and only opens a new one when there is nothing near.
##
## The mission's win and lose conditions still read incidents directly. That is
## deliberate for now -- the shout works and is well covered by tests, and the board
## being a view rather than the authority means it cannot be the thing that breaks it.
## Phase 15's scoring is where calls become what the game is actually judged on.

signal call_opened(call: Call)
signal call_changed(call: Call)
signal call_closed(call: Call, success: bool)

var calls: Array[Call] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		_watch(node)


## Open calls, oldest first, so a row does not jump up the list when the one above it
## is dealt with.
func open_calls() -> Array[Call]:
	var found: Array[Call] = []
	for call in calls:
		if is_instance_valid(call) and call.is_open():
			found.append(call)
	found.sort_custom(func(a: Call, b: Call) -> bool: return a.age > b.age)
	return found


func waiting_count() -> int:
	var total := 0
	for call in open_calls():
		if call.status == Call.Status.WAITING:
			total += 1
	return total


func _on_node_added(node: Node) -> void:
	_watch(node)


func _watch(node: Node) -> void:
	var incident := node as Incident
	if incident == null:
		return
	# Deferred, and this matters: node_added fires from inside add_child, and
	# Fire._spread() sets the new fire's position *after* adding it. Read the position
	# now and every spread fire looks like it is at its parent's feet -- which is close
	# enough to be grouped correctly by luck, and would silently stop being so the day
	# something spawns further from its parent.
	_adopt.call_deferred(incident)


func _adopt(incident: Incident) -> void:
	if not is_instance_valid(incident) or not incident.active:
		return
	for call in open_calls():
		if call.covers(incident.global_position):
			call.adopt(incident)
			call_changed.emit(call)
			return

	var opened := Call.new()
	opened.name = "Call%d" % (calls.size() + 1)
	add_child(opened)
	opened.adopt(incident)
	opened.changed.connect(_on_call_changed)
	opened.closed.connect(_on_call_closed)
	calls.append(opened)
	call_opened.emit(opened)


func _on_call_changed(call: Call) -> void:
	call_changed.emit(call)


func _on_call_closed(call: Call, success: bool) -> void:
	call_closed.emit(call, success)
