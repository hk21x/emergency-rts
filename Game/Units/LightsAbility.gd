extends Ability
class_name LightsAbility

## Manual lightbar switch -- the visual half of the pair, [SirenAbility] is the audio.
##
## The bar already lights itself while the vehicle is responding; this is the parked
## case -- scene lighting at a stop, warning traffic off a cordon. Instant and a
## toggle: press to switch on, press again to switch off. It declines every target so
## it never competes for a right-click.


func id() -> StringName:
	return &"lights"


func label() -> String:
	return "Lights"


func icon() -> StringName:
	return &"beacon"


func hotkey() -> Key:
	return KEY_J


func is_instant() -> bool:
	return true


func execute(unit: Unit) -> void:
	var vehicle := unit as Vehicle
	if vehicle:
		vehicle.lights_on = not vehicle.lights_on


func is_active(unit: Unit) -> bool:
	var vehicle := unit as Vehicle
	return vehicle != null and vehicle.lights_on
