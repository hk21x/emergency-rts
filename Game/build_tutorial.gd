extends SceneTree

## Builds the playable tutorial scene from the user's hand-authored town.
##
##   godot --headless --path . --script res://Game/build_tutorial.gd
##
## Input:  res://Assets/PolygonTown/Scenes/Tutorial.tscn  -- read-only, never edited.
## Output: res://Game/Tutorial.tscn                       -- never hand-edited.
##
## The output is a thin shell: it *instances* the vendor town rather than duplicating
## its 6,700 nodes, adds the game's system nodes around it, and carries the two baked
## navigation meshes. The bake needs road/pavement collision layers, which the vendor
## prefabs do not have -- `TutorialMap.stamp()` applies them in memory here, and again
## at runtime in the scene (pack() drops overrides on non-owned instance children, on
## purpose; the runtime stamp is load-bearing, not belt-and-braces).
##
## Headless is fine: unlike build_map, nothing here touches a MultiMesh -- collider
## parsing and the navigation bake run on the servers that headless ships.
##
## Re-run this when the vendor town's ROADS or PAVEMENTS change (the mesh is baked
## here). Prop and building edits need no re-run -- the shell re-instances the town
## fresh on every load.

const IN := "res://Assets/PolygonTown/Scenes/Tutorial.tscn"
const OUT := "res://Game/Tutorial.tscn"

## Where units spawn and where casualties are handed over -- the user's design: one
## spot serves as forecourt and drop-off both, on the town's western parking
## quarter (the wide kerbed apron off the crossing at (-50, 0); the first cut used
## a street kerb at (10, -3) and the black box promptly caught a fire engine
## turning itself against the buildings there). Yaw 0 faces the vehicles out of
## the quarter toward the street. The 0.45 lifts the point onto the town's ground
## surface, so a dispatched vehicle spawns on the apron rather than in its slab.
const STATION_SPOT := Vector3(-47.5, 0.45, 10.0)
const STATION_YAW := 0.0

## How far the pavements are lifted for the vehicle bake. Clear of the 25cm
## rasterisation cell and of the 30cm a bake will climb, so the kerb reads as a cliff
## and the carriageway mesh ends at it. Everything that comes back at this height is
## then thrown away -- see `_drop_lifted`.
const KERB_LIFT := 0.5

## How far above the carriageway datum a polygon has to sit to be a lifted pavement
## top rather than road, as a fraction of the lift. Half of it: the two surfaces end up
## half a metre apart and the town is flat, so nothing lands near the line.
const LIFTED_FLOOR := 0.5

var _root: Node3D
var _solid_count := 0


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	print("building the tutorial scene from %s" % IN)
	_root = Node3D.new()
	_root.name = "Tutorial"

	# First child on purpose: its _enter_tree flips the lattice flag before any
	# sibling's _ready can consult the grid.
	var setup := Node.new()
	setup.set_script(load("res://Game/TutorialMap.gd"))
	_attach(setup, "TutorialSetup")

	# The environment and suns, the district's own tuning (build_map's values).
	var environment: Environment = (load(
		"res://Assets/Synty/PolygonCity/Materials/WorldEnvironmentLighting.tres")
		as Environment).duplicate(true)
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = Color(0.62, 0.70, 0.80)
	var world := WorldEnvironment.new()
	world.environment = environment
	_attach(world, "WorldEnvironment")

	var key := DirectionalLight3D.new()
	key.transform = Transform3D(
		Basis(Vector3(-0.57357645, 0.0, 0.819152),
			Vector3(0.6087486, 0.66913056, 0.4262504),
			Vector3(-0.54811966, 0.74314487, -0.38379753)), Vector3.ZERO)
	key.light_color = Color(1.0, 0.9569, 0.8392)
	key.shadow_enabled = true
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 0.0
	key.directional_shadow_max_distance = 420.0
	_attach(key, "KeyLight")

	var fill := DirectionalLight3D.new()
	fill.transform = Transform3D(
		Basis(Vector3(0.49999997, 0.0, -0.86602545),
			Vector3(-0.43301272, 0.8660254, -0.24999999),
			Vector3(0.75, 0.5, 0.43301266)), Vector3.ZERO)
	fill.light_color = Color(0.8015, 0.8686, 1.0)
	fill.light_energy = 0.27
	_attach(fill, "FillLight")

	# Empty, but present: Daylight's default street_lights_path points here, and the
	# town has no generated lamp circuit to switch.
	_attach(Node3D.new(), "StreetLights")

	# The town itself, instanced -- and stamped in memory so the bake below can tell
	# a road from a lawn from a house.
	var map := (load(IN) as PackedScene).instantiate()
	_attach(map, "Map")
	map.add_to_group("nav_source", true)

	# **Into the tree before any geometry is measured.** A Node3D outside the tree
	# answers global_transform with nonsense, and the first cut of the lawn pass
	# measured every tile at the origin, concluded all 606 were buried under each
	# other, and dropped the lot. Nothing but the town is attached yet, so no system
	# node's _ready runs -- they are added after the bake.
	root.add_child(_root)
	var buried := TutorialMap.stamp(map)
	_solid_count = 0
	# After the stamp, so the buried lawns are already off the parse layer when the
	# thickening pass decides what to thicken.
	_solidify(map)
	print("stamped the town: %d lawn tiles buried, %d ground colliders solidified"
		% [buried, _solid_count])

	# Both masks are the district's exactly: **ground only**. Adding plain layer-1
	# obstacles to the person parse so they would carve the mesh was tried and
	# measured -- Recast has no notion of "obstacle", so every house roof, tree
	# canopy and mountain flank came back as walkable surface: 34,236 polygons, and
	# a navigation map so dense with edges it answered every query with nothing.
	# Where a walker may not go is decided by what ground is baked, exactly as it
	# is in the district -- see TutorialMap.stamp.
	# Vehicle agent radius 1.0 against the district's 1.5, because this town's
	# streets are one 5m tile wide where the district's are two: 1.5 of erosion each
	# side left a 2m ribbon that pinched shut at every corner piece -- measured, a
	# reachability sweep found exactly two drivable points on the whole map. 1.0 is
	# still a car's half-width, so wheels stay off the kerbs.
	# **The vehicle mesh is carved by the pavements and then made of road alone**, and
	# it takes both halves of that to be right. The two faults it sits between:
	#
	# - Baked from the road layer alone, the mesh claims ground a kerb face is
	#   standing in: the town's pavement slabs are 16.5cm kerbs overlapping the road
	#   tiles at every corner, and 8.5cm of real proudness is under the 25cm
	#   rasterisation cell, so the bake cannot see them. The black box caught that
	#   one as an ambulance at full throttle, zero speed, jammed against a sidewalk
	#   corner fifteen metres short of the forecourt, for ever.
	# - Baked from road *and* pavement with the pavements lifted clear of the 30cm a
	#   bake will climb, the kerb becomes a cliff and the carriageway stops where the
	#   carriageway does -- but the lifted tops bake too, as a second sheet. It was
	#   called harmless, "the same shape as a roof". It is not: a kerbside shout puts
	#   the car next to that sheet, it snaps there, and its way home is on the other
	#   one. Six black-box records of an ambulance shuffling away from a shout, the
	#   last of them saying `reachable: false` while sat on a road collider. Measured
	#   afterwards: four components, two of them map-spanning and interleaved.
	#
	# So: lift the pavements, bake, and then drop every polygon that came back at the
	# lifted height (`_drop_lifted`). The kerbs carve, and nothing is left to strand
	# on. One component, and every drivable point can reach the station -- both
	# checked in the suite, because both faults were invisible until they were driven.
	var vehicle_region := _build_navigation("VehicleNavigation", 1.0, 1,
		TutorialMap.LAYER_ROAD | TutorialMap.LAYER_SIDEWALK)
	var person_region := _build_navigation("PersonNavigation", 0.4, 2,
		TutorialMap.LAYER_ROAD | TutorialMap.LAYER_SIDEWALK)

	_attach(Node3D.new(), "Units")
	_attach(Node3D.new(), "Incidents")

	var station := Node3D.new()
	station.set_script(load("res://Game/Station.gd"))
	_attach(station, "Station")
	station.position = STATION_SPOT
	station.rotation_degrees = Vector3(0.0, STATION_YAW, 0.0)
	# One slot at the node itself: every dispatch lands on the spot, facing the
	# station's own yaw (Station.dispatch copies global_rotation verbatim).
	station.slot_count = 1
	station.slot_pitch = 0.0
	station.slot_depth = 0.0
	station.units_path = NodePath("../Units")
	station.career_path = "user://tutorial-career.cfg"

	# The drop-off, co-located with the spawn by design. Safe: delivery fires on
	# body_entered with casualties aboard, and a returning ambulance has left the
	# box and re-enters it.
	var hospital := _spawn("Hospital", "res://Game/Incidents/Hospital.tscn")
	hospital.position = STATION_SPOT

	var camera := Camera3D.new()
	camera.current = true
	camera.near = 0.1
	camera.far = 2000.0
	camera.set_script(load("res://Game/RTSCamera.gd"))
	_attach(camera, "Camera")
	camera.focus = STATION_SPOT
	camera.pan_limit = 110.0

	var marker := _marker_ring("MoveMarker", 0.55, 0.85, Color(1.0, 0.72, 0.15, 0.9))

	var controller := Node3D.new()
	controller.set_script(load("res://Game/RTSController.gd"))
	_attach(controller, "RTSController")
	controller.move_marker_path = controller.get_path_to(marker)
	controller.camera_path = controller.get_path_to(camera)

	var mission := Node.new()
	mission.set_script(load("res://Game/Mission.gd"))
	_attach(mission, "Mission")

	var board := Node.new()
	board.set_script(load("res://Game/Incidents/CallBoard.gd"))
	_attach(board, "CallBoard")
	mission.call_board_path = mission.get_path_to(board)

	var stuck := Node.new()
	stuck.set_script(load("res://Game/StuckLog.gd"))
	_attach(stuck, "StuckLog")

	var nav_debug := Node3D.new()
	nav_debug.set_script(load("res://Game/NavDebug.gd"))
	_attach(nav_debug, "NavDebug")

	var tutor := Node.new()
	tutor.set_script(load("res://Game/TutorialDirector.gd"))
	_attach(tutor, "TutorialDirector")

	var daylight := Node.new()
	daylight.set_script(load("res://Game/Daylight.gd"))
	_attach(daylight, "Daylight")

	var hud := _spawn("HUD", "res://Game/HUD.tscn")
	hud.controller_path = hud.get_path_to(controller)
	hud.mission_path = hud.get_path_to(mission)
	hud.call_board_path = hud.get_path_to(board)
	hud.station_path = hud.get_path_to(station)
	hud.daylight_path = hud.get_path_to(daylight)
	# No director_path: the freeplay Director does not exist here, and the HUD's
	# F2 path and hint are guarded on its absence.
	var minimap := hud.get_node("Root/World/MinimapCard/Minimap")
	minimap.camera_path = minimap.get_path_to(camera)
	controller.selection_box_path = controller.get_path_to(
		hud.get_node("Root/SelectionBox"))

	# The bake reads collision shapes, which need a live tree -- the scene has been
	# in one since the stamp, for the same reason. The two meshes differ by the
	# geometry each parses, and nothing else: the car gets the carriageway, the
	# walker gets the carriageway and everything made to walk on.
	#
	# There used to be a third ingredient here -- the pavements were lifted half a
	# metre before the car's bake, clear of the 30cm it will climb, so its mesh
	# "ended at the kerb". It did end at the kerb, and it also baked the raised
	# pavements as a second sheet of their own. See the note beside the vehicle
	# region: that sheet is where the ambulance kept getting stranded.
	_lift_kerbs(map, KERB_LIFT)
	for region: NavigationRegion3D in [vehicle_region, person_region]:
		if region == person_region:
			_lift_kerbs(map, -KERB_LIFT)
		region.bake_navigation_mesh(false)
		if region == vehicle_region:
			var dropped := _drop_lifted(region.navigation_mesh)
			print("dropped %d lifted pavement polygons from the carriageway mesh"
				% dropped)
		var polygons: int = region.navigation_mesh.get_polygon_count()
		if polygons == 0:
			push_error("navigation bake produced no polygons for %s" % region.name)
			quit(1)
			return
		print("baked %s: %d polygons" % [region.name, polygons])
	root.remove_child(_root)

	_own(_root)
	var packed := PackedScene.new()
	if packed.pack(_root) != OK:
		push_error("could not pack the tutorial scene")
		quit(1)
		return
	if ResourceSaver.save(packed, OUT) != OK:
		push_error("could not save %s" % OUT)
		quit(1)
		return
	print("wrote %s (%d top-level nodes)" % [OUT, _root.get_child_count()])
	quit()


## The vendor ground tiles carry paper-thin box colliders -- the road slab is a
## 5x0x5 box, literally zero-thick -- and the rasteriser makes a mess of them: the
## first bake produced a road mesh in disconnected fragments and a person mesh with
## degenerate merged edges the console warned about outright. Ground boxes are
## thickened downward before the bake, top faces exactly where they were, on
## duplicated shapes so the vendor's shared resources are never touched. In-memory
## only: the Map instance's children are not serialised into the shell, and runtime
## physics is happy with the thin originals -- this is for the bake alone.
## Moves every made pavement and open lawn up or down by [param delta], for the bake
## only. Buried ground is on plain layer 1 by now and is parsed by neither mesh, so it
## is left where it is.
func _lift_kerbs(node: Node, delta: float) -> void:
	var body := node as StaticBody3D
	if body and (body.collision_layer & TutorialMap.LAYER_SIDEWALK) != 0:
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider:
				collider.position.y += delta
	for child in node.get_children():
		_lift_kerbs(child, delta)


## Throws away the pavement tops the lifted bake produced, leaving the carriageway
## they carved. Returns how many polygons went.
##
## The lift is what makes the kerb a cliff the bake will not merge across; keeping what
## it left up there is what stranded the ambulance. A polygon is judged by the mean
## height of its own corners rather than by any one of them, so a road polygon that
## happens to touch a kerb vertex stays road.
func _drop_lifted(mesh: NavigationMesh) -> int:
	var vertices := mesh.get_vertices()
	var heights: Array[float] = []
	for i in mesh.get_polygon_count():
		var poly := mesh.get_polygon(i)
		if poly.size() == 0:
			heights.append(0.0)
			continue
		var total := 0.0
		for index in poly:
			total += vertices[index].y
		heights.append(total / float(poly.size()))

	# The datum is read off the mesh rather than assumed. The town's ground is not at
	# y=0 -- it sits around 0.45, which is why the station spot carries that number --
	# and a hardcoded floor quietly threw the entire carriageway away the first time.
	var lowest := INF
	var highest := -INF
	for height in heights:
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	var floor_line := lowest + KERB_LIFT * LIFTED_FLOOR
	print("  carriageway heights %.2f .. %.2f, dropping above %.2f"
		% [lowest, highest, floor_line])

	var kept: Array[PackedInt32Array] = []
	var dropped := 0
	for i in mesh.get_polygon_count():
		if heights[i] > floor_line:
			dropped += 1
		else:
			kept.append(mesh.get_polygon(i))
	# Rewritten wholesale: NavigationMesh has no "remove polygon", and leaving the
	# vertex array as it was is harmless -- an unreferenced vertex costs nothing and
	# re-indexing every polygon to save a few is a bug waiting to be written.
	mesh.clear_polygons()
	for poly in kept:
		mesh.add_polygon(poly)
	return dropped


func _solidify(node: Node) -> void:
	var body := node as StaticBody3D
	if body and (body.collision_layer & (TutorialMap.LAYER_ROAD
			| TutorialMap.LAYER_SIDEWALK)) != 0:
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider == null:
				continue
			var box := collider.shape as BoxShape3D
			if box == null or box.size.y >= 0.05:
				continue
			var solid := box.duplicate() as BoxShape3D
			var lift := (0.3 - box.size.y) * 0.5
			solid.size.y = 0.3
			collider.shape = solid
			collider.position.y -= lift
			_solid_count += 1
	for child in node.get_children():
		_solidify(child)




func _build_navigation(node_name: String, radius: float, layers: int,
		mask: int) -> NavigationRegion3D:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = mask
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = &"nav_source"
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = radius
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 45.0
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	region.navigation_layers = layers
	_attach(region, node_name)
	return region


func _marker_ring(node_name: String, inner: float, outer: float,
		colour: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	var node := MeshInstance3D.new()
	node.mesh = torus
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attach(node, node_name)
	return node


func _spawn(node_name: String, scene_path: String) -> Node:
	var node := (load(scene_path) as PackedScene).instantiate()
	_attach(node, node_name)
	return node


func _attach(node: Node, node_name := "") -> void:
	if node_name != "":
		node.name = node_name
	_root.add_child(node)


## Ownership, or pack() saves nothing. Recurses into processor-built nodes; stops at
## instance roots (their internals belong to their own scenes and must stay there).
func _own(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		if child.scene_file_path == "":
			_own(child)
