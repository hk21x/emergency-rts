extends PanelContainer
class_name ObjectiveBar

## The bar at the top-left that says what to do next.
##
## Two different things write to it and neither knows about the other: [HUD] puts the
## district's standing hint there ("Buy your first units from DISPATCH", "Press F2 to
## start a shift"), and [TutorialDirector] puts the teaching line there, a prompt at a
## time, read off the state the player is actually in. Both did it by setting the text
## of one bare Label floating over the middle of the city -- 20pt type with an outline,
## over a lit street, which is legible the way a shout is legible.
##
## In the kit's frame at the top-left it is what the reference calls the mission
## objective: a small caption over a line of instruction, in the corner the eye starts
## from rather than across the thing the player is trying to look at.
##
## **The label kept its name and moved with it**, so the four places that write to it
## needed a path change and nothing else.

var _line: Label


func _ready() -> void:
	theme_type_variation = &"TopBarPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = get_node_or_null("Debrief") as Label


## Follows its own label rather than being switched by the two callers.
##
## Both of them already set the label's visibility and its text; asking them to switch a
## panel as well is a rule that gets forgotten at the third call site, and the failure --
## an empty framed bar sitting in the corner - looks like a bug in the frame rather than
## a missed line. Cheap enough to poll: one string comparison a frame.
func _process(_delta: float) -> void:
	if _line == null:
		return
	visible = _line.visible and _line.text != ""
