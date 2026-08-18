class_name UnitPurchaseModal
extends Control
## Unit requisition modal.
##
##   var m := preload("res://ui/unit_purchase_modal.tscn").instantiate()
##   add_child(m)
##   m.open(12450)
##   m.confirmed.connect(func(order, total): dispatch(order))

signal confirmed(order: Dictionary, total: int)   ## { StringName: int }, total cost
signal cancelled

## **Zero by default here, and that is a deliberate choice rather than an oversight.** The
## kit charges a flat fee per order; this career has never had one, and switching front
## ends is no reason to start charging the player money. Set it from the host if the fee is
## ever wanted as a mechanic.
@export var deployment_fee: int = 0

const CATEGORIES := [
	[&"all", "ALL"], [&"fire", "FIRE"], [&"police", "POLICE"],
	[&"medical", "MEDICAL"], [&"support", "SUPPORT"],
]

var budget: int = 12450
var _order: Dictionary = {}            # StringName -> int
var _units: Array[UnitDef] = []
var _cards: Dictionary = {}            # StringName -> UnitCard
var _rows: Dictionary = {}             # StringName -> OrderRow
var _filter: StringName = &"all"

@onready var _tabs: HBoxContainer = %Tabs
@onready var _grid: GridContainer = %Grid
@onready var _order_list: VBoxContainer = %OrderList
@onready var _empty: Label = %EmptyHint
@onready var _count: Label = %OrderCount
@onready var _budget_value: Label = %BudgetValue
@onready var _subtotal: Label = %SubtotalValue
@onready var _fee: Label = %FeeValue
@onready var _remaining: Label = %RemainingValue
@onready var _total: Label = %TotalValue
@onready var _total_panel: PanelContainer = %TotalPanel
@onready var _deploy: Button = %DeployButton


func _ready() -> void:
	# **Sourced from the game's own catalogue, not the kit's sample one.** `UnitCatalog`'s
	# own comment says to swap this out once the roster settles; [ShopCatalogue] is that
	# swap, reading `Station.TYPES` so a unit is still described in exactly one place.
	_units = ShopCatalogue.units()
	_scroll_the_order_list()
	_build_tabs()
	_build_cards()
	%CloseButton.pressed.connect(_on_cancel)
	%CancelButton.pressed.connect(_on_cancel)
	_deploy.pressed.connect(_on_confirm)
	%Scrim.gui_input.connect(_on_scrim_input)
	_refresh()


func open(starting_budget: int = -1) -> void:
	if starting_budget >= 0:
		budget = starting_budget
	_order.clear()
	visible = true
	_refresh()
	for c in _grid.get_children():
		if c is UnitCard and not c.disabled:
			c.grab_focus()
			break


## Puts the order list inside a [ScrollContainer].
##
## **So the cart cannot resize the dialog.** `OrderList` is a plain [VBoxContainer] and the
## modal sizes itself around its contents, so every unit added made the window taller --
## reported from play with three units in the cart and the dialog filling the screen. The
## rows are 52px again now, but thirteen of them is still 750px against a body of about
## 430, so the list needs somewhere to put the overflow that is not the modal's height.
##
## Done in code rather than by editing `unit_purchase_modal.tscn`, so the kit's scene stays
## exactly as shipped -- the same reasoning as everything else adapted here.
func _scroll_the_order_list() -> void:
	var holder := _order_list.get_parent() as Control
	if holder == null or holder is ScrollContainer:
		return
	var scroll := ScrollContainer.new()
	scroll.name = "OrderScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slot := _order_list.get_index()
	holder.remove_child(_order_list)
	holder.add_child(scroll)
	holder.move_child(scroll, slot)
	scroll.add_child(_order_list)
	_order_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


# ---------------------------------------------------------------- building --
func _build_tabs() -> void:
	# Only the tabs that have something behind them. The kit ships a SUPPORT category and
	# this roster has no support units, so the tab would open onto an empty grid -- which
	# reads as a bug rather than as an empty category.
	var present := ShopCatalogue.categories()
	for id in CATEGORIES:
		if id[0] != &"all" and not present.has(id[0]):
			continue
		var b := Button.new()
		b.text = id[1]
		b.theme_type_variation = &"ERSTertiary" if id[0] == _filter else &"ERSSmall"
		b.toggle_mode = false
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(_on_filter.bind(id[0]))
		b.set_meta(&"cat", id[0])
		_tabs.add_child(b)


func _build_cards() -> void:
	for u in _units:
		var card := UnitCard.new()
		_grid.add_child(card)
		card.setup(u)
		card.add_requested.connect(_on_add)
		_cards[u.id] = card


## The card for [param id], or null. Exposed for the host: the tutorial pulses a named
## card, and reaching into `_cards` from outside would tie that caller to this file's
## private shape.
func card_for(id: StringName) -> UnitCard:
	return _cards.get(id)


## Every card, by id. For the host and its checks.
func cards() -> Dictionary:
	return _cards


## The confirm button. Disabled until the order is non-empty and affordable.
func deploy_button() -> Button:
	return _deploy


## The category tabs, in the order they are shown.
func tab_buttons() -> Array[Node]:
	return _tabs.get_children()


# ------------------------------------------------------------------ events --
func _on_filter(cat: StringName) -> void:
	_filter = cat
	for b in _tabs.get_children():
		b.theme_type_variation = (&"ERSTertiary" if b.get_meta(&"cat") == cat
				else &"ERSSmall")
	_refresh()


func _on_add(u: UnitDef) -> void:
	_change(u, 1)


func _change(u: UnitDef, delta: int) -> void:
	var qty: int = int(_order.get(u.id, 0)) + delta
	qty = maxi(qty, 0)
	if u.stock > 0:
		qty = mini(qty, u.stock)
	if delta > 0 and _spend_with(u, delta) > budget:
		return
	if qty == 0:
		_order.erase(u.id)
	else:
		_order[u.id] = qty
	_refresh()


func _on_cancel() -> void:
	cancelled.emit()
	visible = false


func _on_confirm() -> void:
	confirmed.emit(_order.duplicate(), _total_cost())
	visible = false


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_cancel()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- money --
func _by_id(id: StringName) -> UnitDef:
	for u in _units:
		if u.id == id:
			return u
	return null


func _subtotal_cost() -> int:
	var sum := 0
	for id in _order:
		sum += _by_id(id).cost * int(_order[id])
	return sum


func _total_cost() -> int:
	return _subtotal_cost() + (deployment_fee if not _order.is_empty() else 0)


func _spend_with(u: UnitDef, extra: int) -> int:
	var fee := deployment_fee if (not _order.is_empty() or extra > 0) else 0
	return _subtotal_cost() + u.cost * extra + fee


# ----------------------------------------------------------------- refresh --
func _refresh() -> void:
	var total := _total_cost()
	var remaining := budget - total

	for u in _units:
		var card: UnitCard = _cards[u.id]
		card.visible = _filter == &"all" or u.category == _filter
		var qty := int(_order.get(u.id, 0))
		card.set_state(qty, _spend_with(u, 1) <= budget)

	_sync_order_rows()

	_budget_value.text = "£ %s" % UnitCard._thousands(budget)
	_subtotal.text = "£ %s" % UnitCard._thousands(_subtotal_cost())
	_fee.text = "£ %s" % UnitCard._thousands(deployment_fee if not _order.is_empty() else 0)
	_remaining.text = "£ %s" % UnitCard._thousands(remaining)
	_remaining.add_theme_color_override("font_color",
			Color(0.4314, 0.8157, 0.4941) if remaining >= 0 else Color(0.9412, 0.4471, 0.3608))
	_total.text = "£ %s" % UnitCard._thousands(total)
	_total_panel.theme_type_variation = (&"ERSCostPill" if remaining >= 0
			else &"ERSCostPillOver")

	var n := 0
	for id in _order:
		n += int(_order[id])
	_count.text = "%d UNIT%s" % [n, "" if n == 1 else "S"]
	_empty.visible = _order.is_empty()
	_deploy.disabled = _order.is_empty() or remaining < 0


func _sync_order_rows() -> void:
	for id in _rows.keys():
		if not _order.has(id):
			_rows[id].queue_free()
			_rows.erase(id)
	for id in _order:
		var u := _by_id(id)
		var qty := int(_order[id])
		var can_add := _spend_with(u, 1) <= budget and (u.stock == 0 or qty < u.stock)
		if _rows.has(id):
			_rows[id].refresh(qty, can_add)
		else:
			var row := OrderRow.new()
			_order_list.add_child(row)
			row.setup(u, qty, can_add)
			row.changed.connect(_change)
			_rows[id] = row
