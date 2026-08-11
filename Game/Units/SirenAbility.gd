extends Ability
class_name SirenAbility

## Manual siren switch -- the audio half of the pair, [LightsAbility] is the visual.
##
## Deliberately separate from the lights: pulling up to a scene you kill the noise and
## leave the bar running, which is one button off, not a mode. Instant and a toggle.
## The sound itself is whatever [constant Vehicle.SIREN_STREAM] loads -- with no file
## there the switch still flips, it just has nothing to say.


func id() -> StringName:
	return &"siren"


func label() -> String:
	return "Siren"


func icon() -> StringName:
	return &"horn"


func hotkey() -> Key:
	return KEY_K


func is_instant() -> bool:
	return true


func execute(unit: Unit) -> void:
	var vehicle := unit as Vehicle
	if vehicle:
		vehicle.siren_on = not vehicle.siren_on


func is_active(unit: Unit) -> bool:
	var vehicle := unit as Vehicle
	return vehicle != null and vehicle.siren_on
