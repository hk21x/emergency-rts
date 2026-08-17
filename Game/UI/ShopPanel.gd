extends Control
class_name ShopPanel

## The unit shop: a proper storefront over the district, opened from the DISPATCH
## block. One card per type -- the rendered portrait, the price, what the unit is
## actually for, how many are owned -- and a BUY button sized for a finger. The
## first pass hid purchasing behind chips the size of a fingernail on the bar, and
## the play feedback was immediate.
##
## An overlay like the menu's cards, but game-side: it does **not** pause, so buying
## mid-shift while the district burns is a choice the player is allowed to make.
## While it is open the mouse stops here and the keyboard is swallowed -- command
## hotkeys and F2 have no business firing under a shop.

const PORTRAITS := "res://Game/UI/Portraits/"

var station: Station: set = _set_station

## The shop's rows, in the order they are shown. Police first because it is the service a
## fresh career starts with, fire last because it is the one it unlocks last.
const SHELVES := [
	[Unit.Service.POLICE, "POLICE"],
	[Unit.Service.MEDICAL, "MEDICAL"],
	[Unit.Service.FIRE, "FIRE"],
]

var _purse: Label
## Type id -> the pieces that need refreshing: the BUY chip and the owned line.
var _cards := {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	# Named so a check can find the storefront itself rather than guessing at child
	# indices -- every card is a PanelContainer too, so a search by type finds nine.
	panel.name = "Storefront"
	panel.theme_type_variation = &"CardPanel"
	centre.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", Palette.STEP)
	panel.add_child(body)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	body.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"BannerLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.text = "BUY UNITS"
	header.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gap)
	_purse = Label.new()
	_purse.theme_type_variation = &"BannerLabel"
	_purse.add_theme_font_size_override("font_size", 26)
	header.add_child(_purse)

	# **One row per service, rather than one shelf for everything.** Eight types in a single
	# row ran off the side of the screen the moment the doctor and the doctor's car were
	# added -- and a row that overflows does not wrap, it clips, so the last card bought was
	# simply unreachable. Rows also read better than a wall: the player is nearly always
	# shopping for *a service*, and the four medical types now sit together instead of
	# being separated by a fire engine.
	#
	# Grouped off `config["service"]`, which every catalogue entry already carries, so a new
	# unit lands in the right row without a second list to keep in step. That mattered
	# immediately -- the doctor and the doctor's car were the first entries to be added
	# since, and neither needed a line here.
	var shelf := VBoxContainer.new()
	shelf.add_theme_constant_override("separation", Palette.WIDE)
	body.add_child(shelf)
	for group: Array in SHELVES:
		var kind: int = group[0]
		var row := _build_shelf(str(group[1]), kind)
		if row:
			shelf.add_child(row)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(footer)
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(180.0, 34.0)
	close.pressed.connect(close_shop)
	footer.add_child(close)


## One service's row: a heading in that service's own colour, and its cards beneath.
##
## Returns null when a service has nothing to sell, so an empty heading can never be left
## stranded over a blank strip -- which is what would happen if a service were ever removed
## from the catalogue rather than added to it.
func _build_shelf(heading: String, kind: int) -> Control:
	var configs: Array[Dictionary] = []
	for config: Dictionary in Station.TYPES:
		if int(config.get("service", Unit.Service.NONE)) == kind:
			configs.append(config)
	if configs.is_empty():
		return null

	var row := VBoxContainer.new()
	# Named after its heading so a check can ask what is in each service's row rather than
	# counting children by index -- the layout is three deep and index-walking it would
	# break on any tidy-up.
	row.name = "Shelf" + heading
	row.add_theme_constant_override("separation", Palette.SNUG)
	var label := Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.text = heading
	# The service's light ink rather than the header's default grey: it is the same signal
	# the roster and the selection rings use, so the player reads the row before the words.
	label.add_theme_color_override("font_color", Palette.service(kind)[2])
	row.add_child(label)

	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", Palette.STEP)
	row.add_child(cards)
	for config in configs:
		cards.add_child(_build_card(config))
	return row


func _set_station(value: Station) -> void:
	station = value
	if station:
		station.roster_changed.connect(_refresh)
		_refresh()


func open_shop() -> void:
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func close_shop() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Keyboard discipline while the shop is up: Esc closes, everything else is
## swallowed so hotkeys and F2 cannot fire underneath it.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		close_shop()
	get_viewport().set_input_as_handled()


# --- The shelf ----------------------------------------------------------------

## One type's card: portrait, name, price, what it does, how many are owned, BUY.
func _build_card(config: Dictionary) -> Control:
	# The kit's recessed panel rather than a hand-rolled well: a shop card is a thing
	# sunk into the storefront, and drawing that by hand was one more place for the
	# scheme's surface colours to be restated and then drift.
	var card := PanelContainer.new()
	card.theme_type_variation = &"InsetPanel"
	card.custom_minimum_size = Vector2(190.0, 0.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Palette.TIGHT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)

	var portrait := TextureRect.new()
	# `.get`, because the catalogue treats this key as optional and Station reads it that
	# way too -- an unguarded lookup here threw inside `_ready`, which builds the whole shop,
	# so one entry without a portrait took out every card and six unrelated checks with it.
	var picture := PORTRAITS + str(config.get("portrait", "")) + ".png"
	if ResourceLoader.exists(picture):
		portrait.texture = load(picture)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# **Shorter than it was, and that is a measurement rather than a preference.** Grouping
	# the shop into three service rows cured a horizontal overflow (one row of eight measured
	# 1906 wide in a 1600 viewport) and bought a vertical one: the storefront came out 964
	# tall against 900. Three rows multiply every vertical saving by three, and the portrait
	# is where the height is -- at the old 96 the grouped storefront still measures 916, so
	# this 24px is doing the work on its own. The rest came off the separations.
	portrait.custom_minimum_size = Vector2(108.0, 72.0)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.text = str(config["label"]).to_upper()
	name_row.add_child(name_label)
	var price := Label.new()
	price.add_theme_font_size_override("font_size", 15)
	price.text = "£%d" % int(config["price"])
	name_row.add_child(price)

	for line in config["blurb"]:
		var blurb := Label.new()
		blurb.theme_type_variation = &"DimLabel"
		blurb.add_theme_font_size_override("font_size", 11)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.text = str(line)
		box.add_child(blurb)

	var owned := Label.new()
	owned.theme_type_variation = &"HeaderLabel"
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(owned)

	var buy := Button.new()
	buy.text = "BUY"
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(120.0, 30.0)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(_on_buy.bind(config["id"]))
	box.add_child(buy)

	# The card says all of this on its face already; the tooltip is for the moment the
	# pointer is over the BUY and the eye is not.
	var told := "%s   £%d\n%s" % [str(config["label"]).to_upper(),
		int(config["price"]), "\n".join(PackedStringArray(config["blurb"]))]
	card.tooltip_text = told
	buy.tooltip_text = told

	_cards[config["id"]] = {"buy": buy, "owned": owned}
	return card


## The BUY button for [param id], or null if the shop has no such card.
##
## Public for the tutorial's spotlight: naming a unit in a prompt is not much help when
## the storefront holds eight of them, so the one being named glows.
func card_button(id: StringName) -> Button:
	var pieces: Dictionary = _cards.get(id, {})
	return pieces.get("buy") as Button if not pieces.is_empty() else null


func _refresh() -> void:
	if station == null:
		return
	if _purse:
		_purse.text = "£%d" % station.funds
	for id in _cards:
		var pieces: Dictionary = _cards[id]
		(pieces["owned"] as Label).text = "owned %d, %d in the house" \
			% [station.total(id), station.available(id)]
		(pieces["buy"] as Button).disabled = station.funds < station.price(id)


func _on_buy(id: StringName) -> void:
	if station:
		station.purchase(id)
