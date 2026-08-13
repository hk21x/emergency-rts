extends SceneTree

## Renders a unit portrait for every vehicle and character, for the roster avatars.
##
##   godot --path . --script res://Game/build_portraits.gd
##
## **Run this WITH a window.** It renders through a SubViewport, and `--headless` is
## the dummy driver: every capture comes back empty and the portraits save as blank
## PNGs. Same trap the map generator has with its MultiMesh buffers, and just as quiet.
##
## Drawn silhouettes told a car from a person and nothing more. A photograph of the
## actual vehicle tells a patrol car from an ambulance from a van at 38 pixels, which
## is what a roster is for.
##
## Everything is shot **identically**: the same camera direction, the same lighting,
## and -- the part that matters -- one orthogonal frame size shared across each group,
## sized from the largest member. So every vehicle is photographed the same way *and*
## keeps its true size relative to the others: the ambulance is visibly the big one.
## Framing each to its own bounds instead would make a hatchback and a van the same
## size on screen, which is exactly the pattern this is meant to avoid.
##
## Shot from the shipped prefabs rather than the generated scenes: prefabs are pure
## meshes, while a generated vehicle is a CharacterBody3D carrying a navigation agent
## and a script that expects to be in a live map.

const VEHICLE_PREFABS := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/"
const CHARACTER_PREFABS := "res://Assets/Synty/PolygonCity/Prefabs/Characters/"
const OUT_DIR := "res://Game/UI/Portraits/"

## The fire service's palette, worn by both of its placeholder units.
##
## **An alt palette is a texture atlas, not a colour.** Each mesh's UVs index a swatch
## of it, so one palette paints two meshes two different colours and there is no single
## "orange" material to reach for. It has to be *sampled per mesh*; trusting the name
## is how this shipped the wrong colour twice. Averaged over each body's own UVs:
##
##   palette   patrol-car hull     van hull            crew
##   04_A      rgb(.44,.32,.24)    rgb(.27,.29,.28)    rgb(.39,.39,.30)
##             orange              flat charcoal       olive green
##   02_A      rgb(.26,.27,.27)    rgb(.44,.30,.27)    rgb(.50,.42,.35)
##             charcoal            red                 warm tan
##
## 04_A was picked when the engine was the *patrol car's* hull, where it is genuinely
## orange -- and it quietly dressed the firefighter in green for as long as it stood.
## 02_A is the warmest of the twelve on both the van and the crew, so the appliance and
## the people who ride it now share one palette.
const ALT_FIRE := "res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_02_A_mat.tres"

## The doctor's car. 04_A is the one palette in the pack that is orange on the patrol-car
## hull -- see the table above, where it is also flat charcoal on the van and olive on a
## person. It is safe *here* because it is only ever asked for on that hull.
const ALT_DOCTOR := "res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_04_A_mat.tres"

const SIZE := 192
## Front three-quarter from slightly above -- the angle a vehicle is recognisable from.
## Straight side loses the face; straight front loses the length.
const VIEW := Vector3(0.78, 0.46, 0.72)
## Headroom around the largest member of a group, so nothing touches the frame edge.
## Tight, because the avatar crops this square into a circle and every wasted pixel of
## margin is the subject shrinking away from the disc it is meant to fill.
const MARGIN := 1.02

## How far past the second-largest member the frame may stretch for the largest. Sized
## so the appliance -- the only thing this bites on -- keeps its cab and pump in frame
## while the cards it shares a group with keep their scale. See `_shoot_group`.
const OVERFLOW := 1.35

## Everything the roster can show. Vehicles and characters are separate groups because
## they are scaled together within a group, and a person next to a van on one scale
## would be four pixels tall.
const GROUPS := [
	{
		"dir": VEHICLE_PREFABS,
		"names": [
			"SM_Veh_Car_Police_01", "SM_Veh_Car_Ambo_01", "SM_Veh_Car_Van_01",
			"SM_Veh_Car_Sedan_01", "SM_Veh_Car_Taxi_01", "SM_Veh_Car_Small_01",
			"SM_Veh_Car_Medium_01", "SM_Veh_Car_Muscle_01",
			# The appliance comes from the Town pack and wears its own paint, so unlike
			# every other entry here it needs no palette -- it is a fire engine rather
			# than a body pretending to be one. Keep this prefab in step with
			# build_vehicles.VEHICLES: the shop must sell the vehicle that turns up on
			# the forecourt.
			{"prefab": "res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_Firetruck_01.tscn",
				"out": "FireEngine"},
			# The doctor's car, shot under its own name for exactly the reason the fire
			# engine is: build_vehicles asks for `<out>.png` before falling back to the
			# prefab's, so without this the orange car would wear the blue patrol car's
			# avatar in the roster and the shop.
			{"prefab": "SM_Veh_Car_Police_01", "out": "DoctorCar", "palette": ALT_DOCTOR},
		],
	},
	{
		"dir": CHARACTER_PREFABS,
		"names": ["Character_Male_Police", "Character_Female_Police",
			{"prefab": "Character_Male_Police", "out": "Firefighter",
				"palette": ALT_FIRE},
			# The doctor, shot from the same shirted body Game/Doctor.tscn wears. No
			# palette: this one is not a repaint, it is a different civilian body, chosen
			# because a doctor and a paramedic share a service and therefore a
			# selection-ring colour -- the silhouette is the only thing left to tell them
			# apart on the map, and the roster should agree with it.
			{"prefab": "Character_BusinessMan_Shirt", "out": "Doctor"}],
		# A standing figure is far taller than it is wide, so framing on its full height
		# leaves it a thread. Crop to head and shoulders instead: a frame about a third
		# of the figure, aimed a quarter of its height above the middle. Aim any higher
		# and the shot is the top of a cap.
		"height_ratio": 0.34,
		"raise": 0.26,
	},
]

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _failed := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_studio()

	var written := 0
	for group in GROUPS:
		written += await _shoot_group(group)

	if _failed:
		quit(1)
		return
	print("done -- %d portraits in %s" % [written, OUT_DIR])
	quit()


## A fixed lighting rig and an orthogonal camera. Orthogonal rather than perspective so
## the framing carries no foreshortening of its own: two vehicles of the same length
## come out the same length whatever their height.
func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	# The avatar is a coloured disc with the vehicle on it, so the background has to go.
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.88)
	# Generous ambient: with a single key light the shadowed flank of a dark car goes
	# to black, and at 38 pixels a black shape is a black shape whatever it is.
	environment.ambient_light_energy = 0.85
	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-38.0, -125.0, 0.0)
	_stage.add_child(key)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 60.0
	_stage.add_child(_camera)


func _shoot_group(group: Dictionary) -> int:
	var dir := str(group["dir"])
	var names: Array = group["names"]

	# Two passes. The frame size has to come from the whole group before any single
	# member is shot, or each would be scaled to itself and the relative sizes lost.
	var bounds := {}
	var sizes: Array[float] = []
	for entry in names:
		var name := _prefab_of(entry)
		var box := _measure(_prefab_path(dir, name))
		if box.size == Vector3.ZERO:
			_failed = true
			continue
		bounds[name] = box
		sizes.append(maxf(box.size.x, maxf(box.size.y, box.size.z)))
	sizes.sort()

	# **One outlier must not shrink the whole roster.** Framing on the largest member is
	# what keeps the relative sizes honest, and that held while the biggest vehicle was
	# a 5.2m car. The 9m appliance broke it: framed on the group, the patrol car went
	# from filling 82% of its card to 52%, and at the 38px avatar disc that is 31px of
	# car down to 20px -- eight cards degraded to accommodate one. So the frame is capped
	# a little above the *second* largest, and the appliance is allowed to overhang its
	# own card. It is cropped at the tail, still unmistakably a fire engine, and every
	# other vehicle keeps the size it had.
	var widest: float = sizes[sizes.size() - 1] if sizes.size() > 0 else 0.0
	if sizes.size() > 1:
		widest = minf(widest, sizes[sizes.size() - 2] * OVERFLOW)

	var frame := widest * MARGIN * float(group.get("height_ratio", 1.0))
	var written := 0
	for entry in names:
		var name := _prefab_of(entry)
		if not bounds.has(name):
			continue
		if await _shoot(_prefab_path(dir, name), bounds[name], frame,
				float(group.get("raise", 0.0)), _out_of(entry), _palette_of(entry)):
			written += 1
	return written


## A bare name sits in the group's own pack directory; a full `res://` path is taken as
## given, so one subject can come from another pack without every other entry changing.
## Mirrors `build_vehicles._prefab_path` -- the shop has to sell the vehicle that turns
## up on the forecourt, so the two resolve a prefab the same way.
func _prefab_path(dir: String, name: String) -> String:
	return name if name.begins_with("res://") else dir + name + ".tscn"


## A subject is either a prefab name, or a dictionary naming a repainted variant of
## one. Everything downstream asks these three questions and never looks at the shape.
func _prefab_of(entry: Variant) -> String:
	return str(entry["prefab"]) if entry is Dictionary else str(entry)


func _out_of(entry: Variant) -> String:
	return str(entry["out"]) if entry is Dictionary else str(entry)


func _palette_of(entry: Variant) -> String:
	return str(entry.get("palette", "")) if entry is Dictionary else ""


## Swaps the pack's stock body material for an alt palette, wherever it appears.
## Only that one material is touched, so glass and plates keep theirs -- the same
## rule build_vehicles.gd and the ambient traffic's repaint follow.
func _repaint(node: Node, coat: Material) -> void:
	if coat == null:
		return
	for mesh in _meshes(node):
		for surface in mesh.mesh.get_surface_count():
			var active := mesh.get_active_material(surface)
			if active and "PolygonCity_01_A" in active.resource_path:
				mesh.set_surface_override_material(surface, coat)


## The prefab's combined bounding box, in its own space.
func _measure(path: String) -> AABB:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("missing prefab: %s" % path)
		return AABB()
	var model := packed.instantiate()
	_stage.add_child(model)
	var box := _bounds(model)
	_stage.remove_child(model)
	model.queue_free()
	return box


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var found := false
	for mesh in _meshes(node):
		var world_box := mesh.global_transform * mesh.get_aabb()
		box = world_box if not found else box.merge(world_box)
		found = true
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	if mesh and mesh.mesh:
		found.append(mesh)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


func _shoot(path: String, box: AABB, frame: float, raise: float,
		out_name := "", palette := "") -> bool:
	var model := (load(path) as PackedScene).instantiate()
	_stage.add_child(model)
	if palette != "":
		_repaint(model, load(palette) as Material)

	# Centre the subject on the origin, then look at the origin from a fixed direction.
	# Raising the aim point crops a standing figure to its top half rather than its
	# middle, which is what makes a character portrait a portrait.
	var centre := box.get_center() + Vector3.UP * box.size.y * raise
	model.position = -centre
	_camera.size = frame
	_camera.position = VIEW.normalized() * (box.size.length() + 8.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

	var image := await _capture()
	_stage.remove_child(model)
	model.queue_free()

	if image == null or image.is_empty():
		push_error("empty capture for %s -- is this running headless?" % path)
		_failed = true
		return false

	var stem := out_name if out_name != "" else path.get_file().get_basename()
	var out := OUT_DIR + stem + ".png"
	var err := image.save_png(out)
	if err != OK:
		push_error("save failed for %s: %d" % [out, err])
		_failed = true
		return false
	print("  %s" % out.get_file())
	return true


## The viewport's texture is only valid once the frame that drew it has been presented,
## so this waits for the draw rather than reading straight after moving the camera.
func _capture() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var texture := _viewport.get_texture()
	return texture.get_image() if texture else null
