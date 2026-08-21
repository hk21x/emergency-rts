extends Control
class_name RequisitionPanel

## Hosts the Emergency Ops requisition modal and connects it to the career.
##
## **A drop-in for the old `ShopPanel`, on purpose.** It keeps that class's four public
## names --
## `station`, `open_shop`, `close_shop`, `card_button` -- because three unrelated places
## reach for them: [HUD] wires the buy button, [GameMenu] closes the shop before it will
## open the pause card, and [TutorialDirector] spotlights a named card. Matching the
## surface meant the swap touched one line of `HUD.tscn` and nothing else, which matters
## most for the `Esc` chain: sabotaging that ordering reddens ~150 checks, because a
## district that pauses when the player meant "cancel" stays paused for every check after.
##
## The modal is instanced here rather than embedded in `HUD.tscn` so the kit's scene stays
## exactly as shipped -- it is 400 files of theme, fonts and art, and hand-merging it into
## a scene we regenerate would be a second copy to keep in step.
##
## **The shape of buying changed.** The old storefront sold one unit per click; this is a
## cart -- pick several, then confirm. So the career is charged once, on `confirmed`, and
## the modal is told the purse each time it opens.

const MODAL := "res://ui/unit_purchase_modal.tscn"

var station: Station

var _modal: UnitPurchaseModal


func _ready() -> void:
	var packed := load(MODAL) as PackedScene
	if packed == null:
		push_warning("RequisitionPanel could not load %s" % MODAL)
		return
	_modal = packed.instantiate() as UnitPurchaseModal
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	visible = false
	_modal.confirmed.connect(_on_confirmed)
	_modal.cancelled.connect(close_shop)


## **This node's own `visible` is the open state**, not the modal's, and that is load
## bearing. [GameMenu] and [TutorialDirector] both read `shop.visible` off the node they
## find at `Root/Shop` -- so a host that stayed visible while its child toggled would tell
## the pause menu the shop was open for ever, and `Esc` would never reach pause. A hidden
## parent hides the child anyway, so the modal is simply left visible inside.


## Open, showing whatever the career can currently afford.
func open_shop() -> void:
	if _modal == null or station == null:
		return
	visible = true
	_modal.visible = true
	_modal.open(station.funds)


## Close without buying. Named for the pause menu, which calls it to claim `Esc`.
func close_shop() -> void:
	visible = false


## True while the modal is up. [GameMenu] asks before taking `Esc`.
func is_open() -> bool:
	return visible


## The card for [param id], or null. [TutorialDirector] pulses it; [UnitCard] is a
## [Button], which is what that caller expects.
func card_button(id: StringName) -> Button:
	if _modal == null:
		return null
	return _modal.card_for(id)


## Escape closes the shop, and while it is open no other key reaches the district.
##
## **Both halves matter, and dropping this broke the pause chain.** The first swap left
## input entirely to the modal's own `_unhandled_input`; the shop then never closed, so
## [GameMenu]'s `_escape_is_spoken_for()` saw an open shop for the rest of the session and
## `Esc` could never reach pause again. Three checks went red and, worse, two others
## passed *vacuously* -- "Escape again resumes" is trivially true when Escape never did
## anything and the district was never frozen.
##
## The blanket `set_input_as_handled()` is the second half, inherited deliberately from
## the old `ShopPanel`: while the storefront is up, `F2` must not open a shift under it.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		close_shop()
	get_viewport().set_input_as_handled()


## Every card by id, the confirm button, and the tabs. Proxied rather than reached for
## through `_modal`, so the checks are tied to this seam and not to the kit's internals.
func cards() -> Dictionary:
	return _modal.cards() if _modal else {}


func deploy_button() -> Button:
	return _modal.deploy_button() if _modal else null


func tab_buttons() -> Array[Node]:
	return _modal.tab_buttons() if _modal else []


## Charges the career once for the whole order.
##
## Purchases go through [method Station.purchase] one at a time rather than by adjusting
## funds directly: that method is what writes the career file and keeps `owned` in step,
## and a cart that debited the purse itself would be a second place that knows the price.
func _on_confirmed(order: Dictionary, _total: int) -> void:
	if station == null:
		return
	close_shop()
	for id: StringName in order:
		for i in int(order[id]):
			if not station.purchase(id):
				# Funds ran out mid-order, or the catalogue moved under us. Stop rather
				# than keep asking: the modal already refused anything unaffordable at the
				# time it was confirmed, so this is the unexpected case.
				break
