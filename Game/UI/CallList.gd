extends VBoxContainer
class_name CallList

## The call board: what is outstanding, where, and how long it has been.
##
## A row per open call rather than per incident, which is the difference between one
## line reading "Fire, casualty reported -- 3rd & Oak" and eight lines reading "Fire".
##
## Clicking a row sends the camera to it. In a 130m district with buildings in the way,
## being able to jump to the job that needs attention is worth more than the list is.
##
## Rows are pooled rather than freed, for the same reason the roster pools its chips:
## `queue_free` lands at the end of the frame, so a rebuild that frees and adds at once
## briefly shows both sets.

## Beyond this the panel would run into the help card. A shift with nine simultaneous
## calls has bigger problems than a truncated list, but it says so rather than pretending.
const MAX_ROWS := 6

var controller: RTSController
var board: CallBoard: set = _set_board

var _rows: Array[PanelContainer] = []
var _overflow: Label


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	_overflow = Label.new()
	_overflow.theme_type_variation = &"HeaderLabel"
	_overflow.visible = false
	add_child(_overflow)


func _set_board(value: CallBoard) -> void:
	board = value


func _process(_delta: float) -> void:
	if board == null:
		return
	var open := board.open_calls()

	while _rows.size() < mini(open.size(), MAX_ROWS):
		_rows.append(_build_row())

	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < open.size()
		if row.visible:
			_fill(row, open[i])

	var hidden := open.size() - MAX_ROWS
	_overflow.visible = hidden > 0
	if hidden > 0:
		_overflow.text = "+%d more" % hidden
	# Keeps the overflow note below the rows however many are showing.
	move_child(_overflow, get_child_count() - 1)


# --- Rows --------------------------------------------------------------------

func _build_row() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"ListRow"
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	Hover.attach(pill)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(pill)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	# **The kind badge fills the frame's icon tab.** It is first in the row and 32
	# square because that is the size of the coloured square the art puts at x=1 --
	# anything else there leaves the tab empty, which is what the row looked like
	# before. The separate status dot went with this change: the tab's own colour now
	# says whether a job is waiting, overdue or being worked, and two things saying it
	# is one thing too many at this size.
	var mark := CallMark.new()
	mark.flat = true
	mark.custom_minimum_size = Vector2(32.0, 32.0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	_row_label(row, &"PillLabel", Palette.TEXT)
	_row_label(row, &"HeaderLabel", Palette.TEXT_DIM)

	# How far through the job the crews are. A bar, because the numbers behind it
	# were one percentage per incident and a spreading fire printed six of them.
	var bar := ProgressStrip.new()
	bar.custom_minimum_size = Vector2(54.0, 6.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	_row_label(row, &"HeaderLabel", Palette.TEXT_DIM)
	_row_label(row, &"HeaderLabel", Palette.TEXT_DIM)
	return pill


## The kit's four status dots, mapped onto the board's own statuses. Cached by the
## resource loader, so this is a dictionary lookup after the first row.
func _dot_for(call: Call) -> Texture2D:
	# **Three of the kit's four dots, because the board has three states.** There is no
	# EN_ROUTE on a call: the board knows waiting, on scene, and closed. The kit's fourth
	# dot goes unused rather than being wired to something it does not mean.
	var name := "offline"
	match call.status:
		Call.Status.ON_SCENE:
			name = "on_scene"
		Call.Status.WAITING:
			name = "en_route"
		_:
			name = "offline"
	var path := "res://Game/UI/Kit/frames/controls_status_dot_%s.svg" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _row_label(parent: Node, variation: StringName, colour: Color) -> void:
	var label := Label.new()
	label.theme_type_variation = variation
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _fill(row: PanelContainer, call: Call) -> void:
	var line := row.get_child(0)
	(line.get_child(0) as CallMark).call = call
	(line.get_child(1) as Label).text = call.title()
	(line.get_child(2) as Label).text = call.place
	var bar := line.get_child(3) as ProgressStrip
	bar.value = call.progress()
	# The same colour the badge beside it uses, so a row reads as one thing.
	bar.tint = CallMark.shades(call.kind)[0]
	(line.get_child(4) as Label).text = call.describe()

	# The age column doubles as the status: once a unit is at the scene the number
	# stops being a reproach and starts being how long they have been working.
	var attending := call.status == Call.Status.ON_SCENE
	var clock := line.get_child(5) as Label
	clock.text = ("%s attending" % call.age_text()) if attending else call.age_text()
	clock.add_theme_color_override("font_color",
		Palette.MEDICAL_DEEP if attending else Palette.CASUALTY_DEEP)
	# **Warning, then danger, then calm.** A waiting call was drawn as the kit's
	# *selected* row -- a dark blue plate that reads as "highlighted" to a designer and
	# as nothing much to a player glancing at it over a lit street. The notification
	# frames say the right thing instead: amber the moment a job is on the board, red
	# once it has been waiting longer than the response grace (the same ten seconds the
	# score docks you after), and the plain row once somebody is actually working it.
	# **One style, the kit's danger row.** Amber for a fresh call and red for an overdue
	# one was a nice idea and read as a mistake: the tab changed colour under a badge
	# that was drawing its own, so every row looked like two half-finished states. An
	# open call is a job nobody has done yet -- that is what this list is *for* -- so it
	# gets the one frame, and the plain row once a crew is actually on scene is the only
	# distinction the list needs to draw.
	row.theme_type_variation = &"ListRow" if attending else &"NotifyDanger"
	row.set_meta(&"call", call)

	if not row.gui_input.is_connected(_on_row_input):
		row.gui_input.connect(_on_row_input.bind(row))


func _on_row_input(event: InputEvent, row: PanelContainer) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT:
		return
	row.accept_event()
	var call := row.get_meta(&"call", null) as Call
	if call and is_instance_valid(call) and controller:
		controller.look_at_point(call.position)
