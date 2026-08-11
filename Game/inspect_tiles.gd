extends SceneTree

## Dev utility: renders a contact sheet of kit prefabs so the right piece can be
## picked by looking at it rather than by guessing from its name. Must run WITH a
## window (no --headless):
##
##   godot --path . --script res://Game/inspect_tiles.gd -- <dir> <filter> [pitch] [pitch_deg]
##
## e.g. -- res://Assets/Synty/PolygonCity/Prefabs/Environments Road 6 90
##
## Every piece is laid on a [param pitch]-metre grid in name order and shot from
## above (pitch_deg 90) or from a raking angle, which is what you want for anything
## with height. Output goes to user://shots/.

const OUT_DIR := "user://shots/"
## Kit pieces occupy local x[0,5] z[-5,0], so this recentres them on their cell.
const KIT_OFFSET := Vector3(-2.5, 0.0, 2.5)

var _names := PackedStringArray()
var _dir := ""
var _pitch := 6.0
var _angle := 90.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <dir> <filter> [pitch] [pitch_deg]")
		quit(1)
		return
	_dir = args[0]
	if not _dir.ends_with("/"):
		_dir += "/"
	var filter: String = args[1].to_lower()
	if args.size() > 2:
		_pitch = float(args[2])
	if args.size() > 3:
		_angle = float(args[3])

	for file in DirAccess.get_files_at(_dir):
		if file.ends_with(".tscn") and file.to_lower().contains(filter):
			_names.append(file.get_basename())
	_names.sort()
	if _names.is_empty():
		print("nothing matching '%s' in %s" % [filter, _dir])
		quit(1)
		return

	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var scene := Node3D.new()
	root.add_child(scene)

	var columns := int(ceil(sqrt(float(_names.size()))))
	var rows := int(ceil(float(_names.size()) / columns))

	for i in _names.size():
		var packed := load(_dir + _names[i] + ".tscn") as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		scene.add_child(node)
		node.position = _cell(i, columns) + KIT_OFFSET
		# A label per cell, so the sheet is self-identifying. Billboarded upright
		# rather than lying flat, so it stays legible from a raking camera too.
		var label := Label3D.new()
		label.text = _names[i].replace("SM_Env_", "").replace("SM_Bld_", "")
		label.font_size = 96
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.95, 0.4)
		label.outline_size = 32
		scene.add_child(label)
		label.position = _cell(i, columns) + Vector3(0.0, 0.2, _pitch * 0.42)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	light.light_energy = 1.2
	scene.add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.18, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = environment
	scene.add_child(world)

	# Frame the whole sheet: orthogonal, so every cell is drawn at the same scale
	# and pieces can be compared directly.
	var centre := Vector3(
		(columns - 1) * _pitch * 0.5, 0.0, (rows - 1) * _pitch * 0.5)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(columns, rows) * _pitch * 1.06
	camera.far = 800.0
	scene.add_child(camera)
	if _angle >= 89.9:
		# Straight down, with the basis written out rather than derived from look_at.
		# Looking along -Y makes the up vector colinear with the view, so look_at picks
		# an arbitrary roll -- which silently makes the whole sheet useless for reading
		# which way a piece is authored. This pins screen-right to +X and screen-down
		# to +Z, so a marking's edge can be read straight off the image.
		camera.global_transform = Transform3D(
			Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
			centre + Vector3(0.0, 200.0, 0.0))
	else:
		var radians := deg_to_rad(_angle)
		camera.global_position = centre + Vector3(0.0, sin(radians), cos(radians)) * 200.0
		camera.look_at(centre, Vector3.UP)

	await _wait(40)
	await RenderingServer.frame_post_draw
	var shot_name := "sheet_%s" % _names[0].to_lower().substr(0, 12)
	root.get_texture().get_image().save_png(OUT_DIR + shot_name + ".png")
	if _angle >= 89.9:
		print("plan view: screen-right is +X, screen-down is +Z")
	print("%d pieces -> %s" % [
		_names.size(), ProjectSettings.globalize_path(OUT_DIR + shot_name + ".png")])
	quit()


func _cell(index: int, columns: int) -> Vector3:
	return Vector3((index % columns) * _pitch, 0.0, (index / columns) * _pitch)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
