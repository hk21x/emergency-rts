extends Control
class_name HealthBar

## A thin bar under a roster chip, shown only while its unit is hurt.
##
## **Only people have health.** `health` lives on [Person], not on [Unit] -- a vehicle's
## damage is a `repair_bill` in pounds, settled when it books in, and drawing a bar for it
## would be a readout that means nothing. So a vehicle's chip never shows one.
##
## **And only while it means something.** A full bar under every chip is a row of green
## noise that teaches the eye to skip the place the warning will appear. It hides itself at
## full health, the same rule the top bar's stat blocks follow -- a block with nothing to
## say is not shown.
##
## Worth having only since August 2026, and that is the honest test of it: before fire
## harmed units, `health` moved only when a gas cylinder went off, and a bar would have sat
## at 100% for entire careers. Now a crew member walked into a fire drains visibly, and the
## player can pull them out -- which is the whole reason to draw it.

## Below this the bar turns; above it the unit is merely scratched.
const HURT := 0.6
const CRITICAL := 0.3

var unit: Person: set = _set_unit

var _drawn := -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 3.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _set_unit(value: Person) -> void:
	unit = value
	_drawn = -1.0
	_refresh()


## Polled rather than driven by `took_harm`: the signal fires on damage but nothing emits
## when a unit is replaced in a pooled chip, and a bar left showing the last occupant's
## wound is worse than one a frame late.
func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var health := _health()
	if is_equal_approx(health, _drawn):
		return
	_drawn = health
	visible = health < 1.0
	if visible:
		queue_redraw()


func _health() -> float:
	if unit == null or not is_instance_valid(unit):
		return 1.0
	# A unit that has gone down reads as empty rather than as whatever it stopped at, so
	# the chip says "lost" rather than "nearly".
	return 0.0 if unit.is_down else clampf(unit.health, 0.0, 1.0)


func _draw() -> void:
	var health := _drawn
	draw_rect(Rect2(Vector2.ZERO, size), Palette.WELL, true)
	if health <= 0.0:
		return
	var ink := Palette.GOOD
	if health < CRITICAL:
		ink = Palette.BAD
	elif health < HURT:
		ink = Palette.WARN
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * health, size.y)), ink, true)
