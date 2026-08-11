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
func _build_abilities() -> Array[Ability]:
	match service:
		Service.MEDICAL:
			return [MoveAbility.new(), TreatAbility.new(), CollectAbility.new(),
				BoardAbility.new(), StopAbility.new(), ReturnAbility.new()]
		Service.POLICE:
			return [MoveAbility.new(), ApprehendAbility.new(), ExtinguishAbility.new(),
				SecureAbility.new(), BoardAbility.new(), StopAbility.new(),
				ReturnAbility.new()]
		Service.FIRE:
			# One verb, done properly. A firefighter cannot treat, arrest or cordon --
			# they put fires out, at a rate the police extinguisher cannot touch, and
			# they are the only unit that can put out a *building*.
			return [MoveAbility.new(), ExtinguishAbility.new(), BoardAbility.new(),
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

func is_selectable() -> bool:
	return not is_aboard


## Climbs into a vehicle. The seat is claimed by [method Vehicle.take_aboard] first;
## this is only the passenger's half of it.
func board(vehicle: Vehicle) -> void:
	if is_aboard:
		return
	is_aboard = true
	carrier = vehicle
	clear_orders()
	stop_navigating()
	velocity = Vector3.ZERO
	visible = false
	# Deferred: a shape cannot be disabled during the physics step that is using it.
	$Collision.set_deferred("disabled", true)


func disembark(at: Vector3) -> void:
	if not is_aboard:
		return
	is_aboard = false
	carrier = null
	global_position = at
	velocity = Vector3.ZERO
	visible = true
	$Collision.set_deferred("disabled", false)


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
	var speed := run_speed if to_target.length() > run_distance else walk_speed
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
