extends "res://Game/Tests/OrderQueue.gd"

## Multi-selection -- 3 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_box_select() -> void:
	_controller.clear_selection()
	# Park all three in a tidy row on empty deck and frame them.
	for i in _cars.size():
		await _place_unit(_cars[i], Vector3(14.0 + i * 4.0, 0.15, 18.0))
	_camera.focus = Vector3(18.0, 0.0, 18.0)
	_camera._apply_transform()
	await _wait(5)

	var corners := _screen_bounds(_cars)
	await _drag(corners[0] - Vector2(60, 60), corners[1] + Vector2(60, 60))
	_check(_controller.selection.size() == _cars.size(),
		"box select caught all %d cars (got %d)" % [_cars.size(), _controller.selection.size()])
	for car in _cars:
		if not car.is_selected:
			_check(false, "%s shows a selection ring" % car.display_name)
			return
	_check(true, "every boxed car shows its own ring")


func _test_shift_click_adds() -> void:
	_controller.select([_cars[0]])
	_check(_controller.selection.size() == 1, "starting from a single selection")

	await _click(MOUSE_BUTTON_LEFT, _screen_of(_cars[1].global_position + Vector3.UP * 0.9), true)
	_check(_controller.selection.size() == 2,
		"shift-click added a second unit (%d)" % _controller.selection.size())

	# Shift-clicking an already-selected unit removes it again.
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_cars[1].global_position + Vector3.UP * 0.9), true)
	_check(_controller.selection.size() == 1,
		"shift-clicking it again removed it (%d)" % _controller.selection.size())


func _test_control_groups() -> void:
	_controller.select([_cars[0], _cars[2]])
	await _press_key(KEY_1, true)
	_controller.clear_selection()
	_check(_controller.selection.is_empty(), "selection cleared before recall")

	await _press_key(KEY_1)
	_check(_controller.selection.size() == 2,
		"control group 1 recalled 2 units (%d)" % _controller.selection.size())
	_check(_controller.selection.has(_cars[0]) and _controller.selection.has(_cars[2]),
		"recalled the same two units")


# --- Personnel ---------------------------------------------------------------

# --- Interface ---------------------------------------------------------------
