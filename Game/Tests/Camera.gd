extends "res://Game/Tests/FreeplayTheDirectorAndTheScore.gd"

## Camera -- 2 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


func _test_camera_pan_and_zoom() -> void:
	var before := _camera.focus
	Input.action_press("cam_pan_right")
	await _wait(30)
	Input.action_release("cam_pan_right")
	await _wait(5)
	_check(_camera.focus.distance_to(before) > 1.0,
		"panning moved the camera focus %.1fm" % _camera.focus.distance_to(before))
	_check(absf(_camera.focus.x) <= _camera.pan_limit + 0.01
			and absf(_camera.focus.z) <= _camera.pan_limit + 0.01,
		"focus stayed inside the pan limit")

	var height := _camera.global_position.y
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel)
	await _wait(45)
	_check(_camera.global_position.y < height,
		"wheel zoomed in (%.1f -> %.1f)" % [height, _camera.global_position.y])


func _test_respawn() -> void:
	await _place(ROAD)
	_focus_camera_on_car()
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	if _controller.primary() != _car:
		_check(false, "car is selected before respawn")
		return
	# A real key event, not Input.action_press: the controller listens in
	# _unhandled_input, which only ever sees dispatched events.
	await _press_key(KEY_R)
	await _wait(10)
	# The unit captures its own spawn in _ready. Compared against where the scene
	# actually opened it rather than a written-down coordinate, so moving the station
	# does not break this.
	_check(_flat_distance(_car.global_position, _spawn_slot) < 1.0,
		"respawn returned the car to its start slot (%s, expected %s)"
		% [_car.global_position, _spawn_slot])


# --- Harness -----------------------------------------------------------------
