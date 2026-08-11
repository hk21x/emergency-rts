extends Unit
class_name Vehicle

## Arcade vehicle: a motion model plus an autopilot that drives it to a point.
##
## The motion model reads [member throttle_input], [member steer_input] and
## [member handbrake_input] and knows nothing about where those came from, so the
## same car can be flown by the autopilot or by a player controller.
##
## Longitudinal speed is driven directly, heading comes from a bicycle-steering
## model clamped by an available-grip limit, and the leftover sideways velocity is
## bled off by [member grip] -- lowering that during a handbrake turn is what
## produces a slide.

## Emitted when the physics engine has thrown this vehicle off the world and
## [method _keep_on_the_map] has put it back. Nothing needs to listen -- the recovery
## is silent by design -- but a recurrence is worth being able to see.
signal fell_off_the_map(vehicle: Vehicle)

## Emitted when [method _climb_kerb] has pulled this vehicle over a low step. Nothing
## needs to listen; it exists so a probe can count climbs rather than infer them from a
## height that happens to change, and so the suite can prove the lift came from here
## and not from a car riding up something it collided with.
signal climbed(vehicle: Vehicle)

## Below this the vehicle is under the world rather than on it, and is falling.
##
## The district's roads sit at y = 0 and the ground plane under everything is flat, so
## there is nowhere legitimate to be a couple of metres down. Generous enough that a
## kerb, a ramp or a frame of depenetration cannot trip it.
const FLOOR_FLOOR := -3.0

@export_group("Speed")
## Top speed in m/s. 24 m/s is roughly 86 km/h.
@export var max_speed := 24.0
## Cruising speed when the vehicle is not on a shout -- going back to the station. The
## ambient traffic runs at around 10 m/s, so this keeps a returning unit moving with
## the flow rather than through it.
@export var legal_speed := 12.0
@export var max_reverse_speed := 9.0
@export var acceleration := 16.0
@export var brake_deceleration := 34.0
## How hard the car slows when no pedal is held.
@export var coast_deceleration := 7.0

@export_group("Steering")
@export_range(5.0, 60.0, 0.5) var max_steer_degrees := 33.0
## Radians/sec the virtual steering rack moves toward the input.
@export var steer_response := 7.0
## Radians/sec it recentres when the input is released.
@export var steer_return := 10.0
## Front-to-rear axle distance. Measured from the model: 1.335 - (-1.2131).
@export var wheelbase := 2.548
## Fraction of steering lock removed at top speed, so the car settles down at pace.
@export_range(0.0, 0.95, 0.05) var speed_steer_falloff := 0.55
## Cornering grip ceiling in m/s^2. Caps yaw rate so fast turns stay believable.
@export var max_lateral_accel := 14.0

@export_group("Grip")
## Rate that sideways velocity is scrubbed off. Higher = more planted.
@export var grip := 14.0
## What the road surface is worth right now, as a fraction of dry grip. Multiplies
## **both** grip terms, so it is the one number that says "the road is wet".
##
## The autopilot already derives its corner speeds from available grip --
## `sqrt(max_lateral_accel * radius)` in [method _turn_speed] -- so lowering this
## lengthens braking distances and lowers apex speeds for the player *and* the ambient
## fleet without a line of new driving code. That reuse is the whole reason weather is
## cheap here: rain is a physical property of the road, not a special case in the
## controller. Set by [Daylight]; 1.0 is dry.
@export_range(0.2, 1.0, 0.05) var grip_scale := 1.0
@export var handbrake_grip := 2.5
@export var handbrake_deceleration := 12.0

@export_group("Autopilot")
## How close counts as arrived.
@export var arrive_radius := 2.2
## Distance over which the car eases down to a stop.
@export var slowdown_distance := 16.0
## Steering input per radian of heading error.
@export var steer_gain := 2.2
## Beyond this heading error the car reverses to swing its nose around instead of
## driving a long loop. A car cannot turn on the spot.
@export var reverse_angle_degrees := 115.0
## Reversing stops once the nose is within this much of the target. Deliberately far
## below [member reverse_angle_degrees]: without that gap the car would flip between
## reversing and driving forward every few frames near the threshold.
@export var reverse_exit_angle_degrees := 55.0
## Only worth reversing when the target is close; further out, driving round is faster.
##
## This is measured against the point currently being **aimed at**, which on a lane
## route is the next waypoint rather than the destination -- so it has to stay short.
## Raising it to the lane-route threshold was tried, to close the band where a car
## neither three-point-turns nor routes round a junction, and it made things worse: at
## 40m the latch armed at almost every waypoint transition and cars oscillated instead
## of arriving. The band is closed from the other end, by
## [constant CityGrid.LANE_ROUTE_MIN], which is the number that decides whether a
## journey has waypoints at all.
@export var reverse_trigger_distance := 16.0
## The same thing, but for the **final destination** rather than a waypoint on the way.
##
## These have to be two numbers. The latch decides whether to swing the nose round or
## drive round, and that question is about *where the car is going* -- but it is asked
## against whatever point is currently being aimed at, which on a lane route is the next
## waypoint a few tens of metres ahead. One number could not serve both: raising it to 40
## armed the latch at nearly every waypoint transition and cars oscillated instead of
## arriving, while leaving it at 16 left a band -- roughly 16m to 40m -- where a U-turn
## neither turned on the spot nor routed via a junction and **swung 27 metres off a 10m
## street**. Splitting them lets the destination be generous and the waypoints strict.
@export var turn_round_range := 45.0
## Speed ceiling in the tightest corners, as a fraction of [member max_speed].
@export_range(0.1, 1.0, 0.05) var corner_speed_ratio := 0.35
## How far along the navigation path to look for corners worth slowing down for.
@export var corner_lookahead := 50.0
## Fraction of the brake budgeted when planning a corner approach. Below 1 so speed
## comes off early and smoothly rather than in one late stamp on the pedal.
@export_range(0.1, 1.0, 0.05) var corner_brake_ratio := 0.45
## Corners shallower than this are not worth lifting for.
@export var corner_min_degrees := 12.0
## Distance over which a corner's angle is measured. Has to span a whole junction
## turn, because the navigation mesh delivers one as a run of small bends.
@export var corner_window := 6.0

@export_group("Avoidance")
## Whether this vehicle steers around others in its way. On for the player's units,
## off for ambient traffic, which queues instead -- a taxi that overtook would be
## the district driving like an emergency.
@export var avoids_vehicles := true
## How far ahead another vehicle counts as being in the way.
@export var avoid_lookahead := 14.0
## Half-width of the corridor swept ahead. A vehicle is in the way when it is inside
## this band, **not** merely within some angle: a cone that opens with distance calls
## a car parked at the kerb 12m up the road an obstruction, and the patrol car then
## crawls the length of its own station forecourt.
@export var avoid_width := 2.4
## How far to the side the car aims to pass. About a lane.
@export var avoid_shift := 3.4
## How far ahead the passing aim point sits.
@export var avoid_reach := 9.0
## How far the passing line may sit off the navigation mesh before it counts as no room.
## It does **not** keep the car off the pavement -- both navigation regions share one map
## and this query has no layer filter. The road test in [method _passing_line] is what
## does that.
@export var avoid_room := 1.6
## A passing line with a vehicle this close to it is not a gap.
@export var avoid_clearance := 4.0
## Speed ceiling while passing. Slower than the open road: a manoeuvre this close
## to another car should not also be the fastest part of the journey.
@export var passing_speed := 9.0

@export_group("Siren")
## Lightbar, flashed while the vehicle is on its way somewhere. Left empty on
## anything that has not got one, which is every civilian body.
@export var siren_path: NodePath
## Full two-sided flash cycles per second.
@export var siren_hz := 1.7

## The siren sound, looped while [member siren_on]. The recording first and the
## synthesised placeholder behind it: whichever is found, the switch works, and a
## vehicle with neither still has the switch -- it just has nothing to say through it.
const SIREN_STREAMS := ["res://Game/Audio/siren.mp3", "res://Game/Audio/siren.wav"]
## The engine note, looped for as long as the vehicle exists and pitched by speed.
const ENGINE_STREAMS := ["res://Game/Audio/engine.wav"]

@export_group("Doors")
## Rear doors, if this vehicle has them as separate meshes. Each is hinged on its own
## origin, so opening one is a plain yaw.
@export var door_left_path: NodePath
@export var door_right_path: NodePath
@export var door_open_degrees := 105.0
## Seconds to swing from shut to fully open.
@export var door_travel := 1.4
## How long they stay open after someone has got in or out.
@export var door_hold := 2.2
## Seconds of being pinned at a standstill before the car backs off and tries again.
## A safety net for the cases the navigation path cannot express -- wedged against a
## knocked-over cone, or shunted off the path by a collision.
@export var stuck_timeout := 0.8
@export var escape_duration := 1.0

@export_group("World")
@export var gravity := 32.0
## Impulse applied per m/s of impact speed when shouldering a RigidBody3D aside.
## A CharacterBody3D does not move dynamic bodies on its own; without this the car
## would stop dead against a traffic cone.
@export var push_force := 0.5
@export var max_push_impulse := 9.0

## How high a step the car will pull itself over once it is stuck against one. Well
## clear of the district's 7cm kerb and far under anything structural, so this can
## never walk a car up the side of a building. See [method _climb_kerb].
@export var climb_height := 0.22
## How far past the step it looks for somewhere to land. Roughly a nose's length: less
## and it would lift onto the kerb face itself rather than over it.
@export var climb_reach := 1.2
## How far forward the lift also carries the car, so it lands *on* the step rather than
## dropping back against its face. Must stay well under [member climb_reach], which is
## the distance the clearance test actually sweeps.
@export var climb_nudge := 0.5
## Seconds pinned before the car will try climbing. Deliberately **under**
## [member stuck_timeout], so a kerb is climbed before the car gives up and reverses --
## a reversing car is heading away from the step, not over it.
@export var climb_after := 0.5
## How far the far side of the step may be from the vehicle navigation mesh and still
## count as somewhere to land. A car put down where its agent cannot path is stranded,
## which is worse than a car still stuck on the road.
@export var climb_landing := 1.0
## How many reverse-and-retry manoeuvres must have failed before the car will climb.
## This is what separates "stuck" from "briefly stationary": a car cornering hard is
## the latter and must never climb, and only counting seconds cannot tell them apart.
@export var climb_escapes := 2
## How far a destination must be from any legal route before it counts as a deliberate
## trip off the road. Generous: the navigation mesh stops a little short of the kerb, so
## a tight parking spot on the carriageway must not read as off-road.
@export var off_road_margin := 1.5
## Within this of an off-road destination the car stops manoeuvring and simply drives at
## it. Long enough to cover the approach, the kerb and the far side; short enough that
## the journey up to it is still an ordinary routed drive on the roads.
@export var off_road_approach := 12.0

@export_group("Water")
## Whether this vehicle carries water at all. Only a fire appliance does; on
## everything else the tank is meaningless and never drawn.
@export var carries_water := false
## Refilled beside a hydrant or back at the station, at this much of the tank a
## second. Four seconds for a full one: long enough to be a decision about where to
## park, short enough that it is never the boring part of a shift.
@export var refill_per_second := 0.25
## How much the tank actually holds, in multiples of what one shipped with.
##
## [member water] stays a 0..1 *fullness* -- it is what the portrait's bar reads -- so
## capacity lives here, on the divisor, rather than by rescaling the gauge. Raising it
## makes the same tankful go further without changing anything that reads the bar.
##
## Twenty, from play feedback in August 2026: a crew who had to fight a call across
## several spread nodes were running the tank out and spending the call driving to
## hydrants instead of fighting the fire. At 1.0 a single building node cost 41% of a
## tank, so two and a half nodes emptied it.
@export var tank_capacity := 1.0
## How close to a hydrant an appliance has to stop. Generous -- the prop is drawn
## into a MultiMesh at the kerb and the engine parks in the road beside it.
@export var hydrant_reach := 9.0

@export_group("Crew")
@export var seats := 2
## Stabilised casualties this vehicle can carry to hospital.
@export var stretchers := 1
## Detained suspects this vehicle can take to the station. The back seats, in effect.
@export var cells := 1
## Metres behind the vehicle that dismounting crew are placed.
@export var dismount_back := 3.2
@export var dismount_side := 1.6

@export_group("Visuals")
## Wheel mesh radius, from the mesh AABB (0.6656 / 2).
@export var wheel_radius := 0.3328
## Turns of the steering wheel per unit of road-wheel angle.
@export var steering_wheel_ratio := 3.0
@export var lean_roll_degrees := 4.0
@export var lean_pitch_degrees := 1.6
@export var lean_response := 6.0

@onready var _agent: NavigationAgent3D = $NavigationAgent
@onready var _lean: Node3D = $Lean
@onready var _steering_wheel: Node3D = $Lean/Chassis/SteeringWheel
@onready var _wheels_steered: Array[Node3D] = [$Wheels/FL, $Wheels/FR]
@onready var _wheel_meshes: Array[Node3D] = [
	$Wheels/FL/Mesh, $Wheels/FR/Mesh, $Wheels/RL/Mesh, $Wheels/RR/Mesh,
]

## Control inputs. Set these to drive the car directly; the autopilot overwrites
## them every frame while it has somewhere to be.
var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false

## Signed speed along the car's forward axis. Negative while reversing.
var forward_speed := 0.0
var move_target := Vector3.ZERO
var crew: Array[Person] = []
var casualties: Array[Casualty] = []
var suspects: Array[Suspect] = []

## What is left in the tank, 0 to 1. Drawn down by the crew working off this
## appliance's hose (see [ExtinguishOrder]) and refilled at a hydrant or at home.
## Empty is a real failure state: a building fire grows faster than a firefighter
## with only what they carry can knock it down, so an engine that runs dry has to be
## moved rather than waited out.
var water := 1.0
## True while parked beside a hydrant (or at the station) taking water on. Public so
## the interface can say so rather than leaving a number to climb unexplained.
var is_refilling := false

## True while steering around another vehicle. Public so a test can assert the
## manoeuvre rather than infer it from a line that happens to bend.
var is_avoiding := false
## The vehicle currently being steered around, latched so a blocker that dips in and
## out of the cone does not make the car weave.
var _blocker: Vehicle

## Manual lightbar switch (the visual). The bar also runs on its own while the vehicle
## is responding; this is the parked case -- scene lighting at a stop.
var lights_on := false
## Manual siren switch (the audio), on exactly the terms the lightbar's is: the noise
## runs on its own while the vehicle is responding, and this is the parked case --
## sitting at a scene making yourself heard. Both are read in [method _update_siren];
## neither starts or stops the speaker on assignment, so there is one authority over
## whether it is playing rather than two that can disagree.
var siren_on := false

var _siren: Node3D
var _siren_beads: Array[Node3D] = []
var _siren_time := 0.0
var _siren_audio: AudioStreamPlayer3D
var _engine_audio: AudioStreamPlayer3D
var _doors: Array[Node3D] = []
## 0 shut, 1 fully open, and where it is heading.
var _door_swing := 0.0
var _door_wanted := 0.0
var _door_hold_left := 0.0

var _navigating := false
## Whether the current destination is somewhere the car cannot legally drive to -- a
## pavement, a verge, a park lawn. Sent there on purpose by the player, so the car has
## to be allowed both to keep going after the navigation path runs out and to climb the
## kerb in its way. Recomputed on every aim, so an ordinary road destination clears it.
var _off_road_target := false
## Whether swinging the nose round is allowed for the point currently being aimed at,
## which decides which of the two ranges the reverse latch uses. True for a journey's
## end and for a car that has just been told to go back the way it came; false for a
## waypoint on a lane route, where a three-point turn at every corner is the last thing
## wanted.
var _may_turn_round := true
var _reversing := false
## Seconds spent held below cruising speed by a vehicle it cannot get past.
var _held_time := 0.0
var _stuck_time := 0.0
var _escape_time := 0.0
## Reverse-and-retry manoeuvres run since the car last got moving properly. Counts how
## far it has got through its own options, which is what [method _climb_kerb] needs and
## a timer cannot say.
var _failed_escapes := 0
var _steer_angle := 0.0
var _wheel_spin := 0.0
var _lean_roll := 0.0
var _lean_pitch := 0.0
var _steering_wheel_rest: Basis


func _ready() -> void:
	super()
	_steering_wheel_rest = _steering_wheel.transform.basis
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	# Keep the agent's idea of "arrived" in step with the autopilot's.
	_agent.target_desired_distance = arrive_radius

	_siren = get_node_or_null(siren_path) as Node3D
	if _siren:
		_siren_beads = [_siren.get_node("Left") as Node3D, _siren.get_node("Right") as Node3D]

	# The speaker is built here rather than by build_vehicles.gd so every emergency
	# vehicle grows one without regenerating the scenes. Civilian bodies get none --
	# a taxi with a siren switch would be wrong even unpressable.
	if service != Service.NONE:
		_siren_audio = AudioStreamPlayer3D.new()
		_siren_audio.name = "SirenAudio"
		# Quieter than the synthesised two-tone it replaced, because the recording is a
		# properly mastered one and arrives near full scale where the generated tone
		# peaked around half. Same loudness in the district, six fewer decibels here.
		_siren_audio.volume_db = -12.0
		# Carries across a block at RTS height, without drowning the district.
		_siren_audio.unit_size = 14.0
		_siren_audio.stream = _looped(SIREN_STREAMS)
		add_child(_siren_audio)

		# The engine, which unlike the siren is never switched off: it idles when the
		# vehicle is stopped and rises with speed. Quieter and shorter-range than the
		# siren -- seven of these in a station yard should be a hum, not a chorus.
		_engine_audio = AudioStreamPlayer3D.new()
		_engine_audio.name = "EngineAudio"
		_engine_audio.volume_db = -20.0
		_engine_audio.unit_size = 5.0
		_engine_audio.max_distance = 45.0
		_engine_audio.stream = _looped(ENGINE_STREAMS)
		add_child(_engine_audio)
		if _engine_audio.stream:
			_engine_audio.play()
	var left := get_node_or_null(door_left_path) as Node3D
	var right := get_node_or_null(door_right_path) as Node3D
	if left and right:
		_doors = [left, right]


## The first of [param paths] that exists, set to loop, or null if none of them do.
##
## Looping is a different property in every container: three fields on the WAVs
## [code]build_audio.gd[/code] synthesises, one bool on a dropped-in MP3 or Ogg. The
## whole point of these sounds being files is that a recording can replace a
## placeholder without anything else changing, so the loader has to take either --
## and a siren that plays through once and falls silent is exactly the fault that
## slips past a check for "a sound is loaded".
func _looped(paths: Array) -> AudioStream:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var wav := stream as AudioStreamWAV
		if wav:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			# Frames, not bytes: the data is 16-bit mono.
			wav.loop_end = wav.data.size() / 2
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		return stream
	return null


## Whether [param stream] will loop, whichever container it is. Used by the suite:
## the switch turning a speaker on proves nothing if the sound runs out.
static func loops(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	return false


## Lightbar and doors are presentation, so they run on the render tick rather than
## the physics one -- the flash rate has nothing to do with the simulation step.
func _process(delta: float) -> void:
	_update_siren(delta)
	_update_engine()
	_update_doors(delta)


## Pitches the engine note with road speed. A fixed idle floor keeps a parked unit
## audible as a running vehicle rather than a silent prop.
func _update_engine() -> void:
	if _engine_audio == null or _engine_audio.stream == null:
		return
	var effort := clampf(absf(forward_speed) / maxf(max_speed, 1.0), 0.0, 1.0)
	_engine_audio.pitch_scale = 0.72 + effort * 0.95
	_engine_audio.volume_db = -24.0 + effort * 8.0


## Flashes while the vehicle is on its way somewhere, and stops when it arrives. The
## noise runs on the same terms, so an order sent by right-click lights the bar and
## sounds the horn together, and arriving kills both at once.
##
## They are still two switches on the command bar rather than one, because the cases
## where they come apart are the ones worth having: a unit parked at a scene wants the
## bar lit and the district quiet, and a crew driving through a night street sometimes
## wants the opposite. What is shared is the *automatic* source, not the switches.
func _update_siren(delta: float) -> void:
	# Dark unless this is actually a response -- going home is not one, so a vehicle
	# recalled to the station drives back on side lights like anything else -- or the
	# crew has thrown the switch themselves, which works parked and moving alike.
	var responding := _navigating and is_responding()
	_update_siren_audio(responding or siren_on)
	if _siren == null:
		return
	if not (responding or lights_on):
		if _siren.visible:
			_siren.visible = false
		return

	_siren.visible = true
	_siren_time += delta
	var phase := fposmod(_siren_time * siren_hz, 1.0)
	# A double blink on each side in turn, rather than a plain alternation. That
	# pattern is what reads as an emergency light instead of an indicator, and it
	# survives being seen at two pixels across from the far end of the district.
	_siren_beads[0].visible = phase < 0.11 or (phase >= 0.17 and phase < 0.28)
	_siren_beads[1].visible = (phase >= 0.5 and phase < 0.61) or (phase >= 0.67 and phase < 0.78)


## Starts and stops the speaker to match [param wanted].
##
## Guarded on [member AudioStreamPlayer3D.playing] rather than called blindly: `play()`
## on a player already going restarts the sound from the top, which on a per-frame
## caller is a siren that never gets past its first few milliseconds -- an easy silence
## to mistake for a stream that failed to load.
func _update_siren_audio(wanted: bool) -> void:
	if _siren_audio == null or _siren_audio.stream == null:
		return
	if wanted and not _siren_audio.playing:
		_siren_audio.play()
	elif not wanted and _siren_audio.playing:
		_siren_audio.stop()


## Swings the rear doors open, holds them, then shuts them again. Called whenever
## somebody gets in or out; a no-op on a vehicle whose doors are part of its hull.
func open_doors() -> void:
	if _doors.is_empty():
		return
	_door_wanted = 1.0
	_door_hold_left = door_hold


func _update_doors(delta: float) -> void:
	if _doors.is_empty():
		return
	if _door_hold_left > 0.0:
		_door_hold_left -= delta
		if _door_hold_left <= 0.0:
			_door_wanted = 0.0
	if is_equal_approx(_door_swing, _door_wanted):
		return

	_door_swing = move_toward(_door_swing, _door_wanted, delta / maxf(door_travel, 0.05))
	# Each door's origin is its own outer edge -- that is where the prefab hinges it --
	# so this is a plain yaw. The two mirror, hence the opposite signs.
	var angle := deg_to_rad(door_open_degrees) * _door_swing
	_doors[0].rotation.y = -angle
	_doors[1].rotation.y = angle


# --- Movement interface ------------------------------------------------------

## [param final] says whether this point is where the journey ends or a waypoint on the
## way to it, which is what decides how far out the car will turn round rather than
## drive round. Defaults to true: most callers navigate straight to what they want.
## Sends the car to a point, and **refuses to be sent off the map**.
##
## Every order funnels through here, so it is the one place worth checking. An off-map
## destination does not fail loudly -- the navigation agent clamps it to the nearest
## point it can path to, which may be the far side of the district -- so the car drives
## off in the wrong direction with nothing to say anything went wrong. One was recorded
## aiming at **z = 402 on a 260m map** with no order attached at all, which is a caller
## this guard will now name rather than leave to be inferred.
func navigate_to(point: Vector3, may_turn_round := true) -> void:
	var edge := CityGrid.MAP_HALF
	if absf(point.x) > edge or absf(point.z) > edge:
		push_warning("%s was sent off the map, to %s. Called from:\n%s"
			% [name, point, "\n".join(_caller_trace())])
		point = Vector3(clampf(point.x, -edge, edge), point.y,
			clampf(point.z, -edge, edge))
	_navigate_to(point, may_turn_round)


## Where the off-map call came from. Empty in a release build, which has no stack.
func _caller_trace() -> PackedStringArray:
	var lines := PackedStringArray()
	for frame in get_stack():
		lines.append("    %s:%d in %s" % [frame.get("source", "?"),
			frame.get("line", 0), frame.get("function", "?")])
	return lines


func _navigate_to(point: Vector3, may_turn_round := true) -> void:
	move_target = point
	_navigating = true
	_off_road_target = _is_off_road(point)
	_may_turn_round = may_turn_round
	_agent.target_position = point
	_reset_manoeuvre_state()


## Whether [param point] is somewhere this vehicle has no legal route to -- off its own
## navigation layer, which in this district means a pavement, a verge or a lawn.
##
## **Asked with `map_get_path`.** `map_get_closest_point` is the obvious call and it is
## the wrong one: it takes no layer filter and both navigation regions share one map, so
## it answers 0.00m for a point in the middle of a pavement and this would return false
## everywhere. Only the path query filters by layer. The same trap is written up over
## [method _passing_line], and it has now caught two things in this file.
func _is_off_road(point: Vector3) -> bool:
	if _agent == null:
		return false
	var map := get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(
		map, global_position, point, true, _agent.navigation_layers)
	if path.is_empty():
		return true
	var end := path[path.size() - 1]
	return Vector2(end.x - point.x, end.z - point.z).length() > off_road_margin


func stop_navigating() -> void:
	_navigating = false
	_reset_manoeuvre_state()


func is_navigating() -> bool:
	return _navigating


## Straight-line distance left to run, or 0 when not going anywhere.
func remaining_distance() -> float:
	if not _navigating:
		return 0.0
	return Vector2(move_target.x - global_position.x, move_target.z - global_position.z).length()


func respawn() -> void:
	super()
	velocity = Vector3.ZERO
	forward_speed = 0.0
	_steer_angle = 0.0
	_navigating = false
	_reset_manoeuvre_state()


## Speed for the HUD, in km/h.
func speed_kmh() -> float:
	return absf(forward_speed) * 3.6


func icon() -> StringName:
	return &"ambulance" if service == Service.MEDICAL else &"car"


## True while the current order is a shout rather than routine driving. Blue lights and
## the right to exceed the limit both hang off this, and both belong to the *order* --
## the vehicle has no way of knowing on its own whether it is going to something or
## coming back from it.
func is_responding() -> bool:
	var order := current_order()
	return order == null or order.is_emergency()


## The speed to cruise at. A vehicle not on a shout holds the limit like everyone else;
## corner braking still applies on top, and takes whichever is lower.
func _cruise_ceiling() -> float:
	return max_speed if is_responding() else minf(legal_speed, max_speed)


func _build_abilities() -> Array[Ability]:
	var list: Array[Ability] = [MoveAbility.new()]
	# Collect is the *paramedic's* verb now -- the stretcher run in StretcherOrder --
	# because this vehicle cannot leave the road and a casualty is usually off it.
	# The ambulance still carries them (`stretchers`, load_casualty); it just no
	# longer drives at them.
	#
	# Escort stays on the patrol car: the director only opens crime calls against a
	# kerb, so the car can always pull up within its reach.
	if service == Service.POLICE:
		list.append(LoadSuspectAbility.new())
	list.append(UnloadAbility.new())
	list.append(StopAbility.new())
	# Ambient traffic gets its abilities from here too, and a taxi has no station to go
	# back to -- nor a lightbar or a siren. Nothing can select one, but an empty roster
	# entry would still be wrong.
	if service != Service.NONE:
		list.append(LightsAbility.new())
		list.append(SirenAbility.new())
		list.append(ReturnAbility.new())
	return list


# --- Crew --------------------------------------------------------------------

func has_free_seat() -> bool:
	return crew.size() < seats


## Takes a person aboard. Returns false if the seats filled up while they walked over.
func take_aboard(person: Person) -> bool:
	if not has_free_seat() or crew.has(person):
		return false
	crew.append(person)
	open_doors()
	return true


# --- Water ---------------------------------------------------------------------

## Takes water out of the tank. Called by the crew working off this appliance.
func draw_water(amount: float) -> void:
	water = clampf(water - amount / maxf(tank_capacity, 0.01), 0.0, 1.0)


func has_water() -> bool:
	return carries_water and water > 0.0


## Refills while stood still beside a hydrant, or anywhere on the station forecourt.
## Standing still is required deliberately: an engine that topped up while driving
## past a hydrant would make the tank a formality rather than a reason to park.
func _update_water(delta: float) -> void:
	is_refilling = false
	if not carries_water or water >= 1.0 or absf(forward_speed) > 0.5:
		return
	var supply := Hydrant.nearest(self, global_position, hydrant_reach) != null
	if not supply:
		var home := get_tree().get_first_node_in_group(Station.GROUP) as Station
		supply = home != null and home.is_home(global_position)
	if supply:
		is_refilling = true
		water = minf(water + refill_per_second * delta, 1.0)


# --- Transport ---------------------------------------------------------------

func has_stretcher_space() -> bool:
	return casualties.size() < stretchers


func has_cell_space() -> bool:
	return suspects.size() < cells


## Puts a detained suspect in the back. False if the cell filled up on the way over.
func load_suspect(suspect: Suspect) -> bool:
	if not has_cell_space() or suspects.has(suspect):
		return false
	suspects.append(suspect)
	open_doors()
	return true


## Books everyone in the back in. Called by [Station] when the vehicle drives home.
func deliver_suspects() -> int:
	var carried := suspects.duplicate()
	suspects.clear()
	if not carried.is_empty():
		open_doors()
	for suspect in carried:
		if is_instance_valid(suspect):
			suspect.deliver()
	return carried.size()


## Claims a stretcher. False if it filled up while the vehicle was driving over.
func load_casualty(casualty: Casualty) -> bool:
	if not has_stretcher_space() or casualties.has(casualty):
		return false
	casualties.append(casualty)
	open_doors()
	return true


## Hands over everyone aboard. Called by Hospital when the vehicle drives in.
func deliver_casualties() -> int:
	var carried := casualties.duplicate()
	casualties.clear()
	if not carried.is_empty():
		open_doors()
	for casualty in carried:
		if is_instance_valid(casualty):
			casualty.deliver()
	return carried.size()


## Turns everyone out, spread behind the vehicle.
func unload() -> void:
	if not crew.is_empty():
		open_doors()
	var leaving := crew.duplicate()
	crew.clear()
	for i in leaving.size():
		var person: Person = leaving[i]
		if is_instance_valid(person):
			person.disembark(_dismount_point(i))


## A spot behind the car, alternating sides, snapped onto the navigation mesh so
## nobody is ever put down inside a wall.
func _dismount_point(index: int) -> Vector3:
	var side := 1.0 if index % 2 == 0 else -1.0
	var row := index / 2  # integer division: two per row, then step further out
	var sideways := side * dismount_side * float(1 + row)
	var spot := global_position + global_basis.z * dismount_back + global_basis.x * sideways
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spot)


func _reset_manoeuvre_state() -> void:
	_reversing = false
	_stuck_time = 0.0
	_escape_time = 0.0
	_failed_escapes = 0
	_held_time = 0.0


# --- Frame -------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	_update_water(delta)
	forward_speed = velocity.dot(-global_basis.z)

	if _navigating:
		_update_autopilot(delta)
	else:
		_park()

	_update_steering(delta)
	_update_drive(delta)
	if is_on_floor():
		_apply_yaw(delta)

	# Rebuild velocity against the *new* heading so the car follows where it points,
	# keeping only the sideways component that grip has not yet scrubbed off.
	var forward := -global_basis.z
	var right := global_basis.x
	var lateral := velocity.dot(right)
	var lateral_grip := (handbrake_grip if handbrake_input else grip) * grip_scale
	lateral = move_toward(lateral, 0.0, lateral_grip * delta)

	var vertical := velocity.y
	velocity = forward * forward_speed + right * lateral
	velocity.y = 0.0 if is_on_floor() and vertical < 0.0 else vertical - gravity * delta

	var before := velocity
	move_and_slide()
	_take_damage(before)
	_push_dynamic_bodies()
	_keep_on_the_map(delta)
	# After the damage read, which walks this frame's slide collisions -- the climb only
	# uses `test_move`, so it cannot disturb them, but the ordering says which is the
	# record of what happened and which is a correction on top of it.
	_climb_kerb()

	# A slide or a wall knocks the real speed down; feed that back so the next frame
	# accelerates from what actually happened rather than from what we asked for.
	# Clamped because this is engine-driven speed: whatever a collision does to the
	# car, the drivetrain still cannot propel it faster than its own top speed.
	forward_speed = clampf(velocity.dot(-global_basis.z), -max_reverse_speed, max_speed)

	_update_visuals(delta)


# --- Autopilot ---------------------------------------------------------------

func _update_autopilot(delta: float) -> void:
	var to_target := move_target - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	# is_navigation_finished() also covers a destination clicked off the navmesh, which
	# the agent clamps to the nearest reachable point -- **and that is exactly why a car
	# sent onto a pavement never used to move at all.** The agent declares itself
	# finished on the first frame, before a wheel turns, so the order completed and the
	# player saw a car that ignored the click. When the destination is deliberately off
	# the road the agent has nothing useful to say about it and the car drives at the
	# point itself; `to_point` falls back to the destination below for the same reason.
	if distance <= arrive_radius or (_agent.is_navigation_finished() and not _off_road_target):
		_arrive()
		return

	# Steer at the next corner of the navigation path rather than straight at the
	# destination, so buildings and crates get driven around instead of into.
	var steer_point := _agent.get_next_path_position()
	var to_point := steer_point - global_position
	to_point.y = 0.0
	if to_point.length() < 0.5:
		# Path not solved yet this frame; head for the destination in the meantime.
		to_point = to_target

	var forward := -global_basis.z
	forward.y = 0.0

	# Anything in the way is either passed or queued behind. Vehicles are solid to
	# each other, so an autopilot that ignored them would simply drive into one.
	var ceiling := _cruise_ceiling()
	var blocker := _vehicle_in_the_way(forward)
	if blocker != null:
		var pass_point := _passing_line(forward, blocker)
		if pass_point == Vector3.INF:
			# No gap: hold station behind them. Their speed, not a stop, so a
			# rolling queue keeps rolling.
			ceiling = minf(ceiling, maxf(blocker.forward_speed, 0.0))
			is_avoiding = false
			# **How long it has been someone else's speed.** A unit crawling behind a taxi
			# at 3 m/s with a 25 m/s ceiling is stuck by any useful measure, and nothing
			# saw it: the give-up timer watches for *no progress*, and crawling is
			# progress, so it reset for ever and the reroute never fired.
			_held_time += delta
		else:
			to_point = pass_point - global_position
			to_point.y = 0.0
			ceiling = minf(ceiling, passing_speed)
			is_avoiding = true
			# Passing is not being held: it is getting past.
			_held_time = _cooled(_held_time, delta)
	else:
		is_avoiding = false
		_held_time = _cooled(_held_time, delta)

	# Positive means the target is to the left, matching the sign of steer_input.
	var heading_error := forward.signed_angle_to(to_point, Vector3.UP)

	_update_escape(delta)
	_update_reverse_latch(heading_error, distance)
	# **The last few metres onto a verge are driven, not manoeuvred.** Everything that
	# swings a nose round or backs out of trouble is built for streets, and none of it
	# understands a destination that is not on one: measured, a car that had just climbed
	# onto the pavement promptly reversed off it at 8 m/s, drove round, climbed again,
	# and repeated -- 30 lifts in one journey, ending back on the road 5.3m short of a
	# target it had already reached. The car is a few metres from a spot it can see, so
	# it goes there.
	if _off_road_target and distance < off_road_approach:
		_reversing = false
		_escape_time = 0.0
	if _reversing or _escape_time > 0.0:
		# Back out under opposite lock to swing the nose round, like a three-point
		# turn, rather than driving a wide loop to reach something just behind.
		steer_input = clampf(-heading_error * steer_gain, -1.0, 1.0)
		throttle_input = -1.0
		handbrake_input = false
		return

	steer_input = clampf(heading_error * steer_gain, -1.0, 1.0)

	# Ease off for the turn being taken now, for the ones coming up, and for the
	# destination -- whichever is most limiting.
	var turn_factor := lerpf(1.0, corner_speed_ratio,
		clampf(absf(heading_error) / (PI * 0.5), 0.0, 1.0))
	var arrive_factor := clampf(distance / slowdown_distance, 0.0, 1.0)
	_hold_speed(minf(ceiling * minf(turn_factor, arrive_factor),
		_corner_speed_limit()))
	handbrake_input = false


## The vehicle in the way, or null. Latched: a blocker keeps the job until it is
## well clear or plainly no longer ahead, so a car that dips in and out of the cone
## does not set this one weaving.
##
## A group scan rather than a physics probe, for the same reason the traffic's yield
## uses one: a ray would also catch the buildings a car turns towards and would have
## it dodging every corner.
func _vehicle_in_the_way(forward: Vector3) -> Vehicle:
	if not avoids_vehicles or forward.length() < 0.01:
		return null
	forward = forward.normalized()

	var right := forward.cross(Vector3.UP)
	if is_instance_valid(_blocker):
		var held := _blocker.global_position - global_position
		held.y = 0.0
		# Hysteresis on both ends, or the latch chatters at the boundary.
		var ahead := forward.dot(held)
		if ahead > 0.0 and ahead < avoid_lookahead * 1.3 \
				and absf(right.dot(held)) < avoid_width * 1.4:
			return _blocker
	_blocker = null

	var closest := avoid_lookahead
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var offset := other.global_position - global_position
		offset.y = 0.0
		# In the corridor this car is about to sweep: ahead of it, and inside the
		# width of the lane it occupies.
		var ahead := forward.dot(offset)
		if ahead <= 0.0 or ahead > closest:
			continue
		if absf(right.dot(offset)) > avoid_width:
			continue
		closest = ahead
		_blocker = other
	return _blocker


## Where to aim to get past [param blocker], or INF when there is no gap to use.
##
## The near lane first -- overtaking on the left, this district driving on the right
## -- then the other side, for a blocker sitting in the oncoming lane. A line is only a
## gap if the car is allowed to be there and nobody is standing in it, which is what
## stops a pass from swapping one obstruction for a head-on.
##
## **Asked of the vehicle's own navigation layer, not of the whole map.** The comment
## here used to say a line off the road was rejected "for free" by
## `map_get_closest_point`, and it never was: both navigation regions live on the same
## navigation map and that call takes no layer filter, so a point in the middle of a
## pavement comes back **0.00m away** -- a pass. Every line this returned might as well
## have been unchecked in that respect.
##
## What it bought was passing lines aimed over a kerb. A 7cm kerb is a **vertical wall**
## to a box collider: `move_and_slide` has no step-up, so a car driven straight at one
## stops dead against it and oscillates. The line was not merely untidy, it was aimed at
## something solid. (A person's capsule rides straight over the same step, which is why
## the crowd crosses roads happily and nobody noticed.)
##
## **And the loose test is load-bearing, so it stays.** `map_get_path` does take a layer
## filter, and swapping it in -- asking for the nearest point on the vehicle's own layer,
## which is the question this always meant to ask -- was measured and reverted: the one
## car in the road went from passed in 23s to **never got through in 45**, with fourteen
## reverse-and-retry cycles. Aiming a little wide of the carriageway is how the car gets
## round anything at all, and the kerb it is aiming over then keeps it on the road like a
## rail. Tighten this only together with a district a car can actually drive on.
func _passing_line(forward: Vector3, blocker: Vehicle) -> Vector3:
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var map := get_world_3d().navigation_map
	for side: float in [-1.0, 1.0]:
		var aim := global_position + forward * avoid_reach + right * side * avoid_shift
		var reachable := NavigationServer3D.map_get_closest_point(map, aim)
		if Vector2(reachable.x - aim.x, reachable.z - aim.z).length() > avoid_room:
			continue
		if _lane_occupied(aim, blocker):
			continue
		return aim
	return Vector3.INF


## Whether anything on wheels is standing in a candidate passing line.
func _lane_occupied(aim: Vector3, blocker: Vehicle) -> bool:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var offset := other.global_position - aim
		offset.y = 0.0
		# The blocker itself counts: a line that runs through the car being passed
		# is not a way round it.
		if offset.length() < (avoid_clearance if other == blocker else avoid_clearance * 0.8):
			return true
	return false


## Fastest the car may be going *now* and still make the corners it can see coming.
##
## Without this the only cornering rule was `turn_factor` above, which reacts to the
## heading error -- that is, it only slows once the car is already in the corner.
## Approaching a junction down a straight street the error stays near zero, so the car
## arrived at full speed. Grip caps the tightest circle it can hold at
## v^2/max_lateral_accel: 47m at 26m/s, against a 10m junction. It could not physically
## get round, overshot, and had to be re-routed the long way -- an ambulance failed to
## complete a two-street journey at all.
##
## So: walk the path ahead, and for each corner work out the speed it can be taken at
## and how much room is left to shed speed before reaching it.
func _corner_speed_limit() -> float:
	if corner_lookahead <= 0.0:
		return max_speed
	var path := _agent.get_current_navigation_path()
	var index := _agent.get_current_navigation_path_index()
	if path.size() < 2 or index >= path.size():
		return max_speed

	var limit := max_speed
	var travelled := 0.0
	var previous := global_position
	var decel := brake_deceleration * corner_brake_ratio
	var floor_speed := max_speed * corner_speed_ratio

	for i in range(index, path.size() - 1):
		var point := path[i]
		var incoming := point - previous
		travelled += _flat_length(incoming)
		previous = point
		if travelled > corner_lookahead:
			break
		var turn := _flat_angle(incoming, _direction_after(path, i))
		if turn < deg_to_rad(corner_min_degrees):
			continue
		# v^2 = u^2 + 2as, solved for the speed that decays to `through` over
		# `travelled` metres of braking.
		var through := _turn_speed(turn)
		limit = minf(limit, sqrt(through * through + 2.0 * decel * travelled))
	# Never plan slower than the in-corner floor, or a long string of bends creeps.
	return maxf(limit, floor_speed)


## Speed a corner of [param turn] radians can be held at, taken from the car's own
## geometry: the tightest circle its steering can describe, and the grip available to
## hold it. A right angle gets the full-lock speed; anything gentler is interpolated.
func _turn_speed(turn: float) -> float:
	var radius := wheelbase / tan(deg_to_rad(max_steer_degrees))
	var tightest := sqrt(max_lateral_accel * grip_scale * radius)
	return lerpf(max_speed, tightest, clampf(turn / (PI * 0.5), 0.0, 1.0))


## Where the path is heading over the next [member corner_window] metres from vertex
## [param index].
##
## Sampled over a distance rather than to the next vertex, because the navigation mesh
## rounds a right-angle junction into several small bends: a 90 degree turn came
## through as 47 plus 31 degrees over two and a half metres. Taken one bend at a time
## each reads as gentle, the car never slows for the corner it is actually about to
## take, and it arrives at the junction at 20 m/s needing 27 metres of road to turn in.
func _direction_after(path: PackedVector3Array, index: int) -> Vector3:
	var start := path[index]
	var walked := 0.0
	for i in range(index + 1, path.size()):
		walked += _flat_length(path[i] - path[i - 1])
		if walked >= corner_window:
			return path[i] - start
	return path[path.size() - 1] - start


func _flat_length(vector: Vector3) -> float:
	return Vector2(vector.x, vector.z).length()


func _flat_angle(from: Vector3, to: Vector3) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if a.length() < 0.01 or b.length() < 0.01:
		return 0.0
	return absf(a.angle_to(b))


## Watches for the car being pinned against something and backs it off so it can
## take a different line, rather than pushing into the obstacle forever.
##
## "Pinned" is **not the same as stationary**, and reading it that way was a real hole:
## a car pushed off the road by a collision is falling, so its forward speed is
## whatever it was and this never armed. Being off the floor with somewhere to be
## counts too.
func _update_escape(delta: float) -> void:
	var going_nowhere := absf(forward_speed) < 0.3
	if _escape_time > 0.0:
		_escape_time -= delta
		return
	var off_the_ground := not is_on_floor() and is_navigating()
	if going_nowhere or off_the_ground:
		_stuck_time += delta
		if _stuck_time > stuck_timeout:
			_escape_time = escape_duration
			_stuck_time = 0.0
			_failed_escapes += 1
	else:
		_stuck_time = 0.0
		# Moving again, so whatever was tried worked and the tally starts over. This is
		# the branch that keeps a corner from ever accumulating: a car through a bend is
		# under 0.3 m/s for a moment and back over it long before a second escape.
		_failed_escapes = 0


## Puts the car back on the road when the physics engine has thrown it off the world.
##
## Two CharacterBody3Ds have no solver between them: on a deep overlap `move_and_slide`
## depenetrates along the shortest exit axis, and for a box already well inside another
## box that axis can be **downward, through the floor**. Once below the road there is
## nothing to stand on and gravity does the rest -- measured driving into three parked
## cars, the patrol car reached y = -58,356, which is exactly free-fall for the sixty
## seconds it was watched (0.5 * 32 * 60^2). It never recovers on its own, and neither
## the stuck escape nor the navigation agent has any idea it has happened.
##
## So this is a net rather than a cure: remember the last place the car was genuinely
## on the road, and if it ends up below the world put it back there. It cannot fix the
## depenetration -- that is the engine's -- but it makes the failure survivable, which
## a unit the player *paid for* has to be.
func _keep_on_the_map(_delta: float) -> void:
	if global_position.y > FLOOR_FLOOR:
		return
	# Below the world. Put it back on the nearest piece of road, kill the fall, and let
	# whatever order it was on carry on.
	#
	# **The nearest navigation point, not a remembered one.** Remembering the last spot
	# it was settled on was the first attempt and it was worse than the bug: a vehicle
	# that had been somewhere else earlier got teleported back across the district, and
	# in the suite that dropped a fire engine into the middle of an unrelated scene and
	# broke four checks. The navigation mesh already knows where a car may legally
	# stand, and asking it cannot move the car further than it has already fallen.
	fell_off_the_map.emit(self)
	var road := NavigationServer3D.map_get_closest_point(
		get_world_3d().navigation_map, Vector3(global_position.x, 0.0, global_position.z))
	# Just clear of the surface, not lifted: floor_snap_length settles the rest, and
	# a bigger lift is a second small fall every time this fires.
	global_position = Vector3(road.x, road.y + 0.08, road.z)
	velocity = Vector3.ZERO
	forward_speed = 0.0
	_stuck_time = 0.0
	_escape_time = 0.0


## Lifts the car over a low step it has stopped dead against -- a kerb, in practice.
##
## `move_and_slide` has no step-up and the vehicle collider is a **box**, so a 7cm kerb
## is a vertical wall: a car driven at one halts 2.8m short and oscillates. (A person's
## collider is a capsule and its rounded base rides the same step without noticing,
## which is why the crowd has always crossed roads happily.)
##
## **Two earlier attempts at this were built, measured and reverted, and both failed the
## same way**: they changed the *world* -- first a flush pavement, then a 9-degree
## bevel along every kerb -- and world geometry is unconditional. A kerb a wedged car
## can climb is also a kerb a car cornering at 25 m/s climbs, and what came back was
## cars grinding along pavements (328 frames of one corner off the carriageway, 4.9m
## off the drivable mesh) and lane discipline falling apart. The kerb had been doing a
## second job nobody had credited it with: holding cars in their lane through corners,
## for free. The note left behind said there was no middle setting, because a kinematic
## body climbs any slope under `floor_max_angle` at any speed.
##
## That is true of a *slope*. It is not true of a *body*. So the step-up lives here,
## on the vehicle, gated on its state rather than built into the ground: it runs only
## once the car has been pinned for [member climb_after] with somewhere to be. A moving
## car never accumulates that -- the timer only counts while forward speed is under
## 0.3 m/s -- so the kerb stays exactly as solid as it was for every ordinary corner,
## and softens only for a car that has genuinely run out of answers.
##
## Coming back down needs no code: a 7cm drop is gravity's problem and
## `floor_snap_length` settles it, which is also why nothing like the bevel's
## `_back_to_the_road` companion is needed here. The car climbs out, the navigation
## agent still routes it on the road mesh, and it drops off the far side by itself.
func _climb_kerb() -> void:
	# Not while escaping: that manoeuvre reverses away from the obstruction, and a car
	# heading backwards has no business being helped over the thing in front of it.
	# **Being briefly stationary is not being stuck**, and reading it that way is what
	# the first cut of this got wrong. A car braking hard into a corner dips under
	# 0.3 m/s for half a second with its flank against the kerb, qualifies, and climbs
	# -- and the measured result was the bevel's failure returning move for move: the
	# turn into junction 1,3 went from 12.9s to 41.2s with 423 of 2473 frames up on the
	# pavement and 3.3m off the drivable mesh, against the bevel's own 30.6s / 328 /
	# 4.9m. So the bar is the reverse-and-retry manoeuvre having already been tried and
	# failed [member climb_escapes] times over, which a car taking a corner never does.
	if _escape_time > 0.0:
		return
	# **Two ways to earn a climb, and the ordinary one is the player asking.** A car sent
	# somewhere off the road has been told to go there, so the kerb between it and its
	# destination is the obstacle it was ordered through -- no waiting, no tally of
	# failed manoeuvres, and no requirement that the far side be drivable, because the
	# whole point of the order is that it is not.
	#
	# **No waiting** is the part that had to be learned from play. Requiring the stuck
	# timer here as well read as a car that drove up to the kerb, sat there grinding
	# against it until it had been under 0.3 m/s for half a second, and only then hopped
	# up. The timer is there to keep a car cornering hard from climbing, and an explicit
	# off-road destination already settles that question -- so making the player's own
	# order wait for it bought nothing and looked broken. Without it the lift fires off
	# the 1.2m lookahead instead, before the car ever reaches the face.
	#
	# A car with a road destination still earns it the hard way, which is what keeps
	# corners honest.
	if not (_navigating and _off_road_target):
		if _stuck_time < climb_after or _failed_escapes < climb_escapes:
			return
	var along := (global_basis.z if _reversing else -global_basis.z)
	along = Vector3(along.x, 0.0, along.z).normalized() * climb_reach
	var lift := Vector3.UP * climb_height
	# All three, or this is a wall rather than a step: blocked down here, headroom to
	# rise, and clear ground once risen. The third is what keeps a car from climbing
	# another car -- a vehicle is two metres tall, so lifting the nose finds it again.
	if not test_move(global_transform, along):
		return
	if test_move(global_transform, lift):
		return
	if test_move(global_transform.translated(lift), along):
		return
	# And somewhere legal to land. Clearing the step is not enough: a car put down on a
	# pavement is 1.5m off the vehicle navigation mesh, its agent cannot path from
	# there, and it flounders -- measured, a shut street it got past in 11.4s without
	# this became one it had not got past in 30. That is the bevel's failure returning,
	# and the bevel's recovery was not enough to fix it then either. So the step is only
	# climbed towards ground the car could legitimately have driven to.
	#
	# **Asked with `map_get_path`, not `map_get_closest_point`.** The closest-point call
	# takes no layer filter and both navigation regions share one map, so it answers
	# 0.00m for a point in the middle of a pavement. This check was written with it
	# first and was completely vacuous -- it passed everywhere, and the measurement did
	# not budge by a single frame, which is the only reason it was caught. The same trap
	# is written up over `_passing_line`, thirty lines further down this file.
	# Somewhere it is legal to *be*, even when the player asked for it. The waiver below
	# skips the navigation test for a deliberate off-road order -- the whole point of one
	# is that the destination is off the mesh -- but "off the mesh" covers a pavement, a
	# verge and a park lawn, and it also covers the inside of a building. `standable` is
	# the distinction, and it is the same test that stopped fires spreading into houses.
	var footing := CityGrid.tile_at(global_position + along)
	if not CityGrid.standable(footing.x, footing.y):
		return
	if not _off_road_target:
		var landing := global_position + along
		var map := get_world_3d().navigation_map
		var path := NavigationServer3D.map_get_path(
			map, global_position, landing, true, _agent.navigation_layers)
		if path.is_empty():
			return
		var end := path[path.size() - 1]
		if Vector2(end.x - landing.x, end.z - landing.z).length() > climb_landing:
			return
	# **Up *and* forward.** A pure lift drops the car straight back against the face it
	# was trying to clear, and it fires again next frame: measured, 33 climbs on one
	# journey, the car hopping at the kerb and ending back on the road 5.5m short of a
	# target it had briefly reached. The forward part is what puts it *on* the step. It
	# is safe by construction -- the clearance test above has already swept the full
	# `climb_reach` at this height and found it empty, and this moves a fraction of that.
	global_position += lift + along.normalized() * climb_nudge
	climbed.emit(self)


## Whether the road ahead is blocked by something on wheels.
##
## A **wider and longer** look than [method _vehicle_in_the_way], on purpose: that one
## asks "can I pass this?" and answers it within a passing manoeuvre's reach, while this
## asks "is this street shut?", which a car may well be judging from a standstill some way
## short of the obstruction. Measured against a carriageway walled with four cars, the
## passing reach of 14m said the road was clear from 15m back.
@export var blocked_reach := 24.0
@export var blocked_width := 4.5

## Whether something on wheels sits between this car and [param aim].
##
## Measured along the way it is **trying to go**, not the way it happens to be pointing.
## A car that has just been reversed out by its escape manoeuvre faces back down the
## street, so a test against its own bonnet reports a clear road however solid the wall
## in front of it -- which turned a wall of four cars into "nothing is blocking me" and
## stopped the car ever routing round it.
func road_is_blocked(aim: Vector3) -> bool:
	var towards := aim - global_position
	towards.y = 0.0
	if towards.length() < 0.5:
		return false
	var forward := towards.normalized()
	var reach := minf(blocked_reach, towards.length())
	var right := forward.cross(Vector3.UP)
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other == null or other == self:
			continue
		var offset := other.global_position - global_position
		offset.y = 0.0
		var ahead := forward.dot(offset)
		if ahead <= 0.0 or ahead > reach:
			continue
		if absf(right.dot(offset)) <= blocked_width:
			return true
	return false


## What it would cost to put this vehicle straight, in pounds. Never zero for long: the
## station settles it the moment the unit is booked in.
##
## Damage is **money and nothing else**. A dented patrol car steers, brakes and answers
## exactly as it did new, and the career's other sinks already decide what the player can
## afford to own. Taking a unit off the board mid-shift for a scrape would punish the same
## mistake twice, once at the moment it happens and again for the ten minutes afterwards.
var repair_bill := 0

## Emitted when a knock adds to the bill, with what this one cost.
signal took_damage(vehicle: Vehicle, cost: int)

@export_group("Damage")
## Closing speed below which a knock costs nothing. Kerbs, gentle nudges and the shuffle
## of parking are not accidents, and charging for them would mean charging for driving.
@export var damage_floor := 3.0
## Pounds per m/s of closing speed above that floor.
@export var damage_rate := 18.0
## The most a single frame's contact can cost. A deep overlap can report an enormous
## closing speed for one frame; a cap keeps one physics artefact from emptying the purse.
@export var damage_cap := 400


## Charges the bill for anything this frame's slide ran into.
##
## Measured as the speed lost **into the surface** -- the component of the pre-slide
## velocity along the contact normal -- so a glancing scrape down a wall costs little and
## meeting something head-on costs a lot. The floor is excluded: a car is in contact with
## the road every frame it is on it.
func _take_damage(before: Vector3) -> void:
	var cost := 0
	# **A kerb mounted on purpose is not a collision.** On the last few metres of a trip
	# the player ordered off the road, the thing in front of the car is the thing it was
	# told to drive over -- and at 9 m/s the kerb face bills £38, because it is vertical
	# and so passes the floor test below. Charging for obeying an order is a bill the
	# player cannot avoid except by not using the verb. Other *vehicles* still count:
	# nothing here licenses driving through a car to reach a verge.
	var to_target := move_target - global_position
	var excused: bool = _navigating and _off_road_target \
		and Vector2(to_target.x, to_target.z).length() < off_road_approach
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		if normal.y > 0.7:
			continue
		if excused and not (hit.get_collider() is Vehicle):
			continue
		var closing := -before.dot(normal)
		if closing <= damage_floor:
			continue
		cost += int(mini(int((closing - damage_floor) * damage_rate), damage_cap))
	if cost <= 0:
		return
	repair_bill += cost
	took_damage.emit(self, cost)


## Whether the car is deliberately backing up to swing its nose round, as opposed to
## sitting behind something. Public because an order needs to tell the difference: a car
## halfway through a three-point turn is not making progress towards anything and must
## not be mistaken for one that has given up.
## How long this vehicle has been doing somebody else's speed because it cannot get past
## them. Zero the moment it is moving freely again.
## Impatience **cools rather than resets**. A car held behind something is stopped, which
## trips the escape manoeuvre, which reverses it a metre -- and for that second there is no
## blocker in the corridor. Snapping the timer to zero on those frames meant it never
## reached any threshold worth having: it read 0.5s over and over while the car sat there
## for half a minute. It comes off twice as fast as it goes on, so a car that genuinely
## gets clear forgets quickly.
func _cooled(held: float, delta: float) -> float:
	return maxf(held - delta * 2.0, 0.0)


func held_up_for() -> float:
	return _held_time


func is_turning_round() -> bool:
	return _reversing


## Schmitt trigger on the reverse manoeuvre: enter on a large heading error, leave
## only once the nose is well round or the target is no longer close.
func _update_reverse_latch(heading_error: float, distance: float) -> void:
	var trigger := turn_round_range if _may_turn_round else reverse_trigger_distance
	if _reversing:
		if absf(heading_error) < deg_to_rad(reverse_exit_angle_degrees) \
				or distance > trigger * 1.6:
			_reversing = false
	elif absf(heading_error) > deg_to_rad(reverse_angle_degrees) \
			and distance < trigger:
		_reversing = true


func _arrive() -> void:
	steer_input = 0.0
	if absf(forward_speed) > 0.4:
		# Full brake rather than the handbrake, which is deliberately weaker.
		throttle_input = -signf(forward_speed)
		handbrake_input = false
		return
	throttle_input = 0.0
	handbrake_input = true
	_navigating = false


## Bang-bang throttle toward a target speed, with a deadband so it does not chatter.
func _hold_speed(target_speed: float) -> void:
	if forward_speed < target_speed - 0.5:
		throttle_input = 1.0
	elif forward_speed > target_speed + 0.5:
		throttle_input = -1.0
	else:
		throttle_input = 0.0


func _park() -> void:
	throttle_input = 0.0
	steer_input = 0.0
	handbrake_input = true


# --- Motion model ------------------------------------------------------------

## Knocks props out of the way instead of stopping on them. Applied at the contact
## point so a clipped cone spins off rather than sliding away flat.
func _push_dynamic_bodies() -> void:
	var impact := absf(forward_speed)
	if impact < 0.5:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		var strength := minf(impact * push_force, max_push_impulse)
		body.apply_impulse(
			-collision.get_normal() * strength,
			collision.get_position() - body.global_position)


func _update_steering(delta: float) -> void:
	var speed_ratio := clampf(absf(forward_speed) / max_speed, 0.0, 1.0)
	var lock := deg_to_rad(max_steer_degrees) * lerpf(1.0, 1.0 - speed_steer_falloff, speed_ratio)
	var target := steer_input * lock
	var rate := steer_response if not is_zero_approx(steer_input) else steer_return
	_steer_angle = move_toward(_steer_angle, target, rate * delta)
	_steer_angle = clampf(_steer_angle, -lock, lock)


func _update_drive(delta: float) -> void:
	if handbrake_input:
		forward_speed = move_toward(forward_speed, 0.0, handbrake_deceleration * delta)
		return

	if throttle_input > 0.0:
		if forward_speed < -0.5:
			# Still rolling backwards: treat the throttle as the brake first.
			forward_speed = move_toward(forward_speed, 0.0, brake_deceleration * delta)
		else:
			forward_speed = move_toward(forward_speed, max_speed,
				acceleration * throttle_input * delta)
	elif throttle_input < 0.0:
		if forward_speed > 0.5:
			forward_speed = move_toward(forward_speed, 0.0, brake_deceleration * delta)
		else:
			forward_speed = move_toward(forward_speed, -max_reverse_speed,
				acceleration * -throttle_input * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, coast_deceleration * delta)


func _apply_yaw(delta: float) -> void:
	if is_zero_approx(_steer_angle) or absf(forward_speed) < 0.05:
		return
	var yaw_rate := (forward_speed / wheelbase) * tan(_steer_angle)
	# Cap by the lateral acceleration the tyres could plausibly deliver, otherwise the
	# bicycle model spins the car on the spot at speed.
	var yaw_limit := max_lateral_accel * grip_scale / maxf(absf(forward_speed), 1.0)
	rotate_y(clampf(yaw_rate, -yaw_limit, yaw_limit) * delta)


func _update_visuals(delta: float) -> void:
	for wheel in _wheels_steered:
		wheel.rotation.y = _steer_angle

	_wheel_spin = fposmod(_wheel_spin + (forward_speed / wheel_radius) * delta, TAU)
	for mesh in _wheel_meshes:
		mesh.rotation.x = _wheel_spin

	_steering_wheel.transform.basis = _steering_wheel_rest \
		* Basis(Vector3.UP, -_steer_angle * steering_wheel_ratio)

	# Roll away from the corner, pitch back under power and forward under braking.
	var speed_ratio := clampf(absf(forward_speed) / max_speed, 0.0, 1.0)
	var target_roll := deg_to_rad(lean_roll_degrees) * steer_input * speed_ratio
	var target_pitch := deg_to_rad(lean_pitch_degrees) * -throttle_input
	_lean_roll = lerpf(_lean_roll, target_roll, minf(lean_response * delta, 1.0))
	_lean_pitch = lerpf(_lean_pitch, target_pitch, minf(lean_response * delta, 1.0))
	_lean.rotation = Vector3(_lean_pitch, 0.0, _lean_roll)
