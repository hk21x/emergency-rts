extends Camera3D
class_name ChaseCamera

## Follow camera for exploring the map.
##
## Deliberately not a child of the car -- it chases in world space so it can lag,
## swing wide through corners and pull back with speed. Hold right mouse to look
## around, scroll to zoom, [b]V[/b] to cycle Chase / Orbit / Top-down.

enum Mode { CHASE, ORBIT, TOP_DOWN }

## The car to follow. NodePath rather than a Node3D export so the reference
## survives being written out by Game/build_map.gd.
@export var target_path: NodePath

@export_group("Chase")
@export var distance := 9.0
@export var height := 4.0
@export var look_height := 1.2
## Higher follows more rigidly; lower lets the camera trail behind.
@export var follow_speed := 5.0
@export var aim_speed := 9.0
## Extra distance at top speed, so acceleration reads on screen.
@export var speed_pullback := 2.5
@export var base_fov := 70.0
@export var speed_fov_kick := 12.0

@export_group("Orbit")
@export var orbit_sensitivity := 0.005
@export var min_pitch_degrees := -15.0
@export var max_pitch_degrees := 75.0

@export_group("Zoom")
@export var min_distance := 4.0
@export var max_distance := 30.0
@export var zoom_step := 1.5

@export_group("Top-down")
@export var top_down_height := 34.0

var mode: Mode = Mode.CHASE
var target: Node3D

var _orbit_yaw := 0.0
var _orbit_pitch := 0.35
var _distance := 0.0
var _focus := Vector3.ZERO


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	_distance = distance
	fov = base_fov
	if target:
		_focus = _focus_point()
		global_position = _focus + Vector3(0.0, height, distance)
		look_at(_focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_cycle"):
		mode = ((mode + 1) % Mode.size()) as Mode
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + zoom_step, min_distance, max_distance)

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if mode != Mode.ORBIT:
			mode = Mode.ORBIT
			# Start the orbit from wherever the chase camera currently sits, so
			# grabbing the mouse never snaps the view.
			var offset := global_position - _focus_point()
			_orbit_yaw = atan2(offset.x, offset.z)
			_orbit_pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
		_orbit_yaw -= event.relative.x * orbit_sensitivity
		_orbit_pitch = clampf(
			_orbit_pitch + event.relative.y * orbit_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees),
		)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	_focus = _focus.lerp(_focus_point(), _damp(aim_speed, delta))
	var speed_ratio := _speed_ratio()

	match mode:
		Mode.CHASE:
			_update_chase(speed_ratio, delta)
		Mode.ORBIT:
			_update_orbit(delta)
		Mode.TOP_DOWN:
			_update_top_down(delta)

	fov = lerpf(fov, base_fov + speed_fov_kick * speed_ratio, _damp(4.0, delta))


func _update_chase(speed_ratio: float, delta: float) -> void:
	var flat_forward := -target.global_basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.0001:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()

	var back := _distance + speed_pullback * speed_ratio
	var desired := _focus - flat_forward * back + Vector3.UP * height
	global_position = global_position.lerp(desired, _damp(follow_speed, delta))
	_look_at_focus(delta)


func _update_orbit(delta: float) -> void:
	var offset := Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch),
	) * _distance
	global_position = global_position.lerp(_focus + offset, _damp(12.0, delta))
	_look_at_focus(delta)


func _update_top_down(delta: float) -> void:
	var desired := _focus + Vector3.UP * top_down_height
	global_position = global_position.lerp(desired, _damp(follow_speed, delta))
	# Straight down, so the usual world up is degenerate -- aim "up" at world north.
	var wanted := Transform3D(global_transform.basis, global_position) \
		.looking_at(_focus, Vector3.FORWARD)
	global_basis = global_basis.slerp(wanted.basis, _damp(aim_speed, delta)).orthonormalized()


func _look_at_focus(delta: float) -> void:
	var aim := _focus + Vector3.UP * look_height
	if global_position.distance_squared_to(aim) < 0.0001:
		return
	var wanted := Transform3D(global_transform.basis, global_position).looking_at(aim, Vector3.UP)
	global_basis = global_basis.slerp(wanted.basis, _damp(aim_speed, delta)).orthonormalized()


func _focus_point() -> Vector3:
	return target.global_position if target else Vector3.ZERO


func _speed_ratio() -> float:
	var car := target as Vehicle
	if car == null:
		return 0.0
	return clampf(absf(car.forward_speed) / maxf(car.max_speed, 0.001), 0.0, 1.0)


## Frame-rate independent smoothing factor for a lerp toward a moving target.
func _damp(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)
