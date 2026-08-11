extends WorkOrder
class_name SecureOrder

## Walk to a spot and set a cordon out around it.
##
## Extends [WorkOrder] rather than reimplementing the approach, which needs a node to
## walk to -- so the cordon is created immediately, unraised, and *is* the target. The
## officer walks to it, works for [constant DURATION], and raising it is the finish.
##
## Abandon the order and the cordon goes with it. A ring of cones nobody finished
## putting out is not a thing that should be left lying in the street.

const REACH := 2.5
const DURATION := 3.0
## The library has no "putting a cone down" clip; this is a crouched working pose.
const CLIP := "Interact_Ground"


var _spent := 0.0


func _init(parent: Node, point: Vector3, radius := 6.0) -> void:
	var cordon := Cordon.new()
	cordon.name = "Cordon"
	cordon.radius = radius
	parent.add_child(cordon)
	cordon.global_position = point
	super(cordon, REACH, CLIP, "Securing the scene")


func _work(_unit: Unit, delta: float) -> bool:
	var cordon := target as Cordon
	if cordon == null:
		return true
	_spent += delta
	if _spent < DURATION:
		return false
	cordon.raise_cordon()
	return true


## A pending cordon is nothing but a promise, so dropping the order drops it too. One
## already raised stays: the officer has done the work and walking away does not undo it.
func cancel(unit: Unit) -> void:
	super(unit)
	var cordon := target as Cordon
	if cordon and is_instance_valid(cordon) and not cordon.raised:
		cordon.queue_free()


func describe() -> String:
	if not is_target_valid():
		return verb
	return "%s  %d%%" % [verb, roundi(clampf(_spent / DURATION, 0.0, 1.0) * 100.0)]


## The base class treats a resolved Incident as a dead target. A cordon is neither an
## incident nor something that can be resolved, so it is valid until it is freed.
func is_target_valid() -> bool:
	return is_instance_valid(target)
