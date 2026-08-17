extends RefCounted
class_name Markers

## The two things this game draws on the ground: the bracket under a selected unit, and
## the reticle where it has been told to go.
##
## **Built here rather than in the scenes that carry them**, which is the point. The
## selection ring existed six times over -- once in `build_vehicles.gd` and once in each
## of `Person`, `Paramedic`, `Firefighter` and `Doctor` -- as a `TorusMesh` sub-resource,
## and the move marker twice more in `build_map.gd` and `build_tutorial.gd`. Changing
## how selection *looks* meant editing eight places and regenerating two scenes with a
## window. It is one function now, called at load by [Unit] and [RTSController], and the
## meshes in those scenes are placeholders that get swapped out.
##
## Flat in the XZ plane, y = 0, wound so the face points up. The caller lifts them clear
## of the ground; both are drawn unshaded so they read the same under any sun.
##
## **A bracket rather than a ring** (August 2026), because the rest of the interface is
## the user's UI kit now and a plain torus was the last thing in the game still drawn the
## way phase 1 drew it. Corners also survive being small on screen better than a circle,
## which at 30m of camera height turns into a fuzzy ellipse.

## How much of each side the bracket's arms take up. Two fifths reads as a corner; much
## more and it closes back into the ring it replaced.
const ARM := 0.4
## Arm thickness as a fraction of the bracket's half-width.
const THICKNESS := 0.085


## Four corner brackets around a square of half-width [param reach].
static func bracket(reach: float) -> ArrayMesh:
	var half := maxf(reach, 0.2)
	var arm := half * ARM
	var thick := maxf(half * THICKNESS, 0.03)
	var faces := PackedVector3Array()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var cx := sx * half
			var cz := sz * half
			# The arm running along X from the corner, and the one running along Z.
			# Each is a rectangle; `_quad` winds it face-up whichever way the signs go.
			_quad(faces, Vector2(cx, cz), Vector2(cx - sx * arm, cz - sz * thick))
			_quad(faces, Vector2(cx, cz), Vector2(cx - sx * thick, cz - sz * arm))
	return _mesh(faces)


## A target reticle: a thin ring with four ticks reaching in toward the centre.
##
## Geometry rather than the kit's `icon_target.svg` on a quad, though that was the first
## cut. A textured quad has to face the camera to look right, and this marker is
## deliberately flat on the ground and spun about Y by [RTSController] -- a billboard
## would have thrown that away, and a flat textured quad reads as a decal of an icon
## rather than as something in the world.
static func reticle(radius: float) -> ArrayMesh:
	var faces := PackedVector3Array()
	var thick := maxf(radius * 0.12, 0.05)
	var segments := 32
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var inner := radius - thick
		# One trapezoid of the annulus. Wound anticlockwise seen from above.
		var p0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var p1 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p2 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var p3 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		faces.append_array([p0, p1, p2, p0, p2, p3])
	# The ticks, at the quarters, reaching from the ring toward the middle.
	var reach := radius * 0.45
	for quarter in 4:
		var angle := TAU * float(quarter) / 4.0
		var along := Vector3(cos(angle), 0.0, sin(angle))
		var across := Vector3(-along.z, 0.0, along.x) * thick * 0.5
		var tip := along * (radius - thick - reach)
		var base := along * (radius - thick)
		faces.append_array([tip - across, base - across, base + across,
			tip - across, base + across, tip + across])
	return _mesh(faces)


## Adds the rectangle spanned by two opposite corners, face up.
##
## The corners arrive in whatever order the sign arithmetic produced, so the winding is
## fixed here by sorting rather than assumed. Wound the other way the triangles face the
## ground and the bracket is invisible from the only angle anyone looks at it from --
## which is a slow thing to debug and a cheap thing to prevent.
static func _quad(faces: PackedVector3Array, a: Vector2, b: Vector2) -> void:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.y, b.y)
	var z1 := maxf(a.y, b.y)
	var p0 := Vector3(x0, 0.0, z0)
	var p1 := Vector3(x1, 0.0, z0)
	var p2 := Vector3(x1, 0.0, z1)
	var p3 := Vector3(x0, 0.0, z1)
	faces.append_array([p0, p1, p2, p0, p2, p3])


static func _mesh(faces: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var normals := PackedVector3Array()
	normals.resize(faces.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
