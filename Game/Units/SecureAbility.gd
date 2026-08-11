extends Ability
class_name SecureAbility

## Put a cordon around a scene. Police only.
##
## The one verb here that must be **armed deliberately**. Every other ability wins a
## right-click by outscoring the rest, but "secure" applies to any patch of ground --
## and an ability that applies everywhere would swallow Move, leaving an officer unable
## to be sent anywhere without cordoning it off.
##
## So it declines every right-click and overrides [method can_target] instead: the
## player presses the tile, then clicks where the cordon goes.

const RADIUS := 6.0


func id() -> StringName:
	return &"secure"


func label() -> String:
	return "Secure"


func icon() -> StringName:
	return &"cone"


func hotkey() -> Key:
	return KEY_G


## Never wins a right-click. See the note above.
func score(_unit: Unit, _target: Target) -> int:
	return NOT_APPLICABLE


## Once armed, anywhere on the ground will do.
func can_target(_unit: Unit, target: Target) -> bool:
	return target != null


func make_order(unit: Unit, target: Target) -> Order:
	# Parented to the unit's own parent rather than to the unit: a cordon stays where it
	# was put when the officer who put it there walks away.
	return SecureOrder.new(unit.get_parent(), target.position, RADIUS)
