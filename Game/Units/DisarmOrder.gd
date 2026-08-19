extends WorkOrder
class_name DisarmOrder

## Stand off an armed suspect until they put the weapon down.
##
## The [WorkOrder] shape, with one difference that matters: the reach is deliberately
## longer than an arrest's. Armed response does not close to arm's length with somebody
## holding a weapon -- they hold a distance and talk. It also reads better: two figures a
## few metres apart is legible at this camera height in a way a scuffle is not.

## Further out than an arrest, and the reason is the fiction rather than the geometry.
const REACH := 4.2

## Weapon up, held on the man.
##
## **The one pose in the library authored for a firearm.** The animation set has six
## pistol clips and no rifle ones, which is why the ARV carries a pistol: the walk to the
## scene is the ordinary `Walk` -- gun in hand, arm down, as anybody would carry it -- and
## this is what they change to on arrival. Standing off somebody with a weapon raised is
## exactly what `Pistol_Idle` was drawn for, where the extinguisher's torch pose was a
## stand-in for want of anything better.
const CLIP := "Pistol_Idle"


func _init(suspect: Suspect) -> void:
	super(suspect, REACH, CLIP, "Disarming")


func _work(unit: Unit, delta: float) -> bool:
	var suspect := target as Suspect
	# Gone, or somebody else talked them down. Done rather than failed: two ARVs sent to
	# one man is a reasonable order and the second should stand down quietly.
	if suspect == null or not suspect.active or not suspect.armed:
		return true
	suspect.disarm(suspect.disarm_per_second * delta)
	return not suspect.armed
