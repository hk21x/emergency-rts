extends Ability
class_name ConnectAbility

## Run a line from a hydrant to the appliance, so the hose draws off the main.
##
## **What it changes is where you park.** The tank has always been finite and a hydrant has
## always refilled it — but only while stopped, and only up to full, so a hydrant was a
## refuelling stop. Connected, the tank stops draining altogether: the crew are fighting the
## fire off the water main rather than off what they brought.
##
## That turns one decision into two. The hose reaches 18m from the appliance and a hydrant
## holds it at 9m, so an engine can be parked near the fire, near the water, or at a spot
## that serves both — and only the third lets a big fire be fought without a pause to refill.
## A building fire is sized to the crew you own, so the pause is the thing that loses it.
##
## Targets a *point*, not a thing. The hydrant the player sees is drawn into the street
## furniture MultiMesh and has no collider of its own, so there is nothing to click; this
## looks for one near wherever they clicked, which is also forgiving in the way clicking a
## kerbside object at RTS zoom needs to be.

## How near the clicked point a hydrant has to be to count as "that one".
const PICK_RADIUS := 6.0


func id() -> StringName:
	return &"connect"


func label() -> String:
	return "Connect"


## The droplet is Extinguish's, which is right rather than lazy: this is the same water,
## and the pair reading as a family is the point. The tiles are told apart by their letter
## and their label, which is how every other near-duplicate in the grid is told apart.
func icon() -> StringName:
	return &"droplet"


func hotkey() -> Key:
	return KEY_P


## Deliberately not automatic. Connecting is a decision about where the appliance stands,
## and a vehicle that hooked itself up whenever it passed a hydrant would make that
## decision for the player and then be blamed for it.
func auto_engages(_unit: Unit, _target: Target) -> bool:
	return false


func score(unit: Unit, target: Target) -> int:
	if target == null:
		return NOT_APPLICABLE
	var engine := unit as Vehicle
	# Water carriers only. An ambulance beside a hydrant is a vehicle beside a hydrant.
	if engine == null or not engine.carries_water:
		return NOT_APPLICABLE
	if Hydrant.nearest(unit, target.position, PICK_RADIUS) == null:
		return NOT_APPLICABLE
	# Under Extinguish (20), so right-clicking a fire still fights it, and over Board (10)
	# and Move (0), so a click on the kerb by a hydrant means the hydrant.
	return 15


func make_order(unit: Unit, target: Target) -> Order:
	return ConnectOrder.new(Hydrant.nearest(unit, target.position, PICK_RADIUS))
