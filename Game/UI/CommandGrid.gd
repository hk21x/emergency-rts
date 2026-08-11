extends HFlowContainer
class_name CommandGrid

## The command tiles, built from whatever the selection can do.
##
## Same contract the old text command bar had: the grid is generated from the abilities
## the units advertise, so giving a unit a new verb puts a tile here and binds its key
## with no change to this file. What is new is that the union comes from the controller
## rather than being recomputed here, so the tiles and the hotkeys cannot disagree about
## which abilities are available.

## Wired from a setter, not from _ready. Godot readies children before their parent, so
## by the time the HUD hands this panel its controller the panel's own _ready has long
## since run -- reading the reference there finds null and the grid stays empty.
var controller: RTSController: set = _set_controller

var _tiles: Array[CommandIcon] = []
var _empty: Label


func _ready() -> void:
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)
	# An empty card under a COMMANDS heading reads as broken rather than as idle.
	_empty = Label.new()
	_empty.theme_type_variation = &"DimLabel"
	_empty.add_theme_font_size_override("font_size", 12)
	_empty.text = "Select a unit to see what it can do"
	add_child(_empty)


func _set_controller(value: RTSController) -> void:
	controller = value
	if controller == null:
		return
	controller.selection_changed.connect(_on_selection_changed)
	controller.armed_ability_changed.connect(_highlight)
	_rebuild()


func _on_selection_changed(_units: Array[Unit]) -> void:
	_rebuild()


func _rebuild() -> void:
	var abilities := controller.available_abilities()
	_empty.visible = abilities.is_empty()

	while _tiles.size() < abilities.size():
		var tile := CommandIcon.new()
		tile.pressed.connect(controller.activate)
		_tiles.append(tile)
		add_child(tile)

	for i in _tiles.size():
		var tile := _tiles[i]
		tile.visible = i < abilities.size()
		if tile.visible:
			tile.setup(abilities[i])
			tile.armed = false


func _highlight(ability: Ability) -> void:
	for tile in _tiles:
		tile.armed = tile.visible and tile.ability != null \
			and ability != null and tile.ability.id() == ability.id()


## Toggle state is polled rather than signalled: a switch can be thrown by the tile,
## the hotkey, or code, and a dozen boolean reads a frame is cheaper than making every
## path remember to announce itself. The setter only redraws on change.
func _process(_delta: float) -> void:
	if controller == null:
		return
	for tile in _tiles:
		if not tile.visible or tile.ability == null:
			continue
		var on := false
		for unit in controller.selection:
			if tile.ability.is_active(unit):
				on = true
				break
		tile.active = on
