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

@export var display_name := "Unit"
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
	var material: StandardMaterial3D = mesh.material_override.duplicate()
	if material == null:
		return
	var shades := Palette.service(service)
	material.albedo_color = Color(shades[0].r, shades[0].g, shades[0].b, 0.85)
	mesh.material_override = material


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
