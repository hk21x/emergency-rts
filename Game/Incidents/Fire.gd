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

## What is burning. A fire is not one thing: a bin at the kerb, a car with a tank in
## it and a building alight are three different jobs, and until August 2026 the only
## difference the game expressed was `needs_hose` plus a couple of rates set inline at
## four call sites in the director.
##
## The kind is what carries that now, and it survives a spread for free: `_spread()`
## clones with `duplicate()`, so a building fire throws off building fire, which is
## right.
enum Kind {
	## A bin, a skip, a pile of rubbish. Small, quick, goes out for anyone -- the job
	## that teaches the verb without punishing a career for learning it.
	BIN,
	## A car at the kerb. Slow to knock down and **it damages what is parked near it**,
	## which is the one fire that costs money to stand next to.
	VEHICLE,
	## A building. Only a crew on a hose touches it, and it spreads hard.
	BUILDING,
	## A substation, a junction box, a charging point. Water on live electrics is worse
	## than useless, and the appliance carries no powder -- so this is the **one fire the
	## fire service cannot fight and the police can**. It is small and it does not spread,
	## because a call that inverts the roster should be a puzzle rather than a punishment.
	ELECTRICAL,
}

## Everything that differs by kind, in one table rather than scattered across the
## director's spawners. `flames` names the FX the plume instances; the pack ships three
## severity tiers and the game used only the largest.
## What actually puts this out.
##
## Not a rate table with an extra column: the wrong agent does **nothing**, the same way
## a patrol car's extinguisher does nothing to a building. Gating is hard everywhere else
## in this game and a fire is no place to start being coy about it -- "slower" is
## invisible at RTS zoom, and a player who cannot tell refusal from slowness learns
## nothing from either.
##
## POWDER is deliberately the broad one. A patrol car carries ABC dry powder, which is
## genuinely multi-class, so the officer who could always take a bin or a kerbside car
## still can. What powder cannot do is a building, and what *water* cannot do is a fuel
## fire -- which is the inversion this brings: on an electrical fire the appliance is the
## wrong tool and the patrol car is the right one.
enum Agent { WATER, FOAM, POWDER }

const AGENT_NAMES := {
	Agent.WATER: "water", Agent.FOAM: "foam", Agent.POWDER: "dry powder",
}

const KINDS := {
	Kind.BIN: {
		"flames": "res://Assets/Particle_FX/Prefabs/FX/FX_Fire_Small_01.tscn",
		"needs_hose": false, "growth": 0.03, "douse": 0.34, "spreads": false,
		"max_flame_scale": 1.2, "agent": Agent.WATER,
	},
	Kind.VEHICLE: {
		"flames": "res://Assets/Particle_FX/Prefabs/FX/FX_Fire_Medium_01.tscn",
		"needs_hose": false, "growth": 0.05, "douse": 0.22, "spreads": true,
		"spread_interval": 8.0, "spread_distance": 5.0, "max_flame_scale": 2.4,
		"agent": Agent.FOAM,
	},
	Kind.BUILDING: {
		"flames": "res://Assets/Particle_FX/Prefabs/FX/FX_Fire_Large_01.tscn",
		"needs_hose": true, "growth": 0.07, "douse": 0.12, "spreads": true,
		"spread_interval": 8.0, "spread_distance": 5.0, "max_flame_scale": 2.4,
		"agent": Agent.WATER,
	},
	Kind.ELECTRICAL: {
		"flames": "res://Assets/Particle_FX/Prefabs/FX/FX_Fire_Small_01.tscn",
		"needs_hose": false, "growth": 0.04, "douse": 0.28, "spreads": false,
		"max_flame_scale": 1.4, "agent": Agent.POWDER,
	},
}

@export_group("Burning")
## Which of the three this is. Settable at any point: the setter re-applies the table
## when the node is already in the tree, so a caller cannot get the order wrong.
##
## It could have been a comment telling callers to set it before `add_child`, and that
## was the first cut -- but `Director._spawn()` adds the node and *then* configures it,
## so every building fire came out as the default and two checks went red saying so. A
## rule that has to be remembered at four call sites is a rule that will be broken.
##
## **The middle tier is the default, and its row is deliberately the numbers the game
## has always used.** A bare `Fire.tscn` is instantiated by the director, by the suite
## and by `_spread()`, so a default that retuned every one of them would have changed a
## dozen behaviours while claiming to add a feature. BIN is gentler than the fire this
## game had; BUILDING is harsher; VEHICLE *is* it, plus the scorching.
@export var kind: Kind = Kind.VEHICLE:
	set(value):
		kind = value
		if is_inside_tree():
			_apply_kind()
			_fx = [$Flames, $Smoke]
			_particles = _emitters()
## A building alight, rather than a bin or a car at the kerb. Only a firefighter on
## an appliance's hose brings one down -- a patrol car's extinguisher will not touch
## it -- and the freeplay director refuses to open one unless the career owns a fire
## crew, on the same principle that has always applied here: never set the district
## a job the roster cannot answer.
@export var needs_hose := false
## What will put this out. Set from the kind's row; see [enum Agent].
var agent: Agent = Agent.WATER
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

@export_group("Scorching")
## How far a vehicle fire reaches to damage what is parked beside it, and what it costs
## per second at full intensity.
##
## **The one fire that costs money to stand next to.** The repair economy, the readout
## and the debrief row all existed already -- this only needed something new to bill.
## What it buys is a reason to think about where the appliance stops: nose-in beside a
## burning car is the convenient place to park and the expensive one.
@export var scorch_range := 4.0
## A tenth of the 9.0 it shipped at -- rescaled with the impact damage_rate, see the
## note there; an appliance working a car fire was billing more than the call paid.
@export var scorch_per_second := 0.9

## How close a person has to be to a fire to be hurt by it, and how fast.
##
## **3.2 is chosen against `ExtinguishOrder.REACH` (5.0), not picked for feel.** A unit
## working a fire closes to REACH and stands there, so a firefighter on the hose is 1.8m
## outside this and never singed; one the player walked *past* the fire, or parked a crew
## on top of, is inside it. That is the whole mechanic: fire does not punish fighting it,
## it punishes standing in it.
##
## The design this preserves is deliberate and predates the harm — `ExtinguishOrder` holds
## a firefighter at work range precisely so the fire service stays playable, and a radius
## at or above REACH would make every building fire a war of attrition against your own
## crew. If REACH ever moves, this must move with it; the suite pins the gap.
@export var singe_range := 3.2
@export var singe_per_second := 0.55

@export_group("Visuals")
@export var min_flame_scale := 0.5
@export var max_flame_scale := 2.4

## The burn, looped and scaled by how much of it there is.
const CRACKLE_STREAM := "res://Game/Audio/crackle.wav"

## The two FX roots. Scale goes on these and **only** these: an emitter's scale is
## inherited by its children, so scaling the roots and their sub-emitters both multiplies
## -- a fire at full intensity would throw embers at 2.4 x 2.4.
## Assigned in [method _ready] **after** the kind has swapped the plume, not `@onready`:
## an onready var resolves before the body runs and would point at the FX that was
## replaced.
var _fx: Array[Node3D] = []
## Every emitter under the two FX, **including their own sub-emitters**.
##
## `Flames` and `Smoke` are instanced from the particle pack and are not one node each:
## the fire carries embers and a ground-spread beneath it. Listing the two roots would
## leave those children at full amount on a fire barely alight, because `amount_ratio`
## does not inherit. Collected rather than named so a pack update that adds an emitter
## is picked up rather than silently ignored.
var _particles: Array[GPUParticles3D] = []

var _spread_timer := 0.0
var _spread_index := 0


var _crackle: AudioStreamPlayer3D


func _ready() -> void:
	super()
	add_to_group(FIRE_GROUP)
	_apply_kind()
	_fx = [$Flames, $Smoke]
	_particles = _emitters()
	# Built here rather than in the scene so every fire -- including the ones a
	# spread clones -- has one without the .tscn having to carry it.
	if ResourceLoader.exists(CRACKLE_STREAM):
		var burn := load(CRACKLE_STREAM) as AudioStreamWAV
		if burn:
			burn.loop_mode = AudioStreamWAV.LOOP_FORWARD
			burn.loop_begin = 0
			burn.loop_end = burn.data.size() / 2
			AudioBuses.ensure()
			_crackle = AudioStreamPlayer3D.new()
			_crackle.name = "Crackle"
			_crackle.bus = AudioBuses.SFX
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

	_scorch(delta)
	_singe(delta)

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


## Says **what it wants putting on it**, not merely how bad it is.
##
## Without this the agent rule is a memory test: a crew drives across the district, finds
## the hose does nothing, and has no way to know why. The board already renders this
## string on the call row, so naming the agent costs no interface at all -- and it is the
## difference between a rule and a trap.
func describe_state() -> String:
	var wants := "" if agent == Agent.WATER else \
		" -- needs %s" % AGENT_NAMES.get(agent, "?")
	if intensity >= spread_threshold:
		return ("well alight" if not needs_hose else "building well alight") + wants
	if intensity <= 0.3:
		return "nearly out" + wants
	return ("burning" if not needs_hose else "building alight") + wants


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


## Bills any vehicle standing too close to a burning car.
##
## Only [constant Kind.VEHICLE] does this. A bin fire is not going to cost anyone a
## repair, and a building fire already has the crew standing off it -- billing there
## would tax the correct way to fight one.
func _scorch(delta: float) -> void:
	if kind != Kind.VEHICLE:
		return
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.service == Unit.Service.NONE:
			continue
		var offset := vehicle.global_position - global_position
		offset.y = 0.0
		var gap := offset.length()
		if gap > scorch_range:
			continue
		# Falls off with distance and scales with how big the fire is, so a car pulled
		# up at the edge of a dying fire is charged pennies and one parked in it is not.
		var bite := (1.0 - gap / scorch_range) * intensity * scorch_per_second * delta
		vehicle.scorch(bite)


## Burns whoever is standing in it.
##
## **The most common call in the game could not hurt you until August 2026.**
## `Hazard._hurt_people()` has always had a complete, tested chain — crew take harm and go
## down, civilians convert to casualties wearing what they were wearing — and it fired only
## when a gas cylinder went off, which is the rarest kind in the table. This is that chain
## pointed at fire, which is the second most common.
##
## Written here rather than shared with `Hazard`: a blast is instantaneous and symmetric,
## a fire is continuous and grows, so the two want different shapes even where they want
## the same outcome. What is copied is the *rule*, and the ordering trap with it.
##
## **Civilians are tested before crew, and that order is load-bearing** — `Civilian extends
## Person`, so a `as Person` cast catches shoppers too, and getting it the wrong way round
## both converts a bystander and down-states them on the same frame.
func _singe(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian == null:
			var crew := node as Person
			if crew == null:
				continue
			var bite := _singe_falloff(crew.global_position)
			if bite > 0.0:
				crew.hurt(bite * singe_per_second * delta)
			continue

		# **Only a fire that has got away catches onlookers.** Below the spread threshold
		# it is a bin fire someone is standing near; above it, it is out of hand. The
		# crowd flees fires perfectly well, so anyone still inside this radius at that
		# size was caught rather than careless.
		if intensity < spread_threshold or _singe_falloff(civilian.global_position) <= 0.0:
			continue
		# The missing child is a civilian by construction and never fodder: converting
		# them frees the body their own report is scanning for, and the search call would
		# quietly close as done. Straight from `Hazard._hurt_people`, same reason.
		if civilian is ChildWanderer:
			continue
		var casualty := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
			.instantiate() as Casualty
		if casualty == null:
			continue
		casualty.outfit = civilian.outfit_scene()
		casualty.flavour = "Caught by the fire"
		get_parent().add_child(casualty)
		casualty.global_position = civilian.global_position
		civilian.queue_free()


## How hard the fire bites at [param point]: 0 outside the radius, 1 in the middle of a
## fire at full intensity. Scaled by `intensity` so a dying fire stops hurting before it
## stops burning.
func _singe_falloff(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	var gap := offset.length()
	if gap >= singe_range:
		return 0.0
	return (1.0 - gap / singe_range) * intensity


## Reads the kind's row and applies it: the rates, whether a hose is needed, whether it
## spreads at all, and which plume it wears.
##
## The plume is swapped rather than configured, because the pack ships three fires and
## they differ in more than scale -- the small one has no ground-spread emitter. Guarded
## on the path so a fire cloned by `_spread()`, which already carries the right plume,
## does not free and rebuild one for nothing.
func _apply_kind() -> void:
	var row: Dictionary = KINDS.get(kind, KINDS[Kind.BUILDING])
	needs_hose = bool(row["needs_hose"])
	agent = row["agent"] as Agent
	growth_per_second = float(row["growth"])
	douse_per_second = float(row["douse"])
	max_flame_scale = float(row["max_flame_scale"])
	if bool(row["spreads"]):
		spread_interval = float(row["spread_interval"])
		spread_distance = float(row["spread_distance"])
	else:
		# Above 1.0, so the threshold can never be met and the timer never arms. Cheaper
		# and harder to get wrong than a second flag every spread site would have to ask.
		spread_threshold = 2.0

	var plume := get_node_or_null("Flames") as Node3D
	var wanted := str(row["flames"])
	if plume != null and plume.scene_file_path == wanted:
		return
	var replacement := (load(wanted) as PackedScene).instantiate() as Node3D
	replacement.name = "Flames"
	if plume != null:
		replacement.transform = plume.transform
		plume.free()
	add_child(replacement)


## The emitters under this fire, roots first.
func _emitters() -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for root in [$Flames, $Smoke]:
		if root is GPUParticles3D:
			found.append(root)
		for child in (root as Node).find_children("*", "GPUParticles3D", true, false):
			found.append(child as GPUParticles3D)
	return found


func _update_flame() -> void:
	var scale := lerpf(min_flame_scale, max_flame_scale, intensity)
	for fx in _fx:
		fx.scale = Vector3(scale, scale, scale)

	# The burn is as loud as the fire is big, so knocking one down is audible before
	# it is visible.
	if _crackle:
		_crackle.volume_db = -30.0 + intensity * 18.0

	# Thin the plume out as the fire is knocked down, rather than having it stop dead
	# the instant the last of the intensity goes. Every emitter, sub-emitters included --
	# `amount_ratio` is not inherited the way scale is, so a child left alone keeps
	# throwing a full complement of embers off a fire that is nearly out.
	for particles in _particles:
		particles.amount_ratio = clampf(intensity, 0.12, 1.0)
