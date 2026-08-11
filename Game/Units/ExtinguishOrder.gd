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

	var supply := _supply(unit)
	# A building only yields to a real hose. Anyone else can stand in front of it all
	# day: the order runs, the animation plays, and the fire does not go down.
	if fire.needs_hose and supply == null:
		return not fire.active

	var doused := fire.douse_per_second * _rate(unit, supply != null) * delta
	fire.douse(doused)
	if supply:
		supply.draw_water(water_cost(doused))
	# douse() clears the active flag the moment it is out.
	return not fire.active


## What the tank pays for knocking [param doused] off a fire's intensity. Static so a
## measurement can ask the same question the order does, rather than restating it.
static func water_cost(doused: float) -> float:
	return WATER_PER_DOUSE * doused


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
func _supply(unit: Unit) -> Vehicle:
	if unit.service != Unit.Service.FIRE:
		return null
	for node in unit.get_tree().get_nodes_in_group(Unit.GROUP):
		var engine := node as Vehicle
		if engine == null or engine.service != Unit.Service.FIRE:
			continue
		if not engine.has_water():
			continue
		var offset := engine.global_position - unit.global_position
		offset.y = 0.0
		if offset.length() <= HOSE_REACH:
			return engine
	return null
