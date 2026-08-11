extends RefCounted
class_name Ability

## Something a [Unit] can do to a [Target].
##
## Right-click resolution works by asking every ability on the selected unit to score
## the target and running the best one. Adding "extinguish" later means adding an
## ability that scores fires highly -- no change to the controller.

## Returned by [method score] when the ability cannot act on this target at all.
const NOT_APPLICABLE := -1


## Stable identifier, used by the command bar.
func id() -> StringName:
	return &"ability"


## Short label for the command bar.
func label() -> String:
	return "Ability"


## Which glyph [CommandIcon] draws for this verb. Returning an unknown key draws a
## question mark rather than nothing, so a new ability is visibly missing its icon
## instead of appearing as an empty tile nobody thinks to press.
func icon() -> StringName:
	return &"unknown"


## Key that runs this ability from the command bar, or KEY_NONE for no shortcut.
##
## Bound to the ability rather than to a grid position, so a verb keeps the same key
## whatever else is selected alongside it. The usable range is narrow: the camera polls
## W A S D for panning and Q E for rotation every frame regardless of whether an event
## was consumed, F is focus, R is respawn and 1-9 are control groups.
func hotkey() -> Key:
	return KEY_NONE


## How well this ability fits the target. Higher wins; ties go to the earlier
## ability. Return [constant NOT_APPLICABLE] to decline. Keep generic fallbacks at 0
## so specific verbs beat them.
func score(_unit: Unit, _target: Target) -> int:
	return NOT_APPLICABLE


## Whether an armed ability will act on this target.
##
## Defaults to whatever [method score] says, which is right for every verb that also
## wants to win a right-click. Override it for an ability the player must arm
## deliberately: one that applies to any patch of ground would otherwise swallow Move
## and leave the unit unable to be sent anywhere.
func can_target(unit: Unit, target: Target) -> bool:
	return score(unit, target) != NOT_APPLICABLE


## Builds the order to queue. Only called when the ability did not decline.
func make_order(_unit: Unit, _target: Target) -> Order:
	return null


## True for abilities that fire the moment their command-bar button is pressed, with
## no target to pick. Targeted abilities instead arm the cursor for the next click.
## Whether an idle unit standing near a suitable incident should start this on its own.
##
## Opt-in, ability by ability, rather than "anything that scores": the ladder answers
## *what* a unit would do to a target, not whether it should do it unasked. Working on the
## incident — putting a fire out, treating somebody — is what a crew standing over it is
## for. Deciding to cordon a street, or getting into a vehicle, is the player's call.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return false


func is_instant() -> bool:
	return false


## Runs an instant ability. Ignored for targeted ones.
func execute(_unit: Unit) -> void:
	pass


## Whether this verb is currently switched on for [param unit]. Only toggles -- Lights,
## Siren -- ever say yes; everything else stays false and draws a plain tile. The
## command grid reads it to show a toggle's state on its tile.
func is_active(_unit: Unit) -> bool:
	return false
