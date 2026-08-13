extends SceneTree

## Generates res://Game/Playground.tscn -- a city district assembled from the
## POLYGON City modular kit.
##
## The kit is a strict 5m grid, and two facts about it are relied on throughout:
## every ground tile, facade segment and roof cap occupies x[0,5] z[-5,0] in its own
## local space, and every building facade looks down +Z. _kit_transform() turns a
## tile centre and a facing into the transform that lands a piece there, so nothing
## below has to think about the corner origin again.
##
## Layout is a 52x52 tile grid (260m square). Two-tile roads cut it into a 5x5 of
## blocks -- and the road spacing is **irregular** (see CityGrid.X_BANDS / Z_BANDS),
## so blocks run from 30m to 50m a side and the district reads as a city that grew
## rather than a grid that was stamped.
##
## Most blocks are a one-tile sidewalk ring around a plot that carries a facade
## terrace. The rest vary: monolithic towers of four families, two public parks
## (walkable, strollable), two parking lots with cars in the stalls, and the civic
## hall. What stands where is BLOCK_PLAN below.
##
## Pathfinding falls out of that directly. Road surfaces are the only geometry the
## vehicle navigation mesh is baked from, so the road network *is* the vehicle graph:
## cars cannot cut across the map because there is nothing off-road to path over.
## People get a second mesh baked from roads *and* sidewalks, so they use the
## pavements and cross wherever they like.
##
## Re-run after editing the layout below -- WITH a window, not headless:
##
##   godot --path . --script res://Game/build_map.gd
##
## The district is drawn with MultiMeshInstance3D (see _flush_batches), and a
## MultiMesh keeps its instance transforms in the RenderingServer rather than in the
## resource. Under --headless that is the dummy driver, which discards them: the
## build still reports success, the scene still saves, and every `buffer` comes back
## empty, so the whole city renders as nothing at all. Baking still works headless --
## navigation reads collision shapes, not meshes -- which is what makes the failure
## so quiet.

const OUT_PATH := "res://Game/Playground.tscn"
const PACK := "res://Assets/Synty/PolygonCity/"
const ENVIRONMENT := PACK + "Materials/WorldEnvironmentLighting.tres"
const CONCRETE := PACK + "Materials/Misc/Generic_Concrete_mat.tres"

## Prefab folders, searched in order to resolve a bare prefab name.
const PREFAB_DIRS := [
	PACK + "Prefabs/Environments/",
	PACK + "Prefabs/Environments/Custom/",
	PACK + "Prefabs/Buildings/",
	PACK + "Prefabs/Buildings/Custom/",
	PACK + "Prefabs/Props/",
	# For the parked cars in the lots -- static batched bodies, not units.
	PACK + "Prefabs/Vehicles/",
]

# --- Grid --------------------------------------------------------------------

## The grid itself lives in CityGrid, because the ambient traffic and pedestrians
## navigate by it too -- see the note there. Aliased rather than referenced through
## the class everywhere, so the layout code below stays readable.
const TILE := CityGrid.TILE
const GRID := CityGrid.GRID
const ROAD_WIDTH := CityGrid.ROAD_WIDTH
const BLOCKS := CityGrid.BLOCKS
const ORIGIN := CityGrid.ORIGIN
const MAP_HALF := CityGrid.MAP_HALF

## One storey of the apartment and shop kit.
const STOREY := 3.0
## Top of a sidewalk slab. Matches the kerb modelled into the sidewalk meshes, so
## people stand on the pavement rather than 7cm inside it.
const KERB := 0.07
## How far out from a sidewalk tile's centre street furniture is set, towards the
## gutter and away from the line people walk.
const KERB_INSET := 1.6
## Up the lamp standard to its bulb. Measured, not chosen: LightPole_Base_02 is 4.95m
## tall and the top 60cm of its geometry averages to the post axis, so a light at 4.6
## hangs just under the head instead of glowing inside the pole.
const LAMP_HEIGHT := 4.6
## The four diagonals, for anything that sits on a corner rather than a side.
const CORNERS: Array[Vector3] = [Vector3(-1, 0, -1), Vector3(1, 0, -1),
	Vector3(1, 0, 1), Vector3(-1, 0, 1)]

# --- Collision layers --------------------------------------------------------
# 1 world, 2 knockable props, 4 people, 8 incidents are already spoken for.

## Drivable surface. The vehicle navigation mesh is baked from this and nothing else.
const LAYER_ROAD := 16
## Walkable surface that is not a road.
const LAYER_SIDEWALK := 32
const LAYER_WORLD := 1

## Group both navigation meshes are baked from.
const NAV_SOURCE_GROUP := &"nav_source"
## Road slabs join this too, so the minimap can draw the street plan without being
## told the layout.
const ROAD_GROUP := &"road_surface"

# --- Layout ------------------------------------------------------------------

## What stands on each block, indexed [block row][block column] -- so BLOCK_PLAN[0][0]
## is the north-west block. Block sizes come from CityGrid's band tables, so a kind
## has to suit its plot: the round tower needs a 23m footprint and sits on wide
## columns; the civic hall fills the small centre block exactly as it always has.
##
## The hospital and the police station are put diagonally opposite so that a casualty
## run is a real drive across the district rather than a turn at the end of the street.
const BLOCK_PLAN := [
	["apartments", "park", "shops", "tower_old", "parking"],
	["shops", "tower_round", "apartments", "hospital", "apartments"],
	["apartments", "shops", "civic", "shops", "tower"],
	["tower_octagon", "police", "apartments", "park", "shops"],
	["parking", "apartments", "shops", "apartments", "tower_round"],
]

## The monolithic block kinds: one structure filling the plot rather than a terrace.
## `height` sizes the collision wall and MUST match what the stack actually builds --
## a collider standing proud of its building eats the clicks aimed in front of it.
## Footprints and course heights are **measured** from the prefabs (tmp AABB dump),
## not guessed from their names.
const MONOLITHS := {
	"civic": {"height": 8.8, "size": Vector2(19.0, 19.0)},
	"tower": {"height": 13.2, "size": Vector2(15.5, 15.5)},
	"tower_old": {"height": 16.7, "size": Vector2(15.6, 15.6)},
	"tower_round": {"height": 16.1, "radius": 11.6},
	"tower_octagon": {"height": 15.3, "size": Vector2(20.5, 20.5)},
}

## Facade kits. `ground` is the street-level course, `upper` is repeated `storeys`
## times above it, and `roof` caps the stack. Corner variants wrap two faces.
const FACADES := {
	"apartments": {
		"ground": ["SM_Bld_Apartment_Door_01", "SM_Bld_Apartment_01",
			"SM_Bld_Apartment_02", "SM_Bld_Apartment_03"],
		"ground_corner": "SM_Bld_Apartment_Door_Corner_01",
		"upper": ["SM_Bld_Apartment_01", "SM_Bld_Apartment_02", "SM_Bld_Apartment_03"],
		"upper_corner": "SM_Bld_Apartment_Corner_02",
		"roof": "SM_Bld_Apartment_Roof_02",
		"roof_corner": "SM_Bld_Apartment_Roof_Corner_02",
		"storeys": 3,
	},
	"shops": {
		"ground": ["SM_Bld_Shop_01", "SM_Bld_Shop_02", "SM_Bld_Shop_04",
			"SM_Bld_Shop_05", "SM_Bld_Shop_06"],
		"ground_corner": "SM_Bld_Shop_Corner_01",
		"upper": ["SM_Bld_Apartment_01", "SM_Bld_Apartment_02"],
		"upper_corner": "SM_Bld_Apartment_Corner_01",
		"roof": "SM_Bld_Apartment_Roof_01",
		"roof_corner": "SM_Bld_Apartment_Roof_Corner_01",
		"storeys": 1,
	},
	# The two service blocks reuse the apartment kit at shop height, so they read as
	# civic buildings rather than housing. Their signage is what identifies them.
	"hospital": {
		"ground": ["SM_Bld_Apartment_Door_02", "SM_Bld_Apartment_02"],
		"ground_corner": "SM_Bld_Apartment_Corner_03",
		"upper": ["SM_Bld_Apartment_03"],
		"upper_corner": "SM_Bld_Apartment_Corner_03",
		"roof": "SM_Bld_Apartment_Roof_03",
		"roof_corner": "SM_Bld_Apartment_Roof_Corner_03",
		"storeys": 2,
	},
	"police": {
		"ground": ["SM_Bld_Apartment_Door_02", "SM_Bld_Apartment_01"],
		"ground_corner": "SM_Bld_Apartment_Corner_01",
		"upper": ["SM_Bld_Apartment_02"],
		"upper_corner": "SM_Bld_Apartment_Corner_01",
		"roof": "SM_Bld_Apartment_Roof_01",
		"roof_corner": "SM_Bld_Apartment_Roof_Corner_01",
		"storeys": 1,
	},
}

## Blocks that get a forecourt instead of a facade on one side: the two tile rows
## facing the named road become drivable apron, and the building wraps the other
## three sides. This is what makes a station somewhere vehicles can actually park.
const APRONS := {"hospital": "south", "police": "north"}

## Roof cap thickness, added to a terrace's collider so it matches the silhouette.
const ROOF_CAP := 0.8
## Measured tops of the two monolithic buildings: the CityHall mesh, and the office
## stack's roof course at 12.54 plus its own depth.
const CIVIC_HEIGHT := 8.8
const TOWER_HEIGHT := 13.2
## Boundary walls. Unlike buildings these are invisible, so their height is free.
const BOUNDS_HEIGHT := 14.0

var _root: Node3D
var _rng := RandomNumberGenerator.new()
## Where the kerbside hydrants ended up, so they can be written out as nodes an
## appliance can actually refill at rather than as scenery it drives past.
var _hydrants: Array[Vector3] = []
## Where the lamp standards' heads ended up, same idea: a street the district can
## actually light after dark rather than a post that is dark at midnight. Stored as
## the world position of the bulb (measured at 4.6m up the 4.95m post, whose top
## 60cm of geometry is centred on the post axis), so nothing downstream has to know
## the prefab's shape.
var _lamps: Array[Vector3] = []
## Paint draws only. Its own stream so adding or changing colour picks can never
## shift the layout draws -- the district the tests proved must not move because a
## car changed colour.
var _paint_rng := RandomNumberGenerator.new()
## Prefab name -> scene path, built once by scanning PREFAB_DIRS.
var _index := {}
## Prefab name -> Array of {mesh, material, local} for its drawable parts.
var _parts_cache := {}
## Prefab name -> combined local AABB, for pieces placed by footprint.
var _bounds_cache := {}
## Static geometry is accumulated here and emitted as MultiMeshInstance3D nodes, so a
## district of ~2000 pieces costs a couple of dozen nodes and draw calls rather than
## 2000 of each. Nothing here is ever addressed individually, so nothing is lost.
var _batches := {}


func _init() -> void:
	# Deferred because baking the navigation mesh needs the nodes in a real tree, and
	# the SceneTree's root Window does not exist yet during _init().
	_build.call_deferred()


func _build() -> void:
	_rng.seed = 20260804
	_paint_rng.seed = 20260804 + 7
	_index_prefabs()

	_root = Node3D.new()
	_root.name = "Playground"

	_build_environment()

	# Everything a unit moves on or bumps into goes in one group, which both
	# navigation meshes are baked from. Which of them a piece contributes to is
	# decided by its collision layer, not by where it sits in the tree.
	var world := _attach(_root, Node3D.new(), "World")
	world.add_to_group(NAV_SOURCE_GROUP, true)

	_build_ground()
	_build_surfaces(world)
	_build_bounds(world)
	_build_props()
	# One node per (mesh, material) for the whole district.
	_flush_batches(_attach(_root, Node3D.new(), "City"))

	# Two meshes over the same world. Vehicles get the roads; people get the roads
	# and the pavements, with a small enough radius to use gaps no car would fit.
	_bake_navigation([
		_build_navigation("VehicleNavigation", 1.5, 1, LAYER_ROAD),
		_build_navigation("PersonNavigation", 0.4, 2, LAYER_ROAD | LAYER_SIDEWALK),
	])
	_build_actors()

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("wrote %s (%d nodes, %d batches)" % [OUT_PATH, _count(_root), _batches.size()])
	_root.free()
	quit()


# --- Ground ------------------------------------------------------------------

## Lays every tile in the grid. A tile is road if either of its indices falls in a
## road band; otherwise it belongs to a block, and the block decides.
func _build_ground() -> void:
	for col in GRID:
		for row in GRID:
			if CityGrid.is_road_x(col) or CityGrid.is_road_z(row):
				_road_tile(col, row)
	for bz in BLOCKS:
		for bx in BLOCKS:
			_build_block(bx, bz)


## First tile of the band containing [param index], or -1 when it is not in one.
func _band_start_x(index: int) -> int:
	for start in CityGrid.X_BANDS:
		if index >= start and index < start + ROAD_WIDTH:
			return start
	return -1


func _band_start_z(index: int) -> int:
	for start in CityGrid.Z_BANDS:
		if index >= start and index < start + ROAD_WIDTH:
			return start
	return -1


## Every road tile in the kit is authored for a street running along **Z**, carrying
## its markings on the tile's **+X edge**. The lane lines, the crossing bars and the
## direction arrows all agree on that, so one rule orients the lot: turn the piece so
## its +X edge points at the middle of the band.
##
## That is what puts the two lanes' yellow lines together on the centre line and
## leaves the white ones out at the kerbs. Note this is the opposite convention to the
## building kit, which faces +Z -- hence a second yaw helper.
func _road_tile(col: int, row: int) -> void:
	var centre := _tile_centre(col, row)
	var road_col := CityGrid.is_road_x(col)
	var road_row := CityGrid.is_road_z(row)

	if road_col and road_row:
		# Junction. Markings would have to agree with both streets at once, so it is
		# left bare -- which is also what the kit's own demo does.
		_batch("SM_Env_Road_Bare_01", _kit_transform(centre, 0.0))
		return

	# Across the band, from this lane towards the other one. Which lane this tile is
	# comes from its offset into the band, read off the band tables.
	var lane := (row - _band_start_z(row)) if road_row else (col - _band_start_x(col))
	var inward := Vector3(0.0, 0.0, 1.0) if road_row else Vector3(1.0, 0.0, 0.0)
	if lane != 0:
		inward = -inward

	# Crossings sit on the tiles that flank each junction, which is where the kerb
	# ramps and the corner sidewalks already are: the road tile is a crossing when the
	# tile one step along the street is part of a crossing band.
	var along := col if road_row else row
	var crossing := (CityGrid.is_road_x(along - 1) or CityGrid.is_road_x(along + 1)) \
		if road_row else (CityGrid.is_road_z(along - 1) or CityGrid.is_road_z(along + 1))
	_batch("SM_Env_Road_Crossing_01" if crossing else "SM_Env_Road_YellowLines_01",
		_kit_transform(centre, _yaw_edge(inward)))


## A block: sidewalk ring, then whatever its kind puts inside -- a facade terrace, a
## monolith, a park or a parking lot. Blocks with an apron give up one side of both
## rings to a forecourt.
func _build_block(bx: int, bz: int) -> void:
	var kind: String = BLOCK_PLAN[bz][bx]
	var base_col := CityGrid.block_base_x(bx)
	var base_row := CityGrid.block_base_z(bz)
	var span_x := CityGrid.block_span_x(bx)
	var span_z := CityGrid.block_span_z(bz)
	var apron: String = APRONS.get(kind, "")
	var rows := _plot_rows(apron, span_z)
	var monolith := MONOLITHS.has(kind)

	for bc in span_x:
		for br in span_z:
			var centre := _tile_centre(base_col + bc, base_row + br)
			if _in_apron(bc, br, apron, span_x, span_z):
				_batch("SM_Env_Road_Bare_01", _kit_transform(centre, 0.0))
				continue

			var ring_x := _edge_sign(bc, 0, span_x - 1)
			var ring_z := _edge_sign(br, 0, span_z - 1)
			if ring_x != 0 or ring_z != 0:
				_sidewalk_tile(centre, ring_x, ring_z)
				continue

			if kind == "park":
				_park_tile(centre, bc, br, span_x, span_z)
				continue
			if kind == "parking":
				_parking_tile(centre, bc, br, span_x, span_z)
				continue

			# Inside the ring: the plot the terrace stands on.
			_batch("SM_Env_Sidewalk_01", _kit_transform(centre, 0.0))
			if monolith or br < rows.x or br > rows.y:
				continue
			# Built solid rather than as a hollow ring around a courtyard. A courtyard
			# looks right from directly overhead and wrong from anywhere else: the
			# camera tips down to 52 degrees, which is enough to see over the parapet
			# and straight at the untextured backs of the far facades. Filling it
			# costs a few hidden segments a block and closes the roof over the lot.
			var plot_x := _edge_sign(bc, 1, span_x - 2)
			var plot_z := _edge_sign(br, rows.x, rows.y)
			_facade(centre, plot_x, plot_z, FACADES[kind])

	if monolith:
		_landmark(_block_centre(bx, bz), kind, bx, bz)


## One interior park tile: a grass-path cross through the middle of the lawn, trees
## and furniture scattered over the rest. The grass kit uses the **opposite corner
## origin** to the road kit (x[-5,0], not x[0,5]) -- measured, not assumed -- hence
## its own placement transform.
func _park_tile(centre: Vector3, bc: int, br: int, span_x: int, span_z: int) -> void:
	var mid_c := span_x / 2
	var mid_r := span_z / 2
	var on_ns := bc == mid_c
	var on_ew := br == mid_r
	if on_ns and on_ew:
		_batch("SM_Env_GrassPath_Junction_01", _grass_transform(centre, 0.0))
		return
	if on_ns or on_ew:
		# The GrassPath pieces run their path along local Z; a quarter turn lays the
		# east-west leg of the cross.
		_batch("SM_Env_GrassPath_Straight_01",
			_grass_transform(centre, 0.0 if on_ns else PI * 0.5))
		# A bench beside the path, facing it, every few tiles.
		if _rng.randi() % 3 == 0:
			var out := Vector3(1.0, 0.0, 0.0) if on_ns else Vector3(0.0, 0.0, 1.0)
			if _rng.randi() % 2 == 0:
				out = -out
			_batch("SM_Prop_ParkBench_01", Transform3D(
				Basis(Vector3.UP, _yaw(-out)), centre + out * 2.2 + Vector3(0.0, 0.1, 0.0)))
		return

	_batch("SM_Env_Grass_01", _grass_transform(centre, 0.0))
	# The lawn: trees most tiles, the odd picnic table, flowers in between. Scattered
	# within the tile so the planting does not read as a grid.
	var jitter := Vector3(_rng.randf_range(-1.4, 1.4), 0.1, _rng.randf_range(-1.4, 1.4))
	match _rng.randi() % 5:
		0, 1:
			_batch(_pick(["SM_Env_Tree_01", "SM_Env_Tree_02", "SM_Env_Tree_03"]),
				Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), centre + jitter))
		2:
			_batch("SM_Prop_PicnicTable_01",
				Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), centre + jitter))
		3:
			for i in 3:
				_batch("SM_Env_Flower_01", Transform3D(
					Basis(Vector3.UP, _rng.randf_range(0.0, TAU)),
					centre + Vector3(_rng.randf_range(-1.8, 1.8), 0.12,
						_rng.randf_range(-1.8, 1.8))))
		_:
			pass


## One interior parking-lot tile. The ParkingLines piece is **two tiles wide**
## (measured x[0,10]), so it is laid from every second column; cars stand in the
## stalls, noses alternating. The lot is walkable, not drivable -- the vehicle mesh
## is baked from roads only, so nothing can path into it.
func _parking_tile(centre: Vector3, bc: int, br: int, span_x: int, span_z: int) -> void:
	# Stall rows on alternating tile rows, bare asphalt between.
	if br % 2 == 1:
		if bc % 2 == 1:
			_batch("SM_Env_Road_ParkingLines_01", _kit_transform(centre, 0.0))
			# Not every stall pair is taken; a full lot reads as a wall of cars.
			if _rng.randi() % 3 != 0:
				var body := _pick(["SM_Veh_Car_Sedan_01", "SM_Veh_Car_Small_01",
					"SM_Veh_Car_Van_01", "SM_Veh_Car_Taxi_01", "SM_Veh_Car_Muscle_01",
					"SM_Veh_Car_Medium_01"])
				var nose := 0.0 if _rng.randi() % 2 == 0 else PI
				# A taxi keeps its livery; everything else draws a paint colour.
				var palette: String = "" if body == "SM_Veh_Car_Taxi_01" \
					else str(CAR_PALETTES[_paint_rng.randi() % CAR_PALETTES.size()])
				_batch(body, Transform3D(Basis(Vector3.UP, nose),
					centre + Vector3(_rng.randf_range(2.0, 3.0), 0.02,
						_rng.randf_range(-0.4, 0.4))), palette)
	else:
		_batch("SM_Env_Road_Bare_01", _kit_transform(centre, 0.0))
	# The lot's own sign, once, by the entrance corner.
	if bc == 1 and br == 1:
		_batch("SM_Prop_Sign_Parking_01", Transform3D(Basis(Vector3.UP, PI * 0.5),
			centre + Vector3(-2.0, 0.05, -2.0)))


## Places a grass-kit piece, whose 5x5 footprint sits at local x[-5,0] z[-5,0] --
## the mirror of the road kit's corner. Same idea as _kit_transform, other corner.
func _grass_transform(centre: Vector3, yaw: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(basis, centre - basis * Vector3(-TILE * 0.5, 0.0, -TILE * 0.5))


## First and last block-tile row the terrace occupies. An apron takes the two rows
## nearest its street, so on that side the building closes up a tile short -- which
## keeps it a closed rectangle facing the forecourt rather than a U you can see into.
func _plot_rows(apron: String, span_z: int) -> Vector2i:
	if apron == "south":
		return Vector2i(1, span_z - 3)
	if apron == "north":
		return Vector2i(2, span_z - 2)
	return Vector2i(1, span_z - 2)


## True if the apron faces the [param side] of the block, where -1 is -Z and +1 is +Z.
func _is_apron_side(apron: String, side: float) -> bool:
	return (apron == "south" and side > 0.0) or (apron == "north" and side < 0.0)


## -1 on the low edge, +1 on the high edge, 0 in between.
func _edge_sign(index: int, low: int, high: int) -> int:
	if index == low:
		return -1
	if index == high:
		return 1
	return 0


func _in_apron(bc: int, br: int, apron: String, span_x: int, span_z: int) -> bool:
	if apron == "" or bc < 1 or bc > span_x - 2:
		return false
	if apron == "south":
		return br >= span_z - 2
	return br <= 1


## Sidewalk pieces carry their kerb on the +Z edge, so the same piece serves all four
## sides once it is turned to face the street. Corners use the wrapping variant.
func _sidewalk_tile(centre: Vector3, out_x: int, out_z: int) -> void:
	var outward := Vector3(out_x, 0.0, out_z)
	if out_x != 0 and out_z != 0:
		_batch("SM_Env_Sidewalk_Corner_01", _kit_transform(centre, _corner_yaw(outward)))
	else:
		_batch("SM_Env_Sidewalk_Straight_01", _kit_transform(centre, _yaw(outward)))


## Stacks one facade segment: street-level course, `storeys` repeats above it, then a
## roof cap. Piece choice is seeded from the tile so a run of shopfronts varies
## without any two builds disagreeing.
##
## An interior segment -- one facing nothing, in the middle of the plot -- is laid the
## same way. Only its roof is ever seen.
func _facade(centre: Vector3, out_x: int, out_z: int, kit: Dictionary) -> void:
	var outward := Vector3(out_x, 0.0, out_z)
	var corner := out_x != 0 and out_z != 0
	var yaw := 0.0
	if corner:
		yaw = _corner_yaw(outward)
	elif out_x != 0 or out_z != 0:
		yaw = _yaw(outward)
	var storeys: int = kit["storeys"]

	_batch(kit["ground_corner"] if corner else _pick(kit["ground"]),
		_kit_transform(centre, yaw))
	for i in storeys:
		var lift := Vector3(0.0, STOREY * (i + 1), 0.0)
		_batch(kit["upper_corner"] if corner else _pick(kit["upper"]),
			_kit_transform(centre + lift, yaw))
	_batch(kit["roof_corner"] if corner else kit["roof"],
		_kit_transform(centre + Vector3(0.0, STOREY * (storeys + 1), 0.0), yaw))

	# The odd aircon unit or dish on the cap, so the roofscape is not one unbroken
	# plane from the camera's height. Interior segments included on purpose -- theirs
	# are the roofs most seen.
	if _rng.randi() % 4 == 0:
		var top := STOREY * (storeys + 1) + ROOF_CAP
		_batch(_pick(["SM_Prop_Roof_Aircon_01", "SM_Prop_Roof_Aircon_02",
			"SM_Prop_Roof_Aircon_03", "SM_Prop_SatDish_01"]),
			Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)),
				centre + Vector3(_rng.randf_range(-1.2, 1.2), top,
					_rng.randf_range(-1.2, 1.2))))


## Single monolithic buildings, for the blocks that are one structure rather than a
## terrace. These are several tiles across and do not share the kit's corner origin,
## so they are placed by their measured footprint instead -- and every stack height
## below is measured from the pieces' AABBs, not read off their names.
func _landmark(centre: Vector3, kind: String, bx: int, bz: int) -> void:
	var yaw := PI * 0.5 * ((bx + bz) % 4)
	match kind:
		"civic":
			_place_centred("SM_Bld_CityHall_01", centre, yaw)
		"tower":
			# The original square office: lobby, a floor course, roof. Kept to ~13m --
			# tall enough to read as an office, short enough not to hide the street
			# beside it from an overhead camera.
			_place_centred("SM_Bld_OfficeSquare_Base_01", centre, yaw)
			_place_centred("SM_Bld_OfficeSquare_02", centre + Vector3(0.0, 3.53, 0.0), yaw)
			_place_centred("SM_Bld_OfficeSquare_Roof_01",
				centre + Vector3(0.0, 12.54, 0.0), yaw)
		"tower_round":
			# Base 6.19m, mid course 9.01m, cap: a 16m drum, 23m across.
			_place_centred("SM_Bld_OfficeRound_Base_01", centre, yaw)
			_place_centred("SM_Bld_OfficeRound_02", centre + Vector3(0.0, 6.19, 0.0), yaw)
			_place_centred("SM_Bld_OfficeRound_Roof_01",
				centre + Vector3(0.0, 15.2, 0.0), yaw)
		"tower_old":
			# The brick-era office: 6m base, two 3.19m floors, a 4.2m mansard roof.
			_place_centred("SM_Bld_OfficeOld_Large_Base_01", centre, yaw)
			_place_centred("SM_Bld_OfficeOld_Large_Floor_01",
				centre + Vector3(0.0, 6.0, 0.0), yaw)
			_place_centred("SM_Bld_OfficeOld_Large_Floor_01",
				centre + Vector3(0.0, 9.19, 0.0), yaw)
			_place_centred("SM_Bld_OfficeOld_Large_Roof_01",
				centre + Vector3(0.0, 12.38, 0.0), yaw)
		"tower_octagon":
			# 3.9m base, two 3m floors, a 5.4m stepped crown.
			_place_centred("SM_Bld_OfficeOctagon_Base_01", centre, yaw)
			_place_centred("SM_Bld_OfficeOctagon_Floor_01",
				centre + Vector3(0.0, 3.9, 0.0), yaw)
			_place_centred("SM_Bld_OfficeOctagon_Floor_01",
				centre + Vector3(0.0, 6.9, 0.0), yaw)
			_place_centred("SM_Bld_OfficeOctagon_Roof_01",
				centre + Vector3(0.0, 9.9, 0.0), yaw)


# --- Collision and navigation ------------------------------------------------

## The physical world, and with it the navigation graph. Road bands and sidewalk
## rings are laid as a handful of slabs rather than one body per tile: the tiles are
## flush, so the join is invisible, and the bake has far less geometry to voxelise.
func _build_surfaces(parent: Node) -> void:
	var roads := _attach(parent, Node3D.new(), "Roads")
	var span := GRID * TILE
	for band in CityGrid.BANDS:
		_slab(roads, "RoadEW_%d" % band,
			Vector3(0.0, 0.0, CityGrid.band_centre_z(band)),
			Vector2(span, TILE * ROAD_WIDTH), LAYER_WORLD | LAYER_ROAD)
		_slab(roads, "RoadNS_%d" % band,
			Vector3(CityGrid.band_centre_x(band), 0.0, 0.0),
			Vector2(TILE * ROAD_WIDTH, span), LAYER_WORLD | LAYER_ROAD)
	for node in roads.get_children():
		node.add_to_group(ROAD_GROUP, true)

	var pavements := _attach(parent, Node3D.new(), "Pavements")
	var buildings := _attach(parent, Node3D.new(), "Buildings")
	for bz in BLOCKS:
		for bx in BLOCKS:
			_build_block_surfaces(pavements, buildings, bx, bz)


func _build_block_surfaces(pavements: Node, buildings: Node, bx: int, bz: int) -> void:
	var kind: String = BLOCK_PLAN[bz][bx]
	var centre := _block_centre(bx, bz)
	var apron: String = APRONS.get(kind, "")
	var tag := "%d%d" % [bx, bz]
	var span_x := CityGrid.block_span_x(bx)
	var span_z := CityGrid.block_span_z(bz)

	# Half the block and half the plot inside its sidewalk ring, in metres.
	var outer_x := TILE * span_x * 0.5
	var outer_z := TILE * span_z * 0.5
	var inner_x := outer_x - TILE
	var inner_z := outer_z - TILE

	# Sidewalk ring: the two z edges run the full width, the two x edges fill between.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var edge := Vector3(0.0, 0.0, side * (outer_z - TILE * 0.5))
		if not _is_apron_side(apron, side):
			_slab(pavements, "PaveZ_%s_%d" % [tag, i], centre + edge,
				Vector2(TILE * span_x, TILE), LAYER_WORLD | LAYER_SIDEWALK, KERB)
			continue
		# The apron takes this side of both rings: two tiles deep, and drivable
		# rather than walkable.
		_slab(pavements, "Apron_%s" % tag,
			centre + Vector3(0.0, 0.0, side * (outer_z - TILE)),
			Vector2(TILE * (span_x - 2), TILE * 2.0), LAYER_WORLD | LAYER_ROAD)
		# Its two corners stay pavement, so the ring is never broken.
		for j in 2:
			var corner := -1.0 if j == 0 else 1.0
			_slab(pavements, "Kerb_%s_%d%d" % [tag, i, j],
				centre + edge + Vector3(corner * (outer_x - TILE * 0.5), 0.0, 0.0),
				Vector2(TILE, TILE), LAYER_WORLD | LAYER_SIDEWALK, KERB)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_slab(pavements, "PaveX_%s_%d" % [tag, i],
			centre + Vector3(side * (outer_x - TILE * 0.5), 0.0, 0.0),
			Vector2(TILE, TILE * (span_z - 2)), LAYER_WORLD | LAYER_SIDEWALK, KERB)

	# Parks and parking lots have no building at all: their whole interior is one
	# walkable slab, joined to the ring, so people stroll the lawn and cut across
	# the stalls -- and a freeplay call can open there.
	if kind == "park" or kind == "parking":
		_slab(pavements, "Lot_%s" % tag, centre,
			Vector2(inner_x * 2.0, inner_z * 2.0), LAYER_WORLD | LAYER_SIDEWALK, 0.1)
		return

	# A monolith's collider comes from the same measured table as its stack. The
	# round tower gets a cylinder: a 23m box around a 23m drum would eat the clicks
	# aimed past its shoulders.
	if MONOLITHS.has(kind):
		var config: Dictionary = MONOLITHS[kind]
		if config.has("radius"):
			_column(buildings, "Block_%s" % tag, centre,
				float(config["radius"]), float(config["height"]))
		else:
			_wall(buildings, "Block_%s" % tag, centre,
				config["size"] as Vector2, float(config["height"]))
		return

	# Derived from _plot_rows, exactly as the facades are, so the collision cannot
	# drift from the geometry when a block gains or loses a forecourt.
	var rows := _plot_rows(apron, span_z)
	var near := centre.z + TILE * (rows.x - (span_z - 1) * 0.5 - 0.5)
	var far := centre.z + TILE * (rows.y - (span_z - 1) * 0.5 + 0.5)
	_wall(buildings, "Block_%s" % tag, Vector3(centre.x, 0.0, (near + far) * 0.5),
		Vector2(inner_x * 2.0, far - near), _terrace_height(FACADES[kind]))


## A solid cylindrical obstruction, for the one building that is round. Same rules as
## [method _wall]: world layer only, and the height must match the build.
func _column(parent: Node, node_name: String, centre: Vector3, radius: float,
		height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_attach(parent, body, node_name)
	body.position = centre + Vector3(0.0, height * 0.5, 0.0)

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_attach(body, collider, "Shape")
	return body


## A flat walkable slab. [param top] is where its surface sits; the box hangs below,
## so the surface height is exactly what was asked for.
func _slab(parent: Node, node_name: String, centre: Vector3, size: Vector2,
		layers: int, top := 0.0) -> StaticBody3D:
	var thickness := 0.4
	var body := StaticBody3D.new()
	body.collision_layer = layers
	body.collision_mask = 0
	_attach(parent, body, node_name)
	body.position = centre + Vector3(0.0, top - thickness * 0.5, 0.0)

	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, thickness, size.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_attach(body, collider, "Shape")
	return body


## A solid obstruction. On the world layer only, so it blocks movement without
## appearing in either navigation mesh -- which it does not need to, because neither
## mesh covers the ground it stands on.
##
## [param height] has to match what was actually built. Giving every block the same
## generous box is tempting and wrong: picking is a camera ray, so a collider standing
## proud of its building silently eats the clicks aimed at anything in front of it.
## A 6m police station under a 14m box cannot have its own cars selected.
func _wall(parent: Node, node_name: String, centre: Vector3, size: Vector2,
		height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_attach(parent, body, node_name)
	body.position = centre + Vector3(0.0, height * 0.5, 0.0)

	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, height, size.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_attach(body, collider, "Shape")
	return body


## How tall a terrace built from [param kit] comes out: its street-level course, its
## repeats, and the roof cap on top.
func _terrace_height(kit: Dictionary) -> float:
	return STOREY * (int(kit["storeys"]) + 1) + ROOF_CAP


func _build_bounds(parent: Node) -> void:
	var bounds := _attach(parent, Node3D.new(), "Bounds")
	var span := MAP_HALF * 2.0 + 2.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_wall(bounds, "BoundZ_%d" % i, Vector3(0.0, 0.0, side * (MAP_HALF + 0.5)),
			Vector2(span, 1.0), BOUNDS_HEIGHT)
		_wall(bounds, "BoundX_%d" % i, Vector3(side * (MAP_HALF + 0.5), 0.0, 0.0),
			Vector2(1.0, span), BOUNDS_HEIGHT)


## A region units path across, baked from static colliders on [param mask]. That mask
## is the whole trick: the vehicle mesh sees road slabs only, so it comes out as the
## street plan, while the person mesh also sees pavements and joins the two.
##
## [param layers] is matched against each NavigationAgent3D's navigation_layers, which
## is how one map carries a wide vehicle mesh and a tight person mesh at once.
func _build_navigation(node_name: String, radius: float, layers: int,
		mask: int) -> NavigationRegion3D:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = mask
	# Sourced by group rather than by child nodes, because the same geometry has to
	# feed both regions and a node can only have one parent.
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAV_SOURCE_GROUP
	# Must match the navigation map's cell size/height (the engine defaults), or the
	# baked edges rasterise against a different grid than the map they live on.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = radius
	mesh.agent_height = 1.8
	# Enough to take the 7cm kerb in its stride, so pavement and road join up.
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 45.0

	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	region.navigation_layers = layers
	_attach(_root, region, node_name)
	return region


## Bakes at build time so the shipped scene needs no runtime bake. Baking reads the
## collision shapes, which requires the nodes to actually be in a tree.
func _bake_navigation(regions: Array) -> void:
	root.add_child(_root)
	for region in regions:
		region.bake_navigation_mesh(false)
		var polygons: int = region.navigation_mesh.get_polygon_count()
		if polygons == 0:
			push_error("navigation bake produced no polygons for %s" % region.name)
		else:
			print("baked %s: %d polygons" % [region.name, polygons])
	root.remove_child(_root)


# --- Dressing ----------------------------------------------------------------

func _build_environment() -> void:
	# The pack's environment is tuned for a close-in product shot: its depth fog sits
	# at density 0.26, which over a 130m district bleaches the far blocks, the skyline
	# and the sky itself to a flat grey. Thinned to leave just enough aerial
	# perspective to separate the far side of the map from the near.
	#
	# The fog colour is doing the work at the horizon. At the camera's fixed 52 degree
	# pitch the frame never actually contains sky -- everything above the skyline ring
	# is the surround plane seen at 300m and more, which is to say it is fog. Tinted
	# towards haze so that distance reads as atmosphere rather than as more tarmac.
	#
	# fog_sky_affect only matters if pitch_degrees is wound down far enough to bring
	# the horizon into shot; depth fog saturates at the far plane, so without this the
	# procedural sky behind it would come out the same flat grey.
	#
	# Duplicated rather than edited in place: nothing under Assets/Synty is modified.
	var environment: Environment = (load(ENVIRONMENT) as Environment).duplicate(true)
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = Color(0.62, 0.70, 0.80)
	var world := WorldEnvironment.new()
	world.environment = environment
	_attach(_root, world, "WorldEnvironment")

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9569, 0.8392)
	key.shadow_enabled = true
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 0.0
	key.directional_shadow_max_distance = 420.0
	key.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-125.0), 0.0)
	_attach(_root, key, "KeyLight")

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.8015, 0.8686, 1.0)
	fill.light_energy = 0.27
	fill.shadow_enabled = false
	fill.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(60.0), 0.0)
	_attach(_root, fill, "FillLight")

	# Ground plane under everything, so no camera angle finds a hole between the
	# outermost tiles and the horizon. Flat dark asphalt rather than the pack's
	# concrete material, which is a pale sand colour and rings the district in what
	# looks like desert.
	var surround := StandardMaterial3D.new()
	surround.albedo_color = Color(0.21, 0.22, 0.25)
	surround.roughness = 1.0
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200.0, 1200.0)
	ground.mesh = plane
	ground.material_override = surround
	ground.position.y = -0.05
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attach(_root, ground, "GroundPlane")

	# The city continues past the playable district: a ring of silhouetted blocks well
	# outside the map. The pack's sky dome is deliberately *not* used with it -- the
	# camera pulls back to 130m, which is inside the dome, so its lit underside fills
	# the horizon. The WorldEnvironment sky does the job without that.
	# Pushed out to twice its authored radius so the ring clears the 260m district.
	var skyline := _decor("SM_Gen_Env_Skyline_01", "Skyline")
	skyline.transform = Transform3D(Basis().scaled(Vector3(2.0, 1.5, 2.0)),
		Vector3(0.0, -0.4, 0.0))


## Street furniture. Everything here is batched without collision: it is decoration,
## and it is placed at the kerb rather than down the middle of the pavement, where
## units actually walk. Anything that needs to be interacted with -- a hydrant, a
## cordon -- becomes a real node when the mechanic that uses it arrives.
func _build_props() -> void:
	for bz in BLOCKS:
		for bx in BLOCKS:
			var centre := _block_centre(bx, bz)
			var kind: String = BLOCK_PLAN[bz][bx]
			var apron: String = APRONS.get(kind, "")
			var half_x := TILE * CityGrid.block_span_x(bx) * 0.5 - TILE * 0.5
			var half_z := TILE * CityGrid.block_span_z(bz) * 0.5 - TILE * 0.5

			for side in 4:
				# Each block edge, walked from one corner to the other.
				var outward := _side_normal(side)
				var along := Vector3(outward.z, 0.0, -outward.x)
				var skip := (apron == "south" and outward.z > 0.5) \
					or (apron == "north" and outward.z < -0.5)
				if skip:
					continue
				var outer := half_z if outward.z != 0.0 else half_x
				var reach := half_x if outward.z != 0.0 else half_z
				# The last step either side is the corner tile, left clear for the
				# crossings; longer edges carry more furniture.
				var steps := int(reach / TILE) - 1
				for step in range(-steps, steps + 1):
					# KERB_INSET out from the tile centre, so furniture lines the
					# gutter instead of standing in the middle of the pavement.
					var spot := centre + outward * (outer + KERB_INSET) \
						+ along * (step * TILE)
					_kerb_prop(spot, outward, step)

			_sign_for(kind, centre, apron, bz)

	# Junction furniture, on two opposite corners of each so the crossroads reads as
	# controlled without four of everything crowding it.
	#
	# Deliberately NOT SM_Prop_TrafficLight_01/02/03: those are signal heads meant to
	# hang off a mast arm, and their origin is at the *top* (min y is -0.9), so
	# dropping one on the pavement buries it. Sign_Stop_01 is a complete 2.3m sign
	# standing on its own origin.
	for bz in CityGrid.BANDS:
		for bx in CityGrid.BANDS:
			var junction := CityGrid.junction(Vector2i(bx, bz))
			for i in 2:
				var corner: Vector3 = CORNERS[i * 2]
				# The corner sidewalk tile, pulled in towards the junction it watches.
				var spot := junction + corner * (TILE * 1.5 - KERB_INSET)
				if absf(spot.x) > MAP_HALF or absf(spot.z) > MAP_HALF:
					continue
				_batch("SM_Prop_Sign_Stop_01",
					Transform3D(Basis(Vector3.UP, _yaw(-corner)),
						spot + Vector3(0.0, KERB, 0.0)))


## One piece of street furniture at a kerbside slot. Which one is decided by the slot
## so the same block never comes out twice the same, and so a build is repeatable.
## Everything in the table stands on its own origin (measured) except the trash can.
func _kerb_prop(spot: Vector3, outward: Vector3, step: int) -> void:
	var facing := _yaw(-outward)
	var lifted := spot + Vector3(0.0, KERB, 0.0)
	match _rng.randi() % 12:
		0:
			_batch("SM_Prop_Hydrant_01", Transform3D(Basis(Vector3.UP, facing), lifted))
			# A hydrant is the one piece of kerbside furniture with a *mechanic*
			# behind it, so it is remembered as well as drawn: an appliance refills
			# its tank beside one. The mesh stays in the batch -- this is a bare
			# marker, not a second copy of the prop.
			_hydrants.append(lifted)
		1:
			_batch("SM_Prop_ParkBench_01", Transform3D(Basis(Vector3.UP, facing), lifted))
		2:
			# Centred on its own origin rather than standing on it, so it needs
			# lifting by half its height or it sits sunk into the pavement.
			_batch("SM_Prop_TrashCan_01",
				Transform3D(Basis(Vector3.UP, facing), lifted + Vector3(0.0, 0.44, 0.0)))
		3:
			_batch(_pick(["SM_Env_Tree_01", "SM_Env_Tree_02", "SM_Env_Tree_03"]),
				Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), lifted))
		4, 5:
			# Base_02 is a complete 5m lamp standard. Base_01 is a 6.5m signal mast
			# that expects an arm and a head bolted to it.
			_batch("SM_Prop_LightPole_Base_02",
				Transform3D(Basis(Vector3.UP, facing), lifted))
			# Remembered as well as drawn, the same way a hydrant is: after dark
			# the district hangs a light under each of these heads.
			_lamps.append(lifted + Vector3(0.0, LAMP_HEIGHT, 0.0))
		6:
			_batch("SM_Prop_Planter_01" if step % 2 == 0 else "SM_Prop_Planter_02",
				Transform3D(Basis(Vector3.UP, facing), lifted))
		7:
			_batch("SM_Prop_Mailbox_01", Transform3D(Basis(Vector3.UP, facing), lifted))
		8:
			# A phone box or a paper stand -- the small clutter a real kerb collects.
			_batch("SM_Prop_Phones_01" if step % 2 == 0 else "SM_Prop_Newspaper_01",
				Transform3D(Basis(Vector3.UP, facing), lifted))
		9:
			# 4.5m of shelter, so only where the walk is mid-edge with room to spare.
			if absf(step) <= 1:
				_batch("SM_Prop_BusStop_01",
					Transform3D(Basis(Vector3.UP, facing), lifted))
			else:
				_batch("SM_Prop_ParkingMeter_01",
					Transform3D(Basis(Vector3.UP, facing), lifted))
		_:
			pass


## Signage is what tells the player which building is which -- the two service blocks
## are built from the same kit as the housing.
##
## Sign_Hospital_01 and Sign_Police_01 are fascia boards barely half a metre tall,
## meant to be fixed to a wall. Left on the pavement they read as litter, so they go
## on the building's own face, above the door and over the forecourt.
func _sign_for(kind: String, centre: Vector3, apron: String, bz: int) -> void:
	# One yard houses all three services, so the station says all three -- the police
	# fascia and, since the fire service shipped, the fire department's beside it.
	# Offsets are measured off the boards themselves: Police_01 is 1.94m wide and
	# FireDepartment_01 is 4.20m, both centred on their own origin, so these two
	# centres leave a clean gap and span 6.9m of a 50m block face. The y values put
	# both boards' *centres* level, which their differing heights (0.55 and 0.45) do
	# not do on their own.
	var boards: Array[Dictionary] = []
	match kind:
		"hospital":
			boards.append({"prefab": "SM_Prop_Sign_Hospital_01", "x": 0.0, "y": 2.1})
		"police":
			boards.append({"prefab": "SM_Prop_Sign_Police_01", "x": -2.4, "y": 2.1})
			boards.append({"prefab": "SM_Prop_Sign_FireDepartment_01",
				"x": 1.4, "y": 2.15})
		_:
			return
	var span_z := CityGrid.block_span_z(bz)
	var rows := _plot_rows(apron, span_z)
	# The plot row facing the forecourt, and the outward face of the tile on it.
	var row := rows.y if apron == "south" else rows.x
	var edge := 0.5 if apron == "south" else -0.5
	var outward := Vector3(0.0, 0.0, signf(edge))
	var face := centre.z + TILE * (row - (span_z - 1) * 0.5 + edge)
	for board in boards:
		# The x offset is along the wall, which is the face's own left-right -- so it
		# follows the sign's yaw rather than world x when the block faces south.
		var along := -signf(edge) * float(board["x"])
		_batch(str(board["prefab"]), Transform3D(Basis(Vector3.UP, _yaw(outward)),
			Vector3(centre.x + along, float(board["y"]),
				face + signf(edge) * 0.06)))


func _side_normal(side: int) -> Vector3:
	match side:
		0: return Vector3(0.0, 0.0, -1.0)
		1: return Vector3(1.0, 0.0, 0.0)
		2: return Vector3(0.0, 0.0, 1.0)
		_: return Vector3(-1.0, 0.0, 0.0)


# --- Actors ------------------------------------------------------------------

## The police station forecourt, which is where the shift starts. Diagonally opposite
## the hospital, a couple of blocks in from the map corners on both sides.
const STATION_BLOCK := Vector2i(1, 3)
const HOSPITAL_BLOCK := Vector2i(3, 1)

func _build_actors() -> void:
	var station := _block_centre(STATION_BLOCK.x, STATION_BLOCK.y)
	# North apron: two tiles deep -- the forecourt the fleet parks on.
	var apron := station + Vector3(0.0, 0.0,
		-TILE * (CityGrid.block_span_z(STATION_BLOCK.y) * 0.5 - 1.0))

	# The hydrants, as nodes rather than only as meshes: an appliance refills beside
	# one, so the game has to know where they are and not merely draw them.
	var hydrants := _attach(_root, Node3D.new(), "Hydrants")
	for i in _hydrants.size():
		var hydrant := Node3D.new()
		hydrant.set_script(load("res://Game/Hydrant.gd"))
		_attach(hydrants, hydrant, "Hydrant%d" % (i + 1))
		hydrant.position = _hydrants[i]

	# The street lighting, under every lamp standard the kerb draw put down. Shipped
	# **off**: the district is lit by the key light at midday and switching these on
	# in daylight washes the pavements out. Daylight.gd owns the container's
	# visibility, so dusk is one flag rather than forty.
	#
	# Shadows are off on every one of them. Forty shadow-casting omnis is a real cost
	# for light that only ever falls on flat pavement, and the key light is still
	# casting the shadows that matter.
	var lamps := _attach(_root, Node3D.new(), "StreetLights")
	(lamps as Node3D).visible = false
	for i in _lamps.size():
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.87, 0.66)
		lamp.light_energy = 2.6
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		_attach(lamps, lamp, "Lamp%d" % (i + 1))
		lamp.position = _lamps[i]

	# Empty on purpose: the career starts with money and no units. Everything the
	# player commands is bought through the Station and spawned into this container;
	# the map itself ships nothing but the district. (It used to ship a free shift
	# of seven -- the career economy retired that.)
	var units := _attach(_root, Node3D.new(), "Units")

	# The forecourt itself, as somewhere units come from. One station covers the whole
	# district: this map has a single yard with everything parked on it, and splitting
	# the roster across the hospital as well would buy nothing but a longer walk. The
	# hospital stays what it already is -- where casualties are delivered.
	var house := Node3D.new()
	house.set_script(load("res://Game/Station.gd"))
	_attach(_root, house, "Station")
	house.position = apron
	house.units_path = house.get_path_to(units)

	_build_incidents()
	_build_ambient()

	var camera := Camera3D.new()
	camera.set_script(load("res://Game/RTSCamera.gd"))
	camera.current = true
	camera.near = 0.1
	camera.far = 2000.0
	_attach(_root, camera, "Camera")
	# Open on the forecourt, not on the middle of the station block.
	#
	# Focusing the block centre puts the camera directly over the building, and since
	# picking is a camera ray every unit on the apron below is then behind its roof --
	# the game opened with all seven units unselectable until you panned.
	camera.focus = Vector3(apron.x, 0.0, apron.z)

	# Selection rings live on the units themselves; the controller owns only the
	# destination marker, which it clones per ordered unit.
	var marker := _marker_ring(_root, "MoveMarker", 0.55, 0.85, Color(1.0, 0.72, 0.15, 0.9))

	var controller := Node3D.new()
	controller.set_script(load("res://Game/RTSController.gd"))
	_attach(_root, controller, "RTSController")
	controller.move_marker_path = controller.get_path_to(marker)
	controller.camera_path = controller.get_path_to(camera)

	var mission := Node.new()
	mission.set_script(load("res://Game/Mission.gd"))
	_attach(_root, mission, "Mission")

	# Watches the same incidents the mission does, and groups them into jobs. Passive
	# like the mission: nothing on the map registers with it.
	var board := Node.new()
	board.set_script(load("res://Game/Incidents/CallBoard.gd"))
	_attach(_root, board, "CallBoard")
	mission.call_board_path = mission.get_path_to(board)

	# Freeplay. Inert until the player opens a shift (F2), so the scripted shout --
	# and every test written against it -- runs exactly as it always has.
	# Puts shoppers back on the pavements as medical calls take them. Inert on a district
	# nothing has happened to: it only tops the crowd back up to the size built here.
	var refill := Node.new()
	refill.set_script(load("res://Game/CrowdRefill.gd"))
	_attach(_root, refill, "CrowdRefill")

	# The black box. Records what a player's vehicle was doing when it stopped getting
	# anywhere, because the handling faults that survive are the ones a staged test does
	# not reproduce -- describing one from memory has cost this project whole afternoons.
	var stuck := Node.new()
	stuck.set_script(load("res://Game/StuckLog.gd"))
	_attach(_root, stuck, "StuckLog")

	# Navigation overlay on F4. Off until asked for, and it draws nothing at all until
	# then -- the 360-at-a-junction fault is a disagreement between the lane route, the
	# agent's polyline and the steering aim, and no log shows more than one at a time.
	var nav_debug := Node3D.new()
	nav_debug.set_script(load("res://Game/NavDebug.gd"))
	_attach(_root, nav_debug, "NavDebug")

	# Call spawner on F5. Third of the same shape as the black box and the navigation
	# overlay: inert until a key is pressed, and it places nothing itself -- it asks the
	# director, so every call it opens goes through the same guards a rolled one does.
	var spawner := Node.new()
	spawner.set_script(load("res://Game/CallSpawner.gd"))
	_attach(_root, spawner, "CallSpawner")

	var director := Node.new()
	director.set_script(load("res://Game/Director.gd"))
	_attach(_root, director, "Director")
	director.call_board_path = director.get_path_to(board)
	director.mission_path = director.get_path_to(mission)
	director.incidents_path = director.get_path_to(_root.get_node("Incidents"))
	director.station_path = director.get_path_to(house)
	director.hospital_path = director.get_path_to(_root.get_node("Hospital"))

	# What hour the district works at. Ships at DAY, which is *whatever this generator
	# just wrote* -- the node captures the lights and the environment on ready rather
	# than restating them, so the map at DAY is the map as built and nothing written
	# against it has to move.
	var daylight := Node.new()
	daylight.set_script(load("res://Game/Daylight.gd"))
	_attach(_root, daylight, "Daylight")
	daylight.key_light_path = daylight.get_path_to(_root.get_node("KeyLight"))
	daylight.fill_light_path = daylight.get_path_to(_root.get_node("FillLight"))
	daylight.environment_path = daylight.get_path_to(_root.get_node("WorldEnvironment"))
	daylight.street_lights_path = daylight.get_path_to(_root.get_node("StreetLights"))

	var hud := _spawn(_root, "HUD", "res://Game/HUD.tscn")
	if hud:
		hud.controller_path = hud.get_path_to(controller)
		hud.mission_path = hud.get_path_to(mission)
		hud.call_board_path = hud.get_path_to(board)
		hud.station_path = hud.get_path_to(house)
		hud.director_path = hud.get_path_to(director)
		hud.daylight_path = hud.get_path_to(daylight)
		# A CanvasLayer cannot hold a theme, so the HUD hangs everything off a Root
		# control that can. These two paths cross into that.
		var minimap := hud.get_node("Root/World/MinimapCard/Minimap")
		minimap.camera_path = minimap.get_path_to(camera)
		# The drag rectangle lives inside the HUD scene, so the path crosses into
		# that instance.
		controller.selection_box_path = controller.get_path_to(
			hud.get_node("Root/SelectionBox"))


## The population. Nothing here is commandable -- it is the district being inhabited
## rather than empty, which is most of what separates "a map" from "a place".
const CIVILIANS := "res://Game/Civilians/"
const TRAFFIC := "res://Game/Traffic/"
## Scaled with the district: four times the ground of the 130m map.
const CROWD_SIZE := 60
const TRAFFIC_SIZE := 22
## Clear space between two cars as they are laid down. Comfortably over the longest
## body in the fleet (5.6m), because cars are solid to each other now and a pair
## placed inside one another is ejected by the physics engine, not tolerated.
const TRAFFIC_SPACING := 8.0
## Cleared around the station forecourt, so the shift does not start by reversing
## into a shopper.
const STATION_CLEARANCE := 14.0


func _build_ambient() -> void:
	var outfits := _scene_list(CIVILIANS)
	var cars := _scene_list(TRAFFIC)
	if outfits.is_empty() or cars.is_empty():
		push_warning("no ambient scenes -- run build_civilians.gd and build_vehicles.gd")
		return

	var people := _attach(_root, Node3D.new(), "Crowd")
	var station := _block_centre(STATION_BLOCK.x, STATION_BLOCK.y)
	# Pavement tile centres, straight from the same table that laid the pavements.
	var pavements := CityGrid.pavement_points()
	_shuffle(pavements)

	var placed := 0
	for spot in pavements:
		if placed >= CROWD_SIZE:
			break
		if spot.distance_to(station) < STATION_CLEARANCE:
			continue
		var civilian := _spawn(people, "Civilian%d" % (placed + 1),
			CIVILIANS + outfits[_rng.randi() % outfits.size()])
		if civilian == null:
			return
		# Scattered within the tile rather than stood on its centre, so a crowd does
		# not read as a grid.
		civilian.position = spot + Vector3(
			_rng.randf_range(-1.6, 1.6), 0.05, _rng.randf_range(-1.6, 1.6))
		civilian.rotation.y = _rng.randf_range(0.0, TAU)
		placed += 1

	var traffic := _attach(_root, Node3D.new(), "Traffic")
	var taken: Array[Vector3] = []
	for i in TRAFFIC_SIZE:
		var car := _spawn(traffic, "Traffic%d" % (i + 1),
			TRAFFIC + cars[_rng.randi() % cars.size()])
		if car == null:
			return
		car.transform = _traffic_clear_start(taken)
		taken.append(car.position)


## A starting spot on the road with no other car already in it.
##
## Spacing has to be *checked*, not assumed -- the same lesson the station's dispatch
## slots taught. Two of these used to spawn 3.9m apart, which is inside each other for
## a 5m car. It went unnoticed for as long as traffic could pass through traffic; the
## day they became solid, the physics engine did what it is supposed to and shoved the
## pair apart, and one of them left the world at 600 metres a second.
func _traffic_clear_start(taken: Array[Vector3]) -> Transform3D:
	var start := _traffic_start()
	for attempt in 40:
		var clear := true
		for other in taken:
			if start.origin.distance_to(other) < TRAFFIC_SPACING:
				clear = false
				break
		if clear:
			return start
		start = _traffic_start()
	return start


## Fisher-Yates through the generator's own seeded RNG.
##
## `Array.shuffle()` looks like the obvious call and is the wrong one: it draws from
## Godot's *global* random state, which is seeded afresh at startup, so it ignores the
## seed set in `_init` entirely. The map came out different on every rebuild -- only
## the crowd, so the district looked stable and nobody noticed until a test that
## depended on where a particular civilian stood started failing on a build that had
## changed nothing near it.
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


## Somewhere on the road grid, in lane and pointing the right way. Picked as a segment
## between two junctions rather than a random point on the navigation mesh: a car that
## starts facing across its own street spends its first few seconds doing a three
## point turn in the middle of the road.
func _traffic_start() -> Transform3D:
	var from := Vector2i(_rng.randi() % CityGrid.BANDS, _rng.randi() % CityGrid.BANDS)
	var options := CityGrid.neighbours(from)
	var to: Vector2i = options[_rng.randi() % options.size()]

	var start := CityGrid.junction(from)
	var end := CityGrid.junction(to)
	var direction := (end - start).normalized()
	var right := direction.cross(Vector3.UP)
	var along := start.lerp(end, _rng.randf_range(0.2, 0.8))
	return Transform3D(
		Basis(Vector3.UP, CityGrid.heading(direction)),
		along + right * CityGrid.LANE_OFFSET + Vector3(0.0, 0.2, 0.0))


## Scene filenames in a directory, so adding an outfit or a car body is a build step
## rather than another list to keep in step with the generators.
func _scene_list(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			found.append(file)
	found.sort()
	return found


## The map ships **quiet**: no scripted shout. The district idles -- crowds stroll,
## traffic drives -- until the player opens a freeplay shift (F2) and the Director
## starts producing calls. The empty Incidents container is still load-bearing: it is
## where the Director (and the test suite) parent everything they spawn.
func _build_incidents() -> void:
	_attach(_root, Node3D.new(), "Incidents")

	# Drop-off on the hospital forecourt.
	var block := _block_centre(HOSPITAL_BLOCK.x, HOSPITAL_BLOCK.y)
	var hospital := _spawn(_root, "Hospital", "res://Game/Incidents/Hospital.tscn")
	if hospital:
		hospital.position = block + Vector3(0.0, 0.0,
			TILE * (CityGrid.block_span_z(HOSPITAL_BLOCK.y) * 0.5 - 1.0))


# --- Kit plumbing ------------------------------------------------------------

## Maps every prefab name in the pack to its scene path, once, so the layout above
## can name pieces without repeating folders.
func _index_prefabs() -> void:
	for dir in PREFAB_DIRS:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn"):
				_index[file.get_basename()] = dir + file


## A prefab's drawable parts, resolved once and reused. Most kit prefabs are a
## MeshInstance3D root with a StaticBody3D child, which is dropped: collision here is
## built in slabs, not per tile. A few add a second mesh for glass.
func _parts(prefab: String) -> Array:
	if _parts_cache.has(prefab):
		return _parts_cache[prefab]
	var parts: Array = []
	if not _index.has(prefab):
		push_warning("no prefab named %s" % prefab)
	else:
		var packed := load(_index[prefab]) as PackedScene
		if packed == null:
			push_warning("not a PackedScene: %s" % _index[prefab])
		else:
			var node := packed.instantiate()
			_collect_parts(node, Transform3D.IDENTITY, parts)
			node.free()
	_parts_cache[prefab] = parts
	return parts


func _collect_parts(node: Node, above: Transform3D, into: Array) -> void:
	var local := above
	var spatial := node as Node3D
	if spatial != null:
		local = above * spatial.transform
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		into.append({
			"mesh": mesh_node.mesh,
			"material": mesh_node.get_surface_override_material(0),
			"local": local,
		})
	for child in node.get_children():
		_collect_parts(child, local, into)


## Queues a prefab for drawing at [param placement]. Nothing is instanced here; the
## transform is filed against the (mesh, material) it needs and drawn in bulk later.
## The body palettes parked cars draw from. The pack paints every vehicle body off
## the shared 01_A atlas -- which is why an unmodified lot is a wall of blue -- and
## the Alts fold the same atlas through different palettes, so swapping the material
## recolours the paintwork and nothing else. "" keeps the shipped colour.
const CAR_PALETTES := [
	"",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_B_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_C_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_02_A_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_03_A_mat.tres",
	"res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_04_A_mat.tres",
]


## [param palette] swaps the 01_A body material for an alt before batching. The
## batch key already includes the material, so each colour gets its own MultiMesh
## and the variety costs a handful of extra draw calls, not one per car.
func _batch(prefab: String, placement: Transform3D, palette := "") -> void:
	for part in _parts(prefab):
		var mesh: Mesh = part["mesh"]
		var material: Material = part["material"]
		if palette != "" and material and "PolygonCity_01_A" in material.resource_path:
			material = load(palette)
		var key: String = "%s|%s" % [mesh.resource_path,
			material.resource_path if material else ""]
		if not _batches.has(key):
			_batches[key] = {"mesh": mesh, "material": material, "transforms": []}
		_batches[key]["transforms"].append(placement * part["local"])


func _flush_batches(parent: Node) -> void:
	var keys := _batches.keys()
	# Sorted so a rebuild of an unchanged layout produces an identical scene file.
	keys.sort()
	var used := {}
	for key in keys:
		var bucket: Dictionary = _batches[key]
		var transforms: Array = bucket["transforms"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = bucket["mesh"]
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])

		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		if bucket["material"] != null:
			node.material_override = bucket["material"]

		# Names have to be unique, and two materials can share a mesh.
		var node_name: String = str(bucket["mesh"].resource_path.get_file().get_basename())
		node_name = node_name.replace("SM_", "")
		used[node_name] = int(used.get(node_name, 0)) + 1
		if used[node_name] > 1:
			node_name += "_%d" % used[node_name]
		_attach(parent, node, node_name)


# --- Geometry helpers --------------------------------------------------------

## Centre of a grid tile, in world space.
func _tile_centre(col: int, row: int) -> Vector3:
	return CityGrid.tile_centre(col, row)


## Centre of a block. Blocks span an even number of tiles, so this lands on a tile
## boundary: block (0,0) is centred at (-40, -40) and the middle block on the origin.
func _block_centre(bx: int, bz: int) -> Vector3:
	return CityGrid.block_centre(bx, bz)


## Places a kit piece so its 5x5 footprint lands on [param centre] whatever the yaw.
## Kit pieces occupy local x[0,5] z[-5,0], so their footprint centre is (2.5, 0, -2.5)
## and the origin has to be pulled back by that, rotated.
func _kit_transform(centre: Vector3, yaw: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(basis, centre - basis * Vector3(TILE * 0.5, 0.0, -TILE * 0.5))


## Yaw that turns a piece's authored +Z face towards [param outward]. Buildings,
## sidewalks and props are all authored that way.
func _yaw(outward: Vector3) -> float:
	return atan2(outward.x, outward.z)


## Yaw that turns a piece's authored **+X** edge towards [param outward]. The road kit
## alone uses that convention, carrying its markings on the +X edge of a tile whose
## street runs along Z.
func _yaw_edge(outward: Vector3) -> float:
	return atan2(-outward.z, outward.x)


## Yaw for a corner piece, which wraps its +Z and -X faces. [param outward] is the
## diagonal it has to cover; the extra eighth-turn is the difference between facing
## that diagonal and straddling the two sides either side of it.
func _corner_yaw(outward: Vector3) -> float:
	return _yaw(outward) + PI * 0.25


## Batches a piece that is not a single grid tile -- a tower, a civic building -- so
## that its measured footprint lands centred on [param centre].
##
## Grid pieces deliberately do *not* come through here. Their alignment has to follow
## the nominal 5x5 tile, not an AABB that includes awnings, stoops and window boxes;
## centring those on their bounds would leave the terrace a few centimetres ragged.
func _place_centred(prefab: String, centre: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var bounds := _footprint(prefab)
	var middle := bounds.position + bounds.size * 0.5
	_batch(prefab, Transform3D(basis, centre - basis * Vector3(middle.x, 0.0, middle.z)))


## Combined bounds of every mesh in a prefab, in its own local space.
func _footprint(prefab: String) -> AABB:
	if _bounds_cache.has(prefab):
		return _bounds_cache[prefab]
	var bounds := AABB()
	var first := true
	for part in _parts(prefab):
		var part_bounds: AABB = (part["local"] as Transform3D) * (part["mesh"] as Mesh).get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	_bounds_cache[prefab] = bounds
	return bounds


func _pick(options: Array) -> String:
	return str(options[_rng.randi() % options.size()])


# --- Scene helpers -----------------------------------------------------------

## Adds [param node] under [param parent] and gives it to the scene root, which is
## what makes PackedScene.pack() keep it.
func _attach(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = _root
	return node


## Instances a scene by path. Returns null (with a warning) rather than crashing if
## the asset is absent.
func _spawn(parent: Node, node_name: String, scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		push_warning("missing scene: %s" % scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("not a PackedScene: %s" % scene_path)
		return null
	var node := packed.instantiate()
	# Explicit, so pack() writes an instance reference instead of inlining the
	# prefab's whole node tree into Playground.tscn.
	node.scene_file_path = scene_path
	return _attach(parent, node, node_name)


## A single non-colliding copy of a prefab's first mesh, for one-off backdrop pieces
## that are not worth a batch.
func _decor(prefab: String, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var parts := _parts(prefab)
	if not parts.is_empty():
		node.mesh = parts[0]["mesh"]
		if parts[0]["material"] != null:
			node.material_override = parts[0]["material"]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attach(_root, node, node_name)
	return node


## Flat unshaded ring used for the destination marker. TorusMesh already lies in the
## XZ plane, so it needs no rotation. Unshaded keeps it a constant readable colour
## regardless of where the sun is.
func _marker_ring(parent: Node, node_name: String, inner: float, outer: float,
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
	_attach(parent, node, node_name)
	return node


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
