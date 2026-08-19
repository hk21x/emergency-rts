extends Unit
class_name Person

## A unit on foot.
##
## Much simpler than [Vehicle]: a person can turn on the spot, so there is no
## steering model, no reversing and no turning circle. Steer straight at the next
## path corner and walk.
##
## Paths come from the person navigation mesh, baked with a much smaller agent radius
## than the vehicle one, so people can use gaps no car would fit through.

@export_group("Movement")
@export var walk_speed := 2.2
@export var run_speed := 4.6
## Beyond this far from the destination a person breaks into a jog.
@export var run_distance := 7.0
## Forces the run gait however near the target is. A pedestrian-graph hop is about a tile,
## which is under `run_distance`, so a civilian fleeing hop by hop would otherwise *walk*
## away from a fire. Set by [Civilian] while panicking and cleared when it passes.
var hurry := false
@export var acceleration := 14.0
## Radians/sec the body turns to face where it is going.
@export var turn_speed := 9.0
@export var arrive_radius := 0.7
@export var gravity := 24.0

@export_group("Getting past things")
## How long walking into something counts as being stuck rather than brushing it.
##
## People collide with the player's vehicles -- a person masks layer 1 and that is what
## a patrol car sits on -- but no vehicle can see a person at all, so nothing is going to
## move out of the way. Left alone the walker simply stops: measured with a car parked
## between an officer and where they were sent, **1,716 frames of the next 1,747 were
## spent stationary against it**, and they never arrived.
@export var blocked_after := 0.5
## How long one sideways step lasts. Long enough at walking pace to clear the width of a
## car, so a step that starts beside a bonnet finishes past it.
@export var sidestep_time := 1.1
## Below this speed, while trying to go somewhere, counts as not moving.
@export var stuck_speed := 0.35

## How far ahead to feel for whatever is in the way, once stuck. A little past arm's
## reach: far enough to find the panel of a car a body's width away, short enough that
## it cannot pick up something on the far side of a gap the person could walk through.
const FEEL_AHEAD := 1.4

## Where the water leaves the person: chest height, and a little way out in front so the
## stream does not start inside their own body.
const NOZZLE_HEIGHT := 1.15
const NOZZLE_REACH := 0.45

## How long one call to [method spray_at] keeps the water on. Comfortably longer than a
## physics frame, so a stream driven frame by frame reads as continuous, and short enough
## that it stops the moment the work does.
const SPRAY_HOLD := 0.25

## One jet scene per agent. Two scenes rather than one recoloured, because the agent rule
## is only fair if a player can see which substance is coming out: water is thin streaks
## that fall, foam is soft blobs that hang and swell. Dry powder has no scene -- an
## officer's extinguisher is an implied tool -- no pack has one -- but the powder coming
## out of it is not, and it borrowed the water jet until August 2026: an officer on an
## electrical fire was drawn spraying water, on the one call whose whole rule is that
## water is wrong. A visual that contradicts the mechanic is worse than none.
const JET_SCENES := {
	Fire.Agent.WATER: "res://Game/Units/WaterJet.tscn",
	Fire.Agent.FOAM: "res://Game/Units/FoamJet.tscn",
	Fire.Agent.POWDER: "res://Game/Units/PowderJet.tscn",
}

## The nozzle a firefighter holds while working: the appliance's **own** hose nozzle,
## `SM_Veh_Firetruck_Hose_Nozzle`, which is already a part on the built engine. Taken off
## the shelf rather than modelled, and it is the only hand-held fire tool in any pack --
## there is no extinguisher anywhere in the 516 props, which is why an officer gets none.
const NOZZLE_MESH := "res://Assets/PolygonTown/Models/Vehicles/extracted/" \
	+ "SM_Veh_Firetruck_Hose_Nozzle.res"

## How far the barrel reaches past the hand, measured off the mesh: it runs 0.51m along
## its own -Y from the coupling, which is where the hand goes.
const NOZZLE_LENGTH := 0.52

## The bone the nozzle is held in. The characters are retargeted to SkeletonProfile-
## Humanoid, so this name is the same on every one of them.
const HAND_BONE := &"RightHand"

@export_group("Animation")
## Fraction of [member run_speed] above which the jog clip is used.
@export var jog_threshold := 0.6
@export var blend_time := 0.18
## Clip playback is scaled by actual speed to keep the feet from skating.
@export var min_playback := 0.6
@export var max_playback := 1.7

@onready var _agent: NavigationAgent3D = $NavigationAgent
@onready var _animation: AnimationPlayer = $Character/AnimationPlayer

var move_target := Vector3.ZERO
## Set while riding in a vehicle. An aboard person is hidden, has no collision and
## cannot be selected.
var is_aboard := false
var carrier: Vehicle

## Clip forced by a WorkOrder while the person is doing a job. Overrides locomotion.
var action_clip := ""

var _navigating := false
## Seconds spent walking into something, and the sidestep it eventually earns.
var _blocked_time := 0.0
var _sidestep_time_left := 0.0
var _sidestep := Vector3.ZERO

## The hose stream, instanced the first time this person actually sprays something.
## Lazily rather than shipped in every character scene: there are eleven of those, all
## generated by build_character.gd, and only a firefighter or an officer will ever want
## one. Loading an FX scene by path at runtime is what Fire.gd already does to swap its
## plume.
## Jets already built, keyed by agent. Kept rather than swapped so a crew that fights a
## bin and then a car does not rebuild a particle system mid-shift.
var _jets := {}
var _jet: GPUParticles3D
var _spray_left := 0.0
var _spray_point := Vector3.ZERO
var _spray_agent: Fire.Agent = Fire.Agent.WATER

## The held nozzle, and the bone it is held in. Both resolved lazily, like the jet.
var _nozzle: Node3D
var _skeleton: Skeleton3D
var _hand_bone := -1


func _physics_process(delta: float) -> void:
	super(delta)
	_update_spray(delta)


func _ready() -> void:
	super()
	_agent.target_desired_distance = arrive_radius
	_play("Idle")


# --- Movement interface ------------------------------------------------------

## Somebody on foot turns on the spot, so the waypoint/destination distinction that
## [Vehicle] needs means nothing here.
func navigate_to(point: Vector3, _may_turn_round := true) -> void:
	move_target = point
	_navigating = true
	_agent.target_position = point


func stop_navigating() -> void:
	_navigating = false


func is_navigating() -> bool:
	return _navigating


func remaining_distance() -> float:
	if not _navigating:
		return 0.0
	return Vector2(move_target.x - global_position.x, move_target.z - global_position.z).length()


func respawn() -> void:
	super()
	velocity = Vector3.ZERO
	_navigating = false


## What this person can do, decided by which service they belong to.
##
## The gating is **hard**: an officer offers no Treat at all, so right-clicking a
## casualty with one selected produces a Move order and nothing else. Sending the wrong
## unit is a wasted trip rather than a slower one, which is the whole point of having a
## roster to choose from.
##
## It needs no new machinery. `Unit.resolve()` already picks the best-scoring ability
## and returns null when none applies, so an ability that simply is not in this list
## can never win a right-click and never gets a command tile.
##
## Police carry the extinguisher a patrol car actually carries -- enough for a bin or a
## vehicle, which is what the district throws at them. A building fire needs an
## appliance, and the City pack has neither one of those nor a firefighter to crew it.
## What this unit is *within* its service.
##
## [member Unit.service] is identity -- it decides the brand colour, the roster grouping and
## which calls a unit is considered for -- and until August 2026 it was also the only thing
## that decided capability: [method _build_abilities] matched on it and nothing else. That
## made a specialist inexpressible. A doctor is not a fourth emergency service, but they can
## do something a paramedic cannot, and the only way to say so was to invent a service for
## them, which would have been a lie the interface then had to carry everywhere.
##
## So capability is now service **plus** speciality. Empty means the ordinary member of the
## service, which is what almost every unit is.
##
## It does not yet add *verbs* -- the doctor's difference is what their treatment achieves,
## not a new tile -- and it deliberately is not wired into [method _build_abilities] until a
## specialist actually needs one, because a hook with no caller is the kind of thing this
## project has had to delete before. The hazmat team is the one that will want it.
@export var speciality := &""

## The doctor: advanced care, and the only unit that can stabilise a casualty too far gone
## for a paramedic. See [member Casualty.needs_doctor].
const DOCTOR := &"doctor"

## Armed response: the officer who can face a suspect carrying a weapon.
##
## **The first speciality that adds a verb.** The note above says this hook deliberately
## did not touch `_build_abilities` until a specialist actually needed one, so that a hook
## with no caller would not sit there being nearly used. This is that specialist: an armed
## suspect cannot be walked up to and arrested, and [DisarmAbility] is the only answer.
const ARMED := &"armed"


## Whether this unit can stabilise a casualty a paramedic can only hold. Asked by
## [method Casualty.treat] rather than by an ability, because the *verb* is the same one --
## a paramedic sent to a dying patient should still get to work on them, and telling the
## player "you cannot even try" would be both unkind and untrue.
func has_advanced_care() -> bool:
	return speciality == DOCTOR


func _build_abilities() -> Array[Ability]:
	match service:
		Service.MEDICAL:
			return [MoveAbility.new(), TreatAbility.new(), CollectAbility.new(),
				BoardAbility.new(), StopAbility.new(), ReturnAbility.new()]
		Service.POLICE:
			# Escort moved here from the patrol car in August 2026: an arrest is made on
			# foot and the walk to the car should be too, for the same reason the
			# stretcher run is the paramedic's rather than the ambulance's.
			if speciality == ARMED:
				return [MoveAbility.new(), DisarmAbility.new(),
					ApprehendAbility.new(), LoadSuspectAbility.new(),
					ExtinguishAbility.new(), SecureAbility.new(),
					BoardAbility.new(), StopAbility.new(), ReturnAbility.new()]
			return [MoveAbility.new(), ApprehendAbility.new(),
				LoadSuspectAbility.new(), ExtinguishAbility.new(),
				SecureAbility.new(), ClearAbility.new(), BoardAbility.new(),
				StopAbility.new(), ReturnAbility.new()]
		Service.FIRE:
			# A firefighter still cannot treat, arrest or cordon. What they have is the
			# hose -- at a rate the police extinguisher cannot touch, and the only thing
			# that touches a *building* -- Cool, which is the same hose pointed at
			# something that has not caught yet, and Free, which is the odd one: it
			# helps nobody they can help, and exists to unblock the paramedic.
			# Clear is shared with the police: box-lugging is not specialist work.
			return [MoveAbility.new(), ExtinguishAbility.new(), CoolAbility.new(),
				FreeAbility.new(), ClearAbility.new(), BoardAbility.new(),
				StopAbility.new(), ReturnAbility.new()]
		_:
			return [MoveAbility.new(), BoardAbility.new(), StopAbility.new()]


func set_action(clip: String) -> void:
	action_clip = clip


func clear_action() -> void:
	action_clip = ""


func face_towards(point: Vector3) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return
	# Same convention as _face_travel: this aims the node's -Z, and the visual's 180
	# yaw turns that into the model looking the right way.
	rotation.y = atan2(flat.x, flat.z) + PI


# --- Riding ------------------------------------------------------------------

## Condition, 1.0 to 0.0. At zero they go down and a [Casualty] is left where they fell.
##
## Until August 2026 nothing in the district could touch a person the player had paid
## for: damage existed only on [Vehicle], and the blast that turned bystanders into
## casualties walked straight past the crew standing in it. That made every scene safe to
## walk into, which removes the one decision the genre is built on.
var health := 1.0
## True between going down and being delivered or written off. They stay in the tree --
## see [method _go_down] for why that matters more than it sounds.
var is_down := false

signal took_harm(person: Person, amount: float)


func is_selectable() -> bool:
	return not is_aboard and not is_down


## What this person is wearing, as a path an [Incident] can pass to `_wear_outfit()`.
##
## **Not `scene_file_path`.** That is the *unit* scene and the outfit is the character
## inside it; the two differ by one directory and `ResourceLoader.exists()` says yes to
## both, so the wrong one silently gives an incident a whole unit as its body. Lifted
## here from [Civilian] when crew casualties arrived, because a downed firefighter should
## be lying there in their own kit rather than wearing a stranger's.
func outfit_scene() -> String:
	var body := get_node_or_null("Character") as Node3D
	return body.scene_file_path if body else ""


## Takes condition off. The single entry point, deliberately shaped like
## [method Vehicle.scorch] so there is one verb for "this hurt something".
##
## Three no-ops, each load-bearing:
## - **the crowd is not crew.** [Civilian] extends this class, so any `as Person` cast
##   catches shoppers too; they have their own conversion path and must not also be
##   down-stated by it.
## - **a passenger is not standing there.** An aboard person rides at the carrier's
##   position, so a blast beside the appliance would otherwise take out the crew sitting
##   safely inside it.
## - **already down** cannot be hurt again, or one blast files two casualties.
func hurt(amount: float) -> void:
	if service == Unit.Service.NONE or is_aboard or is_down or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	took_harm.emit(self, amount)
	if health <= 0.0:
		_go_down()


## Puts them on the floor and files a casualty where they fell.
##
## **The person stays in the tree.** `Station._alive()` counts group membership, so a unit
## that is still there still counts against `available()` -- the player cannot dispatch a
## replacement for somebody lying in the street, which is the whole tension. Freeing them
## and spawning a bare casualty would make being blown up *refund* a unit.
func _go_down() -> void:
	if is_down:
		return
	is_down = true
	var scene := load("res://Game/Incidents/Casualty.tscn") as PackedScene
	var parent := get_tree().get_first_node_in_group(Incident.GROUP)
	var host := get_parent() if parent == null else parent.get_parent()
	var fell_at := global_position
	_leave_play()
	if scene == null or host == null:
		return
	var casualty := scene.instantiate() as Casualty
	if casualty == null:
		return
	casualty.outfit = outfit_scene()
	casualty.crew = self
	casualty.flavour = "%s down" % display_name
	host.add_child(casualty)
	casualty.global_position = fell_at


## Back on the forecourt, whole again. Called when their casualty reaches hospital.
func return_to_duty(at: Vector3) -> void:
	if not is_down:
		return
	is_down = false
	health = 1.0
	_rejoin_play(at)


## Out of play but still on the books: hidden, unpickable, holding no orders.
##
## Boarding, dismounting, going down and coming back all did these four toggles by hand
## in four places. Four places to forget one.
func _leave_play() -> void:
	clear_orders()
	stop_navigating()
	velocity = Vector3.ZERO
	visible = false
	# Deferred: a shape cannot be disabled during the physics step that is using it.
	$Collision.set_deferred("disabled", true)


func _rejoin_play(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	visible = true
	$Collision.set_deferred("disabled", false)


## Climbs into a vehicle. The seat is claimed by [method Vehicle.take_aboard] first;
## this is only the passenger's half of it.
func board(vehicle: Vehicle) -> void:
	if is_aboard:
		return
	is_aboard = true
	carrier = vehicle
	_leave_play()


func disembark(at: Vector3) -> void:
	if not is_aboard:
		return
	is_aboard = false
	carrier = null
	_rejoin_play(at)


# --- Frame -------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	if is_aboard:
		# Ride along, so the ring and any later dismount start from the right place.
		if is_instance_valid(carrier):
			global_position = carrier.global_position
		return

	var desired := _step_round_obstacles(_desired_velocity(), delta)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(desired, acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() and velocity.y < 0.0 else velocity.y - gravity * delta

	move_and_slide()
	_face_travel(delta)
	_update_animation()
	_update_weapon()


## Where the person wants to be heading, or zero when standing still.
func _desired_velocity() -> Vector3:
	if not _navigating:
		return Vector3.ZERO

	var to_target := move_target - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_radius or _agent.is_navigation_finished():
		_navigating = false
		return Vector3.ZERO

	# Head for the next corner of the path, not straight at the destination.
	var step := _agent.get_next_path_position() - global_position
	step.y = 0.0
	if step.length() < 0.05:
		step = to_target
	var speed := run_speed if hurry or to_target.length() > run_distance else walk_speed
	return step.normalized() * speed


## Turns walking *into* something into walking *along* it.
##
## Godot's [method CharacterBody3D.move_and_slide] already slides along a surface, but
## only where the motion has something tangential to slide with -- head-on into the side
## of a car it resolves to nothing at all, every frame, for ever. So once someone has
## been getting nowhere for [member blocked_after], their intent is swung round to run
## along whatever is in the way and the sliding does the rest.
##
## Deliberately not solved by taking vehicles out of the person collision mask. Walking
## *through* a parked car is worse than stopping at one, and vehicles cannot be given the
## people layer either -- a car that collided with pedestrians would push them into
## walls, or through the floor, which is the failure [method Vehicle._keep_on_the_map]
## exists to survive.
func _step_round_obstacles(desired: Vector3, delta: float) -> Vector3:
	if desired.length() < 0.01:
		_blocked_time = 0.0
		_sidestep_time_left = 0.0
		return desired

	if _sidestep_time_left > 0.0:
		_sidestep_time_left -= delta
		return _sidestep * desired.length()

	if Vector2(velocity.x, velocity.z).length() > stuck_speed:
		_blocked_time = 0.0
		return desired
	_blocked_time += delta
	if _blocked_time < blocked_after:
		return desired

	_blocked_time = 0.0
	var way_round := _way_round(desired)
	if way_round == Vector3.ZERO:
		return desired
	_sidestep = way_round
	_sidestep_time_left = sidestep_time
	return way_round * desired.length()


## Which way along the obstruction to go, or zero if there is nothing to go along.
##
## The obstruction is found by **asking the physics space directly** rather than by
## reading this frame's slide collisions. A person walked flat into the side of a parked
## car has `velocity` zeroed and `get_slide_collision_count()` of two -- both of them the
## road they are standing on. Whatever the engine does with a contact that stops the
## motion outright, it is not something to build behaviour on.
##
## The normal points back out of what was hit, so its tangent runs along the face; of the
## two directions that offers, the one still heading roughly where the person was going
## is the short way round. A quarter of the normal is mixed back in so they peel away
## from the surface rather than grinding along it.
func _way_round(desired: Vector3) -> Vector3:
	var eye := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(eye,
		eye + desired.normalized() * FEEL_AHEAD, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	var out := Vector3(hit["normal"].x, 0.0, hit["normal"].z)
	if out.length() < 0.01:
		return Vector3.ZERO
	out = out.normalized()
	var tangent := out.cross(Vector3.UP)
	if tangent.dot(desired) < 0.0:
		tangent = -tangent
	var way := (tangent + out * 0.25).normalized()
	if not _may_step_to(global_position + way * walk_speed * sidestep_time):
		# The short way round is somewhere this person may not go. The other way along
		# the same face is the only other option worth trying.
		way = (-tangent + out * 0.25).normalized()
		if not _may_step_to(global_position + way * walk_speed * sidestep_time):
			return Vector3.ZERO
	return way


## Whether a sidestep may finish at [param point]. Anyone under orders goes wherever the
## navigation mesh goes; [Civilian] overrides this, because the crowd has to stay on the
## pavement graph and a step off it would put someone in the middle of a road.
func _may_step_to(_point: Vector3) -> bool:
	return true


func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.05:
		return
	# Model faces -Z like the rest of Godot, so atan2 of the travel direction is the
	# yaw directly.
	var wanted := atan2(flat.x, flat.z) + PI
	rotation.y = rotate_toward(rotation.y, wanted, turn_speed * delta)


func _update_animation() -> void:
	if not action_clip.is_empty():
		# Work clips are one-shots; _play restarts them once current_animation clears,
		# which loops them for as long as the job lasts.
		_animation.speed_scale = 1.0
		_play(action_clip)
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	var clip := "Idle"
	var playback := 1.0

	if speed > run_speed * jog_threshold:
		clip = "Jog_Fwd"
		playback = speed / run_speed
	elif speed > 0.12:
		clip = "Walk"
		playback = speed / walk_speed

	_animation.speed_scale = clampf(playback, min_playback, max_playback)
	_play(clip)


func _play(clip: String) -> void:
	if _animation.current_animation == clip:
		return
	if not _animation.has_animation(clip):
		return
	_animation.play(clip, blend_time)


## Puts water on [param point] for this frame.
##
## An **expiring ask**, the same shape as the appliance's ladder: an order calls this
## every frame it delivers water and simply stops calling it when it does not. Nothing
## has to remember to turn the jet off — which matters, because there are four ways to
## stop working (finished, shoved out of range, cancelled, target freed) and a latch
## would have to be released on every one of them.
##
## Driven by **delivery**, deliberately, not by the order starting. A firefighter with no
## appliance in reach still walks up and still plays the animation and still gets
## nowhere; drawing a jet there would say water is landing when the entire point is that
## none is. The same goes for an officer in front of a building fire.
func spray_at(point: Vector3, agent: Fire.Agent = Fire.Agent.WATER) -> void:
	_spray_point = point
	_spray_left = SPRAY_HOLD
	_spray_agent = agent


func _update_spray(delta: float) -> void:
	_spray_left = maxf(_spray_left - delta, 0.0)
	var wanted := _spray_left > 0.0 and not is_aboard
	# Anything that is not the agent being sprayed goes quiet, or a crew switching from
	# water to foam leaves the old stream hanging in the air.
	for other in _jets.values():
		if other != _jets.get(_spray_agent):
			(other as GPUParticles3D).emitting = false
	_jet = _jets.get(_spray_agent)
	if _jet == null:
		if not wanted:
			return
		var scene := load(str(JET_SCENES.get(
			_spray_agent, JET_SCENES[Fire.Agent.WATER]))) as PackedScene
		if scene == null:
			return
		_jet = scene.instantiate() as GPUParticles3D
		if _jet == null:
			return
		_jets[_spray_agent] = _jet
		add_child(_jet)
		# **Top level, so the body does not drag the water about.** The particles are in
		# world space; if the nozzle inherited this person's transform, turning to face a
		# second fire would swing the droplets already in the air round with it.
		_jet.top_level = true

	if not wanted:
		_jet.emitting = false
		if _nozzle:
			_nozzle.visible = false
		return

	# A firefighter holds the appliance's nozzle; anyone else is working an extinguisher
	# no pack has a model for, so their water comes from the chest and no tool is drawn.
	var held := _hand_point()
	var from := held if held != Vector3.INF else \
		global_position + Vector3.UP * NOZZLE_HEIGHT
	var along := _spray_point - from
	# Nothing sensible to aim at: a target on top of the nozzle has no direction, and
	# look_at() throws on a zero-length basis rather than shrugging.
	if along.length() < 0.1:
		_jet.emitting = false
		if _nozzle:
			_nozzle.visible = false
		return
	var aim := along.normalized()
	# Straight up or down would be collinear with the up vector and look_at() would fail.
	# Nothing in the game sprays at its own feet, but the guard costs a line.
	var up := Vector3.UP
	if absf(aim.dot(up)) > 0.99:
		up = Vector3.FORWARD

	# The water leaves the muzzle, not the hand -- otherwise the first half-metre of the
	# stream is inside the tool that is supposed to be producing it.
	var muzzle := NOZZLE_REACH
	if held != Vector3.INF:
		_show_nozzle(from, up)
		muzzle = NOZZLE_LENGTH
	elif _nozzle:
		_nozzle.visible = false

	_jet.global_position = from + aim * muzzle
	_jet.look_at(_spray_point, up)
	_jet.emitting = true


## A firearm held in the right hand, or empty for the unarmed.
##
## Set on [ArmedOfficer.tscn] rather than derived, because carrying a weapon is a property
## of the unit rather than of its service -- an ordinary officer and an ARV are both
## POLICE. Placed each frame off the hand bone for the same reason the hose nozzle is: a
## `BoneAttachment3D` would have to live inside the character scene, and those are
## regenerated by `build_character.gd`, which would throw it away.
@export var weapon_scene := ""

var _weapon: Node3D


## Keeps the held weapon on the hand. Called from the movement update, beside the nozzle.
func _update_weapon() -> void:
	if weapon_scene.is_empty():
		return
	if _weapon == null:
		var packed := load(weapon_scene) as PackedScene
		if packed == null:
			weapon_scene = ""
			return
		_weapon = packed.instantiate() as Node3D
		if _weapon == null:
			weapon_scene = ""
			return
		_weapon.name = "HeldWeapon"
		Unit.strip_collision(_weapon)
		add_child(_weapon)
	var hand := _weapon_hand_point()
	if hand == Vector3.INF:
		_weapon.visible = false
		return
	_weapon.visible = true
	_weapon.global_position = hand
	# Along the body's own facing, so it points where the officer does.
	_weapon.global_rotation = global_rotation


## The right hand, for anything held. Same lookup as [method _hand_point] without the fire
## service gate -- that one is about the hose and answers INF for everybody else.
func _weapon_hand_point() -> Vector3:
	if _skeleton == null:
		_skeleton = get_node_or_null("Character/Armature/GeneralSkeleton") as Skeleton3D
	if _skeleton == null:
		return Vector3.INF
	var bone := _skeleton.find_bone(HAND_BONE)
	if bone < 0:
		return Vector3.INF
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


## Where this person's right hand is, or [constant Vector3.INF] if they have no skeleton
## or are not carrying a nozzle.
##
## Read off the skeleton each frame rather than hung on a `BoneAttachment3D`, because the
## attachment would have to live *inside* the character scene -- and those eleven scenes
## are generated by build_character.gd, so anything added there is lost the next time
## they are rebuilt.
func _hand_point() -> Vector3:
	if service != Unit.Service.FIRE:
		return Vector3.INF
	if _hand_bone < 0:
		_skeleton = get_node_or_null("Character/Armature/GeneralSkeleton") as Skeleton3D
		if _skeleton == null:
			_hand_bone = -2
			return Vector3.INF
		_hand_bone = _skeleton.find_bone(HAND_BONE)
		if _hand_bone < 0:
			_hand_bone = -2
			return Vector3.INF
	if _hand_bone < 0 or _skeleton == null:
		return Vector3.INF
	return _skeleton.global_transform \
		* _skeleton.get_bone_global_pose(_hand_bone).origin


## Puts the held nozzle in the hand, pointing where the water is going.
func _show_nozzle(at: Vector3, up: Vector3) -> void:
	if _nozzle == null:
		var mesh := load(NOZZLE_MESH) as Mesh
		if mesh == null:
			return
		# An outer node carries the aim and an inner one the mesh's own orientation. The
		# barrel runs along the mesh's -Y, so a quarter turn about X lays it along -Z --
		# which is where look_at() points, and where the particles fire.
		_nozzle = Node3D.new()
		_nozzle.name = "HeldNozzle"
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.rotation.x = PI / 2.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_nozzle.add_child(visual)
		add_child(_nozzle)
		# Top level for the same reason the jet is: the aim is computed in world space.
		_nozzle.top_level = true
	_nozzle.global_position = at
	_nozzle.look_at(_spray_point, up)
	_nozzle.visible = true
