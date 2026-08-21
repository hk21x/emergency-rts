extends SceneTree

## Headless behaviour test for the RTS playground. Physics runs for real without a
## renderer, so this exercises the actual autopilot and picking code.
##
##   godot --headless --path . --script res://Game/smoke_test.gd
##
## Exits non-zero if any check fails.

const SCENE := "res://Game/Playground.tscn"
## A clear stretch of a north-south avenue near the middle of the district. Vehicle
## tests start here rather than anywhere convenient: the vehicle navigation mesh is
## the road network, so a car has to be *on* a road before it can be asked to go
## anywhere. x=20 is a band centre in CityGrid.X_BANDS -- kept there deliberately
## when the map grew, so the mid-map test positions stayed on real streets.
const ROAD := Vector3(20.0, 0.15, 5.0)
## Road bands are 10m wide; their (irregular) positions come from CityGrid's tables.
const BAND_WIDTH := 10.0
## Any civilian outfit will do; the roster check only cares that it has no service.
const CIVILIAN_SCENE := "res://Game/Civilians/BusinessMan_Suit.tscn"
## Frames allowed for the corner-to-corner drive -- half a kilometre with a turn at
## every junction, which measures around 3,800. Generous on purpose: this is a
## journey time, and a budget set close to it fails on any unrelated change that
## costs the car a second.
const CROSSING_BUDGET := 6000

var _failures := 0
## Every check that ran, so the summary can state its own total. Without it the only
## way to know the size of the suite is to count `ok` lines, and a number nobody
## measures is a number that drifts -- these documents have carried a stale check
## count more than once.
var _checks := 0
var _car: Vehicle
var _cars: Array[Vehicle] = []
var _ambulance: Vehicle
var _officer: Person
var _paramedic: Person
var _incidents: Node3D
var _hospital: Area3D
var _mission: Mission
var _camera: RTSCamera
var _controller: RTSController
## The transparent layer the bottom panels live on, and the two panels themselves.
var _bar: Control
var _unit_panel: PanelContainer
var _command_panel: PanelContainer
var _help: PanelContainer
var _portrait: Portrait
var _roster: RosterSidebar
var _grid: CommandGrid
var _call_list: CallList
var _board: CallBoard
var _station: Station
var _director: Director
var _menu: GameMenu
## How many player units the map itself shipped -- must be zero under the career.
var _shipped_units := -1
var _ring: Node3D
var _marker: Node3D
var _scene: Node3D
var _spawn_slot := Vector3.ZERO
var _opening_focus := Vector3.ZERO
var _opening_distance := 0.0


## True where a pedestrian is allowed to be: on a block, or on a road tile that
## carries a crossing. The inside of a junction box is nobody's.
func _pedestrian_legal(point: Vector3) -> bool:
	return CityGrid.walkable(
		int(floorf((point.x - CityGrid.ORIGIN) / CityGrid.TILE)),
		int(floorf((point.z - CityGrid.ORIGIN) / CityGrid.TILE)))


## The bodywork: the largest textured mesh under [param root].
##
## Picked by size rather than by node path so this works on a vehicle and on a person
## without knowing either layout. Requiring an albedo is what keeps it off the
## selection ring, which is a MeshInstance3D with a flat colour and would otherwise be
## found first on a character and sampled as "no paint at all".
func _body_mesh(root: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var most := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
			continue
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		if uvs.size() > most:
			most = uvs.size()
			best = mesh
	return best


## How far red leads the other two channels in a mesh's albedo, sampled at the mesh's
## own UVs: min(r-g, r-b), averaged. Positive is warm; olive and grey both land at or
## below zero. Returns -1.0 when there is nothing to sample, which fails the check that
## asks rather than passing it by default.
func _paint_warmth(mesh: MeshInstance3D) -> float:
	var material := mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		return -1.0
	var image := material.albedo_texture.get_image()
	if image == null:
		return -1.0
	# The imported atlases are VRAM-compressed; get_pixel needs them raw.
	if image.is_compressed():
		image.decompress()
	var arrays := mesh.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return -1.0
	var sum := Color(0, 0, 0)
	var taken := 0
	# Every 7th: enough to characterise a body, cheap enough to run in the suite.
	for i in range(0, uvs.size(), 7):
		var uv := uvs[i]
		sum += image.get_pixel(
			int(clampf(uv.x, 0.0, 0.999) * image.get_width()),
			int(clampf(uv.y, 0.0, 0.999) * image.get_height()))
		taken += 1
	if taken == 0:
		return -1.0
	var mean := sum / float(taken)
	return minf(mean.r - mean.g, mean.r - mean.b)


## True where "which side of the road" is a question with an answer: on a street, and
## clear of the station.
##
## Junctions are already excluded by [method _lane_offset] -- there is no lane inside
## one. The forecourt is excluded here because turning into it means crossing the
## oncoming lane, which is what turning into anything on the far side of a road means,
## and counting it would be measuring the manoeuvre rather than the driving.
##
## Turn *arcs* reach past the junction box and are deliberately left in. They are the
## reason the wrong-side count is a few percent rather than zero, and excluding them
## too made the check pass whether or not the route was in lane at all.
func _on_open_street(point: Vector3) -> bool:
	if _lane_offset(point) == Vector3.ZERO:
		return false
	return _station == null or _flat_distance(point, _station.global_position) > 20.0


## Offset from the centre line of the road band a point is on, or zero if it is in a
## junction (both axes in a band) or off the grid entirely.
func _lane_offset(point: Vector3) -> Vector3:
	var in_x := _in_band_x(point.x)
	var in_z := _in_band_z(point.z)
	if in_x == in_z:
		return Vector3.ZERO
	if in_x:
		return Vector3(
			point.x - CityGrid.band_centre_x(CityGrid.band_at_x(point.x)), 0.0, 0.0)
	return Vector3(
		0.0, 0.0, point.z - CityGrid.band_centre_z(CityGrid.band_at_z(point.z)))


## The text of the most recent block in the black box's log.
func _last_record(log: StuckLog) -> String:
	var file := FileAccess.open(log.log_path, FileAccess.READ)
	if file == null:
		return ""
	var whole := file.get_as_text()
	file.close()
	var blocks := whole.split("--- ")
	return blocks[blocks.size() - 1] if blocks.size() > 1 else whole


## Drives one fixed route with a junction turn in it, and hands back the speed at the
## point the car was turning **hardest**. Shared, so the dry and wet runs are provably
## the same drive.
##
## The apex is found by watching yaw rate rather than by naming a junction, and that is
## not a stylistic choice. This check used to measure the speed at the closest approach
## to a hardcoded corner at (-20, 20) -- and the route does not go anywhere near it: the
## car heads east first, and its closest approach is **38 metres**, reached at the very
## end while parking. So it was sampling a stationary car and passing `radius < 9.0`
## trivially. It had presumably been real when written and stopped being so when the
## district doubled to 260m and every junction moved; nothing pointed at the coordinate
## to say it had gone stale. Peak yaw rate cannot go stale -- wherever the turn is, that
## is where the car turns hardest.
##
## The `speed > 1.0` guard keeps the parking manoeuvre at the destination out of it: a
## car shuffling into its final position turns sharply at walking pace and would
## otherwise win.
func _corner_apex() -> float:
	await _place(Vector3(-20.0, 0.15, -25.0), PI)
	_car.issue(MoveOrder.new(Vector3(18.0, 0.0, 20.0)))
	var last_yaw := _car.rotation.y
	var hardest := 0.0
	var speed := 0.0
	for i in 1500:
		await physics_frame
		var yaw := _car.rotation.y
		var turned := absf(wrapf(yaw - last_yaw, -PI, PI))
		last_yaw = yaw
		var now := absf(_car.forward_speed)
		if turned > hardest and now > 1.0:
			hardest = turned
			speed = now
		if not _car.has_orders():
			break
	return speed


func _chip_for(unit: Unit) -> Control:
	for chip in _visible_chips():
		if _roster.unit_for(chip) == unit:
			return chip
	return null


func _commanded_units() -> Array[Unit]:
	var found: Array[Unit] = []
	for node in _scene.get_node("Units").get_children():
		var unit := node as Unit
		if unit != null and unit.service != Unit.Service.NONE:
			found.append(unit)
	return found


func _visible_tiles() -> Array[CommandIcon]:
	var found: Array[CommandIcon] = []
	for tile in _grid._tiles:
		if tile.visible:
			found.append(tile)
	return found


func _tile_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		found.append(tile.ability.id())
	return found


func _armed_tiles() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		if tile.armed:
			found.append(tile.ability.id())
	return found


func _active_tiles() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		if tile.active:
			found.append(tile.ability.id())
	return found


func _armed_id() -> StringName:
	return _controller.armed_ability.id() if _controller.armed_ability else &"none"


## What a right-click would mean, named.
##
## `"%s" % ability` prints `<RefCounted#-92233708...>`, so every `resolve()` assertion in
## this file used to fail with a line a reader could learn nothing from -- it could not tell
## Disarm from Apprehend from Move, which is precisely the distinction those legs exist to
## draw. Found while sabotage-proving the armed-response check, where the failing line was
## the only evidence available.
func _resolved_id(unit: Unit, target: Target) -> StringName:
	var ability := unit.resolve(target)
	return ability.id() if ability else &"nothing"


## The rows currently on the roster.
##
## Was `_visible_chips`, walking `Roster._chips` directly. It asks [RosterSidebar] now,
## because reaching into the panel's private members is what made ten checks fail at once
## the moment the panel was replaced -- the checks were coupled to an implementation, not
## to a behaviour.
func _visible_chips() -> Array:
	return _roster.rows() if _roster else []


# --- Calls -------------------------------------------------------------------

## The newest line on the log, or every line joined when [param all] is set.
## Every HUD panel that occupies space, as name -> screen rect.
##
## **Resolved by path, deliberately.** The checks this feeds used to walk a container's
## children, which meant anything reparented dropped silently out of coverage and
## anything renamed made the check pass on an empty set. Naming them means a rename
## fails loudly here instead, and the list is the one place to edit when a panel is
## added -- which is the honest cost of asserting on a layout at all.
##
## Hidden panels are skipped: the help card, the debrief and the shop are modal things
## that are *meant* to cover the screen when they are up.
func _hud_panels() -> Dictionary:
	var wanted := {
		"status": "HUD/Root/World/StatusStrip",
		"score": "HUD/Root/World/ScoreStrip",
		"objective": "HUD/Root/World/ObjectiveBar",
		"calls": "HUD/Root/World/CallList",
		"minimap": "HUD/Root/World/MinimapCard",
		"mapcontrols": "HUD/Root/World/MapControls",
		"radio": "HUD/Root/World/RadioLog",
		"controls": "HUD/Root/World/ControlsToggle",
		"unit": "HUD/Root/Bar/Row/PortraitBlock",
		"roster": "HUD/Root/Bar/Row/RosterBlock",
		"commands": "HUD/Root/Bar/Row/CommandBlock",
		# **Added when the selection bar overflowed onto the minimap in play.** The
		# invariant that would have caught it could not see the panel, because the panel
		# was not on this list -- a geometry guard only guards what it is handed.
		"selection": "HUD/Root/Bar/Row/SelectionBlock",
		"dispatch": "HUD/Root/Bar/Row/DispatchBlock",
	}
	var found := {}
	for name in wanted:
		var panel := _scene.get_node_or_null(str(wanted[name])) as Control
		if panel and panel.visible and panel.size.x > 1.0 and panel.size.y > 1.0:
			found[name] = panel.get_global_rect()
	return found


func _radio_text(radio: RadioLog, all := false) -> String:
	var lines := PackedStringArray()
	for child in radio.get_children():
		# **Looks inside the row.** Log lines were bare Labels until the UI kit's
		# notification frames arrived, and are now a Label inside a PanelContainer. A
		# reader that only understood the old shape returned "" for every line and took
		# three checks with it -- while the log itself was working perfectly.
		var label := child as Label
		if label == null:
			for inner in child.get_children():
				if inner is Label:
					label = inner as Label
		if label:
			lines.append(label.text)
	if lines.is_empty():
		return ""
	return " | ".join(lines) if all else lines[lines.size() - 1]


## The minimap as a control surface: left-click looks, right-click orders, and the
## view is drawn as the camera frustum's actual footprint on the ground.
## The map's own zoom buttons, which do what the wheel does for anyone who has not
## discovered the wheel.
##
## **Asserted on the camera moving, not on the buttons existing.** Twice this session a
## check passed on a feature that was doing nothing -- a pre-warm that only ever failed,
## and seven characters placed but never animated -- because the cheap half was the half
## that got tested.
## How many of [param mesh]'s triangles face the ground rather than the sky.
##
## **The one property of a flat marker that nothing else can witness.** Class, size,
## position and colour all survive a mesh being wound backwards, and `Markers._mesh`
## fills the normal array with `Vector3.UP` regardless -- so a bracket built face-down is
## byte-identical to a correct one in every reading the suite took, and simply invisible
## in the game. Found by sabotage, which reversed the winding and reddened nothing at all.
## This reads the vertices back and works the sign out from the winding itself.
func _faces_down(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var down := 0
	var i := 0
	while i + 2 < verts.size():
		# **Godot's front face is wound clockwise seen from the front**, so a triangle
		# facing +Y yields a *negative* y from this cross product. Getting that backwards
		# is how this helper first shipped: it called both correct meshes face-down and
		# went green on the sabotage that actually inverted them. Checked against
		# `SurfaceTool.generate_normals()` and a front-face raycast before trusting it.
		var facing := -(verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).y
		if facing <= 0.0:
			down += 1
		i += 3
	return down


func _triangles(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


## The number the strip's UNITS block is showing, or -1 if it has no such block.
func _strip_units(strip: ScoreStrip) -> int:
	var entry: Dictionary = strip._blocks.get(&"units", {})
	if entry.is_empty():
		return -1
	var label := entry["value"] as Label
	return int(label.text) if label and label.text.is_valid_int() else 0


func _visible_call_rows() -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	for row in _call_list._rows:
		if row.visible:
			found.append(row)
	return found


## Clears every incident and lets the board close the calls that held them, so each
## check starts from an empty board rather than from whatever the last one left.
func _clear_calls() -> void:
	await _clear_incidents()
	await _idle(4)


## Waits for a door to swing past [param target] radians, one way or the other.
##
## Deliberately a condition rather than a frame budget: headless runs process frames
## far above 60/s, so "wait 130 frames for a 2.2 second hold" is not 2.2 seconds, and
## the first version of this test failed on its own arithmetic rather than on the door.
func _await_door(door: Node3D, target: float, opening: bool, budget: int) -> bool:
	for i in budget:
		await _idle(1)
		var angle := absf(door.rotation.y)
		if angle >= target if opening else angle <= target:
			return true
	return false


## True where no firefighter could stand: not pavement, not park, not carriageway.
## True where no firefighter could stand: not pavement, not park, not carriageway.
## What the picking ray finds at a world point, named. Debug helper for the click checks.
func _raycast_from_camera(point: Vector3) -> String:
	var hit := _controller._raycast(_screen_of(point))
	if hit.is_empty():
		return "nothing"
	var collider: Object = hit.get("collider")
	return str(collider.name) if collider else "unnamed"


func _inside_a_building(point: Vector3) -> bool:
	var tile := CityGrid.tile_at(point)
	return not CityGrid.standable(tile.x, tile.y)


func _clear_cordons() -> void:
	for node in get_nodes_in_group(Cordon.GROUP):
		node.queue_free()
	_officer.clear_orders()
	await _idle(4)


## The water jet a person has instanced, or null if they have never sprayed anything.
func _jet_of(person: Person) -> GPUParticles3D:
	if person == null or not is_instance_valid(person):
		return null
	for child in person.get_children():
		var jet := child as GPUParticles3D
		if jet:
			return jet
	return null



## The first MeshInstance3D under [param root], for asking where a prop actually is
## rather than where its node was put.
func _first_mesh(root: Node) -> MeshInstance3D:
	var mesh := root as MeshInstance3D
	if mesh:
		return mesh
	for child in root.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null


## Every node under [param root], for counting widgets built at runtime.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child in root.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found



## The nearest ambient civilian to [param point], for a test that needs a bystander.
func _nearest_civilian(point: Vector3) -> Civilian:
	var best: Civilian = null
	var closest := INF
	for node in get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian == null:
			continue
		var gap := civilian.global_position.distance_to(point)
		if gap < closest:
			closest = gap
			best = civilian
	return best



## The scene file of the first mesh under an incident -- what it is actually wearing.
func _first_mesh_scene(node: Node) -> String:
	var body := node.get_node_or_null("Character") as Node3D
	return body.scene_file_path if body else ""


## Every material path used by any mesh in a built scene.
func _materials_in(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var packed := load(path) as PackedScene
	if packed == null:
		return found
	var root := packed.instantiate()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material and material.resource_path != "" \
					and not found.has(material.resource_path):
				found.append(material.resource_path)
	root.free()
	return found


## The burning cars a vehicle fire leaves at the kerb -- siblings of the fire in
## the Incidents container, so they are counted by name rather than by parentage.
func _wrecks() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in _incidents.get_children():
		if "Veh" in str(child.name):
			found.append(child as Node3D)
	return found


## The dispatch panel's row for a type, for driving the interface the way a
## player does.
## The dispatch row for a unit type, searched **through** the panel rather than across
## its immediate children.
##
## `DispatchPanel._build_row` parents each row to its inner grid, so the rows are
## grandchildren and a scan of `panel.get_children()` never matched one. This returned
## null every time it was ever called, and the one caller then threw on
## `get_global_rect()` -- which silently abandoned the rest of that check, so the click
## path it was written to cover had never actually been exercised.
## The roster chip standing for a unit of [param id] sitting in the station.
##
## Was a row in the DISPATCH block until August 2026, when that block was hidden and
## sending a unit out moved onto the roster's dimmed standby chips. Same helper name and
## same job -- find the control that dispatches this type -- so the checks that use it
## did not have to change.
func _dispatch_row(id: StringName) -> Control:
	var roster := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/RosterBlock/Body/Roster") as RosterSidebar
	if roster == null:
		return null
	# Asked of the panel rather than walked out of its internals. This reached into
	# `roster._chips` and kept working for exactly as long as the panel had a member by
	# that name; the swap turned it into a runtime error that silently truncated the check
	# around it.
	for row in roster.rows():
		var waiting := roster.standby_for(row)
		if not waiting.is_empty() and waiting.get("id", &"") == id:
			return row
	return null


## A fixture unit: dispatched through the station -- the only door units come
## through now -- then stood on a chosen spot.
func _dispatch_to(id: StringName, spot: Vector3) -> Unit:
	var unit := _station.dispatch(id)
	if unit == null:
		push_error("fixture dispatch failed for %s" % id)
		return null
	unit.global_position = spot
	unit.global_rotation = Vector3.ZERO
	unit.mark_spawn()
	return unit


func _buy(id: StringName, count: int) -> void:
	_station.funds += _station.price(id) * count
	for i in count:
		_station.purchase(id)


## Removes a spare unit bought for one test, so the owned fleet stays the canonical
## seven the fixtures established.
func _dissolve(unit: Unit, id: StringName) -> void:
	if unit and is_instance_valid(unit):
		unit.queue_free()
	_station.owned[id] = maxi(0, int(_station.owned.get(id, 0)) - 1)
	_station._save_career()
	_station.roster_changed.emit()


## Parks the whole shift on the station forecourt, well out of ON_SCENE_RADIUS of
## anywhere the director may open a call, so nothing reads as attended by accident.
func _park_the_shift() -> void:
	var index := 0
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit == null or unit.service == Unit.Service.NONE:
			continue
		unit.clear_orders()
		unit.global_position = _station.global_position \
			+ Vector3(4.0 * (index % 4) - 6.0, 0.2, 4.0 * (index / 4))
		unit.velocity = Vector3.ZERO
		index += 1
	await _wait(4)


## Deals with everything at a scene from code -- douse the fire, treat and deliver the
## casualty -- so the pacing tests measure the director, not a drive across town.
func _resolve_call(call: Call) -> void:
	for incident in call.incidents.duplicate():
		if not is_instance_valid(incident):
			continue
		var fire := incident as Fire
		if fire:
			fire.douse(5.0)
			continue
		var casualty := incident as Casualty
		if casualty:
			casualty.treat(1.0)
			casualty.deliver()
			continue
		var suspect := incident as Suspect
		if suspect:
			suspect.detain(1.0)
			suspect.deliver()
			continue
		# A cylinder is made safe by being cold with nothing burning near it, and the
		# fire beside it is dealt with by the Fire branch above -- so all this has to do
		# is take the heat out.
		var hazard := incident as Hazard
		if hazard:
			hazard.cool(2.0)
			continue
		# A shed load and a written-off car are both worked down to nothing. They share
		# the name because they share the verb -- see [ClearAbility].
		if incident.has_method("clear"):
			incident.call("clear", 1.0)


## Stands the director down and returns the mission to the scripted rules, so the
## tests after these run against the same game the ones before them did.
func _end_freeplay() -> void:
	_director.active = false
	_mission.scoring = false
	await _clear_calls()
	_reset_mission()


# --- Camera ------------------------------------------------------------------

## Runs until the car reports its order finished, or gives up. Returns whether it
## arrived, so a stuck car fails loudly instead of hanging the suite.
func _await_orders_done(unit: Unit, timeout_frames: int) -> bool:
	for i in timeout_frames:
		if not unit.has_orders():
			return true
		await physics_frame
	return false


func _await_arrival(timeout_frames: int, trace := false) -> bool:
	for i in timeout_frames:
		if not _car.has_orders():
			return true
		if trace and i % 20 == 0:
			print("    t%04d %s" % [i, _car_state()])
		await physics_frame
	return false


func _place(position: Vector3, yaw := 0.0) -> void:
	await _place_unit(_car, position, yaw)


func _place_unit(unit: Unit, position: Vector3, yaw := 0.0) -> void:
	unit.clear_orders()
	unit.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	unit.velocity = Vector3.ZERO
	await _wait(12)


## Screen-space bounding box of some units, as [top_left, bottom_right].
func _screen_bounds(units: Array[Vehicle]) -> Array:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for unit in units:
		var point := _screen_of(unit.global_position)
		low.x = minf(low.x, point.x)
		low.y = minf(low.y, point.y)
		high.x = maxf(high.x, point.x)
		high.y = maxf(high.y, point.y)
	return [low, high]


func _spawn_fire(position: Vector3, intensity: float) -> Fire:
	var fire: Fire = (load("res://Game/Incidents/Fire.tscn") as PackedScene).instantiate()
	_incidents.add_child(fire)
	fire.global_position = position
	fire.intensity = intensity
	return fire


func _spawn_hazard(position: Vector3) -> Hazard:
	var hazard: Hazard = (load("res://Game/Incidents/Hazard.tscn") as PackedScene).instantiate()
	_incidents.add_child(hazard)
	hazard.global_position = position
	return hazard


func _spawn_suspect(position: Vector3) -> Suspect:
	var suspect: Suspect = (load("res://Game/Incidents/Suspect.tscn") as PackedScene).instantiate()
	_incidents.add_child(suspect)
	suspect.global_position = position
	return suspect


func _spawn_casualty(position: Vector3) -> Casualty:
	var casualty: Casualty = (load("res://Game/Incidents/Casualty.tscn") as PackedScene).instantiate()
	_incidents.add_child(casualty)
	casualty.global_position = position
	return casualty


## Fires spread, so a leftover from one test would corrupt the next one's counts.
## Children of one of the map's ambient containers.
func _ambient(node_name: String) -> Array:
	var holder := _scene.get_node_or_null(node_name)
	return holder.get_children() if holder else []


func _first_civilian() -> Civilian:
	var crowd := _civilians()
	return crowd[0] if not crowd.is_empty() else null


func _civilians() -> Array[Civilian]:
	var found: Array[Civilian] = []
	for node in _ambient("Crowd"):
		var civilian := node as Civilian
		if civilian:
			found.append(civilian)
	return found


## Empties the district of everyone who is not the player's. See the note in _run.
func _clear_ambient() -> void:
	for holder_name in ["Crowd", "Traffic"]:
		for node in _ambient(str(holder_name)):
			node.queue_free()
	await _wait(4)


## Stops every player unit starting work on its own, and lets them again.
##
## For checks that need an incident left alone. Auto-engage is deliberately on by default,
## so a test that wants "nobody touches this" has to say so.
func _stand_down() -> void:
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit:
			unit.auto_engage = false


func _stand_to() -> void:
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit:
			unit.auto_engage = true


func _clear_incidents() -> void:
	_officer.clear_orders()
	for node in get_nodes_in_group(Incident.GROUP):
		node.queue_free()
	await _wait(4)


func _reset_mission() -> void:
	# Through `_set_state` rather than by assignment, because a scripted win now raises
	# a **modal** card that holds the mouse until it is dismissed -- and a bare
	# assignment moves the state without telling the HUD, leaving that card standing
	# over the district. It cost seven click checks their targets the first time, none
	# of them anywhere near the mission tests that caused it.
	_mission._set_state(Mission.State.RUNNING)
	_mission.fires_out = 0
	_mission.casualties_saved = 0
	_mission.casualties_lost = 0
	_mission.scoring = false
	_mission.score = 0
	_mission.calls_cleared = 0
	_mission.calls_failed = 0
	# **The house account, or it follows the suite around.** Every shift exit now sweeps
	# outstanding repair bills onto `Station.debt`, and a residual bill from one of the
	# driving checks would otherwise ride along and fail an affordability check a long way
	# from its cause -- the kind of failure nobody traces back.
	_station.debt = 0
	_mission.crew_lost = 0
	_mission.crew_recovered = 0
	_mission.lanes_cleared = 0


func _target_for(incident: Incident) -> Target:
	var target := Target.new()
	target.position = incident.global_position
	target.collider = incident
	target.incident = incident
	return target


func _find_ability(unit: Unit, id: StringName) -> Ability:
	for ability in unit.abilities():
		if ability.id() == id:
			return ability
	return null


## Puts the car in the middle of the view so unproject_position stays on screen.
func _focus_camera_on_car() -> void:
	_camera.focus = Vector3(_car.global_position.x, 0.0, _car.global_position.z)
	_camera._apply_transform()


func _screen_of(world_position: Vector3) -> Vector2:
	return _camera.unproject_position(world_position)


func _press_key(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		root.push_input(event)
		await _idle(2)


## Clears a debrief modal out of the way before a synthesised click, the way a player
## would with the CONTINUE button.
##
## Winning a scripted shout now raises a card that **holds the mouse** until it is
## dismissed, and `_evaluate` declares that win whenever the last incident resolves
## outside a scored shift -- which is most of this suite. So a fire doused in a radio
## test left a modal standing over the district, and the next four click checks missed
## targets they were nowhere near responsible for. Dismissed here rather than in each
## test: no click check is about the modal, and the modal's own behaviour is asserted
## where it belongs, on the tutorial's finished shout.
func _dismiss_any_modal() -> void:
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	if card and card.visible:
		card.hide_card()


func _click(button: int, screen_position: Vector2, shift := false) -> void:
	_dismiss_any_modal()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = screen_position
		event.global_position = screen_position
		root.push_input(event)
		await _idle(2)


## Press, move, release: a left-drag, which the controller reads as a box select.
func _drag(from: Vector2, to: Vector2) -> void:
	_dismiss_any_modal()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	root.push_input(press)
	await _idle(2)

	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	root.push_input(motion)
	await _idle(2)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	root.push_input(release)
	await _idle(2)


func _car_state() -> String:
	var agent := _car.get_node("NavigationAgent") as NavigationAgent3D
	var next := agent.get_next_path_position()
	return "pos=(%.1f, %.2f, %.1f) speed=%.1f floor=%s target=(%.1f, %.1f) next=(%.1f, %.1f) reach=%s pathlen=%d fin=%s" % [
		_car.global_position.x, _car.global_position.y, _car.global_position.z,
		_car.forward_speed, _car.is_on_floor(),
		_car.move_target.x, _car.move_target.z,
		next.x, next.z,
		agent.is_target_reachable(),
		agent.get_current_navigation_path().size(),
		agent.is_navigation_finished(),
	]


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True if a point lies in one of the map's road bands. A point is on a road if
## *either* axis falls in a band -- that is what makes a junction a junction.
##
## Station and hospital forecourts are drivable too and are not bands, so this is a
## sufficient test for "on the street", not a complete one for "drivable".
func _on_a_road(point: Vector3) -> bool:
	return _in_band_x(point.x) or _in_band_z(point.z)



func _in_band_x(value: float) -> bool:
	return absf(value - CityGrid.band_centre_x(CityGrid.band_at_x(value))) \
		<= BAND_WIDTH * 0.5


func _in_band_z(value: float) -> bool:
	return absf(value - CityGrid.band_centre_z(CityGrid.band_at_z(value))) \
		<= BAND_WIDTH * 0.5


func _settle(frames: int) -> void:
	await _wait(frames)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## Yields on idle frames. Synthetic input must be pushed from here, not from inside
## a physics step.
func _idle(frames: int) -> void:
	for i in frames:
		await process_frame


## Checks run, per section file.
##
## **The reason the split was worth doing.** A runtime error inside a check skips the rest
## of that check silently: the suite goes on, reports `all checks passed`, and only the
## total falls -- which is how two checks stopped short for months and cost three out of six
## hundred without anybody noticing. One number for the whole suite makes that invisible.
## Fourteen numbers make it legible: a section that quietly loses a check moves its own
## line, and the line names the file to open.
##
## Attributed from the call stack rather than from markers in the run order, so a check
## added to a section file is counted there with nothing else to remember.
var _by_file := {}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	var stack := get_stack()
	var where: String = str(stack[1].get("source", "?")).get_file() if stack.size() > 1 \
		else "?"
	_by_file[where] = int(_by_file.get(where, 0)) + 1
	if condition:
		print("  ok    ", description)
	else:
		print("  FAIL  ", description)
		_failures += 1


## The summary carries its own total, so nothing downstream has to count `ok` lines to
## find out how big the suite is. Both forms keep the exact substrings the Stop hook
## and the reporting agents grep for -- "all checks passed" and "check(s) failed" --
## so the count is additive rather than a format change.
func _finish() -> void:
	_report_sections()
	if _failures == 0:
		print("\nall checks passed (%d)" % _checks)
		quit(0)
	else:
		print("\n%d check(s) failed of %d" % [_failures, _checks])
		quit(1)


## The per-section tally, and a guard that it accounts for every check.
##
## The sum is asserted rather than assumed: attribution walks the call stack, and a check
## called from a helper rather than directly from a test would land against the helper's
## file. That is fine -- it is still a real file -- but a tally that did not add up to the
## total would mean checks were being attributed to nothing at all, and the tally would
## quietly stop being the truncation detector it exists to be.
func _report_sections() -> void:
	var files := _by_file.keys()
	files.sort()
	var total := 0
	print("")
	for file: String in files:
		var count: int = _by_file[file]
		total += count
		print("  %5d  %s" % [count, file])
	if total != _checks:
		# **Failed rather than merely printed.** A `!!` line among 1,126 `ok` lines is
		# exactly the sort of thing that gets scrolled past, and an instrument nobody
		# notices has stopped being one. This is a guard on the tally, not a check of the
		# game, so it does not add to the count -- it just refuses to let the run pass.
		print("  !! per-section tally %d does not match the total %d" % [total, _checks])
		_failures += 1
