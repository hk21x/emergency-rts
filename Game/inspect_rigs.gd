extends SceneTree

## Dev utility: dumps the node tree of the rig sources, so retargeting can be pointed
## at the right Skeleton3D nodes.
##
##   godot --headless --path . --script res://Game/inspect_rigs.gd

const SOURCES: Array[String] = [
	"res://Assets/Synty/PolygonStarter/Models/Characters.fbx",
	"res://Assets/animations/UAL1_Standard.glb",
]


func _init() -> void:
	for path in SOURCES:
		print("\n=== %s ===" % path)
		if not ResourceLoader.exists(path):
			print("  MISSING")
			continue
		var root := (load(path) as PackedScene).instantiate()
		_dump(root, root, 0)
		root.free()
	quit()


func _dump(node: Node, root: Node, depth: int) -> void:
	var detail := ""
	if node is Skeleton3D:
		detail = "  <-- bones=%d  subresource key: \"PATH:%s\"" % [
			(node as Skeleton3D).get_bone_count(), root.get_path_to(node)]
	elif node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		detail = "  surfaces=%d" % (mesh.get_surface_count() if mesh else 0)
	elif node is AnimationPlayer:
		detail = "  clips=%d" % (node as AnimationPlayer).get_animation_list().size()
	print("%s%s [%s]%s" % ["  ".repeat(depth), node.name, node.get_class(), detail])
	for child in node.get_children():
		_dump(child, root, depth + 1)
