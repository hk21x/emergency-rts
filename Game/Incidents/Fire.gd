extends Incident
class_name Fire

## A fire that grows on its own and spreads once established.
##
## This is the clock the player is racing. Left alone, one fire becomes several, and
## each new one starts the same cycle.

const FIRE_GROUP := &"fires"
## Successive spreads are placed a golden angle apart, which scatters them without
## needing a random number generator -- so a test run is reproducible.
const GOLDEN_ANGLE := 2.399963

@export_group("Burning")
## A building alight, rather than a bin or a car at the kerb. Only a firefighter on
## an appliance's hose brings one down -- a patrol car's extinguisher will not touch
## it -- and the freeplay director refuses to open one unless the career owns a fire
## crew, on the same principle that has always applied here: never set the district
## a job the roster cannot answer.
@export var needs_hose := false
## 0 to 1. Fires start small and build.
@export var intensity := 0.3
@export var growth_per_second := 0.05
## How fast one worker knocks it down. Above growth_per_second, or it is unwinnable.
@export var douse_per_second := 0.22

@export_group("Spreading")
## Only an established fire throws off new ones.
@export var spread_threshold := 0.7
@export var spread_interval := 8.0
@export var spread_distance := 5.0
## How many directions to try before letting a spread lapse. A fire wedged against a
## frontage has most of its circle inside the building.
const SPREAD_TRIES := 8
## Never spread onto a fire that already exists nearby.
@export var min_spacing := 3.5
## Total cap across the map, so an unattended fire cannot run away forever.
@export var max_fires := 8

@export_group("Visuals")
@export var min_flame_scale := 0.5
@export var max_flame_scale := 2.4

## The burn, looped and scaled by how much of it there is.
const CRACKLE_STREAM := "res://Game/Audio/crackle.wav"

@onready var _flame: Node3D = $Flame
@onready var _particles: Array[GPUParticles3D] = [$Flames, $Smoke]

var _spread_timer := 0.0
var _spread_index := 0


var _crackle: AudioStreamPlayer3D


func _ready() -> void:
	super()
	add_to_group(FIRE_GROUP)
	# Built here rather than in the scene so every fire -- including the ones a
	# spread clones -- has one without the .tscn having to carry it.
	if ResourceLoader.exists(CRACKLE_STREAM):
		var burn := load(CRACKLE_STREAM) as AudioStreamWAV
		if burn:
			burn.loop_mode = AudioStreamWAV.LOOP_FORWARD
			burn.loop_begin = 0
			burn.loop_end = burn.data.size() / 2
			_crackle = AudioStreamPlayer3D.new()
			_crackle.name = "Crackle"
			_crackle.stream = burn
			_crackle.unit_size = 6.0
			_crackle.max_distance = 40.0
			add_child(_crackle)
			_crackle.play()
	_update_flame()


func _physics_process(delta: float) -> void:
	if not active:
		return
	intensity = minf(intensity + growth_per_second * delta, 1.0)
	_update_flame()

	if intensity < spread_threshold:
		# Knocked back below the threshold, so it has to build again before spreading.
		_spread_timer = 0.0
		return
	_spread_timer += delta
	if _spread_timer >= spread_interval:
		_spread_timer = 0.0
		_spread()


## Knocks the fire down. Extinguished at zero.
func douse(amount: float) -> void:
	if not active:
		return
	intensity -= amount
	if intensity <= 0.0:
		intensity = 0.0
		_finish(true)
		return
	_update_flame()


func describe_state() -> String:
	if intensity >= spread_threshold:
		return "well alight" if not needs_hose else "building well alight"
	if intensity <= 0.3:
		return "nearly out"
	return "burning" if not needs_hose else "building alight"


## Knocking it down fills the bar.
func progress() -> float:
	return clampf(1.0 - intensity, 0.0, 1.0)


func _spread() -> void:
	var fires := get_tree().get_nodes_in_group(FIRE_GROUP)
	if fires.size() >= max_fires:
		return

	# **Somewhere a crew can get to.** The angle alone does not care what it lands on, and
	# a fire against a block's frontage spreading five metres inward lands *inside the
	# building* -- unreachable, undousable, and burning until the call fails. Reported from
	# play. Several angles are tried before giving up, because one blocked direction is no
	# reason to stop a fire spreading in the others.
	var spot := Vector3.INF
	for attempt in SPREAD_TRIES:
		var angle := _spread_index * GOLDEN_ANGLE
		_spread_index += 1
		var candidate := global_position \
			+ Vector3(sin(angle), 0.0, cos(angle)) * spread_distance
		if not _reachable(candidate):
			continue
		var crowded := false
		for node in fires:
			var other := node as Node3D
			if other and other.global_position.distance_to(candidate) < min_spacing:
				crowded = true
				break
		if crowded:
			continue
		spot = candidate
		break
	if spot == Vector3.INF:
		return

	var child: Fire = duplicate()
	child.intensity = 0.2
	child._spread_timer = 0.0
	child._spread_index = 0
	get_parent().add_child(child)
	child.global_position = spot


## Whether a fire could be fought here -- pavement, park or carriageway, all of which a
## firefighter can stand on.
##
## [method CityGrid.standable], **not** `walkable`: the latter is the pedestrian graph's
## question and means only "not in the middle of the road", so it says yes to a building's
## footprint. This fix was written against `walkable` first and did nothing at all -- every
## spread it was meant to reject sailed through, and only a check that could not be made to
## fail gave it away.
func _reachable(spot: Vector3) -> bool:
	var tile := CityGrid.tile_at(spot)
	return CityGrid.standable(tile.x, tile.y)


func _update_flame() -> void:
	if _flame == null:
		return
	var scale := lerpf(min_flame_scale, max_flame_scale, intensity)
	_flame.scale = Vector3(scale, scale, scale)
	_flame.position.y = scale * 0.5

	# The burn is as loud as the fire is big, so knocking one down is audible before
	# it is visible.
	if _crackle:
		_crackle.volume_db = -30.0 + intensity * 18.0

	# Thin the plume out as the fire is knocked down, rather than having it stop dead
	# the instant the last of the intensity goes.
	for particles in _particles:
		particles.amount_ratio = clampf(intensity, 0.12, 1.0)
		particles.scale = Vector3(scale, scale, scale)
