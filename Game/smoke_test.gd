extends "res://Game/Tests/Camera.gd"

## Headless behaviour test for the RTS playground. Physics runs for real without a
## renderer, so this exercises the actual autopilot and picking code.
##
##   godot --headless --path . --script res://Game/smoke_test.gd
##
## Exits non-zero if any check fails.
##
## **The checks themselves live in `Game/Tests/`.** This file is the run order and
## nothing else; the fixture and every helper are in `Tests/TestCase.gd`, and each
## section is a link in a plain script-inheritance chain ending here -- which is what
## let the split be a pure move, with one `self`, one set of fixture fields, and not
## one test body rewritten.


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
	_roster = scene.get_node_or_null("HUD/Root/Bar/Row/RosterBlock/Body/Roster") as RosterSidebar
	# **Asked of the panel that has it, not of its authored path.** The grid is written
	# into `CommandBlock` so `HUD.gd` can reach it with `$`, and re-homed into the
	# selection panel at startup -- so the authored path resolves to nothing at runtime,
	# and resolving it that way silently gave the whole suite a null grid.
	var selection := scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	_grid = selection.command_grid() if selection else null
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
	await _test_panic_stays_on_the_pavement()
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
	await _test_the_bar_answers_the_selection_at_once()
	await _test_the_order_bar_fills_as_the_job_is_done()
	await _test_hud_panels_hold_their_corners()
	await _test_bar_does_not_swallow_world_clicks()
	await _test_command_grid_follows_the_selection()
	await _test_command_hotkeys_run_abilities()
	await _test_the_selection_panel_shows_who_is_aboard()
	await _test_the_bar_can_buy_and_send_units()
	await _test_no_unit_offers_two_verbs_on_one_key()
	await _test_every_command_symbol_resolves()
	await _test_roster_lists_everything_under_command()
	await _test_the_roster_groups_by_service()
	await _test_the_roster_shows_a_hurt_crew_member()
	await _test_roster_marks_the_selection()
	await _test_the_roster_says_what_a_unit_is_doing()
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
	await _test_the_board_triages_casualties()
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
	await _test_a_held_prop_sits_in_the_hand()
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
	await _test_armed_response_disarms_before_anyone_arrests()
	await _test_every_call_gate_has_a_caption()
	await _test_a_doctor_cannot_run_the_stretcher()
	await _test_an_officer_can_board_a_landed_helicopter()
	await _test_the_air_ambulance_is_a_second_stretcher()
	await _test_no_two_purchasable_units_are_the_same_unit()
	await _test_a_career_with_no_truck_gets_no_wreck()
	await _test_a_collision_reads_as_a_road_job_to_the_end()
	await _test_a_collision_leaves_a_wreck_for_the_truck()
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
	await _test_a_fire_burns_what_stands_in_it()
	await _test_a_spreading_fire_catches_an_onlooker()
	await _test_only_prisoner_carriers_have_cells()
	await _test_the_rescue_helicopter_wears_the_rescue_livery()
	await _test_every_emergency_vehicle_is_purchasable()
	await _test_every_responding_vehicle_has_a_lightbar()
	await _test_the_helicopter_flies_and_lands_on_open_ground()
	await _test_an_appliance_can_work_off_a_hydrant()
	await _test_the_fire_service_fights_fires()
	await _test_building_fires_wait_for_a_fire_service()
	await _test_the_appliance_runs_on_water()
	await _test_the_district_makes_a_noise()
	await _test_the_interface_clicks()
	await _test_the_display_setting_is_headless_safe()
	await _test_the_call_rate_is_a_setting()
	await _test_the_hour_is_a_setting()
	await _test_the_shift_rolls_its_own_weather()
	await _test_wet_weather_loads_the_table_with_collisions()
	await _test_vehicles_light_up_after_dark()
	await _test_a_rescue_needs_every_service()
	await _test_a_park_collapse_is_out_of_reach_of_the_road()
	await _test_arson_is_a_fire_and_an_arrest()
	await _test_an_affray_puts_a_casualty_inside_the_cordon()
	await _test_a_pile_up_waits_for_a_recovery_truck()
	await _test_a_spill_shuts_the_road_around_a_hazard()
	await _test_an_armed_robbery_needs_the_arv_and_a_paramedic()
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
	await _test_every_menu_card_fits_the_screen()
	await _test_settings_back_returns_where_it_came_from()
	await _test_reset_career_asks_first()
	await _test_quit_to_title_stands_the_shift_down()
	await _test_a_bad_shift_cannot_be_quit_away()
	await _test_a_scenario_plays_its_timeline()
	await _test_a_lost_scenario_offers_another_go()
	await _test_camera_pan_and_zoom()
	await _test_respawn()
	# Dead last, deliberately: it wipes the fleet the whole suite ran on.
	await _test_reset_career_starts_over()

	_finish()
