extends SceneTree

## Dev utility: print the AABB of every extracted mesh, so scene authoring can use
## real dimensions instead of guesses.
##
##   godot --headless --path . --script res://Game/inspect_meshes.gd
##   godot --headless --path . --script res://Game/inspect_meshes.gd -- <dir> [filter]
##
## e.g. -- res://Assets/Synty/PolygonCity/Models/extracted/ Veh_Car_Ambo

const DEFAULT_DIR := "res://Assets/Synty/PolygonStarter/Models/extracted/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else DEFAULT_DIR
	var filter: String = args[1].to_lower() if args.size() > 1 else ""

	if not dir.ends_with("/"):
		dir += "/"
	if not DirAccess.dir_exists_absolute(dir):
		print("no such directory: ", dir)
		quit(1)
		return

	var names := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".res") and not file.ends_with(".mesh"):
			continue
		if filter != "" and not file.to_lower().contains(filter):
			continue
		names.append(file)
	names.sort()

	print("%s  (%d matching)" % [dir, names.size()])
	for file in names:
		var mesh := ResourceLoader.load(dir + file) as Mesh
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		print("%-46s size=(%6.2f,%6.2f,%6.2f)  min=(%6.2f,%6.2f,%6.2f)" % [
			file.get_basename(),
			aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.x, aabb.position.y, aabb.position.z,
		])
	quit()
