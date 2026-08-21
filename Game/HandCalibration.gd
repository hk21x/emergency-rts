extends Node3D
class_name HandCalibration

## Dial in where a prop sits in a character's hand, and print the row to paste back.
##
## Run it directly, **with a window** -- this is the one tool in the project that cannot
## be run headless, because the whole job is looking:
## [codeblock]
##   godot --path . res://Game/HandCalibration.tscn
## [/codeblock]
##
## **Why this exists rather than a screenshot.** A held prop has to look right across the
## clips the unit actually plays, not in one pose: [HeldItem] places it off the hand
## bone's full basis, so the wrist turns it, and a correction that reads perfectly in the
## idle will swing wrong the moment somebody walks. A contact sheet would let you fix the
## idle and ship the walk broken. So this scrubs the animation *while* you nudge, which is
## the only arrangement that can settle it.
##
## The loop is: pick a prop, pick a character, run the clip it will really be seen in,
## nudge until it looks held, press P, paste the printed row into [constant
## HeldItem.OFFSETS]. Nothing here writes to the project -- it prints, and you paste.
##
## No `user://` writes of any kind, deliberately: this scene never touches [Station], so
## it cannot be the probe that overwrites a career. See CLAUDE.md on that.
##
## It carries a `class_name` -- unusual for a standalone viewer -- so the suite can sweep
## [constant BODIES] for the hand bone this whole tool assumes. A rig that retargets
## without a `RightHand` shows here as a prop floating beside a character, and in the game
## as a weapon that never appears; the check reads the same list the tool offers rather
## than a second copy that could drift from it.

## The props that get held. Anything in [constant HeldItem.OFFSETS] plus anything a scene
## sets on `weapon_scene`, listed here because a calibration tool should show you every
## prop, including the ones nobody has corrected yet.
const PROPS: Array[String] = [
	"res://Assets/Synty/PolygonHeist/Prefab/Weapons/SM_Wep_PistolSwat_01.tscn",
	"res://Assets/Synty/PolygonHeist/Prefab/Weapons/SM_Wep_PistolBandit_01.tscn",
]

## The bodies that hold them. The armed officer and a plain officer first, since those are
## the two the sidearm is actually seen on; the rest are here because a rig that retargets
## differently would show up as a prop that fits one body and not another.
const BODIES: Array[String] = [
	"res://Game/Characters/ArmedOfficer.tscn",
	"res://Game/Characters/PoliceOfficer.tscn",
	"res://Game/Characters/Male_Jacket.tscn",
	"res://Game/Characters/Female_Jacket.tscn",
	"res://Game/Characters/Firefighter.tscn",
	"res://Game/Characters/Paramedic.tscn",
]

## How far one press moves things. Coarse by default with a fine modifier on Shift,
## because the first pass is centimetres and the last is millimetres.
const STEP := 0.01
const FINE_STEP := 0.002
const TURN := 5.0
const FINE_TURN := 1.0
const SCALE_STEP := 0.05

@export_group("Camera")
## Framed on the hand rather than on the body: the hand is the subject, and a camera set
## up for the whole character puts the thing being judged in about forty pixels.
@export var start_distance := 0.55
@export var min_distance := 0.12
@export var max_distance := 4.0
@export var orbit_sensitivity := 0.007
@export var zoom_step := 0.06

@onready var _camera: Camera3D = $Camera
@onready var _head: Label = $UI/Head
@onready var _numbers: Label = $UI/Numbers
@onready var _keys: Label = $UI/Keys

var _body: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _prop: Node3D

var _body_index := 0
var _prop_index := 0
var _clips: PackedStringArray
var _clip_index := 0

## The live correction, in the same units [constant HeldItem.OFFSETS] is authored in.
var _pos := Vector3.ZERO
var _rot := Vector3.ZERO
var _scale := 1.0

var _yaw := 0.6
var _pitch := 0.25
var _distance := 0.0
## Follow the hand, or hold the camera still and let the hand move through the frame.
## Following is right for judging grip; still is right for judging swing.
var _follow := true
var _anchor := Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	_distance = start_distance
	_keys.text = "\n".join([
		"[ ]  prop        - =  character        , .  clip        Space  pause",
		"WASD / QE  move        arrows + RF  turn        Z X  scale",
		"Shift  fine        0  reset        F  follow hand        P  print row",
		"drag  orbit        wheel  zoom        Esc  quit",
	])
	_load_body()


# --- Loading ------------------------------------------------------------------

func _load_body() -> void:
	if _body:
		_body.queue_free()
		_body = null
	_prop = null
	var packed := load(BODIES[_body_index]) as PackedScene
	if packed == null:
		_head.text = "missing body scene: %s" % BODIES[_body_index]
		return
	_body = packed.instantiate() as Node3D
	if _body == null:
		return
	add_child(_body)
	# **The character scene, not a unit.** These are the rigs `build_character.gd` writes;
	# instancing a Person here would drag in orders, navigation and a Station lookup, none
	# of which has anything to do with where a pistol sits.
	_player = _body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _player == null:
		for node in _body.find_children("*", "AnimationPlayer", true, false):
			_player = node as AnimationPlayer
			break
	_skeleton = _body.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if _skeleton == null:
		for node in _body.find_children("*", "Skeleton3D", true, false):
			_skeleton = node as Skeleton3D
			break

	_clips = _player.get_animation_list() if _player else PackedStringArray()
	_clips.sort()
	_clip_index = maxi(_clips.find("Idle"), 0)
	_play_clip()
	_load_prop()


func _load_prop() -> void:
	if _prop:
		_prop.queue_free()
		_prop = null
	var path := PROPS[_prop_index]
	var packed := load(path) as PackedScene
	if packed == null:
		_head.text = "missing prop scene: %s" % path
		return
	_prop = packed.instantiate() as Node3D
	if _prop == null:
		return
	Unit.strip_collision(_prop)
	add_child(_prop)
	# Open on whatever is already in the table, so the tool always shows you the state
	# that ships rather than a blank slate you have to re-derive.
	var fix := HeldItem.offset_for(path)
	_pos = fix.get("pos", Vector3.ZERO)
	_rot = fix.get("rot", Vector3.ZERO)
	_scale = float(fix.get("scale", 1.0))


func _play_clip() -> void:
	if _player == null or _clips.is_empty():
		return
	var clip := _clips[_clip_index]
	var animation := _player.get_animation(clip)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	_player.speed_scale = 1.0
	_player.play(clip)


# --- The loop -----------------------------------------------------------------

func _process(_delta: float) -> void:
	_place_prop()
	_move_camera()
	_write_labels()


## The same call the game makes, with the live numbers standing in for the table -- so
## what you are looking at is what will ship, not an approximation of it.
func _place_prop() -> void:
	if _prop == null or _skeleton == null:
		return
	var bone := _skeleton.find_bone(HeldItem.HAND_BONE)
	if bone < 0:
		_head.text = "%s has no %s bone" % [
			BODIES[_body_index].get_file(), HeldItem.HAND_BONE]
		return
	# **Through `HeldItem.place`, not a copy of it.** This composed the transform itself
	# for one revision, which is the same duplication [HeldItem] exists to have ended --
	# and the worst place to have it, because a calibration tool that composes differently
	# from the game shows you numbers that are wrong the moment you paste them.
	HeldItem.place(_prop, _skeleton, PROPS[_prop_index],
		{"pos": _pos, "rot": _rot, "scale": _scale})
	if _follow:
		_anchor = (_skeleton.global_transform
			* _skeleton.get_bone_global_pose(bone)).origin


func _move_camera() -> void:
	_camera.global_position = _anchor + Vector3(
		sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(_anchor, Vector3.UP)


func _write_labels() -> void:
	var clip := _clips[_clip_index] if not _clips.is_empty() else "no clips"
	_head.text = "%s   holding   %s\n%s   (%d/%d)%s" % [
		BODIES[_body_index].get_file().trim_suffix(".tscn"),
		PROPS[_prop_index].get_file().trim_suffix(".tscn"),
		clip, _clip_index + 1, _clips.size(),
		"   PAUSED" if _player and is_zero_approx(_player.speed_scale) else "",
	]
	_numbers.text = "pos %+.3f %+.3f %+.3f    rot %+.1f %+.1f %+.1f    scale %.2f%s" % [
		_pos.x, _pos.y, _pos.z, _rot.x, _rot.y, _rot.z, _scale,
		"    [free camera]" if not _follow else "",
	]


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - zoom_step, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + zoom_step, min_distance, max_distance)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch + event.relative.y * orbit_sensitivity,
			deg_to_rad(-80.0), deg_to_rad(80.0))
	if not (event is InputEventKey and event.pressed):
		return
	var key := event as InputEventKey
	var step := FINE_STEP if key.shift_pressed else STEP
	var turn := FINE_TURN if key.shift_pressed else TURN

	match key.physical_keycode:
		KEY_BRACKETLEFT:
			_prop_index = wrapi(_prop_index - 1, 0, PROPS.size())
			_load_prop()
		KEY_BRACKETRIGHT:
			_prop_index = wrapi(_prop_index + 1, 0, PROPS.size())
			_load_prop()
		KEY_MINUS:
			_body_index = wrapi(_body_index - 1, 0, BODIES.size())
			_load_body()
		KEY_EQUAL:
			_body_index = wrapi(_body_index + 1, 0, BODIES.size())
			_load_body()
		KEY_COMMA:
			_step_clip(-1)
		KEY_PERIOD:
			_step_clip(1)
		KEY_SPACE:
			if _player:
				_player.speed_scale = 0.0 if _player.speed_scale > 0.0 else 1.0

		# Nudge, in the hand's own space -- the same space the table is written in, so
		# what you press is what you paste.
		KEY_A: _pos.x -= step
		KEY_D: _pos.x += step
		KEY_Q: _pos.y -= step
		KEY_E: _pos.y += step
		KEY_W: _pos.z -= step
		KEY_S: _pos.z += step

		KEY_LEFT: _rot.y -= turn
		KEY_RIGHT: _rot.y += turn
		KEY_UP: _rot.x -= turn
		KEY_DOWN: _rot.x += turn
		KEY_R: _rot.z -= turn
		KEY_F1: _rot.z += turn

		KEY_Z: _scale = maxf(_scale - SCALE_STEP, 0.05)
		KEY_X: _scale += SCALE_STEP

		KEY_F:
			_follow = not _follow
		KEY_0:
			_pos = Vector3.ZERO
			_rot = Vector3.ZERO
			_scale = 1.0
		KEY_P:
			_print_row()
		KEY_ESCAPE:
			get_tree().quit()


func _step_clip(direction: int) -> void:
	if _clips.is_empty():
		return
	_clip_index = wrapi(_clip_index + direction, 0, _clips.size())
	_play_clip()


## Prints the finished row, formatted to drop straight into [constant HeldItem.OFFSETS].
##
## Printed rather than written: this scene is a viewer, and a tool that edits source while
## you are looking at it is a tool that can lose an afternoon's tuning to a stray keypress.
func _print_row() -> void:
	print("\n\t\"%s\": {" % PROPS[_prop_index])
	print("\t\t\"pos\": Vector3(%.4f, %.4f, %.4f)," % [_pos.x, _pos.y, _pos.z])
	print("\t\t\"rot\": Vector3(%.1f, %.1f, %.1f)," % [_rot.x, _rot.y, _rot.z])
	print("\t\t\"scale\": %.3f," % _scale)
	print("\t},")
