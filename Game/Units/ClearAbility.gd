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


## **`O`, not `J`.** It shared `J` with Lights for most of its life on the reasoning that
## one is a foot verb and the other a vehicle verb, so the two could never appear on the
## same unit. Giving the recovery truck `can_tow` ended that: it is a [Vehicle], so it has
## a lightbar, and `_handle_hotkey` takes the first match in tile order -- which was this
## one, leaving the truck's lights unreachable from the keyboard. `O` is the only letter
## the camera does not poll and no other verb had taken.
func hotkey() -> Key:
	return KEY_O


## A crew member standing at a shed load is there to shift it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true


## Between Cool's 28 and Extinguish's 20: on a mixed scene the fire wants putting out
## and the cylinder wants cooling before anyone worries about the road, but clearing
## still beats walking away. Debris is this verb's only target, so on a plain shed
## load the number does no work at all.
func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var debris := target.incident as Debris
	if debris != null and debris.active:
		return 26
	# **A wreck is the same verb with a different tool.** Extending this ability rather
	# than adding a seventeenth keeps the command tile, the hotkey and the right-click
	# meaning the player already knows -- and the gate is the winch, so a patrol car is
	# never offered a job it cannot do.
	var wreck := target.incident as Wreck
	if wreck != null and wreck.active:
		var vehicle := unit as Vehicle
		return 26 if vehicle != null and vehicle.can_tow else NOT_APPLICABLE
	return NOT_APPLICABLE


func make_order(unit: Unit, target: Target) -> Order:
	var reach := ClearOrder.VEHICLE_REACH if unit is Vehicle else ClearOrder.REACH
	return ClearOrder.new(target.incident, reach)
