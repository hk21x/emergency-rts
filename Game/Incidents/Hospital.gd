extends Area3D
class_name Hospital

## Found by group rather than by path, the way [Station] is: an [Ability] is shared by
## every unit of its type, so it cannot hold a reference to one hospital.
const GROUP := &"hospitals"

## Drop-off point. Any vehicle that drives in hands over whoever it is carrying.
##
## Delivery is automatic on arrival rather than another order to issue: the player has
## already said what they mean by driving here.

signal delivered(vehicle: Unit, count: int)


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# **A [Unit], not a [Vehicle].** The air ambulance lands on the hospital pad and is
	# not a Vehicle -- it has no wheels, no lightbar and no repair bill -- so this cast
	# returned null for it and a helicopter could fly a casualty in and deliver nobody.
	var vehicle := body as Unit
	if vehicle == null:
		return
	var count := vehicle.deliver_casualties()
	if count > 0:
		delivered.emit(vehicle, count)
