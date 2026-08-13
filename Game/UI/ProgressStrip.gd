extends Control
class_name ProgressStrip

## A job's progress as a bar: a dim track with a filled portion in the call's own
## colour.
##
## It replaced a row of percentages. A fire that has spread six times used to print
## six numbers side by side -- honest, but data rather than a readout, and the eye
## cannot rank two calls by reading twelve digits. A bar is read at a glance and
## says the one thing the player wants between orders: how close is this to done.
##
## Drawn rather than themed, like [Glyph] and [CallMark], because it is two
## rectangles and a ProgressBar's stylebox chrome would have to be undone first.

## The unfilled part of the bar. Sourced from the table rather than written here: as a
## 13% white it was drawn onto a white card and was therefore **invisible** -- every call
## row has been showing its fill against nothing.
const TRACK := Palette.WELL
## Never draws as completely empty: a sliver says "this bar is a bar" rather than
## leaving the row looking like it failed to render.
const MIN_FILL := 0.06

var value := 0.0: set = _set_value
var tint: Color = Color.WHITE: set = _set_tint


func _set_value(next: float) -> void:
	next = clampf(next, 0.0, 1.0)
	# Redrawn only when it actually moves -- this sits in a list that refreshes
	# every frame.
	if is_equal_approx(next, value):
		return
	value = next
	queue_redraw()


func _set_tint(next: Color) -> void:
	if next == tint:
		return
	tint = next
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TRACK)
	var filled := maxf(size.x * value, size.x * MIN_FILL)
	draw_rect(Rect2(Vector2.ZERO, Vector2(filled, size.y)), tint)
