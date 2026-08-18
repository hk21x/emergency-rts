class_name UnitCatalog
extends RefCounted
## Sample catalogue. Swap this for a folder of .tres UnitDef resources once the
## roster settles — nothing below depends on the data living in code.

const ICON := "res://ui/art/icons/icon_%s.svg"


static func _t(n: String) -> Texture2D:
	return load(ICON % n)


static func default_units() -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for d in [
		{"id": &"pump", "display_name": "Fire Engine", "role": "Pump ladder · Station 1",
		 "category": &"fire", "cost": 4200, "crew": 6, "trait_text": "1,800 L",
		 "icon": _t("truck"), "trait_icon": _t("water_drop"), "stock": 4},
		{"id": &"aerial", "display_name": "Aerial Platform", "role": "32 m · Station 3",
		 "category": &"fire", "cost": 6500, "crew": 4, "trait_text": "High-rise",
		 "icon": _t("water_jet"), "trait_icon": _t("flame"), "stock": 2},
		{"id": &"dsu", "display_name": "Ambulance", "role": "Double crew · Station 1",
		 "category": &"medical", "cost": 3100, "crew": 2, "trait_text": "ALS",
		 "icon": _t("medical"), "trait_icon": _t("medical"), "stock": 6},
		{"id": &"hems", "display_name": "Air Ambulance", "role": "HEMS · Regional",
		 "category": &"medical", "cost": 9800, "crew": 4, "trait_text": "Critical",
		 "icon": _t("helicopter"), "trait_icon": _t("shield_check"), "stock": 1},
		{"id": &"patrol", "display_name": "Patrol Car", "role": "Response · Station 2",
		 "category": &"police", "cost": 2400, "crew": 2, "trait_text": "Fast",
		 "icon": _t("shield_person"), "trait_icon": _t("target"), "stock": 8},
		{"id": &"asu", "display_name": "Armed Response", "role": "Firearms · Regional",
		 "category": &"police", "cost": 5600, "crew": 3, "trait_text": "Specialist",
		 "icon": _t("shield"), "trait_icon": _t("alert"), "stock": 2},
		{"id": &"command", "display_name": "Command Unit", "role": "Incident command",
		 "category": &"support", "cost": 5200, "crew": 3, "trait_text": "Comms",
		 "icon": _t("truck"), "trait_icon": _t("clipboard"),
		 "locked_reason": "Requires Station 3", "stock": 1},
		{"id": &"welfare", "display_name": "Welfare Unit", "role": "Rehab · Station 2",
		 "category": &"support", "cost": 1800, "crew": 2, "trait_text": "Rest",
		 "icon": _t("home"), "trait_icon": _t("group"), "stock": 2},
	]:
		out.append(UnitDef.make(d))
	return out
