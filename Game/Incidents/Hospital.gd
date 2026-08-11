extends Area3D
class_name Hospital

## Found by group rather than by path, the way [Station] is: an [Ability] is shared by
## every unit of its type, so it cannot hold a reference to one hospital.
const GROUP := &"hospitals"

## Drop-off point. Any vehicle that drives in hands over whoever it is carrying.
##
## Delivery is automatic on arrival rather than another order to issue: the player has
## already said what they mean by driving here.

signal delivered(vehicle: Vehicle, count: int)


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as Vehicle
	if vehicle == null:
		return
	var count := vehicle.deliver_casualties()
	if count > 0:
		delivered.emit(vehicle, count)
