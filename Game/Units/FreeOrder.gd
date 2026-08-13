extends WorkOrder
class_name FreeOrder

## Work the weight off a trapped casualty until they can be moved.
##
## The same shape as every other [WorkOrder] and deliberately so, but note what it does
## *not* do: it never treats. A casualty who is freed is exactly as hurt as they were,
## and their health has been running down the whole time -- so a crew that takes too long
## hands the paramedic a worse job than the one they were waiting for.

## Close enough to get hands on it.
const REACH := 2.4

## Idle_Torch again, the one-handed "holding something out in front" pose. The library
## has no lifting or cutting clip, and at this camera distance it reads as working on
## something at waist height, which is what this is.
const CLIP := "Idle_Torch"


func _init(casualty: Casualty) -> void:
	super(casualty, REACH, CLIP, "Freeing")


func _work(unit: Unit, delta: float) -> bool:
	var casualty := target as Casualty
	if casualty == null or not casualty.active:
		return true
	# Already out: the order is done rather than failed. Two firefighters sent at the
	# same casualty is a reasonable thing for a player to do, and the second should
	# simply finish rather than stand there working on nothing.
	if not casualty.trapped:
		return true
	casualty.free_from_weight(casualty.free_per_second * delta)
	return not casualty.trapped
