extends Control
## Standalone host so you can run the modal on its own (F6 on this scene).

func _ready() -> void:
	var modal: UnitPurchaseModal = %Modal
	modal.confirmed.connect(func(order: Dictionary, total: int):
		print("Dispatching %s for £%d" % [order, total]))
	modal.cancelled.connect(func(): print("Requisition cancelled"))
	modal.open(12450)
