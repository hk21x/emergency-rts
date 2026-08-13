extends WorkOrder
class_name TreatOrder

## Stabilise a casualty. Close range, because you have to kneel next to them.

const REACH := 2.0
const CLIP := "Fixing_Kneeling"


func _init(casualty: Casualty) -> void:
	super(casualty, REACH, CLIP, "Treating")


func _work(unit: Unit, delta: float) -> bool:
	var casualty := target as Casualty
	if casualty == null:
		return true
	# **Who is treating decides what the treatment achieves.** On an ordinary casualty this
	# changes nothing; on one that needs a doctor, a paramedic's work holds the decline off
	# and never stabilises them. See [member Casualty.needs_doctor].
	var medic := unit as Person
	casualty.treat(casualty.treat_per_second * delta,
		medic != null and medic.has_advanced_care())
	# Done once they are stable; the incident stays open until they reach hospital. A
	# paramedic holding a doctor's case is *not* done -- they stay until pulled off, which is
	# the point: the holding is the job until the doctor arrives.
	return casualty.is_stable or not casualty.active
