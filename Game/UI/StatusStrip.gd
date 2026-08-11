extends HBoxContainer
class_name StatusStrip

## The shift clock and what is outstanding, as pills across the top of the screen.
##
## Small, and deliberately the only thing up there. It is what a player glances at
## between orders -- how long they have been at this, and how much is still burning --
## so it goes where the eye returns to rather than into a corner with the map.
##
## Builds its own children: three pills described in code read better than sixty lines
## of scene text setting anchors, and it keeps the layout beside the logic that fills it.

var mission: Mission: set = _set_mission
var board: CallBoard: set = _set_board
## Set during freeplay; the strip adds the score and how much of the shift is left.
var director: Director

var _clock: Label
var _score: PanelContainer
var _score_label: Label
var _outstanding: PanelContainer
var _outstanding_label: Label
var _saved: PanelContainer
var _saved_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	var clock_pill := _pill("PillPanel")
	_clock = _label(clock_pill, "ValueLabel")
	_clock.text = "00:00"

	_score = _pill("PillPanel")
	_score_label = _label(_score, "ValueLabel")

	_outstanding = _pill("AlarmPill")
	_outstanding_label = _label(_outstanding, "AlarmLabel")

	_saved = _pill("PillPanel")
	_saved_label = _label(_saved, "PillLabel")


func _set_mission(value: Mission) -> void:
	mission = value
	_refresh()


func _set_board(value: CallBoard) -> void:
	board = value
	_refresh()


func _pill(variation: StringName) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.theme_type_variation = variation
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(pill)
	return pill


func _label(parent: Node, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	if mission and mission.state == Mission.State.RUNNING:
		_refresh()


func _refresh() -> void:
	if _clock == null:
		return
	if mission:
		# During a shift the clock also says how long is left in it -- the number a
		# dispatcher watching the board actually plans around.
		if director and director.active:
			_clock.text = "%s   ·   %s left" % [
				mission.elapsed_text(), director.remaining_text()]
		else:
			_clock.text = mission.elapsed_text()

	_score.visible = mission != null and mission.scoring
	if _score.visible:
		_score_label.text = "SCORE %d" % mission.score

	# Calls, not incidents: the number a dispatcher cares about is how many jobs are
	# open and how many of them nobody has reached yet, not how many separate bodies
	# one spreading fire has turned into.
	var parts := PackedStringArray()
	if board:
		var open := board.open_calls().size()
		var waiting := board.waiting_count()
		if open > 0:
			parts.append("%d call%s" % [open, "" if open == 1 else "s"])
		if waiting > 0:
			parts.append("%d unattended" % waiting)
	_outstanding.visible = not parts.is_empty()
	_outstanding_label.text = "   ".join(parts)

	var done := PackedStringArray()
	if mission:
		if mission.casualties_saved > 0:
			done.append("%d delivered" % mission.casualties_saved)
		if mission.casualties_lost > 0:
			done.append("%d lost" % mission.casualties_lost)
	_saved.visible = not done.is_empty()
	_saved_label.text = "   ".join(done)
