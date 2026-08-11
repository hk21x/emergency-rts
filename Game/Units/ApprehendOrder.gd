extends WorkOrder
class_name ApprehendOrder

## Walk to a suspect and take them into custody. Close range -- it is hands-on work.

const REACH := 2.0
const CLIP := "Interact"


func _init(suspect: Suspect) -> void:
	super(suspect, REACH, CLIP, "Arresting")


func _work(unit: Unit, delta: float) -> bool:
	var suspect := target as Suspect
	if suspect == null:
		return true
	# Handing over who is doing the arresting: it is who they square up to, and the
	# order is the only thing that knows for certain.
	suspect.detain(suspect.detain_per_second * delta, unit)
	# Done once they are in custody; the incident stays open until they are booked in
	# at the station, which is what makes the drive back part of the job.
	return suspect.is_detained or not suspect.active
