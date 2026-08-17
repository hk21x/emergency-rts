extends SceneTree

## Bakes Game/UI/Theme.tres from the UI kit's art and the colours in Palette.gd.
##
##   godot --headless --path . --script res://Game/UI/build_theme.gd
##
## Safe headless: a Theme is plain resource data, unlike the map's MultiMesh buffers.
##
## Generated rather than hand-authored for the usual reason -- a StyleBoxTexture written
## as scene text is a dozen unlabelled numbers, and there are thirty of them here. It
## also keeps every colour and every nine-slice margin coming from one table, so the
## interface cannot end up with two nearly-identical card whites or a frame whose
## corners stretch.
##
## Type variations do the work that per-node `theme_override_*` used to. The old HUD set
## font size, colour, outline colour and outline width on every single label; now a label
## says what kind of label it is and the theme knows the rest.
##
## **Since August 2026 the chrome is drawn from the kit** (`Game/UI/Kit/frames/`, vectors
## the user supplied): panels, buttons, bars and tiles are nine-sliced textures rather
## than StyleBoxFlat. Two things follow. The nine-slice margins are not free parameters --
## they come from `ui-kit/NINE-SLICE.md` and a wrong one visibly stretches a corner. And
## the *drawn* parts of the interface (minimap, command tiles, avatars) still paint
## themselves from Palette, so Palette's chrome colours are set to the kit's tokens: art
## and code have to agree, or a drawn tile sits a shade off the frame around it.

const OUT := "res://Game/UI/Theme.tres"
const KIT := "res://Game/UI/Kit/frames/"
const FONTS := "res://Game/UI/Fonts/"

## Rajdhani for display, headings and button labels; Barlow for body copy. The kit's
## own pairing, and the single biggest reason the interface reads as the reference
## rather than as stock Godot.
const DISPLAY_BOLD := FONTS + "Rajdhani-Bold.ttf"
const DISPLAY_SEMI := FONTS + "Rajdhani-SemiBold.ttf"
const DISPLAY_MED := FONTS + "Rajdhani-Medium.ttf"
const BODY := FONTS + "Barlow-Regular.ttf"
const BODY_MED := FONTS + "Barlow-Medium.ttf"

## The kit's type scale, in its own words: title 20, label 13, body 12.5, caption 11,
## eyebrow 10. Rajdhani runs small for its point size, so the game's working sizes sit a
## little above the scale's -- these are the kit's numbers read at this screen size.
const FONT_SIZE := 15
const HEADER_SIZE := 12
const VALUE_SIZE := 24
const BANNER_SIZE := 54

## A slider's track has no size of its own -- it is drawn from the stylebox's vertical
## content margin, so this *is* the track height.
const TRACK_HEIGHT := 6
const KNOB_RADIUS := 7
## The pill radius is deliberately larger than any pill is tall, which is what makes the
## ends semicircular however much text is in one. Pills stay flat-drawn: the kit has no
## capsule frame, and a nine-sliced rectangle cannot be one.
const PILL_RADIUS := 999

var _fonts := {}


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	var theme := Theme.new()
	theme.default_font = _font(BODY)
	theme.default_font_size = FONT_SIZE

	_labels(theme)
	_panels(theme)
	_buttons(theme)
	_containers(theme)
	_sliders(theme)
	_bars(theme)

	var err := ResourceSaver.save(theme, OUT)
	if err != OK:
		push_error("save failed for %s: %d" % [OUT, err])
		quit(1)
		return
	print("done -- %s" % OUT)
	quit()


# --- Labels ------------------------------------------------------------------

func _labels(theme: Theme) -> void:
	theme.add_type("Label")
	theme.set_font("font", "Label", _font(BODY))
	theme.set_font_size("font_size", "Label", FONT_SIZE)
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("font_outline_color", "Label", Palette.OUTLINE)
	theme.set_constant("outline_size", "Label", 0)

	# Column headings and units. Dim and small, so the eye lands on the value instead --
	# and in the display face, because the kit's eyebrows are Rajdhani.
	_label_variation(theme, "HeaderLabel", HEADER_SIZE, Palette.TEXT_DIM, 0, DISPLAY_MED)
	# The one number a panel exists to show: a speed, a count, the clock.
	_label_variation(theme, "ValueLabel", VALUE_SIZE, Palette.TEXT, 0, DISPLAY_BOLD)
	_label_variation(theme, "DimLabel", FONT_SIZE, Palette.TEXT_DIM, 0, BODY)
	_label_variation(theme, "PillLabel", 14, Palette.TEXT, 0, DISPLAY_SEMI)
	_label_variation(theme, "AlarmLabel", 14, Palette.CASUALTY_DEEP, 0, DISPLAY_SEMI)
	# The banner has no card behind it, so it carries its own outline: the text is
	# near-white and the ground it sits over is a lit Synty street rather than a card.
	_label_variation(theme, "BannerLabel", BANNER_SIZE, Palette.TEXT, 10, DISPLAY_BOLD)
	# **The radio log has no panel at all** -- four lines of dispatch chatter straight over
	# the city. `DimLabel` cannot simply gain an outline, because it is also used inside
	# cards where an outline is wrong; this is the same label with something behind it.
	_label_variation(theme, "RadioLabel", FONT_SIZE, Palette.TEXT_DIM, 4, BODY_MED)


func _label_variation(theme: Theme, name: String, size: int, colour: Color,
		outline: int, face: String) -> void:
	theme.add_type(name)
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, _font(face))
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, colour)
	theme.set_color("font_outline_color", name, Palette.OUTLINE)
	theme.set_constant("outline_size", name, outline)


# --- Panels ------------------------------------------------------------------

func _panels(theme: Theme) -> void:
	# The kit's raised panel: a #18222F -> #0E1620 gradient inside a #212D3C stroke,
	# nine-sliced at 10 so its 6px corner radius stays a radius at any size.
	theme.add_type("PanelContainer")
	theme.set_stylebox("panel", "PanelContainer", _frame("panels_panel", 10, 10))

	# The docked bar. Opaque, square, and edged only along the top -- it is the bottom
	# of the screen, so a frame around it would be drawing a border around nothing.
	# Flat rather than art for exactly that reason: every kit frame is a closed box.
	theme.add_type("BarPanel")
	theme.set_type_variation("BarPanel", "PanelContainer")
	var bar := _flat(Palette.BAR, 0, 10)
	bar.border_width_top = 1
	bar.border_color = Palette.EDGE
	theme.set_stylebox("panel", "BarPanel", bar)

	# A card in the bar, or a panel floating over the city.
	theme.add_type("CardPanel")
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _frame("panels_panel", 10, 10))

	# The recessed one: darker than what it sits in, with the soft stroke. For anything
	# the interface has *sunk* rather than raised -- a minimap well, a log.
	theme.add_type("InsetPanel")
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", _frame("panels_panel_inset", 8, 8))

	# A window: the panel with a 46px title bar built into the art, so the heading sits
	# in the frame's own header rather than floating in the body.
	theme.add_type("WindowPanel")
	theme.set_type_variation("WindowPanel", "PanelContainer")
	theme.set_stylebox("panel", "WindowPanel",
		_frame("panels_window", 10, 12, 46, 10, 12))

	# The unit readout at the bottom-left of the reference, header bar and all.
	theme.add_type("UnitPanel")
	theme.set_type_variation("UnitPanel", "PanelContainer")
	theme.set_stylebox("panel", "UnitPanel",
		_frame("hud_unit_selection_panel", 10, 10, 34, 10, 10))

	# The top strip: mission line, clock, score, unit count.
	theme.add_type("TopBarPanel")
	theme.set_type_variation("TopBarPanel", "PanelContainer")
	theme.set_stylebox("panel", "TopBarPanel", _frame("topbar_topbar_frame", 10, 10))

	# Rounded to a capsule whatever it contains. Used for the clock, the call count,
	# and every incident row. Flat-drawn -- see PILL_RADIUS.
	theme.add_type("PillPanel")
	theme.set_type_variation("PillPanel", "PanelContainer")
	var pill := _flat(Palette.CARD, PILL_RADIUS, 6)
	pill.border_width_bottom = 1
	pill.border_width_top = 1
	pill.border_width_left = 1
	pill.border_width_right = 1
	pill.border_color = Palette.EDGE
	pill.content_margin_left = 12
	pill.content_margin_right = 12
	theme.set_stylebox("panel", "PillPanel", pill)

	# Same shape, washed with alarm colour: something is waiting to be dealt with.
	theme.add_type("AlarmPill")
	theme.set_type_variation("AlarmPill", "PanelContainer")
	var alarm := pill.duplicate() as StyleBoxFlat
	alarm.bg_color = Palette.ALARM_WASH
	alarm.border_color = Palette.CASUALTY_MARKER
	theme.set_stylebox("panel", "AlarmPill", alarm)

	# The main menu's column, and the two plates that top and tail it. The title plate
	# is an empty slot in the kit -- sized to the column, meant for a logo -- so the
	# game's name is drawn into it as text.
	theme.add_type("MenuContainer")
	theme.set_type_variation("MenuContainer", "PanelContainer")
	theme.set_stylebox("panel", "MenuContainer", _frame("menu_menu_container", 12, 14))
	theme.add_type("TitlePlate")
	theme.set_type_variation("TitlePlate", "PanelContainer")
	theme.set_stylebox("panel", "TitlePlate", _frame("menu_title_plate", 8, 16, 14))
	theme.add_type("VersionPlate")
	theme.set_type_variation("VersionPlate", "PanelContainer")
	theme.set_stylebox("panel", "VersionPlate", _frame("menu_version_plate", 8, 12, 9))

	# List rows, for anything that is a *list* rather than a set of badges: the call
	# board, the roster, the shop. The kit does not give these a nine-slice margin --
	# they are drawn as fixed-size art -- so the 6 here is a judgement call: enough to
	# hold the 4px corner while the middle stretches to whatever a row is wide.
	theme.add_type("ListRow")
	theme.set_type_variation("ListRow", "PanelContainer")
	theme.set_stylebox("panel", "ListRow", _frame("controls_list_row_default", 6, 10, 7))
	theme.add_type("ListRowAlt")
	theme.set_type_variation("ListRowAlt", "PanelContainer")
	theme.set_stylebox("panel", "ListRowAlt", _frame("controls_list_row_alt", 6, 10, 7))
	theme.add_type("ListRowHover")
	theme.set_type_variation("ListRowHover", "PanelContainer")
	theme.set_stylebox("panel", "ListRowHover",
		_frame("controls_list_row_hover", 6, 10, 7))
	theme.add_type("ListRowSelected")
	theme.set_type_variation("ListRowSelected", "PanelContainer")
	theme.set_stylebox("panel", "ListRowSelected",
		_frame("controls_list_row_selected", 6, 10, 7))
	theme.add_type("ListHeader")
	theme.set_type_variation("ListHeader", "PanelContainer")
	theme.set_stylebox("panel", "ListHeader", _frame("controls_list_header", 6, 10, 6))

	# Notification rows. **The art is 360x34 with a 32x32 coloured square at x=1** --
	# an icon tab, not a stripe. Two things follow, and getting either wrong is what
	# made the first cut look like an empty amber block bolted to a row:
	#
	# The left texture margin must clear the square (40 > 33), or nine-slicing stretches
	# it into a smear -- the kit's own NINE-SLICE.md says so outright. And the *content*
	# margin must not push past it, because whatever sits first in the row is what fills
	# the tab. At 46 the tab was left empty and the row's own icon sat in the body.
	#
	# The vertical padding is 1, not 8: the square is as tall as the art, so a row much
	# taller than 34 stretches it into a bar. Keep the row the height of the art and the
	# tab stays a tab.
	for tone: String in ["info", "success", "warning", "danger"]:
		var name := "Notify" + tone.capitalize()
		theme.add_type(name)
		theme.set_type_variation(name, "PanelContainer")
		theme.set_stylebox("panel", name, _frame(
			"notifications_notification_%s_blank" % tone, 8, 1, 1, 12, 1, 40))

	# The command tiles' backing, and the stat rows inside the unit readout.
	theme.add_type("CommandGridPanel")
	theme.set_type_variation("CommandGridPanel", "PanelContainer")
	theme.set_stylebox("panel", "CommandGridPanel", _frame("hud_command_grid", 8, 8))
	theme.add_type("StatRow")
	theme.set_type_variation("StatRow", "PanelContainer")
	theme.set_stylebox("panel", "StatRow", _frame("hud_stat_row", 6, 9, 5))
	theme.add_type("MinimapPanel")
	theme.set_type_variation("MinimapPanel", "PanelContainer")
	theme.set_stylebox("panel", "MinimapPanel", _frame("hud_minimap_frame", 10, 8))

	# The roster's tiles: a portrait-aspect well, with a lit variant for the selected
	# one. 48x56 in the kit, which is a 38px badge and its callsign almost exactly.
	theme.add_type("UnitTile")
	theme.set_type_variation("UnitTile", "PanelContainer")
	theme.set_stylebox("panel", "UnitTile", _frame("hud_unit_portrait", 6, 4, 4))
	theme.add_type("UnitTileSelected")
	theme.set_type_variation("UnitTileSelected", "PanelContainer")
	theme.set_stylebox("panel", "UnitTileSelected",
		_frame("hud_unit_portrait_selected", 6, 4, 4))

	# The plate a command tile is drawn on. Four states in the kit including an
	# `_empty` slot, at 38px -- nine-sliced at 8, so it stretches to this game's 54
	# without the corners going oval.
	for state: String in ["default", "hover", "pressed", "empty"]:
		var name := "CommandPlate" + state.capitalize()
		theme.add_type(name)
		theme.set_type_variation(name, "PanelContainer")
		theme.set_stylebox("panel", name,
			_frame("buttons_command_button_" + state, 8, 4))

	# A tooltip, which the kit gives a pointer notch along the bottom -- hence the 22px
	# bottom margin, the one asymmetric slice in the set.
	theme.add_type("TooltipPanel")
	theme.set_stylebox("panel", "TooltipPanel",
		_frame("notifications_tooltip", 12, 12, 12, 12, 22))
	theme.add_type("TooltipLabel")
	theme.set_type_variation("TooltipLabel", "Label")
	theme.set_color("font_color", "TooltipLabel", Palette.TEXT)


# --- Buttons -----------------------------------------------------------------

func _buttons(theme: Theme) -> void:
	theme.add_type("Button")
	theme.set_font("font", "Button", _font(DISPLAY_SEMI))
	theme.set_font_size("font_size", "Button", FONT_SIZE + 1)
	# The kit's secondary button is the default one: dark fill, visible stroke, the
	# primary blue held back for the button a card is actually asking you to press.
	_button_states(theme, "Button", "buttons_large_button_secondary", 8, 16, 8)
	# Focus is drawn as nothing on purpose. Buttons here are set to FOCUS_NONE so the
	# control-group keys keep working, and a focus ring on a button that cannot hold
	# focus is a lie.
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT)
	theme.set_color("font_pressed_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_pressed_color", "Button", Palette.TEXT)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_DISABLED)

	# The blue one, for the action a card exists to offer: PLAY, CONFIRM, BUY.
	theme.add_type("PrimaryButton")
	theme.set_type_variation("PrimaryButton", "Button")
	_button_states(theme, "PrimaryButton", "buttons_large_button_primary", 8, 16, 8)

	# The red one, for anything that throws work away: QUIT, ABANDON.
	theme.add_type("DangerButton")
	theme.set_type_variation("DangerButton", "Button")
	_button_states(theme, "DangerButton", "buttons_large_button_danger", 8, 16, 8)

	# The quiet one: a hairline, no fill. For BACK, and for rows of choices where
	# every option drawn as a button would be a wall of boxes.
	theme.add_type("TertiaryButton")
	theme.set_type_variation("TertiaryButton", "Button")
	_button_states(theme, "TertiaryButton", "buttons_large_button_tertiary", 8, 16, 8)

	# The title card's rows, which are wider and taller than a button and carry a
	# left-hand accent bar in the art.
	theme.add_type("MenuItem")
	theme.set_type_variation("MenuItem", "Button")
	_button_states(theme, "MenuItem", "menu_menu_item", 8, 18, 11)
	theme.set_font("font", "MenuItem", _font(DISPLAY_SEMI))
	theme.set_font_size("font_size", "MenuItem", FONT_SIZE + 3)
	# The row's icon, which the kit ships white so it can be tinted. Dim at rest and
	# full-strength under the pointer, so the column reads as a list until the eye
	# lands on one -- the same trick the text colours play, one step quieter.
	theme.set_color("icon_normal_color", "MenuItem", Palette.TEXT_DIM)
	theme.set_color("icon_hover_color", "MenuItem", Palette.TEXT)
	theme.set_color("icon_pressed_color", "MenuItem", Palette.PRIMARY_LINE)
	theme.set_color("icon_hover_pressed_color", "MenuItem", Palette.PRIMARY_LINE)
	theme.set_color("icon_disabled_color", "MenuItem", Palette.TEXT_DISABLED)
	theme.set_constant("icon_max_width", "MenuItem", 20)
	# The gap between icon and label. Godot spends `h_separation` on that pair, so this
	# is what stops the two touching in a left-aligned row.
	theme.set_constant("h_separation", "MenuItem", 12)

	# The little plates beside the minimap: zoom, centre, follow. Single-state art, so
	# the tint does the work of hover and pressed.
	theme.add_type("MapControl")
	theme.set_type_variation("MapControl", "Button")
	_button_states(theme, "MapControl", "buttons_map_control", 6, 4, 4)
	theme.set_color("icon_normal_color", "MapControl", Palette.TEXT_DIM)
	theme.set_color("icon_hover_color", "MapControl", Palette.TEXT)
	theme.set_color("icon_pressed_color", "MapControl", Palette.PRIMARY_LINE)
	theme.set_constant("icon_max_width", "MapControl", 16)

	# The top-right cluster: menu and pause. Also single-state art.
	theme.add_type("TransportButton")
	theme.set_type_variation("TransportButton", "Button")
	_button_states(theme, "TransportButton", "topbar_pause_button", 8, 8, 8)
	theme.set_color("icon_normal_color", "TransportButton", Palette.TEXT_DIM)
	theme.set_color("icon_hover_color", "TransportButton", Palette.TEXT)
	theme.set_color("icon_pressed_color", "TransportButton", Palette.PRIMARY_LINE)
	theme.set_constant("icon_max_width", "TransportButton", 22)
	# **Font colours, because the plate cannot say it.** `topbar_pause_button` is a
	# single-state file, so `_button_states` points normal, hover and pressed at the same
	# art -- which is fine for the icon buttons, where the tint above carries the state,
	# and useless for the speed buttons, which are text and *toggle*. Without these the
	# chosen speed looked exactly like the two that were not chosen.
	theme.set_color("font_color", "TransportButton", Palette.TEXT_DIM)
	theme.set_color("font_hover_color", "TransportButton", Palette.TEXT)
	theme.set_color("font_pressed_color", "TransportButton", Palette.PRIMARY_LINE)
	theme.set_color("font_hover_pressed_color", "TransportButton", Palette.PRIMARY_LINE)

	# A square tile carrying an icon and nothing else.
	theme.add_type("IconTile")
	theme.set_type_variation("IconTile", "Button")
	_button_states(theme, "IconTile", "buttons_icon_tile", 12, 8, 8)


## Fills in normal / hover / pressed / disabled from one family of kit frames.
##
## The disabled frame is shared across the whole button set in the kit -- there is one
## `button-disabled.svg`, not one per colour -- which is why it is looked up separately
## and why a family name is not enough on its own.
func _button_states(theme: Theme, type: String, family: String, slice: int,
		pad_x: int, pad_y: int) -> void:
	# **Some of the kit's plates ship one state, not three.** The map control and the
	# two topbar buttons are single files with no `_hover`/`_pressed` beside them, and
	# `_frame` calls `load()` unconditionally -- so asking for a state that has no art
	# is a broken load rather than a graceful fallback. Where the family has no
	# `_default`, the family name *is* the art and every state points at it; hover and
	# pressed then come from the icon tint, which is how the kit draws those anyway.
	var single := not ResourceLoader.exists(KIT + family + "_default.svg")
	var base := family if single else family + "_default"
	theme.set_stylebox("normal", type, _frame(base, slice, pad_x, pad_y, pad_x, pad_y))
	theme.set_stylebox("hover", type, _frame(
		base if single else family + "_hover", slice, pad_x, pad_y, pad_x, pad_y))
	theme.set_stylebox("pressed", type, _frame(
		base if single else family + "_pressed", slice, pad_x, pad_y, pad_x, pad_y))
	# **The selected-and-hovered state.** Without it Godot falls back to `hover`, so
	# running the mouse along the settings rows made the *chosen* option look unchosen --
	# in all four toggle groups (shift length, call rate, time of day, weather).
	theme.set_stylebox("hover_pressed", type, _frame(
		base if single else family + "_pressed", slice, pad_x, pad_y, pad_x, pad_y))
	var off := family + "_disabled"
	if not ResourceLoader.exists(KIT + off + ".svg"):
		off = ("menu_menu_item_disabled" if family.begins_with("menu")
			else "buttons_large_button_disabled")
	theme.set_stylebox("disabled", type, _frame(off, slice, pad_x, pad_y, pad_x, pad_y))


# --- Bars --------------------------------------------------------------------

func _bars(theme: Theme) -> void:
	theme.add_type("ProgressBar")
	theme.set_stylebox("background", "ProgressBar", _frame("bars_bar_track", 3, 0))
	theme.set_stylebox("fill", "ProgressBar", _frame("bars_bar_fill_progress", 3, 0))
	theme.set_color("font_color", "ProgressBar", Palette.TEXT)

	theme.add_type("HealthBar")
	theme.set_type_variation("HealthBar", "ProgressBar")
	theme.set_stylebox("fill", "HealthBar", _frame("bars_bar_fill_health", 3, 0))

	theme.add_type("DangerBar")
	theme.set_type_variation("DangerBar", "ProgressBar")
	theme.set_stylebox("fill", "DangerBar", _frame("bars_bar_fill_danger", 3, 0))


# --- Sliders -----------------------------------------------------------------

## The volume slider was the one control in the game with no theme entry at all --
## stock Godot, a mid-grey grabber, invisible until you went looking for it.
func _sliders(theme: Theme) -> void:
	theme.add_type("HSlider")
	# **The track's height is its content margin**, which is the whole trap here. The
	# first cut passed padding 0 -- correct for a card, meaningless for a slider -- and
	# baked a track zero pixels high. The volume grabber floated on nothing, which is
	# worse than the stock control it replaced.
	@warning_ignore("integer_division")
	var half := TRACK_HEIGHT / 2
	theme.set_stylebox("slider", "HSlider", _flat(Palette.WELL, half, 0, half))
	theme.set_stylebox("grabber_area", "HSlider",
		_flat(Palette.PRIMARY, half, 0, half))
	theme.set_stylebox("grabber_area_highlight", "HSlider",
		_flat(Palette.PRIMARY_LIGHT, half, 0, half))
	# **Circular, so it is not nine-sliced** -- the kit says so outright, and a stretched
	# grabber is an oval. Drawn flat at the size it is wanted.
	var knob := StyleBoxFlat.new()
	knob.bg_color = Palette.TEXT
	knob.set_corner_radius_all(PILL_RADIUS)
	knob.content_margin_left = KNOB_RADIUS
	knob.content_margin_right = KNOB_RADIUS
	knob.content_margin_top = KNOB_RADIUS
	knob.content_margin_bottom = KNOB_RADIUS
	theme.set_stylebox("grabber", "HSlider", knob)
	var lit := knob.duplicate() as StyleBoxFlat
	lit.bg_color = Palette.PRIMARY_LINE
	theme.set_stylebox("grabber_highlight", "HSlider", lit)


# --- Containers --------------------------------------------------------------

func _containers(theme: Theme) -> void:
	theme.add_type("HBoxContainer")
	theme.set_constant("separation", "HBoxContainer", Palette.STEP)
	theme.add_type("VBoxContainer")
	theme.set_constant("separation", "VBoxContainer", Palette.SNUG)
	theme.add_type("HFlowContainer")
	# **The flow container keeps its own numbers.** Its h_separation is what decides how
	# many command tiles fit a row, and therefore whether the bar is one row or two. It is
	# not a spacing preference, it is load-bearing geometry.
	theme.set_constant("h_separation", "HFlowContainer", 9)
	theme.set_constant("v_separation", "HFlowContainer", Palette.SNUG)


# --- Helpers -----------------------------------------------------------------

## A nine-sliced kit frame.
##
## [param slice] is the stretch margin from `ui-kit/NINE-SLICE.md` -- **not** a free
## parameter: too small and the corner radius stretches into an ellipse, too large and
## the middle stops repeating. The content margins are this project's padding, which is
## a separate question from where the texture is cut.
func _frame(art: String, slice: int, pad_left: int, pad_top := -1, pad_right := -1,
		pad_bottom := -1, slice_left := -1) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(KIT + art + ".svg")
	box.texture_margin_left = slice if slice_left < 0 else slice_left
	box.texture_margin_top = slice
	box.texture_margin_right = slice
	box.texture_margin_bottom = slice
	box.content_margin_left = pad_left
	box.content_margin_top = pad_left if pad_top < 0 else pad_top
	box.content_margin_right = pad_left if pad_right < 0 else pad_right
	box.content_margin_bottom = pad_left if pad_bottom < 0 else pad_bottom
	return box


## [param vertical] defaults to [param padding]; a slider needs its two axes to differ,
## because the horizontal margin insets the track's ends while the vertical one *is* its
## height.
func _flat(colour: Color, radius: int, padding: int, vertical := -1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding if vertical < 0 else vertical
	box.content_margin_bottom = padding if vertical < 0 else vertical
	return box


## Loaded once each: a Theme holds references, and six FontFile loads turning into
## thirty would be thirty copies in the saved resource.
func _font(path: String) -> FontFile:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]
