extends VBoxContainer
class_name RosterSidebar

## Hosts the Emergency Ops unit sidebar and connects it to the district.
##
## **A drop-in for [Roster]**, the same tactic the shop swap used: it keeps `controller`,
## `station` and `standby_chip`, so [HUD] and [TutorialDirector] need no changes and the
## swap is one line of `HUD.tscn`.
##
## The kit's sidebar models a roster of [UnitInstance]s -- a callsign, a status, a
## condition -- which is a richer thing than the chips it replaces. This maps our two
## populations onto it:
##
## - **Units on the map** become EN_ROUTE, ON_SCENE or RETURNING, read from what they are
##   actually doing, and carry their real health as `condition`.
## - **Units in the house** become AVAILABLE, one row per unit rather than per type,
##   because the fleet count in the top bar counts units and a roster that disagreed with
##   it would be worse than no roster.
##
## Selecting an available one **dispatches it**, which is what clicking a dimmed standby
## chip did. That behaviour has no equivalent in the kit -- its sidebar assumes every unit
## is already in the world -- so it lives here rather than in `ui/`.

var controller: RTSController: set = _set_controller
var station: Station

var _sidebar: UnitSidebar
## The world unit or catalogue row behind each [UnitInstance] the sidebar is showing.
var _behind := {}
var _dirty := true

## Order class name -> what to put in the row's task column.
const TASKS := {
	"Extinguish": "Fighting fire", "Treat": "Treating", "Apprehend": "Arresting",
	"Escort": "Escorting", "Collect": "Collecting", "Stretcher": "Stretchering",
	"Secure": "Securing", "Clear": "Clearing", "Connect": "On hydrant",
	"Move": "En route", "Return": "Returning", "Land": "Landing",
	"TakeOff": "Lifting", "Board": "Boarding", "LoadSuspect": "Loading",
}


## Set [code]LEGACY_ROSTER=1[/code] to run the chip strip this panel replaced.
##
## **A bisect switch, not a fallback.** Three hard crashes arrived the day the sidebar
## landed -- two with an identical unsymbolised stack in the renderer, one as heap
## corruption noticed on an unrelated thread -- and none could be reproduced, headlessly
## or under a windowed stress probe. Guessing at the cause had already been wrong twice.
## This makes the question answerable in one play session: run with the old roster, and
## either the crashes stop (the sidebar is implicated) or they do not (it is exonerated
## and the search was in the wrong place).
##
## An environment variable rather than an edit, so the suite keeps exercising the real
## panel and stays green while the question is open.
## **The requisition sidebar is the default; `LEGACY_ROSTER=1` runs the chip strip.**
##
## The strip is kept as a bisect fallback, not as the shipping roster. Four hard crashes
## have arrived with the sidebar, all on the same interaction (clicking a unit) and all
## with an identical unsymbolised stack in the renderer, while the strip has never crashed
## once -- but the fault is still not understood, and switching the default away from the
## roster that was asked for is not a call this file gets to make on its own.
const LEGACY_ENV := "LEGACY_ROSTER"

var _legacy: Control


func _ready() -> void:
	if OS.get_environment(LEGACY_ENV) != "":
		_legacy = VBoxContainer.new()
		_legacy.set_script(load("res://Game/UI/Roster.gd"))
		_legacy.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_legacy)
		print("[roster] LEGACY_ROSTER set -- running the old chip strip")
		return
	var packed := load("res://ui/unit_sidebar.tscn") as PackedScene
	if packed == null:
		push_warning("RosterSidebar could not load the sidebar scene")
		return
	_sidebar = packed.instantiate() as UnitSidebar
	_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sidebar)
	_sidebar.unit_selected.connect(_on_selected)
	_sidebar.focus_requested.connect(_on_focused)
	_sidebar.request_units_pressed.connect(_on_request_units)


func _set_controller(value: RTSController) -> void:
	controller = value
	if _legacy:
		_legacy.controller = value
	if controller and not controller.selection_changed.is_connected(_on_selection_changed):
		controller.selection_changed.connect(_on_selection_changed)


func _on_selection_changed(_units: Array[Unit]) -> void:
	_dirty = true


## Rebuilt on a tick rather than on every signal: units appear, are dispatched, take
## damage and finish orders constantly, and the roster only has to be right, not instant.
func _process(_delta: float) -> void:
	if _legacy:
		_process_legacy()
		return
	if _dirty:
		_dirty = false
	_refresh()


## One [UnitInstance] per unit under command, plus one per unit waiting in the house.
func _refresh() -> void:
	if _sidebar == null:
		return
	var wanted: Array = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit != null and unit.service != Unit.Service.NONE:
			wanted.append(unit)
	var waiting: Array[Dictionary] = []
	if station:
		for config: Dictionary in Station.TYPES:
			for i in station.available(config["id"]):
				waiting.append(config)
	# **The two populations are counted separately, and that is the whole fix.** This
	# compared the *total* -- and dispatching a unit moves it from the house to the map, so
	# `wanted` gains one exactly as `waiting` loses one and the total never moves. The
	# roster therefore never rebuilt on the one event that matters most: the row stayed
	# bound to the station entry it started as, and read AVAILABLE / Station for the rest
	# of the shift however far the unit drove.
	var on_map := 0
	for instance: UnitInstance in _sidebar.units:
		if not (_behind.get(instance) is Dictionary):
			on_map += 1
	if wanted.size() != on_map or waiting.size() != _sidebar.units.size() - on_map:
		_rebuild(wanted, waiting)
	else:
		_restate(wanted)
	_mark_selection()


## **Multi-selection, which the kit's sidebar does not model.** It tracks one `selected`
## instance; this game lets the player box-select a dozen and expects every one of them
## lit. So the rows are marked from the controller's selection directly.
func _mark_selection() -> void:
	if _sidebar == null:
		return
	var chosen := {}
	if controller:
		for unit in controller.selection:
			chosen[unit] = true
	for instance: UnitInstance in _sidebar.units:
		var row := _sidebar.row_for(instance)
		if row == null or not is_instance_valid(row):
			continue
		var behind: Variant = _behind.get(instance)
		var lit := not (behind is Dictionary) and is_instance_valid(behind) \
			and chosen.has(behind)
		if row.is_selected != lit:
			row.is_selected = lit
			row.refresh()


func _rebuild(wanted: Array, waiting: Array[Dictionary]) -> void:
	_sidebar.units.clear()
	_behind.clear()
	# Callsigns run per service, in the order the roster is built, so a unit keeps the same
	# one for as long as the fleet does not change under it.
	var issued := {}
	for unit: Unit in wanted:
		var instance := _instance_for(unit, issued)
		_sidebar.units.append(instance)
		_behind[instance] = unit
	for config: Dictionary in waiting:
		var instance := UnitInstance.new()
		instance.def = _def_for(config["id"])
		instance.callsign = _callsign(int(config["service"]), issued)
		instance.status = UnitInstance.Status.AVAILABLE
		instance.task = "Station"
		instance.condition = 1.0
		_sidebar.units.append(instance)
		_behind[instance] = config
	_sidebar._rebuild()


## Updates status and condition without rebuilding rows.
##
## **Rebuilding here broke the game, not just the look.** The first cut called the
## sidebar's `_rebuild()` whenever anything changed, which destroys and recreates every
## row -- and rows are [Button]s. Doing that continuously cost ten checks across the
## arrest and escort sequence: the officer would be given Apprehend and never complete it.
## Disabling this one call turned 15 failures into 5 and the arrests came back, which is
## how it was found; the cause was measured rather than guessed at, because the failures
## were nowhere near the roster and looked like a police bug.
func _restate(wanted: Array) -> void:
	var changed := false
	for instance: UnitInstance in _sidebar.units:
		# **Typed before it is cast, and the order matters.** `_behind` holds a [Unit] for
		# a unit on the map and a plain [Dictionary] for one waiting in the house, so
		# `as Unit` on a station row is a non-object assignment -- which throws, and a
		# throw *aborts the rest of this loop*. Every frame with anything in the house
		# died at the first station row, so no unit after it was ever restated, and the
		# run logged 22,000 script errors while the suite still reported green.
		var behind: Variant = _behind.get(instance)
		if behind is Dictionary or not is_instance_valid(behind):
			continue
		var unit := behind as Unit
		if unit == null:
			continue
		var status := _status_of(unit)
		var condition := _condition_of(unit)
		# **The task is restated too, and was not.** Status and condition were kept up to
		# date while the task column kept whatever it was given when the row was built --
		# so a unit would correctly move to EN ROUTE while still reading "Standing by"
		# beside it. Two readouts of the same thing disagreeing is worse than one.
		var task := _task_of(unit)
		if is_equal_approx(instance.condition, condition) and instance.status == status \
				and instance.task == task:
			continue
		instance.task = task
		# **Status moves a row between groups, so only that needs the list rebuilt.**
		# Condition is a number inside a row and can be redrawn where it stands.
		var moved := instance.status != status
		instance.status = status
		instance.condition = condition
		if moved:
			changed = true
		else:
			var row := _sidebar.row_for(instance)
			if row:
				row.refresh()
	if changed:
		_sidebar._rebuild()


func _instance_for(unit: Unit, issued: Dictionary) -> UnitInstance:
	var instance := UnitInstance.new()
	# **Keyed off the unit's own service, not its name.** The first cut looked the
	# catalogue up by `display_name`, and units are called "Patrol 1" while the catalogue
	# says "Patrol" -- so every lookup missed, every def fell back to `support`, and all
	# three service filters showed nothing. They passed anyway, reading "0 shown, 0
	# strays", which is why the check that adds the filters back up to the whole exists.
	instance.def = _def_for_service(unit.service, unit.display_name)
	# **A callsign and a type, not the same string twice.** The row shows the callsign
	# large with the type beneath it, and feeding `display_name` to both printed "Patrol"
	# over "Patrol" on every line -- a row that has told you nothing.
	instance.callsign = _callsign(unit.service, issued)
	instance.status = _status_of(unit)
	instance.condition = _condition_of(unit)
	instance.task = _task_of(unit)
	return instance


## The next callsign for [param service] -- P01, A02, F03 -- counted per service in
## [param issued]. The letters are the kit's own convention.
## The three readouts below are [UnitReadout]'s.
##
## **They used to live here, and the selection panel needs the same three.** Two panels
## deriving "what is this unit doing" separately is two answers waiting to disagree, and
## the callsign is the sharp case: the nth police vehicle is P0n only if one pass counts
## them, so a second panel keeping its own tally would label the same engine F01 in one
## corner of the screen and F03 in another.
static func _callsign(service: int, issued: Dictionary) -> String:
	return UnitReadout.callsign(service, issued)


static func _task_of(unit: Unit) -> String:
	return UnitReadout.task_of(unit)


func _status_of(unit: Unit) -> UnitInstance.Status:
	return UnitReadout.status_of(unit)


## People carry `health`; vehicles do not, so they read as sound. The same split
## [HealthBar] makes, and for the same reason.
func _condition_of(unit: Unit) -> float:
	var person := unit as Person
	return clampf(person.health, 0.0, 1.0) if person else -1.0


## A def carrying the right service colour, and the right portrait where the unit's name
## still identifies its type ("Patrol 1" -> patrol).
static func _def_for_service(service: int, display_name: String) -> UnitDef:
	var category: StringName = ShopCatalogue.CATEGORY.get(service, &"support")
	var best: UnitDef = null
	for def in ShopCatalogue.units():
		if def.category != category:
			continue
		if best == null:
			best = def
		if display_name.begins_with(def.display_name):
			return def
	if best != null:
		return best
	var fallback := UnitDef.new()
	fallback.display_name = display_name
	fallback.category = category
	return fallback


func _def_for(id: StringName) -> UnitDef:
	for def in ShopCatalogue.units():
		if def.id == id:
			return def
	var fallback := UnitDef.new()
	fallback.display_name = "Unit"
	fallback.category = &"support"
	return fallback


## Selecting a unit in the house sends it out; selecting one on the map selects it.
## **Deferred, and that is the whole of the fix for a crash.**
##
## This signal is emitted by a [UnitRow] -- a [Button] Godot is still dispatching input
## through. Dispatching a unit from here changes the roster's populations, which rebuilds
## the list, which `queue_free`s **every row including the one still mid-signal**. The
## engine went on touching that node and the game died in the Metal renderer with a bus
## error, on the frame a row was clicked.
##
## Doing the work on the next idle frame costs nothing anybody can perceive, and means no
## row is ever destroyed from inside its own signal.
func _on_selected(instance: UnitInstance) -> void:
	_act_on.call_deferred(instance)


func _act_on(instance: UnitInstance) -> void:
	var behind: Variant = _behind.get(instance)
	if behind is Dictionary:
		if station == null:
			return
		var sent := station.dispatch(behind["id"])
		if sent and controller:
			controller.select([sent])
		_dirty = true
		return
	if not is_instance_valid(behind):
		return
	var unit := behind as Unit
	if controller and unit and unit.is_selectable():
		controller.select([unit])


## Deferred for the same reason as [method _on_selected]: following a unit moves the
## camera, and the roster can rebuild underneath the row that asked for it.
func _on_focused(instance: UnitInstance) -> void:
	_follow.call_deferred(instance)


func _follow(instance: UnitInstance) -> void:
	var behind: Variant = _behind.get(instance)
	if behind is Dictionary or not is_instance_valid(behind):
		return
	var unit := behind as Unit
	if controller and unit and unit.is_selectable():
		controller.follow(unit)


func _on_request_units() -> void:
	var shop := get_node_or_null("../../../../../Shop") as RequisitionPanel
	if shop:
		shop.open_shop()


# --- What the checks ask ------------------------------------------------------
#
# Exposed here rather than reached for inside the kit, so the suite is tied to this seam
# and not to `UnitRow`'s private members -- which is the mistake the old roster checks
# made, and the reason swapping it reddened ten of them at once.

## Forwarded while the bisect switch is on, so the tutorial still has something to point
## at and the old strip still gets its station.
func _process_legacy() -> void:
	if _legacy and _legacy.station != station:
		_legacy.station = station


## The panel's own REQUEST UNITS button -- the way into the shop since the corner buy
## button was retired.
func request_button() -> Button:
	return _sidebar.get_node_or_null("%RequestButton") as Button if _sidebar else null


## Every row currently on screen.
func rows() -> Array:
	var found: Array = []
	if _sidebar == null:
		return found
	for instance: UnitInstance in _sidebar.units:
		var row := _sidebar.row_for(instance)
		if row != null and is_instance_valid(row) and row.visible:
			found.append(row)
	return found


## The callsign this panel has issued to [param unit], or "" if it has none.
##
## **The selection panel asks rather than counting.** Callsigns are issued by walking the
## whole roster in order -- the nth police vehicle is P0n -- so a second panel running its
## own tally would number the same engine differently. There is exactly one tally and it
## lives here, because this is the panel that walks every unit anyway.
func callsign_for(unit: Unit) -> String:
	if unit == null or _sidebar == null:
		return ""
	for instance: UnitInstance in _sidebar.units:
		# **Typed before compared.** A standby row's `_behind` entry is a Dictionary -- the
		# catalogue row for a unit still in the house -- and `Dictionary == Object` is not
		# a false comparison in GDScript, it is a runtime error. Harmless-looking until
		# something asked for a callsign while a standby row existed, which is every frame
		# the fleet strip is up.
		var behind: Variant = _behind.get(instance)
		if behind is Dictionary or not is_instance_valid(behind):
			continue
		if behind == unit:
			return instance.callsign
	return ""


## The world unit a row stands for, or null if the row is a unit waiting in the house.
func unit_for(row: Control) -> Unit:
	if row == null:
		return null
	var behind: Variant = _behind.get((row as UnitRow).unit)
	if behind is Dictionary or not is_instance_valid(behind):
		return null
	return behind as Unit


## The catalogue entry a standby row stands for, or an empty dictionary.
func standby_for(row: Control) -> Dictionary:
	if row == null:
		return {}
	var behind: Variant = _behind.get((row as UnitRow).unit)
	return behind if behind is Dictionary else {}


## The status this row is currently reporting, or -1 for a row that has none.
##
## **Exposed because the roster's worst bug was invisible without it.** Rows stayed on
## AVAILABLE for the whole shift however far the unit drove -- `_refresh` compared the
## *total* of the two populations, and dispatching a unit moves it from house to map, so
## the total never changed and the rebuild never fired. The fix (counting the two
## separately) had no check watching it, because nothing outside this panel could read
## what a row actually said.
func status_of(row: Control) -> int:
	if row == null or not is_instance_valid(row):
		return -1
	var instance := (row as UnitRow).unit
	return instance.status if instance else -1


## The free text on the right of a row -- "Treating", "Station 2", "ETA 0:42".
func task_of(row: Control) -> String:
	if row == null or not is_instance_valid(row):
		return ""
	var instance := (row as UnitRow).unit
	return instance.task if instance else ""


func is_row_selected(row: Control) -> bool:
	return row != null and (row as UnitRow).is_selected


## Whether this row draws a condition bar at all. False for anything without a `health`.
func shows_condition(row: Control) -> bool:
	if row == null or not is_instance_valid(row):
		return false
	var track := (row as UnitRow)._track
	return track != null and track.visible


## Shows only [param category], or everything for `&"all"`. The sidebar groups by status
## and separates the services by *filter* -- the roster it replaced put each service on
## its own line instead.
func filter_to(category: StringName) -> void:
	if _sidebar:
		_sidebar._filter = category
		_sidebar._rebuild()


## The row standing for a unit of [param id] waiting in the house.
##
## Same name and job as [Roster]'s, so [TutorialDirector] can still pulse it -- it returns
## a [Control] rather than a `UnitChip` now, which is all that caller ever needed.
func standby_chip(id: StringName) -> Control:
	if _legacy:
		return _legacy.standby_chip(id)
	if _sidebar == null:
		return null
	for instance: UnitInstance in _sidebar.units:
		var behind: Variant = _behind.get(instance)
		if behind is Dictionary and behind["id"] == id:
			return _sidebar.row_for(instance)
	return null
