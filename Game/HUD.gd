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
@onready var _debrief: Label = $Root/World/ObjectiveBar/Body/Debrief
@onready var _menu: GameMenu = $Root/Menu
@onready var _shop: RequisitionPanel = $Root/Shop
@onready var _help: PanelContainer = $Root/World/HelpPanel
@onready var _controls_toggle: PanelContainer = $Root/World/ControlsToggle
@onready var _status: StatusStrip = $Root/World/StatusStrip
@onready var _score: ScoreStrip = $Root/World/ScoreStrip
@onready var _calls: CallList = $Root/World/CallList
@onready var _radio: RadioLog = $Root/World/RadioLog
@onready var _debrief_card: DebriefCard = $Root/World/DebriefCard
@onready var _dispatch: DispatchPanel = $Root/Bar/Row/DispatchBlock/Body/Dispatch
@onready var _portrait: Portrait = $Root/Bar/Row/PortraitBlock/Portrait
@onready var _roster: RosterSidebar = $Root/Bar/Row/RosterBlock/Body/Roster
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
		_score.mission = _mission
	# The only on-screen route to the pause card and settings; `P` is its shortcut.
	_score.menu = _menu

	_director = get_node_or_null(director_path) as Director
	_status.director = _director
	# The menu restarts shifts and applies the stored shift length, so it needs the
	# director; assigning it is what pushes the setting onto the node.
	_menu.director = _director
	# Same shape: the stored hour is applied by handing the node over, so a district
	# that was left at night comes back at night.
	_menu.daylight = get_node_or_null(daylight_path) as Daylight
	_station = get_node_or_null(station_path) as Station
	_score.station = _station
	if _station:
		# The strip re-reads itself every frame *while a shift runs*, which is when the
		# score moves. Buying the first unit happens before that, on a quiet district --
		# so the fleet count needs telling, or it sits on zero until F2.
		_station.roster_changed.connect(_score.refresh)
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
	# The roster is where units are sent out from now, so it needs the books as well as
	# the selection.
	_roster.station = _station
	# Not to build anything with -- the menu needs it to tell "cancel what I am doing"
	# from "open the menu" now that both are Escape.
	_menu.controller = controller
	_commands.controller = controller
	_calls.controller = controller
	_dispatch.controller = controller
	var controls := get_node_or_null(
		"Root/World/MapControls") as MapControls
	if controls:
		controls.camera = get_viewport().get_camera_3d() as RTSCamera
	var minimap := get_node_or_null("Root/World/MinimapCard/Minimap") as Minimap
	if minimap:
		minimap.controller = controller
	# The shop and the dispatch rows both answer to the same station; the panel also
	# holds the shop so its heading (and any unowned row) can open it.
	_shop.station = _station
	_dispatch.shop = _shop
	_wire_buy_button()
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
	_debrief.text = "Buy your first units from the  CART  button" if _station and fleet == 0 \
		else "Press  F2  to start a shift"
	_debrief.visible = true


## The corner buy button: an icon, a tooltip, and the shop behind it.
##
## Dressed here rather than in `HUD.tscn` because a `.tscn` cannot say "use this icon if
## the file exists" -- and the kit's icon set is a vendor folder, so a missing name has to
## cost the picture and not the button. Same rule the glyph pack and the map controls
## follow.
func _wire_buy_button() -> void:
	var buy := get_node_or_null("Root/World/BuyButton") as Button
	if buy == null:
		return
	# **A cart, drawn for this button.** It was the kit's plus, because none of its 44
	# icons is a cart -- and a plus reads as "add one more of whatever I am looking at",
	# which is not what a storefront door means. `Game/UI/Icons/` is the project's own
	# folder, so a glyph the vendor pack does not carry is authored here rather than
	# added to `Game/UI/Kit/`, which is a copy of someone else's set.
	var path := "res://Game/UI/Icons/cart.svg"
	if ResourceLoader.exists(path):
		buy.icon = load(path) as Texture2D
	# **Godot left-aligns a Button's icon**, even when the button has no text for it to
	# sit beside -- so an icon-only button draws its glyph against the left margin and
	# looks skewed. Both alignments have to be said; setting the horizontal one alone
	# leaves it riding high.
	buy.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	buy.tooltip_text = "Buy units"
	Hover.attach(buy)
	if not buy.pressed.is_connected(_shop.open_shop):
		buy.pressed.connect(_shop.open_shop)


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
			# The card carries the heading now, the same trade the end of a shift
			# makes: a banner can say the job is done and nothing else, and what a
			# player wants at the end of one is what it came to.
			_banner.visible = false
			if _mission:
				_debrief_card.show_shout(_mission)
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
			# Back to RUNNING -- a new shift, or a shout re-opened. The card goes with
			# it, and takes its hold on the mouse with it: a modal left standing over a
			# live district would swallow every order the player gave.
			_debrief_card.hide_card()
