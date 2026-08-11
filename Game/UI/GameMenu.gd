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

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS }

const TITLE_TEXT := "EMERGENCY RTS"
## Both halves of the old line went stale: the roster stopped being a fixed issue when
## the career economy made it something bought, and the five minutes became a setting.
## What is still true of every shift is the district and the clock.
const SUBTITLE_TEXT := "A district, a fleet you paid for, and a clock."
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
## the index *is* the value, so there is no table to fall out of step.
const WEATHER_CHOICES := ["CLEAR", "RAIN"]

## A var rather than a const so the test suite can point it at a disposable file.
var settings_path := "user://settings.cfg"

## Wired by the HUD. Assigning the director applies the stored shift length to it.
var director: Director:
	set(value):
		director = value
		if director:
			director.shift_length = shift_minutes * 60.0
			director.pace = pace_scale()

## Wired by the HUD, same as the director. Assigning it applies the stored hour, which
## is what makes the setting survive a restart rather than only a change.
var daylight: Daylight:
	set(value):
		daylight = value
		if daylight:
			daylight.set_time_of_day(time_of_day)
			daylight.set_weather(wet_weather)

var screen: Screen = Screen.HIDDEN
## Master volume as a linear 0..1, applied to the Master bus.
var master_volume := 1.0
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

## Where SETTINGS was opened from, so BACK returns there.
var _settings_from: Screen = Screen.TITLE

var _dim: ColorRect
var _title_card: Control
var _pause_card: Control
var _settings_card: Control
var _volume_slider: HSlider
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

	# The session opens here.
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
			if key.physical_keycode == KEY_P:
				open_pause()
				get_viewport().set_input_as_handled()
		Screen.TITLE:
			if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE:
				play()
			get_viewport().set_input_as_handled()
		Screen.PAUSE:
			if key.physical_keycode == KEY_P or key.physical_keycode == KEY_ESCAPE:
				resume()
				get_viewport().set_input_as_handled()
		Screen.SETTINGS:
			if key.physical_keycode == KEY_ESCAPE:
				close_settings()
				get_viewport().set_input_as_handled()


# --- The four states ----------------------------------------------------------

func show_title() -> void:
	_switch(Screen.TITLE)


## PLAY: the card lifts and the game underneath starts hearing the player.
func play() -> void:
	_switch(Screen.HIDDEN)


func open_pause() -> void:
	_switch(Screen.PAUSE)


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
	resume()
	if director == null:
		return
	director.abandon_shift()
	# The freed scenes close their calls over the next frames -- with scoring
	# already off they count for nothing -- and the new shift must not inherit them.
	for i in 3:
		await get_tree().process_frame
	director.begin_shift()


## Back to the title. A running shift is stood down without a debrief; the district
## idles on behind the card.
func quit_to_title() -> void:
	if director and director.active:
		director.abandon_shift()
	show_title()


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
	# The one line that freezes the district: everything else inherits PAUSABLE.
	# The title deliberately does not pause -- the living city is the backdrop.
	get_tree().paused = screen == Screen.PAUSE \
		or (screen == Screen.SETTINGS and _settings_from == Screen.PAUSE)


# --- Settings -----------------------------------------------------------------

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


## Wet or dry. Applied live like the hour, so the card previews it: the district behind
## the menu starts raining while the button is being pressed.
func set_weather(index: int) -> void:
	wet_weather = clampi(index, 0, WEATHER_CHOICES.size() - 1)
	if daylight:
		daylight.set_weather(wet_weather)
	for i in _weather_buttons.size():
		_weather_buttons[i].button_pressed = i == wet_weather
	_save_settings()


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	master_volume = clampf(float(settings.get_value("settings", "volume", 1.0)), 0.0, 1.0)
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
	settings.set_value("settings", "shift_minutes", shift_minutes)
	settings.set_value("settings", "call_pace", call_pace)
	settings.set_value("settings", "time_of_day", time_of_day)
	settings.set_value("settings", "weather", wet_weather)
	settings.save(settings_path)


# --- Building the cards -------------------------------------------------------

func _build_title() -> Control:
	var body := _card()
	var name_label := _label(body, TITLE_TEXT, &"BannerLabel")
	name_label.add_theme_font_size_override("font_size", 54)
	_label(body, SUBTITLE_TEXT, &"DimLabel")
	_gap(body, 14.0)
	_button(body, "PLAY", play)
	_button(body, "SETTINGS", open_settings)
	_button(body, "QUIT", quit_game)
	_gap(body, 8.0)
	_label(body, "F2 opens a shift once you are in", &"HeaderLabel")
	return body.get_parent().get_parent()


func _build_pause() -> Control:
	var body := _card()
	_label(body, "PAUSED", &"BannerLabel")
	_gap(body, 10.0)
	_button(body, "RESUME", resume)
	_button(body, "RESTART SHIFT", restart_shift)
	_button(body, "SETTINGS", open_settings)
	_button(body, "QUIT TO TITLE", quit_to_title)
	_button(body, "QUIT GAME", quit_game)
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
	_button(body, "RESET CAREER", reset_career)
	_button(body, "BACK", close_settings)
	return body.get_parent().get_parent()


## Wipes the career back to the starting purse. The station is found by group the
## same way the mission finds it -- the generated scene never learns a new wire.
func reset_career() -> void:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station:
		station.reset_career()


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


func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(250.0, 38.0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _gap(parent: Node, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size = Vector2(0.0, height)
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(space)
