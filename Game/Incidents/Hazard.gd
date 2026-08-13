extends Incident
class_name Hazard

## A pressure cylinder that cooks off if a fire is left burning beside it.
##
## The first thing in the district that hurts back. Everything else here is a job waiting
## to be done -- a fire grows, a casualty declines, a suspect stands about -- and the
## worst that happens is a call fails. A hazard **acts**: it damages the vehicles parked
## near it, hurts the people standing near it, and throws fires of its own.
##
## What makes it a decision rather than a timer is that it is beaten two ways. Cool it
## with a hose, which is a firefighter standing still doing nothing about the fire; or put
## the fire out first and let it cool on its own. Both are right in different scenes, and
## the one that is wrong is treating it as scenery.
##
## The blast is composed rather than authored: no pack on disk ships an explosion, so it
## is a large fire flash, a dust cloud, a synthesised boom, and the consequences.

## Its own group, beside the base class's `incidents`, exactly as Fire and Casualty do.
const HAZARD_GROUP := &"hazards"

@export_group("Heating")
## How far a fire has to be before it stops cooking this.
@export var heat_range := 7.0
## Heat gained per second from a fire at full intensity, at zero distance. A fire further
## off or further down contributes proportionally less.
@export var heat_per_second := 0.075
## Heat shed per second with nothing burning near it. Well below the gain, so walking
## away from a warm cylinder is not a plan -- but not zero, so putting the fire out is a
## real answer and not merely a way of freezing the problem.
@export var cool_per_second := 0.03
## What a hose takes off per second. See [CoolOrder].
@export var hose_per_second := 0.22

@export_group("Blast")
## Everything within this takes the full effect, falling off to nothing at twice it.
@export var blast_range := 9.0
## Repair cost to a vehicle at the centre of it.
@export var blast_damage := 260.0
## Condition taken off a crew member at the centre of it, falling off the same way.
##
## **Above 1.0 on purpose**, because it is scaled by the same distance falloff as the
## damage: at 0.85 the strongest possible hit left a firefighter on 0.22 and standing, so
## a cylinder going off in somebody's face was survivable every time. At 1.2 the centre
## puts them down and the edge of the radius only hurts -- which is the gradient the
## feature is for. The player who parked the appliance beside a cooking cylinder loses
## the crew member who was working it.
@export var blast_harm := 1.2
## How many fires it throws, and how far.
@export var blast_fires := 2
@export var blast_fire_distance := 5.0

## 0 to 1. At 1 it goes.
var heat := 0.0
## Set while a crew is working on it, so [method describe_state] can say so and the board
## does not read "about to go" at somebody who is dealing with it.
var is_cooling := false
## True once this has actually been in danger -- heated, or with a fire in range.
##
## Without it a hazard resolves on its first frame: `Director._spawn_gas_leak()` adds the
## cylinder and *then* the fire beside it, so for a frame or two it is stone cold with
## nothing near it, which is indistinguishable from having been made safe.
var _was_threatened := false

@onready var _marker: MeshInstance3D = $Marker
var _cool_heat := 0.0


func _ready() -> void:
	super()
	add_to_group(HAZARD_GROUP)


func _physics_process(delta: float) -> void:
	if not active:
		return
	# The cooling flag is refreshed by the order every frame it works and decays here,
	# so nothing has to remember to switch it off -- the same shape Suspect uses for
	# `is_fighting`.
	_cool_heat = maxf(_cool_heat - delta, 0.0)
	is_cooling = _cool_heat > 0.0

	# **Checked before anything is allowed to take heat off.** At the limit it goes, and
	# that has to be true however the limit was reached -- the first cut cooled first and
	# tested second, so a cylinder sitting at exactly 1.0 shed a fraction and survived.
	# In play the two happen in the same frame and it never showed; a check that set the
	# heat directly found it immediately.
	if heat >= 1.0:
		_explode()
		return

	var from_fire := _nearest_fire_heat()
	if from_fire > 0.0:
		heat = minf(heat + from_fire * delta, 1.0)
	else:
		heat = maxf(heat - cool_per_second * delta, 0.0)
	_update_marker()
	if heat >= 1.0:
		_explode()
		return

	# **Made safe: cold, and nothing left burning near it.**
	#
	# This was missing entirely until August 2026, and the omission is worth recording
	# because of how it hid. `_finish(false)` on the blast was the *only* exit -- so a
	# gas leak could be beaten perfectly and the call stayed on the board for ever, the
	# shift could never end, and `Mission.HAZARD_POINTS` was unreachable. Three checks
	# covered this incident and every one of them tested a *mechanism* -- it heats, it
	# cools, it goes bang -- and not one asked whether the job could be finished.
	#
	# It surfaced only because adding a later call kind reshuffled a seeded roll and put
	# a gas leak in front of a shift-end test.
	_was_threatened = _was_threatened or from_fire > 0.0 or heat > 0.0
	if _was_threatened and heat <= 0.0 and from_fire <= 0.0:
		_finish(true)


## Heat per second being delivered by whatever is burning nearby, or 0 if nothing is.
##
## Scaled by the fire's own intensity as well as its distance, so a fire that is being
## knocked down stops threatening this before it is fully out -- which is what makes
## "put the fire out first" a real answer rather than a race that is always lost.
func _nearest_fire_heat() -> float:
	var worst := 0.0
	for node in get_tree().get_nodes_in_group(Fire.FIRE_GROUP):
		var fire := node as Fire
		if fire == null or not fire.active:
			continue
		var offset := fire.global_position - global_position
		offset.y = 0.0
		var gap := offset.length()
		if gap > heat_range:
			continue
		worst = maxf(worst, (1.0 - gap / heat_range) * fire.intensity * heat_per_second)
	return worst


## Takes heat off. Called by [CoolOrder] every frame it is worked.
func cool(amount: float) -> void:
	if not active:
		return
	_cool_heat = 0.5
	heat = maxf(heat - amount, 0.0)
	_update_marker()


## Amber when cold, red when it is about to go. The ring is the only warning a player
## gets at RTS zoom, and a number on the call row is not one.
func _update_marker() -> void:
	if _marker == null:
		return
	var coat := _marker.material_override as StandardMaterial3D
	if coat:
		coat.albedo_color = Color(1.0, lerpf(0.66, 0.1, heat), lerpf(0.15, 0.1, heat), 0.8)


## The blast. Damage, casualties, fires, a flash and a bang -- then the hazard is gone
## and its call has failed.
func _explode() -> void:
	if not active:
		return
	var here := global_position
	var parent := get_parent()
	_hurt_vehicles(here)
	_hurt_people(here)
	_light_fires(here, parent)
	_flash(here, parent)
	# A cylinder that goes off is a job that was not done, whatever else was going well.
	_finish(false)


func _hurt_vehicles(here: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.service == Unit.Service.NONE:
			continue
		var share := _falloff(vehicle.global_position, here)
		if share > 0.0:
			vehicle.scorch(blast_damage * share)


## Anyone standing in it is hurt. Takes the civilian who was there rather than conjuring a
## stranger, which is the same thing a medical call does and for the same reason: the
## person on the pavement is the person it happened to.
func _hurt_people(here: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		# **The crowd is tested first, and this order is load-bearing.** `Civilian extends
		# Person`, so a `as Person` cast catches shoppers too -- get these the wrong way
		# round and a blast both converts a bystander and down-states them.
		var civilian := node as Civilian
		if civilian == null:
			var crew := node as Person
			if crew:
				crew.hurt(blast_harm * _falloff(crew.global_position, here))
			continue
		if _falloff(civilian.global_position, here) <= 0.0:
			continue
		var casualty := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
			.instantiate() as Casualty
		if casualty == null:
			continue
		casualty.outfit = civilian.outfit_scene()
		casualty.flavour = "Explosion, casualties reported"
		get_parent().add_child(casualty)
		casualty.global_position = civilian.global_position
		civilian.queue_free()


## Throws fires, through the same standable test a spread uses. A blast that lit the
## inside of a building would be a call nobody could answer, which is the one rule every
## placement in this game funnels through.
func _light_fires(here: Vector3, parent: Node) -> void:
	if parent == null:
		return
	var placed := 0
	for i in 8:
		if placed >= blast_fires:
			return
		var angle := float(i) * Fire.GOLDEN_ANGLE
		var spot := here + Vector3(sin(angle), 0.0, cos(angle)) * blast_fire_distance
		var tile := CityGrid.tile_at(spot)
		if not CityGrid.standable(tile.x, tile.y):
			continue
		var fire := (load("res://Game/Incidents/Fire.tscn") as PackedScene) \
			.instantiate() as Fire
		if fire == null:
			return
		parent.add_child(fire)
		fire.kind = Fire.Kind.BIN
		fire.global_position = spot
		fire.intensity = 0.35
		placed += 1


## A flash and a dust cloud, freed on a timer. No pack on disk ships an explosion, so
## this is the largest fire the particle pack has plus its dust, both one-shot.
func _flash(here: Vector3, parent: Node) -> void:
	if parent == null:
		return
	for path in ["res://Assets/Particle_FX/Prefabs/FX/FX_Fire_Large_01.tscn",
			"res://Assets/Particle_FX/Prefabs/FX/FX_Dust_01.tscn"]:
		if not ResourceLoader.exists(path):
			continue
		var puff := (load(path) as PackedScene).instantiate() as Node3D
		if puff == null:
			continue
		parent.add_child(puff)
		puff.global_position = here
		puff.scale = Vector3(2.5, 2.5, 2.5)
		var timer := get_tree().create_timer(2.5)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(puff):
				puff.queue_free())


## 1 at the centre, 0 at twice the blast range, linear between. Flat, so something on a
## roof is not spared by being above it.
func _falloff(point: Vector3, here: Vector3) -> float:
	var offset := point - here
	offset.y = 0.0
	var gap := offset.length()
	if gap >= blast_range * 2.0:
		return 0.0
	return clampf(1.0 - gap / (blast_range * 2.0), 0.0, 1.0)


func describe_state() -> String:
	if is_cooling:
		return "being cooled"
	if not _was_threatened:
		return "not alight yet"
	if heat >= 0.75:
		return "about to go"
	if heat >= 0.35:
		return "venting"
	if heat > 0.0:
		return "warming"
	return "safe for now"


## Drains as it heats, so the bar on the call row empties as the thing gets worse -- the
## same shape a casualty's health has, and for the same reason: a bar that filled toward
## the explosion would read as progress.
func progress() -> float:
	return clampf(1.0 - heat, 0.0, 1.0)
