extends "res://Game/Tests/Multiselection.gd"

## Interface -- 15 checks-worth of behaviour, moved verbatim out of the
## single 13,000-line suite in August 2026. One link in a chain of scripts that
## ends at `smoke_test.gd`, so every fixture field and helper is inherited and no
## test body changed a character.


## The layout invariant that replaced the six checks describing a docked bar.
##
## Each of those six named the neighbours it compared, so a renamed panel made them pass
## on an empty comparison. This asks the same questions of *every* panel at once, off a
## table resolved by path -- so a rename fails loudly here instead, which is the honest
## cost of asserting on a layout at all.

## The selection panel says who is aboard a vehicle.
##
## **The readout the bar never had.** A patrol car with two officers in it and an empty one
## looked identical from outside, and a van's six cells said nothing about who was in the
## back — so "where is everybody" was a question the interface could not answer and the
## player had to hold in their head.
##
## Driven through `resolve()` and the boarding order rather than `take_aboard()`, because a
## panel that reports what the *model* was told directly proves nothing about the path a
## player actually uses.

## How many cards on the fleet strip are showing a repair bill instead of a seat count.
func _cards_showing_money(panel: SelectionPanel) -> int:
	var strip := panel.roster_strip()
	if strip == null:
		return 0
	var owing := 0
	for node in strip.find_children("*", "Label", true, false):
		if "£" in (node as Label).text:
			owing += 1
	return owing



## The bar can spend money and put units on the map, without the sidebar.
##
## **These are the only two things the roster sidebar did that nothing else does.** It
## carried the sole door into the shop, and the sole way to send a bought unit out of the
## station -- so retiring it without these would leave a career unable to spend its money
## or to get anything onto the map at all.
func _test_the_bar_can_buy_and_send_units() -> void:
	await _clear_calls()
	var panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	if panel == null:
		_check(false, "the HUD carries a selection panel")
		return
	_controller.clear_selection()
	await _idle(16)

	# The shop button, and that it actually opens the shop.
	var buy := panel.request_button()
	_check(buy != null, "the bar carries a REQUEST UNITS button")
	var shop := _scene.get_node_or_null("HUD/Root/Shop") as RequisitionPanel
	if buy and shop:
		_check(not shop.visible, "the shop starts shut")
		buy.pressed.emit()
		await _idle(6)
		_check(shop.visible, "and the button opens it")
		shop.close_shop()
		await _idle(6)

	# A unit bought but not yet sent has a card, and clicking it sends it out.
	_buy(&"patrol", 1)
	var waiting := _station.available(&"patrol")
	_check(waiting > 0, "a bought patrol waits in the station (%d)" % waiting)
	var pol: Button = panel.filter_tabs().get(&"police")
	if pol:
		pol.pressed.emit()
	await _idle(16)

	var standby: UnitInstance = null
	for model: UnitInstance in panel.roster_strip().get("units"):
		if model.status == UnitInstance.Status.OFF_RUN:
			standby = model
	_check(standby != null, "and it shows on the strip as still in the house")
	if standby == null:
		return
	# **The card's own button, not the signal.** Emitting `unit_picked` by hand is what let
	# this ship broken: the handler was fine and the *card* was the problem -- rebuilt six
	# times a second, so a real click pressed a button that had been freed before it was
	# released, and nothing happened. A check that skips the button cannot see that.
	var card: Button = null
	for node in panel.roster_strip().find_children("*", "Button", true, false):
		var button := node as Button
		if button and standby.callsign in button.tooltip_text:
			card = button
	_check(card != null, "the standby card is a button that can be pressed")
	if card == null:
		return
	# Survives a tick: the card must still be the same node after the bar has refreshed,
	# or a click cannot span press and release.
	var was := card.get_instance_id()
	await _idle(20)
	var still: Button = null
	for node in panel.roster_strip().find_children("*", "Button", true, false):
		if (node as Button).get_instance_id() == was:
			still = node as Button
	_check(still != null,
		"and it is still the same button a moment later (%s)"
		% ("yes" if still else "rebuilt underneath the pointer"))

	# **The whole card is the target, not just the gaps between its decorations.**
	# Reported from play: clicking the unit's avatar did nothing. `mouse_filter` does not
	# inherit, and the defaults are not uniform -- a Label is IGNORE and a TextureRect is
	# PASS, but a Panel and a PanelContainer are **STOP**, so the portrait's frame, the
	# status stripe and the condition track each swallowed clicks inside their own
	# rectangle while the card around them worked fine.
	#
	# Asserted on every descendant rather than on the three known offenders, because the
	# bug is the *default*, and the next decoration added to a card arrives carrying it.
	#
	# **The click legs below are not a witness to this**, and that is worth saying so
	# nobody retires this leg as redundant: they fire the card with `pressed.emit()`, which
	# bypasses hit-testing entirely, so they print `8 units, was 7` whether the decoration
	# eats the click or not. Proven, not assumed -- under the sabotage that removes the
	# sweep they were identical to the healthy run. This is the only leg that sees it.
	#
	# "Takes mouse input" rather than "swallows": of the six parts this catches, the
	# TextureRect and the HBox default to PASS, which forwards the click rather than eating
	# it. Flagging them is still right -- the rule is blanket, and a part that merely
	# forwards today is one edit from stopping -- but the wording should not over-claim.
	var greedy := PackedStringArray()
	for node in card.find_children("*", "Control", true, false):
		if (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			greedy.append("%s(%s)" % [node.name, node.get_class()])
	_check(greedy.is_empty(),
		"no part of the card takes mouse input of its own (%s)"
		% ("clear" if greedy.is_empty() else ", ".join(greedy)))
	# **And the sweep stopped at the card.** Catching the Button itself would make every
	# card in the strip inert -- the opposite fault, and one the leg above cannot see.
	_check(card.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"while the card itself still takes one (%d)" % card.mouse_filter)

	var before := _commanded_units().size()
	if still:
		still.pressed.emit()
	await _idle(16)
	_check(_commanded_units().size() == before + 1,
		"clicking its card puts it on the map (%d units, was %d)"
		% [_commanded_units().size(), before])
	_check(_station.available(&"patrol") == waiting - 1,
		"and takes it out of the station (%d, was %d)"
		% [_station.available(&"patrol"), waiting])

	# **Put back.** The unit this check sent out is a real one on a real map, and the
	# fixture's seven is what every later roster check counts against -- leaving an eighth
	# behind reddened three checks in another file.
	var put_back := false
	for node in _commanded_units():
		var extra := node as Unit
		if extra and extra.type_id == &"patrol" and not _cars.has(extra):
			_dissolve(extra, &"patrol")
			put_back = true
			break
	if not put_back:
		# **The purchase comes back even when the dispatch never happened.** `_buy` raises
		# `owned` before anything reaches the map, so a run where the card fails to send
		# the car leaves the fixture an eighth patrol -- and the August 2026 sabotage pass
		# measured the cost: reddening this check reddened three more in two other files,
		# none of them about this behaviour. A check that fails should fail alone.
		_station.owned[&"patrol"] = maxi(0, int(_station.owned.get(&"patrol", 0)) - 1)
		_station._save_career()
		_station.roster_changed.emit()
	await _idle(6)
	await _clear_calls()


func _test_the_selection_panel_shows_who_is_aboard() -> void:
	var panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	if panel == null:
		_check(false, "the HUD carries a selection panel")
		return

	# **The kit's own buttons must still be alive.** They are hidden rather than freed, and
	# the distinction is invisible to every other signal the suite reports: freeing them
	# leaves the kit walking its `_cmd_buttons` dictionary over dead objects, which spends
	# a run emitting six thousand `previously freed instance` errors -- with the suite fully
	# green and the check count unmoved. Measured, not theorised: reinstating the free
	# produced 6,540 of them and zero failures.
	var held := panel.kit_buttons()
	var dead := 0
	for button in held:
		if not is_instance_valid(button):
			dead += 1
	_check(held.size() >= 8 and dead == 0,
		"the kit's own command buttons are hidden, not freed (%d held, %d dead)"
		% [held.size(), dead])

	# **The tiles have to be inside the panel the player is looking at.** The grid is
	# authored into a hidden `CommandBlock` and re-homed here at startup; skip the move and
	# every other check still passes, because they all reach the grid through the panel's
	# accessor rather than caring where it sits. Asserted on parentage, not visibility --
	# `is_visible_in_tree()` reads false headlessly for both the healthy and the broken
	# tree, so it cannot tell them apart and would be a check that proves nothing.
	_check(panel.command_grid() != null
			and panel.is_ancestor_of(panel.command_grid()),
		"the command tiles live inside the selection panel (%s)"
		% (panel.command_grid().get_parent() if panel.command_grid() else "no grid"))

	# **The bar has two states and the frame belongs to both.** Nothing selected shows the
	# fleet strip; a selection shows the unit. The strip has no background of its own -- in
	# the kit's own project the panel drew the frame and the strip sat in a slot inside it
	# -- so hosting it as a sibling and hiding the panel left it floating on the bare map
	# with its labels spilling over the world. It lives inside the frame.
	_controller.clear_selection()
	await _idle(14)
	var strip := panel.roster_strip()
	_check(strip != null and panel.frame() != null
			and panel.frame().is_ancestor_of(strip),
		"the fleet strip sits inside the bar's own frame (%s)"
		% (strip.get_parent() if strip else "no strip"))
	_check(strip != null and strip.visible and panel.frame().visible,
		"with nothing selected it is the strip that shows (strip %s, frame %s)"
		% [strip.visible if strip else false,
			panel.frame().visible if panel.frame() else false])

	# **The service tabs.** Built from `UnitSidebar.FILTERS`, so a service added to the
	# game turns up here without a scene edit -- and they stand down with the strip,
	# because filtering a fleet you are not looking at is a control with nothing to do.
	#
	# **No ALL tab.** The bar shows one service at a time, so something is always selected,
	# and it opens on a service the career actually owns units in -- a fixed default would
	# greet a player who has not bought that one with an empty strip.
	var tabs := panel.filter_tabs()
	_check(not tabs.has(&"all"),
		"the bar has no ALL tab (%s)"
		% ", ".join(PackedStringArray(tabs.keys())))
	_check(tabs.size() == UnitSidebar.FILTERS.size() - 1,
		"one tab per service and no more (%d of %d)"
		% [tabs.size(), UnitSidebar.FILTERS.size() - 1])
	_check(tabs.has(panel.filter_category()),
		"and it opens on one of them (%s)" % panel.filter_category())
	var opened: int = panel.roster_strip().get("units").size() if strip else 0
	_check(opened > 0,
		"showing a service the career actually owns (%d units)" % opened)

	# **A healthy unit must not wear the damaged styling.** The strip shipped its own
	# `condition < 0.35` with no floor, and a negative condition means *this unit has no
	# condition*, not that it is wrecked -- so every aircraft on the strip wore the red
	# alert border while reporting itself AVAILABLE beside it. It is the sentinel bug the
	# roster rows already had once, in a second copy of the rule.
	_buy(&"helicopter", 1)
	var flier := _station.dispatch(&"helicopter") as Aircraft
	if flier:
		await _idle(16)
		var card: UnitInstance = null
		for model: UnitInstance in panel.roster_strip().get("units"):
			if model.callsign == _roster.callsign_for(flier):
				card = model
		_check(card != null, "the helicopter has a card on the strip")
		if card:
			_check(card.condition < 0.0,
				"an aircraft reports no condition at all (%.2f)" % card.condition)
			_check(not card.needs_attention(),
				"and is not drawn as damaged for it (%s)" % card.needs_attention())
			# It gained seats when the carrying contract moved up to Unit; the seat count
			# was still asking a `Vehicle` and reporting 0 of 0.
			_check(card.seats_total() == flier.seats,
				"and its seats are counted (%d of %d)"
				% [card.seats_total(), flier.seats])
		_dissolve(flier, &"helicopter")
		await _idle(6)

	# **A red card says why it is red.** A vehicle's condition on the strip *is* its
	# outstanding repair, and the card used to go red while the only figure on it was a
	# seat count that had not moved -- a border with no explanation, asked about twice
	# before anyone worked out it meant "this one needs paying for".
	# **Looking at the strip while asserting about it.** The bar only refreshes the fleet
	# while the fleet is what it is showing -- so with a unit selected the model updated
	# and the card did not, and the first version of this check read a stale card while
	# `owed` was already right. Two states means asserting in the right one.
	_controller.clear_selection()
	# **And looking at the right tab.** The strip shows one service at a time, so an
	# assertion about a patrol car has to be made with POL up -- the previous block left
	# MED selected, and a police car simply is not on the strip then.
	var pol: Button = panel.filter_tabs().get(&"police")
	if pol:
		pol.pressed.emit()
	await _idle(16)

	# **Counted from a known baseline.** Two earlier versions of this got it wrong: the
	# first scanned the strip for any `£` and found one, because another unit in the
	# fixture had genuinely accrued a £252 bill; the second counted, but `_car` already
	# owed money itself, so setting a bill changed the figure and not the count. Zero it
	# first and the transition is unambiguous.
	_car.repair_bill = 0
	await _idle(16)
	var owing_before := _cards_showing_money(panel)
	_car.repair_bill = 240
	await _idle(16)
	var mine: UnitInstance = null
	for model: UnitInstance in panel.roster_strip().get("units"):
		if model.callsign == _roster.callsign_for(_car):
			mine = model
	_check(mine != null and mine.owed == 240,
		"a damaged car carries its bill to the card (%d)"
		% (mine.owed if mine else -1))
	# **This witnesses `condition_of`, not the bill plumbing, and sits in the middle of
	# three money legs that do.** It reads `condition` -- which a Vehicle derives from
	# `repair_bill` via BILL_SCALE -- and never reads `owed`, so zeroing `instance.owed`
	# leaves it correctly true: the car really is damaged and really should be flagged,
	# even while the figure beside it has stopped arriving. It printed `(true)` in all six
	# runs of the August 2026 sabotage batch and no cycle moved it. Not a defect, but do
	# not count it as a second witness for the two legs either side of it; reddening it
	# needs `condition_of` or `BILL_SCALE` broken.
	_check(mine != null and mine.needs_attention(),
		"and is drawn as needing attention (%s)"
		% (mine.needs_attention() if mine else false))
	var owing_while_owed := _cards_showing_money(panel)
	_check(owing_while_owed == owing_before + 1,
		"one more card prints money rather than a seat count (%d, was %d)"
		% [owing_while_owed, owing_before])

	# And a unit with no seats says nothing rather than "0/0", which reads as a fault.
	var zeroes := 0
	for node in panel.roster_strip().find_children("*", "Label", true, false):
		if (node as Label).text == "0/0":
			zeroes += 1
	_check(zeroes == 0, "and nobody is labelled 0/0 (%d)" % zeroes)

	# Paid off rather than put back to what it was: `billed` is damage this car had already
	# taken from earlier checks, and restoring it would reintroduce the very bill the
	# assertion is about. A repaired car is also the tidier state to hand to what runs next.
	_car.repair_bill = 0
	await _idle(16)
	# **Both ends of the transition, in one claim.** This asserted only that the count was
	# back to `owing_before` -- which is `0 == 0` when the bill never reached the card in
	# the first place. Under the sabotage that zeroed `instance.owed` it printed
	# `(0, was 0)` in the healthy tree, the broken tree and the restore alike: green in
	# every possible world, and therefore evidence about none of them. Requiring the count
	# to have *risen* first is what excludes the never-showed-money satisfier.
	_check(owing_while_owed > owing_before
			and _cards_showing_money(panel) == owing_before,
		"and it goes back to seats once the bill is paid (%d, up from %d, was %d)"
		% [_cards_showing_money(panel), owing_while_owed, owing_before])

	# Switching has to change *what* is on the strip, not merely the highlight -- so both
	# services are asked for and each is checked for strays from the other.
	for want: StringName in [&"police", &"medical"]:
		var tab: Button = tabs.get(want)
		if tab == null:
			continue
		tab.pressed.emit()
		await _idle(14)
		_check(panel.filter_category() == want,
			"pressing %s selects it (%s)" % [want, panel.filter_category()])
		var stray := PackedStringArray()
		for model: UnitInstance in panel.roster_strip().get("units"):
			if model.def and model.def.category != want:
				stray.append(model.callsign)
		_check(stray.is_empty(),
			"and only %s units are on the strip (%s)"
			% [want, "clean" if stray.is_empty() else ", ".join(stray)])

	_controller.select([_car])
	await _idle(14)
	_check(strip == null or not strip.visible,
		"selecting a unit swaps the strip out (%s)"
		% (strip.visible if strip else "no strip"))
	_check(panel.frame() != null and panel.frame().visible,
		"and the frame stays either way")

	# **One height, both states.** The dock sized itself to whichever content was showing,
	# so it jumped every time a unit was selected or dropped.
	var tall_detail := panel.size.y
	_controller.clear_selection()
	await _idle(16)
	var tall_fleet := panel.size.y
	_check(is_equal_approx(tall_detail, tall_fleet),
		"the bar is the same height with a unit selected and without (%.0f vs %.0f)"
		% [tall_detail, tall_fleet])
	_controller.select([_car])
	await _idle(14)
	_check(panel.shown_units().size() == 1 and panel.shown_units()[0] == _car,
		"selecting a car puts it on the panel (%d shown)" % panel.shown_units().size())

	# **Nothing is cut off the bottom.** Reported from play twice. The dock was pinned at a
	# hand-picked height with `clip_contents` on, which does not make content fit -- it
	# hides the part that does not, so 65px including half the portrait and the whole
	# HEALTH row was simply gone on screen while every measurement in this suite read the
	# pinned number and looked correct. The dock sizes itself from the panel now, and this
	# is the assertion that says so.
	var needs := panel.content_height()
	var got := panel.size.y
	_check(needs > 0.0 and got + 0.5 >= needs,
		"the dock is tall enough for what is in it (%.0fpx for %.0fpx of content)"
		% [got, needs])
	# **The top edge, not only the bottom.** The bottom is a *pinned quantity*: the dock is
	# bottom-anchored and `_fit_to_content` only ever writes `offset_top`, so the bottom
	# sits at viewport-height minus BOTTOM_MARGIN by construction. It printed `878 of 900`
	# through five runs across two different height sabotages -- identical every time,
	# because no fault in the sizing code *can* move it. Only a hand-authored anchor
	# mistake in HUD.tscn could, which is not what this check is here for. The top edge is
	# the one the sizing code pushes off the screen when the dock grows too tall, so the
	# claim is the whole rect.
	var rect := panel.get_global_rect()
	var screen := float(_scene.get_viewport().get_visible_rect().size.y)
	_check(rect.end.y <= screen and rect.position.y >= 0.0,
		"and the whole dock is on the screen (%.0f to %.0f of %.0f)"
		% [rect.position.y, rect.end.y, screen])
	# The callsign is the roster's, not a second tally -- the same engine must not be P01
	# in one corner of the screen and P03 in another.
	_check(panel.callsign_of(_car) == _roster.callsign_for(_car),
		"and wears the roster's callsign ('%s' vs '%s')"
		% [panel.callsign_of(_car), _roster.callsign_for(_car)])

	var empty := panel.occupancy_of(_car)
	_check(empty.is_empty(),
		"an empty car shows nobody aboard (%s)" % str(empty))

	# Aboard through the ladder: the officer is asked what a right-click on the car means.
	await _place_unit(_officer, _car.global_position + Vector3(2.5, 0.0, 0.0))
	var target := Target.new()
	target.position = _car.global_position
	target.unit = _car
	_check(_resolved_id(_officer, target) == &"board",
		"an officer beside it is offered Board (%s)" % _resolved_id(_officer, target))
	_officer.issue(_officer.resolve(target).make_order(_officer, target))
	var aboard := false
	for i in 600:
		await physics_frame
		if _car.crew.has(_officer):
			aboard = true
			break
	_check(aboard, "and gets in (%d aboard)" % _car.crew.size())

	await _idle(12)
	var filled := panel.occupancy_of(_car)
	_check(filled.size() == 1 and filled.has(&"officer"),
		"the panel shows one seat filled, by an officer (%s)" % str(filled))

	# **The seat is a button.** Clicking an occupant on the bar puts that one person out
	# and leaves the rest aboard -- so the pip has to know *which* rider it stands for,
	# which the kit's list of role names cannot say on its own.
	var pips := panel.seat_pips()
	_check(pips.size() >= 2, "the bar draws a pip per seat (%d)" % pips.size())
	var seat := pips[0] as Control if not pips.is_empty() else null
	if seat:
		# **The tooltip, not the mouse filter.** Asserting `MOUSE_FILTER_STOP` proves
		# nothing: it is 0, which is a bare `Panel`'s default, so that check passed
		# whether or not the seats had been wired at all. The rider's name can only be
		# on the pip if the wiring found which person that seat stands for.
		_check(_officer.display_name in seat.tooltip_text,
			"and the seat knows whose it is ('%s')" % seat.tooltip_text)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		seat.gui_input.emit(click)
		await _idle(12)
		_check(not _car.crew.has(_officer),
			"clicking it sends that officer out (%d aboard)" % _car.crew.size())
		_check(panel.occupancy_of(_car).is_empty(),
			"and the seat empties on the bar (%s)" % str(panel.occupancy_of(_car)))

	_car.unload()
	await _idle(12)
	_check(panel.occupancy_of(_car).is_empty(),
		"and empties again when they get out (%s)" % str(panel.occupancy_of(_car)))

	# **The vehicle is drawn larger inside the same tile.** Asked for as "2x the size":
	# the tile does not change, the crop does, so the same avatar shows a smaller piece of
	# a bigger picture. Both halves asserted, because the cap is the interesting one --
	# measured across the renders, a car has 33% of dead border to give and a helicopter
	# has 12%, so a flat half-frame crop would have sliced its rotors off and beheaded
	# every character portrait, which fill their frames edge to edge.
	var car_art := load("res://Game/UI/Portraits/SM_Veh_Car_Police_01.png") as Texture2D
	var car_crop := SelectionPanel._cropped(car_art) as AtlasTexture
	# **A floor, not an equality.** The crop is capped by each picture's own dead border,
	# and the runtime measurement runs on a *decompressed* copy whose artefacts loosen the
	# subject box slightly -- so the exact figure moves with the import settings while the
	# thing being asserted, "a car is drawn at least twice as large in the same tile",
	# does not.
	var zoom: float = (car_art.get_size().x / car_crop.region.size.x) if car_crop else 1.0
	_check(car_crop != null and zoom >= 2.0,
		"a car portrait is cropped to at least twice the size (x%.2f)" % zoom)
	# **Paired with the positive, or it is inert.** Asserting only "not an AtlasTexture" is
	# satisfied by a `_cropped` that does nothing whatsoever -- which is the likely failure
	# direction, and it stayed green under exactly that sabotage while the leg above went
	# red. It has to say that *this* picture was left alone **while the car's was not**, or
	# it is a claim about cropping that survives cropping being switched off.
	var face := load("res://Game/UI/Portraits/Character_Male_Police.png") as Texture2D
	var face_crop := SelectionPanel._cropped(face)
	_check(face_crop == face and car_crop != null,
		"and a portrait with no border to spare is left alone (face kept %s, car cropped %s)"
		% [face_crop == face, car_crop != null])

	# **Every catalogue portrait resolves, and nobody is wearing somebody else's face.**
	# The paramedic pointed at `Character_Female_Police` for months after their own render
	# started shipping -- a leftover from when the crew genuinely were repainted police --
	# so the roster, the shop and the bar all drew an officer where a paramedic belonged.
	# A missing file is loud; a plausible wrong one is silent, which is why the second leg
	# names the unit rather than just counting.
	var missing := PackedStringArray()
	var borrowed := PackedStringArray()
	var seen := {}
	for config: Dictionary in Station.TYPES:
		if not config.has("portrait"):
			continue
		var art := String(config["portrait"])
		if not ResourceLoader.exists("res://Game/UI/Portraits/%s.png" % art):
			missing.append(art)
		if seen.has(art):
			borrowed.append("%s and %s share %s" % [seen[art], config["id"], art])
		seen[art] = config["id"]
	_check(seen.size() >= 12,
		"%d catalogue portraits were read" % seen.size())
	_check(missing.is_empty(),
		"and every one of them is a file that exists (%s)"
		% ("all present" if missing.is_empty() else ", ".join(missing)))
	_check(borrowed.is_empty(),
		"and no two units wear the same face (%s)"
		% ("all distinct" if borrowed.is_empty() else "; ".join(borrowed)))

	# **The leg that actually catches the paramedic bug.** The two above do not, and I
	# checked rather than assumed: before the fix the paramedic pointed at
	# `Character_Female_Police`, which is a real file and was used by nobody else, so both
	# "it exists" and "no two share" passed on the broken data.
	#
	# The rule that does catch it: a person built from `Paramedic.tscn` must use
	# `Paramedic.png` if such a render exists. Scenes with no same-named portrait are
	# exempt -- an officer comes from `Person.tscn`, and there is no `Person.png`.
	var borrowed_face := PackedStringArray()
	var matched := 0
	for config: Dictionary in Station.TYPES:
		if bool(config.get("vehicle", false)) or not config.has("portrait"):
			continue
		var own := String(config["scene"]).get_file().trim_suffix(".tscn")
		if not ResourceLoader.exists("res://Game/UI/Portraits/%s.png" % own):
			continue
		matched += 1
		if String(config["portrait"]) != own:
			borrowed_face.append("%s wears %s, not %s"
				% [config["id"], config["portrait"], own])
	_check(matched >= 3,
		"%d units have a render named after their own scene" % matched)
	_check(borrowed_face.is_empty(),
		"and each of them wears it (%s)"
		% ("all their own" if borrowed_face.is_empty() else "; ".join(borrowed_face)))

	# **The water reads in litres a firefighter would recognise.** `tank_capacity` is a
	# multiplier rather than a volume, so the panel needs a scale to turn it into a number
	# -- and the first scale printed **36,000 L** on a pump, a tanker's worth. A units
	# error is invisible to arithmetic: every sum is self-consistent at any scale, so the
	# only thing that catches it is a check that knows what an appliance actually carries.
	_buy(&"engine", 1)
	var appliance := _station.dispatch(&"engine") as Vehicle
	if appliance:
		_controller.select([appliance])
		await _idle(12)
		var litres := panel.litres_of(appliance)
		_check(litres >= 1000 and litres <= 3000,
			"a full appliance reads as a pump, not a tanker (%d L)" % litres)
		_dissolve(appliance, &"engine")
		await _idle(4)
	_controller.clear_selection()
	await _idle(4)


## The CURRENT ORDER bar reports the job, not a decoration.
##
## **The bar had no witness at all until this check.** It drew a hardcoded `0.62` and
## printed the string "62%" beside it for any unit that happened to read EN ROUTE -- a bar
## that looked alive on screen, never moved, and said the same thing about every journey
## in the game. Nothing in the suite could tell that from a working one, because nothing
## in the suite looked at it.
##
## Driven through `resolve()` and a real order rather than by setting `progress` on the
## instance, because the point is the whole chain: the order measures itself,
## [method SelectionPanel._instance_for] copies that onto the [UnitInstance], and the kit
## scene draws it. A check that filled in the middle of that would prove the last link and
## vouch for the two that actually broke.
func _test_the_order_bar_fills_as_the_job_is_done() -> void:
	await _clear_incidents()
	await _clear_cordons()
	var panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	if panel == null:
		_check(false, "the HUD carries a selection panel")
		return

	# **A cordon, because it is the case the bar was rebuilt for.** SecureOrder is the one
	# order that measures itself against a fixed duration, so it is the only one whose
	# fill can be predicted rather than merely watched.
	var ability := _find_ability(_officer, &"secure")
	if ability == null:
		_check(false, "the officer offers Secure")
		return
	var spot := Vector3(24.0, 0.0, 14.0)
	var target := Target.new()
	target.position = spot
	await _place_unit(_officer, Vector3(26.0, 0.1, 14.0))
	_controller.select([_officer])
	_controller.activate(ability)
	_controller._fire_armed(target)
	if not _officer.has_orders():
		_check(false, "clicking the ground issued a Secure order")
		await _clear_cordons()
		return

	# Walk the officer to the spot first: SecureOrder only spends time once it has
	# arrived, so reading the fill mid-walk measures the approach, not the cordon.
	var working := false
	for i in 1500:
		await physics_frame
		var walking := _officer.current_order() as SecureOrder
		if walking and walking.progress() > 0.0:
			working = true
			break
	_check(working, "the officer walks over and starts setting it out")

	var order := _officer.current_order() as SecureOrder
	if order == null:
		_check(false, "the Secure order is still the one in hand")
		await _clear_cordons()
		return

	# **Let the job get properly under way before comparing anything.** The first cut read
	# the bar at 0.02 done and asserted it matched the order to within 0.08 -- which a bar
	# stuck at zero passes without ever moving, and it did: that leg printed
	# `bar 0.00, order 0.02` and called it agreement while the track was not up at all.
	# A third of the way through, "stuck at empty" and "drawing the figure" are finally
	# two different answers.
	var under_way := false
	for i in 600:
		await physics_frame
		if order.progress() >= 0.30:
			under_way = true
			break
	_check(under_way, "and the cordon gets properly under way (%.2f)" % order.progress())
	_check(order.progress() < 0.9,
		"with the job still in hand to be read (%.2f)" % order.progress())

	# **The panel is drawing that figure, not one of its own.**
	#
	# Read after the loop above rather than after `await _idle(2)`: SelectionPanel
	# refreshes on a 0.12s TICK, not every frame, so two frames samples the bar as it was
	# *before* the order existed. That is what the first run reported -- `shown = false`
	# while the cordon was going out, then a stale "18%" after the orders were cleared,
	# the whole readout lagging one tick and looking, at a glance, like an inverted bar.
	var drawn: Dictionary = panel.order_readout()
	var fill := float(drawn.get("fill", -1.0))
	_check(drawn.get("shown", false), "the bar's track is up while there is a job")
	_check(fill > 0.15, "and the bar is not sitting at empty (%.2f)" % fill)
	# 0.12 of slack: one tick is 0.12s against SecureOrder's 3.0s DURATION, so the bar can
	# honestly sit 4% behind the order. Still nowhere near room for a constant -- the
	# hardcoded 0.62 this replaced fails against a cordon a third of the way out.
	_check(absf(fill - order.progress()) < 0.12,
		"drawing the order's own figure (bar %.2f, order %.2f)"
		% [fill, order.progress()])
	# **This leg is self-consistency only, and that is worth stating.** It compares the
	# caption to the fill the same scene just drew, so it catches a formatting divergence
	# and *cannot* see a wrong figure: under the sabotage that reinstated the hardcoded
	# 0.62 it printed "'62%' against 0.62" and stayed green while four legs around it went
	# red. It is not inert -- it reddens when the plumbing hands over nothing -- but it is
	# never independent evidence about the number, and should not be read as such.
	_check(drawn.get("caption", "") == "%d%%" % roundi(fill * 100.0),
		"with the caption agreeing ('%s' against %.2f)"
		% [drawn.get("caption", ""), fill])

	# **It climbs, and the bar is what is asked.** The shipped fault was a bar that was
	# correct once and never moved, so a single reading proves nothing. The order's own
	# climb is covered above; it is the bar that was lying, so it is the bar that answers.
	await _idle(30)
	var later: Dictionary = panel.order_readout()
	var climbed := float(later.get("fill", -1.0))
	_check(climbed > fill + 0.05,
		"and the bar fills as the cones go out (%.2f then %.2f)" % [fill, climbed])

	# **An order with nothing to measure hides the track rather than drawing zero.** The
	# base Order.progress() is -1.0 and every consumer has to read that as "no figure",
	# not as "none done" -- a bar sitting empty at 0% on a unit standing by would read as
	# a job that had stalled.
	_officer.clear_orders()
	_check(Order.new().progress() < 0.0,
		"an order with no measurable progress reports -1, not 0")
	await _idle(14)
	var idle_bar: Dictionary = panel.order_readout()
	_check(not idle_bar.get("shown", true),
		"so the track stands down rather than drawing an empty job")
	_check(idle_bar.get("caption", "x") == "",
		"and prints no percentage ('%s')" % idle_bar.get("caption", ""))

	_controller.clear_selection()
	await _clear_cordons()
	await _clear_incidents()


## The bar answers a click on the frame it happens, not at its next poll.
##
## **Reported from play as "a delay between clicking and the action".** This panel was
## built as a pure poll loop on a 0.12s TICK while every other panel in the interface --
## CommandGrid, Roster, RosterSidebar -- had listened to `selection_changed` since the
## signal existed. So the bar could take a seventh of a second to notice a selection,
## which is inside the range a player reads as lag rather than as instant.
##
## **Nothing in the suite could see it**, and that is why this check exists rather than
## just the fix. Every other assertion about this panel waits `_idle(14)` or more before
## looking -- comfortably past the tick -- so a bar that answered only on the poll was
## indistinguishable from one that answered at once. One frame is the whole point of the
## measurement: at 60fps a tick is about seven, so a poll-only bar shows nothing here.
func _test_the_bar_answers_the_selection_at_once() -> void:
	var panel := _scene.get_node_or_null(
		"HUD/Root/Bar/Row/SelectionBlock") as SelectionPanel
	if panel == null:
		_check(false, "the HUD carries a selection panel")
		return

	# Settle on "nothing selected" with a full poll's grace, so the next reading cannot be
	# a leftover from before.
	_controller.clear_selection()
	await _idle(16)
	_check(panel.shown_units().is_empty(),
		"the bar starts with nothing on it (%d shown)" % panel.shown_units().size())

	_controller.select([_car])
	await _idle(1)
	var shown := panel.shown_units()
	_check(shown.size() == 1 and shown[0] == _car,
		"and one frame after a selection the unit is already on it (%d shown)"
		% shown.size())

	# **Establish the precondition before testing the drop.** Without this the leg below
	# is vacuous under exactly the fault above it: a poll-only bar never showed the unit,
	# so "clear again" was satisfied by a bar that had always been empty, and it printed
	# `0 shown` in the healthy tree and the broken one alike. Settling a full tick lets a
	# polling bar catch up, so the drop is measured against a bar that genuinely holds
	# something -- which is the only state in which clearing it means anything.
	await _idle(16)
	_check(panel.shown_units().size() == 1,
		"the unit is still on the bar a tick later (%d shown)"
		% panel.shown_units().size())

	# The same on the way out: dropping a selection must not leave a stale unit on the bar
	# for a seventh of a second either.
	_controller.clear_selection()
	await _idle(1)
	_check(panel.shown_units().is_empty(),
		"and one frame after dropping it the bar is clear again (%d shown)"
		% panel.shown_units().size())
	await _idle(16)


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
## Every unit's own command grid, swept for keys that answer twice.
##
## **Written because the game shipped one and nothing noticed.** `Clear` and `Lights` both
## returned `KEY_J`, on the documented reasoning that one is a foot verb and the other a
## vehicle verb so they could never meet -- and then `can_tow` gave the recovery truck the
## winch, which made it the one unit carrying both. `_handle_hotkey` takes the first match
## in tile order, so the truck's lightbar became unreachable from the keyboard while the
## reference file still described the situation as impossible.
##
## Three legs, because the near misses differ. A key that answers twice on one unit is the
## fault above. A key the camera *polls* (`W A S D Q E`) is worse -- `Input.get_vector`
## reads it whether or not the event was consumed, so the command would fire and the camera
## would move. And a key outside [constant RTSController.COMMAND_KEYS] has no defined slot
## in the row, so `_key_order` files it last alongside every other unplaced verb and the
## tile order stops meaning anything.
func _test_no_unit_offers_two_verbs_on_one_key() -> void:
	# Polled by RTSCamera, or claimed by the shell. A command on any of these is a command
	# that also does something else.
	var reserved := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_F, KEY_R,
		KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5,
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	var paths: Array[String] = ["res://Game/Person.tscn", "res://Game/Paramedic.tscn",
		"res://Game/Firefighter.tscn", "res://Game/Doctor.tscn",
		"res://Game/ArmedOfficer.tscn"]
	var dir := DirAccess.open("res://Game/Vehicles")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tscn"):
				paths.append("res://Game/Vehicles/%s" % file)

	var swept := 0
	var verbs := 0
	var clashes: Array[String] = []
	var stolen: Array[String] = []
	var unplaced: Array[String] = []
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var unit := packed.instantiate() as Unit
		if unit == null:
			continue
		# Abilities are built in `_ready`, so the unit has to be in the tree: reading them
		# off a bare `instantiate()` returns an empty list and passes everything.
		_scene.add_child(unit)
		await _idle(1)
		swept += 1
		var seen := {}
		for ability in unit.abilities():
			var key: int = ability.hotkey()
			if key == KEY_NONE:
				continue
			verbs += 1
			var named := OS.get_keycode_string(key)
			if seen.has(key):
				clashes.append("%s: %s and %s both on %s"
					% [path.get_file(), seen[key], ability.id(), named])
			seen[key] = ability.id()
			if reserved.has(key):
				stolen.append("%s: %s on %s" % [path.get_file(), ability.id(), named])
			if not RTSController.COMMAND_KEYS.has(key):
				unplaced.append("%s: %s on %s" % [path.get_file(), ability.id(), named])
		unit.queue_free()
		await _idle(1)

	# Two-sided: a folder that read as empty would leave all three lists empty and pass.
	_check(swept >= 12 and verbs >= 60,
		"%d unit scenes swept, offering %d bound verbs between them" % [swept, verbs])
	_check(clashes.is_empty(),
		"no unit offers two verbs on one key (%s)"
		% ("none" if clashes.is_empty() else "; ".join(clashes)))
	_check(stolen.is_empty(),
		"and none takes a key the camera polls (%s)"
		% ("none" if stolen.is_empty() else "; ".join(stolen)))
	_check(unplaced.is_empty(),
		"and every one has a slot in COMMAND_KEYS (%s)"
		% ("none" if unplaced.is_empty() else "; ".join(unplaced)))


## A scratch canvas that draws whatever icon keys it is handed.
##
## Real drawing, in a real `_draw()` pass, because that is the only place the fall-through
## happens -- `Glyph.draw` picks the texture, misses, calls `_fallback`, and the `match`
## default fires. Reading a list of keys and comparing it to a list of files would test two
## lists against each other and nothing against the code.
class SymbolCanvas extends Control:
	var keys: Array[StringName] = []
	var drew := 0

	func _draw() -> void:
		drew += 1
		for key in keys:
			Glyph.draw(self, key, Vector2(12.0, 12.0), 10.0, Color.WHITE)


## Every symbol the command tiles can ask for actually draws something.
##
## **`Glyph._fallback` ends in `_: _unknown(...)`**, which paints a question mark. So an
## ability whose `icon()` names a key nobody drew -- a typo, or a symbol that was planned
## and never made -- renders a `?` on its tile and ships without a warning. At tile size a
## question mark reads as a deliberate symbol, which is how it would survive being looked at.
func _test_every_command_symbol_resolves() -> void:
	var wanted: Array[StringName] = []
	var dir := DirAccess.open("res://Game/Units")
	if dir == null:
		_check(false, "the ability folder can be read")
		return
	for file in dir.get_files():
		if not file.ends_with("Ability.gd"):
			continue
		var script := load("res://Game/Units/%s" % file) as GDScript
		if script == null:
			continue
		var ability := script.new() as Ability
		if ability:
			wanted.append(ability.icon())

	var canvas := SymbolCanvas.new()
	canvas.keys = wanted
	_scene.add_child(canvas)
	Glyph.missed.clear()
	canvas.queue_redraw()
	await _idle(4)
	var missed := Glyph.missed.duplicate()
	_check(canvas.drew > 0 and wanted.size() >= 18,
		"%d command symbols drawn for real in %d passes"
		% [wanted.size(), canvas.drew])
	_check(missed.is_empty(),
		"and every one of them draws a symbol rather than a question mark (%s)"
		% ("none missed" if missed.is_empty() else ", ".join(missed)))

	# **Two-sided, and it has to be.** The leg above passes on a game where the counter is
	# never written -- which is most of the ways this instrument could be wrong. Handing it
	# a key that certainly does not exist proves the question mark is still detectable.
	Glyph.missed.clear()
	canvas.keys = [&"no_such_symbol"]
	canvas.queue_redraw()
	await _idle(4)
	_check(Glyph.missed.has(&"no_such_symbol"),
		"a key nobody drew is still caught (%s)" % str(Glyph.missed))

	Glyph.missed.clear()
	canvas.queue_free()
	await _idle(2)


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
		if not _roster.standby_for(chip).is_empty():
			continue
		var listed := _roster.unit_for(chip)
		if listed == null or listed.service == Unit.Service.NONE:
			strays.append(str(listed))
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
		"HUD/Root/Bar/Row/RosterBlock/Body/Roster") as RosterSidebar
	if roster == null:
		_check(false, "the HUD carries a roster")
		return
	await _idle(3)

	# **The design changed here and the check changed with it.** The roster this replaced
	# put each service on its own line, and this asserted that no line ever mixed two.
	# The sidebar groups by *status* instead -- available, en route, on scene -- and keeps
	# the services apart with a filter. So the surviving question is the one that was
	# really being asked: **can the player see one service without the others?**
	var everything := roster.rows().size()
	_check(everything >= 2, "the roster lists something to filter (%d rows)" % everything)

	var per_service := {}
	for service: int in [Unit.Service.POLICE, Unit.Service.MEDICAL, Unit.Service.FIRE]:
		var category: StringName = ShopCatalogue.CATEGORY.get(service, &"support")
		roster.filter_to(category)
		await _idle(2)
		var strays := PackedStringArray()
		var shown := 0
		for row in roster.rows():
			shown += 1
			var listed := roster.unit_for(row)
			var waiting := roster.standby_for(row)
			var of: int = listed.service if listed \
				else int(waiting.get("service", Unit.Service.NONE))
			if of != service:
				strays.append(str(of))
		per_service[service] = shown
		_check(strays.is_empty(),
			"filtering to %s shows only that service (%d shown, %d strays)"
			% [category, shown, strays.size()])
	roster.filter_to(&"all")
	await _idle(2)

	# Both directions: a filter that showed *nothing* would satisfy the assertions above,
	# and the parts have to add back up to the whole.
	var summed := 0
	for service in per_service:
		summed += int(per_service[service])
	_check(summed == everything,
		"and the filters between them account for every row (%d of %d)"
		% [summed, everything])


## The roster shows a hurt crew member's health, and never invents one for a vehicle.
##
## **The second half is the point.** `health` is a [Person] field; a vehicle's damage is a
## `repair_bill` in pounds, settled when it books in. A bar under a patrol car would be a
## readout with nothing behind it -- so this asserts the vehicle's bar stays hidden even
## while a person's is showing, which a "does the bar exist" check would sail past.
func _test_the_roster_shows_a_hurt_crew_member() -> void:
	_controller.clear_selection()
	await _idle(3)
	var hurt_chip: Control = null
	var car_chip: Control = null
	for chip in _visible_chips():
		var listed := _roster.unit_for(chip)
		if listed == _officer:
			hurt_chip = chip
		elif listed == _car:
			car_chip = chip
	if hurt_chip == null or car_chip == null:
		_check(false, "a person and a vehicle on the roster to compare")
		return

	_check(not _roster.shows_condition(hurt_chip),
		"an unhurt crew member shows no health bar")
	var kept := _officer.health
	_officer.hurt(0.5)
	await _idle(4)
	_check(_roster.shows_condition(hurt_chip),
		"and a hurt one does (health %.2f)" % _officer.health)
	_check(not _roster.shows_condition(car_chip),
		"while a vehicle never does -- it has a repair bill, not health")

	# Back to full, and the bar goes away again rather than sitting at 100%.
	_officer.health = kept
	await _idle(4)
	_check(not _roster.shows_condition(hurt_chip),
		"and it hides again once they are patched up")


func _test_roster_marks_the_selection() -> void:
	_controller.select([_cars[0], _cars[1]])
	await _idle(3)
	var marked := PackedStringArray()
	for chip in _visible_chips():
		if _roster.is_row_selected(chip):
			marked.append(_roster.unit_for(chip).display_name)
	_check(marked.size() == 2,
		"selecting two rings two chips (%d: %s)" % [marked.size(), ", ".join(marked)])
	_check(marked.has(_cars[0].display_name) and marked.has(_cars[1].display_name),
		"and they are the two that were selected")

	_controller.clear_selection()
	await _idle(3)
	var still := 0
	for chip in _visible_chips():
		if _roster.is_row_selected(chip):
			still += 1
	_check(still == 0, "clearing the selection un-rings them (%d still ringed)" % still)


## Sending one unit from the bar is the reason the roster exists, so it is clicked for
## real rather than called directly -- which also proves a chip is reachable inside the
## bar, and that the bar does not intercept its own children's clicks.
## A row must stop saying AVAILABLE once its unit is doing something.
##
## **The roster's worst shipped bug, and nothing was watching it.** Every row read
## AVAILABLE / Station for the whole shift however far the unit drove -- the player
## reported it as "the status of the units only seems to stay as Available". `_refresh`
## compared the *total* of the two populations, and dispatching a unit moves it from the
## house to the map, so `wanted` gained one exactly as `waiting` lost one, the total never
## moved, and the rebuild never fired. The row stayed bound to the station entry it was
## born as.
##
## **The unit has to come out of the station for this to mean anything**, and the first
## version of this check did not do that -- it drove a car that was already on the map,
## which `_restate()` services every frame whether or not the rebuild fires. Reverting the
## fix left it entirely green. `_restate` skips any row whose `_behind` entry is still a
## Dictionary, so the fault is only reachable through a row that began as a station entry:
## the scenario was under-provoked, and the repair belonged there rather than in the
## assertion.
func _test_the_roster_says_what_a_unit_is_doing() -> void:
	_controller.clear_selection()
	await _idle(4)
	# Two-sided, on a unit that was already out: a row jammed on EN ROUTE would otherwise
	# pass the half that matters most.
	var parked := _chip_for(_car)
	if parked == null:
		_check(false, "the patrol car has a row on the roster")
		return
	_car.stop_navigating()
	_car.clear_orders()
	await _idle(6)
	_check(_roster.status_of(parked) == UnitInstance.Status.AVAILABLE,
		"a parked car reads AVAILABLE (%s)"
		% UnitInstance.STATUS_LABEL.get(_roster.status_of(parked), "?"))

	# **Out of the house through the standby chip**, which is the door the player uses and
	# the only one that leaves a row bound to a station entry.
	_buy(&"paramedic", 1)
	await _idle(4)
	var chip := _dispatch_row(&"paramedic")
	_check(chip != null, "a standby chip for the paramedic just bought")
	if chip == null:
		return
	# **Identified by set difference, never by "has a row".** The first rewrite picked the
	# dispatched unit with `_chip_for(unit) != null` -- which is exactly the condition the
	# fault destroys, so under the fault the loop skipped the paramedic that had just come
	# out of the house and silently fell back to one that was already on the map, whose row
	# `_restate()` services every frame. The check then measured the wrong unit and passed.
	# The world knows who was dispatched; the panel under test must not be asked.
	var before := {}
	for unit in _commanded_units():
		before[unit] = true
	(chip as UnitRow).selected.emit((chip as UnitRow).unit)
	await _idle(6)
	var sent: Unit = null
	var after := _commanded_units()
	for unit in after:
		if not before.has(unit):
			sent = unit
	_check(after.size() == before.size() + 1 and sent != null,
		"and it comes out onto the forecourt (%d units, was %d)"
		% [after.size(), before.size()])
	if sent == null:
		return

	sent.issue(MoveOrder.new(sent.global_position + Vector3(0.0, 0.0, -14.0)))
	# Long enough for the panel to notice and rebuild, not so long the walk can finish.
	await _idle(30)
	var row := _chip_for(sent)
	var said: int = _roster.status_of(row) if row else -1
	# **`row != null` is load-bearing.** Under the fault the dispatched unit has no row at
	# all, `said` falls back to the -1 sentinel, and `-1 != AVAILABLE` is perfectly true --
	# so the leg claiming "a row stopped reading AVAILABLE" passed on a unit that had no row
	# to read. A sentinel that satisfies its own negation is the quiet way an assertion goes
	# vacuous while its printed measurement plainly shows the fault.
	_check(row != null and said != UnitInstance.Status.AVAILABLE,
		"a unit sent from the station stops reading AVAILABLE (%s)"
		% UnitInstance.STATUS_LABEL.get(said, "no row of its own"))
	_check(said == UnitInstance.Status.EN_ROUTE,
		"-- it reads EN ROUTE (%s)"
		% UnitInstance.STATUS_LABEL.get(said, "no row of its own"))

	sent.stop_navigating()
	sent.clear_orders()
	_dissolve(sent, &"paramedic")
	await _idle(4)


func _test_roster_chip_selects_a_unit() -> void:
	_controller.clear_selection()
	await _idle(3)
	var target := _chip_for(_ambulance)
	if target == null:
		_check(false, "the ambulance has a chip to click")
		return

	# **Driven through the row's own signal, not a pushed click.** Measured during the shop
	# swap: synthetic input reaches controls outside a `ScrollContainer` and not the ones
	# inside it, and these rows live in one. Everything downstream of the row is exercised
	# -- the panel's handler, the controller, the selection -- but that a mouse click lands
	# on the row is unproven, and saying so beats asserting something weaker in silence.
	(target as UnitRow).selected.emit((target as UnitRow).unit)
	await _idle(3)
	_check(_controller.selection.size() == 1 and _controller.primary() == _ambulance,
		"clicking the ambulance's chip selected it, and only it (%d selected)"
			% _controller.selection.size())


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
