extends Node
class_name Spotlight

## Pulses whichever controls the player is meant to press next.
##
## The tutorial has always *said* what to do -- "buy an Ambulance and a Paramedic" -- and
## saying it is only half the job when the thing being named is one of eight cards in a
## storefront the player has never seen. This is the other half: the words name the step,
## and the control the words mean glows.
##
## **Driven by the same reading as the words**, not by a parallel script.
## [TutorialDirector] works out what is missing once, per tick, and hands the answer to
## both -- so a prompt that says "buy an ambulance" cannot end up pointing at the
## firefighter. That is the whole reason this is a node the tutorial pushes to, rather
## than something that inspects the tutorial itself.
##
## Nothing outside the tutorial uses it. The district assumes a player who has been
## through the tutorial or does not need it, and a live shift with a glowing button in it
## would be nagging rather than teaching.

## Seconds for a full bright-dim-bright cycle. Slow enough to read as breathing rather
## than blinking -- a fast pulse on a button reads as an error state.
const PERIOD := 1.2
## Peak brightness. Above the hover lift (1.18) by enough that a spotlit control is
## obviously different from one merely under the pointer.
const LIFT := 0.55

var _targets: Array[Control] = []
var _phase := 0.0


## Points at [param controls], releasing anything previously pointed at.
##
## Nulls are dropped rather than rejected, because every caller is looking a control up by
## path or by id and "the shop is not open yet" is the normal answer, not a mistake.
func point_at(controls: Array[Control]) -> void:
	var wanted: Array[Control] = []
	for control in controls:
		if control != null and is_instance_valid(control):
			wanted.append(control)
	if wanted == _targets:
		return
	_release()
	_targets = wanted
	_phase = 0.0


func clear() -> void:
	point_at([])


func _process(delta: float) -> void:
	if _targets.is_empty():
		return
	_phase = fmod(_phase + delta, PERIOD)
	# Sine rather than a sawtooth: a linear ramp that snaps back at the top reads as a
	# flicker, which is the one thing a "look here" cue must not look like.
	var lift := 1.0 + LIFT * 0.5 * (1.0 - cos(_phase / PERIOD * TAU))
	for control in _targets:
		if is_instance_valid(control):
			control.modulate = Color(lift, lift, lift, control.modulate.a)


## Puts the brightness back.
##
## **[Hover] writes the same property**, and while a control is spotlit this node wins
## because it writes every frame. So releasing has to restore 1.0 rather than whatever
## Hover last set -- if the pointer happens to be resting on the control as the step
## completes, Hover will put its own lift back on the next `mouse_entered`, and until then
## a plain control is the right answer.
func _release() -> void:
	for control in _targets:
		if is_instance_valid(control):
			control.modulate = Color(1.0, 1.0, 1.0, control.modulate.a)
	_targets = []
