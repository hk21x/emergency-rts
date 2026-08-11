extends Order
class_name WorkOrder

## Go to something and work on it until it is done.
##
## This is the shape [MoveOrder] and [BoardOrder] did not need: an order with a
## **range** to close, a **duration** to spend and a **failure** it must survive. The
## target can vanish mid-job -- a fire goes out because someone else reached it, a
## casualty is lost -- so every tick re-checks that the target is still worth working
## on, and ends the order cleanly if it is not.
##
## Subclasses supply the actual work in [method _work].

var target: Node3D
## How close the worker has to be. Measured flat, ignoring height.
var work_range := 3.0
## Clip a [Person] plays while working. Empty leaves the locomotion animation alone.
var action_clip := ""
## Shown in the HUD, e.g. "Extinguishing".
var verb := "Working"

var _working := false


func _init(work_target: Node3D, reach: float, clip: String, label: String) -> void:
	target = work_target
	work_range = reach
	action_clip = clip
	verb = label


func start(unit: Unit) -> void:
	_approach(unit)


func tick(unit: Unit, delta: float) -> bool:
	# The target may have been dealt with, or lost, since the last frame.
	if not is_target_valid():
		_release(unit)
		return true

	var offset := target.global_position - unit.global_position
	offset.y = 0.0

	if offset.length() > work_range:
		if _working:
			# Shoved out of range; go back to walking.
			_release_action(unit)
			_working = false
		if not unit.is_navigating():
			_approach(unit)
		return false

	# In range: stop, turn to the job, and start putting time in.
	unit.stop_navigating()
	unit.face_towards(target.global_position)
	if not _working:
		_working = true
		_apply_action(unit)

	if _work(unit, delta):
		_release(unit)
		return true
	return false


func cancel(unit: Unit) -> void:
	_release(unit)


func destination() -> Vector3:
	return target.global_position if is_target_valid() else NO_DESTINATION


func describe() -> String:
	if not is_target_valid():
		return verb
	var incident := target as Incident
	if incident == null:
		return verb
	var state := incident.describe_state()
	return verb if state.is_empty() else "%s  %s" % [verb, state]


## An incident that has been resolved is freed at the end of the frame, so the active
## flag has to be trusted rather than is_instance_valid alone.
func is_target_valid() -> bool:
	if not is_instance_valid(target):
		return false
	var incident := target as Incident
	return incident == null or incident.active


## One tick of the job. Return true when finished.
func _work(_unit: Unit, _delta: float) -> bool:
	return true


func _approach(unit: Unit) -> void:
	if is_target_valid():
		unit.navigate_to(target.global_position)


func _release(unit: Unit) -> void:
	unit.stop_navigating()
	_release_action(unit)
	_working = false


func _apply_action(unit: Unit) -> void:
	var person := unit as Person
	if person and not action_clip.is_empty():
		person.set_action(action_clip)


func _release_action(unit: Unit) -> void:
	var person := unit as Person
	if person:
		person.clear_action()
