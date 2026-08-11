extends Ability
class_name MoveAbility

## The universal fallback verb: go to where the cursor is pointing.
##
## Scores 0 deliberately -- it applies to everything, so any purposeful verb should
## outrank it simply by scoring above zero.


func id() -> StringName:
	return &"move"


func label() -> String:
	return "Move"


func icon() -> StringName:
	return &"arrow"


func hotkey() -> Key:
	return KEY_Z


func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	# Ordering a unit into itself is a no-op, not a move.
	if target.unit == unit:
		return NOT_APPLICABLE
	return 0


func make_order(_unit: Unit, target: Target) -> Order:
	return MoveOrder.new(target.position)
