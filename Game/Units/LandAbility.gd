extends Ability
class_name LandAbility

## Put the helicopter down on open ground.
##
## **Refuses anywhere that is not clear land**, which is `CityGrid.standable()` — roads,
## parks and the pavement ring around each block. Everything inside a block is the
## building, so a helicopter can never be set down on a roof or in a living room. Declining
## rather than scoring low is what makes that read well: a player right-clicking a rooftop
## gets Move, and the aircraft flies over and holds station instead of refusing to move at
## all.
##
## The same rule the crowd walks on, deliberately. A landing rule of its own would be a
## second definition of "ground" to keep in step with the first.


func id() -> StringName:
	return &"land"


func label() -> String:
	return "Land"


func icon() -> StringName:
	return &"door_in"


func hotkey() -> Key:
	return KEY_Y


func auto_engages(_unit: Unit, _target: Target) -> bool:
	return false


## **Armed only, and this was wrong at first.** It scored 12 against Move's 0, so *every*
## right-click on open ground put the helicopter down -- which made flying somewhere and
## hovering impossible, since the only ground it will land on is the only ground you would
## send it to. A helicopter's default answer to "go there" is to go there and hold.
##
## So landing is a deliberate act: press the key, then click the spot. The same shape
## [SecureAbility] uses, and for the same reason -- a verb whose target is *ground* cannot
## be resolved from a plain right-click without swallowing Move.
func score(_unit: Unit, _target: Target) -> int:
	return NOT_APPLICABLE


## Armed, the click is checked here instead. Refusing a rooftop leaves the aircraft where
## it is rather than flying it somewhere it cannot land.
func can_target(unit: Unit, target: Target) -> bool:
	return target != null and unit is Aircraft and Aircraft.can_land_at(target.position)


func make_order(_unit: Unit, target: Target) -> Order:
	return LandOrder.new(target.position)
