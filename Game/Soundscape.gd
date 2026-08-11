extends Node
class_name Soundscape

## The sounds that belong to the district rather than to any one thing in it: the
## city under everything, and the dispatch radio over the top.
##
## Positional audio lives on the thing making it -- an engine note on the vehicle, a
## crackle on the fire -- because it has somewhere to be. These two have nowhere:
## the ambience is everywhere at once, and a radio call is in the player's ear, not
## at the address it is about.
##
## Wired to the board and the director rather than being told when to speak, the same
## shape everything else in this project takes: nothing has to remember to call it.

const CITY_STREAM := "res://Game/Audio/city.wav"
const RADIO_STREAM := "res://Game/Audio/radio.wav"

## Quiet enough to sit under a conversation. The city is a bed, not a feature.
@export var ambience_db := -26.0
@export var radio_db := -12.0

var _ambience: AudioStreamPlayer
var _radio: AudioStreamPlayer


func _ready() -> void:
	_ambience = _player(CITY_STREAM, ambience_db, true)
	if _ambience:
		_ambience.play()
	_radio = _player(RADIO_STREAM, radio_db, false)


## Hooked to whatever exists. Both are optional: a scene without a board still runs,
## it just has less to say.
func listen(board: CallBoard, director: Director) -> void:
	if board and not board.call_opened.is_connected(_on_call_opened):
		board.call_opened.connect(_on_call_opened)
	if director and not director.shift_started.is_connected(chirp):
		director.shift_started.connect(chirp)


## One press of the transmit key. Public so anything worth announcing can use it.
func chirp() -> void:
	if _radio and _radio.stream:
		_radio.play()


func _on_call_opened(_call: Call) -> void:
	chirp()


func _player(path: String, level: float, looping: bool) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		return null
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Frames, not bytes: the data is 16-bit mono.
		stream.loop_end = stream.data.size() / 2
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = level
	add_child(player)
	return player
