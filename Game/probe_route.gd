extends SceneTree

## Dev utility: does the lane route ever start with a waypoint **behind** the car?
##
##   godot --headless --path . --script res://Game/probe_route.gd
##
## A car steered at a point behind itself drives away from its destination and then has
## to come back, which from the player's chair is a full circle instead of a turn. It has
## been reported from play repeatedly, and the F4 overlay finally caught it: the first
## route ring sitting on the crossing the car had already cleared, with the rest of the
## route running the other way.
##
## `lane_route` already guards against this -- `already_past` drops the approach waypoint
## when the car has demonstrably passed that junction. This sweeps a car up to and
## through a junction and asks, at every metre, whether the waypoint it would be given is
## in front of it or behind it. No scene needed: the grid is all static.

const STEP := 1.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n============ ROUTE PROBE ============")
	print("JUNCTION_MARGIN %.1f, LANE_OFFSET %.1f"
		% [CityGrid.JUNCTION_MARGIN, CityGrid.LANE_OFFSET])

	# Approach junction (2,2) from the west, bound for somewhere north of it, so the
	# route turns at that junction -- the shape in both screenshots.
	var corner := CityGrid.junction(Vector2i(2, 2))
	var target := CityGrid.junction(Vector2i(2, 4))
	var along := (corner - CityGrid.junction(Vector2i(1, 2))).normalized()

	print("\napproaching %s bound for %s" % [_str(corner), _str(target)])
	print("  (a negative figure means the first waypoint is BEHIND the car)\n")
	print("  %8s  %10s  %s" % ["offset", "ahead by", "first waypoint"])

	var worst := INF
	var bad := 0
	var tested := 0
	for i in 41:
		# From 30m before the junction centre to 10m past it.
		var offset := -30.0 + STEP * i
		var from := corner + along * offset
		var points := CityGrid.lane_route(from, target)
		if points.is_empty():
			continue
		tested += 1
		# **Progress toward the destination, not distance along the approach axis.**
		# The first cut measured the latter and condemned every turn: on a left-hander
		# the first waypoint is properly 2.5m back along the incoming street and 9m up
		# the outgoing one, which is correct and read as "behind". What actually hurts is
		# a waypoint that takes the car *away* from where it was sent -- that is the
		# "clicked east, drove west" the trail recorded.
		var reach := (target - from)
		reach.y = 0.0
		var step := (points[0] - from)
		step.y = 0.0
		var ahead := step.dot(reach.normalized())
		worst = minf(worst, ahead)
		if ahead < 0.0:
			bad += 1
		if absf(offset) <= 12.0:
			print("  %+8.1f  %+10.2f  %s" % [offset, ahead, _str(points[0])])

	print("\n  %d of %d start positions get a waypoint behind them" % [bad, tested])
	print("  furthest behind: %.2fm" % worst)
	quit()


func _str(point: Vector3) -> String:
	return "(%.1f, %.1f)" % [point.x, point.z]
