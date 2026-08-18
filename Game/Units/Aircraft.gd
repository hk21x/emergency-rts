extends Unit
class_name Aircraft

## A helicopter: the first unit that does not touch the road network.
##
## **There is no air pathfinding, and that is the finding rather than a shortcut.** The
## brief asked for it, and the honest answer after looking is that at cruise height nothing
## obstructs — the district's tallest tower families are modelled as footprints and the
## helicopter flies over all of them. A navigation mesh exists to route *around* obstacles;
## an air mesh here would have none to route around, so it would be a second navigation
## system whose every query returned the straight line this class already flies. The real
## work in flight is not the route, it is the **vertical states** and **where you are
## allowed to put it down**, which is what this file is mostly about.
##
## Sibling to [Vehicle] and [Person] rather than a subclass of either: `Unit`'s movement
## contract is five methods, and a helicopter satisfies all five without inheriting 2,400
## lines of steering, kerbs, reversing and lane discipline that mean nothing in the air.
##
## Position is written directly rather than through `move_and_slide`. A `CharacterBody3D`
## in the air has nothing to slide against, and letting it collide would let a tower it is
## flying *over* shove it off course.

## Cruise altitude, and how fast it gets there. Well above the tallest building family so
## the flight path never has to think about them.
@export var cruise_height := 24.0
@export var climb_speed := 7.0
@export var max_speed := 26.0
## How close counts as arrived, horizontally. Generous: a helicopter hovering a metre off
## its mark is on station, and chasing an exact point would make it jitter.
@export var arrive_within := 3.0

## How fast it swings its nose round, in radians a second. Roughly 90 degrees a second,
## so the worst case -- a destination directly behind it -- takes a shade over two.
@export var turn_speed := 1.6
## Fraction of cruise speed available while the nose is still coming round.
##
## **Not zero, deliberately.** Translation stays straight at the destination whatever the
## aircraft is pointing at, so a floor above zero means it cannot stall facing the wrong
## way, and -- more to the point -- it cannot *orbit*. Flying along the heading instead
## would have looked better and opened the door to a circling limit cycle whenever the
## turn rate could not keep up with the speed, which is a fault this project has already
## paid to learn once, in a car.
const SIDEWAYS_SPEED := 0.3

## The generator sets these on every vehicle it builds; a helicopter carries crew and has
## no stretchers, no cells and no tank.
@export var seats := 2

## Where the generator parents the prefab's parts. The two rotors are found by name
## rather than wired by path, because the pack names them and the generator copies them
## through unchanged -- a path in a config would be a third place to keep in step.
const BLADE_PARENT := "Lean/Chassis"
const MAIN_ROTOR := "SM_Veh_Helicopter_Blades_Main_01"
const TAIL_ROTOR := "SM_Veh_Helicopter_Blades_Back_01"

## Rotor speed at full song, and how long the blades take to reach it from a standstill.
##
## **The spool is a real part of the take-off, not a flourish on it.** The first cut drove
## rotor speed off altitude, which put the two in the wrong order: the aircraft left the
## ground and the discs picked up afterwards, so it appeared to be lifted by something
## other than its rotors. It now spends [member rotor_spool] seconds on the pad winding up
## and does not move until the blades are at full speed -- which is both what a helicopter
## does and, unexpectedly, a better piece of pacing: air support acquires a cost in
## seconds that the road units do not pay.
@export var rotor_speed := 44.0
@export var rotor_spool := 4.0

## GROUNDED and SPOOLING are both *on the ground*; what separates them is that a spooling
## aircraft has been told to go and is winding up to do it.
enum Phase { GROUNDED, SPOOLING, CLIMBING, CRUISING, DESCENDING }

var phase := Phase.GROUNDED
## Where it is going, on the ground plane. `INF` when it has nowhere to be.
var _destination := Vector3.INF
## Whether arriving means putting down or holding station.
var _landing := false
## The height of the ground it took off from, so it lands back onto the same datum.
var _ground_y := 0.0

var _main_rotor: Node3D
var _tail_rotor: Node3D
## 0 stopped, 1 at full speed. Follows whether it is airborne.
var _rotor := 0.0


func _ready() -> void:
	super()
	_ground_y = global_position.y
	var blades := get_node_or_null(BLADE_PARENT)
	if blades:
		_main_rotor = blades.get_node_or_null(MAIN_ROTOR) as Node3D
		_tail_rotor = blades.get_node_or_null(TAIL_ROTOR) as Node3D


## Turns the rotors, and spools them up and down with the flight.
##
## Driven off `is_airborne()` rather than off speed: a helicopter holding station has its
## rotors at full song, and one sitting on the pad has them stopped. The main disc turns
## about its own vertical axis; the tail rotor is mounted sideways, so it turns about its
## local X.
func _update_rotors(delta: float) -> void:
	# **The phase, not the altitude.** Driving this off height read plausibly and was
	# wrong at both ends of a flight: the blades were still slow as the aircraft lifted,
	# and they wound *down* through the descent, so it landed under stopped rotors. A
	# helicopter turns its discs at full speed whenever it is doing anything at all --
	# spooling on the pad, climbing, holding station, or coming down -- and stops them only
	# once it is parked. One line, and both ends come right.
	#
	# (Height also had a defect the check caught: `_ground_y` is read in `_ready`, so any
	# aircraft positioned *after* it enters the tree measured altitude against a datum from
	# somewhere else and turned its blades while sitting still.)
	var wanted := 0.0 if phase == Phase.GROUNDED else 1.0
	_rotor = move_toward(_rotor, wanted, delta / maxf(rotor_spool, 0.01))
	if _rotor <= 0.0:
		return
	# Squared, so the wind-up is felt rather than merely present: linear against altitude
	# spends most of the climb already looking fast, and the interesting part of a spool is
	# the bottom of it.
	var turn := rotor_speed * _rotor * _rotor * delta
	if _main_rotor:
		_main_rotor.rotate_y(turn)
	if _tail_rotor:
		_tail_rotor.rotate_x(turn)


## Whether [param point] may be landed on.
##
## **Clear land only — never a property.** `CityGrid.standable()` already draws exactly
## that line for people: roads, parks and the pavement ring around each block are ground,
## and everything inside a block is the building. Reusing it means a helicopter can never
## be put down on a roof or inside a house, and it means the rule cannot drift from the one
## the rest of the game walks on.
##
## Off-lattice maps (the tutorial town) have no such table, so nothing is landable there
## and the verb simply never offers itself.
static func can_land_at(point: Vector3) -> bool:
	if not CityGrid.lattice_fits:
		return false
	var tile := CityGrid.tile_at(point)
	return CityGrid.standable(tile.x, tile.y)


## On the ground and winding up does not count: [LandAbility] and the landing rule read
## this, and an aircraft that has not left the pad has nothing to land.
func is_airborne() -> bool:
	return phase != Phase.GROUNDED and phase != Phase.SPOOLING


## Start the rotors and leave the ground once they are up to speed.
##
## The wait is in [enum Phase].SPOOLING rather than a timer here, so every way off the
## ground goes through it -- a right-click across the district spools exactly as a
## deliberate take-off does. Three call sites used to set CLIMBING themselves, which is
## three places to forget.
func take_off() -> void:
	if phase == Phase.GROUNDED:
		_destination = Vector3.INF
		_landing = false
		_leave_ground()


## GROUNDED -> SPOOLING, and the altitude datum captured at the moment it commits.
##
## Read here rather than in `_ready` on purpose: a dispatched aircraft is positioned after
## it enters the tree, so a datum from `_ready` belongs to wherever it was assembled.
func _leave_ground() -> void:
	if phase != Phase.GROUNDED:
		return
	_ground_y = global_position.y
	phase = Phase.SPOOLING


## Fly to [param point] and put down there. The caller is expected to have checked
## [method can_land_at]; this refuses rather than trusting it, because an order that
## survives a scene change could otherwise land one in a living room.
func land_at(point: Vector3) -> void:
	if not can_land_at(point):
		return
	_destination = Vector3(point.x, global_position.y, point.z)
	_landing = true
	_leave_ground()


## Move, Stop, Return and the two verbs that are its own. No Lights or Siren: the pack's
## body carries neither, and a tile that toggles nothing is worse than an absent one.
func _build_abilities() -> Array[Ability]:
	var list: Array[Ability] = [MoveAbility.new(), StopAbility.new()]
	list.append(TakeOffAbility.new())
	list.append(LandAbility.new())
	if service != Service.NONE:
		list.append(ReturnAbility.new())
	return list


# --- The Unit movement contract ----------------------------------------------

## Flying somewhere. Takes off on its own if it is on the ground: a player who
## right-clicks across the district means "go there", and being told to take off first
## would be a rule to learn for no gain.
func navigate_to(point: Vector3, _may_turn_round := true) -> void:
	_destination = Vector3(point.x, global_position.y, point.z)
	_landing = false
	_leave_ground()


func stop_navigating() -> void:
	_destination = Vector3.INF
	_landing = false


## True while it still has somewhere to be *or* is still going up or down. The vertical
## states count: an order that ended the moment the destination was reached horizontally
## would report a landing finished while the aircraft was still twenty metres up.
func is_navigating() -> bool:
	return _destination != Vector3.INF or phase == Phase.SPOOLING \
		or phase == Phase.CLIMBING or phase == Phase.DESCENDING


## Snaps round to face [param point].
##
## This is [Unit]'s one-argument contract, which [WorkOrder] and the stretcher orders call
## expecting the unit to be looking the right way on the next frame. It stays instant for
## them. Cruising uses [method _turn_towards] instead.
func face_towards(point: Vector3) -> void:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.1:
		return
	global_rotation.y = atan2(-offset.x, -offset.z)


## Eases the nose toward [param point], and reports how much of cruise speed that leaves.
##
## The first cut simply wrote the bearing every frame, so the aircraft pivoted to face a
## new destination within a single frame and then slid there already pointed -- which
## reads as a sprite being rotated rather than as something flying. Turning it into a
## rate is most of what makes it look airborne.
##
## Returns 1.0 when it is pointed at the destination, falling to [constant
## SIDEWAYS_SPEED] when the destination is behind it, so it eases into the turn rather
## than flying backwards at full speed for the two seconds the nose takes to come round.
func _turn_towards(point: Vector3, delta: float) -> float:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.1:
		return 1.0
	var wanted := atan2(-offset.x, -offset.z)
	var diff := angle_difference(global_rotation.y, wanted)
	var step := turn_speed * delta
	global_rotation.y += clampf(diff, -step, step)
	# Whatever is left over after this frame's turn: 1 pointed at it, 0 pointed away.
	var aligned := (cos(angle_difference(global_rotation.y, wanted)) + 1.0) * 0.5
	return lerpf(SIDEWAYS_SPEED, 1.0, aligned)


func _update_movement(delta: float) -> void:
	# Before the match, so the rotors keep turning in every phase -- including the early
	# return a grounded aircraft takes, where they need to spool *down*.
	_update_rotors(delta)
	match phase:
		Phase.GROUNDED:
			return
		Phase.SPOOLING:
			# Sat still with the rotors winding up. `_update_rotors` above has already run
			# this frame, so the aircraft lifts on the frame the blades reach full speed
			# rather than the one after.
			if _rotor >= 1.0:
				phase = Phase.CLIMBING
			return
		Phase.CLIMBING:
			global_position.y = minf(global_position.y + climb_speed * delta,
				_ground_y + cruise_height)
			if global_position.y >= _ground_y + cruise_height - 0.01:
				phase = Phase.CRUISING
		Phase.DESCENDING:
			global_position.y = maxf(global_position.y - climb_speed * delta, _ground_y)
			if global_position.y <= _ground_y + 0.01:
				phase = Phase.GROUNDED
				_destination = Vector3.INF
				_landing = false
			return
		Phase.CRUISING:
			pass

	if _destination == Vector3.INF:
		return
	var offset := _destination - global_position
	offset.y = 0.0
	var gap := offset.length()
	if gap <= arrive_within:
		if _landing and phase == Phase.CRUISING:
			phase = Phase.DESCENDING
		elif not _landing:
			_destination = Vector3.INF
		return
	# Only travels once it is up. Climbing out of a street between buildings and moving
	# at the same time is how an aircraft ends up inside one.
	if phase != Phase.CRUISING:
		return
	var throttle := _turn_towards(_destination, delta)
	global_position += offset.normalized() * minf(max_speed * throttle * delta, gap)
