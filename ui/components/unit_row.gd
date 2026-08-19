class_name UnitRow
extends Button
## One line in the unit sidebar. Click selects; double-click asks the game to
## put the camera on it.

signal selected(unit: UnitInstance)
signal focus_requested(unit: UnitInstance)

const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)
const ACCENT := Color(0.2902, 0.6118, 0.9412)

var unit: UnitInstance
var is_selected: bool = false

## How much of each edge of a portrait is transparent border, as a fraction. The vehicle
## sits in the middle; trimming this much off every side fills the tile with it.
const TRIM := 0.22

## Cropped copies, made once per texture rather than once per row: forty rows show maybe
## eight distinct vehicles between them.
static var _crops := {}

var _stripe: Panel
var _portrait: PanelContainer
var _glyph: TextureRect
var _bar_fill: Panel
## The condition bar's container, hidden outright for units that have no condition.
var _track: Control
var _callsign: Label
var _type: Label
var _dot: Panel
var _alert: TextureRect
var _status: Label
var _task: Label


## [param texture] with its transparent border trimmed away, or null.
static func _cropped(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	if _crops.has(texture):
		return _crops[texture]
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var size := texture.get_size()
	atlas.region = Rect2(size * TRIM, size * (1.0 - TRIM * 2.0))
	_crops[texture] = atlas
	return atlas


## Points an existing row at a different unit.
##
## **So the list can be reordered without destroying it.** Rebuilding used to free every
## row and build new ones; these are focusable [Button]s with input handlers, and freeing
## the one under the mouse -- or the one holding focus -- while the engine still refers to
## it is a hazard the renderer paid for. Reuse means the nodes outlive the shuffling.
func rebind(u: UnitInstance) -> void:
	unit = u
	# **The identity fields are written in `_build`, not `refresh`.** They never changed
	# while every rebuild made a new row, so `refresh` had no reason to touch them --
	# which meant a pooled row kept the callsign and type of whatever it held before and
	# every line in the roster read "P01". Anything a rebind can change belongs here.
	if _glyph:
		_glyph.texture = _cropped(u.def.icon if u.def else null)
	if _callsign:
		_callsign.text = u.callsign
	if _type:
		_type.text = u.def.display_name if u.def else ""
	refresh()


func setup(u: UnitInstance) -> void:
	unit = u
	# Sized around the portrait. The tile has been scaled up twice and then halved; the
	# text columns have kept the same width throughout, so every change has come out of
	# the picture and the row around it rather than out of the callsign and status.
	custom_minimum_size = Vector2(294, 62)
	focus_mode = Control.FOCUS_ALL
	text = ""
	_build()
	pressed.connect(func(): selected.emit(unit))
	gui_input.connect(_on_gui_input)
	refresh()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.double_click 			and event.button_index == MOUSE_BUTTON_LEFT:
		focus_requested.emit(unit)


func _flat(colour: Color, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(radius)
	return sb


func _build() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad, false, Node.INTERNAL_MODE_FRONT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	_stripe = Panel.new()
	# **Short and centred, not full-bleed.** A zero height makes it stretch to the row's
	# whole inner height, which sits proud of the rounded panel the row is drawn with and
	# reads as a line escaping its box.
	_stripe.custom_minimum_size = Vector2(4, 30)
	_stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_stripe)

	# portrait with a condition bar tucked underneath
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 3)
	pcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pcol)

	_portrait = PanelContainer.new()
	_portrait.theme_type_variation = &"ERSPortraitSmall"
	# **Bigger than the kit drew it**, because what sits in here is a rendered vehicle
	# rather than a line icon: a pickup and a patrol car at 32px are the same grey smudge,
	# and telling them apart at a glance is the entire job of a roster. The row is 62px
	# tall, so this fits with padding to spare.
	# **Sized to the space that actually exists.** The row is 62 tall with 10px of padding
	# top and bottom, so 42 is all there is -- and this column carries the tile plus a 3px
	# gap and the 5px condition track beneath it. At 58 the tile alone was 16px taller than
	# the row could hold, so it and the bar hung outside the panel.
	_portrait.custom_minimum_size = Vector2(46, 32)
	pcol.add_child(_portrait)

	# **Cropped at the source, not overdrawn and clipped.** The portraits carry a wide
	# transparent border -- a 192px PNG with the vehicle in roughly the middle half -- so
	# fitting one to the tile draws a small vehicle surrounded by nothing, and growing the
	# tile grows the border with it.
	#
	# The first cut solved that by oversizing the picture past a `clip_contents` frame. It
	# looked right, but it meant forty-odd clipped canvas items each drawing well outside
	# their own bounds, and the game then crashed inside the Metal renderer. **That crash
	# is not attributed** -- it could not be reproduced headlessly, since headless has no
	# Metal, and the obvious hypothesis (a panel rebuilding every frame) was measured and
	# disproved at one rebuild in a hundred and eighty. This is a mitigation kept because
	# it is the better construct regardless: an [AtlasTexture] hands the renderer only the
	# middle of the image, so an ordinary TextureRect at an ordinary size draws a
	# full-tile vehicle with nothing overdrawn and nothing clipped.
	_glyph = TextureRect.new()
	_glyph.texture = _cropped(unit.def.icon if unit.def else null)
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# **The fourth place this bites.** A [TextureRect]'s minimum size is its *texture's*
	# size unless told otherwise, and this game hands the kit 192x192 rendered portraits
	# where it was drawn against 24x24 icons -- so each row blew out to a picture the size
	# of a card with its text pushed off the side. [UnitCard] and `OrderRow` had the same
	# line and were fixed one screenshot at a time; this one was missed because the roster
	# had not been swapped in yet when the other two were found.
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# **Sized against the drawn vehicle, not the file.** The rendered portraits carry a
	# wide transparent margin -- a 192px PNG with a car occupying about half of it -- so a
	# 52px TextureRect draws a 25px car, which is the same grey smudge whatever it is. The
	# tile grows with it; identifying the unit at a glance is what a roster is for.
	_glyph.custom_minimum_size = Vector2(42, 28)
	_portrait.add_child(_glyph)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(40, 5)
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078)))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcol.add_child(track)

	_bar_fill = Panel.new()
	_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar_fill)
	_track = track

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	_callsign = Label.new()
	_callsign.text = unit.callsign
	_callsign.theme_type_variation = &"ERSTitle"
	_callsign.add_theme_font_size_override("font_size", 16)
	mid.add_child(_callsign)

	_type = Label.new()
	_type.text = unit.def.display_name if unit.def else ""
	_type.theme_type_variation = &"ERSBody"
	_type.add_theme_font_size_override("font_size", 11)
	_type.clip_text = true
	mid.add_child(_type)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 3)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_END
	srow.add_theme_constant_override("separation", 6)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(srow)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(7, 7)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(_dot)

	_alert = TextureRect.new()
	_alert.texture = load("res://ui/art/icons/icon_alert.svg")
	_alert.custom_minimum_size = Vector2(13, 13)
	_alert.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_alert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_alert.visible = false
	srow.add_child(_alert)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	srow.add_child(_status)

	_task = Label.new()
	_task.theme_type_variation = &"ERSBody"
	_task.add_theme_font_size_override("font_size", 11)
	_task.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_task)


func refresh() -> void:
	var col := unit.status_color()
	var attention := unit.needs_attention()
	var dead := unit.status == UnitInstance.Status.OFF_RUN

	if is_selected:
		theme_type_variation = &"ERSUnitRowSelected"
	elif attention:
		theme_type_variation = &"ERSUnitRowAlert"
	elif dead:
		theme_type_variation = &"ERSUnitRowOffline"
	else:
		theme_type_variation = &"ERSUnitRow"

	_stripe.add_theme_stylebox_override("panel", _flat(col))
	_portrait.theme_type_variation = (&"ERSPortraitSmallSelected" if is_selected
			else &"ERSPortraitSmall")
	_glyph.modulate = ACCENT if is_selected else (OFF if dead else DIM)

	var bar := (Color("4caf50") if unit.condition >= 0.6
			else Color("d8aa33") if unit.condition >= 0.35 else Color("c4442f"))
	_bar_fill.add_theme_stylebox_override("panel", _flat(bar))
	_bar_fill.anchor_right = clampf(unit.condition, 0.0, 1.0)
	# **A negative condition means "this unit has no condition", and the bar goes away.**
	# `health` is a [Person] field; a vehicle's damage is a repair bill in pounds, settled
	# when it books in. A full green bar under a patrol car would be a readout with nothing
	# behind it, which is precisely what the roster this replaced was careful not to draw.
	if _track:
		# Shown only when there is something to say: a negative condition means the unit
		# has none (a vehicle's damage is a repair bill), and a full one means nothing is
		# wrong. A bar that is always there, always full, is furniture -- the roster this
		# replaced hid it in both cases and the checks pin both.
		_track.visible = unit.condition >= 0.0 and unit.condition < 1.0

	_callsign.add_theme_color_override("font_color", OFF if dead and not attention else TEXT)
	_type.add_theme_color_override("font_color", OFF if dead else DIM)
	_dot.add_theme_stylebox_override("panel", _flat(col, 4))
	_dot.visible = not attention
	_alert.visible = attention
	_alert.modulate = col
	_status.text = unit.status_label()
	_status.add_theme_color_override("font_color", col)
	_task.text = unit.task
	tooltip_text = "%s — %s\nCondition %d%%" % [unit.callsign,
			unit.def.display_name if unit.def else "", roundi(unit.condition * 100)]


func set_selected(v: bool) -> void:
	is_selected = v
	refresh()
