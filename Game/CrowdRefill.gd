extends Node
class_name CrowdRefill

## Puts people back on the pavements as the district loses them.
##
## Every medical call takes a shopper **permanently** -- the body on the pavement is the
## person who was standing there, which is the point of taking one rather than spawning a
## stranger -- and until this, nothing replaced them. A long career quietly emptied the
## district, and once it was empty the call had nobody left to take and fell back to
## conjuring a casualty from thin air, which is the very thing taking a civilian exists to
## avoid.
##
## It only ever tops the crowd back up to the size the map was built with, so on a
## district nothing has happened to it does nothing at all.
##
## A passive watcher, like [Mission] and [CallBoard]: it finds the crowd rather than being
## handed it, and nothing else has to know it exists.

## The container the map's crowd lives under.
@export var crowd_path := NodePath("../Crowd")

## Seconds between arrivals. Slow on purpose -- a district that refills faster than it
## empties is a district with a queue of people walking out of thin air, and one shopper
## every half minute comfortably outpaces a shift's medical calls.
@export var every := 30.0

## How far a new arrival must be from the camera. Somebody appearing in shot is worse than
## a slightly thinner pavement, so an arrival that cannot be placed out of sight simply
## waits for the next one.
@export var out_of_shot := 55.0

## And how far from anything going on. A shopper strolling out of nowhere beside a fire
## reads as a bug whether or not it is one.
@export var clear_of_incidents := 18.0

## The size to keep the crowd at, and the outfits it was built from. Both read off the map
## at startup rather than configured: the district decides how many people it has.
var target := 0
var _outfits: Array[String] = []
var _due := 0.0
var _rng := RandomNumberGenerator.new()
## Arrivals since the map loaded. Public so a check can assert the refill happened without
## counting heads at exactly the right moment.
var arrivals := 0


func _ready() -> void:
	_rng.seed = hash(name)
	var crowd := get_node_or_null(crowd_path)
	if crowd == null:
		return
	for child in crowd.get_children():
		var civilian := child as Civilian
		if civilian == null:
			continue
		target += 1
		if not _outfits.has(civilian.scene_file_path):
			_outfits.append(civilian.scene_file_path)
	# **A packed scene may not remember where its children came from.** The crowd is
	# instanced into Playground.tscn by the generator, and `scene_file_path` survives that
	# only if each child was stored as an instance rather than flattened. When it has not,
	# the district is asked directly.
	if _outfits.is_empty():
		_outfits = _civilian_scenes()
	_due = every


## Every civilian scene the project ships, for when the crowd cannot say what it is made
## of. Read from disk rather than listed here, so adding an outfit needs no edit.
func _civilian_scenes() -> Array[String]:
	var found: Array[String] = []
	var folder := DirAccess.open("res://Game/Civilians")
	if folder == null:
		return found
	for file in folder.get_files():
		# An exported project serves `.tscn` as `.remap`; both name the same scene.
		var scene := file.trim_suffix(".remap")
		if scene.ends_with(".tscn"):
			found.append("res://Game/Civilians/" + scene)
	return found


func _process(delta: float) -> void:
	if target <= 0 or _outfits.is_empty():
		return
	# Never longer than the current gap. A countdown started at the old interval ignores a
	# new one entirely -- set `every` to a twentieth of a second and the next arrival is
	# still half a minute away -- which is the same trap [StuckLog]'s cooldown fell into.
	_due = minf(_due - delta, every)
	if _due > 0.0:
		return
	_due = every
	var crowd := get_node_or_null(crowd_path)
	if crowd == null or _living(crowd) >= target:
		return
	var spot := _somewhere_out_of_sight()
	if spot == Vector3.INF:
		return
	var arrival := (load(_outfits[_rng.randi() % _outfits.size()]) as PackedScene) \
		.instantiate() as Civilian
	if arrival == null:
		return
	crowd.add_child(arrival)
	arrival.global_position = spot
	arrivals += 1


## How many of the crowd are still on their feet. Counted rather than tracked, because a
## civilian can leave by more routes than the medical call -- a scene can clear them, and
## the suite removes them wholesale.
func _living(crowd: Node) -> int:
	var alive := 0
	for child in crowd.get_children():
		if child is Civilian and is_instance_valid(child):
			alive += 1
	return alive


## A pavement tile far enough from the camera and from anything happening, or INF if the
## district offers nowhere suitable this time round.
func _somewhere_out_of_sight() -> Vector3:
	var eye := Vector3.INF
	var camera := get_viewport().get_camera_3d()
	if camera:
		eye = camera.global_position
	var points := CityGrid.pavement_points()
	if points.is_empty():
		return Vector3.INF
	# A handful of tries rather than a sorted search: the pavement ring is thousands of
	# tiles and any of them will do, so failing this turn and arriving next is cheaper
	# than ranking them.
	for attempt in 12:
		var spot: Vector3 = points[_rng.randi() % points.size()]
		if eye != Vector3.INF and _flat(spot - eye) < out_of_shot:
			continue
		if _near_something_happening(spot):
			continue
		return spot
	return Vector3.INF


func _near_something_happening(spot: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var incident := node as Node3D
		if incident and _flat(incident.global_position - spot) < clear_of_incidents:
			return true
	return false


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
