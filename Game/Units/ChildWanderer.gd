extends Civilian
class_name ChildWanderer

## The child a missing-child call is about: a small figure strolling the pedestrian
## graph somewhere in the district, wearing **no marker of any kind**.
##
## That absence is the game. The call's marker stands at the last-seen anchor
## ([MissingChild]); the child is found by a unit physically getting close, so the
## player sweeps streets rather than clicking a dot. Being a [Civilian] gives all of
## that for free -- crowd collision layer, invisible to the picking ray, unselectable --
## and the walk graph guarantees they are always somewhere a searcher on foot can reach.
##
## No child-sized mesh exists in any pack -- Synty's "SchoolBoy" is a school uniform on
## the standard adult rig, measured at 1.84m like every other body -- so the child is an
## ordinary outfit scaled down in Child.tscn. At RTS distance, small *is* young.

## How far the stroll may drift from where they were left. Bounds the search: the call
## promises the child is *near* somewhere, and a wanderer free to cross the whole
## district would turn the search into a shift-long trawl.
@export var roam_radius := 32.0

## How close behind the finder they walk, and how far they may fall back before the
## heel point is re-aimed. Following is what a found child does: they cannot be
## clicked, so the escort is not an order -- it is them trusting whoever found them.
const HEEL_GAP := 1.6
const HEEL_SLACK := 2.4

## Where "near" is measured from. Set by the director at spawn, before entering the
## tree; falls back to the spawn point so a hand-placed child still behaves.
var wander_centre := Vector3.INF

## The unit that found them, once somebody has. While set, the stroll is over: the
## child walks at heel wherever the finder goes.
var following: Unit

## The patrol car they were put in. Hidden and inert while riding; the report watches
## the car from here on, not the child.
var riding: Vehicle

## Throttles heel re-aiming, so a moving finder is re-pathed a few times a second
## rather than every frame.
var _heel_left := 0.0


func _ready() -> void:
	super()
	if wander_centre == Vector3.INF:
		wander_centre = global_position


## A child does not drift over to gawk at casualties and suspects the way the grown
## crowd does. Partly tone, mostly mechanics: a wanderer pulled toward every incident
## would walk up to the player's units and find *them*, and the search is the call.
func _update_watching() -> void:
	is_watching = false


## Taken in hand: the stroll ends and the heel walk begins. Called by the report's
## scan the moment a searcher gets close.
func follow(finder: Unit) -> void:
	following = finder
	is_watching = false
	is_fleeing = false
	_heel_left = 0.0


## Into the back of the patrol car: hidden, inert, carried. The seat is cosmetic --
## no cell bookkeeping, because a child is not a prisoner -- and the report tracks
## the car from here to the reunion.
func ride(car: Vehicle) -> void:
	riding = car
	following = null
	visible = false
	velocity = Vector3.ZERO
	stop_navigating()
	var shape := get_node_or_null("Collision") as CollisionShape3D
	if shape:
		shape.set_deferred("disabled", true)


## The found states replace the brain: at heel there is no strolling, no gawking and
## no fleeing -- the child is in somebody's care. Riding, there is nothing to think
## about at all.
func _think(delta: float) -> void:
	if riding != null:
		return
	if following != null:
		if not is_instance_valid(following):
			# The finder left the world; wait where they were left until the report's
			# scan hands them to somebody else.
			following = null
			stop_navigating()
			return
		_heel_left -= delta
		if _heel_left > 0.0:
			return
		_heel_left = 0.3
		var behind := following.global_position
		var back := following.global_basis.z
		back.y = 0.0
		if back.length() > 0.01:
			behind += back.normalized() * HEEL_GAP
		var offset := behind - global_position
		offset.y = 0.0
		if offset.length() > HEEL_SLACK:
			navigate_to(behind)
		return
	super(delta)


## The stroll is the parent's, filtered to the tether. When every legal move leads out
## of range the unfiltered list is returned instead -- a stranded child frozen on one
## tile reads as a bug, and one loose hop is recovered on the next.
func _moves_here() -> Array[Vector2i]:
	var moves := super()
	var kept: Array[Vector2i] = []
	for move in moves:
		var spot := CityGrid.tile_centre(move.x, move.y)
		var offset := spot - wander_centre
		offset.y = 0.0
		if offset.length() <= roam_radius:
			kept.append(move)
	return kept if not kept.is_empty() else moves
