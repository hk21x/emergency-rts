extends Incident
class_name Debris

## A shed load: cargo strewn across the carriageway, shutting the street until a crew
## clears it.
##
## The blocking is done three ways because three different things need telling. A raised
## [Cordon] child turns the ambient traffic back -- cars already honour cordons, and the
## cordon spawns no cones because the boxes *are* the visual. A solid `Blocker` body in
## the scene stalls anything that drives at it -- without something physical a vehicle
## never stops, and both consumers of `road_is_blocked` only fire on a stalled vehicle.
## And `Vehicle.road_is_blocked` scans this class's group, which is what lets a stalled
## player vehicle write the street off and route round the block.

const DEBRIS_GROUP := &"debris"

const BOX_PREFABS := [
	"res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_CardboardBox_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_CardboardBox_02.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_CardboardBox_03.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_CardboardBox_04.tscn",
]

## One worker's clearing rate: about seven seconds of standing at the boxes. Two crew
## members halve it, the same arithmetic as every other WorkOrder job.
@export var clear_per_second := 0.15

var cleared := 0.0


func _ready() -> void:
	super()
	add_to_group(DEBRIS_GROUP)
	_scatter_boxes()
	# Raised directly, never through raise_cordon(): that call cones the scene, and the
	# spilled cargo is the visual here. The ring still turns traffic back either way.
	var cordon := Cordon.new()
	cordon.name = "Cordon"
	cordon.raised = true
	add_child(cordon)


## Work from a [ClearOrder]. Guards `active` so a crew shovelling in the resolution
## frame does not resurrect the incident.
func clear(amount: float) -> void:
	if not active:
		return
	cleared = minf(cleared + amount, 1.0)
	if cleared >= 1.0:
		_finish(true)


func describe_state() -> String:
	if cleared > 0.0:
		return "being cleared"
	return "boxes across the carriageway"


func progress() -> float:
	return cleared


## The spilled cargo. Cosmetic draw on its own instance-seeded generator, the
## _wear_outfit() idiom: never a stream anything reproducible shares.
func _scatter_boxes() -> void:
	var pick := RandomNumberGenerator.new()
	pick.seed = get_instance_id()
	var count := 4 + pick.randi() % 3
	for i in count:
		var packed := load(str(BOX_PREFABS[pick.randi() % BOX_PREFABS.size()])) as PackedScene
		if packed == null:
			continue
		var box := packed.instantiate()
		_strip_collision(box)
		add_child(box)
		var angle := pick.randf() * TAU
		box.position = Vector3(sin(angle), 0.0, cos(angle)) * (0.6 + pick.randf() * 1.8)
		box.rotation.y = pick.randf() * TAU


## The shipped props wrap their meshes in StaticBody3D. The Blocker in the scene file is
## the one deliberate solid; loose boxes must not add bollards of their own.
func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_collision(child)
