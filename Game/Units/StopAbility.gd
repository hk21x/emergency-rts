extends Ability
class_name StopAbility

## Cancel everything the unit is doing and hold position.
##
## Instant: it has no target, so it never competes for right-click. Scoring
## NOT_APPLICABLE keeps it out of verb resolution entirely.


func id() -> StringName:
	return &"stop"


func label() -> String:
	return "Stop"


func icon() -> StringName:
	return &"halt"


func hotkey() -> Key:
	return KEY_X


func is_instant() -> bool:
	return true


func execute(unit: Unit) -> void:
	unit.clear_orders()
