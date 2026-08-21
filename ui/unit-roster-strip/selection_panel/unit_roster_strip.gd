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

const ICON := "res://selection_panel/art/icons/icon_%s.svg"
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


func _needs_attention(u: UnitInstance) -> bool:
	return u.condition < 0.35 or u.status == UnitInstance.Status.OFF_RUN


func _icon_name(u: UnitInstance) -> String:
	if u.def and u.def.icon:
		return u.def.icon.resource_path.get_file().trim_prefix("icon_").trim_suffix(".svg")
	return "truck"


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
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)

	var stripe := Panel.new()
	stripe.custom_minimum_size = Vector2(0, 4)
	stripe.add_theme_stylebox_override("panel", _flat(u.status_color()))
	col.add_child(stripe)

	var status := Label.new()
	status.text = u.status_label()
	status.add_theme_font_size_override("font_size", 9)
	status.add_theme_color_override("font_color", u.status_color())
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.theme_type_variation = &"ERSEyebrow"
	col.add_child(status)

	var port := PanelContainer.new()
	port.theme_type_variation = &"ERSPortraitLarge"
	port.custom_minimum_size = Vector2(44, 44)
	port.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(port)
	var g := TextureRect.new()
	g.texture = load(ICON % _icon_name(u))
	g.custom_minimum_size = Vector2(22, 22)
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port.add_child(g)

	var cs := Label.new()
	cs.text = u.callsign
	cs.theme_type_variation = &"ERSTitle"
	cs.add_theme_font_size_override("font_size", 15)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cs)

	var ty := Label.new()
	ty.text = u.def.display_name if u.def else ""
	ty.add_theme_font_size_override("font_size", 10)
	ty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ty.clip_text = true
	col.add_child(ty)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 5)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", _flat(Color(0.031, 0.051, 0.078)))
	foot.add_child(track)
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(u.condition, 0.0, 1.0)
	fill.add_theme_stylebox_override("panel", _flat(
			Color("4caf50") if u.condition >= 0.6
			else Color("d8aa33") if u.condition >= 0.35 else Color("c4442f")))
	track.add_child(fill)
	var seats := Label.new()
	seats.text = "%d/%d" % [u.seats_taken(), u.seats_total()]
	seats.add_theme_font_size_override("font_size", 10)
	foot.add_child(seats)

	b.set_meta(&"parts", {&"glyph": g, &"callsign": cs, &"type": ty, &"seats": seats})
	_style_card(b, u)
	return b


func _style_card(b: Button, u: UnitInstance) -> void:
	var alert := _needs_attention(u)
	var is_sel := u == selected
	b.theme_type_variation = (&"ERSRosterCardSelected" if is_sel
			else &"ERSRosterCardAlert" if alert else &"ERSRosterCard")
	var parts: Dictionary = b.get_meta(&"parts")
	parts[&"glyph"].modulate = (Color("7fb8f5") if is_sel
			else Color("e8735c") if alert else DIM)
	parts[&"callsign"].add_theme_color_override("font_color", TEXT)
	parts[&"type"].add_theme_color_override("font_color", DIM)
	parts[&"seats"].add_theme_color_override("font_color", DIM)


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
