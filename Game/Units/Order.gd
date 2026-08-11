extends RefCounted
class_name Order

## One queued instruction for a [Unit].
##
## A unit runs the order at the front of its queue: [method start] once, then
## [method tick] every physics frame until it returns true. Orders own *what* should
## happen; the unit owns *how* it moves. That split is what lets a firefighter and a
## fire engine share the same order queue.

## Sentinel for orders that are not aimed at a place, so markers can skip them.
const NO_DESTINATION := Vector3.INF


## Called once when the order reaches the front of the queue.
func start(_unit: Unit) -> void:
	pass


## Called every physics frame while the order is current.
## Return true when it is finished and the queue should advance.
func tick(_unit: Unit, _delta: float) -> bool:
	return true


## Called when the order is abandoned rather than completed.
func cancel(_unit: Unit) -> void:
	pass


## World point this order is aimed at, for destination markers.
func destination() -> Vector3:
	return NO_DESTINATION


func has_destination() -> bool:
	return destination() != NO_DESTINATION


## Short label for the HUD.
func describe() -> String:
	return "Order"


## Whether this order is a response. True for everything the player sends a unit *to*:
## lightbars on, and the speed limit is whatever the vehicle can hold.
##
## Returning to station is the exception. A unit that has finished with a call is not
## on a shout any more, and driving back through the district on blues at 90km/h is
## exactly what an emergency vehicle is not allowed to do.
func is_emergency() -> bool:
	return true
