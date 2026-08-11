extends SceneTree

## Dev utility: lists the animation clips in the imported animation libraries and the
## skeleton they were authored against, so clips can be matched to the character rig.
##
##   godot --headless --path . --script res://Game/inspect_animations.gd
##
## Pass a filter after `--` to only print clips whose name contains it, e.g.
##   ... --script res://Game/inspect_animations.gd -- sit

const FILES: Array[String] = [
	"res://Assets/animations/UAL1_Standard.glb",
	"res://Assets/animations/UAL1_Standard_RM.glb",
]
## The FBX, not the hand-authored prefab: the prefab bakes its own Skeleton3D, so it
## is unaffected by the importer's retargeting.
const CHARACTER := "res://Assets/Synty/PolygonStarter/Models/Characters.fbx"


func _init() -> void:
	var filter := ""
	var extra := OS.get_cmdline_user_args()
	if extra.size() > 0:
		filter = extra[0].to_lower()

	_report_character_rig()

	for path in FILES:
		if not ResourceLoader.exists(path):
			print("\nMISSING  ", path)
			continue
		var root := (load(path) as PackedScene).instantiate()
		print("\n=== %s ===" % path.get_file())
		_report_skeleton(root)
		_report_animations(root, filter)
		root.free()
	quit()


func _report_character_rig() -> void:
	if not ResourceLoader.exists(CHARACTER):
		return
	var root := (load(CHARACTER) as PackedScene).instantiate()
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	if skeleton:
		print("=== character rig (%s) ===" % CHARACTER.get_file())
		print("  bones: %d" % skeleton.get_bone_count())
		var names := PackedStringArray()
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		print("  all: %s" % ", ".join(names))
	else:
		print("=== character rig: no Skeleton3D in %s ===" % CHARACTER.get_file())
	root.free()


func _report_skeleton(root: Node) -> void:
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		print("  (no Skeleton3D)")
		return
	print("  bones: %d" % skeleton.get_bone_count())
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	print("  all: %s" % ", ".join(names))
	var mesh := _find(root, "MeshInstance3D")
	print("  ships a mesh: %s" % (mesh.name if mesh else "no"))


func _report_animations(root: Node, filter: String) -> void:
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	if player == null:
		print("  (no AnimationPlayer)")
		return

	var clips := PackedStringArray()
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for clip in library.get_animation_list():
			clips.append(clip)
	clips.sort()

	var shown := 0
	print("  clips: %d" % clips.size())
	for clip in clips:
		if filter != "" and not clip.to_lower().contains(filter):
			continue
		var animation := player.get_animation(clip)
		print("    %-52s %5.2fs  loop=%s" % [clip, animation.length, animation.loop_mode != 0])
		shown += 1
	if filter != "":
		print("  (%d matched '%s')" % [shown, filter])


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found:
			return found
	return null
