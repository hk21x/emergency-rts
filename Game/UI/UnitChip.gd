extends VBoxContainer
class_name UnitChip

## One unit in the roster: a circular avatar over its callsign.
##
## Click selects it on its own, ctrl-click adds or drops it, double-click sends the
## camera after it. The point is being able to pull one ambulance out of a group of six
## without hunting for it in the street.

signal clicked(unit: Unit, additive: bool)
signal focused(unit: Unit)

@export var badge_size := 38.0

var unit: Unit: set = _set_unit

var _badge: UnitBadge
var _name: Label


func _ready() -> void:
	custom_minimum_size = Vector2(badge_size + 10.0, 0.0)
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Hover.attach(self)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_badge = UnitBadge.new()
	_badge.custom_minimum_size = Vector2(badge_size, badge_size)
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The chip handles the click, so nothing inside it may swallow one first.
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 10)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	_refresh()


func _set_unit(value: Unit) -> void:
	unit = value
	if is_node_ready():
		_refresh()


## [param lead] is the one the portrait is showing, which in a group of six is the one
## whose speed and orders are on screen.
func set_selected(selected: bool, lead: bool) -> void:
	if _badge == null:
		return
	_badge.highlighted = selected
	_name.add_theme_color_override("font_color",
		Palette.TEXT if selected or lead else Palette.TEXT_DIM)


func _refresh() -> void:
	_badge.unit = unit
	if unit == null:
		_name.text = ""
		tooltip_text = ""
		return
	_name.text = _short_name(unit.display_name)
	tooltip_text = "%s\nClick to select, Ctrl-click to add, double-click to follow" \
		% unit.display_name


## "Officer 3" -> "Off 3", "Ambulance 1" -> "Amb 1". The chip is 38px wide; a full name
## in it is a smear. Every unit the player commands is named "<type> <number>", so
## keeping three letters of the type and all of the number tells two patrol cars apart,
## which is the whole job.
func _short_name(full: String) -> String:
	var parts := full.split(" ", false)
	if parts.size() < 2:
		return full.left(7)
	return "%s %s" % [parts[0].left(3), parts[parts.size() - 1]]


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT or unit == null:
		return
	accept_event()
	if button.double_click:
		focused.emit(unit)
		return
	clicked.emit(unit, button.ctrl_pressed)
