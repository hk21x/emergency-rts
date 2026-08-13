extends Node
class_name StuckLog

## Writes down what a player's vehicle was doing when it got caught, so a fault seen in
## play can be read afterwards instead of described.
##
## Every handling fault in this project so far has been misdiagnosed on the first guess,
## and the ones that survive are the ones a staged test does not reproduce -- a car
## trapped at a crossroads has been reported repeatedly and every attempt to stage it
## headlessly came out clean. So this stops trying to reproduce the fault and records the
## real one: the position, the speed, what the autopilot thought it was doing, and
## everything within reach of the car at the moment it stopped getting anywhere.
##
## Two ways in. It arms itself when a vehicle under orders stops closing on what it is
## aiming at, and the player can force a record with **F3** for anything that looks wrong
## but is technically moving. Records append to [member log_path], one block each.
##
## A passive watcher, like [Mission] and [CallBoard]: it hooks `node_added` rather than
## being registered with, so nothing else has to know it exists.

## Where records are written. A variable rather than a constant so the suite can point it
## somewhere disposable.
@export var log_path := "user://stuck-log.txt"

## No progress towards the current aim for this long arms a record.
@export var report_after := 4.0
## Closing by less than this does not count as progress.
@export var progress_step := 0.5
## After a record, this long before the same vehicle can file another. Without it a car
## wedged for a minute writes fifteen copies of the same block.
##
## Held as *time since the last record* rather than as a countdown, so lowering it takes
## effect at once. Stored the other way round, a cooldown already ticking from an earlier
## record went on swallowing the next one however the number was changed.
@export var quiet_for := 20.0
## How far around the car to look when describing what it was caught in.
@export var look_around := 14.0
## How often a position is added to each vehicle's trail, and how many are kept. Twenty
## marks at half a second is ten seconds of history, which is comfortably longer than
## the four a record waits for.
@export var trail_every := 0.5
@export var trail_length := 20

var _watched: Array[Vehicle] = []
## Per vehicle: nearest it has been to its aim, seconds since that improved, and seconds
## since it last filed a record.
var _closest := {}
var _stalled := {}
## What each vehicle was last seen aiming at, so a new waypoint starts a new reckoning.
var _aim := {}
var _since_record := {}
## The last few seconds of each vehicle's positions.
var _trails := {}
var _trail_due := 0.0
var _records := 0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		_watch(node)


func _on_node_added(node: Node) -> void:
	_watch(node)


func _watch(node: Node) -> void:
	var vehicle := node as Vehicle
	# The player's own, not the district's. An ambient car queueing at a junction is
	# doing its job, and there are twenty-two of them.
	if vehicle == null or vehicle is TrafficCar or _watched.has(vehicle):
		return
	_watched.append(vehicle)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_F3:
		return
	get_viewport().set_input_as_handled()
	var wrote := 0
	for vehicle in _watched:
		if is_instance_valid(vehicle) and vehicle.is_navigating():
			_write(vehicle, "F3 -- the player said this one is wrong")
			wrote += 1
	if wrote == 0:
		_write_line("\n[F3 pressed with nothing under orders to describe]")


func _physics_process(delta: float) -> void:
	_trail_due -= delta
	var mark := _trail_due <= 0.0
	if mark:
		_trail_due = trail_every
	for vehicle in _watched:
		if not is_instance_valid(vehicle):
			continue
		var id := vehicle.get_instance_id()
		_since_record[id] = float(_since_record.get(id, quiet_for)) + delta
		if mark:
			var trail: Array = _trails.get(id, [])
			trail.append(vehicle.global_position)
			while trail.size() > trail_length:
				trail.remove_at(0)
			_trails[id] = trail
		if not vehicle.is_navigating():
			_closest.erase(id)
			_aim.erase(id)
			_stalled[id] = 0.0
			continue

		# Progress towards the aim, not speed. A car shuffling back and forth under the
		# escape manoeuvre is never stationary and never arriving, which is exactly the
		# case worth a record.
		#
		# **Measured against the aim it currently has.** A lane route hands the car one
		# waypoint after another, and the next one is usually further off than the last
		# was close -- so a baseline kept across the switch can never be beaten again, and
		# a car motoring along at 25 m/s files a record for making no progress. Three of
		# the first five records read that way, which is an instrument crying wolf.
		if vehicle.move_target != _aim.get(id, Vector3.INF):
			_aim[id] = vehicle.move_target
			_closest.erase(id)
			_stalled[id] = 0.0
			continue
		var gap := _flat(vehicle.global_position - vehicle.move_target)
		if gap < float(_closest.get(id, INF)) - progress_step:
			_closest[id] = gap
			_stalled[id] = 0.0
			continue
		_stalled[id] = float(_stalled.get(id, 0.0)) + delta
		if float(_stalled[id]) < report_after \
				or float(_since_record[id]) < quiet_for:
			continue
		_stalled[id] = 0.0
		_since_record[id] = 0.0
		_write(vehicle, "no progress for %.0fs" % report_after)


## How many records have been filed this session. Public so a check can assert on it
## without reading the file back.
func records() -> int:
	return _records


func _write(vehicle: Vehicle, why: String) -> void:
	_records += 1
	var order := vehicle.current_order()
	var lines := PackedStringArray()
	lines.append("\n--- %s: %s ---" % [vehicle.display_name, why])
	lines.append("  at (%.1f, %.1f)  on a road: %s  speed %.1f  on the floor: %s"
		% [vehicle.global_position.x, vehicle.global_position.z,
			CityGrid.is_road(vehicle.global_position), vehicle.forward_speed,
			vehicle.is_on_floor()])
	lines.append("  aiming at (%.1f, %.1f), %.1fm away"
		% [vehicle.move_target.x, vehicle.move_target.z,
			_flat(vehicle.global_position - vehicle.move_target)])
	# **"Recovering" is not the same question as "turning round".** A car reverses under
	# two different mechanisms -- the reverse latch, which `is_turning_round()` reports,
	# and the stuck escape, which it does not. Four August 2026 records read
	# `turning round: false` while the car was doing -4 to -5 m/s under an escape, and
	# that read as "no recovery is firing" when in fact it was firing repeatedly and not
	# helping. Those are opposite conclusions wanting opposite fixes, so the record now
	# separates them rather than leaving the escape timer further down to be cross-read.
	lines.append("  order: %s   turning round: %s   escaping: %s   passing: %s"
		% [order.describe() if order else "none", vehicle.is_turning_round(),
			vehicle.is_escaping(), vehicle.is_avoiding])
	# **The destination, not just the waypoint.** Two records were replayed from the
	# waypoint alone and both drove it cleanly, because a waypoint out of context is a
	# different question from the journey it belongs to. Without the end point and the
	# route's shape there is nothing to reconstruct.
	if order:
		var end := order.destination()
		lines.append("  destination (%.1f, %.1f), %.1fm away"
			% [end.x, end.z, _flat(vehicle.global_position - end)])
	if order is MoveOrder:
		var move := order as MoveOrder
		lines.append("  route: waypoint %d of %d, %d street(s) written off"
			% [move._at, move._route.size(), move._shut.size()])
		if move._at > 0 and move._at - 1 < move._route.size():
			var last: Vector3 = move._route[move._at - 1]
			lines.append("    came from (%.1f, %.1f), %.1fm back"
				% [last.x, last.z, _flat(vehicle.global_position - last)])
		if move._at + 1 < move._route.size():
			var next: Vector3 = move._route[move._at + 1]
			lines.append("    then (%.1f, %.1f)" % [next.x, next.z])
	# What the navigation agent makes of it. A car steering at a target it believes it
	# has already reached looks identical from outside to one that is blocked.
	var agent := vehicle.get_node_or_null("NavigationAgent") as NavigationAgent3D
	if agent:
		lines.append("  agent: %d points in its path, finished: %s, reachable: %s"
			% [agent.get_current_navigation_path().size(),
				agent.is_navigation_finished(), agent.is_target_reachable()])
	# **Why it is not moving.** A car holding station behind a stopped vehicle looks
	# identical to one that has simply given up: both sit still with a valid path. The
	# ceiling is the number that separates them -- it drops to the blocker's own speed,
	# which is zero.
	var forward := -vehicle.global_basis.z
	forward.y = 0.0
	var blocker := vehicle._vehicle_in_the_way(forward.normalized()) \
		if forward.length() > 0.01 else null
	lines.append("  speed ceiling %.1f, throttle %.2f, holding behind: %s"
		% [vehicle._cruise_ceiling(), vehicle.throttle_input,
			blocker.name if blocker else "nothing"])
	lines.append("  escape timer %.2f, stuck timer %.2f"
		% [vehicle._escape_time, vehicle._stuck_time])
	# **Where it has been**, not just where it is. Every record so far has been a
	# snapshot, and a snapshot cannot tell a car that stopped where it stood from one
	# that wandered thirty metres off its route and stopped there -- which is the
	# difference between a blockage and a steering fault. One was found 31m north of a
	# dead straight path east with no way to see how it got there.
	var trail: Array = _trails.get(vehicle.get_instance_id(), [])
	if not trail.is_empty():
		var marks := PackedStringArray()
		for point: Vector3 in trail:
			marks.append("(%.0f,%.0f)" % [point.x, point.z])
		lines.append("  came by, over the last %.0fs: %s"
			% [trail.size() * trail_every, " -> ".join(marks)])
	lines.append("  in a junction box: %s" % _junction_note(vehicle))
	lines.append("  within %.0fm:" % look_around)
	var found := 0
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var other := node as Unit
		if other == null or other == vehicle:
			continue
		# Crew riding in the vehicle are pinned to it and would list as being 0.0m away,
		# which reads like a collision and is just a paramedic in the back.
		var person := other as Person
		if person and person.is_aboard:
			continue
		var gap := _flat(other.global_position - vehicle.global_position)
		if gap > look_around:
			continue
		found += 1
		var speed := (other as Vehicle).forward_speed if other is Vehicle else 0.0
		lines.append("    %-18s %5.1fm %s  speed %5.1f%s"
			% [other.name, gap, _bearing_note(vehicle, other), speed,
				_traffic_note(other)])
	if found == 0:
		lines.append("    nothing -- it is not blocked by a unit")
	lines.append("  touching: %s" % _contact_note(vehicle))
	_write_line("\n".join(lines))


## Where something is relative to the nose, not just how far. Range alone cannot be
## reconstructed into a geometry: three records of a car at full throttle and zero speed
## each listed a neighbour within 7m, and there was no way to tell whether it was in
## front, alongside or behind -- so no way to stage the fault and no way to say whether
## the forward-cone test that reported "nothing" was wrong or right.
func _bearing_note(vehicle: Vehicle, other: Unit) -> String:
	var offset := other.global_position - vehicle.global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return "on top"
	var nose := -vehicle.global_basis.z
	nose.y = 0.0
	var degrees := rad_to_deg(nose.signed_angle_to(offset, Vector3.UP))
	var side := "left" if degrees > 0.0 else "right"
	if absf(degrees) < 15.0:
		return "dead ahead"
	if absf(degrees) > 165.0:
		return "behind   "
	return "%3.0f° %-5s" % [absf(degrees), side]


## What the car is actually in contact with.
##
## The one thing that separates the three readings a stalled record cannot tell apart:
## a car pressed against another vehicle, a car pressed against scenery, and a car
## touching nothing at all whose trouble is entirely in its own steering. All three
## present identically as "on a road, full throttle, zero speed, nothing in front",
## because `holding behind` only ever names a vehicle in the forward cone.
func _contact_note(vehicle: Vehicle) -> String:
	var names := PackedStringArray()
	for i in vehicle.get_slide_collision_count():
		var hit := vehicle.get_slide_collision(i)
		if hit == null:
			continue
		var body := hit.get_collider() as Node
		names.append(body.name if body else "?")
	if names.is_empty():
		return "nothing -- it is not wedged against anything"
	return ", ".join(names)


func _junction_note(vehicle: Vehicle) -> String:
	var cell := CityGrid.junction_at(vehicle.global_position)
	var gap := _flat(vehicle.global_position - CityGrid.junction(cell))
	if gap > 9.0:
		return "no, %.0fm from the nearest crossroads" % gap
	return "yes, %.1fm from the middle of %d,%d" % [gap, cell.x, cell.y]


func _traffic_note(unit: Unit) -> String:
	var traffic := unit as TrafficCar
	if traffic == null:
		return ""
	var notes := PackedStringArray()
	if traffic.is_yielding:
		notes.append("yielding")
	if traffic.is_pulled_over:
		notes.append("pulled over")
	return "  (%s)" % ", ".join(notes) if not notes.is_empty() else "  (ambient)"


func _write_line(text: String) -> void:
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_warning("StuckLog could not open %s" % log_path)
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()
