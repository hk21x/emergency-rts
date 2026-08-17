extends VBoxContainer
class_name ControlsPanel

## The controls card, with the keyboard drawn as keys and the bindings grouped by
## what they are *for* -- selecting, ordering, driving the camera -- rather than
## listed in the order they were implemented.
##
## Keycap textures come from `Game/UI/Keys/` (the pack's dark set). Letters and
## digits have their own caps; anything the pack does not letter -- Ctrl, Esc, F1,
## the mouse buttons -- is drawn as a matching dark chip with its own small label,
## so the card reads as one keyboard rather than two styles.
##
## Built in code, like the status strip: a dozen rows described in a table read
## better than two hundred lines of scene text setting anchors. The card itself is
## hidden by default and opened from the CONTROLS chip beside it (or F1).

const KEYS_DIR := "res://Game/UI/Keys/"
const CHIP_HEIGHT := 20.0
const CHIP_COLOUR := Color(0.13, 0.13, 0.14)

## Sections by function. Each row is a list of parts: `k` a keycap texture, `c` a
## labelled chip, `t` running text, `s` a small spacer.
const SECTIONS := [
	{"title": "SELECT", "rows": [
		[{"c": "L-CLICK"}, {"t": "select"}, {"c": "DRAG"}, {"t": "box-select"},
			{"c": "SHIFT"}, {"t": "add"}],
	]},
	{"title": "ORDER", "rows": [
		[{"c": "R-CLICK"}, {"t": "order"}, {"c": "SHIFT"}, {"t": "queue it"},
			{"s": true}, {"c": "ESC"}, {"t": "cancel"}],
		[{"k": "Z"}, {"k": "X"}, {"k": "C"}, {"k": "V"}, {"k": "B"}, {"k": "N"},
			{"k": "M"}, {"k": "G"}, {"k": "H"}, {"k": "J"}, {"k": "K"},
			{"t": "the command tiles"}],
		[{"c": "CTRL"}, {"t": "+"}, {"k": "1"}, {"t": "…"}, {"k": "9"},
			{"t": "assign a group · press alone to recall"}],
	]},
	{"title": "CAMERA", "rows": [
		[{"k": "W"}, {"k": "A"}, {"k": "S"}, {"k": "D"}, {"t": "pan"},
			{"c": "SHIFT"}, {"t": "faster"}, {"s": true},
			{"k": "Q"}, {"k": "E"}, {"t": "rotate"}],
		[{"c": "WHEEL"}, {"t": "zoom"}, {"c": "MID-DRAG"}, {"t": "pan"},
			{"s": true}, {"k": "F"}, {"t": "follow the selection"}],
	]},
	{"title": "MINIMAP", "rows": [
		[{"c": "L-CLICK"}, {"t": "look there"}, {"c": "R-CLICK"},
			{"t": "send the selection there"}],
	]},
	{"title": "SHIFT", "rows": [
		[{"c": "F2"}, {"t": "start a freeplay shift"}, {"s": true},
			{"c": "ESC"}, {"t": "pause"}, {"s": true},
			{"k": "R"}, {"t": "respawn"}],
		[{"c": "F3"}, {"t": "report a unit that is stuck"}, {"s": true},
			{"c": "F4"}, {"t": "show what a unit is steering at"}],
	]},
]


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for section in SECTIONS:
		var title := Label.new()
		title.theme_type_variation = &"HeaderLabel"
		title.text = str(section["title"])
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title)
		for row in section["rows"]:
			add_child(_build_row(row))


func _build_row(parts: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in parts:
		var piece: Dictionary = part
		if piece.has("k"):
			row.add_child(_keycap(str(piece["k"])))
		elif piece.has("c"):
			row.add_child(_chip(str(piece["c"])))
		elif piece.has("t"):
			row.add_child(_text(str(piece["t"])))
		elif piece.has("s"):
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10.0, 0.0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
	return row


## A keycap from the pack. "Shift" and friends are wider caps; keep-aspect handles it.
func _keycap(key: String) -> TextureRect:
	var cap := TextureRect.new()
	var path := "%s%s-Key.png" % [KEYS_DIR, key]
	if ResourceLoader.exists(path):
		cap.texture = load(path)
	cap.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	cap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cap.custom_minimum_size = Vector2(CHIP_HEIGHT, CHIP_HEIGHT)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap


## A key the pack does not letter, drawn to match it: same dark cap, same radius,
## its own small label.
func _chip(caption: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_COLOUR
	style.set_corner_radius_all(4)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Palette.CARD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


func _text(caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override("font_size", 12)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
