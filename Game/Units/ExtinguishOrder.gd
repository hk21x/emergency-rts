extends WorkOrder
class_name ExtinguishOrder

## Put a fire out. Hose reach is why this order has a range at all.
##
## How *fast* depends on who is holding the hose, and on whether it is a hose at all:
##
## - A **firefighter within [constant HOSE_REACH] of a fire appliance** is on the
##   engine's hose and works at [constant HOSE_RATE] -- comfortably the fastest thing
##   in the game, and faster than the fire's own baseline. Parking the engine at the
##   scene is therefore part of the job rather than a formality, which is the whole
##   reason an appliance is more than a bus for the crew.
## - A **firefighter away from their engine** has only what they can carry, and drops
##   to [constant OFF_HOSE_RATE] of it.
## - **Police** carry the extinguisher a patrol car actually carries: they keep the
##   fires they always could -- a bin, a kerbside car -- at [constant POLICE_RATE],
##   and a building does not yield to them at all (see [member Fire.needs_hose]).

const REACH := 5.0
## How far a hose runs from the appliance.
const HOSE_REACH := 18.0
## Rate multipliers on the fire's own douse_per_second. The gap between them is what
## makes the engine worth driving.
##
## The hose is deliberately **above 1.0**: it is a pressurised line off a tank, not
## the baseline everything else is a fraction of. It was 1.0 until August 2026, which
## made a building fire eleven seconds a node -- and buildings spread, so a real
## building call was a minute of standing still holding a hose. At 1.8 the same node
## is under four seconds and the appliance matters *more* than it did, because the gap
## to a crew working off it went from 2.9x to 5.1x.
const HOSE_RATE := 1.8
const OFF_HOSE_RATE := 0.35
const POLICE_RATE := 0.45
## Tank drawn per unit of intensity knocked down, as a fraction of a full tank.
##
## Charged against the **work done**, not against the clock, so the tank costs the same
## per fire however fast the crew are. Per-second was the same thing while the hose ran
## at exactly the fire's own rate; the moment that rate moved, a faster crew started
## putting fires out for less water, which is backwards. 0.5 is what the old
## 0.06/second worked out to on a building fire, so the economy is unchanged: a
## building is most of a tank, and a bad scene is two trips or a well-parked engine.
const WATER_PER_DOUSE := 0.5
## Idle_Torch is a one-handed "holding something out in front" pose, which reads
## well enough as a hose at this camera distance. The library has no spray clip.
const CLIP := "Idle_Torch"


func _init(fire: Fire) -> void:
	super(fire, REACH, CLIP, "Extinguishing")


func _work(unit: Unit, delta: float) -> bool:
	var fire := target as Fire
	if fire == null:
		return true

	var supply := _supply(unit, fire)
	# A building only yields to a real hose. Anyone else can stand in front of it all
	# day: the order runs, the animation plays, and the fire does not go down.
	if fire.needs_hose and supply == null:
		return not fire.active

	# **And the right stuff has to be coming out of it.** A hose is water and a patrol
	# car's extinguisher is dry powder, so neither is universal: water spreads a fuel
	# fire and does nothing at all to live electrics. Same shape as the rule above --
	# the order runs and the fire does not move -- because that is the shape this game
	# already uses to say no, and a second grammar for the same refusal would be worse
	# than either.
	if not _can_apply(unit, supply, fire.agent):
		return not fire.active

	var doused := fire.douse_per_second * _rate(unit, supply != null) * delta
	fire.douse(doused)
	# Water on the fire, for as long as water is going on the fire. Asked for every frame
	# rather than latched, exactly like the ladder below -- see Person.spray_at. It sits
	# after the needs_hose gate on purpose: an officer in front of a building fire has
	# already returned by now, so nothing draws a stream that is achieving nothing.
	var person := unit as Person
	if person:
		person.spray_at(fire.global_position, _applied_agent(unit, supply, fire))
	if supply:
		# Billed against the tank the fire actually drew from, so a shift of car fires
		# empties the foam and leaves the water untouched.
		if fire.agent == Fire.Agent.FOAM:
			supply.draw_foam(water_cost(doused))
		else:
			supply.draw_water(water_cost(doused))
		# The appliance's own flourish, in place of the rear doors the van had: the
		# ladder goes up while its hose is being worked. Asked for every frame rather
		# than latched, so it comes down by itself the moment the crew stop -- see
		# Vehicle.raise_ladder.
		supply.raise_ladder()
	# douse() clears the active flag the moment it is out.
	return not fire.active


## What the tank pays for knocking [param doused] off a fire's intensity. Static so a
## measurement can ask the same question the order does, rather than restating it.
static func water_cost(doused: float) -> float:
	return WATER_PER_DOUSE * doused


## What this worker is actually putting on the fire, which is **not** what the fire wants.
##
## The two coincide often enough to be confused, and the first cut passed `fire.agent`
## straight through -- so an officer taking a bin fire was drawn hosing water, when the
## only thing they carry is dry powder. What comes out of a nozzle is a property of who
## is holding it; what the fire needs is a property of the fire; and `_can_apply` above
## is the one place they have to agree.
func _applied_agent(unit: Unit, supply: Vehicle, fire: Fire) -> Fire.Agent:
	if unit.service != Unit.Service.FIRE:
		return Fire.Agent.POWDER
	if fire.agent == Fire.Agent.FOAM and supply != null:
		return Fire.Agent.FOAM
	return Fire.Agent.WATER


## Whether this worker can put [param agent] on the fire at all.
##
## The appliance carries water and foam; a patrol car carries ABC dry powder, which is
## genuinely multi-class and so keeps the officer every fire they could always take. What
## nobody carries is powder on the appliance, and that is the point of the electrical
## fire: it is the one call where the right answer is the patrol car.
func _can_apply(unit: Unit, supply: Vehicle, agent: Fire.Agent) -> bool:
	if unit.service != Unit.Service.FIRE:
		# ABC dry powder really is multi-class, so the officer keeps every fire they
		# could always take -- and gains the one nobody else can. What still stops them
		# at a building is `needs_hose`, which is about volume rather than chemistry.
		return true
	match agent:
		Fire.Agent.WATER:
			return true
		Fire.Agent.FOAM:
			# Only off the appliance, and only while there is foam left in it. A crew
			# with an empty foam tank is a crew that has to drive home -- a hydrant is a
			# water main and will not help them.
			return supply != null and supply.has_foam()
		Fire.Agent.POWDER:
			return false
	return false


## What multiple of the fire's own rate this worker manages.
func _rate(unit: Unit, on_hose: bool) -> float:
	if unit.service != Unit.Service.FIRE:
		return POLICE_RATE
	return HOSE_RATE if on_hose else OFF_HOSE_RATE


## The appliance this firefighter is working off: in reach, and **with water left**.
## An engine that has run dry stops being a supply, which is what turns the tank
## into a decision rather than a number -- a building grows faster than a crew with
## only what they carry can knock it down, so a dry engine has to be moved to a
## hydrant, not waited out.
func _supply(unit: Unit, fire: Fire = null) -> Vehicle:
	if unit.service != Unit.Service.FIRE:
		return null
	# Which tank has to have something in it depends on what is burning: an appliance
	# out of foam is still a perfectly good supply for a building.
	var wants_foam := fire != null and fire.agent == Fire.Agent.FOAM
	for node in unit.get_tree().get_nodes_in_group(Unit.GROUP):
		var engine := node as Vehicle
		if engine == null or engine.service != Unit.Service.FIRE:
			continue
		if wants_foam:
			if not engine.has_foam():
				continue
		elif not engine.has_water():
			continue
		var offset := engine.global_position - unit.global_position
		offset.y = 0.0
		if offset.length() <= HOSE_REACH:
			return engine
	return null
