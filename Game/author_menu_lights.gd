extends SceneTree

## Writes the menu scene's lighting into the scene file, once.
##
##   godot --headless --path . --script res://Game/author_menu_lights.gd
##
## Street lamps on every pole, headlights and a lightbar on each emergency vehicle --
## all of it previously built at run time by [MenuBackdrop], which meant the editor
## viewport showed a scene lit only by two suns while the game showed something else.
## Authored, the editor tells the truth and the lights can be dragged, re-coloured and
## re-aimed by hand like anything else in the scene.
##
## **What this costs, stated plainly.** The lamps used to hang off the shell's
## `StreetLights` node, whose visibility [Daylight] switches with the hour, so they came
## on at dusk by the same mechanism the district's forty use. Authored into the scene
## they are simply on. That is the right trade only because this scene is a *set*: it is
## always dusk here, `MenuBackdrop.HOUR` is a constant, and nothing in a menu ever asks
## for noon. Do not copy the pattern into the district, where the hour is a setting.
##
## Re-running is safe: anything already authored is left alone, so this can be run again
## after adding a third pole without doubling the first two.

const SCENE := "res://Assets/PolygonTown/Scenes/MainMenu.tscn"

## The district's own lamp, from `build_map`: warm, no shadows.
const LAMP_COLOUR := Color(1.0, 0.87, 0.66)
const LAMP_ENERGY := 2.6
const LAMP_RANGE := 11.0
const LAMP_ATTENUATION := 1.4
const LAMP_DROP := 0.45

var _added := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# GEN_EDIT_STATE_MAIN, or the instanced sub-scenes come back collapsed and packing
	# the result would flatten 6,700 nodes of the user's town into one file.
	var packed := load(SCENE) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	# **Into the tree before anything is measured.** Every hull below is read from
	# global transforms, and a Node3D outside the tree answers those with nonsense --
	# the same trap that once measured all 606 of the tutorial's lawn tiles at the
	# origin and concluded every one of them was buried.
	get_root().add_child(root)

	for pole in root.find_children("SM_Prop_LightPole*", "", true, false):
		_lamp(root, pole as Node3D)
	_vehicle(root, root.get_node_or_null("SM_Veh_Car_Police_01") as Node3D,
		[Color(1.0, 0.16, 0.16), Color(0.24, 0.45, 1.0)])
	_vehicle(root, root.get_node_or_null("SM_Veh_Firetruck_01") as Node3D,
		[Color(1.0, 0.20, 0.12), Color(1.0, 0.30, 0.10)])

	get_root().remove_child(root)
	var out := PackedScene.new()
	if out.pack(root) != OK:
		push_error("could not pack the menu scene")
		quit(1)
		return
	if ResourceSaver.save(out, SCENE) != OK:
		push_error("could not save %s" % SCENE)
		quit(1)
		return
	print("authored %d light nodes into %s" % [_added, SCENE])
	quit()


## A bulb at the lantern end of a pole.
func _lamp(root: Node, mast: Node3D) -> void:
	if mast == null or mast.get_node_or_null("Lamp") != null:
		return
	var hull := _hull(mast)
	if hull.size == Vector3.ZERO:
		return
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = LAMP_COLOUR
	lamp.light_energy = LAMP_ENERGY
	lamp.omni_range = LAMP_RANGE
	lamp.omni_attenuation = LAMP_ATTENUATION
	lamp.shadow_enabled = false
	# The hull's centre in plan, so on a cantilevered pole the bulb leans out over the
	# road the way the arm does rather than sitting in the tip of the mast.
	lamp.position = Vector3(hull.get_center().x,
		hull.position.y + hull.size.y - LAMP_DROP, hull.get_center().z)
	_own(mast, lamp, root)


## Headlights and a lightbar, hung off the prop itself so they move with it.
func _vehicle(root: Node, vehicle: Node3D, colours: Array) -> void:
	if vehicle == null or vehicle.get_node_or_null("Headlights") != null:
		return
	var hull := _hull(vehicle)
	if hull.size == Vector3.ZERO:
		return
	# Which way the prop faces, read off the mesh: Synty's vehicles are not all modelled
	# nose-forward.
	var nose := -1.0 if hull.get_center().z <= 0.0 else 1.0

	var beams := Node3D.new()
	beams.name = "Headlights"
	_own(vehicle, beams, root)
	for side in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.name = "Left" if side < 0.0 else "Right"
		beam.light_color = Daylight.BEAM_COLOUR
		beam.light_energy = Daylight.BEAM_ENERGY
		beam.spot_range = Daylight.BEAM_RANGE
		beam.spot_angle = Daylight.BEAM_ANGLE
		beam.spot_angle_attenuation = 0.9
		beam.shadow_enabled = false
		beam.position = Vector3(side * hull.size.x * 0.32,
			hull.position.y + hull.size.y * 0.34,
			hull.get_center().z + nose * hull.size.z * 0.5)
		beam.look_at_from_position(beam.position,
			beam.position + Vector3(0.0, -0.12, nose), Vector3.UP)
		_own(beams, beam, root)

	var bar := Node3D.new()
	bar.name = "Lightbar"
	_own(vehicle, bar, root)
	for i in 2:
		var bead := MeshInstance3D.new()
		bead.name = "Left" if i == 0 else "Right"
		var ball := SphereMesh.new()
		ball.radius = 0.14
		ball.height = 0.28
		bead.mesh = ball
		var glow := StandardMaterial3D.new()
		glow.albedo_color = colours[i]
		glow.emission_enabled = true
		glow.emission = colours[i]
		glow.emission_energy_multiplier = 4.0
		bead.material_override = glow
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bead.position = Vector3((-0.42 if i == 0 else 0.42),
			hull.position.y + hull.size.y + 0.06,
			hull.get_center().z - nose * hull.size.z * 0.08)
		_own(bar, bead, root)
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		lamp.light_color = colours[i]
		lamp.light_energy = 4.0
		lamp.omni_range = 11.0
		lamp.shadow_enabled = false
		_own(bead, lamp, root)


## Adds a node **and gives it an owner**, which is the whole trick: `pack()` writes out
## only what the scene root owns, so an un-owned child is built, saved over, and gone.
func _own(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root
	_added += 1


func _hull(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in _meshes(node):
		var local := (node.global_transform.affine_inverse()
			* child.global_transform) * child.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	if mesh:
		found.append(mesh)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
