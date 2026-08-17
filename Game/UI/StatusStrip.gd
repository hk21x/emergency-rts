extends PanelContainer
class_name StatusStrip

## The top bar: what the shift is doing, in one framed strip across the top.
##
## Small, and deliberately the only thing up there. It is what a player glances at
## between orders -- how long they have been at this, and how much is still burning --
## so it goes where the eye returns to rather than into a corner with the map.
##
## **A PanelContainer that builds an HBox, not an HBox.** The node keeps its name and
## its place in `HUD.tscn` because half a dozen things reach it by path; what changed is
## what it *is*. That is also why the kit's top bar could be adopted at all -- wrapping
## the strip in a new frame node would have moved `Root/World/StatusStrip` and taken
## those references with it.
##
## The layout is the UI kit's, read off the reference: a label on the left saying what
## the shift is, then stat blocks to the right, each a small dim caption over a bright
## value. Stat blocks rather than pills because a pill is a *badge* -- fine for one
## number that comes and goes, wrong for a row of readings the eye compares.
##
## Builds its own children: a dozen blocks described in code read better than a hundred
## lines of scene text setting anchors, and it keeps the layout beside the logic that
## fills it.

## The blocks, in the order they sit. `id` is what `_refresh` looks them up by.
##
## **Score is not here.** It moved to [ScoreStrip] in the top-right corner when that
## panel arrived: the reference puts the running total opposite the clock, and a number
## that appears in two strips at once invites the two to disagree.
const BLOCKS := [
	{"id": &"time", "caption": "TIME"},
	{"id": &"calls", "caption": "CALLS"},
	{"id": &"saved", "caption": "SAVED"},
]

var mission: Mission: set = _set_mission
var board: CallBoard: set = _set_board
## Set during freeplay; the strip adds the score and how much of the shift is left.
var director: Director

## `id -> {"block": PanelContainer, "value": Label}`.
var _blocks := {}
var _headline: Label


func _ready() -> void:
	theme_type_variation = &"TopBarPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# The left-hand line. In the reference this is the mission objective; here it is
	# what the district is doing, which is the same question asked of a game that has
	# no objectives -- idle, on a shift, or working a designed scenario.
	_headline = Label.new()
	_headline.theme_type_variation = &"PillLabel"
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_headline)

	for spec: Dictionary in BLOCKS:
		var made := stat_block(str(spec["caption"]))
		row.add_child(made["block"])
		_blocks[spec["id"]] = made
	_refresh()


## One reading: a dim caption beside a bright value, on the kit's inset plate.
##
## Static, and shared with [ScoreStrip], because two strips drawing the same kind of
## block from two copies of this code is how they drift apart -- one gains a separation
## constant, the other does not, and the top of the screen stops looking like one row.
## Returns `{"block": PanelContainer, "value": Label}`; the caller parents the block and
## keeps the label to write to.
##
## **Caption beside the value, not above it.** Stacked, each block was two lines of type
## and the strip was 116px of a 900px screen -- most of the room above the city, for four
## short numbers. On one line the whole bar is a single row of text and the district
## keeps its sky.
static func stat_block(caption_text: String) -> Dictionary:
	var block := PanelContainer.new()
	block.theme_type_variation = &"InsetPanel"
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var stack := HBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(stack)

	var caption := Label.new()
	caption.theme_type_variation = &"HeaderLabel"
	caption.text = caption_text
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(caption)

	var value := Label.new()
	value.theme_type_variation = &"PillLabel"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(value)

	return {"block": block, "value": value}


func _set_mission(value: Mission) -> void:
	mission = value
	_refresh()


func _set_board(value: CallBoard) -> void:
	board = value
	_refresh()


func _process(_delta: float) -> void:
	if mission and mission.state == Mission.State.RUNNING:
		_refresh()


func _refresh() -> void:
	if _blocks.is_empty():
		return

	# The clock is the one block that is always up: a shift with nothing on it still
	# has a duration, and a bar whose first block came and went would jump.
	_show(&"time", true, mission.elapsed_text() if mission else "00:00")

	# Calls, not incidents: the number a dispatcher cares about is how many jobs are
	# open and how many of them nobody has reached yet, not how many separate bodies
	# one spreading fire has turned into.
	var open := board.open_calls().size() if board else 0
	var waiting := board.waiting_count() if board else 0
	_show(&"calls", open > 0,
		"%d" % open if waiting <= 0 else "%d / %d" % [open - waiting, open])

	var saved: int = mission.casualties_saved if mission else 0
	var lost: int = mission.casualties_lost if mission else 0
	_show(&"saved", saved > 0 or lost > 0,
		str(saved) if lost <= 0 else "%d  -%d" % [saved, lost])

	_headline.text = _what_is_happening()


## The left-hand line: what the district is doing right now, in the plainest words that
## are true. Not an objective -- freeplay has none -- but the same slot in the bar.
func _what_is_happening() -> String:
	if mission == null:
		return ""
	match mission.state:
		Mission.State.WON:
			return "Shout complete"
		Mission.State.LOST:
			return "Casualty lost"
		Mission.State.OVER:
			return "Shift over"
	if director and director.active:
		return "Shift running   ·   %s left" % director.remaining_text()
	if mission.par_seconds > 0.0:
		return "Scenario running"
	if board and not board.open_calls().is_empty():
		return "Calls on the board"
	return "District quiet   ·   F2 opens a shift"


func _show(id: StringName, visible_now: bool, text: String) -> void:
	var entry: Dictionary = _blocks.get(id, {})
	if entry.is_empty():
		return
	(entry["block"] as Control).visible = visible_now
	(entry["value"] as Label).text = text
