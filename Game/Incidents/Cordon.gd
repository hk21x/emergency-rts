extends Node3D
class_name Cordon

## A ring of cones an officer puts out to keep the public away from a scene.
##
## Two states. While an officer is still walking to it and setting it out it is
## *pending* -- nothing is drawn and it does nothing. Once raised, the cones appear and
## civilians treat the ring the way they treat a fire: they get out of it and stay out.
##
## Cones are visual only. The colliders that ship on the prefab are dropped, because a
## cordon that physically blocked the road would trap the ambulance the officer put it
## there to make room for. Keeping the public out is a decision the crowd makes, not a
## wall.

const GROUP := &"cordons"
const CONE_PREFAB := "res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Cone_01.tscn"

## How far out the cones stand, and how far civilians are pushed back.
@export var radius := 6.0
@export var cone_count := 8

## False until the officer has finished setting it out.
var raised := false


func _ready() -> void:
	add_to_group(GROUP)


## Puts the cones out. Called by [SecureOrder] once the work is done.
func raise_cordon() -> void:
	if raised:
		return
	raised = true
	var packed := load(CONE_PREFAB) as PackedScene
	if packed == null:
		push_warning("no cone prefab at %s -- cordon is invisible" % CONE_PREFAB)
		return
	for i in cone_count:
		var angle := TAU * i / cone_count
		var cone := packed.instantiate()
		_strip_collision(cone)
		add_child(cone)
		cone.position = Vector3(sin(angle), 0.0, cos(angle)) * radius
		cone.rotation.y = angle


## True if [param point] is inside the ring, and the ring is actually up.
func contains(point: Vector3) -> bool:
	if not raised:
		return false
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() < radius


## The shipped props wrap their mesh in a StaticBody3D. Left in, a cordon would be
## eight bollards in the road and the officer who placed it could not walk back out.
func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_collision(child)
