extends Control
class_name CallMark

## A call as a circular badge: a flame for a fire, a cross for a medical shout.
##
## The counterpart to [UnitBadge], drawn the same way for the same reason -- so the
## symbol on a call row is the symbol on the minimap. One shape, two sizes.

var call: Call: set = _set_call

var _drawn := -1


func _set_call(value: Call) -> void:
	call = value
	_drawn = -1
	queue_redraw()


func _process(_delta: float) -> void:
	var state := _state()
	if state != _drawn:
		_drawn = state
		queue_redraw()


func _state() -> int:
	if call == null or not is_instance_valid(call):
		return -1
	return call.kind * 8 + call.status


## Fill and symbol ink for a call, so a row, a map marker and anything later all agree
## about what colour a fire is.
static func shades(kind: Call.Kind) -> Array[Color]:
	match kind:
		Call.Kind.FIRE:
			return [Palette.FIRE_MARKER, Palette.FIRE_MARKER_DEEP]
		Call.Kind.RESCUE:
			return [Palette.FIRE, Palette.CARD]
		Call.Kind.CRIME:
			return [Palette.POLICE, Palette.CARD]
		_:
			return [Palette.CASUALTY_MARKER, Palette.CARD]


## A rescue is both at once, so it takes the flame -- the fire is what makes it the
## harder job, and it is what the player has to get to first.
static func symbol(kind: Call.Kind) -> StringName:
	match kind:
		Call.Kind.MEDICAL: return &"cross"
		Call.Kind.CRIME: return &"shield"
		_: return &"flame"


func _draw() -> void:
	if call == null or not is_instance_valid(call):
		return
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var tone := shades(call.kind)
	draw_circle(centre, radius, tone[0])
	Glyph.draw(self, symbol(call.kind), centre, radius * 0.56, tone[1], tone[0])
