extends SceneTree

## Headless behaviour test for the RTS playground. Physics runs for real without a
## renderer, so this exercises the actual autopilot and picking code.
##
##   godot --headless --path . --script res://Game/smoke_test.gd
##
## Exits non-zero if any check fails.

const SCENE := "res://Game/Playground.tscn"
## A clear stretch of a north-south avenue near the middle of the district. Vehicle
## tests start here rather than anywhere convenient: the vehicle navigation mesh is
## the road network, so a car has to be *on* a road before it can be asked to go
## anywhere. x=20 is a band centre in CityGrid.X_BANDS -- kept there deliberately
## when the map grew, so the mid-map test positions stayed on real streets.
const ROAD := Vector3(20.0, 0.15, 5.0)
## Road bands are 10m wide; their (irregular) positions come from CityGrid's tables.
const BAND_WIDTH := 10.0
## Any civilian outfit will do; the roster check only cares that it has no service.
const CIVILIAN_SCENE := "res://Game/Civilians/BusinessMan_Suit.tscn"
## Frames allowed for the corner-to-corner drive -- half a kilometre with a turn at
## every junction, which measures around 3,800. Generous on purpose: this is a
## journey time, and a budget set close to it fails on any unrelated change that
## costs the car a second.
const CROSSING_BUDGET := 6000

var _failures := 0
## Every check that ran, so the summary can state its own total. Without it the only
## way to know the size of the suite is to count `ok` lines, and a number nobody
## measures is a number that drifts -- these documents have carried a stale check
## count more than once.
var _checks := 0
var _car: Vehicle
var _cars: Array[Vehicle] = []
var _ambulance: Vehicle
var _officer: Person
var _paramedic: Person
var _incidents: Node3D
var _hospital: Area3D
var _mission: Mission
var _camera: RTSCamera
var _controller: RTSController
## The transparent layer the bottom panels live on, and the two panels themselves.
var _bar: Control
var _unit_panel: PanelContainer
var _command_panel: PanelContainer
var _help: PanelContainer
var _portrait: Portrait
var _roster: Roster
var _grid: CommandGrid
var _call_list: CallList
var _board: CallBoard
var _station: Station
var _director: Director
var _menu: GameMenu
## How many player units the map itself shipped -- must be zero under the career.
var _shipped_units := -1
var _ring: Node3D
var _marker: Node3D
var _scene: Node3D
var _spawn_slot := Vector3.ZERO
var _opening_focus := Vector3.ZERO
var _opening_distance := 0.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# --headless gives a 64x64 viewport. That makes unproject_position return
	# meaningless coordinates, and leaves the bottom-anchored command bar spanning
	# the whole screen, where it swallows every click as GUI input before
	# _unhandled_input ever sees it. Give the tests a real screen to click on.
	#
	# Sized to the project's own stretch base, deliberately. The project scales canvas
	# items, so at any other window size the interface lives in a coordinate space that
	# is not the window's -- and push_input takes window coordinates while
	# unproject_position returns interface ones. Matching them makes the scale factor 1
	# and the two agree again; at 1152x648 every synthesised click landed about a third
	# of the way off its target.
	root.size = Vector2i(1600, 900)

	_test_the_characters_share_one_animation_library()
	await _test_the_menu_backdrop_is_dressed()

	# The tutorial town, checked FIRST and freed before the district loads: two
	# Stations, Hospitals or Daylights in one tree would poison every
	# get_first_node_in_group fixture the rest of the suite stands on.
	await _test_the_tutorial_town_boots()

	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_scene = scene as Node3D

	_camera = scene.get_node_or_null("Camera") as RTSCamera
	_controller = scene.get_node_or_null("RTSController") as RTSController
	_station = scene.get_node_or_null("Station") as Station

	# The map ships EMPTY of player units now -- a career buys its fleet. The suite
	# is that career: a scratch save, a topped-up purse, and the classic seven
	# bought and dispatched onto the same apron spots the map used to ship them on.
	_shipped_units = scene.get_node("Units").get_child_count()
	if _station:
		_station.career_path = "user://smoke-career.cfg"
		_station.reset_career()
		_station.funds = 99999
		for id in [&"patrol", &"patrol", &"ambulance",
				&"officer", &"officer", &"paramedic", &"paramedic"]:
			_station.purchase(id)
		var home: Vector3 = _station.global_position
		_car = _dispatch_to(&"patrol", home + Vector3(-6.0, 0.2, -2.5)) as Vehicle
		var patrol2 := _dispatch_to(&"patrol", home + Vector3(0.0, 0.2, -2.5)) as Vehicle
		_ambulance = _dispatch_to(&"ambulance", home + Vector3(6.0, 0.2, -2.5)) as Vehicle
		_officer = _dispatch_to(&"officer", home + Vector3(-9.0, 0.05, -2.0)) as Person
		_dispatch_to(&"officer", home + Vector3(-3.0, 0.05, -2.0))
		_paramedic = _dispatch_to(&"paramedic", home + Vector3(3.0, 0.05, -2.0)) as Person
		_dispatch_to(&"paramedic", home + Vector3(9.0, 0.05, -2.0))
		_cars = [_car, patrol2, _ambulance]
	_incidents = scene.get_node_or_null("Incidents") as Node3D
	_hospital = scene.get_node_or_null("Hospital") as Area3D
	_mission = scene.get_node_or_null("Mission") as Mission
	_ring = _car.get_node_or_null("SelectionRing") as Node3D if _car else null
	_marker = scene.get_node_or_null("MoveMarker") as Node3D
	# **The bottom panels, not a bar.** `Bar` is a transparent full-rect layer since the
	# HUD was floated into corners -- it has no stylebox and no size of its own, so the
	# thing worth measuring is the panels inside it. Cast as Control, not
	# PanelContainer: the old cast quietly returned null and took nineteen checks with
	# it, which the count caught and the FAIL line did not.
	_bar = scene.get_node_or_null("HUD/Root/Bar") as Control
	_unit_panel = scene.get_node_or_null(
		"HUD/Root/Bar/Row/PortraitBlock") as PanelContainer
	_command_panel = scene.get_node_or_null(
		"HUD/Root/Bar/Row/CommandBlock") as PanelContainer
	_help = scene.get_node_or_null("HUD/Root/World/HelpPanel") as PanelContainer
	_portrait = scene.get_node_or_null(
		"HUD/Root/Bar/Row/PortraitBlock/Portrait") as Portrait
	_roster = scene.get_node_or_null("HUD/Root/Bar/Row/RosterBlock/Body/Roster") as Roster
	_grid = scene.get_node_or_null(
		"HUD/Root/Bar/Row/CommandBlock/Body/CommandGrid") as CommandGrid
	_call_list = scene.get_node_or_null("HUD/Root/World/CallList") as CallList
	_board = scene.get_node_or_null("CallBoard") as CallBoard
	_director = scene.get_node_or_null("Director") as Director
	if _car == null or _camera == null or _controller == null:
		_check(false, "scene has a Car, an RTSCamera and an RTSController")
		_finish()
		return

	# The mission banks its best shift to user:// when one ends. Pointed at a
	# disposable file and zeroed, or every suite run would write a record the player
	# then has to beat.
	if _mission:
		_mission.records_path = "user://smoke-records.cfg"
	# **Before a single check runs.** The recorder defaults to the player's own log, and
	# redirecting it inside the check that exercises it is far too late: every suite run
	# had been appending its fixtures into `user://stuck-log.txt`, including a deliberate
	# 400m destination the pull-over check uses to keep a car counting as a responder.
	# Reading that log afterwards, those fixtures are indistinguishable from play -- and
	# one of them was diagnosed as a live bug.
	var stuck := scene.get_node_or_null("StuckLog") as StuckLog
	if stuck:
		stuck.log_path = "user://smoke-stuck-log.txt"
		_mission.best_score = 0
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_mission.records_path))
	# Same treatment for the menu's settings file, and the values it already loaded
	# from the player's real one are put back to the defaults the tests assume.
	_menu = _scene.get_node_or_null("HUD/Root/Menu") as GameMenu
	if _director:
		# Tests set their own intervals; the settings card's call-rate multiplier
		# would silently stretch every one of them.
		_director.pace = 1.0
	if _menu:
		_menu.settings_path = "user://smoke-settings.cfg"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_menu.settings_path))
		_menu.set_volume(1.0)
		_menu.set_shift_minutes(5)
		# And the hour, for the same reason as the pace above -- but this one bites
		# harder, because the menu's own `_ready` has already *loaded and applied* the
		# player's real settings.cfg before this fixture can repoint the path. Leave a
		# session ended at dusk and the whole suite ran at dusk, with the street lights
		# on; the check that noon is not lit by streetlight is what caught it.
		_menu.set_time_of_day(Daylight.Mode.DAY)
		# And the weather, which is the same trap wearing a different hat: rain takes
		# 28% of the grip off every vehicle, so a session left in the wet would quietly
		# reduce the speed every driving check measures.
		_menu.set_weather(Daylight.Weather.CLEAR)

	# Where the car starts, captured before any test moves it, so the respawn check
	# does not have to know the map layout.
	_spawn_slot = _car.global_position
	# The framing the game opens on, kept so a test can check the map as presented
	# rather than as some later test happened to leave it.
	_opening_focus = _camera.focus
	_opening_distance = _camera._distance

	await _settle(45)
	# Phase 18: the session opens on the title card, and everything after this
	# assumes a live district -- so this runs, and lifts the card, first.
	await _test_the_game_opens_on_the_title()
	# Then, before anything is teleported: these are about the map as it ships,
	# seen from the view the game opens on.
	await _test_starting_units_are_clickable()
	await _test_the_map_opens_quiet()
	await _test_the_district_doubled_with_variety()
	await _test_parked_cars_wear_different_paints()
	await _test_the_district_is_dressed_from_a_wide_vocabulary()
	await _test_terraces_do_not_all_stand_the_same_height()
	await _test_the_appliance_is_a_real_appliance()
	await _test_the_fire_service_paint_is_warm()
	await _test_the_doctors_car_is_orange_and_carries_nobody()
	await _test_the_street_lights_ship_off()

	# Belt and braces: the map ships quiet now, but every incident test spawns what it
	# needs and cleans up after itself, so start from a provably empty street.
	await _clear_incidents()

	# The ambient population is exercised first and then removed. Everything after
	# this teleports the player's units around and clicks on them, and a taxi parked
	# between the camera and the car would quietly swallow that click.
	await _test_civilians_are_not_commandable()
	await _test_civilians_stroll()
	await _test_the_crowd_keeps_to_the_pavements()
	await _test_civilians_flee_a_fire()
	await _test_civilians_gather_at_a_collapse()
	await _test_the_crowd_comes_back()
	await _test_a_medical_call_takes_a_civilian()
	await _test_incident_figures_are_dressed()
	await _test_traffic_drives_the_roads()
	await _test_traffic_wears_different_paints()
	await _test_traffic_does_not_deadlock()
	await _test_traffic_does_not_drive_through_itself()
	await _test_traffic_gives_way_at_junctions()
	await _test_traffic_keeps_right()
	await _test_traffic_yields()
	await _test_traffic_turns_back_at_a_cordon()
	await _test_traffic_pulls_over_for_a_response()
	await _test_traffic_at_the_map_edge_does_not_pull_over_off_it()
	await _clear_ambient()

	await _test_left_turns_round_the_apex()
	await _test_starts_parked()
	await _test_drives_to_target()
	await _test_stops_on_arrival()
	await _test_turns_around_for_a_target_behind()
	await _test_crosses_the_map()
	await _test_routes_around_a_building()
	await _test_a_route_does_not_start_behind_the_car()
	await _test_a_shut_street_is_routed_around()
	await _test_a_clear_street_is_not_written_off()
	await _test_traffic_is_warned_in_time()
	await _test_crawling_behind_someone_counts_as_stuck()
	await _test_a_car_gives_up_on_a_blocked_street()
	await _test_queued_orders_are_drawn()
	await _test_a_group_move_spreads_out()
	await _test_the_interface_can_be_read()
	await _test_clickable_things_respond_to_the_pointer()
	await _test_command_tiles_say_what_they_do()
	await _test_a_stuck_unit_is_written_down()
	await _test_an_order_cannot_leave_the_map()
	await _test_a_knock_costs_money()
	await _test_the_station_repairs_what_comes_home()
	await _test_vehicles_slow_for_corners()
	await _test_rain_makes_the_road_slippery()
	await _test_fog_and_snow_are_weather_too()
	await _test_vehicles_keep_out_of_the_buildings()
	await _test_vehicles_cannot_drive_through_each_other()
	await _test_a_vehicle_thrown_off_the_map_comes_back()
	await _test_a_vehicle_drives_around_what_is_in_its_way()
	await _test_left_click_selects()
	await _test_clicking_ground_deselects()
	await _test_right_click_issues_order()
	await _test_order_ignored_with_no_selection()
	await _test_shift_right_click_queues()
	await _test_stop_cancels_orders()
	await _test_box_select()
	await _test_shift_click_adds()
	await _test_control_groups()
	await _test_hud_panels_hold_their_corners()
	await _test_bar_does_not_swallow_world_clicks()
	await _test_command_grid_follows_the_selection()
	await _test_command_hotkeys_run_abilities()
	await _test_roster_lists_everything_under_command()
	await _test_the_roster_groups_by_service()
	await _test_roster_marks_the_selection()
	await _test_roster_chip_selects_a_unit()
	await _test_portrait_names_the_lead()
	await _test_units_carry_a_service_and_a_portrait()
	await _test_the_interface_wears_the_icon_pack()
	await _test_streets_have_names()
	await _test_an_incident_opens_a_call()
	await _test_a_spreading_fire_stays_one_call()
	await _test_a_call_upgrades_when_the_scene_changes()
	await _test_the_board_draws_progress_as_a_bar()
	await _test_a_call_notices_a_unit_arriving()
	await _test_a_call_closes_when_its_incidents_do()
	await _test_a_lost_casualty_fails_its_call()
	await _test_clicking_a_call_moves_the_camera()
	await _test_the_radio_reports_what_happens()
	await _test_the_minimap_commands_camera_and_shift()
	await _test_the_move_marker_is_a_reticle()
	_test_the_map_zoom_buttons_work()
	await _test_the_score_strip_reads_and_pauses()
	await _test_person_walks()
	await _test_a_person_gets_round_a_parked_car()
	await _test_the_crowd_sidesteps_onto_pavement_only()
	await _test_person_animates()
	await _test_person_faces_travel()
	await _test_person_navmesh_is_tighter()
	await _test_clicking_a_person_selects()
	await _test_boarding()
	await _test_unload()
	await _test_seats_are_limited()
	await _test_the_navigation_overlay_is_off_until_asked()
	await _test_a_car_sent_off_the_road_climbs_the_kerb()
	await _test_a_narrow_street_u_turn_completes()
	await _test_a_routed_car_brakes_for_the_junction_turn()
	await _test_a_shut_street_is_passed_over_the_pavement()
	await _test_a_junction_queue_does_not_earn_the_pavement()
	await _test_siren_runs_while_responding()
	await _test_lights_switch_on_by_hand()
	await _test_siren_is_the_audio_and_separate()
	await _test_lights_and_siren_are_crew_switches()
	await _test_ambulance_doors_open_for_boarding()
	await _test_vehicles_without_doors_cope()
	await _test_idle_units_get_on_with_it()
	await _test_fire_grows_and_spreads()
	await _test_fire_resolves_to_extinguish()
	await _test_no_call_opens_inside_a_property()
	await _test_return_delivers_before_going_home()
	await _test_fire_spreads_only_where_a_crew_can_reach()
	await _test_right_clicking_a_crewed_vehicle_unloads_it()
	await _test_officer_extinguishes_a_fire()
	await _test_casualty_is_prone()
	await _test_casualty_declines()
	await _test_paramedic_treats_a_casualty()
	await _test_a_paramedic_holds_a_doctors_case_but_cannot_finish_it()
	await _test_a_doctor_stabilises_what_a_paramedic_cannot()
	await _test_a_collapse_is_only_offered_with_a_doctor_on_the_books()
	await _test_two_specialists_in_one_service_stay_told_apart()
	await _test_services_gate_their_verbs()
	await _test_an_officer_secures_a_scene()
	await _test_a_cordon_clears_the_public()
	await _test_a_career_buys_its_fleet()
	await _test_the_career_survives_reload()
	await _test_the_shop_previews_and_sells()
	await _test_dispatch_puts_a_unit_on_the_forecourt()
	await _test_dispatch_stops_when_the_yard_is_empty()
	await _test_returning_parks_on_the_forecourt()
	await _test_a_returning_vehicle_runs_dark_and_legal()
	await _test_a_u_turn_is_turned_not_routed()
	await _test_a_responding_vehicle_keeps_its_lane()
	await _test_a_returning_vehicle_keeps_its_lane()
	await _test_the_route_home_is_laid_out_in_lane()
	await _test_the_route_home_rounds_left_turns()
	await _test_work_order_survives_target_loss()
	await _test_transport_to_hospital()
	await _test_a_stretcher_reaches_where_wheels_cannot()
	await _test_mission_wins_when_everything_is_clear()
	await _test_mission_is_lost_when_a_casualty_dies()
	await _test_the_director_sleeps_until_started()
	await _test_the_director_opens_calls_where_they_belong()
	await _test_the_director_caps_simultaneous_calls()
	await _test_the_director_breathes_after_a_close()
	await _test_the_director_escalates_late_in_the_shift()
	await _test_an_rtc_reads_as_one_call()
	await _test_a_bus_collision_scales_to_the_medical_roster()
	await _test_a_bus_collision_grows_with_the_roster()
	await _test_a_vehicle_fire_burns_at_the_kerb()
	await _test_a_cylinder_cooks_off()
	await _test_a_cylinder_going_off_takes_the_street()
	await _test_a_hose_beats_a_cylinder()
	await _test_water_shows_where_it_is_landing()
	await _test_a_fire_wants_the_right_stuff_on_it()
	await _test_a_trapped_casualty_needs_cutting_free_first()
	await _test_a_shed_load_shuts_the_street()
	await _test_a_crew_clears_a_shed_load()
	await _test_calls_can_be_spawned_on_demand()
	await _test_a_cylinder_made_safe_finishes_the_job()
	await _test_a_disorder_call_grows_until_it_is_contained()
	await _test_a_patrol_car_takes_two_prisoners()
	await _test_a_crew_member_can_be_lost()
	await _test_a_passenger_is_not_caught_by_a_blast()
	await _test_fires_have_character()
	await _test_a_car_fire_scorches_what_is_near_it()
	await _test_a_fire_looks_like_its_intensity()
	await _test_the_appliance_raises_its_ladder()
	await _test_the_fire_service_fights_fires()
	await _test_building_fires_wait_for_a_fire_service()
	await _test_the_appliance_runs_on_water()
	await _test_the_district_makes_a_noise()
	await _test_the_interface_clicks()
	await _test_the_call_rate_is_a_setting()
	await _test_the_hour_is_a_setting()
	await _test_the_shift_rolls_its_own_weather()
	await _test_wet_weather_loads_the_table_with_collisions()
	await _test_vehicles_light_up_after_dark()
	await _test_a_rescue_needs_every_service()
	await _test_a_disturbance_lives_before_the_law()
	await _test_a_disturbance_is_arrested_and_delivered()
	await _test_a_drunk_call_can_be_just_a_collapse()
	await _test_a_drunk_call_can_turn_into_an_arrest()
	await _test_a_missing_child_call_stages_a_search()
	await _test_a_found_child_closes_the_call()
	await _test_the_missing_child_stays_out_of_other_calls()
	await _test_scoring_rewards_a_fast_response()
	await _test_a_slow_response_scores_at_the_floor()
	await _test_a_lost_casualty_costs_points_not_the_shift()
	await _test_the_shift_ends_with_a_summary()
	await _test_freeplay_key_starts_the_shift()
	await _test_the_best_score_survives()
	await _test_the_debrief_reads_as_a_table()
	await _test_a_shift_ends_even_with_an_unanswerable_call()
	await _test_pause_freezes_the_district()
	await _test_escape_closes_the_shop_before_it_pauses()
	await _test_the_speed_buttons_run_the_district_faster()
	await _test_the_menu_restarts_a_shift()
	await _test_settings_shape_the_shift_and_survive()
	await _test_quit_to_title_stands_the_shift_down()
	await _test_a_bad_shift_cannot_be_quit_away()
	await _test_a_scenario_plays_its_timeline()
	await _test_camera_pan_and_zoom()
	await _test_respawn()
	# Dead last, deliberately: it wipes the fleet the whole suite ran on.
	await _test_reset_career_starts_over()

	_finish()


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

func _test_civilians_are_not_commandable() -> void:
	var civilian := _first_civilian()
	if civilian == null:
		_check(false, "the map has a crowd on it")
		return
	_check(not civilian.is_selectable(), "a civilian is not selectable")
	_check(civilian.abilities().is_empty(),
		"and offers no abilities (%d)" % civilian.abilities().size())

	_controller.clear_selection()
	_camera.stop_following()

	# A civilian must not stop the picking ray, or one wandering between the camera and
	# an officer makes that officer unclickable. Checked against a full-mask query
	# first, so "the picking ray missed them" cannot pass by the camera simply being
	# aimed somewhere else.
	#
	# Which civilian is found by looking rather than assumed: the crowd is scattered
	# over the pavements, and whoever happens to be first may be stood against a wall
	# with a lamp post between them and the camera. Any one of them proves the point.
	var screen := Vector2.ZERO
	var aimed: Civilian = null
	for candidate in _civilians():
		_camera.focus = Vector3(
			candidate.global_position.x, 0.0, candidate.global_position.z)
		_camera._target_distance = 16.0
		await _idle(12)
		var at := _screen_of(candidate.global_position + Vector3.UP * 1.0)
		var from := _camera.project_ray_origin(at)
		var query := PhysicsRayQueryParameters3D.create(
			from, from + _camera.project_ray_normal(at) * 400.0)
		query.collide_with_areas = false
		if _scene.get_world_3d().direct_space_state.intersect_ray(query)\
				.get("collider") == candidate:
			aimed = candidate
			screen = at
			break

	_check(aimed != null, "found a civilian the camera has a clear line to")
	if aimed == null:
		return
	civilian = aimed
	_check(_controller._raycast(screen).get("collider") != civilian,
		"but the picking ray passes straight through them")

	await _click(MOUSE_BUTTON_LEFT, screen)
	_check(_controller.selection.is_empty(),
		"clicking a civilian selects nothing (%d selected)" % _controller.selection.size())


func _test_civilians_stroll() -> void:
	var crowd := _ambient("Crowd")
	if crowd.is_empty():
		_check(false, "the map has a crowd on it")
		return
	var before: Array[Vector3] = []
	for node in crowd:
		before.append((node as Node3D).global_position)

	await _wait(420)

	var moved := 0
	for i in crowd.size():
		if (crowd[i] as Node3D).global_position.distance_to(before[i]) > 1.0:
			moved += 1
	# Not all of them: strolling includes standing still for a few seconds, and some
	# of the crowd will be mid-pause for the whole sample.
	_check(moved >= crowd.size() / 2,
		"%d of %d civilians walked somewhere" % [moved, crowd.size()])


## Pedestrians belong on the pavement, and the only way across a road is the zebra.
## The graph is asserted directly, then the live crowd is sampled against it.
func _test_the_crowd_keeps_to_the_pavements() -> void:
	# A kerb tile beside a junction offers both painted crossings...
	var corner := Vector2i(23, 23)
	var moves := CityGrid.walk_moves(corner.x, corner.y)
	_check(moves.has(Vector2i(20, 23)) and moves.has(Vector2i(23, 20)),
		"a kerb tile by the junction offers both zebra crossings (%s)" % [moves])
	# ...and a kerb tile mid-block offers the ring and nothing over the road.
	var mid := CityGrid.walk_moves(23, 25)
	var jaywalk := false
	for move in mid:
		if CityGrid.block_of(move.x, move.y) != CityGrid.block_of(23, 25):
			jaywalk = true
	_check(not mid.is_empty() and not jaywalk,
		"a mid-block kerb offers the ring only -- jaywalking is not on the menu (%s)"
		% [mid])

	var crowd := _civilians()
	if crowd.is_empty():
		_check(false, "a crowd to watch")
		return
	var samples := 0
	var offside := 0
	for sweep in 120:
		await _wait(5)
		for civilian in crowd:
			if not is_instance_valid(civilian):
				continue
			samples += 1
			if not _pedestrian_legal(civilian.global_position):
				offside += 1
	_check(samples > 1000 and offside == 0,
		"the crowd kept to pavements and crossings (%d of %d samples offside)"
		% [offside, samples])


## True where a pedestrian is allowed to be: on a block, or on a road tile that
## carries a crossing. The inside of a junction box is nobody's.
func _pedestrian_legal(point: Vector3) -> bool:
	return CityGrid.walkable(
		int(floorf((point.x - CityGrid.ORIGIN) / CityGrid.TILE)),
		int(floorf((point.z - CityGrid.ORIGIN) / CityGrid.TILE)))


func _test_civilians_flee_a_fire() -> void:
	var civilian := _first_civilian()
	if civilian == null:
		_check(false, "the map has a crowd on it")
		return
	var spot := civilian.global_position
	var fire := _spawn_fire(spot + Vector3(4.0, 0.0, 0.0), 0.6)
	var start := _flat_distance(spot, fire.global_position)

	# Sampled while they are still running. Left any longer this reads false, because
	# by then they are clear of flee_radius and have gone back to strolling -- which
	# is correct behaviour and a misleading thing to assert on.
	await _wait(45)
	_check(civilian.is_fleeing, "a civilian beside a fire is running from it")

	# Fleeing follows the same pavement graph strolling does -- sampled while they
	# run, because a shopper sprinting through the carriageway has swapped one
	# incident for another.
	var offside := 0
	for i in 180:
		await physics_frame
		if is_instance_valid(civilian) \
				and not _pedestrian_legal(civilian.global_position):
			offside += 1
	_check(offside == 0,
		"they fled along the pavement, not through the road (%d frames offside)"
		% offside)
	var now := _flat_distance(civilian.global_position, fire.global_position)
	_check(now > start + 4.0,
		"and put %.1fm between them, up from %.1fm" % [now, start])

	await _clear_incidents()
	await _wait(40)
	_check(not civilian.is_fleeing, "and settles once the fire is out")


## The street dressing draws on the pack rather than on a handful of favourites.
##
## Reported from play as the district looking bland and reusing the same assets, and the
## count agreed: the generator named **22 of the 174 props the pack ships**, so the same
## bench and the same bin appeared down every street. Buildings were never the problem --
## those were already at 51 of 75 -- it was the street furniture, which is what a player
## actually looks at from the RTS camera.
##
## Counted off the **built scene**, not off the generator's tables, so it measures what was
## placed rather than what was listed. A name in a table that never survives a placement
## rule is exactly the sort of thing that would make a table-reading check lie.
func _test_the_district_is_dressed_from_a_wide_vocabulary() -> void:
	var props := {}
	for node in _scene.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		var path := batch.multimesh.mesh.resource_path
		if "SM_Prop_" in path:
			props[path] = true
	# 22 before the widening, 45 after. A floor between the two, nearer the new figure, so
	# this fails if the vocabulary is narrowed again without failing on one prop moving.
	_check(props.size() >= 35,
		"the district places a wide spread of props (%d distinct)" % props.size())


## And the terraces are not all one height per kind.
##
## The other half of "too much of a grid". Every block of a kind used to stand at exactly
## its kit's height -- twenty-one terraces sharing **three** silhouettes, in rows -- which
## reads as a lattice from above however irregular the block spacing is.
##
## Measured off the colliders rather than the facades on purpose: the collider is the thing
## that must agree with what was built, and reading it here means this check also fails if
## the two ever drift apart. The two blocks with a forecourt are excluded from the variation
## at source and stay at kit height, because raising the station wall put it between the
## opening camera and every unit parked on its own apron.
func _test_terraces_do_not_all_stand_the_same_height() -> void:
	var heights := {}
	var buildings := _scene.get_node_or_null("World/Buildings")
	if buildings == null:
		_check(false, "the map has a Buildings node to measure")
		return
	for node in buildings.get_children():
		if not String(node.name).begins_with("Block_"):
			continue
		var body := node as StaticBody3D
		var shape := body.get_node_or_null("Shape") as CollisionShape3D
		var box := shape.shape as BoxShape3D if shape else null
		if box == null:
			continue
		heights[snappedf(box.size.y, 0.01)] = true
	# Two of the twenty-one blocks are round towers on a CylinderShape3D and are skipped
	# here by construction. Note for anyone sabotaging this: flattening the colliders also
	# reddens the prisoner-loading scenario, which walks suspects through that geometry --
	# that is a real consequence of moving thirteen building walls, not a check reaching
	# too far. Collapsing only the singleton heights isolates it if you want one red.
	_check(heights.size() >= 6,
		"terraces stand at a spread of heights (%d distinct across %d blocks)"
			% [heights.size(), buildings.get_child_count()])


## The district's cars are not all blue. The pack paints every body off one atlas
## palette; the generator folds parked cars through the alt palettes -- each colour
## its own batch -- and the ambient fleet repaints itself at spawn.
func _test_parked_cars_wear_different_paints() -> void:
	var paints := {}
	var car_batches := 0
	for node in _scene.find_children("*", "MultiMeshInstance3D", true, false):
		var batch := node as MultiMeshInstance3D
		if batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		if "Veh_Car" not in batch.multimesh.mesh.resource_path:
			continue
		car_batches += 1
		if batch.material_override:
			paints[batch.material_override.resource_path] = true
	_check(car_batches > 0, "the lots hold batched parked cars (%d batches)" % car_batches)
	var alts := 0
	for path in paints:
		if "Alts/" in str(path):
			alts += 1
	_check(paints.size() >= 3 and alts >= 2,
		"parked in %d paints, %d off the alt palettes -- not a wall of blue"
		% [paints.size(), alts])


## The appliance is the van, not the patrol car it used to borrow.
##
## Measured off the generated scene rather than read off the config, because the map
## bakes each instanced vehicle's properties -- regenerating build_vehicles.gd alone
## has silently changed nothing before, and the file on disk looked right the whole
## time. Wheelbase is the sharpest single number: 4.46 on the appliance against 2.88 on
## the patrol car.
##
## This checked for the *van's rear doors* until August 2026, which was the right proof
## while the appliance was a van in orange paint. The real appliance has no separate
## doors, so that assertion had to go with the placeholder it pinned -- and what
## replaces it is the thing a fire engine has that nothing else on the map does.
func _test_the_appliance_is_a_real_appliance() -> void:
	var engine := (load("res://Game/Vehicles/FireEngine.tscn") as PackedScene).instantiate()
	var patrol := (load("res://Game/Vehicles/PoliceCar.tscn") as PackedScene).instantiate()
	var engine_base := (engine as Vehicle).wheelbase
	var patrol_base := (patrol as Vehicle).wheelbase
	_check(engine_base > patrol_base + 0.3,
		"the appliance rides a longer wheelbase than a patrol car (%.2f vs %.2f)"
		% [engine_base, patrol_base])
	# A ladder, which is proof of the body underneath in a way no dimension is: no other
	# prefab in any pack on disk has one, so this fails the moment `prefab` points
	# somewhere else.
	var ladder := 0
	for part in engine.find_children("*Ladder*", "Node3D", true, false):
		ladder += 1
	_check(ladder >= 2, "and carries a ladder, which no other body on the map has (%d parts)"
		% ladder)
	# Bulk, from the collider the generator sized off the hull. The appliance is the
	# largest thing the player drives and it should not be quietly swapped for a car.
	var box := (engine.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	var car := (patrol.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	_check(box.size.z > car.size.z * 1.4 and box.size.y > car.size.y * 1.4,
		"and is a size no car is (%.1f x %.1f against %.1f x %.1f)"
		% [box.size.z, box.size.y, car.size.z, car.size.y])
	# **Crew get out behind it, not inside it.** `dismount_back` was a fixed 3.2 that
	# suited a 5m van, and on an 8.8m body it put four firefighters a metre inside the
	# truck. Nothing caught it: a vehicle is a CharacterBody3D, so it is absent from the
	# baked navigation the dismount point snaps to, and the crew simply appeared in the
	# bodywork. It is derived from the hull now, and this is the number that says so.
	var shape := engine.get_node("Collision") as CollisionShape3D
	var tail: float = box.size.z * 0.5 + shape.position.z
	_check(engine.dismount_back > tail + 0.5,
		"and turns its crew out behind itself, not inside it (%.1fm back, tail at %.1fm)"
		% [engine.dismount_back, tail])
	engine.free()
	patrol.free()


## The **repainted** half of the fire service reads warm.
##
## The check that would have caught the two colour bugs this project has shipped. An
## alt palette is a texture atlas, not a colour: a mesh's UVs choose the swatch, so
## naming a material proves nothing about what comes out. 04_A is genuinely orange on
## the patrol car's hull, charcoal on the van's, and olive on the crew -- the appliance
## shipped black and the fire crew shipped green, and every existing check passed.
##
## **The appliance left this test in August 2026 when it stopped being a repaint.** It is
## now a purpose-built fire engine wearing its own texture, and this measure cannot say
## anything useful about it: averaged over its own UVs a red-and-white livery reads
## +0.03, under the bar, while a yellow taxi reads warmer than either. Averages are the
## wrong question for two-tone bodywork. What guards the appliance instead is
## `_test_the_appliance_is_a_real_appliance`, which pins the body itself rather than its
## colour. The firefighter is still a repainted police model, so the fault this was
## written for is still live for them, and here it stays.
func _test_the_fire_service_paint_is_warm() -> void:
	for subject in [
		{"scene": "res://Game/Firefighter.tscn", "what": "firefighter"},
	]:
		var node := (load(str(subject["scene"])) as PackedScene).instantiate()
		var mesh := _body_mesh(node)
		if mesh == null:
			_check(false, "%s has a body mesh to sample" % subject["what"])
			node.free()
			continue
		var warmth := _paint_warmth(mesh)
		# Red has to lead **both** other channels, which is what separates a warm coat
		# from the two things that have actually shipped here. Red-minus-blue alone
		# does not: the olive crew scored +0.09 on it, a hair under the charcoal van's
		# failing -0.01 and a hair over nothing. Against min(r-g, r-b) the same three
		# read -0.02 charcoal, 0.00 olive, and +0.08 / +0.14 for the palette in use --
		# a gap wide enough to put a threshold in the middle of.
		_check(warmth > 0.05,
			"the %s's paint reads warm, not charcoal or olive (min(r-g,r-b) %+.2f)"
			% [subject["what"], warmth])
		node.free()


## The doctor's car wears its own paint and cannot do the ambulance's job.
##
## **Sampled off the built scene, never taken from the palette name.** An alt palette is a
## texture atlas rather than a colour, so the same swatch is orange on this hull, flat
## charcoal on the van and olive on a person -- picking by name once shipped a black fire
## engine and dressed the firefighter in green for months. The only honest test is to read
## the pixels the mesh's own UVs land on, which is what [method _paint_warmth] does.
##
## The second half is a design constraint rather than a cosmetic one, and it is the more
## important of the two: give this car a stretcher and it quietly becomes a second
## ambulance, the patient never waits, and the bottleneck the doctor exists to be is gone.
func _test_the_doctors_car_is_orange_and_carries_nobody() -> void:
	var car := (load("res://Game/Vehicles/DoctorCar.tscn") as PackedScene).instantiate()
	var mesh := _body_mesh(car)
	if mesh == null:
		_check(false, "the doctor's car has a body mesh to sample")
		car.free()
		return
	var warmth := _paint_warmth(mesh)
	# The same bar the fire service's paint clears, and set in the same place: measured,
	# charcoal reads -0.02 and olive 0.00 on this scale, so 0.05 sits clear of both.
	_check(warmth > 0.05,
		"the doctor's car is painted warm, not the patrol car's blue (min(r-g,r-b) %+.2f)"
			% warmth)

	var vehicle := car as Vehicle
	_check(vehicle != null and vehicle.service == Unit.Service.MEDICAL,
		"it is a medical vehicle")
	_check(vehicle != null and vehicle.stretchers == 0,
		"and carries no stretcher, so it cannot do the ambulance's job (%d)"
			% (vehicle.stretchers if vehicle else -1))
	_check(vehicle != null and not vehicle.has_stretcher_space(),
		"which Collect reads straight off, so it is never offered one")
	# Faster than the ambulance, which is the entire point of a response car.
	var ambulance := (load("res://Game/Vehicles/Ambulance.tscn") as PackedScene).instantiate()
	_check(vehicle != null and vehicle.max_speed > (ambulance as Vehicle).max_speed,
		"and gets there quicker than the ambulance (%.0f vs %.0f)"
			% [vehicle.max_speed if vehicle else 0.0, (ambulance as Vehicle).max_speed])
	ambulance.free()
	car.free()


## The bodywork: the largest textured mesh under [param root].
##
## Picked by size rather than by node path so this works on a vehicle and on a person
## without knowing either layout. Requiring an albedo is what keeps it off the
## selection ring, which is a MeshInstance3D with a flat colour and would otherwise be
## found first on a character and sampled as "no paint at all".
func _body_mesh(root: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var most := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
			continue
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		if uvs.size() > most:
			most = uvs.size()
			best = mesh
	return best


## How far red leads the other two channels in a mesh's albedo, sampled at the mesh's
## own UVs: min(r-g, r-b), averaged. Positive is warm; olive and grey both land at or
## below zero. Returns -1.0 when there is nothing to sample, which fails the check that
## asks rather than passing it by default.
func _paint_warmth(mesh: MeshInstance3D) -> float:
	var material := mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		return -1.0
	var image := material.albedo_texture.get_image()
	if image == null:
		return -1.0
	# The imported atlases are VRAM-compressed; get_pixel needs them raw.
	if image.is_compressed():
		image.decompress()
	var arrays := mesh.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return -1.0
	var sum := Color(0, 0, 0)
	var taken := 0
	# Every 7th: enough to characterise a body, cheap enough to run in the suite.
	for i in range(0, uvs.size(), 7):
		var uv := uvs[i]
		sum += image.get_pixel(
			int(clampf(uv.x, 0.0, 0.999) * image.get_width()),
			int(clampf(uv.y, 0.0, 0.999) * image.get_height()))
		taken += 1
	if taken == 0:
		return -1.0
	var mean := sum / float(taken)
	return minf(mean.r - mean.g, mean.r - mean.b)


## The street lighting ships **dark**.
##
## Same rule the director follows: the map is quiet until asked. A hundred omni lights
## burning at midday washes the pavements out, and Daylight.gd owns the switch -- so
## the container is what must be off, not each lamp.
func _test_the_street_lights_ship_off() -> void:
	var lights := _scene.get_node_or_null("StreetLights") as Node3D
	_check(lights != null, "the district ships street lighting")
	if lights == null:
		return
	var lamps := lights.find_children("*", "OmniLight3D", true, false)
	_check(lamps.size() >= 20,
		"one light under every lamp standard the kerb draw put down (%d)" % lamps.size())
	_check(not lights.visible, "and it ships off, so noon is not lit by streetlight")


func _test_traffic_wears_different_paints() -> void:
	var paints := {}
	for node in _ambient("Traffic"):
		var car := node as TrafficCar
		if car == null:
			continue
		var coat := "stock"
		for part in car.find_children("*", "MeshInstance3D", true, false):
			var body := part as MeshInstance3D
			if body.mesh == null:
				continue
			for i in body.mesh.get_surface_count():
				var override := body.get_surface_override_material(i)
				if override and "Alts/" in override.resource_path:
					coat = override.resource_path
		paints[coat] = true
	_check(paints.size() >= 3,
		"the ambient fleet drives %d different paint jobs" % paints.size())


## A body on the pavement draws a crowd. Nearby civilians walk the pavement graph in
## and stand at a respectful distance -- close enough to gawp, never on top of the
## scene -- and go back to their day once it is cleared away.
func _test_civilians_gather_at_a_collapse() -> void:
	var crowd := _civilians()
	if crowd.is_empty():
		_check(false, "the map has a crowd on it")
		return

	# A pavement point with several civilians in gawping range but none already on
	# top of it, so the gather has to be walked rather than inherited.
	var spot := Vector3.INF
	var most := 0
	for point in CityGrid.pavement_points():
		var near := 0
		var clear := true
		for civilian in crowd:
			var away := _flat_distance(civilian.global_position, point)
			if away < 8.0:
				clear = false
			elif away < civilian.watch_radius - 1.0:
				near += 1
		if clear and near > most:
			most = near
			spot = point
	if spot == Vector3.INF:
		_check(false, "a pavement point with civilians in range")
		return

	var casualty := _spawn_casualty(spot)
	var came_over := false
	var legal := true
	for i in 900:
		await physics_frame
		for civilian in crowd:
			if not is_instance_valid(civilian) or not civilian.is_watching:
				continue
			if not _pedestrian_legal(civilian.global_position):
				legal = false
			if _flat_distance(civilian.global_position, spot) \
					<= civilian.watch_near + 2.0:
				came_over = true
		if came_over:
			break
	_check(came_over, "a civilian came over to watch the collapse")
	_check(legal, "every onlooker stayed on the pedestrian graph")

	# Let the gathering settle before measuring the standoff, or a crowd still
	# converging is measured mid-stride.
	await _wait(60)
	var on_top := false
	for civilian in crowd:
		if is_instance_valid(civilian) and civilian.is_watching \
				and _flat_distance(civilian.global_position, spot) < 1.5:
			on_top = true
	_check(not on_top, "and nobody is standing on the casualty")

	casualty.queue_free()
	await _wait(40)
	var still_watching := false
	for civilian in crowd:
		if is_instance_valid(civilian) and civilian.is_watching:
			still_watching = true
	_check(not still_watching, "the crowd disperses once the scene is cleared")
	await _clear_calls()


## A freeplay medical call takes a *civilian*: the director swaps a crowd member for
## a casualty where they stood, so the collapse is somebody who was just there --
## and only falls back to thin air when nobody qualifies.
## The district refills as it empties.
##
## Every medical call takes a shopper permanently, and nothing replaced them until August
## 2026: a long career quietly emptied the pavements, and once empty the call had nobody
## left to take and fell back to conjuring a casualty from thin air -- the very thing
## taking a civilian exists to avoid.
func _test_the_crowd_comes_back() -> void:
	var refill := _scene.get_node_or_null("CrowdRefill") as CrowdRefill
	if refill == null:
		_check(false, "the map carries a CrowdRefill")
		return
	_check(refill.target > 0, "it knows how many people the district holds (%d)"
		% refill.target)
	_check(not refill._outfits.is_empty(),
		"and what they are dressed in (%d outfits)" % refill._outfits.size())

	# Take a dozen off the pavements, the way a run of medical calls would.
	var crowd := _civilians()
	var taken := mini(12, crowd.size())
	for i in taken:
		crowd[i].queue_free()
	await _idle(4)
	var thinned := _civilians().size()
	_check(thinned == crowd.size() - taken,
		"a run of calls thins the crowd (%d -> %d)" % [crowd.size(), thinned])

	# Hurried along, because the arrival gap is half a minute of real play.
	refill.every = 0.05
	var before := refill.arrivals
	await _wait(120)
	_check(refill.arrivals > before,
		"and people come back to it (%d arrivals)" % [refill.arrivals - before])
	_check(_civilians().size() > thinned,
		"so the pavements refill (%d -> %d)" % [thinned, _civilians().size()])
	# Never past what the district was built to hold.
	_check(_civilians().size() <= refill.target,
		"and never past what it was built to hold (%d of %d)"
		% [_civilians().size(), refill.target])
	refill.every = 30.0
	await _idle(4)


func _test_a_medical_call_takes_a_civilian() -> void:
	await _clear_calls()
	var before := _civilians()
	if before.is_empty():
		_check(false, "a crowd for the director to draw on")
		return
	var stood_at: Array[Vector3] = []
	for civilian in before:
		stood_at.append(civilian.global_position)

	_director._spawn_medical()
	await _idle(6)
	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	_check(bodies.size() == 1, "the call put one casualty on the map (%d)" % bodies.size())
	var after := _civilians().size()
	_check(after == before.size() - 1,
		"and the crowd is one lighter (%d -> %d)" % [before.size(), after])
	if bodies.size() == 1:
		var body := bodies[0] as Casualty
		var matched := false
		for point in stood_at:
			if _flat_distance(point, body.global_position) < 0.5:
				matched = true
		_check(matched, "the body lies where the civilian stood")
	await _clear_calls()

	# Nobody eligible -- everybody mid-flight -- and the call must still open.
	for civilian in _civilians():
		civilian.is_fleeing = true
	_director._spawn_medical()
	await _idle(6)
	var fallback := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	var untouched := _civilians().size()
	_check(fallback == 1 and untouched == after,
		"with nobody eligible it falls back to the pavement (%d body, crowd %d)"
		% [fallback, untouched])
	for civilian in _civilians():
		civilian.is_fleeing = false
	await _clear_calls()


func _test_traffic_drives_the_roads() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return
	var before: Array[Vector3] = []
	for node in traffic:
		before.append((node as Node3D).global_position)

	await _wait(300)

	var moved := 0
	var on_road := 0
	# **Say which ones, and why.** A bare count tells you two cars did not get going and
	# nothing else, which is a poor thing to hand whoever has to find out why -- and this
	# check has failed at exactly 20 of 22 while every neighbouring one passed. Naming
	# them, with how far they got and whether they were waiting for somebody, costs a
	# string and turns a shrug into a lead.
	var stalled: Array[String] = []
	var gaps: Array[float] = []
	for i in traffic.size():
		var car := traffic[i] as Vehicle
		var here: Vector3 = car.global_position
		var gap := here.distance_to(before[i])
		gaps.append(gap)
		if gap > 3.0:
			moved += 1
		else:
			stalled.append("%s %.1fm at (%.0f,%.0f) held=%.1fs speed=%.1f yielding=%s"
				% [car.name, gap, here.x, here.z, car.held_up_for(), car.forward_speed,
					car.get("is_yielding")])
		if _on_a_road(here):
			on_road += 1
	# The three shortest hops, always -- not only when it fails. The bar is 3m of net
	# displacement in five seconds, and knowing whether the fleet clears it by a metre or
	# by twenty is the difference between a real stall and a threshold sitting on a cliff.
	gaps.sort()
	var tightest := ""
	for i in mini(3, gaps.size()):
		tightest += "%s%.1f" % ["" if i == 0 else "/", gaps[i]]
	_check(moved >= traffic.size() - 1,
		"%d of %d traffic cars drove off (shortest hops %s)%s"
		% [moved, traffic.size(), tightest,
			"" if stalled.is_empty() else " -- " + "; ".join(stalled)])
	# The whole point of routing them by CityGrid rather than by random navigation
	# mesh points: they keep to the streets and to their own side of them.
	_check(on_road == traffic.size(),
		"%d of %d were still on a road" % [on_road, traffic.size()])


func _test_traffic_does_not_deadlock() -> void:
	# Long enough for every car to have reached a junction and turned. The failure
	# this catches is silent and total: two cars meeting at a crossroads each held the
	# other in their forward cone, both stopped, and the whole district's traffic
	# queued up behind them and never moved again. Sampled over the *second* half of
	# the run, because a car briefly stopped at a junction is fine.
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return

	await _wait(900)
	var before: Array[Vector3] = []
	for node in traffic:
		before.append((node as Node3D).global_position)
	await _wait(600)

	var stuck := PackedStringArray()
	for i in traffic.size():
		var car := traffic[i] as TrafficCar
		if car.global_position.distance_to(before[i]) < 2.0:
			stuck.append("%s (yielding=%s)" % [car.name, car.is_yielding])
	_check(stuck.is_empty(), "all %d cars were still moving after 25s%s" % [
		traffic.size(),
		"" if stuck.is_empty() else " -- stalled: " + ", ".join(stuck)])


## Vehicles are solid to one another. Measured rather than assumed, because the
## failure is invisible from the code: two cars sharing a point look like one car
## until you watch the centres. Before they were given collision the closest pair
## in a 15-second sample was 0.16m -- one car inside another.
func _test_traffic_does_not_drive_through_itself() -> void:
	var traffic := _ambient("Traffic")
	if traffic.size() < 6:
		_check(false, "a fleet to watch (%d)" % traffic.size())
		return

	var worst := INF
	var sunk := PackedStringArray()
	for frame in 600:
		await physics_frame
		for a in traffic.size():
			var one := traffic[a] as Node3D
			if one.global_position.y < -2.0 and sunk.find(one.name) < 0:
				sunk.append(one.name)
			for b in range(a + 1, traffic.size()):
				var two := traffic[b] as Node3D
				worst = minf(worst, _flat_distance(one.global_position,
					two.global_position))
	# A body is 1.9m wide and up to 5.6m long, so centres this close are
	# interpenetrating whatever the relative heading.
	_check(worst > 2.2,
		"no two cars ever shared the same space (closest pair %.2fm)" % worst)
	# The other half of solid: two cars laid down inside each other are flung apart
	# by the physics engine, and one of them left the world at 600 metres down.
	_check(sunk.is_empty(), "and none was ejected out of the world%s"
		% ("" if sunk.is_empty() else " -- lost: " + ", ".join(sunk)))


## Traffic gives way at the crossroads, and does it in a **strict order**: of two
## cars converging on the same junction, the nearer takes it and the farther waits.
## The follow rule cannot do this -- it deliberately only sees traffic going the same
## way -- so without this the two would drive into each other now they are solid, and
## a rule where both waited would lock the district instead.
##
## Staged with two cars of its own at a junction the ambient fleet is nowhere near,
## because the property being asserted is about exactly two cars.
func _test_traffic_gives_way_at_junctions() -> void:
	# An interior junction -- both approach streets have to exist -- that the ambient
	# fleet is nowhere near, so the only two cars in the rule are the staged ones.
	var cell := Vector2i(-1, -1)
	for x in range(1, CityGrid.BANDS - 1):
		for z in range(1, CityGrid.BANDS - 1):
			if cell.x >= 0:
				break
			var centre := CityGrid.junction(Vector2i(x, z))
			var quiet := true
			for node in _ambient("Traffic"):
				if _flat_distance((node as Node3D).global_position, centre) < 26.0:
					quiet = false
			if quiet:
				cell = Vector2i(x, z)
	if cell.x < 0:
		_check(false, "a junction with no ambient traffic near it")
		return

	var centre := CityGrid.junction(cell)
	var packed := load("res://Game/Traffic/Sedan.tscn") as PackedScene
	var near := packed.instantiate() as TrafficCar
	var far := packed.instantiate() as TrafficCar
	_scene.add_child(near)
	_scene.add_child(far)
	# Converging: one from the west 7m out, one from the south 12m out. Each is
	# re-anchored onto the leg it is driving -- a TrafficCar picks its route in
	# _ready, at whatever position it had then, which is the origin here.
	near.global_position = centre + Vector3(-7.0, 0.2, CityGrid.LANE_OFFSET)
	near.global_rotation = Vector3(0.0, -PI * 0.5, 0.0)
	near._from = Vector2i(cell.x - 1, cell.y)
	near._to = cell
	near._begin_leg()
	far.global_position = centre + Vector3(-CityGrid.LANE_OFFSET, 0.2, 12.0)
	far.global_rotation = Vector3(0.0, PI, 0.0)
	far._from = Vector2i(cell.x, cell.y + 1)
	far._to = cell
	far._begin_leg()
	await _idle(4)

	_check(not near._junction_taken(),
		"the car nearest the crossroads takes it")
	_check(far._junction_taken(),
		"and the one further out gives way rather than meeting it in the middle")

	# Both must eventually get through: a rule where each waited for the other is
	# the deadlock that kept these cars intangible for months.
	var closest := INF
	for i in 900:
		await physics_frame
		closest = minf(closest, _flat_distance(near.global_position,
			far.global_position))
	_check(closest > 2.2,
		"and they never met in the box (closest %.1fm)" % closest)
	_check(_flat_distance(near.global_position, centre) > 9.0
			and _flat_distance(far.global_position, centre) > 9.0,
		"with both clear of the junction afterwards")

	near.queue_free()
	far.queue_free()
	await _idle(4)


func _test_traffic_keeps_right() -> void:
	# Sampled repeatedly rather than once, because the failure being watched for is a
	# car swinging wide through the oncoming lane mid-turn -- which a single snapshot
	# would almost always miss. Cars inside a junction are skipped: there is no lane
	# there, which is the whole reason a junction is a junction.
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return

	var wrong_side := 0
	var samples := 0
	for sweep in 24:
		await _wait(25)
		for node in traffic:
			var car := node as TrafficCar
			var here := car.global_position
			var across := _lane_offset(here)
			if across == Vector3.ZERO:
				continue  # in a junction, or off the grid
			var right := (-car.global_basis.z).cross(Vector3.UP)
			right.y = 0.0
			if right.length() < 0.01:
				continue
			samples += 1
			# A car is 2.2m wide and a lane 5m, so a metre the wrong side of the line
			# is a wheel over it rather than a car in the oncoming lane.
			if across.dot(right.normalized()) < -1.0:
				wrong_side += 1
	_check(samples > 100, "sampled traffic on open road %d times" % samples)
	_check(wrong_side * 20 < samples,
		"traffic held its own side of the road: %d of %d samples over the line"
		% [wrong_side, samples])


## True where "which side of the road" is a question with an answer: on a street, and
## clear of the station.
##
## Junctions are already excluded by [method _lane_offset] -- there is no lane inside
## one. The forecourt is excluded here because turning into it means crossing the
## oncoming lane, which is what turning into anything on the far side of a road means,
## and counting it would be measuring the manoeuvre rather than the driving.
##
## Turn *arcs* reach past the junction box and are deliberately left in. They are the
## reason the wrong-side count is a few percent rather than zero, and excluding them
## too made the check pass whether or not the route was in lane at all.
func _on_open_street(point: Vector3) -> bool:
	if _lane_offset(point) == Vector3.ZERO:
		return false
	return _station == null or _flat_distance(point, _station.global_position) > 20.0


## Offset from the centre line of the road band a point is on, or zero if it is in a
## junction (both axes in a band) or off the grid entirely.
func _lane_offset(point: Vector3) -> Vector3:
	var in_x := _in_band_x(point.x)
	var in_z := _in_band_z(point.z)
	if in_x == in_z:
		return Vector3.ZERO
	if in_x:
		return Vector3(
			point.x - CityGrid.band_centre_x(CityGrid.band_at_x(point.x)), 0.0, 0.0)
	return Vector3(
		0.0, 0.0, point.z - CityGrid.band_centre_z(CityGrid.band_at_z(point.z)))


func _test_traffic_yields() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "the map has traffic on it")
		return
	var car := traffic[0] as TrafficCar
	# The rest of the traffic is removed first, so the only thing that can be in front
	# of this one is the car the test puts there. Otherwise it depends on where nine
	# independently-driving cars happen to be, which is not a property worth asserting.
	for i in range(1, traffic.size()):
		traffic[i].queue_free()
	await _wait(10)
	_check(not car.is_yielding, "traffic with a clear road ahead is not yielding")

	# Park the patrol car directly in its path. Traffic does not physically block the
	# player, so this has to be caught by the driver rather than by a collision.
	await _place_unit(_car, car.global_position - car.global_basis.z * 5.0)
	await _wait(20)
	_check(car.is_yielding, "and waits for a vehicle stopped in front of it")

	await _place_unit(_car, ROAD)
	await _wait(30)
	_check(not car.is_yielding, "then moves off once the road is clear")


## Blues coming through: a driving response makes traffic tuck in at the kerb and
## stop, then rejoin the lane once it has passed. The yield test above already
## thinned the traffic to one car, which is exactly what this needs.
## Traffic waits behind one of ours, and turns back when police close the road.
##
## Two halves of the same complaint. A car queued behind a stopped unit should wait — it
## already does — but a car queued into a **cordon** is waiting for something that will
## never move, and the cones are visual, so nothing stopped it driving in and sitting
## there. An officer closing a street is an instruction, and until now only the crowd
## listened to it.
func _test_traffic_turns_back_at_a_cordon() -> void:
	await _clear_incidents()
	var lane := CityGrid.LANE_OFFSET
	var street := CityGrid.band_centre_z(2)
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	await _idle(4)

	# Heading east down an open street: it keeps going.
	taxi.global_position = Vector3(-40.0, 0.2, street + lane)
	taxi.rotation.y = -PI * 0.5
	taxi._cordon_cooldown = 0.0
	await _idle(30)
	var open_start := taxi.global_position.x
	await _wait(180)
	_check(taxi.global_position.x > open_start + 4.0,
		"traffic drives on down an open street (%.1fm)"
		% (taxi.global_position.x - open_start))

	# Now close it in front of them.
	# Built in code, not from a scene: SecureOrder makes one the same way, and there is no
	# Cordon.tscn to load.
	var cordon := Cordon.new()
	_scene.add_child(cordon)
	cordon.global_position = Vector3(taxi.global_position.x + 40.0, 0.0, street)
	cordon.raise_cordon()
	taxi._cordon_cooldown = 0.0
	var was_east := -taxi.global_basis.z
	# **Does it leave, and does it stay out?** Not "how far past the cones did it get":
	# the car can pass the cordon, turn, and be back near it inside one sampling window,
	# and an assertion on a single distance reads that as driving into the closure. What
	# matters is that it turns away and is not still sitting there.
	var nearest_after := INF
	var last_gap := 0.0
	for sweep in 420:
		await physics_frame
		last_gap = _flat_distance(taxi.global_position, cordon.global_position)
		nearest_after = minf(nearest_after, last_gap)
	var now_facing := -taxi.global_basis.z
	_check(now_facing.dot(was_east) < 0.3,
		"a raised cordon turns it round (heading dot %.2f)" % now_facing.dot(was_east))
	_check(nearest_after > cordon.radius,
		"without driving into the cones (closest %.1fm, ring is %.1fm)"
		% [nearest_after, cordon.radius])
	_check(last_gap > cordon.radius * 2.0,
		"and it has left rather than queued at them (%.1fm away)" % last_gap)
	_check(_on_a_road(taxi.global_position),
		"and it is still on the road afterwards (%.1f, %.1f)"
		% [taxi.global_position.x, taxi.global_position.z])

	cordon.queue_free()
	taxi.queue_free()
	await _clear_incidents()
	await _idle(6)


## A car with no district left in front of it declines the tuck rather than aiming past
## the edge of the world.
##
## Reported from play, once, as a warning with a stack trace: `Traffic3 was sent off the map,
## to (-86.2, 0.0, -131.0)` on a district that ends at 130. The tuck aims seven metres ahead
## plus a couple across, and near an edge that lands outside. `Vehicle.navigate_to` caught it
## and clamped -- which is that guard doing exactly its job -- but clamping aims the car at
## the boundary rather than at a kerb, so it performs a tuck towards nothing.
##
## **The second half is the important half.** Asserting only that an edge car does not pull
## over would pass just as happily if the manoeuvre were broken everywhere, which is the
## commonest way a check here turns out to be worth nothing. So the same car, at the same
## moment, with the same responder, is then moved into open district and must pull over.
func _test_traffic_at_the_map_edge_does_not_pull_over_off_it() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "a traffic car to place at the edge")
		return
	var car := traffic[0] as TrafficCar
	car._tuck_cooldown = 0.0

	# Nose to the southern boundary with less than a tuck's length in front of it. The
	# manoeuvre reaches 7m ahead and 2.2m across, so 3m of district cannot contain it.
	var edge := CityGrid.MAP_HALF
	var outward := Vector3(0.0, 0.0, -1.0)
	var facing := atan2(-outward.x, -outward.z)
	await _place_unit(car, Vector3(-86.0, 0.1, -(edge - 3.0)), facing)
	await _place_unit(_car, car.global_position - outward * 6.0, facing)
	_car.lights_on = true
	await _wait(20)

	_check(not car.is_pulled_over,
		"a car three metres from the boundary does not pull over")
	var aim := car.move_target
	_check(absf(aim.x) <= edge and absf(aim.z) <= edge,
		"and is not aiming off the map (%.0f, %.0f of +/-%.0f)" % [aim.x, aim.z, edge])

	# The control: same car, same responder, room to do it. Without this the two checks
	# above would be green on a pull-over that never fires at all.
	var from := Vector2i(2, 2)
	var to := Vector2i(2, 3)
	var start := CityGrid.junction(from)
	var finish := CityGrid.junction(to)
	var direction := start.direction_to(finish)
	var lane := direction.cross(Vector3.UP) * CityGrid.LANE_OFFSET
	car._tuck_cooldown = 0.0
	await _place_unit(car, start.lerp(finish, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	await _place_unit(_car, start.lerp(finish, 0.15) + lane,
		atan2(-direction.x, -direction.z))
	_car.navigate_to(finish + direction * 25.0)
	var tucked := false
	for i in 600:
		await physics_frame
		if car.is_pulled_over:
			tucked = true
			break
	_check(tucked, "but the same car in open district still pulls over")
	# **Put back everything this disturbed, and `clear_orders` is not enough.** Two things
	# leaked out of the first cut of this check and cost thirteen reds in unrelated places:
	# `navigate_to` is not an order, so `clear_orders()` leaves the car still driving at a
	# point 25m past a junction and the next navigation check finds it already under way;
	# and the manual lightbar switch thrown above stays thrown, so every later check that
	# asserts a dark bar reads a lit one. The suite has no teardown -- what a check touches,
	# it hands back.
	_car.stop_navigating()
	_car.clear_orders()
	_car.lights_on = false
	car._release_tuck()
	car._tuck_cooldown = 0.0
	await _park_the_shift()


func _test_traffic_pulls_over_for_a_response() -> void:
	var traffic := _ambient("Traffic")
	if traffic.is_empty():
		_check(false, "a traffic car to pull over")
		return
	var car := traffic[0] as TrafficCar

	# Stage a long straight leg: the taxi ahead in lane, the patrol car well behind
	# it -- outside the pull-over radius, so the manoeuvre is provoked by the
	# approach rather than by the placement.
	var from := Vector2i(2, 2)
	var to := Vector2i(2, 3)
	var start := CityGrid.junction(from)
	var end := CityGrid.junction(to)
	var direction := (start.direction_to(end))
	var lane := direction.cross(Vector3.UP) * CityGrid.LANE_OFFSET
	var centre_x := start.x

	await _place_unit(car, start.lerp(end, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	# Parked *inside* the pull-over radius first: proximity alone must not do it --
	# an emergency vehicle stood at a scene is driven around, not parked behind.
	await _place_unit(_car, start.lerp(end, 0.40) + lane,
		atan2(-direction.x, -direction.z))
	await _wait(10)
	_check(not car.is_pulled_over,
		"a parked patrol car is not a reason to pull over")
	await _place_unit(_car, start.lerp(end, 0.15) + lane,
		atan2(-direction.x, -direction.z))
	await _wait(4)

	# Sent well past the far junction, so the response is still driving -- and the
	# taxi still held at the kerb -- for long enough to be seen stopped there.
	_car.navigate_to(end + direction * 25.0)
	var tucked := false
	var widest := 0.0
	var stopped := false
	# How long it actually spends at the kerb, timed from the tuck. Timing from after
	# the release instead was inert: this loop already breaks on the release, so the
	# clock started once it had happened and read 0.0s whichever branch let the car go.
	var at_kerb := 0.0
	for i in 600:
		await physics_frame
		if car.is_pulled_over:
			tucked = true
			at_kerb += 1.0 / 60.0
			widest = maxf(widest, absf(car.global_position.x - centre_x))
			if absf(car.forward_speed) < 0.4:
				stopped = true
		if stopped and not car.is_pulled_over:
			break
	_check(tucked, "the taxi pulled over for the approaching response")
	_check(widest > CityGrid.LANE_OFFSET + 0.6,
		"tucked in past its own lane (%.1fm off the centre line)" % widest)
	_check(stopped, "and waited at the kerb")

	var resumed := false
	for i in 600:
		await physics_frame
		if not car.is_pulled_over and car.is_navigating():
			resumed = true
			break
	# It left the kerb *before the cap could have fired*, which is what makes this the
	# distance release rather than the timeout added later. There are two independent
	# ways out of the tuck and this check names one of them, so it has to exclude the
	# other or it is green whichever fired.
	_check(resumed and at_kerb < car.pull_over_max,
		"then rejoined the lane once the response had passed (%.1fs at the kerb, "
		% at_kerb + "cap is %.0fs)" % car.pull_over_max)

	# And it rejoins even when the response *never* passes.
	#
	# The tuck used to end only on distance, so a player working the same streets with
	# the lightbar on was never far enough away and the cars never came back: measured
	# over seventy seconds, pulled-over cars went 1, 3, 5, 6, 7 while the number still
	# moving fell from 21 to 16. They are solid, so each new arrival tucked into an
	# already-tucked car and stopped at an angle across the lane -- a pile-up that only
	# grew. A responder is passing, not parking, so the manoeuvre has to have an end of
	# its own.
	await _place_unit(car, start.lerp(end, 0.62) + lane,
		atan2(-direction.x, -direction.z))
	car._from = from
	car._to = to
	car._last_direction = direction
	car._begin_leg()
	car._tuck_cooldown = 0.0
	# The responder sitting on top of it and **still navigating**, for longer than the
	# cap. Keeping it navigating is the whole trick: `_responder_near` gates on
	# `is_navigating()`, so a car that reaches its target stops counting as a responder
	# and the tuck ends by *distance* within a frame. The first version of this hopped
	# the responder two metres, and the check passed at "after 0s" -- measuring the
	# distance release while claiming to measure the cap.
	await _place_unit(_car, start.lerp(end, 0.55) + lane,
		atan2(-direction.x, -direction.z))
	# Navigating to somewhere it can never reach, and pinned where it is. A responder
	# that *arrives* stops being one -- `_responder_near` gates on `is_navigating()` --
	# and re-issuing the order each frame still leaves a frame's gap in which the tuck
	# releases on distance. This never arrives, so the only way out of the kerb is the
	# cap, which is the thing under test.
	var post := start.lerp(end, 0.55) + lane
	var facing := atan2(-direction.x, -direction.z)
	# **Unreachable, but on the map.** 400m along the street lands at z 402 on a district
	# that ends at 130, so this tripped `navigate_to`'s off-map guard on every single run --
	# a warning with a full stack trace, fired by design, in a suite whose whole value is
	# that its output means something. It very nearly buried a real one: the guard caught a
	# genuine off-map pull-over reported from play, and this was the noise it was sitting in.
	# The distance was never load-bearing anyway -- `pin` below holds the car still every
	# frame, so it cannot arrive at anything, however close.
	var far := post + direction * 400.0
	var edge := CityGrid.MAP_HALF
	_car.navigate_to(Vector3(clampf(far.x, -edge, edge), far.y, clampf(far.z, -edge, edge)))
	var pin := func() -> void:
		_car.global_position = post
		_car.rotation.y = facing
		_car.velocity = Vector3.ZERO
	var held := false
	for i in 300:
		await physics_frame
		pin.call()
		if car.is_pulled_over:
			held = true
			break
	_check(held, "a car tucks in for a response sitting on top of it")
	var let_go := false
	var waited := 0.0
	for i in int((car.pull_over_max + 4.0) * 60.0):
		await physics_frame
		waited += 1.0 / 60.0
		pin.call()
		if car.is_pulled_over:
			continue
		let_go = true
		break
	# The lower bound is what makes this the *cap* rather than the distance release.
	# A release at 0s means the responder stopped being one, which proves nothing about
	# a car that has been sat at the kerb too long.
	_check(let_go and waited > 1.0,
		"and rejoins the road anyway after %.1fs rather than silting up the street "
		% waited + "(cap is %.0fs)" % car.pull_over_max)
	_car.stop_navigating()


# --- Autopilot ---------------------------------------------------------------

func _test_starting_units_are_clickable() -> void:
	# Run before anything is teleported, so this is the arrangement the map actually
	# ships, seen from the view the game actually opens on.
	#
	# The bug it catches: picking is a camera ray, so a unit parked close to a
	# building simply cannot be selected -- the building is in the way. It is
	# invisible to every other check, because the unit itself works perfectly. The
	# station crew were parked 2m from a 6.8m frontage and none of the four could be
	# clicked at all.
	_camera.stop_following()
	_camera.focus = _opening_focus
	_camera._target_distance = _opening_distance
	await _idle(60)

	var blocked := PackedStringArray()
	for node in _scene.get_node("Units").get_children():
		var unit := node as Unit
		if unit == null or not unit.is_selectable():
			continue
		var aim := unit.global_position + Vector3.UP * 0.9
		if _camera.is_position_behind(aim):
			blocked.append("%s (off screen)" % unit.name)
			continue
		var hit := _controller._raycast(_screen_of(aim)).get("collider") as Node
		if hit != unit:
			blocked.append("%s (ray stops on %s)" % [unit.name, hit])
	_check(blocked.is_empty(),
		"all %d starting units can be clicked from the opening view%s" % [
			_scene.get_node("Units").get_child_count(),
			"" if blocked.is_empty() else " -- blocked: " + ", ".join(blocked)])


## A left turn's chord from stop line to exit lane cuts through the oncoming halves
## of both streets -- the taxi on the wrong side of the yellow line mid-junction.
## CityGrid.turn_apex is the fix; this pins its geometry, then stages the drive.
func _test_left_turns_round_the_apex() -> void:
	var junction := CityGrid.junction(Vector2i(3, 2))
	var east := Vector3(1.0, 0.0, 0.0)
	var north := Vector3(0.0, 0.0, -1.0)
	var south := Vector3(0.0, 0.0, 1.0)
	var apex := CityGrid.turn_apex(junction, east, north)
	_check(apex != Vector3.ZERO and apex.x > junction.x and apex.z > junction.z,
		"a left turn gets an apex on the driver's own quadrant (%s)" % apex)
	_check(CityGrid.turn_apex(junction, east, south) == Vector3.ZERO,
		"a right turn gets none -- it hugs its own corner already")
	_check(CityGrid.turn_apex(junction, east, east) == Vector3.ZERO,
		"and straight on gets none")

	# The drive: a taxi at the stop line, eastbound, staged into the left turn north.
	# Sampled north of the junction's centre line, where the old chord put it a good
	# two metres onto the oncoming side of the avenue it was turning into.
	var packed := load("res://Game/Traffic/Taxi.tscn") as PackedScene
	if packed == null:
		_check(false, "a taxi scene to stage the turn with")
		return
	var taxi := packed.instantiate() as TrafficCar
	_scene.add_child(taxi)
	taxi.global_position = Vector3(14.0, 0.2, -17.5)
	taxi.global_rotation = Vector3(0.0, CityGrid.heading(east), 0.0)
	await _wait(4)
	taxi._from = Vector2i(3, 2)
	taxi._to = Vector2i(3, 1)
	taxi._last_direction = east
	taxi._begin_leg()

	var worst := INF
	for i in 900:
		await physics_frame
		var here := taxi.global_position
		if here.z < -26.0:
			break
		if here.z < junction.z:
			worst = minf(worst, here.x)
	_check(worst != INF and worst > 19.0,
		"turning left it kept east of the exit street's centre line (min x %.1f)"
		% (worst if worst != INF else -1.0))
	taxi.queue_free()
	await _wait(4)


func _test_starts_parked() -> void:
	var start := _car.global_position
	await _wait(60)
	_check(not _car.has_orders(), "starts with no order")
	_check(start.distance_to(_car.global_position) < 0.2,
		"sits still until ordered (drifted %.3fm)" % start.distance_to(_car.global_position))
	_check(absf(_car.global_position.y) < 0.1,
		"rests on the deck (y=%.3f)" % _car.global_position.y)


func _test_drives_to_target() -> void:
	await _place(ROAD)
	# Straight up the same avenue, through one junction.
	var target := Vector3(20.0, 0.0, -14.0)
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(900)
	_check(arrived, "completed the order before the timeout [%s]" % _car_state())
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the target" % _flat_distance(_car.global_position, target))


func _test_stops_on_arrival() -> void:
	# Carries straight on from the previous test's arrival.
	await _wait(60)
	_check(absf(_car.forward_speed) < 0.5,
		"came to rest (%.2f m/s)" % _car.forward_speed)
	_check(not _car.has_orders(), "cleared its order on arrival")


func _test_turns_around_for_a_target_behind() -> void:
	await _place(ROAD)
	# Car faces -Z, so a target at +Z is directly behind it: this is the case that
	# needs the reverse manoeuvre, since a car cannot turn on the spot.
	var target := ROAD + Vector3(0.0, 0.0, 6.0)
	target.y = 0.0
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(900)
	_check(arrived, "reached a target directly behind it")
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the target behind" % _flat_distance(_car.global_position, target))


func _test_crosses_the_map() -> void:
	# Corner to opposite corner of the outer ring road: the better part of half a
	# kilometre of driving, with a turn at every junction it takes on the way.
	await _place(CityGrid.junction(Vector2i(0, 0)) + Vector3(10.0, 0.15, 0.0))
	var target := CityGrid.junction(Vector2i(CityGrid.BANDS - 1, CityGrid.BANDS - 1))
	_car.issue(MoveOrder.new(target))
	# Counted rather than merely timed out on. This is the longest drive in the suite
	# and its budget has twice been the thing that broke -- once at 3600 frames, when
	# the drive itself takes around 3800. A timeout says only "too slow"; the count
	# says how slow, so the next slowdown is legible instead of mysterious.
	var frames := 0
	var arrived := false
	for i in CROSSING_BUDGET:
		if not _car.has_orders():
			arrived = true
			break
		frames = i
		await physics_frame
	_check(arrived, "drove corner to corner of the district in %d of %d frames [%s]"
		% [frames, CROSSING_BUDGET, _car_state()])
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.0,
		"stopped %.2fm from the far corner" % _flat_distance(_car.global_position, target))


func _test_routes_around_a_building() -> void:
	# Straight across the centre block, which is 30m of solid building. The only way
	# there is round it, and the road network is the only thing that offers one.
	await _place(Vector3(20.0, 0.15, 0.0))
	var target := Vector3(-20.0, 0.0, 0.0)
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(1800)
	_check(arrived, "found a way round the centre block [%s]" % _car_state())
	_check(_flat_distance(_car.global_position, target) < _car.arrive_radius + 1.5,
		"stopped %.2fm the far side" % _flat_distance(_car.global_position, target))


## A route never starts by sending a car the wrong way.
##
## The lattice route begins at the nearest junction, and nearest is often *behind*: two
## thirds of the way along a street, the corner already passed is closer than the one
## ahead. Reported from play as "it immediately turns left and does a 360 degree loop
## before heading right", and measured from the recorded start: bound 185m east, the car
## went up to 25m **west** and turned through **523 degrees** before making any eastward
## ground.
func _test_a_route_does_not_start_behind_the_car() -> void:
	# The position the black box recorded, and a destination far to the east of it.
	var from := Vector3(-58.0, 0.0, 26.0)
	var to := Vector3(126.5, 0.0, -75.0)
	var route := CityGrid.lane_route(from, to)
	_check(route.size() > 2, "a journey across the district is lane routed (%d waypoints)"
		% route.size())
	if route.is_empty():
		return
	var onward := to - from
	onward.y = 0.0
	var first := route[0] - from
	first.y = 0.0
	_check(first.dot(onward) > 0.0,
		"and sets off towards the destination, not away from it (first waypoint %.1f, %.1f)"
		% [route[0].x, route[0].z])


## Shutting a street and asking the lattice for a way round. Pure routing, no driving:
## if this is wrong the behavioural check below cannot be right for the right reason.
func _test_a_shut_street_is_routed_around() -> void:
	var a := Vector2i(2, 3)
	var b := Vector2i(2, 2)
	var direct := CityGrid.route(a, b)
	_check(direct.size() == 2, "two neighbouring junctions are one street apart (%d)"
		% direct.size())

	var shut := {CityGrid.street_key(a, b): true}
	var round_it := CityGrid.route(a, b, shut)
	_check(round_it.size() > direct.size(),
		"with that street shut the way there is longer (%d junctions, was %d)"
		% [round_it.size(), direct.size()])
	var used := false
	for i in range(1, round_it.size()):
		if CityGrid.street_key(round_it[i - 1], round_it[i]) == CityGrid.street_key(a, b):
			used = true
	_check(not used and round_it.size() > 0, "and does not use the shut street")
	# Named the same both ways round, or a driver that gave up going one way would plan
	# straight back down it going the other.
	_check(CityGrid.street_key(a, b) == CityGrid.street_key(b, a),
		"a street has one name whichever way it is driven")


## A street is only written off when something is actually sitting in it.
##
## Getting nowhere and being blocked are different, and confusing them is expensive: a
## car recorded in play reversed out of its own escape manoeuvre with nothing within 14m,
## concluded the street was shut, wrote off two of them, and turned a journey 200m **east**
## into a twenty-waypoint route ending at the far **west** edge of the map.
func _test_a_clear_street_is_not_written_off() -> void:
	await _place(CityGrid.junction(Vector2i(3, 2)) + Vector3(CityGrid.LANE_OFFSET, 0.15, 20.0))
	var order := MoveOrder.new(CityGrid.junction(Vector2i(3, 1)))
	_car.issue(order)
	await _idle(4)
	# Pinned where it stands, so it makes no progress at all -- which is exactly what the
	# give-up timer watches for. Nothing is in its way; the road is not the problem.
	#
	# Held in place rather than frozen: `set_physics_process(false)` also stops the order
	# ticking, so the give-up never runs at all and the check passes with its subject
	# deleted.
	var spot := _car.global_position
	for i in int(MoveOrder.GIVE_UP_AFTER * 60.0) + 180:
		await physics_frame
		_car.global_position = spot
		_car.velocity = Vector3.ZERO
	_check(order._shut.is_empty(),
		"a car going nowhere on an empty street writes none of it off (%d shut)"
		% order._shut.size())
	_car.clear_orders()
	await _idle(6)


## Traffic gets warning proportional to how fast the response is coming.
##
## A flat 16m radius is two thirds of a second at 25 m/s: the car began tucking when the
## responder was already on top of it, never cleared the lane, and the response spent the
## pass crawling behind it. Notice is time, not distance.
func _test_traffic_is_warned_in_time() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	await _idle(4)
	var street := CityGrid.band_centre_z(2)
	taxi.global_position = Vector3(0.0, 0.2, street + CityGrid.LANE_OFFSET)
	taxi.rotation.y = -PI * 0.5

	# A responder 40m back: too far to have registered under the old flat radius.
	await _place_unit(_car, Vector3(-40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	_car.issue(MoveOrder.new(Vector3(60.0, 0.0, street + CityGrid.LANE_OFFSET)))
	await _idle(2)
	# Asked in the same breath as it is set: `_update_movement` recomputes `forward_speed`
	# from the actual velocity on its first line, so a speed assigned between frames is
	# gone before the next one reads it.
	_car.forward_speed = 25.0
	_check(taxi._responder_near(taxi.pull_over_radius) != null,
		"a taxi 40m ahead of a fast response has already been warned")

	# Crawling, the same car at the same distance is not its problem yet.
	_car.clear_orders()
	await _place_unit(_car, Vector3(-40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	await _idle(2)
	_car.forward_speed = 0.0
	_check(taxi._responder_near(taxi.pull_over_radius) == null,
		"and a stationary one 40m back is not")

	# Nor is one that has already gone past, however fast it is going.
	await _place_unit(_car, Vector3(40.0, 0.15, street + CityGrid.LANE_OFFSET),
		-PI * 0.5)
	_car.issue(MoveOrder.new(Vector3(90.0, 0.0, street + CityGrid.LANE_OFFSET)))
	await _idle(2)
	_car.forward_speed = 25.0
	_check(taxi._responder_near(taxi.pull_over_radius) == null,
		"nor one that is already past and driving away")

	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


## Being held at somebody else's speed counts as stuck.
##
## The give-up timer watches for **no progress**, and a car crawling behind a taxi is
## making progress — so it reset every frame and a journey could spend its whole length
## doing 3 m/s with a 25 m/s ceiling, which is stuck by any measure a player would use.
func _test_crawling_behind_someone_counts_as_stuck() -> void:
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	# **Two abreast**, because one is passable: with a lane free the car finds a gap, takes
	# it, and is never held at all -- which is the system working and no test of this.
	# One **in the lane** and one **on the passing line**. Placed 2.6m either side of the
	# centre they sat outside the 2.4m corridor the car sweeps, so neither counted as in
	# the way and it drove between them; and with only the first, the car simply passes,
	# which is the system working and no test of this.
	var junction := CityGrid.junction(Vector2i(3, 2))
	var wall: Array[TrafficCar] = []
	for across in [CityGrid.LANE_OFFSET, CityGrid.LANE_OFFSET - 3.4]:
		var blocker := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
			.instantiate() as TrafficCar
		_scene.add_child(blocker)
		blocker.set_physics_process(false)
		blocker.global_position = junction + Vector3(across, 0.2, -8.0)
		wall.append(blocker)
	await _idle(6)

	# Facing the way it is going: forward is -Z, and junction 3,1 lies south of 3,2.
	await _place_unit(_car, junction + lane, 0.0)
	_car.issue(MoveOrder.new(CityGrid.junction(Vector2i(3, 1)) + lane))
	var held := 0.0
	for i in 900:
		await physics_frame
		held = maxf(held, _car.held_up_for())
		if held > 0.5:
			break
	_check(held > 0.0, "a unit stuck behind a slower vehicle knows it (%.1fs)" % held)

	for blocker in wall:
		blocker.queue_free()
	_car.clear_orders()
	# Put it somewhere clear before leaving: this check ends with the car nose-first
	# against a wall of parked cars, and the next one places it and expects it to drive.
	await _idle(6)
	await _place_unit(_car, CityGrid.junction(Vector2i(2, 3)))
	await _idle(6)


## The fault this was built for: a car that sits behind an obstruction for ever.
##
## Four cars fill the full 10m width of a carriageway, which is not shovable and has no
## gap, and the patrol car is sent to the far side of them. Before the give-up timer it
## spent the whole minute pushing at them and finished 18.7m short.
func _test_a_car_gives_up_on_a_blocked_street() -> void:
	var a := CityGrid.junction(Vector2i(4, 3))
	var b := CityGrid.junction(Vector2i(4, 2))
	var along := (b - a).normalized()
	var across := along.cross(Vector3.UP)
	var mid := (a + b) * 0.5

	var wall: Array[Vehicle] = []
	for offset in [-3.75, -1.25, 1.25, 3.75]:
		var blocker := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
			.instantiate() as TrafficCar
		_scene.add_child(blocker)
		blocker.set_physics_process(false)
		blocker.global_position = mid + across * offset
		blocker.rotation.y = atan2(along.x, along.z) + PI
		wall.append(blocker)
	await _idle(10)

	await _place_unit(_car, a + along * 14.0 + across * CityGrid.LANE_OFFSET,
		atan2(along.x, along.z) + PI)
	var target := mid + along * 14.0
	_car.issue(MoveOrder.new(target))
	var arrived := await _await_arrival(3600)

	# Only the arrival is asserted. "And it did not shove them out of the way" reads like
	# a useful companion and is not one: with vehicle-on-vehicle collision working it
	# cannot come out any way but zero, and it stayed zero in a run where the car spent
	# the whole minute pushing at the wall. That the wall is solid belongs to
	# _test_vehicles_cannot_drive_through_each_other, which can actually fail.
	_check(arrived, "got to the far side of a street with no way through [%s]"
		% _car_state())
	for blocker in wall:
		blocker.queue_free()
	_car.clear_orders()
	await _idle(6)



## The interface's ink stays legible on the ground it is drawn on.
func _test_the_interface_can_be_read() -> void:
	# **A class of bug, not an instance of it.** Two colours have shipped written by hand
	# at a call site, correct for the scheme at the time and wrong afterwards: a 13% white
	# progress track that was invisible on a white card, and near-black shop wells left
	# over from a dark scheme on a light one. Both were found by eye, months apart. A
	# table of the pairs the interface actually uses catches the next one for free -- and
	# it earned its place immediately, because the August 2026 restyle inverted the whole
	# palette and every one of these pairs had to survive it.
	#
	# **Two tables, because these are two questions.** Ink on a ground has to be *read*,
	# and 3.0 is the bar (rather than WCAG's 4.5 -- this is chrome and large glyphs, not
	# body copy, and a bar too strict to pass is one that gets loosened rather than
	# obeyed). Two adjacent *surfaces* only have to be told apart, which is a much lower
	# bar and the reference does half of it with a border rather than with contrast.
	#
	# Splitting them was not a way to make a failing row pass: the surface row failed at
	# 1.2:1 and the palette was changed to fix it. Folding it into the ink table at 3.0
	# would have meant a tile brighter than the card it sits in.
	# **The chrome is the UI kit's art, and the theme has to still be made of it.**
	# `build_theme.gd` used to bake StyleBoxFlat -- a colour and a corner radius -- and
	# the difference between that and the kit is invisible to every other check here:
	# the sizes are the same, the text is the same, the suite is headless and never
	# looks at a pixel. Re-running an older builder, or one edit that drops back to
	# `_flat()`, would quietly return the game to its old look with everything green.
	# So: the panel a card is drawn with must be a *texture* box, and that texture must
	# come from the kit folder.
	var chrome := _scene.get_node("HUD/Root").theme as Theme
	var card_box := chrome.get_stylebox("panel", "CardPanel") as StyleBoxTexture
	var card_art := card_box.texture.resource_path if card_box and card_box.texture else ""
	_check(card_box != null and card_art.begins_with("res://Game/UI/Kit/"),
		"a card is drawn from the kit's art ('%s')" % card_art)
	# And the kit's faces, which is what actually makes it read as the reference rather
	# than as stock Godot. Checked on the button, because a button label is the one
	# piece of text that is neither body copy nor a heading.
	#
	# **Names the face, not just the folder.** Asking only for something under
	# `Game/UI/Fonts/` had a second, independent payer: the theme's `default_font` is a
	# kit face too, so deleting the button's own font left the check green reading
	# Barlow -- it could not tell "deliberately set in the display face" from "never
	# styled and fell through to body copy". The kit pairs Rajdhani with buttons for a
	# reason, and that is the thing worth pinning.
	var button_font := chrome.get_font("font", "Button")
	var face := button_font.resource_path if button_font else ""
	_check(face.begins_with("res://Game/UI/Fonts/Rajdhani"),
		"and its labels are set in the kit's display face ('%s')" % face)

	var pairs := [
		["text on a card", Palette.TEXT, Palette.CARD],
		["dim text on a card", Palette.TEXT_DIM, Palette.CARD],
		["text on the bar", Palette.TEXT, Palette.BAR],
		["tile ink on an unarmed tile", Palette.TEXT, Palette.WELL],
		["tile ink on an armed tile", Palette.CARD, Palette.MEDICAL],
		["tile ink on a running toggle", Palette.CARD, Palette.POLICE],
		["an alarm label on its wash", Palette.CASUALTY_DEEP, Palette.ALARM_WASH],
		["police ink on its muted fill", Palette.POLICE_DEEP, Palette.POLICE_PALE],
		["medical ink on its muted fill", Palette.MEDICAL_DEEP, Palette.MEDICAL_PALE],
		["fire ink on its muted fill", Palette.FIRE_DEEP, Palette.FIRE_PALE],
		["a progress fill against its track", Palette.GOOD, Palette.WELL],
	]
	var worst := INF
	var worst_pair := ""
	for pair: Array in pairs:
		var ratio: float = Palette.contrast(pair[1] as Color, pair[2] as Color)
		if ratio < worst:
			worst = ratio
			worst_pair = str(pair[0])
	_check(worst >= 3.0,
		"every ink reads on its ground (worst: %s at %.1f:1)" % [worst_pair, worst])

	# **Each pair now names what separates it, because the scheme changed under this
	# check.** The UI kit adopted in August 2026 separates surfaces with a *stroke* and a
	# gradient rather than a step in fill: its raised panel is #18222F -> #0E1620 inside
	# a #212D3C line, and the fills either side of that line are 1.16:1 apart. Held to
	# the old flat 1.3 this row failed on art that is plainly legible on screen.
	#
	# **This is a loosening, and worth saying so.** What stops it being the kind that
	# gets obeyed-by-lowering: a pair with no stroke is still held to 1.3, and a pair
	# that claims one must show that stroke stepping clear of the darker fill. The
	# original failure mode -- a surface the same colour as its ground, with nothing
	# between them -- fails either arm. What is no longer asserted is that two *fills*
	# alone carry the separation, which in this scheme is simply not how it is done.
	var surfaces := [
		["a recessed tile against its card", Palette.WELL, Palette.CARD,
			Palette.EDGE_SOFT],
		["a hovered tile against its card", Palette.HOVER, Palette.CARD, null],
		["a card against the bar", Palette.CARD, Palette.BAR, Palette.EDGE],
	]
	var flattest := INF
	var flattest_pair := ""
	var unlined := ""
	for pair: Array in surfaces:
		var ratio: float = Palette.contrast(pair[1] as Color, pair[2] as Color)
		var stroke: Variant = pair[3]
		if stroke == null:
			# Nothing between them: the fills have to do all of it, at the old bar.
			if ratio < flattest:
				flattest = ratio
				flattest_pair = str(pair[0])
			continue
		# Lined: the fills need only differ, and the line has to clear the darker of
		# the two it sits between.
		var darker: Color = (pair[1] as Color) if Palette.contrast(pair[1] as Color,
			Color.WHITE) > Palette.contrast(pair[2] as Color, Color.WHITE) \
			else (pair[2] as Color)
		var edge: float = Palette.contrast(stroke as Color, darker)
		if ratio < 1.10 or edge < 1.15:
			unlined = "%s (fills %.2f:1, line %.2f:1)" % [pair[0], ratio, edge]
	_check(flattest >= 1.3 and unlined == "",
		"and every surface is told apart from the one behind it (%s)"
		% [unlined if unlined != "" else "worst unlined: %s at %.2f:1"
			% [flattest_pair, flattest]])

	# **A slider's track is drawn from its stylebox's vertical content margin**, so a box
	# built with zero padding -- which is right for a card and meaningless here -- bakes a
	# track zero pixels high. That shipped: the volume grabber floated on nothing, which
	# is worse than the stock control it replaced, and it was found by eye.
	var theme := _scene.get_node_or_null("HUD/Root") as Control
	var track: StyleBoxFlat = theme.theme.get_stylebox("slider", "HSlider") \
		if theme and theme.theme else null
	var height := (track.content_margin_top + track.content_margin_bottom) \
		if track else 0.0
	_check(track != null and height >= 4.0,
		"the volume track has a height to draw (%.0fpx)" % height)


## Every command tile names its verb.
func _test_command_tiles_say_what_they_do() -> void:
	_controller.select([_car])
	await _idle(3)
	var named := 0
	var tiles := 0
	for child in _grid.get_children():
		var tile := child as CommandIcon
		if tile == null or not tile.visible or tile.ability == null:
			continue
		tiles += 1
		# The tile draws the label, so what is asserted is that it *has* one to draw --
		# a verb with an empty label would render a blank strip and read as a bug.
		if not tile.ability.label().strip_edges().is_empty():
			named += 1
	_check(tiles > 0 and named == tiles,
		"every tile has a name to draw (%d of %d)" % [named, tiles])
	_controller.select([])
	await _idle(2)



## Orders you queued are drawn, not just the one being driven at.
func _test_queued_orders_are_drawn() -> void:
	await _clear_calls()
	_controller.select([_car])
	await _idle(3)
	# Three stops, queued. Shift-right-click has queued orders since phase 1 and nothing
	# ever drew them: a player who lined three up had no way to see what they had asked
	# for, or to notice they had queued one by accident.
	var stops := [CityGrid.junction(Vector2i(2, 2)), CityGrid.junction(Vector2i(3, 2)),
		CityGrid.junction(Vector2i(3, 1))]
	_car.clear_orders()
	for i in stops.size():
		_car.issue(MoveOrder.new(stops[i]), i > 0)
	await _idle(6)
	_check(_car.orders.size() == 3, "three orders are queued (%d)" % _car.orders.size())

	var shown: Array[Node3D] = []
	for node in _controller._markers:
		var marker := node as Node3D
		if marker and marker.visible:
			shown.append(marker)
	_check(shown.size() >= 3, "and a marker stands at each (%d)" % shown.size())

	# Every queued destination has a marker on it, so the display is the queue rather
	# than a coincidence of the right count.
	var unmatched := 0
	for order in _car.orders:
		var found := false
		for marker in shown:
			var offset := marker.global_position - order.destination()
			offset.y = 0.0
			if offset.length() < 1.0:
				found = true
		if not found:
			unmatched += 1
	_check(unmatched == 0,
		"each marker sits on an order the unit is actually holding (%d adrift)" % unmatched)

	# The one being driven at is told apart from the ones waiting -- by size, because the
	# marker is a duplicated scene and recolouring would need a material per copy.
	var sizes: Array[float] = []
	for marker in shown:
		sizes.append(marker.scale.x)
	sizes.sort()
	_check(sizes.size() >= 2 and sizes[0] < sizes[sizes.size() - 1] - 0.1,
		"the current order stands taller than the queue (%.2f against %.2f)"
		% [sizes[0], sizes[sizes.size() - 1]])

	_car.clear_orders()
	_controller.select([])
	await _idle(3)



## A group ordered to one point spreads instead of stacking on it.
func _test_a_group_move_spreads_out() -> void:
	await _clear_calls()
	var fleet: Array[Unit] = []
	for car in _cars:
		if car and is_instance_valid(car):
			fleet.append(car)
	if fleet.size() < 3:
		_check(false, "three vehicles to send somewhere together")
		return
	fleet = fleet.slice(0, 3)
	var junction := CityGrid.junction(Vector2i(2, 2))
	var along := CityGrid.junction(Vector2i(2, 3))
	for i in fleet.size():
		# Along the street between two junctions, so every start point is carriageway.
		# Guessed offsets put one of them off the mesh, and it was still falling when a
		# later check picked it up -- "on floor false, -3.7 m/s vertical", two tests away.
		await _place_unit(fleet[i],
			junction.lerp(along, 0.30 + 0.14 * float(i)) + Vector3.UP * 0.2)
	_controller.select(fleet)
	await _idle(4)

	# **The fault, stated.** `MoveAbility.make_order` handed every selected unit the same
	# coordinate, so ten units ordered to a point all navigated to one spot and shoved
	# each other apart. It is the first thing an RTS player notices.
	_controller.order_at_point(junction)
	await _idle(6)
	var aims: Array[Vector3] = []
	for unit in fleet:
		var order := unit.current_order()
		if order and order.has_destination():
			aims.append(order.destination())
	_check(aims.size() == 3, "all three took the order (%d)" % aims.size())
	var closest := INF
	for i in aims.size():
		for j in range(i + 1, aims.size()):
			var offset := aims[i] - aims[j]
			offset.y = 0.0
			closest = minf(closest, offset.length())
	_check(closest > 3.0,
		"and each was sent somewhere of its own (%.1fm apart at the closest)" % closest)

	# Every slot has to be somewhere the unit could actually get to, on **its own**
	# navigation layer -- a car's slot on a pavement is no use to it.
	var unreachable := 0
	for i in fleet.size():
		if not Unit.can_reach(fleet[i], aims[i], 3.0):
			unreachable += 1
	_check(unreachable == 0,
		"every one of them somewhere it can drive to (%d adrift)" % unreachable)

	# **Staged against a frontage on purpose.** In open street every offset is trivially
	# fine and this check would pass without the fallback existing at all -- which is the
	# shape of vacuity this project has shipped twice.
	var block := CityGrid.junction(Vector2i(2, 2)) + Vector3(18.0, 0.0, 18.0)
	_controller.order_at_point(block)
	await _idle(6)
	# The contract is **not** "never aim at a building" -- ordering a unit into a block is
	# a thing the player may do, and the terminal approach already stops it short. It is
	# that a *slot* never makes things worse: each unit is sent either somewhere it could
	# stand, or to the exact point that was ordered, and never to an offset of its own
	# invention that happens to be inside a wall.
	var invented := 0
	for unit in fleet:
		var order := unit.current_order()
		if order == null or not order.has_destination():
			continue
		var aim := order.destination()
		var tile := CityGrid.tile_at(aim)
		if CityGrid.standable(tile.x, tile.y):
			continue
		var drift := aim - block
		drift.y = 0.0
		if drift.length() > 0.5:
			invented += 1
	_check(invented == 0,
		"and against a frontage each falls back to the point rather than inventing an "
		+ "offset inside the wall (%d of %d)" % [invented, fleet.size()])

	# **Reachability, measured on the hard order rather than the easy one.** The first
	# version asserted this only after the junction order, where every ring offset is
	# open carriageway and the answer is trivially yes -- the sabotage agent removed both
	# validity tests and it stayed green. Against a frontage a slot is either somewhere
	# the unit can genuinely path to, or the point it was given; nothing else is allowed.
	var stranded := 0
	for unit in fleet:
		var order := unit.current_order()
		if order == null or not order.has_destination():
			continue
		var aim := order.destination()
		var drift := aim - block
		drift.y = 0.0
		if drift.length() <= 0.5:
			continue
		if not Unit.can_reach(unit, aim, 3.0):
			stranded += 1
	_check(stranded == 0,
		"and no invented slot is one it could not path to (%d stranded)" % stranded)

	for unit in fleet:
		unit.clear_orders()
	_controller.select([])
	# **Put the fleet back.** This test moves the shared patrol cars, and a car left in
	# the middle of a street is a fixture the next check inherits.
	await _park_the_shift()
	await _idle(3)



## Things that answer a click look like they will.
func _test_clickable_things_respond_to_the_pointer() -> void:
	await _clear_calls()
	_controller.select([])
	await _idle(3)
	# Roster chips, call rows, dispatch rows and the CONTROLS chip all stop the mouse and
	# act on a click, and until August 2026 every one looked exactly like the things that
	# do not. A player had to find them by trying.
	var chip := _scene.get_node_or_null(
		"HUD/Root/World/ControlsToggle") as Control
	var subjects: Array[Control] = []
	if chip:
		subjects.append(chip)
	for path in ["HUD/Root/Bar/Row/DispatchBlock/Body/Heading"]:
		var found := _scene.get_node_or_null(path) as Control
		if found:
			subjects.append(found)
	_check(subjects.size() >= 2,
		"there are clickable controls to test (%d)" % subjects.size())

	# **Counted separately.** A single tally cannot tell "never brightened" from "never
	# went back", and both sabotages printed the same 0 of 2 -- so a future failure would
	# say something broke without saying which half, which is most of the debugging the
	# check exists to save.
	var lifted := 0
	var settled := 0
	for control in subjects:
		var before := control.modulate
		control.mouse_entered.emit()
		await _idle(2)
		if control.modulate != before:
			lifted += 1
		control.mouse_exited.emit()
		await _idle(2)
		# It must go back, or the first thing the pointer touches stays lit for ever.
		if control.modulate == before:
			settled += 1
	_check(lifted == subjects.size() and settled == subjects.size(),
		"each brightens under the pointer and settles again (%d lit, %d settled, of %d)"
		% [lifted, settled, subjects.size()])

	# **Brightness, not a stylebox.** Half of these are bare containers with no panel, and
	# giving one a panel changes its size -- which in the bar makes the bar taller, which
	# covers whatever floats above it. Six incidents deep, that is not a trade worth
	# making for a hover effect, so the hover must not move anything.
	var bar_before := _command_panel.get_global_rect().size.y
	if chip:
		chip.mouse_entered.emit()
	await _idle(3)
	_check(absf(_command_panel.get_global_rect().size.y - bar_before) < 0.5,
		"and none of it moves the panels (%.0f from %.0f)"
		% [_command_panel.get_global_rect().size.y, bar_before])
	if chip:
		chip.mouse_exited.emit()
	await _idle(2)


## The black box files a record when a unit stops getting anywhere.
##
## Worth a check because it is the only instrument for the faults that matter most --
## the ones a staged test does not reproduce -- and an instrument that has quietly
## stopped recording is worse than none, since its silence reads as "no fault".
func _test_a_stuck_unit_is_written_down() -> void:
	var log := _scene.get_node_or_null("StuckLog") as StuckLog
	if log == null:
		_check(false, "the map carries a StuckLog")
		return
	_check(log.log_path != "user://stuck-log.txt",
		"the suite is not writing into the player's own log (%s)" % log.log_path)
	# No cooldown for the staging. It exists so a car wedged for a minute does not write
	# fifteen copies of the same block, and it had already swallowed this record: the same
	# car files during earlier checks, and twenty seconds had not passed.
	log.quiet_for = 0.0
	var before := log.records()

	# **Held still under orders**, rather than walled in. Three stagings of a trap were
	# tried -- four cars across the carriageway, a short order with no route to give up
	# on, a long one -- and the car got round every time, which is the game working and
	# no test at all. What is being checked here is the instrument: a unit that is trying
	# to go somewhere and not closing on it gets written down.
	await _place_unit(_car, CityGrid.junction(Vector2i(3, 2))
		+ Vector3(CityGrid.LANE_OFFSET, 0.15, 20.0))
	_car.issue(MoveOrder.new(CityGrid.junction(Vector2i(3, 1))))
	await _idle(4)
	_car.set_physics_process(false)
	# A neighbour at a **known bearing**, so the record can be asked whether it says
	# where things are and not merely how far. Placed off the car's own basis rather
	# than a world axis, because which way it ended up facing is the staging's business.
	await _place_unit(_ambulance,
		_car.global_position - _car.global_basis.x * 6.0 + Vector3.UP * 0.15)
	for i in int(log.report_after * 60.0) + 120:
		await physics_frame
		if log.records() > before:
			break
	_car.set_physics_process(true)

	_check(log.records() > before,
		"a unit that stopped getting anywhere was written down (%d records, was %d)"
		% [log.records(), before])

	# **What the record says, not just that there is one.** Three August 2026 stalls read
	# "on a road, full throttle, zero speed, nothing in front" and could not be told
	# apart -- wedged against a car, wedged against scenery, or trouble entirely of the
	# car's own making. Range without bearing cannot be staged from, and the old record
	# had no line at all for what the car was in contact with.
	var text := _last_record(log)
	_check("touching:" in text,
		"and the record says what it is in contact with")
	# **Scanned over the neighbour lines only.** The first cut searched the whole record
	# for "behind", which every record already contains in `holding behind: nothing` --
	# so the check passed with `_bearing_note` stubbed out to return nothing at all. The
	# fault reached the measurement perfectly well; the assertion was simply looking at
	# more text than the mechanism writes.
	var neighbours: Array[String] = []
	var bearings := 0
	for line in text.split("\n"):
		if not line.begins_with("    ") or not ("speed" in line):
			continue
		neighbours.append(line)
		if "°" in line or "dead ahead" in line or "behind" in line:
			bearings += 1
	_check(not neighbours.is_empty() and bearings == neighbours.size(),
		"and where its neighbours are, not just how far (%d of %d carry a bearing)"
		% [bearings, neighbours.size()])
	# The ambulance was put on the car's left, so a record that reads "right" has the
	# sign inverted -- which would send the next investigation looking the wrong way.
	var ambulance_line := ""
	for line in text.split("\n"):
		if _ambulance.name in line:
			ambulance_line = line
	_check("left" in ambulance_line,
		"with the side it is actually on (%s)" % ambulance_line.strip_edges())

	_car.clear_orders()
	await _idle(6)


## The text of the most recent block in the black box's log.
func _last_record(log: StuckLog) -> String:
	var file := FileAccess.open(log.log_path, FileAccess.READ)
	if file == null:
		return ""
	var whole := file.get_as_text()
	file.close()
	var blocks := whole.split("--- ")
	return blocks[blocks.size() - 1] if blocks.size() > 1 else whole


## An order can only ever be given to somewhere on the map.
##
## The fault this pins came out of the black box rather than out of a staged test: a
## patrol car was found aiming at **z = 402 on a 260m map**, 270m outside the district.
## Off-map destinations do not fail loudly -- the navigation agent clamps one to the
## nearest point it can reach, which may be the far side of the city, so the unit drives
## off in the wrong direction and tours the perimeter with nothing to say it went wrong.
func _test_an_order_cannot_leave_the_map() -> void:
	var minimap := _scene.get_node_or_null(
		"HUD/Root/World/MinimapCard/Minimap") as Control
	if minimap == null:
		_check(false, "the HUD carries a minimap")
		return

	# `_gui_input` keeps delivering events to a control while a drag is in progress,
	# wherever the pointer has got to, so a position outside the card is not a
	# hypothetical.
	var beyond: Vector3 = minimap._to_world(minimap.size * 2.5)
	var short: Vector3 = minimap._to_world(-minimap.size)
	_check(absf(beyond.x) <= CityGrid.MAP_HALF and absf(beyond.z) <= CityGrid.MAP_HALF,
		"a click past the far corner of the minimap still lands on the map (%.0f, %.0f)"
		% [beyond.x, beyond.z])
	_check(absf(short.x) <= CityGrid.MAP_HALF and absf(short.z) <= CityGrid.MAP_HALF,
		"and so does one past the near corner (%.0f, %.0f)" % [short.x, short.z])

	# And the funnel itself refuses one, whatever hands it over.
	await _place(Vector3(20.0, 0.15, 0.0))
	_controller.selection = [_car] as Array[Unit]
	_car.clear_orders()
	_controller.order_at_point(Vector3(0.0, 0.0, CityGrid.MAP_HALF * 3.0))
	_check(not _car.has_orders(), "and an order off the map is refused outright")
	_controller.order_at_point(CityGrid.junction(Vector2i(2, 2)))
	_check(_car.has_orders(), "while one on it is still taken")
	_car.clear_orders()
	await _idle(4)


## Hitting something costs money, and costs it in proportion.
##
## The career only ever went up before this: calls paid, and nothing took anything back.
## Damage is the sink, and it is **money and nothing else** -- a dented car steers, brakes
## and answers exactly as it did new. Taking a unit off the board for a scrape would
## punish the same mistake twice.
func _test_a_knock_costs_money() -> void:
	var wall := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(wall)
	wall.set_physics_process(false)
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	wall.global_position = Vector3(20.0, 0.2, -20.0) + lane
	wall.rotation.y = PI * 0.5
	await _idle(10)

	# **Two different run-ups**, not two forced speeds. Setting `forward_speed` between
	# frames does nothing: `_update_movement` recomputes it from the actual velocity on
	# its first line, so both trials collided at the autopilot's own approach speed and
	# billed the identical £117.
	#
	# **And pointed at the wall, which it was not until August 2026.** Started yawed 180
	# the car spent its run-up turning round: the long trial billed 54.8m from the wall,
	# 7.4m from where it began, having scraped something mid-manoeuvre and never reached
	# the obstacle at all. Both trials therefore hit at the same 9 m/s and the ordering
	# came down to which scrape happened to be worse -- it passed on luck, and any change
	# to the steering flipped it. Facing the wall, the trials land 3.7m from it at 10 and
	# 25 m/s, which is the thing this check has always claimed to measure.
	var bills: Array[int] = []
	var speeds: Array[float] = []
	for run_up in [7.0, 60.0]:
		_car.repair_bill = 0
		await _place_unit(_car, Vector3(20.0, 0.15, -20.0 + run_up) + lane, 0.0)
		_car.avoids_vehicles = false
		_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -32.0) + lane))
		var fastest := 0.0
		for i in 600:
			await physics_frame
			fastest = maxf(fastest, absf(_car.forward_speed))
			if _car.repair_bill > 0:
				break
		bills.append(_car.repair_bill)
		speeds.append(fastest)
		_car.clear_orders()
		_car.avoids_vehicles = true
		await _idle(4)

	_check(bills[0] > 0 and bills[1] > 0,
		"driving into something bills for the damage (£%d at %.0f m/s, £%d at %.0f)"
		% [bills[0], speeds[0], bills[1], speeds[1]])
	_check(bills[1] > bills[0],
		"and a harder knock costs more than a gentle one (£%d against £%d)"
		% [bills[1], bills[0]])
	_check(_car.max_speed > 0.0 and _car.is_selectable(),
		"a damaged unit is still a working unit")
	wall.queue_free()
	_car.repair_bill = 0
	await _idle(4)


## Bringing a unit home is what settles its bill.
func _test_the_station_repairs_what_comes_home() -> void:
	_station.funds = 500
	_station.repairs_paid = 0
	_car.repair_bill = 120
	_check(_station.outstanding_repairs() >= 120,
		"the fleet's outstanding damage is visible before it is paid (£%d)"
		% _station.outstanding_repairs())

	_station.accept(_car)
	_check(_car.repair_bill == 0, "booking in puts the vehicle right (£%d left)"
		% _car.repair_bill)
	_check(_station.funds == 380, "and the purse paid for it (£%d)" % _station.funds)
	_check(_station.repairs_paid == 120,
		"the shift's repair tally follows it (£%d)" % _station.repairs_paid)

	# A career that cannot afford its repairs should feel poor, not stop working.
	_station.funds = 50
	_car.repair_bill = 200
	_station.accept(_car)
	_check(_station.funds == 0 and _car.repair_bill == 150,
		"an empty purse pays what it can and the rest stays owed (£%d left, £%d owed)"
		% [_station.funds, _car.repair_bill])
	_car.repair_bill = 0
	_station.funds = 99999
	await _idle(4)


func _test_vehicles_slow_for_corners() -> void:
	# A long approach up the avenue, then a left at the junction.
	#
	# The check is physical rather than cosmetic. Grip caps the tightest circle a car
	# can hold at v^2/max_lateral_accel, and a junction is 10m across -- so arriving at
	# the corner much above 10 m/s means the turn simply cannot be made, and the car
	# swings wide into the oncoming lane and whatever is on the far side of it.
	#
	# Before the autopilot looked ahead it arrived at 17.8 m/s, wanting a 23m circle.
	var speed := await _corner_apex()

	_check(not _car.has_orders(), "drove a route with a junction turn in it [%s]" % _car_state())
	_check(speed > 1.0, "and was actually cornering when measured (%.1f m/s)" % speed)
	var radius := speed * speed / _car.max_lateral_accel
	_check(radius < 9.0,
		"took the corner at %.1f m/s, needing a %.1fm circle inside a 10m junction"
		% [speed, radius])


## Rain, and the reason it is worth having at all: it is not a filter over the screen.
##
## The autopilot already plans corner entry from the grip available to hold the turn,
## so scaling grip changes how the whole district drives -- the player's units and the
## ambient fleet alike -- without a line anywhere asking whether it is raining. This
## measures that: the *same* corner, driven dry and then wet, and the wet one has to be
## slower. Anything less and the weather is a screen effect wearing a physics label.
func _test_rain_makes_the_road_slippery() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district knows what the weather is doing")
		return
	var kept := daylight.weather

	daylight.set_weather(Daylight.Weather.CLEAR)
	_check(is_equal_approx(_car.grip_scale, 1.0),
		"a dry road is full grip (%.2f)" % _car.grip_scale)
	var dry := await _corner_apex()

	daylight.set_weather(Daylight.Weather.RAIN)
	_check(_car.grip_scale < 1.0,
		"rain takes grip off every vehicle on the map (%.2f)" % _car.grip_scale)
	var wet := await _corner_apex()

	# Grip enters the corner planner under a square root -- the tightest circle is
	# sqrt(max_lateral_accel * grip_scale * radius) -- so 0.72 grip is about 0.85 of the
	# dry apex speed, roughly 7.5 m/s against 8.9. The margin below is well inside that
	# and well outside frame-to-frame noise.
	_check(wet < dry * 0.94,
		"and the same corner is taken slower in the wet (%.1f m/s vs %.1f dry)"
		% [wet, dry])
	# Slower, but still *possible*. A grip figure low enough to make an ordinary
	# junction turn unmakeable would send the car wide and get it re-routed the long
	# way round, which reads as a broken car rather than as weather.
	_check(wet > 0.0 and not _car.has_orders(),
		"and the turn is still makeable rather than re-routed [%s]" % _car_state())

	# The watcher, same as the headlamps: something bought mid-downpour is wet too.
	var kept_funds := _station.funds
	var kept_owned: Dictionary = _station.owned.duplicate()
	_station.funds += _station.price(&"patrol")
	_station.purchase(&"patrol")
	var bought := _station.dispatch(&"patrol")
	if bought == null:
		_check(false, "a patrol car could be bought to test the wet fitting")
	else:
		await _idle(4)
		_check((bought as Vehicle).grip_scale < 1.0,
			"a car bought in the rain drives on a wet road from its first metre (%.2f)"
			% (bought as Vehicle).grip_scale)
		bought.queue_free()
		await _idle(2)
	_station.funds = kept_funds
	_station.owned = kept_owned

	daylight.set_weather(kept)
	_check(is_equal_approx(_car.grip_scale, daylight.road_grip()),
		"and the road dries out again (%.2f)" % _car.grip_scale)


## Fog and snow, the other two skies. Each is rain's shape -- one grip number and an
## air treatment composed over the hour -- so this asserts exactly those two halves,
## plus the visual that separates snow from rain: flakes, not streaks.
func _test_fog_and_snow_are_weather_too() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	var world := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if daylight == null or world == null:
		_check(false, "the district has a sky to weather")
		return
	var air := world.environment
	daylight.set_weather(Daylight.Weather.CLEAR)
	var clear_fog := air.fog_density

	daylight.set_weather(Daylight.Weather.FOG)
	# **The switch, not just the number.** The map ships with fog_enabled off in depth
	# mode, and two earlier cuts of this treatment wrote densities into that disabled
	# path -- the checks measured the values moving and a player pressing FOG saw
	# nothing. Weather must turn the fog on, in the mode where density means density.
	_check(air.fog_enabled and air.fog_mode == Environment.FOG_MODE_EXPONENTIAL,
		"fog switches the air on, exponentially (enabled %s, mode %d)"
		% [air.fog_enabled, air.fog_mode])
	_check(air.fog_density >= 0.019,
		"and thick enough to read at RTS distance (%.4f from %.4f)"
		% [air.fog_density, clear_fog])
	_check(is_equal_approx(_car.grip_scale, 0.88),
		"and takes a little grip -- caution, not a surface (%.2f)" % _car.grip_scale)
	_check(not daylight.is_wet(), "but the road under fog is not wet")
	# What real fog does to a real city: the lights come on at noon. Street lamps and
	# every vehicle's headlamps, through the same lights_on() the hours use.
	var street := _scene.get_node_or_null("StreetLights") as Node3D
	var beams := _car.get_node_or_null("Headlights") as Node3D
	_check(street != null and street.visible,
		"fog turns the street lights on at noon")
	_check(beams != null and beams.visible,
		"and every vehicle runs its headlamps")

	daylight.set_weather(Daylight.Weather.SNOW)
	_check(is_equal_approx(_car.grip_scale, 0.62),
		"snow grips below rain (%.2f)" % _car.grip_scale)
	_check(daylight.is_wet(), "and counts as water on the road")
	var flakes := daylight.get_node_or_null("Snow") as GPUParticles3D
	var streaks := daylight.get_node_or_null("Rain") as GPUParticles3D
	_check(flakes != null and flakes.visible and flakes.emitting,
		"snow falls as its own particles")
	_check(streaks == null or not streaks.visible,
		"and the rain stays off while it does")

	daylight.set_weather(Daylight.Weather.CLEAR)
	_check(is_equal_approx(air.fog_density, clear_fog)
			and not air.fog_enabled
			and is_equal_approx(_car.grip_scale, 1.0),
		"and the sky clears back to the hour's own air, switch and all (%.4f)"
		% air.fog_density)
	_check(street != null and not street.visible
			and beams != null and not beams.visible,
		"with the lights back out -- noon is noon again")


## Drives one fixed route with a junction turn in it, and hands back the speed at the
## point the car was turning **hardest**. Shared, so the dry and wet runs are provably
## the same drive.
##
## The apex is found by watching yaw rate rather than by naming a junction, and that is
## not a stylistic choice. This check used to measure the speed at the closest approach
## to a hardcoded corner at (-20, 20) -- and the route does not go anywhere near it: the
## car heads east first, and its closest approach is **38 metres**, reached at the very
## end while parking. So it was sampling a stationary car and passing `radius < 9.0`
## trivially. It had presumably been real when written and stopped being so when the
## district doubled to 260m and every junction moved; nothing pointed at the coordinate
## to say it had gone stale. Peak yaw rate cannot go stale -- wherever the turn is, that
## is where the car turns hardest.
##
## The `speed > 1.0` guard keeps the parking manoeuvre at the destination out of it: a
## car shuffling into its final position turns sharply at walking pace and would
## otherwise win.
func _corner_apex() -> float:
	await _place(Vector3(-20.0, 0.15, -25.0), PI)
	_car.issue(MoveOrder.new(Vector3(18.0, 0.0, 20.0)))
	var last_yaw := _car.rotation.y
	var hardest := 0.0
	var speed := 0.0
	for i in 1500:
		await physics_frame
		var yaw := _car.rotation.y
		var turned := absf(wrapf(yaw - last_yaw, -PI, PI))
		last_yaw = yaw
		var now := absf(_car.forward_speed)
		if turned > hardest and now > 1.0:
			hardest = turned
			speed = now
		if not _car.has_orders():
			break
	return speed


func _test_vehicles_keep_out_of_the_buildings() -> void:
	# The whole point of baking the vehicle mesh from road surfaces alone. Ordered into
	# the middle of a block -- 30m of building, no navigation mesh anywhere near it --
	# the car must come to rest short of it rather than driving at a wall or refusing
	# the order.
	#
	# **It used to have to stop on the road, and that stopped being right.** Measured
	# along this block: the building is the middle 0-9m, the pavement ring is 10-14m,
	# and the carriageway starts at 15m. Once a car could climb a kerb on an order sent
	# somewhere off-road -- which is a verb the player asked for -- a car aimed at the
	# block centre correctly mounts the pavement and stops at the building line. It now
	# comes to rest around 12.8m, which the old bar read as failure and which is exactly
	# what should happen.
	#
	# So the assertion moved to the guarantee that actually matters and has not changed:
	# it never gets *inside*. `CityGrid.standable` is the line -- true on road and
	# pavement, false on a building footprint -- and it is the same test that keeps
	# fires and casualties out of people's houses.
	await _place(Vector3(20.0, 0.15, 0.0))
	_car.issue(MoveOrder.new(Vector3.ZERO))
	await _await_arrival(1800)
	var here := _car.global_position
	var tile := CityGrid.tile_at(here)
	_check(CityGrid.standable(tile.x, tile.y),
		"stopped somewhere it may stand at (%.1f, %.1f), not inside the block"
		% [here.x, here.z])
	_check(_flat_distance(here, Vector3.ZERO) > 10.0,
		"which is %.1fm out, clear of the building it was aimed into"
		% _flat_distance(here, Vector3.ZERO))


# --- Selection and orders ----------------------------------------------------

## Vehicles are solid to one another, proved by staging rather than by watching the
## district and hoping: "no two cars happened to overlap in this window" is not the
## same claim as "no two cars can". With the steering avoidance switched off, a car
## driven straight at a parked one has to stop against it.
func _test_vehicles_cannot_drive_through_each_other() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	taxi.set_physics_process(false)
	# **In the lane the car will actually drive**, not on the centre line. Since
	# MoveOrder routes vehicles junction to junction in their own lane, a car heading
	# south down this street sits LANE_OFFSET to its right -- so a taxi parked on the
	# centre gets passed at 2.4m rather than hit, and this check quietly stopped
	# staging a collision at all. The car was not wrong; the staging was.
	var lane := Vector3(CityGrid.LANE_OFFSET, 0.0, 0.0)
	taxi.global_position = Vector3(20.0, 0.2, -20.0) + lane

	await _place_unit(_car, Vector3(20.0, 0.15, 4.0) + lane)
	# The point is the collision, not the manoeuvre -- the swerve has its own check.
	_car.avoids_vehicles = false
	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -45.0)))

	var closest := INF
	var through := false
	for i in 900:
		await physics_frame
		closest = minf(closest, _flat_distance(_car.global_position,
			taxi.global_position))
		if _car.global_position.z < taxi.global_position.z - 1.5:
			through = true
			break
		if not _car.has_orders():
			break
	_check(not through, "a car driven at a parked one cannot pass through it")
	_check(closest > 3.0,
		"it is stopped by the other car's body (closest %.1fm)" % closest)

	_car.avoids_vehicles = true
	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


## A vehicle thrown off the world comes back, and can carry on.
##
## Two CharacterBody3Ds have no solver between them: on a deep overlap `move_and_slide`
## depenetrates along the shortest exit axis, and for a box well inside another box that
## axis can be **downward, through the road**. Measured by driving one at three parked
## cars -- the patrol car reached **y = -58,356**, which is free-fall for the sixty
## seconds it was watched, and it never came back. Neither the stuck escape nor the
## navigation agent noticed: the escape only armed on a *stationary* car, and a falling
## one is moving.
##
## This is the net rather than a cure for the depenetration, which belongs to the
## engine. What matters is that a unit the player paid for cannot be lost to it.
func _test_a_vehicle_thrown_off_the_map_comes_back() -> void:
	await _place(Vector3(-20.0, 0.15, 0.0), 0.0)
	# Settled on the road for a moment, which is what the guard remembers.
	await _idle(40)
	var good := _car.global_position
	_check(good.y > Vehicle.FLOOR_FLOOR, "the car starts on the road (y %.2f)" % good.y)

	# Straight under the world, exactly where depenetration puts it.
	_car.global_position = Vector3(good.x, -50.0, good.z)
	_car.velocity = Vector3(0.0, -30.0, 0.0)
	await _idle(10)

	_check(_car.global_position.y > Vehicle.FLOOR_FLOOR,
		"and is put back on it rather than falling for ever (y %.2f)"
		% _car.global_position.y)
	# **Full 3D distance, not flat.** Measuring only x/z was vacuous against the fault
	# this test exists for: a car in free-fall directly beneath its start scores a
	# perfect 0.0m, and it read 0.0 whether the guard ran or was disabled entirely. The
	# vertical term is the whole difference between "back on the road" and "still on its
	# way to the centre of the earth".
	_check(_car.global_position.distance_to(good) < 6.0,
		"on the road under where it fell, not teleported across the district (%.1fm)"
		% _car.global_position.distance_to(good))
	# Settled, rather than "velocity is zero on the very next frame". The guard puts the
	# car down a few centimetres clear of the road so it is not inside the collider, so
	# gravity is still doing its job for the moment it takes to land -- which is the
	# difference between a car dropping onto a road and a car falling through one.
	await _idle(40)
	_check(_car.is_on_floor() and absf(_car.velocity.y) < 1.0,
		"and settles on it (on floor %s, %.1f m/s vertical)"
		% [_car.is_on_floor(), _car.velocity.y])

	# And it is a working vehicle afterwards, not a recovered wreck.
	#
	# "Is it moving" is not enough, and asserting only that was vacuous: a car falling
	# through the void still spins its wheels up to forward speed, and this passed with
	# the car sixty-seven metres under the district. What makes it a working vehicle is
	# being **on the road** and **closing on its target** -- neither of which a falling
	# one manages.
	var away := Vector3(-20.0, 0.0, 30.0)
	var opening := _flat_distance(_car.global_position, away)
	_car.issue(MoveOrder.new(away))
	var moved := false
	for i in 300:
		await physics_frame
		if _car.is_on_floor() and absf(_car.forward_speed) > 3.0 \
				and _flat_distance(_car.global_position, away) < opening - 4.0:
			moved = true
			break
	_check(moved, "and drives away from it under orders, on the road [%s]" % _car_state())
	_car.clear_orders()
	await _idle(4)


## Solid vehicles need somewhere to go. The player's autopilot steers around what is
## in its way instead of driving into it -- the other half of giving traffic mass,
## and the reason the two were kept intangible for so long.
func _test_a_vehicle_drives_around_what_is_in_its_way() -> void:
	var taxi := (load("res://Game/Traffic/Sedan.tscn") as PackedScene) \
		.instantiate() as TrafficCar
	_scene.add_child(taxi)
	# Parked, not driving: this measures the patrol car's manoeuvre, not a chase.
	taxi.set_physics_process(false)
	var lane := Vector3(20.0, 0.2, -20.0)
	taxi.global_position = lane

	await _place_unit(_car, Vector3(20.0, 0.15, 8.0))
	await _idle(6)
	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -48.0)))

	var closest := INF
	var swerved := false
	var arrived := false
	for i in 1800:
		await physics_frame
		closest = minf(closest, _flat_distance(_car.global_position,
			taxi.global_position))
		if _car.is_avoiding:
			swerved = true
		if not _car.has_orders():
			arrived = true
			break
	_check(swerved, "the patrol car went round the parked taxi rather than at it")
	_check(closest > 2.2,
		"never driving through it (closest approach %.1fm)" % closest)
	_check(arrived, "and still got where it was sent")

	taxi.queue_free()
	_car.clear_orders()
	await _idle(4)


func _test_left_click_selects() -> void:
	await _place(ROAD)
	_focus_camera_on_car()
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	_check(_controller.primary() == _car, "left-clicking the car selects it")
	_check(_ring != null and _ring.visible, "selection ring is shown")

	# **The bracket, not the torus the scene ships.** The shape is swapped in at load by
	# `Unit._tint_ring`, so the placeholder in each of the six scenes that carry a ring
	# never has to be edited again -- and a swap that silently did not happen leaves a
	# perfectly visible ring of the wrong design, which is the sort of thing only a
	# screenshot catches. Asserted on the mesh's own geometry: an ArrayMesh of flat
	# triangles, sized to this unit rather than to whatever the scene author chose.
	var ring_mesh := _ring as MeshInstance3D
	_check(ring_mesh != null and ring_mesh.mesh is ArrayMesh,
		"and it is the bracket built at load, not the scene's torus (%s)"
		% (ring_mesh.mesh.get_class() if ring_mesh and ring_mesh.mesh else "none"))
	if ring_mesh and ring_mesh.mesh:
		var span: Vector3 = ring_mesh.mesh.get_aabb().size
		# A patrol car is about 4.5m long, so its bracket should be metres across --
		# not the fixed 1m a shared placeholder would give every unit alike.
		_check(span.x > 1.5 and span.z > 1.5 and span.y < 0.01,
			"sized to the car and flat on the ground (%.1f x %.1f x %.2f)"
			% [span.x, span.z, span.y])
		# The tint is what tells a police unit from a medical one at a glance, and it is
		# applied to a *duplicated* material -- shared, it would repaint every officer.
		var ink := (ring_mesh.material_override as StandardMaterial3D).albedo_color
		var police := Palette.service(Unit.Service.POLICE)[0]
		_check(absf(ink.r - police.r) < 0.02 and absf(ink.g - police.g) < 0.02,
			"and still wearing its service colour")
		_check(_faces_down(ring_mesh.mesh as ArrayMesh) == 0,
			"and wound face-up rather than into the ground (%d of %d triangles down)"
			% [_faces_down(ring_mesh.mesh as ArrayMesh),
				_triangles(ring_mesh.mesh as ArrayMesh)])


func _test_clicking_ground_deselects() -> void:
	# A point on the deck well clear of the car.
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3(9.0, 0.0, 0.0)))
	_check(_controller.selection.is_empty(), "clicking the ground clears the selection")
	_check(_ring != null and not _ring.visible, "selection ring is hidden")


func _test_right_click_issues_order() -> void:
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	if _controller.primary() != _car:
		_check(false, "car is selected before ordering")
		return

	# Along the avenue, so the clicked point is somewhere the car can actually go.
	var aim := _car.global_position + Vector3(0.0, 0.0, -11.0)
	aim.y = 0.0
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(aim))
	_check(_car.has_orders(), "right click issued a move order")
	_check(_flat_distance(_car.move_target, aim) < 2.5,
		"order landed %.2fm from where it was clicked" % _flat_distance(_car.move_target, aim))
	_check(_marker != null and _marker.visible, "destination marker is shown")

	var arrived := await _await_arrival(900)
	_check(arrived, "carried out the clicked order")
	await _wait(5)
	_check(_marker != null and not _marker.visible, "marker cleared once the car arrived")


func _test_order_ignored_with_no_selection() -> void:
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3(9.0, 0.0, 0.0)))
	if not _controller.selection.is_empty():
		_check(false, "selection was cleared before this check")
		return
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(_car.global_position + Vector3(-9.0, 0.0, 0.0)))
	_check(not _car.has_orders(), "right click does nothing with no selection")


# --- Order queue -------------------------------------------------------------

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

## The layout invariant that replaced the six checks describing a docked bar.
##
## Each of those six named the neighbours it compared, so a renamed panel made them pass
## on an empty comparison. This asks the same questions of *every* panel at once, off a
## table resolved by path -- so a rename fails loudly here instead, which is the honest
## cost of asserting on a layout at all.
func _test_hud_panels_hold_their_corners() -> void:
	if _bar == null or _help == null:
		_check(false, "the HUD has its panel layer")
		return
	await _idle(3)
	# The viewport, not the window. The project stretches canvas items, so the
	# interface is laid out in a 1600x900 space whatever size the window happens to be
	# -- and measuring the window instead would report a panel as the wrong width on
	# every display but one.
	var screen := root.get_visible_rect().size
	var panels := _hud_panels()
	_check(panels.size() >= 6,
		"the HUD is a set of panels (%d found)" % panels.size())
	# **Every panel inside the viewport.** Replaces nothing -- this was never checked
	# for the bar, because a bar pinned to three edges cannot leave the screen. A
	# floating panel can, and at the wrong anchor it does so silently off the bottom.
	var outside := PackedStringArray()
	for name in panels:
		if not Rect2(Vector2.ZERO, screen).encloses(panels[name] as Rect2):
			outside.append(str(name))
	_check(outside.is_empty(),
		"and every one of them is on screen (%s)"
		% ("all" if outside.is_empty() else ", ".join(outside)))

	var visible_before := _help.visible
	await _press_key(KEY_F1)
	_check(_help.visible != visible_before, "F1 toggles the controls overlay")
	await _press_key(KEY_F1)
	_check(_help.visible == visible_before, "and toggles it back")

	# **The bar must not grow over the chip above it.** Tiles that wrap to a second row
	# grow the PanelContainer, the bar grows upward with it, and the CONTROLS chip
	# silently stops being clickable -- a trap this project has fallen into five times.
	#
	# This pinned a height of 148px until August 2026, and a magic number is what would
	# have let it happen a sixth time: the block was widened for a ninth tile, the height
	# was untouched, and a check on the number would have gone red for a change that was
	# fine. What matters is not the figure, it is that the chip is still there. So the
	# assertion is the overlap itself, measured against the fattest selection.
	# **Every selectable unit at once**, because `available_abilities()` returns the
	# *union* across the selection -- so a mixed box-select is the widest the bar ever
	# gets, and it is wider than any one unit. The first cut of this selected a single
	# patrol car, whose tiles fit one row at the old width: the sabotage agent reverted
	# the widening and the check stayed green, because the fault never reached the
	# measurement. A scenario that cannot provoke the fault is no better than an
	# assertion that cannot see it.
	var everyone: Array[Unit] = []
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.service != Unit.Service.NONE:
			everyone.append(unit)
	_controller.select(everyone)
	await _idle(3)
	# Stated rather than assumed: if the roster ever shrinks below the width the bar was
	# built for, this check quietly stops testing anything and should say so.
	# Tied to the union the controller actually offers, so the grid and the ladder cannot
	# drift apart silently. The >= 9 floor stays beside it: a shrinking roster would make
	# this stop testing anything, and it should say so rather than go quiet.
	var offered := _controller.available_abilities().size()
	# **Visible tiles, not children.** The grid pools -- `_tiles` grows to the high-water
	# mark and the surplus is hidden rather than freed -- and it also carries an "empty"
	# label. Counting children read 14 for 13 abilities and was measuring the pool.
	var shown := 0
	for child in _grid.get_children():
		var tile := child as CommandIcon
		if tile and tile.visible:
			shown += 1
	_check(shown == offered and offered >= 9,
		"the fattest selection fills the bar (%d tiles for %d abilities)"
		% [shown, offered])
	var chip := _scene.get_node_or_null(
		"HUD/Root/World/ControlsToggle") as PanelContainer
	_check(chip != null, "there is a CONTROLS chip above the bar")

	# **Everything that floats above the bar, not just the chip.** The bar is a
	# PanelContainer and grows to fit its content; when it grows it covers whatever is
	# over it, silently. That has caught this project six times -- the dispatch pills, and
	# the CONTROLS chip twice -- and each time the fix pinned the *one* thing that had
	# just been eaten. This asserts the whole floor, which is what would have caught all
	# six rather than the sixth.
	# **No two panels overlap, and the middle is left to the city.**
	#
	# This replaces two checks that each hard-coded the neighbours they cared about --
	# "the bar covers nothing floating above it" walked the direct children of
	# `Root/World` against the bar's top edge, and "the top bar shares its band with
	# nothing" named CallList and MinimapCard as strings. Both were written for a
	# layout with one docked bar and a couple of floating cards. Neither survives the
	# panels being floated into corners, and worse, both went *green* if a name
	# changed: `get_node_or_null` returning null recorded no clash.
	#
	# Asked as one question of the whole set, it covers all six of the historical
	# incidents (the dispatch pills, the CONTROLS chip twice, and the three from this
	# session) rather than the specific pair each fix pinned.
	var clashes := PackedStringArray()
	var names := panels.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = panels[names[i]]
			var b: Rect2 = panels[names[j]]
			if a.intersects(b):
				clashes.append("%s/%s" % [names[i], names[j]])
	_check(clashes.is_empty(),
		"no two panels overlap (%s)"
		% ("clear" if clashes.is_empty() else ", ".join(clashes)))

	# The city has to be visible through the middle of them. This is what "leaving N%%
	# of the screen to the world" was really protecting, asked of the place the player
	# actually looks rather than of one panel's height.
	# The central 40%. Half the screen reaches x=400 at 1600x900, which is inside any
	# sane left-hand column -- a bar that strict would forbid the reference's own
	# layout rather than protect the view through it.
	var middle := Rect2(screen * 0.3, screen * 0.4)
	var intruders := PackedStringArray()
	for name in panels:
		if (panels[name] as Rect2).intersects(middle):
			intruders.append(str(name))
	_check(intruders.is_empty(),
		"and the middle of the screen is the city's (%s)"
		% ("clear" if intruders.is_empty() else ", ".join(intruders)))

	# Nor may the layout depend on the selection. A panel that changed size between
	# selections would jump the world view and re-open the trap above -- which is why
	# the blocks carry minimum sizes rather than being left to their contents.
	var fat := _hud_panels()
	_controller.select([])
	await _idle(3)
	var lean := _hud_panels()
	_controller.select(everyone)
	await _idle(3)
	var moved := PackedStringArray()
	for name in fat:
		if lean.has(name) and not (fat[name] as Rect2).is_equal_approx(lean[name]):
			moved.append(str(name))
	var fat_height: float = (fat.get("commands", Rect2()) as Rect2).size.y
	var lean_height: float = (lean.get("commands", Rect2()) as Rect2).size.y
	_check(moved.is_empty() and absf(fat_height - lean_height) < 1.0,
		"and no panel moves with the selection (%s, %.0f against %.0f)"
		% [("none" if moved.is_empty() else ", ".join(moved)), fat_height, lean_height])

	# The visible route in: the card ships closed, the chip above the bar opens it.
	_check(not _help.visible, "the controls card ships closed")
	var toggle := _scene.get_node_or_null(
		"HUD/Root/World/ControlsToggle") as PanelContainer
	if toggle == null:
		_check(false, "a visible CONTROLS chip to click")
		return
	await _click(MOUSE_BUTTON_LEFT, toggle.get_global_rect().get_center())
	_check(_help.visible, "clicking the chip opens it")
	await _click(MOUSE_BUTTON_LEFT, toggle.get_global_rect().get_center())
	_check(not _help.visible, "and clicking again closes it")

	# The card itself: sectioned by function, and the keyboard drawn as keys.
	var panel := _help.get_node_or_null("Help") as ControlsPanel
	if panel == null:
		_check(false, "the card carries the controls panel")
		return
	var titles := PackedStringArray()
	var keycaps := 0
	for child in panel.get_children():
		var label := child as Label
		if label:
			titles.append(label.text)
		for part in child.get_children():
			var cap := part as TextureRect
			if cap and cap.texture != null:
				keycaps += 1
	_check(titles.has("SELECT") and titles.has("ORDER") and titles.has("CAMERA")
			and titles.has("MINIMAP") and titles.has("SHIFT"),
		"the bindings are sectioned by function (%s)" % ", ".join(titles))
	_check(keycaps >= 15,
		"and the keyboard is drawn as keycaps, not prose (%d caps)" % keycaps)


## The one that matters. Picking is a camera ray fired from _unhandled_input, and the
## GUI sees every click first -- so a control that covers the screen silently eats the
## game. The old floating command bar did exactly this under a headless viewport.
func _test_bar_does_not_swallow_world_clicks() -> void:
	await _place(ROAD)
	_focus_camera_on_car()
	await _idle(3)
	_controller.clear_selection()

	var bar := _command_panel.get_global_rect()
	var above := _screen_of(_car.global_position + Vector3.UP * 0.9)
	# Without this the rest is vacuous: if the car happened to be drawn under the bar,
	# "the click did not select it" would prove nothing.
	_check(above.y < bar.position.y,
		"the car is drawn above the bar (y %.0f vs %.0f)" % [above.y, bar.position.y])

	await _click(MOUSE_BUTTON_LEFT, above)
	_check(_controller.primary() == _car, "a click above the bar still reaches the world")

	_car.clear_orders()
	await _click(MOUSE_BUTTON_RIGHT, bar.get_center())
	_check(not _car.has_orders(), "a right-click on the bar issues no order")
	_check(_controller.primary() == _car, "and leaves the selection alone")


func _test_command_grid_follows_the_selection() -> void:
	_controller.select([_car])
	await _idle(3)
	var tiles := _visible_tiles()
	var offered := _controller.available_abilities()
	_check(tiles.size() == offered.size(),
		"the grid shows one tile per ability the car offers (%d of %d)" % [
			tiles.size(), offered.size()])

	# Tiles read along the row in the same order as the keys under the player's hand.
	var order := PackedInt32Array()
	for tile in tiles:
		order.append(RTSController.COMMAND_KEYS.find(tile.ability.hotkey()))
	var sorted := true
	for i in range(1, order.size()):
		if order[i] <= order[i - 1]:
			sorted = false
	_check(sorted and (order.is_empty() or order[0] >= 0),
		"and lays them out in keyboard order (%s)" % str(order))

	_controller.select([_officer])
	await _idle(3)
	var verbs := _tile_ids()
	_check(verbs.has(&"extinguish") and verbs.has(&"secure"),
		"an officer's grid offers Extinguish and Secure (%s)" % str(verbs))
	_check(not verbs.has(&"collect"),
		"and not Collect, which is the medical service's")


func _test_command_hotkeys_run_abilities() -> void:
	_controller.select([_officer])
	await _idle(3)

	# Targeted: the key arms the ability and waits for a click, exactly as the tile does.
	await _press_key(KEY_V)
	_check(_controller.armed_ability != null
			and _controller.armed_ability.id() == &"extinguish",
		"V armed Extinguish (%s)" % _armed_id())
	var armed_tile := _armed_tiles()
	_check(armed_tile.size() == 1 and armed_tile[0] == &"extinguish",
		"and the tile lit up with it (%s)" % str(armed_tile))

	await _press_key(KEY_ESCAPE)
	_check(_controller.armed_ability == null, "Esc disarmed it")
	_check(_armed_tiles().is_empty(), "and the tile went dark")
	# Escape became the pause key in August 2026, and this is the line that keeps the
	# rebind honest at its most annoying failure: cancelling an armed ability must not
	# also throw up the pause menu.
	_check(not paused, "and did not pause the game while doing it")

	# Instant: the key fires straight away, with nothing to click.
	_officer.issue(MoveOrder.new(_officer.global_position + Vector3(0.0, 0.0, -6.0)))
	await _wait(4)
	_check(_officer.has_orders(), "the officer has an order to cancel")
	await _press_key(KEY_X)
	_check(not _officer.has_orders(), "X stopped them")

	# Ctrl is the control-group modifier, so it must not double as a command.
	_officer.issue(MoveOrder.new(_officer.global_position + Vector3(0.0, 0.0, -6.0)))
	await _wait(4)
	await _press_key(KEY_X, true)
	_check(_officer.has_orders(), "Ctrl-X is a control group key, not Stop")
	_officer.clear_orders()


## The roster lists the whole shift, not the selection. That is what makes it a control
## rather than a readout: the parked ambulance can be sent from here without first
## finding it in the street.
func _test_roster_lists_everything_under_command() -> void:
	_controller.clear_selection()
	await _idle(3)
	var chips := _visible_chips()
	var commanded := _commanded_units()
	_check(chips.size() == commanded.size(),
		"the roster lists all %d units under command (%d chips)" % [
			commanded.size(), chips.size()])
	_check(not chips.is_empty(), "and is not empty with nothing selected")

	# A civilian is put back on the map for this, because by now the suite has cleared
	# the crowd -- and a check that the roster excludes shoppers passes trivially when
	# there are no shoppers to exclude. It has to be shown refusing a real one.
	var shopper := (load(CIVILIAN_SCENE) as PackedScene).instantiate() as Civilian
	_scene.add_child(shopper)
	shopper.global_position = Vector3(0.0, 0.2, 0.0)
	await _idle(3)

	var strays := PackedStringArray()
	for chip in _visible_chips():
		# A standby chip legitimately has no unit -- it stands for one still in the
		# station. Only a chip that is neither is a stray.
		if not chip.standby.is_empty():
			continue
		if chip.unit == null or chip.unit.service == Unit.Service.NONE:
			strays.append(str(chip.unit))
	_check(strays.is_empty() and _visible_chips().size() == commanded.size(),
		"and refuses a civilian standing in the middle of the map%s" % (
			"" if strays.is_empty() else " -- listed " + ", ".join(strays)))
	shopper.queue_free()
	await _idle(3)


## One service per line, and never two on the same line.
##
## The roster was a single wrapping flow, so a patrol car and an ambulance shared a row
## and the next ambulance began a new one -- a shape that changed every time a unit was
## bought. Asserted by **reading the rows back**, not by trusting the grouping code:
## every visible chip is asked which row it sits in, and a row that holds two services is
## the failure. That form survives the rows being rebuilt, reordered or reparented.
func _test_the_roster_groups_by_service() -> void:
	var roster := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/RosterBlock/Body/Roster") as Roster
	if roster == null:
		_check(false, "the HUD carries a roster")
		return
	await _idle(3)

	# `service -> row`, built from what is actually on screen.
	var seen := {}
	var mixed := PackedStringArray()
	for chip in _visible_chips():
		var service: int = chip.unit.service if chip.unit \
			else int(chip.standby.get("service", Unit.Service.NONE))
		var row := chip.get_parent()
		if seen.has(service) and seen[service] != row:
			mixed.append("service %d split across rows" % service)
		seen[service] = row
	# The other direction: no row may carry two services.
	var owners := {}
	for service in seen:
		var row: Variant = seen[service]
		if owners.has(row):
			mixed.append("services %d and %d share a row" % [owners[row], service])
		owners[row] = service

	_check(not seen.is_empty(), "the roster has chips to group (%d)" % seen.size())
	_check(mixed.is_empty(), "each service keeps its own line (%s)" % (
		"clear" if mixed.is_empty() else ", ".join(mixed)))

	# And the fixture really does have more than one service on the strip, or the two
	# assertions above are true of any roster at all.
	_check(seen.size() >= 2,
		"with at least two services on it to keep apart (%d)" % seen.size())


func _test_roster_marks_the_selection() -> void:
	_controller.select([_cars[0], _cars[1]])
	await _idle(3)
	var marked := PackedStringArray()
	for chip in _visible_chips():
		if chip._badge.highlighted:
			marked.append(chip.unit.display_name)
	_check(marked.size() == 2,
		"selecting two rings two chips (%d: %s)" % [marked.size(), ", ".join(marked)])
	_check(marked.has(_cars[0].display_name) and marked.has(_cars[1].display_name),
		"and they are the two that were selected")

	_controller.clear_selection()
	await _idle(3)
	var still := 0
	for chip in _visible_chips():
		if chip._badge.highlighted:
			still += 1
	_check(still == 0, "clearing the selection un-rings them (%d still ringed)" % still)


## Sending one unit from the bar is the reason the roster exists, so it is clicked for
## real rather than called directly -- which also proves a chip is reachable inside the
## bar, and that the bar does not intercept its own children's clicks.
func _test_roster_chip_selects_a_unit() -> void:
	_controller.clear_selection()
	await _idle(3)
	var target := _chip_for(_ambulance)
	if target == null:
		_check(false, "the ambulance has a chip to click")
		return

	await _click(MOUSE_BUTTON_LEFT, target.get_global_rect().get_center())
	_check(_controller.selection.size() == 1 and _controller.primary() == _ambulance,
		"clicking the ambulance's chip selected it, and only it (%d selected)"
			% _controller.selection.size())


func _chip_for(unit: Unit) -> UnitChip:
	for chip in _visible_chips():
		if chip.unit == unit:
			return chip
	return null


func _commanded_units() -> Array[Unit]:
	var found: Array[Unit] = []
	for node in _scene.get_node("Units").get_children():
		var unit := node as Unit
		if unit != null and unit.service != Unit.Service.NONE:
			found.append(unit)
	return found


func _test_portrait_names_the_lead() -> void:
	_controller.select([_car])
	# The portrait refreshes in _process, so give it a frame to catch up.
	await _idle(3)
	_check(_portrait._name.text == _car.display_name,
		"the portrait names the selected unit ('%s')" % _portrait._name.text)

	_controller.select([_cars[0], _cars[1]])
	await _idle(3)
	_check(_portrait._name.text == "2 units selected",
		"and counts a group instead ('%s')" % _portrait._name.text)
	_check(_portrait._stats.text.contains(_cars[0].display_name),
		"naming the lead in the stats line ('%s')" % _portrait._stats.text)
	_controller.clear_selection()


## The avatars are photographs of the actual prefabs, rendered by build_portraits.gd.
## Miss that step and every one falls back to a drawn outline -- which still works, and
## so goes unnoticed until someone looks at the bar.
func _test_units_carry_a_service_and_a_portrait() -> void:
	var missing := PackedStringArray()
	for unit in _commanded_units():
		if unit.portrait == null:
			missing.append(unit.display_name)
	_check(missing.is_empty(), "every commanded unit has a rendered portrait%s" % (
		"" if missing.is_empty() else " -- missing: " + ", ".join(missing)))

	_check(_ambulance.service == Unit.Service.MEDICAL,
		"the ambulance is a medical unit (%d)" % _ambulance.service)
	_check(_car.service == Unit.Service.POLICE,
		"the patrol car is a police unit (%d)" % _car.service)
	_check(_officer.service == Unit.Service.POLICE,
		"and so is an officer (%d)" % _officer.service)
	# The ambulance is the only unit that should draw the medical symbol, and it is
	# picked by service rather than by whether it happens to carry a stretcher.
	_check(_ambulance.icon() == &"ambulance" and _car.icon() == &"car",
		"their fallback symbols differ ('%s' vs '%s')" % [
			_ambulance.icon(), _car.icon()])

	var civilian := _first_civilian()
	if civilian:
		_check(civilian.service == Unit.Service.NONE,
			"a civilian belongs to no service (%d)" % civilian.service)


func _visible_tiles() -> Array[CommandIcon]:
	var found: Array[CommandIcon] = []
	for tile in _grid._tiles:
		if tile.visible:
			found.append(tile)
	return found


func _tile_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		found.append(tile.ability.id())
	return found


func _armed_tiles() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		if tile.armed:
			found.append(tile.ability.id())
	return found


func _active_tiles() -> Array[StringName]:
	var found: Array[StringName] = []
	for tile in _visible_tiles():
		if tile.active:
			found.append(tile.ability.id())
	return found


func _armed_id() -> StringName:
	return _controller.armed_ability.id() if _controller.armed_ability else &"none"


func _visible_chips() -> Array[UnitChip]:
	var found: Array[UnitChip] = []
	for chip in _roster._chips:
		if chip.visible:
			found.append(chip)
	return found


# --- Calls -------------------------------------------------------------------

## Every symbol key the game uses must resolve to a texture from the icon pack --
## otherwise a tile quietly falls back to the plainer drawn primitive and nobody
## notices until it looks wrong in a screenshot.
func _test_the_interface_wears_the_icon_pack() -> void:
	var wanted: Array[StringName] = [&"arrow", &"halt", &"cross", &"droplet",
		&"stretcher", &"door_in", &"door_out", &"cone", &"station", &"flame",
		&"car", &"ambulance", &"person", &"beacon", &"horn", &"unknown"]
	var missing := PackedStringArray()
	for key in wanted:
		if Glyph._texture(key) == null:
			missing.append(key)
	_check(missing.is_empty(),
		"every glyph key has its icon from the pack%s"
		% ("" if missing.is_empty() else " -- missing: " + ", ".join(missing)))


func _test_streets_have_names() -> void:
	# Six road bands per axis are the district's avenues and streets, so every point
	# in it has an address. The corners of the outer ring pin the two ends of both
	# tables; the mid-block point pins "nearest crossroads", not "containing".
	var north_west := CityGrid.place_name(CityGrid.junction(Vector2i(0, 0)))
	_check(north_west == "1st Ave & Elm St",
		"the north-west junction is 1st & Elm ('%s')" % north_west)
	var south_east := CityGrid.place_name(
		CityGrid.junction(Vector2i(CityGrid.BANDS - 1, CityGrid.BANDS - 1)))
	_check(south_east == "6th Ave & Birch St",
		"and the south-east one is 6th & Birch ('%s')" % south_east)
	# Partway down a block still has to answer, and answer with the nearest crossroads.
	var near := CityGrid.place_name(Vector3(18.0, 0.0, -55.0))
	_check(near == "4th Ave & Oak St",
		"a point mid-block takes the nearest junction ('%s')" % near)


func _test_an_incident_opens_a_call() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.5)
	await _idle(4)

	var open := _board.open_calls()
	_check(open.size() == 1, "one fire opens one call (%d)" % open.size())
	if open.is_empty():
		return
	_check(open[0].kind == Call.Kind.FIRE,
		"and it is a fire call ('%s')" % open[0].title())
	_check(open[0].place == CityGrid.place_name(fire.global_position),
		"addressed to the nearest junction ('%s')" % open[0].place)
	_check(open[0].status == Call.Status.WAITING,
		"and starts unattended (%d)" % open[0].status)


## The reason calls exist. A fire left alone becomes eight bodies, and eight rows on the
## board would be eight jobs when it is plainly still one.
func _test_a_spreading_fire_stays_one_call() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.95)
	await _idle(4)
	_check(_board.open_calls().size() == 1, "starting from one call")

	# Let it throw off children of its own rather than placing them by hand, so this
	# measures the real spread and not a staged one. Fire.spread_interval is 8s, so a
	# second body takes about 480 physics frames to appear.
	var spread := 0
	for i in 900:
		await physics_frame
		spread = get_nodes_in_group(Fire.FIRE_GROUP).size()
		if spread >= 2:
			break
	await _idle(4)

	_check(spread >= 2, "the fire spread to %d bodies" % spread)
	var open := _board.open_calls()
	_check(open.size() == 1,
		"and they are still one call (%d calls for %d fires)" % [open.size(), spread])
	if not open.is_empty():
		_check(open[0].incidents.size() == spread,
			"which holds all %d of them (%d)" % [spread, open[0].incidents.size()])


func _test_a_call_upgrades_when_the_scene_changes() -> void:
	await _clear_calls()
	var spot := Vector3(20.0, 0.0, 20.0)
	_spawn_fire(spot, 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.size() != 1:
		_check(false, "a fire call to upgrade (%d)" % open.size())
		return
	_check(open[0].kind == Call.Kind.FIRE, "a fire, on its own")

	# Someone hurt at the same scene makes it the job that needs two services, and the
	# call has to say so without anyone telling it.
	_spawn_casualty(spot + Vector3(3.0, 0.0, 0.0))
	await _idle(4)
	_check(open[0].kind == Call.Kind.RESCUE,
		"a casualty at the same scene upgrades it to a rescue ('%s')" % open[0].title())
	_check(_board.open_calls().size() == 1,
		"and it is still one call (%d)" % _board.open_calls().size())


## The board reports a scene in words and draws the number as a bar. It used to
## print one percentage per incident, so a fire that had spread six times read as
## six numbers in a row.
func _test_the_board_draws_progress_as_a_bar() -> void:
	await _clear_calls()
	var spot := Vector3(20.0, 0.0, -20.0)
	# **A hose fire**, so the capability gate is real: an officer carries an extinguisher
	# and can fight a bin, which is why the first version of this check passed while the
	# officer was busily extinguishing.
	var fire := _spawn_fire(spot, 0.6)
	await _idle(8)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to read")
		return
	var call := open[0]
	_check(not ("%" in call.describe()),
		"the board says what a scene is doing in words, not percentages ('%s')"
		% call.describe())
	_check(absf(call.progress() - 0.4) < 0.12,
		"a fire well alight reads as barely started (%.2f done)" % call.progress())

	var rows := _visible_call_rows()
	if rows.is_empty():
		_check(false, "a row on screen to read it off")
		return
	# **Found, not counted to.** This read `get_child(3)` until the UI kit's status dot
	# was added at the head of the row and shifted every column by one. A positional
	# index into a layout is a check that breaks the next time the layout gains a
	# column -- which is a fact about the *test*, not about the game.
	var bar: ProgressStrip = null
	for cell in rows[0].get_child(0).get_children():
		if cell is ProgressStrip:
			bar = cell as ProgressStrip
	if bar == null:
		_check(false, "the row carries a progress bar")
		return
	_check(absf(bar.value - call.progress()) < 0.02,
		"and the row draws that as a bar (%.2f)" % bar.value)

	fire.douse(0.45)
	await _idle(6)
	_check(bar.value > 0.7, "knocking the fire down fills it (%.2f)" % bar.value)

	# Two more fires at the same scene: one line that counts them, not three
	# numbers side by side.
	_spawn_fire(spot + Vector3(3.5, 0.0, 0.0), 0.5)
	_spawn_fire(spot + Vector3(-3.5, 0.0, 0.0), 0.5)
	await _idle(8)
	_check(call.describe() == "3 fires",
		"several incidents are counted, not listed ('%s')" % call.describe())
	await _clear_calls()


func _test_a_call_notices_a_unit_arriving() -> void:
	await _clear_calls()
	# Well away from ROAD, where the rest of the suite parks the patrol car -- 47m,
	# against the 15m that counts as being at a scene. Put the call next to it instead
	# and it opens already attended, which is a check that proves nothing.
	var spot := Vector3(-20.0, 0.0, -20.0)
	await _place(ROAD)
	_spawn_fire(spot, 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to attend")
		return

	_check(_board.waiting_count() == 1,
		"the board counts it unattended (%d)" % _board.waiting_count())
	await _place(spot + Vector3(0.0, 0.0, 6.0))
	await _idle(4)
	_check(open[0].status == Call.Status.ON_SCENE,
		"a patrol car pulling up marks it attended (%d)" % open[0].status)
	_check(_board.waiting_count() == 0,
		"and it stops counting as waiting (%d)" % _board.waiting_count())

	# Ambient traffic carries no service, so a taxi driving past is not a response.
	await _place(ROAD)
	await _idle(4)
	_check(open[0].status == Call.Status.WAITING,
		"driving away leaves it unattended again (%d)" % open[0].status)


func _test_a_call_closes_when_its_incidents_do() -> void:
	await _clear_calls()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.4)
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to close")
		return
	var closed: Array = []
	open[0].closed.connect(func(_call: Call, ok: bool) -> void: closed.append(ok))

	fire.douse(2.0)
	await _idle(4)
	_check(closed.size() == 1 and closed[0] == true,
		"putting the fire out closes its call successfully (%s)" % str(closed))
	_check(_board.open_calls().is_empty(),
		"and it leaves the board (%d still open)" % _board.open_calls().size())


## Getting three of four casualties out is not a job well done, so any loss fails the
## whole call rather than the rest of it quietly succeeding.
func _test_a_lost_casualty_fails_its_call() -> void:
	await _clear_calls()
	var casualty := _spawn_casualty(Vector3(-20.0, 0.0, 20.0))
	casualty.decline_per_second = 4.0
	await _idle(4)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to fail")
		return
	var call := open[0]
	_check(call.kind == Call.Kind.MEDICAL, "a medical call ('%s')" % call.title())

	for i in 200:
		await physics_frame
		if not call.is_open():
			break
	_check(call.status == Call.Status.FAILED,
		"losing the casualty fails the call (%d)" % call.status)
	_check(_board.open_calls().is_empty(),
		"and closes it (%d still open)" % _board.open_calls().size())


func _test_clicking_a_call_moves_the_camera() -> void:
	await _clear_calls()
	var spot := Vector3(-20.0, 0.0, -20.0)
	_spawn_fire(spot, 0.4)
	await _idle(6)

	_camera.stop_following()
	_camera.focus = Vector3(40.0, 0.0, 40.0)
	await _idle(6)
	var rows := _visible_call_rows()
	if rows.is_empty():
		_check(false, "a call row to click (%d open)" % _board.open_calls().size())
		return

	await _click(MOUSE_BUTTON_LEFT, rows[0].get_global_rect().get_center())
	_check(_flat_distance(_camera.focus, spot) < 2.0,
		"clicking the row put the camera on the call (%.1fm away)"
			% _flat_distance(_camera.focus, spot))
	await _clear_calls()


## Dispatch traffic. The district is 260m and the camera sees about a fifth of it, so
## the log's job is telling the player about the four fifths they cannot see.
##
## The interesting half of this check is the *repeat suppression*. The board emits
## `call_changed` on every tick a call's state moves, so a crew standing at a scene
## would announce its arrival for as long as it stood there -- once a frame, until the
## log was nothing but one unit saying it had arrived. A readout nobody can read is
## worse than no readout: it costs the same corner of the screen and teaches the player
## to ignore it.
func _test_the_radio_reports_what_happens() -> void:
	await _clear_calls()
	var radio := _scene.get_node_or_null("HUD/Root/World/RadioLog") as RadioLog
	_check(radio != null, "the interface carries a radio log")
	if radio == null:
		return
	for line in radio.get_children():
		line.free()

	# A job opening is the first thing worth hearing.
	var fire := _spawn_fire(Vector3(28.0, 0.0, 28.0), 0.4)
	await _idle(6)
	_check(radio.get_child_count() >= 1,
		"a call opening puts a line on it (%d)" % radio.get_child_count())
	# Across the whole log rather than off the end of it: if a unit happens to be
	# standing within the on-scene radius when the call opens -- which is entirely
	# possible, since nothing moves the fleet away between tests -- the call opens and
	# goes ON SCENE in the same breath, and the newest line is the arrival.
	var opened := _radio_text(radio, true)
	_check("CONTROL" in opened, "which says who is speaking ('%s')" % opened)

	# A crew arriving says so exactly once, however long it stands there.
	#
	# Counted by **content**, not by how many lines are on the log. Comparing the child
	# count before and after was the first attempt and it was vacuous: say() trims to
	# MAX_LINES, so the number it measured was pinned at 4 by the very thing under test,
	# and a log reading "ON SCENE | ON SCENE | ON SCENE | ON SCENE" passed it happily.
	# A flood and silence are indistinguishable once the log is full; only the text
	# tells them apart.
	await _place_unit(_officer, Vector3(30.0, 0.05, 28.0))
	await _idle(60)
	await _idle(120)
	# Counted off the same reader the other log checks use, rather than reaching for a
	# Label directly -- a log line is a framed row with the words inside it now.
	var arrivals := 0
	for line in _radio_text(radio, true).split(" | "):
		if "ON SCENE" in line:
			arrivals += 1
	_check(arrivals == 1,
		"a crew standing on scene announces itself once, not once a frame (%d of %d "
		% [arrivals, radio.get_child_count()]
		+ "lines say it: %s)" % _radio_text(radio, true))

	# The outcome, per incident rather than per call.
	var before := radio.get_child_count()
	fire.douse(2.0)
	await _idle(6)
	_check(radio.get_child_count() > before,
		"putting the fire out is worth a line too (%d -> %d)"
		% [before, radio.get_child_count()])
	_check("FIRE" in _radio_text(radio), "naming the service ('%s')" % _radio_text(radio))

	# And it does not grow without bound.
	for i in 12:
		radio.say("filler %d" % i)
	_check(radio.get_child_count() <= RadioLog.MAX_LINES,
		"the log keeps only the last %d lines (%d)"
		% [RadioLog.MAX_LINES, radio.get_child_count()])

	_officer.clear_orders()
	await _clear_incidents()
	await _clear_calls()


## The newest line on the log, or every line joined when [param all] is set.
## Every HUD panel that occupies space, as name -> screen rect.
##
## **Resolved by path, deliberately.** The checks this feeds used to walk a container's
## children, which meant anything reparented dropped silently out of coverage and
## anything renamed made the check pass on an empty set. Naming them means a rename
## fails loudly here instead, and the list is the one place to edit when a panel is
## added -- which is the honest cost of asserting on a layout at all.
##
## Hidden panels are skipped: the help card, the debrief and the shop are modal things
## that are *meant* to cover the screen when they are up.
func _hud_panels() -> Dictionary:
	var wanted := {
		"status": "HUD/Root/World/StatusStrip",
		"score": "HUD/Root/World/ScoreStrip",
		"objective": "HUD/Root/World/ObjectiveBar",
		"calls": "HUD/Root/World/CallList",
		"minimap": "HUD/Root/World/MinimapCard",
		"mapcontrols": "HUD/Root/World/MapControls",
		"radio": "HUD/Root/World/RadioLog",
		"controls": "HUD/Root/World/ControlsToggle",
		"unit": "HUD/Root/Bar/Row/PortraitBlock",
		"roster": "HUD/Root/Bar/Row/RosterBlock",
		"commands": "HUD/Root/Bar/Row/CommandBlock",
		"dispatch": "HUD/Root/Bar/Row/DispatchBlock",
		"buy": "HUD/Root/World/BuyButton",
	}
	var found := {}
	for name in wanted:
		var panel := _scene.get_node_or_null(str(wanted[name])) as Control
		if panel and panel.visible and panel.size.x > 1.0 and panel.size.y > 1.0:
			found[name] = panel.get_global_rect()
	return found


func _radio_text(radio: RadioLog, all := false) -> String:
	var lines := PackedStringArray()
	for child in radio.get_children():
		# **Looks inside the row.** Log lines were bare Labels until the UI kit's
		# notification frames arrived, and are now a Label inside a PanelContainer. A
		# reader that only understood the old shape returned "" for every line and took
		# three checks with it -- while the log itself was working perfectly.
		var label := child as Label
		if label == null:
			for inner in child.get_children():
				if inner is Label:
					label = inner as Label
		if label:
			lines.append(label.text)
	if lines.is_empty():
		return ""
	return " | ".join(lines) if all else lines[lines.size() - 1]


## The minimap as a control surface: left-click looks, right-click orders, and the
## view is drawn as the camera frustum's actual footprint on the ground.
## The map's own zoom buttons, which do what the wheel does for anyone who has not
## discovered the wheel.
##
## **Asserted on the camera moving, not on the buttons existing.** Twice this session a
## check passed on a feature that was doing nothing -- a pre-warm that only ever failed,
## and seven characters placed but never animated -- because the cheap half was the half
## that got tested.
## How many of [param mesh]'s triangles face the ground rather than the sky.
##
## **The one property of a flat marker that nothing else can witness.** Class, size,
## position and colour all survive a mesh being wound backwards, and `Markers._mesh`
## fills the normal array with `Vector3.UP` regardless -- so a bracket built face-down is
## byte-identical to a correct one in every reading the suite took, and simply invisible
## in the game. Found by sabotage, which reversed the winding and reddened nothing at all.
## This reads the vertices back and works the sign out from the winding itself.
func _faces_down(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var down := 0
	var i := 0
	while i + 2 < verts.size():
		# **Godot's front face is wound clockwise seen from the front**, so a triangle
		# facing +Y yields a *negative* y from this cross product. Getting that backwards
		# is how this helper first shipped: it called both correct meshes face-down and
		# went green on the sabotage that actually inverted them. Checked against
		# `SurfaceTool.generate_normals()` and a front-face raycast before trusting it.
		var facing := -(verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).y
		if facing <= 0.0:
			down += 1
		i += 3
	return down


func _triangles(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


## The destination reticle: the other half of the in-world pass.
##
## Asserted on the mesh the controller swapped in and on the queue still being drawn from
## it, because the marker is *duplicated* per queued order -- a shape built in the wrong
## place would give the first order a reticle and every queued one a torus.
func _test_the_move_marker_is_a_reticle() -> void:
	var marker := _scene.get_node_or_null("MoveMarker") as MeshInstance3D
	if marker == null:
		_check(false, "the map carries a move marker")
		return
	_check(marker.mesh is ArrayMesh,
		"the move marker is the reticle built at load (%s)"
		% (marker.mesh.get_class() if marker.mesh else "none"))
	var span: Vector3 = marker.mesh.get_aabb().size if marker.mesh else Vector3.ZERO
	_check(span.x > 1.0 and span.y < 0.01,
		"flat on the ground and about a metre across (%.1f x %.2f)" % [span.x, span.y])
	_check(_faces_down(marker.mesh as ArrayMesh) == 0,
		"and wound face-up (%d of %d triangles down)"
		% [_faces_down(marker.mesh as ArrayMesh), _triangles(marker.mesh as ArrayMesh)])

	# Queue two orders and confirm the copies carry the same shape.
	_controller.select([_car])
	await _idle(3)
	# Both destinations measured off where the car actually is. `ROAD` is a fixture
	# position the car is often already standing on, and an order that is satisfied on
	# the frame it is issued leaves one marker rather than two -- which is how this check
	# failed twice before the staging was the problem rather than the code.
	var from := _car.global_position
	_car.issue(MoveOrder.new(from + Vector3(0.0, 0.0, -30.0)))
	# `queue` true, or the second order replaces the first.
	_car.issue(MoveOrder.new(from + Vector3(0.0, 0.0, -60.0)), true)
	await _idle(6)
	_check(_car.orders.size() == 2,
		"two orders are queued to draw (%d)" % _car.orders.size())
	var drawn := 0
	var wrong := 0
	for node in _controller._markers:
		if not node.visible:
			continue
		drawn += 1
		if (node as MeshInstance3D).mesh != marker.mesh:
			wrong += 1
	_check(drawn >= 2 and wrong == 0,
		"and a queued order's copy carries it too (%d drawn, %d wrong)" % [drawn, wrong])
	_car.clear_orders()
	_controller.clear_selection()
	await _idle(3)


func _test_the_map_zoom_buttons_work() -> void:
	var controls := _scene.get_node_or_null(
		"HUD/Root/World/MapControls") as MapControls
	if controls == null or controls.get_child_count() < 2:
		_check(false, "the minimap carries its zoom buttons")
		return
	_check(controls.camera != null, "the zoom buttons are wired to the camera")
	if controls.camera == null:
		return
	# Away from either stop, or a clamp hides the result.
	controls.camera._target_distance = (controls.camera.min_distance
		+ controls.camera.max_distance) * 0.5
	var start: float = controls.camera._target_distance
	(controls.get_child(0) as Button).pressed.emit()
	var pulled_in: float = controls.camera._target_distance
	(controls.get_child(1) as Button).pressed.emit()
	(controls.get_child(1) as Button).pressed.emit()
	var pushed_out: float = controls.camera._target_distance
	_check(pulled_in < start and pushed_out > pulled_in,
		"+ pulls the view in and - pushes it out (%.0f -> %.0f -> %.0f)"
		% [start, pulled_in, pushed_out])


## The top-right strip: the fleet count it advertises, and the only on-screen way into
## the pause card.
##
## **The count is asserted on a change, not on a match.** Reading the label once and
## comparing it to the station's own total passes just as happily when the strip is a
## dead label that happened to be built with the right number in it -- which is the exact
## shape of the two features this suite has caught doing nothing. Buying a unit and
## watching the label follow is the cheapest thing that cannot pass while disconnected.
##
## The button is asserted on the *tree freezing*, for the same reason: a button that
## opens a card but leaves the district running is not a pause button.
func _test_the_score_strip_reads_and_pauses() -> void:
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	if strip == null or _station == null:
		_check(false, "the HUD carries a score strip")
		return

	var kept_funds := _station.funds
	var before := _strip_units(strip)
	_station.funds = maxi(_station.funds, 10000)
	var bought := _station.purchase(&"patrol")
	await _idle(2)
	var after := _strip_units(strip)
	_check(bought and after == before + 1,
		"buying a unit moves the strip's UNITS count (%d -> %d)" % [before, after])

	# Back to the books the rest of the suite was handed: this runs mid-session and
	# several later checks count the fleet and the purse.
	_station.owned[&"patrol"] = int(_station.owned.get(&"patrol", 0)) - 1
	_station.funds = kept_funds
	_station.roster_changed.emit()
	await _idle(2)

	var buttons: Array[Button] = []
	for node in strip.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	if buttons.size() < 2:
		_check(false, "the strip carries its pause and settings buttons")
		return

	buttons[0].pressed.emit()
	await _idle(2)
	var froze: bool = _menu.visible and _menu.screen == GameMenu.Screen.PAUSE and paused
	_check(froze, "its pause button opens the pause card and freezes the district")
	_menu.resume()
	await _idle(2)
	# **The transition, not the reading.** `not paused` on its own is trivially true when
	# the button never paused anything -- a sabotage that gutted `_open()` left this line
	# green while the check above went red. Carrying `froze` in makes it say what it means:
	# the district was frozen by that button and thawed again.
	_check(froze and not paused, "and resuming thaws it again")


## The number the strip's UNITS block is showing, or -1 if it has no such block.
func _strip_units(strip: ScoreStrip) -> int:
	var entry: Dictionary = strip._blocks.get(&"units", {})
	if entry.is_empty():
		return -1
	var label := entry["value"] as Label
	return int(label.text) if label and label.text.is_valid_int() else 0


func _test_the_minimap_commands_camera_and_shift() -> void:
	var minimap := _scene.get_node_or_null(
		"HUD/Root/World/MinimapCard/Minimap") as Minimap
	if minimap == null:
		_check(false, "the HUD carries a minimap")
		return

	_camera.stop_following()
	_camera.focus = Vector3.ZERO
	await _idle(4)
	var spot := Vector3(60.0, 0.0, 60.0)
	var pixel: Vector2 = minimap.get_global_rect().position + minimap._to_map(spot)
	await _click(MOUSE_BUTTON_LEFT, pixel)
	_check(_flat_distance(_camera.focus, spot) < 6.0,
		"left-clicking the map looked there (%.1fm off)"
		% _flat_distance(_camera.focus, spot))

	# The view quad: centred on the focus, wider at its far edge than its near one --
	# a tilted camera's footprint is a trapezoid -- and *capped*: the honest frustum
	# reaches the best part of 100m towards the skyline, which turned the marker into
	# half the map.
	await _idle(4)
	var centre := _camera.ground_point(Vector2(0.5, 0.5))
	_check(_flat_distance(centre, _camera.focus) < 8.0,
		"the view footprint centres on the camera focus (%.1fm off)"
		% _flat_distance(centre, _camera.focus))
	var footprint := minimap.view_footprint()
	if footprint.size() != 4:
		_check(false, "the minimap shapes a four-corner view footprint")
		return
	var near_width := footprint[0].distance_to(footprint[1])
	var far_width := footprint[3].distance_to(footprint[2])
	_check(far_width > near_width and near_width > 0.0,
		"and is wider at its far edge (%.0fm far, %.0fm near)"
		% [far_width, near_width])
	var eye := _camera.global_position
	var eye_ground := Vector3(eye.x, 0.0, eye.z)
	var reach: float = (eye - _camera.focus).length() * Minimap.VIEW_REACH
	var longest := 0.0
	for point in footprint:
		longest = maxf(longest, (point - eye_ground).length())
	_check(longest <= reach + 0.5,
		"and its far sweep is capped, so the marker stays a marker (%.0fm of %.0fm)"
		% [longest, reach])

	# Right-click: the same meaning it has out in the world -- an order.
	await _place(ROAD)
	_controller.select([_car])
	await _idle(3)
	var order_spot := Vector3(20.0, 0.0, -45.0)
	await _click(MOUSE_BUTTON_RIGHT,
		minimap.get_global_rect().position + minimap._to_map(order_spot))
	var destination := _car.current_order().destination() \
		if _car.current_order() else Vector3.INF
	_check(_car.has_orders()
			and _flat_distance(destination, order_spot) < 6.0,
		"right-clicking the map sent the selection there (%.1fm off)"
		% (_flat_distance(destination, order_spot) if _car.has_orders() else -1.0))
	_car.clear_orders()
	_controller.clear_selection()


func _visible_call_rows() -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	for row in _call_list._rows:
		if row.visible:
			found.append(row)
	return found


## Clears every incident and lets the board close the calls that held them, so each
## check starts from an empty board rather than from whatever the last one left.
func _clear_calls() -> void:
	await _clear_incidents()
	await _idle(4)


func _test_person_walks() -> void:
	# Off the junction and onto the pavement of the centre block: a route that only
	# exists on the person navigation mesh, since it ends where no car can go.
	await _place_unit(_officer, Vector3(18.0, 0.1, 24.0))
	var target := Vector3(12.0, 0.0, 12.0)
	_officer.issue(MoveOrder.new(target))
	var arrived := await _await_orders_done(_officer, 1800)
	_check(arrived, "the officer walked to the target")
	_check(_flat_distance(_officer.global_position, target) < _officer.arrive_radius + 0.8,
		"stopped %.2fm away" % _flat_distance(_officer.global_position, target))
	_check(absf(_officer.global_position.y) < 0.2,
		"stayed on the deck (y=%.2f)" % _officer.global_position.y)


## People collide with the player's vehicles; no vehicle can see a person at all. So
## nothing gets out of anybody's way, and a walker who meets a parked car used to stand
## against it indefinitely -- measured at 1,716 stationary frames out of 1,747, never
## arriving. They have to find their own way round.
func _test_a_person_gets_round_a_parked_car() -> void:
	var here := CityGrid.junction(Vector2i(1, 3)) + Vector3(0.0, 0.0, 18.0)
	# **A player vehicle, not a traffic one.** The first version of this parked a Sedan
	# from Game/Traffic, and an officer masks layer 1 while ambient traffic sits on 64 --
	# so the officer walked clean through it and the check passed with the whole sidestep
	# deleted. A zero reading and an obstacle that was never there look identical from
	# the outside, which is why the contact is asserted below rather than assumed.
	#
	# Its own car rather than one of the fixture's, because this one gets freed. Borrowing
	# `_cars[1]` and parking it back on the forecourt afterwards was tried and it took a
	# slot a later dispatch check wanted, landing two paramedics on the same spot.
	var parked := (load("res://Game/Vehicles/PoliceCar.tscn") as PackedScene) \
		.instantiate() as Vehicle
	_scene.add_child(parked)
	parked.set_physics_process(false)
	parked.global_position = here
	parked.rotation.y = PI * 0.5
	await _idle(6)

	# Squarely between the officer and where they are sent, on a street wide enough that
	# there is a way round: this asks whether they take it, not whether one exists.
	await _place_unit(_officer, here + Vector3(0.0, 0.0, 7.0))
	var target := here - Vector3(0.0, 0.0, 7.0)
	_officer.issue(MoveOrder.new(target))

	var stopped_dead := 0
	var arrived := false
	for i in 1800:
		await physics_frame
		if _flat_distance(_officer.global_position, parked.global_position) < 3.0 \
				and Vector2(_officer.velocity.x, _officer.velocity.z).length() < 0.05:
			stopped_dead += 1
		if not _officer.has_orders():
			arrived = true
			break
	_check(stopped_dead > 0,
		"the officer really did meet the parked car (%d frames held up by it)"
		% stopped_dead)
	_check(arrived, "the officer got round a car parked in the way [%.1fm short]"
		% _flat_distance(_officer.global_position, target))
	_check(stopped_dead < 120,
		"without standing against it (%d frames stationary at the panel)" % stopped_dead)

	# Take the car away again. Left standing it is a solid layer-1 obstacle in the middle
	# of a street two tests before the officer is sent 9m up that same street -- which
	# timed out with the walk clip still playing, a failure that read as an animation
	# fault and was a piece of scenery this test forgot to tidy away.
	parked.queue_free()
	_officer.clear_orders()
	await _idle(6)


## The crowd gets the same sidestep, but not the same freedom. An officer may cut across
## a road to get past something; a passer-by doing that is walking down the middle of the
## carriageway, which is the one thing the district's pedestrians never do.
func _test_the_crowd_sidesteps_onto_pavement_only() -> void:
	# One of its own, rather than one off the map: by the time the person checks run the
	# ambient crowd has been exercised and cleared away, and a parked civilian would
	# swallow the clicks the later checks depend on anyway.
	var civilian := (load("res://Game/Civilians/Male_Jacket.tscn") as PackedScene) \
		.instantiate() as Civilian
	_scene.add_child(civilian)
	civilian.set_physics_process(false)
	await _idle(2)
	# The middle of a junction box: on the vehicle mesh, on nobody's pavement.
	var road := CityGrid.junction(Vector2i(2, 2))
	var pavement := CityGrid.tile_centre(23, 25)
	_check(not civilian._may_step_to(road) and civilian._may_step_to(pavement),
		"a civilian will step onto a pavement tile but not into the road")
	_check(_officer._may_step_to(road) and _officer._may_step_to(pavement),
		"an officer under orders may step either way")
	civilian.queue_free()
	await _idle(2)


func _test_person_animates() -> void:
	var player: AnimationPlayer = _officer.get_node("Character/AnimationPlayer")
	await _wait(30)
	_check(player.current_animation == "Idle",
		"idles when standing still (playing '%s')" % player.current_animation)

	_officer.issue(MoveOrder.new(_officer.global_position + Vector3(0.0, 0.0, 9.0)))
	await _wait(45)
	var moving := player.current_animation
	_check(moving == "Walk" or moving == "Jog_Fwd",
		"plays a locomotion clip while travelling (playing '%s')" % moving)
	await _await_orders_done(_officer, 1200)
	await _wait(45)
	_check(player.current_animation == "Idle",
		"returns to idle on arrival (playing '%s')" % player.current_animation)


func _test_person_faces_travel() -> void:
	# The character mesh faces +Z while Godot's forward is -Z, so Person.tscn yaws the
	# visual 180. Get that wrong and the officer moonwalks: steering is correct and
	# every other check still passes, because nothing in code reads the model's
	# orientation. Only an explicit check catches it.
	await _place_unit(_officer, Vector3(20.0, 0.1, 20.0))
	_officer.issue(MoveOrder.new(Vector3(20.0, 0.0, 8.0)))
	await _wait(60)

	var travel := Vector3(_officer.velocity.x, 0.0, _officer.velocity.z)
	if travel.length() < 0.3:
		_check(false, "the officer is walking when facing is sampled (%.2f m/s)"
			% travel.length())
		_officer.clear_orders()
		return

	# The mesh's face points along the visual node's +Z, so that is what must line up
	# with the direction of travel.
	var character: Node3D = _officer.get_node("Character")
	var alignment := character.global_basis.z.normalized().dot(travel.normalized())
	_check(alignment > 0.8,
		"the officer faces the way they walk (alignment %.2f, -1 means moonwalking)"
		% alignment)
	_officer.clear_orders()
	await _wait(20)


func _test_person_navmesh_is_tighter() -> void:
	# Query the two layers directly rather than inferring the difference from where
	# units happen to stop. The two meshes are baked from different geometry, not just
	# at different radii.
	#
	# So a target on the pavement outside the centre block is reachable on one layer and
	# roughly a road's half-width short on the other.
	var map := _officer.get_world_3d().navigation_map
	var from := Vector3(0.0, 0.0, -20.0)
	var target := Vector3(0.0, 0.0, -12.5)

	var vehicle_path := NavigationServer3D.map_get_path(map, from, target, true, 1)
	var person_path := NavigationServer3D.map_get_path(map, from, target, true, 2)
	if vehicle_path.is_empty() or person_path.is_empty():
		_check(false, "both navigation layers return a path (vehicle=%d person=%d)"
			% [vehicle_path.size(), person_path.size()])
		return

	var vehicle_gap := _flat_distance(vehicle_path[vehicle_path.size() - 1], target)
	var person_gap := _flat_distance(person_path[person_path.size() - 1], target)
	_check(person_gap < vehicle_gap - 2.0,
		"person layer reaches %.2fm from the pavement, vehicle layer %.2fm"
		% [person_gap, vehicle_gap])


func _test_clicking_a_person_selects() -> void:
	# People are on collision layer 4 and are a much smaller target than a car, so
	# picking them deserves its own check rather than being assumed from the cars.
	_controller.clear_selection()
	await _place_unit(_officer, Vector3(20.0, 0.1, 20.0))
	_camera.focus = Vector3(20.0, 0.0, 20.0)
	_camera._target_distance = 18.0
	await _idle(40)

	var aim := _officer.global_position + Vector3.UP * 1.0
	var hit := _controller._raycast(_screen_of(aim))
	_check(hit.get("collider") == _officer,
		"a ray at the officer hits them (hit '%s')" % hit.get("collider"))

	await _click(MOUSE_BUTTON_LEFT, _screen_of(aim))
	_check(_controller.primary() == _officer, "left-clicking an officer selects them")

	var board := _find_ability(_officer, &"board")
	_check(board != null, "an officer offers a Board ability for the command bar")


func _test_boarding() -> void:
	# Right-clicking a car with an officer selected should mean "get in", not "walk
	# to that spot": BoardAbility scores 10 against MoveAbility's 0.
	await _place_unit(_car, Vector3(20.0, 0.15, 4.0))
	await _place_unit(_officer, Vector3(20.0, 0.1, 12.0))
	_car.crew.clear()

	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	var ability := _officer.resolve(target)
	_check(ability != null and ability.id() == &"board",
		"right-clicking a car resolves to Board (got '%s')"
		% ("none" if ability == null else ability.id()))

	_officer.issue(ability.make_order(_officer, target))
	var done := await _await_orders_done(_officer, 1800)
	_check(done, "the officer finished the boarding order")
	_check(_officer.is_aboard, "the officer is aboard")
	_check(_car.crew.size() == 1, "the car reports 1 crew (%d)" % _car.crew.size())
	_check(not _officer.visible, "an aboard officer is hidden")
	_check(not _officer.is_selectable(), "an aboard officer cannot be selected")


func _test_unload() -> void:
	if not _officer.is_aboard:
		_check(false, "officer was aboard before unloading")
		return
	var unload := _find_ability(_car, &"unload")
	if unload == null:
		_check(false, "the car offers an Unload ability")
		return

	_controller.select([_car])
	_controller.activate(unload)
	await _wait(20)
	_check(not _officer.is_aboard, "the officer is back on foot")
	_check(_car.crew.is_empty(), "the car reports no crew")
	_check(_officer.visible, "the officer is visible again")
	_check(_officer.global_position.distance_to(_car.global_position) < 8.0,
		"dismounted beside the car (%.1fm away)"
		% _officer.global_position.distance_to(_car.global_position))
	_check(absf(_officer.global_position.y) < 1.0,
		"dismounted onto the deck (y=%.2f)" % _officer.global_position.y)


func _test_seats_are_limited() -> void:
	# Fill every seat, then check the ability declines rather than overfilling.
	_car.crew.clear()
	for i in _car.seats:
		_car.crew.append(_officer)
	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	_check(not _car.has_free_seat(), "a full car reports no free seat")
	var ability := _officer.resolve(target)
	_check(ability != null and ability.id() == &"move",
		"a full car falls back to Move (got '%s')"
		% ("none" if ability == null else ability.id()))
	_car.crew.clear()


# --- Lightbar and doors ------------------------------------------------------

## A car told to go somewhere off the road gets up onto it.
##
## Two things have to hold at once and only one of them is obvious. The car has to
## *set off* -- an order aimed off the navigation mesh used to complete on its first
## frame, because the agent clamps the destination and reports itself finished, so the
## player saw a car that ignored the click entirely. And it has to *get up*, which a box
## collider against a 7cm vertical face does not do on its own.
##
## The kerb is found by sweeping off the centre of a road band rather than named as a
## coordinate: the band tables are deliberately irregular, and a hand-picked number
## lands inside a building often enough to turn this into a test of the waypoint.
func _test_a_car_sent_off_the_road_climbs_the_kerb() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)

	var across := Vector3.ZERO
	var edge := Vector3.ZERO
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		for step in 40:
			var here: Vector3 = _car.global_position + direction * (0.25 * step)
			if not CityGrid.is_road(here):
				edge = here
				across = direction
				break
		if across != Vector3.ZERO:
			break
	if across == Vector3.ZERO:
		_check(false, "the district still has a kerb to drive at")
		return

	# Put down square to the kerb it just found, rather than left wherever `ROAD` is.
	# Sent from an arbitrary spot the car reached the pavement having climbed *nothing*
	# -- it had simply driven round to a junction box, which is also not a road tile.
	# "Off the carriageway" is too weak a claim on its own; the height is the evidence.
	await _place(edge - across * 8.0)
	await _idle(20)
	var target := edge + across * 4.0
	_check(CityGrid.is_road(_car.global_position) and not CityGrid.is_road(target),
		"the car starts on the road and is sent off it")

	# Connected **before** the order. Connecting it after a settling wait was the first
	# version and it could only ever undercount.
	# **A one-element array, not an int.** GDScript lambdas capture by *value*, so a
	# captured `var climbs := 0` is incremented on a copy and the outer one stays zero
	# for ever. This read "0 climbs, rose 0.22m" -- and 0.22 is exactly `climb_height`,
	# so the climb had plainly happened and only the tally had not. An array is a
	# reference, so mutating through it is visible outside the lambda.
	var climbs := [0]
	_car.climbed.connect(func(_v: Vehicle) -> void: climbs[0] += 1)
	var floor_y := _car.global_position.y
	_car.issue(MoveOrder.new(target))
	await _idle(20)
	_check(_car.has_orders() and _car.is_navigating(),
		"the order survives being aimed off the navigation mesh")

	var highest := floor_y
	var crawling := 0
	for i in 60 * 25:
		await _idle(1)
		highest = maxf(highest, _car.global_position.y)
		# Frames spent barely moving *before* it is up. Reported from play: the car drove
		# to the kerb and sat there grinding against it until it had slowed enough to be
		# allowed over, which is what happens when the lift waits on the stuck timer.
		if absf(_car.forward_speed) < 0.3:
			crawling += 1
		if not CityGrid.is_road(_car.global_position):
			break
	_check(not CityGrid.is_road(_car.global_position),
		"and the car gets up onto the pavement")
	_check(int(climbs[0]) > 0 and highest > floor_y + 0.05,
		"by climbing the kerb, not driving round it (%d climbs, rose %.2fm)"
			% [climbs[0], highest - floor_y])
	# Half a second of it is the stuck timer; anything approaching that means the lift is
	# waiting for the car to stop rather than carrying it over at speed.
	_check(crawling < 15,
		"and without stopping dead at the face first (%d frames under 0.3 m/s)" % crawling)
	_car.clear_orders()
	await _idle(5)


## An appliance on a shout takes the pavement past a shut street -- **and comes back down.**
##
## The check above is the *ordered* climb: the player right-clicks a verge and the car goes
## there. This is the earned one, and the two halves matter equally. Going up was built
## first and on its own it is a trap: measured, an appliance that mounted successfully then
## spent 555 frames off the carriageway, 161 of them *turning round*, because from up on the
## pavement the navigation agent's nearest reachable point is the carriageway it just left,
## on the **near** side of the obstruction. It drove back, met the wall, and mounted again.
## A 33.3s journey did not finish in sixty seconds. So the assertion that matters most here
## is the last one: the appliance ends up **on the road**.
##
## **What each assertion is worth, from the sabotage pass -- read this before adding more.**
## Disabling the mount reddens all four, with no collateral. Disabling *only* the recovery
## reddens exactly one: "steers itself back down". "Finishes the journey" stays green,
## because the navigation agent also gets the car off the pavement eventually in this
## fixture -- it is over-determined with respect to the recovery, and only goes red when
## every route back down is removed. It is kept because it is the end-to-end statement and
## it does go red when the mount is disabled, but **it is not evidence about the recovery**.
## A third assertion, "ending on the carriageway", was written here and deleted: it
## snapshotted `CityGrid.is_road()` on whichever frame the sample loop happened to exit and
## read true under every sabotage, including one where the car was demonstrably stranded 23m
## short. Bounding the off-road frame count instead does not discriminate either -- a
## healthy run spends *more* frames up there (296) than a sabotaged one (201), because the
## steered recovery is a deliberate excursion and the broken version simply mills about. The
## count is printed for the reader and asserted on by nothing.
##
## **Three abreast, an appliance, and a short hop -- all three load-bearing.**
## [method Vehicle._passing_line] finds a way round one vehicle every time and should; two
## made the result flap between 0 and 21 mounting frames on a decimetre of spacing. A patrol
## car is small enough to squeeze through the same wall (33.3s, mounting nothing), so the
## mover has to be an appliance and the fixture has to buy one. And the destination is kept
## under [constant CityGrid.LANE_ROUTE_MIN], because past that the order plans a lane route,
## writes the shut street off after four seconds and drives round the block instead -- which
## is a perfectly good answer, and not the one under test.
func _test_a_shut_street_is_passed_over_the_pavement() -> void:
	_controller.clear_selection()
	# A straight street between two junctions on the same row: one heading throughout, so
	# nothing in the result is a cornering artefact, and well clear of a junction mouth,
	# which the feature requires and the check after this one is about.
	var start := CityGrid.junction(Vector2i(1, 1))
	var along := (CityGrid.junction(Vector2i(3, 1)) - start).normalized()
	var across := along.cross(Vector3.UP)
	var yaw := atan2(-along.x, -along.z)
	var goal := start + along * 40.0

	_station.purchase(&"engine")
	var engine := _dispatch_to(&"engine", start + along * 6.0) as Vehicle
	var wall: Array[Vehicle] = [_cars[1]]
	for i in 2:
		_station.purchase(&"patrol")
		wall.append(_dispatch_to(&"patrol", start + along * 24.0) as Vehicle)
	if engine == null or wall.has(null):
		_check(false, "the fixture can put an appliance behind a shut street")
		return
	for i in wall.size():
		await _place_unit(wall[i], start + along * 24.0 + across * (float(i) - 1.0) * 2.6,
			yaw)
	# The two left-over fixture units parked well clear, so nothing an earlier check left
	# lying in this street gets to decide the answer.
	await _place_unit(_ambulance, start - along * 14.0, yaw)
	await _place_unit(_car, start - along * 20.0, yaw)
	await _place_unit(engine, start + along * 6.0, yaw)
	await _idle(20)

	# An array, not an int: GDScript lambdas capture by value and a captured int stays at
	# zero for ever. Written up at length over the ordered-climb check above.
	var climbs := [0]
	engine.climbed.connect(func(_v: Vehicle) -> void: climbs[0] += 1)
	var mounted := false
	var came_back := false
	var off_road := 0
	# The licence's own terms, reported whatever happens. A bare "it did not mount" sent this
	# check round the houses twice; the peak against the bar says at a glance whether the
	# manoeuvre was refused or simply never came due.
	var peak := 0.0
	var crawling := 0
	var blocked_frames := 0
	engine.issue(MoveOrder.new(goal))
	for i in 60 * 45:
		await _idle(1)
		if engine.is_mounting():
			mounted = true
		if engine.is_returning():
			came_back = true
		if not CityGrid.is_road(engine.global_position):
			off_road += 1
		peak = maxf(peak, engine._blocked_time)
		if engine.forward_speed < engine.mount_crawl:
			crawling += 1
			if engine.road_is_blocked(engine.move_target):
				blocked_frames += 1
		if not engine.is_navigating():
			break

	_check(mounted,
		"an appliance on a shout takes the pavement when the street is shut (blocked peaked at %.2f of %.2f, %d of %d crawling frames with the street shut)"
			% [peak, engine.mount_after, blocked_frames, crawling])
	_check(int(climbs[0]) > 0,
		"and gets up there over the kerb rather than round it (%d climbs)" % climbs[0])
	_check(came_back,
		"and steers itself back down off the pavement afterwards (%d frames off the road)"
			% off_road)
	_check(engine.global_position.distance_to(goal) < 8.0,
		"and finishes the journey (%.0fm short of a target %.0fm past the wall)"
			% [engine.global_position.distance_to(goal), 16.0])
	_station.write_off(engine)
	for i in range(1, wall.size()):
		_station.write_off(wall[i])
	await _park_the_shift()


## And an appliance merely queueing at a junction does **not**.
##
## The other half of the same behaviour, and the more important half. A kerb runs along a
## street; a junction is a crossing, and the ground at its mouth is off the vehicle
## navigation mesh without having any step on it -- so a car that mounts there drives onto
## flat tarmac, off its route, and has to find its way back. Measured with the junction
## exclusion removed, a 76.7s journey became one the car had not finished in 150 seconds.
## Nothing in the check above would have caught that.
##
## Walled in by the **same three abreast**, so the only difference between the two scenarios
## is where the appliance is standing. A weaker wall here would make this a negative control
## that proves nothing: of course a car that was never provoked did not mount.
func _test_a_junction_queue_does_not_earn_the_pavement() -> void:
	_controller.clear_selection()
	var box := CityGrid.junction(Vector2i(1, 1))
	var out := (CityGrid.junction(Vector2i(3, 1)) - box).normalized()
	var across := out.cross(Vector3.UP)
	var yaw := atan2(-out.x, -out.z)

	_station.purchase(&"engine")
	var engine := _dispatch_to(&"engine", box + out * 1.0) as Vehicle
	var wall: Array[Vehicle] = [_cars[1]]
	for i in 2:
		_station.purchase(&"patrol")
		wall.append(_dispatch_to(&"patrol", box + out * 7.0) as Vehicle)
	if engine == null or wall.has(null):
		_check(false, "the fixture can put an appliance in a junction")
		return
	for i in wall.size():
		await _place_unit(wall[i], box + out * 7.0 + across * (float(i) - 1.0) * 2.6, yaw)
	await _place_unit(_ambulance, box - out * 14.0, yaw)
	await _place_unit(_car, box - out * 20.0, yaw)
	await _place_unit(engine, box + out * 1.0, yaw)
	await _idle(20)

	var mounted := false
	engine.issue(MoveOrder.new(box + out * 40.0))
	for i in 60 * 12:
		await _idle(1)
		if engine.is_mounting():
			mounted = true
	_check(not mounted,
		"an appliance queueing in a junction does not take the pavement")
	_station.write_off(engine)
	for i in range(1, wall.size()):
		_station.write_off(wall[i])
	await _park_the_shift()


## A car sent to a point dead behind it, on a street, turns round and arrives.
##
## The navigation block already proves "reached a target directly behind it" -- on the
## station forecourt, which is open ground where a single full-lock loop fits. A street
## is the case that spent a year broken: the carriageway is narrower than the turning
## circle, so the manoeuvre must be a multi-point turn, and the machinery for that used
## to be a latch that released into arcs that did not fit the road plus a blind timed
## escape -- eight escapes in thirty seconds on this stage, never arriving. The bounded
## turn (Vehicle._begin_turn / _plan_turn_leg) plans each leg against the road instead.
##
## **What this can and cannot guard, established by two rounds of sabotage.** It cannot
## see the *quality* of the manoeuvre: the year-old faulty release was restored under it
## and the whole suite stayed green -- on a lightly-trafficked street that fault arrives
## *faster*, by sweeping, and excursion measured identical (4.4m) under both. Quality
## lives in the probes: `probe_orbit.gd` (zero escapes on every staged case) and
## `probe_journeys.gd` (fleet escapes 75 -> 31). What it does guard, with the redundancy
## mapped by measurement rather than assumed:
##
## - "starts a turn-round" reds only when **both** arming paths die -- the latch and the
##   escape-conversion each arm this stage alone (killing just the latch left it green
##   while two *other* driving checks went red). It guards the class, not one path.
## - "by the designed release" is the line with teeth: the turn has one designed exit
##   (a rolling forward leg inside the exit angle, which leaves Vehicle._turn_rest at
##   zero) and two fallbacks (abandon, plan-failure), both of which arm the rest.
##   Killing the designed release alone still arrives -- the plan-failure exit frees the
##   car within a second of when the release would -- but it arrives *resting*, which is
##   what this asserts against. Killing all three exits strands the car outright
##   (18.1m off, 30s) and takes nine other driving checks with it.
func _test_a_narrow_street_u_turn_completes() -> void:
	_controller.clear_selection()
	var j := CityGrid.junction(Vector2i(1, 1))
	var east := Vector3(1, 0, 0)
	await _place(j + east * 10.0, atan2(-east.x, -east.z))
	await _idle(10)
	var aim := j - east * 10.0

	var turned := false
	var elapsed := 0.0
	_car.issue(MoveOrder.new(aim))
	for i in 60 * 30:
		await _idle(1)
		elapsed += 1.0 / 60.0
		if _car.is_turning_round():
			turned = true
		if not _car.is_navigating():
			break

	var gap := Vector2(_car.global_position.x - aim.x,
		_car.global_position.z - aim.z).length()
	_check(turned, "a dead-behind order on a street starts a turn-round")
	_check(gap < 4.0 and elapsed < 29.0 and is_zero_approx(_car._turn_rest),
		"and it arrives by the designed release, not a fallback (%.1fm off, %.1fs, rest %.1f)"
			% [gap, elapsed, _car._turn_rest])
	_car.clear_orders()
	_car.stop_navigating()
	await _park_the_shift()


## A car on a lane route slows for the junction turn before it gets there.
##
## The junction overshoot two F3s from play pinned on the fast cars, fixed at the root:
## the corner planner used to read corners off the agent path, and with
## junction-to-junction waypoints that path **ends at the junction** -- the turn onto the
## next street does not exist in it until the 7m waypoint switch, far too late to brake
## from 26 m/s. Every apparent corner it did read was the car's own off-line position
## swinging the measured vector. The route now annotates its aim with the turn's exact
## angle ([member Vehicle.turn_at_aim], set in MoveOrder._aim from the lattice), and the
## turn's cap holds while the car is in the box ([member Vehicle.turn_here]).
##
## The bar is generous -- holdable for this car is 7.9 m/s and unfixed entries measured
## 14-20 -- so ambient traffic slowing the car further can only make it pass. Arrival is
## asserted so a car that never reaches the corner cannot pass by absence.
func _test_a_routed_car_brakes_for_the_junction_turn() -> void:
	_controller.clear_selection()
	var a := CityGrid.junction(Vector2i(1, 1))
	var b := CityGrid.junction(Vector2i(3, 1))
	var east := (b - a).normalized()
	# South off junction b, far enough that the route must turn there.
	var goal := b + Vector3(0, 0, 1) * 35.0
	await _place(a + east * 6.0, atan2(-east.x, -east.z))
	await _idle(10)

	# **Measured on both worlds before the bar was set** (tmp probe, since deleted, same
	# stage, empty district): fixed, the braked car corner-cuts and never appears within
	# 5m of the box centre at all; sabotaged (annotation zeroed), it barrels through the
	# middle at 13.3 m/s while overshooting the turn line. An 8m ring was tried first and
	# was arithmetic-blind: the fix's own braking curve legitimately crosses it at 14-16,
	# so the check failed on the healthy tree. The 5m/10.0 pair separates cleanly, and a
	# car forced through the middle *slowly* by traffic still passes, as it should.
	var centre_peak := 0.0
	var reached := false
	_car.issue(MoveOrder.new(goal))
	for i in 60 * 40:
		await _idle(1)
		var gap := Vector2(_car.global_position.x - b.x,
			_car.global_position.z - b.z).length()
		if gap < 8.0:
			reached = true
		if gap < 5.0:
			centre_peak = maxf(centre_peak, absf(_car.forward_speed))
		if not _car.is_navigating():
			break
	_check(reached, "the routed car reaches the turning junction")
	_check(reached and centre_peak < 10.0,
		"and is never at speed through the middle of the box (fastest within 5m: %.1f m/s; the unbraked world reads 13+)"
			% centre_peak)
	_car.clear_orders()
	_car.stop_navigating()
	await _park_the_shift()


func _test_siren_runs_while_responding() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)
	var siren := _car.get_node("Lean/Chassis/Siren") as Node3D
	# The bar and the noise run off one condition, so they are checked as a pair at
	# each of the three moments -- parked, under way, arrived. Checking only the bar
	# is how the two drifted apart in the first place: the light was automatic from
	# Phase 17 and the audio stayed manual for a year without anything noticing.
	var speaker := _car.get_node_or_null("SirenAudio") as AudioStreamPlayer3D
	_check(not siren.visible, "the lightbar is dark while parked")
	_check(speaker != null and not speaker.playing, "and the siren is silent with it")

	_car.issue(MoveOrder.new(Vector3(20.0, 0.0, -20.0)))
	await _idle(15)
	_check(siren.visible, "and lit once the car is on its way")
	_check(speaker != null and speaker.playing,
		"and the siren sounds the moment it is sent, without anyone throwing a switch")

	# Both beads are sampled over a couple of cycles. A lamp that is simply switched
	# on is not a siren, and would sail through a bare visibility check.
	var left := siren.get_node("Left") as Node3D
	var right := siren.get_node("Right") as Node3D
	var left_lit := 0
	var right_lit := 0
	var together := 0
	for i in 150:
		await _idle(1)
		if left.visible:
			left_lit += 1
		if right.visible:
			right_lit += 1
		if left.visible and right.visible:
			together += 1
	_check(left_lit > 10 and left_lit < 140, "the red bead flashes (lit %d of 150)" % left_lit)
	_check(right_lit > 10 and right_lit < 140, "the blue bead flashes (lit %d of 150)" % right_lit)
	_check(together == 0, "and the two alternate (%d frames with both lit)" % together)

	await _await_arrival(900)
	await _idle(10)
	_check(not siren.visible, "the lightbar goes out once it arrives")
	_check(speaker != null and not speaker.playing, "and the siren stops with it")


func _test_lights_switch_on_by_hand() -> void:
	_controller.clear_selection()
	await _place(ROAD)
	await _idle(10)
	var bar := _car.get_node("Lean/Chassis/Siren") as Node3D
	_check(not bar.visible, "the lightbar is dark parked with no orders")

	var lights := _find_ability(_car, &"lights")
	if lights == null:
		_check(false, "the car offers a Lights switch")
		return
	lights.execute(_car)
	await _idle(6)
	_check(_car.lights_on and bar.visible,
		"the switch lights the bar with the car standing still")

	# Sampled, not just visible: a lamp burning steady is not a lightbar. Same rule as
	# the responding test -- the beads must never both be lit at once.
	var left := bar.get_node("Left") as Node3D
	var right := bar.get_node("Right") as Node3D
	var lit := 0
	var together := 0
	for i in 90:
		await _idle(1)
		if left.visible or right.visible:
			lit += 1
		if left.visible and right.visible:
			together += 1
	_check(lit > 0 and together == 0,
		"and it flashes rather than burns (%d lit, %d together)" % [lit, together])

	lights.execute(_car)
	await _idle(6)
	_check(not _car.lights_on and not bar.visible, "a second press puts it out")


func _test_siren_is_the_audio_and_separate() -> void:
	var siren := _find_ability(_car, &"siren")
	if siren == null:
		_check(false, "the car offers a Siren switch")
		return
	var speaker := _car.get_node_or_null("SirenAudio") as AudioStreamPlayer3D
	_check(speaker != null and speaker.stream != null,
		"the car carries a siren speaker with a sound loaded")
	# The recording runs under three seconds, so a siren that does not loop falls
	# silent partway through the first street -- and every check above this one still
	# passes, because the speaker did start. Looping is a different property in every
	# container, which is exactly how a format swap loses it.
	_check(speaker != null and Vehicle.loops(speaker.stream),
		"and the sound loops rather than running out mid-call")

	var bar := _car.get_node("Lean/Chassis/Siren") as Node3D
	siren.execute(_car)
	await _idle(6)
	_check(_car.siren_on, "the switch turns the siren on")
	_check(speaker != null and speaker.playing, "and the speaker is playing")
	_check(not _car.lights_on and not bar.visible,
		"without touching the lights -- the two switches are separate")

	siren.execute(_car)
	await _idle(6)
	_check(not _car.siren_on and (speaker == null or not speaker.playing),
		"a second press silences it")


func _test_lights_and_siren_are_crew_switches() -> void:
	var officer_ids: Array[StringName] = []
	for ability in _officer.abilities():
		officer_ids.append(ability.id())
	_check(not officer_ids.has(&"lights") and not officer_ids.has(&"siren"),
		"someone on foot has no lightbar or siren to switch")

	_controller.select([_car])
	await _idle(3)
	var verbs := _tile_ids()
	_check(verbs.has(&"lights") and verbs.has(&"siren"),
		"a vehicle's grid offers both switches (%s)" % str(verbs))

	await _press_key(KEY_J)
	await _idle(3)
	_check(_car.lights_on, "J throws the lights on")
	_check(_active_tiles().has(&"lights"),
		"and the tile shows it running (%s)" % str(_active_tiles()))

	await _press_key(KEY_K)
	await _idle(3)
	_check(_car.siren_on, "K the siren")

	await _press_key(KEY_J)
	await _press_key(KEY_K)
	await _idle(3)
	_check(not _car.lights_on and not _car.siren_on and _active_tiles().is_empty(),
		"pressing again switches both off and the tiles go quiet (%s)"
		% str(_active_tiles()))
	_controller.clear_selection()


func _test_ambulance_doors_open_for_boarding() -> void:
	var door := _ambulance.get_node_or_null("Lean/Chassis/DoorL") as Node3D
	if door == null:
		_check(false, "the ambulance has separate rear door meshes")
		return
	var full := deg_to_rad(_ambulance.door_open_degrees)
	_ambulance.crew.clear()
	await _idle(180)
	_check(absf(door.rotation.y) < 0.02, "the ambulance's rear doors start shut")

	_ambulance.take_aboard(_officer)
	await _idle(8)
	var early := absf(door.rotation.y)
	_check(early > 0.005 and early < full * 0.5,
		"they swing rather than snap open (%.0f of %.0f degrees after 0.13s)"
		% [rad_to_deg(early), _ambulance.door_open_degrees])

	_check(await _await_door(door, full * 0.9, true, 3000),
		"and reach full travel (%.0f degrees)" % rad_to_deg(absf(door.rotation.y)))
	_check(await _await_door(door, 0.05, false, 6000),
		"then shut again afterwards (%.0f degrees)" % rad_to_deg(absf(door.rotation.y)))
	_ambulance.crew.clear()


## Waits for a door to swing past [param target] radians, one way or the other.
##
## Deliberately a condition rather than a frame budget: headless runs process frames
## far above 60/s, so "wait 130 frames for a 2.2 second hold" is not 2.2 seconds, and
## the first version of this test failed on its own arithmetic rather than on the door.
func _await_door(door: Node3D, target: float, opening: bool, budget: int) -> bool:
	for i in budget:
		await _idle(1)
		var angle := absf(door.rotation.y)
		if angle >= target if opening else angle <= target:
			return true
	return false


func _test_vehicles_without_doors_cope() -> void:
	# The patrol car's doors are part of its hull, so there is nothing to swing. The
	# call still has to be safe, because the boarding code does not know the difference.
	_check(_car.get_node_or_null("Lean/Chassis/DoorL") == null,
		"a patrol car ships no separate door meshes")
	_car.open_doors()
	await _idle(5)
	_check(true, "and opening doors it has not got is a no-op")


# --- Incidents ---------------------------------------------------------------

## An idle unit standing near something it can deal with gets on with it.
##
## Three things have to be true at once, and the third is what makes it safe: the right
## unit engages, the wrong one does not, and **an order the player gave is never
## countermanded** by a unit noticing something on the way past.
func _test_idle_units_get_on_with_it() -> void:
	await _clear_incidents()
	_stand_to()

	# A firefighter put down beside a fire starts fighting it, unasked.
	var spot := CityGrid.junction(Vector2i(2, 2)) + Vector3(0.0, 0.0, 12.0)
	# **A hose fire**, so the capability gate is real: an officer carries an extinguisher
	# and can fight a bin perfectly well, which is why the first version of this check
	# passed while the officer was busily extinguishing.
	var fire := _spawn_fire(spot, 0.6)
	fire.needs_hose = true
	# Dispatched rather than borrowed: the fixtures carry no firefighter, and the other
	# checks that need one buy their own the same way.
	_station.purchase(&"firefighter")
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to try it with")
		return
	crew.clear_orders()
	await _place_unit(crew, spot + Vector3(6.0, 0.0, 0.0))
	await _wait(90)
	_check(crew.has_orders(), "a firefighter beside a fire starts on it unasked")
	if crew.has_orders():
		_check(crew.current_order() is ExtinguishOrder,
			"and it is work rather than a walk (%s)" % crew.current_order().describe())

	# An officer beside the same fire does not: the capability gate is hard, and standing
	# next to something does not grant an ability the unit has not got.
	_officer.clear_orders()
	await _place_unit(_officer, spot + Vector3(-6.0, 0.0, 0.0))
	await _wait(90)
	# Asked by type, not by the label: `describe()` reads "Extinguishing <flavour>", so a
	# comparison against "Extinguish" is never equal and the check could not fail.
	var wrong: Order = _officer.current_order()
	_check(not (wrong is ExtinguishOrder),
		"an officer beside a hose fire does not fight it (%s)"
		% ["idle" if wrong == null else wrong.describe()])

	# And a unit already under orders is left alone, whatever it walks past.
	# **Standing right next to it**, or the guard is never asked: parked thirty metres off
	# the fire is out of range and the unit would have kept its order regardless, which is
	# a check that cannot fail.
	crew.clear_orders()
	await _place_unit(crew, spot + Vector3(5.0, 0.0, 0.0))
	var away := spot + Vector3(60.0, 0.0, 0.0)
	crew.issue(MoveOrder.new(away))
	await _wait(60)
	var kept: Order = crew.current_order()
	_check(kept != null and kept.describe() == "Move",
		"a unit under orders is not diverted by what it passes (%s)"
		% ["idle" if kept == null else kept.describe()])

	crew.clear_orders()
	crew.queue_free()
	_officer.clear_orders()
	await _clear_incidents()
	await _idle(6)


func _test_fire_grows_and_spreads() -> void:
	await _clear_incidents()
	# **Genuinely unattended.** Idle units now start work on an incident they are standing
	# near, so "nobody is fighting it" has to be arranged rather than assumed — this fire
	# was being put out by a passing officer and the check read it as one that would not
	# grow.
	_stand_down()
	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.3)
	var before := fire.intensity
	await _wait(120)
	_check(fire.intensity > before + 0.05,
		"an unattended fire grew (%.2f -> %.2f)" % [before, fire.intensity])

	# Established, and impatient, so the test does not sit through the real interval.
	fire.intensity = 0.9
	fire.spread_interval = 1.0
	var count_before: int = get_nodes_in_group(&"fires").size()
	await _wait(90)
	var count_after: int = get_nodes_in_group(&"fires").size()
	_check(count_after > count_before,
		"an established fire spread (%d -> %d fires)" % [count_before, count_after])
	await _clear_incidents()

	_stand_to()


func _test_fire_resolves_to_extinguish() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.5)
	var ability := _officer.resolve(_target_for(fire))
	_check(ability != null and ability.id() == &"extinguish",
		"right-clicking a fire resolves to Extinguish (got '%s')"
		% ("none" if ability == null else ability.id()))

	# People before property: with a unit that can do both, a casualty outranks a fire.
	# Nobody has both any more -- gating is hard -- so this asks the ladder directly
	# rather than through a unit, which is where the ordering actually lives.
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 12.0))
	var treat := TreatAbility.new()
	var extinguish := ExtinguishAbility.new()
	_check(treat.score(_paramedic, _target_for(casualty))
			> extinguish.score(_officer, _target_for(fire)),
		"Treat still outranks Extinguish (%d vs %d)" % [
			treat.score(_paramedic, _target_for(casualty)),
			extinguish.score(_officer, _target_for(fire))])

	var medical := _paramedic.resolve(_target_for(casualty))
	_check(medical != null and medical.id() == &"treat",
		"a casualty resolves to Treat for a paramedic (got '%s')"
		% ("none" if medical == null else medical.id()))
	await _clear_incidents()


## A fire never spreads somewhere a crew cannot reach.
##
## The spread angle does not care what it lands on, and a fire against a block's frontage
## spreading five metres inward lands **inside the building** — unreachable, undousable,
## and burning until the call fails. Reported from play.
## Nothing opens inside a property.
##
## Reported from play as casualties inside buildings. The rescue set piece placed its two
## casualties at **fixed offsets** from the fire, which is pavement on a frontage facing
## one way and the inside of the building on a frontage facing the other.
func _test_no_call_opens_inside_a_property() -> void:
	await _clear_incidents()
	await _clear_calls()
	# The grid's own answer first, since everything else leans on it.
	var indoors := CityGrid.block_centre(2, 2)
	var tile := CityGrid.tile_at(indoors)
	_check(not CityGrid.standable(tile.x, tile.y),
		"the middle of a block is nowhere to stand (%.1f, %.1f)" % [indoors.x, indoors.z])
	var lawn := CityGrid.block_centre(CityGrid.PARKS[1].x, CityGrid.PARKS[1].y)
	var lawn_tile := CityGrid.tile_at(lawn)
	_check(CityGrid.standable(lawn_tile.x, lawn_tile.y),
		"a park's lawn is somewhere to stand")

	# Then the director, over enough draws that a fixed offset would show up.
	var placed := 0
	var inside := 0
	for run in 12:
		_director._spawn_rescue()
		_director._spawn_building_fire()
		_director._spawn_medical()
		await _idle(2)
		for group in [Fire.FIRE_GROUP, Casualty.CASUALTY_GROUP]:
			for node in get_nodes_in_group(group):
				var thing := node as Node3D
				if thing == null:
					continue
				placed += 1
				if _inside_a_building(thing.global_position):
					inside += 1
		await _clear_incidents()
	_check(placed > 20, "the director placed plenty to judge (%d)" % placed)
	_check(inside == 0, "and none of it inside a property (%d of %d)" % [inside, placed])
	await _clear_incidents()
	await _clear_calls()


## Return takes a loaded unit to its drop-off rather than home.
func _test_return_delivers_before_going_home() -> void:
	await _clear_incidents()
	var hospital := get_first_node_in_group(Hospital.GROUP) as Node3D
	if hospital == null:
		_check(false, "the map carries a hospital")
		return

	await _place_unit(_ambulance, CityGrid.junction(Vector2i(2, 2)))
	var ability: Ability = null
	for candidate in _ambulance.abilities():
		if candidate.id() == &"return":
			ability = candidate
	if ability == null:
		_check(false, "the ambulance offers Return")
		return

	# Empty, it goes home.
	_ambulance.casualties.clear()
	_ambulance.clear_orders()
	ability.execute(_ambulance)
	await _idle(4)
	var home := _ambulance.current_order()
	_check(home != null and home.describe() != "Move",
		"an empty unit is sent home (%s)" % ["none" if home == null else home.describe()])

	# Carrying somebody, it goes to the hospital instead.
	var casualty := _spawn_casualty(_ambulance.global_position + Vector3(2.0, 0.0, 0.0))
	_ambulance.casualties.append(casualty)
	_ambulance.clear_orders()
	ability.execute(_ambulance)
	await _idle(4)
	var order := _ambulance.current_order()
	_check(order != null, "a loaded one is sent somewhere")
	if order:
		_check(_flat_distance(order.destination(), hospital.global_position) < 2.0,
			"and that somewhere is the hospital (%.1fm off)"
			% _flat_distance(order.destination(), hospital.global_position))
	_ambulance.casualties.clear()
	_ambulance.clear_orders()
	# Off the crossroads before leaving: the next check but one parks the patrol car on
	# this exact junction and clicks it, and two vehicles on one spot means the ray picks
	# whichever it reaches first.
	await _place_unit(_ambulance, CityGrid.junction(Vector2i(1, 1)))
	await _clear_incidents()
	await _idle(4)


func _test_fire_spreads_only_where_a_crew_can_reach() -> void:
	await _clear_incidents()
	# Hard against a frontage, so most of the circle around it is building.
	var block := CityGrid.block_centre(2, 2)
	# **Hard against the wall**, at the inner edge of the ring rather than its centre: from
	# the middle of the pavement tile most of the spread circle still lands on pavement or
	# road, and the check passed with reachability deleted.
	var frontage := block + Vector3(0.0, 0.0, CityGrid.block_span_z(2) * CityGrid.TILE
		* 0.5 - CityGrid.TILE)
	var fire := _spawn_fire(frontage, 1.0)
	_check(not _inside_a_building(fire.global_position),
		"the fire starts somewhere reachable (%.1f, %.1f)"
		% [fire.global_position.x, fire.global_position.z])

	fire.spread_interval = 0.05
	fire.min_spacing = 0.5
	# **Every child, not the first one.** Stopping at the first spread checked a single
	# golden angle, which happened to land safely — the check passed with reachability
	# deleted. A fire against a frontage has most of its circle inside the building, so it
	# is the later angles that matter.
	var indoors := 0
	var spread := 0
	for sweep in 900:
		await physics_frame
		spread = 0
		indoors = 0
		for node in get_nodes_in_group(Fire.FIRE_GROUP):
			var other := node as Fire
			if other == null or other == fire:
				continue
			spread += 1
			if _inside_a_building(other.global_position):
				indoors += 1
		if spread >= 4:
			break
	_check(spread >= 4, "and it spreads repeatedly (%d children)" % spread)
	_check(indoors == 0, "with none of it inside a building (%d of %d)" % [indoors, spread])
	await _clear_incidents()


## True where no firefighter could stand: not pavement, not park, not carriageway.
## True where no firefighter could stand: not pavement, not park, not carriageway.
## What the picking ray finds at a world point, named. Debug helper for the click checks.
func _raycast_from_camera(point: Vector3) -> String:
	var hit := _controller._raycast(_screen_of(point))
	if hit.is_empty():
		return "nothing"
	var collider: Object = hit.get("collider")
	return str(collider.name) if collider else "unnamed"


func _inside_a_building(point: Vector3) -> bool:
	var tile := CityGrid.tile_at(point)
	return not CityGrid.standable(tile.x, tile.y)


## Right-clicking a crewed vehicle turns the crew out of it.
func _test_right_clicking_a_crewed_vehicle_unloads_it() -> void:
	await _place_unit(_car, CityGrid.junction(Vector2i(2, 2)))
	await _place_unit(_officer, _car.global_position + Vector3(3.0, 0.0, 0.0))
	# Both halves: the vehicle takes the seat, the person goes aboard. `Person.board` only
	# does the second, and a crew list that never grew is a vehicle with nothing to unload.
	_car.take_aboard(_officer)
	_officer.board(_car)
	await _idle(6)
	_check(_car.crew.size() == 1 and _officer.is_aboard,
		"the officer is aboard to begin with (%d crew)" % _car.crew.size())

	# **The actual gesture**, not a synthesised target: selected units are normally
	# excluded from the pick so a click near one's own feet reaches the ground, and a
	# crewed vehicle has to be exempt from that or the click never lands on it. Resolving
	# a hand-built Target skips exactly the half worth testing.
	_focus_camera_on_car()
	await _click(MOUSE_BUTTON_LEFT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	_check(_controller.primary() == _car, "with the vehicle selected")
	await _click(MOUSE_BUTTON_RIGHT, _screen_of(_car.global_position + Vector3.UP * 0.9))
	await _idle(10)
	_check(_car.crew.is_empty() and not _officer.is_aboard,
		"right-clicking it turns the crew out (%d aboard)" % _car.crew.size())

	# An empty vehicle offers nothing, so a right-click on one still means "drive there".
	var target := Target.new()
	target.position = _car.global_position
	target.collider = _car
	target.unit = _car
	var empty := _car.resolve(target)
	_check(empty == null or empty.id() != &"unload",
		"an empty vehicle does not offer it (%s)"
		% ["none" if empty == null else empty.id()])
	# Unconditionally, whatever the checks above found: an officer left aboard is hidden
	# with its collision disabled, and every later check that needs one on foot fails.
	_car.unload()
	await _idle(6)
	# Put the officer back where the next check expects to find them: on their feet, clear
	# of the car, with nothing outstanding.
	_officer.clear_orders()
	await _place_unit(_officer, CityGrid.junction(Vector2i(2, 2)) + Vector3(8.0, 0.0, 0.0))
	await _idle(4)


func _test_officer_extinguishes_a_fire() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(20.0, 0.0, 14.0), 0.5)
	fire.spread_interval = 9999.0
	await _place_unit(_officer, Vector3(28.0, 0.1, 14.0))
	_officer.issue(ExtinguishOrder.new(fire))

	# The order has to close the distance before any work happens.
	await _wait(20)
	_check(_officer.is_navigating(), "walks to the fire before starting work")

	var in_range := false
	for i in 900:
		if _officer.global_position.distance_to(fire.global_position) <= ExtinguishOrder.REACH:
			in_range = true
			break
		await physics_frame
	_check(in_range, "reached hose range")
	await _wait(10)
	_check(_officer.action_clip == ExtinguishOrder.CLIP,
		"plays the work clip while working (got '%s')" % _officer.action_clip)

	var done := await _await_orders_done(_officer, 3000)
	_check(done, "finished the extinguish order")
	_check(not is_instance_valid(fire) or not fire.active, "the fire is out")
	_check(_officer.action_clip.is_empty(), "stopped playing the work clip afterwards")
	await _clear_incidents()


func _test_casualty_is_prone() -> void:
	# A casualty standing up looks like nothing is wrong, and no behavioural check
	# would notice: this asserts the pose itself.
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	await _wait(10)

	# Assert the pose, not the player state: current_animation clears when a one-shot
	# finishes, even though the final frame is still held.
	var player: AnimationPlayer = casualty.get_node("Character/AnimationPlayer")
	var skeleton: Skeleton3D = casualty.get_node("Character/Armature/GeneralSkeleton")
	var hips := skeleton.find_bone("Hips")
	var height := (skeleton.global_transform * skeleton.get_bone_global_pose(hips)).origin.y
	# Standing puts the hips near 0.95m; prone is under a third of that.
	_check(height < 0.4,
		"is lying down, not standing (hips at %.2fm, held at %.2fs)"
		% [height, player.current_animation_position])
	await _clear_incidents()


func _test_casualty_declines() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	var before := casualty.health
	await _wait(150)
	_check(casualty.health < before - 0.01,
		"an untreated casualty declined (%.3f -> %.3f)" % [before, casualty.health])
	_check(not casualty.is_stable, "and is not stable")
	await _clear_incidents()


## A paramedic, not an officer. Gating is hard, so an officer has no Treat to issue --
## and this check would pass anyway if it kept using one, because it hands the order
## over directly rather than resolving it. Only the caller changed; that is the point.
func _test_paramedic_treats_a_casualty() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	await _place_unit(_paramedic, Vector3(26.0, 0.1, 14.0))
	_paramedic.issue(TreatOrder.new(casualty))

	var done := await _await_orders_done(_paramedic, 3000)
	_check(done, "finished the treat order")
	_check(not is_instance_valid(casualty) or casualty.is_stable,
		"the casualty was stabilised")
	await _clear_incidents()


## A paramedic sent to a casualty beyond them **holds** them and never finishes.
##
## Both halves matter and they fail in opposite directions. Without the hold this is a unit
## standing uselessly over someone who dies anyway, and the player learns to leave; without
## the refusal there is no specialist and the doctor is decoration. The interesting state is
## the one in between -- alive, and going nowhere -- because that is the state the player has
## to answer by dispatching somebody else.
##
## **Long enough to have finished twice over.** `treat_per_second` is 0.2, so an ordinary
## casualty stabilises in five seconds; ten proves the refusal rather than a slow rate.
func _test_a_paramedic_holds_a_doctors_case_but_cannot_finish_it() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	casualty.needs_doctor = true
	await _place_unit(_paramedic, Vector3(21.2, 0.1, 14.0))
	await _idle(10)

	# **Read before the work, and read the health rather than the clock.** A casualty that
	# was already stable, or already dead, would make every assertion below vacuous.
	_check(not casualty.is_stable and casualty.health > 0.5,
		"the casualty starts alive and unstable (health %.2f)" % casualty.health)
	var opening := casualty.health
	_paramedic.issue(TreatOrder.new(casualty))
	for i in 60 * 10:
		await _idle(1)
		if not is_instance_valid(casualty) or casualty.is_stable:
			break

	_check(is_instance_valid(casualty) and not casualty.is_stable,
		"a paramedic cannot stabilise a casualty who needs a doctor")
	# The decline is 0.012/sec, so ten unheld seconds costs 0.12 -- an order of magnitude
	# more than the rounding this allows for.
	_check(is_instance_valid(casualty) and casualty.health > opening - 0.02,
		"but holds them steady while they work (health %.2f, from %.2f)"
			% [casualty.health if is_instance_valid(casualty) else 0.0, opening])
	_check(is_instance_valid(casualty)
			and casualty.describe_state().contains("doctor"),
		"and the panel says what is needed ('%s')"
			% (casualty.describe_state() if is_instance_valid(casualty) else "gone"))
	_paramedic.clear_orders()
	await _clear_incidents()


## And a doctor finishes it. The same fixture, one unit swapped -- which is the claim.
func _test_a_doctor_stabilises_what_a_paramedic_cannot() -> void:
	await _clear_incidents()
	_station.purchase(&"doctor")
	var doctor := _dispatch_to(&"doctor", Vector3(26.0, 0.1, 14.0)) as Person
	if doctor == null:
		_check(false, "the career can buy a doctor")
		return
	_check(doctor.has_advanced_care(), "a doctor has advanced care")
	_check(not _paramedic.has_advanced_care(), "and a paramedic does not")
	# Same service, so the specialist is expressed *within* it rather than as a fourth
	# emergency service -- which is the whole point of `speciality`.
	_check(doctor.service == _paramedic.service,
		"both are the same service (%d vs %d)" % [doctor.service, _paramedic.service])

	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	casualty.needs_doctor = true
	await _place_unit(doctor, Vector3(21.2, 0.1, 14.0))
	await _idle(10)
	doctor.issue(TreatOrder.new(casualty))
	for i in 60 * 10:
		await _idle(1)
		if not is_instance_valid(casualty) or casualty.is_stable:
			break
	_check(is_instance_valid(casualty) and casualty.is_stable,
		"a doctor stabilises the case a paramedic could only hold")

	# And the rest of the chain is untouched: stable means liftable, which is what makes
	# the doctor a bottleneck in an existing loop rather than a separate one.
	_check(CollectAbility.new().score(_paramedic, _target_for(casualty))
			!= Ability.NOT_APPLICABLE,
		"and the paramedic can now lift them onto the stretcher")
	doctor.clear_orders()
	_station.write_off(doctor)
	await _clear_incidents()


## Two unit types in the same service stay told apart on the books.
##
## The check for a bug that cost an afternoon and whose symptoms point nowhere near it.
## [method Station.type_of] used to identify a unit by (service, vehicle), which is exact
## only while each service has exactly one kind of person. The doctor made MEDICAL-and-not-a-
## vehicle match two catalogue entries, the scan returned the first, and so writing off a
## doctor decremented the **paramedic** count while `_alive` counted every doctor as a
## paramedic -- the dispatch panel then offered paramedics that did not exist and refused
## doctors that did. Every specialist added from here on would have re-broken it identically,
## which is why this is a check and not a comment.
func _test_two_specialists_in_one_service_stay_told_apart() -> void:
	var medics := _station.total(&"paramedic")
	_station.purchase(&"doctor")
	var doctor := _dispatch_to(&"doctor", Vector3(30.0, 0.1, 20.0)) as Person
	if doctor == null:
		_check(false, "the career can buy a doctor")
		return
	# **Stated as a difference, not as two identities.** Written as a pair of `== &"doctor"` /
	# `== &"paramedic"` assertions, the second is inert: the bug returns `paramedic` for both,
	# so it is green either way and cannot see the fault it is here for.
	_check(Station.type_of(doctor) != Station.type_of(_paramedic),
		"a doctor and a paramedic in one service are told apart ('%s' vs '%s')"
			% [Station.type_of(doctor), Station.type_of(_paramedic)])
	_check(Station.type_of(doctor) == &"doctor",
		"and the doctor is identified as a doctor (got '%s')" % Station.type_of(doctor))
	# **Not `available()`.** That is `owned - alive`, so one bought and one dispatched is
	# correctly **zero**, and an assertion of `>= 1` here passed only while `_alive`
	# miscounted the live doctor as a paramedic -- green under the bug, red once fixed. The
	# sabotage pass caught it; it is the exact inversion this project keeps finding.
	_check(_station.total(&"doctor") == 1 and _station.available(&"doctor") == 0,
		"one bought and one out means none spare (%d owned, %d spare)"
			% [_station.total(&"doctor"), _station.available(&"doctor")])

	_station.write_off(doctor)
	await _idle(2)
	_check(_station.total(&"paramedic") == medics,
		"and writing the doctor off leaves the paramedics alone (%d, was %d)"
			% [_station.total(&"paramedic"), medics])
	_check(_station.total(&"doctor") == 0,
		"while the doctor comes off the books (%d)" % _station.total(&"doctor"))
	# **Put the books back whatever happened above.** This test buys and writes off, and if
	# its own assertions fail it fails *because* the roster ended up wrong -- so leaving it
	# wrong contaminates everything downstream. Sabotaged, that cost four further reds and
	# nine checks that never ran, none of them about specialists. The collapse test below
	# cleans up after itself for the same reason.
	_station.owned.erase(&"doctor")
	_station.owned[&"paramedic"] = medics
	await _clear_incidents()


## The director never sets a collapse to a career with no doctor on the books.
##
## Same rule as building fires and an engine, and for the same reason: paramedics would hold
## the casualty indefinitely, the call would never close, and it would read as a bug rather
## than as a hard call. Rolled rather than reasoned about, because the gate lives in the
## weighting and a check that read the table would pass with the filter deleted.
func _test_a_collapse_is_only_offered_with_a_doctor_on_the_books() -> void:
	var before := _station.owns(&"doctor")
	_check(not before, "the fixture career owns no doctor to begin with")
	var without := 0
	for i in 400:
		if _director._pick_kind() == &"collapse":
			without += 1
	_check(without == 0,
		"a career with no doctor is never set a collapse (%d of 400 rolls)" % without)

	_station.purchase(&"doctor")
	var with_one := 0
	for i in 400:
		if _director._pick_kind() == &"collapse":
			with_one += 1
	# Weight 14 of roughly 190 offered: about 7%, so 400 rolls missing it entirely is a
	# one-in-10^12 event. A zero here means the kind is unreachable, not unlucky.
	_check(with_one > 0,
		"and one that owns a doctor is (%d of 400 rolls)" % with_one)
	# Bought but never dispatched, so there is no unit for `write_off` to take -- put the
	# count back by hand rather than leave a doctor on the books for every later check.
	_station.owned.erase(&"doctor")


# --- Roles -------------------------------------------------------------------

## The phase's whole claim: sending the wrong unit is a wasted trip, not a slower one.
func _test_services_gate_their_verbs() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, 14.0))
	var fire := _spawn_fire(Vector3(20.0, 0.0, 20.0), 0.5)

	var treat := TreatAbility.new()
	var extinguish := ExtinguishAbility.new()
	_check(treat.score(_officer, _target_for(casualty)) != Ability.NOT_APPLICABLE,
		"Treat itself would apply to a casualty for anybody")
	_check(_find_ability(_officer, &"treat") == null,
		"but an officer is not offered it at all")
	_check(_find_ability(_paramedic, &"extinguish") == null,
		"and a paramedic is not offered Extinguish")
	_check(_find_ability(_paramedic, &"secure") == null,
		"nor Secure, which is a police job")

	# The consequence, through the resolution the player actually uses.
	var officer_verb := _officer.resolve(_target_for(casualty))
	_check(officer_verb != null and officer_verb.id() == &"move",
		"right-clicking a casualty with an officer means Move (got '%s')"
			% ("none" if officer_verb == null else officer_verb.id()))
	var medic_verb := _paramedic.resolve(_target_for(fire))
	_check(medic_verb != null and medic_verb.id() == &"move",
		"and a fire with a paramedic means Move (got '%s')"
			% ("none" if medic_verb == null else medic_verb.id()))

	# Collect follows the service, and now the feet: the paramedic runs the
	# stretcher, and the ambulance -- which cannot leave the road -- no longer
	# pretends it can drive to a casualty.
	_check(_find_ability(_paramedic, &"collect") != null,
		"the paramedic is offered Collect")
	_check(_find_ability(_ambulance, &"collect") == null,
		"the ambulance is not -- the stretcher does the collecting")
	_check(_find_ability(_car, &"collect") == null,
		"nor the patrol car")
	_check(_ambulance.service == Unit.Service.MEDICAL
			and _paramedic.service == Unit.Service.MEDICAL,
		"the ambulance and the paramedic are the same service")
	await _clear_incidents()


## Secure declines every right-click on purpose -- it applies to any patch of ground,
## so left to score it would swallow Move and an officer could never be sent anywhere.
## It has to be armed, which is what can_target() exists for.
func _test_an_officer_secures_a_scene() -> void:
	await _clear_incidents()
	var ability := _find_ability(_officer, &"secure")
	if ability == null:
		_check(false, "the officer offers Secure")
		return

	var spot := Vector3(20.0, 0.0, 10.0)
	var target := Target.new()
	target.position = spot
	_check(ability.score(_officer, target) == Ability.NOT_APPLICABLE,
		"Secure declines a right-click on open ground")
	_check(ability.can_target(_officer, target),
		"but accepts it once armed")

	await _place_unit(_officer, Vector3(26.0, 0.1, 10.0))
	_controller.select([_officer])
	_controller.activate(ability)
	_check(_controller.armed_ability != null
			and _controller.armed_ability.id() == &"secure",
		"the tile armed it (%s)" % _armed_id())
	_controller._fire_armed(target)
	_check(_officer.has_orders(), "and clicking the ground issued the order")

	var raised: Cordon = null
	for i in 1500:
		await physics_frame
		for node in get_nodes_in_group(Cordon.GROUP):
			var cordon := node as Cordon
			if cordon and cordon.raised:
				raised = cordon
				break
		if raised:
			break
	_check(raised != null, "the officer walked over and set the cordon out")
	if raised:
		_check(_flat_distance(raised.global_position, spot) < 1.0,
			"where it was clicked (%.1fm away)"
				% _flat_distance(raised.global_position, spot))
		_check(raised.get_child_count() >= raised.cone_count,
			"with its cones out (%d)" % raised.get_child_count())
	await _clear_cordons()


## The cordon is not a wall -- it has no collision, because one across the road would
## trap the ambulance the officer put it there to make room for. Keeping the public out
## is a decision the crowd makes.
func _test_a_cordon_clears_the_public() -> void:
	await _clear_cordons()
	var spot := Vector3(20.0, 0.0, -20.0)
	var cordon := Cordon.new()
	_scene.add_child(cordon)
	cordon.global_position = spot

	# The crowd was cleared long ago, so put one back -- a check that the public leaves
	# a cordon proves nothing with no public to leave it.
	var shopper := (load(CIVILIAN_SCENE) as PackedScene).instantiate() as Civilian
	_scene.add_child(shopper)
	shopper.global_position = spot + Vector3(1.5, 0.2, 0.0)
	await _wait(40)
	_check(not shopper.is_fleeing,
		"a civilian ignores a cordon that has not been set out yet")

	cordon.raise_cordon()
	_check(cordon.contains(shopper.global_position),
		"the shopper is inside the ring once it is up")
	await _wait(40)
	_check(shopper.is_fleeing, "raising it sends them out")

	var left := false
	for i in 900:
		await physics_frame
		if not cordon.contains(shopper.global_position):
			left = true
			break
	_check(left, "and they clear it (%.1fm from the middle)"
		% _flat_distance(shopper.global_position, spot))

	shopper.queue_free()
	await _clear_cordons()


# --- Dispatch ----------------------------------------------------------------

## The roster is finite, and the units already parked on the forecourt are part of it.
## Miss that and the station hands out four more patrol cars than exist.
## The career: money in, fleet out. Run against a pocket career on the side so the
## suite's own fixture fleet -- which is also a career -- is not disturbed.
func _test_a_career_buys_its_fleet() -> void:
	if _station == null:
		_check(false, "the map has a station")
		return
	_check(_shipped_units == 0,
		"the map ships no player units -- the career buys them (%d shipped)"
		% _shipped_units)

	# The hint only speaks between shifts with the mission at rest; earlier tests
	# may have left it WON.
	_reset_mission()
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()
	_station.owned = {}
	_station.funds = Station.STARTING_FUNDS

	# The screen tells a fresh career what to do first.
	_station.roster_changed.emit()
	await _idle(3)
	var hint := _scene.get_node_or_null("HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
	_check(hint != null and hint.visible and "Buy your first units" in hint.text,
		"an empty career is told to buy, not to press F2 ('%s')"
		% (hint.text if hint else "no hint"))

	_check(_station.total(&"patrol") == 0 and _station.total(&"officer") == 0,
		"a fresh career owns nothing")
	var kit_price := _station.price(&"patrol") + _station.price(&"officer") \
		+ _station.price(&"ambulance") + _station.price(&"paramedic")
	_check(kit_price <= Station.STARTING_FUNDS,
		"the starter purse covers a minimal mixed crew (£%d of £%d)"
		% [kit_price, Station.STARTING_FUNDS])

	for id in [&"patrol", &"officer", &"ambulance", &"paramedic"]:
		_station.purchase(id)
	_check(_station.total(&"patrol") == 1 and _station.total(&"paramedic") == 1
			and _station.funds == Station.STARTING_FUNDS - kit_price,
		"buying the kit moves money into fleet (£%d left)" % _station.funds)

	# Broke, **stated rather than inherited**. This used to lean on the leftover after the
	# starter kit happening to be smaller than an officer, which was true at a £2,000 purse
	# and stopped being true the moment it went to £3,200 for the doctor: £1,250 remained,
	# the officer was affordable, the purchase went through, and two checks went red for a
	# reason that had nothing to do with affordability. A check about being broke should say
	# how broke, not depend on a constant three screens away.
	_station.funds = _station.price(&"officer") - 1
	var before := _station.funds
	_check(not _station.purchase(&"officer"),
		"an unaffordable purchase is refused (£%d for a £%d unit)"
			% [before, _station.price(&"officer")])
	_check(_station.funds == before and _station.total(&"officer") == 1,
		"and neither purse nor fleet moved (£%d, %d officers)"
		% [_station.funds, _station.total(&"officer")])

	_station.owned = kept_owned
	_station.funds = kept_funds
	_station._save_career()
	_station.roster_changed.emit()
	await _idle(3)
	_check(hint != null and "Press  F2" in hint.text,
		"with a fleet owned the advice moves on to F2")

	# Type is derived from what a unit is, not from a tag, so any unit on the map
	# and one still in the house have to look the same to the station.
	_check(Station.type_of(_ambulance) == &"ambulance"
			and Station.type_of(_car) == &"patrol"
			and Station.type_of(_paramedic) == &"paramedic"
			and Station.type_of(_officer) == &"officer",
		"the station recognises all four types of unit on the map")


## The career survives the window closing: funds and fleet come back off disk.
func _test_the_career_survives_reload() -> void:
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()

	_station.funds = 1234
	_station.owned = {&"patrol": 5, &"paramedic": 3}
	_station._save_career()
	_station.funds = 0
	_station.owned = {}
	_station._load_career()
	_check(_station.funds == 1234 and _station.total(&"patrol") == 5
			and _station.total(&"paramedic") == 3,
		"the career survives a reload (£%d, %d patrols, %d paramedics)"
		% [_station.funds, _station.total(&"patrol"), _station.total(&"paramedic")])

	_station.funds = kept_funds
	_station.owned = kept_owned
	_station._save_career()


func _test_dispatch_puts_a_unit_on_the_forecourt() -> void:
	# **The purse lives in the top bar** since August 2026, when the dispatch block that
	# used to carry it was hidden. Asserted on the number *tracking the books* rather than
	# on the label being non-empty: a readout wired to nothing still reads "£0", which is
	# a plausible balance and therefore an invisible failure.
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	var purse: Label = null
	if strip:
		var entry: Dictionary = strip._blocks.get(&"funds", {})
		purse = entry.get("value") as Label if not entry.is_empty() else null
	var before_funds := _station.funds
	_station.funds = before_funds + 4321
	await _idle(3)
	_check(purse != null and purse.text.contains(str(before_funds + 4321)),
		"the top bar's purse follows the books ('%s' for £%d)"
		% [purse.text if purse else "no purse", before_funds + 4321])
	_station.funds = before_funds

	# Everything owned is already standing on the map, so buy the two this test
	# sends out.
	_buy(&"paramedic", 2)
	var before := _station.available(&"paramedic")
	_check(before == 2, "the bought pair wait in the house (%d)" % before)
	var unit := _station.dispatch(&"paramedic")
	_check(unit != null, "dispatching a paramedic produced a unit")
	if unit == null:
		return
	await _idle(4)

	_check(_station.available(&"paramedic") == before - 1,
		"and took one off the roster (%d -> %d)"
			% [before, _station.available(&"paramedic")])
	_check(unit.service == Unit.Service.MEDICAL,
		"it is a medical unit (%d)" % unit.service)
	_check(_find_ability(unit, &"treat") != null
			and _find_ability(unit, &"extinguish") == null,
		"with a paramedic's verbs, not an officer's")
	_check(_station.is_home(unit.global_position),
		"standing on the station forecourt (%.1fm out)"
			% _flat_distance(unit.global_position, _station.global_position))

	# The forecourt already has seven units on it, so a slot has to be picked rather
	# than assumed -- two dispatched into the same spot would shove each other across it.
	var second := _station.dispatch(&"paramedic")
	await _idle(4)
	_check(second != null and _flat_distance(
			unit.global_position, second.global_position) > 2.0,
		"a second one lands clear of the first (%.1fm apart)" % (
			0.0 if second == null else _flat_distance(
				unit.global_position, second.global_position)))
	_check(second != null and second.display_name != unit.display_name,
		"and is named separately ('%s' vs '%s')" % [
			unit.display_name, "none" if second == null else second.display_name])

	# The regression that hid the first career's fleet: the slots used to sit on
	# the building side of the yard, and from the opening view the station's own
	# roof swallowed every dispatched unit -- bought, alive, selected, invisible.
	# Both rows now stand street-side, and the pick ray must reach them.
	_camera.stop_following()
	_camera.focus = _opening_focus
	_camera._target_distance = _opening_distance
	await _idle(40)
	var seen := 0
	for candidate: Unit in [unit, second]:
		if candidate == null:
			continue
		var aim: Vector3 = candidate.global_position + Vector3.UP * 0.9
		if not _camera.is_position_behind(aim) \
				and _controller._raycast(_screen_of(aim)).get("collider") == candidate:
			seen += 1
	_check(seen == 2,
		"both dispatched units are visible and clickable from the opening view (%d of 2)"
		% seen)

	# And the click path itself: the row is the only door the player has, and it
	# went untested while the hidden slots were burying its results.
	_buy(&"paramedic", 1)
	# **The panel rebuilds its rows off a signal, not inline.** Asking for the row in the
	# same frame as the purchase got null, and `get_global_rect()` on null threw -- which
	# abandoned the rest of this check silently, so everything below here had not run in a
	# long time while the suite reported green. Waiting is the fix; asserting the row
	# exists is what stops the same thing being silent if it ever returns.
	await _idle(4)
	var units_node := _scene.get_node("Units")
	var before_click := units_node.get_child_count()
	var row := _dispatch_row(&"paramedic")
	_check(row != null, "the roster offers a standby chip for a paramedic just bought")
	var clicked: Unit = null
	if row != null:
		# The centre of the chip. The old dispatch row was 126px wide and this clicked
		# 60px in; a chip is 48 wide, so that offset would now land outside it.
		await _click(MOUSE_BUTTON_LEFT, row.get_global_rect().get_center())
		await _idle(4)
		_check(units_node.get_child_count() == before_click + 1
				and _station.available(&"paramedic") == 0,
			"clicking the standby chip sends one out through the real interface")
		clicked = units_node.get_child(units_node.get_child_count() - 1) as Unit

	# The spares go, and the books with them, so the fleet stays the canonical seven.
	_dissolve(unit, &"paramedic")
	_dissolve(second, &"paramedic")
	if clicked != null:
		_dissolve(clicked, &"paramedic")
	await _idle(4)


func _test_dispatch_stops_when_the_yard_is_empty() -> void:
	_buy(&"patrol", 3)
	var sent: Array[Unit] = []
	for i in 20:
		var unit := _station.dispatch(&"patrol")
		if unit == null:
			break
		sent.append(unit)
	await _idle(4)

	_check(_station.available(&"patrol") == 0,
		"emptying the house leaves nothing to send (%d)"
			% _station.available(&"patrol"))
	_check(sent.size() == 3,
		"it handed out exactly the three that were bought (%d)" % sent.size())
	_check(_station.dispatch(&"patrol") == null,
		"and refuses the next one rather than conjuring it")

	# Taking them back *parks* them: they are still on the map, still owned, so the
	# house stays empty -- parked is not un-owned.
	for unit in sent:
		_station.accept(unit)
	await _idle(4)
	_check(_station.available(&"patrol") == 0,
		"accepting them home parks them without refilling the house (%d)"
		% _station.available(&"patrol"))
	for unit in sent:
		_dissolve(unit, &"patrol")
	await _idle(4)


## The other half of the career: a unit sent home is an asset parking, not a token
## vanishing back into a counter. It stays on the map, selectable, ready to go again.
func _test_returning_parks_on_the_forecourt() -> void:
	_buy(&"officer", 1)
	var unit := _station.dispatch(&"officer")
	if unit == null:
		_check(false, "an officer to send home")
		return
	await _idle(4)

	# Put them across the district first, so this measures the walk home and not a
	# unit that was already standing on the doorstep.
	await _place_unit(unit, Vector3(20.0, 0.1, 0.0))
	_check(not _station.is_home(unit.global_position),
		"the officer starts well away from the station")

	var ability := _find_ability(unit, &"return")
	_check(ability != null and ability.is_instant(),
		"Return is offered, and needs no target")
	if ability == null:
		return
	ability.execute(unit)
	_check(unit.has_orders(), "pressing it sent them home")

	var home := false
	for i in 3000:
		await physics_frame
		if not is_instance_valid(unit):
			break
		if _station.is_home(unit.global_position) and not unit.has_orders():
			home = true
			break
	_check(home, "they reached the station and parked")
	_check(is_instance_valid(unit) and unit.visible and unit.is_selectable(),
		"still on the map, visible and selectable -- property, not a token")
	_check(_station.available(&"officer") == 0,
		"and the house is no fuller for it (%d in it)"
		% _station.available(&"officer"))
	if is_instance_valid(unit):
		_controller.select([unit])
		_check(unit.is_selected, "the parked officer can be picked straight up")
		_controller.select([])
	_dissolve(unit, &"officer")
	await _idle(4)


## Going home is not a shout: lightbar off, and the limit applies.
##
## These use a spare car bought for the test rather than a fixture, then dissolve it
## afterwards, so the canonical seven-unit fleet the rest of the suite leans on is
## never disturbed.
func _test_a_returning_vehicle_runs_dark_and_legal() -> void:
	await _clear_ambient()
	_buy(&"patrol", 1)
	var car := _station.dispatch(&"patrol") as Vehicle
	if car == null:
		_check(false, "a spare patrol car to send home")
		return
	await _idle(4)
	await _place_unit(car, ROAD)

	# On a shout first, so this measures the difference and not just a dark vehicle.
	car.issue(MoveOrder.new(Vector3(20.0, 0.0, -40.0)))
	await _wait(60)
	var siren := car.get_node_or_null(car.siren_path) as Node3D
	_check(car.is_responding(), "answering a call counts as responding")
	_check(siren != null and siren.visible, "and the lightbar is on")

	car.clear_orders()
	car.issue(ReturnOrder.new(_station))
	await _wait(60)
	_check(not car.is_responding(), "going home does not")
	_check(siren != null and not siren.visible, "and the lightbar goes dark")

	# Held to the limit rather than the vehicle's own top speed.
	var limit := car.legal_speed
	var top := car.max_speed
	var fastest := 0.0
	for i in 900:
		await physics_frame
		if not is_instance_valid(car) or not car.has_orders():
			break
		fastest = maxf(fastest, car.forward_speed)
	_check(fastest <= limit + 1.0,
		"and it holds the limit going back (peaked at %.1f, limit %.1f, flat out %.1f)"
			% [fastest, limit, top])
	_check(fastest > 4.0, "while still actually driving (%.1f m/s)" % fastest)
	_dissolve(car, &"patrol")
	await _idle(4)


## The navigation mesh covers the full width of every road, so a car left to it
## straight-lines down the middle and meets oncoming traffic head on. A unit that is no
## longer on a shout has no business doing that.
## A vehicle **on a shout** keeps its side of the road too.
##
## Being on a shout is a reason to go faster, not a reason to drive on the wrong side.
## For a long time only a returning vehicle drove in lane: responses were left to the
## navigation mesh, which covers the full width of every street, so the car tracked the
## middle and swung across the centre line on every bend. Measured on a response before
## this: **37% of samples over the line and 3.9m into the oncoming lane** -- a whole car
## on the wrong side, and worse than the 18% the mesh gives a slower vehicle, because a
## responder carries more speed into every swing. Routed in lane it measures 9%.
## A U-turn is turned round, not routed round.
##
## Lane discipline is about travelling; reversing direction is its own manoeuvre, and
## the motion model already does it well -- a three-point turn inside the width of the
## street. Sending a U-turn round the junction lattice instead measured a **25m sweep
## off a 10m street**, which is what "turning circles do not work" looked like. The
## exemption is bounded: a long drive that merely *begins* facing the wrong way is still
## a drive and still wants its lane, and without the range test a corner-to-corner
## response that started backwards lost lane discipline for all of it -- 9% over the
## centre line became 58%.
func _test_a_u_turn_is_turned_not_routed() -> void:
	# On a north-south street, facing north, sent back south -- far enough that the old
	# threshold would have routed it, near enough that turning round is the whole job.
	#
	# Offset a lane's width rather than *exactly* 180 degrees behind. At a dead 180 the
	# heading error is ill-conditioned -- signed_angle_to can return either sign, so the
	# opposite lock flips every frame, the nose never swings, and the car reverses the
	# whole way at max_reverse_speed instead of turning. That is a real edge in the
	# motion model (noted in NEXT.md); it is not what this check is about, and a player
	# right-clicking the road behind them practically never lands on it.
	var here := Vector3(20.0, 0.15, -22.0)
	var target := Vector3(20.0 + CityGrid.LANE_OFFSET, 0.0, 22.0)
	await _place_unit(_car, here, 0.0)
	var order := MoveOrder.new(target)
	_car.issue(order)
	await _idle(4)
	_check(order._route.is_empty(),
		"a U-turn is driven at directly rather than routed (%d waypoints)"
		% order._route.size())

	# Watched for long enough to complete the manoeuvre and set off, which is what this
	# is measuring. **Arrival is deliberately not asserted here.** On the live district
	# this drive queues behind whatever the earlier tests left standing, and it took
	# more than ninety seconds while still closing -- a fact about the traffic, not about
	# turning. `Game/diagnose_driving.gd` measures the same turn on a cleared street and
	# gets 7.9s; asserting a time here would only ever be measuring the neighbours.
	var widest := 0.0
	for i in 900:
		await physics_frame
		widest = maxf(widest, absf(_car.global_position.x - 20.0))
		if not _car.has_orders():
			break
	_check(_car.global_position.z > here.z + 6.0,
		"and comes round to head back the way it came (%.1fm along)"
		% (_car.global_position.z - here.z))
	# The street is two lanes -- ten metres. Anything much past that is the car leaving
	# the road to come round, which is the sweep this exists to forbid. Measured 2.7m
	# turning, 25.4m routed.
	_check(widest < 10.0,
		"turning round inside the street rather than sweeping out of it (%.1fm)"
		% widest)

	# And at **25m**, which is the range that was actually broken. It sat in a band too
	# far for the motion model to turn round in (the strict waypoint trigger, 16m) and
	# too near to lane-route (40m), so it did neither and swept: measured 27m off a 10m
	# street, worse than the same turn at 45m and slower than one twice as long. The
	# generous `turn_round_range` covers it now, and only applies to a straight drive at
	# a destination -- giving it to the last leg of a *routed* journey let the latch
	# re-arm on the approach and took line-keeping from 9% back to 36%.
	var near_here := Vector3(20.0, 0.15, -12.0)
	await _place_unit(_car, near_here, 0.0)
	_car.issue(MoveOrder.new(Vector3(20.0 + CityGrid.LANE_OFFSET, 0.0, 13.0)))
	var near_widest := 0.0
	for i in 900:
		await physics_frame
		near_widest = maxf(near_widest, absf(_car.global_position.x - 20.0))
		if not _car.has_orders():
			break
	_check(near_widest < 10.0,
		"and at 25m too, which is the range that used to sweep (%.1fm)" % near_widest)
	_car.clear_orders()
	await _idle(4)

	# And a long drive that starts facing the wrong way is still routed, or the
	# exemption would swallow lane discipline whole.
	var far := MoveOrder.new(CityGrid.junction(Vector2i(4, 4)))
	await _place_unit(_car, CityGrid.junction(Vector2i(1, 1)), 0.0)
	_car.issue(far)
	await _idle(4)
	_check(not far._route.is_empty(),
		"but a long journey keeps its lane route even so (%d waypoints)"
		% far._route.size())
	_car.clear_orders()
	await _idle(4)


func _test_a_responding_vehicle_keeps_its_lane() -> void:
	# Corner to corner, so the drive is several streets and turns rather than one run.
	var from := CityGrid.junction(Vector2i(1, 1))
	var to := CityGrid.junction(Vector2i(4, 4))
	await _place_unit(_car, from + Vector3(0.0, 0.15, 0.0))
	_car.issue(MoveOrder.new(to))
	_check(_car.is_responding(), "the car is on a shout, not going home")

	var samples := 0
	var wrong := 0
	for i in 5400:
		await physics_frame
		if not _car.has_orders():
			break
		if not _on_open_street(_car.global_position):
			continue
		var across := _lane_offset(_car.global_position)
		var right := (-_car.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		samples += 1
		# A metre the wrong side is a wheel over the line rather than a car in the
		# oncoming lane -- the same tolerance the return and the traffic use.
		if across.dot(right.normalized()) < -1.0:
			wrong += 1

	_check(samples > 100, "sampled the response %d times" % samples)
	# Turn arcs reach past the junction box and are counted, so this is not zero: a car
	# coming round a corner is over the line by definition. Sabotaging the lane route
	# in *this* scenario measures **69%** -- and the drive takes four times as long --
	# so the margin is wide. (The standalone diagnostic measures 37% on its own shorter
	# route; the number that matters here is the one this check itself moves by.)
	_check(wrong * 5 < samples,
		"and it kept its side of the road on the way (%d of %d over the line, %.0f%%)"
			% [wrong, samples, 100.0 * wrong / maxi(samples, 1)])
	_car.clear_orders()
	await _idle(4)


func _test_a_returning_vehicle_keeps_its_lane() -> void:
	_buy(&"ambulance", 1)
	var van := _station.dispatch(&"ambulance") as Vehicle
	if van == null:
		_check(false, "a spare ambulance to send home")
		return
	await _idle(4)
	# Well across the district, so the route home is several streets and turns rather
	# than one straight run. Faced towards its first junction, as the old start was by
	# accident of the old grid: opening with a three-point turn would fill the sample
	# with the manoeuvre and measure that instead of the driving.
	await _place_unit(van, Vector3(20.0, 0.15, -45.0), PI)
	van.issue(ReturnOrder.new(_station))

	var samples := 0
	var wrong := 0
	for i in 3000:
		await physics_frame
		if not is_instance_valid(van) or not van.has_orders():
			break
		if not _on_open_street(van.global_position):
			continue
		var across := _lane_offset(van.global_position)
		var right := (-van.global_basis.z).cross(Vector3.UP)
		right.y = 0.0
		if right.length() < 0.01:
			continue
		samples += 1
		# A metre the wrong side is a wheel over the line rather than a vehicle in the
		# oncoming lane, which is the tolerance traffic is measured against too.
		if across.dot(right.normalized()) < -1.0:
			wrong += 1

	_check(samples > 40, "sampled the drive home %d times" % samples)
	# Tight, because it measures **zero**: since the routing moved to
	# CityGrid.lane_route the drive home does not put a wheel over the line at all, and
	# a bar of "under a tenth" would have passed at ninety-six bad samples out of a
	# thousand. The old 6%-with / 18%-without figures predate the shared route and no
	# longer describe this scenario.
	_check(wrong * 30 < samples,
		"and it kept its side of the road (%d of %d over the line, %.0f%%)"
			% [wrong, samples, 100.0 * wrong / maxi(samples, 1)])
	_check(is_instance_valid(van) and _station.is_home(van.global_position),
		"arriving home and parking on the forecourt")
	_dissolve(van, &"ambulance")
	await _idle(4)


## The route itself, rather than a statistic about driving it. Sampling a drive can
## only ever say "mostly" -- a car swings wide, brakes late, gets nudged. The waypoints
## are exact, and every one of them on a street should be in the right-hand lane.
func _test_the_route_home_is_laid_out_in_lane() -> void:
	_buy(&"ambulance", 1)
	var van := _station.dispatch(&"ambulance") as Vehicle
	if van == null:
		_check(false, "a spare ambulance to route home")
		return
	await _idle(4)
	await _place_unit(van, Vector3(20.0, 0.15, -45.0))

	var order := ReturnOrder.new(_station)
	var route: Array[Vector3] = order._build_route(van)
	_check(route.size() >= 6,
		"the way home is laid out as %d waypoints, not one" % route.size())

	var checked := 0
	var offside := 0
	for i in range(route.size() - 1):
		var here := _lane_offset(route[i])
		var next := _lane_offset(route[i + 1])
		# Both ends on the same street. A pair that crosses a junction has a diagonal
		# between them and no single side to be on.
		if here == Vector3.ZERO or next == Vector3.ZERO:
			continue
		if is_zero_approx(here.x) != is_zero_approx(next.x):
			continue
		var direction := route[i + 1] - route[i]
		direction.y = 0.0
		if direction.length() < 1.0:
			continue
		checked += 1
		if here.dot(direction.normalized().cross(Vector3.UP)) < 1.0:
			offside += 1

	_check(checked >= 3, "%d of those waypoints sit on an open street" % checked)
	_check(offside == 0,
		"and every one is in the right-hand lane (%d were not)" % offside)
	_dissolve(van, &"ambulance")
	await _idle(4)


## The route home is exact, so the left-turn fix can be asserted on the waypoint
## itself rather than a statistic: a leg that starts with a left turn must carry a
## point inside the junction box, on the driver's own quadrant.
func _test_the_route_home_rounds_left_turns() -> void:
	await _place_unit(_ambulance, Vector3(20.0, 0.15, -45.0), PI)
	var order := ReturnOrder.new(_station)
	var route := order._build_route(_ambulance)

	# The BFS route from here runs west, west, then south to the station -- so the
	# turn at the junction two avenues over is a left, and must be rounded.
	var turn := CityGrid.junction(Vector2i(1, 2))
	var apex := Vector3.ZERO
	for point in route:
		if _flat_distance(point, turn) < 4.0:
			apex = point
	_check(apex != Vector3.ZERO,
		"the route home carries a waypoint inside the left-turn junction box")
	_check(apex != Vector3.ZERO and apex.x < turn.x and apex.z < turn.z,
		"on the driver's own quadrant of it (%s)" % apex)
	_ambulance.clear_orders()


func _clear_cordons() -> void:
	for node in get_nodes_in_group(Cordon.GROUP):
		node.queue_free()
	_officer.clear_orders()
	await _idle(4)


func _test_work_order_survives_target_loss() -> void:
	await _clear_incidents()
	# Far enough that the officer is still walking when the target disappears, which
	# is the case most likely to strand an order mid-approach.
	var fire := _spawn_fire(Vector3(10.0, 0.0, 14.0), 0.5)
	await _place_unit(_officer, Vector3(27.0, 0.1, 14.0))
	_officer.issue(ExtinguishOrder.new(fire))
	await _wait(25)
	_check(_officer.has_orders(), "the order is running before the target is lost")

	fire.queue_free()
	await _wait(20)
	_check(not _officer.has_orders(), "the order ended when the fire vanished")
	_check(not _officer.is_navigating(), "and the officer stopped walking")
	_check(_officer.action_clip.is_empty(), "and dropped the work clip")
	await _clear_incidents()


func _test_transport_to_hospital() -> void:
	await _clear_incidents()
	var casualty := _spawn_casualty(Vector3(18.0, 0.0, -12.0))
	# Pre-treated: this test is about the ride, not the treatment.
	casualty.treat(1.0)
	_check(casualty.is_stable, "the casualty is stable before collection")
	_check(casualty.active,
		"and the incident is still open -- stabilising is not saving them")

	# Collect is the paramedic's verb: the stretcher run. The ambulance itself waits
	# at the kerb -- its navigation mesh is the road and a casualty usually is not.
	var patrol_verb := _car.resolve(_target_for(casualty))
	_check(patrol_verb != null and patrol_verb.id() == &"move",
		"a patrol car means Move (got '%s')"
		% ("none" if patrol_verb == null else patrol_verb.id()))
	var wheels_verb := _ambulance.resolve(_target_for(casualty))
	_check(wheels_verb != null and wheels_verb.id() == &"move",
		"and so does the ambulance -- the stretcher does the collecting (got '%s')"
		% ("none" if wheels_verb == null else wheels_verb.id()))
	var officer_verb := _officer.resolve(_target_for(casualty))
	_check(officer_verb != null and officer_verb.id() == &"move",
		"and an officer, who has no stretcher to fetch (got '%s')"
		% ("none" if officer_verb == null else officer_verb.id()))
	var ability := _paramedic.resolve(_target_for(casualty))
	_check(ability != null and ability.id() == &"collect",
		"a stable casualty resolves to Collect for a paramedic (got '%s')"
		% ("none" if ability == null else ability.id()))
	if ability == null:
		return

	await _place_unit(_ambulance, Vector3(20.0, 0.2, -2.0))
	await _place_unit(_paramedic, Vector3(20.0, 0.0, -8.0))
	_paramedic.issue(ability.make_order(_paramedic, _target_for(casualty)))
	var wheeled := await _await_orders_done(_paramedic, 3000)
	_check(wheeled, "the paramedic ran the stretcher round trip")
	_check(casualty.is_loaded, "the casualty is aboard")
	_check(_ambulance.casualties.size() == 1,
		"the ambulance reports 1 aboard (%d)" % _ambulance.casualties.size())
	_check(not casualty.visible, "and is hidden while riding")
	_check(_paramedic.get_node_or_null("Stretcher") == null,
		"the stretcher went back with the handover")

	_ambulance.issue(MoveOrder.new(_hospital.global_position))
	await _await_orders_done(_ambulance, 3600)
	_check(not is_instance_valid(casualty) or not casualty.active,
		"driving into the hospital delivered them")
	_check(_ambulance.casualties.is_empty(), "the ambulance is empty again")
	await _clear_incidents()


## The regression that forced the stretcher: a casualty in the middle of a park,
## where no vehicle mesh runs. The old vehicle Collect parked as close as the road
## ran and never closed the gap; the paramedic closes it on foot.
func _test_a_stretcher_reaches_where_wheels_cannot() -> void:
	await _clear_incidents()
	var park := CityGrid.block_centre(1, 0)
	var casualty := _spawn_casualty(park)
	casualty.treat(1.0)

	var road_gap := INF
	for band in CityGrid.BANDS:
		road_gap = minf(road_gap, minf(
			absf(park.x - CityGrid.band_centre_x(band)),
			absf(park.z - CityGrid.band_centre_z(band))))
	_check(road_gap > 9.0,
		"the park centre is genuinely off the road network (%.1fm)" % road_gap)

	# The ambulance parks at the nearest crossroads; the paramedic starts beside it.
	var kerb := CityGrid.junction(Vector2i(2, 1))
	await _place_unit(_ambulance, kerb)
	await _place_unit(_paramedic, kerb + Vector3(3.0, 0.0, 0.0))
	var ability := _paramedic.resolve(_target_for(casualty))
	if ability == null or ability.id() != &"collect":
		_check(false, "the park casualty resolves to Collect")
		await _clear_incidents()
		return
	_paramedic.issue(ability.make_order(_paramedic, _target_for(casualty)))
	var wheeled := await _await_orders_done(_paramedic, 6000)
	_check(wheeled and casualty.is_loaded and _ambulance.casualties.size() == 1,
		"wheeled aboard from the middle of a park (done %s, aboard %s)"
		% [wheeled, casualty.is_loaded])
	_ambulance.casualties.clear()
	casualty.queue_free()
	await _clear_incidents()
	_reset_mission()


func _test_mission_wins_when_everything_is_clear() -> void:
	# Earlier tests resolve incidents of their own, so the tallies are reset here
	# rather than assumed. This is about the win rule, not the running total.
	await _clear_incidents()
	_reset_mission()

	var fire := _spawn_fire(Vector3(22.0, 0.0, 8.0), 0.4)
	await _wait(6)
	_check(_mission.fires_remaining() == 1,
		"the mission sees 1 fire burning (%d)" % _mission.fires_remaining())
	_check(_mission.state == Mission.State.RUNNING, "and is still running")

	fire.douse(5.0)
	await _wait(10)
	_check(_mission.fires_out == 1, "counted the fire as out (%d)" % _mission.fires_out)
	_check(_mission.state == Mission.State.WON, "won once nothing was left burning")
	# The win puts a modal over the district and it stays there until dismissed, which
	# is the point of it -- so this test clears up after itself rather than leaving the
	# rest of the suite clicking through a card it cannot see.
	_reset_mission()


func _test_mission_is_lost_when_a_casualty_dies() -> void:
	await _clear_incidents()
	_reset_mission()

	var casualty := _spawn_casualty(Vector3(22.0, 0.0, 8.0))
	# On the edge, and declining fast, so the test does not sit through 80 seconds.
	casualty.health = 0.05
	casualty.decline_per_second = 1.0
	await _wait(30)
	_check(_mission.casualties_lost == 1,
		"counted the casualty as lost (%d)" % _mission.casualties_lost)
	_check(_mission.state == Mission.State.LOST, "and the shout is lost")

	await _clear_incidents()
	_reset_mission()


# --- Freeplay: the director and the score ------------------------------------

func _test_the_director_sleeps_until_started() -> void:
	await _clear_calls()
	if _director == null:
		_check(false, "the map ships a Director")
		return
	_check(not _director.active, "the director sleeps until a shift is opened")

	# Wound right down, so if the gate were broken this would catch it inside the
	# window rather than passing because the default first call is 10 seconds out.
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.3
	_director.call_interval_max = 0.3
	await _wait(90)
	_check(get_nodes_in_group(Incident.GROUP).is_empty(),
		"and opens nothing on its own (%d incidents)"
		% get_nodes_in_group(Incident.GROUP).size())


## The navigation overlay ships off, and draws nothing until it is switched on.
##
## Same rule the director lives by: a diagnostic that starts on is a diagnostic that
## ships on, and this one draws over the whole district. Checking `showing` alone would
## pass on an overlay that is invisible but still rebuilding a mesh from every vehicle
## every frame, so the node's own visibility is checked too.
func _test_the_navigation_overlay_is_off_until_asked() -> void:
	var overlay := _scene.get_node_or_null("NavDebug") as Node3D
	_check(overlay != null, "the district carries a navigation overlay")
	if overlay == null:
		return
	_check(not overlay.get("showing"), "which is off on a district nobody has asked")
	_check(not overlay.visible, "and draws nothing while it is")


func _test_the_director_opens_calls_where_they_belong() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 7
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.5
	_director.call_interval_min = 1.5
	_director.call_interval_max = 1.5
	_director.max_open_calls = 4
	_director.breather = 0.5
	_director.begin_shift()
	_check(_director.active, "begin_shift opens the shift")
	_check(_mission.scoring, "and the mission starts scoring")

	# Capped at 5 game-seconds on purpose: by 8 a fire would be established enough to
	# spread, and a spread body lands 5m from its parent -- inside the clearance this
	# test is asserting.
	var titles := {}
	for i in 300:
		await physics_frame
		for call in _board.open_calls():
			titles[call.title()] = true
		if _board.open_calls().size() >= 3:
			break
	var open := _board.open_calls()
	_check(open.size() >= 3,
		"the district produced %d simultaneous calls" % open.size())

	var clear := true
	for node in get_nodes_in_group(Incident.GROUP):
		var incident := node as Incident
		if incident == null:
			continue
		if _flat_distance(incident.global_position, _station.global_position) \
					< Director.CLEAR_OF_FORECOURTS \
				or _flat_distance(incident.global_position, _hospital.global_position) \
					< Director.CLEAR_OF_FORECOURTS:
			clear = false
	_check(clear, "every call keeps clear of the station and hospital forecourts")

	# Not measured off the live calls, deliberately: the board already refuses to open
	# a second call within GROUPING_RADIUS, so a distance check on open calls passes
	# whatever the director does. The invariant that actually matters is that the
	# director's spacing clears the board's grouping -- shrink it below and a "new"
	# call would silently join the scene it was meant to be distinct from.
	_check(Director.CLEAR_OF_OTHER_CALLS > Call.GROUPING_RADIUS,
		"a new call is kept further from an open one than the board would group (%0.f > %0.f)"
		% [Director.CLEAR_OF_OTHER_CALLS, Call.GROUPING_RADIUS])

	var known := true
	for title in titles:
		if title not in ["Medical emergency", "Fire", "Road traffic collision",
				"Disturbance", "Vehicle fire", "Electrical fire, water unsuitable",
				"Bus collision, multiple casualties", "Shed load blocking the road",
				"Person collapsed, drink suspected", "Child reported missing"]:
			known = false
	_check(known and titles.size() >= 2,
		"the mix drew %d kinds, all of them answerable by the roster (%s)"
		% [titles.size(), ", ".join(titles.keys())])
	await _end_freeplay()


func _test_the_director_caps_simultaneous_calls() -> void:
	_director.shift_seed = 11
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.4
	_director.call_interval_max = 0.4
	_director.max_open_calls = 2
	_director.breather = 0.2
	_director.begin_shift()

	# Interval far below the cap: left ungoverned this would be a call every 0.4s.
	var worst := 0
	for i in 300:
		await physics_frame
		worst = maxi(worst, _board.open_calls().size())
	_check(worst > 0, "calls opened under the cap test (%d)" % worst)
	_check(worst <= 2, "and never more than the cap of 2 at once (worst %d)" % worst)
	await _end_freeplay()


func _test_the_director_breathes_after_a_close() -> void:
	_director.shift_seed = 3
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 0.2
	_director.call_interval_max = 0.2
	_director.max_open_calls = 1
	_director.breather = 4.0
	_director.begin_shift()

	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to close for the breather test")
		await _end_freeplay()
		return
	var first := _board.open_calls()[0]
	_resolve_call(first)
	await _idle(6)
	_check(not first.is_open(), "dealing with the scene closed its call")

	# Two seconds of the four-second breather: nothing new may open in it.
	var quiet := true
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			quiet = false
	_check(quiet, "the district gets its breather before the next call")

	var next := false
	for i in 360:
		await physics_frame
		if not _board.open_calls().is_empty():
			next = true
			break
	_check(next, "and the next call comes once it has passed")
	await _end_freeplay()


## The set-piece call. Two casualties in the same crossroads have to read as one job
## with a name, not as a pair of unrelated collapses.
func _test_an_rtc_reads_as_one_call() -> void:
	await _clear_calls()
	var cell := Vector2i(2, 1)
	_director._spawn_rtc(cell)
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(bodies == 2, "an RTC puts two casualties in the road (%d)" % bodies)
	var open := _board.open_calls()
	_check(open.size() == 1, "grouped as a single call (%d)" % open.size())
	if not open.is_empty():
		_check(open[0].title() == "Road traffic collision",
			"titled by what happened, not what it left behind ('%s')" % open[0].title())
		_check(_flat_distance(open[0].position, CityGrid.junction(cell)) < 5.0,
			"and placed at the crossroads (%.1fm out)"
			% _flat_distance(open[0].position, CityGrid.junction(cell)))
	await _clear_calls()


## The RTC grown into a mass-casualty scene: sized by the medical roster, gentled so it
## reads as triage rather than a massacre, wearing a bus, and still one call.
func _test_a_bus_collision_scales_to_the_medical_roster() -> void:
	await _clear_calls()
	# A bare medical roster for the bottom BUS_SIZE row. The fixture fleet owns three
	# medical hands (an ambulance and two paramedics), which is already the middle row.
	var kept_ambulances := int(_station.owned.get(&"ambulance", 0))
	var kept_paramedics := int(_station.owned.get(&"paramedic", 0))
	_station.owned[&"ambulance"] = 0
	_station.owned[&"paramedic"] = 0
	_director._rng.seed = 5
	_director._spawn_bus_rtc(Vector2i(2, 1))
	_station.owned[&"ambulance"] = kept_ambulances
	_station.owned[&"paramedic"] = kept_paramedics
	await _idle(6)

	var bodies: Array[Casualty] = []
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		bodies.append(node as Casualty)
	_check(bodies.size() == 3,
		"a bus collision on a bare roster is three casualties (%d)" % bodies.size())
	var open := _board.open_calls()
	_check(open.size() == 1, "grouped as a single call (%d)" % open.size())
	if not open.is_empty():
		_check(open[0].title() == "Bus collision, multiple casualties",
			"titled by what happened ('%s')" % open[0].title())
	var gentled := not bodies.is_empty()
	for body in bodies:
		if body.decline_per_second > 0.011:
			gentled = false
	_check(gentled, "every casualty declines at the gentled rate")

	# The bus itself: a stripped Town-pack prop among the bodies, not an incident.
	var wreck: Node3D = null
	for child in _incidents.get_children():
		if not (child is Incident) and str(child.scene_file_path).contains("Bus"):
			wreck = child
	_check(wreck != null, "and a bus lies at the junction")

	# Resolve the whole scene from code: the wreck leaves with the *last* casualty.
	# **The flag is latched before the delivery, not read after it.** A freed object
	# compares equal to null, so `wreck != null` after the free is false and the check
	# would fail on exactly the behaviour it exists to confirm.
	var had_wreck := wreck != null
	for body in bodies:
		body.treat(1.0)
		body.deliver()
	await _idle(6)
	_check(had_wreck and not is_instance_valid(wreck),
		"the bus goes with the last of them")
	await _clear_calls()


## The same scene against fatter rosters: more medical hands, more patients.
func _test_a_bus_collision_grows_with_the_roster() -> void:
	await _clear_calls()
	# The fixture fleet's three medical hands are the middle BUS_SIZE row.
	_director._rng.seed = 9
	_director._spawn_bus_rtc(Vector2i(3, 2))
	await _idle(6)
	var middle := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(middle == 4,
		"a bus collision on the fixture roster is four casualties (%d)" % middle)
	await _clear_calls()

	# Four extra paramedics on the books -- bought, never dispatched -- takes the
	# medical hands to seven, the top row.
	_buy(&"paramedic", 4)
	_director._rng.seed = 9
	_director._spawn_bus_rtc(Vector2i(3, 2))
	await _idle(6)
	var full := get_nodes_in_group(Casualty.CASUALTY_GROUP).size()
	_check(full == 5,
		"and five against a full medical roster (%d)" % full)
	_station.owned[&"paramedic"] = int(_station.owned.get(&"paramedic", 0)) - 4
	_station._save_career()
	_station.roster_changed.emit()
	await _clear_calls()


## The pacing constants are not flat: the district gets busier as the shift wears
## on. Pure arithmetic on the director, asserted at the three points that matter.
func _test_the_director_escalates_late_in_the_shift() -> void:
	_director.shift_length = 100.0
	_director.max_open_calls = 3
	_director.clock = 0.0
	_check(_director.current_cap() == 3,
		"the shift opens at the flat cap (%d)" % _director.current_cap())
	_check(absf(_director.interval_scale() - 1.0) < 0.01,
		"with the intervals unscaled (x%.2f)" % _director.interval_scale())

	_director.clock = 70.0
	_check(_director.current_cap() == 4,
		"the late surge takes one extra call at once (%d)" % _director.current_cap())
	_check(_director.interval_scale() < 0.75,
		"with calls arriving faster (x%.2f)" % _director.interval_scale())

	_director.clock = 100.0
	_check(_director.interval_scale() <= _director.late_interval_scale + 0.01,
		"sliding to the floor by the final bell (x%.2f)" % _director.interval_scale())
	_director.clock = 0.0
	_director.shift_length = 300.0


## A car alight at the kerb: parked against the edge of a street, wearing a wreck,
## named for what it is -- and the wreck goes when the fire does.
func _test_a_vehicle_fire_burns_at_the_kerb() -> void:
	await _clear_calls()
	_director._rng.seed = 42
	_director._spawn_vehicle_fire()
	await _idle(6)

	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	if fires.size() != 1:
		_check(false, "a vehicle fire on the map (%d fires)" % fires.size())
		return
	var fire := fires[0] as Fire
	_check(fire.flavour == "Vehicle fire",
		"the fire knows what it is ('%s')" % fire.flavour)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Vehicle fire",
		"and the board names the job ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	# At the kerb of a street: on a road band along exactly one axis -- between
	# junctions, off the blocks -- and pulled to the carriageway's edge.
	var spot := fire.global_position
	_check(_in_band_x(spot.x) != _in_band_z(spot.z),
		"it burns on a street, not a junction or a block (%.1f, %.1f)"
		% [spot.x, spot.z])
	var off_centre := INF
	for band in CityGrid.BANDS:
		off_centre = minf(off_centre, minf(
			absf(spot.x - CityGrid.band_centre_x(band)),
			absf(spot.z - CityGrid.band_centre_z(band))))
	_check(absf(off_centre - Director.KERB_OFFSET) < 0.6,
		"parked against the kerb (%.1fm off the centre line)" % off_centre)

	var wreck := _wrecks()
	_check(wreck.size() == 1, "with a wreck under the flames (%d)" % wreck.size())

	# The bug this check exists for: Fire._spread() clones itself with duplicate(),
	# which copies children -- so a wreck parented to the fire bred a new car on the
	# street with every spread. It is a sibling now, and spreading must not multiply
	# it. Wound right down so the spread happens inside the window.
	fire.intensity = 0.95
	fire.spread_interval = 0.2
	var spread := false
	for i in 240:
		await physics_frame
		if get_nodes_in_group(Fire.FIRE_GROUP).size() > 1:
			spread = true
			break
	_check(spread, "the fire spread (%d fires)"
		% get_nodes_in_group(Fire.FIRE_GROUP).size())
	_check(_wrecks().size() == 1,
		"and one burning car stayed one burning car (%d wrecks)" % _wrecks().size())

	for node in get_nodes_in_group(Fire.FIRE_GROUP):
		(node as Fire).douse(5.0)
	await _idle(8)
	_check(_board.open_calls().is_empty(), "dousing it clears the call")
	_check(_wrecks().is_empty(), "and the wreck went with the fire")
	await _clear_calls()


## Before the law arrives a disturbance is somebody, not a statue: animated from
## the first frame (the first suspect shipped in a T-pose -- the clip name it
## trusted was not on the rig), pacing a few metres about the scene along the
## pedestrian graph, and never leaving it.
func _test_a_disturbance_lives_before_the_law() -> void:
	await _clear_calls()
	_director._rng.seed = 21
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerbside spot for the disturbance")
		return
	var suspect := _director._spawn_suspect(spot)
	await _wait(20)
	var player := suspect.get_node("Character/AnimationPlayer") as AnimationPlayer
	_check(player.current_animation != "",
		"a fresh suspect is animated, not a T-pose ('%s')" % player.current_animation)

	var moved := 0.0
	var legal := true
	for i in 600:
		await physics_frame
		if not is_instance_valid(suspect):
			break
		var away := _flat_distance(suspect.global_position, spot)
		moved = maxf(moved, away)
		if away > 0.5 and not _pedestrian_legal(suspect.global_position):
			legal = false
	_check(moved > 0.8,
		"they pace about the scene (peaked %.1fm from the spot)" % moved)

	# The moonwalk again, in a second costume: Person.tscn yaws its visual 180 and
	# the whole project steers on that assumption, but Suspect.tscn shipped without
	# it and the first disturbance paced about backwards. Nothing in code reads the
	# model's orientation, so only an explicit check catches it.
	var was := suspect.global_position
	var backwards := 0
	var sampled := 0
	for i in 600:
		await physics_frame
		if not is_instance_valid(suspect):
			break
		var travel := suspect.global_position - was
		was = suspect.global_position
		travel.y = 0.0
		if travel.length() < 0.01:
			continue
		sampled += 1
		var face: Node3D = suspect.get_node("Character")
		if face.global_basis.z.normalized().dot(travel.normalized()) < 0.8:
			backwards += 1
	_check(sampled > 20, "sampled the pacing %d times" % sampled)
	_check(backwards == 0,
		"and they walk forwards, not backwards (%d of %d steps moonwalked)"
		% [backwards, sampled])
	_check(moved <= suspect.wander_radius + 1.5,
		"without leaving it (radius %.1f)" % suspect.wander_radius)
	_check(legal, "and keep to the pedestrian graph")

	# **Cuffed, they stand still.** They used to trudge back to the spot the call opened
	# on, because that kerb was where the patrol car's reach was measured from -- the car
	# came to them. Since the escort moved onto the officer's feet in August 2026 nothing
	# needs them at a particular place, and walking off on their own would mean an officer
	# sent to collect somebody arrives to find them somewhere else.
	#
	# Caught mid-pace, or the check proves nothing: a suspect who happened to be standing
	# still anyway would pass it without the detained branch existing at all.
	var away_now := 0.0
	for i in 600:
		await physics_frame
		away_now = _flat_distance(suspect.global_position, spot)
		if away_now > 1.2:
			break
	if away_now <= 1.2:
		_check(false, "caught the suspect mid-pace to cuff them")
	else:
		suspect.detain(1.0)
		var cuffed_at := suspect.global_position
		var drifted := 0.0
		for i in 600:
			await physics_frame
			drifted = maxf(drifted, _flat_distance(suspect.global_position, cuffed_at))
		_check(drifted < 0.5,
			"cuffed, they stand where they are rather than wandering (%.2fm)" % drifted)
	await _clear_calls()


## The fire service, end to end. Its shape is the point: one verb done properly, a
## rate that depends on standing near your own appliance, and a kind of fire nobody
## else can touch.
## The appliance raises its ladder while its hose is being worked, and lowers it after.
##
## This is what the fire engine does instead of swinging rear doors. The van it replaced
## had them as separate meshes and the real appliance has none, so the flourish moved
## from the back of the vehicle to the top of it -- and it is wired to something true
## rather than to a timer: `ExtinguishOrder` asks for it every frame it draws from this
## appliance's tank, so an engine parked doing nothing keeps its ladder stowed and one
## actually supplying a hose puts it up.
## A fire's visuals answer to its intensity, sub-emitters included.
##
## Nothing pinned the fire's appearance at all until August 2026, in either direction:
## the flame was a cone and two hand-built quad emitters, and a regression in any of it
## would have gone unnoticed. That mattered when they were replaced by the particle
## pack's, whose fire is not one emitter but three -- flame, embers and a ground spread
## -- because `amount_ratio` does not inherit, and a fire barely alight would otherwise
## still throw a full complement of embers.
## Fires of different kinds behave differently, and a car fire costs you to park by.
##
## A fire was one thing with four fields the director set inline, and the only difference
## it expressed was whether a hose was needed. Three kinds now carry their own rates,
## plume and spread, and the table is the only place they are written down -- which is
## worth pinning, because a table that drifts back into agreement is a table that stopped
## doing anything.
## A cylinder heats beside a fire, cools under a hose, and takes the street with it if
## nobody deals with it.
##
## The first thing in the district that acts rather than waits. Everything else here gets
## worse and eventually fails; this one damages what is parked near it, hurts whoever is
## standing near it and throws fires of its own -- so it is worth pinning that it can be
## beaten, and that the blast lands where a blast may land.
func _test_a_cylinder_cooks_off() -> void:
	await _clear_incidents()
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	await _idle(30)
	_check(is_zero_approx(hazard.heat),
		"a cylinder with nothing burning near it is cold (%.2f)" % hazard.heat)

	var fire := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 1.0)
	fire.growth_per_second = 0.0
	await _idle(120)
	var warmed := hazard.heat
	_check(warmed > 0.0, "a fire beside it starts cooking it (%.2f after 2s)" % warmed)

	# Put the fire out and it sheds heat on its own -- which is what makes "deal with the
	# fire first" a real answer rather than a race that is always lost.
	fire.douse(2.0)
	await _idle(120)
	_check(hazard.heat < warmed,
		"and it cools once the fire is out (%.2f from %.2f)" % [hazard.heat, warmed])
	await _clear_incidents()


## The blast, staged rather than waited for: what it costs, and where it puts its fires.
func _test_a_cylinder_going_off_takes_the_street() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	if engine == null:
		_check(false, "an engine to park beside it")
		return
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	await _place_unit(engine, spot + Vector3(4.0, 0.2, 0.0))
	engine.repair_bill = 0
	await _idle(4)

	# **The hazard is gone by the time this is read**, because `_finish()` frees it, so
	# the outcome is taken off the signal rather than off the object. The first cut read
	# `hazard.active` after the blast, which raises a runtime error -- and a runtime error
	# in this suite does not fail a check, it silently abandons the rest of the test. All
	# four checks below vanished and the run still reported green; only the count said so.
	# An Array box rather than a captured bool: GDScript lambdas capture by value.
	# Somebody standing in it, so the blast has a person to hurt. Without one the outfit
	# check below reads "0 bodiless of 0" and proves nothing -- which is how it first
	# went red, and a fair warning about staging a blast in an empty street.
	var bystander := _nearest_civilian(spot)
	if bystander:
		await _place_unit(bystander, spot + Vector3(2.0, 0.0, 0.0))
		await _idle(4)
	var outcome: Array = []
	hazard.resolved.connect(func(_incident: Incident, success: bool) -> void:
		outcome.append(success))
	hazard.heat = 1.0
	await _idle(10)
	_check(outcome == [false],
		"a cylinder at full heat goes off, and the call is lost (%s)" % [outcome])
	_check(engine.repair_bill > 0,
		"and bills what was parked beside it (£%d)" % engine.repair_bill)

	var lit := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(lit.size() > 0, "throwing fires of its own (%d)" % lit.size())
	# The same rule every placement in this game funnels through. A blast that lit the
	# inside of a building would be a call nobody could answer.
	var indoors := 0
	for node in lit:
		var tile := CityGrid.tile_at((node as Node3D).global_position)
		if not CityGrid.standable(tile.x, tile.y):
			indoors += 1
	_check(indoors == 0,
		"and none of them inside a building (%d of %d)" % [indoors, lit.size()])

	# **And the people it hurt have bodies.** `_hurt_people` dresses a new casualty in
	# the civilian's outfit, and it had the same one-directory bug that made a recruited
	# suspect invisible in play: `scene_file_path` is the *unit* scene, not the outfit,
	# and `ResourceLoader.exists()` accepts both. That twin was uncovered when the first
	# was found -- so this is here to stop the identical fault shipping twice.
	var bodiless := 0
	var hurt := 0
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty == null:
			continue
		hurt += 1
		var body := casualty.get_node_or_null("Character") as Node3D
		if body == null or not (body.scene_file_path in Incident.OUTFITS):
			bodiless += 1
	_check(hurt > 0 and bodiless == 0,
		"and whoever it hurt is wearing a real outfit (%d bodiless of %d)"
		% [bodiless, hurt])

	await _clear_incidents()
	_dissolve(engine, &"engine")
	await _idle(4)



## The stream is a readout, not a flourish: it shows up exactly where water is landing.
func _test_water_shows_where_it_is_landing() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"officer", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	var officer := _station.dispatch(&"officer") as Person
	if engine == null or crew == null or officer == null:
		_check(false, "an engine, a crew and an officer to send")
		return
	# Away from (20, -20), where the fire-service tests stage their own appliance.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	await _idle(4)

	_check(_jet_of(crew) == null, "a firefighter walking about carries no jet")

	crew.issue(ExtinguishOrder.new(fire))
	await _idle(30)
	var jet := _jet_of(crew)
	_check(jet != null and jet.emitting, "and on the job the water is running")
	if jet != null:
		# The stream has to leave the person and travel to the fire. Both halves matter:
		# a jet aimed correctly but emitted from the middle of the body reads as a
		# firefighter steaming rather than hosing.
		var chest := crew.global_position + Vector3.UP * Person.NOZZLE_HEIGHT
		_check(jet.global_position.distance_to(chest) > 0.2,
			"out of a nozzle in front of them (%.2fm)"
			% jet.global_position.distance_to(chest))
		# -Z is where a GPUParticles3D fires, so this is the aim itself rather than a
		# proxy for it.
		var aim := -jet.global_transform.basis.z.normalized()
		var at_fire := (fire.global_position - jet.global_position).normalized()
		_check(aim.dot(at_fire) > 0.98,
			"and pointed at the fire (%.3f of 1.0)" % aim.dot(at_fire))

	# The nozzle: the appliance's own, held in the hand the skeleton says is there.
	var nozzle := crew.get_node_or_null("HeldNozzle") as Node3D
	_check(nozzle != null and nozzle.visible, "a firefighter is holding a nozzle")
	if nozzle != null and jet != null:
		# In the hand, not floating at the middle of the body. Measured against the
		# skeleton rather than against a guessed height, because the hand is what the
		# code reads and a check on a constant would agree with itself.
		var skel := crew.get_node_or_null(
			"Character/Armature/GeneralSkeleton") as Skeleton3D
		var bone := skel.find_bone(Person.HAND_BONE) if skel else -1
		if bone >= 0:
			var hand: Vector3 = skel.global_transform \
				* skel.get_bone_global_pose(bone).origin
			_check(nozzle.global_position.distance_to(hand) < 0.05,
				"in the hand the skeleton reports (%.3fm off)"
				% nozzle.global_position.distance_to(hand))
		else:
			_check(false, "a RightHand bone to hold it in")
		# And the water leaves the muzzle rather than the grip, or the first half-metre
		# of the stream is inside the tool making it.
		var barrel := jet.global_position.distance_to(nozzle.global_position)
		_check(absf(barrel - Person.NOZZLE_LENGTH) < 0.02,
			"with the water leaving its muzzle (%.2fm down a %.2fm barrel)"
			% [barrel, Person.NOZZLE_LENGTH])

	# It expires on its own. Nothing tells it to stop -- the order simply stops asking,
	# and the ask times out.
	#
	# The fire is put **out** rather than the order cleared, which the first cut of this
	# did and which failed: a firefighter left standing beside a live fire with no orders
	# auto-engages and picks it straight back up, so the water quite correctly kept
	# running. That is the game working; the check was wrong.
	fire.douse(5.0)
	await _idle(45)
	jet = _jet_of(crew)
	_check(jet != null and not jet.emitting, "it stops when the work does")
	var stowed := crew.get_node_or_null("HeldNozzle") as Node3D
	_check(stowed != null and not stowed.visible, "and the nozzle goes away with it")

	# **The design pin.** A building fire yields to nothing but a hose, and an officer
	# in front of one achieves precisely nothing -- so they must not appear to be doing
	# something. The jet is driven by water delivered, not by an order being run, and
	# this is the check that says so.
	var building := _spawn_fire(spot + Vector3(0.0, 0.0, 8.0), 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	await _place_unit(officer, spot + Vector3(2.0, 0.0, 8.0))
	await _idle(4)
	officer.issue(ExtinguishOrder.new(building))
	await _idle(45)
	var officer_jet := _jet_of(officer)
	_check(officer_jet == null or not officer_jet.emitting,
		"and an officer achieving nothing on a building fire shows no water")
	# Not a vacuous pairing: the same officer on a fire they *can* fight does spray, so
	# the check above is about this fire and not about officers.
	officer.clear_orders()
	var bin := _spawn_fire(spot + Vector3(0.0, 0.0, 16.0), 0.6)
	bin.kind = Fire.Kind.BIN
	bin.growth_per_second = 0.0
	await _place_unit(officer, spot + Vector3(2.0, 0.0, 16.0))
	await _idle(4)
	officer.issue(ExtinguishOrder.new(bin))
	await _idle(30)
	officer_jet = _jet_of(officer)
	_check(officer_jet != null and officer_jet.emitting,
		"though the same officer on a bin fire does")
	# **No pack has a fire extinguisher** -- 516 props and not one, so an officer works
	# an implied tool rather than being handed the appliance's hose nozzle, which would
	# say the wrong thing about what a patrol car carries.
	_check(officer.get_node_or_null("HeldNozzle") == null,
		"and carries no hose nozzle, which is the appliance's")

	officer.clear_orders()
	crew.clear_orders()
	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	_dissolve(officer, &"officer")
	await _idle(4)


## The water jet a person has instanced, or null if they have never sprayed anything.
func _jet_of(person: Person) -> GPUParticles3D:
	if person == null or not is_instance_valid(person):
		return null
	for child in person.get_children():
		var jet := child as GPUParticles3D
		if jet:
			return jet
	return null



## Different fires want different things put on them, and the wrong thing does nothing.
func _test_a_fire_wants_the_right_stuff_on_it() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"officer", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	var officer := _station.dispatch(&"officer") as Person
	if engine == null or crew == null or officer == null:
		_check(false, "an engine, a crew and an officer to send")
		return
	# Away from (20, -20), which the fire-service tests stage their own appliance at.
	var spot := Vector3(-60.0, 0.0, 60.0)
	_check(engine.carries_foam, "the appliance carries foam as well as water")

	# A car burns fuel, so it costs foam -- and only foam.
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	var car := _spawn_fire(spot, 0.9)
	car.kind = Fire.Kind.VEHICLE
	car.growth_per_second = 0.0
	engine.water = 1.0
	engine.foam = 1.0
	crew.issue(ExtinguishOrder.new(car))
	await _wait(60)
	_check(engine.foam < 1.0 and is_equal_approx(engine.water, 1.0),
		"a car fire drains the foam and not the water (foam %.3f, water %.3f)"
		% [engine.foam, engine.water])
	# The foam has to be visibly foam, or the rule is a memory test. A separate scene,
	# not the water jet in another colour -- see FoamJet.tscn.
	var foam_jet := crew.get_node_or_null("FoamJet") as GPUParticles3D
	# Reads the node, so what it pins is that a **separate emitter** is built and
	# running -- not that the pixels look like foam, which no check can judge. That
	# distinction is the whole reason FoamJet.tscn is a second scene rather than the
	# water jet recoloured, so it is worth pinning even in this weaker form.
	_check(foam_jet != null and foam_jet.emitting,
		"and it comes out of its own emitter, not the water one")
	crew.clear_orders()

	# **Out of foam, with a full water tank.** This is the decision the second tank
	# exists to create: the crew are not dry, they are simply out of the only thing
	# that touches this, and a hydrant will not help them.
	engine.foam = 0.0
	engine.water = 1.0
	car.intensity = 0.9
	crew.issue(ExtinguishOrder.new(car))
	var before := car.intensity
	await _wait(90)
	_check(is_equal_approx(car.intensity, before),
		"out of foam the hose does nothing to a car (%.2f -> %.2f)"
		% [before, car.intensity])
	crew.clear_orders()

	# An officer's dry powder is genuinely multi-class, so they keep the fires they
	# always had. Without this the change would have quietly taken work away from police.
	await _place_unit(officer, spot + Vector3(-2.0, 0.0, 0.0))
	officer.issue(ExtinguishOrder.new(car))
	before = car.intensity
	await _wait(90)
	_check(car.intensity < before - 0.01,
		"but an officer's powder still takes it (%.2f -> %.2f)"
		% [before, car.intensity])
	# On a fire that *wants* foam, an officer still sprays the powder they carry -- the
	# jet follows the tool, not the target.
	_check(officer.get_node_or_null("FoamJet") == null,
		"and it is still powder, on a fire that wanted foam")
	officer.clear_orders()

	# The inversion: the one fire the appliance cannot fight and the patrol car can.
	var elec := _spawn_fire(spot + Vector3(0.0, 0.0, 14.0), 0.7)
	elec.kind = Fire.Kind.ELECTRICAL
	elec.growth_per_second = 0.0
	engine.water = 1.0
	engine.foam = 1.0
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 14.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 14.0))
	crew.issue(ExtinguishOrder.new(elec))
	before = elec.intensity
	await _wait(90)
	# **Guarded, because a fire that goes out frees itself.** Reading `.intensity` on a
	# freed incident raises, and a runtime error in this suite does not fail a check --
	# it abandons the rest of the test. A sabotage run proved it: five checks stopped
	# running and the suite reported green at 698. Being freed is itself the failure
	# here, so it is folded into the assertion rather than guarded around.
	var still_burning := is_instance_valid(elec)
	_check(still_burning and is_equal_approx(elec.intensity, before),
		"a full appliance does nothing to live electrics (%.2f -> %s)"
		% [before, "%.2f" % elec.intensity if still_burning else "put out"])
	crew.clear_orders()

	await _place_unit(officer, spot + Vector3(-2.0, 0.0, 14.0))
	officer.issue(ExtinguishOrder.new(elec))
	before = elec.intensity
	await _wait(90)
	# Out entirely is the best possible version of "took it", so a freed fire passes.
	var left := elec.intensity if is_instance_valid(elec) else 0.0
	_check(left < before - 0.01,
		"and the patrol car is the right answer to it (%.2f -> %.2f)" % [before, left])
	# **What comes out of the nozzle belongs to whoever is holding it.** Powder borrowed
	# the water jet at first, so an officer on an electrical fire was drawn spraying the
	# one substance the call exists to rule out. And the agent passed to the jet was the
	# fire's rather than the unit's, so an officer on a bin fire hosed water they do not
	# carry -- pinned below, because that one is silent rather than absurd.
	var powder := officer.get_node_or_null("PowderJet") as GPUParticles3D
	_check(powder != null and powder.emitting,
		"and it is powder coming out of the officer, not water")
	officer.clear_orders()

	# Said out loud on the call row, or none of the above is discoverable.
	_check("foam" in car.describe_state() and "powder" in elec.describe_state(),
		"the board says what each wants (%s / %s)"
		% [car.describe_state(), elec.describe_state()])

	# **A hydrant is a water main.** Water comes back at the kerb; foam only at home,
	# which is what makes a shift of car fires a reason to drive back.
	var hydrant := get_nodes_in_group(Hydrant.GROUP).front() as Node3D
	if hydrant != null:
		engine.water = 0.2
		engine.foam = 0.2
		await _place_unit(engine, hydrant.global_position + Vector3(1.5, 0.2, 0.0))
		engine.velocity = Vector3.ZERO
		await _wait(90)
		_check(engine.water > 0.25, "a hydrant puts water back (%.2f)" % engine.water)
		_check(is_equal_approx(engine.foam, 0.2),
			"and no foam at all (%.2f)" % engine.foam)
	else:
		_check(false, "a hydrant on the map to park beside")

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	_dissolve(officer, &"officer")
	await _idle(4)



## Someone pinned needs two services, and in an order.
func _test_a_trapped_casualty_needs_cutting_free_first() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	_buy(&"paramedic", 1)
	_buy(&"ambulance", 1)
	var crew := _station.dispatch(&"firefighter") as Person
	var medic := _station.dispatch(&"paramedic") as Person
	var ambulance := _station.dispatch(&"ambulance") as Vehicle
	if crew == null or medic == null or ambulance == null:
		_check(false, "a crew, a paramedic and an ambulance to send")
		return
	# Away from (20, -20), which the fire-service tests stage their own appliance at.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var casualty := _spawn_casualty(spot)
	casualty.trapped = true
	casualty.decline_per_second = 0.0
	await _place_unit(ambulance, spot + Vector3(8.0, 0.2, 0.0))
	await _place_unit(medic, spot + Vector3(2.0, 0.0, 0.0))
	await _place_unit(crew, spot + Vector3(-2.0, 0.0, 0.0))
	await _idle(6)

	# **Where it is, not merely that it exists.** The first version asserted only that a
	# Pin node had been created, and was perfectly happy with a four-metre pipe whose
	# origin is at one end -- which laid the whole length beside the casualty with one
	# end on their shins. A prop lying *next to* someone satisfies "there is something
	# lying on them" if nobody checks the geometry.
	var pin := casualty.get_node_or_null("Pin") as Node3D
	var over := INF
	if pin:
		var mesh := _first_mesh(pin)
		if mesh and mesh.mesh:
			var centre: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_center()
			var offset := centre - casualty.global_position
			offset.y = 0.0
			over = offset.length()
	_check(pin != null and over < 0.6,
		"there is something visibly lying on them (%.2fm off centre)" % over)
	_check(_find_ability(crew, &"free") != null
			and _find_ability(medic, &"free") == null,
		"a firefighter is offered Free and a paramedic is not")
	# **The gate that makes it a sequence.** A paramedic can treat them where they lie --
	# that is the whole reason arriving first is not wasted -- but nothing can lift them.
	casualty.treat(1.0)
	await _idle(4)
	_check(casualty.is_stable, "a paramedic can still treat someone who is pinned")
	var at_them := Target.new()
	at_them.position = casualty.global_position
	at_them.collider = casualty
	at_them.incident = casualty
	_check(_find_ability(medic, &"collect") != null
			and _find_ability(medic, &"collect").score(medic, at_them)
				== Ability.NOT_APPLICABLE,
		"but Collect declines a trapped casualty, so a right-click is a Move")

	# The crew do their half.
	crew.issue(FreeOrder.new(casualty))
	var before := casualty.release
	await _wait(120)
	_check(casualty.release > before, "a firefighter shifts the weight (%.2f from %.2f)"
		% [casualty.release, before])
	for i in 30:
		await _wait(20)
		if not casualty.trapped:
			break
	_check(not casualty.trapped, "and gets them out (release %.2f)" % casualty.release)
	_check(casualty.get_node_or_null("Pin") == null, "the load comes off with them")
	crew.clear_orders()

	# And only then is the ambulance any use.
	await _idle(6)
	_check(_find_ability(medic, &"collect").score(medic, at_them) > 0,
		"now the stretcher run is on")

	await _clear_incidents()
	_dissolve(crew, &"firefighter")
	_dissolve(medic, &"paramedic")
	_dissolve(ambulance, &"ambulance")
	_dissolve(_station.dispatch(&"engine") as Unit, &"engine")
	await _idle(4)


## The shed load shuts the street three ways, and each has its own witness: the board
## reads it as a scene hazard, the traffic-facing cordon stands raised without cones,
## and a vehicle's own road_is_blocked sees it -- which is what buys the reroute.
func _test_a_shed_load_shuts_the_street() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 13
	_director._spawn_shed_load()
	await _idle(6)

	var piles := get_nodes_in_group(Debris.DEBRIS_GROUP)
	if piles.size() != 1:
		_check(false, "a shed load on the map (%d)" % piles.size())
		_stand_to()
		return
	var debris := piles[0] as Debris
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].kind == Call.Kind.FIRE,
		"the board reads it as a scene hazard, not a medical call")
	_check(not open.is_empty() and open[0].title() == "Shed load blocking the road",
		"and names the job ('%s')" % (open[0].title() if not open.is_empty() else "no call"))
	var cordon := debris.get_node_or_null("Cordon") as Cordon
	_check(cordon != null and cordon.raised and cordon.get_child_count() == 0,
		"a raised cordon turns the traffic, with no cones -- the boxes are the visual")

	# The player's own routing sees it too. Pure cone math, so the street's axis does
	# not matter: the car sits 10m one side of the pile, the aim 10m past the other.
	var spot := debris.global_position
	await _place_unit(_car, spot + Vector3(10.0, 0.2, 0.0))
	var aim := spot - Vector3(10.0, 0.0, 0.0)
	_check(_car.road_is_blocked(aim), "a vehicle aimed past it reads the street as blocked")
	debris.clear(2.0)
	await _idle(6)
	_check(not _car.road_is_blocked(aim), "and clear again once the load is shifted")
	_stand_to()
	await _clear_calls()


## The Clear verb: both boots-on-the-ground services carry it, the medical service does
## not, and working it reopens the street and pays like a disaster prevented.
func _test_a_crew_clears_a_shed_load() -> void:
	await _clear_calls()
	await _park_the_shift()
	_buy(&"firefighter", 1)
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to send")
		return
	_mission.begin_scoring()
	_director._rng.seed = 21
	_director._spawn_shed_load()
	await _idle(6)

	var piles := get_nodes_in_group(Debris.DEBRIS_GROUP)
	if piles.size() != 1:
		_check(false, "a shed load on the map (%d)" % piles.size())
		_dissolve(crew, &"firefighter")
		await _end_freeplay()
		return
	var debris := piles[0] as Debris
	var target := _target_for(debris)
	_check(_find_ability(_officer, &"clear") != null
			and _find_ability(_officer, &"clear").score(_officer, target) > 0,
		"an officer is offered Clear on a shed load")
	_check(_find_ability(crew, &"clear") != null
			and _find_ability(crew, &"clear").score(crew, target) > 0,
		"and so is a firefighter -- box-lugging is not specialist work")
	_check(_find_ability(_paramedic, &"clear") == null,
		"a paramedic is not")
	var verb := _officer.resolve(target)
	_check(verb != null and verb.id() == &"clear",
		"right-clicking the load with an officer means Clear (got '%s')"
		% ("none" if verb == null else verb.id()))
	if verb == null:
		_dissolve(crew, &"firefighter")
		await _end_freeplay()
		return

	# The work. Sped up so the check measures the loop, not seven seconds of lugging.
	debris.clear_per_second = 0.9
	await _place_unit(_officer, debris.global_position + Vector3(4.0, 0.0, 0.0))
	_officer.issue(verb.make_order(_officer, target))
	var opened := false
	for i in 600:
		await physics_frame
		if not is_instance_valid(debris) or not debris.active:
			opened = true
			break
	_check(opened, "the officer works the load off the road")
	await _idle(8)
	_check(_board.open_calls().is_empty(), "the call closes with the street")
	_check(_mission.lanes_cleared == 1,
		"the debrief counts it (%d)" % _mission.lanes_cleared)
	# **Exact, not a floor.** The response bonus alone is 100, so a `>= 60` bound stayed
	# green with the whole Debris scoring arm deleted -- measured, via the sabotage run.
	# The disturbance test's equality is the precedent: scoring began at zero, the
	# officer is standing at the scene, so the sum is deterministic.
	_check(_mission.score == Mission.DEBRIS_POINTS + Mission.RESPONSE_BONUS,
		"scored like a disaster prevented plus the response bonus (%d, expected %d)"
		% [_mission.score, Mission.DEBRIS_POINTS + Mission.RESPONSE_BONUS])
	# A consistency assertion: deleting score and pay together keeps it green by
	# construction (both sides move). Its sabotage is dropping `_pay` alone, which
	# reddened it in isolation.
	_check(_mission.earned == _mission.score,
		"an obstruction pays what it scores (£%d)" % _mission.earned)
	_dissolve(crew, &"firefighter")
	await _end_freeplay()


## The dev call spawner: inert until asked, and it asks the director rather than placing
## anything itself.
func _test_calls_can_be_spawned_on_demand() -> void:
	await _clear_incidents()
	var spawner := _scene.get_node_or_null("CallSpawner") as CallSpawner
	if spawner == null:
		_check(false, "the map carries a call spawner")
		return
	_check(true, "the map carries a call spawner")
	# **Inert until a key is pressed.** The map ships quiet on purpose and a director that
	# could start on its own breaks dozens of checks at once; this builds nothing, watches
	# nothing and spawns nothing until asked.
	var built := 0
	for child in spawner.get_children():
		if child is CanvasLayer:
			built += 1
	_check(built == 0, "and has built nothing before it is opened")

	await _press_key(KEY_F5)
	await _idle(4)
	var layer: CanvasLayer = null
	for child in spawner.get_children():
		if child is CanvasLayer:
			layer = child
	_check(layer != null and layer.visible, "F5 opens it")
	# Built from the director's own table, so a call kind added there cannot go missing
	# from the tool because somebody forgot to list it twice. The +4 is the weather
	# preview strip, counted separately below.
	var buttons := 0
	var weather_row: HBoxContainer = null
	for node in _descendants(layer):
		if node is Button:
			buttons += 1
		if node.name == "WeatherRow":
			weather_row = node
	_check(buttons == _director.KINDS.size() + 4,
		"with a row for every call the director knows (%d of %d + 4 weather)"
		% [buttons, _director.KINDS.size()])
	_check(weather_row != null and weather_row.get_child_count() == 4,
		"and a weather preview strip with all four skies")

	# The preview drives the sky directly and leaves the settings card's stored choice
	# alone -- a dev tool must not rewrite what the player chose.
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	var kept_choice := _menu.wet_weather
	spawner.preview_weather(Daylight.Weather.FOG)
	_check(daylight != null and daylight.weather == Daylight.Weather.FOG,
		"pressing a sky previews it on the district")
	_check(_menu.wet_weather == kept_choice,
		"without touching the settings card's own choice")
	spawner.preview_weather(Daylight.Weather.CLEAR)
	_check(daylight != null and daylight.weather == Daylight.Weather.CLEAR,
		"and CLEAR puts the map back as generated")

	await _press_key(KEY_F5)
	await _idle(2)

	# And it actually opens one. Asked for by name, through the director.
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	spawner.spawn_call(&"trapped")
	await _idle(8)
	var pinned := 0
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty and casualty.trapped:
			pinned += 1
	_check(pinned > 0, "and asking for a trapped casualty produces one (%d)" % pinned)

	await _clear_incidents()
	await _idle(4)


## The first MeshInstance3D under [param root], for asking where a prop actually is
## rather than where its node was put.
func _first_mesh(root: Node) -> MeshInstance3D:
	var mesh := root as MeshInstance3D
	if mesh:
		return mesh
	for child in root.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null


## Every node under [param root], for counting widgets built at runtime.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child in root.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found



## A cylinder made safe closes its call. This is the check that was missing.
func _test_a_cylinder_made_safe_finishes_the_job() -> void:
	await _clear_incidents()
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	var fire := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 0.8)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	var outcome: Array = []
	hazard.resolved.connect(func(_incident: Incident, success: bool) -> void:
		outcome.append(success))
	await _wait(60)
	_check(hazard.active and hazard.heat > 0.0,
		"a cylinder beside a fire is a live job (%.2f)" % hazard.heat)

	# Put the fire out and take the heat off: the two ways it is beaten, together.
	fire.douse(5.0)
	hazard.cool(2.0)
	await _wait(60)
	# **The exit that did not exist.** `_finish(false)` on the blast was the only way out
	# of this incident until August 2026, so a gas leak beaten perfectly stayed on the
	# board for ever, the shift could not end, and HAZARD_POINTS was unreachable. Three
	# checks covered the hazard and every one tested a mechanism -- heats, cools, goes
	# bang -- and none asked whether the job could be finished.
	_check(outcome == [true],
		"cooled, with the fire out, it counts as made safe (%s)" % [outcome])
	_check(not is_instance_valid(hazard) or not hazard.active,
		"and the job is closed")
	await _clear_incidents()
	await _idle(4)


## A crowd turns unless somebody stands in it.
func _test_a_disorder_call_grows_until_it_is_contained() -> void:
	await _clear_incidents()
	_buy(&"officer", 1)
	var officer := _station.dispatch(&"officer") as Person
	if officer == null:
		_check(false, "an officer to send")
		return
	var spot := Vector3(-60.0, 0.0, 60.0)
	# Parked far enough away that the officer is not containing it by accident.
	await _place_unit(officer, spot + Vector3(40.0, 0.0, 0.0))

	var ringleader := _spawn_suspect(spot)
	ringleader.recruits = true
	# **Room to grow throughout.** The first cut capped this at 3, and the group hit the
	# cap during the first phase -- after which `_update_recruiting` returns at
	# `_group_size() >= max_group` *before* it ever asks `_is_contained()`. Both
	# containment checks then passed no matter what containment did, because the count
	# they watch could not move either way. The assertions were sound; the scenario was
	# saturated, which is a third way for a check to be worthless and the hardest to see.
	ringleader.max_group = 12
	ringleader.recruit_interval = 0.5
	ringleader.recruit_distance = 8.0
	# A bystander to draw in. Taken from the crowd rather than conjured, which is what
	# the mechanism itself does -- the person who joins in is somebody who was there.
	var bystander := _nearest_civilian(spot)
	if bystander == null:
		_check(false, "a bystander on the pavement to draw in")
		return
	await _place_unit(bystander, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(4)

	var before := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(90)
	var after := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	_check(after > before, "left alone it draws a bystander in (%d from %d)"
		% [after, before])

	# **And they have a body.** A civilian's `scene_file_path` is the *unit* scene, one
	# directory away from the outfit -- and `ResourceLoader.exists()` says yes to both,
	# so passing the wrong one silently gave the recruit a whole Civilian as its body,
	# script and all, which promptly walked off. The suspect was invisible; reported from
	# play, because nothing here looked at what the new arrival was wearing.
	var bodiless := 0
	var checked := 0
	for node in get_nodes_in_group(Suspect.SUSPECT_GROUP):
		var joined := node as Suspect
		if joined == null or joined == ringleader:
			continue
		checked += 1
		var body := joined.get_node_or_null("Character") as Node3D
		if body == null or not (body.scene_file_path in Incident.OUTFITS):
			bodiless += 1
	_check(checked > 0 and bodiless == 0,
		"and each of them is wearing a real outfit (%d bodiless of %d)"
		% [bodiless, checked])

	# **Containment, and the reason Secure now matters.** An officer standing in it takes
	# the heat out; so does a cordon, which until this call had no job in the game at all.
	await _place_unit(officer, spot + Vector3(3.0, 0.0, 0.0))
	await _idle(4)
	var held := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(120)
	var now := get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	# The headroom is asserted alongside the result, so this can never again pass because
	# the group had simply run out of room to grow.
	_check(now == held and held < ringleader.max_group,
		"an officer standing in it stops the spread (%d, was %d, cap %d)"
		% [now, held, ringleader.max_group])

	# And the cordon does it with nobody there.
	await _place_unit(officer, spot + Vector3(40.0, 0.0, 0.0))
	var cordon := Cordon.new()
	_scene.get_node("Incidents").add_child(cordon)
	cordon.global_position = spot
	cordon.raise_cordon()
	var another := _nearest_civilian(spot)
	if another:
		await _place_unit(another, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(4)
	held = get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	await _wait(120)
	now = get_nodes_in_group(Suspect.SUSPECT_GROUP).size()
	_check(now == held and held < ringleader.max_group,
		"and a cordon does it with nobody standing there (%d, was %d, cap %d)"
		% [now, held, ringleader.max_group])
	cordon.queue_free()

	# The job fits the roster rather than being withheld from it -- BUILDING_SIZE's rule.
	var sizes: Array = Director.DISORDER_SIZE
	var one: Dictionary = sizes[0]
	var many: Dictionary = sizes[sizes.size() - 1]
	_check(int(many["max_group"]) > int(one["max_group"]),
		"a bigger force gets a bigger job (%d against %d)"
		% [int(many["max_group"]), int(one["max_group"])])

	await _clear_incidents()
	_dissolve(officer, &"officer")
	await _idle(4)


## The nearest ambient civilian to [param point], for a test that needs a bystander.
func _nearest_civilian(point: Vector3) -> Civilian:
	var best: Civilian = null
	var closest := INF
	for node in get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian == null:
			continue
		var gap := civilian.global_position.distance_to(point)
		if gap < closest:
			closest = gap
			best = civilian
	return best



## Two in the back of a patrol car, walked there one at a time.
func _test_a_patrol_car_takes_two_prisoners() -> void:
	await _clear_incidents()
	# **A kerb the director itself would open a call on**, rather than a convenient-looking
	# coordinate. The first cut of this staged at (-60, 60) -- fine for the earlier tests
	# there, which only ever needed people to *stand* -- and the officer fell through the
	# world on the first step, reaching y = -11012 while the order patiently reported
	# "Escorting". Anything that has to walk needs ground the game vouches for.
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerb to stage an arrest on")
		return
	_check(_car.cells == 2, "a patrol car has two cells (%d)" % _car.cells)
	await _place_unit(_car, spot + Vector3(10.0, 0.2, 0.0))
	await _place_unit(_officer, spot + Vector3(3.0, 0.0, 0.0))

	var first := _spawn_suspect(spot)
	var second := _spawn_suspect(spot + Vector3(2.0, 0.0, 0.0))
	first.detain(1.0)
	second.detain(1.0)
	await _idle(6)

	# One at a time, because an officer has one pair of hands. The point of the check is
	# the *second* one: with a single cell the car was full after the first, and a scene
	# with two arrests needed two cars -- which the disorder call made the normal case.
	for suspect: Suspect in [first, second]:
		var verb := _officer.resolve(_target_for(suspect))
		if verb == null or verb.id() != &"escort":
			_check(false, "an officer offered Escort for each of them (got '%s')"
				% ("none" if verb == null else verb.id()))
			return
		_officer.issue(verb.make_order(_officer, _target_for(suspect)))
		for i in 900:
			await physics_frame
			if suspect.is_loaded:
				break
	_check(first.is_loaded and second.is_loaded,
		"both are walked in and both get in (%s, %s)"
		% [first.is_loaded, second.is_loaded])
	_check(_car.suspects.size() == 2, "the car is carrying two (%d)" % _car.suspects.size())

	# And it stops at two. With nowhere left to put anybody, Escort declines and a
	# right-click falls back to Move rather than starting a walk that cannot finish.
	#
	# **Every car, not just this one.** The first cut asserted a third was declined once
	# `_car` was full, and it was offered Escort anyway -- correctly, because the suite
	# owns more than one patrol car and `nearest_vehicle` found the other one. That is
	# the game working; the check had quietly assumed a one-car world.
	_check(not _car.has_cell_space(), "and is full")
	var spare: Array[Vehicle] = []
	for node in get_nodes_in_group(Unit.GROUP):
		var other := node as Vehicle
		if other and other != _car and not (other is TrafficCar) \
				and other.service == Unit.Service.POLICE and other.cells > 0:
			spare.append(other)
			other.cells = 0
	var third := _spawn_suspect(spot + Vector3(4.0, 0.0, 0.0))
	third.detain(1.0)
	await _idle(6)
	var declined := _officer.resolve(_target_for(third))
	_check(declined != null and declined.id() == &"move",
		"with every cell full a third is declined (got '%s', %d spare cars emptied)"
		% [("none" if declined == null else declined.id()), spare.size()])
	for other in spare:
		other.cells = 2

	_officer.clear_orders()
	await _clear_incidents()
	_car.suspects.clear()
	await _idle(4)



## Your own people can be hurt, and losing one costs the career a unit.
func _test_a_crew_member_can_be_lost() -> void:
	await _clear_incidents()
	# **Two, so the count has somewhere to fall.** `available()` reads the live roster; if
	# the career owned exactly one firefighter and it went down, the count would be 0
	# before and 0 after and the check would pass without the feature existing.
	_buy(&"firefighter", 2)
	var crew := _station.dispatch(&"firefighter") as Person
	if crew == null:
		_check(false, "a firefighter to put in harm's way")
		return
	var spot := _director._pick_pavement(true)
	if spot == Vector3.INF:
		_check(false, "a kerb to stage this on")
		return
	await _place_unit(crew, spot)
	await _idle(4)
	var owned_before := _station.total(&"firefighter")
	var spare_before := _station.available(&"firefighter")

	# A blast they are standing in.
	var hazard := _spawn_hazard(spot + Vector3(1.5, 0.0, 0.0))
	hazard.heat = 1.0
	await _idle(12)
	_check(crew.health < 1.0, "a blast hurts the crew standing in it (%.2f)" % crew.health)
	_check(crew.is_down and not crew.is_selectable(),
		"enough of it puts them down and out of the selection")
	var fallen: Casualty = null
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var casualty := node as Casualty
		if casualty and casualty.crew == crew:
			fallen = casualty
	_check(fallen != null, "and files a casualty where they fell")
	if fallen == null:
		return
	# In their own kit -- the `Civilians/` vs `Characters/` path trap, which has bitten
	# twice and is silent both times.
	var body := _first_mesh_scene(fallen)
	_check(body == crew.outfit_scene(),
		"wearing their own kit, not a stranger's (%s)" % body.get_file())
	# The unit is still on the books while they lie there, so the player cannot simply
	# dispatch a replacement -- `Station._alive()` counts group membership, and that is
	# the reason the person is not freed.
	_check(_station.available(&"firefighter") == spare_before,
		"they still count against the roster while down (%d, was %d)"
		% [_station.available(&"firefighter"), spare_before])

	# Losing them takes the unit off the books. Read everything *before* the free.
	var outcome: Array = []
	fallen.resolved.connect(func(_incident: Incident, ok: bool) -> void:
		outcome.append(ok))
	fallen.health = 0.0
	await _idle(10)
	_check(outcome == [false], "letting them die closes it as a loss (%s)" % [outcome])
	_check(_station.total(&"firefighter") == owned_before - 1,
		"and writes the unit off the books (%d, was %d)"
		% [_station.total(&"firefighter"), owned_before])
	_check(_mission.crew_lost >= 1, "the debrief counts it (%d)" % _mission.crew_lost)

	await _clear_incidents()
	await _idle(4)


## A crew member riding in a vehicle is not standing in the street.
func _test_a_passenger_is_not_caught_by_a_blast() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew to ride in it")
		return
	var spot := Vector3(-60.0, 0.0, 60.0)
	await _place_unit(engine, spot)
	crew.board(engine)
	await _idle(6)
	# An aboard person rides at the carrier's position, so without the guard a blast
	# beside the appliance would take out the crew sitting safely inside it.
	var hazard := _spawn_hazard(spot + Vector3(1.0, 0.0, 0.0))
	hazard.heat = 1.0
	await _idle(12)
	_check(is_equal_approx(crew.health, 1.0) and not crew.is_down,
		"riding in the appliance keeps them out of it (%.2f)" % crew.health)
	crew.disembark(spot + Vector3(4.0, 0.0, 0.0))
	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


## The scene file of the first mesh under an incident -- what it is actually wearing.
func _first_mesh_scene(node: Node) -> String:
	var body := node.get_node_or_null("Character") as Node3D
	return body.scene_file_path if body else ""


## A firefighter with a hose beats it; one without cannot.
func _test_a_hose_beats_a_cylinder() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew to send")
		return
	# **Well away from (20, -20).** That is where the fire-service tests stage their own
	# engine and crew, and an appliance left within `ExtinguishOrder.HOSE_REACH` of it
	# becomes a supply for somebody else's check -- which made a building fire yield to a
	# patrol car three tests later.
	var spot := Vector3(-60.0, 0.0, 60.0)
	var hazard := _spawn_hazard(spot)
	# **A fire burns beside it for both halves of this test.** Without one the first half
	# was vacuous: the assertion is only "cooler than it was", and the hazard's own
	# ambient shed satisfies that on its own -- the sabotage agent stubbed `cool()` out
	# entirely and the check stayed green, because two different things could satisfy it
	# and nothing distinguished them. Against a fire the cylinder is gaining heat every
	# frame, so it can only get cooler if water is landing on it.
	var cooker := _spawn_fire(spot + Vector3(3.0, 0.0, 0.0), 1.0)
	cooker.growth_per_second = 0.0
	cooker.spread_threshold = 2.0
	hazard.heat = 0.6
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.5, 0.0, 0.0))
	await _idle(10)

	_check(_find_ability(crew, &"cool") != null,
		"a firefighter is offered Cool")
	crew.issue(CoolOrder.new(hazard))
	var before := hazard.heat
	await _idle(120)
	_check(hazard.heat < before,
		"and on the hose the cylinder cools (%.2f from %.2f)" % [hazard.heat, before])

	# Away from the appliance there is no hose, and an extinguisher against a pressure
	# vessel is not a slower answer -- it is not an answer. Same fire, still cooking it.
	crew.clear_orders()
	await _place_unit(engine, spot + Vector3(60.0, 0.2, 0.0))
	hazard.heat = 0.4
	await _idle(10)
	var stranded := hazard.heat
	crew.issue(CoolOrder.new(hazard))
	await _idle(120)
	_check(hazard.heat > stranded,
		"but off it the cylinder keeps heating anyway (%.2f from %.2f)"
		% [hazard.heat, stranded])

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


func _test_fires_have_character() -> void:
	await _clear_incidents()
	var bin := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.5)
	bin.kind = Fire.Kind.BIN
	var building := _spawn_fire(Vector3(-20.0, 0.0, 20.0), 0.5)
	building.kind = Fire.Kind.BUILDING
	await _idle(4)

	_check(not bin.needs_hose and building.needs_hose,
		"a bin fire yields to anyone and a building fire does not")
	_check(bin.douse_per_second > building.douse_per_second,
		"a bin goes out faster than a building (%.2f against %.2f)"
		% [bin.douse_per_second, building.douse_per_second])
	# The threshold is put out of reach rather than a second flag being added, so this
	# reads the consequence: a bin fire can never arm its spread timer.
	_check(bin.spread_threshold > 1.0 and building.spread_threshold <= 1.0,
		"and a bin never spreads while a building does (%.1f against %.1f)"
		% [bin.spread_threshold, building.spread_threshold])
	# Different plumes, not one rescaled: the pack ships three and the small one has no
	# ground-spread emitter at all.
	var bin_fx := bin.get_node("Flames").scene_file_path
	var building_fx := building.get_node("Flames").scene_file_path
	_check(bin_fx != building_fx and "Small" in bin_fx and "Large" in building_fx,
		"each wearing its own plume (%s, %s)"
		% [bin_fx.get_file(), building_fx.get_file()])
	await _clear_incidents()


## A burning car bills what is parked beside it.
##
## The economy for this already existed -- `repair_bill`, the debrief row, the station's
## books -- and all that was missing was something other than a collision to charge for.
## What it buys is that where the appliance stops is a decision: nose-in beside a burning
## car is the convenient place to park and the expensive one.
func _test_a_car_fire_scorches_what_is_near_it() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	if engine == null:
		_check(false, "an engine to park beside it")
		return
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(2.0, 0.2, 0.0))
	engine.repair_bill = 0
	var fire := _spawn_fire(spot, 1.0)
	fire.kind = Fire.Kind.VEHICLE
	fire.growth_per_second = 0.0
	await _idle(180)
	var close := engine.repair_bill
	_check(close > 0, "parking in a car fire costs money (£%d after 3s)" % close)

	# Out of reach, and the same three seconds. Distance is the whole mechanic: a bill
	# that applied across the district would just be a tax on attending at all.
	await _place_unit(engine, spot + Vector3(14.0, 0.2, 0.0))
	engine.repair_bill = 0
	await _idle(180)
	_check(engine.repair_bill == 0,
		"and standing off it costs nothing (£%d)" % engine.repair_bill)

	await _clear_incidents()
	_dissolve(engine, &"engine")
	await _idle(4)


func _test_a_fire_looks_like_its_intensity() -> void:
	await _clear_incidents()
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 1.0)
	fire.growth_per_second = 0.0
	await _idle(4)

	# **Counted off the scene, not off `_particles`.** Reading the list the code under
	# test iterates makes "all N of N" true by construction: the sabotage pass deleted
	# the sub-emitter collection entirely and this check still passed, reading 2 of 2.
	# Walking the tree is what lets it see an emitter that `_update_flame` never reached.
	var emitters: Array[Node] = fire.find_children("*", "GPUParticles3D", true, false)
	_check(emitters.size() >= 3,
		"a fire runs the pack's emitters, sub-emitters and all (%d)" % emitters.size())
	var lit := 0
	for e in emitters:
		if (e as GPUParticles3D).emitting:
			lit += 1
	_check(lit == emitters.size(), "all of them alight (%d of %d)" % [lit, emitters.size()])

	# Read off the plume itself. There was an orange cone under these particles to be the
	# readable silhouette at RTS zoom, and this measured that; the pack's fire made it
	# redundant and it was removed, so the size of the fire is now the size of the fire.
	var big: float = (fire.get_node("Flames") as Node3D).scale.x
	fire.intensity = 0.15
	fire.call("_update_flame")
	await _idle(2)
	var small: float = (fire.get_node("Flames") as Node3D).scale.x
	_check(small < big, "a dying fire is a smaller one (%.2f against %.2f)" % [small, big])
	# Scale lives on the roots alone, because a child inherits it: setting it on both
	# squares it, and a fire at full intensity threw embers at 5.8x rather than 2.4x.
	var embers := fire.get_node_or_null("Flames/FX_Fire_Embers_01") as Node3D
	_check(embers == null or is_equal_approx(embers.scale.x, 1.0),
		"and its sub-emitters ride the root's scale rather than squaring it (%.2f)"
		% (embers.scale.x if embers else 1.0))
	var thinned := 0
	for e in emitters:
		if (e as GPUParticles3D).amount_ratio < 0.9:
			thinned += 1
	_check(thinned == emitters.size(),
		"and every emitter thins with it, not just the parent (%d of %d)"
		% [thinned, emitters.size()])

	await _clear_incidents()


func _test_the_appliance_raises_its_ladder() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a firefighter to send")
		return
	await _idle(4)

	var ladder := engine.get_node_or_null(engine.ladder_path) as Node3D
	_check(ladder != null, "the appliance carries a ladder it can raise")
	if ladder == null:
		_dissolve(engine, &"engine")
		_dissolve(crew, &"firefighter")
		return

	# Measured as the height of the ladder's far end in the vehicle's own frame, so this
	# says nothing about which axis the prefab happened to author it on.
	var tip := func() -> float:
		var box: AABB = (ladder as MeshInstance3D).get_aabb()
		var far := box.position + Vector3(box.size.x * 0.5, box.size.y * 0.5, box.size.z)
		return engine.to_local(ladder.to_global(far)).y

	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	await _idle(10)
	var stowed: float = tip.call()
	_check(engine.get("_ladder_raise") == 0.0,
		"which is stowed on an appliance doing nothing")

	var fire := _spawn_fire(spot, 0.9)
	fire.growth_per_second = 0.0
	crew.issue(ExtinguishOrder.new(fire))
	await _idle(150)
	var raised: float = tip.call()
	_check(raised > stowed + 1.0,
		"and goes up while the crew work off its tank (%.1fm to %.1fm)" % [stowed, raised])

	crew.clear_orders()
	await _idle(240)
	_check(tip.call() < stowed + 0.2,
		"and comes back down when they stop (%.1fm)" % tip.call())

	await _clear_incidents()
	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _idle(4)


func _test_the_fire_service_fights_fires() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a firefighter to send")
		return
	await _idle(4)

	_check(engine.service == Unit.Service.FIRE
			and crew.service == Unit.Service.FIRE,
		"both belong to the fire service")
	_check(engine.seats >= 4, "the appliance carries a crew (%d seats)" % engine.seats)
	_check(_find_ability(crew, &"extinguish") != null,
		"a firefighter is offered Extinguish")
	_check(_find_ability(crew, &"treat") == null
			and _find_ability(crew, &"apprehend") == null
			and _find_ability(crew, &"secure") == null,
		"and nothing else -- no treating, no arrests, no cordons")

	# On the hose: the engine parked at the scene. Rate is measured rather than
	# asserted from the constants, because the constants are not what the player sees.
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	# **Staged as a water fire on purpose.** This measures the water economy -- the hose
	# rate, the tank price, a dry engine -- and the default kind is VEHICLE, which since
	# August 2026 burns fuel and draws the foam tank instead. A check that leaned on the
	# default was measuring whichever agent the table happened to name.
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	var order := ExtinguishOrder.new(fire)
	crew.issue(order)
	var before := fire.intensity
	await _wait(60)
	var on_hose := before - fire.intensity
	_check(on_hose > 0.0, "on the hose, the fire goes down (%.3f/s)" % on_hose)
	# And goes down *faster than the fire's own baseline rate*, which is the whole
	# point of the appliance being there. The hose ran at exactly 1.0 of that baseline
	# until August 2026, which put a building fire at eleven seconds a node -- and
	# buildings spread, so a real building call was a minute of holding a hose still.
	# Measured against douse_per_second rather than against a fixed number, so it keeps
	# meaning the same thing if a fire's own rate is ever retuned.
	_check(on_hose > fire.douse_per_second * 1.2,
		"and faster than the fire's own rate -- the hose is a multiplier, not the "
		+ "ceiling (%.3f/s vs %.3f/s)" % [on_hose, fire.douse_per_second])
	crew.clear_orders()

	# Off the hose: the same firefighter, the same fire, the engine driven away.
	fire.intensity = 0.9
	await _place_unit(engine, Vector3(20.0, 0.2, 60.0))
	await _idle(4)
	crew.issue(ExtinguishOrder.new(fire))
	before = fire.intensity
	await _wait(60)
	var off_hose := before - fire.intensity
	crew.clear_orders()
	_check(off_hose > 0.0 and off_hose < on_hose * 0.6,
		"away from the appliance they have only what they carry (%.3f vs %.3f)"
		% [off_hose, on_hose])

	# A building yields to the hose and to nothing else.
	fire.queue_free()
	await _idle(4)
	var building := _spawn_fire(spot, 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	await _place_unit(_officer, spot + Vector3(2.0, 0.0, 0.0))
	_officer.issue(ExtinguishOrder.new(building))
	before = building.intensity
	await _wait(90)
	_check(is_equal_approx(building.intensity, before),
		"a building fire does not yield to a patrol car's extinguisher (%.3f -> %.3f)"
		% [before, building.intensity])
	_officer.clear_orders()

	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	crew.issue(ExtinguishOrder.new(building))
	var out := false
	for i in 900:
		await physics_frame
		# **A freed incident is the success, not an error.** An extinguished fire frees
		# itself, so reading `active` on it throws -- and a runtime error inside a check
		# silently abandons the rest of that check, which is why the assertion below and
		# the cleanup after it had not run in a long time while the suite read green.
		if not is_instance_valid(building) or not building.active:
			out = true
			break
	_check(out, "and a crew on the hose puts it out")

	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _clear_incidents()


## The people in an incident come out of the crowd's wardrobe, not the Starter
## pack's grey mannequin -- which is what a suspect and a casualty shipped wearing,
## and which reads as a placeholder standing in a city full of dressed pedestrians.
func _test_incident_figures_are_dressed() -> void:
	await _clear_incidents()
	var suspect := _director._spawn_suspect(Vector3(20.0, 0.0, -20.0))
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -26.0))
	await _idle(6)

	for figure: Node in [suspect, casualty]:
		var body := figure.get_node_or_null("Character") as Node3D
		_check(body != null and body.scene_file_path in Incident.OUTFITS,
			"%s wears one of the crowd's outfits ('%s')"
			% [figure.name, "none" if body == null else body.scene_file_path])
		_check(body != null and body.get_node_or_null("AnimationPlayer") != null,
			"and keeps an animation player after the swap")
	# The swap must not undo the 180 yaw that stops them moonwalking.
	var worn := suspect.get_node("Character") as Node3D
	_check(worn.transform.basis.z.z < -0.9,
		"with the visual still yawed to face travel (%.2f)" % worn.transform.basis.z.z)

	# A collapse takes a specific shopper, so the body wears what they were wearing.
	await _clear_incidents()
	var crowd := _civilians()
	if crowd.is_empty():
		# Silently skipping this is how a check quietly stops meaning anything: it
		# runs in the crowd section for exactly this reason.
		_check(false, "a crowd to take a collapse from")
	else:
		_director._rng.seed = 5
		var before := {}
		for civilian in crowd:
			var dress := civilian.get_node_or_null("Character")
			if dress:
				before[civilian.get_instance_id()] = dress.scene_file_path
		_director._spawn_medical()
		await _idle(6)

		# *Which* shopper went, not merely "some outfit the crowd owns": with seven
		# outfits across sixty people, every one of them is in the crowd somewhere,
		# so matching the set proves nothing. The one that vanished is the test.
		var still_here := {}
		for civilian in _civilians():
			still_here[civilian.get_instance_id()] = true
		var lost := ""
		for id in before:
			if not still_here.has(id):
				lost = str(before[id])
		var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
		if bodies.size() == 1 and lost != "":
			var taken: String = (bodies[0] as Node3D).get_node("Character").scene_file_path
			_check(taken == lost,
				"the collapsed shopper keeps their own clothes (wore '%s', body wears '%s')"
				% [lost.get_file(), taken.get_file()])
		else:
			_check(false, "exactly one shopper became exactly one casualty")
	await _clear_incidents()


## How often the district calls is a setting, because the first thing said after a
## full shift was that they came too fast.
func _test_the_call_rate_is_a_setting() -> void:
	var kept := _menu.call_pace
	var kept_pace := _director.pace

	_menu.set_call_pace(2)
	_check(is_equal_approx(_director.pace, 1.0),
		"BUSY is the pace the game shipped with (%.2f)" % _director.pace)
	_menu.set_call_pace(0)
	_check(_director.pace > 1.9,
		"QUIET stretches the gaps between calls (%.2f)" % _director.pace)

	# And it reaches the roll itself, not just the readout.
	_director.shift_length = 9999.0
	_director.call_interval_min = 2.0
	_director.call_interval_max = 2.0
	_director.clock = 0.0
	_check(_director.interval_scale() > 0.99,
		"with the shift's own escalation still at its start (%.2f)"
		% _director.interval_scale())

	_menu.call_pace = kept
	_menu._save_settings()
	_menu.call_pace = 9
	_menu._load_settings()
	_check(_menu.call_pace == kept,
		"the choice survives a reload (%d)" % _menu.call_pace)
	_director.pace = kept_pace


## What hour the district works at, and everything that has to follow from it.
##
## The lighting is the one system in the project with no behaviour to observe -- it is
## only ever seen -- so these checks watch the *consequences* instead: which lights are
## on, whether the fleet has beams, and whether coming back to day restores what the
## generator wrote. That last one is the important one. Day is not a preset; it is the
## captured baseline, and if a round trip through night does not return it exactly then
## every check written against the shipped map is quietly measuring something else.
func _test_the_hour_is_a_setting() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	_check(daylight != null, "the district knows what hour it is working at")
	if daylight == null:
		return
	var kept := daylight.time_of_day
	var street := _scene.get_node_or_null("StreetLights") as Node3D

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var noon_rotation := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	var noon_fog := (_scene.get_node("WorldEnvironment") as WorldEnvironment) \
		.environment.fog_density
	_check(not daylight.is_dark(), "day is not dark")
	_check(street != null and not street.visible, "and the street lights are out")

	daylight.set_time_of_day(Daylight.Mode.NIGHT)
	var night_rotation := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	_check(daylight.is_dark(), "night is dark")
	_check(street != null and street.visible, "and the district turns its lights on")
	_check(not noon_rotation.is_equal_approx(night_rotation),
		"the sun has moved (%.0f deg elevation to %.0f)"
		% [rad_to_deg(noon_rotation.x), rad_to_deg(night_rotation.x)])

	# Dusk is lit too: LIT_BELOW is one threshold, so nothing can disagree about it.
	daylight.set_time_of_day(Daylight.Mode.DUSK)
	_check(daylight.is_dark() and street.visible,
		"dusk is lit as well -- one threshold decides, not a flag per system")

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var back := (_scene.get_node("KeyLight") as DirectionalLight3D).rotation
	var back_fog := (_scene.get_node("WorldEnvironment") as WorldEnvironment) \
		.environment.fog_density
	_check(back.is_equal_approx(noon_rotation) and is_equal_approx(back_fog, noon_fog),
		"and coming back to day restores the map as generated, exactly")

	# The setting itself, the same round trip the call rate takes.
	var kept_choice := _menu.time_of_day
	_menu.set_time_of_day(Daylight.Mode.NIGHT)
	_check(daylight.time_of_day == Daylight.Mode.NIGHT,
		"the settings card drives the district, not a copy of it")
	_menu._save_settings()
	_menu.time_of_day = 0
	_menu._load_settings()
	_check(_menu.time_of_day == Daylight.Mode.NIGHT,
		"and the hour survives a reload")

	_menu.time_of_day = kept_choice
	_menu._save_settings()
	daylight.set_time_of_day(kept)


## SHIFT'S OWN: the last weather button is a policy, not a sky. The director draws from
## its seeded stream when the shift opens, so every shift has its own weather and a
## reproduced seed is rained on identically. Two properties, each its own witness: a
## fixed choice never rolls, and the roll both happens and reproduces.
func _test_the_shift_rolls_its_own_weather() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district has a sky to roll")
		return
	await _clear_calls()
	await _park_the_shift()

	# Policy off: a fixed CLEAR choice stays CLEAR through a shift opening.
	_menu.set_weather(Daylight.Weather.CLEAR)
	_director.shift_seed = 23
	_director.begin_shift()
	await _idle(2)
	_check(daylight.weather == Daylight.Weather.CLEAR,
		"a fixed weather choice never rolls (%d)" % daylight.weather)
	await _end_freeplay()

	# Policy on. **Hunted, not assumed**: half the table is CLEAR, and a broken roll
	# that never fires also leaves CLEAR -- so the check walks seeds until it sees a
	# weather actually land, which is what proves the wiring, then re-runs that seed
	# for the reproduction.
	_menu.set_weather(GameMenu.SHIFT_WEATHER)
	var rolled_seed := 0
	var rolled: int = Daylight.Weather.CLEAR
	for seed_try in range(1, 21):
		_director.shift_seed = seed_try
		_director.begin_shift()
		await _idle(2)
		var drawn := daylight.weather
		await _end_freeplay()
		if drawn != Daylight.Weather.CLEAR:
			rolled_seed = seed_try
			rolled = drawn
			break
	_check(rolled_seed != 0,
		"the shift's own policy actually rolls weather (seed %d drew %d)"
		% [rolled_seed, rolled])
	if rolled_seed != 0:
		daylight.set_weather(Daylight.Weather.CLEAR)
		_director.shift_seed = rolled_seed
		_director.begin_shift()
		await _idle(2)
		_check(daylight.weather == rolled,
			"and the same seed draws the same sky (%d)" % daylight.weather)
		await _end_freeplay()

	_menu.set_weather(Daylight.Weather.CLEAR)
	_director.shift_seed = 0


## Wet weather is a dispatch fact, not a screen effect: the collision kinds carry a
## wet_weight and the picker consults the sky. Asserted at the weight level (the
## mechanism) and the distribution level (the outcome), both seeded.
func _test_wet_weather_loads_the_table_with_collisions() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district has a sky to consult")
		return
	var rtc_row: Dictionary
	for kind: Dictionary in Director.KINDS:
		if kind["id"] == &"rtc":
			rtc_row = kind
	_check(not rtc_row.is_empty()
			and _director._kind_weight(rtc_row, true)
				== 2 * _director._kind_weight(rtc_row, false),
		"a wet road doubles the collision weight (%d from %d)"
		% [_director._kind_weight(rtc_row, true), _director._kind_weight(rtc_row, false)])

	daylight.set_weather(Daylight.Weather.RAIN)
	_director._rng.seed = 77
	var wet_hits := 0
	for i in 400:
		var kind := _director._pick_kind()
		if kind == &"rtc" or kind == &"bus_rtc":
			wet_hits += 1
	daylight.set_weather(Daylight.Weather.CLEAR)
	_director._rng.seed = 77
	var dry_hits := 0
	for i in 400:
		var kind := _director._pick_kind()
		if kind == &"rtc" or kind == &"bus_rtc":
			dry_hits += 1
	_check(wet_hits > dry_hits,
		"and a wet shift draws more collisions (%d wet vs %d dry in 400)"
		% [wet_hits, dry_hits])


## Headlamps, and the reason [Daylight] is a passive watcher rather than something the
## station has to remember to call: a vehicle bought at midnight needs lights, and the
## station knows nothing about the hour.
func _test_vehicles_light_up_after_dark() -> void:
	var daylight := _scene.get_node_or_null("Daylight") as Daylight
	if daylight == null:
		_check(false, "the district knows what hour it is working at")
		return
	var kept := daylight.time_of_day

	daylight.set_time_of_day(Daylight.Mode.DAY)
	var beams := _car.get_node_or_null("Headlights") as Node3D
	_check(beams != null, "a vehicle carries headlamps")
	if beams == null:
		daylight.set_time_of_day(kept)
		return
	_check(beams.get_child_count() == 2,
		"two of them (%d)" % beams.get_child_count())
	# Measured off the vehicle's own collider, so they sit at the nose rather than at
	# whatever a hard-coded offset assumed. -Z is forward.
	var lamp := beams.get_child(0) as SpotLight3D
	_check(lamp != null and lamp.position.z < 0.0,
		"on the nose, not the boot (z %.2f)" % (lamp.position.z if lamp else 0.0))
	_check(not beams.visible, "and off in daylight")

	daylight.set_time_of_day(Daylight.Mode.NIGHT)
	_check(beams.visible, "and lit after dark")

	# The watcher: something that arrives *while* it is dark is fitted too. The
	# fixtures already have every owned patrol standing on the map, so this buys one
	# more and puts the career back afterwards -- the career checks at the end of the
	# suite are counting.
	var kept_funds := _station.funds
	var kept_owned: Dictionary = _station.owned.duplicate()
	_station.funds += _station.price(&"patrol")
	_station.purchase(&"patrol")
	var bought := _station.dispatch(&"patrol")
	if bought == null:
		_check(false, "a patrol car could be bought to test the night fitting")
	else:
		await _idle(4)
		var late := bought.get_node_or_null("Headlights") as Node3D
		_check(late != null and late.visible,
			"a vehicle bought at midnight turns up with its lights on")
		bought.queue_free()
		await _idle(2)
	_station.funds = kept_funds
	_station.owned = kept_owned

	daylight.set_time_of_day(kept)


## The interface's own click, driven through a real press.
##
## Asserted on the player **actually running** after a synthesised click on a real
## control, not on the signal being connected: a connection proves the watcher found the
## button, and proves nothing about whether a sound comes out of it. The two failure modes
## that matter here are both silent -- an OGG that did not import, and a click wired to a
## player whose stream is null -- and neither shows up anywhere but the speakers.
##
## The rollover is checked the same way, and separately, because it is the one that gets
## broken by accident: it is rate-limited, so a bug in the gate silences it while the
## click keeps working.
func _test_the_interface_clicks() -> void:
	var clicks := _scene.get_node_or_null("HUD/ClickSounds") as ClickSounds
	if clicks == null:
		_check(false, "the HUD ships a click watcher")
		return
	_check(clicks._click != null and clicks._click.stream != null,
		"the click sound is loaded")
	_check(clicks._rollover != null and clicks._rollover.stream != null,
		"and so is the rollover")
	if clicks._click == null or clicks._rollover == null:
		return
	_check(clicks._click.bus == AudioBuses.UI,
		"on the UI bus (%s)" % clicks._click.bus)

	# A real control, clicked where it is: the corner buy button, which the watcher had
	# to have found on its own -- nothing in `HUD.gd` tells it that button exists.
	var buy := _scene.get_node_or_null("HUD/Root/World/BuyButton") as Button
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as ShopPanel
	if buy == null:
		_check(false, "a button to press")
		return
	clicks._click.stop()
	await _idle(2)
	await _click(MOUSE_BUTTON_LEFT, buy.get_global_rect().get_center())
	_check(clicks._click.playing, "pressing a button makes a click")
	if shop:
		shop.close_shop()
		await _idle(2)

	# The rollover, off its own gate rather than a click.
	clicks._rollover.stop()
	clicks._last_rollover = -999.0
	await _idle(2)
	buy.mouse_entered.emit()
	await _idle(2)
	_check(clicks._rollover.playing, "and the pointer crossing one makes a tick")

	# The gate: a second crossing inside the window must not stack a second tick.
	clicks._rollover.stop()
	await _idle(1)
	buy.mouse_entered.emit()
	_check(not clicks._rollover.playing,
		"a second crossing straight after is swallowed rather than rattling")


## Every sound is wired and loaded. Audio fails *silently* -- a missing file, an
## unimported one, a player nobody called play() on all look identical from the
## code, and none of them makes a noise. So this asserts the streams exist, are
## attached, and are running.
func _test_the_district_makes_a_noise() -> void:
	var soundscape := _scene.get_node_or_null("HUD/Soundscape") as Soundscape
	if soundscape == null:
		_check(false, "the HUD ships a soundscape")
		return
	_check(soundscape._ambience != null and soundscape._ambience.playing,
		"the city bed is playing under everything")
	_check(soundscape._radio != null and soundscape._radio.stream != null,
		"and the dispatch radio is loaded")

	# **The music bed.** Same reasoning as everything else in this check, and then some:
	# `Soundscape._player` casts what it loads to `AudioStreamWAV`, so a music file in any
	# other format comes back null and the bed is simply absent -- no error, no warning,
	# and nothing on screen to notice. It also has to be on its own bus, or the settings
	# card's music slider moves the sirens with it.
	_check(soundscape._music != null and soundscape._music.stream != null
			and soundscape.music_playing(),
		"the ambient bed is playing")
	_check(soundscape._music != null and soundscape._music.bus == AudioBuses.MUSIC,
		"on the music bus, so it can be balanced against the game (%s)"
		% (soundscape._music.bus if soundscape._music else "no player"))
	var music_bus := AudioServer.get_bus_index(AudioBuses.MUSIC)
	_check(music_bus > 0, "and that bus exists (%d)" % music_bus)

	# **The shipped default is a bed, and applying it works.** Reported as too loud on
	# first listen, and the cause was half arithmetic: the settings slider steps in 0.05,
	# so a default of -18 dB (0.126 linear) rounded *up* to 0.15 and played louder than
	# the constant said.
	#
	# Asserted by *applying* the default and reading the bus back, rather than by
	# measuring the bus as it stands. The live bus reflects whatever the player last chose
	# and a player is entitled to turn the music up -- the first cut of this check read it
	# directly and failed on a stale 0.15 left in the settings file, which is a fact about
	# a save rather than about the game. This form tests the plumbing and the default at
	# once and depends on neither.
	if music_bus > 0:
		var kept_db := AudioServer.get_bus_volume_db(music_bus)
		AudioBuses.set_music_volume(db_to_linear(AudioBuses.MUSIC_DEFAULT_DB))
		var gap: float = AudioServer.get_bus_volume_db(0) \
			- AudioServer.get_bus_volume_db(music_bus)
		_check(gap >= 24.0,
			"the default level sits %.1fdB under master, so it stays a bed" % gap)
		AudioServer.set_bus_volume_db(music_bus, kept_db)

	# The radio answers the board rather than being told: opening a call chirps.
	await _clear_calls()
	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -20.0))
	await _idle(6)
	_check(soundscape._radio.playing, "a new call puts a tone over the radio")
	casualty.queue_free()
	await _clear_calls()

	# The engine note: every emergency vehicle runs one, pitched by speed.
	var note := _car.get_node_or_null("EngineAudio") as AudioStreamPlayer3D
	_check(note != null and note.stream != null and note.playing,
		"a vehicle runs an engine note")
	if note:
		await _place(ROAD)
		await _idle(4)
		var idle_pitch := note.pitch_scale
		_car.issue(MoveOrder.new(ROAD + Vector3(0.0, 0.0, -40.0)))
		await _wait(45)
		_check(note.pitch_scale > idle_pitch + 0.1,
			"which rises with the revs (%.2f -> %.2f)" % [idle_pitch, note.pitch_scale])
		_car.clear_orders()

	# And fires burn audibly, louder for being bigger.
	var fire := _spawn_fire(Vector3(20.0, 0.0, -20.0), 0.9)
	await _idle(6)
	var crackle := fire.get_node_or_null("Crackle") as AudioStreamPlayer3D
	_check(crackle != null and crackle.playing, "a fire crackles")
	if crackle:
		var loud := crackle.volume_db
		fire.douse(0.6)
		await _idle(4)
		_check(crackle.volume_db < loud - 5.0,
			"and quietens as it is knocked down (%.0f -> %.0f dB)"
			% [loud, crackle.volume_db])
	await _clear_incidents()


## The appliance carries water, and running dry is a real failure rather than a
## slower one: a building grows faster than a crew with only what they carry.
func _test_the_appliance_runs_on_water() -> void:
	await _clear_incidents()
	_buy(&"engine", 1)
	_buy(&"firefighter", 1)
	var engine := _station.dispatch(&"engine") as Vehicle
	var crew := _station.dispatch(&"firefighter") as Person
	if engine == null or crew == null:
		_check(false, "an engine and a crew for the water test")
		return
	_check(engine.carries_water, "the appliance carries a tank")
	_check(not _car.carries_water and not _ambulance.carries_water,
		"and nothing else does")

	# A scene with no hydrant within reach of where the engine parks -- found rather
	# than assumed. There are 41 of them on the kerbs, and the first spot picked for
	# this test happened to be beside one: the tank refilled as fast as the hose drew
	# it down and the drain looked broken.
	var spot := Vector3.INF
	for candidate in CityGrid.pavement_points():
		if Hydrant.nearest(_scene, candidate + Vector3(6.0, 0.0, 0.0),
				engine.hydrant_reach + 4.0) == null:
			spot = candidate
			break
	if spot == Vector3.INF:
		_check(false, "a scene out of reach of every hydrant")
		return

	# Hosing draws the tank down.
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _place_unit(crew, spot + Vector3(2.0, 0.0, 0.0))
	# **Staged as a water fire on purpose.** This measures the water economy -- the hose
	# rate, the tank price, a dry engine -- and the default kind is VEHICLE, which since
	# August 2026 burns fuel and draws the foam tank instead. A check that leaned on the
	# default was measuring whichever agent the table happened to name.
	var fire := _spawn_fire(spot, 0.9)
	fire.kind = Fire.Kind.BIN
	fire.growth_per_second = 0.0
	engine.water = 1.0
	crew.issue(ExtinguishOrder.new(fire))
	await _wait(60)
	# One second of hosing, against what the model says it should cost. Pinning the
	# arithmetic rather than a magic threshold, because all three terms have now moved
	# under this check: the hose rate, the per-douse price, and the tank's capacity.
	# The old form asserted `water < 0.99` and went red the moment the tank grew 20x --
	# correctly complaining, but about the threshold rather than about the model.
	var drained := 1.0 - engine.water
	var expected := ExtinguishOrder.water_cost(
		fire.douse_per_second * ExtinguishOrder.HOSE_RATE) / engine.tank_capacity
	_check(drained > 0.0, "working the hose empties it (%.4f of a tank a second)"
		% drained)
	_check(absf(drained - expected) < expected * 0.3,
		"at the rate the tank's own capacity says it should (%.4f, expected %.4f)"
		% [drained, expected])
	crew.clear_orders()

	# Dry: a building stops going down at all.
	fire.queue_free()
	await _idle(4)
	var building := _spawn_fire(spot, 0.8)
	building.kind = Fire.Kind.BUILDING
	building.growth_per_second = 0.0
	engine.water = 0.0
	crew.issue(ExtinguishOrder.new(building))
	var before := building.intensity
	await _wait(90)
	_check(is_equal_approx(building.intensity, before),
		"a dry appliance is no supply at all (%.2f -> %.2f)"
		% [before, building.intensity])
	crew.clear_orders()

	# A hydrant refills it -- parked, because an engine that filled up while driving
	# past would make the tank a formality.
	var hydrant := get_nodes_in_group(Hydrant.GROUP)
	_check(hydrant.size() > 10,
		"the district has hydrants to refill at (%d)" % hydrant.size())
	if hydrant.is_empty():
		return
	var tap := hydrant[0] as Node3D
	await _place_unit(engine, tap.global_position + Vector3(3.0, 0.2, 0.0))
	await _wait(60)
	_check(engine.water > 0.0 and engine.is_refilling,
		"parked beside one, it fills (%.2f)" % engine.water)

	# And away from any supply it does not. Incidents cleared first: a crew that can see a
	# fire will hose it off this engine's tank, and the water going down is then the crew
	# working rather than a hydrant that will not stop giving.
	await _clear_incidents()
	engine.water = 0.2
	await _place_unit(engine, spot + Vector3(6.0, 0.2, 0.0))
	await _wait(60)
	_check(is_equal_approx(engine.water, 0.2) and not engine.is_refilling,
		"away from one it does not (%.2f)" % engine.water)

	_dissolve(engine, &"engine")
	_dissolve(crew, &"firefighter")
	await _clear_incidents()


## The set piece: one scene that no single service can finish.
func _test_a_rescue_needs_every_service() -> void:
	await _clear_calls()
	_director._rng.seed = 12
	_director._spawn_rescue()
	await _idle(8)

	var open := _board.open_calls()
	_check(open.size() == 1,
		"a building fire with casualties is one call, not three (%d)" % open.size())
	if open.is_empty():
		return
	var call := open[0]
	_check(call.kind == Call.Kind.RESCUE,
		"the board reads it as a rescue (%d)" % call.kind)
	_check("casualties" in call.title(),
		"and says so ('%s')" % call.title())
	_check(get_nodes_in_group(Casualty.CASUALTY_GROUP).size() == 2,
		"two casualties are out in front of it (%d)"
		% get_nodes_in_group(Casualty.CASUALTY_GROUP).size())
	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(fires.size() == 1 and (fires[0] as Fire).needs_hose,
		"with a fire only a hose will touch")

	# The casualties are clear of the flames but inside the board's grouping radius:
	# one job, and a paramedic who is not standing in it.
	var fire := fires[0] as Fire
	var reachable := true
	for node in get_nodes_in_group(Casualty.CASUALTY_GROUP):
		var away := _flat_distance((node as Node3D).global_position,
			fire.global_position)
		if away < 3.0 or away > Call.GROUPING_RADIUS:
			reachable = false
	_check(reachable, "placed out of the fire but inside the same call")
	await _clear_calls()


## The director has always refused to open a call the roster cannot answer -- which
## is why building fires did not exist while there was no fire service to buy. Now
## the same rule is a career gate rather than a permanent ban.
func _test_building_fires_wait_for_a_fire_service() -> void:
	await _clear_calls()
	var kept := _station.owned.duplicate()

	_station.owned = {&"patrol": 2, &"ambulance": 1}
	_check(not _director._can_fight_buildings(),
		"a career with no fire service cannot fight buildings")
	var offered := {}
	_director._rng.seed = 3
	for i in 200:
		offered[_director._pick_kind()] = true
	_check(not offered.has(&"building"),
		"so the director never draws one (%s)" % str(offered.keys()))

	_station.owned = {&"engine": 1, &"firefighter": 1}
	_check(_director._can_fight_buildings(),
		"buying an engine and a firefighter changes that")
	offered = {}
	for i in 200:
		offered[_director._pick_kind()] = true
	_check(offered.has(&"building"), "and the call kind unlocks")

	# An engine with nobody to crew it is not a fire service.
	_station.owned = {&"engine": 1}
	_check(not _director._can_fight_buildings(),
		"an appliance with no crew does not count")

	# The fire is sized to the crew that will have to fight it, rather than withheld
	# until the crew is big enough. Gating on a full crew of four was tried first and
	# worked, but it meant a one- or two-firefighter career never saw the most
	# interesting call in the game.
	var sizes := {}
	for hands in [1, 2, 3, 4]:
		_station.owned = {&"engine": 1, &"firefighter": hands}
		var sized := Fire.new()
		_director._size_to_crew(sized)
		sizes[hands] = {"nodes": sized.max_fires, "interval": sized.spread_interval}
		sized.free()
	_check(sizes[1]["nodes"] < sizes[4]["nodes"],
		"a lone firefighter is sent a smaller fire than a full crew (%d nodes vs %d)"
		% [sizes[1]["nodes"], sizes[4]["nodes"]])
	_check(sizes[1]["interval"] > sizes[4]["interval"],
		"and one that spreads more slowly (%.0fs vs %.0fs)"
		% [sizes[1]["interval"], sizes[4]["interval"]])
	var climbs := true
	for hands in [2, 3, 4]:
		if int(sizes[hands]["nodes"]) < int(sizes[hands - 1]["nodes"]):
			climbs = false
	_check(climbs, "and the job grows with every firefighter hired (%d/%d/%d/%d nodes)"
		% [sizes[1]["nodes"], sizes[2]["nodes"], sizes[3]["nodes"], sizes[4]["nodes"]])
	# Past a full appliance it stops growing: a fire that outran four would just be
	# the unwinnable scene again, wearing a bigger number.
	_station.owned = {&"engine": 1, &"firefighter": 9}
	var capped := Fire.new()
	_director._size_to_crew(capped)
	_check(capped.max_fires == int(sizes[4]["nodes"]),
		"and stops growing past a full appliance (%d)" % capped.max_fires)
	capped.free()

	_station.owned = kept
	_station._save_career()
	_director._spawn_building_fire()
	await _idle(6)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Building fire",
		"a building fire reads as one on the board ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))
	var fires := get_nodes_in_group(Fire.FIRE_GROUP)
	_check(fires.size() == 1 and (fires[0] as Fire).needs_hose,
		"and it is flagged as needing a hose")
	await _clear_calls()


## The police half of the casualty loop, end to end: a suspect on the board as a
## Disturbance, an officer's Apprehend, a patrol car's Escort, and the drive back to
## the station booking them in -- with the medical service locked out of all of it.
func _test_a_disturbance_is_arrested_and_delivered() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	var spot := Vector3(20.0, 0.0, -20.0)
	var suspect := _director._spawn_suspect(spot)
	await _idle(6)
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Disturbance"
			and open[0].kind == Call.Kind.CRIME,
		"a suspect opens a crime call ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	_check(_find_ability(_officer, &"apprehend") != null,
		"an officer is offered Apprehend")
	_check(_find_ability(_paramedic, &"apprehend") == null,
		"a paramedic is not")
	# Escort moved from the patrol car to the officer in August 2026: an arrest is made
	# on foot and the walk to the car is too, exactly as the stretcher run is the
	# paramedic's rather than the ambulance's.
	_check(_find_ability(_officer, &"escort") != null,
		"an officer is offered Escort")
	_check(_find_ability(_car, &"escort") == null,
		"and the patrol car is not -- it no longer collects anybody")
	_check(_find_ability(_paramedic, &"escort") == null,
		"nor a paramedic")
	var medic_verb := _paramedic.resolve(_target_for(suspect))
	_check(medic_verb != null and medic_verb.id() == &"move",
		"right-clicking the suspect with a paramedic means Move (got '%s')"
		% ("none" if medic_verb == null else medic_verb.id()))

	# The arrest. Sped up so the check measures the loop, not the scuffle.
	suspect.detain_per_second = 2.0
	await _place_unit(_officer, spot + Vector3(4.0, 0.0, 0.0))
	var verb := _officer.resolve(_target_for(suspect))
	_check(verb != null and verb.id() == &"apprehend",
		"and with an officer it means Apprehend (got '%s')"
		% ("none" if verb == null else verb.id()))
	if verb == null:
		await _clear_calls()
		return
	_officer.issue(verb.make_order(_officer, _target_for(suspect)))
	var detained := false
	var fought := false
	var swung := false
	var squared_up := 0
	var swings := 0
	var player := suspect.get_node("Character/AnimationPlayer") as AnimationPlayer
	var face: Node3D = suspect.get_node("Character")
	for i in 600:
		await physics_frame
		if suspect.is_fighting:
			fought = true
			if player.current_animation in ["Punch_Jab", "Punch_Cross"]:
				swung = true
				# Punching *at* the officer, not at the air beside them.
				var towards := _officer.global_position - suspect.global_position
				towards.y = 0.0
				if towards.length() > 0.05:
					swings += 1
					if face.global_basis.z.normalized().dot(towards.normalized()) > 0.8:
						squared_up += 1
		if suspect.is_detained:
			detained = true
			break
	_check(detained, "the officer takes them into custody")
	_check(fought and swung,
		"and they fought it, swinging, until the cuffs went on (fought %s, swung %s)"
		% [fought, swung])
	_check(swings > 0 and squared_up == swings,
		"squared up to the officer rather than punching the air (%d of %d swings on target)"
		% [squared_up, swings])
	await _wait(90)
	_check(not suspect.is_fighting
			and player.current_animation not in ["Punch_Jab", "Punch_Cross"],
		"the fight ends with the arrest ('%s')" % player.current_animation)
	_check(not _board.open_calls().is_empty(),
		"the call stays open until they are booked in")

	# The walk in, to a car parked a short way off. The car stays put: it is the officer
	# who covers the ground now, which is the whole point of the move.
	await _place_unit(_car, spot + Vector3(14.0, 0.0, 0.0), PI * 0.5)
	var escort := _officer.resolve(_target_for(suspect))
	_check(escort != null and escort.id() == &"escort",
		"right-clicking a detained suspect with an officer means Escort (got '%s')"
		% ("none" if escort == null else escort.id()))
	if escort != null:
		_officer.issue(escort.make_order(_officer, _target_for(suspect)))
	# **Walked, not teleported.** Catch them in hand partway there: the old order put
	# the suspect inside the car from five metres away, and a check that only looked at
	# the end state could not tell the two apart.
	var walked := false
	var loaded := false
	for i in 900:
		await physics_frame
		if suspect.escorted_by == _officer:
			walked = true
		if suspect.is_loaded:
			loaded = true
			break
	_check(walked, "the officer takes them in hand and walks them")
	_check(loaded, "the suspect gets in the back")

	# The drive home. Placed rather than driven -- the route home has its own tests.
	await _place_unit(_car, _station.global_position + Vector3(0.0, 0.0, -2.0))
	var booked := false
	for i in 120:
		await physics_frame
		if _board.open_calls().is_empty():
			booked = true
			break
	_check(booked, "driving into the station books them in and clears the call")
	_check(_mission.arrests == 1, "the arrest is tallied (%d)" % _mission.arrests)
	_check(_mission.score == Mission.ARREST_POINTS + Mission.RESPONSE_BONUS,
		"and scored with the response bonus (%d, expected %d)"
		% [_mission.score, Mission.ARREST_POINTS + Mission.RESPONSE_BONUS])
	_check(_mission.earned == _mission.score,
		"an arrest pays what it scores (£%d)" % _mission.earned)

	# Crime stays kerbside. The escort reach bridges road edge to pavement tile but
	# no further, so every spot the picker offers must stand against a road -- a
	# suspect in a park interior would be one no patrol car could ever collect.
	_director._rng.seed = 9
	var kerbside := true
	var offered := 0
	for i in 30:
		var pick := _director._pick_pavement(true)
		if pick == Vector3.INF:
			continue
		offered += 1
		if not _director._roadside(pick):
			kerbside = false
	_check(offered > 0 and kerbside,
		"every crime spot stands against a road (%d sampled)" % offered)

	_mission.scoring = false
	_reset_mission()
	await _clear_calls()


## A collapse with a bottle beside it, and the assessment comes back medical: the call
## carries on exactly as any other casualty, and the not-knowing is all it cost.
func _test_a_drunk_call_can_be_just_a_collapse() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 31
	_director._spawn_drunk()
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	if bodies.size() != 1:
		_check(false, "a drunk call is one casualty (%d)" % bodies.size())
		_stand_to()
		return
	var casualty := bodies[0] as Casualty
	_check(casualty.needs_assessment, "flagged as needing assessment")
	var propped := false
	for child in casualty.get_children():
		if str(child.scene_file_path).contains("SM_Item_"):
			propped = true
	_check(propped, "with the drink lying beside them")
	_check(casualty.describe_state() == "unresponsive -- cause unknown",
		"the readout commits to nothing ('%s')" % casualty.describe_state())
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].title() == "Person collapsed, drink suspected",
		"and the board says only what was called in")

	# Force the roll medical, then work past the assessment threshold.
	casualty.turns_rowdy = false
	casualty.treat(0.5)
	await _idle(4)
	_check(is_instance_valid(casualty) and casualty.active
			and not casualty.needs_assessment,
		"the assessment comes back medical and the casualty stays a casualty")
	_check(get_nodes_in_group(Suspect.SUSPECT_GROUP).is_empty(),
		"nobody stood up swinging")
	casualty.treat(1.0)
	_check(casualty.is_stable, "and they stabilise like anyone else")
	_stand_to()
	await _clear_calls()


## The other half of the roll: they were never hurt at all. The suspect stands up in the
## casualty's own clothes, the *same* call flips to crime rather than closing, and
## nobody is paid or penalised for a patient that never existed.
func _test_a_drunk_call_can_turn_into_an_arrest() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 37
	_director._spawn_drunk()
	await _idle(6)

	var bodies := get_nodes_in_group(Casualty.CASUALTY_GROUP)
	if bodies.size() != 1:
		_check(false, "a drunk call is one casualty (%d)" % bodies.size())
		_stand_to()
		return
	var casualty := bodies[0] as Casualty
	var call: Call = null
	if not _board.open_calls().is_empty():
		call = _board.open_calls()[0]
	var worn := str(casualty.get_node("Character").scene_file_path)
	var spot := casualty.global_position
	var saved_before := _mission.casualties_saved
	var lost_before := _mission.casualties_lost
	var arrests_before := _mission.arrests

	casualty.turns_rowdy = true
	casualty.treat(0.5)
	await _idle(8)

	_check(not is_instance_valid(casualty),
		"the casualty is gone -- there was never a patient")
	var suspects := get_nodes_in_group(Suspect.SUSPECT_GROUP)
	if suspects.size() != 1:
		_check(false, "one suspect stood up (%d)" % suspects.size())
		_stand_to()
		await _clear_calls()
		return
	var suspect := suspects[0] as Suspect
	_check(_flat_distance(suspect.global_position, spot) < 1.0,
		"where the casualty lay (%.1fm off)"
		% _flat_distance(suspect.global_position, spot))
	_check(str(suspect.get_node("Character").scene_file_path) == worn,
		"wearing the same clothes")
	# **The call survives the swap.** The deferred-adopt trap pinned: the suspect must
	# be in the call's list before the casualty leaves it, or the list empties and the
	# call closes RESOLVED -- banking a cleared call and a response bonus for a job
	# nobody did. Sabotage map: reddened by re-staging the swap retire-first (suspect
	# spawned frames after the free); deleting only the frame-wait keeps it green,
	# because the add-before-retire ordering alone holds the list non-empty -- the
	# wait is margin, not the mechanism.
	var held := call != null and is_instance_valid(call) and call.is_open()
	_check(held, "the same call is still open")
	_check(held and call.kind == Call.Kind.CRIME, "and now reads as crime")
	_check(held and call.title() == "Drunk and disorderly",
		"under its new name ('%s')" % (call.title() if held else "?"))
	_check(_mission.casualties_saved == saved_before
			and _mission.casualties_lost == lost_before,
		"and the medical ledger never moved")

	# Book them in from code -- the walk and the drive have their own tests.
	suspect.detain(1.0)
	suspect.deliver()
	await _idle(6)
	_check(_board.open_calls().is_empty(), "the arrest closes the call")
	_check(_mission.arrests == arrests_before + 1,
		"and is tallied (%d)" % _mission.arrests)
	_stand_to()
	await _clear_calls()


## The first call the player searches: a marked report where the child was last seen,
## and an unmarked child strolling the walk graph a genuine walk away. The marker's
## honesty is the whole design -- it points at what is known, not at the answer.
func _test_a_missing_child_call_stages_a_search() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 41
	_director._spawn_missing_child()
	await _idle(6)

	var reports: Array[Node] = []
	for node in get_nodes_in_group(Incident.GROUP):
		if node is MissingChild:
			reports.append(node)
	if reports.size() != 1:
		_check(false, "a missing-child call is one report (%d)" % reports.size())
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var open := _board.open_calls()
	_check(not open.is_empty() and open[0].kind == Call.Kind.CRIME,
		"a missing person is police work on the board")
	_check(not open.is_empty() and open[0].title() == "Child reported missing",
		"named for the report ('%s')"
		% (open[0].title() if not open.is_empty() else "no call"))

	var child := report.child
	if child == null or not is_instance_valid(child):
		_check(false, "a child to search for")
		_stand_to()
		await _clear_calls()
		return
	var gap := _flat_distance(child.global_position, report.global_position)
	_check(gap >= 40.0, "the child is a genuine journey from the report (%.0fm)" % gap)
	# The marker's honesty: the call sits on the report, never on the child.
	_check(not open.is_empty()
			and _flat_distance(open[0].position, report.global_position) < 5.0,
		"the call's marker stands at the last-seen point")
	_check(not child.is_selectable(), "the child cannot be selected")
	_check(child.collision_layer == 128,
		"and lives on the crowd layer the picking ray ignores (%d)"
		% child.collision_layer)
	_check(not child.is_in_group(Incident.GROUP),
		"and is not an incident -- nothing on the board points at them")
	var body := child.get_node_or_null("Character") as Node3D
	_check(body != null and body.scale.x < 0.8,
		"a small figure reads as a child (scale %.2f)"
		% (body.scale.x if body else 0.0))

	# Teardown wiring: the child leaves with the report.
	await _clear_calls()
	_check(not is_instance_valid(child), "the child leaves with the report")
	_stand_to()


## The three beats: a person finds the child (vehicles driving past do not), the
## child walks at heel and climbs into a *police* car (an ambulance is refused), and
## the call closes only when that car pulls up back at the parent -- with the score
## landing on the reunion, not the find.
func _test_a_found_child_closes_the_call() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_mission.begin_scoring()
	_director._rng.seed = 43
	_director._spawn_missing_child()
	await _idle(6)

	var reports := get_nodes_in_group(Incident.GROUP).filter(
		func(node: Node) -> bool: return node is MissingChild)
	if reports.size() != 1:
		_check(false, "a missing-child call to work (%d)" % reports.size())
		await _end_freeplay()
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var child := report.child
	# Captured now, because every later dereference of `report` is guarded: a fault
	# that closes the call early frees it, and an unguarded read converts the red
	# assertions below into a SCRIPT ERROR that silently skips them -- measured, by
	# the sabotage run that came back green-looking with eleven checks missing.
	var home_spot := report.global_position

	# Attend the report first, so the response clock stops at once and the score
	# below is the deterministic sum -- the tightened-equality lesson from the
	# shed-load check.
	await _place_unit(_officer, home_spot + Vector3(2.0, 0.0, 0.0))
	await _idle(8)

	# A vehicle beside the child is not a find: the scan asks people only. Parked
	# outside board_reach so this stages only the question it asks.
	await _place_unit(_car, child.global_position + Vector3(5.5, 0.2, 0.0))
	await _wait(30)
	_check(is_instance_valid(report) and report.active and not report.found,
		"a patrol car driving up does not find a child")
	await _place_unit(_car, _station.global_position + Vector3(-6.0, 0.2, -2.5))

	# The find is the middle of the job, not the end.
	await _place_unit(_officer, child.global_position + Vector3(1.5, 0.0, 0.0))
	var taken := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(report) or not report.active:
			break
		if report.found:
			taken = true
			break
	_check(taken and is_instance_valid(child) and child.following == _officer,
		"an officer reaching the child takes them in hand")
	_check(is_instance_valid(report) and report.active
			and not _board.open_calls().is_empty(),
		"and finding them is not the end of the job -- the call stays open")
	if not is_instance_valid(report) or not is_instance_valid(child):
		# The reds above have already said what broke; bailing keeps a freed report
		# from converting the rest of this check into a silent skip.
		await _end_freeplay()
		_stand_to()
		return

	# A child is driven home in a patrol car, not stretchered home in an ambulance.
	await _place_unit(_ambulance, child.global_position + Vector3(2.0, 0.2, 0.0))
	await _wait(45)
	_check(child.riding == null,
		"an ambulance alongside them is not their ride")
	await _place_unit(_ambulance, _station.global_position + Vector3(6.0, 0.2, -2.5))

	await _place_unit(_car, child.global_position + Vector3(2.0, 0.2, 0.0))
	var aboard := false
	for i in 120:
		await physics_frame
		if child.riding == _car:
			aboard = true
			break
	_check(aboard, "a patrol car alongside them is")
	_check(not child.visible, "and they are riding, not walking beside it")
	# The child is 45m+ from home here, so a call that closes now has confused
	# boarding with arriving -- the reunion is at the parent, not at the kerb where
	# they were picked up.
	await _wait(30)
	_check(is_instance_valid(report) and report.active,
		"aboard is not home -- the call holds until the car gets there")

	# The drive home. Placed rather than driven -- the route has its own tests. The
	# destination is the captured spot, not a read of the possibly-freed report.
	await _place_unit(_car, home_spot + Vector3(4.0, 0.2, 0.0))
	var home := false
	for i in 120:
		await physics_frame
		if not is_instance_valid(report) or not report.active:
			home = true
			break
	_check(home, "pulling up at the parent ends the job")
	await _idle(8)
	_check(_board.open_calls().is_empty(), "the reunion closes the call")
	_check(_mission.children_found == 1,
		"the debrief counts it (%d)" % _mission.children_found)
	_check(_mission.score == Mission.MISSING_POINTS + Mission.RESPONSE_BONUS,
		"scored like a person recovered plus the response bonus (%d, expected %d)"
		% [_mission.score, Mission.MISSING_POINTS + Mission.RESPONSE_BONUS])
	_check(_mission.earned == _mission.score,
		"a reunion pays what it scores (£%d)" % _mission.earned)
	await _end_freeplay()
	_stand_to()


## The child is a civilian by construction, and three systems consume civilians: a
## medical call takes one, a disturbance recruits one, a blast converts one. Each
## taking the child would free the body its report is scanning for -- and the report
## then retires silently, closing the call for a job nobody did. All three exclusions
## in one staging: the child is parked in a quiet corner and each consumer is offered
## them directly.
func _test_the_missing_child_stays_out_of_other_calls() -> void:
	await _clear_calls()
	await _park_the_shift()
	_stand_down()
	_director._rng.seed = 47
	_director._spawn_missing_child()
	await _idle(6)

	var reports := get_nodes_in_group(Incident.GROUP).filter(
		func(node: Node) -> bool: return node is MissingChild)
	if reports.size() != 1:
		_check(false, "a missing-child call to stage against (%d)" % reports.size())
		_stand_to()
		return
	var report := reports[0] as MissingChild
	var child := report.child
	# Parked well clear of the report's own call, so the director's clearance rules
	# would offer them to a medical call but for the class exclusion.
	var corner := report.global_position
	for point in CityGrid.pavement_points():
		if _flat_distance(point, report.global_position) > 60.0:
			corner = point
			break
	child.global_position = corner
	child.wander_centre = corner
	await _idle(4)

	# **One civilian parked somewhere provably eligible, first.**
	#
	# The second half of this check reads the *pool*, and the pool is every civilian
	# standing clear of every open call. By this point in the suite the board is busy
	# and the crowd has wandered, so on some runs the pool is empty and the check fails
	# on a picker that is working perfectly -- it went red in a Stop gate having passed
	# on the re-run before it, which is the worst way for a suite to behave.
	#
	# Staging a stand-in makes the assertion about the thing it is named for: the child
	# is excluded *and* somebody else is not. The point is chosen the same way the
	# child's corner was, and asked of the director's own clearance rule rather than a
	# distance guessed here.
	var stand_in: Civilian = null
	# The suite *is* the SceneTree, so groups are read off it directly.
	for node in get_nodes_in_group(Unit.GROUP):
		var civilian := node as Civilian
		if civilian and not (civilian is ChildWanderer):
			stand_in = civilian
			break
	if stand_in:
		for point in CityGrid.pavement_points():
			if _flat_distance(point, corner) > 40.0 and _director._clear(point):
				# Position only: `wander_centre` belongs to the child's wanderer, not to
				# an ordinary civilian, and assigning it here threw -- which abandoned
				# the rest of this check and cost four more without a FAIL line.
				stand_in.global_position = point
				stand_in.is_fleeing = false
				break
		await _idle(4)
	_check(stand_in != null and _director._clear(stand_in.global_position),
		"a civilian stood somewhere a medical call could take them")

	# The medical call's picker. Two hundred seeded draws: none may be the child, and
	# at least one must be somebody -- a picker that returns nothing proves nothing.
	_director._rng.seed = 3
	var drew_child := false
	var drew_anyone := false
	for i in 200:
		var pick := _director._pick_civilian()
		if pick is ChildWanderer:
			drew_child = true
		elif pick != null:
			drew_anyone = true
	_check(not drew_child and drew_anyone,
		"a medical call never takes the child (200 draws, someone else %s)"
		% drew_anyone)

	# The disturbance's recruiter, offered the child at point-blank range. The clock
	# is lowered the way the disorder test lowers it -- the recruit interval latches
	# at a full 9s in _ready, and a 4s window against that never reaches the
	# exclusion at all. Measured: the first cut of this line stayed green with the
	# exclusion deleted, because _draw_one_in had never once run.
	var suspect := _spawn_suspect(corner + Vector3(2.0, 0.0, 0.0))
	suspect.recruits = true
	suspect.max_group = 8
	suspect.recruit_interval = 0.5
	await _wait(240)
	_check(is_instance_valid(child) and child is ChildWanderer,
		"a disturbance never recruits the child")

	# The blast, applied to the child's own doorstep.
	var hazard := (load("res://Game/Incidents/Hazard.tscn") as PackedScene) \
		.instantiate() as Hazard
	if hazard:
		_incidents.add_child(hazard)
		hazard.global_position = corner + Vector3(3.0, 0.0, 0.0)
		await _idle(4)
		hazard._hurt_people(child.global_position)
		await _idle(4)
	_check(is_instance_valid(child) and child is ChildWanderer,
		"a blast never converts the child")
	_check(is_instance_valid(report) and report.active,
		"and through all three the search stays open")

	await _clear_calls()
	_stand_to()


func _test_scoring_rewards_a_fast_response() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	# The officer is already standing at the scene when it opens, which is as fast as
	# a response can be: the bonus should not lose a point of its 100.
	var spot := Vector3(20.0, 0.0, -20.0)
	await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
	var fire := _spawn_fire(spot, 0.5)
	await _idle(6)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to score")
		return
	_check(open[0].response_age >= 0.0,
		"the call recorded when it was first attended (%.1fs)" % open[0].response_age)

	var purse := _station.funds
	fire.douse(5.0)
	await _idle(6)
	_check(_mission.calls_cleared == 1,
		"the cleared call was counted (%d)" % _mission.calls_cleared)
	var expected := Mission.FIRE_POINTS + Mission.RESPONSE_BONUS
	_check(_mission.score == expected,
		"a fast attendance earns fire points plus the full bonus (%d, expected %d)"
		% [_mission.score, expected])
	_check(_station.funds - purse == expected and _mission.earned == expected,
		"and the same number lands in the purse as pounds (£%d banked)"
		% (_station.funds - purse))


func _test_a_slow_response_scores_at_the_floor() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	var spot := Vector3(20.0, 0.0, -20.0)
	var fire := _spawn_fire(spot, 0.5)
	await _idle(6)
	var open := _board.open_calls()
	if open.is_empty():
		_check(false, "a call to keep waiting")
		return
	# Nobody comes for 80 seconds -- said rather than sat through.
	open[0].age = 80.0
	await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
	await _idle(6)
	_check(open[0].response_age >= 60.0,
		"the wait went on the record (%.1fs)" % open[0].response_age)

	var purse := _station.funds
	fire.douse(5.0)
	await _idle(6)
	var expected := Mission.FIRE_POINTS \
		+ roundi(Mission.RESPONSE_BONUS * Mission.RESPONSE_FLOOR)
	_check(_mission.score == expected,
		"a response that slow earns only the floor of the bonus (%d, expected %d)"
		% [_mission.score, expected])
	_check(_station.funds - purse == expected,
		"the multiplier squeezes the pay the same way (£%d)"
		% (_station.funds - purse))


func _test_a_lost_casualty_costs_points_not_the_shift() -> void:
	await _clear_calls()
	_mission.begin_scoring()
	var purse := _station.funds

	var casualty := _spawn_casualty(Vector3(20.0, 0.0, -20.0))
	casualty.health = 0.05
	casualty.decline_per_second = 0.5
	await _wait(30)
	_check(_mission.state == Mission.State.RUNNING,
		"freeplay survives a lost casualty -- the shift goes on (%d)" % _mission.state)
	_check(_mission.score == -Mission.LOST_PENALTY,
		"the loss is charged to the score (%d)" % _mission.score)
	_check(_mission.calls_failed == 1,
		"and the call goes down as failed (%d)" % _mission.calls_failed)
	_check(_station.funds == purse,
		"but never to the purse -- a struggling career is not fined into the ground")
	await _clear_calls()


func _test_the_shift_ends_with_a_summary() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 5
	_director.shift_length = 1.5
	_director.first_call_delay = 0.3
	_director.call_interval_min = 5.0
	_director.call_interval_max = 5.0
	_director.max_open_calls = 1
	_director.breather = 0.2
	_director.begin_shift()

	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to finish the shift on")
		await _end_freeplay()
		return
	# Past the end of the shift with the call still open: it must not end early.
	await _wait(90)
	_check(_mission.state == Mission.State.RUNNING,
		"time running out does not end a shift with a job on the board (%d)"
		% _mission.state)

	_resolve_call(_board.open_calls()[0])
	var over := false
	for i in 120:
		await physics_frame
		if _mission.state == Mission.State.OVER:
			over = true
			break
	_check(over, "the shift ends once the last call clears (%d)" % _mission.state)
	_check(not _director.active, "and the director stands down")

	# The card carries its own heading, so the banner and the one-line debrief both
	# stand down at the end of a shift rather than repeating above a table that says
	# the same thing at length. Both used to be the debrief; this asserts they are not
	# still showing under it.
	var banner := _scene.get_node_or_null("HUD/Root/World/Banner") as Label
	var debrief := _scene.get_node_or_null("HUD/Root/World/ObjectiveBar/Body/Debrief") as Label
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	_check(card != null and card.visible, "the debrief card is what announces the end")
	_check(banner != null and not banner.visible
			and debrief != null and not debrief.visible,
		"and the banner and the old one-line debrief stand down under it")
	# The shift's actual record reached the card, not just a card.
	var shown := PackedStringArray()
	if card:
		for line in card.get_child(0).get_child(0).get_child(0).get_children():
			for cell in line.get_children():
				var text := cell as Label
				if text:
					shown.append(text.text)
	var joined := " ".join(shown)
	_check("Calls cleared" in joined and "1" in joined,
		"carrying the shift's own record ('%s')" % joined)
	# Deliberately not resetting the mission here: the next test starts a new shift
	# over this debrief and has to clear it, exactly as a player would see it.


func _test_freeplay_key_starts_the_shift() -> void:
	# Parked out of the way so the new shift opens no calls while it is under test.
	_director.first_call_delay = 999.0
	_director.shift_length = 9999.0
	await _press_key(KEY_F2)
	await _idle(4)
	_check(_director.active, "F2 opens a shift")
	_check(_mission.scoring and _mission.state == Mission.State.RUNNING,
		"scoring is live (%s, state %d)" % [_mission.scoring, _mission.state])

	var banner := _scene.get_node_or_null("HUD/Root/World/Banner") as Label
	_check(banner != null and not banner.visible,
		"and starting a new shift clears the last debrief")

	var before: float = _director.clock
	await _press_key(KEY_F2)
	await _idle(4)
	_check(_director.active and _director.clock >= before,
		"a second press does not restart the shift (%.2f -> %.2f)"
		% [before, _director.clock])
	await _end_freeplay()


## The debrief score outlives the window: the best shift is banked to disk and every
## later one is measured against it. This is the project's only save-shaped code, so
## the reload is exercised too.
func _test_the_best_score_survives() -> void:
	await _clear_calls()
	_mission.begin_scoring()
	_mission.score = 9999
	_mission.end_shift()
	_check(_mission.is_new_best and _mission.best_score == 9999,
		"a record shift becomes the new best (%d)" % _mission.best_score)
	_check("NEW BEST" in _mission.summary(),
		"and the debrief says so ('%s')" % _mission.summary())

	# The next session: a fresh load finds the banked record.
	_mission.best_score = 0
	_mission._load_records()
	_check(_mission.best_score == 9999,
		"the record survives a reload (%d)" % _mission.best_score)

	_mission.begin_scoring()
	_mission.score = 120
	_mission.end_shift()
	_check(not _mission.is_new_best and _mission.best_score == 9999,
		"an ordinary shift does not disturb it (best still %d)" % _mission.best_score)
	_check("BEST 9999" in _mission.summary(),
		"and its debrief shows the bar to clear")
	_mission.scoring = false
	_reset_mission()


## The end-of-shift debrief as a table, and the average response inside it.
##
## The average is the part worth checking, because it is the one number on the card the
## mission has to *accumulate* rather than count -- everything else is a tally that was
## already there. It is fed from the same figure the response bonus is paid on, which
## the shift had been using and throwing away.
func _test_the_debrief_reads_as_a_table() -> void:
	await _clear_calls()
	await _park_the_shift()
	_mission.begin_scoring()

	_check(_mission.average_response() < 0.0,
		"a shift that has cleared nothing has no average response to give (%.1f)"
		% _mission.average_response())

	# Two calls attended at different speeds, so the mean is a mean of something.
	#
	# **Both waits are substantial, and that is the point.** The first version used a
	# near-instant arrival (~0.1s) against a slow one, and was vacuous: with one sample
	# contributing almost nothing, a `=` instead of a `+=` moved the mean by 0.05s --
	# invisible inside any sane tolerance -- and a missing divide landed at 3.2 against
	# a range whose upper edge was 3.6. It passed against both of the faults its own
	# comment named. Two comparable waits make the arithmetic discriminating: 2s and 6s
	# mean the true average is 4.0, last-value-wins gives 3.0, and a missing divide
	# gives 8.0.
	var waits := []
	for run in [{"at": Vector3(20.0, 0.0, -20.0), "wait": 120}, \
			{"at": Vector3(-24.0, 0.0, 24.0), "wait": 360}]:
		var spot: Vector3 = run["at"]
		var fire := _spawn_fire(spot, 0.5)
		await _idle(6)
		# The slow one is left alone for a while before anybody arrives.
		await _idle(int(run["wait"]))
		await _place_unit(_officer, spot + Vector3(5.0, 0.0, 0.0))
		await _idle(10)
		var open := _board.open_calls()
		if not open.is_empty():
			waits.append(open[0].response_age)
		fire.douse(5.0)
		await _idle(8)

	_check(_mission.calls_cleared == 2,
		"two calls cleared at different speeds (%d)" % _mission.calls_cleared)
	var mean := _mission.average_response()
	_check(mean > 0.0, "the shift has an average response (%.1fs)" % mean)
	# Against the arithmetic mean itself, not against a range containing it. "Between
	# the two" is far too weak a claim: a sum that never divided, and a total that kept
	# only the last call, both sit inside that range for these numbers.
	if waits.size() == 2:
		var low: float = minf(waits[0], waits[1])
		var high: float = maxf(waits[0], waits[1])
		var expected := (low + high) * 0.5
		_check(absf(mean - expected) < 0.5,
			"and it is the mean of the two it averaged (%.1f, expected %.1f from "
			% [mean, expected] + "%.1f and %.1f)" % [low, high])
		_check(high - low > 2.0,
			"which were far enough apart to tell a mean from either (%.1fs apart)"
			% (high - low))

	# The card itself: rows, not a sentence.
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	_check(card != null, "the interface carries a debrief card")
	if card != null:
		var rows := _mission.debrief_rows()
		_check(rows.size() >= 5, "the debrief has rows to lay out (%d)" % rows.size())
		var labels := PackedStringArray()
		for row in rows:
			labels.append(str(row["label"]))
		var joined := " | ".join(labels)
		_check("Average response" in joined,
			"including the average response (%s)" % joined)
		card.show_shift(_mission)
		_check(card.visible, "and the card shows when a shift ends")
		# Every row reached the screen, plus the heading.
		var body := card.get_child(0).get_child(0).get_child(0) as VBoxContainer
		_check(body != null and body.get_child_count() == rows.size() + 1,
			"with every row drawn (%d children for %d rows and a heading)"
			% [body.get_child_count() if body else -1, rows.size()])
		card.hide_card()

	_mission.scoring = false
	_reset_mission()
	await _clear_incidents()
	await _clear_calls()


## A shift has to be able to *end*, even when one of its calls cannot be finished.
##
## Time running out deliberately does not end a shift -- you finish what you started,
## and the debrief waits for the board to clear. That rule assumed every open call can
## be cleared, and it cannot: a career with a paramedic and no ambulance treats a
## casualty to stable and then owns nothing that can collect them, so the call stays
## open for ever. Measured before the fix, a four-second shift was still running forty
## seconds later, and five played sessions in a row wrote no best-score record because
## not one of them ever reached a debrief. The overrun is the deadline that ends it.
func _test_a_shift_ends_even_with_an_unanswerable_call() -> void:
	await _clear_calls()
	await _park_the_shift()

	var kept_length := _director.shift_length
	var kept_grace := _director.overrun_grace
	var kept_delay := _director.first_call_delay
	# No rolled calls; this stages the one call it cares about.
	_director.first_call_delay = 99999.0
	_director.shift_length = 1.0
	_director.overrun_grace = 3.0
	_director.begin_shift()
	await _idle(4)

	# A casualty treated to stable, with nothing on the map that can carry them. The
	# ambulance is parked but its Collect is the paramedic's stretcher run, so simply
	# not ordering it leaves the call genuinely outstanding.
	var spot := Vector3(26.0, 0.0, 26.0)
	var casualty := _spawn_casualty(spot)
	await _idle(6)
	casualty.treat(2.0)
	await _idle(8)
	_check(casualty.is_stable and not casualty.is_loaded,
		"a stabilised casualty nothing has collected")
	_check(_board.open_calls().size() == 1,
		"holds its call open (%d)" % _board.open_calls().size())

	# Well past the shift *and* its overrun.
	var ended := false
	for i in 60 * 8:
		await physics_frame
		if not _director.active:
			ended = true
			break
	_check(ended, "the shift stands down anyway at the overrun deadline (%.1fs of %.1f)"
		% [_director.clock, _director.shift_length + _director.overrun_grace])
	_check(_board.open_calls().is_empty(),
		"with the outstanding call closed (%d left)" % _board.open_calls().size())
	_check(_mission.calls_failed >= 1,
		"counted as failed rather than quietly forgotten (%d)" % _mission.calls_failed)
	_check(_mission.state == Mission.State.OVER,
		"and the mission reaches its debrief (%d)" % _mission.state)

	_director.shift_length = kept_length
	_director.overrun_grace = kept_grace
	_director.first_call_delay = kept_delay
	_mission.scoring = false
	_reset_mission()
	await _clear_incidents()
	await _clear_calls()


## Escape freezes the district: one flag, and everything PAUSABLE -- vehicles, fires,
## clocks, call ages -- stops together. The menu runs ALWAYS, which is what lets Escape
## also thaw it.
##
## Was `P` until August 2026. The key moved because Escape is where every other game puts
## it; what the move cost is that Escape already meant "cancel" twice over, which
## `_test_escape_cancels_before_it_pauses` is the check for.
func _test_pause_freezes_the_district() -> void:
	await _place(ROAD)
	_car.navigate_to(ROAD + Vector3(0.0, 0.0, -60.0))
	await _wait(30)
	_check(absf(_car.forward_speed) > 1.0,
		"a car is on the move (%.1f m/s)" % _car.forward_speed)

	await _press_key(KEY_ESCAPE)
	_check(_menu.visible and _menu.screen == GameMenu.Screen.PAUSE
			and paused,
		"Escape pauses the game and shows the menu")
	var held := _car.global_position
	await _wait(60)
	_check(_car.global_position.distance_to(held) < 0.05,
		"the district is frozen (%.2fm drift over a second)"
		% _car.global_position.distance_to(held))

	await _press_key(KEY_ESCAPE)
	_check(not _menu.visible and not paused, "Escape again resumes")
	await _wait(30)
	_check(_car.global_position.distance_to(held) > 1.0, "and the car drives on")
	_car.stop_navigating()


## Escape unwinds the innermost thing first: the shop closes, and the pause menu stays
## shut.
##
## The armed-ability half of this rule is checked where the ability is armed, in
## `_test_command_hotkeys_run_abilities`. This is the other claimant, and it is the one
## the tree order would get wrong on its own -- `GameMenu._input` runs *before*
## `ShopPanel._input`, so without the guard the pause card would open over an open shop.
func _test_escape_closes_the_shop_before_it_pauses() -> void:
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as ShopPanel
	if shop == null or _menu == null:
		_check(false, "a shop and a menu to arbitrate between")
		return
	# **The entry state, carried into the verdict below.** Found by sabotage: when the
	# guard is broken, the checks *before* this one leave the tree paused and the menu
	# already in PAUSE -- so this check's Escape *resumes* instead of pausing, and
	# "the pause menu was left alone" reads true on the very fault it exists to catch.
	# A probe in a clean tree confirmed the fault does reach it; the suite was simply
	# too contaminated by then for the reading to mean anything. Requiring a fit tree
	# turns that false green into an honest red.
	var was_clear: bool = _menu.screen == GameMenu.Screen.HIDDEN and not paused
	_check(was_clear, "the menu is down before the shop opens")

	shop.open_shop()
	await _idle(3)
	_check(shop.visible, "the shop is open")

	await _press_key(KEY_ESCAPE)
	_check(not shop.visible, "Escape closed the shop")
	_check(was_clear and not paused and _menu.screen != GameMenu.Screen.PAUSE,
		"and left the pause menu alone")

	# And with nothing to cancel, the same key does pause -- otherwise the guard above
	# could be an Escape handler that never fires at all.
	await _press_key(KEY_ESCAPE)
	_check(paused and _menu.screen == GameMenu.Screen.PAUSE,
		"with nothing open, Escape pauses")
	await _press_key(KEY_ESCAPE)
	await _idle(2)


## The speed buttons: the district genuinely runs faster, and normal puts it back.
##
## **Asserted on the shift clock, not on `Engine.time_scale`.** Reading back the property
## the button just set proves the button is wired to that property and nothing else --
## `Mission.elapsed` accumulates `delta`, so it can only double if the frames the rest of
## the game sees doubled too. The clock is also the flattest thing here to measure: a car
## would carry acceleration and steering into the number.
func _test_the_speed_buttons_run_the_district_faster() -> void:
	var strip := _scene.get_node_or_null("HUD/Root/World/ScoreStrip") as ScoreStrip
	if strip == null or _mission == null or _menu == null:
		_check(false, "a strip, a mission and a menu")
		return
	var speeds: Array[Button] = []
	for node in strip.find_children("*", "Button", true, false):
		var button := node as Button
		if button and button.toggle_mode:
			speeds.append(button)
	_check(speeds.size() == GameMenu.SPEEDS.size(),
		"the strip offers %d speeds (%d)" % [GameMenu.SPEEDS.size(), speeds.size()])
	if speeds.size() < GameMenu.SPEEDS.size():
		return

	var kept_state := _mission.state
	_mission.state = Mission.State.RUNNING

	speeds[0].pressed.emit()
	await _idle(2)
	var mark := _mission.elapsed
	await _idle(30)
	var normal: float = _mission.elapsed - mark

	speeds[2].pressed.emit()
	await _idle(2)
	mark = _mission.elapsed
	await _idle(30)
	var doubled: float = _mission.elapsed - mark

	_check(normal > 0.0 and doubled > normal * 1.7 and doubled < normal * 2.3,
		"2x runs the shift clock about twice as fast (%.2fs against %.2fs, 30 frames)"
		% [doubled, normal])

	# **Put the engine back, and check that putting it back works.** `Engine.time_scale`
	# is global and outlives a scene, so a suite that left here at 2x would hand every
	# later check a district running at double speed -- and the failures would land
	# anywhere but here.
	_menu.reset_speed()
	await _idle(2)
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"and normal speed puts the engine back (%.2f)" % Engine.time_scale)
	_mission.state = kept_state


## A designed shift, end to end: the picker offers it, the timeline opens its waves in
## order, the win is held back until the last one, and the debrief says what it came to
## against par.
##
## Driven through the menu rather than by making a ScenarioDirector by hand, because
## the wiring *is* the feature -- the node is created at runtime precisely so the
## generated district needs no new node in it, and a check that built one itself would
## never notice that path breaking.
func _test_a_scenario_plays_its_timeline() -> void:
	await _clear_incidents()
	_reset_mission()
	_director.abandon_shift()
	await _idle(2)

	# A scenario the suite's fleet can actually field. The police one: the suite buys
	# patrols and officers, and asserting on a scenario whose units nobody owns would
	# be asserting on the picker's refusal instead.
	var index := -1
	for i in Scenarios.ALL.size():
		if Scenarios.ALL[i]["id"] == &"night_shift":
			index = i
	_check(index >= 0, "the night shift is on the card")
	if index < 0:
		return
	var scenario: Dictionary = Scenarios.by_index(index)
	_check(Scenarios.missing_for(scenario, _station).is_empty(),
		"and this career can field it (%s)"
		% ", ".join(PackedStringArray(Scenarios.missing_for(scenario, _station))))

	_menu.open_scenarios()
	await _idle(2)
	_check(_menu.screen == GameMenu.Screen.SCENARIOS,
		"the picker opens (screen %d)" % _menu.screen)

	_menu.start_scenario(index)
	await _idle(2)
	var runner := _scene.get_node_or_null("ScenarioDirector") as ScenarioDirector
	_check(runner != null, "picking one puts a runner in the district")
	if runner == null:
		return
	_check(not _menu.visible and _mission.par_seconds == scenario["par"],
		"the card lifts and the mission takes its par (%.0fs)" % _mission.par_seconds)
	# The freeplay director must stay stood down: a scenario is a shout, not a shift,
	# and a scoring mission would switch the scripted win rule off entirely.
	_check(not _director.active and not _mission.scoring,
		"with freeplay left alone (active %s, scoring %s)"
		% [_director.active, _mission.scoring])

	# Hurried along rather than waited out: the real timeline is 55 seconds and this
	# is checking the order, not the arithmetic of a clock.
	#
	# On the runner's own **copy**. `Scenarios.ALL` is a const, and a const's nested
	# dictionaries are read-only at runtime -- writing to one throws, and a throw
	# inside a check silently abandons the rest of it. That is exactly what happened
	# here: six checks stopped running and the suite still called itself green apart
	# from the count. See the working notes in NEXT.md.
	var hurried := scenario.duplicate(true)
	for wave: Dictionary in hurried["waves"]:
		wave["at"] = 0.0
	runner.scenario = hurried
	await _idle(30)
	var opened := get_nodes_in_group(Incident.GROUP).size()
	_check(opened > 0, "the timeline opens its calls (%d on the map)" % opened)
	_check(not _mission.more_to_come,
		"and lets go of the win once the last wave is out")

	# Clearing everything wins it, and the modal says so with a score of its own --
	# `scoring` is off, so Mission.score is zero throughout and shout_score is what
	# the card has to be reading.
	for node in get_nodes_in_group(Incident.GROUP):
		(node as Incident)._finish(true)
	await _idle(8)
	_check(_mission.state == Mission.State.WON,
		"clearing the last of it wins the scenario (%d)" % _mission.state)
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	var shown := PackedStringArray()
	if card and card.visible:
		for line in card.get_child(0).get_child(0).get_child(0).get_children():
			for cell in line.get_children():
				var text := cell as Label
				if text:
					shown.append(text.text)
	var joined := " ".join(shown)
	_check(card != null and card.visible and "Par" in joined,
		"and the debrief reports it against par ('%s')" % joined)

	runner.queue_free()
	await _clear_incidents()
	_reset_mission()
	_mission.par_seconds = 0.0
	await _idle(2)


func _test_the_menu_restarts_a_shift() -> void:
	await _clear_calls()
	await _park_the_shift()
	_director.shift_seed = 4
	_director.shift_length = 9999.0
	_director.first_call_delay = 0.2
	_director.call_interval_min = 5.0
	_director.call_interval_max = 5.0
	_director.max_open_calls = 2
	_director.breather = 0.2
	_director.begin_shift()
	var opened := false
	for i in 120:
		await physics_frame
		if not _board.open_calls().is_empty():
			opened = true
			break
	if not opened:
		_check(false, "a call to restart away")
		await _end_freeplay()
		return
	_mission.score = 500

	_menu.open_pause()
	await _idle(2)
	await _menu.restart_shift()
	await _idle(8)
	_check(_director.active and _director.clock < 2.0,
		"restart opens a fresh shift (clock %.1f)" % _director.clock)
	_check(_board.open_calls().is_empty(), "with a clear board")
	_check(_mission.scoring and _mission.score == 0 and _mission.calls_cleared == 0,
		"and a zeroed score (%d, %d cleared)"
		% [_mission.score, _mission.calls_cleared])
	_check(not paused, "unpaused and playing")
	await _end_freeplay()


func _test_settings_shape_the_shift_and_survive() -> void:
	_menu.set_shift_minutes(10)
	_check(absf(_director.shift_length - 600.0) < 0.1,
		"a 10-minute shift reaches the director (%.0fs)" % _director.shift_length)
	_menu.set_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.1,
		"the volume slider drives the master bus (%.1f dB)"
		% AudioServer.get_bus_volume_db(0))

	# The next session: wipe the in-memory values and read the file back.
	_menu.shift_minutes = 5
	_menu.master_volume = 1.0
	_menu._load_settings()
	_check(_menu.shift_minutes == 10 and absf(_menu.master_volume - 0.5) < 0.01,
		"settings survive a reload (%d min, %.2f)"
		% [_menu.shift_minutes, _menu.master_volume])

	_menu.set_shift_minutes(5)
	_menu.set_volume(1.0)


func _test_quit_to_title_stands_the_shift_down() -> void:
	await _clear_calls()
	_director.shift_length = 9999.0
	_director.first_call_delay = 999.0
	_director.begin_shift()
	_check(_director.active, "a shift is running to walk out on")
	_menu.open_pause()
	await _idle(2)
	# **`stand_down()`, not `quit_to_title()`.** Since the title became its own scene
	# the full call ends in `change_scene_to_file`, which would tear this district out
	# from under every check that follows -- it did, once, and took three unrelated
	# checks and a script error with it. This is the half that belongs to the district;
	# the half that leaves is a one-line scene change to a constant.
	_menu.stand_down()
	# The suite *is* the SceneTree, so this is its own property rather than a call.
	paused = false
	await _idle(6)
	_check(not paused, "quit-to-title leaves a district that idles on, unpaused")
	_check(not _director.active and not _mission.scoring,
		"with the shift stood down")
	_check(GameMenu.MENU_SCENE == "res://Game/MainMenu.tscn"
			and ResourceLoader.exists(GameMenu.MENU_SCENE),
		"and a main menu on disk to go back to (%s)" % GameMenu.MENU_SCENE)
	_menu.show_title()
	await _idle(2)
	await _press_key(KEY_ENTER)
	_check(not _menu.visible, "and ENTER goes again")
	_reset_mission()



## A shift you walk out on still costs you. Until August 2026 it did not.
func _test_a_bad_shift_cannot_be_quit_away() -> void:
	await _clear_calls()
	var funds_before := _station.funds
	_station.debt = 0
	_car.repair_bill = 0

	# **The exploit, stated.** Money banks on every `earn()`; the score only banks in
	# `end_shift()`; and `repair_bill` lived on the vehicle and was never serialised. So
	# abandoning at 90% kept the takings, dropped the score, escaped the lost-casualty
	# penalty and wiped the damage. Quitting a bad shift beat finishing it.
	_director.shift_length = 9999.0
	_director.first_call_delay = 999.0
	_director.begin_shift()
	_car.repair_bill = 200
	var spot := _director._pick_pavement(true)
	if spot != Vector3.INF:
		_spawn_fire(spot, 0.5)
	await _idle(10)
	var open_before := _board.open_calls().size()
	var failed_before := _mission.calls_failed

	_director.abandon_shift()
	await _idle(8)
	_check(_station.debt >= 200 and _car.repair_bill == 0,
		"walking out sweeps the damage onto the house (£%d owed, £%d on the car)"
		% [_station.debt, _car.repair_bill])
	_check(open_before == 0 or _mission.calls_failed > failed_before,
		"and the calls you left behind are failed, not forgotten (%d from %d, %d open)"
		% [_mission.calls_failed, failed_before, open_before])
	# The debrief already reads `outstanding_repairs()`, so the house figure reaches the
	# player with no interface change at all.
	_check(_station.outstanding_repairs() >= 200,
		"the readout counts what the house is owed (£%d)"
		% _station.outstanding_repairs())

	# Debt comes off the top of earnings -- the sink the career has never had.
	_station.debt = 100
	var purse := _station.funds
	_station.earn(100)
	_check(_station.debt == 0 and _station.funds == purse,
		"earnings pay the debt down before they reach the purse (£%d debt, £%d purse)"
		% [_station.debt, _station.funds])
	_station.earn(100)
	_check(_station.funds == purse + 100,
		"and reach it once the debt is clear (£%d)" % _station.funds)

	# It survives the process, which is the whole point.
	_station.debt = 175
	_station._save_career()
	_station.debt = 0
	_station._load_career()
	_check(_station.debt == 175, "the house account survives a reload (£%d)" % _station.debt)

	_station.debt = 0
	_station.funds = funds_before
	_car.repair_bill = 0
	_station._save_career()
	_reset_mission()


## The settings card's hard reset: fleet dissolved, purse back to the starter
## budget. Destructive by design, which is why it runs dead last.
func _test_reset_career_starts_over() -> void:
	_check(_station.funds != Station.STARTING_FUNDS
			or _station.total(&"patrol") > 0,
		"there is a career to wipe")
	_menu.reset_career()
	await _idle(6)
	_check(_station.funds == Station.STARTING_FUNDS,
		"reset refills the purse to the starter budget (£%d)" % _station.funds)
	_check(_station.total(&"patrol") == 0 and _station.total(&"paramedic") == 0,
		"and takes the fleet off the books")
	var alive := 0
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.service != Unit.Service.NONE:
			alive += 1
	_check(alive == 0, "and off the map (%d left standing)" % alive)


## The shop: a storefront with the portrait and the job description, not a
## fingernail chip on the bar. Opened from the DISPATCH heading, sells through its
## BUY buttons, and swallows the keyboard while it is up.
func _test_the_shop_previews_and_sells() -> void:
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as ShopPanel
	if shop == null:
		_check(false, "the HUD ships a shop")
		return
	var kept_funds := _station.funds
	var kept_owned := _station.owned.duplicate()
	_check(not shop.visible, "the shop ships closed")

	# **The corner buy button is the front door** since August 2026, when the dispatch
	# block gave up the corner and kept only its rows. Clicked through the real interface
	# rather than by calling `open_shop()`, because a button wired to nothing looks
	# identical to a button wired correctly from everywhere except a click.
	var corner_buy := _scene.get_node_or_null("HUD/Root/World/BuyButton") as Button
	if corner_buy == null:
		_check(false, "the corner carries a buy button")
		return
	await _click(MOUSE_BUTTON_LEFT, corner_buy.get_global_rect().get_center())
	_check(shop.visible, "clicking the corner buy button opens the shop")
	# **And it has a picture on it.** The icon is loaded behind an
	# `ResourceLoader.exists()` guard, so a glyph that never imported costs the picture
	# and not the button -- which is the right behaviour and completely invisible. It
	# happened the day the cart was drawn: the SVG was on disk, Godot had not imported it,
	# and the button worked perfectly while showing nothing at all.
	_check(corner_buy.icon != null, "and carries its cart icon")


	# Every card carries the unit's rendered portrait -- the preview is the point.
	var missing := 0
	for id in shop._cards:
		var buy := shop._cards[id]["buy"] as Button
		var portrait := (buy.get_parent() as Node).get_child(0) as TextureRect
		if portrait == null or portrait.texture == null:
			missing += 1
	_check(shop._cards.size() == Station.TYPES.size() and missing == 0,
		"every card shows the unit's rendered portrait (%d missing of %d)"
		% [missing, shop._cards.size()])

	# **And every one of them is reachable.** Reported from play once the doctor and the
	# doctor's car took the catalogue to eight: a single row of cards ran off the side of
	# the screen, and an overflowing container clips rather than wrapping, so the cards past
	# the edge could not be clicked at all. The shop is grouped by service now, which fixes
	# it for eight -- this is what stops the ninth quietly breaking it again.
	#
	# Asserted on the **BUY buttons**, not on the storefront's own rect, because a panel
	# that fits while its contents hang out of it is exactly the shape of the bug. And
	# against the viewport rather than the window: the project stretches canvas items, so
	# the interface is laid out in a 1600x900 space whatever size the window happens to be.
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var unreachable: Array[String] = []
	for id in shop._cards:
		var chip := shop._cards[id]["buy"] as Button
		if not screen.encloses(chip.get_global_rect()):
			unreachable.append(String(id))
	_check(unreachable.is_empty(),
		"and every BUY is on screen and clickable (%d off it%s)"
			% [unreachable.size(),
				"" if unreachable.is_empty() else ": " + ", ".join(unreachable)])
	# **And the cards are grouped by service, which is the point of the layout.** These say
	# something the fit assertions above cannot: those two describe a *symptom*, and would go
	# green again the moment anybody made the cards small enough, grouped or not. Measured
	# against the ungrouped layout all six fire together -- one row of eight comes out
	# **1906 wide** in a 1600 viewport with the paramedic's and the doctor's BUY buttons off
	# the screen entirely, which is precisely the bug reported from play.
	var grouped := 0
	for group: Array in ShopPanel.SHELVES:
		var kind: int = group[0]
		var wanted := 0
		for config: Dictionary in Station.TYPES:
			if int(config.get("service", Unit.Service.NONE)) == kind:
				wanted += 1
		var cards := shop.find_child("Shelf" + str(group[1]), true, false)
		var holder := cards.get_node_or_null("Cards") if cards else null
		var got: int = holder.get_child_count() if holder else -1
		_check(got == wanted,
			"the %s shelf holds its own %d units (got %d)" % [group[1], wanted, got])
		grouped += maxi(got, 0)
	_check(grouped == Station.TYPES.size(),
		"and every unit in the catalogue sits on a shelf (%d of %d)"
			% [grouped, Station.TYPES.size()])

	var storefront := shop.find_child("Storefront", true, false) as Control
	_check(storefront != null and screen.encloses(storefront.get_global_rect()),
		"and the storefront itself fits the viewport (%s in %.0fx%.0f)"
			% ["none" if storefront == null else str(storefront.get_global_rect().size),
				screen.size.x, screen.size.y])

	# Buying through the interface moves real money.
	_station.funds = 10000
	_station.roster_changed.emit()
	await _idle(2)
	var funds_before := _station.funds
	var owned_before := _station.total(&"patrol")
	var buy_button := shop._cards[&"patrol"]["buy"] as Button
	await _click(MOUSE_BUTTON_LEFT, buy_button.get_global_rect().get_center())
	_check(_station.funds == funds_before - _station.price(&"patrol")
			and _station.total(&"patrol") == owned_before + 1,
		"BUY buys (£%d -> £%d)" % [funds_before, _station.funds])

	_station.funds = 10
	_station.roster_changed.emit()
	await _idle(2)
	_check(buy_button.disabled, "an unaffordable card's BUY is disabled")

	# The keyboard has no business reaching the game underneath.
	await _press_key(KEY_F2)
	await _idle(2)
	_check(not _director.active, "F2 does not open a shift under the shop")
	await _press_key(KEY_ESCAPE)
	await _idle(2)
	_check(not shop.visible, "Esc closes it")

	# Books back to canonical -- the bought patrol never materialised on the map.
	_station.funds = kept_funds
	_station.owned = kept_owned
	_station._save_career()
	_station.roster_changed.emit()


## The burning cars a vehicle fire leaves at the kerb -- siblings of the fire in
## the Incidents container, so they are counted by name rather than by parentage.
func _wrecks() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in _incidents.get_children():
		if "Veh" in str(child.name):
			found.append(child as Node3D)
	return found


## The dispatch panel's row for a type, for driving the interface the way a
## player does.
## The dispatch row for a unit type, searched **through** the panel rather than across
## its immediate children.
##
## `DispatchPanel._build_row` parents each row to its inner grid, so the rows are
## grandchildren and a scan of `panel.get_children()` never matched one. This returned
## null every time it was ever called, and the one caller then threw on
## `get_global_rect()` -- which silently abandoned the rest of that check, so the click
## path it was written to cover had never actually been exercised.
## The roster chip standing for a unit of [param id] sitting in the station.
##
## Was a row in the DISPATCH block until August 2026, when that block was hidden and
## sending a unit out moved onto the roster's dimmed standby chips. Same helper name and
## same job -- find the control that dispatches this type -- so the checks that use it
## did not have to change.
func _dispatch_row(id: StringName) -> UnitChip:
	var roster := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/RosterBlock/Body/Roster") as Roster
	if roster == null:
		return null
	# The pool, not the children: chips live inside per-service rows since the roster was
	# grouped, so a walk of the roster's own children now finds three containers.
	for chip in roster._chips:
		if chip.visible and not chip.standby.is_empty() \
				and chip.standby.get("id", &"") == id:
			return chip
	return null


## A fixture unit: dispatched through the station -- the only door units come
## through now -- then stood on a chosen spot.
func _dispatch_to(id: StringName, spot: Vector3) -> Unit:
	var unit := _station.dispatch(id)
	if unit == null:
		push_error("fixture dispatch failed for %s" % id)
		return null
	unit.global_position = spot
	unit.global_rotation = Vector3.ZERO
	unit.mark_spawn()
	return unit


## Buys [param count] of a type, topping the purse up first: tests that use this are
## about dispatch and driving, not affordability, which has its own checks.
## The main menu's picture is dressed at run time, and has to actually be dressed.
##
## `MenuBackdrop` turns a parked tableau into an incident: lightbars and headlights on
## the two emergency vehicles, a line of cones across the police car's nose, a crew out
## and a few onlookers. All of it is placed in code against a scene the user keeps
## editing, so every part of it can silently stop happening -- a renamed vehicle node
## and the lights go, a moved prefab and the cones go. None of that would show on a
## boot, which is clean either way.
##
## Asserted on the **result** rather than on the attempt, which is the lesson of the
## tutorial pre-warm: that one checked a request had been made, was green for weeks,
## and the work behind it failed every time.
func _test_the_menu_backdrop_is_dressed() -> void:
	var menu := (load("res://Game/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	# Deferred dressing, so it lands a frame after the scene is up.
	for i in 12:
		await physics_frame

	var backdrop := menu.get_node_or_null("Backdrop")
	var lit := 0
	for name in ["SM_Veh_Car_Police_01", "SM_Veh_Firetruck_01"]:
		var vehicle := backdrop.get_node_or_null(name) as Node3D if backdrop else null
		if vehicle == null:
			continue
		var beams := vehicle.get_node_or_null("Headlights")
		var bar := vehicle.get_node_or_null("Lightbar")
		# Exactly two each: a surviving run-time builder would double them.
		if beams and beams.get_child_count() == 2 and bar and bar.get_child_count() == 2:
			lit += 1
	_check(lit == 2,
		"both emergency vehicles have headlights and a lightbar (%d of 2)" % lit)

	# **Authored into the scene, so the editor shows them** -- which means this counts
	# lamps hung on the poles themselves rather than on a runtime circuit. It also
	# guards the other half of that move: the run-time builder was deleted when the
	# lights were authored, and had it been left in there would now be two of
	# everything, which renders as a slightly brighter scene and nothing else.
	var poles := backdrop.find_children("SM_Prop_LightPole*", "", true, false) \
		if backdrop else []
	var lamps := 0
	for pole in poles:
		for child in pole.get_children():
			if child is OmniLight3D:
				lamps += 1
	_check(poles.size() > 0 and lamps == poles.size(),
		"every light pole carries exactly one lamp (%d lamps, %d poles)"
		% [lamps, poles.size()])

	var dressing := menu.get_node_or_null("Dressing")
	var cones := 0
	var people := 0
	var animated := 0
	var floating := 0
	for child in dressing.get_children() if dressing else []:
		var here: Vector3 = (child as Node3D).global_position
		# Everything is placed on the ground plane; a cone at head height is a
		# placement bug that only a screenshot would otherwise catch.
		if absf(here.y) > 1.0:
			floating += 1
		# Told apart by what they are, not by what they are called: only the first
		# instance of a scene keeps its name and the rest come back as
		# `@MeshInstance3D@82`, which a name test reads as one cone and eleven people.
		var player := child.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player == null:
			cones += 1
			continue
		people += 1
		# **Animating, not merely present.** The first cut asked for `Idle_Loop`, which
		# the retarget renames to `Idle`, so `has_animation` said no and `_idle`
		# returned quietly -- seven people placed perfectly and every one of them stood
		# in the rig's rest pose. Counting bodies would still have passed.
		if player.current_animation != "":
			animated += 1
	# Five: two officers, two firefighters, and the member of the public one of them is
	# talking to. It was seven until three scattered bystanders were cut for reading as
	# people who had wandered into shot.
	_check(cones >= 5 and people >= 5 and floating == 0,
		"the scene is dressed: %d cones, %d people, %d off the ground"
		% [cones, people, floating])
	_check(people > 0 and animated == people,
		"and every one of them is animating rather than stood in rest pose (%d of %d)"
		% [animated, people])
	menu.free()


## Every character wears the same 43 clips, and must do it by reference.
##
## This is a performance fact with a correctness-shaped guard. `build_character`
## saves the animation library to disk and hands the same in-memory object to all
## eleven scenes -- but `ResourceSaver.save` leaves that object pathless, and
## `PackedScene.pack()` inlines any resource it cannot point at. For months the
## library sat on disk referenced by nothing while every character embedded its own
## 3MB copy: 315ms to parse, eleven times over, which is what made the tutorial take
## five seconds to open and every casualty spawn cost two thirds of a second. The
## fix is one `take_over_path` call, and nothing about the game looks any different
## when it is missing -- it just gets slow again, quietly, on the next rebuild.
## So: the sharing itself is the assertion.
func _test_the_characters_share_one_animation_library() -> void:
	var libraries := {}
	var paths := {}
	var counted := 0
	var directory := DirAccess.open("res://Game/Characters")
	for file in directory.get_files() if directory else PackedStringArray():
		var name := str(file).trim_suffix(".remap")
		if not name.ends_with(".tscn"):
			continue
		var character := (load("res://Game/Characters/" + name)
			as PackedScene).instantiate()
		var player := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player:
			var library := player.get_animation_library("")
			libraries[library.get_instance_id()] = true
			paths[library.resource_path] = true
			counted += 1
		character.free()

	_check(counted >= 11 and libraries.size() == 1,
		"all %d character scenes share one animation library instance (%d distinct)"
		% [counted, libraries.size()])
	# An embedded copy has no path of its own, so this catches the same regression
	# from the other side -- and pins the binary file, which loads in 7ms where the
	# text one took 313ms.
	_check(paths.has("res://Game/Rigs/ual_standard.res"),
		"and it is the one on disk (%s)" % ", ".join(PackedStringArray(paths.keys())))


## The tutorial town, structurally. Runs before the district loads (see _run) and
## frees everything it touched. Headless cannot judge how the town looks -- that is
## the windowed pass -- but it can pin every wiring fact the migration relies on.
func _test_the_tutorial_town_boots() -> void:
	var town := (load("res://Game/Tutorial.tscn") as PackedScene).instantiate()
	root.add_child(town)
	# The navigation map ingests its regions asynchronously -- measured at ~30
	# frames; queries against a half-synced map answer confidently and wrongly.
	for i in 45:
		await physics_frame

	_check(CityGrid.lattice_fits == false,
		"the town switches the lattice machinery off while it is loaded")

	var station := town.get_node_or_null("Station") as Station
	var spawn := Vector3(-47.5, 0.45, 10.0)
	_check(station != null and station.global_position.is_equal_approx(spawn),
		"the station stands on the parking quarter")
	var faced := Basis(Vector3.UP, deg_to_rad(0.0)).z
	_check(station != null and station.global_basis.z.dot(faced) > 0.99,
		"facing out of the quarter toward the street")
	_check(station != null and station.slot_count == 1,
		"with a single dispatch slot on the spot")
	_check(station != null and station.career_path == "user://tutorial-career.cfg",
		"and its own career book -- practice never touches the district's")

	var hospital := town.get_node_or_null("Hospital") as Area3D
	_check(hospital != null and hospital.global_position.is_equal_approx(spawn),
		"the drop-off shares the spawn point, as designed")
	var pad := town.get_node_or_null("Hospital/Pad") as Node3D
	_check(pad != null and not pad.visible,
		"and wears no red pad -- the overlap needs no advertisement")

	for absent in ["Traffic", "Director", "CallSpawner"]:
		_check(town.get_node_or_null(absent) == null,
			"the town ships no %s -- lattice natives stay in the district" % absent)

	# The crowd is not shipped in the scene either -- it is put down at load from
	# the person mesh's own vertices, so nobody ever stands somewhere this town
	# cannot be stood on.
	var crowd := town.get_node_or_null("Crowd")
	var walkers := crowd.get_child_count() if crowd else 0
	_check(walkers >= TutorialMap.CROWD_SIZE,
		"the streets are populated (%d walking)" % walkers)
	var on_mesh := 0
	var off_forecourt := 0
	if crowd:
		for node in crowd.get_children():
			var walker := node as Civilian
			if walker == null:
				continue
			if Unit.can_reach(walker, walker.global_position, 1.5):
				on_mesh += 1
			if _flat_distance(walker.global_position, spawn) \
					>= TutorialMap.CROWD_CLEAR_OF_STATION - 1.0:
				off_forecourt += 1
	_check(walkers > 0 and on_mesh == walkers,
		"every one of them stands where the mesh allows (%d of %d)"
		% [on_mesh, walkers])
	_check(walkers > 0 and off_forecourt == walkers,
		"and clear of the forecourt the vehicles land on (%d of %d)"
		% [off_forecourt, walkers])

	var roads := town.get_node_or_null("VehicleNavigation") as NavigationRegion3D
	var paths := town.get_node_or_null("PersonNavigation") as NavigationRegion3D
	# Bounded on BOTH sides, and the upper bound is the one with a story. The kerbs
	# carving this mesh is half the driving fix, and with that pass off the bake still
	# produced 452 polygons -- a wrong mesh merged over the pavements, not a small one,
	# which a bare `> 100` slept through. But the carve alone then bakes the lifted
	# pavement tops as a second sheet, and *that* read as 695: a bigger number for a
	# worse mesh. The carriageway alone is 117. A count that can only grow is not a
	# measure of a road network.
	var road_polygons := roads.navigation_mesh.get_polygon_count() if roads else 0
	_check(roads != null and road_polygons > 80 and road_polygons < 200,
		"the carriageway mesh is the streets, not the pavements too (%d polygons)"
		% road_polygons)
	# **The property the polygon count cannot see.** Six black-box records of an
	# ambulance shuffling away from a shout were one fault: the lifted pavements baked
	# as their own sheet, a car beside a kerbside casualty snapped onto it, and its way
	# home was on the other one -- `reachable: false`, on a road collider, with nothing
	# in its way. Measured then: four components, two map-spanning and interleaved.
	# So this asks the question the fault asked. Every point a car can actually stand
	# on has to be able to reach the station, or the mesh has somewhere to strand.
	var station_spot := Vector3(-47.5, 0.45, 10.0)
	var road_map := roads.get_navigation_map() if roads else RID()
	var standing := 0
	var stranded := 0
	for x in range(-60, 60, 4):
		for z in range(-60, 40, 4):
			var here := Vector3(float(x), 0.45, float(z))
			var route := NavigationServer3D.map_get_path(road_map, here, station_spot,
				true, 1)
			if route.size() <= 1:
				continue
			# Points out in the gardens snap to the nearest road and would otherwise
			# flatter the count; only samples that really sit on the mesh are asked.
			if Vector2(route[0].x - here.x, route[0].z - here.z).length() > 2.0:
				continue
			standing += 1
			var arrival := route[route.size() - 1]
			if Vector2(arrival.x - station_spot.x,
					arrival.z - station_spot.z).length() > 2.0:
				stranded += 1
	_check(standing > 100 and stranded == 0,
		"and every drivable point on it can reach the station (%d of %d stranded)"
		% [stranded, standing])
	# Flat road furniture must not be solid: a manhole's mesh collider sat exactly
	# where the tutorial's casualty lay and an ambulance ground against it for the
	# whole forty seconds a probe would give it.
	# **Subjects named literally, not read from the constant under test.** Drawing
	# them from TutorialMap.FLAT_FURNITURE made the check self-referential: empty
	# that array and the check reddens on an empty subject list rather than on
	# solid manholes -- a red for the wrong reason, which is worse than a green.
	var flat := 0
	var solid_flat := 0
	for node in _descendants(town.get_node("Map")):
		var furniture := node as StaticBody3D
		if furniture == null:
			continue
		if not str(furniture.get_parent().name).begins_with("SM_Prop_Manhole"):
			continue
		flat += 1
		if furniture.collision_layer != 0:
			solid_flat += 1
	_check(flat > 0 and solid_flat == 0,
		"and the manholes are flat, not walls (%d solid of %d)" % [solid_flat, flat])
	# Tight, not merely non-zero: the walkable ground is pavements *and* gardens
	# and measures 386 polygons. A loose `> 100` bound slept through a rebuild that
	# halved it to 198 by dropping every buried-lawn rule -- measured, in sabotage.
	_check(paths != null and paths.navigation_mesh.get_polygon_count() > 300,
		"and the pavement mesh baked (%d polygons)"
		% (paths.navigation_mesh.get_polygon_count() if paths else 0))
	_check(get_nodes_in_group("road_surface").size() > 200,
		"the runtime stamper marked the road slabs (%d)"
		% get_nodes_in_group("road_surface").size())

	# The proving shout's geography: drivable to within a kerb's width, walkable to
	# the centimetre. This is the check that catches a re-authored town whose roads
	# no longer reach the shout -- and the driveway-islet trap, where the network
	# looked baked but the station's clamp sat on a two-polygon stub of drive.
	var tutor := town.get_node_or_null("TutorialDirector") as TutorialDirector
	_check(tutor != null, "the town carries its scripted director")
	if tutor and station:
		var map: RID = station.get_world_3d().navigation_map
		for spot: Vector3 in [tutor.casualty_spot, tutor.fire_spot]:
			var drive := NavigationServer3D.map_get_path(
				map, station.global_position, spot, true, 1)
			var drive_end := drive[drive.size() - 1] if not drive.is_empty() \
				else Vector3.INF
			_check(not drive.is_empty() and Vector2(drive_end.x - spot.x,
					drive_end.z - spot.z).length() < 8.0,
				"the road network reaches the shout at %s" % spot)
			var walk := NavigationServer3D.map_get_path(
				map, station.global_position, spot, true, 2)
			var walk_end := walk[walk.size() - 1] if not walk.is_empty() \
				else Vector3.INF
			_check(not walk.is_empty() and Vector2(walk_end.x - spot.x,
					walk_end.z - spot.z).length() < 0.5,
				"and the pavements deliver a walker onto it")

	# **The gardens walk.** The town lays grass under everything, so the first two
	# cuts of this mesh either stacked two walkable surfaces (and the navigation map
	# answered nothing at all) or dropped the lawns outright and left a walker
	# confined to the pavements. Measured across a 5m sweep of the whole town: a
	# walker should reach the great majority of it, including the gaps between
	# houses -- and still not the inside of a house.
	if station:
		var map: RID = station.get_world_3d().navigation_map
		var here := station.global_position
		var open := 0
		var sampled := 0
		for x in range(-60, 91, 10):
			for z in range(-95, 56, 10):
				var spot := Vector3(x, 0.45, z)
				sampled += 1
				var walk := NavigationServer3D.map_get_path(map, here, spot, true, 2)
				if walk.is_empty():
					continue
				var end := walk[walk.size() - 1]
				if Vector2(end.x - spot.x, end.z - spot.z).length() < 0.6:
					open += 1
		_check(sampled > 0 and float(open) / float(sampled) > 0.8,
			"a walker reaches the gardens and the gaps between houses (%d of %d)"
			% [open, sampled])
		# The other half of the same rule: grass under a house is not a floor.
		# **The point matters.** The first one chosen sat over a driveway, which is
		# excluded ground for its own reasons -- so it read as blocked whatever the
		# burial rule did, and a sabotage that skipped burial entirely left it
		# green. This one has a house collider and a grass tile overhead and
		# nothing else: measured 5.25m short healthy, 0.00m with burial skipped.
		var indoors := Vector3(-35.0, 0.45, -45.0)
		var into := NavigationServer3D.map_get_path(map, here, indoors, true, 2)
		var stopped := INF
		if not into.is_empty():
			var end := into[into.size() - 1]
			stopped = Vector2(end.x - indoors.x, end.z - indoors.z).length()
		_check(stopped > 2.0,
			"but not through the living rooms (stopped %.1fm short)" % stopped)

	var menu := town.get_node_or_null("HUD/Root/Menu") as GameMenu
	_check(menu != null and menu.in_tutorial,
		"the menu knows it is the tutorial's")

	# The shout comes a job at a time, and the mission is told so -- the scripted
	# win rule reads a clear map as a job done, and a staged shout is clear between
	# its stages.
	var tutor_stage := town.get_node_or_null("TutorialDirector") as TutorialDirector
	var mission := town.get_node_or_null("Mission") as Mission
	_check(tutor_stage != null and tutor_stage._stages().size() == 2,
		"the tutorial opens in two stages")
	_check(mission != null and not mission.more_to_come,
		"and holds nothing back before the player has started")
	if tutor_stage and mission:
		# Shortened before the first stage opens: the breather is set when a stage
		# opens, so lowering it afterwards leaves the old one already counting.
		tutor_stage.between_calls = 0.2
		tutor_stage._open_stage(0)
		await _idle(4)
		var first := get_nodes_in_group(Incident.GROUP).size()
		_check(first == 1, "the first stage opens one job, not two (%d)" % first)
		_check(mission.more_to_come,
			"with the mission told there is more coming")
		# Clear it, and the win must NOT be declared -- this is the trap the flag
		# exists for. The next stage arrives on its own after the breather.
		for node in get_nodes_in_group(Incident.GROUP):
			(node as Incident)._finish(true)
		await _idle(6)
		_check(mission.state == Mission.State.RUNNING,
			"clearing it does not end the tutorial (%d)" % mission.state)
		var second := 0
		for i in 120:
			await physics_frame
			second = get_nodes_in_group(Incident.GROUP).size()
			if second > 0:
				break
		_check(second == 1, "the second stage follows on its own (%d)" % second)
		_check(not mission.more_to_come,
			"and the mission is told it is the last")
		for node in get_nodes_in_group(Incident.GROUP):
			(node as Incident)._finish(true)
		await _idle(6)
		_check(mission.state == Mission.State.WON,
			"clearing the last one wins the shout (%d)" % mission.state)

		# What the player is left looking at. A banner could only say the job was
		# done; the card says what it came to, and takes the mouse until it is
		# dismissed so the district underneath cannot be ordered around behind it.
		var banner := town.get_node_or_null("HUD/Root/World/Banner") as Label
		var card := town.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
		_check(card != null and card.visible and banner != null and not banner.visible,
			"and the modal is what says so, not the banner")
		_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_STOP,
			"it holds the mouse while it is up (filter %d)"
			% (card.mouse_filter if card else -1))
		# The figures reached it -- and are the shout's own, which is the part that
		# `scoring` being off would otherwise have made zero.
		#
		# Redrawn first, deliberately. The automatic card is a snapshot taken the
		# instant the shout was won, and a call's response bonus lands a beat later
		# when the board closes it -- so the number on screen is a moment older than
		# the mission's own. That is right for the player and useless to compare
		# against, and it failed here as 250 against 350 before this line existed.
		# The redraw runs the same show_shout -> shout_rows -> shout_score path.
		card.show_shout(mission)
		var shown := PackedStringArray()
		if card:
			for line in card.get_child(0).get_child(0).get_child(0).get_children():
				for cell in line.get_children():
					var text := cell as Label
					if text:
						shown.append(text.text)
		var joined := " ".join(shown)
		_check("Score" in joined and str(mission.shout_score()) in joined
				and mission.shout_score() > 0,
			"carrying a score the shout actually earned (%d in '%s')"
			% [mission.shout_score(), joined])
		# Dismissing it gives the district back. Pressed rather than hidden directly:
		# the button is the only way a player has, so it is the thing worth testing.
		var dismiss: Button = null
		if card:
			for node in card.get_child(0).get_child(0).get_child(0).get_children():
				if node is Button:
					dismiss = node as Button
		_check(dismiss != null, "the modal offers a way out of itself")
		if dismiss:
			dismiss.pressed.emit()
		await _idle(2)
		_check(card != null and not card.visible
				and card.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"and CONTINUE puts it away and hands the mouse back")

	# **The drive the black box caught**, run for real. Coming home from the shout,
	# an ambulance used to jam against a sidewalk corner whose kerb face stood
	# inside the drivable mesh: full throttle, zero speed, fifteen metres short,
	# escaping and re-approaching for ever. Measured before the fix: never arrived,
	# twelve escapes, 27% of frames going nowhere. After: 12s, no escapes.
	#
	# Driven rather than inspected because the fix is a *bake*, and the geometry
	# checks above cannot tell a right mesh from a wrong one of similar size --
	# proven, by a sabotage that broke the bake and reddened nothing.
	if station:
		var kept_fleet: Dictionary = station.owned.duplicate()
		station.funds = 99999
		station.purchase(&"ambulance")
		var runner := station.dispatch(&"ambulance") as Vehicle
		if runner == null:
			_check(false, "an ambulance to drive home")
		else:
			# Started where an ambulance actually parks: the drivable point nearest
			# the shout, asked of the mesh rather than guessed. Started *on* the
			# pavement instead, the agent reports its path finished before a wheel
			# turns -- the trap written up in Vehicle._drive -- and the order
			# completes on the spot, which reads as a 50m failure that is really a
			# broken fixture.
			var to_shout := NavigationServer3D.map_get_path(
				station.get_world_3d().navigation_map, station.global_position,
				tutor_stage.casualty_spot if tutor_stage else spawn, true, 1)
			var kerb := to_shout[to_shout.size() - 1] if not to_shout.is_empty() \
				else spawn
			runner.global_position = Vector3(kerb.x, 0.45, kerb.z)
			runner.velocity = Vector3.ZERO
			runner.look_at(runner.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
			await _idle(8)
			runner.issue(MoveOrder.new(station.global_position))
			# **Pre-roll before watching.** A freshly dispatched agent has no path
			# on its first frame and reports itself finished, which Vehicle reads as
			# an arrival -- so a watch that starts immediately sees the order end on
			# the spot, 54m from home, and calls the game broken. Measured, from the
			# diagnostic that caught it.
			await _wait(25)
			var short := INF
			for i in 1500:
				await physics_frame
				short = _flat_distance(runner.global_position,
					station.global_position)
				if short < 4.0:
					break
				if not runner.is_navigating() and i > 60:
					break
			_check(short < 4.0,
				"an ambulance drives home from the shout without jamming (%.1fm)"
				% short)
			runner.free()

		# **And from where the player actually leaves it**, which is a different
		# question and the one that was failing. The check above teleports the
		# ambulance onto the drivable point nearest the shout, zeroes its velocity and
		# faces it down +Z -- an ideal start that passed throughout the months the black
		# box was filing records about this drive. Started at a position taken from those
		# records, it drove to within 15m of the station and then oscillated: forward to
		# the same sidewalk corner, dead stop, reverse 7.5m, forward again, for as long
		# as anyone watched. Nothing in front of it and the mesh saying the ground was
		# fine; `climb_escapes` was simply unreachable, because an escape moves the car
		# and movement used to forgive the escape tally.
		station.purchase(&"ambulance")
		var wedged := station.dispatch(&"ambulance") as Vehicle
		if wedged == null:
			_check(false, "a second ambulance for the awkward start")
		else:
			wedged.global_position = Vector3(-21.0, 0.6, -33.0)
			wedged.velocity = Vector3.ZERO
			wedged.rotation = Vector3.ZERO
			await _idle(30)
			wedged.issue(MoveOrder.new(station.global_position))
			await _wait(25)
			var awkward := INF
			for i in 2400:
				await physics_frame
				awkward = _flat_distance(wedged.global_position,
					station.global_position)
				if awkward < 5.0:
					break
			_check(awkward < 5.0,
				"and from the awkward parking the black box recorded (%.1fm)"
				% awkward)
			wedged.free()
		station.owned = kept_fleet
		await _idle(2)

	# The teaching line: a reading of the world, not a script of it. Each prompt is
	# asserted from the state that should produce it, in the order the job happens.
	if tutor_stage and mission and station:
		mission.state = Mission.State.RUNNING
		for node in get_nodes_in_group(Incident.GROUP):
			node.free()
		tutor_stage._opened = false
		await _idle(2)
		_check(tutor_stage._lesson() == "",
			"the tutorial says nothing before the player has started")

		tutor_stage._opened = true
		var lesson := (load("res://Game/Incidents/Casualty.tscn") as PackedScene) \
			.instantiate() as Casualty
		town.get_node("Incidents").add_child(lesson)
		lesson.global_position = tutor_stage.casualty_spot
		var kept_owned: Dictionary = station.owned.duplicate()
		station.owned = {}
		await _idle(4)
		_check(tutor_stage._lesson().contains("CART"),
			"an empty roster is sent to the shop ('%s')" % tutor_stage._lesson())

		# **The words and the glow are one reading.** A prompt naming a unit is thin help
		# when the storefront holds eight cards, so the tutorial also points at the control
		# it is talking about -- and the failure worth catching is not "nothing glows" but
		# "the wrong thing glows", which is why this asserts *which* control it is.
		var spotlight := town.get_node_or_null("HUD/Spotlight") as Spotlight
		var cart := town.get_node_or_null("HUD/Root/World/BuyButton") as Control
		# **Long enough for a teaching tick.** The prompt -- and with it the spotlight --
		# is re-read four times a second, so the four frames that suffice for a direct
		# `_lesson()` call are a sixteenth of what the glow needs.
		await _idle(20)
		_check(spotlight != null and spotlight._targets.size() == 1
				and spotlight._targets[0] == cart,
			"and the cart button is the thing lit up (%d lit)"
			% (spotlight._targets.size() if spotlight else -1))

		# Open the storefront and the target moves from the door to the two cards named.
		var tutor_shop := town.get_node_or_null("HUD/Root/Shop") as ShopPanel
		if tutor_shop:
			tutor_shop.open_shop()
			await _idle(20)
			var lit: Array[StringName] = []
			for id: StringName in [&"ambulance", &"paramedic", &"engine",
					&"firefighter", &"patrol", &"officer"]:
				if spotlight and spotlight._targets.has(tutor_shop.card_button(id)):
					lit.append(id)
			_check(lit.size() == 2 and lit.has(&"ambulance") and lit.has(&"paramedic"),
				"with the shop open it lights the two cards the prompt named (%s)"
				% str(lit))
			tutor_shop.close_shop()
			await _idle(3)

		station.funds = 99999
		station.purchase(&"ambulance")
		station.purchase(&"paramedic")
		_check(tutor_stage._lesson().contains("Send them out"),
			"units on the books but not on the map are sent out ('%s')"
			% tutor_stage._lesson())

		# Bought but parked: the glow follows the words onto the roster chips.
		await _idle(20)
		var tutor_roster := town.get_node_or_null(
			"HUD/Root/Bar/Row/RosterBlock/Body/Roster") as Roster
		var chip := tutor_roster.standby_chip(&"ambulance") if tutor_roster else null
		_check(chip != null and spotlight != null and spotlight._targets.has(chip),
			"and once bought, the standby chip is what is lit")

		var bus := station.dispatch(&"ambulance") as Vehicle
		var medic := station.dispatch(&"paramedic") as Person
		await _idle(4)
		_check(tutor_stage._lesson().contains("treat"),
			"a crew on the map is told to treat ('%s')" % tutor_stage._lesson())

		lesson.treat(1.0)
		_check(tutor_stage._lesson().contains("carry"),
			"a stable casualty is told to be carried ('%s')" % tutor_stage._lesson())
		lesson.take_by_stretcher()
		_check(tutor_stage._lesson().contains("Wheel"),
			"and one on the stretcher, wheeled ('%s')" % tutor_stage._lesson())
		if bus:
			lesson.load_into(bus)
			_check(tutor_stage._lesson().contains("station"),
				"aboard, the lesson is the drive home ('%s')" % tutor_stage._lesson())

		# The fire half, from the same reading.
		lesson.free()
		var blaze := (load("res://Game/Incidents/Fire.tscn") as PackedScene) \
			.instantiate() as Fire
		town.get_node("Incidents").add_child(blaze)
		blaze.global_position = tutor_stage.fire_spot
		await _idle(4)
		_check(tutor_stage._lesson().contains("Fire Engine"),
			"a fire with no engine on the books is sent to the shop ('%s')"
			% tutor_stage._lesson())

		mission.state = Mission.State.WON
		_check(tutor_stage._lesson() == "",
			"and it falls silent once the shout is complete")
		station.owned = kept_owned
		if bus:
			bus.free()
		if medic:
			medic.free()
	# The card must survive the minimap's own _ready, which loads the DISTRICT's
	# photograph: a first-frame call was silently overwritten by it, and the player
	# navigated the tutorial by a picture of the wrong town. Now the town has its
	# own baked photograph, the assertion is that THAT one is up, framed on the
	# town's centre rather than the district's origin.
	var minimap := town.get_node_or_null("HUD/Root/World/MinimapCard/Minimap")
	var shown := ""
	if minimap and minimap._base != null:
		shown = str(minimap._base.resource_path)
	_check(shown.ends_with("TutorialMinimapBase.png")
			and minimap.world_centre.is_equal_approx(TutorialMap.MINIMAP_CENTRE)
			and is_equal_approx(minimap.world_extent, TutorialMap.MINIMAP_EXTENT),
		"the minimap shows this town's own photograph, framed on it ('%s')" % shown)

	town.free()
	await process_frame
	_check(CityGrid.lattice_fits == true,
		"and leaving the town hands the district its lattice back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		"user://tutorial-career.cfg"))


func _buy(id: StringName, count: int) -> void:
	_station.funds += _station.price(id) * count
	for i in count:
		_station.purchase(id)


## Removes a spare unit bought for one test, so the owned fleet stays the canonical
## seven the fixtures established.
func _dissolve(unit: Unit, id: StringName) -> void:
	if unit and is_instance_valid(unit):
		unit.queue_free()
	_station.owned[id] = maxi(0, int(_station.owned.get(id, 0)) - 1)
	_station._save_career()
	_station.roster_changed.emit()


## Parks the whole shift on the station forecourt, well out of ON_SCENE_RADIUS of
## anywhere the director may open a call, so nothing reads as attended by accident.
func _park_the_shift() -> void:
	var index := 0
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit == null or unit.service == Unit.Service.NONE:
			continue
		unit.clear_orders()
		unit.global_position = _station.global_position \
			+ Vector3(4.0 * (index % 4) - 6.0, 0.2, 4.0 * (index / 4))
		unit.velocity = Vector3.ZERO
		index += 1
	await _wait(4)


## Deals with everything at a scene from code -- douse the fire, treat and deliver the
## casualty -- so the pacing tests measure the director, not a drive across town.
func _resolve_call(call: Call) -> void:
	for incident in call.incidents.duplicate():
		if not is_instance_valid(incident):
			continue
		var fire := incident as Fire
		if fire:
			fire.douse(5.0)
			continue
		var casualty := incident as Casualty
		if casualty:
			casualty.treat(1.0)
			casualty.deliver()
			continue
		var suspect := incident as Suspect
		if suspect:
			suspect.detain(1.0)
			suspect.deliver()
			continue
		# A cylinder is made safe by being cold with nothing burning near it, and the
		# fire beside it is dealt with by the Fire branch above -- so all this has to do
		# is take the heat out.
		var hazard := incident as Hazard
		if hazard:
			hazard.cool(2.0)


## Stands the director down and returns the mission to the scripted rules, so the
## tests after these run against the same game the ones before them did.
func _end_freeplay() -> void:
	_director.active = false
	_mission.scoring = false
	await _clear_calls()
	_reset_mission()


# --- Camera ------------------------------------------------------------------

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

## Runs until the car reports its order finished, or gives up. Returns whether it
## arrived, so a stuck car fails loudly instead of hanging the suite.
func _await_orders_done(unit: Unit, timeout_frames: int) -> bool:
	for i in timeout_frames:
		if not unit.has_orders():
			return true
		await physics_frame
	return false


func _await_arrival(timeout_frames: int, trace := false) -> bool:
	for i in timeout_frames:
		if not _car.has_orders():
			return true
		if trace and i % 20 == 0:
			print("    t%04d %s" % [i, _car_state()])
		await physics_frame
	return false


func _place(position: Vector3, yaw := 0.0) -> void:
	await _place_unit(_car, position, yaw)


func _place_unit(unit: Unit, position: Vector3, yaw := 0.0) -> void:
	unit.clear_orders()
	unit.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	unit.velocity = Vector3.ZERO
	await _wait(12)


## Screen-space bounding box of some units, as [top_left, bottom_right].
func _screen_bounds(units: Array[Vehicle]) -> Array:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for unit in units:
		var point := _screen_of(unit.global_position)
		low.x = minf(low.x, point.x)
		low.y = minf(low.y, point.y)
		high.x = maxf(high.x, point.x)
		high.y = maxf(high.y, point.y)
	return [low, high]


func _spawn_fire(position: Vector3, intensity: float) -> Fire:
	var fire: Fire = (load("res://Game/Incidents/Fire.tscn") as PackedScene).instantiate()
	_incidents.add_child(fire)
	fire.global_position = position
	fire.intensity = intensity
	return fire


func _spawn_hazard(position: Vector3) -> Hazard:
	var hazard: Hazard = (load("res://Game/Incidents/Hazard.tscn") as PackedScene).instantiate()
	_incidents.add_child(hazard)
	hazard.global_position = position
	return hazard


func _spawn_suspect(position: Vector3) -> Suspect:
	var suspect: Suspect = (load("res://Game/Incidents/Suspect.tscn") as PackedScene).instantiate()
	_incidents.add_child(suspect)
	suspect.global_position = position
	return suspect


func _spawn_casualty(position: Vector3) -> Casualty:
	var casualty: Casualty = (load("res://Game/Incidents/Casualty.tscn") as PackedScene).instantiate()
	_incidents.add_child(casualty)
	casualty.global_position = position
	return casualty


## Fires spread, so a leftover from one test would corrupt the next one's counts.
## Children of one of the map's ambient containers.
func _ambient(node_name: String) -> Array:
	var holder := _scene.get_node_or_null(node_name)
	return holder.get_children() if holder else []


func _first_civilian() -> Civilian:
	var crowd := _civilians()
	return crowd[0] if not crowd.is_empty() else null


func _civilians() -> Array[Civilian]:
	var found: Array[Civilian] = []
	for node in _ambient("Crowd"):
		var civilian := node as Civilian
		if civilian:
			found.append(civilian)
	return found


## Empties the district of everyone who is not the player's. See the note in _run.
func _clear_ambient() -> void:
	for holder_name in ["Crowd", "Traffic"]:
		for node in _ambient(str(holder_name)):
			node.queue_free()
	await _wait(4)


## Stops every player unit starting work on its own, and lets them again.
##
## For checks that need an incident left alone. Auto-engage is deliberately on by default,
## so a test that wants "nobody touches this" has to say so.
func _stand_down() -> void:
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit:
			unit.auto_engage = false


func _stand_to() -> void:
	for node in get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit:
			unit.auto_engage = true


func _clear_incidents() -> void:
	_officer.clear_orders()
	for node in get_nodes_in_group(Incident.GROUP):
		node.queue_free()
	await _wait(4)


func _reset_mission() -> void:
	# Through `_set_state` rather than by assignment, because a scripted win now raises
	# a **modal** card that holds the mouse until it is dismissed -- and a bare
	# assignment moves the state without telling the HUD, leaving that card standing
	# over the district. It cost seven click checks their targets the first time, none
	# of them anywhere near the mission tests that caused it.
	_mission._set_state(Mission.State.RUNNING)
	_mission.fires_out = 0
	_mission.casualties_saved = 0
	_mission.casualties_lost = 0
	_mission.scoring = false
	_mission.score = 0
	_mission.calls_cleared = 0
	_mission.calls_failed = 0
	# **The house account, or it follows the suite around.** Every shift exit now sweeps
	# outstanding repair bills onto `Station.debt`, and a residual bill from one of the
	# driving checks would otherwise ride along and fail an affordability check a long way
	# from its cause -- the kind of failure nobody traces back.
	_station.debt = 0
	_mission.crew_lost = 0
	_mission.crew_recovered = 0
	_mission.lanes_cleared = 0


func _target_for(incident: Incident) -> Target:
	var target := Target.new()
	target.position = incident.global_position
	target.collider = incident
	target.incident = incident
	return target


func _find_ability(unit: Unit, id: StringName) -> Ability:
	for ability in unit.abilities():
		if ability.id() == id:
			return ability
	return null


## Puts the car in the middle of the view so unproject_position stays on screen.
func _focus_camera_on_car() -> void:
	_camera.focus = Vector3(_car.global_position.x, 0.0, _car.global_position.z)
	_camera._apply_transform()


func _screen_of(world_position: Vector3) -> Vector2:
	return _camera.unproject_position(world_position)


func _press_key(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		root.push_input(event)
		await _idle(2)


## Clears a debrief modal out of the way before a synthesised click, the way a player
## would with the CONTINUE button.
##
## Winning a scripted shout now raises a card that **holds the mouse** until it is
## dismissed, and `_evaluate` declares that win whenever the last incident resolves
## outside a scored shift -- which is most of this suite. So a fire doused in a radio
## test left a modal standing over the district, and the next four click checks missed
## targets they were nowhere near responsible for. Dismissed here rather than in each
## test: no click check is about the modal, and the modal's own behaviour is asserted
## where it belongs, on the tutorial's finished shout.
func _dismiss_any_modal() -> void:
	var card := _scene.get_node_or_null("HUD/Root/World/DebriefCard") as DebriefCard
	if card and card.visible:
		card.hide_card()


func _click(button: int, screen_position: Vector2, shift := false) -> void:
	_dismiss_any_modal()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = screen_position
		event.global_position = screen_position
		root.push_input(event)
		await _idle(2)


## Press, move, release: a left-drag, which the controller reads as a box select.
func _drag(from: Vector2, to: Vector2) -> void:
	_dismiss_any_modal()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	root.push_input(press)
	await _idle(2)

	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	root.push_input(motion)
	await _idle(2)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	root.push_input(release)
	await _idle(2)


func _car_state() -> String:
	var agent := _car.get_node("NavigationAgent") as NavigationAgent3D
	var next := agent.get_next_path_position()
	return "pos=(%.1f, %.2f, %.1f) speed=%.1f floor=%s target=(%.1f, %.1f) next=(%.1f, %.1f) reach=%s pathlen=%d fin=%s" % [
		_car.global_position.x, _car.global_position.y, _car.global_position.z,
		_car.forward_speed, _car.is_on_floor(),
		_car.move_target.x, _car.move_target.z,
		next.x, next.z,
		agent.is_target_reachable(),
		agent.get_current_navigation_path().size(),
		agent.is_navigation_finished(),
	]


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True if a point lies in one of the map's road bands. A point is on a road if
## *either* axis falls in a band -- that is what makes a junction a junction.
##
## Station and hospital forecourts are drivable too and are not bands, so this is a
## sufficient test for "on the street", not a complete one for "drivable".
func _on_a_road(point: Vector3) -> bool:
	return _in_band_x(point.x) or _in_band_z(point.z)



func _in_band_x(value: float) -> bool:
	return absf(value - CityGrid.band_centre_x(CityGrid.band_at_x(value))) \
		<= BAND_WIDTH * 0.5


func _in_band_z(value: float) -> bool:
	return absf(value - CityGrid.band_centre_z(CityGrid.band_at_z(value))) \
		<= BAND_WIDTH * 0.5


func _settle(frames: int) -> void:
	await _wait(frames)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## Yields on idle frames. Synthetic input must be pushed from here, not from inside
## a physics step.
func _idle(frames: int) -> void:
	for i in frames:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", description)
	else:
		print("  FAIL  ", description)
		_failures += 1


## The summary carries its own total, so nothing downstream has to count `ok` lines to
## find out how big the suite is. Both forms keep the exact substrings the Stop hook
## and the reporting agents grep for -- "all checks passed" and "check(s) failed" --
## so the count is additive rather than a format change.
func _finish() -> void:
	if _failures == 0:
		print("\nall checks passed (%d)" % _checks)
		quit(0)
	else:
		print("\n%d check(s) failed of %d" % [_failures, _checks])
		quit(1)
