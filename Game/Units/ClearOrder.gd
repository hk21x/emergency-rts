extends WorkOrder
class_name ClearOrder

## Shift a shed load off the road, box by box, until the street is open again.
##
## The FreeOrder shape exactly: walk up, stand at it, work it down. Nothing else changes
## state -- the cordon, the blocker and the boxes all leave with the Debris node when the
## work is done.

## Further out than Free's 2.4, and the number is load-bearing: the debris origin sits
## mid-lane inside its own Blocker, whose face is 2.75m from centre, and a person's own
## capsule holds them another ~0.3m off that. Anything under ~3.1 is physically
## unreachable -- the first cut used 2.6 and the officer stood pushing the boxes forever.
const REACH := 3.6

## The one-handed "holding something out in front" pose again; at this camera distance
## it reads as working on something at waist height, which lugging boxes is.
const CLIP := "Idle_Torch"


func _init(debris: Debris) -> void:
	super(debris, REACH, CLIP, "Clearing")


func _work(unit: Unit, delta: float) -> bool:
	var debris := target as Debris
	# Gone -- cleared by somebody else, or the scene was torn down. Done, not failed:
	# two crew sent at the same pile is a reasonable order and the second should finish
	# quietly rather than stand there working on nothing.
	if debris == null or not debris.active:
		return true
	debris.clear(debris.clear_per_second * delta)
	return not debris.active
