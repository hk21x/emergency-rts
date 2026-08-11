extends SceneTree

## Wraps each generated civilian character in a walking body, producing the scenes the
## map spawns its crowd from.
##
##   godot --headless --path . --script res://Game/build_civilians.gd
##
## Run build_character.gd first: this consumes what that produces.
##
## The same job Person.tscn does by hand for an officer, done seven times over. It is
## generated rather than seven copy-pasted scenes so the body, the collision capsule
## and the navigation agent cannot drift apart between outfits -- and so adding an
## eighth is one line in build_character.gd.

const CHARACTERS := "res://Game/Characters/"
const OUT_DIR := "res://Game/Civilians/"

## Matches build_character.gd's CIVILIANS, minus the "Character_" prefix it strips.
const OUTFITS := [
	"BusinessMan_Shirt", "BusinessMan_Suit", "BusinessWoman", "Female_Coat",
	"Female_Jacket", "Male_Hoodie", "Male_Jacket",
]

## The Synty character meshes face +Z; Godot's forward is -Z. Same correction
## Person.tscn applies, and for the same reason: get it wrong and they moonwalk.
const FLIP := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)),
	Vector3.ZERO)

var _failed := false


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for outfit in OUTFITS:
		if not _build_civilian(str(outfit)):
			_failed = true
	if _failed:
		quit(1)
		return
	print("done -- %d civilians" % OUTFITS.size())
	quit()


func _build_civilian(outfit: String) -> bool:
	var character_path := CHARACTERS + outfit + ".tscn"
	if not ResourceLoader.exists(character_path):
		push_error("missing character: %s -- run build_character.gd first" % character_path)
		return false

	var root := CharacterBody3D.new()
	root.name = "Civilian"
	root.set_script(load("res://Game/Units/Civilian.gd"))
	# Layer 128 marks the crowd -- deliberately not layer 4, which is the player's
	# people. RTSController's picking ray ignores 128 and 64 (traffic), so a shopper
	# standing between the camera and an officer does not swallow the click meant for
	# them. Making them merely unselectable is not enough: the ray still stops dead.
	#
	# Mask 1 is the static world only. Like an officer, a civilian does not collide
	# with vehicles or with other people, so a crowd cannot wedge itself in a doorway
	# and a patrol car cannot be brought to a halt by a shopper.
	root.collision_layer = 128
	root.collision_mask = 1
	root.display_name = outfit.replace("_", " ")

	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.9, 0.0)
	_add(root, collision, "Collision")

	var agent := NavigationAgent3D.new()
	# Layer 2 is the person navigation mesh -- roads and pavements, baked at a 0.4m
	# agent radius. Vehicles use layer 1 and its road-only mesh.
	agent.navigation_layers = 2
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.7
	agent.avoidance_enabled = false
	_add(root, agent, "NavigationAgent")

	# Person.gd reads $Character/AnimationPlayer, so the name is load-bearing.
	var character := (load(character_path) as PackedScene).instantiate()
	character.scene_file_path = character_path
	character.transform = FLIP
	_add(root, character, "Character")

	return _save(root, OUT_DIR + outfit + ".tscn")


func _add(root: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	root.add_child(node)
	node.owner = root


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
	print("  %s" % path.get_file())
	return true
