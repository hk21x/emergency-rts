extends Node
class_name ClickSounds

## The interface's own noises: a click when something is pressed, a tick when the pointer
## crosses it.
##
## **A passive watcher, not a helper you have to remember to call.** Every interactive
## control in this game would otherwise need a `Click.attach(self)` beside its existing
## `Hover.attach(self)` -- and they are built in nine different files, several of them at
## runtime (roster chips, command tiles, call rows, shop cards). A helper is a rule, and a
## rule that has to be repeated at nine call sites is a rule that will be missed at the
## tenth. So this hooks `SceneTree.node_added` and finds them itself, the same shape
## [Mission] and [CallBoard] take, which CLAUDE.md asks new systems to keep.
##
## What counts as interactive is deliberately narrow: a [Button], or a [Control] that
## stops the mouse *and* has something connected to `gui_input`. The second clause is what
## keeps the sound off the panels -- a `PanelContainer` set to STOP purely so a click does
## not fall through to the world is not a control, and clicking one should be silent.
##
## Sounds are CC0 from Kenney's UI Audio pack; see `Game/Audio/CREDITS.txt`.

const CLICK := "res://Game/Audio/UI/click1.ogg"
const ROLLOVER := "res://Game/Audio/UI/rollover2.ogg"
## Kept for a toggle that wants to sound different from a press. Nothing uses it yet;
## it is here because picking the third sound was part of curating the pack, and finding
## it again later is the expensive half.
const SWITCH := "res://Game/Audio/UI/switch2.ogg"

## Well under the click's own length, so a drag across five roster chips is a texture
## rather than five separate ticks stacking into a rattle.
const ROLLOVER_GAP := 0.06

@export var click_db := -14.0
## Quieter than the click by a wide margin. A hover is feedback you should notice only
## when you are looking for it; at the click's level it becomes the loudest thing in the
## game, because the pointer crosses controls far more often than it presses them.
@export var rollover_db := -26.0

var _click: AudioStreamPlayer
var _rollover: AudioStreamPlayer
## Guards the rollover against a control that re-enters under a stationary pointer, which
## a rebuilt roster does every time the fleet changes.
var _last_rollover := -999.0
var _elapsed := 0.0


func _ready() -> void:
	AudioBuses.ensure()
	_click = _player(CLICK, click_db)
	_rollover = _player(ROLLOVER, rollover_db)
	get_tree().node_added.connect(_on_node_added)
	# Everything already in the tree when this node arrives -- the HUD builds its panels
	# before the watcher is ready, so without this pass the whole interface is silent.
	_scan(get_tree().root)


func _process(delta: float) -> void:
	_elapsed += delta


func _on_node_added(node: Node) -> void:
	_attach(node as Control)


func _scan(node: Node) -> void:
	_attach(node as Control)
	for child in node.get_children():
		_scan(child)


## Wires [param control] if it is something a player presses.
##
## Safe to call twice: the connection check makes a second pass a no-op, which matters
## because `_scan` and `node_added` overlap for anything added while the tree is loading.
func _attach(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return

	var button := control as Button
	if button != null:
		# **`button_down`, not `pressed`.** Godot's `pressed` is a button-*up* signal: it
		# fires when the mouse is released, so the click sound arrived at the end of the
		# gesture rather than the start and the interface sounded like it was lagging
		# behind the hand. Reported from play, and the fix was already written down three
		# lines below -- `_on_gui_input` takes the press "because that is when the thing it
		# does happens", and only the Button branch disagreed with it.
		#
		# The *action* stays on `pressed`, deliberately: releasing is when a button should
		# act, because it is what lets a player slide off a control to cancel. Feedback
		# leads the action by a few tens of milliseconds, which is the way round that reads
		# as responsive.
		if not button.button_down.is_connected(_play_click):
			button.button_down.connect(_play_click)
	elif control.mouse_filter == Control.MOUSE_FILTER_STOP \
			and control.gui_input.get_connections().size() > 0:
		if not control.gui_input.is_connected(_on_gui_input):
			control.gui_input.connect(_on_gui_input)
	else:
		return

	if not control.mouse_entered.is_connected(_play_rollover):
		control.mouse_entered.connect(_play_rollover)


## A non-Button control's press. Left button only, and on the press rather than the
## release, because that is when the thing it does happens.
func _on_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_play_click()


## **Guarded on being in the tree**, which is not paranoia: a scene change frees the HUD
## and this node with it, and a button's `pressed` can still arrive in the same frame from
## the card that ordered the change -- QUIT TO TITLE being the one that found it. Godot
## answers a `play()` on a detached player with "Playback can only happen when a node is
## inside the scene tree", which is an error in the console on an otherwise clean quit.
func _play_click() -> void:
	if _click and _click.is_inside_tree():
		_click.play()


func _play_rollover() -> void:
	if _rollover == null or not _rollover.is_inside_tree() \
			or _elapsed - _last_rollover < ROLLOVER_GAP:
		return
	_last_rollover = _elapsed
	_rollover.play()


## **Not cast to [AudioStreamWAV].** [Soundscape] does, because everything it plays is
## generated by `build_audio.gd` -- and that cast is why an OGG dropped into this project
## produces silence rather than an error. These are OGG, straight from the pack.
func _player(path: String, level: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = level
	player.bus = AudioBuses.UI
	# The interface is audible while the district is frozen: a pause menu whose buttons
	# went silent when they paused the game would read as broken.
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player
