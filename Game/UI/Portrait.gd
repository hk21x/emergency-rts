extends VBoxContainer
class_name Portrait

## Who is selected and what they are doing, in the left block of the command bar.
##
## Builds its own children rather than having them authored in `HUD.tscn`. Four labels
## and a badge described in code read better than forty lines of scene text setting
## anchors, and it keeps the panel's layout next to the logic that fills it.
##
## Reads the controller directly and refreshes every frame: a speed and a distance both
## move continuously, so there is nothing to signal on.

@export var badge_size := 48.0

var controller: RTSController

var _badge: UnitBadge
var _name: Label
var _stats: Label
var _activity: Label
var _tank: ProgressStrip


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)

	_badge = UnitBadge.new()
	_badge.custom_minimum_size = Vector2(badge_size, badge_size)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_badge)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)

	_name = _label(titles, 16, Palette.TEXT)
	_stats = _label(titles, 11, Palette.TEXT_DIM)

	# The appliance's tank, as a bar. Shown only for something that carries water,
	# which is the fire engine and nothing else -- and a bar rather than a figure
	# for the same reason the call board stopped printing percentages.
	_tank = ProgressStrip.new()
	_tank.custom_minimum_size = Vector2(96.0, 5.0)
	_tank.tint = Palette.MEDICAL
	_tank.visible = false
	titles.add_child(_tank)

	_activity = _label(self, 12, Palette.MEDICAL_DEEP)
	_activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_activity.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _label(parent: Node, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	if controller == null:
		return
	var count := controller.selection.size()
	var unit := controller.primary()
	_badge.unit = unit
	# An empty avatar is a grey disc that means nothing. Better to have the card just
	# say what it wants.
	_badge.visible = unit != null

	if count == 0:
		_name.text = "Nothing selected"
		_stats.text = ""
		_tank.visible = false
		_activity.text = "Click a unit in the street or on the roster"
		_activity.add_theme_color_override("font_color", Palette.TEXT_DIM)
		return

	# Amber while the cursor is armed and waiting for a target, green otherwise: the
	# armed state is the only one where the interface is holding the player up.
	_activity.add_theme_color_override("font_color",
		Palette.FIRE_DEEP if controller.armed_ability else Palette.MEDICAL_DEEP)
	_name.text = "%d units selected" % count if count > 1 else unit.display_name
	_stats.text = _stats_line(unit, count)

	var appliance := unit as Vehicle
	_tank.visible = appliance != null and appliance.carries_water
	if _tank.visible:
		_tank.value = appliance.water
		# Blue while it is filling, so a crew waiting at a hydrant can see that
		# something is happening; the service colour otherwise.
		_tank.tint = Palette.POLICE if appliance.is_refilling else Palette.FIRE

	if controller.armed_ability:
		_activity.text = "Click a target for %s\nEsc or right-click to cancel" \
			% controller.armed_ability.label()
		return
	_activity.text = _activity_line(unit, count)


## The steady facts about the lead unit: what it is carrying and how fast it is going.
func _stats_line(unit: Unit, count: int) -> String:
	var parts := PackedStringArray()
	if count > 1:
		parts.append("lead: %s" % unit.display_name)
	var vehicle := unit as Vehicle
	if vehicle:
		parts.append("%.0f km/h" % vehicle.speed_kmh())
		if not vehicle.crew.is_empty():
			parts.append("crew %d/%d" % [vehicle.crew.size(), vehicle.seats])
		if not vehicle.casualties.is_empty():
			parts.append("carrying %d" % vehicle.casualties.size())
		if not vehicle.suspects.is_empty():
			parts.append("%d in custody" % vehicle.suspects.size())
		if vehicle.carries_water:
			parts.append("refilling" if vehicle.is_refilling
				else ("tank dry" if not vehicle.has_water() else "tank"))
	return "   ".join(parts)


## What it is doing right now, or the hint that it is doing nothing.
func _activity_line(unit: Unit, count: int) -> String:
	if count > 1:
		var busy := 0
		for other in controller.selection:
			if other.has_orders():
				busy += 1
		if busy == 0:
			return "Right-click to send them somewhere"
		return "%d of %d on the move" % [busy, count]

	var order := unit.current_order()
	if order == null:
		# A vehicle with somebody in the back is not standing by, it is holding them.
		# Delivery is automatic on arrival at the right yard, so the only thing the
		# player has to know is *which* yard -- and until this line existed, nothing
		# anywhere said it. Both destinations are on the minimap.
		var idle_vehicle := unit as Vehicle
		if idle_vehicle:
			if not idle_vehicle.suspects.is_empty():
				return "Holding %d - drive to the STATION to book them in" \
					% idle_vehicle.suspects.size()
			if not idle_vehicle.casualties.is_empty():
				return "Carrying %d - drive to the HOSPITAL to hand them over" \
					% idle_vehicle.casualties.size()
		return "Standing by"

	var text := order.describe()
	var vehicle := unit as Vehicle
	if vehicle and vehicle.is_navigating():
		text += "  -  %.0f m to go" % vehicle.remaining_distance()
	var waiting := unit.orders.size() - 1
	if waiting > 0:
		text += "   (+%d queued)" % waiting
	return text
