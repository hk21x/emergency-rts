extends "res://Game/Tests/TestCase.gd"

## Harness -- 3 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## Phase 18: the session opens on a title card over the idling district. Nothing
## underneath may hear the mouse or the keyboard until PLAY -- an F2 that opened a
## shift under the menu would be a shift the player never asked for.
func _test_the_game_opens_on_the_title() -> void:
	if _menu == null:
		_check(false, "the HUD ships a menu")
		return
	_check(_menu.visible and _menu.screen == GameMenu.Screen.TITLE,
		"the session opens on the title card")

	# **A column down the left, not a card in the middle.** The reference the user
	# supplied puts its menu in a left-hand column with the picture beside it, and here
	# the picture is the district itself -- so the menu has to leave the district
	# visible. A centred card would satisfy every other check on this screen while
	# looking nothing like what was asked for.
	var column := _menu._menu_column.get_global_rect()
	var screen_width := float(root.size.x)
	_check(column.position.x < screen_width * 0.1
			and column.end.x < screen_width * 0.4,
		"the main menu is a column down the left (ends %.0f%% across)"
		% (100.0 * column.end.x / screen_width))
	# Every row carries a kit icon. Checked because the icons are looked up by name at
	# build time and a renamed file returns null silently -- the row keeps working and
	# simply loses its picture, which is exactly the kind of thing nobody notices.
	var rows := 0
	var pictured := 0
	for node in _descendants(_menu._title_card):
		var row := node as Button
		if row == null or row.theme_type_variation != &"MenuItem":
			continue
		rows += 1
		if row.icon != null:
			pictured += 1
	_check(rows >= 4 and pictured == rows,
		"and every one of its %d rows carries a kit icon (%d did)" % [rows, pictured])

	# **Aimed at a unit the card is not sitting on.** The title card is centred, and
	# clicking a unit that happens to be behind it lands on a *button* rather than on
	# the district -- which swallows the click in the least useful possible way, and
	# then plays the game. It went unnoticed until the card grew a SCENARIOS row and
	# the old fixed target moved under PLAY. Picked by rect rather than by nudging the
	# coordinate, so the next button added to the card cannot repeat it.
	var picked: Unit = _car
	# **The column, not the card.** Since the main menu was built to the reference the
	# title card is a full-rect transparent page with a column down the left, so asking
	# whether a point is "over the card" is now always true and the pan below would
	# never find a gap. What occupies space is the column.
	var card_rect: Rect2 = _menu._menu_column.get_global_rect()
	var aim := _screen_of(picked.global_position + Vector3.UP * 0.9)
	# The fleet parks together on the forecourt, so when the card covers one it covers
	# all seven -- picking a different unit is no escape. Panning is: the camera is not
	# paused by the title, so the district can be slid out from under the card until a
	# unit is somewhere clickable, and slid back afterwards.
	var was_focus: Vector3 = _camera.focus
	var slid := 0
	while card_rect.has_point(aim) and slid < 6:
		_camera.focus += Vector3(14.0, 0.0, 14.0)
		await _idle(2)
		aim = _screen_of(picked.global_position + Vector3.UP * 0.9)
		slid += 1
	_check(not card_rect.has_point(aim),
		"a unit stands clear of the title card to click at")
	await _click(MOUSE_BUTTON_LEFT, aim)
	_check(not picked.is_selected and _menu.visible,
		"a click on the district is swallowed by the card")
	_camera.focus = was_focus
	await _idle(2)
	await _press_key(KEY_F2)
	await _idle(2)
	_check(not _director.active, "and F2 does not open a shift under it")

	await _press_key(KEY_ENTER)
	await _idle(2)
	_check(not _menu.visible and _menu.screen == GameMenu.Screen.HIDDEN,
		"ENTER plays: the card lifts")


## The map ships quiet: no scripted shout. The district idles -- crowds, traffic, a
## parked shift -- until the player opens a freeplay shift, so the game has to open
## with an empty board and say how to start.
func _test_the_map_opens_quiet() -> void:
	_check(get_nodes_in_group(Incident.GROUP).is_empty(),
		"the map ships no incidents (%d)" % get_nodes_in_group(Incident.GROUP).size())
	_check(_board.open_calls().is_empty(),
		"the board opens empty (%d)" % _board.open_calls().size())
	_check(_mission.state == Mission.State.RUNNING and not _mission.scoring,
		"the mission idles rather than scoring (state %d)" % _mission.state)
	var hint := _scene.get_node_or_null("HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
	_check(hint != null and hint.visible and "F2" in hint.text,
		"and the screen says how to start ('%s')" % (hint.text if hint else "no label"))


## The 260m map, and the irregularity that keeps it from reading as a stamp. Also
## pins the parks: their lawns must be strollable (in the pavement table, so the
## crowd and the director both use them) and walkable (covered by the person mesh).
func _test_the_district_doubled_with_variety() -> void:
	_check(CityGrid.MAP_HALF == 130.0,
		"the district is 260m across (half %.0f)" % CityGrid.MAP_HALF)

	var spans_x: Array[int] = []
	var spans_z: Array[int] = []
	for i in CityGrid.BLOCKS:
		spans_x.append(CityGrid.block_span_x(i))
		spans_z.append(CityGrid.block_span_z(i))
	_check(spans_x.min() != spans_x.max() and spans_z.min() != spans_z.max(),
		"blocks vary in size rather than repeating one span (x %s, z %s)"
		% [spans_x, spans_z])

	var park := CityGrid.block_centre(CityGrid.PARKS[0].x, CityGrid.PARKS[0].y)
	var lawn_tiles := 0
	for point in CityGrid.pavement_points():
		if _flat_distance(point, park) < 10.0:
			lawn_tiles += 1
	_check(lawn_tiles >= 4,
		"the park lawn is in the strolling table (%d tiles near its centre)" % lawn_tiles)

	var nav_map := _officer.get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(nav_map, park)
	_check(_flat_distance(snapped, park) < 2.0,
		"and the walking mesh covers the lawn (nearest point %.1fm off)"
		% _flat_distance(snapped, park))


# --- Ambient population ------------------------------------------------------
