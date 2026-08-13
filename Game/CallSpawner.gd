extends Node
class_name CallSpawner

## Dev tool: open any call kind on demand, on **F5**.
##
## The freeplay director rolls from a weighted table, so seeing a particular call means
## opening a shift and waiting. `trapped` is 12 of about 166 weight -- roughly one call in
## fourteen -- and four kinds shipped in August 2026 that were never once looked at during
## the work that added them. Everything a check cannot judge about them (whether a blast
## reads, whether foam looks unlike water, whether a pinned casualty is legible at RTS
## zoom) can only be settled by looking, and looking should not cost five minutes of
## waiting each time.
##
## **It asks the director rather than placing anything itself.** `Director.open_kind()`
## runs the same `_clear()` and `_pick_pavement()` guards the rolled path does, which are
## what keep a call out of the inside of a building. A spawner with its own placement
## could show a fire in a wall and look like a bug in the game rather than in the tool.
##
## Third of the same shape as F3 (force a black-box record) and F4 (navigation overlay):
## a passive node that does nothing whatever until a key is pressed. That matters more
## than it sounds -- the map ships quiet by design, and a director that could start on its
## own breaks dozens of checks at once. This one cannot start anything; it can only
## forward a keypress.

## Where the tool lives on screen, and how wide. Right-hand side, clear of the roster and
## the dispatch panel on the left of the bar.
const PANEL_WIDTH := 260.0
const MARGIN := 22.0

## Toggled by the key; nothing is built until the first time it is asked for.
var _layer: CanvasLayer
var _panel: PanelContainer
var _open := false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_F5:
		return
	_open = not _open
	if _open:
		_build()
	if _layer:
		_layer.visible = _open
	get_viewport().set_input_as_handled()


## Builds the list once, from the director's own table rather than a second copy of it --
## so a call kind added to `Director.KINDS` appears here without anyone remembering to.
func _build() -> void:
	if _layer != null:
		return
	var director := _director()
	if director == null:
		return
	_layer = CanvasLayer.new()
	# Above the HUD's own layer so it is not covered by the bar.
	_layer.layer = 10
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -PANEL_WIDTH - MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	_layer.add_child(_panel)

	var body := VBoxContainer.new()
	_panel.add_child(body)
	var heading := Label.new()
	heading.text = "SPAWN A CALL   ·   F5"
	body.add_child(heading)

	for row: Dictionary in director.KINDS:
		var kind: StringName = row["id"]
		var button := Button.new()
		# The gate is named rather than hidden: `building`, `rescue`, `gas_leak` and
		# `trapped` are refused by the director unless the career owns a fire service,
		# `collapse` unless it owns a doctor, and a button that silently did nothing would
		# read as a broken tool. Read off the same table the director filters on, so a new
		# gate cannot be added there and quietly forgotten here.
		var gate := ""
		if bool(row.get("needs_fire_service", false)):
			gate = "   (needs a fire crew)"
		elif bool(row.get("needs_doctor", false)):
			gate = "   (needs a doctor)"
		button.text = "%s%s" % [String(kind).capitalize(), gate]
		button.pressed.connect(spawn_call.bind(kind))
		body.add_child(button)

	var note := Label.new()
	note.text = "Opens through the director's own placement,\nso nothing lands inside a building."
	note.add_theme_font_size_override("font_size", 11)
	body.add_child(note)


## Opens one call of [param kind]. Public because a check has to be able to ask for one
## without synthesising a mouse click on a button built at runtime.
func spawn_call(kind: StringName) -> void:
	var director := _director()
	if director:
		director.open_kind(kind)


## The director, found the way everything else finds it: by name, as a sibling under the
## map root. It joins no group, and adding one purely for a dev tool would be a change to
## the game for the benefit of the thing looking at it.
func _director() -> Director:
	var parent := get_parent()
	return parent.get_node_or_null("Director") as Director if parent else null
