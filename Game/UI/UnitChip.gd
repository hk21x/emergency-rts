extends PanelContainer
class_name UnitChip

## One unit in the roster: a circular avatar over its callsign, on a tile.
##
## Click selects it on its own, ctrl-click adds or drops it, double-click sends the
## camera after it. The point is being able to pull one ambulance out of a group of six
## without hunting for it in the street.
##
## **A PanelContainer since the UI kit arrived**, where it used to be a bare VBox over
## whatever was behind it. The kit ships `hud_unit_portrait` and a lit
## `hud_unit_portrait_selected` at 48x56 -- a portrait-aspect well that is almost
## exactly a 38px badge and its callsign -- so selection is now a *frame* rather than a
## ring drawn round the avatar. The ring stays as well: the frame says which tile, the
## ring survives the tile being read at a glance in a column of eight.

signal clicked(unit: Unit, additive: bool)
signal focused(unit: Unit)
## A standby chip was pressed: send one of this type out of the house.
signal dispatch_requested(id: StringName)

@export var badge_size := 38.0

var unit: Unit: set = _set_unit

## A [constant Station.TYPES] entry when this chip stands for a unit **in the house**
## rather than one on the map, or `{}` when it does not.
##
## The roster's own description has always been "pale avatars are standing by, solid ones
## are working" -- but a unit sitting in the station is not in the scene tree, so for most
## of this project's life the pale half of that sentence could only ever mean "on the map
## with nothing to do". These chips are the other half, and clicking one sends it out.
var standby := {}: set = _set_standby

var _badge: UnitBadge
## Drawn instead of the badge for a standby chip: there is nothing on the map to
## photograph until somebody presses it, which is exactly what [ServiceMark] is for.
var _mark: ServiceMark
var _name: Label
var _stack: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(badge_size + 10.0, 0.0)
	theme_type_variation = &"UnitTile"
	mouse_filter = Control.MOUSE_FILTER_STOP
	Hover.attach(self)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# The tile is the frame; the stack is what used to be this node.
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 3)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

	_badge = UnitBadge.new()
	_badge.custom_minimum_size = Vector2(badge_size, badge_size)
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The chip handles the click, so nothing inside it may swallow one first.
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(_badge)

	_mark = ServiceMark.new()
	_mark.custom_minimum_size = Vector2(badge_size, badge_size)
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	_stack.add_child(_mark)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 10)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(_name)

	_refresh()


func _set_unit(value: Unit) -> void:
	unit = value
	if is_node_ready():
		_refresh()


func _set_standby(value: Dictionary) -> void:
	standby = value
	if is_node_ready():
		_refresh()


## [param lead] is the one the portrait is showing, which in a group of six is the one
## whose speed and orders are on screen.
func set_selected(selected: bool, lead: bool) -> void:
	if _badge == null:
		return
	_badge.highlighted = selected
	theme_type_variation = &"UnitTileSelected" if selected else &"UnitTile"
	_name.add_theme_color_override("font_color",
		Palette.TEXT if selected or lead else Palette.TEXT_DIM)


func _refresh() -> void:
	_badge.unit = unit
	_badge.visible = unit != null
	_mark.visible = unit == null and not standby.is_empty()
	theme_type_variation = &"UnitTile"

	if unit != null:
		_name.text = _short_name(unit.display_name)
		_name.add_theme_color_override("font_color", Palette.TEXT_DIM)
		tooltip_text = "%s\nClick to select, Ctrl-click to add, double-click to follow" \
			% unit.display_name
		return

	if standby.is_empty():
		_name.text = ""
		tooltip_text = ""
		return

	_mark.service = int(standby["service"])
	_mark.symbol = &"car" if standby["vehicle"] else &"person"
	_name.text = str(standby["label"]).left(3)
	# Dimmer than a unit that is out: the whole point of the chip is that this one is
	# still in the station.
	_name.add_theme_color_override("font_color", Palette.dim(Palette.TEXT_DIM, 0.8))
	tooltip_text = "%s in the station\nClick to send one out" % standby["label"]


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
			or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if unit == null:
		if not standby.is_empty():
			accept_event()
			dispatch_requested.emit(standby["id"])
		return
	accept_event()
	if button.double_click:
		focused.emit(unit)
		return
	clicked.emit(unit, button.ctrl_pressed)
