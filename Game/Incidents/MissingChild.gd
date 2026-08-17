extends Incident
class_name MissingChild

## The report of a missing child: a parent standing at the place they were last seen.
##
## The first call whose marker is honest about *not knowing where the job is*. The
## anchor -- this node -- holds the call, the marker and the flavour, and never moves;
## the child ([ChildWanderer]) strolls the pedestrian graph somewhere within roaming
## distance, wearing no marker at all. Nothing on the board or minimap gives them away:
## the player searches by sending people to walk the nearby streets, and the find is a
## unit physically getting close.
##
## **Found is the middle of the job, not the end.** The child attaches to whoever
## found them and walks at heel; brought within reach of a *police* vehicle they climb
## in; and the call closes when that car pulls up back here, at the parent. Search,
## walk them to the car, drive them home -- three beats, and only the last one pays.

## How close a searcher must come to the child to have found them. Comfortably inside
## a street's width, so driving past on the carriageway does not count -- and the scan
## only asks people, so it cannot anyway.
@export var find_reach := 6.0

## How close the child must come to a police car to climb in. Wider than the find:
## the pedestrian mesh ends at the kerb and the car stands in its lane, so this has to
## bridge kerb-to-lane the same way the suspect escort's reach does.
@export var board_reach := 4.5

## How close the car must pull up to the parent for the reunion. A kerbside stop by
## the marker, not a parking manoeuvre.
@export var home_reach := 10.0

## The Suspect._is_contained cadence: a scan of the unit group four times a second is
## indistinguishable from per-frame at walking speeds and costs a quarter as much.
const SCAN_EVERY := 0.25

## The wanderer this report is about. Set by the director at spawn; the director also
## ties the child's teardown to this node's `tree_exited`, the shed-load truck pattern.
var child: ChildWanderer

## Latched at the first find and never unset: the readout must not fall back to
## "search the streets" because the finder wandered out of reach -- the child stays
## where they were left, waiting to be collected.
var found := false

var _scan_left := 0.0


func _ready() -> void:
	super()
	var animation := _wear_outfit()
	# The parent stands and waits; without a clip the rig holds a T-pose.
	if animation and animation.has_animation("Idle"):
		animation.play("Idle")


func _physics_process(delta: float) -> void:
	if not active:
		return
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_EVERY
	if child == null or not is_instance_valid(child):
		# The child left the world some other way -- a scene being torn down. Nothing
		# was earned, so nothing is banked: retire silently rather than emit a
		# resolution in either polarity, the drunk-call rule.
		active = false
		queue_free()
		return

	# Riding: the job is the drive now. Home is here, where the parent stands.
	if child.riding != null and is_instance_valid(child.riding):
		var run := child.riding.global_position - global_position
		run.y = 0.0
		if run.length() <= home_reach:
			_finish(true)
		return

	# Loose, or at heel. A searcher within reach takes them in hand -- also how they
	# are handed on if their finder left the map.
	if child.following == null or not is_instance_valid(child.following):
		for node in get_tree().get_nodes_in_group(Unit.GROUP):
			# People only. A Person cast drops every vehicle, and the service gate
			# drops the crowd -- a passing shopper finding the child would start the
			# job with nobody the player sent anywhere near it.
			var person := node as Person
			if person == null or person.service == Unit.Service.NONE:
				continue
			var offset := person.global_position - child.global_position
			offset.y = 0.0
			if offset.length() <= find_reach:
				found = true
				child.follow(person)
				break

	# Found or not, a police car close enough takes them aboard -- whether the officer
	# led them to it or the car came to them.
	if found:
		for node in get_tree().get_nodes_in_group(Unit.GROUP):
			var car := node as Vehicle
			# The police car, by the user's own words: a child is driven home in a
			# patrol car, not stretchered home in an ambulance.
			if car == null or car.service != Unit.Service.POLICE:
				continue
			var gap := car.global_position - child.global_position
			gap.y = 0.0
			if gap.length() <= board_reach:
				child.ride(car)
				return


func describe_state() -> String:
	if child != null and is_instance_valid(child) \
			and child.riding != null and is_instance_valid(child.riding):
		return "in the patrol car, coming home"
	if found:
		return "found -- bring a patrol car for them"
	return "last seen here -- search the streets nearby"


func progress() -> float:
	# The three beats, in the casualty journey's bands: found reads like treated,
	# aboard like loaded, and full only at the reunion, which closes the call anyway.
	if child != null and is_instance_valid(child) \
			and child.riding != null and is_instance_valid(child.riding):
		return 0.7
	if found:
		return 0.4
	return 0.0
