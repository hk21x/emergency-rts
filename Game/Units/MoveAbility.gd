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


## Spacing between units in a group move, by what they drive on. Taken off the bodies
## rather than guessed: a car is about 4.4m long, a person about 0.6m wide.
const VEHICLE_SPACING := 5.5
const PERSON_SPACING := 1.4
## Rings of a spiral, so a group opens outward from the point rather than forming a line
## that may run through a wall.
const RING_STEP := 6


func make_order(unit: Unit, target: Target) -> Order:
	return MoveOrder.new(_slot_point(unit, target))


## Where this unit should actually stop, given its place in the group.
##
## A single unit gets the raw point, always -- the common case must not pay for the
## uncommon one, and it keeps every existing check measuring what it measured before.
##
## **A slot that cannot be reached falls back to the point itself.** Stacking two units is
## much better than putting one inside a building, and a group order that silently dropped
## a unit would be worse than either.
func _slot_point(unit: Unit, target: Target) -> Vector3:
	if target.slot_count <= 1 or target.slot_index <= 0:
		return target.position
	var spacing := VEHICLE_SPACING if unit is Vehicle else PERSON_SPACING
	# Ring 1 holds six, ring 2 twelve, and so on -- the layout a crowd naturally takes
	# around a thing they are all going to.
	var ring := 1
	var seen := 0
	var index := target.slot_index
	while index > seen + ring * RING_STEP:
		seen += ring * RING_STEP
		ring += 1
	var within := index - seen - 1
	var angle := TAU * float(within) / float(ring * RING_STEP)
	var offset := Vector3(sin(angle), 0.0, cos(angle)) * spacing * float(ring)
	var candidate := target.position + offset
	# Cheap test first: "could anyone stand here at all". `standable` rather than
	# `walkable`, which says yes to a building footprint.
	var tile := CityGrid.tile_at(candidate)
	if not CityGrid.standable(tile.x, tile.y):
		return target.position
	# Then the honest one, on this unit's own navigation layer.
	if not Unit.can_reach(unit, candidate):
		return target.position
	return candidate
