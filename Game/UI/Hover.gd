extends RefCounted
class_name Hover

## Makes a clickable Control look clickable.
##
## Several things in this interface stop the mouse and answer clicks -- roster chips, call
## rows, dispatch rows, the CONTROLS chip -- and until August 2026 every one of them looked
## exactly like the things that do not. A player had to discover them by trying, which is
## the worst kind of discoverability: it only works for people who already suspect.
##
## `CommandIcon` had the pattern already (`mouse_entered` / `mouse_exited` flipping a flag
## and redrawing); this is that, lifted out so five call sites do not each write it again.
##
## **Brightening rather than swapping a stylebox**, deliberately. Half of these controls
## are bare containers with no panel at all -- a `UnitChip` is a `VBoxContainer` -- and
## giving one a stylebox changes its size. In the bar, a control that changes size makes
## the bar taller, and a taller bar covers whatever floats above it. That trap has caught
## this project six times and it is not worth re-opening for a hover effect.

## How much brighter a hovered control gets. Enough to notice at a glance, not enough to
## read as selected -- selection is the amber in [Palette], and two states that look alike
## are worse than one that is invisible.
const LIFT := 1.18


## Brightens [param control] while the pointer is over it.
##
## Safe to call on anything: a control whose `mouse_filter` ignores the pointer simply
## never emits, so this quietly does nothing rather than lying about being interactive.
static func attach(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if control.mouse_entered.is_connected(_lift):
		return
	control.mouse_entered.connect(_lift.bind(control))
	control.mouse_exited.connect(_settle.bind(control))


static func _lift(control: Control) -> void:
	if is_instance_valid(control):
		control.modulate = Color(LIFT, LIFT, LIFT, control.modulate.a)


static func _settle(control: Control) -> void:
	if is_instance_valid(control):
		control.modulate = Color(1.0, 1.0, 1.0, control.modulate.a)
