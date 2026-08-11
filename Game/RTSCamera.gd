extends Camera3D
class_name RTSCamera

## Overhead strategy camera. Holds a ground [member focus] point and orbits at a
## fixed pitch above it, so panning and rotating never change the viewing angle.
##
## WASD/arrows pan, Q/E rotate, wheel zooms, middle-drag pans, F follows the
## selection. Any manual pan drops the follow.

@export_group("Framing")
## Ground point the camera looks at.
@export var focus := Vector3.ZERO
## Angle below the horizon. Kept under 85 so the look-at up vector stays valid.
@export_range(20.0, 85.0, 1.0) var pitch_degrees := 52.0
@export var start_distance := 34.0

@export_group("Pan")
@export var pan_speed := 26.0
@export var fast_pan_multiplier := 2.2
@export var drag_sensitivity := 0.055
## Focus is clamped to a square this many metres from the origin, so the camera
## cannot be driven off into empty space. Matches the district plus a small margin.
@export var pan_limit := 135.0

@export_group("Zoom")
@export var min_distance := 9.0
@export var max_distance := 170.0
@export var zoom_step := 5.0
@export var zoom_response := 12.0

@export_group("Rotate")
@export var rotate_speed := 1.9

@export_group("Follow")
@export var follow_response := 5.0

var follow_target: Node3D

var _yaw := 0.0
var _distance := 0.0
var _target_distance := 0.0


func _ready() -> void:
	_distance = start_distance
	_target_distance = start_distance
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_distance = clampf(_target_distance - zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_distance = clampf(_target_distance + zoom_step, min_distance, max_distance)

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		# Drag the world under the cursor. Scaled by distance so the grab feels the
		# same whether zoomed in or out.
		var scale := drag_sensitivity * _distance / start_distance
		_pan(-event.relative.x * scale, event.relative.y * scale)


func _process(delta: float) -> void:
	var pan := Input.get_vector("cam_pan_left", "cam_pan_right",
		"cam_pan_forward", "cam_pan_back")
	if pan != Vector2.ZERO:
		var speed := pan_speed * delta * (_distance / start_distance)
		if Input.is_action_pressed("cam_fast"):
			speed *= fast_pan_multiplier
		_pan(pan.x * speed, -pan.y * speed)

	var rotate := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if not is_zero_approx(rotate):
		_yaw -= rotate * rotate_speed * delta

	if follow_target != null and is_instance_valid(follow_target):
		focus = focus.lerp(follow_target.global_position, _damp(follow_response, delta))

	_distance = lerpf(_distance, _target_distance, _damp(zoom_response, delta))
	_clamp_focus()
	_apply_transform()


## Centres on a point and starts following it.
## Where the camera ray through [param fraction] of the viewport (0-1 across and
## down) meets the ground plane, or INF for a ray that never comes down. At this
## camera's fixed downward pitch every ray lands, so INF is a guard, not a case the
## minimap has to draw.
func ground_point(fraction: Vector2) -> Vector3:
	var pixel := fraction * Vector2(get_viewport().get_visible_rect().size)
	var origin := project_ray_origin(pixel)
	var direction := project_ray_normal(pixel)
	if direction.y >= -0.001:
		return Vector3.INF
	return origin + direction * (-origin.y / direction.y)


func follow(target: Node3D) -> void:
	follow_target = target


func stop_following() -> void:
	follow_target = null


## Moves the focus in camera-relative ground space.
func _pan(right_amount: float, forward_amount: float) -> void:
	# Manually driving the view means you no longer want to be dragged along.
	follow_target = null
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	focus += right * right_amount + forward * forward_amount


func _clamp_focus() -> void:
	focus.x = clampf(focus.x, -pan_limit, pan_limit)
	focus.z = clampf(focus.z, -pan_limit, pan_limit)
	focus.y = 0.0


func _apply_transform() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		sin(_yaw) * cos(pitch),
		sin(pitch),
		cos(_yaw) * cos(pitch),
	) * _distance
	global_position = focus + offset
	look_at(focus, Vector3.UP)


## Frame-rate independent smoothing factor for a lerp toward a moving target.
func _damp(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)
