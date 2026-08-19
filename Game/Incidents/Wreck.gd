extends Incident
class_name Wreck

## A written-off car across the carriageway, waiting for a recovery truck.
##
## **The first incident that outlives its casualties.** Every other call in this game ends
## when the last body leaves the scene; a collision leaves a car in the road, and the
## street stays shut until somebody tows it. That is the whole point of the unit that
## clears it, and the reason an RTC now has a tail rather than a finish line.
##
## Blocks the street the three ways [Debris] does, and for the same three reasons: a
## raised [Cordon] turns ambient traffic back, a solid `Blocker` in the scene actually
## stalls a vehicle that drives at it, and this class's own group is what
## `Vehicle.road_is_blocked` scans so a stalled player vehicle can write the street off
## and route round.

const WRECK_GROUP := &"wrecks"

## How far from a wreck's centre anything else must be placed.
##
## The `Blocker` is 5.5m square, so its face stands 2.75m out; a person's own capsule
## holds them a further ~0.4m off it. **Casualties spawned inside this were trapped under
## the car** -- reported from play, and the reason the figure is named rather than left as
## whatever offset happened to look right in the editor.
const CLEAR_RADIUS := 3.6

## The body left in the road. A civilian saloon, collision-stripped and laid over: the
## same car the traffic is made of, which is what makes it read as one of them.
const BODY := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Medium_01.tscn"

## One truck's recovery rate: about ten seconds of winching. Slower than a shed load,
## because a car is not something two people pick up -- and the wait is the cost of not
## having bought a recovery truck.
@export var clear_per_second := 0.1

var cleared := 0.0


func _ready() -> void:
	super()
	add_to_group(WRECK_GROUP)
	_lay_the_car()
	# Raised directly rather than through `raise_cordon()`: that call cones the scene, and
	# the car in the road is the visual. The ring still turns traffic back either way.
	var cordon := Cordon.new()
	cordon.name = "Cordon"
	cordon.raised = true
	add_child(cordon)


## Winching from a [ClearOrder]. Named to match [Debris] so one order serves both.
## Guards `active` so a truck working in the resolution frame cannot resurrect it.
func clear(amount: float) -> void:
	if not active:
		return
	cleared = minf(cleared + amount, 1.0)
	if cleared >= 1.0:
		_finish(true)


func describe_state() -> String:
	if cleared > 0.0:
		return "on the winch"
	return "written off across the carriageway"


func progress() -> float:
	return cleared


## The car itself: dropped on its side, angled off the lane, seeded per instance so two
## wrecks in one shift do not sit identically. The `_wear_outfit()` idiom -- a cosmetic
## draw on its own generator, never a stream anything reproducible shares.
func _lay_the_car() -> void:
	var packed := load(BODY) as PackedScene
	if packed == null:
		return
	var body := packed.instantiate()
	_strip_collision(body)
	add_child(body)
	var pick := RandomNumberGenerator.new()
	pick.seed = get_instance_id()
	var node := body as Node3D
	if node == null:
		return
	node.rotation.y = pick.randf() * TAU
	# Rolled most of the way onto its side, and nose-down a little. Enough to read as
	# wrecked from the camera's height rather than as a car that has simply parked.
	node.rotation.z = deg_to_rad(74.0 + pick.randf() * 16.0)
	node.rotation.x = deg_to_rad(-6.0 + pick.randf() * 12.0)
	node.position.y = 0.75


## The shipped prefabs wrap their meshes in StaticBody3D. The Blocker in the scene file is
## the one deliberate solid; the wreck's own body must not add a second.
func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_collision(child)
