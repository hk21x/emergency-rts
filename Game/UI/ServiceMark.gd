extends Control
class_name ServiceMark

## A service and a shape, as a small circular badge.
##
## The counterpart to [UnitBadge] for things that are not a unit yet. The dispatch panel
## lists what the station *holds*, and there is nothing on the map to photograph until
## somebody presses the row -- so this draws the same disc with the plain silhouette.

var service := Unit.Service.NONE: set = _set_service
var symbol: StringName = &"person": set = _set_symbol


func _set_service(value: int) -> void:
	service = value
	queue_redraw()


func _set_symbol(value: StringName) -> void:
	symbol = value
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var shades := Palette.service(service)
	draw_circle(centre, radius, shades[1])
	Glyph.draw(self, symbol, centre, radius * 0.56, shades[2], shades[1])
