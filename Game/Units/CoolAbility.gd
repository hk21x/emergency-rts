extends Ability
class_name CoolAbility

## Put water on a heating cylinder before it goes off.
##
## Separate from Extinguish rather than folded into it, and the distinction is the point:
## "put this out" and "stop this exploding" are different decisions, and a crew can only
## do one of them at a time. Folding it in would have made the choice invisible -- the
## ladder would simply pick whichever happened to score higher and the player would never
## know there had been a call to make.
##
## Scores above Extinguish so a firefighter standing between a fire and a warming cylinder
## deals with the cylinder, which is the right default: the fire will still be there in
## ten seconds and the cylinder may not be.


func id() -> StringName:
	return &"cool"


func label() -> String:
	return "Cool"


## The pack's icon set has no cylinder and no hazard glyph, and a check asserts every key
## resolves to a texture, so this borrows one rather than shipping a question mark.
## `flame` over `droplet`: droplet is Extinguish's, and two tiles with the same picture on
## the same firefighter is worse than one whose picture is approximate.
func icon() -> StringName:
	return &"flame"


func hotkey() -> Key:
	return KEY_L


## A crew standing beside a cylinder that is heating should be cooling it. Unconditional,
## unlike Extinguish's -- there is no equivalent of the building fire's "only a hose will
## touch this", because a hazard is only ever worked by someone who has one.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return true


func score(_unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var hazard := target.incident as Hazard
	if hazard == null or not hazard.active:
		return NOT_APPLICABLE
	# Nothing to do for a cylinder that is stone cold and has no fire near it. Declining
	# rather than scoring low matters: it lets Move win, so a player right-clicking past
	# a safe cylinder sends the crew where they pointed.
	if hazard.heat <= 0.0:
		return NOT_APPLICABLE
	return 28


func make_order(_unit: Unit, target: Target) -> Order:
	return CoolOrder.new(target.incident as Hazard)
