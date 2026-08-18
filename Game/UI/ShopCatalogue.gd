extends RefCounted
class_name ShopCatalogue

## Turns [member Station.TYPES] into the [UnitDef] list the Emergency Ops purchase modal
## expects.
##
## **The kit ships its own sample catalogue and says to replace it** -- `UnitCatalog`'s own
## comment is "swap this for a folder of .tres UnitDef resources once the roster settles;
## nothing below depends on the data living in code". This is that swap, done in code
## rather than in `.tres` files because the roster already has a source of truth and a
## second one would be a thing to keep in step. `Station.TYPES` stays the only place a unit
## is described.
##
## Nothing here reads or writes the career. Building a card list is a pure function of the
## catalogue, and the modal hands back an order for [Station] to charge for.

## Our services onto the kit's four tabs. Everything the player can buy belongs to a
## service, so `support` stays empty and the tab is dropped rather than shown bare.
const CATEGORY := {
	Unit.Service.FIRE: &"fire",
	Unit.Service.POLICE: &"police",
	Unit.Service.MEDICAL: &"medical",
}


## One [UnitDef] per catalogue row, in catalogue order.
static func units() -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for config: Dictionary in Station.TYPES:
		var def := UnitDef.new()
		def.id = config["id"]
		def.display_name = String(config["label"])
		def.category = CATEGORY.get(config["service"], &"support")
		def.cost = int(config["price"])
		def.icon = _portrait(String(config.get("portrait", "")))
		def.role = _role(config)
		# **Read off the built scene, not the catalogue row.** `seats`, `cells` and
		# `stretchers` are set by `build_vehicles.gd` and live on the unit; `Station.TYPES`
		# never carried them, so the first cut quietly read its own defaults and every
		# vehicle came out "crew 1, Response". A silent `.get()` default is how a bridge
		# ends up describing units that do not exist.
		var built := _stats(String(config["scene"])) if bool(config["vehicle"]) else {}
		def.trait_text = _trait(built, bool(config["vehicle"]))
		def.crew = int(built.get("seats", 1))
		# **No cap.** The kit defaults `stock` to 4 and enforces it; this career has never
		# limited how many of anything you may own, and a silent cap arriving with a new
		# front end would be a rules change disguised as a skin.
		def.stock = 0
		out.append(def)
	return out


## The tabs actually populated, so an empty SUPPORT tab is never shown.
static func categories() -> Array[StringName]:
	var seen: Array[StringName] = []
	for def in units():
		if not seen.has(def.category):
			seen.append(def.category)
	return seen


static func _portrait(name: String) -> Texture2D:
	if name == "":
		return null
	return load("res://Game/UI/Portraits/%s.png" % name) as Texture2D


## The card's second line. The catalogue's `blurb` already carries a written description
## and its first line is the summary one.
static func _role(config: Dictionary) -> String:
	var blurb: Array = config.get("blurb", [])
	if blurb.is_empty():
		return ""
	# **The blurbs are written as two lines and the first is often a fragment** -- the
	# officer's reads "Apprehends suspects, fights small fires," and continues below. On a
	# card there is room for one line, and a line ending in a comma reads as text that has
	# been cut off rather than as a description. Trimming the dangling clause is the
	# cheapest honest fix; the alternative is a second set of strings to keep in step with
	# the catalogue.
	var line := String(blurb[0]).strip_edges()
	# **No first-sentence trim, and that was tried.** Cutting at the first full stop kept
	# long blurbs on one line, but the recovery truck's reads "Seats 2. Slower than a
	# patrol car." -- and the informative half is the *second* sentence, so trimming left
	# the card saying "Seats 2." and nothing else. The card wraps to two lines now, which
	# solves the length problem without a rule that guesses which half matters.
	while line.ends_with(",") or line.ends_with(" and"):
		line = line.trim_suffix(" and").trim_suffix(",").strip_edges()
	return line


## The small stat chip. Whatever this unit is actually distinguished by, in the order a
## player would care about it.
static func _trait(built: Dictionary, is_vehicle: bool) -> String:
	if not is_vehicle:
		return "Crew"
	if int(built.get("cells", 0)) > 0:
		return "%d cells" % int(built["cells"])
	if int(built.get("stretchers", 0)) > 0:
		return "%d stretchers" % int(built["stretchers"])
	if bool(built.get("flies", false)):
		return "Air"
	return "Seats %d" % int(built.get("seats", 2))


## `seats`, `cells` and `stretchers` as the generator actually set them, plus whether the
## thing flies. Instantiated and freed: these are scene properties and there is nowhere
## cheaper to read them that is still true.
static func _stats(scene: String) -> Dictionary:
	var packed := load(scene) as PackedScene
	if packed == null:
		return {}
	var unit := packed.instantiate()
	var stats := {
		"seats": int(unit.get("seats")) if "seats" in unit else 2,
		"cells": int(unit.get("cells")) if "cells" in unit else 0,
		"stretchers": int(unit.get("stretchers")) if "stretchers" in unit else 0,
		"flies": unit is Aircraft,
	}
	unit.free()
	return stats
