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
## Whether this casualty is beyond what a paramedic can finish.
##
## A paramedic sent to one of these still works, and the work still matters -- it **holds
## the decline off** -- but it never accumulates towards stable, so they can never be lifted
## onto a stretcher. Only a unit with [method Person.has_advanced_care] closes that gap.
##
## This is the medical service's first real dispatch decision. Everything before it was a
## sequence: treat, lift, drive, deliver, in that order, with no question about who goes
## where. With one doctor and three paramedics on the books, a call with one of these in it
## is a question about where the doctor is, and the paramedics are how you buy time to
## answer it.
##
## **The director only opens these when the career owns a doctor**, on exactly the terms it
## only opens building fires when the career owns an engine and a firefighter. A casualty
## nobody on the roster can finish is not a hard call, it is a broken one.
@export var needs_doctor := false
## Seconds of held-off decline bought by the last frame of paramedic treatment. An expiring
## ask, like [member Person.SPRAY_HOLD]: the order re-asks every frame it works, and this
## lapses on its own the moment they stop, so nothing has to notice the order ending.
const CARE_HOLD := 0.25

@export_group("Assessment")
## Nobody at the scene yet knows what this collapse *is*. A paramedic's first working
## seconds settle it -- into an ordinary casualty, or into somebody who was never hurt
## at all and does not want the attention. Until then the readout commits to nothing.
@export var needs_assessment := false
## The hidden truth, rolled by the director's seeded RNG at spawn and surfaced only when
## the assessment reaches it. Never shown to the player before that: the not-knowing is
## the call.
var turns_rowdy := false
## How much treatment work it takes to know which of the two this is.
const ASSESS_AT := 0.4

@export_group("Trapped")
## Pinned under something. They can be treated where they lie -- a paramedic kneels
## beside them either way -- but they **cannot be moved** until a fire crew lifts it off.
##
## That is the whole point of the state: it makes one call need two services *in
## sequence* rather than in parallel. A rescue needs an engine and an ambulance at the
## same time; this needs the engine to have finished before the ambulance can start, and
## a paramedic who arrives first has something to do and a reason to wait.
@export var trapped := false:
	set(value):
		trapped = value
		_show_pin()
## 0 to 1, filled by [FreeOrder]. At 1 the weight comes off.
var release := 0.0
## How much of that a firefighter shifts per second. About three and a half seconds of
## work: long enough to be a job, short enough that it is not the boring part of a call
## the player has already committed two units to.
@export var free_per_second := 0.28

@export_group("Visuals")
## What is lying on them.
##
## A pallet, and the choice is about the **origin** rather than the look. The first cut
## used `SM_Prop_Pipe_Small_01`, four metres of pipe -- but its mesh runs from its origin
## along +Y, so its centre sits 2m out, and laying it flat put the whole length beside the
## casualty with one end resting on their shins. The pallet's mesh is centred on its
## origin (0.00, 0.19, 0.00), so it needs no rotation and no offset: dropped at the body
## it covers the body. It is also the right thing for a call flavoured "trapped under a
## load".
@export var pin_scene := "res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Pallet_01.tscn"
## Held pose for the body. Seeked to the end so they are already down at spawn.
@export var down_clip := "Death01"

@onready var _animation: AnimationPlayer = $Character/AnimationPlayer

## 0 to 1. At 1 the casualty stops declining and becomes ready to move.
var treatment := 0.0
## Treated, no longer declining, and waiting for a ride.
var is_stable := false
## Riding in a vehicle: hidden, unpickable, not yet delivered.
var is_loaded := false
## The crew member lying here, if this is one of the player's own rather than a member of
## the public. Set before the node enters the tree, exactly as [member outfit] is.
##
## The whole medical chain -- treat, stretcher, ambulance, hospital -- works on any
## casualty and needed no changes at all to carry a firefighter. What differs is only
## what happens at the end: see [method _settle_crew].
var crew: Unit
## Whether this *was* one of the player's own, latched at the moment the incident closes.
##
## `crew` cannot be read from the `resolved` handler: settling clears it, and a written-off
## unit is freed, so by the time the mission looks there is either null or a dangling
## reference. A plain bool survives both.
var was_crew := false
## On a paramedic's stretcher, being wheeled to the vehicle: visible, unpickable,
## still the same open incident.
var is_carried := false
## See [constant CARE_HOLD].
var _care_hold := 0.0


func _ready() -> void:
	super()
	add_to_group(CASUALTY_GROUP)
	# The same wardrobe the suspects use -- and when a collapse took a specific
	# shopper, the outfit the director passed is the one they were wearing.
	_animation = _wear_outfit()
	# The export has already been applied by now, so the prop is placed once the node is
	# actually in the tree and its setter can do something.
	_show_pin()
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
	if _care_hold > 0.0:
		# Being held by a paramedic who cannot finish the job. They do not get better and
		# they do not get worse -- which is the whole of what a paramedic can do here, and
		# is worth doing: it is the difference between losing this one and waiting.
		_care_hold = maxf(_care_hold - delta, 0.0)
		return
	health = maxf(health - decline_per_second * delta, 0.0)
	if health <= 0.0:
		_finish(false)


## Adds treatment progress. At 1 they stop declining and become ready to move.
## Shifts the weight. Called by [FreeOrder] every frame it is worked.
func free_from_weight(amount: float) -> void:
	if not active or not trapped:
		return
	release = minf(release + amount, 1.0)
	if release >= 1.0:
		trapped = false


## Puts the pinning prop on or takes it off. Guarded on being in the tree because the
## setter fires from the export before `_ready`, and on `pin_scene` being loadable
## because a missing prop should cost a visual and not a call.
func _show_pin() -> void:
	if not is_inside_tree():
		return
	var existing := get_node_or_null("Pin")
	if not trapped:
		if existing:
			existing.queue_free()
		return
	if existing or not ResourceLoader.exists(pin_scene):
		return
	var pin := (load(pin_scene) as PackedScene).instantiate() as Node3D
	if pin == null:
		return
	pin.name = "Pin"
	add_child(pin)
	# No rotation and no offset beyond the lift: the prop is centred on its own origin,
	# so sitting it at the body's origin puts it over the body. Just clear of the ground
	# so it reads as resting on them rather than sunk into the pavement.
	pin.position = Vector3(0.0, 0.12, 0.0)


func treat(amount: float, advanced := false) -> void:
	if not active or is_stable:
		return
	if needs_doctor and not advanced:
		# A paramedic on a doctor's case: holds them, finishes nothing.
		_care_hold = CARE_HOLD
		return
	treatment = minf(treatment + amount, 1.0)
	if needs_assessment and treatment >= ASSESS_AT:
		needs_assessment = false
		if turns_rowdy:
			_stand_up_swinging()
			return
	if treatment >= 1.0:
		# Stable, not saved. The incident stays open until they reach hospital, which
		# is what makes the ambulance trip part of the job rather than a formality.
		is_stable = true


## Hands a downed crew member back, or takes them off the books.
##
## Saved means the ambulance reached the hospital: they go back on the forecourt whole.
## Lost means they did not, and the career loses the unit it paid for -- the one thing in
## the game that makes `owned` go down. That asymmetry is the point of the feature: the
## player who sends a paramedic keeps their firefighter, and the one who does not, does
## not.
func _settle_crew(saved: bool) -> void:
	if crew == null or not is_instance_valid(crew):
		return
	var house := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if house == null:
		return
	if saved:
		house.accept(crew)
		var person := crew as Person
		if person:
			person.return_to_duty(person.global_position)
	else:
		house.write_off(crew)
	crew = null


func _finish(success: bool) -> void:
	if not active:
		return
	was_crew = crew != null and is_instance_valid(crew)
	_settle_crew(success)
	super(success)


## The assessment came back: not a patient. A suspect stands up where the casualty lay,
## wearing the same clothes, and the casualty retires **silently** -- no `resolved`
## emission in either polarity, because `false` fails the whole call and `true` pays
## £100 for a patient nobody delivered. **The order is the load-bearing part**: the
## suspect goes in before the casualty leaves, because retired the other way round the
## call's list empties and it closes RESOLVED, banking a cleared call for a job nobody
## did -- measured, by re-staging the swap retire-first. The frame-wait below is margin
## on top of that ordering, not the mechanism: adoption is deferred, and the wait keeps
## the retire clear of the same end-of-frame window rather than racing it.
func _stand_up_swinging() -> void:
	var packed := load("res://Game/Incidents/Suspect.tscn") as PackedScene
	if packed == null:
		return
	var suspect := packed.instantiate() as Suspect
	# The outfit is the Character child's scene path -- after _wear_outfit() that child
	# *is* the outfit scene -- so the one who stands up is dressed as the one who lay
	# down. Set before add_child, as everywhere.
	suspect.outfit = get_node("Character").scene_file_path
	suspect.flavour = "Drunk and disorderly"
	get_parent().add_child(suspect)
	suspect.global_position = global_position
	await get_tree().physics_frame
	if not active or not is_inside_tree():
		return
	active = false
	queue_free()


func describe_state() -> String:
	# **Said first, and said even when they are stable.** Trapped is the thing standing
	# between this call and its next step, so it outranks every other description --
	# "stable, needs an ambulance" on someone nobody can lift would send the player for
	# the wrong unit.
	if trapped:
		return "trapped -- needs cutting free" if release <= 0.0 else "being freed"
	# Named destinations, for the same reason the suspect's are: "en route" never said
	# where to, and the hospital is only obvious once you already know.
	if is_loaded:
		return "aboard, for the hospital"
	if is_carried:
		return "on the stretcher"
	if is_stable:
		return "stable, needs an ambulance"
	# **Said before "under treatment", because it outranks it.** A paramedic working on one
	# of these looks exactly like a paramedic working on anyone else, and without this the
	# panel would report steady progress towards a stable that is never coming.
	if needs_doctor:
		return "held by the crew -- needs a doctor" if _care_hold > 0.0 \
			else "critical -- needs a doctor"
	# Before the treatment arm: an unassessed collapse must not read as progress towards
	# a stable that may never be coming. It reads as the unknown it is.
	if needs_assessment:
		return "being assessed" if treatment > 0.0 else "unresponsive -- cause unknown"
	if treatment > 0.0:
		return "under treatment"
	return "critical" if health < 0.35 else "hurt"


## The casualty's whole journey, in stages: treated, lifted, aboard. It only reads
## full when they are delivered, which is when the incident closes anyway -- a bar
## that filled on treatment alone would say "done" with the ambulance still coming.
func progress() -> float:
	# While pinned the bar tracks the weight coming off, because that is the work in
	# front of the player. Capped below the treatment band so it never reads as further
	# along than someone who is merely hurt.
	if trapped:
		return release * 0.4
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
