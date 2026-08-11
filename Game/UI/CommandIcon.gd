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

## Fraction of the tile the symbol occupies, leaving room for the hotkey letter.
const GLYPH_RATIO := 0.28
const CORNER := 8.0

var ability: Ability
## Filled while this ability is waiting for a target click.
var armed := false: set = _set_armed
## Filled while a toggle -- Lights, Siren -- is switched on for the selection. Blue,
## against the green of armed, so "waiting for a click" and "currently running" cannot
## be mistaken for one another.
var active := false: set = _set_active

var _hovered := false


func _ready() -> void:
	custom_minimum_size = Vector2(54.0, 54.0)
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
	_rounded(fill)

	# Light ink on the filled states, dark ink on the recessed one.
	var ink := Palette.CARD if armed or active else Palette.TEXT
	Glyph.draw(self, ability.icon(), size * Vector2(0.5, 0.44),
		minf(size.x, size.y) * GLYPH_RATIO, ink, fill)

	if ability.hotkey() == KEY_NONE:
		return
	var font := get_theme_default_font()
	var key := OS.get_keycode_string(ability.hotkey())
	var width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(size.x - width - 6.0, size.y - 6.0), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Palette.dim(ink, 0.75 if armed or active else 0.55))


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
