extends StaticBody3D
class_name Incident

## Something on the map that needs dealing with, and that gets worse if it is not.
##
## Incidents sit on collision layer 8: pickable by the selection raycast, but outside
## the vehicle and person collision masks, so nobody drives into a fire or trips over
## a casualty. They are also excluded from the navigation bake, which only reads
## layer 1, so an incident never carves a hole in the paths.

## Emitted once when the incident is dealt with, or when it is lost.
signal resolved(incident: Incident, success: bool)

const GROUP := &"incidents"

@export var display_name := "Incident"

## Names the job on the board when the default kind title undersells it -- an RTC's
## casualties read "Road traffic collision", not "Medical emergency". Empty for
## anything that is just what it looks like.
@export var flavour := ""

## The crowd's wardrobe. An incident involving a *person* wears one of these, because
## the person it involves came from the pavement: the scenes ship with the Starter
## pack's grey-blue mannequin, which reads as a placeholder standing in a city full
## of dressed pedestrians.
const OUTFITS := [
	"res://Game/Characters/BusinessMan_Shirt.tscn",
	"res://Game/Characters/BusinessMan_Suit.tscn",
	"res://Game/Characters/BusinessWoman.tscn",
	"res://Game/Characters/Female_Coat.tscn",
	"res://Game/Characters/Female_Jacket.tscn",
	"res://Game/Characters/Male_Hoodie.tscn",
	"res://Game/Characters/Male_Jacket.tscn",
]

## Which outfit to wear, set before this node enters the tree. Empty picks one.
## The director fills it in when a collapse takes a specific civilian, so the body
## on the pavement is wearing what that shopper was wearing a moment ago.
var outfit := ""

## Cleared the moment the incident ends. queue_free() does not take effect until the
## end of the frame, so orders need a flag they can trust immediately.
var active := true


func _ready() -> void:
	add_to_group(GROUP)


## State of this incident in words, for the HUD -- "well alight", "critical". The
## *number* behind it belongs to [method progress] and is drawn as a bar: a scene
## with six fires on it read as six percentages in a row, which is data, not a
## readout.
func describe_state() -> String:
	return ""


## How far through dealing with this incident the crews are, 0 to 1. Drawn as the
## bar on its call row.
func progress() -> float:
	return 0.0


## Dresses this incident's figure, replacing the scene's placeholder body with one of
## the crowd's, and hands back the new [AnimationPlayer].
##
## The swap has to happen in `_ready` **and** the caller has to take the returned
## player: `@onready var _animation := $Character/AnimationPlayer` has already
## resolved by then and would be left pointing at a freed node.
func _wear_outfit() -> AnimationPlayer:
	var existing := get_node_or_null("Character") as Node3D
	if existing == null:
		return null

	var wanted := outfit
	if wanted == "":
		# Its own generator: cosmetic draws never share a stream with anything that
		# has to reproduce. The instance id is unique and stable within a run.
		var pick := RandomNumberGenerator.new()
		pick.seed = get_instance_id()
		wanted = str(OUTFITS[pick.randi() % OUTFITS.size()])
	if not ResourceLoader.exists(wanted):
		return existing.get_node_or_null("AnimationPlayer") as AnimationPlayer

	# The scene's transform carries the 180 yaw that makes the model face the way the
	# node does, so it goes on the replacement rather than being rediscovered.
	var placement := existing.transform
	remove_child(existing)
	existing.queue_free()

	var body := (load(wanted) as PackedScene).instantiate() as Node3D
	body.name = "Character"
	add_child(body)
	body.transform = placement
	return body.get_node_or_null("AnimationPlayer") as AnimationPlayer


func _finish(success: bool) -> void:
	if not active:
		return
	active = false
	resolved.emit(self, success)
	queue_free()
