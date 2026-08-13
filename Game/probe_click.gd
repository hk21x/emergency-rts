extends SceneTree

## Dev utility: does **right-clicking a pavement** put a car on it?
##
##   godot --headless --fixed-fps 60 --path . --script res://Game/probe_click.gd
##
## `probe_kerb.gd`'s "sent" pass already answers a very similar question and answers it
## yes -- but it issues `MoveOrder.new(point)` straight at the car, which skips everything
## between the player's mouse and that order: the raycast, the [Target] it builds, the
## ability ladder deciding the verb, and `MoveAbility.make_order` choosing the point.
##
## Reported from play as "there's no ability to drive over kerbs currently still" while
## the direct probe passed, which is exactly the shape of a fault living in the part the
## probe skips. So this drives the click path instead: a Target at a pavement point,
## resolved through the car's own abilities, issued the way the controller issues it.

const SCENE := "res://Game/Playground.tscn"

var _scene: Node3D
var _car: Vehicle


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	await process_frame
	var stuck := _scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://probe-stuck-log.txt"
	var station := _scene.get_node("Station")
	station.career_path = "user://probe-click-career.cfg"
	station.funds = 999999
	station.owned = {}
	station.purchase(&"patrol")
	_car = station.dispatch(&"patrol") as Vehicle
	if _car == null:
		print("no car"); quit(); return
	await _idle(40)

	# A kerb, and a spot on the pavement behind it -- the same geometry the direct probe
	# uses, so any difference in the result is the click path and nothing else.
	var from := Vector3(-23.0, 0.0, -6.0)
	var to := Vector3(-11.0, 0.0, -6.0)
	_car.global_position = from + Vector3.UP * 0.2
	_car.look_at(to, Vector3.UP)
	_car.velocity = Vector3.ZERO
	await _idle(10)

	var tile := CityGrid.tile_at(to)
	print("\n============ CLICK PROBE ============")
	print("target (%.1f, %.1f) standable=%s walkable=%s"
		% [to.x, to.z, CityGrid.standable(tile.x, tile.y),
			CityGrid.walkable(tile.x, tile.y)])
	print("  car can reach it on its own layer: %s" % Unit.can_reach(_car, to, 2.0))

	# The click path: a Target as the controller would build it, the verb chosen by the
	# ladder rather than named here, and the order the ability hands back.
	var target := Target.new()
	target.position = to
	var ability := _car.resolve(target)
	print("  right-click resolves to: %s"
		% ("nothing" if ability == null else String(ability.id())))
	if ability == null:
		quit(); return
	var order := ability.make_order(_car, target)
	var aimed: Vector3 = order.destination() if order else Vector3.INF
	print("  the order it makes aims at (%.1f, %.1f)%s"
		% [aimed.x, aimed.z,
			"" if aimed.distance_to(to) < 0.5 else "  <-- NOT where it was clicked"])
	var climbs := 0
	# `climbed` carries the vehicle, so a zero-arg lambda raises on every emit -- which
	# printed a wall of signal errors and left the counter reading 0 while the car was
	# visibly climbing.
	_car.climbed.connect(func(_who: Vehicle) -> void: climbs += 1)
	_car.issue(order)

	# **Physics frames, and let the order start before asking whether it has finished.**
	# An order does not begin until the next `_advance_orders`, so `is_navigating()` is
	# still false the instant after `issue()` -- the first cut of this probe used it as a
	# while-condition, never entered the loop, and reported "finished after 0.0s, 12m
	# short". That is the harness measuring itself, and it very nearly got read as the
	# fault under investigation.
	var elapsed := 0.0
	for i in 20:
		await physics_frame
		elapsed += 1.0 / 60.0
	while elapsed < 20.0 and _car.is_navigating():
		await physics_frame
		elapsed += 1.0 / 60.0

	var ended := _car.global_position
	var ended_tile := CityGrid.tile_at(ended)
	print("\n  order finished     %s after %.1fs" % [not _car.is_navigating(), elapsed])
	print("  climbs fired       %d" % climbs)
	print("  ended at           (%.1f, %.1f), y %.2f" % [ended.x, ended.z, ended.y])
	# Road level settles at y 0.04 and the kerb is 0.07 proud of it, so anything clearly
	# above 0.08 is up on the pavement. The first cut asked for > 0.12 and the car ended
	# at exactly 0.12 -- reported as "not on the pavement" while sitting on it.
	print("  on the pavement    %s (y %.2f, road settles at 0.04)"
		% [CityGrid.standable(ended_tile.x, ended_tile.y) and ended.y > 0.08, ended.y])
	print("  short of target by %.1fm" % Vector2(ended.x - to.x, ended.z - to.z).length())
	quit()


func _idle(frames: int) -> void:
	for i in frames:
		await process_frame
