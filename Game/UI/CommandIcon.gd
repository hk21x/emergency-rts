extends Control
class_name CommandIcon

## One tile in the command grid: an ability's symbol, its hotkey, and its armed state.
##
## Drawn rather than textured. Neither Synty pack ships a single interface icon, and a
## row of buttons reading "Ext" / "Brd" / "Unl" is not a command bar -- it is a list of
## abbreviations. The symbols themselves live in [Glyph], shared with the unit avatars.
##
## A plain Control rather than a Button so the drawing order is unambiguous: a Button
## renders its own StyleBox from the engine side, and layering a script's `_draw` over
## that is a coin toss. Here every pixel is this file's.

signal pressed(ability: Ability)

## Fraction of the tile the symbol occupies, leaving room for the hotkey letter and the
## name beneath it.
const GLYPH_RATIO := 0.24
const CORNER := 8.0
## Point size of the verb's name along the bottom of the tile.
##
## The tile carried a symbol and a hotkey letter and nothing else, which asks the player
## to already know what a droplet means. The reference the restyle follows labels every
## tile -- MOVE, STOP, SPRAY -- and naming the verb is the cheapest teaching this
## interface has, since the alternative is hovering each one for a tooltip.
##
## Dropped 9 → 8 when the tile came down to 48px. The longest verb, EXTINGUISH, is the
## one that sets this: at 9pt it measures wider than a 48px tile and spilled into its
## neighbours, and the label is centred, so it spilled both ways.
const LABEL_SIZE := 8

var ability: Ability
## Filled while this ability is waiting for a target click.
var armed := false: set = _set_armed
## Filled while a toggle -- Lights, Siren -- is switched on for the selection. Blue,
## against the green of armed, so "waiting for a click" and "currently running" cannot
## be mistaken for one another.
var active := false: set = _set_active

var _hovered := false


func _ready() -> void:
	# 48, down from 54 (August 2026, at the user's ask for a slimmer command block). The
	# art is 38px nine-sliced at 8, so it carries any size above 16 without the corners
	# going oval; what actually bounds this from below is the verb label, not the plate.
	custom_minimum_size = Vector2(48.0, 48.0)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


## Fills in the tile. Kept separate from the constructor so the grid can pool tiles.
func setup(value: Ability) -> void:
	ability = value
	var key := OS.get_keycode_string(value.hotkey()) if value.hotkey() != KEY_NONE else ""
	tooltip_text = value.label() if key.is_empty() else "%s   (%s)" % [value.label(), key]
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if ability:
			pressed.emit(ability)


func _set_armed(value: bool) -> void:
	if armed == value:
		return
	armed = value
	queue_redraw()


func _set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	queue_redraw()


func _on_hover(inside: bool) -> void:
	_hovered = inside
	queue_redraw()


## The kit plate for this tile's state, or null if the theme has none.
func _plate() -> StyleBox:
	var variation := &"CommandPlateDefault"
	if armed or active:
		variation = &"CommandPlatePressed"
	elif _hovered:
		variation = &"CommandPlateHover"
	return get_theme_stylebox(&"panel", variation)


func _draw() -> void:
	if ability == null:
		return

	var fill := Palette.WELL
	if armed:
		fill = Palette.MEDICAL
	elif active:
		fill = Palette.POLICE
	elif _hovered:
		fill = Palette.HOVER

	# **The kit's plate, drawn as a stylebox.** `draw_style_box` is the one drawing call
	# that understands nine-slicing, which is what lets 38px art carry a 54px tile
	# without the corners going oval -- `draw_texture_rect` would stretch the lot.
	# Falls back to the hand-rolled rounded rect if the variation is missing, the same
	# rule the glyph pack follows: a missing asset costs the look, not the tile.
	var plate := _plate()
	if plate:
		draw_style_box(plate, Rect2(Vector2.ZERO, size))
		# The state colour goes on *over* the plate, washed rather than solid. The kit
		# has three states; this game has four meanings (rest, hovered, armed, running)
		# and the two extra are colour-coded -- medical green for an armed verb, police
		# blue for a toggle that is on. Losing that to match the art would be trading a
		# fact the player needs for a texture.
		if armed or active:
			_rounded(Color(fill, 0.72))
	else:
		_rounded(fill)

	# Ink that reads on whichever fill won. On the recessed tile that is the ordinary
	# text colour; on a filled one it is the card colour, which since the restyle is the
	# dark slate rather than white.
	var ink := Palette.CARD if armed or active else Palette.TEXT
	Glyph.draw(self, ability.icon(), size * Vector2(0.5, 0.38),
		minf(size.x, size.y) * GLYPH_RATIO, ink, fill)

	var font := get_theme_default_font()
	# The verb, along the bottom. Uppercased because at nine points a mixed-case word is
	# a smudge, and centred so a four-letter verb and an eleven-letter one both sit right.
	var name := ability.label().to_upper()
	var name_width := font.get_string_size(
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	draw_string(font, Vector2((size.x - name_width) * 0.5, size.y - 7.0), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
		Palette.dim(ink, 0.9 if armed or active else 0.7))

	if ability.hotkey() == KEY_NONE:
		return
	var key := OS.get_keycode_string(ability.hotkey())
	draw_string(font, Vector2(5.0, 13.0), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Palette.dim(ink, 0.75 if armed or active else 0.5))


## Rounds the corners by filling four quarter-circles and the two spanning rectangles.
## `draw_rect` has no radius, and a StyleBox would need a Button underneath -- which is
## exactly the drawing-order coin toss this control exists to avoid.
func _rounded(fill: Color) -> void:
	var r := minf(CORNER, minf(size.x, size.y) * 0.5)
	draw_rect(Rect2(Vector2(r, 0.0), Vector2(size.x - r * 2.0, size.y)), fill, true)
	draw_rect(Rect2(Vector2(0.0, r), Vector2(size.x, size.y - r * 2.0)), fill, true)
	for corner in [Vector2(r, r), Vector2(size.x - r, r),
			Vector2(r, size.y - r), Vector2(size.x - r, size.y - r)]:
		draw_circle(corner, r, fill)
