extends SceneTree

## Builds animated character scenes: a skinned body on its skeleton, with Synty's
## Universal Animation Library attached.
##
##   godot --headless --path . --script res://Game/build_character.gd
##
## Sources differ but the output does not. The POLYGON Starter character comes from a
## retargeted FBX (see setup_retarget.gd); the POLYGON City characters ship already
## retargeted, with a `GeneralSkeleton` whose bones are SkeletonProfileHumanoid names.
## Because both end up on the same bone set, one animation library drives both.
##
## Node layout matters: the library's tracks are authored as
## "Armature/GeneralSkeleton:BoneName", so the skeleton has to sit at that path
## beneath the AnimationPlayer's root for the tracks to bind. The City prefabs put
## their skeleton directly under the root, which is why they are rebuilt rather than
## instanced.

const UAL := "res://Assets/animations/UAL1_Standard.glb"
const OUT_DIR := "res://Game/Characters/"
## Binary, and deliberately so. The library is 43 clips of keyframed float tracks;
## written as text it is 3.0MB that takes 313ms to parse, and written as a binary
## `.res` it is 1.2MB that loads in 7ms. Measured, both.
const LIBRARY_PATH := "res://Game/Rigs/ual_standard.res"
const MAT_01 := "res://Assets/Synty/PolygonStarter/Materials/PolygonStarter_Mat_01_mat.tres"

## Each source carries several bodies on one shared skeleton; `keep` picks the one
## this scene is for and the rest are dropped.
const CHARACTERS := [
	{
		"source": "res://Assets/Synty/PolygonStarter/Models/Characters.fbx",
		"keep": "SM_Character_Male_01",
		"out": "Character.tscn",
		"material": MAT_01,
	},
	{
		"source": "res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Male_Police.tscn",
		"keep": "Character_Male_Police",
		"out": "PoliceOfficer.tscn",
		# Keeps whatever the City prefab already assigned.
		"material": "",
	},
	# **A real paramedic, since August 2026.** Both of these were repainted police for
	# the whole life of the project -- the City pack has neither a paramedic nor a
	# firefighter, only police, and the standing note here said so apologetically. The
	# POLYGON City Characters pack arrived with both, in their own kit.
	#
	# They carry their own material off the FBX, so `material` stays empty. The old
	# firefighter entry repainted a police body to `PolygonCity_02_A` to at least read
	# warm beside the appliance; a real fire kit needs no such trick, and the
	# paint-warmth check that guarded it now guards the kit itself.
	#
	# **These sit on a third rig.** The pack is mostly Unreal-mannequin naming with some
	# bones capitalised and Synty's merged fingers, so it needed its own bone map --
	# `setup_retarget.CITY_CHARACTERS`, which renames it onto the same humanoid profile
	# the Starter rig and the animation library already share. Without that map they
	# import with their own bone names and silently play nothing at all.
	{
		"source": "res://Assets/Polygon-Characters/Characters/SK_Character_Paramedic.fbx",
		"keep": "SK_Character_Paramedic",
		"out": "Paramedic.tscn",
		"material": "",
	},
	{
		"source": "res://Assets/Polygon-Characters/Characters/SK_Character_FireFighter.fbx",
		"keep": "SK_Character_FireFighter",
		"out": "Firefighter.tscn",
		"material": "",
	},
	# **Armed response**, from the Heist pack. That pack's rig uses the same bone names
	# the City characters do -- `Ankle_L`, `Clavicle_L`, `Hips` -- so it needs no third
	# retarget map and drops straight through this pipeline.
	{
		# **The FBX, not the prefab.** The prefab embeds its own `Skeleton3D` with the raw
		# Synty bone names baked in, so patching the pack's import settings never reaches
		# it -- the SWAT officer imported un-retargeted and stood in bind pose. The FBX is
		# what `setup_retarget.gd` patches, and it carries the same wardrobe.
		"source": "res://Assets/Synty/PolygonHeist/Model/Characters.fbx",
		# The *mesh*, not the file. These prefabs are wardrobes -- one skeleton wearing a
		# dozen alternative bodies -- and the root node's name is the pack's file name,
		# not the outfit. The police entry above keeps `Character_Male_Police` for the
		# same reason.
		"keep": "Character_Male_SWAT_01",
		"out": "ArmedOfficer.tscn",
		# **Named, not inherited.** An empty string means "keep whatever the source
		# assigned", which is what every other entry here wants -- but the materials live
		# on the pack's *prefabs*, not in the FBX this is built from, so inheriting got
		# nothing and the officer turned out plain white.
		"material": "res://Assets/Synty/PolygonHeist/Materials/PolygonHeist_Character_01_mat.tres",
	},
]

## The public. Same treatment as the officer above -- these prefabs ship on the same
## already-retargeted rig, so the one animation library drives all of them.
const CIVILIANS := [
	"Character_BusinessMan_Shirt",
	"Character_BusinessMan_Suit",
	"Character_BusinessWoman",
	"Character_Female_Coat",
	"Character_Female_Jacket",
	"Character_Male_Hoodie",
	"Character_Male_Jacket",
]
const CITY_CHARACTERS := "res://Assets/Synty/PolygonCity/Prefabs/Characters/"

var _failed := false


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var library := _extract_library()
	if library == null:
		quit(1)
		return

	for config in CHARACTERS:
		if not _build_character(config, library):
			_failed = true

	for civilian in CIVILIANS:
		var built := _build_character({
			"source": CITY_CHARACTERS + civilian + ".tscn",
			"keep": civilian,
			"out": civilian.replace("Character_", "") + ".tscn",
			"material": "",
		}, library)
		if not built:
			_failed = true

	if _failed:
		quit(1)
		return
	print("done -- verify with Game/check_retarget.gd")
	quit()


## Pulls the AnimationLibrary out of the imported GLB and saves it standalone, so
## every character scene references one copy instead of embedding 43 clips each.
func _extract_library() -> AnimationLibrary:
	var scene := load(UAL) as PackedScene
	if scene == null:
		push_error("could not load %s" % UAL)
		return null
	var root := scene.instantiate()
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	if player == null:
		push_error("no AnimationPlayer in %s" % UAL)
		root.free()
		return null

	var names := player.get_animation_library_list()
	if names.is_empty():
		push_error("no animation libraries in %s" % UAL)
		root.free()
		return null

	var library: AnimationLibrary = player.get_animation_library(names[0]).duplicate(true)
	root.free()

	var err := ResourceSaver.save(library, LIBRARY_PATH)
	if err != OK:
		push_error("could not save %s: %d" % [LIBRARY_PATH, err])
		return null

	# The line the sharing actually hangs on. `ResourceSaver.save` writes the file but
	# leaves the in-memory resource pathless, and a pathless resource is one `pack()`
	# has nowhere to point at -- so it inlines a copy instead. That is exactly what
	# happened here for months: the library sat on disk, correctly saved, referenced
	# by nothing, while all eleven character scenes embedded their own 3MB copy of it
	# and cost 315ms each to parse. Claiming the path makes them external references,
	# and ten of the eleven loads become cache hits.
	library.take_over_path(LIBRARY_PATH)
	print("saved %d clips -> %s" % [library.get_animation_list().size(), LIBRARY_PATH])
	return library


func _build_character(config: Dictionary, library: AnimationLibrary) -> bool:
	var source_path: String = config["source"]
	if not ResourceLoader.exists(source_path):
		push_error("missing source: %s" % source_path)
		return false

	var source := (load(source_path) as PackedScene).instantiate()
	var skeleton := _find(source, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("no Skeleton3D in %s" % source_path)
		source.free()
		return false

	var root := Node3D.new()
	root.name = "Character"

	var armature := Node3D.new()
	armature.name = "Armature"
	root.add_child(armature)
	armature.owner = root

	# Lift the skeleton out of the source scene and into our own layout. Owners are
	# cleared first: reparenting a node that still belongs to the old scene root warns
	# about an inconsistent owner, even though _take_ownership fixes it below.
	_clear_ownership(skeleton)
	skeleton.get_parent().remove_child(skeleton)
	# Named to match the animation tracks, whatever the source called it.
	skeleton.name = "GeneralSkeleton"
	armature.add_child(skeleton)
	source.free()

	# One body per outfit on a shared skeleton: keep the requested one, drop the rest
	# so the scene is not carrying eight invisible meshes.
	var keep: String = config["keep"]
	var kept := 0
	for child in skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		if mesh.name.contains(keep):
			mesh.visible = true
			var material_path: String = config["material"]
			if material_path != "":
				mesh.set_surface_override_material(0, load(material_path))
			kept += 1
		else:
			skeleton.remove_child(mesh)
			mesh.queue_free()

	if kept == 0:
		push_error("no mesh matching '%s' in %s" % [keep, source_path])
		root.free()
		return false

	_take_ownership(skeleton, root)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	# Tracks are relative to the AnimationPlayer's root, which defaults to its parent.
	player.add_animation_library("", library)
	root.add_child(player)
	player.owner = root

	var out: String = OUT_DIR + str(config["out"])
	print("%-22s from %s  (%d bones)" % [
		config["out"], source_path.get_file(), skeleton.get_bone_count()])
	return _save(root, out)


# --- Helpers -----------------------------------------------------------------

func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return false
	return true


func _clear_ownership(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_ownership(child)


func _take_ownership(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_take_ownership(child, root)


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found:
			return found
	return null
