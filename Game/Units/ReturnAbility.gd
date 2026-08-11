extends Ability
class_name ReturnAbility

## Send a unit to where it needs to be: **its drop-off if it is carrying somebody, its
## station if it is not.**
##
## A casualty aboard means the hospital, a detained suspect means the custody door, and an
## empty unit means home. The unit works out which, because that is the useful part —
## both deliveries already happen automatically on arrival, and what was missing was any
## way to say "take them in" without knowing which end of the district the right door is
## at.
##
## One tile rather than two on purpose. The command bar holds exactly seven before the
## PanelContainer grows and silently swallows the CONTROLS chip above it, and a patrol car
## already carries seven.
##
## Instant, like Stop and Unload: there is nothing to click. It declines every target so
## it never competes for a right-click -- "go home" should be a deliberate press, not
## something a stray click on the forecourt can mean.


func id() -> StringName:
	return &"return"


func label() -> String:
	return "Return"


func icon() -> StringName:
	return &"station"


func hotkey() -> Key:
	return KEY_H


func is_instant() -> bool:
	return true


func execute(unit: Unit) -> void:
	# Casualties first: a unit carrying both is carrying somebody who is bleeding, and the
	# custody door can wait.
	var vehicle := unit as Vehicle
	if vehicle and not vehicle.casualties.is_empty():
		var hospital := unit.get_tree().get_first_node_in_group(Hospital.GROUP) as Node3D
		if hospital:
			unit.issue(MoveOrder.new(hospital.global_position))
			return
	var station := _nearest(unit)
	if station:
		unit.issue(ReturnOrder.new(station))


## Found through the group rather than held as a reference: an Ability is a RefCounted
## shared by every unit of its type, so it cannot own a pointer to one station without
## every unit agreeing on it before the map has finished building.
func _nearest(unit: Unit) -> Station:
	var best: Station = null
	var closest := INF
	for node in unit.get_tree().get_nodes_in_group(Station.GROUP):
		var station := node as Station
		if station == null:
			continue
		var distance := unit.global_position.distance_to(station.global_position)
		if distance < closest:
			closest = distance
			best = station
	return best
