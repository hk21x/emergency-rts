extends Incident
class_name Casualty

## Someone hurt, whose condition declines until a paramedic reaches them.
##
## Two separate quantities: [member health] runs down on its own, and [member
## treatment] is what a worker adds. Treatment stabilises; running out of health does
## not. That gap is the whole point -- arrive late and the casualty is lost, which is
## a failure the player can actually feel.

const CASUALTY_GROUP := &"casualties"

@export_group("Condition")
## 0 to 1. Reaching zero before treatment completes loses them.
@export var health := 1.0
@export var decline_per_second := 0.012
## Fraction of treatment added per second of work.
@export var treat_per_second := 0.2

@export_group("Visuals")
## Held pose for the body. Seeked to the end so they are already down at spawn.
@export var down_clip := "Death01"

@onready var _animation: AnimationPlayer = $Character/AnimationPlayer

## 0 to 1. At 1 the casualty stops declining and becomes ready to move.
var treatment := 0.0
## Treated, no longer declining, and waiting for a ride.
var is_stable := false
## Riding in a vehicle: hidden, unpickable, not yet delivered.
var is_loaded := false
## On a paramedic's stretcher, being wheeled to the vehicle: visible, unpickable,
## still the same open incident.
var is_carried := false


func _ready() -> void:
	super()
	add_to_group(CASUALTY_GROUP)
	# The same wardrobe the suspects use -- and when a collapse took a specific
	# shopper, the outfit the director passed is the one they were wearing.
	_animation = _wear_outfit()
	if _animation and _animation.has_animation(down_clip):
		_animation.play(down_clip)
		# Jump to the end: they are found already on the ground, not dying on cue.
		# Stop just short of the final frame -- seeking to exactly the length of a
		# non-looping clip ends it, and the player snaps back to the standing rest
		# pose. pause() then holds the prone frame.
		_animation.seek(_animation.get_animation(down_clip).length - 0.05, true)
		_animation.pause()


func _physics_process(delta: float) -> void:
	if not active or is_stable:
		return
	health = maxf(health - decline_per_second * delta, 0.0)
	if health <= 0.0:
		_finish(false)


## Adds treatment progress. At 1 they stop declining and become ready to move.
func treat(amount: float) -> void:
	if not active or is_stable:
		return
	treatment = minf(treatment + amount, 1.0)
	if treatment >= 1.0:
		# Stable, not saved. The incident stays open until they reach hospital, which
		# is what makes the ambulance trip part of the job rather than a formality.
		is_stable = true


func describe_state() -> String:
	# Named destinations, for the same reason the suspect's are: "en route" never said
	# where to, and the hospital is only obvious once you already know.
	if is_loaded:
		return "aboard, for the hospital"
	if is_carried:
		return "on the stretcher"
	if is_stable:
		return "stable, needs an ambulance"
	if treatment > 0.0:
		return "under treatment"
	return "critical" if health < 0.35 else "hurt"


## The casualty's whole journey, in stages: treated, lifted, aboard. It only reads
## full when they are delivered, which is when the incident closes anyway -- a bar
## that filled on treatment alone would say "done" with the ambulance still coming.
func progress() -> float:
	if is_loaded:
		return 0.9
	if is_carried:
		return 0.7
	if is_stable:
		return 0.5
	return treatment * 0.5


## Lifted onto a stretcher. The body stays visible -- it rides the prop, moved by
## the order carrying it -- but the red marker and the pick box go: nothing targets
## a casualty already in hand.
func take_by_stretcher() -> void:
	if is_loaded or is_carried or not is_stable:
		return
	is_carried = true
	$Marker.visible = false
	$Collision.set_deferred("disabled", true)


## Put back down mid-run -- the order was cancelled, or lost its vehicle. Still
## open, still collectable, lying wherever the stretcher stood.
func put_down() -> void:
	if not is_carried:
		return
	is_carried = false
	$Marker.visible = true
	$Collision.set_deferred("disabled", false)


## Climbs aboard a vehicle. Seat is claimed by Vehicle.load_casualty() first.
func load_into(_vehicle: Vehicle) -> void:
	if is_loaded or not is_stable:
		return
	is_loaded = true
	is_carried = false
	visible = false
	$Collision.set_deferred("disabled", true)


## Handed over at hospital: the incident is finally closed, successfully.
func deliver() -> void:
	_finish(true)
