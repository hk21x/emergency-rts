extends SceneTree

## Renders the minimap's base image: a top-down photograph of the district itself.
##
##   godot --path . --script res://Game/build_minimap.gd
##
## **Run this WITH a window, and after build_map.gd.** It renders through a SubViewport,
## and `--headless` is the dummy driver: the capture comes back empty and the image
## saves blank. Same trap as the map's MultiMesh buffers and the unit portraits.
##
## Drawing the street plan from the road colliders was honest but plain -- it showed
## where cars could go and nothing else. A render shows the actual city: which block is
## the hospital, where the forecourts are, that the middle block is a park. It also
## cannot drift from the world, because it *is* the world.
##
## Two things have to be exactly right or the map lies about where things are:
##
## - The camera is **orthogonal**. A perspective shot has parallax -- buildings lean
##   outward from the centre -- so a unit drawn at the edge would sit beside a building
##   it is nowhere near.
## - The camera basis is written out **longhand**, never `look_at`. Looking straight
##   down makes the up vector colinear with the view, so Godot picks an arbitrary roll.
##   That is the same trap that put the entire road kit in at right angles to its
##   streets; here it would silently rotate the whole map under the markers.

const SCENE := "res://Game/Playground.tscn"
const OUT := "res://Game/UI/MinimapBase.png"

## Rendered at four times the panel it is shown in, so the card can grow without the
## image going soft.
const SIZE := 768

## Everything that is not the district. Units, incidents and the crowd move, so baking
## them in would leave ghosts of where they stood when the map was built; the HUD is a
## CanvasLayer and would draw the whole interface into the picture.
const TRANSIENT := ["Units", "Incidents", "Hospital", "Crowd", "Traffic", "Camera",
	"MoveMarker", "RTSController", "Mission", "HUD"]

## Washed out on purpose. This is the background a dozen markers are read against, so
## it has to sit back: full-strength Synty colour competes with every dot on top of it.
const SATURATION := 0.5
const BRIGHTNESS := 1.18
const CONTRAST := 0.88


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("missing %s -- run build_map.gd first" % SCENE)
		quit(1)
		return

	# Stripped before the scene enters the tree, so none of the removed nodes ever runs
	# its _ready. A controller looking for a camera that is no longer there is not a
	# useful error to have to read.
	var scene := packed.instantiate()
	for node_name in TRANSIENT:
		var node := scene.get_node_or_null(NodePath(node_name))
		if node:
			scene.remove_child(node)
			node.queue_free()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(scene)

	_flatten(scene)
	viewport.add_child(_overhead())

	var image := await _capture(viewport)
	if image == null or image.is_empty():
		push_error("empty capture -- is this running headless?")
		quit(1)
		return

	var err := image.save_png(OUT)
	if err != OK:
		push_error("save failed for %s: %d" % [OUT, err])
		quit(1)
		return
	print("done -- %s (%dx%d covering %.0fm)" % [
		OUT, SIZE, SIZE, Minimap.EXTENT * 2.0])
	quit()


## Turns the district's lighting into map lighting.
##
## The scene is lit for a street-level view: a low key light for long dramatic shadows,
## and depth fog for aerial perspective. From 200m up, the fog swallows the city and
## the shadows lie across it in stripes that read as streets that are not there.
func _flatten(scene: Node) -> void:
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		var environment: Environment = world.environment.duplicate(true)
		environment.fog_enabled = false
		environment.adjustment_enabled = true
		environment.adjustment_saturation = SATURATION
		environment.adjustment_brightness = BRIGHTNESS
		environment.adjustment_contrast = CONTRAST
		world.environment = environment

	# Sun almost overhead, and shadows off. What is wanted is the shape of the city,
	# not the time of day.
	var key := scene.get_node_or_null("KeyLight") as DirectionalLight3D
	if key:
		key.rotation = Vector3(deg_to_rad(-78.0), deg_to_rad(-125.0), 0.0)
		key.shadow_enabled = false


## An orthogonal camera looking straight down, framing exactly the span the minimap
## draws into -- so world-to-pixel is the same linear mapping in both, and a marker
## drawn at a road junction lands on that junction.
func _overhead() -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Minimap.EXTENT * 2.0
	camera.near = 1.0
	camera.far = 500.0
	camera.current = true
	# Longhand, not look_at. Columns are the camera's X, Y and Z axes: it views along
	# its own -Z, so putting +Y there aims it at the ground, and putting -Z in the up
	# slot makes world +Z run down the image -- which is the convention Minimap._to_map
	# uses.
	camera.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
		Vector3(0.0, 200.0, 0.0))
	return camera


## The viewport's texture is only valid once the frame that drew it has been presented.
func _capture(viewport: SubViewport) -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	return texture.get_image() if texture else null
