extends CanvasLayer

## Wires the interface panels to the controller and the mission, and nothing else.
##
## Each panel owns what it shows: the portrait reads the selection, the roster lists
## every unit under command, the command grid builds tiles from the abilities the
## selection advertises, the status strip and the incident list read the world. This
## file only hands them the two references they need, and keeps the win/lose banner,
## which belongs to no panel.
##
## The command bar being generated from abilities is unchanged from the first version:
## give a unit a new verb and a tile appears here, with its hotkey bound, without this
## file knowing the verb exists.

## NodePath rather than a typed export so the reference survives being written out
## by Game/build_map.gd.
@export var controller_path: NodePath
@export var mission_path: NodePath
@export var call_board_path: NodePath
@export var station_path: NodePath
@export var director_path: NodePath
@export var daylight_path: NodePath

@onready var _banner: Label = $Root/World/Banner
@onready var _debrief: Label = $Root/World/Debrief
@onready var _menu: GameMenu = $Root/Menu
@onready var _shop: ShopPanel = $Root/Shop
@onready var _help: PanelContainer = $Root/World/HelpPanel
@onready var _controls_toggle: PanelContainer = $Root/World/ControlsToggle
@onready var _status: StatusStrip = $Root/World/StatusStrip
@onready var _calls: CallList = $Root/World/CallList
@onready var _radio: RadioLog = $Root/World/RadioLog
@onready var _debrief_card: DebriefCard = $Root/World/DebriefCard
@onready var _dispatch: DispatchPanel = $Root/Bar/Row/DispatchBlock/Body/Dispatch
@onready var _portrait: Portrait = $Root/Bar/Row/PortraitBlock/Portrait
@onready var _roster: Roster = $Root/Bar/Row/RosterBlock/Body/Roster
@onready var _commands: CommandGrid = $Root/Bar/Row/CommandBlock/Body/CommandGrid

var _mission: Mission
var _director: Director
var _station: Station


func _ready() -> void:
	Hover.attach(_controls_toggle)
	# The visible route to the controls card; F1 is its shortcut, not its secret.
	_controls_toggle.gui_input.connect(_on_controls_toggle)

	_mission = get_node_or_null(mission_path) as Mission
	if _mission:
		_mission.state_changed.connect(_show_banner)
		_status.mission = _mission

	_director = get_node_or_null(director_path) as Director
	_status.director = _director
	# The menu restarts shifts and applies the stored shift length, so it needs the
	# director; assigning it is what pushes the setting onto the node.
	_menu.director = _director
	# Same shape: the stored hour is applied by handing the node over, so a district
	# that was left at night comes back at night.
	_menu.daylight = get_node_or_null(daylight_path) as Daylight
	_station = get_node_or_null(station_path) as Station
	# The radio takes all three: the board for jobs opening and crews arriving, the
	# director for the shift's own start and finish, the station for a booking-in.
	# Everything else it hears by watching incidents resolve.
	_radio.director = _director
	_radio.station = _station
	if _director:
		# The map opens quiet -- and now empty -- so the screen has to say what comes
		# first: buying a fleet, then F2. Cleared by shift_started rather than by a
		# state change, because opening a shift leaves the mission RUNNING, which it
		# already was; re-read whenever the roster moves, because the first purchase
		# is what changes the advice.
		_refresh_hint()
		_director.shift_started.connect(func() -> void:
			_debrief.visible = false
			_debrief_card.hide_card())
		if _station:
			_station.roster_changed.connect(_refresh_hint)

	var board := get_node_or_null(call_board_path) as CallBoard
	_status.board = board
	_calls.board = board
	_radio.board = board
	# The radio answers to the board and the shift; the city bed just plays.
	var soundscape := get_node_or_null("Soundscape") as Soundscape
	if soundscape:
		soundscape.listen(board, _director)

	var controller := get_node_or_null(controller_path) as RTSController
	if controller == null:
		return
	# Godot readies children before their parent, so every panel below has already run
	# its own _ready by now. The ones that build from the controller connect through a
	# setter for exactly that reason; reading the reference in their _ready would find
	# null and leave the bar empty for the whole session.
	_portrait.controller = controller
	_roster.controller = controller
	_commands.controller = controller
	_calls.controller = controller
	_dispatch.controller = controller
	var minimap := get_node_or_null("Root/World/MinimapCard/Minimap") as Minimap
	if minimap:
		minimap.controller = controller
	# The shop and the dispatch rows both answer to the same station; the panel also
	# holds the shop so its heading (and any unowned row) can open it.
	_shop.station = _station
	_dispatch.shop = _shop
	# Last: the setter builds the rows and needs the controller already in place, so a
	# dispatched unit can be handed straight to the selection.
	_dispatch.station = _station


## The mid-screen line before a shift: what to do next. "Buy units" until anything
## is owned, then "press F2". Only touched while it is the thing on screen -- a
## running shift has it hidden, and a debrief owns the label for its own text.
func _refresh_hint() -> void:
	if _director == null or _director.active:
		return
	if _mission and _mission.state != Mission.State.RUNNING:
		return
	var fleet := 0
	if _station:
		for config in Station.TYPES:
			fleet += _station.total(config["id"])
	_debrief.text = "Buy your first units from  DISPATCH" if _station and fleet == 0 \
		else "Press  F2  to start a shift"
	_debrief.visible = true


func _on_controls_toggle(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_controls_toggle.accept_event()
		_help.visible = not _help.visible


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		_help.visible = not _help.visible
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F2:
		# The freeplay shift. Idempotent mid-shift; after a debrief it opens a new one.
		if _director:
			_director.begin_shift()
		get_viewport().set_input_as_handled()


func _show_banner(state: Mission.State) -> void:
	_debrief.visible = false
	match state:
		Mission.State.WON:
			_banner.text = "SHOUT COMPLETE"
			_banner.add_theme_color_override("font_color", Palette.MEDICAL_DEEP)
			_banner.visible = true
		Mission.State.LOST:
			_banner.text = "CASUALTY LOST"
			_banner.add_theme_color_override("font_color", Palette.CASUALTY_DEEP)
			_banner.visible = true
		Mission.State.OVER:
			# End of a freeplay shift. The card carries its own heading, so the banner
			# and the one-line debrief both stand down rather than repeating it above a
			# table that says the same thing at length.
			_banner.visible = false
			_debrief.visible = false
			if _mission:
				_debrief_card.show_shift(_mission)
		_:
			_banner.visible = false
