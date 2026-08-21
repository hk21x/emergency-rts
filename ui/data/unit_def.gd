@tool
class_name UnitDef
extends Resource
## One purchasable unit. Make these as .tres files so designers can tune costs
## without touching code.

@export var id: StringName = &""
@export var display_name: String = "Unit"
@export var role: String = ""
## One of: &"fire", &"police", &"medical", &"support"
@export var category: StringName = &"support"
@export var cost: int = 1000
@export var icon: Texture2D
@export var crew: int = 2
## Small secondary stat shown on the card, e.g. "1,800 L" or "ALS".
@export var trait_text: String = ""
@export var trait_icon: Texture2D
## Non-empty means the unit is locked and the string explains why.
@export var locked_reason: String = ""
## Cap on how many of this unit can be requested at once. 0 = no cap.
@export var stock: int = 4

## --- occupancy ---
## Total seats, crew and passengers together.
@export var seats: int = 4
## Roles this unit rides with by default, e.g. [&"driver", &"firefighter"].
@export var default_crew: Array[StringName] = []

## --- carried liquid ---
## Leave false for units that carry nothing; the panel then omits the chip.
@export var carries_liquid: bool = false
@export var liquid_label: String = "Water"
@export var liquid_capacity: int = 0


static func make(p: Dictionary) -> UnitDef:
	var u := UnitDef.new()
	for k in p:
		u.set(k, p[k])
	return u
