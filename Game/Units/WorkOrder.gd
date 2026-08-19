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


## Where a vehicle is sent: just outside the 2.75m face of a work target's blocker, so
## the point is on road the agent can actually route to.
const VEHICLE_STANDOFF := 3.4


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


## Drives or walks toward the job.
##
## **A vehicle is aimed beside the target, not at it.** Work targets that shut a street
## carry a solid blocker around their centre -- that is what makes a vehicle stall against
## them rather than drive through -- so a truck asked to navigate to the centre is asked
## for a point its agent cannot reach. It closed to about 8m, turned, and wandered off,
## winching nothing: the recovery truck could not do the one job it exists for.
##
## People still aim at the centre. They can stand against a blocker and be in range, that
## path has worked since the shed load shipped, and changing it would risk a verb that is
## already right for the sake of one that was not.
func _approach(unit: Unit) -> void:
	if not is_target_valid():
		return
	if unit is not Vehicle:
		unit.navigate_to(target.global_position)
		return
	var out := unit.global_position - target.global_position
	out.y = 0.0
	if out.length() < 0.1:
		unit.navigate_to(target.global_position)
		return
	# **A fixed standoff, not one scaled off the reach.** Aiming at `work_range * 0.8` made
	# the two chase each other: raising the reach pushed the aim point further out, so the
	# truck parked further away and was still outside its own range. This aims just clear
	# of the blocker and lets the vehicle stop wherever its own avoidance decides, which is
	# what the reach is then sized to cover.
	unit.navigate_to(target.global_position + out.normalized() * VEHICLE_STANDOFF)


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
