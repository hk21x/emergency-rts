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
	panel.theme_type_variation = &"CardPanel"
	centre.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
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

	var shelf := HBoxContainer.new()
	shelf.add_theme_constant_override("separation", 10)
	body.add_child(shelf)
	for config in Station.TYPES:
		shelf.add_child(_build_card(config))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(footer)
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(180.0, 34.0)
	close.pressed.connect(close_shop)
	footer.add_child(close)


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
	var card := PanelContainer.new()
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.11, 0.115, 0.125)
	well.set_corner_radius_all(6)
	well.set_content_margin_all(10.0)
	card.add_theme_stylebox_override("panel", well)
	card.custom_minimum_size = Vector2(200.0, 0.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)

	var portrait := TextureRect.new()
	var picture := PORTRAITS + str(config["portrait"]) + ".png"
	if ResourceLoader.exists(picture):
		portrait.texture = load(picture)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(120.0, 96.0)
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

	_cards[config["id"]] = {"buy": buy, "owned": owned}
	return card


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
