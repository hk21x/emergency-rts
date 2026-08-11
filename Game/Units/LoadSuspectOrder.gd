extends WorkOrder
class_name LoadSuspectOrder

## Drive a patrol car to a detained suspect and put them in the back.
##
## The reach has to bridge the kerb: the car's navigation mesh stops inside the road
## edge (inset by its agent radius) and a kerbside suspect stands a pavement tile
## beyond it, which is about 4m of gap before either has moved. The director only
## opens crime calls against a kerb -- see Director._pick_pavement(roadside) -- so
## this reach is always enough.

const REACH := 5.5


func _init(suspect: Suspect) -> void:
	super(suspect, REACH, "", "Picking up")


func _work(unit: Unit, _delta: float) -> bool:
	var suspect := target as Suspect
	var vehicle := unit as Vehicle
	if suspect == null or vehicle == null:
		return true
	# Another car may have taken them while this one drove over.
	if vehicle.load_suspect(suspect):
		suspect.load_into(vehicle)
	return true
