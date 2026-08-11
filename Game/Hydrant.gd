extends Node3D
class_name Hydrant

## A kerbside hydrant. Somewhere an appliance refills its tank.
##
## Bare on purpose: no mesh, no collider, no script beyond joining a group. The
## hydrant the player *sees* is drawn into the street-furniture MultiMesh with every
## other bench and bin, and this stands at the same spot to say where that one is.
## Giving the prop itself a body would mean several hundred new collision shapes and
## a navigation re-bake to make one of them addressable.
##
## It is the first piece of street furniture with a mechanic behind it, which is the
## bar the project set for making any of them real.

const GROUP := &"hydrants"


func _ready() -> void:
	add_to_group(GROUP)


## The nearest hydrant to [param point] within [param reach], or null.
static func nearest(from: Node, point: Vector3, reach: float) -> Hydrant:
	var closest: Hydrant = null
	var best := reach
	for node in from.get_tree().get_nodes_in_group(GROUP):
		var hydrant := node as Hydrant
		if hydrant == null:
			continue
		var offset := hydrant.global_position - point
		offset.y = 0.0
		var span := offset.length()
		if span < best:
			best = span
			closest = hydrant
	return closest
