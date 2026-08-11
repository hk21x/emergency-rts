extends Node3D

## Animation viewer: plays a clip on the retargeted character so the body movement
## can be inspected up close.
##
## Run it directly:
##   godot --path . res://Game/AnimationViewer.tscn
##
## Clips play in place -- the in-place library is the one units will use, since code
## owns their position. Use the _RM library if you want the animation to travel.

## Clip to open on. Falls back to the first clip if it is missing.
@export var start_clip := "Walk"

@export_group("Camera")
@export var focus_height := 1.0
@export var start_distance := 3.3
@export var min_distance := 1.4
@export var max_distance := 12.0
@export var orbit_sensitivity := 0.007
@export var zoom_step := 0.4

@onready var _player: AnimationPlayer = $Character/AnimationPlayer
@onready var _camera: Camera3D = $Camera
@onready var _clip_label: Label = $UI/Clip
@onready var _time_label: Label = $UI/Time

var _clips: PackedStringArray
var _index := 0
var _yaw := 0.35
var _pitch := 0.15
var _distance := 0.0


func _ready() -> void:
	_distance = start_distance

	_clips = _player.get_animation_list()
	_clips.sort()
	if _clips.is_empty():
		_clip_label.text = "no clips on the character"
		return

	_index = maxi(_clips.find(start_clip), 0)
	_play_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_RIGHT, KEY_D:
				_step_clip(1)
			KEY_LEFT, KEY_A:
				_step_clip(-1)
			KEY_SPACE:
				_player.speed_scale = 0.0 if _player.speed_scale > 0.0 else 1.0
			KEY_UP:
				_player.speed_scale = minf(_player.speed_scale + 0.25, 2.0)
			KEY_DOWN:
				_player.speed_scale = maxf(_player.speed_scale - 0.25, 0.0)
			KEY_R:
				_play_current()
			KEY_ESCAPE:
				get_tree().quit()

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + zoom_step, min_distance, max_distance)

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch + event.relative.y * orbit_sensitivity,
			deg_to_rad(-20.0), deg_to_rad(70.0))


func _process(_delta: float) -> void:
	var focus := Vector3(0.0, focus_height, 0.0)
	_camera.global_position = focus + Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch),
	) * _distance
	_camera.look_at(focus, Vector3.UP)

	if _clips.is_empty():
		return
	var clip := _clips[_index]
	var animation := _player.get_animation(clip)
	_time_label.text = "%.2f / %.2fs      speed %.2fx%s" % [
		_player.current_animation_position, animation.length, _player.speed_scale,
		"      PAUSED" if is_zero_approx(_player.speed_scale) else "",
	]


func _step_clip(direction: int) -> void:
	if _clips.is_empty():
		return
	_index = wrapi(_index + direction, 0, _clips.size())
	_play_current()


func _play_current() -> void:
	var clip := _clips[_index]
	var animation := _player.get_animation(clip)
	# Most one-shots read better looped here; this is an inspection tool, not gameplay.
	animation.loop_mode = Animation.LOOP_LINEAR
	_player.speed_scale = 1.0
	_player.play(clip)
	_clip_label.text = "%s        (%d / %d)" % [clip, _index + 1, _clips.size()]
