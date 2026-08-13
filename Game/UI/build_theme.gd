extends SceneTree

## Bakes Game/UI/Theme.tres from the colours in Palette.gd.
##
##   godot --headless --path . --script res://Game/UI/build_theme.gd
##
## Safe headless: a Theme is plain resource data, unlike the map's MultiMesh buffers.
##
## Generated rather than hand-authored for the usual reason -- a StyleBoxFlat written as
## scene text is a dozen unlabelled numbers, and there are twenty of them here. It also
## keeps every colour coming from one table, so the interface cannot end up with two
## nearly-identical card whites.
##
## Type variations do the work that per-node `theme_override_*` used to. The old HUD set
## font size, colour, outline colour and outline width on every single label; now a label
## says what kind of label it is and the theme knows the rest.

const OUT := "res://Game/UI/Theme.tres"

const FONT_SIZE := 14
const HEADER_SIZE := 11
const VALUE_SIZE := 22
const BANNER_SIZE := 54

## Cards. The pill radius is deliberately larger than any pill is tall, which is what
## makes the ends semicircular however much text is in one.
const CARD_RADIUS := 12
const TILE_RADIUS := 8
const PILL_RADIUS := 999
## A slider's track has no size of its own -- it is drawn from the stylebox's vertical
## content margin, so this *is* the track height.
const TRACK_HEIGHT := 6
const KNOB_RADIUS := 7


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	_labels(theme)
	_panels(theme)
	_buttons(theme)
	_containers(theme)
	_sliders(theme)

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
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("font_outline_color", "Label", Palette.OUTLINE)
	theme.set_constant("outline_size", "Label", 0)

	# Column headings and units. Dim and small, so the eye lands on the value instead.
	_label_variation(theme, "HeaderLabel", HEADER_SIZE, Palette.TEXT_DIM, 0)
	# The one number a panel exists to show: a speed, a count, the clock.
	_label_variation(theme, "ValueLabel", VALUE_SIZE, Palette.TEXT, 0)
	_label_variation(theme, "DimLabel", FONT_SIZE, Palette.TEXT_DIM, 0)
	_label_variation(theme, "PillLabel", 13, Palette.TEXT, 0)
	_label_variation(theme, "AlarmLabel", 13, Palette.CASUALTY_DEEP, 0)
	# The banner has no card behind it, so it carries its own outline. Since the restyle
	# that outline is near-black: the text is now near-white, and the ground it sits over
	# is a lit Synty street rather than a card.
	_label_variation(theme, "BannerLabel", BANNER_SIZE, Palette.TEXT, 10)
	# **The radio log has no panel at all** -- four lines of dispatch chatter straight over
	# the city. `DimLabel` cannot simply gain an outline, because it is also used inside
	# cards where an outline is wrong; this is the same label with something behind it.
	_label_variation(theme, "RadioLabel", FONT_SIZE, Palette.TEXT_DIM, 4)


func _label_variation(theme: Theme, name: String, size: int, colour: Color,
		outline: int) -> void:
	theme.add_type(name)
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, colour)
	theme.set_color("font_outline_color", name, Palette.OUTLINE)
	theme.set_constant("outline_size", name, outline)


# --- Panels ------------------------------------------------------------------

func _panels(theme: Theme) -> void:
	theme.add_type("PanelContainer")
	theme.set_stylebox("panel", "PanelContainer", _box(Palette.CARD, CARD_RADIUS, 10))

	# The docked bar. Opaque, square, and edged only along the top -- it is the bottom
	# of the screen, so a border on three sides would be drawing a frame around nothing.
	theme.add_type("BarPanel")
	theme.set_type_variation("BarPanel", "PanelContainer")
	var bar := _box(Palette.BAR, 0, 10)
	bar.border_width_top = 1
	bar.border_color = Palette.EDGE
	theme.set_stylebox("panel", "BarPanel", bar)

	# A white card: a block in the bar, or a panel floating over the city.
	theme.add_type("CardPanel")
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", _box(Palette.CARD, CARD_RADIUS, 10))

	# Rounded to a capsule whatever it contains. Used for the clock, the call count,
	# and every incident row.
	theme.add_type("PillPanel")
	theme.set_type_variation("PillPanel", "PanelContainer")
	var pill := _box(Palette.CARD, PILL_RADIUS, 6)
	pill.content_margin_left = 12
	pill.content_margin_right = 12
	theme.set_stylebox("panel", "PillPanel", pill)

	# Same shape, washed with alarm colour: something is waiting to be dealt with.
	theme.add_type("AlarmPill")
	theme.set_type_variation("AlarmPill", "PanelContainer")
	var alarm := _box(Palette.ALARM_WASH, PILL_RADIUS, 6)
	alarm.content_margin_left = 12
	alarm.content_margin_right = 12
	theme.set_stylebox("panel", "AlarmPill", alarm)


# --- Buttons -----------------------------------------------------------------

func _buttons(theme: Theme) -> void:
	theme.add_type("Button")
	theme.set_stylebox("normal", "Button", _box(Palette.WELL, TILE_RADIUS, 8))
	theme.set_stylebox("hover", "Button", _box(Palette.HOVER, TILE_RADIUS, 8))
	theme.set_stylebox("pressed", "Button", _box(Palette.PRESSED, TILE_RADIUS, 8))
	theme.set_stylebox("disabled", "Button",
		_box(Palette.dim(Palette.WELL, 0.5), TILE_RADIUS, 8))
	# Focus is drawn as nothing on purpose. Buttons here are set to FOCUS_NONE so the
	# control-group keys keep working, and a focus ring on a button that cannot hold
	# focus is a lie.
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT)
	# **The selected-and-hovered state.** Without it Godot falls back to `hover`, so
	# running the mouse along the settings rows made the *chosen* option look unchosen --
	# in all four toggle groups (shift length, call rate, time of day, weather).
	theme.set_stylebox("hover_pressed", "Button",
		_box(Palette.HOVER.lerp(Palette.PRESSED, 0.6), TILE_RADIUS, 8))
	theme.set_color("font_pressed_color", "Button", Palette.MEDICAL_DEEP)
	theme.set_color("font_hover_pressed_color", "Button", Palette.MEDICAL_DEEP)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_DISABLED)
	theme.set_font_size("font_size", "Button", FONT_SIZE)


# --- Sliders -----------------------------------------------------------------

## The volume slider was the one control in the game with no theme entry at all --
## stock Godot, a mid-grey grabber, invisible until you went looking for it.
func _sliders(theme: Theme) -> void:
	theme.add_type("HSlider")
	# **The track's height is its content margin**, which is the whole trap here. The
	# first cut passed padding 0 -- correct for a card, meaningless for a slider -- and
	# baked a track zero pixels high. The volume grabber floated on nothing, which is
	# worse than the stock control it replaced.
	theme.set_stylebox("slider", "HSlider", _box(Palette.WELL, TRACK_HEIGHT / 2, 0,
		TRACK_HEIGHT / 2))
	theme.set_stylebox("grabber_area", "HSlider",
		_box(Palette.SELECTED, TRACK_HEIGHT / 2, 0, TRACK_HEIGHT / 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider",
		_box(Palette.ACCENT, TRACK_HEIGHT / 2, 0, TRACK_HEIGHT / 2))
	var knob := StyleBoxFlat.new()
	knob.bg_color = Palette.TEXT
	knob.set_corner_radius_all(PILL_RADIUS)
	knob.content_margin_left = KNOB_RADIUS
	knob.content_margin_right = KNOB_RADIUS
	knob.content_margin_top = KNOB_RADIUS
	knob.content_margin_bottom = KNOB_RADIUS
	theme.set_stylebox("grabber", "HSlider", knob)
	var lit := knob.duplicate() as StyleBoxFlat
	lit.bg_color = Palette.SELECTED
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


## [param vertical] defaults to [param padding]; a slider needs its two axes to differ,
## because the horizontal margin insets the track's ends while the vertical one *is* its
## height.
func _box(colour: Color, radius: int, padding: int, vertical := -1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding if vertical < 0 else vertical
	box.content_margin_bottom = padding if vertical < 0 else vertical
	return box
