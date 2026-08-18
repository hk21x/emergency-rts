extends SceneTree

## Generates driveable vehicle scenes from the POLYGON City vehicle prefabs.
##
##   godot --headless --path . --script res://Game/build_vehicles.gd
##
## The shipped prefabs cannot be instanced directly: each wraps its hull and every
## wheel in a StaticBody3D, which would fight the CharacterBody3D that drives it. So
## this walks a prefab, copies out just the MeshInstance3D parts with their authored
## transforms and materials, and rebuilds them into the layout Vehicle.gd expects.
##
## Generated rather than hand-written because these vehicles carry doors, glass and
## plates with baked offsets; transcribing a dozen transforms per vehicle by hand is
## how you get a door floating two metres off the back.
##
## Layout produced (Vehicle.gd depends on these exact paths):
##   Vehicle [CharacterBody3D]
##     Collision, NavigationAgent, SelectionRing
##     Lean / Chassis (yawed 180) / <body, glass, plates, doors...> + SteeringWheel
##     Wheels (yawed 180) / FL|FR|RL|RR / Mesh

const PREFABS := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/"
const PORTRAITS := "res://Game/UI/Portraits/"
const OUT_DIR := "res://Game/Vehicles/"

## The Synty meshes face +Z; Godot's forward is -Z. Same correction the Starter car
## and the officers need.
const FLIP := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)),
	Vector3.ZERO)

const VEHICLES := [
	{
		"prefab": "SM_Veh_Car_Police_01",
		"out": "PoliceCar.tscn",
		"display": "Patrol Car",
		"service": Unit.Service.POLICE,
		"seats": 2,
		# A patrol car carries no stretcher, so Collect never offers itself on one.
		"stretchers": 0,
		# **Two in the back.** One was the shipped figure and it made a second arrest at
		# the same scene need a second car -- which the disorder call turned from an
		# occasional nuisance into the normal case, since that one produces three or more
		# suspects at a single kerb by design.
		"cells": 2,
		"max_speed": 26.0,
		# Measured from the hull's own vertices: the roof-peak cluster spans
		# x[-0.52,0.52] y[1.63,1.74] z[-0.31,-0.06].
		"siren": {"height": 1.78, "along": -0.19, "spread": 0.34},
	},
	# **A real appliance at last**, from the Town pack (August 2026). This entry spent
	# two rounds as a placeholder and the note it used to carry ended "swap `prefab`
	# for a real appliance when a pack provides one and nothing else here has to
	# change" -- which turned out to be very nearly true. The history is worth keeping
	# because the sizes explain the tuning below: the patrol-car hull (2.17 x 1.52 x
	# 5.25) read as a saloon with an odd paint job, the van that replaced it (2.47 x
	# 1.78 x 5.02) read as an appliance at RTS zoom, and this reads as a fire engine
	# because it is one -- **3.11 x 2.84 x 8.82**, 76% longer than the van.
	#
	# That length is not free. Turn radius is `wheelbase / tan(steer)`, so the longest
	# body on the map corners widest, in a district where wide cornering is already the
	# known-worst behaviour (see NEXT.md). It was measured against a patrol car on the
	# same junctions before this landed rather than after.
	#
	# It brings a ladder and a hose nozzle as separate meshes, and it carries **no
	# separate doors** -- the van's rear doors are the one thing lost. `open_doors()`
	# already no-ops on a body without them, which the patrol car has always proved.
	{
		"prefab": "res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_Firetruck_01.tscn",
		"out": "FireEngine.tscn",
		"display": "Fire Engine",
		"service": Unit.Service.FIRE,
		# A crew carrier: the whole point of an appliance is the firefighters on it.
		"seats": 4,
		"stretchers": 0,
		# Heavy: it corners and accelerates like the ambulance rather than a car.
		"max_speed": 21.0,
		"water": true,
		# The second tank. Same appliance, and the only thing on the map that carries
		# foam at all -- a patrol car's extinguisher is dry powder.
		"foam": true,
		# Twenty tankfuls, from play feedback: fires were "still too difficult to put
		# out", and the tank was the reason -- one building node cost 41% of it, so a
		# call that had spread while the crew drove over ran the engine dry mid-fight
		# and turned the job into a hydrant run. The tank is now a long way from being
		# the binding constraint; it still empties, and running dry still stops the
		# hose dead, but it takes a genuinely bad scene to do it.
		"tank_capacity": 20.0,
		# **No palette, for the first time.** Every previous appliance was a generic body
		# being recoloured, and the note here used to explain at length which alt to pick
		# -- an alt palette is a texture atlas, not a colour, so 04_A was orange on the
		# patrol car and flat charcoal on the van, and picking by name once shipped a
		# black fire engine. None of that applies now: this body has its own texture,
		# authored for a fire engine, and it is the wrong shape of question to ask which
		# City swatch suits it. Sampled anyway rather than assumed -- see the paint check
		# in smoke_test.gd, which measures the built scene.
		#
		# Measured off this hull in 1m slices along z, not inherited -- the van's 2.07
		# would have put the beacons *inside* an appliance whose bodywork tops out at
		# 3.01. The cab is the front two metres (z +2.4..+3.4), roofed at 2.82 and 2.79
		# wide, with the nose dropping to 2.54 beyond it and the pump housing behind
		# rising to 3.01. Beacons over the **cab** as on the other two -- the front is
		# +z, where the steering wheel and front wheels are -- clearing its roof by the
		# same 4cm the ambulance and patrol car use.
		"siren": {"height": 2.86, "along": 2.90, "spread": 0.60},
	},
	{
		# **The doctor's car: the patrol hull in orange.** A doctor who walks the district
		# is a doctor who arrives after the call has resolved itself, and a specialist you
		# cannot get to the scene is not a decision, it is a tax. This is the vehicle that
		# makes the doctor dispatchable.
		#
		# **It carries no stretcher, deliberately.** A rapid-response car that could also
		# take the patient to hospital would quietly replace the ambulance and dissolve the
		# bottleneck the doctor exists to be. It brings the doctor to the casualty; the
		# ambulance still does the carrying.
		#
		# 04_A on *this* hull is genuinely orange -- rgb(.44,.32,.24), sampled off its own
		# UVs, and the one place in the pack where that palette does what its name suggests.
		# The same swatch is flat charcoal on the van and olive on a person, which is how
		# the fire service shipped a green firefighter for a while. Never trust the name
		# here; the paint check in smoke_test.gd samples the built scene.
		"prefab": "SM_Veh_Car_Police_01",
		"out": "DoctorCar.tscn",
		"display": "Doctor Car",
		"service": Unit.Service.MEDICAL,
		"palette": "res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_04_A_mat.tres",
		"seats": 2,
		"stretchers": 0,
		"cells": 0,
		# A shade quicker than the patrol car it shares a body with, and a good deal
		# quicker than the ambulance's 21 -- getting there first is the entire job.
		"max_speed": 27.0,
		# The same hull, so the same measured roof-peak cluster.
		"siren": {"height": 1.78, "along": -0.19, "spread": 0.34},
	},
	{
		"prefab": "SM_Veh_Car_Ambo_01",
		"out": "Ambulance.tscn",
		"display": "Ambulance",
		"service": Unit.Service.MEDICAL,
		"seats": 2,
		"stretchers": 2,
		# Heavier and taller, so it corners a little more sedately.
		"max_speed": 21.0,
		# Roof-peak cluster spans x[-0.49,0.49] y=2.58 z[0.50,0.75] -- the bar over
		# the cab rather than over the box.
		"siren": {"height": 2.62, "along": 0.62, "spread": 0.32},
	},
	# **The prisoner transport**, from the Heist pack (August 2026). The cheapest unit in
	# the game to add -- no new code at all, one entry here and one in `Station.TYPES` --
	# and it answers a problem the disorder call created by design: `DISORDER_SIZE` runs
	# to eight suspects at one kerb and a patrol car holds two, so the answer until now
	# was driving back and forth while the rest of the crowd recruited.
	{
		"prefab": "res://Assets/Synty/PolygonHeist/Prefab/Vehicles/SM_Veh_SwatVan_01.tscn",
		"out": "PoliceVan.tscn",
		"display": "Police Van",
		"service": Unit.Service.POLICE,
		"seats": 2,
		"stretchers": 0,
		"cells": 6,
		# Van-shaped: heavier than a patrol car, lighter than the appliance.
		"max_speed": 22.0,
		# **Missed when the van was added**, and the omission is invisible in the data:
		# a vehicle with no `siren` key simply gets no lightbar built, so it responded to
		# every call dark and silent while looking entirely correct on the forecourt.
		# Measured off the prefab like the others -- hull tops at y 2.72 and the patrol
		# car sits its beads 0.04 proud of 1.74, so 2.76. The windscreen glass ends at
		# z 1.69 and the front wheels sit at z[1.41,2.44], so +1.30 is on the cab roof
		# just behind the screen rather than adrift in the middle of a long box roof.
		# Spread scaled off the patrol car's 0.34 by the extra half-width (1.23/1.09).
		"siren": {"height": 2.76, "along": 1.30, "spread": 0.38},
	},
	# **A second patrol body**, from the Heist pack. Mechanically a faster interceptor:
	# the same two cells as the patrol car, a higher top speed, and a price between the
	# patrol car and the van. What it buys is arriving first, which is the same thing the
	# doctor car sells and the reason both exist.
	{
		"prefab": "res://Assets/Synty/PolygonHeist/Prefab/Vehicles/SM_Veh_Car_Police_Heist_01.tscn",
		"out": "Interceptor.tscn",
		"display": "Interceptor",
		"service": Unit.Service.POLICE,
		"seats": 2,
		"stretchers": 0,
		"cells": 2,
		# The quickest car on the road: past the patrol car's 26 and the doctor car's 27.
		"max_speed": 28.0,
		# **Derived rather than read straight off**, because this hull's 2.22 maximum is
		# its antennae, not its roof. The patrol car sits its beads 0.34 above its own
		# glass line (glass 1.44, siren 1.78), and this glass tops at 1.55 -- so 1.89.
		# Half-width is 1.09, the same as the patrol car, so the spread carries over.
		"siren": {"height": 1.89, "along": -0.19, "spread": 0.34},
	},
	# **The air rescue helicopter.** Same airframe as Air Support, wearing the Heist
	# pack's fourth livery -- `PolygonHeist_04_A` carries RESCUE in red on amber exactly
	# where `01_A` carries POLICE in white on blue, which is what makes this a palette
	# swap and not a modelling job.
	{
		"prefab": "res://Assets/Synty/PolygonHeist/Prefab/Vehicles/SM_Veh_Helicopter_01.tscn",
		"out": "RescueHelicopter.tscn",
		"display": "Air Rescue",
		"script": "res://Game/Units/Aircraft.gd",
		"service": Unit.Service.FIRE,
		# **Ours, not the pack's.** Synty ships `PolygonHeist_04_A.png` -- the atlas with
		# RESCUE on it -- but no material for that atlas, only for 01 and 02. So this is a
		# clone of the pack's own `PolygonHeist_01_A_mat` with the albedo swapped, kept in
		# `Game/Materials/` because `Assets/Synty/` is vendor and never edited.
		"palette": "res://Game/Materials/RescueLivery.tres",
		"seats": 2,
		"stretchers": 0,
		"max_speed": 34.0,
	},
	# **The recovery truck.** The unit that gives a road traffic collision a *tail*: every
	# incident in this game has ended when the last body left the scene, and a wreck that
	# has to be lifted is the first thing that outlives the casualties.
	{
		"prefab": "res://Assets/PolygonTown/Prefabs/Vehicles/SM_Veh_Pickup_01.tscn",
		"out": "TowTruck.tscn",
		"display": "Recovery Truck",
		"service": Unit.Service.POLICE,
		"seats": 2,
		"stretchers": 0,
		"max_speed": 20.0,
		# Same omission as the van's, found by the same check. This one is dispatched to
		# collisions from the same forecourt, so responding dark was equally wrong.
		#
		# **Placed less confidently than the others.** The hull's 2.27 maximum is bodywork
		# behind the cab, not the cab roof, so the beads go on the roof inferred from the
		# windscreen instead: glass tops at y 1.97 and spans z[-0.38,1.07], which puts the
		# cab roof near 2.00 and its middle near z 0.30. If they ever look like they are
		# floating, that is the number to move.
		"siren": {"height": 2.04, "along": 0.30, "spread": 0.36},
	},
	# **The helicopter**, and the one body here that does not drive. It is built by the
	# same generator for the same reason everything else is -- one place that knows how a
	# unit scene is assembled -- but its `script` is [Aircraft], a sibling of [Vehicle]
	# rather than a subclass, so the driving fields are skipped for it. See the `drives`
	# split in `_build_vehicle`.
	{
		"prefab": "res://Assets/Synty/PolygonHeist/Prefab/Vehicles/SM_Veh_Helicopter_01.tscn",
		"out": "Helicopter.tscn",
		"display": "Air Support",
		"script": "res://Game/Units/Aircraft.gd",
		"service": Unit.Service.POLICE,
		"seats": 2,
		"stretchers": 0,
		# Faster than anything on the road, because it is the one unit that never has to
		# follow one. That is the whole of its advantage and it should be felt.
		"max_speed": 34.0,
	},
]

## Ambient traffic. Same chassis treatment, different driver.
##
## `seats` is zero and deliberately so: TrafficCar offers no abilities, but BoardAbility
## scores against the *target* vehicle, so an officer right-clicking a passing taxi
## would climb into it if there were a seat free.
##
## Speeds are city speeds -- around 10 m/s, roughly 36 km/h -- and that is a handling
## limit, not a stylistic one. Vehicle caps yaw rate by available grip
## (max_lateral_accel), so the tightest turn a car can hold is v^2/14 metres. At the
## 15 m/s these first ran at that is a 16m radius, and a junction is 10m across: they
## simply could not get round a corner, and swung wide through the oncoming lane and
## into the buildings. At 10 m/s it is 7m, which fits.
const TRAFFIC_DIR := "res://Game/Traffic/"
const TRAFFIC := [
	{"prefab": "SM_Veh_Car_Sedan_01", "out": "Sedan.tscn", "display": "Sedan",
		"max_speed": 10.0},
	{"prefab": "SM_Veh_Car_Taxi_01", "out": "Taxi.tscn", "display": "Taxi",
		"max_speed": 10.5},
	{"prefab": "SM_Veh_Car_Van_01", "out": "Van.tscn", "display": "Van",
		"max_speed": 9.0},
	{"prefab": "SM_Veh_Car_Small_01", "out": "Hatchback.tscn", "display": "Hatchback",
		"max_speed": 10.0},
	{"prefab": "SM_Veh_Car_Medium_01", "out": "Saloon.tscn", "display": "Saloon",
		"max_speed": 9.5},
	{"prefab": "SM_Veh_Car_Muscle_01", "out": "Muscle.tscn", "display": "Muscle Car",
		"max_speed": 11.0},
]

## Steering lock for traffic, against the 33 degrees a patrol car gets. Turning radius
## is wheelbase / tan(lock), so this takes a 2.9m wheelbase from 4.5m round to 3.5m --
## the difference between making a junction turn in one go and sawing at it.
const TRAFFIC_STEER := 40.0
## Traffic eases down over a shorter run-in than an emergency vehicle. Its waypoints
## are ~25m apart, so the patrol car's 16m would have it braking for most of every
## street rather than driving down it.
const TRAFFIC_SLOWDOWN := 9.0

## Collision layer for ambient traffic, so it can be told apart from the player's
## vehicles on layer 1.
##
## **Everything on wheels collides with everything else on wheels.** Every vehicle
## masks layer 1 (world, and the player's own cars) plus this traffic layer, so no
## car can occupy another's space -- a taxi queues behind a taxi, and a patrol car
## cannot drive through either.
##
## This was asymmetric until August 2026: traffic saw the player, the player did not
## see traffic, on the theory that mutual collision would deadlock a queue the moment
## a player car nosed into it. It bought exactly that -- vehicles sliding through each
## other, measured at 0.16m between two car *centres*. The answer was not to keep them
## ghosts but to give both sides a rule: traffic gives way at junctions in a strict
## order (see TrafficCar), and the player's autopilot steers around what is in its way
## (see Vehicle's avoidance).
const TRAFFIC_LAYER := 64
## Layer 1 world and the player's cars, layer 2 knockable props, layer 64 traffic.
const VEHICLE_MASK := 1 | 2 | TRAFFIC_LAYER

var _failed := false


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(TRAFFIC_DIR)
	for config in VEHICLES:
		if not _build_vehicle(config):
			_failed = true
	for config in TRAFFIC:
		var traffic: Dictionary = config.duplicate()
		traffic["seats"] = 0
		traffic["stretchers"] = 0
		traffic["script"] = "res://Game/Units/TrafficCar.gd"
		traffic["layer"] = TRAFFIC_LAYER
		traffic["dir"] = TRAFFIC_DIR
		traffic["steer"] = TRAFFIC_STEER
		traffic["slowdown"] = TRAFFIC_SLOWDOWN
		if not _build_vehicle(traffic):
			_failed = true
	if _failed:
		quit(1)
		return
	print("done")
	quit()


## A bare name is looked up in the City pack, which is where all but one of these live.
## A full `res://` path is taken as given, so a body can come from another pack without a
## second global constant and without every other entry growing a field it does not need.
func _prefab_path(prefab: String) -> String:
	return prefab if prefab.begins_with("res://") else PREFABS + prefab + ".tscn"


func _build_vehicle(config: Dictionary) -> bool:
	var path: String = _prefab_path(str(config["prefab"]))
	if not ResourceLoader.exists(path):
		push_error("missing prefab: %s" % path)
		return false
	var source := (load(path) as PackedScene).instantiate()

	# The prefab root is itself the hull MeshInstance3D; its children are the extra
	# parts plus the StaticBody3D colliders we are deliberately dropping.
	var hull := source as MeshInstance3D
	if hull == null or hull.mesh == null:
		push_error("%s root is not a MeshInstance3D" % config["prefab"])
		source.free()
		return false

	var root := CharacterBody3D.new()
	root.name = "Vehicle"
	root.set_script(load(str(config.get("script", "res://Game/Units/Vehicle.gd"))))
	root.collision_layer = int(config.get("layer", 1))
	# Only layer 1 counts as ground, or driving over a cone makes the car inherit
	# the struck body's velocity.
	root.collision_mask = VEHICLE_MASK
	root.platform_floor_layers = 1

	var lean := _add(root, Node3D.new(), "Lean", root)
	var chassis := _add(lean, Node3D.new(), "Chassis", root)
	chassis.transform = FLIP
	var wheels := _add(root, Node3D.new(), "Wheels", root)
	wheels.transform = FLIP

	# The hull mesh sits at the chassis origin.
	var palette := str(config.get("palette", ""))
	var body := MeshInstance3D.new()
	body.mesh = hull.mesh
	_copy_materials(hull, body, palette)
	_add(chassis, body, "Body", root)

	var wheel_radius := 0.35
	var front_z := 0.0
	var rear_z := 0.0
	var found_steering := false

	for child in source.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue  # StaticBody3D colliders: deliberately dropped
		var slot := _wheel_slot(mesh.name)
		if slot != "":
			var pivot := _add(wheels, Node3D.new(), slot, root)
			pivot.transform = mesh.transform
			var wheel_mesh := MeshInstance3D.new()
			wheel_mesh.mesh = mesh.mesh
			_copy_materials(mesh, wheel_mesh)
			_add(pivot, wheel_mesh, "Mesh", root)
			wheel_radius = mesh.mesh.get_aabb().size.y * 0.5
			if slot.begins_with("F"):
				front_z = mesh.transform.origin.z
			else:
				rear_z = mesh.transform.origin.z
			continue

		# Vehicle.gd looks these up by name, so all three are load-bearing.
		var part_name := str(mesh.name)
		if mesh.name.contains("SteeringW"):
			part_name = "SteeringWheel"
			found_steering = true
		elif mesh.name.contains("Door_l"):
			part_name = "DoorL"
		elif mesh.name.contains("Door_r"):
			part_name = "DoorR"
		_copy_part(mesh, chassis, part_name, root, palette)

	if not found_steering:
		# Vehicle.gd reads $Lean/Chassis/SteeringWheel unconditionally.
		_add(chassis, Node3D.new(), "SteeringWheel", root)

	var aabb := hull.mesh.get_aabb()
	source.free()

	_add_collision(root, aabb)
	_add_agent(root)
	_add_ring(root, aabb)

	if config.has("siren"):
		_add_siren(chassis, root, config["siren"])
		root.siren_path = NodePath("Lean/Chassis/Siren")
	# Only the ambulance ships separate door meshes; on everything else these stay
	# empty and Vehicle simply has no doors to swing.
	if chassis.has_node("DoorL") and chassis.has_node("DoorR"):
		root.door_left_path = NodePath("Lean/Chassis/DoorL")
		root.door_right_path = NodePath("Lean/Chassis/DoorR")
	# And only the appliance ships a ladder. Found by name rather than configured,
	# exactly as the doors are: the part keeps whatever the prefab called it, so this
	# asks the body what it has instead of a table asserting what it should have. The
	# main section is the one that pitches -- the base is the turntable it pivots on and
	# stays put, and the fly section rides the main one.
	for part in chassis.get_children():
		if "Ladder_01" in part.name and root is Vehicle:
			root.ladder_path = NodePath("Lean/Chassis/" + part.name)
			break

	# **Only a thing that drives gets the driving fields.** The generator builds every
	# body the same way, but since August 2026 one of them is an [Aircraft] -- a sibling of
	# [Vehicle] rather than a subclass, with no tank, no cells, no stretchers and no
	# steering. Assigning those to it is not a no-op in GDScript, it is an error on an
	# undeclared property, so the split is explicit.
	var drives := root is Vehicle
	if drives:
		root.carries_water = bool(config.get("water", false))
		root.carries_foam = bool(config.get("foam", false))
		# **Absent means none.** This defaulted to 1, and a `.tscn` only stores properties
		# that differ from the script's own default -- so the ambulance, the fire engine
		# and the recovery truck, none of which mention cells, each silently got one. Two
		# were inert because [LoadSuspectAbility] gates on POLICE service, but the recovery
		# truck is police and could hold a prisoner in a vehicle with nowhere to put one.
		# Found while mapping the catalogue onto a new shop UI, which had to read these
		# numbers and printed "1 cells" against a tow truck.
		root.cells = int(config.get("cells", 0))
		root.tank_capacity = float(config.get("tank_capacity", 1.0))
	root.display_name = str(config["display"])
	# Ambient traffic inherits no service, so it stays NONE and the interface never
	# colours a passing taxi as though it were dispatchable.
	root.service = int(config.get("service", Unit.Service.NONE))
	# Shot from this very prefab by build_portraits.gd, so the avatar in the roster is
	# the vehicle in the street. Missing is not an error: run that script and they
	# appear, and until then the interface draws a car outline instead.
	# A repainted variant is shot under its own name, so ask for that first: the fire
	# engine's avatar must be the orange one, not the patrol car it borrows its body
	# from.
	var portrait := PORTRAITS + str(config["out"]).get_basename() + ".png"
	if not ResourceLoader.exists(portrait):
		portrait = PORTRAITS + str(config["prefab"]) + ".png"
	if ResourceLoader.exists(portrait):
		root.portrait = load(portrait)
	root.selection_ring_path = NodePath("SelectionRing")
	root.seats = int(config["seats"])
	root.max_speed = float(config["max_speed"])
	var wheelbase := absf(front_z - rear_z)
	if drives:
		root.stretchers = int(config["stretchers"])
		root.max_steer_degrees = float(config.get("steer", root.max_steer_degrees))
		root.slowdown_distance = float(config.get("slowdown", root.slowdown_distance))
		root.wheel_radius = wheel_radius
		root.wheelbase = wheelbase
	# **Where the crew step out, sized off this body rather than fixed.** The default 3.2
	# was measured on a 5m van whose tail sits 2.3m back, and it survived the ambulance
	# for the same reason. The appliance's tail is 4.4m back, so a fixed number puts four
	# firefighters *inside* the truck -- and nothing catches it, because a vehicle is a
	# CharacterBody3D and so is absent from the baked navigation the dismount point snaps
	# to. Half the body, plus however far the hull sits off centre, plus room to stand.
	if drives:
		root.dismount_back = aabb.size.z * 0.5 + absf(aabb.get_center().z) + 0.9

	# Reported before saving: _save() frees the node.
	print("%-22s hull %.2f x %.2f x %.2f   wheelbase %.2f   wheel r %.2f" % [
		config["out"], aabb.size.x, aabb.size.y, aabb.size.z, wheelbase, wheel_radius])
	return _save(root, str(config.get("dir", OUT_DIR)) + str(config["out"]))


## Copies a prefab part, and anything hanging off it.
##
## The recursion is not decoration: the ambulance's rear doors carry their own glass as
## a child, and the flat copy this used to do dropped it. A door that swings open
## leaving its window hanging in mid-air is worse than one that never moves.
func _copy_part(source: MeshInstance3D, parent: Node, node_name: String,
		root: Node, palette := "") -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = source.mesh
	part.transform = source.transform
	_copy_materials(source, part, palette)
	_add(parent, part, node_name, root)
	for child in source.get_children():
		var child_mesh := child as MeshInstance3D
		if child_mesh != null and child_mesh.mesh != null:
			_copy_part(child_mesh, part, str(child_mesh.name), root, palette)
	return part


## The lightbar, as a pair of coloured beads with a lamp inside each.
##
## The prefabs model the bar into the hull mesh and share one palette atlas across the
## whole vehicle, so there is no node to switch on and no way to recolour just those
## polygons. These sit on top of the modelled bar instead. Positions come from reading
## the hull's own vertices -- everything within 12cm of the roof peak, which on an
## emergency vehicle is the lightbar and nothing else.
func _add_siren(chassis: Node, root: Node, config: Dictionary) -> void:
	var siren := _add(chassis, Node3D.new(), "Siren", root)
	# Off until the vehicle is actually responding.
	(siren as Node3D).visible = false

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var colour := Color(1.0, 0.13, 0.10) if i == 0 else Color(0.16, 0.36, 1.0)

		var sphere := SphereMesh.new()
		sphere.radius = 0.115
		sphere.height = 0.2
		sphere.radial_segments = 10
		sphere.rings = 5

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colour
		material.emission_enabled = true
		material.emission = colour
		# Well above 1 so the environment's glow picks it up. At RTS zoom in daylight
		# the lamp below contributes almost nothing -- the bloom is what you see.
		material.emission_energy_multiplier = 8.0

		var bead := MeshInstance3D.new()
		bead.mesh = sphere
		bead.material_override = material
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bead.position = Vector3(side * float(config["spread"]),
			float(config["height"]), float(config["along"]))
		_add(siren, bead, "Left" if i == 0 else "Right", root)

		# Child of the bead, so hiding one hides the other.
		var lamp := OmniLight3D.new()
		lamp.light_color = colour
		lamp.light_energy = 3.5
		lamp.omni_range = 10.0
		lamp.shadow_enabled = false
		_add(bead, lamp, "Lamp", root)


## Box from the ground to the top of the hull, inset slightly so the vehicle does not
## catch on scenery it visually clears. Mirrored on x/z because the visuals are yawed
## 180 but this shape is not.
func _add_collision(root: CharacterBody3D, aabb: AABB) -> void:
	var shape := BoxShape3D.new()
	var top := aabb.position.y + aabb.size.y
	shape.size = Vector3(aabb.size.x * 0.94, top, aabb.size.z * 0.96)

	var collider := CollisionShape3D.new()
	collider.shape = shape
	var centre := aabb.get_center()
	collider.position = Vector3(-centre.x, top * 0.5, -centre.z)
	_add(root, collider, "Collision", root)


func _add_agent(root: CharacterBody3D) -> void:
	var agent := NavigationAgent3D.new()
	agent.path_desired_distance = 2.0
	agent.target_desired_distance = 2.2
	agent.avoidance_enabled = false
	_add(root, agent, "NavigationAgent", root)


func _add_ring(root: CharacterBody3D, aabb: AABB) -> void:
	var reach := maxf(aabb.size.x, aabb.size.z) * 0.5
	var torus := TorusMesh.new()
	torus.inner_radius = reach * 0.92
	torus.outer_radius = reach * 0.92 + 0.3
	torus.rings = 48
	torus.ring_segments = 8

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 1.0, 0.4, 0.85)

	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.06, 0.0)
	_add(root, ring, "SelectionRing", root)


## Copies a part's materials across, optionally repainting the bodywork.
##
## [param palette] swaps the pack's stock body material (`PolygonCity_01_A`, which
## every vehicle in the pack shares) for one of the alt palettes. Only that material
## is touched, so glass, plates and lights keep theirs -- the same rule the ambient
## traffic's runtime repaint follows.
func _copy_materials(from: MeshInstance3D, to: MeshInstance3D, palette := "") -> void:
	var coat: Material = load(palette) if palette != "" else null
	for surface in from.mesh.get_surface_count():
		var material := from.get_surface_override_material(surface)
		if material == null:
			material = from.mesh.surface_get_material(surface)
		if material == null:
			continue
		# **The base coat of whichever pack, matched by suffix.** This read
		# `"PolygonCity_01_A" in path`, which is the City pack's body material and nothing
		# else -- so a palette on a Heist vehicle was accepted, ignored, and produced a
		# scene identical to the unpainted one with no warning anywhere. Exactly the
		# silent kind: the config looks applied and the model does not change.
		#
		# `ends_with` rather than `in`, because Heist ships `PolygonHeist_01_A_Glass_mat`
		# and `_Shiny_mat` alongside `PolygonHeist_01_A_mat`, and repainting a windscreen
		# with the bodywork atlas is how you get an opaque cockpit.
		if coat and material.resource_path.ends_with("_01_A_mat.tres"):
			material = coat
		to.set_surface_override_material(surface, material)
	to.cast_shadow = from.cast_shadow


## "SM_Veh_Car_Ambo_Wheel_fl" -> "FL", or "" when it is not a wheel.
func _wheel_slot(node_name: String) -> String:
	for slot in ["fl", "fr", "rl", "rr"]:
		if node_name.to_lower().ends_with("wheel_" + slot):
			return slot.to_upper()
	return ""


func _add(parent: Node, node: Node, node_name: String, owner_node: Node) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = owner_node
	return node


func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return false
	return true
