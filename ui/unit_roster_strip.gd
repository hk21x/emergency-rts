@tool
class_name UnitRosterStrip
extends Control
## Horizontal fleet strip: one card per unit, scrolled sideways, clickable.
##
##   strip.set_units(all_units)
##   strip.unit_picked.connect(func(u): select(u))
##   strip.unit_focused.connect(func(u): camera.centre_on(u))   # double-click
##
## Works as the bottom bar's idle state or on its own anywhere you can dock a
## 1100x140 control.

signal unit_picked(unit: UnitInstance)
signal unit_focused(unit: UnitInstance)

## URGENCY puts anything needing a decision on the left, so the units you care
## about are never the ones you have to scroll to find. That's the whole reason
## a strip survives a fleet it can't show at once.
enum Sort { URGENCY, STATUS, CALLSIGN, SERVICE }

const ICON := "res://ui/art/icons/icon_%s.svg"
const TEXT := Color(0.8745, 0.9059, 0.9412)
const DIM := Color(0.5608, 0.6275, 0.6980)
const OFF := Color(0.3333, 0.3882, 0.4353)

const URGENCY_RANK := {
	UnitInstance.Status.OFF_RUN: 0, UnitInstance.Status.ON_SCENE: 1,
	UnitInstance.Status.EN_ROUTE: 2, UnitInstance.Status.RETURNING: 3,
	UnitInstance.Status.AVAILABLE: 4,
}
const SERVICE_RANK := {&"fire": 0, &"police": 1, &"medical": 2, &"support": 3}

@export var sort_mode: Sort = Sort.URGENCY:
	set(v):
		sort_mode = v
		if is_node_ready():
			## Re-sorting mid-scroll leaves you looking at an arbitrary window,
			## so jump back to the start where the new ordering makes sense.
			_scroll.scroll_horizontal = 0
			_rebuild()
@export var card_width: int = 116
## Scroll the selected card back into view whenever selection changes.
@export var follow_selection: bool = true
## How far one press of an edge chevron travels, in cards.
@export var page_cards: int = 3
@export var preview_in_editor: bool = true:
	set(v):
		preview_in_editor = v
		if is_inside_tree():
			_apply_preview()

var units: Array[UnitInstance] = []
var selected: UnitInstance

var _cards: Dictionary = {}          # UnitInstance -> Button
var _tween: Tween

@onready var _scroll: ScrollContainer = %Scroll
@onready var _row: HBoxContainer = %Cards
@onready var _prev: Button = %PrevButton
@onready var _next: Button = %NextButton
@onready var _empty: Label = %EmptyLabel


func _ready() -> void:
	custom_minimum_size.y = 140
	_prev.pressed.connect(_page.bind(-1))
	_next.pressed.connect(_page.bind(1))
	_scroll.get_h_scroll_bar().value_changed.connect(func(_v): _update_edges())
	resized.connect(_update_edges)
	_apply_preview()


func _apply_preview() -> void:
	if units.is_empty() and Engine.is_editor_hint() and preview_in_editor:
		set_units(_sample_fleet())
	else:
		_rebuild()


# ------------------------------------------------------------------- public --
func set_units(list: Array) -> void:
	units.clear()
	for u in list:
		units.append(u)
	_rebuild()


func select(u: UnitInstance) -> void:
	selected = u
	for unit in _cards:
		_style_card(_cards[unit], unit)
	if follow_selection and u != null and _cards.has(u):
		_scroll.ensure_control_visible(_cards[u])


func clear_selection() -> void:
	select(null)


## Call after mutating units in place — the strip doesn't poll.
func refresh() -> void:
	_rebuild()


## Repaints the cards that are already there, without tearing any of them down.
##
## **The difference matters more than it looks.** `_rebuild()` frees every card and builds
## it again, and `Button.pressed` fires on *release* -- so a rebuild between press and
## release presses a button that no longer exists, and the click is simply lost. A bar that
## refreshed by rebuilding ate clicks on a timer.
##
## So a caller with a changed *list* calls `set_units`, and a caller whose units merely
## changed their *values* -- a repair bill, a status, a crew getting in -- calls this.
func restate() -> void:
	for card in _row.get_children():
		var b := card as Button
		if b == null or not b.has_meta(&"parts"):
			continue
		var parts: Dictionary = b.get_meta(&"parts")
		var u: UnitInstance = parts.get(&"unit")
		if u == null:
			continue
		_style_card(b, u)


# ------------------------------------------------------------------ sorting --
func _sorted() -> Array:
	var out := units.duplicate()
	match sort_mode:
		Sort.URGENCY:
			out.sort_custom(func(a, b):
				var ra := _urgency(a)
				var rb := _urgency(b)
				if ra != rb:
					return ra < rb
				return a.callsign < b.callsign)
		Sort.STATUS:
			out.sort_custom(func(a, b):
				if a.status != b.status:
					return URGENCY_RANK[a.status] < URGENCY_RANK[b.status]
				return a.callsign < b.callsign)
		Sort.SERVICE:
			out.sort_custom(func(a, b):
				var ra: int = SERVICE_RANK.get(a.def.category if a.def else &"support", 9)
				var rb: int = SERVICE_RANK.get(b.def.category if b.def else &"support", 9)
				if ra != rb:
					return ra < rb
				return a.callsign < b.callsign)
		Sort.CALLSIGN:
			out.sort_custom(func(a, b): return a.callsign < b.callsign)
	return out


func _urgency(u: UnitInstance) -> int:
	## Damage outranks status: a wrecked engine sitting "available" still wants
	## looking at before a healthy one that happens to be on scene.
	if u.condition < 0.35:
		return -1
	return URGENCY_RANK.get(u.status, 5)


# ----------------------------------------------------------------- building --
func _rebuild() -> void:
	if not is_node_ready():
		return
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	_cards.clear()

	_empty.visible = units.is_empty()
	_scroll.visible = not units.is_empty()
	for u in _sorted():
		var card := _card(u)
		_row.add_child(card)
		_cards[u] = card
	call_deferred("_update_edges")


func _flat(c: Color, r: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	return sb


## Whether this card wears the red alert border.
##
## **Delegated, because the private copy reintroduced a bug the model already fixed.** It
## read `condition < 0.35` with no floor -- and a negative condition means *this unit has
## none*, not that it is wrecked. Aircraft report -1 (no health, no repair bill), so every
## helicopter on the strip wore the damaged styling while reporting itself AVAILABLE
## beside it.
##
## `UnitInstance.needs_attention()` carries the `condition >= 0.0` guard and a comment
## recording the same fault the first time it was found, on the roster rows. A sentinel is
## only safe while every reader knows it is one -- so there is one reader now.
func _needs_attention(u: UnitInstance) -> bool:
	return u.needs_attention()


## The picture for a card.
##
## **The texture itself, not a name derived back out of its path.** The strip shipped
## deriving `icon_<name>.svg` from `def.icon.resource_path` and loading it a second time,
## which works only while every icon is one of the kit's own SVGs. This game hands it the
## rendered unit portraits: a `.png`, and often an [AtlasTexture] crop of one, whose
## `resource_path` is empty -- so the round trip asked for `res://ui/art/icons/icon_.svg`
## and flooded the run with "Resource file not found".
##
## Using what it was given also makes the card match the rest of the bar, which draws the
## same portrait.
func _card_icon(u: UnitInstance) -> Texture2D:
	if u.def and u.def.icon:
		return u.def.icon
	return load(ICON % "truck") as Texture2D


## The card standing for [param u], or null when it is not on the strip -- which is the
## normal answer, not a fault: the strip shows one service at a time.
func card_for(u: UnitInstance) -> Button:
	return _cards.get(u)


func _card(u: UnitInstance) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(card_width, 124)
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "%s — %s\n%s · %d/%d aboard · %d%%" % [
		u.callsign, u.def.display_name if u.def else "",
		u.status_label().capitalize(), u.seats_taken(), u.seats_total(),
		roundi(u.condition * 100)]
	b.pressed.connect(func():
		select(u)
		unit_picked.emit(u))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.double_click \
				and e.button_index == MOUSE_BUTTON_LEFT:
			unit_focused.emit(u))
	## Keyboard and gamepad walk the row for free because the cards are focusable
	## siblings — this just keeps the viewport following along.
	b.focus_entered.connect(func(): _scroll.ensure_control_visible(b))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_top = 4
	col.offset_right = -8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 4)
	col.name = "Body"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)

	var stripe := Panel.new()
	stripe.name = "StatusStripe"
	stripe.custom_minimum_size = Vector2(0, 4)
	stripe.add_theme_stylebox_override("panel", _flat(u.status_color()))
	col.add_child(stripe)

	var status := Label.new()
	status.name = "StatusLabel"
	status.text = u.status_label()
	status.add_theme_font_size_override("font_size", 9)
	status.add_theme_color_override("font_color", u.status_color())
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.theme_type_variation = &"ERSEyebrow"
	col.add_child(status)

	var port := PanelContainer.new()
	port.name = "PortraitFrame"
	port.theme_type_variation = &"ERSPortraitLarge"
	port.custom_minimum_size = Vector2(44, 44)
	port.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(port)
	var g := TextureRect.new()
	g.name = "Portrait"
	g.texture = _card_icon(u)
	g.custom_minimum_size = Vector2(22, 22)
	# **`EXPAND_IGNORE_SIZE`, or the picture sets the card's size.** A `TextureRect`
	# defaults to `EXPAND_KEEP_SIZE`, which reports the *texture's* dimensions as its
	# minimum -- `custom_minimum_size` is only a floor. The kit's own icons are 22px SVGs
	# so it never showed; this game hands it 192px unit renders, and a character portrait
	# (which fills its frame and so is never cropped) blew each card up to the height of
	# the bar with the face spilling out of the tile.
	#
	# That is the sixth time this exact default has cost this project a bug.
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port.add_child(g)

	var cs := Label.new()
	cs.name = "Callsign"
	cs.text = u.callsign
	cs.theme_type_variation = &"ERSTitle"
	cs.add_theme_font_size_override("font_size", 15)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cs)

	var ty := Label.new()
	ty.name = "TypeName"
	ty.text = u.def.display_name if u.def else ""
	ty.add_theme_font_size_override("font_size", 10)
	ty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ty.clip_text = true
	col.add_child(ty)

	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	var track := Panel.new()
	track.name = "ConditionTrack"
	track.custom_minimum_size = Vector2(0, 5)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078)))
	foot.add_child(track)
	var fill := Panel.new()
	fill.name = "ConditionFill"
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(u.condition, 0.0, 1.0)
	fill.add_theme_stylebox_override("panel", _flat(
			Color("4caf50") if u.condition >= 0.6
			else Color("d8aa33") if u.condition >= 0.35 else Color("c4442f")))
	track.add_child(fill)
	var seats := Label.new()
	seats.name = "SeatCount"
	seats.text = _foot_text(u)
	seats.add_theme_font_size_override("font_size", 10)
	foot.add_child(seats)

	# **Everything inside a card is decoration, and decoration must not eat the click.**
	# `mouse_filter` is per-node and does **not** inherit, so setting it on the VBox above
	# leaves every child sitting on its own default -- and those defaults are not what they
	# look like. Measured rather than assumed, because guessing them is how this got here:
	#
	#     Label IGNORE | VBox/HBox PASS | TextureRect PASS | Panel STOP | PanelContainer STOP
	#
	# So the avatar's own `TextureRect` was innocent: it passes the click up, straight into
	# the `PanelContainer` frame around it, which stops it dead before the Button ever sees
	# it. The status stripe and the condition track are `Panel`s and swallowed their own
	# rectangles the same way. The avatar is simply the one players noticed, being the
	# biggest target on the card and the most obviously a thing you would click.
	#
	# Every part above is given a `name`, and that is for the check rather than the game:
	# these are all built with `Type.new()`, so without one Godot auto-generates
	# `@Panel@8612` and the failure line reads as three indistinguishable panels with a
	# per-run instance counter that cannot be grepped or compared between runs. Named, the
	# same line says `StatusStripe, PortraitFrame, ConditionTrack` and needs no explaining.
	#
	# Blanket rather than naming the three: nothing inside a card takes input of its own,
	# and a fourth decoration added later would otherwise arrive carrying the same bug.
	# `find_children` returns descendants only, so the Button itself keeps its STOP and
	# stays clickable -- a sweep that caught `b` too would kill the whole card.
	for node in b.find_children("*", "Control", true, false):
		var part := node as Control
		if part:
			part.mouse_filter = Control.MOUSE_FILTER_IGNORE

	b.set_meta(&"parts", {&"glyph": g, &"callsign": cs, &"type": ty, &"seats": seats,
			&"fill": fill, &"unit": u})
	_style_card(b, u)
	return b


## What the bottom-right of a card says: the repair bill if it owes one, else the seats.
##
## **The bill wins, because it is why the card is red.** A vehicle's condition here *is*
## its outstanding repair, so a card could go red while the only figure on it was a seat
## count that had not changed -- which is a border with no explanation, and it was asked
## about twice. A unit that owes money says so; everything else goes on showing who is
## aboard, which is the more useful number when there is nothing to pay.
func _foot_text(u: UnitInstance) -> String:
	if u.owed > 0:
		return "£%s" % _thousands(u.owed)
	# **Nothing at all for a unit with no seats.** A person is on this strip too, and
	# `0 / 0` is not a readout -- it is a number that looks like a fault. Only something
	# that can carry anybody says how many it is carrying.
	if u.seats_total() <= 0:
		return ""
	return "%d/%d" % [u.seats_taken(), u.seats_total()]


## 1234 -> "1,234". The bill is the only number here that gets big enough to need it.
func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _style_card(b: Button, u: UnitInstance) -> void:
	var parts: Dictionary = b.get_meta(&"parts") if b.has_meta(&"parts") else {}
	var fill := parts.get(&"fill") as Panel
	if fill:
		fill.anchor_right = clampf(u.condition, 0.0, 1.0)
		fill.add_theme_stylebox_override("panel", _flat(
				Color("4caf50") if u.condition >= 0.6
				else Color("d8aa33") if u.condition >= 0.35 else Color("c4442f")))
	var alert := _needs_attention(u)
	var is_sel := u == selected
	b.theme_type_variation = (&"ERSRosterCardSelected" if is_sel
			else &"ERSRosterCardAlert" if alert else &"ERSRosterCard")
	if parts.is_empty():
		return
	# Untinted here too, and for the same reason: these are renders, not glyphs. The card
	# already says its state three other ways -- the border, the status stripe and the
	# status word -- so a colour wash over the picture only makes the vehicle harder to
	# recognise, which is the one job the picture has.
	parts[&"glyph"].modulate = Color.WHITE
	parts[&"callsign"].add_theme_color_override("font_color", TEXT)
	parts[&"type"].add_theme_color_override("font_color", DIM)
	parts[&"seats"].text = _foot_text(u)
	parts[&"seats"].add_theme_color_override("font_color",
			Color("e8735c") if u.owed > 0 else DIM)


# ------------------------------------------------------------------ scroll ---
func _gui_input(event: InputEvent) -> void:
	## A horizontal ScrollContainer ignores the wheel by default, which feels
	## broken the first time anyone tries it.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_nudge(card_width + 10)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_nudge(-(card_width + 10))
			accept_event()


func _nudge(delta: float) -> void:
	_scroll.scroll_horizontal += int(delta)
	_update_edges()


func _page(direction: int) -> void:
	var target: float = _scroll.scroll_horizontal + direction * (card_width + 10) * page_cards
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_scroll, "scroll_horizontal", int(target), 0.22)
	_tween.tween_callback(_update_edges)


func _update_edges() -> void:
	if not is_node_ready():
		return
	var bar := _scroll.get_h_scroll_bar()
	var scrollable: bool = bar.max_value > bar.page + 1
	_prev.visible = scrollable
	_next.visible = scrollable
	if scrollable:
		_prev.disabled = _scroll.scroll_horizontal <= 0
		_next.disabled = _scroll.scroll_horizontal >= int(bar.max_value - bar.page) - 1


# ------------------------------------------------------------------ sample ---
static func _sample_fleet() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	var spec := [["F01", "Fire Engine", &"fire", "truck", 6, UnitInstance.Status.EN_ROUTE, 0.94, 5],
		["A14", "Ambulance", &"medical", "medical", 4, UnitInstance.Status.ON_SCENE, 0.62, 3],
		["P21", "Patrol Car", &"police", "shield_person", 4, UnitInstance.Status.ON_SCENE, 0.86, 3],
		["F02", "Fire Engine", &"fire", "truck", 6, UnitInstance.Status.OFF_RUN, 0.24, 1],
		["A15", "Ambulance", &"medical", "medical", 4, UnitInstance.Status.AVAILABLE, 1.0, 2]]
	for r in spec:
		var d := UnitDef.new()
		d.display_name = r[1]
		d.category = r[2]
		d.icon = load(ICON % r[3])
		d.seats = r[4]
		var u := UnitInstance.new()
		u.def = d
		u.callsign = r[0]
		u.status = r[5]
		u.condition = r[6]
		var occ: Array[StringName] = []
		for i in int(r[7]):
			occ.append(&"driver" if i == 0 else &"firefighter")
		u.occupants = occ
		out.append(u)
	return out
