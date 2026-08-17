extends SceneTree

## Writes [Daylight]'s grade for [constant MenuBackdrop.HOUR] into the menu's own scene.
##
##   godot --headless --path . --script res://Game/author_menu_hour.gd
##
## **Re-run this whenever `MenuBackdrop.HOUR` changes.** The hour is applied twice over
## -- once here into the saved scene, so the editor viewport shows what ships, and once
## at run time by Daylight. They cannot disagree about the *values*, because both read
## the same preset table; they can disagree about *which hour*, and this script is what
## settles that.
##
## Why author it rather than leave it to run time: the scene is the thing the user
## opens in the editor to place lights in, and until now it described a bright midday
## forecourt that nothing ever shipped -- `Daylight` rewrote the lights and the
## environment on load. Lighting a scene against a reference you never see is guesswork.
##
## The values are **read out of `Daylight.PRESETS`**, not retyped, so the authored scene
## and the runtime grade cannot disagree. Both write the same absolute numbers, which
## makes running the grade over an already-dusk scene a no-op rather than a second
## darkening -- so the game keeps its one-line control of the hour and the editor shows
## the truth.
##
## The environment is written to a **copy**. The vendor `.tres` the scene referenced is
## shared with the district; editing it in place would have dimmed the whole game.
##
## One-shot. Re-running is harmless but pointless; the scene is the record now.

const SCENE := "res://Assets/PolygonTown/Scenes/MainMenu.tscn"
const OUT_ENV := "res://Game/UI/MenuEnvironment.tres"

## Named in the print so a run says which hour it just wrote.
const HOURS := ["DAY", "DUSK", "NIGHT"]

## **The scene's own daylight, as the user authored it.**
##
## DAY is not in `Daylight.PRESETS` and never was: at run time it means "restore the
## baseline captured from the scene", so the scene *is* the day preset. That worked
## until this script overwrote those values with dusk -- after which the baseline was
## dusk, and asking for DAY would have restored dusk while calling it noon.
##
## So the original values are kept here, read out of the pristine scene before the
## first authoring run. The lights are exact; the environment is restored by copying
## the vendor resource the scene shipped pointing at, unmodified.
const DAY_KEY_COLOUR := Color(1.0, 0.9043611, 0.8308824)
const DAY_KEY_ENERGY := 1.24
const DAY_KEY_BASIS := [-0.68303114, 0.4124619, 0.60278,
	0.3271477, -0.5651046, 0.7573845, 0.653026, 0.7145152, 0.2510481]
const DAY_FILL_COLOUR := Color(1.0, 0.9043611, 0.8308824)
const DAY_FILL_ENERGY := 0.25
const VENDOR_ENV := "res://Assets/Synty/PolygonStarter/Materials/WorldEnvironmentLighting.tres"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# **Indexed through a variable, deliberately.** `Daylight.PRESETS[MenuBackdrop.HOUR]`
	# is two constants, so GDScript folds it at *parse* time -- and since there is no DAY
	# entry the whole script then fails to load rather than taking the branch that
	# avoids the lookup. A var defers it to run time, where the branch works.
	var hour: int = MenuBackdrop.HOUR
	var day := hour == Daylight.Mode.DAY
	# Empty for DAY, which has no preset -- see DAY_KEY_COLOUR above.
	var preset: Dictionary = {} if day else Daylight.PRESETS[hour]

	# --- the environment, as a copy -----------------------------------------
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate()
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		push_error("no WorldEnvironment in %s" % SCENE)
		quit(1)
		return
	# For DAY the scene gets the vendor environment back, verbatim -- but still as its
	# own copy, because Daylight writes into whatever it is handed and that file is
	# shared with the district.
	var source := (load(VENDOR_ENV) as Environment) if day else world.environment
	var env := source.duplicate(true) as Environment
	if day:
		if ResourceSaver.save(env, OUT_ENV) != OK:
			push_error("could not save %s" % OUT_ENV)
			quit(1)
			return
		print("wrote %s (the scene's own daylight)" % OUT_ENV)
	else:
		env.ambient_light_energy = float(preset["ambient_energy"])
		env.ambient_light_color = preset["ambient_colour"]
		env.fog_enabled = true
		env.fog_density = float(preset["fog_density"])
		env.fog_light_color = preset["fog_colour"]
		env.tonemap_exposure = float(preset["exposure"])
		var sky := env.sky.duplicate(true) as Sky if env.sky else null
		var material := sky.sky_material as ProceduralSkyMaterial if sky else null
		if material:
			material.sky_top_color = preset["sky_top"]
			material.sky_horizon_color = preset["sky_horizon"]
			material.ground_horizon_color = preset["ground_horizon"]
			material.ground_bottom_color = preset["ground_bottom"]
			env.sky = sky
		if ResourceSaver.save(env, OUT_ENV) != OK:
			push_error("could not save %s" % OUT_ENV)
			quit(1)
			return
		print("wrote %s" % OUT_ENV)

	# --- the two suns, as a transform this script does not have to derive ----
	# Godot builds the basis from the euler; hand-computing it into scene text is how
	# a sign error gets baked into a file nobody re-reads.
	var key := scene.get_node_or_null("Directional light") as DirectionalLight3D
	var fill := scene.get_node_or_null("Directional light (2)") as DirectionalLight3D
	if key == null or fill == null:
		push_error("the menu scene's two directional lights are not where they were")
		quit(1)
		return
	if day:
		key.transform = Transform3D(
			Vector3(DAY_KEY_BASIS[0], DAY_KEY_BASIS[1], DAY_KEY_BASIS[2]),
			Vector3(DAY_KEY_BASIS[3], DAY_KEY_BASIS[4], DAY_KEY_BASIS[5]),
			Vector3(DAY_KEY_BASIS[6], DAY_KEY_BASIS[7], DAY_KEY_BASIS[8]),
			key.position)
		key.light_energy = DAY_KEY_ENERGY
		key.light_color = DAY_KEY_COLOUR
		fill.light_energy = DAY_FILL_ENERGY
		fill.light_color = DAY_FILL_COLOUR
	else:
		key.rotation = Vector3(deg_to_rad(float(preset["elevation"])),
			deg_to_rad(float(preset["azimuth"])), 0.0)
		key.light_energy = float(preset["key_energy"])
		key.light_color = preset["key_colour"]
		fill.light_energy = float(preset["fill_energy"])
		fill.light_color = preset["fill_colour"]

	var text := FileAccess.get_file_as_string(SCENE)
	text = _replace_node(text, "Directional light", key, true)
	text = _replace_node(text, "Directional light (2)", fill, false)
	# Point the scene at its own environment instead of the shared vendor one.
	text = text.replace(
		'[ext_resource type="Environment" uid="uid://bubfaqibysqev" '
		+ 'path="res://Assets/Synty/PolygonStarter/Materials/WorldEnvironmentLighting.tres" '
		+ 'id="1_1b7sj"]',
		'[ext_resource type="Environment" path="%s" id="1_1b7sj"]' % OUT_ENV)

	var file := FileAccess.open(SCENE, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("authored %s into %s" % [HOURS[hour], SCENE])
	quit()


## Rewrites one light's properties in the scene text, leaving the rest of the node --
## and the other 6,700 -- exactly as the user left them.
func _replace_node(text: String, node_name: String, light: DirectionalLight3D,
		with_transform: bool) -> String:
	var head := '[node name="%s" type="DirectionalLight3D"' % node_name
	var start := text.find(head)
	if start < 0:
		push_error("could not find %s in the scene" % node_name)
		return text
	var body_start := text.find("\n", start) + 1
	var body_end := text.find("\n[node ", body_start)
	var body := text.substr(body_start, body_end - body_start)

	var lines := PackedStringArray()
	for line in body.split("\n"):
		# Everything this script owns is dropped and rewritten below; anything else the
		# user put on the node stays.
		if line.begins_with("transform = ") and with_transform:
			continue
		if line.begins_with("light_color = ") or line.begins_with("light_energy = "):
			continue
		lines.append(line)
	var rewritten := PackedStringArray()
	if with_transform:
		var basis := light.transform.basis
		var origin := light.position
		rewritten.append(("transform = Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s,"
			+ " %s, %s, %s)") % [basis.x.x, basis.x.y, basis.x.z,
			basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z,
			origin.x, origin.y, origin.z])
	rewritten.append("light_color = Color(%s, %s, %s, 1)"
		% [light.light_color.r, light.light_color.g, light.light_color.b])
	rewritten.append("light_energy = %s" % light.light_energy)
	for line in lines:
		if line != "":
			rewritten.append(line)
	return text.substr(0, body_start) + "\n".join(rewritten) + "\n" \
		+ text.substr(body_end + 1)
