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

## What a *vehicle* needs instead, and the number is load-bearing in the same way.
##
## [REACH] is measured off a person's capsule. A recovery truck is 5.44m long and its
## origin is its centre, so to bring that centre within 3.6m of a wreck's centre it would
## have to drive inside the 5.5m blocker -- which is what the blocker exists to stop. It
## stalled at about 8m, drifted, and winched nothing for as long as anyone watched: the
## identical fault this file's own comment records for the officer and the boxes, arriving
## again the moment a vehicle was given the verb.
##
## Half the truck (2.72) plus the blocker's face (2.75) is 5.47 on paper -- and **the
## figure that matters is where it actually comes to rest, which is 7.3m.** It stops
## further out than the geometry alone predicts: its own obstacle avoidance slows it
## before the bumper touches anything. Measured rather than derived, because a reach set
## from the arithmetic left it parked half a metre outside its own working range,
## stationary and winching nothing -- which looks identical to a truck that cannot path.
const VEHICLE_REACH := 8.0

## The one-handed "holding something out in front" pose again; at this camera distance
## it reads as working on something at waist height, which lugging boxes is.
const CLIP := "Idle_Torch"


## Takes any incident that can be worked down -- a [Debris] or a [Wreck]. Typed as
## [Incident] rather than branching on the two, because both expose the same two names
## and the order has no reason to care which it is standing at.
## [param reach] is chosen by [ClearAbility] from whoever is doing the work: a person can
## stand at the boxes, a truck has to back up to the car.
func _init(what: Incident, reach := REACH) -> void:
	super(what, reach, CLIP, "Clearing")


func _work(unit: Unit, delta: float) -> bool:
	var debris := target as Incident
	# Gone -- cleared by somebody else, or the scene was torn down. Done, not failed:
	# two crew sent at the same pile is a reasonable order and the second should finish
	# quietly rather than stand there working on nothing.
	if debris == null or not debris.active:
		return true
	debris.clear(debris.clear_per_second * delta)
	return not debris.active
