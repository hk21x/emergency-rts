extends WorkOrder
class_name ConnectOrder

## Drive to a hydrant and hook up to it.
##
## A [WorkOrder] because the approach-then-act shape is exactly the one it already models,
## and it is safe on a vehicle: `_apply_action` guards its animation on `unit as Person`, so
## an appliance simply skips the clip a firefighter would play.
##
## The job finishes the moment the line is on. What it leaves behind is *state on the
## appliance*, not a running order — the crew are then free to be given something else to do
## while the engine stands there supplying them, which is the whole point of connecting.

## The reach the appliance's own refill uses. Sharing it means a connection is possible
## exactly where a top-up already was, rather than at a second, invisible distance.
const REACH := 9.0


func _init(hydrant: Hydrant) -> void:
	super(hydrant, REACH, "", "Connecting")


func _work(unit: Unit, _delta: float) -> bool:
	var engine := unit as Vehicle
	if engine == null:
		return true
	engine.connect_to_main(target as Hydrant)
	return true
