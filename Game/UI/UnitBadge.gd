extends Control
class_name UnitBadge

## A unit as a circular avatar: service colour behind a photograph of the unit itself.
##
## The picture is a real render of the same prefab that is driving around the map, shot
## by `build_portraits.gd` -- every vehicle from one camera angle under one light, at
## one shared scale, so the ambulance is visibly the big one and a patrol car is a
## patrol car. A drawn outline told a car from a person and nothing more.
##
## A unit with no portrait falls back to the drawn symbol [method Unit.icon] names, so
## anything that has not been through the generator still appears.
##
## Used at three sizes -- large in the portrait, medium in the roster, small on a pill --
## so it is one script rather than three that have to agree.
##
## The fill carries the unit's state, which is most of what the roster is for. A unit
## standing by is pale; one that is working is the full service colour; the one the
## portrait is showing wears a dark ring. Two patrol cars side by side, one out on a
## shout and one parked, should be tellable apart without reading either label.

var unit: Unit: set = _set_unit
## Drawn as a ring around the avatar. The portrait leaves this off -- everything it
## shows is selected by definition -- and the roster uses it to mark the lead unit.
var highlighted := false: set = _set_highlighted


## What was last drawn, so an avatar only repaints when it has something new to say.
## Whether a unit is working has no signal behind it -- it is the order queue being
## non-empty -- so this is polled, and the check has to be cheaper than the repaint.
var _drawn := -1


func _process(_delta: float) -> void:
	var state := _state()
	if state != _drawn:
		_drawn = state
		queue_redraw()


func _state() -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	var busy := 1 if unit.has_orders() else 0
	var lead := 1 if highlighted else 0
	var faded := 1 if not unit.is_selectable() else 0
	return unit.service * 8 + busy * 4 + lead * 2 + faded


func _set_unit(value: Unit) -> void:
	unit = value
	_drawn = -1
	queue_redraw()


func _set_highlighted(value: bool) -> void:
	if highlighted == value:
		return
	highlighted = value
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var shades := Palette.service(unit.service if unit else Unit.Service.NONE)
	# Working units take the solid fill and a light symbol; ones standing by take the
	# pale fill and a dark one, so a busy avatar is the louder of the two.
	var working := unit != null and unit.has_orders()
	var fill: Color = shades[0] if working else shades[1]
	var ink: Color = Palette.CARD if working else shades[2]
	# Out of play -- riding in a vehicle. Still listed, because a crew that vanished
	# from the roster the moment it got in a car would look like it had been lost.
	if unit != null and not unit.is_selectable():
		fill = Palette.dim(fill, 0.35)
		ink = Palette.dim(ink, 0.5)

	draw_circle(centre, radius, fill)
	if highlighted:
		draw_arc(centre, radius - 1.5, 0.0, TAU, 32, shades[2], 3.0, true)
	if unit == null:
		return

	# **Condition, once there is any to report.** A unit that can be lost needs a readout
	# or the first the player knows about it is a body -- and the roster is where they are
	# already looking. Drawn as an arc of the circumference rather than a bar because the
	# badge is a disc at three different sizes and a bar would have to be placed three
	# times. Absent at full health, so an ordinary shift shows nothing.
	var person := unit as Person
	if person and person.health < 1.0:
		var span := TAU * clampf(person.health, 0.0, 1.0)
		var tone: Color = Palette.BAD if person.health < 0.4 else Palette.WARN
		draw_arc(centre, radius - 1.5, -PI * 0.5, -PI * 0.5 + span, 32, tone, 3.0, true)

	if unit.portrait:
		# Inset so the subject sits inside the disc rather than running off its edge.
		# The render already carries its own margin, so this only has to clear the ring.
		var span := radius * 1.94
		draw_texture_rect(unit.portrait,
			Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span)), false,
			Color(1.0, 1.0, 1.0, ink.a))
		return
	Glyph.draw(self, unit.icon(), centre, radius * 0.52, ink, fill)
