extends SceneTree

## Sets up humanoid retargeting so Synty's Universal Animation Library plays on the
## POLYGON Starter characters.
##
##   godot --headless --path . --script res://Game/setup_retarget.gd
##   godot --headless --path . --import          # then reimport
##
## The two rigs are unrelated: the characters use Synty's own naming (50 bones) and
## the animation library uses the Unreal mannequin's (65 bones). Mapping both onto
## SkeletonProfileHumanoid makes the importer rename their bones to a shared set and
## fix the rest poses, after which either rig's clips drive either skeleton.
##
## Watch out for Synty's names: they do not mean what a humanoid profile means by
## them. Shoulder_L is the upper arm, Clavicle_L is the shoulder, Elbow_L is the
## forearm and Ankle_L is the foot. Getting those wrong folds the rig inside out.
##
## Safe to re-run; it overwrites the same maps and import keys.

const MAP_DIR := "res://Game/Rigs/"
const SYNTY_MAP := MAP_DIR + "synty_bone_map.tres"
const MANNEQUIN_MAP := MAP_DIR + "mannequin_bone_map.tres"
const CITY_CHARACTERS_MAP := MAP_DIR + "city_characters_bone_map.tres"

## Where the POLYGON City Characters pack lives, and the skeleton inside each of its 19
## scenes. Scanned rather than listed: the pack is one file per character and hand-listing
## nineteen import paths is nineteen chances to miss one.
const CITY_CHARACTERS_DIR := "res://Assets/Polygon-Characters/Characters/"
const CITY_CHARACTERS_SKELETON := "Root/Skeleton3D"

## profile bone name -> bone name in the Synty POLYGON Starter rig.
const SYNTY := {
	"Root": "Root", "Hips": "Hips",
	"Spine": "Spine_01", "Chest": "Spine_02", "UpperChest": "Spine_03",
	"Neck": "Neck", "Head": "Head", "Jaw": "Jaw",
	"LeftShoulder": "Clavicle_L", "LeftUpperArm": "Shoulder_L",
	"LeftLowerArm": "Elbow_L", "LeftHand": "Hand_L",
	"RightShoulder": "Clavicle_R", "RightUpperArm": "Shoulder_R",
	"RightLowerArm": "Elbow_R", "RightHand": "Hand_R",
	"LeftUpperLeg": "UpperLeg_L", "LeftLowerLeg": "LowerLeg_L",
	"LeftFoot": "Ankle_L", "LeftToes": "Ball_L",
	"RightUpperLeg": "UpperLeg_R", "RightLowerLeg": "LowerLeg_R",
	"RightFoot": "Ankle_R", "RightToes": "Ball_R",
	# Synty merges middle/ring/little into one chain, so only thumb, index and that
	# merged chain can be mapped. Invisible at RTS camera distance.
	"LeftThumbMetacarpal": "Thumb_01_L", "LeftThumbProximal": "Thumb_02_L",
	"LeftThumbDistal": "Thumb_03_L",
	"LeftIndexProximal": "IndexFinger_01_L", "LeftIndexIntermediate": "IndexFinger_02_L",
	"LeftIndexDistal": "IndexFinger_03_L",
	"LeftMiddleProximal": "Finger_01_L", "LeftMiddleIntermediate": "Finger_02_L",
	"LeftMiddleDistal": "Finger_03_L",
	"RightThumbMetacarpal": "Thumb_01_R", "RightThumbProximal": "Thumb_02_R",
	"RightThumbDistal": "Thumb_03_R",
	"RightIndexProximal": "IndexFinger_01_R", "RightIndexIntermediate": "IndexFinger_02_R",
	"RightIndexDistal": "IndexFinger_03_R",
	"RightMiddleProximal": "Finger_01_R", "RightMiddleIntermediate": "Finger_02_R",
	"RightMiddleDistal": "Finger_03_R",
}

## profile bone name -> bone name in the Unreal mannequin rig the library uses.
const MANNEQUIN := {
	"Root": "root", "Hips": "pelvis",
	"Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l",
	"LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r",
	"RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l",
	"LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r",
	"RightFoot": "foot_r", "RightToes": "ball_r",
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l",
	"LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l", "LeftIndexIntermediate": "index_02_l",
	"LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l", "LeftMiddleIntermediate": "middle_02_l",
	"LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l", "LeftRingIntermediate": "ring_02_l",
	"LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l", "LeftLittleIntermediate": "pinky_02_l",
	"LeftLittleDistal": "pinky_03_l",
	"RightThumbMetacarpal": "thumb_01_r", "RightThumbProximal": "thumb_02_r",
	"RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r", "RightIndexIntermediate": "index_02_r",
	"RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r", "RightMiddleIntermediate": "middle_02_r",
	"RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r", "RightRingIntermediate": "ring_02_r",
	"RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r", "RightLittleIntermediate": "pinky_02_r",
	"RightLittleDistal": "pinky_03_r",
}

## profile bone name -> bone name in the POLYGON City Characters pack.
##
## **A third rig, and a hybrid one.** It is mostly the Unreal mannequin's naming, which is
## why the existing `MANNEQUIN` map is so nearly right -- but a handful of bones are
## capitalised (`Pelvis`, `UpperArm_L`, `Hand_L`, `Thigh_L`, `Foot_L`) where the mannequin
## has them lowercase, the head is `head` where the mannequin has `Head`, and the fingers
## follow Synty's merged convention rather than the mannequin's five separate chains. Bone
## names are matched exactly and case-sensitively, so near enough is not enough and this
## could not simply reuse `MANNEQUIN`.
##
## **No Root.** This rig starts at `Pelvis`; the `_ik_*` bones are IK helpers, not a
## character root, and mapping one to `Root` would put the whole skeleton under a bone the
## animations never move.
const CITY_CHARACTERS := {
	"Hips": "Pelvis",
	"Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
	"Neck": "neck_01", "Head": "head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "UpperArm_L",
	"LeftLowerArm": "lowerarm_l", "LeftHand": "Hand_L",
	"RightShoulder": "clavicle_r", "RightUpperArm": "UpperArm_R",
	"RightLowerArm": "lowerarm_r", "RightHand": "Hand_R",
	"LeftUpperLeg": "Thigh_L", "LeftLowerLeg": "calf_l",
	"LeftFoot": "Foot_L", "LeftToes": "ball_l",
	"RightUpperLeg": "Thigh_R", "RightLowerLeg": "calf_r",
	"RightFoot": "Foot_R", "RightToes": "ball_r",
	# Merged middle/ring/little, exactly as the Starter rig does it.
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l",
	"LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "indexFinger_01_l", "LeftIndexIntermediate": "indexFinger_02_l",
	"LeftIndexDistal": "indexFinger_03_l",
	"LeftMiddleProximal": "finger_01_l", "LeftMiddleIntermediate": "finger_02_l",
	"LeftMiddleDistal": "finger_03_l",
	"RightThumbMetacarpal": "thumb_01_r", "RightThumbProximal": "thumb_02_r",
	"RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "indexFinger_01_r", "RightIndexIntermediate": "indexFinger_02_r",
	"RightIndexDistal": "indexFinger_03_r",
	"RightMiddleProximal": "finger_01_r", "RightMiddleIntermediate": "finger_02_r",
	"RightMiddleDistal": "finger_03_r",
}


## Which skeleton inside each imported scene gets which map.
const TARGETS := [
	{
		"import": "res://Assets/Synty/PolygonStarter/Models/Characters.fbx.import",
		"skeleton": "Skeleton3D",
		"map": SYNTY,
		"map_path": SYNTY_MAP,
	},
	# **The Heist pack's characters, on the same map as the Starter pack's.** Its rig uses
	# the raw Synty names -- `Ankle_L`, `Clavicle_L`, `Spine_01` -- which is exactly what
	# [constant SYNTY] renames. Without this the SWAT officer imports with those names, the
	# animation library (which speaks the humanoid profile) resolves nothing, and the unit
	# stands in bind pose: reported from play as "the response unit is in a T pose".
	{
		"import": "res://Assets/Synty/PolygonHeist/Model/Characters.fbx.import",
		"skeleton": "Skeleton3D",
		"map": SYNTY,
		"map_path": SYNTY_MAP,
	},
	{
		"import": "res://Assets/animations/UAL1_Standard.glb.import",
		"skeleton": "Armature/Skeleton3D",
		"map": MANNEQUIN,
		"map_path": MANNEQUIN_MAP,
	},
	{
		"import": "res://Assets/animations/UAL1_Standard_RM.glb.import",
		"skeleton": "Armature/Skeleton3D",
		"map": MANNEQUIN,
		"map_path": MANNEQUIN_MAP,
	},
]

var _failed := false


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(MAP_DIR)

	var profile_bones := _profile_bone_names()
	print("SkeletonProfileHumanoid exposes %d bones" % profile_bones.size())

	if not _save_map(SYNTY, SYNTY_MAP, profile_bones, "Synty"):
		_failed = true
	if not _save_map(MANNEQUIN, MANNEQUIN_MAP, profile_bones, "Mannequin"):
		_failed = true
	if not _save_map(CITY_CHARACTERS, CITY_CHARACTERS_MAP, profile_bones, "CityChars"):
		_failed = true

	for target in TARGETS:
		_patch_import(target)
	for target in _city_character_targets():
		_patch_import(target)

	if _failed:
		print("\nsetup finished with problems -- see above")
		quit(1)
		return
	print("\nretarget configured. Now run:  --headless --path . --import")
	quit()


## One target per character file in the pack, built by scanning the directory.
##
## Listed by scan rather than by hand because the pack is nineteen separate scenes and a
## hand-written list is nineteen chances to forget one -- and a character that misses the
## map imports with its own bone names, so it silently plays no animation at all rather
## than failing loudly.
func _city_character_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var dir := DirAccess.open(CITY_CHARACTERS_DIR)
	if dir == null:
		push_error("no character pack at %s" % CITY_CHARACTERS_DIR)
		_failed = true
		return targets
	for file in dir.get_files():
		if not file.ends_with(".fbx"):
			continue
		targets.append({
			"import": CITY_CHARACTERS_DIR + file + ".import",
			"skeleton": CITY_CHARACTERS_SKELETON,
			"map": CITY_CHARACTERS,
			"map_path": CITY_CHARACTERS_MAP,
		})
	return targets


func _profile_bone_names() -> PackedStringArray:
	var profile := SkeletonProfileHumanoid.new()
	var names := PackedStringArray()
	for i in profile.bone_size:
		names.append(profile.get_bone_name(i))
	return names


## Builds a BoneMap and saves it. Every key is checked against the profile, because a
## misspelled profile bone is silently ignored rather than reported by BoneMap.
func _save_map(mapping: Dictionary, path: String, profile_bones: PackedStringArray,
		label: String) -> bool:
	var unknown := PackedStringArray()
	for profile_bone in mapping:
		if not profile_bones.has(profile_bone):
			unknown.append(profile_bone)

	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_bone in mapping:
		if profile_bones.has(profile_bone):
			bone_map.set_skeleton_bone_name(profile_bone, mapping[profile_bone])

	var err := ResourceSaver.save(bone_map, path)
	if err != OK:
		push_error("could not save %s: %d" % [path, err])
		return false

	print("  %-10s mapped %d/%d bones -> %s" % [
		label, mapping.size() - unknown.size(), mapping.size(), path])
	if unknown.size() > 0:
		push_error("%s: these are not SkeletonProfileHumanoid bones: %s"
			% [label, ", ".join(unknown)])
		return false
	return true


## Writes retarget/bone_map into the scene importer's per-node subresource settings.
## Done through ConfigFile so the Resource reference is serialised by the engine
## rather than hand-written, and so existing keys (animation slices, other nodes)
## are merged rather than clobbered.
func _patch_import(target: Dictionary) -> void:
	var path: String = target["import"]
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK:
		push_error("could not read %s: %d" % [path, err])
		_failed = true
		return

	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	var nodes: Dictionary = subresources.get("nodes", {})
	var key := "PATH:" + str(target["skeleton"])
	var settings: Dictionary = nodes.get(key, {})

	settings["retarget/bone_map"] = load(target["map_path"])
	nodes[key] = settings
	subresources["nodes"] = nodes
	config.set_value("params", "_subresources", subresources)

	err = config.save(path)
	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		_failed = true
		return
	print("  patched %s  [%s]" % [path.get_file(), key])
