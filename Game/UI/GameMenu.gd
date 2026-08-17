extends Control
class_name GameMenu

## The game's framing: the title card a session opens on, the pause menu under `P`,
## and the settings screen behind both.
##
## An overlay in the HUD rather than a separate scene, deliberately: the district
## already idles beautifully -- crowds, traffic, the parked shift -- so the title
## sits over a *live* city instead of a still, the main scene stays Playground.tscn,
## and the generated map is never touched. The cost is input discipline: while the
## title is up this node stops the mouse (a full-rect STOP control) and swallows the
## keyboard in [method _input], so nothing underneath hears a thing until PLAY.
##
## Pausing uses the scene tree's own pause: this node runs PROCESS_MODE_ALWAYS (set
## where it is added in HUD.tscn), everything else in the map inherits PAUSABLE and
## freezes -- vehicles, fires, casualties, the shift clock and the call ages all
## stop together for free.
##
## Settings persist to their own ConfigFile: volume, shift length and call rate --
## the second save-shaped thing in the project, after Mission's records and before
## the station's career.

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS, SCENARIOS }

const TITLE_TEXT := "EMERGENCY RTS"
## Both halves of the old line went stale: the roster stopped being a fixed issue when
## the career economy made it something bought, and the five minutes became a setting.
## What is still true of every shift is the district and the clock.
const SUBTITLE_TEXT := "A district, a fleet you paid for, and a clock."
## The main menu's column: how far in from the left edge, and how wide. The reference
## puts its menu in a column down the left with the picture beside it; here the
## picture is the district itself, so the column is inset rather than boxed in.
const COLUMN_INSET := 64.0
const COLUMN_WIDTH := 340.0

## The foot of the menu. The kit's version plate reads "Your studio name"; this is
## ours, and it is the only place in the interface that says which build this is.
const VERSION_TEXT := "BUILD 20260817   ·   PHASE 20"

## The practice town, the district, and the screen both go back to.
const TUTORIAL_SCENE := "res://Game/Tutorial.tscn"
const DISTRICT_SCENE := "res://Game/Playground.tscn"
const MENU_SCENE := "res://Game/MainMenu.tscn"

## The shift lengths on offer, in minutes.
const SHIFT_CHOICES := [5, 10, 15]
## How often the district calls. The multiplier goes on the director's intervals, so
## BUSY is the pace the game shipped with and the other two are calmer -- the first
## thing anyone said after playing a full shift was that the calls came too fast.
const PACE_CHOICES := [
	{"label": "QUIET", "scale": 2.0},
	{"label": "STEADY", "scale": 1.35},
	{"label": "BUSY", "scale": 1.0},
]
## What hour the shift works at. The labels are in [Daylight]'s order, so the index
## *is* the mode -- there is no table mapping one to the other to get out of step.
const TIME_CHOICES := ["DAY", "DUSK", "NIGHT"]
## Weather, in [enum Daylight.Weather] order for the same reason as the hours above --
## the index *is* the value for every fixed state, so there is no table to fall out of
## step. The last entry is the exception: SHIFT'S OWN is a *policy*, not a state -- the
## director rolls the weather from its seeded stream when a shift opens, so every shift
## has its own sky and a reproduced seed is rained on identically.
const WEATHER_CHOICES := ["CLEAR", "RAIN", "FOG", "SNOW", "SHIFT'S OWN"]
## The index of that policy entry: everything below it is a Daylight.Weather verbatim.
const SHIFT_WEATHER := 4

## A var rather than a const so the test suite can point it at a disposable file.
var settings_path := "user://settings.cfg"

## Wired by the HUD. Assigning the director applies the stored shift length to it.
var director: Director:
	set(value):
		if director and director.shift_started.is_connected(_on_shift_started):
			director.shift_started.disconnect(_on_shift_started)
		director = value
		if director:
			director.shift_length = shift_minutes * 60.0
			director.pace = pace_scale()
			director.shift_started.connect(_on_shift_started)

## Wired by the HUD, same as the director. Assigning it applies the stored hour, which
## is what makes the setting survive a restart rather than only a change.
var daylight: Daylight:
	set(value):
		daylight = value
		if daylight:
			daylight.set_time_of_day(time_of_day)
			if wet_weather < SHIFT_WEATHER:
				daylight.set_weather(wet_weather)

var screen: Screen = Screen.HIDDEN
## Master volume as a linear 0..1, applied to the Master bus.
var master_volume := 1.0
## Music volume as a linear 0..1, applied to the Music bus. Starts below unity because a
## bed at the same level as the game is not a bed.
var music_volume := db_to_linear(AudioBuses.MUSIC_DEFAULT_DB)
var shift_minutes := 5
## Index into PACE_CHOICES. Steady by default: calmer than the game shipped, with the
## old pace still one button away.
var call_pace := 1
## Index into TIME_CHOICES, and a [enum Daylight.Mode] by construction. Day by default:
## it is the map as generated, and a player who has not been to settings should not be
## given a district they cannot read.
var time_of_day := 0
## Index into WEATHER_CHOICES, and a [enum Daylight.Weather]. Clear by default, for the
## same reason -- and because rain lowers grip, so it is a difficulty setting wearing a
## weather label and should be opted into.
var wet_weather := 0

## True when this menu **is** the main menu -- its own scene, over the backdrop, with
## no game HUD anywhere near it. PLAY then loads the district rather than lifting a
## card off one that was already running.
@export var is_main_menu := false

## Set by the main menu as it hands over, read by the district's own menu as it starts.
## A static rather than a signal because the two never exist at the same time: one
## scene is torn down before the other is built, and this is the only thing that has to
## survive the gap.
##
## `Playground.tscn` still opens on its own title card when it is loaded directly --
## which is what the suite does, and what a developer running the district does -- so
## the skip has to be asked for rather than assumed.
static var skip_title := false
## The scenario the main menu picked, if it picked one, as an index into
## [constant Scenarios.ALL]. -1 for none.
static var pending_scenario := -1

## True when this menu belongs to the tutorial scene, set by its TutorialSetup node
## after the HUD builds. Redirects restart/quit to scene changes -- the district's
## versions lean on a Director the tutorial deliberately does not have -- and hides
## the title furniture that only makes sense in the district.
var in_tutorial := false:
	set(value):
		in_tutorial = value
		if _f2_hint:
			_f2_hint.visible = not in_tutorial
		if _tutorial_button:
			_tutorial_button.visible = not in_tutorial
		if _scenario_button:
			_scenario_button.visible = not in_tutorial

var _f2_hint: Label
## The main menu's left-hand column. Held because it is the part of the title screen
## that actually occupies space -- the page around it is full-rect and transparent, so
## anything asking "is this point over the menu?" has to ask the column.
var _menu_column: PanelContainer
var _tutorial_button: Button
var _scenario_button: Button

## The speeds the transport buttons offer. 1.0 first, so index 0 is always normal.
const SPEEDS := [1.0, 1.5, 2.0]

## How fast the district is running, as a multiple. Not persisted with the other
## settings on purpose: shift length and call pace are *preferences*, and speed is a
## thing you reach for during one busy minute and put back. A session that silently
## opened at 2x because of something you did last week would read as a bug.
var game_speed := 1.0

## Handed over by [HUD] so Escape can tell "cancel what I am doing" from "open the menu".
## Null in the main menu, which has no district to be doing anything in.
var controller: RTSController

## Where SETTINGS was opened from, so BACK returns there.
var _settings_from: Screen = Screen.TITLE

var _dim: ColorRect
var _title_card: Control
var _scenario_card: Control
## The list inside the scenario card, refilled every time it opens.
var _scenario_rows: VBoxContainer
var _pause_card: Control
var _settings_card: Control
var _volume_slider: HSlider
var _music_slider: HSlider
var _length_buttons: Array[Button] = []
var _pace_buttons: Array[Button] = []
var _time_buttons: Array[Button] = []
var _weather_buttons: Array[Button] = []


func _ready() -> void:
	_load_settings()
	_apply_volume()

	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.05, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_title_card = _build_title()
	_pause_card = _build_pause()
	_settings_card = _build_settings()
	_scenario_card = _build_scenarios()

	# The session opens here -- unless the main menu has already been through and sent
	# the player somewhere. Arriving at a second title card, having just pressed PLAY on
	# the first, would read as the button not having worked.
	if skip_title and not is_main_menu:
		skip_title = false
		_switch(Screen.HIDDEN)
		played.emit()
		if pending_scenario >= 0:
			# Deferred twice over: the district's own nodes are still readying, and
			# `start_scenario` needs the scene root to be able to take a child.
			_start_pending.call_deferred()
	else:
		show_title()


## Keyboard, ahead of the GUI and of everything underneath. While the title is up
## every key is swallowed -- F2 must not open a shift under a menu -- and while
## paused the rest of the tree is not listening anyway.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match screen:
		Screen.HIDDEN:
			if key.physical_keycode == KEY_ESCAPE and not _escape_is_spoken_for():
				open_pause()
				get_viewport().set_input_as_handled()
		Screen.TITLE:
			if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE:
				play()
			get_viewport().set_input_as_handled()
		Screen.PAUSE:
			if key.physical_keycode == KEY_ESCAPE:
				resume()
				get_viewport().set_input_as_handled()
		Screen.SETTINGS:
			if key.physical_keycode == KEY_ESCAPE:
				close_settings()
				get_viewport().set_input_as_handled()
		Screen.SCENARIOS:
			# Back to the title, not into the game: this card is a step on the way in,
			# and Escape from it should undo the step. Everything else is swallowed
			# for the same reason the title swallows it.
			if key.physical_keycode == KEY_ESCAPE:
				show_title()
			get_viewport().set_input_as_handled()


## Whether something nearer the player already means something by Escape.
##
## Escape was "cancel" long before it was "pause": it disarms an armed ability
## ([RTSController]) and closes the shop ([ShopPanel]). Moving pause onto the same key
## puts three claims on it, and the order they are resolved in cannot be left to the
## tree -- this node's `_input` runs *before* both of them, so without this guard
## Escape-to-cancel would have opened the pause menu instead, which is the most annoying
## possible outcome of a rebind.
##
## The rule is the ordinary one for a cancel key: **it unwinds the innermost thing
## first.** Pause is the outermost, so it only fires when nothing else is open or armed.
func _escape_is_spoken_for() -> bool:
	if controller and controller.armed_ability:
		return true
	var shop := get_parent().get_node_or_null("Shop") as ShopPanel
	return shop != null and shop.visible


# --- The four states ----------------------------------------------------------

func show_title() -> void:
	_switch(Screen.TITLE)


## Fired the moment the player first lifts the title card -- PLAY, Enter and Space
## all route through [method play], so one emission covers every way in. The
## tutorial's director opens its scripted shout off this.
signal played

## PLAY: the card lifts and the game underneath starts hearing the player.
##
## Two shapes, because there are two menus. The main menu has no game under it, so PLAY
## is a scene change into the district with its title told to stand down. The district's
## own menu -- the one behind P -- lifts off a world that has been running all along.
func play() -> void:
	if is_main_menu:
		skip_title = true
		get_tree().paused = false
		get_tree().change_scene_to_file(DISTRICT_SCENE)
		return
	played.emit()
	_switch(Screen.HIDDEN)


## Opens the scenario the main menu picked, now that the district exists to run it in.
func _start_pending() -> void:
	var index := pending_scenario
	pending_scenario = -1
	if index >= 0:
		start_scenario(index)


## Nothing pre-loads the tutorial any more, and the reason is worth keeping.
##
## This used to fire `ResourceLoader.load_threaded_request` while the title was up, on
## the theory that the vendor town's 2.4MB of text could be parsed on a worker while
## the player read the menu. **It never worked.** Threaded, that file comes back a
## parse error every time -- at boot, a second and a half later, with the type named,
## in the district and in the menu scene alike -- while the same path loads perfectly
## synchronously. The measurement that seemed to prove it (819ms cold, 0ms warm) was a
## resource-cache hit in a probe, not the threaded path succeeding; and the check that
## guarded it asserted only that a *request had been made*, which was true of a feature
## that was failing on every boot.
##
## It stayed invisible because nothing reads stderr on a normal run. The main menu
## surfaced it: a fresh boot scene made the errors the first thing on the console.
## Into the practice town. The tutorial is its own scene with its own career file,
## so nothing a new player does there can touch the real books.
func start_tutorial() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TUTORIAL_SCENE)


func open_pause() -> void:
	_switch(Screen.PAUSE)


## Runs the district at [param multiple] normal speed.
##
## `Engine.time_scale` rather than a factor threaded through every `_process`: it scales
## physics, timers and animation together, which is the whole of what "faster" should
## mean here. Anything that must stay at wall-clock speed would have to opt out, and
## nothing currently does -- the shift clock is meant to run fast when the shift does.
##
## **Independent of pause.** `get_tree().paused` is a separate switch, so pausing at 2x
## and resuming comes back at 2x, which is what the player asked for and what they will
## expect.
func set_speed(multiple: float) -> void:
	game_speed = clampf(multiple, SPEEDS[0], SPEEDS[SPEEDS.size() - 1])
	Engine.time_scale = game_speed
	speed_changed.emit(game_speed)


## Emitted so the strip's buttons can follow a speed set from anywhere else.
signal speed_changed(multiple: float)


## Back to wall-clock. **`Engine.time_scale` is global and survives a scene change**, so
## anything that leaves the district has to put it back or the main menu's backdrop --
## and the next shift, and the suite -- all run at whatever the last shift was left on.
func reset_speed() -> void:
	set_speed(SPEEDS[0])


func resume() -> void:
	_switch(Screen.HIDDEN)


func open_settings() -> void:
	_settings_from = screen
	_switch(Screen.SETTINGS)


func close_settings() -> void:
	_switch(_settings_from)


## Abandon the running shift and open a fresh one. Units stay where they are --
## exactly what F2 after a debrief does -- but the board is cleared first, silently.
func restart_shift() -> void:
	# The tutorial restarts by reloading its scene: TutorialSetup re-runs, the
	# career resets and the board comes back clean -- replays are clean by
	# construction. `paused` survives a scene change, so the unpause is load-bearing.
	if in_tutorial:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	resume()
	if director == null:
		return
	director.abandon_shift()
	# The freed scenes close their calls over the next frames -- with scoring
	# already off they count for nothing -- and the new shift must not inherit them.
	for i in 3:
		await get_tree().process_frame
	director.begin_shift()


## Back to the main menu. A running shift is stood down first, without a debrief.
##
## A scene change from wherever it is used, because the title is a real screen now
## rather than a card over the district. `paused` survives a scene change, so the
## unpause is load-bearing -- this is reachable from the pause card, and arriving at a
## frozen main menu would look like a hang.
func quit_to_title() -> void:
	stand_down()
	get_tree().paused = false
	# Same reasoning as the unpause above, and the same trap: `Engine.time_scale` is
	# global and outlives the scene, so a shift left at 2x would hand the main menu a
	# backdrop running at double speed.
	reset_speed()
	get_tree().change_scene_to_file(MENU_SCENE)


## The half of leaving that belongs to the district: a running shift is abandoned, so
## the calls it leaves behind close silently rather than counting as cleared.
##
## Split out to be testable. Since the title became its own scene, `quit_to_title` ends
## in a scene change -- which in the suite would tear the district out from under every
## check after it, so the suite exercises this half and the constant it changes to.
func stand_down() -> void:
	if director and director.active:
		director.abandon_shift()


func quit_game() -> void:
	get_tree().quit()


func _switch(next: Screen) -> void:
	screen = next
	visible = screen != Screen.HIDDEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE if screen == Screen.HIDDEN \
		else Control.MOUSE_FILTER_STOP
	if _title_card:
		_title_card.visible = screen == Screen.TITLE
	if _pause_card:
		_pause_card.visible = screen == Screen.PAUSE
	if _settings_card:
		_settings_card.visible = screen == Screen.SETTINGS
	if _scenario_card:
		_scenario_card.visible = screen == Screen.SCENARIOS
	# The one line that freezes the district: everything else inherits PAUSABLE.
	# The title deliberately does not pause -- the living city is the backdrop.
	get_tree().paused = screen == Screen.PAUSE \
		or (screen == Screen.SETTINGS and _settings_from == Screen.PAUSE)


# --- Settings -----------------------------------------------------------------

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	AudioBuses.set_music_volume(music_volume)
	_save_settings()


func set_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	_save_settings()


func set_shift_minutes(minutes: int) -> void:
	shift_minutes = minutes
	if director:
		director.shift_length = minutes * 60.0
	for button in _length_buttons:
		button.button_pressed = int(button.get_meta(&"minutes")) == minutes
	_save_settings()


## The multiplier the current choice puts on the director's intervals.
func pace_scale() -> float:
	var choice: Dictionary = PACE_CHOICES[clampi(call_pace, 0, PACE_CHOICES.size() - 1)]
	return float(choice["scale"])


func set_call_pace(index: int) -> void:
	call_pace = clampi(index, 0, PACE_CHOICES.size() - 1)
	if director:
		director.pace = pace_scale()
	for i in _pace_buttons.size():
		_pace_buttons[i].button_pressed = i == call_pace
	_save_settings()


## The hour the district works at. Applied live, so the settings card is a preview:
## the map behind it goes dark while the button is being pressed.
func set_time_of_day(index: int) -> void:
	time_of_day = clampi(index, 0, TIME_CHOICES.size() - 1)
	if daylight:
		daylight.set_time_of_day(time_of_day)
	for i in _time_buttons.size():
		_time_buttons[i].button_pressed = i == time_of_day
	_save_settings()


## Which sky. Applied live like the hour for the fixed states, so the card previews
## it: the district behind the menu starts raining while the button is being pressed.
## SHIFT'S OWN previews nothing -- there is nothing to preview until a shift rolls --
## and deliberately leaves whatever sky is up, rather than yanking a rolled weather
## back to clear because the player opened the settings card mid-shift.
func set_weather(index: int) -> void:
	wet_weather = clampi(index, 0, WEATHER_CHOICES.size() - 1)
	if daylight and wet_weather < SHIFT_WEATHER:
		daylight.set_weather(wet_weather)
	for i in _weather_buttons.size():
		_weather_buttons[i].button_pressed = i == wet_weather
	_save_settings()


## The roll itself, on the shift opening. The menu owns only the policy: the director's
## seeded stream draws the answer, the sky wears it. Fixed choices leave the sky alone
## here -- it is already what the card set it to.
func _on_shift_started() -> void:
	if wet_weather == SHIFT_WEATHER and daylight and director:
		daylight.set_weather(director.roll_weather())


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioBuses.set_music_volume(music_volume)


func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	master_volume = clampf(float(settings.get_value("settings", "volume", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(settings.get_value("settings", "music",
		db_to_linear(AudioBuses.MUSIC_DEFAULT_DB))), 0.0, 1.0)
	var stored := int(settings.get_value("settings", "shift_minutes", 5))
	shift_minutes = stored if stored in SHIFT_CHOICES else 5
	call_pace = clampi(int(settings.get_value("settings", "call_pace", 1)),
		0, PACE_CHOICES.size() - 1)
	time_of_day = clampi(int(settings.get_value("settings", "time_of_day", 0)),
		0, TIME_CHOICES.size() - 1)
	wet_weather = clampi(int(settings.get_value("settings", "weather", 0)),
		0, WEATHER_CHOICES.size() - 1)


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("settings", "volume", master_volume)
	settings.set_value("settings", "music", music_volume)
	settings.set_value("settings", "shift_minutes", shift_minutes)
	settings.set_value("settings", "call_pace", call_pace)
	settings.set_value("settings", "time_of_day", time_of_day)
	settings.set_value("settings", "weather", wet_weather)
	settings.save(settings_path)


# --- Building the cards -------------------------------------------------------

## The main menu: a column down the left, the living district as the picture.
##
## Built to the reference the user supplied -- title plate, a stack of icon rows, a
## version plate at the foot -- with one deliberate substitution. The reference fills
## its right-hand two thirds with a painted key-art panel. This game does not have one,
## and it does not need one: the district behind this menu is **live** -- crowds
## walking, traffic moving, the shift parked -- which is the thing a still image of a
## game is trying to imply. So the column sits over the city rather than beside a
## painting of it, and the right-hand two thirds are the city itself.
##
## That is also why this is still an overlay in the HUD rather than its own scene.
## Three things fall out of it: the backdrop is alive, `main_scene` stays
## `Playground.tscn`, and PLAY costs nothing -- no scene load, no loading screen, the
## card simply lifts off a world that has been running the whole time. A separate menu
## scene would buy a static picture and a wait.
func _build_title() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	# Anchored to the left edge and centred vertically: top and bottom anchors both at
	# the middle with both grow directions, so the column is as tall as its own content
	# and stays centred however many rows are showing. The tutorial hides two of them.
	_menu_column = PanelContainer.new()
	_menu_column.theme_type_variation = &"MenuContainer"
	_menu_column.anchor_left = 0.0
	_menu_column.anchor_right = 0.0
	_menu_column.anchor_top = 0.5
	_menu_column.anchor_bottom = 0.5
	_menu_column.offset_left = COLUMN_INSET
	_menu_column.offset_right = COLUMN_INSET + COLUMN_WIDTH
	_menu_column.grow_vertical = Control.GROW_DIRECTION_BOTH
	page.add_child(_menu_column)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_menu_column.add_child(body)

	# The kit's title plate is an empty slot sized to the column -- meant for a logo,
	# and carrying the game's name as type until there is one.
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"TitlePlate"
	body.add_child(plate)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	plate.add_child(heading)
	var name_label := _label(heading, TITLE_TEXT, &"BannerLabel")
	name_label.add_theme_font_size_override("font_size", 38)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# No outline here, unlike the in-world banner this variation is named for: the plate
	# is behind it, so an outline would only thicken the letters.
	name_label.add_theme_constant_override("outline_size", 0)
	var subtitle := _label(heading, SUBTITLE_TEXT, &"HeaderLabel")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_gap(body, 10.0)

	_button(body, "PLAY", play, "MenuItem").icon = _icon("play")
	_tutorial_button = _button(body, "TUTORIAL", start_tutorial, "MenuItem")
	_tutorial_button.icon = _icon("info")
	_tutorial_button.visible = not in_tutorial
	# Not offered inside the tutorial for the same reason TUTORIAL is not: a scenario
	# is a district shift, and this menu belongs to a practice town that has no
	# freeplay director to place one with.
	_scenario_button = _button(body, "SCENARIOS", open_scenarios, "MenuItem")
	_scenario_button.icon = _icon("clipboard")
	_scenario_button.visible = not in_tutorial
	_button(body, "SETTINGS", open_settings, "MenuItem").icon = _icon("gear")
	_button(body, "QUIT", quit_game, "MenuItem").icon = _icon("exit")

	_gap(body, 10.0)

	var version := PanelContainer.new()
	version.theme_type_variation = &"VersionPlate"
	body.add_child(version)
	var stamp := VBoxContainer.new()
	stamp.add_theme_constant_override("separation", 1)
	version.add_child(stamp)
	var build_line := _label(stamp, VERSION_TEXT, &"HeaderLabel")
	build_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_f2_hint = _label(stamp, "F2 opens a shift once you are in", &"HeaderLabel")
	_f2_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_f2_hint.visible = not in_tutorial
	return page


## A kit icon by its bare name. Returns null for a missing one, which a Button treats
## as "no icon" rather than raising -- the same rule the glyph pack follows, so a row
## whose icon is renamed loses its picture instead of the menu.
func _icon(name: String) -> Texture2D:
	var path := "res://Game/UI/Kit/icons/icon_%s.svg" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _build_pause() -> Control:
	var body := _card()
	_label(body, "PAUSED", &"BannerLabel")
	_gap(body, 10.0)
	_button(body, "RESUME", resume, "PrimaryButton")
	_button(body, "RESTART SHIFT", restart_shift)
	_button(body, "SETTINGS", open_settings)
	_button(body, "QUIT TO TITLE", quit_to_title, "DangerButton")
	_button(body, "QUIT GAME", quit_game, "DangerButton")
	return body.get_parent().get_parent()


func _build_settings() -> Control:
	var body := _card()
	_label(body, "SETTINGS", &"BannerLabel")
	_gap(body, 10.0)

	_label(body, "MASTER VOLUME", &"HeaderLabel")
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = master_volume
	_volume_slider.custom_minimum_size = Vector2(240.0, 20.0)
	_volume_slider.focus_mode = Control.FOCUS_NONE
	_volume_slider.value_changed.connect(set_volume)
	body.add_child(_volume_slider)
	_gap(body, 10.0)

	# **Balance, not level.** Master is the whole game; this is how loud the bed sits
	# under it. Separate because the only way to quieten music on a single bus is to
	# quieten the sirens with it, and the sirens are information.
	_label(body, "MUSIC", &"HeaderLabel")
	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step = 0.05
	_music_slider.value = music_volume
	_music_slider.custom_minimum_size = Vector2(240.0, 20.0)
	_music_slider.focus_mode = Control.FOCUS_NONE
	_music_slider.value_changed.connect(set_music_volume)
	body.add_child(_music_slider)
	_gap(body, 10.0)

	_label(body, "SHIFT LENGTH", &"HeaderLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	for minutes in SHIFT_CHOICES:
		var choice := Button.new()
		choice.text = "%d MIN" % minutes
		choice.toggle_mode = true
		choice.button_pressed = minutes == shift_minutes
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size = Vector2(74.0, 34.0)
		choice.set_meta(&"minutes", minutes)
		choice.pressed.connect(set_shift_minutes.bind(int(minutes)))
		row.add_child(choice)
		_length_buttons.append(choice)
	_gap(body, 10.0)

	_label(body, "CALL RATE", &"HeaderLabel")
	var pace_row := HBoxContainer.new()
	pace_row.add_theme_constant_override("separation", 8)
	pace_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(pace_row)
	for i in PACE_CHOICES.size():
		var choice := Button.new()
		choice.text = str(PACE_CHOICES[i]["label"])
		choice.toggle_mode = true
		choice.button_pressed = i == call_pace
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size = Vector2(78.0, 34.0)
		choice.pressed.connect(set_call_pace.bind(i))
		pace_row.add_child(choice)
		_pace_buttons.append(choice)
	_gap(body, 10.0)

	_label(body, "TIME OF DAY", &"HeaderLabel")
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(time_row)
	for i in TIME_CHOICES.size():
		var choice := Button.new()
		choice.text = str(TIME_CHOICES[i])
		choice.toggle_mode = true
		choice.button_pressed = i == time_of_day
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size = Vector2(78.0, 34.0)
		choice.pressed.connect(set_time_of_day.bind(i))
		time_row.add_child(choice)
		_time_buttons.append(choice)
	_gap(body, 10.0)

	_label(body, "WEATHER", &"HeaderLabel")
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 8)
	weather_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(weather_row)
	for i in WEATHER_CHOICES.size():
		var choice := Button.new()
		choice.text = str(WEATHER_CHOICES[i])
		choice.toggle_mode = true
		choice.button_pressed = i == wet_weather
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size = Vector2(78.0, 34.0)
		choice.pressed.connect(set_weather.bind(i))
		weather_row.add_child(choice)
		_weather_buttons.append(choice)
	_gap(body, 12.0)

	# The career hard-reset: fleet dissolved, purse back to the starter budget.
	# In settings rather than on a face button, so it takes deliberate digging.
	_button(body, "RESET CAREER", reset_career, "DangerButton")
	_button(body, "BACK", close_settings, "TertiaryButton")
	return body.get_parent().get_parent()


## Wipes the career back to the starting purse. The station is found by group the
## same way the mission finds it -- the generated scene never learns a new wire.
func reset_career() -> void:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station:
		station.reset_career()


## The designed shifts, one row each: name, brief, par, and a button that is only
## live if the career can field what the scenario asks for.
##
## Rebuilt every time the card opens rather than once in `_ready`, because the roster
## is the thing that decides whether a row can be played and the player buys units
## between visits. A card built at startup would still be offering a warehouse fire to
## someone who has since sold the engine -- or, more likely, refusing one to someone
## who has just bought it.
func _build_scenarios() -> Control:
	var body := _card()
	_label(body, "SCENARIOS", &"BannerLabel")
	_label(body, "A written shift, against the clock.", &"DimLabel")
	_gap(body, 10.0)
	_scenario_rows = VBoxContainer.new()
	_scenario_rows.add_theme_constant_override("separation", 12)
	body.add_child(_scenario_rows)
	_gap(body, 8.0)
	_button(body, "BACK", show_title, "TertiaryButton")
	return body.get_parent().get_parent()


func open_scenarios() -> void:
	_fill_scenarios()
	_switch(Screen.SCENARIOS)


func _fill_scenarios() -> void:
	if _scenario_rows == null:
		return
	for child in _scenario_rows.get_children():
		_scenario_rows.remove_child(child)
		child.queue_free()

	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	for index in Scenarios.ALL.size():
		var scenario: Dictionary = Scenarios.ALL[index]
		var missing := Scenarios.missing_for(scenario, station)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_scenario_rows.add_child(row)

		var brief := _label(row, str(scenario["brief"]), &"DimLabel")
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(360.0, 0.0)
		# Under the brief, so the reason a row is dead is next to the row rather than
		# in a message somewhere else on the card.
		if not missing.is_empty():
			_label(row, "needs " + ", ".join(PackedStringArray(missing)),
				&"HeaderLabel")
		var caption := "%s   ·   par %02d:%02d" % [str(scenario["name"]),
			int(scenario["par"]) / 60, int(scenario["par"]) % 60]
		var button := _button(row, caption, start_scenario.bind(index),
			"PrimaryButton")
		button.disabled = not missing.is_empty()
		# The brief reads above its own button, not below the one before it.
		row.move_child(button, 0)


## Opens a designed shift in the district: the card lifts and a [ScenarioDirector]
## created here plays the timeline.
##
## Made at runtime on purpose. `Playground.tscn` is generated, so shipping a node in it
## means editing `build_map.gd` and regenerating with a window; this needs neither, and
## a scenario the player never picks costs nothing at all.
func start_scenario(index: int) -> void:
	var scenario := Scenarios.by_index(index)
	if scenario.is_empty():
		return
	# From the main menu there is no district to put a runner in yet: the pick is
	# carried across the scene change and started by the district's own menu.
	if is_main_menu:
		pending_scenario = index
		skip_title = true
		get_tree().paused = false
		get_tree().change_scene_to_file(DISTRICT_SCENE)
		return
	var scene := _scene_root()
	if scene == null:
		return
	# One at a time: picking a second scenario replaces the first rather than running
	# two timelines into the same district.
	for existing in scene.get_children():
		if existing is ScenarioDirector:
			existing.queue_free()
	var runner := ScenarioDirector.new()
	runner.name = "ScenarioDirector"
	scene.add_child(runner)
	runner.begin(scenario)
	play()


## The top of the running scene, whatever added it.
##
## `get_tree().current_scene` is the obvious answer and the wrong one: it is only set
## for the scene the tree itself opened, and the test suite adds the district by hand,
## so a scenario picked under test had nowhere to put its runner and quietly did
## nothing. Walking up from this node reaches the same place either way.
func _scene_root() -> Node:
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node


## A centred card: CenterContainer -> CardPanel -> VBox, returning the VBox.
func _card() -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	centre.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(body)
	return body


func _label(parent: Node, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


## [param variation] picks the UI kit's button family: "MenuItem" for a title row,
## "PrimaryButton" for the one thing a card is asking you to do, "DangerButton" for
## anything that throws work away, "TertiaryButton" for a way back out. Empty is the
## kit's secondary button, which is the sensible default for a row of equals.
func _button(parent: Node, caption: String, action: Callable,
		variation := "") -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	# Menu rows are taller than a plain button: the kit's menu-item art carries a
	# left-hand accent bar and needs the height to read as a row rather than a box.
	button.custom_minimum_size = Vector2(250.0, 44.0 if variation == "MenuItem" else 38.0)
	if variation != "":
		button.theme_type_variation = StringName(variation)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _gap(parent: Node, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size = Vector2(0.0, height)
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(space)
