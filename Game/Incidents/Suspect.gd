extends Incident
class_name Suspect

## Somebody causing trouble: pacing about, mouthing off, refusing to move on.
##
## The police half of what [Casualty] is to the medical service, with the same
## three-beat job -- work the scene, load, deliver -- but nothing here runs down on
## a timer. An unattended disturbance is not *lost*, it just carries on while the
## response bonus drains away: the pressure is the score, not a fuse.
##
## Alive, not a statue. Until the police arrive they pace a few metres around where
## the call opened -- along the pedestrian graph, like everyone else on foot -- and
## when an officer starts the arrest they fight it, swinging until the cuffs go on.
## Once detained they walk back to the spot the call opened on and stand quietly,
## which is also what keeps them within the escorting patrol car's kerbside reach.
##
## Every clip here is a one-shot on the shared rig (the *_Loop variants are not in
## the player -- trusting them left the first suspect in a T-pose), so the loop is
## the same restart pattern [Person] uses: when the clip ends, play it again.

const SUSPECT_GROUP := &"suspects"

@export_group("Arrest")
## Fraction of the arrest completed per second of an officer's work.
@export var detain_per_second := 0.25

@export_group("Pacing")
## How far from where the call opened they will wander. Small on purpose: a
## disturbance paces about a spot, it does not leave the scene -- and the escorting
## car's reach is measured from that spot.
@export var wander_radius := 5.5
@export var walk_speed := 1.5
@export var pause_min := 1.0
@export var pause_max := 3.0

@export_group("Visuals")
## Giving an officer-summoning amount of lip. A one-shot, restart-looped.
@export var rowdy_clip := "Idle_Talking"
## Quiet, cuffed, waiting for the car.
@export var calmed_clip := "Idle"
@export var walk_clip := "Walk"
## Alternated while resisting arrest.
@export var fight_clips: Array[String] = ["Punch_Jab", "Punch_Cross"]

@onready var _animation: AnimationPlayer = $Character/AnimationPlayer

## 0 to 1, filled by an officer's work.
var detain_progress := 0.0
## In custody and ready for transport.
var is_detained := false
## Riding in a patrol car: hidden, unpickable, not yet booked in.
var is_loaded := false
## True while resisting an arrest in progress. Derived from detain() being ticked:
## the work refreshes the heat, the heat decays, and no order has to remember to
## switch it off.
var is_fighting := false
## Who is making the arrest, so the swings land on somebody rather than on the air.
## Passed in by [ApprehendOrder] rather than guessed from the nearest officer: the
## order knows, and a scan would pick the wrong one when two officers are on scene.
var arresting: Unit

## Where the call opened. Captured on the first physics tick, because the director
## positions the node *after* adding it -- _ready still stands at the origin.
var _anchor := Vector3.INF
var _target := Vector3.INF
var _pause := 0.0
var _fight_heat := 0.0
var _fight_swing := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super()
	add_to_group(SUSPECT_GROUP)
	# Somebody off the pavement, not the pack's grey mannequin: a disturbance is a
	# member of the public having a bad afternoon.
	_animation = _wear_outfit()
	_rng.seed = hash(name)


func _physics_process(delta: float) -> void:
	if not active or is_loaded:
		return
	if _anchor == Vector3.INF:
		_anchor = global_position
		_pause = _rng.randf_range(pause_min, pause_max)

	_fight_heat = maxf(_fight_heat - delta, 0.0)
	is_fighting = _fight_heat > 0.0 and not is_detained

	if is_fighting:
		_target = Vector3.INF
		_brawl()
		return
	if is_detained:
		# Cuffed: back to the spot the call opened on -- the kerb the patrol car
		# can actually reach -- then stand.
		if _step_towards(_anchor, delta):
			_loop(calmed_clip)
		return

	# The disturbance itself: pace a few metres, stop, give it some more mouth.
	if _target != Vector3.INF:
		if _step_towards(_target, delta):
			_target = Vector3.INF
			_pause = _rng.randf_range(pause_min, pause_max)
		return
	_loop(rowdy_clip)
	_pause -= delta
	if _pause <= 0.0:
		_target = _pick_pace()


## An officer's work. At 1 the suspect is in custody and ready for the car.
## Being worked on is what they fight: each tick refreshes the scuffle, and
## [param by] is who they square up to.
func detain(amount: float, by: Unit = null) -> void:
	if not active or is_detained:
		return
	_fight_heat = 0.5
	if by != null:
		arresting = by
	detain_progress = minf(detain_progress + amount, 1.0)
	if detain_progress >= 1.0:
		is_detained = true
		is_fighting = false
		_fight_heat = 0.0
		arresting = null


func describe_state() -> String:
	# Both of these name the *destination*. "Aboard, en route" was true and useless:
	# the first thing anyone asked after their first arrest was what happens now, and
	# the answer -- drive them to the station -- was nowhere on screen.
	if is_loaded:
		return "aboard, for the station"
	if is_detained:
		return "in custody, needs a patrol car"
	if is_fighting:
		return "resisting arrest"
	if detain_progress > 0.0:
		return "being detained"
	return "causing a disturbance"


## Same stages as the casualty's: worked, then loaded, then booked in.
func progress() -> float:
	if is_loaded:
		return 0.9
	if is_detained:
		return 0.5
	return detain_progress * 0.5


## Climbs into the back of a patrol car. The seat is claimed by
## [method Vehicle.load_suspect] first; this is only the passenger's half of it.
func load_into(_vehicle: Vehicle) -> void:
	if is_loaded or not is_detained:
		return
	is_loaded = true
	visible = false
	$Collision.set_deferred("disabled", true)


## Booked in at the station: the job closes, successfully.
func deliver() -> void:
	_finish(true)


# --- Moving and animating -----------------------------------------------------

## Glides toward [param point], facing travel, walking clip on. True on arrival.
## The body is a StaticBody3D moved by hand, exactly as the stretcher moves a
## casualty -- it collides with nothing, so there is nothing to get wrong.
func _step_towards(point: Vector3, delta: float) -> bool:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() <= 0.25:
		return true
	var step := offset.normalized() * walk_speed * delta
	global_position += step
	_face(point)
	_loop(walk_clip)
	return false


## Turn to look at a world point. Aims the node's -Z, which the Character child's
## 180 yaw turns into the model looking that way -- the same convention (and the
## same trap) as [method Person.face_towards].
func _face(point: Vector3) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return
	rotation.y = atan2(flat.x, flat.z) + PI


## Somewhere legal to pace to: an adjacent tile on the pedestrian graph, kept
## inside the wander radius. A suspect on a tile the graph does not serve -- the
## middle of a road, say, where the tests like to put them -- simply stands still
## and keeps talking.
func _pick_pace() -> Vector3:
	var col := int(floorf((_anchor.x - CityGrid.ORIGIN) / CityGrid.TILE))
	var row := int(floorf((_anchor.z - CityGrid.ORIGIN) / CityGrid.TILE))
	var spots: Array[Vector3] = [_anchor]
	for move in CityGrid.walk_moves(col, row):
		var spot := CityGrid.tile_centre(move.x, move.y)
		if Vector2(spot.x - _anchor.x, spot.z - _anchor.z).length() <= wander_radius:
			spots.append(spot)
	var pick := spots[_rng.randi_range(0, spots.size() - 1)]
	# Scattered a little so the pacing does not retrace one line.
	return pick + Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8))


## The scuffle: squared up to the officer, the two punch one-shots alternated as
## each lands. Facing is re-aimed every frame -- the officer shuffles about while
## working, and a suspect swinging past their shoulder reads as punching the air.
func _brawl() -> void:
	if is_instance_valid(arresting):
		_face(arresting.global_position)
	if _animation == null:
		return
	if _animation.current_animation == "":
		_fight_swing = (_fight_swing + 1) % fight_clips.size()
	var swing := fight_clips[_fight_swing]
	if _animation.current_animation != swing and _animation.has_animation(swing):
		_animation.play(swing, 0.1)


## The restart loop for one-shot clips: play it, and play it again when it ends.
func _loop(clip: String) -> void:
	if _animation == null or not _animation.has_animation(clip):
		return
	if _animation.current_animation == "":
		_animation.play(clip, 0.2)
	elif _animation.current_animation != clip \
			and _animation.current_animation not in fight_clips:
		_animation.play(clip, 0.2)