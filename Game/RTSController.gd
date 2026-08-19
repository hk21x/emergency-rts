extends Node3D
class_name RTSController

## Selection and order issuing.
##
## Left click picks a unit, dragging box-selects, shift adds to the selection.
## Right click asks each selected unit which of its abilities best fits whatever was
## clicked and queues the resulting order — the controller never names a verb itself,
## so new abilities work here without touching this file.
##
## Picking uses a physics raycast from the camera, so orders land on the surface
## actually clicked rather than on an assumed ground plane. Box selection instead
## projects unit positions to the screen, which is cheaper and catches units whose
## visible body is partly occluded.

signal selection_changed(units: Array[Unit])
## Emitted when a targeted ability is armed or cleared, so the UI can reflect it.
signal armed_ability_changed(ability: Ability)

const RAY_LENGTH := 4000.0
## Collision layers the picking ray ignores: ambient traffic (64) and the crowd (128).
##
## They are solid bodies -- they stand on the ground and stop against walls -- but
## they are not things the player clicks, and a body the ray stops on is a click
## consumed. Marking them unselectable is not enough on its own: the ray still ends
## there, so a pedestrian wandering between the camera and an officer would make that
## officer unclickable until they moved.
const AMBIENT_LAYERS := 64 | 128
const PICK_MASK := 0xFFFFFFFF & ~AMBIENT_LAYERS
## Drag shorter than this (in pixels) counts as a click, not a box.
const DRAG_THRESHOLD := 6.0
const CONTROL_GROUP_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
## Keys abilities may bind to, in the order they sit on the keyboard's bottom row. The
## command grid is laid out in this order, so a tile's position along the row matches
## the key under the player's hand.
##
## The cluster is this narrow because almost everything else is taken, and taken by a
## poller rather than a handler: RTSCamera reads W A S D and Q E through
## Input.get_vector every frame, so those keys pan and rotate whether or not the event
## was consumed. F is focus, R is respawn, Esc disarms and 1-9 are control groups.
## G sits off the end of that row because the row ran out: seven keys, eight verbs. It
## is the nearest free key to the cluster -- A S D F are camera and focus. L continues
## the home row past K, and was added when the hazard's Cool verb needed a twelfth.
## Ceiling on destination markers. Six units with long queues could otherwise put a
## hundred nodes on the map, and past a couple of dozen the display is noise anyway.
const MAX_MARKERS := 40
## How much smaller a queued marker is than the one being driven at. The current order
## keeps the bob and the spin; the rest sit still, which is the difference the eye reads
## before it reads the size.
const QUEUED_SCALE := 0.55

const COMMAND_KEYS := [
	KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L,
	KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P]

@export var move_marker_path: NodePath
@export var selection_box_path: NodePath
@export var camera_path: NodePath

@export_group("Feedback")
@export var marker_height := 0.06
@export var marker_spin_speed := -1.6
@export var marker_bob_height := 0.25
@export var marker_bob_speed := 3.0

var selection: Array[Unit] = []
## Ability waiting for a target click, armed from the command bar.
var armed_ability: Ability

var _marker: Node3D
var _markers: Array[Node3D] = []
var _box: Control
var _camera: RTSCamera
var _elapsed := 0.0
var _drag_start := Vector2.ZERO
var _dragging := false
var _control_groups := {}


func _ready() -> void:
	_marker = get_node_or_null(move_marker_path) as Node3D
	# Same swap the selection bracket gets in `Unit`: the scene ships a torus and the
	# shape is decided here, so the two generators that build a MoveMarker stay
	# placeholders and never need regenerating to change how an order looks. Duplicates
	# made for queued orders share this mesh, which is what keeps them consistent.
	var marker_mesh := _marker as MeshInstance3D
	if marker_mesh:
		marker_mesh.mesh = Markers.reticle(0.85)
	_box = get_node_or_null(selection_box_path) as Control
	_camera = get_node_or_null(camera_path) as RTSCamera
	if _marker:
		_marker.visible = false
		_markers.append(_marker)


# --- Selection API -----------------------------------------------------------

## The unit the HUD treats as representative of the selection.
func primary() -> Unit:
	return selection[0] if not selection.is_empty() else null


func select(units: Array[Unit], additive := false) -> void:
	var next: Array[Unit] = []
	if additive:
		next.assign(selection)
	for unit in units:
		if unit != null and is_instance_valid(unit) and not next.has(unit):
			next.append(unit)
	_apply_selection(next)


func toggle(unit: Unit) -> void:
	var next: Array[Unit] = []
	next.assign(selection)
	if next.has(unit):
		next.erase(unit)
	else:
		next.append(unit)
	_apply_selection(next)


func clear_selection() -> void:
	_apply_selection([])


func _apply_selection(units: Array[Unit]) -> void:
	for unit in selection:
		if is_instance_valid(unit) and not units.has(unit):
			unit.set_selected(false)
	for unit in units:
		unit.set_selected(true)
	selection = units
	_disarm()
	selection_changed.emit(selection)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("car_reset"):
		for unit in selection:
			unit.respawn()
		return

	if event.is_action_pressed("cam_focus"):
		follow(primary())
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE and armed_ability:
			_disarm()
			return
		var slot := CONTROL_GROUP_KEYS.find(event.physical_keycode)
		if slot >= 0:
			_handle_control_group(slot, event.ctrl_pressed)
			return
		# Ctrl is the control-group modifier, so a bare letter is the only thing that
		# can mean a command.
		if not event.ctrl_pressed and _handle_hotkey(event.physical_keycode):
			return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		if _box:
			_box.show_box(_drag_start, event.position)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_dragging = true
		elif _dragging:
			_dragging = false
			if _box:
				_box.hide_box()
			if _drag_start.distance_to(event.position) < DRAG_THRESHOLD:
				_handle_click(event.position, event.shift_pressed)
			else:
				_handle_box(Rect2(_drag_start, event.position - _drag_start).abs(),
					event.shift_pressed)
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Right click cancels an armed ability rather than issuing an order, which is
		# what a player expects from a mis-click on the command bar.
		if armed_ability:
			_disarm()
			return
		_handle_order(event.position, event.shift_pressed)


func _handle_click(screen_position: Vector2, additive: bool) -> void:
	var hit := _raycast(screen_position)
	var unit := hit.get("collider") as Unit
	# Box select checks this too. Without it here, clicking any solid thing that
	# happens to be a Unit picks it up -- a pedestrian, a passing taxi, an officer
	# riding in a car -- none of which the player commands.
	if unit != null and not unit.is_selectable():
		unit = null

	if armed_ability:
		_fire_armed(Target.from_hit(hit))
		return

	if unit == null:
		if not additive:
			clear_selection()
		return
	if additive:
		toggle(unit)
	else:
		select([unit])


func _handle_box(rect: Rect2, additive: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var found: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit == null:
			continue
		# Behind the camera, unproject_position still returns a point, which would
		# select units the player cannot even see.
		if not unit.is_selectable() or camera.is_position_behind(unit.global_position):
			continue
		if rect.has_point(camera.unproject_position(unit.global_position)):
			found.append(unit)
	if not found.is_empty() or not additive:
		select(found, additive)


func _handle_order(screen_position: Vector2, queue: bool) -> void:
	if selection.is_empty():
		return
	# Selected units are usually excluded so a right-click near one's own feet reaches the
	# ground rather than the unit -- but a **vehicle with a crew aboard** is worth being
	# able to click, because clicking the appliance you have just parked at a scene and
	# having the crew get out is the obvious gesture. See [UnloadAbility.score].
	var exclude: Array[RID] = []
	for unit in selection:
		var vehicle := unit as Vehicle
		if vehicle and not vehicle.crew.is_empty():
			continue
		exclude.append(unit.get_rid())
	var target := Target.from_hit(_raycast(screen_position, exclude))
	if target == null:
		return
	# **Slots are assigned by navigation layer, and by who is nearest.** Vehicles path on
	# the carriageway and people on the pavement, so one formation for both would put a
	# car on a kerb; and handing slots out in selection order makes eight units cross each
	# other's paths on every group move.
	var slots := _assign_slots(target.position)
	for unit in selection:
		var slot: Vector2i = slots.get(unit, Vector2i(0, 1))
		target.slot_index = slot.x
		target.slot_count = slot.y
		var ability := unit.resolve(target)
		if ability == null:
			continue
		# An **instant** ability has no order to issue -- `make_order` returns nothing --
		# so one that wins a right-click has to be executed. Before this, an instant that
		# scored highest silently did nothing at all: the click resolved to Unload, the
		# order came back null, and the crew stayed where they were.
		if ability.is_instant():
			ability.execute(unit)
		else:
			unit.issue(ability.make_order(unit, target), queue)


## Orders the selection to a world point directly -- the minimap's right-click, which
## has a map position but no camera ray to cast. Resolution is the same scoring the
## main-view right-click runs, against a bare point target, so Move wins it.
func order_at_point(point: Vector3, queue := false) -> void:
	if selection.is_empty():
		return
	# Nowhere outside the district is a place to be sent. This is the one funnel where a
	# bare world point becomes an order without a raycast having proved it is somewhere
	# real, and an off-map destination does not fail loudly: the navigation agent clamps
	# it to the nearest reachable point, which can be the opposite side of the city, and
	# the unit drives off the wrong way with no sign anything is wrong.
	var edge := CityGrid.MAP_HALF
	if absf(point.x) > edge or absf(point.z) > edge:
		push_warning("order_at_point ignored a destination off the map: %s" % point)
		return
	var target := Target.new()
	target.position = point
	# Slots here too, or a minimap right-click stacks the group where a world one spreads
	# it -- the same order given two ways should not behave two ways.
	var slots := _assign_slots(point)
	for unit in selection:
		var slot: Vector2i = slots.get(unit, Vector2i(0, 1))
		target.slot_index = slot.x
		target.slot_count = slot.y
		var ability := unit.resolve(target)
		if ability:
			unit.issue(ability.make_order(unit, target), queue)


func _handle_control_group(slot: int, assign: bool) -> void:
	if assign:
		var members: Array[Unit] = []
		members.assign(selection)
		_control_groups[slot] = members
		return
	var stored: Array = _control_groups.get(slot, [])
	var alive: Array[Unit] = []
	for unit in stored:
		if is_instance_valid(unit):
			alive.append(unit)
	_control_groups[slot] = alive
	select(alive)


# --- Command bar hooks -------------------------------------------------------

## Every ability the current selection offers, deduplicated by id, ordered by hotkey.
##
## The command grid draws from this and the hotkey handler resolves against it, so a
## tile the player can see and the key printed on it are always the same ability. Two
## separate walks of the selection would eventually disagree.
##
## Sorted by key rather than left in declaration order so the tiles read along the row
## in the same order as the keys under the player's hand. Declaration order still
## decides score ties -- that reads `unit.abilities()`, not this.
func available_abilities() -> Array[Ability]:
	var found: Array[Ability] = []
	var seen := {}
	for unit in selection:
		for ability in unit.abilities():
			if seen.has(ability.id()):
				continue
			seen[ability.id()] = true
			found.append(ability)
	found.sort_custom(_by_hotkey)
	return found


## Position along [constant COMMAND_KEYS], with anything unbound last. Sorting by the
## raw keycode would put the tiles in alphabetical order, which is not the order the
## keys are in under the player's hand.
func _by_hotkey(a: Ability, b: Ability) -> bool:
	return _key_order(a) < _key_order(b)


func _key_order(ability: Ability) -> int:
	var slot := COMMAND_KEYS.find(ability.hotkey())
	return COMMAND_KEYS.size() if slot < 0 else slot


## Centres the camera on a unit and keeps it there.
func follow(unit: Unit) -> void:
	if unit and _camera:
		_camera.follow(unit)


## Jumps the camera to a place and stops following whatever it was following. Used by
## the incident list, which is about looking rather than about who is selected.
func look_at_point(point: Vector3) -> void:
	if _camera == null:
		return
	_camera.stop_following()
	_camera.focus = Vector3(point.x, 0.0, point.z)


## Runs the ability bound to [param keycode], if the selection offers one.
## Returns whether the key was claimed.
func _handle_hotkey(keycode: Key) -> bool:
	for ability in available_abilities():
		if ability.hotkey() == keycode:
			activate(ability)
			return true
	return false


## Runs an instant ability across the selection, or arms a targeted one.
func activate(ability: Ability) -> void:
	if ability == null or selection.is_empty():
		return
	if ability.is_instant():
		for unit in selection:
			ability.execute(unit)
		return
	armed_ability = ability
	armed_ability_changed.emit(armed_ability)


func _fire_armed(target: Target) -> void:
	var ability := armed_ability
	_disarm()
	if target == null:
		return
	for unit in selection:
		# can_target, not score: an ability may decline every right-click and still be
		# perfectly targetable once the player has armed it deliberately.
		if ability.can_target(unit, target):
			unit.issue(ability.make_order(unit, target))


func _disarm() -> void:
	if armed_ability == null:
		return
	armed_ability = null
	armed_ability_changed.emit(null)


# --- Feedback ----------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	_prune_selection()
	_update_markers()


## Drops freed units so the selection never holds dangling references, and units that
## have left play -- someone who just climbed into a car should not stay selected.
func _prune_selection() -> void:
	var alive: Array[Unit] = []
	for unit in selection:
		if is_instance_valid(unit) and unit.is_selectable():
			alive.append(unit)
	if alive.size() != selection.size():
		for unit in selection:
			if is_instance_valid(unit) and not alive.has(unit):
				unit.set_selected(false)
		selection = alive
		selection_changed.emit(selection)


## One marker per selected unit that is heading somewhere, from a pool grown on
## demand by cloning the marker the map generator provided.
## Hands every selected unit an index into a formation, grouped by what it can drive on.
##
## Returns unit -> (index, count). Everything else about the spread -- where the slots
## actually sit, and whether one is reachable -- belongs to [MoveAbility], because that is
## the only verb it means anything to.
func _assign_slots(centre: Vector3) -> Dictionary:
	var groups := {}
	for unit in selection:
		if not is_instance_valid(unit):
			continue
		var lane := 1 if unit is Vehicle else 0
		if not groups.has(lane):
			groups[lane] = []
		groups[lane].append(unit)

	var slots := {}
	for lane in groups:
		var members: Array = groups[lane]
		# Nearest-first, so the unit closest to the point takes the nearest slot and the
		# group does not turn itself inside out getting there.
		members.sort_custom(func(a: Unit, b: Unit) -> bool:
			return a.global_position.distance_squared_to(centre) \
				< b.global_position.distance_squared_to(centre))
		for i in members.size():
			slots[members[i]] = Vector2i(i, members.size())
	return slots


func _update_markers() -> void:
	if _marker == null:
		return
	# **The whole queue, not just the order in hand.** Shift-right-click has queued orders
	# since phase 1 and nothing ever drew them, so a player who lined up three stops had
	# no way to see what they had asked for -- or to notice they had queued one by
	# accident. Walking `orders` instead of `current_order()` is the entire change.
	var points: Array[Vector3] = []
	var queued: Array[bool] = []
	for unit in selection:
		if not is_instance_valid(unit):
			continue
		for i in unit.orders.size():
			if points.size() >= MAX_MARKERS:
				break
			var order := unit.orders[i]
			if order and order.has_destination():
				points.append(order.destination())
				queued.append(i > 0)

	while _markers.size() < points.size():
		var clone := _marker.duplicate() as Node3D
		_marker.get_parent().add_child(clone)
		_markers.append(clone)

	var bob := marker_height \
		+ marker_bob_height * (0.5 + 0.5 * sin(_elapsed * marker_bob_speed))
	for i in _markers.size():
		var node := _markers[i]
		node.visible = i < points.size()
		if not node.visible:
			continue
		# Told apart by size and stillness rather than colour: the marker is a duplicated
		# scene, and recolouring one would mean its own material per copy.
		var later: bool = queued[i]
		node.global_position = points[i] + Vector3.UP * (bob if not later else marker_height)
		node.rotation.y = 0.0 if later else _elapsed * marker_spin_speed
		node.scale = Vector3.ONE * (QUEUED_SCALE if later else 1.0)


# --- Picking -----------------------------------------------------------------

## Casts from the camera through a screen point into the world.
func _raycast(screen_position: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = PICK_MASK
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)
