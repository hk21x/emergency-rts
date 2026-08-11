extends Node3D
class_name NavDebug

## Draws what each player vehicle thinks it is doing, on **F4**.
##
## Built for one complaint that no amount of logging has settled: cars that answer a
## right-click by swinging a full circle instead of steering left and then right. That
## fault is a *disagreement between three things*, and a log can only ever show one of
## them at a time -- the lane route [MoveOrder] plotted over the street grid, the polyline
## the navigation agent solved inside it, and the single point the steering is actually
## aimed at this frame. Seen together the answer is usually obvious in a second: a first
## waypoint behind the car, an agent path that doubles back, or a reverse latch that has
## engaged when nothing needed reversing.
##
## Godot's own `--debug-navigation` draws the baked mesh and is worth having on at the
## same time; it answers "where may a car go", which is the one question this does not.
##
## Drawn with a single [ImmediateMesh] rebuilt each frame rather than a pool of nodes. At
## a handful of vehicles that is cheaper than keeping the nodes in step with orders that
## change every few seconds, and it cannot leave a stale line behind -- which matters,
## because a stale line here is a false diagnosis.
##
## A passive watcher, like [Mission] and [StuckLog]: it finds the vehicles rather than
## being handed them, and nothing else knows it exists.

## The lane route the order plotted, junction to junction.
const ROUTE_COLOUR := Color(0.25, 0.85, 1.0)
## Waypoints already cleared. Dim, and joined to nothing: they are history, and drawing
## them as part of the route is what made a car look steered at a point behind itself.
const PASSED_COLOUR := Color(0.35, 0.45, 0.5)
## The polyline the navigation agent solved.
const AGENT_COLOUR := Color(1.0, 0.85, 0.2)
## Where the steering is pointed this frame.
const AIM_COLOUR := Color(0.3, 1.0, 0.4)
## The same, while the car is reversing or running its escape -- the states in which a
## car is *deliberately* not driving at its aim point, and so the ones worth telling
## apart at a glance from a car that has simply lost the plot.
const REVERSING_COLOUR := Color(1.0, 0.35, 0.35)
## The final destination.
const TARGET_COLOUR := Color(1.0, 1.0, 1.0)

## How tall the vertical sticks are. Drawn well above roof height so they read against
## the district from the RTS camera rather than disappearing into the car.
const STICK := 6.0
## Lines are lifted this far off the road so they do not z-fight with it.
const LIFT := 0.35

var showing := false
var _mesh: ImmediateMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	var view := MeshInstance3D.new()
	view.name = "Lines"
	view.mesh = _mesh
	# Never culled: the lines are rebuilt from world positions every frame, so the AABB
	# Godot infers from the last build is wrong the moment a car moves, and a debug
	# overlay that vanishes when you pan is worse than none.
	view.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	# Through walls and buildings. The interesting case is a car on the far side of a
	# block from the camera, which is exactly when an occluded overlay is no use.
	_material.no_depth_test = true
	_material.disable_receive_shadows = true
	view.material_override = _material
	add_child(view)
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_F4:
		return
	showing = not showing
	visible = showing
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not showing:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew := false
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		# Player vehicles only. Ambient traffic drives on its own rails and has none of
		# the machinery this exists to show, so drawing it would be forty lines of noise
		# around the two that matter.
		if vehicle == null or vehicle.service == Unit.Service.NONE:
			continue
		if not vehicle.is_navigating():
			continue
		_draw_vehicle(vehicle)
		drew = true
	# An empty surface is not allowed; give it a degenerate line rather than branching
	# every caller on whether anything was found.
	if not drew:
		_line(Vector3.ZERO, Vector3.ZERO, TARGET_COLOUR)
	_mesh.surface_end()
	_mesh.surface_set_material(0, _material)


func _draw_vehicle(vehicle: Vehicle) -> void:
	var from := vehicle.global_position

	# 1. The lane route, if the order plotted one. Read off the order rather than
	#    recomputed: a route recomputed here would be a *different* route from the one
	#    the car is following, and the whole point is to see what it actually has.
	var order := vehicle.current_order()
	if order != null:
		var route: Variant = order.get("_route")
		var at: Variant = order.get("_at")
		if route is Array and (route as Array).size() > 0:
			var points := route as Array
			var reached := int(at) if at != null else 0
			# **Only the part of the route still to be driven is joined to the car.** The
			# first version chained every waypoint from the car's current position, so a
			# waypoint already cleared still had a line running *backwards* out of the
			# bonnet -- which reads exactly like a car being steered at a point behind
			# itself, and was mistaken for one from a screenshot. Cleared waypoints are
			# still drawn, because where the car has been is useful, but as bare rings in
			# a dim colour with nothing joining them to it.
			var previous := from
			for i in points.size():
				var point: Vector3 = points[i]
				if i < reached:
					_ring(point, 0.7, PASSED_COLOUR)
					continue
				_line(previous, point, ROUTE_COLOUR)
				_ring(point, 1.6 if i == reached else 1.0,
					AIM_COLOUR if i == reached else ROUTE_COLOUR)
				previous = point

	# 2. The agent's solved polyline, which is what actually steers the car between
	#    waypoints. Where this disagrees with the route above is where a car goes round
	#    the houses.
	var agent := vehicle.get_node_or_null("NavigationAgent") as NavigationAgent3D
	if agent:
		var path := agent.get_current_navigation_path()
		for i in range(1, path.size()):
			_line(path[i - 1], path[i], AGENT_COLOUR)

	# 3. The single point the steering is pointed at this frame, and the destination.
	#    Red while reversing or escaping, because a car backing out of trouble is *meant*
	#    to be driving away from its aim and should not be read as a car that is lost.
	var backing: bool = vehicle.is_turning_round() or vehicle.get("_escape_time") > 0.0
	var aim_colour := REVERSING_COLOUR if backing else AIM_COLOUR
	if agent:
		var steer: Vector3 = agent.get_next_path_position()
		_line(from, steer, aim_colour)
		_stick(steer, STICK * 0.5, aim_colour)
	_stick(vehicle.move_target, STICK, TARGET_COLOUR)
	# The car's own heading, so a nose pointing the wrong way is visible without having
	# to judge it from the model at RTS distance.
	_line(from, from - vehicle.global_basis.z * 4.0, aim_colour)


func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(a + Vector3.UP * LIFT)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(b + Vector3.UP * LIFT)


func _stick(at: Vector3, height: float, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(at + Vector3.UP * LIFT)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(at + Vector3.UP * height)


## A flat ring on the ground, drawn as a fan of chords. Eight segments is plenty at the
## distance these are read from and keeps the per-frame vertex count small.
func _ring(at: Vector3, radius: float, colour: Color) -> void:
	var steps := 8
	for i in steps:
		var a := TAU * float(i) / steps
		var b := TAU * float(i + 1) / steps
		_line(at + Vector3(cos(a), 0.0, sin(a)) * radius,
			at + Vector3(cos(b), 0.0, sin(b)) * radius, colour)
