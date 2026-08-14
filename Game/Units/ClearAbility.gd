extends Ability
class_name ClearAbility

## Lug the spilled cargo off the carriageway.
##
## The second verb after Free whose purpose is to unblock rather than to save: nothing is
## hurt and nothing is burning, the street itself is the patient. Unusually it belongs to
## **two** services -- box-lugging is not specialist work, so an officer and a firefighter
## are equally the right pair of hands, and whichever arrives first starts.


func id() -> StringName:
	return &"clear"


func label() -> String:
	return "Clear"


func icon() -> StringName:
	return &"box"


func hotkey() -> Key:
	return KEY_J


## A crew member standing at a shed load is there to shift it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true


## Between Cool's 28 and Extinguish's 20: on a mixed scene the fire wants putting out
## and the cylinder wants cooling before anyone worries about the road, but clearing
## still beats walking away. Debris is this verb's only target, so on a plain shed
## load the number does no work at all.
func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var debris := target.incident as Debris
	if debris == null or not debris.active:
		return NOT_APPLICABLE
	return 26


func make_order(_unit: Unit, target: Target) -> Order:
	return ClearOrder.new(target.incident as Debris)
