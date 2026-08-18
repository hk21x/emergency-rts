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

@export var deployment_fee: int = 350

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
	_units = UnitCatalog.default_units()
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


# ---------------------------------------------------------------- building --
func _build_tabs() -> void:
	for id in CATEGORIES:
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
