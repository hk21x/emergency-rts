extends "res://Game/Tests/SelectionAndOrders.gd"

## Order queue -- 2 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_shift_right_click_queues() -> void:
	await _place(ROAD)
	_focus_camera_on_car()
	_controller.select([_car])

	var first := _car.global_position + Vector3(0.0, 0.0, -8.0)
	var second := _car.global_position + Vector3(0.0, 0.0, -17.0)
	first.y = 0.0
	second.y = 0.0
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(first))
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(second), true)
	_check(_car.orders.size() == 2, "shift right-click queued a second order (%d)"
		% _car.orders.size())
	# The queued order must not have started; only the front one drives.
	_check(_flat_distance(_car.move_target, first) < 2.5,
		"the car is still working on the first order")

	var done := await _await_arrival(1800)
	_check(done, "worked through both queued orders [%s]" % _car_state())
	_check(_flat_distance(_car.global_position, second) < _car.arrive_radius + 1.5,
		"finished at the second destination")


func _test_stop_cancels_orders() -> void:
	await _place(ROAD)
	_controller.select([_car])
	_car.issue(MoveOrder.new(Vector3(-20.0, 0.0, -20.0)))
	await _wait(30)
	_check(_car.has_orders(), "car has an order before Stop")

	var stop := _find_ability(_car, &"stop")
	if stop == null:
		_check(false, "car offers a Stop ability")
		return
	_controller.activate(stop)
	await _wait(10)
	_check(not _car.has_orders(), "Stop cleared the order queue")
	_check(not _car.is_navigating(), "Stop cancelled the navigation")


# --- Multi-selection ---------------------------------------------------------
