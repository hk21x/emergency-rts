extends PanelContainer
class_name ScoreStrip

## The top-right strip: the score, the fleet, and the way out of the game.
##
## The reference layout puts a small cluster opposite the clock -- a running total, a
## count of what you have, and transport controls -- and this is that corner. Two of the
## three are readings the district already keeps; the third is the only *new* control the
## restructure added, and it is the one that mattered most: until this panel existed the
## pause menu could be reached by pressing `P` and by no other means. A game whose menu
## is a keystroke nobody was told about is a game with no menu.
##
## **Not the reference's transport row.** That draws play, pause and fast-forward, which
## implies game-speed control; this game has one speed. So the two buttons are pause and
## settings, which are the two things a player actually wants from that corner, on the
## kit's transport-button art.
##
## Score moved here out of [StatusStrip] rather than being copied: a number shown in two
## strips at once is a number that will eventually disagree with itself.

## The readings, left to right. `id` is what [method refresh] looks them up by.
const BLOCKS := [
	{"id": &"funds", "caption": "£"},
	{"id": &"score", "caption": "SCORE"},
	{"id": &"units", "caption": "UNITS"},
]

## Only while a shift is being scored does the total mean anything; the strip keeps the
## fleet count and the buttons up regardless, so the corner never empties out.
var mission: Mission: set = _set_mission
var station: Station: set = _set_station
var menu: GameMenu: set = _set_menu

## `id -> {"block": PanelContainer, "value": Label}`.
var _blocks := {}
## The speed buttons, in [constant GameMenu.SPEEDS] order.
var _speeds: Array[Button] = []


func _ready() -> void:
	theme_type_variation = &"TopBarPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for spec: Dictionary in BLOCKS:
		var made := StatusStrip.stat_block(str(spec["caption"]))
		row.add_child(made["block"])
		_blocks[spec["id"]] = made

	_button(row, "pause", func() -> void: _open(true))
	_build_speeds(row)
	_button(row, "gear", func() -> void: _open(false))
	refresh()


## The speed buttons: 1x, 1.5x, 2x, one of them always on.
##
## **Normal speed gets a button too**, though only the faster two were asked for. Two
## buttons that turn something on need a third that turns it off, or the way back to
## wall-clock is "press the lit one again", which is a thing you have to be told. Three
## in a group is self-describing: one is lit, and it is the speed you are running at.
##
## Text rather than icons. The kit ships play and fast-forward vectors, but a
## fast-forward glyph cannot say *which* fast -- and the difference between 1.5x and 2x
## is the entire point of having two of them.
func _build_speeds(row: HBoxContainer) -> void:
	var group := ButtonGroup.new()
	for multiple: float in GameMenu.SPEEDS:
		var button := Button.new()
		button.theme_type_variation = &"TransportButton"
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(46.0, 34.0)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# "1x" not "1.0x": the trailing zero reads as precision the setting does not have.
		button.text = ("%.1fx" % multiple).replace(".0x", "x")
		button.button_pressed = is_equal_approx(multiple, 1.0)
		button.pressed.connect(func() -> void:
			if menu:
				menu.set_speed(multiple))
		row.add_child(button)
		_speeds.append(button)


## A transport button. Deliberately the only thing on this strip that takes the mouse --
## the panel and every label on it ignore it, so a drag started over the readings is
## still a box-select out in the world.
func _button(row: HBoxContainer, icon: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"TransportButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(40.0, 34.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var path := "res://Game/UI/Kit/icons/icon_%s.svg" % icon
	if ResourceLoader.exists(path):
		button.icon = load(path) as Texture2D
	# Icon-only, so both alignments have to be centred -- see the note in `HUD.gd`.
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	row.add_child(button)
	return button


## Opens the pause card, or settings on top of it.
##
## Both go through [GameMenu] rather than pausing here: pausing the tree is one line in
## `_switch` and the card that says so is the same node's, so a second place that froze
## the district would be a second place to unfreeze it from.
func _open(paused_only: bool) -> void:
	if menu == null:
		return
	menu.open_pause()
	if not paused_only:
		menu.open_settings()


## Takes the menu and immediately reads the speed *off* it rather than assuming 1x.
##
## The buttons are built in `_ready`, before [HUD] hands this over, so they start lit on
## normal by construction. If the menu ever arrives running at something else -- a
## restart that kept the speed, a scene that set it before the HUD built -- the strip
## would sit there claiming 1x while the district ran at 2x, which is the sort of
## disagreement that gets reported as "the buttons do nothing".
func _set_menu(value: GameMenu) -> void:
	menu = value
	if menu == null:
		return
	if not menu.speed_changed.is_connected(_show_speed):
		menu.speed_changed.connect(_show_speed)
	_show_speed(menu.game_speed)


func _show_speed(multiple: float) -> void:
	for i in _speeds.size():
		_speeds[i].button_pressed = is_equal_approx(
			float(GameMenu.SPEEDS[i]), multiple)


func _set_mission(value: Mission) -> void:
	mission = value
	refresh()


func _set_station(value: Station) -> void:
	station = value
	refresh()


func _process(_delta: float) -> void:
	if mission and mission.state == Mission.State.RUNNING:
		refresh()


func refresh() -> void:
	if _blocks.is_empty():
		return

	var scoring: bool = mission != null and mission.scoring
	_show(&"score", scoring, str(mission.score) if scoring else "")

	# What is on the books, not what is out on the map: this is the count the roster
	# down the left-hand side is listing, and the two disagreeing would read as a bug in
	# whichever the player happened to trust.
	var fleet := 0
	if station:
		for config in Station.TYPES:
			fleet += station.total(config["id"])
	_show(&"units", fleet > 0, str(fleet))

	# **The purse, up here since August 2026.** It used to be the dispatch block's
	# heading, and the dispatch block is gone -- but the number outlived it, because what
	# it answers ("can I afford another one?") is asked while looking at the shop, not
	# while looking at a list of what is parked. Always shown, unlike the two beside it:
	# a career with £0 needs to know that more than a career with money does. Damage owed
	# rides along when there is any, since it is money that is already spoken for.
	if station:
		_show(&"funds", true, "%d" % station.funds if station.debt <= 0
			else "%d   -%d" % [station.funds, station.debt])
	else:
		_show(&"funds", false, "")


func _show(id: StringName, visible_now: bool, text: String) -> void:
	var entry: Dictionary = _blocks.get(id, {})
	if entry.is_empty():
		return
	(entry["block"] as Control).visible = visible_now
	(entry["value"] as Label).text = text
