extends Control
class_name SelectionPanel

## The bottom bar: who is selected, what is aboard them, and what they can be told to do.
##
## **A drop-in for [Portrait], on the tactic the shop and roster swaps both used.** It
## keeps the one public name anything outside cares about — `controller` — so `HUD.gd`
## wires it exactly as it wired the portrait, and hosts the user's `unit_selection_panel`
## scene for the look.
##
## What it adds over the portrait it replaces is **occupancy**: a fire engine with four
## firefighters aboard and one with an empty cab looked identical from outside, and a van
## with six cells said nothing about who was in the back. That is the readout this panel
## exists for.
##
## > **The command grid is not the kit's.** The scene ships a fixed table of eight buttons
## > with hardcoded ids; this game generates its grid from [method
## > RTSController.available_abilities], which is what gives a verb its tile, its hotkey
## > and its right-click meaning from the scoring ladder with no UI change. Adopting the
## > kit's table would have thrown away the ladder and every verb added since. So the kit's
## > buttons are cleared on ready and the real [CommandGrid] is re-homed into the slot they
## > came out of — the look, not the mechanism.

const PANEL_SCENE := "res://ui/unit_selection_panel.tscn"
## The fleet strip that fills the bar when nothing is selected.
const STRIP_SCENE := "res://ui/unit_roster_strip.tscn"

## Redrawn on a tick rather than every frame. The readout is text and bars, none of which
## changes fast enough to notice at 60Hz — and the last panel to rebuild itself per frame
## cost this project a fortnight of crash bisecting.
const TICK := 0.12

## How wide the command column is allowed to be. Wide enough that the tiles flow into
## rows rather than stacking into one tall column, which is what drove the panel off the
## bottom of the screen the first time it was seen in play.
const COMMANDS_WIDTH := 300.0

## Gap between the bottom of the dock and the bottom of the screen, matching the margin
## every other floating panel keeps.
const BOTTOM_MARGIN := 22.0

## Litres per unit of [member Vehicle.tank_capacity], for the water readout.
##
## `tank_capacity` is a **multiplier**, not a volume -- the appliance carries 20 of
## whatever one unit is -- so the panel needs a scale to turn it into a number a player
## recognises. 90 puts the fire engine at **1,800 L**, which is what a real pump carries.
## The first cut used 1,800 as the per-unit figure and printed *36,000 L*, a tanker's worth
## of water on a pump: a units error is invisible to every check in the suite, because the
## arithmetic is self-consistent at any scale.
const LITRES_PER_TANK := 90.0

## How much bigger the vehicle should be drawn inside the portrait tile.
##
## The tile does not change size -- the subject inside it does, by cropping the render's
## dead border away and letting the same tile show a smaller piece of a bigger picture.
##
## **Capped per portrait, because a flat crop does not fit them all.** Measured across the
## twenty-one renders: a car occupies about 65px of its 192px frame and could take 2.9x,
## the appliance 1.76x, but a helicopter is 144px wide and has only **1.33x** of room, and
## the character portraits fill their frame edge to edge with none at all. Cropping every
## one to a flat fraction would have sliced the rotors off and beheaded the crew.
##
## At 3.0 the cars are asking for more than they have, so they land on their own limit and
## fill the tile -- which is the point. Raising this further moves nothing; the pictures
## are the constraint now, not the number.
const PORTRAIT_ZOOM := 3.0

## Cropped copies, made once per texture. Finding the subject means reading every pixel of
## a 192x192 render, which is nothing once and a great deal every tick -- and a panel doing
## per-frame work on the renderer's own resources is what crashed this game in August 2026.
static var _crops := {}

var controller: RTSController:
	set = _set_controller

## The books: what is bought, what is still in the house, and what a purchase costs.
var station: Station

## The roster sidebar, if the scene still has one. Optional -- the bar issues its own
## callsigns now, so a scene without a sidebar names units perfectly well.
var roster: RosterSidebar

## Callsign per unit, assigned on first sight and never reissued.
##
## **Kept rather than recomputed.** Callsigns are issued by counting -- the nth police
## vehicle is P0n -- so recomputing the tally each tick would renumber the whole fleet
## every time one unit was lost or bought, and the card you were looking at would change
## its name under you.
var _named: Dictionary = {}
var _issued: Dictionary = {}
## Which catalogue id each standby card stands for.
var _standby_ids: Dictionary = {}
var _standby_defs: Dictionary = {}
var _standby_cards: Dictionary = {}
## The fleet as last handed to the strip, so an unchanged fleet is not rebuilt.
var _shown_fleet: Array = []
## The tallest either state has ever asked to be, so the bar keeps one height.
var _tallest := 0.0
var _request: Button

## Which service the fleet strip is showing.
##
## **There is no ALL.** The bar is one service at a time, so this always names a real one.
## It opens on whichever the career actually owns units in -- see [method _build_filters] --
## because defaulting to a fixed service would show an empty strip to anyone who happens
## not to have bought that one yet.
var _filter: StringName = &"fire"

var _panel: Control
var _strip: Control
var _chips: Dictionary = {}
## False until the opening tab has been chosen from a fleet that actually exists.
var _filter_settled := false
var _grid: CommandGrid
var _instances: Dictionary = {}
var _clock := 0.0
var _last: Array[Unit] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var packed := load(PANEL_SCENE) as PackedScene
	if packed == null:
		push_warning("SelectionPanel: %s is missing" % PANEL_SCENE)
		return
	_panel = packed.instantiate() as Control
	if _panel == null:
		return
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_strip_kit_commands()
	_build_strip()
	_build_filters()
	_build_request_button()
	# **The dock is sized to what the panel asks for, every tick.** It was pinned at a
	# hand-picked 188 with `clip_contents` on, which does not fit a panel -- it hides the
	# part that does not fit. The panel wanted 253 and the bottom 65px of it, including
	# half the portrait and the HEALTH row, was simply cut off on screen while every
	# measurement here read 188 and looked correct.
	set_process(true)


## Puts the kit's own command grid out of sight.
##
## **Hidden, emphatically not freed.** Freeing the buttons was the first cut and it was
## wrong: the kit keeps them in a `_cmd_buttons` dictionary and walks that dictionary on
## every refresh, so a freed button meant `Trying to assign invalid previously freed
## instance` -- **over six thousand of them in a single suite run**, which is the volume of
## `SCRIPT ERROR` spam that hides a real one, and this project has already lost checks to
## errors nobody could see for the noise.
##
## Hiding costs nothing and keeps the kit's own bookkeeping honest. The real grid goes in
## beside it rather than inside it -- see [method adopt_command_grid].
func _strip_kit_commands() -> void:
	var slot := _kit_grid()
	if slot is Control:
		(slot as Control).visible = false


func _kit_grid() -> Node:
	return _panel.get_node_or_null("%CommandGrid") if _panel else null


## Puts the game's real command grid where the kit's buttons were.
##
## Called by [HUD] once it has resolved the grid, because the grid is authored into
## `HUD.tscn` and this panel has no business reaching across the scene to find it.
func adopt_command_grid(grid: CommandGrid) -> void:
	if grid == null:
		return
	_grid = grid
	var slot := _kit_grid()
	if slot == null:
		return
	# Beside the kit's hidden grid, under the same COMMANDS heading, rather than inside it:
	# the kit grid is a fixed-column GridContainer laying out buttons that are still there,
	# and this one is an HFlowContainer that wants the width to itself.
	var home := slot.get_parent()
	if home == null:
		return
	var parent := grid.get_parent()
	if parent:
		parent.remove_child(grid)
	home.add_child(grid)
	# **Fills the width, never demands height.** An `HFlowContainer` of fourteen tiles in
	# a narrow column reports a minimum height of the whole stack, and a PanelContainer
	# grows to its content -- so asking this to expand vertically pushed the dock off the
	# bottom of the screen and over the minimap's zoom buttons. It flows into rows now.
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.custom_minimum_size = Vector2(COMMANDS_WIDTH, 0.0)


func _set_controller(value: RTSController) -> void:
	controller = value
	# **Answer the selection the moment it changes, rather than at the next tick.**
	# This panel was built as a pure poll loop, and every other panel in the interface --
	# CommandGrid, Roster, RosterSidebar -- has listened to `selection_changed` since it
	# existed. That made the bar the one part of the UI that could take a full TICK (0.12s)
	# to notice a click, which is squarely inside the range a player reads as lag rather
	# than as instant. Reported from play as "a delay between clicking and the action".
	#
	# The tick stays: it carries everything that changes *without* a click -- condition,
	# task, water, order progress -- and polling those is right. What it should never have
	# been carrying is the response to input.
	if controller and not controller.selection_changed.is_connected(_on_selection_changed):
		controller.selection_changed.connect(_on_selection_changed)
	_refresh()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_clock = 0.0
	_refresh()
	_fit_to_content()


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK:
		return
	_clock = 0.0
	_refresh()
	_fit_to_content()


func _refresh() -> void:
	if _panel == null:
		return
	var live: Array[Unit] = []
	if controller:
		for unit in controller.selection:
			if is_instance_valid(unit):
				live.append(unit)
	var shown: Array[UnitInstance] = []
	for unit in live:
		shown.append(_instance_for(unit))
	# **One state or the other, never both.** The bar is the fleet when nothing is selected
	# and the unit when something is -- the kit's own design, and the only arrangement that
	# fits 188px: side by side the two would want 2,200.
	#
	# The panel itself always stays visible; it is the frame. Only what sits inside it
	# swaps.
	var idle := live.is_empty()
	_settle_opening_filter()
	_panel.call(&"show_units", shown)
	if _strip:
		_strip.visible = idle
		if idle:
			var fleet := _fleet()
			# **Only when it changed.** `set_units` tears every card down and builds them
			# again; doing that on a tick nothing moved is what ate the clicks.
			if fleet != _shown_fleet:
				_shown_fleet = fleet.duplicate()
				_strip.call(&"set_units", fleet)
			else:
				# Same units, possibly different facts about them -- a repair bill paid,
				# a crew getting in. Repainted in place, because rebuilding is what ate
				# the clicks.
				_strip.call(&"restate")
	# The tabs belong to the fleet, so they go with it.
	for chip: Button in _chips.values():
		chip.visible = idle
	# The kit puts up a "select a unit" hint when it has nothing to show. The strip is a
	# better answer to the same question, so the hint stands down for it.
	var hint := _panel.get_node_or_null("%Empty") as Control
	if hint:
		hint.visible = false
	_last = live
	if idle:
		return
	_wire_seats(live)


## The kit record for a unit, kept between ticks.
##
## Cached per unit rather than rebuilt: the readout changes, the record does not, and a
## panel that rebuilt its models every tick is exactly the shape that put an
## instantiate-and-free loop on the renderer's own resources and crashed the game.
func _instance_for(unit: Unit) -> UnitInstance:
	var instance: UnitInstance = _instances.get(unit)
	if instance == null:
		instance = UnitInstance.new()
		instance.def = _def_for(unit)
		_instances[unit] = instance
	instance.callsign = _callsign_for(unit)
	instance.condition = UnitReadout.condition_of(unit)
	instance.status = UnitReadout.status_of(unit)
	instance.task = UnitReadout.task_of(unit)
	instance.occupants = UnitReadout.occupants_of(unit)
	var vehicle := unit as Vehicle
	instance.liquid = vehicle.water if vehicle and vehicle.carries_water else 0.0
	instance.owed = vehicle.repair_bill if vehicle else 0
	var order := unit.current_order()
	instance.progress = order.progress() if order else -1.0
	return instance


## A catalogue entry for the unit's own type, with the carrying numbers filled in from the
## unit itself.
##
## [ShopCatalogue] already turns `Station.TYPES` into kit records and caches them, so the
## portrait and the service colour come free. What it cannot know is how many seats *this*
## body has, because that lives on the built scene — which is the same split the shop had
## to learn when it printed "1 cells" beside a tow truck.
func _def_for(unit: Unit) -> UnitDef:
	var source: UnitDef = null
	for def in ShopCatalogue.units():
		if def.id == unit.type_id:
			source = def
			break
	var out := UnitDef.new()
	if source:
		out.id = source.id
		out.display_name = source.display_name
		out.category = source.category
		out.icon = _cropped(source.icon)
	else:
		out.display_name = unit.display_name
		out.category = ShopCatalogue.CATEGORY.get(unit.service, &"support")
	out.seats = UnitReadout.seats_of(unit)
	var vehicle := unit as Vehicle
	out.carries_liquid = vehicle != null and vehicle.carries_water
	out.liquid_label = "Water"
	out.liquid_capacity = roundi(LITRES_PER_TANK * vehicle.tank_capacity) if vehicle else 0
	return out


## The kit panel's own command buttons, for the suite.
##
## Exposed for one reason: freeing them instead of hiding them floods the run with
## thousands of `previously freed instance` errors while **every check stays green and the
## check count does not move**. The suite reports nothing that would catch it, so the
## regression is asserted directly.
func kit_buttons() -> Array:
	var out: Array = []
	if _panel == null:
		return out
	var held: Variant = _panel.get(&"_cmd_buttons")
	if held is Dictionary:
		for key in held:
			out.append(held[key])
	return out


## How tall the hosted panel says it needs to be.
##
## Exposed so the suite can assert the dock is at least that tall. Content taller than its
## dock is not a layout that is slightly wrong -- it is content cut off the bottom edge of
## the screen, which is what a player sees and what no other measurement here reports.
func content_height() -> float:
	return _panel.get_combined_minimum_size().y if _panel else 0.0


## The command grid this panel has taken in, or null before [method adopt_command_grid].
##
## **The grid no longer lives where it is authored.** It is written into `CommandBlock` so
## `HUD.gd` can reach it with `$`, then moved in here at startup -- so anything looking for
## it by its authored path finds nothing at runtime, which is how the suite first met this
## change. Ask the panel that has it.
func command_grid() -> CommandGrid:
	return _grid


## What the panel is currently showing, for the suite.
##
## **Read back off the kit panel, not off this one's bookkeeping.** The first version
## returned `_last`, which is set on the line after `show_units` is called -- so severing
## the call entirely left this reporting one unit while the bar drew nothing, and the
## check that watched it passed. An accessor for a panel has to ask the thing that draws.
func shown_units() -> Array[Unit]:
	var drawn: Array[Unit] = []
	if _panel == null:
		return drawn
	var models: Variant = _panel.get(&"units")
	if models is not Array:
		return drawn
	for model in models:
		for unit in _instances:
			if _instances[unit] == model and is_instance_valid(unit):
				drawn.append(unit)
	return drawn


## The seat roles the panel is drawing for [param unit], in seat order.
func occupancy_of(unit: Unit) -> Array[StringName]:
	var instance: UnitInstance = _instances.get(unit)
	return instance.occupants.duplicate() if instance else [] as Array[StringName]


## Litres of water the panel is reporting for [param unit], or 0 for a unit with no tank.
func litres_of(unit: Unit) -> int:
	var instance: UnitInstance = _instances.get(unit)
	return instance.liquid_litres() if instance else 0


## The fleet strip, or null if it failed to load.
func roster_strip() -> Control:
	return _strip


## The kit panel that draws the bar's frame.
func frame() -> Control:
	return _panel


## The clickable seat pips on the bar, for the suite.
func seat_pips() -> Array:
	var seats := _panel.get_node_or_null("%Seats") if _panel else null
	return seats.get_children() if seats else []


## The callsign on the panel for [param unit].
func callsign_of(unit: Unit) -> String:
	var instance: UnitInstance = _instances.get(unit)
	return instance.callsign if instance else ""


## Grows the dock to whatever the panel needs, pinned to the bottom margin.
##
## The block is bottom-anchored with `grow_vertical = 0`, so moving `offset_top` is what
## sets its height. Driven from the panel's own combined minimum rather than a constant:
## a number typed in here is a number that stops being true the next time a row is added
## to the panel, and the failure mode is content silently cut off the bottom of the screen.
func _fit_to_content() -> void:
	if _panel == null:
		return
	var wanted := _panel.get_combined_minimum_size().y
	if wanted <= 0.0:
		return
	# **The taller of the two states, always.** The bar has two contents -- the fleet strip
	# and the unit detail -- and they do not want the same height, so sizing to whichever
	# is showing made the dock jump every time a unit was selected or dropped. Remembering
	# the largest asked for pins both to one height, and it settles after the first time
	# each state has been seen.
	_tallest = maxf(_tallest, wanted)
	var top := -(_tallest + BOTTOM_MARGIN)
	if not is_equal_approx(offset_top, top):
		offset_top = top


## The portrait cropped so the vehicle in it is drawn [constant PORTRAIT_ZOOM] times larger.
##
## The crop is centred on what is actually in the picture rather than on the middle of the
## frame: the renders are not all centred, and a fixed inset would shave one side off a
## long body like the appliance. Never smaller than the subject itself, so a portrait with
## no room to spare -- a character, or a helicopter with its rotors nearly touching the
## edges -- is returned untouched instead of clipped.
static func _cropped(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	if _crops.has(texture):
		return _crops[texture]
	var result := texture
	var image := texture.get_image()
	# **Decompressed first, or not read at all.** These import as compressed textures, and
	# `get_pixel` refuses one -- loudly, once per pixel attempted, which turned a suite run
	# into 17.9MB of `Can't get_pixel() on compressed image`. A standalone probe on the same
	# file read it happily, because the copy it loaded had not been through the same import
	# path: proof on one texture is not proof on the texture the game actually holds.
	if image and image.is_compressed():
		image = image.duplicate()
		if image.decompress() != OK:
			image = null
	if image:
		var frame := Vector2(image.get_width(), image.get_height())
		var subject := _subject_rect(image)
		if subject.size.x > 0.0 and subject.size.y > 0.0:
			# What 2x asks for, widened to whatever the subject actually needs.
			var want := frame / PORTRAIT_ZOOM
			want.x = maxf(want.x, subject.size.x)
			want.y = maxf(want.y, subject.size.y)
			if want.x < frame.x or want.y < frame.y:
				var middle := subject.position + subject.size * 0.5
				var corner := middle - want * 0.5
				corner.x = clampf(corner.x, 0.0, frame.x - want.x)
				corner.y = clampf(corner.y, 0.0, frame.y - want.y)
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(corner, want)
				result = atlas
	_crops[texture] = result
	return result


## The bounding box of everything that is not the flat background colour.
##
## Read against the top-left pixel rather than against alpha: these renders are shot onto
## an opaque card, so every pixel is opaque and an alpha test reports the whole frame as
## subject -- which is what made the first attempt at this measure a zero-margin portrait
## for all twenty-one of them.
static func _subject_rect(image: Image) -> Rect2:
	var background := image.get_pixel(0, 0)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var difference := absf(pixel.r - background.r) + absf(pixel.g - background.g) \
				+ absf(pixel.b - background.b) + absf(pixel.a - background.a)
			if difference > 0.1:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2()
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Makes an occupied seat a button that puts that person on the pavement.
##
## **Wired after the fact rather than built in.** The kit draws its seats from a list of
## role names -- `driver`, `officer`, `casualty` -- which is all it needs to colour them
## and all it has: a pip cannot say *which* officer it is, so it cannot put one out. The
## identity is recovered here, from the order [method UnitReadout.occupants_of] builds the
## list in: the driver first, then `crew`, then casualties, then anyone in the cells.
##
## Only crew seats answer. The driver is nobody -- a vehicle drives itself in this game --
## and a casualty or a prisoner is aboard because a job put them there.
func _wire_seats(live: Array[Unit]) -> void:
	var seats := _panel.get_node_or_null("%Seats") if _panel else null
	if seats == null or live.size() != 1:
		return
	var unit := live[0]
	var pips := seats.get_children()
	for index in pips.size():
		var pip := pips[index] as Control
		if pip == null:
			continue
		# Crew fill the strip from the front -- there is no driver's seat any more, so seat
		# n is crew member n. Anything past the crew is a casualty, a prisoner or an empty
		# seat, none of which is a passenger who can be told to get out.
		var rider: Person = unit.crew[index] if index < unit.crew.size() else null
		if rider == null:
			continue
		pip.mouse_filter = Control.MOUSE_FILTER_STOP
		pip.tooltip_text = "%s - click to send them out" % rider.display_name
		_dress_seat(pip, rider)
		if not pip.gui_input.is_connected(_on_seat_input):
			pip.gui_input.connect(_on_seat_input.bind(unit, rider))


func _on_seat_input(event: InputEvent, unit: Unit, rider: Person) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_instance_valid(unit) or not is_instance_valid(rider):
		return
	unit.put_down(rider)
	# Straight away, so the seat empties under the pointer rather than on the next tick.
	_refresh()
	get_viewport().set_input_as_handled()


## Puts the rider's own face on their seat, in place of the role icon.
##
## The kit draws a generic silhouette tinted to the service colour, which says *what* is in
## the seat. This says *who*: the same rendered portrait the roster and the shop use, so a
## paramedic in the back of a van is the paramedic you bought rather than a green outline.
##
## The role-coloured border on the pip is left alone -- it is what still carries the service
## at a glance when the picture is sixteen pixels across.
func _dress_seat(pip: Control, rider: Person) -> void:
	var art := _avatar_for(rider)
	if art == null:
		return
	for child in pip.get_children():
		var slot := child as TextureRect
		if slot == null:
			continue
		if slot.texture == art:
			return
		slot.texture = art
		# **Untinted, and told to ignore its own size.** The kit modulates the silhouette
		# to the service colour, which on a photograph reads as a fault; and a 192px render
		# in a 16px hole needs `EXPAND_IGNORE_SIZE`, or the TextureRect claims the texture's
		# full size as its minimum and shoves the whole occupancy strip apart. That trap has
		# now cost this project five separate bugs.
		slot.modulate = Color.WHITE
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return


## The rendered portrait for whoever this is, from the catalogue that already holds one.
func _avatar_for(rider: Person) -> Texture2D:
	if rider == null:
		return null
	for def in ShopCatalogue.units():
		if def.id == rider.type_id:
			return def.icon
	return null


## The fleet strip, added beside the detail panel and shown instead of it.
##
## **A sibling, not a replacement.** The kit ships a newer selection panel with this strip
## built into it, and adopting that wholesale would have cost the group view: its API is
## `show_unit` and `command_issued(action, unit)`, one unit at a time, and this game has
## box-select and control groups. Hosting the strip alongside keeps multi-selection and
## still gives the bar its two states.
func _build_strip() -> void:
	var packed := load(STRIP_SCENE) as PackedScene
	if packed == null:
		push_warning("SelectionPanel: %s is missing" % STRIP_SCENE)
		return
	_strip = packed.instantiate() as Control
	if _strip == null:
		return
	_strip.set("preview_in_editor", false)
	# **Inside the panel's frame, not beside it.** The strip scene is a bare `Control` with
	# no background of its own -- in the kit's standalone project the selection panel drew
	# the frame and the strip sat in a slot inside it. Added as a sibling and shown while
	# the panel was hidden, it floated on the bare map with its labels spilling over the
	# world: the bar simply was not there.
	#
	# It goes into `%Rows`, under the header, where the kit's own "nothing selected" hint
	# sits -- so the frame, the header and the UNITS caption all stay put and only the
	# contents swap.
	# **By path, not by unique name.** `Rows` is a plain child in the kit scene -- it
	# carries no `unique_name_in_owner`, unlike most of its siblings -- so `%Rows` resolved
	# to null and the fallback below quietly parented the strip to the dock instead. That
	# fallback is why the miss was invisible from here and obvious on screen: the strip
	# floated on the bare map with nothing behind it.
	var rows := _panel.get_node_or_null("Rows") as Control
	if rows == null:
		push_warning("SelectionPanel: the kit panel has no Rows container")
		add_child(_strip)
		return
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_strip)
	if _strip.has_signal("unit_picked"):
		_strip.unit_picked.connect(_on_strip_picked)
	if _strip.has_signal("unit_focused"):
		_strip.unit_focused.connect(_on_strip_focused)


## Picking a card selects that unit, which flips the bar into its detail state.
func _on_strip_picked(model: UnitInstance) -> void:
	# A card for something still in the house sends it out; a card for something on the
	# map selects it. Same click, and the difference is which one the card stands for.
	if _standby_ids.has(model):
		if station:
			var sent := station.dispatch(_standby_ids[model])
			if sent and controller:
				controller.select([sent])
		_standby_ids.erase(model)
		for slot in _standby_cards.keys():
			if _standby_cards[slot] == model:
				_standby_cards.erase(slot)
		_shown_fleet.clear()
		_refresh()
		return
	var unit := _unit_behind(model)
	if unit and controller:
		controller.select([unit])
		_refresh()


## Double-clicking one takes the camera to it, the same gesture the roster row uses.
func _on_strip_focused(model: UnitInstance) -> void:
	var unit := _unit_behind(model)
	if unit and controller:
		controller.follow(unit)


func _unit_behind(model: UnitInstance) -> Unit:
	for unit in _instances:
		if _instances[unit] == model and is_instance_valid(unit):
			return unit
	return null


## Everything under command, for the strip.
##
## Built from the unit group rather than from the station's books, so a unit still in the
## house is not offered as something to select -- the roster sidebar shows those as standby
## chips, and a card that selects nothing would be a dead card.
func _fleet() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit == null or unit.service == Unit.Service.NONE:
			continue
		if ShopCatalogue.CATEGORY.get(unit.service, &"support") != _filter:
			continue
		out.append(_instance_for(unit))
	out.append_array(_standby())
	return out


## Cards for units bought but still in the station.
##
## **The one job the roster sidebar did that nothing else does.** A unit in the house is
## not in the scene, so it is not in the unit group and cannot be selected -- but sending
## it out is how a career gets anything onto the map at all. Without these the shop would
## take your money and nothing would ever arrive.
##
## They are drawn OFF_RUN so they read as not-yet-out rather than as idle-on-scene, and
## clicking one dispatches it -- see [method _on_strip_picked].
func _standby() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	if station == null:
		return out
	for config: Dictionary in Station.TYPES:
		var id: StringName = config["id"]
		if ShopCatalogue.CATEGORY.get(config["service"], &"support") != _filter:
			continue
		for i in station.available(id):
			# **Reused, never re-minted.** A fresh object each tick made every `set_units`
			# a changed list, so the strip rebuilt all its cards six times a second -- and
			# `Button.pressed` fires on *release*, so a click that straddled a rebuild was
			# pressing a button that no longer existed by the time it was let go. Clicking
			# a standby card simply did nothing, most of the time.
			#
			# It is also the per-tick rebuild that cost this project a fortnight of crash
			# bisecting, arriving from a new direction.
			var slot := "%s#%d" % [id, i]
			var waiting: UnitInstance = _standby_cards.get(slot)
			if waiting == null:
				waiting = UnitInstance.new()
				waiting.def = _catalogue_def(id)
				waiting.callsign = String(config["label"]).to_upper()
				waiting.status = UnitInstance.Status.OFF_RUN
				waiting.task = "In the station"
				waiting.condition = 1.0
				_standby_cards[slot] = waiting
				_standby_ids[waiting] = id
			out.append(waiting)
	return out


## The catalogue's own record for a type, for a standby card. Cached: [ShopCatalogue]
## instantiates and frees a scene per entry to measure it, and doing that per tick is what
## crashed this game in August 2026.
func _catalogue_def(id: StringName) -> UnitDef:
	if _standby_defs.has(id):
		return _standby_defs[id]
	var found: UnitDef = null
	for def in ShopCatalogue.units():
		if def.id == id:
			found = def
	if found:
		var copy := UnitDef.new()
		copy.id = found.id
		copy.display_name = found.display_name
		copy.category = found.category
		copy.icon = _cropped(found.icon)
		copy.seats = 0
		_standby_defs[id] = copy
		return copy
	return null


## The service tabs across the top of the bar.
##
## **Built here rather than authored into the scene**, the same choice the debrief card and
## the status strip make: the list comes from [constant UnitSidebar.FILTERS], so a service
## added to the game arrives here without a scene edit.
##
## They sit in the header beside the UNIT SELECTION caption and stand down with the strip
## -- filtering a fleet you are not looking at would be a control with nothing to do.
func _build_filters() -> void:
	var header := _panel.get_node_or_null("Rows/HeaderWrap/Header") as Control
	if header == null:
		push_warning("SelectionPanel: the kit panel has no header to put tabs in")
		return
	# `FILTERS` opens with an ALL entry, which the roster sidebar still uses. The bar does
	# not: it shows one service at a time.
	for entry in UnitSidebar.FILTERS:
		var category: StringName = entry[0]
		if category == &"all":
			continue
		var chip := Button.new()
		chip.name = "Filter_%s" % category
		chip.text = String(entry[1])
		chip.theme_type_variation = &"ERSChipActive" if category == _filter else &"ERSChip"
		chip.custom_minimum_size = Vector2(54.0, 24.0)
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_filter.bind(category))
		header.add_child(chip)
		_chips[category] = chip
	# Painted directly rather than through `_on_filter`, which marks the choice as the
	# player's and would stop `_settle_opening_filter` ever running -- the tab then stayed
	# on whatever `_ready` guessed, with an empty strip under it.
	if not _chips.is_empty():
		_filter = _chips.keys()[0]
	_paint_chips()


## Settles the opening tab on a service the career owns units in.
##
## **Once, and not in `_ready`.** Without an ALL tab something is always selected, and a
## fixed default would greet a player who has not bought that service with an empty strip
## -- which reads as broken rather than as filtered. The first attempt picked the service
## at build time and always landed on the first tab, because `_ready` runs before a single
## unit has been dispatched and the scan had an empty tree to look at.
##
## So it waits for a fleet to exist, chooses once, and never overrides the player again.
func _settle_opening_filter() -> void:
	if _filter_settled or _chips.is_empty():
		return
	for key: StringName in _chips:
		for node in get_tree().get_nodes_in_group(Unit.GROUP):
			var unit := node as Unit
			if unit == null or unit.service == Unit.Service.NONE:
				continue
			if ShopCatalogue.CATEGORY.get(unit.service, &"support") == key:
				_filter_settled = true
				if key != _filter:
					_on_filter(key)
				return


func _on_filter(category: StringName) -> void:
	_filter = category
	# A tab the player pressed is final; the opening guess stops second-guessing it.
	_filter_settled = true
	_paint_chips()
	if _strip:
		_strip.call(&"set_units", _fleet())


func _paint_chips() -> void:
	for key: StringName in _chips:
		var chip: Button = _chips[key]
		chip.theme_type_variation = &"ERSChipActive" if key == _filter else &"ERSChip"


## The service tabs, for the suite.
## What the bar's CURRENT ORDER row is drawing -- see the kit panel's `order_readout`.
##
## Empty while the panel is standing down, which is the honest answer: there is no bar to
## read, rather than a bar reading zero.
func order_readout() -> Dictionary:
	return _panel.call(&"order_readout") if _panel else {}


func filter_tabs() -> Dictionary:
	return _chips.duplicate()


## Which service the strip is filtered to.
func filter_category() -> StringName:
	return _filter


## This unit's callsign, issued once and remembered.
##
## Prefers the roster sidebar's answer while one exists, so the two panels agree for as
## long as they are both on screen; issues its own otherwise. Either way a unit keeps the
## name it was first given.
func _callsign_for(unit: Unit) -> String:
	var known: String = _named.get(unit, "")
	if not known.is_empty():
		return known
	var name := roster.callsign_for(unit) if roster else ""
	if name.is_empty():
		name = UnitReadout.callsign(unit.service, _issued)
	_named[unit] = name
	return name


## REQUEST UNITS, in the bar's header beside the service tabs.
##
## **The other thing the roster sidebar was for.** It carried the only door into the shop,
## so retiring it would have left a career with no way to spend its money -- and the corner
## cart button that used to do this job was itself retired when the sidebar took over.
func _build_request_button() -> void:
	var header := _panel.get_node_or_null("Rows/HeaderWrap/Header") as Control
	if header == null:
		return
	_request = Button.new()
	_request.name = "RequestUnits"
	_request.text = "REQUEST UNITS"
	_request.theme_type_variation = &"ERSChipActive"
	_request.custom_minimum_size = Vector2(132.0, 24.0)
	_request.focus_mode = Control.FOCUS_NONE
	_request.pressed.connect(_on_request_units)
	header.add_child(_request)


func _on_request_units() -> void:
	var shop := _find_shop()
	if shop:
		shop.open_shop()


## The requisition modal, found by type rather than by path.
##
## By path is how the sidebar did it -- `../../../../../Shop` -- which is five levels of
## assumption about where this panel sits, and would break the moment the bar moved.
func _find_shop() -> RequisitionPanel:
	# Walked up to the CanvasLayer the whole interface hangs off, rather than named: the
	# HUD script has no `class_name`, so there is no type to test against.
	var top: Node = self
	while top != null and top is not CanvasLayer:
		top = top.get_parent()
	if top == null:
		return null
	for node in top.find_children("*", "RequisitionPanel", true, false):
		return node as RequisitionPanel
	return null


## The shop button, for the suite and for the tutorial's spotlight.
func request_button() -> Button:
	return _request


## The standby card for a unit type, for the tutorial's spotlight.
##
## Null when that type has none waiting in the station -- **and also when its service's
## tab is not the one showing**, because the strip only builds cards for the filtered
## service. That second case is why [method tab_for] exists: a lesson that says "send the
## ambulance" has to point at something, and when the ambulance's card is on another tab
## the honest thing to point at is the tab.
func standby_card(id: StringName) -> Button:
	if _strip == null:
		return null
	for model: Variant in _standby_ids:
		if _standby_ids[model] != id:
			continue
		var card := _strip.call(&"card_for", model) as Button
		if card != null:
			return card
	return null


## The service tab a unit type's cards live under.
func tab_for(id: StringName) -> Button:
	for config: Dictionary in Station.TYPES:
		if config["id"] != id:
			continue
		return _chips.get(
			ShopCatalogue.CATEGORY.get(config["service"], &"support")) as Button
	return null
