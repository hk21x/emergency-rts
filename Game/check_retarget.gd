extends SceneTree

## Verifies that the retargeted animation library actually drives the character rig,
## and renders a contact sheet of poses.
##
##   godot --path . --script res://Game/check_retarget.gd
##
## Built and played at runtime rather than from a saved scene: an autoplay set on an
## instanced scene's child is not preserved by PackedScene.pack(), which is exactly
## how the first attempt produced six identical T-poses.

## Defaults to the Starter character; pass another after `--`, e.g.
##   ... --script res://Game/check_retarget.gd -- res://Game/Characters/PoliceOfficer.tscn
const DEFAULT_CHARACTER := "res://Game/Characters/Character.tscn"
const OUT_DIR := "user://shots/"

const CLIPS: Array[String] = [
	"Idle", "Walk", "Driving", "Sitting_Idle", "Fixing_Kneeling", "PickUp_Table",
]

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var args := OS.get_cmdline_user_args()
	var character_path: String = args[0] if args.size() > 0 else DEFAULT_CHARACTER
	print("checking ", character_path)

	var scene := load(character_path) as PackedScene
	if scene == null:
		_check(false, "%s loads" % character_path)
		_finish()
		return

	var root := Node3D.new()
	get_root().add_child(root)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-120.0), 0.0)
	root.add_child(light)

	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(0.0, 1.05, 7.6)
	root.add_child(camera)

	var players: Array[AnimationPlayer] = []
	var skeletons: Array[Skeleton3D] = []
	for i in CLIPS.size():
		var character := scene.instantiate()
		character.position = Vector3((i - (CLIPS.size() - 1) * 0.5) * 2.0, 0.0, 0.0)
		root.add_child(character)
		players.append(character.get_node("AnimationPlayer"))
		skeletons.append(character.get_node("Armature/GeneralSkeleton"))

	var available := players[0].get_animation_list()
	_check(available.size() > 0, "character carries %d clips" % available.size())

	# Rest pose of a bone the clips all move, to prove the tracks actually bind.
	var bone := skeletons[0].find_bone("LeftUpperArm")
	_check(bone >= 0, "rig exposes the humanoid bone LeftUpperArm")
	var rest := skeletons[0].get_bone_pose_rotation(bone) if bone >= 0 else Quaternion()

	for i in CLIPS.size():
		var clip := CLIPS[i]
		if not players[i].has_animation(clip):
			_check(false, "clip '%s' is present" % clip)
			continue
		players[i].play(clip)
		# Part-way in, so a looping clip is caught mid-motion rather than at its
		# first frame, which is often near the rest pose.
		players[i].seek(players[i].get_animation(clip).length * 0.4, true)

	await physics_frame
	await physics_frame

	for i in CLIPS.size():
		if bone < 0:
			break
		var posed := skeletons[i].get_bone_pose_rotation(bone)
		_check(posed.angle_to(rest) > 0.02,
			"'%s' moves the rig (%.1f deg from rest)" % [
				CLIPS[i], rad_to_deg(posed.angle_to(rest))])

	await RenderingServer.frame_post_draw
	var shot: String = OUT_DIR + character_path.get_file().get_basename() + "_poses.png"
	get_root().get_texture().get_image().save_png(shot)
	print("  wrote ", ProjectSettings.globalize_path(shot))
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok    ", description)
	else:
		print("  FAIL  ", description)
		_failures += 1


func _finish() -> void:
	if _failures == 0:
		print("\nretarget verified")
		quit(0)
	else:
		print("\n%d check(s) failed" % _failures)
		quit(1)
