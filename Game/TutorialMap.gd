extends Node
class_name TutorialMap

## The tutorial scene's setup node -- and the one classifier both its builders share.
##
## The tutorial town is the user's hand-authored scene under Assets/PolygonTown, which
## this project treats as read-only input: `build_tutorial.gd` instances it, stamps
## collision layers so the navigation bake can tell a road from a pavement from a
## house, bakes, and saves the shell. But `PackedScene.pack()` deliberately drops
## property overrides on non-owned instance children -- the same behaviour the minimap
## once lost its camera path to -- so the stamps do not survive into the saved file.
## This node re-applies them at runtime, from the same static classifier the processor
## baked with. One table, two callers: the mesh and the world can never disagree.
##
## It also owns the lattice flag. [CityGrid]'s tables describe the generated district,
## and on this map every one of their answers would be a confident lie -- so entering
## the tree switches the lattice-guarded machinery off, and leaving it switches it
## back on. Scene changes free the old scene, so the district always gets its lattice
## back without anyone remembering to give it back.

## Prefab families whose colliders are carriageway.
##
## Deliberately NOT the driveways. Each one is severed from the road by the sidewalk
## strip it crosses, so stamping them drivable minted six two-polygon islands --
## measured by a union-find over the baked mesh -- and the station's spawn point
## clamped onto one, which marooned every dispatched vehicle on a stub of drive.
## The 138-polygon street network is the road; drives are scenery.
const ROAD_PREFIXES: Array[String] = ["SM_Env_Road"]

## Prefab families whose colliders are made ground: pavements, paths, forecourts.
const PAVEMENT_PREFIXES: Array[String] = [
	"SM_Env_Sidewalk", "SM_Env_Path", "SM_Env_Concrete_Base",
]

## Prefab families that are open ground -- lawns, verges, flower beds. Walkable like
## a pavement, and separated from one only at bake time.
##
## The town tiles grass **under everything** and lays its sidewalks and roads on
## top, so a naive parse stacks two walkable surfaces in the same place. That is
## what killed the person mesh twice: the navigation *map* -- not the bake --
## reported more than two edges in one rasterisation cell and then answered every
## layer-2 query with nothing. Sinking the lawns 20cm did not help, because the
## map's height cells are 25cm and both surfaces still landed in one.
##
## `build_tutorial` therefore drops the **covered** lawn tiles from the bake
## entirely (see its `_uncover_lawns`): grass that lies under a pavement or a road
## is scenery, and grass that lies in the open is ground. No stack, no duplicate
## edges, and the gardens and gaps between houses walk properly -- which is what a
## town is.
const LAWN_PREFIXES: Array[String] = [
	"SM_Env_Grass", "SM_Env_DirtPatch", "SM_Env_FlowerPatch",
]

## Road furniture that lies flat in the carriageway and must not be solid. A car
## drives over a manhole; it does not stop dead at one. Both specimens here were
## caught by the black box rather than reasoned out: a speed bump's 13.5cm hull
## walled an ambulance mid-street (the user deleted the bumps on that evidence), and
## a manhole's mesh collider sat exactly where the tutorial's casualty lay, so the
## ambulance sent to it ground against a drain cover for the whole forty seconds a
## probe would give it.
const FLAT_FURNITURE: Array[String] = [
	"SM_Env_Road_SpeedBump", "SM_Prop_Manhole", "SM_Prop_Drain",
]

## build_map.gd's layer scheme, restated because the generator is not loaded at play
## time: world 1, road 16, sidewalk 32.
const LAYER_WORLD := 1
const LAYER_ROAD := 16
const LAYER_SIDEWALK := 32

## How many people are about. The district runs 60 over 260m; this town is smaller
## and its shout is a lesson, so a couple of dozen is enough to make the streets
## read as inhabited without crowding the thing the player is meant to be looking at.
const CROWD_SIZE := 24

## Where the crowd may be put down: on the person mesh, and clear of the forecourt
## so nobody is standing in the spawn slot when a vehicle arrives.
const CROWD_CLEAR_OF_STATION := 12.0

## How the minimap frames this town. The playable footprint spans roughly
## X -65..95, Z -100..60 -- centred near (15, -20), not the origin -- so the card
## frames 95m either side of the town's own middle rather than showing it shoved
## into a corner of a district-sized frame.
const MINIMAP_EXTENT := 95.0
const MINIMAP_CENTRE := Vector3(15.0, 0.0, -20.0)


func _enter_tree() -> void:
	CityGrid.lattice_fits = false


func _exit_tree() -> void:
	CityGrid.lattice_fits = true


func _ready() -> void:
	var map := get_node_or_null("../Map")
	if map:
		TutorialMap.stamp(map)
		# The town ships one parked vendor ambulance -- a dead ringer for the
		# player's own, permanently stationed and forever ignoring orders. Any
		# vendor vehicle prop goes, for the same reason.
		for prop in map.find_children("SM_Veh_*", "", true, false):
			prop.queue_free()
		# The vendor scene brings its own two suns, a camera and an environment --
		# all neutralised in favour of the shell's, which carry the game's tuning.
		# Node properties only; the shared vendor resources are never mutated.
		for lamp_name in ["Directional light", "Directional light (2)"]:
			var lamp := map.get_node_or_null(lamp_name) as Node3D
			if lamp:
				lamp.visible = false
		var vendor_camera := map.get_node_or_null("Camera") as Camera3D
		if vendor_camera:
			vendor_camera.current = false
		var vendor_world := map.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if vendor_world:
			vendor_world.environment = null

	# The drop-off works by overlap and needs no advertisement: the red pad decal
	# reads as a mystery marker on a tutorial forecourt. Hidden here rather than in
	# the processor -- pack() drops overrides on the instance's internals.
	var pad := get_node_or_null("../Hospital/Pad") as Node3D
	if pad:
		pad.visible = false

	# A clean slate every entry. The station carries its own career file, so nothing
	# a practice run does can touch the real books.
	var station := get_node_or_null("../Station") as Station
	if station:
		station.reset_career()

	# The minimap photographer, only when asked for by the bake command -- see
	# build_tutorial_minimap.gd for why it rides the game boot rather than being a
	# --script tool (the short version: the script path crashes the engine).
	if OS.get_environment("TUTORIAL_MINIMAP_BAKE") != "":
		var bake := Node.new()
		bake.set_script(load("res://Game/build_tutorial_minimap.gd"))
		bake.name = "MinimapBake"
		add_child(bake)

	_late_setup.call_deferred()


## The HUD's pieces build in their own _ready, and this node readies FIRST (it is
## deliberately the scene's first child, for the lattice flag) -- so everything that
## talks to the HUD lands a frame later. The minimap call especially: made directly
## from _ready it ran before the minimap's own _ready, which then loaded the
## district's photograph over the street plan. The player saw the wrong town.
func _late_setup() -> void:
	var menu := get_node_or_null("../HUD/Root/Menu") as GameMenu
	if menu:
		menu.in_tutorial = true
	var minimap := get_node_or_null("../HUD/Root/World/MinimapCard/Minimap")
	if minimap:
		minimap.use_photo("res://Game/UI/TutorialMinimapBase.png",
			MINIMAP_EXTENT, MINIMAP_CENTRE)
	# Deferred with the rest: a node cannot add children to a parent that is still
	# setting its own up, and _ready runs inside exactly that window -- measured,
	# `add_child() failed` and a town with nobody in it.
	_populate(get_node_or_null("../Station") as Station)


## Stamps collision layers and the road_surface group across the vendor town, by the
## prefab family each collider belongs to. Bodies are classified by their nearest
## ancestor whose name begins `SM_` -- collider node names vary (`BoxCollider`,
## `MeshCollider`) and are never consulted. Everything unrecognised keeps layer 1:
## solid world, but not ground anything paths across.
##
## Then the geometry pass: a lawn tile that lies **under** a pavement, a road or a
## building is put back to plain layer 1. Buried grass would otherwise stack a
## second walkable surface under the first, which is what twice left the town with
## a person mesh the navigation map answered nothing on; grass under a house would
## let a walker stroll through the living room. Both fall out of one rule -- ground
## is ground only where nothing is on top of it.
##
## **The map must be inside the tree.** Every footprint here is a global transform,
## and a Node3D outside the tree answers those with nonsense: the first cut measured
## all 606 lawns at the origin, called every one of them buried, and dropped the lot.
## Puts people on the streets.
##
## Spawned here rather than baked into the scene, and placed from the **person
## navigation mesh's own vertices** rather than from a table of spots: the mesh is
## the one description of this town that cannot drift from it, so every civilian
## starts somewhere a civilian can actually stand -- including the gardens, now
## that the gaps between houses are walkable. They stroll by mesh as well, since
## the pedestrian lattice describes a different city entirely (see Civilian's
## off-lattice branches).
func _populate(station: Station) -> void:
	var region := get_node_or_null("../PersonNavigation") as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		return
	var vertices := region.navigation_mesh.get_vertices()
	if vertices.is_empty():
		return
	var outfits := _civilian_scenes()
	if outfits.is_empty():
		return
	var crowd := Node3D.new()
	crowd.name = "Crowd"
	get_parent().add_child(crowd)

	# Seeded, so a tutorial looks the same every time it is opened -- a lesson that
	# rearranges itself is harder to talk about.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816
	var placed := 0
	var attempts := 0
	while placed < CROWD_SIZE and attempts < CROWD_SIZE * 40:
		attempts += 1
		var spot := vertices[rng.randi() % vertices.size()]
		if station and Vector2(spot.x - station.global_position.x,
				spot.z - station.global_position.z).length() < CROWD_CLEAR_OF_STATION:
			continue
		var packed := load(str(outfits[rng.randi() % outfits.size()])) as PackedScene
		if packed == null:
			continue
		var walker := packed.instantiate() as Node3D
		crowd.add_child(walker)
		# Scattered a little off the vertex, which sits on a mesh edge: dropped
		# exactly there, a row of them lines up along the kerb.
		walker.global_position = spot + Vector3(rng.randf_range(-0.8, 0.8), 0.05,
			rng.randf_range(-0.8, 0.8))
		walker.rotation.y = rng.randf() * TAU
		placed += 1


## The civilian scenes on disk, the way CrowdRefill finds them -- so an outfit added
## to the folder turns up in the tutorial too, with nobody having to list it twice.
func _civilian_scenes() -> Array[String]:
	var scenes: Array[String] = []
	var directory := DirAccess.open("res://Game/Civilians")
	if directory == null:
		return scenes
	for file in directory.get_files():
		var name := str(file).trim_suffix(".remap")
		if name.ends_with(".tscn"):
			scenes.append("res://Game/Civilians/" + name)
	return scenes


## Returns how many lawn tiles were buried, which is what the build prints.
static func stamp(map: Node) -> int:
	if not map.is_inside_tree():
		push_warning("TutorialMap.stamp needs the map in the tree -- "
			+ "global footprints are meaningless outside it")
	var covers: Array[Rect2] = []
	var lawns: Array[Dictionary] = []
	_stamp_walk(map, "", covers, lawns)
	var buried := 0
	for lawn in lawns:
		var centre: Vector2 = (lawn["rect"] as Rect2).get_center()
		for rect in covers:
			if rect.has_point(centre):
				(lawn["body"] as StaticBody3D).collision_layer = LAYER_WORLD
				buried += 1
				break
	return buried


static func _stamp_walk(node: Node, prefab: String, covers: Array[Rect2],
		lawns: Array[Dictionary]) -> void:
	var node_name := str(node.name)
	if node_name.begins_with("SM_"):
		prefab = node_name
	var body := node as StaticBody3D
	if body:
		# Tested before the road match, which its name would otherwise win: the
		# bump's collider is a 13.5cm convex hull with a face past the floor
		# angle, so a vehicle reads it as a wall and stops dead -- the black box
		# caught an ambulance shuffling against one four metres short of it,
		# nothing else within 14m. Visual only: no physics, and (since the same
		# rule runs at bake time) no lump in the drivable mesh either. The town
		# ships none today -- the user deleted them on the same evidence -- so
		# this arm is unexercised defence, kept for the day one is re-authored
		# in. The can_reach precedent: defence in depth, recorded as such.
		if _prefixed(prefab, FLAT_FURNITURE):
			body.collision_layer = 0
		elif _prefixed(prefab, ROAD_PREFIXES):
			body.collision_layer = LAYER_WORLD | LAYER_ROAD
			body.add_to_group("road_surface")
		elif _prefixed(prefab, PAVEMENT_PREFIXES) \
				or _prefixed(prefab, LAWN_PREFIXES):
			body.collision_layer = LAYER_WORLD | LAYER_SIDEWALK

		# What can bury a lawn: made ground and buildings. Every house in this town
		# is one Preset collider covering its whole footprint -- measured -- so a
		# name match on the family is all "indoors" needs.
		var lawn := _prefixed(prefab, LAWN_PREFIXES)
		var covering := not lawn and (_prefixed(prefab, PAVEMENT_PREFIXES)
			or _prefixed(prefab, ROAD_PREFIXES) or prefab.begins_with("SM_Bld"))
		if lawn or covering:
			for child in body.get_children():
				var collider := child as CollisionShape3D
				if collider == null:
					continue
				var rect := _footprint(collider)
				if rect.size.x <= 0.0:
					continue
				if lawn:
					lawns.append({"body": body, "rect": rect})
				else:
					covers.append(rect)
	for child in node.get_children():
		_stamp_walk(child, prefab, covers, lawns)


## True when this prefab family is open ground -- lawns and their kin.
static func is_lawn(prefab: String) -> bool:
	return _prefixed(prefab, LAWN_PREFIXES)


## A collider's world XZ footprint, whatever shape it carries. The basis terms
## matter: a good many of the town's tiles are laid at right angles, which swaps
## the extents.
static func _footprint(collider: CollisionShape3D) -> Rect2:
	var points := PackedVector3Array()
	var box := collider.shape as BoxShape3D
	var convex := collider.shape as ConvexPolygonShape3D
	var concave := collider.shape as ConcavePolygonShape3D
	if box:
		var half := box.size * 0.5
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				points.append(Vector3(half.x * sx, 0.0, half.z * sz))
	elif convex:
		points = convex.points
	elif concave:
		points = concave.get_faces()
	if points.is_empty():
		return Rect2()
	var placement := collider.global_transform
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		var world := placement * point
		low = low.min(Vector2(world.x, world.z))
		high = high.max(Vector2(world.x, world.z))
	return Rect2(low, high - low)


static func _prefixed(prefab: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if prefab.begins_with(prefix):
			return true
	return false
