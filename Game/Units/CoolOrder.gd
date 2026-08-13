extends WorkOrder
class_name CoolOrder

## Stand by a heating cylinder and hose it until it is cold.
##
## The same shape as [ExtinguishOrder] and it draws from the same tank, because it is the
## same hose. What differs is what it is racing: a fire gets worse on its own and can be
## come back to, while a cylinder that reaches its limit takes the street with it. So
## there is no partial credit here -- stopping halfway leaves it exactly as dangerous as
## the fire beside it makes it.

## How close to work from. The same reach the hose has on a fire: this is a firefighter
## standing off a thing they expect to go bang, not leaning on it.
const REACH := 5.0

## Water drawn per unit of heat taken off. Cheaper than fighting the fire itself --
## cooling is a jet held on one spot, not knocking down a building -- so a crew is never
## made to choose between saving the cylinder and having a tank left.
const WATER_PER_HEAT := 0.35


func _init(hazard: Hazard) -> void:
	super(hazard, REACH, "Idle_Torch", "Cooling")


func _work(unit: Unit, delta: float) -> bool:
	var hazard := target as Hazard
	if hazard == null or not hazard.active:
		return true

	var supply := _supply(unit)
	# **No hose, no cooling.** Unlike a fire, there is no reduced rate for standing there
	# with what you carry: an extinguisher against a pressure vessel is not a slower
	# answer, it is not an answer. The order still runs and the animation still plays,
	# which is the same lesson a building fire teaches a patrol car.
	if supply == null:
		return not hazard.active

	var taken := hazard.hose_per_second * delta
	hazard.cool(taken)
	supply.draw_water(taken * WATER_PER_HEAT)
	# Below the no-supply return above, so a crew away from the appliance shows no jet --
	# which is the visible half of "not a slower answer, not an answer".
	var person := unit as Person
	if person:
		person.spray_at(hazard.global_position)
	supply.raise_ladder()
	return hazard.heat <= 0.0


## The appliance this firefighter is working off: in reach, and with water left. Shares
## [ExtinguishOrder]'s reach and its rule -- an engine that has run dry stops being a
## supply, which is what turns the tank into a decision rather than a readout.
func _supply(unit: Unit) -> Vehicle:
	if unit == null:
		return null
	for node in unit.get_tree().get_nodes_in_group(Unit.GROUP):
		var engine := node as Vehicle
		if engine == null or not engine.carries_water:
			continue
		if not engine.has_water():
			continue
		var offset := engine.global_position - unit.global_position
		offset.y = 0.0
		if offset.length() <= ExtinguishOrder.HOSE_REACH:
			return engine
	return null
