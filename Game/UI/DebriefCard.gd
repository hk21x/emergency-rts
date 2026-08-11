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
	if mission == null or _body == null:
		return
	# Removed as well as freed. queue_free() alone does not take effect until the end of
	# the frame, so a card shown twice in one frame -- which is exactly what happens when
	# the shift ends and anything else asks it to redraw -- would stack the old rows
	# under the new ones and still be carrying them when counted.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	var heading := Label.new()
	heading.text = "SHIFT COMPLETE"
	heading.theme_type_variation = &"BannerLabel"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(heading)

	for row in mission.debrief_rows():
		_body.add_child(_row(row))
	visible = true


func hide_card() -> void:
	visible = false


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
