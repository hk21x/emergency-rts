extends SceneTree

## Is the drivable mesh one sheet now, and can a car get home from the shout?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_departure.gd

const STATION := Vector3(-47.5, 0.45, 10.0)
const CASUALTY := Vector3(-25.0, 0.45, -35.0)
const FIRE := Vector3(-25.0, 0.45, 25.0)
const VEHICLE_LAYER := 1

## Every position the black box has recorded the shuffle at.
const RECORDED := [
	Vector2(-23.3, -43.2), Vector2(-25.2, -32.3), Vector2(-19.1, -27.3),
	Vector2(-26.0, -41.0), Vector2(-27.0, -41.0), Vector2(-20.0, -34.0),
	Vector2(-22.0, -39.0),
]

var _parent: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var town := (load("res://Game/Tutorial.tscn") as PackedScene).instantiate()
	root.add_child(town)
	for i in 60:
		await physics_frame
	var region := town.get_node_or_null("VehicleNavigation") as NavigationRegion3D
	var map := region.get_navigation_map()
	var mesh := region.navigation_mesh
	print("vehicle mesh: %d polygons" % mesh.get_polygon_count())

	# Welded by position rather than by index: the bake emits coincident vertices at
	# tile seams, and an index-keyed union would call every tile its own island.
	var count := mesh.get_polygon_count()
	var vertices := mesh.get_vertices()
	_parent.resize(count)
	for i in count:
		_parent[i] = i
	var edges := {}
	for i in count:
		var poly := mesh.get_polygon(i)
		for e in poly.size():
			var a: Vector3 = vertices[poly[e]]
			var b: Vector3 = vertices[poly[(e + 1) % poly.size()]]
			var ka := "%.2f,%.2f,%.2f" % [a.x, a.y, a.z]
			var kb := "%.2f,%.2f,%.2f" % [b.x, b.y, b.z]
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			if edges.has(key):
				_union(i, int(edges[key]))
			else:
				edges[key] = i
	var groups := {}
	for i in count:
		groups[_find(i)] = int(groups.get(_find(i), 0)) + 1
	var sizes: Array = groups.values()
	sizes.sort()
	sizes.reverse()
	print("connected components (by welded edge): %d  sizes %s"
		% [groups.size(), str(sizes.slice(0, 6))])

	print("\n=== the tutorial's own journeys ===")
	_leg(map, "station", STATION, "casualty", CASUALTY)
	_leg(map, "casualty", CASUALTY, "station", STATION)
	_leg(map, "station", STATION, "fire", FIRE)
	_leg(map, "fire", FIRE, "station", STATION)

	print("\n=== home from every spot the black box recorded ===")
	var stranded := 0
	for spot in RECORDED:
		var here := Vector3(spot.x, 0.45, spot.y)
		var path := NavigationServer3D.map_get_path(map, here, STATION, true,
			VEHICLE_LAYER)
		var short := INF
		if not path.is_empty():
			var end := path[path.size() - 1]
			short = Vector2(end.x - STATION.x, end.z - STATION.z).length()
		if short > 2.0:
			stranded += 1
		print("  (%6.1f,%6.1f) -> station: %s"
			% [spot.x, spot.y,
				"no path" if path.is_empty() else "%.1fm short" % short])
	print("  %d of %d still stranded" % [stranded, RECORDED.size()])

	print("\n=== can a car get home from anywhere it can stand? ===")
	var on_mesh := 0
	var cannot := 0
	for x in range(-60, 60, 2):
		for z in range(-60, 40, 2):
			var here := Vector3(float(x), 0.45, float(z))
			var path := NavigationServer3D.map_get_path(map, here, STATION, true,
				VEHICLE_LAYER)
			if path.size() <= 1:
				continue
			var end := path[path.size() - 1]
			# Only count samples that really sit on the mesh: a point out in a garden
			# snaps to the nearest road and would otherwise flatter the result.
			if Vector2(path[0].x - here.x, path[0].z - here.z).length() > 2.0:
				continue
			on_mesh += 1
			if Vector2(end.x - STATION.x, end.z - STATION.z).length() > 2.0:
				cannot += 1
	print("  %d sampled points on the carriageway, %d cannot reach the station"
		% [on_mesh, cannot])

	quit()


func _leg(map: RID, from_name: String, from: Vector3, to_name: String,
		to: Vector3) -> void:
	var path := NavigationServer3D.map_get_path(map, from, to, true, VEHICLE_LAYER)
	if path.is_empty():
		print("  %-9s -> %-9s : NO PATH" % [from_name, to_name])
		return
	var end := path[path.size() - 1]
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	print("  %-9s -> %-9s : %2d points, %5.1fm driven, ends %.1fm short"
		% [from_name, to_name, path.size(), length,
			Vector2(end.x - to.x, end.z - to.z).length()])


func _find(i: int) -> int:
	while _parent[i] != i:
		_parent[i] = _parent[_parent[i]]
		i = _parent[i]
	return i


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		_parent[rb] = ra
