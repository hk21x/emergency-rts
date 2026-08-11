extends SceneTree

## Dev utility: renders the playground and writes PNGs so the visuals can be checked
## without sitting in the editor. Must run WITH a window (no --headless):
##
##   godot --path . --script res://Game/screenshot.gd
##
## Pass any scene after `--` to just render that instead, e.g. the pack's own
## Scenes/Demo.tscn. Output goes to user:// -- the path is printed on exit.

const SCENE := "res://Game/Playground.tscn"
const OUT_DIR := "user://shots/"

var _car: Vehicle
var _camera: RTSCamera
var _controller: RTSController


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var extra := OS.get_cmdline_user_args()
	if extra.size() > 0:
		await _render_only(extra[0])
		return

	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_car = scene.get_node("Units/Police1")
	_camera = scene.get_node("Camera")
	_controller = scene.get_node("RTSController")
	# The map ships quiet now, so the incident shot spawns its own fire where the
	# scripted shout used to be.
	var fire: Node3D = (load("res://Game/Incidents/Fire.tscn") as PackedScene).instantiate()
	scene.get_node("Incidents").add_child(fire)
	fire.global_position = Vector3(20.0, 0.0, 2.0)

	# The whole district from above.
	_camera.focus = Vector3.ZERO
	_camera._target_distance = 125.0
	await _wait(90)
	await _shot("01_overview")

	# Back down to the station the shift starts at.
	_camera.focus = Vector3(_car.global_position.x, 0.0, _car.global_position.z)
	_camera._target_distance = 34.0
	await _wait(60)
	await _shot("01a_station")

	# Close on the incident: fire particles, minimap and the objectives panel.
	_camera.focus = Vector3(fire.global_position.x, 0.0, fire.global_position.z)
	_camera._target_distance = 17.0
	await _wait(120)
	await _shot("01b_incident")

	_camera.focus = Vector3(_car.global_position.x, 0.0, _car.global_position.z)
	_camera._target_distance = 34.0
	await _wait(40)

	# Real clicks, so the shots show what a player actually triggers.
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	await _wait(30)
	await _shot("02_selected")

	# Box-select the whole flotilla to show multi-selection and the command bar.
	var units := scene.get_node("Units").get_children()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for unit in units:
		var point: Vector2 = _screen_of(unit.global_position)
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	await _drag(low - Vector2(90, 90), high + Vector2(90, 90))
	await _wait(20)
	await _shot("02b_multi_select")

	# An officer on their own: the command bar should offer Move / Board / Stop.
	var officer: Person = scene.get_node("Units/Officer1")
	_camera.focus = Vector3(officer.global_position.x, 0.0, officer.global_position.z)
	_camera._target_distance = 16.0
	await _wait(40)
	await _click(MOUSE_BUTTON_LEFT, _screen_of(officer.global_position + Vector3.UP * 1.0))
	await _wait(20)
	await _shot("02c_officer")

	# Send them to the nearest car; Board outranks Move, so they climb in.
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(_car.global_position + Vector3.UP * 0.8))
	await _wait(90)
	await _shot("02d_boarding")

	# Back onto the car -- the officer shots left the camera 16m up and framed on
	# them, which is not somewhere the car is necessarily even on screen.
	_controller.clear_selection()
	_camera.focus = Vector3(_car.global_position.x, 0.0, _car.global_position.z)
	_camera._target_distance = 40.0
	await _wait(50)

	# Select the patrol car and send it out of the forecourt to the junction north
	# east of the station -- a point on the street, since that is the only place the
	# vehicle navigation mesh goes.
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	await _wait(20)
	var destination := Vector3(-20.0, 0.0, 20.0)
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(destination))
	await _wait(20)
	await _shot("03_order_given")

	_camera.follow(_car)
	await _wait(70)
	await _shot("04_en_route")

	await _wait(240)
	await _shot("05_arrived")

	_camera.stop_following()
	_camera._target_distance = 70.0
	await _wait(90)
	await _shot("06_zoomed_out")

	print("shots written to ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## Loads a scene as-is, using whatever camera it ships with.
func _render_only(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("no such scene: %s" % path)
		quit(1)
		return
	root.add_child((load(path) as PackedScene).instantiate())
	await _wait(90)
	await _shot(path.get_file().get_basename())
	print("shots written to ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


func _screen_of(world_position: Vector3) -> Vector2:
	return _camera.unproject_position(world_position)


func _drag(from: Vector2, to: Vector2) -> void:
	for step in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = step
		event.position = from if step else to
		event.global_position = event.position
		root.push_input(event)
		if step:
			var motion := InputEventMouseMotion.new()
			motion.position = to
			motion.global_position = to
			motion.relative = to - from
			root.push_input(motion)
		await _wait(4)


func _click(button: int, screen_position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = screen_position
		event.global_position = screen_position
		root.push_input(event)
		await _wait(2)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OUT_DIR + shot_name + ".png")
	print("  captured ", shot_name)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
