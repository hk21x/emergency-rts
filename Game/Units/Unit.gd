extends CharacterBody3D
class_name Unit

## A selectable, commandable thing. Base for vehicles and, later, personnel.
##
## Owns selection state, the ability list and the order queue; knows nothing about
## how it physically moves. Subclasses implement the movement interface at the bottom
## and do their locomotion in [method _update_movement].

signal selection_changed(selected: bool)
signal orders_changed

## Which emergency service a unit belongs to.
##
## Identity, not capability. The interface colours avatars, selection rings and map
## markers by it, so a green vehicle on the roster is the same green vehicle in the
## street. Phase 13 will read the same value to *gate* abilities -- which is what makes
## "send the right unit" mean anything -- but until then a unit's service says who it
## is, not what it can do.
enum Service { NONE, POLICE, MEDICAL, FIRE }

## Which catalogue entry this unit was bought from, stamped by [method Station.dispatch].
##
## Not exported: it belongs to the purchase, not to the scene, and a hand-placed unit that
## nobody bought genuinely has no answer. See [method Station.type_of] for why guessing it
## back from the service stopped working.
var type_id := &""

@export var display_name := "Unit"

@export_group("Carrying")
## People this unit can take aboard.
##
## **On [Unit] rather than [Vehicle], because an aircraft carries people and is not a
## Vehicle.** [Aircraft] extends Unit directly -- it has no lightbar, no siren and no
## repair bill -- so while the crew contract lived on Vehicle, `BoardAbility` cast its
## target to Vehicle, that cast returned null for every helicopter, and a £1,800 unit with
## two seats could not be boarded by anybody. The seats were declared and dead.
##
## **Defaults to zero, deliberately.** It was 2 on Vehicle, which meant a scene that said
## nothing got two seats -- and a `.tscn` omits any value equal to the default, so moving
## the export with its old default would have silently emptied every car that had been
## relying on it. That is exactly how `cells` once put a prisoner in a tow truck. Every
## body states its own number now.
@export var seats := 0
## Stabilised casualties this unit can carry to hospital. Zero for anything that is not an
## ambulance or an air ambulance -- see [member seats] on why the default is not 1.
@export var stretchers := 0
## Metres behind the unit that dismounting crew are placed.
@export var dismount_back := 3.2
## Metres to each side, alternating, so a full crew does not land in one heap.
@export var dismount_side := 1.6

## Who is riding in this unit.
var crew: Array[Person] = []
## Stabilised casualties aboard, on their way to hospital.
var casualties: Array[Casualty] = []
@export var service: Service = Service.NONE
## Rendered snapshot of this unit for the roster avatar, from `build_portraits.gd`.
## Left unset -- ambient traffic, the crowd -- the interface falls back to the drawn
## symbol [method icon] names.
@export var portrait: Texture2D
## Ring shown under this unit while it is selected. Per-unit rather than shared, so
## each unit type can size its own.
@export var selection_ring_path: NodePath

var is_selected := false
var orders: Array[Order] = []

var _abilities: Array[Ability] = []
@export_group("Getting on with it")
## Whether an idle unit starts work on an incident it is standing near.
@export var auto_engage := true
## How near it has to be. About a scene's width: close enough that the unit is plainly
## *at* the incident, far enough that a crew put down beside a building fire finds it
## without being walked the last few metres.
@export var auto_engage_range := 14.0
## How often to look around. Cheap either way, but there is no reason to scan the
## incident list every frame for something that changes on a human timescale.
@export var auto_engage_interval := 0.5

## Seconds until the next look around for something to get on with.
var _auto_due := 0.0
var _ring: Node3D
## Whether the front order has had start() called yet.
var _order_started := false
var _spawn_transform: Transform3D


## Every unit joins this so box selection can enumerate candidates without the
## controller holding a registry.
const GROUP := &"units"


func _ready() -> void:
	add_to_group(GROUP)
	_spawn_transform = global_transform
	_ring = get_node_or_null(selection_ring_path) as Node3D
	if _ring:
		_ring.visible = false
		_tint_ring()
	_abilities = _build_abilities()


## Colours the selection ring by service, so the green ring under a paramedic is the
## green avatar in the roster and the green dot on the map. Picking one unit out of six
## in a busy street is easier when its own colour is on the ground under it.
##
## The material is duplicated first. A scene's sub-resources are shared between every
## instance of it, so recolouring in place would repaint every officer at once.
func _tint_ring() -> void:
	var mesh := _ring as MeshInstance3D
	if mesh == null or mesh.material_override == null:
		return
	# **The shape is this file's, not the scene's.** Every unit scene ships a TorusMesh
	# placeholder -- six of them, across a generator and four hand-authored scenes -- and
	# they are all swapped for one bracket here. Sized off the unit's own collider so a
	# patrol car and a paramedic each get a bracket that fits, which the shared torus in
	# each scene could not do.
	mesh.mesh = Markers.bracket(_ring_reach())
	var material: StandardMaterial3D = mesh.material_override.duplicate()
	if material == null:
		return
	var shades := Palette.service(service)
	material.albedo_color = Color(shades[0].r, shades[0].g, shades[0].b, 0.85)
	mesh.material_override = material


## Half the footprint of whatever this unit actually is, for sizing the bracket.
##
## Read off the collision shape rather than the visual mesh: the visual is a Synty prefab
## whose AABB includes a light bar or a raised arm, and a bracket drawn round *that* sits
## a metre off the ground plane the unit occupies.
func _ring_reach() -> float:
	var shape := get_node_or_null("Collision") as CollisionShape3D
	if shape and shape.shape:
		var box := shape.shape as BoxShape3D
		if box:
			return maxf(box.size.x, box.size.z) * 0.5 + 0.25
		var capsule := shape.shape as CapsuleShape3D
		if capsule:
			return capsule.radius + 0.35
	return 1.0


## Re-anchors where respawn returns to. The station calls this after standing a
## freshly dispatched unit on its slot: _ready ran at the origin, before the unit
## was placed, and respawning to the origin would drop it inside a block.
func mark_spawn() -> void:
	_spawn_transform = global_transform


## Returns the unit to where it started and drops everything it was doing.
func respawn() -> void:
	clear_orders()
	global_transform = _spawn_transform


func _physics_process(delta: float) -> void:
	_auto_engage(delta)
	_advance_orders(delta)
	_update_movement(delta)


## Starts work on a nearby incident when there is nothing else to do.
##
## A firefighter standing beside a fire should be putting it out, and a paramedic beside a
## casualty should be treating them — waiting to be told twice is not realism, it is
## bookkeeping. What makes this safe rather than presumptuous is the two gates it goes
## through: it only ever fires when the unit is **idle**, so it can never countermand an
## order the player gave, and only for abilities that have opted in via
## [method Ability.auto_engages], so a unit will start work but never decide on its own to
## cordon a street or get into a vehicle.
##
## The scoring ladder does the rest. It already answers "what would this unit do to this
## target", including the hard capability gating — an officer has no Extinguish to score,
## so no amount of standing next to a building fire will make one fight it.
func _auto_engage(delta: float) -> void:
	if service == Service.NONE or not auto_engage or has_orders():
		return
	_auto_due -= delta
	if _auto_due > 0.0:
		return
	_auto_due = auto_engage_interval
	if not is_selectable():
		return

	var best: Ability = null
	var best_target: Target = null
	var best_score := 0
	for node in get_tree().get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident == null or not incident.active:
			continue
		var offset := incident.global_position - global_position
		offset.y = 0.0
		if offset.length() > auto_engage_range:
			continue
		var target := Target.new()
		target.position = incident.global_position
		target.collider = incident
		target.incident = incident
		var ability := resolve(target)
		if ability == null or not ability.auto_engages(self, target):
			continue
		# Nearest wins ties, so a crew does not walk past the fire at its feet.
		var rank := ability.score(self, target) * 1000 - int(offset.length())
		if rank > best_score:
			best_score = rank
			best = ability
			best_target = target
	if best:
		issue(best.make_order(self, best_target))


# --- Selection ---------------------------------------------------------------

func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	if _ring:
		_ring.visible = value
	selection_changed.emit(value)


# --- Orders ------------------------------------------------------------------

## Gives the unit an order. [param queue] appends instead of replacing, which is what
## shift-click does.
func issue(order: Order, queue := false) -> void:
	if order == null:
		return
	if not queue:
		_abandon_current()
		orders.clear()
	orders.append(order)
	orders_changed.emit()


func clear_orders() -> void:
	if orders.is_empty():
		return
	_abandon_current()
	orders.clear()
	orders_changed.emit()


## Whether [param unit] could actually path to [param point] on **its own** navigation
## layer.
##
## Lifted out of `Vehicle._is_off_road` so people and vehicles can both be asked. The
## layer argument is the entire point: `map_get_closest_point` takes no layer filter and
## both navigation regions share one map, so it happily answers "0.00m away" for a spot in
## the middle of a pavement when asked about a car. That call has already produced one
## completely vacuous check in this project, and the only reason it was caught is that
## adding it did not move the measurement by a single frame.
static func can_reach(unit: Unit, point: Vector3, margin := 2.0) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var agent := unit.get_node_or_null("NavigationAgent") as NavigationAgent3D
	if agent == null:
		return true
	var path := NavigationServer3D.map_get_path(unit.get_world_3d().navigation_map,
		unit.global_position, point, true, agent.navigation_layers)
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return Vector2(end.x - point.x, end.z - point.z).length() <= margin


func current_order() -> Order:
	return orders[0] if not orders.is_empty() else null


func has_orders() -> bool:
	return not orders.is_empty()


func abilities() -> Array[Ability]:
	return _abilities


## Best ability for this target, or null if nothing applies.
func resolve(target: Target) -> Ability:
	var best: Ability = null
	var best_score := Ability.NOT_APPLICABLE
	for ability in _abilities:
		var value := ability.score(self, target)
		if value > best_score:
			best_score = value
			best = ability
	return best if best_score > Ability.NOT_APPLICABLE else null


func _advance_orders(delta: float) -> void:
	if orders.is_empty():
		return
	var order := orders[0]
	if not _order_started:
		order.start(self)
		_order_started = true
	if order.tick(self, delta):
		orders.pop_front()
		_order_started = false
		orders_changed.emit()


func _abandon_current() -> void:
	# Only cancel an order that actually started, or a queued order would be told to
	# stop something it never began.
	if _order_started and not orders.is_empty():
		orders[0].cancel(self)
	_order_started = false


# --- Overridable -------------------------------------------------------------

## False while the unit is out of play -- riding in a vehicle, say. Unselectable
## units are skipped by box select and dropped from the selection.
func is_selectable() -> bool:
	return true


## Symbol the interface draws for this unit. See [Glyph].
func icon() -> StringName:
	return &"person"


## Abilities this unit type offers. Order matters only for breaking score ties, and
## for the left-to-right order of the command bar.
## Removes every collider from [param node] and its children.
##
## **For props a unit carries.** The Synty prefabs wrap their meshes in a `MeshCollider`
## StaticBody3D, and a held weapon is parented inside the character and teleported onto the
## hand bone every frame -- so the prop's own collider shoves its carrier. An armed
## response officer drifted three metres a second across the road with zero velocity and
## no orders, which is what that looks like from outside.
##
## [Debris] and [Wreck] each carry a private copy of this for their scattered props; this
## is the one people use.
static func strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		strip_collision(child)


func _build_abilities() -> Array[Ability]:
	return [MoveAbility.new(), StopAbility.new()]


## Locomotion, run every physics frame after the order queue.
func _update_movement(_delta: float) -> void:
	pass


## Turn to face a world point. Only meaningful for units that can pivot on the spot.
func face_towards(_point: Vector3) -> void:
	pass


## Head for a world point.
## [param _final] says whether this point ends the journey or is a waypoint on the way.
## Only a vehicle cares -- it decides how far out one will turn round rather than drive
## round -- but the signature lives here because orders hold a [Unit], not a [Vehicle].
func navigate_to(_point: Vector3, _may_turn_round := true) -> void:
	pass


## Give up on the current destination and come to rest.
func stop_navigating() -> void:
	pass


## True while still travelling. Orders use this to know when they are done.
func is_navigating() -> bool:
	return false


# --- Carrying ------------------------------------------------------------------
#
# **Hoisted here from [Vehicle] in August 2026, so an aircraft can carry people.**
# [Aircraft] extends Unit directly rather than Vehicle -- it has no lightbar, no siren,
# no repair bill and no wheels -- so while this contract lived on Vehicle, every cast in
# `BoardAbility`, `UnloadAbility`, `StretcherOrder` and `Hospital` returned null for a
# helicopter. Two £1,800 units advertised seats that nothing in the game could fill.
#
# What stayed on Vehicle: cells and suspects. A helicopter has no cage, and doors, which
# only a road body has -- [method open_doors] is a no-op here and a real animation there.


func has_free_seat() -> bool:
	return crew.size() < seats


## Takes a person aboard. Returns false if the seats filled up while they walked over.
func take_aboard(person: Person) -> bool:
	if not has_free_seat() or crew.has(person):
		return false
	crew.append(person)
	open_doors()
	return true


func has_stretcher_space() -> bool:
	return casualties.size() < stretchers


## Claims a stretcher. False if it filled up while the vehicle was driving over.
func load_casualty(casualty: Casualty) -> bool:
	if not has_stretcher_space() or casualties.has(casualty):
		return false
	casualties.append(casualty)
	open_doors()
	return true


## Hands over everyone aboard. Called by Hospital when the vehicle drives in.
func deliver_casualties() -> int:
	var carried := casualties.duplicate()
	casualties.clear()
	if not carried.is_empty():
		open_doors()
	for casualty in carried:
		if is_instance_valid(casualty):
			casualty.deliver()
	return carried.size()


## Turns everyone out, spread behind the vehicle.
func unload() -> void:
	if not crew.is_empty():
		open_doors()
	var leaving := crew.duplicate()
	crew.clear()
	for i in leaving.size():
		var person: Person = leaving[i]
		if is_instance_valid(person):
			person.disembark(_dismount_point(i))


## Turns one person out, leaving everyone else aboard.
##
## **The single-passenger half of [method unload].** The bar's occupancy strip is clickable
## -- a seat with somebody in it is a button that puts that somebody on the pavement -- and
## "everybody out" is the wrong answer to a click on one seat.
##
## Only crew can be asked to leave this way. A casualty aboard is on their way to hospital
## and a suspect is on their way to a cell; neither is a passenger who can be told to hop
## out, and dropping one on the kerb would undo the job that put them there.
func put_down(person: Person) -> bool:
	if person == null or not crew.has(person):
		return false
	var seat := crew.find(person)
	crew.erase(person)
	open_doors()
	if is_instance_valid(person):
		person.disembark(_dismount_point(seat))
	return true


## A spot behind the car, alternating sides, snapped onto the navigation mesh so
## nobody is ever put down inside a wall.
func _dismount_point(index: int) -> Vector3:
	var side := 1.0 if index % 2 == 0 else -1.0
	var row := index / 2  # integer division: two per row, then step further out
	var sideways := side * dismount_side * float(1 + row)
	var spot := global_position + global_basis.z * dismount_back + global_basis.x * sideways
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spot)


## Swings whatever doors this unit has. Nothing, unless it is a [Vehicle] with some.
##
## A virtual rather than a check at each call site: `take_aboard` and `load_casualty` both
## want to open up as somebody gets in, and neither should have to know what kind of body
## it is attached to.
func open_doors() -> void:
	pass
