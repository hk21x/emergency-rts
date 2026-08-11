extends Node
class_name Daylight

## What hour the district is working at: the light, the air, and everything that has
## to switch on when it gets dark.
##
## One value drives all of it -- [member time_of_day] -- and everything else is
## derived, so there is no way for the street lights to be on while the sun is up.
## The three settings are fixed rather than a rolling clock on purpose: three states
## can be tested, and a shift that drifted through them would mean every check about
## lighting had to say *when* it was looking.
##
## **Day is whatever the generator wrote.** The baseline is captured from the scene on
## ready rather than restated here, so the shipped map is byte-identical at DAY and
## every check written against it still describes what it sees. Dusk and night are
## departures from that baseline; going back to day restores it exactly.
##
## Passive where it can be, like [Mission] and [CallBoard]: it watches
## `SceneTree.node_added` and fits headlights to any vehicle that turns up, so a car
## bought at midnight has lights without the station knowing anything about the hour.

signal changed(mode: int)

## DAY is the map as it ships. DUSK is the interesting one to play -- long shadows,
## lit windows, and you can still read the street.
enum Mode { DAY, DUSK, NIGHT }

## CLEAR is the map as it ships. RAIN is the only weather with a *mechanical* half, and
## deliberately so -- see [constant WET_GRIP].
enum Weather { CLEAR, RAIN }

## Below this the district is dark enough to want its lights on. A single threshold
## rather than a flag per system, so nothing can disagree about whether it is night.
const LIT_BELOW := Mode.DUSK

## What a wet road is worth, as a fraction of dry grip.
##
## This is the whole of the weather's mechanics, and it is one number because the
## driving model already asks the right question. The autopilot plans corner entry
## speeds from `sqrt(max_lateral_accel * grip_scale * radius)` and caps yaw by the same
## term, so scaling grip lengthens braking distances and lowers apex speeds for the
## player's units *and* the ambient fleet, with no branch anywhere saying "if raining".
## Rain is a property of the road, not a case in the controller.
##
## 0.72 rather than something dramatic: the district's junctions are 10m across and the
## corner planner is already close to the limit of what a car can hold: 0.5 made
## ordinary junction turns miss their apex and re-route, which reads as broken rather
## than as weather.
const WET_GRIP := 0.72

@export var time_of_day := Mode.DAY: set = set_time_of_day
@export var weather := Weather.CLEAR: set = set_weather

@export_group("Wiring")
## All optional. A scene without them still runs; it just has one hour.
@export var key_light_path := NodePath("../KeyLight")
@export var fill_light_path := NodePath("../FillLight")
@export var environment_path := NodePath("../WorldEnvironment")
@export var street_lights_path := NodePath("../StreetLights")

## Where each mode departs from the captured daylight baseline. Elevation and azimuth
## are the sun's, in degrees; energies are absolute; the colours are what the light
## and the air are tinted to.
##
## Dusk is a low western sun -- 9 degrees above the horizon, which is what makes the
## shadows long -- and night is not black but a dim cool wash, because a city at night
## is lit, and a district the player cannot read is not atmospheric, it is broken.
const PRESETS := {
	Mode.DUSK: {
		"elevation": -9.0, "azimuth": -104.0,
		"key_energy": 0.62, "key_colour": Color(1.0, 0.66, 0.38),
		"fill_energy": 0.30, "fill_colour": Color(0.62, 0.66, 0.92),
		"ambient_energy": 0.34, "ambient_colour": Color(0.82, 0.76, 0.82),
		"fog_density": 0.0060, "fog_colour": Color(0.52, 0.42, 0.44),
		"exposure": 1.24,
		"sky_top": Color(0.20, 0.26, 0.48), "sky_horizon": Color(0.92, 0.56, 0.34),
		"ground_horizon": Color(0.46, 0.30, 0.26), "ground_bottom": Color(0.20, 0.18, 0.22),
	},
	Mode.NIGHT: {
		"elevation": -24.0, "azimuth": -70.0,
		"key_energy": 0.18, "key_colour": Color(0.60, 0.72, 1.0),
		"fill_energy": 0.10, "fill_colour": Color(0.42, 0.52, 0.86),
		"ambient_energy": 0.16, "ambient_colour": Color(0.44, 0.52, 0.76),
		"fog_density": 0.0085, "fog_colour": Color(0.10, 0.13, 0.24),
		"exposure": 1.02,
		"sky_top": Color(0.03, 0.04, 0.10), "sky_horizon": Color(0.10, 0.13, 0.26),
		"ground_horizon": Color(0.08, 0.10, 0.18), "ground_bottom": Color(0.04, 0.05, 0.09),
	},
}

## The rain box: half-width in metres, how high above the ground it emits, and how many
## drops are alive at once. Sized to cover the view rather than the district -- the box
## follows the camera, so 40m across is plenty and 260m would be forty times the
## particles for weather nobody is looking at.
##
## The half-width is also what keeps the rain **out of the lens**. It is centred on the
## ground point the camera is aimed at, and the camera sits roughly 25m back from that
## at this pitch — so a box any wider than this spawns drops between the camera and the
## district, where a 1m streak a metre from the near plane renders as a glass rod
## standing over the whole city. That is exactly what the first build looked like.
const RAIN_BOX := 20.0
const RAIN_HEIGHT := 24.0
const RAIN_DROPS := 1800

## Headlamps, fitted to every vehicle on the map. Measured off each vehicle's own
## collision box rather than hard-coded, so the van-bodied appliance gets them at its
## own width and the hatchback at its.
const BEAM_ANGLE := 34.0
const BEAM_RANGE := 22.0
const BEAM_ENERGY := 3.2
const BEAM_COLOUR := Color(1.0, 0.95, 0.84)

var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _street: Node3D
var _environment: Environment
## The sky's own material, so night is a night sky rather than a dark city under a
## noon one -- which is what the first build looked like, and it read as broken.
var _sky: ProceduralSkyMaterial
## The generator's own daylight, captured once. Restored verbatim for Mode.DAY.
var _baseline := {}
## Built the first time it rains and kept thereafter, because a GPUParticles3D with a
## process material is not free to construct and the weather is a toggle.
var _rain: GPUParticles3D


func _ready() -> void:
	_key = get_node_or_null(key_light_path) as DirectionalLight3D
	_fill = get_node_or_null(fill_light_path) as DirectionalLight3D
	_street = get_node_or_null(street_lights_path) as Node3D
	var world := get_node_or_null(environment_path) as WorldEnvironment
	if world:
		_environment = world.environment
		if _environment and _environment.sky:
			_sky = _environment.sky.sky_material as ProceduralSkyMaterial
	_capture()
	# Vehicles already standing when this wakes up, then everything added later.
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		_fit_headlights(node)
	get_tree().node_added.connect(_on_node_added)
	_apply()


## True when the district is dark enough to be running on its own lights. The one
## question anything else should ask -- nothing outside here compares modes.
func is_dark() -> bool:
	return time_of_day >= LIT_BELOW


## True when the road is wet. The counterpart to [method is_dark], and the only
## question anything else should ask about the weather.
func is_wet() -> bool:
	return weather == Weather.RAIN


## Grip every vehicle on the map is running on, dry 1.0. Public so a measurement can
## ask the same question the vehicles do rather than restating the constant.
func road_grip() -> float:
	return WET_GRIP if is_wet() else 1.0


func set_time_of_day(mode: int) -> void:
	var wanted: Mode = clampi(mode, Mode.DAY, Mode.NIGHT) as Mode
	if wanted == time_of_day and not _baseline.is_empty():
		return
	time_of_day = wanted
	if is_inside_tree():
		_apply()
		changed.emit(time_of_day)


func set_weather(next: int) -> void:
	var wanted: Weather = clampi(next, Weather.CLEAR, Weather.RAIN) as Weather
	if wanted == weather and not _baseline.is_empty():
		return
	weather = wanted
	if is_inside_tree():
		_apply()


## The generator's daylight, read out of the scene so it never has to be restated.
func _capture() -> void:
	if _key:
		_baseline["key_rotation"] = _key.rotation
		_baseline["key_energy"] = _key.light_energy
		_baseline["key_colour"] = _key.light_color
	if _fill:
		_baseline["fill_energy"] = _fill.light_energy
		_baseline["fill_colour"] = _fill.light_color
	if _environment:
		_baseline["ambient_energy"] = _environment.ambient_light_energy
		_baseline["ambient_colour"] = _environment.ambient_light_color
		_baseline["fog_density"] = _environment.fog_density
		_baseline["fog_colour"] = _environment.fog_light_color
		_baseline["exposure"] = _environment.tonemap_exposure
	if _sky:
		_baseline["sky_top"] = _sky.sky_top_color
		_baseline["sky_horizon"] = _sky.sky_horizon_color
		_baseline["ground_horizon"] = _sky.ground_horizon_color
		_baseline["ground_bottom"] = _sky.ground_bottom_color


func _apply() -> void:
	var preset: Dictionary = PRESETS.get(time_of_day, {})
	if preset.is_empty():
		_restore_daylight()
	else:
		if _key:
			_key.rotation = Vector3(deg_to_rad(float(preset["elevation"])),
				deg_to_rad(float(preset["azimuth"])), 0.0)
			_key.light_energy = float(preset["key_energy"])
			_key.light_color = preset["key_colour"]
		if _fill:
			_fill.light_energy = float(preset["fill_energy"])
			_fill.light_color = preset["fill_colour"]
		if _environment:
			_environment.ambient_light_energy = float(preset["ambient_energy"])
			_environment.ambient_light_color = preset["ambient_colour"]
			_environment.fog_density = float(preset["fog_density"])
			_environment.fog_light_color = preset["fog_colour"]
			_environment.tonemap_exposure = float(preset["exposure"])
		if _sky:
			_sky.sky_top_color = preset["sky_top"]
			_sky.sky_horizon_color = preset["sky_horizon"]
			# The ground half of the procedural sky is a white band at the horizon by
			# default, and at night it reads as a strip of daylight under the skyline.
			_sky.ground_horizon_color = preset["ground_horizon"]
			_sky.ground_bottom_color = preset["ground_bottom"]

	# Rain thickens the air and cools it, on top of whatever the hour just set. Applied
	# after the preset rather than folded into it, so the two settings compose: every
	# hour has a wet version without six more rows in the table.
	if is_wet() and _environment:
		_environment.fog_density *= 2.4
		_environment.fog_light_color = _environment.fog_light_color.lerp(
			Color(0.44, 0.47, 0.53), 0.55)
		_environment.tonemap_exposure *= 0.92

	var wet := road_grip()
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var vehicle := node as Vehicle
		if vehicle:
			vehicle.grip_scale = wet
	_update_rain()

	var dark := is_dark()
	if _street:
		_street.visible = dark
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var beams := (node as Node).get_node_or_null("Headlights") as Node3D
		if beams:
			beams.visible = dark


func _restore_daylight() -> void:
	if _baseline.is_empty():
		return
	if _key:
		_key.rotation = _baseline["key_rotation"]
		_key.light_energy = _baseline["key_energy"]
		_key.light_color = _baseline["key_colour"]
	if _fill:
		_fill.light_energy = _baseline["fill_energy"]
		_fill.light_color = _baseline["fill_colour"]
	if _environment:
		_environment.ambient_light_energy = _baseline["ambient_energy"]
		_environment.ambient_light_color = _baseline["ambient_colour"]
		_environment.fog_density = _baseline["fog_density"]
		_environment.fog_light_color = _baseline["fog_colour"]
		_environment.tonemap_exposure = _baseline["exposure"]
	if _sky and _baseline.has("sky_top"):
		_sky.sky_top_color = _baseline["sky_top"]
		_sky.sky_horizon_color = _baseline["sky_horizon"]
		_sky.ground_horizon_color = _baseline["ground_horizon"]
		_sky.ground_bottom_color = _baseline["ground_bottom"]


func _on_node_added(node: Node) -> void:
	# Vehicles arrive from the station mid-shift, and the ambient fleet is laid down
	# with the map. Both come through here.
	if node is Vehicle:
		_fit_headlights.call_deferred(node)
		# And it drives on the same road as everything else: a car bought in the rain
		# is wet from its first metre, without the station knowing about the weather.
		(node as Vehicle).grip_scale = road_grip()


## The rain, built once and then only shown or hidden.
##
## Parented to this node and moved to sit over the camera each frame rather than made a
## child of the camera: the camera is the RTS rig, which is rotated and zoomed, and rain
## that inherited that would tilt with it. Water falls straight down whatever the player
## is looking at.
func _update_rain() -> void:
	if not is_wet():
		if _rain:
			_rain.emitting = false
			_rain.visible = false
		set_process(false)
		return
	if _rain == null:
		_rain = _build_rain()
	_rain.visible = true
	_rain.emitting = true
	set_process(true)
	_track_camera()


func _process(_delta: float) -> void:
	_track_camera()


## Keeps the rain box over whatever the camera is looking at. The district is 260m and
## the box is 60m, so following the view is what stops the player driving out from under
## the weather.
func _track_camera() -> void:
	if _rain == null or not _rain.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# The ground point the camera is aimed at, not the camera itself -- at this pitch
	# they are 30m apart and the rain would fall behind the view.
	var focus := camera.global_position
	var forward := -camera.global_basis.z
	if absf(forward.y) > 0.05:
		focus += forward * (camera.global_position.y / -forward.y)
	_rain.global_position = Vector3(focus.x, RAIN_HEIGHT, focus.z)


func _build_rain() -> GPUParticles3D:
	var drops := GPUParticles3D.new()
	drops.name = "Rain"
	drops.amount = RAIN_DROPS
	drops.lifetime = 1.4
	drops.preprocess = 1.4
	drops.explosiveness = 0.0
	# The box is wide enough to cover the view and is not culled when its origin
	# leaves the frustum, which at this size it constantly would be.
	drops.visibility_aabb = AABB(Vector3(-RAIN_BOX, -RAIN_HEIGHT, -RAIN_BOX),
		Vector3(RAIN_BOX * 2.0, RAIN_HEIGHT * 2.0, RAIN_BOX * 2.0))

	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(RAIN_BOX, 1.0, RAIN_BOX)
	motion.direction = Vector3(0.05, -1.0, 0.0)
	motion.spread = 2.0
	motion.initial_velocity_min = 18.0
	motion.initial_velocity_max = 24.0
	motion.gravity = Vector3(0.0, -22.0, 0.0)
	motion.scale_min = 0.7
	motion.scale_max = 1.3
	drops.process_material = motion

	# A thin stretched quad reads as a falling streak at RTS distance; a round sprite
	# reads as snow.
	var streak := QuadMesh.new()
	# Small and faint on purpose. Rain reads as *quantity*, not as size: a big bright
	# streak at RTS distance looks like debris, and any streak that passes close to the
	# camera is magnified enormously whatever it measures on the ground.
	streak.size = Vector2(0.02, 0.42)
	var wet := StandardMaterial3D.new()
	wet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.albedo_color = Color(0.80, 0.87, 0.97, 0.22)
	# BILLBOARD_PARTICLES, not BILLBOARD_ENABLED: the particle form keeps the quad's
	# own Y axis upright while turning it to face the view, which is what makes a drop
	# read as a falling streak instead of a flake turning end-on.
	wet.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	streak.material = wet
	drops.draw_pass_1 = streak
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drops)
	return drops


## Two beams on the nose, sized from the vehicle's own collision box.
##
## Deferred and guarded: `node_added` fires from inside `add_child`, before the
## vehicle's own `_ready` has run and before its collider is reachable -- the same
## ordering trap the call board hit reading a spreading fire's position.
func _fit_headlights(node: Node) -> void:
	var vehicle := node as Vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if vehicle.has_node("Headlights"):
		return
	var collider := vehicle.get_node_or_null("Collision") as CollisionShape3D
	var box := collider.shape as BoxShape3D if collider else null
	if box == null:
		return

	var beams := Node3D.new()
	beams.name = "Headlights"
	beams.visible = is_dark()
	vehicle.add_child(beams)
	for side in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.light_color = BEAM_COLOUR
		beam.light_energy = BEAM_ENERGY
		beam.spot_range = BEAM_RANGE
		beam.spot_angle = BEAM_ANGLE
		beam.spot_angle_attenuation = 0.9
		# Shadows off, and not a close call: this is up to sixty lights once the
		# ambient fleet has them, thrown at flat tarmac.
		beam.shadow_enabled = false
		# The nose is -Z, the collider is centred on the hull, and the lamps sit a
		# third of the way up it. Aimed slightly down so the beam lands on the road
		# ahead rather than lighting first-floor windows.
		beam.position = Vector3(side * box.size.x * 0.34, box.size.y * 0.34,
			-box.size.z * 0.5 + collider.position.z)
		beam.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
		beams.add_child(beam)
