extends Control
class_name Minimap

## Top-down overview of the district. Click or drag it to move the camera.
##
## The base is a real overhead render of the map, produced by `build_minimap.gd` -- so
## the block that looks like a hospital is the hospital, and the picture cannot drift
## from the world because it *is* the world. Markers are drawn on top every frame, read
## from groups, so anything that appears later shows up without registering itself.
##
## With no base image it falls back to drawing the street plan from the road slabs'
## own collision shapes. That is plainer, but it keeps the map working before the
## generator has been run -- and it can still never disagree with where cars can go,
## because it is built from the same bodies the vehicle navigation mesh is baked from.

## Half-width of the world area shown. The district is 130x130, so this leaves a thin
## margin around the outer ring road.
##
## `build_minimap.gd` frames its render on this exact number. Change it and the base
## image has to be re-rendered, or every marker sits at the wrong place on it.
const EXTENT := 132.0
const BASE_IMAGE := "res://Game/UI/MinimapBase.png"

@export var world_extent := EXTENT
@export var camera_path: NodePath

## Defaults come from [Palette], the same table the theme is baked from, so the map and
## the panels around it cannot end up two different greys.
@export_group("Colours")
## Opaque on purpose. The map has to be read at a glance while the street behind it is
## moving, and a translucent one puts a lit shopfront straight through the middle of
## the district.
@export var background := Palette.BLOCKS
@export var street := Palette.STREET
@export var border := Palette.EDGE
@export var selected_colour := Palette.SELECTED
@export var fire_colour := Palette.FIRE_MARKER
@export var casualty_colour := Palette.CASUALTY_MARKER
@export var view_colour := Palette.TEXT

## Group the road slabs join. Matches build_map.gd's ROAD_GROUP.
const ROAD_GROUP := &"road_surface"

var _camera: RTSCamera
## Wired by the HUD, like every other panel. Right-clicking the map orders the
## selection to that spot, exactly as right-clicking the street would.
var controller: RTSController
## The overhead render, or null -- in which case the street plan below is drawn instead.
var _base: Texture2D
## Where the framed world is centred. The district sits on the origin; a guest map
## (the tutorial town, centred near (15, -20)) says where its middle actually is.
var world_centre := Vector3.ZERO
## The street plan in world XZ, collected once. Roads do not move.
var _streets: Array[Rect2] = []


func _ready() -> void:
	# Must swallow clicks: a click meant for the minimap should never also be read as
	# an order out in the world.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_camera = get_node_or_null(camera_path) as RTSCamera
	if _camera == null:
		# The exported path is assigned by build_map.gd -- but this node is a child of
		# the instanced HUD scene, and pack() silently drops property overrides on
		# instance children unless they are owner-flagged. That left the shipped scene
		# with no camera and a minimap that quietly ignored every click. The game has
		# exactly one current 3D camera and it is the RTS one, so fall back to it.
		_camera = get_viewport().get_camera_3d() as RTSCamera
	if ResourceLoader.exists(BASE_IMAGE):
		_base = load(BASE_IMAGE) as Texture2D
	else:
		_collect_streets()


## Drops the baked photograph and draws the schematic street plan instead, framed to
## [param extent] either side of [param centre]. For maps that are not the district
## the photograph shows -- the tutorial town calls this on entry, because a confident
## render of the wrong city is worse than a plain plan of the right one.
##
## **Must be called deferred if called from another node's _ready**: this node's own
## _ready loads the photograph, and readiness order put a first-frame call *before*
## it -- the plan was collected and then silently replaced by the district's photo a
## moment later. Measured, by a player looking at the wrong town.
func use_streets(extent: float, centre := Vector3.ZERO) -> void:
	_base = null
	world_extent = extent
	world_centre = centre
	_streets.clear()
	_collect_streets()


## A guest map's own photograph, framed like [method use_streets] -- the tutorial
## bakes one with build_tutorial_minimap.gd. Falls back to the street plan when the
## photograph has not been baked yet, which is plain but never wrong. The same
## deferral rule as use_streets applies, and for the same measured reason.
func use_photo(path: String, extent: float, centre := Vector3.ZERO) -> void:
	if not ResourceLoader.exists(path):
		use_streets(extent, centre)
		return
	_base = load(path) as Texture2D
	world_extent = extent
	world_centre = centre
	_streets.clear()


## Reads the footprint of every road slab in the map. Doing it from the collision
## shapes rather than a table means the minimap and the vehicle navigation mesh can
## never disagree about where the roads are -- they are built from the same bodies.
func _collect_streets() -> void:
	for node in get_tree().get_nodes_in_group(ROAD_GROUP):
		var body := node as StaticBody3D
		if body == null:
			continue
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider == null:
				continue
			var box := collider.shape as BoxShape3D
			if box == null:
				continue
			var origin := body.global_position + collider.position
			_streets.append(Rect2(
				origin.x - box.size.x * 0.5, origin.z - box.size.z * 0.5,
				box.size.x, box.size.z))


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _camera == null:
		return
	var button := event as InputEventMouseButton
	# Right-click: an order, not a look. The same meaning the same click has out in
	# the world, so the map can be commanded from without ever leaving it.
	if button != null and button.pressed \
			and button.button_index == MOUSE_BUTTON_RIGHT:
		# An order is worth refusing rather than relocating. Clamping is right for the
		# camera below -- drag to the edge and you meant the edge -- but a right-click
		# the pointer was nowhere near the card for is not an order to its border, it is
		# an order the player never gave.
		if not Rect2(Vector2.ZERO, size).has_point(button.position):
			return
		if controller:
			controller.order_at_point(_to_world(button.position), button.shift_pressed)
		accept_event()
		return
	var dragging := event is InputEventMouseMotion \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var clicked := button != null and button.pressed \
		and button.button_index == MOUSE_BUTTON_LEFT
	if clicked or dragging:
		_camera.stop_following()
		_camera.focus = _to_world(event.position)
		accept_event()


## How far the render is taken down. Enough that the chrome wins and the markers still
## read; a wash this side of half hides the street plan the map exists to show.
const WASH := Color(0.031, 0.051, 0.078, 0.42)


func _draw() -> void:
	if _base:
		# Stretched to the panel. The render covers exactly world_extent either side of
		# the origin, which is the same span _to_map projects into, so the two agree
		# whatever size the card is given.
		draw_texture_rect(_base, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), background, true)
		for road in _streets:
			var corner := _to_map(Vector3(road.position.x, 0.0, road.position.y))
			var far := _to_map(Vector3(road.end.x, 0.0, road.end.y))
			draw_rect(Rect2(corner, far - corner), street, true)

	# **A wash over the render, under everything the map is for.** The baked photograph
	# is a daylit city and reads far brighter than the chrome around it -- bright enough
	# that the card pulls the eye away from the street it is meant to support. Drawn
	# here rather than as a `modulate` on the node, because modulate would take the
	# units and the call markers down with it, and those have to stay legible: the wash
	# is the *ground* going quiet, not the map going dim.
	draw_rect(Rect2(Vector2.ZERO, size), WASH, true)

	# Units first, incidents over them: a casualty lying under an ambulance is the one
	# thing on this map you must not lose sight of.
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		# Ambient traffic and the crowd carry no service, so the map shows the shift
		# rather than the whole city's worth of moving dots.
		if unit == null or unit.service == Unit.Service.NONE or not unit.is_selectable():
			continue
		var point := _to_map(unit.global_position)
		var shades := Palette.service(unit.service)
		var radius := 4.5 if unit is Vehicle else 3.5
		# Always the solid shade, never the pale one the roster uses for a unit standing
		# by. The roster draws 38px avatars on white; this draws 4px dots on a pale
		# street, and a pale dot on a pale ground is not a dot.
		draw_circle(point, radius + 1.5, Palette.CARD)
		draw_circle(point, radius, shades[0])
		if unit.is_selected:
			draw_arc(point, radius + 2.5, 0.0, TAU, 20, Palette.TEXT, 1.5, true)

	# One marker per call, not per incident: a fire that has spread into six bodies is
	# still one place the player has to get to.
	for node in get_tree().get_nodes_in_group(Call.GROUP):
		var call := node as Call
		if call == null or not call.is_open():
			continue
		var at := _to_map(call.position)
		# A white collar, so a marker stays legible over a unit or a pale street.
		draw_circle(at, 5.5, Palette.CARD)
		draw_circle(at, 4.0, CallMark.shades(call.kind)[0])

	# The view itself: the camera frustum's footprint on the ground, as a quad. A
	# trapezoid rather than a square, because the camera is tilted -- the far edge of
	# what you see is wider than the near one.
	var footprint := view_footprint()
	if footprint.size() == 4:
		var quad := PackedVector2Array()
		for world in footprint:
			quad.append(_to_map(world))
		quad.append(quad[0])
		draw_polyline(quad, view_colour, 1.5, true)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.0)


## How far the drawn view footprint may reach, as a multiple of the camera distance.
## The honest frustum is enormous: a tilted camera's top-of-screen rays land the
## better part of 100m away, which turned the marker into half the map. The near edge
## and the sides are exact; only the far sweep -- the ground rolling away towards the
## skyline, which nobody reads the minimap for -- is trimmed to keep the shape a
## marker rather than a region.
const VIEW_REACH := 1.5


## The camera frustum's ground footprint as four world points -- near-left, near-right,
## far-right, far-left -- with the far corners capped at VIEW_REACH. Empty when there
## is no camera. Split out from _draw so a test can hold the shape itself.
func view_footprint() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _camera == null:
		return points
	var eye := _camera.global_position
	var eye_ground := Vector3(eye.x, 0.0, eye.z)
	var reach: float = (eye - _camera.focus).length() * VIEW_REACH
	for corner in [Vector2(0.0, 1.0), Vector2(1.0, 1.0),
			Vector2(1.0, 0.0), Vector2(0.0, 0.0)]:
		var world := _camera.ground_point(corner)
		if world == Vector3.INF:
			return []
		var offset := world - eye_ground
		if offset.length() > reach:
			world = eye_ground + offset.normalized() * reach
		points.append(world)
	return points


## World XZ to minimap pixels. +Z maps downward, so -Z (Godot's forward) is up.
func _to_map(world: Vector3) -> Vector2:
	return Vector2(
		(world.x - world_centre.x + world_extent) / (world_extent * 2.0) * size.x,
		(world.z - world_centre.z + world_extent) / (world_extent * 2.0) * size.y)


## The world point a place on the card stands for.
##
## **Clamped to the card**, because a position handed to this is not guaranteed to be
## inside it: `_gui_input` keeps delivering events to a control while the pointer is
## being dragged, wherever the pointer has got to. Unclamped, one of those turns into a
## world point outside the district -- a right-click read as 384px down a 190px card
## produced a destination at **z = 402 on a 260m map**, the navigation agent clamped that
## unreachable target to the nearest point it could path to, and the car set off the
## wrong way and toured the perimeter. The click was on the map either way; the only
## question was which edge of it.
func _to_world(point: Vector2) -> Vector3:
	var inside := Vector2(clampf(point.x, 0.0, size.x), clampf(point.y, 0.0, size.y))
	# Clamped to the **district**, not to the card. The card frames a little more than
	# the city -- [constant EXTENT] is 132 against a 130m half-width -- so even its own
	# corners stand for ground a unit cannot be sent to.
	var edge := CityGrid.MAP_HALF
	return Vector3(
		clampf(inside.x / size.x * world_extent * 2.0 - world_extent
			+ world_centre.x, -edge, edge),
		0.0,
		clampf(inside.y / size.y * world_extent * 2.0 - world_extent
			+ world_centre.z, -edge, edge))
