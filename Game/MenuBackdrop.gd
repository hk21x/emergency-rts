extends Node3D
class_name MenuBackdrop

## The main menu's picture: the user's hand-built scene -- a petrol station well alight,
## a police cordon, an appliance pulled up -- shown at dusk in the rain.
##
## The scene itself is `Assets/PolygonTown/Scenes/MainMenu.tscn`, authored in the editor
## and treated as **read-only input** exactly like the tutorial town. Nothing here edits
## it; this node instances it and dresses it at run time, so the user can keep moving
## cars around in the editor and the menu simply shows the new arrangement.
##
## Dusk and rain come from [Daylight], the same node the district uses, rather than from
## anything painted into the scene. That is the whole reason this is cheap: the weather
## already exists, it already knows how to grade the lights and hang rain over the
## camera, and pointing it at a different set of lights is a NodePath.
##
## **The environment is duplicated before it is touched.** The vendor scene's
## WorldEnvironment references a shared `.tres` that other scenes use, and Daylight
## writes fog and ambient values into whatever it is given -- so handing it the shared
## resource would dim the district's sky as a side effect of opening the menu. Same trap
## the tutorial's setup node documents, same answer.

## Where the picture is graded to.
##
## **These two constants are the whole control, and one of them has a second half.**
## `SKY` is applied at run time and nothing else needs doing. `HOUR` is *also written
## into the scene* so the editor shows what ships -- so changing it here and stopping
## leaves the game right and the editor a lie. Re-run `author_menu_hour.gd`, which
## reads this constant, and the two agree again.
const HOUR := Daylight.Mode.DAY
const SKY := Daylight.Weather.CLEAR

## The cordon prop, the same one every incident in the game puts down.
const CONE := "res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Cone_01.tscn"
const OFFICER := "res://Game/Characters/PoliceOfficer.tscn"
const FIREFIGHTER := "res://Game/Characters/Firefighter.tscn"
## The member of the public the officer is talking to. One, not a crowd: three
## bystanders scattered along the crossing read as people who had wandered into shot
## rather than as anyone connected to what is happening.
const PUBLIC := "res://Game/Characters/Male_Jacket.tscn"

## What each pair is doing. Names are the retargeted library's, which drops the pack's
## `_Loop` suffix -- `Idle`, not `Idle_Loop`.
## One officer stays with the car and the cordon; the other is in the conversation
## below, which has its own clip.
const OFFICER_CLIPS := ["Idle"]
const CREW_CLIPS := ["Fixing_Kneeling", "Idle_Torch"]

## How fast the lightbars run, in full cycles a second -- [Vehicle]'s own figure, so the
## menu's beacons and the game's beat at the same rate.
const BEACON_HZ := 1.7

## **Everything below is placed in the vehicle's own local space**, so moving a car in
## the editor takes its lights, its crew and its cordon with it. The numbers are metres
## and are meant to be nudged: nobody can see this scene from a headless run, so they
## are constants rather than literals buried in the placement code.
##
## The cordon's width and the gap between cones. Where the line sits is CORDON_OUT.
const CONE_SPAN := 7.0
const CONE_STEP := 1.4
## Where crew stand relative to their vehicle: out to the side, at the ends of the
## cordon rather than behind it.
const CREW_ASIDE := 2.6
const CREW_AHEAD := 2.2

## The conversation stands **beside** the car on its camera-facing flank, not between
## the car and the lens. Between is where it went first: 3.8m toward a camera 5m away
## and 7m up put both of them under it and out of frame, with the cordon officer left
## looking like the only person in the shot. Beside the bonnet is where they read.
const PAIR_GAP := 1.4

## The cordon goes on the far side of the car -- between it and the fire, which is what
## a cordon is for and, not coincidentally, the part of the forecourt the camera can
## see. Laid across the car's nose it ran off the left edge behind the menu column.
const CORDON_OUT := 4.0

var _beads: Array[Array] = []
var _beacon_time := 0.0


func _ready() -> void:
	var backdrop := get_node_or_null("Backdrop")
	if backdrop == null:
		push_warning("MenuBackdrop has no Backdrop to dress")
		return

	# The vendor scene ships its camera switched off, because in the editor it is a
	# framing aid rather than the view. Here it *is* the view.
	var camera := backdrop.get_node_or_null("Camera") as Camera3D
	if camera:
		camera.visible = true
		camera.current = true

	var world := backdrop.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		world.environment = world.environment.duplicate(true)

	var weather := get_node_or_null("Daylight") as Daylight
	if weather:
		weather.set_time_of_day(HOUR)
		weather.set_weather(SKY)

	# Deferred, all of it: a node cannot add children to a parent that is still setting
	# its own up, and `_ready` runs inside exactly that window. The tutorial's crowd was
	# empty for a day over this.
	_dress.call_deferred(backdrop, camera)


## Turns the scene from a parked tableau into an incident: lights on, a crew out, a
## cordon down.
func _dress(backdrop: Node, camera: Camera3D) -> void:
	var police := backdrop.get_node_or_null("SM_Veh_Car_Police_01") as Node3D
	var engine := backdrop.get_node_or_null("SM_Veh_Firetruck_01") as Node3D
	var props := Node3D.new()
	props.name = "Dressing"
	add_child(props)

	if police and camera:
		_beads_of(police)
		_cordon(props, police, camera)
		# One on the radio, one watching the fire. A pair doing the same thing reads
		# as a copy-paste; a pair doing two things reads as two people.
		_crew(props, police, OFFICER, OFFICER_CLIPS)
	if engine:
		_beads_of(engine)
		# One down at the pump working, one stood with a lamp up.
		_crew(props, engine, FIREFIGHTER, CREW_CLIPS)
	# The bit of human business the shot needed: an officer with a member of the public,
	# on the near side of the car where the eye already is.
	if police and camera:
		_conversation(props, police, camera)


## Collects a vehicle's lightbar beads so [method _process] can flash them.
##
## **Finds, does not build.** The lights are authored into the scene now -- headlights,
## beads and their bulbs -- so the editor viewport shows what ships and they can be
## dragged and recoloured by hand. Building them here as well would simply put a second
## set inside the first. What run time still owns is the *flashing*, because a saved
## scene cannot blink.
func _beads_of(vehicle: Node3D) -> void:
	var bar := vehicle.get_node_or_null("Lightbar")
	if bar == null or bar.get_child_count() < 2:
		return
	var pair: Array[Node3D] = []
	for child in bar.get_children():
		var bead := child as Node3D
		if bead:
			pair.append(bead)
	if pair.size() >= 2:
		_beads.append([pair[0], pair[1]])


## A line of cones across the car's nose.
func _cordon(props: Node, car: Node3D, camera: Camera3D) -> void:
	if not ResourceLoader.exists(CONE):
		return
	var packed := load(CONE) as PackedScene
	# Away from the camera: the far flank of the car, which is the side the fire is on
	# and the side the shot is looking across.
	var away := car.global_position - camera.global_position
	away.y = 0.0
	if away.length() < 0.01:
		return
	away = away.normalized()
	var along := away.cross(Vector3.UP).normalized()
	var middle := car.global_position + away * CORDON_OUT
	middle.y = car.global_position.y
	var count := int(CONE_SPAN / CONE_STEP)
	for i in count + 1:
		var cone := packed.instantiate() as Node3D
		props.add_child(cone)
		var across := -CONE_SPAN * 0.5 + float(i) * CONE_STEP
		# Bowed towards the fire, so the line reads as holding a space rather than as a
		# fence -- the ends come forward, the middle sits back.
		var bow := absf(across) / (CONE_SPAN * 0.5)
		cone.global_position = middle + along * across + away * bow * 0.9
		cone.rotation.y = car.global_rotation.y


## Two of a service, stood at the ends of their vehicle.
func _crew(props: Node, vehicle: Node3D, outfit: String, clips: Array) -> void:
	if not ResourceLoader.exists(outfit):
		return
	var packed := load(outfit) as PackedScene
	var hull := _hull(vehicle)
	var nose := -1.0 if hull.get_center().z <= 0.0 else 1.0
	for i in clips.size():
		var person := packed.instantiate() as Node3D
		props.add_child(person)
		var side := -1.0 if i == 0 else 1.0
		person.global_position = vehicle.to_global(Vector3(
			side * (hull.size.x * 0.5 + CREW_ASIDE), 0.0, nose * CREW_AHEAD))
		# Facing the way the car is pointed, turned a little towards each other so the
		# pair reads as a pair rather than as two people who arrived separately.
		person.global_rotation.y = vehicle.global_rotation.y + side * 0.35
		_idle(person, str(clips[i]))


## An officer and a member of the public, talking, on the camera's side of the car.
##
## Placed against the **camera** rather than against the car's own axes, because "this
## side" is a fact about the shot rather than about the vehicle: the direction from car
## to camera is the near side by definition, and it stays the near side if the user
## turns the car around in the editor.
func _conversation(props: Node, car: Node3D, camera: Camera3D) -> void:
	if not (ResourceLoader.exists(OFFICER) and ResourceLoader.exists(PUBLIC)):
		return
	var hull := _hull(car)
	var nose := -1.0 if hull.get_center().z <= 0.0 else 1.0
	# Which flank the camera is on, asked of the car rather than assumed -- the answer
	# has to survive the user turning the car round in the editor.
	var flank := 1.0 if car.to_local(camera.global_position).x > 0.0 else -1.0
	# The same spot a crew member stands on, which is the one placement in this scene
	# already known to frame well.
	var middle := car.to_global(Vector3(
		flank * (hull.size.x * 0.5 + CREW_ASIDE), 0.0, nose * CREW_AHEAD))

	var officer := (load(OFFICER) as PackedScene).instantiate() as Node3D
	props.add_child(officer)
	officer.global_position = middle
	var civilian := (load(PUBLIC) as PackedScene).instantiate() as Node3D
	props.add_child(civilian)
	# A pace further out from the car, so the two of them face across the shot rather
	# than one standing behind the other from where the camera is.
	civilian.global_position = car.to_global(Vector3(
		flank * (hull.size.x * 0.5 + CREW_ASIDE + PAIR_GAP), 0.0,
		nose * (CREW_AHEAD + PAIR_GAP * 0.6)))

	_face(officer, civilian.global_position)
	_face(civilian, officer.global_position)
	_idle(officer, "Idle_Talking")
	_idle(civilian, "Idle_Talking")


## Turns [param person] to face [param target].
##
## `atan2(x, z) + PI` is the project's own convention, from [Person]: these models face
## -Z, so the half turn is not a fudge -- drop it and everyone talks to the back of the
## person opposite.
func _face(person: Node3D, target: Vector3) -> void:
	var flat := target - person.global_position
	flat.y = 0.0
	if flat.length() < 0.01:
		return
	person.global_rotation.y = atan2(flat.x, flat.z) + PI


## Sets a character going. Without this they stand in the rig's rest pose, which reads
## as a shop mannequin rather than a person -- the T-pose trap by another name.
##
## **The clip names have no `_Loop` suffix**, whatever the source library called them:
## the retarget strips it, so the pack's `Idle_Loop` is `Idle` here. Asking for the
## suffixed name fails `has_animation` and returns quietly, which is exactly what this
## did on its first outing -- seven people placed correctly and every one of them stood
## in rest pose. The suite now checks they are actually animating.
func _idle(person: Node, clip: String) -> void:
	var player := person.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(clip):
		return
	player.play(clip)
	# Started at a different point each time, or seven people breathe in lockstep.
	var length := player.get_animation(clip).length
	player.seek(randf() * length, true)
	# **Some of these do not loop, and the library is shared with the whole game.**
	# `Fixing_Kneeling` is a one-shot; setting its `loop_mode` would make it loop for
	# every character in every scene, since all eleven now reference one library. So it
	# is re-triggered here instead, which keeps the change to this scene.
	if player.get_animation(clip).loop_mode == Animation.LOOP_NONE:
		player.animation_finished.connect(func(_finished: StringName) -> void:
			if is_instance_valid(player):
				player.play(clip))


## The prop's own bounding box, in its local space, from the meshes it is made of.
func _hull(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in _meshes(node):
		var local := (node.global_transform.affine_inverse()
			* child.global_transform) * child.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	if mesh:
		found.append(mesh)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


## The lightbars, running the game's own double-blink: two quick flashes one side, then
## two the other. A plain alternation reads as an indicator; this reads as an emergency
## light, and it is copied from [Vehicle] rather than re-invented so the two match.
func _process(delta: float) -> void:
	if _beads.is_empty():
		return
	_beacon_time += delta
	var phase := fposmod(_beacon_time * BEACON_HZ, 1.0)
	var left := phase < 0.11 or (phase >= 0.17 and phase < 0.28)
	var right := (phase >= 0.5 and phase < 0.61) or (phase >= 0.67 and phase < 0.78)
	for pair in _beads:
		pair[0].visible = left
		pair[1].visible = right
