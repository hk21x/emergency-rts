extends RefCounted
class_name Target

## What the player right-clicked: a world point, whatever body was under the cursor,
## and that body as a [Unit] if it is one.
##
## Abilities are asked to score a Target, which is how one right-click can mean
## "drive there", "treat that casualty" or "tow that wreck" without the controller
## knowing about any of them.

var position := Vector3.ZERO
var collider: Object
var unit: Unit
var incident: Incident

## Which place in a group order this unit has been given, and how many there are.
##
## The controller sees the whole selection; an ability sees one unit. Ordering ten units
## to a point used to hand every one of them the *same* coordinate, so they arrived
## stacked and shoved each other apart. These two fields are the seam: the controller
## fills them before the per-unit loop, [MoveAbility] reads them to pick an offset, and
## every other ability ignores them -- so the controller still never branches on a verb,
## which is the property the scoring ladder exists to protect.
var slot_index := 0
var slot_count := 1


## Builds a Target from a PhysicsDirectSpaceState3D.intersect_ray result.
## Returns null for a miss, so callers can bail on empty space.
static func from_hit(hit: Dictionary) -> Target:
	if hit.is_empty():
		return null
	var target := Target.new()
	target.position = hit.get("position", Vector3.ZERO)
	target.collider = hit.get("collider")
	target.unit = target.collider as Unit
	target.incident = target.collider as Incident
	return target


func is_unit() -> bool:
	return unit != null


func is_incident() -> bool:
	return incident != null
