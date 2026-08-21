@tool
class_name UnitDef
extends Resource
## Catalogue entry. If your project already defines UnitDef, delete this file —
## the panel only reads the properties below.

@export var id: StringName = &""
@export var display_name: String = "Fire Engine"
@export var role: String = ""
## &"fire", &"police", &"medical" or &"support" — drives which commands apply.
@export var category: StringName = &"fire"
@export var icon: Texture2D

## --- occupancy ---
@export var seats: int = 6
## Roles this unit rides with by default, e.g. [&"driver", &"firefighter"].
@export var default_crew: Array[StringName] = []

## --- carried liquid ---
## False for units that carry nothing; the panel then omits the chip entirely.
@export var carries_liquid: bool = false
@export var liquid_label: String = "Water"
@export var liquid_capacity: int = 0


static func make(p: Dictionary) -> UnitDef:
	var u := UnitDef.new()
	for k in p:
		u.set(k, p[k])
	return u
