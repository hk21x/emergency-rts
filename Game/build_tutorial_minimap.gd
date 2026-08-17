extends Node

## Renders the tutorial minimap's base image: a top-down photograph of the town.
##
##   TUTORIAL_MINIMAP_BAKE=1 godot --path . res://Game/Tutorial.tscn
##
## **Not a --script tool, deliberately.** The first cut was a SceneTree script in
## build_minimap.gd's mould, and instantiating this scene during a windowed script's
## startup aborts inside the engine allocator -- macOS crash report in hand, a native
## double-free in a run-loop observer, three runs out of three. The same scene boots
## flawlessly through the normal game path every day, so the bake rides that instead:
## TutorialSetup spawns this node when the environment variable is set, the town
## settles for thirty frames, an orthogonal camera photographs it through a
## SubViewport sharing the live world, and the process quits.
##
## Run WITH a window (headless captures come back empty) and after build_tutorial.gd.
## Then `godot --headless --path . --import` alone, so the fresh PNG is importable.

const OUT := "res://Game/UI/TutorialMinimapBase.png"
const SIZE := 768

## The district minimap's wash, verbatim: this is a background for markers.
const SATURATION := 0.5
const BRIGHTNESS := 1.18
const CONTRAST := 0.88


func _ready() -> void:
	_bake.call_deferred()


func _bake() -> void:
	# Let the boot finish properly -- shaders compiled, vendor prop removal and the
	# layer stamp done, the title card up. The whole point of riding the game boot.
	for i in 30:
		await get_tree().process_frame

	# The clouds float at rooftop height and photograph as white blobs over the
	# streets. Play keeps them; the photograph must not.
	var map := get_node_or_null("../../Map")
	if map:
		for cloud in map.find_children("SM_Generic_Cloud*", "", true, false):
			(cloud as Node3D).visible = false

	# Map lighting, the district recipe: fog off, washed grading, sun near-overhead
	# with shadows off. Nothing is restored -- the process quits after the shot.
	var world := get_node_or_null("../../WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		var environment: Environment = world.environment.duplicate(true)
		environment.fog_enabled = false
		environment.adjustment_enabled = true
		environment.adjustment_saturation = SATURATION
		environment.adjustment_brightness = BRIGHTNESS
		environment.adjustment_contrast = CONTRAST
		world.environment = environment
	var key := get_node_or_null("../../KeyLight") as DirectionalLight3D
	if key:
		key.rotation = Vector3(deg_to_rad(-78.0), deg_to_rad(-125.0), 0.0)
		key.shadow_enabled = false

	# A SubViewport with no world of its own photographs the live one. The HUD is a
	# CanvasLayer on the root viewport, so it never reaches this render.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = TutorialMap.MINIMAP_EXTENT * 2.0
	camera.near = 1.0
	camera.far = 500.0
	# Longhand basis, never look_at: straight down makes the up vector colinear and
	# the roll arbitrary -- the trap that once rotated a whole road kit.
	camera.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
		TutorialMap.MINIMAP_CENTRE + Vector3(0.0, 200.0, 0.0))
	viewport.add_child(camera)
	camera.current = true

	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	var image := texture.get_image() if texture else null
	if image == null or image.is_empty():
		push_error("empty capture -- is this running headless?")
		get_tree().quit(1)
		return
	var err := image.save_png(OUT)
	if err != OK:
		push_error("save failed for %s: %d" % [OUT, err])
		get_tree().quit(1)
		return
	print("done -- %s (%dx%d covering %.0fm about %s)" % [
		OUT, SIZE, SIZE, TutorialMap.MINIMAP_EXTENT * 2.0,
		TutorialMap.MINIMAP_CENTRE])
	get_tree().quit()
