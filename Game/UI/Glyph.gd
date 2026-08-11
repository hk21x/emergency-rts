extends RefCounted
class_name Glyph

## Every symbol the interface uses, in one place.
##
## Symbols come from the icon pack -- one white 64px PNG per key under
## `Game/UI/Icons/`, tinted to the ink colour at draw time, so one texture serves a
## 54px command tile, a 38px avatar and a 22px pill badge in whatever colour each
## needs. The drawn primitives below are the **fallback**: a key with no texture on
## disk still renders, just plainer -- the same rule the minimap applies when its
## base render is missing.
##
## Fallback shapes are given in a unit box -- x and y from -1 to 1, y pointing down,
## the way a Control's coordinates run -- and scaled to [param r] pixels at draw time.
##
## `Array[Vector2]` rather than `PackedVector2Array` throughout: the packed
## constructor is a call, and GDScript will not fold a call into a constant.

const ICON_DIR := "res://Game/UI/Icons/"
## The pack's icons carry their own padding, so at the same radius they read smaller
## than the primitives did. Drawn a third larger to sit at the same optical size.
const ICON_SCALE := 1.35

static var _textures := {}


## Draws [param key] centred on [param at], fitting a box of +/- [param r] pixels.
##
## [param accent] is the colour of the detail a symbol carries on top of itself --
## the cross on the ambulance's box. An unknown key draws a question mark rather than
## nothing, so a panel that asks for a symbol nobody wrote is visibly wrong instead
## of quietly blank.
static func draw(target: CanvasItem, key: StringName, at: Vector2, r: float,
		ink: Color, accent := Color.TRANSPARENT) -> void:
	var texture := _texture(key)
	if texture != null:
		var half := r * ICON_SCALE
		target.draw_texture_rect(texture,
			Rect2(at - Vector2(half, half), Vector2(half * 2.0, half * 2.0)),
			false, ink)
		# The ambulance is the pack's box truck with the cross stamped on its box --
		# the same composite the drawn version used, because the cross is the whole
		# difference between it and a delivery run.
		if key == &"ambulance" and accent.a > 0.0:
			_cross(target, at + Vector2(-r * 0.35, -r * 0.1), r * 0.28, accent)
		return
	_fallback(target, key, at, r, ink, accent)


## A key's texture, loaded once. Null -- and the primitives below -- when the pack
## has nothing for it.
static func _texture(key: StringName) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var path := ICON_DIR + str(key) + ".png"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[key] = texture
	return texture


static func _fallback(target: CanvasItem, key: StringName, at: Vector2, r: float,
		ink: Color, accent := Color.TRANSPARENT) -> void:
	match key:
		&"arrow": _polygon(target, at, r, ARROW, ink)
		&"halt": _polygon(target, at, r, _octagon(), ink)
		&"cross": _cross(target, at, r, ink)
		&"droplet": _polygon(target, at, r, DROPLET, ink)
		&"stretcher": _stretcher(target, at, r, ink)
		&"door_in": _door(target, at, r, ink, 1.0)
		&"door_out": _door(target, at, r, ink, -1.0)
		&"cone": _polygon(target, at, r, CONE, ink)
		&"station": _polygon(target, at, r, STATION, ink)
		&"flame": _polygon(target, at, r, FLAME, ink)
		&"car": _car(target, at, r, ink, Color.TRANSPARENT)
		&"ambulance": _car(target, at, r, ink, accent)
		&"person": _person(target, at, r, ink)
		&"beacon": _beacon(target, at, r, ink)
		&"horn": _horn(target, at, r, ink)
		_: _unknown(target, at, r, ink)


# --- Command symbols ---------------------------------------------------------

const ARROW: Array[Vector2] = [
	Vector2(0.0, -1.0), Vector2(0.62, -0.16), Vector2(0.26, -0.16),
	Vector2(0.26, 1.0), Vector2(-0.26, 1.0), Vector2(-0.26, -0.16),
	Vector2(-0.62, -0.16)]

const DROPLET: Array[Vector2] = [
	Vector2(0.0, -1.0), Vector2(0.42, -0.22), Vector2(0.60, 0.26),
	Vector2(0.44, 0.72), Vector2(0.0, 0.92), Vector2(-0.44, 0.72),
	Vector2(-0.60, 0.26), Vector2(-0.42, -0.22)]

const CONE: Array[Vector2] = [
	Vector2(0.0, -1.0), Vector2(0.38, 0.62), Vector2(0.78, 0.62),
	Vector2(0.78, 0.95), Vector2(-0.78, 0.95), Vector2(-0.78, 0.62),
	Vector2(-0.38, 0.62)]

const STATION: Array[Vector2] = [
	Vector2(0.0, -0.95), Vector2(1.0, -0.05), Vector2(0.66, -0.05),
	Vector2(0.66, 0.95), Vector2(-0.66, 0.95), Vector2(-0.66, -0.05),
	Vector2(-1.0, -0.05)]

## Two licks rather than one, or it reads as a leaf.
const FLAME: Array[Vector2] = [
	Vector2(0.0, -1.0), Vector2(0.34, -0.42), Vector2(0.52, -0.60),
	Vector2(0.66, -0.10), Vector2(0.72, 0.36), Vector2(0.40, 0.86),
	Vector2(-0.06, 0.98), Vector2(-0.50, 0.80), Vector2(-0.70, 0.32),
	Vector2(-0.54, -0.18), Vector2(-0.24, -0.52)]

# --- Unit silhouettes --------------------------------------------------------

## Side profile. Reads as a car at 20px, which a three-quarter view does not.
const BODY: Array[Vector2] = [
	Vector2(-1.0, 0.28), Vector2(-0.78, -0.12), Vector2(-0.34, -0.46),
	Vector2(0.34, -0.46), Vector2(0.78, -0.12), Vector2(1.0, 0.28),
	Vector2(1.0, 0.52), Vector2(-1.0, 0.52)]

const TORSO: Array[Vector2] = [
	Vector2(-0.46, 0.95), Vector2(-0.42, 0.05), Vector2(-0.22, -0.16),
	Vector2(0.22, -0.16), Vector2(0.42, 0.05), Vector2(0.46, 0.95)]


# --- Composites --------------------------------------------------------------

## Computed rather than tabulated: eight points from a loop is less to get wrong than
## eight hand-typed pairs, and a stop sign has to be regular or it reads as a blob.
static func _octagon() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in 8:
		var angle := PI / 8.0 + TAU * i / 8.0
		points.append(Vector2(cos(angle), sin(angle)))
	return points


static func _cross(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var arm := r * 0.30
	target.draw_rect(Rect2(at - Vector2(r, arm), Vector2(r * 2.0, arm * 2.0)), ink, true)
	target.draw_rect(Rect2(at - Vector2(arm, r), Vector2(arm * 2.0, r * 2.0)), ink, true)


## A visible [param cross] stamps the flank, which is the whole difference between the
## ambulance avatar and the patrol car one at 38 pixels.
static func _car(target: CanvasItem, at: Vector2, r: float, ink: Color,
		cross: Color) -> void:
	_polygon(target, at + Vector2(0.0, -r * 0.15), r, BODY, ink)
	target.draw_circle(at + Vector2(-r * 0.52, r * 0.42), r * 0.24, ink)
	target.draw_circle(at + Vector2(r * 0.52, r * 0.42), r * 0.24, ink)
	if cross.a > 0.0:
		_cross(target, at + Vector2(0.0, -r * 0.1), r * 0.30, cross)


static func _person(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	target.draw_circle(at + Vector2(0.0, -r * 0.55), r * 0.32, ink)
	_polygon(target, at, r, TORSO, ink)


static func _stretcher(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var thickness := maxf(r * 0.16, 1.5)
	# Bed, handles either end, and two legs -- reads as a trolley rather than a plank.
	target.draw_rect(Rect2(at + Vector2(-r * 0.72, -r * 0.14),
		Vector2(r * 1.44, r * 0.28)), ink, true)
	target.draw_line(at + Vector2(-r, 0.0), at + Vector2(-r * 0.72, 0.0), ink, thickness)
	target.draw_line(at + Vector2(r * 0.72, 0.0), at + Vector2(r, 0.0), ink, thickness)
	target.draw_line(at + Vector2(-r * 0.45, r * 0.14), at + Vector2(-r * 0.45, r * 0.8),
		ink, thickness)
	target.draw_line(at + Vector2(r * 0.45, r * 0.14), at + Vector2(r * 0.45, r * 0.8),
		ink, thickness)
	# The patient's head, so it is not just furniture.
	target.draw_circle(at + Vector2(-r * 0.4, -r * 0.5), r * 0.24, ink)


## A doorway with an arrow beside it. [param way] is +1 to go in, -1 to come out.
##
## Both arrows occupy exactly the same span, and only which end carries the head says
## which verb it is. Letting the shaft move as well made Board and Unload read as the
## same tile at a glance, which is the one thing these two must not do.
static func _door(target: CanvasItem, at: Vector2, r: float, ink: Color,
		way: float) -> void:
	var thickness := maxf(r * 0.16, 1.5)
	target.draw_rect(Rect2(at + Vector2(r * 0.18, -r), Vector2(r * 0.82, r * 2.0)),
		ink, false, thickness)
	target.draw_circle(at + Vector2(r * 0.36, 0.0), r * 0.12, ink)

	var near := at + Vector2(-r * 0.15, 0.0)
	var far := at + Vector2(-r * 0.95, 0.0)
	var tip := near if way > 0.0 else far
	target.draw_line(near, far, ink, thickness)
	target.draw_colored_polygon(PackedVector2Array([
		tip + Vector2(r * 0.30 * way, 0.0),
		tip + Vector2(0.0, -r * 0.28),
		tip + Vector2(0.0, r * 0.28)]), ink)


## A roof beacon: dome on a base bar, with rays coming off it so it reads as a light
## that is *on* rather than an upturned bowl.
const BEACON_DOME: Array[Vector2] = [
	Vector2(-0.55, 0.35), Vector2(-0.55, 0.15), Vector2(-0.30, -0.30),
	Vector2(0.30, -0.30), Vector2(0.55, 0.15), Vector2(0.55, 0.35)]

static func _beacon(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var thickness := maxf(r * 0.14, 1.5)
	_polygon(target, at, r, BEACON_DOME, ink)
	target.draw_rect(Rect2(at + Vector2(-r * 0.78, r * 0.35), Vector2(r * 1.56, r * 0.26)),
		ink, true)
	for spread in [-0.7, 0.0, 0.7]:
		var direction := Vector2(sin(spread), -cos(spread))
		target.draw_line(at + Vector2(0.0, -r * 0.35) + direction * r * 0.5,
			at + Vector2(0.0, -r * 0.35) + direction * r * 0.95, ink, thickness)


## A loudhailer with sound arcs. The pair with the beacon: this one is the noise.
const HORN_BODY: Array[Vector2] = [
	Vector2(-0.95, -0.30), Vector2(-0.40, -0.30), Vector2(0.10, -0.75),
	Vector2(0.10, 0.75), Vector2(-0.40, 0.30), Vector2(-0.95, 0.30)]

static func _horn(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var thickness := maxf(r * 0.14, 1.5)
	_polygon(target, at, r, HORN_BODY, ink)
	for reach in [0.45, 0.75]:
		target.draw_arc(at + Vector2(r * 0.15, 0.0), r * reach,
			-PI * 0.32, PI * 0.32, 10, ink, thickness)


## Deliberately loud: a symbol nobody wrote should look wrong, not absent.
static func _unknown(target: CanvasItem, at: Vector2, r: float, ink: Color) -> void:
	var font := ThemeDB.fallback_font
	var height := roundi(r * 2.2)
	var width := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
	target.draw_string(font, at + Vector2(-width * 0.5, r * 0.8), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1, height, ink)


static func _polygon(target: CanvasItem, at: Vector2, r: float, shape: Array[Vector2],
		ink: Color) -> void:
	var points := PackedVector2Array()
	for point in shape:
		points.append(at + point * r)
	target.draw_colored_polygon(points, ink)
