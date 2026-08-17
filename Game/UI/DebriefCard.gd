extends Control
class_name DebriefCard

## The end-of-shift card: what the last five to fifteen minutes came to, as a table.
##
## The debrief used to be [method Mission.summary] -- one run-on line of eight facts
## joined by interpuncts, in the same label the "press F2" hint uses. That line is a
## perfectly good *sentence*, and it is still what a scripted shout's banner shows and
## what the tests read. It is the wrong shape for the end of a shift: a player who has
## just worked one will read a table and will not read a paragraph.
##
## Built in code rather than authored into `HUD.tscn`, the same choice [StatusStrip] and
## the menu's cards make: the rows come from the mission and their number varies with
## what the shift actually did, so scene text would only be describing a layout that has
## to be rebuilt anyway.

## Rows whose `muted` flag is set are drawn faint. They are the ones only worth reading
## when they are not zero -- a clean shift should not announce the nothing it lost.
const MUTED_ALPHA := 0.45

var _body: VBoxContainer


func _ready() -> void:
	# The card never takes the mouse. It sits over the district and there is nothing on
	# it to click; the player dismisses it by starting another shift.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	panel.add_child(_body)


## Fills the card from a finished shift and shows it.
func show_shift(mission: Mission) -> void:
	if mission == null:
		return
	_fill("SHIFT COMPLETE", mission.debrief_rows(), false)


## The end of a scripted shout, as a modal.
##
## A shift's card is a readout the player leaves behind by pressing F2; a shout's is
## the end of the thing they were doing, so it takes the mouse and waits to be
## dismissed. That difference is the whole reason for the [param modal] flag: a card
## that swallowed clicks during freeplay would leave the district uncommandable until
## the next shift opened.
func show_shout(mission: Mission) -> void:
	if mission == null:
		return
	_fill("SHOUT COMPLETE", mission.shout_rows(), true)


func hide_card() -> void:
	visible = false
	# Handed straight back. A modal that stayed modal after it was dismissed would take
	# every click on the district with it, and nothing about the card would look wrong.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fill(heading_text: String, rows: Array[Dictionary], modal: bool) -> void:
	if _body == null:
		return
	# Removed as well as freed. queue_free() alone does not take effect until the end of
	# the frame, so a card shown twice in one frame -- which is exactly what happens when
	# the shift ends and anything else asks it to redraw -- would stack the old rows
	# under the new ones and still be carrying them when counted.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	var heading := Label.new()
	heading.text = heading_text
	heading.theme_type_variation = &"BannerLabel"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(heading)

	for row in rows:
		_body.add_child(_row(row))

	if modal:
		# Its own line, kept clear of the last row so the card does not read as though
		# the button were another figure in the table.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 10.0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(spacer)

		var dismiss := Button.new()
		dismiss.name = "Dismiss"
		dismiss.theme_type_variation = &"PrimaryButton"
		dismiss.text = "CONTINUE"
		dismiss.pressed.connect(hide_card)
		_body.add_child(dismiss)

	# STOP rather than IGNORE: a modal has to eat the click that lands on it, or the
	# player selects and orders units through the card. Children are hit-tested either
	# way, so the CONTINUE button still answers.
	mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	visible = true


## One label/value line, with the optional note trailing the value.
func _row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 18)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = str(row["label"])
	label.theme_type_variation = &"DimLabel"
	# The label side expands and the value side does not, which is what puts every
	# value on the same right edge however long the labels are.
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)

	var value := Label.new()
	var note := str(row.get("note", ""))
	value.text = str(row["value"]) if note == "" \
		else "%s   (%s)" % [str(row["value"]), note]
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)

	if bool(row.get("muted", false)):
		line.modulate.a = MUTED_ALPHA
	return line
