extends WorkOrder
class_name TreatOrder

## Stabilise a casualty. Close range, because you have to kneel next to them.

const REACH := 2.0
const CLIP := "Fixing_Kneeling"


func _init(casualty: Casualty) -> void:
	super(casualty, REACH, CLIP, "Treating")


func _work(_unit: Unit, delta: float) -> bool:
	var casualty := target as Casualty
	if casualty == null:
		return true
	casualty.treat(casualty.treat_per_second * delta)
	# Done once they are stable; the incident stays open until they reach hospital.
	return casualty.is_stable or not casualty.active
