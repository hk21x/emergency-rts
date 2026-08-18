extends Control
## Main menu wiring. Each entry emits a signal — connect them to your own
## scene loads rather than hard-coding paths here.

signal entry_chosen(id: StringName)

@onready var _column: VBoxContainer = %MenuColumn
@onready var _notices: ERSNotificationLayer = %NotificationLayer


func _ready() -> void:
	for child in _column.get_children():
		if child is Button:
			child.pressed.connect(_on_entry.bind(child.name))
	if _column.get_child_count() > 0:
		_column.get_child(0).grab_focus()


func _on_entry(id: StringName) -> void:
	entry_chosen.emit(id)
	match id:
		&"Exit":
			get_tree().quit()
		_:
			_notices.push("%s is not wired up yet." % str(id),
					ERSNotificationLayer.Kind.INFO)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_notices.push("Nothing to go back to from here.",
				ERSNotificationLayer.Kind.WARNING)
