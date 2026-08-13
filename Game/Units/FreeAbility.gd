extends Ability
class_name FreeAbility

## Lift the weight off someone who is pinned under it.
##
## The first verb in the game whose whole purpose is to **unblock another service**. It
## heals nobody and puts nothing out: a firefighter cuts the casualty loose and then has
## no further part in the call, which is left to the paramedic who could not start until
## they had.
##
## That sequencing is the point, and it is what a rescue does not have. A rescue needs an
## engine and an ambulance at the same time; this needs one to have *finished* before the
## other can begin, so arriving in the wrong order costs real time rather than being a
## matter of taste.
##
## Fire service only, because they are the ones with cutting gear -- and because a
## paramedic who could free people would collapse the whole call back into one unit.


func id() -> StringName:
	return &"free"


func label() -> String:
	return "Free"


## `person` was the one icon in the set nobody had taken, and it happens to be the right
## one: this verb is entirely about who is underneath.
func icon() -> StringName:
	return &"person"


func hotkey() -> Key:
	return KEY_T


## A crew member standing over someone pinned is there to get them out.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true


## Above Cool's 28 and Treat's 30. A firefighter has neither, so the number does no work
## against their own list -- it is set for the day someone gives this to a second service,
## and because the ladder should read in the order a scene actually wants doing.
func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var casualty := target.incident as Casualty
	if casualty == null or not casualty.active or not casualty.trapped:
		return NOT_APPLICABLE
	return 32


func make_order(_unit: Unit, target: Target) -> Order:
	return FreeOrder.new(target.incident as Casualty)
