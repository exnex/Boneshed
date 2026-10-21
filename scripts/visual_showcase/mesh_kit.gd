extends RefCounted
## Procedural mesh accumulator for the visual showcase. Primitives are appended per
## material id and committed as one ArrayMesh with one surface per material, so a
## character or a whole room costs one draw call per material (plus shadow passes).
##
## Skinning: every vertex carries up to four bone influences (normalised). A rigid part
## (an armor plate, a skull, a buckle) passes a single bone with weight 1, so it never
## deforms; deformable parts (skin, cloth, mail) blend neighbouring bones. Static props
## pass an empty weight dictionary and are committed without skin arrays.
##
## Conventions: metres, forward −Z, right +X, up +Y (same as the melee lab rules frame).

const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const MAX_INFLUENCES := 4

## material id → {"st": SurfaceTool, "count": int}
var _surfaces: Dictionary = {}
var skinned: bool = true
var triangle_count: int = 0
## Applied to every vertex: lets modular pieces build in their own local frame.
var base: Transform3D = Transform3D.IDENTITY
## Flat primitives use smooth group -1 so SurfaceTool keeps hard edges.
var _flat: bool = false

func _init(is_skinned := true) -> void:
	skinned = is_skinned

func _surface(material: String) -> Dictionary:
	if not _surfaces.has(material):
		var st := SurfaceTool.new()
		if skinned:
			st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = {"st": st, "count": 0}
	return _surfaces[material]

## Normalised top-4 influences as parallel arrays.
static func influences(weights: Dictionary) -> Array:
	var pairs: Array = []
	for bone: int in weights:
		if float(weights[bone]) > 0.0001:
			pairs.append([bone, float(weights[bone])])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	pairs = pairs.slice(0, MAX_INFLUENCES)
	var total := 0.0
	for pair: Array in pairs:
		total += pair[1]
	var bones := PackedInt32Array([0, 0, 0, 0])
	var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if total <= 0.0:
		values[0] = 1.0
		return [bones, values]
	for i in range(pairs.size()):
		bones[i] = pairs[i][0]
		values[i] = pairs[i][1] / total
	return [bones, values]

func _vertex(s: Dictionary, position: Vector3, uv: Vector2, weights: Dictionary, color := Color.WHITE) -> int:
	var st: SurfaceTool = s.st
	st.set_smooth_group(-1 if _flat else 0)
	st.set_uv(uv)
	st.set_color(color)
	if skinned:
		var inf := influences(weights)
		st.set_bones(inf[0])
		st.set_weights(inf[1])
	st.add_vertex(base * position)
	s.count += 1
	return s.count - 1

func _tri(s: Dictionary, a: int, b: int, c: int) -> void:
	var st: SurfaceTool = s.st
	st.add_index(a)
	st.add_index(b)
	st.add_index(c)
	triangle_count += 1

## A ring is {"c": centre, "x": unit axis, "z": unit axis, "rx", "rz", "w": weights}
## plus optional "shape": Callable(angle: float) -> float radius multiplier, and
## optional "wfn": Callable(angle) -> Dictionary per-vertex weights (overrides "w").
## Rings are connected in order; `cap_start`/`cap_end` close the ends with a fan.
## Faces are oriented outward automatically; `flip` turns the surface inside out.
func loft(material: String, rings: Array, segments: int, cap_start := false, cap_end := false, flip := false, v_scale := 1.0) -> void:
	var s := _surface(material)
	# Orient faces outward whatever the ring axes' handedness and the advance direction.
	if rings.size() > 1:
		var first: Dictionary = rings[0]
		var advance: Vector3 = (rings[1].c as Vector3) - (first.c as Vector3)
		if (first.x as Vector3).cross(first.z as Vector3).dot(advance) > 0.0:
			flip = not flip
	var rows: Array[PackedInt32Array] = []
	var length := 0.0
	for r in range(rings.size()):
		var ring: Dictionary = rings[r]
		if r > 0:
			length += (ring.c as Vector3).distance_to(rings[r - 1].c)
		var row := PackedInt32Array()
		for i in range(segments + 1):
			var angle := TAU * float(i) / segments
			row.append(_vertex(s, ring_point(ring, angle), Vector2(float(i) / segments, length * v_scale), _ring_weights(ring, angle)))
		rows.append(row)
	for r in range(rows.size() - 1):
		for i in range(segments):
			var a := rows[r][i]
			var b := rows[r][i + 1]
			var c := rows[r + 1][i]
			var d := rows[r + 1][i + 1]
			if flip:
				_tri(s, a, c, b)
				_tri(s, b, c, d)
			else:
				_tri(s, a, b, c)
				_tri(s, b, d, c)
	for end: Array in [[cap_start, 0, true], [cap_end, rings.size() - 1, false]]:
		if not end[0]:
			continue
		var ring: Dictionary = rings[end[1]]
		var centre := _vertex(s, ring.c, Vector2(0.5, 0.5), ring.get("w", {}))
		var row: PackedInt32Array = rows[end[1]]
		for i in range(segments):
			if end[2] != flip:
				_tri(s, centre, row[i + 1], row[i])
			else:
				_tri(s, centre, row[i], row[i + 1])

static func ring_point(ring: Dictionary, angle: float) -> Vector3:
	var scale := 1.0
	if ring.has("shape"):
		scale = float((ring.shape as Callable).call(angle))
	return ring.c + (ring.x as Vector3) * cos(angle) * float(ring.rx) * scale + (ring.z as Vector3) * sin(angle) * float(ring.rz) * scale

static func _ring_weights(ring: Dictionary, angle: float) -> Dictionary:
	if ring.has("wfn"):
		return (ring.wfn as Callable).call(angle)
	return ring.get("w", {})

## Superellipsoid (exponent 2 = ellipsoid, higher = boxier) in `xf` space. `deform`
## (optional) maps a unit-sphere direction to a radius multiplier; `wfn` (optional)
## maps the local point to weights.
func blob(material: String, xf: Transform3D, radii: Vector3, weights: Dictionary, segments := 16, stacks := 10,
		exponent := 2.0, deform: Callable = Callable(), wfn: Callable = Callable()) -> void:
	var s := _surface(material)
	var grid: Array[PackedInt32Array] = []
	for j in range(stacks + 1):
		var v := float(j) / stacks
		var phi := PI * v - PI * 0.5
		var row := PackedInt32Array()
		for i in range(segments + 1):
			var u := float(i) / segments
			var theta := TAU * u
			var cp := _spow(cos(phi), exponent)
			var local := Vector3(cp * _spow(cos(theta), exponent), _spow(sin(phi), exponent), cp * _spow(sin(theta), exponent))
			var unit := Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
			var m := float(deform.call(unit)) if deform.is_valid() else 1.0
			var p := local * radii * m
			var w: Dictionary = wfn.call(p) if wfn.is_valid() else weights
			row.append(_vertex(s, xf * p, Vector2(u, v), w))
		grid.append(row)
	for j in range(stacks):
		for i in range(segments):
			var a := grid[j][i]
			var b := grid[j][i + 1]
			var c := grid[j + 1][i]
			var d := grid[j + 1][i + 1]
			_tri(s, a, b, c)
			_tri(s, b, d, c)

static func _spow(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), 2.0 / exponent)

## Flat-shaded box (separate vertices per face) with optional chamfer-free jitter.
func box(material: String, xf: Transform3D, size: Vector3, weights: Dictionary, uv_scale := 1.0, uv_offset := Vector2.ZERO) -> void:
	var s := _surface(material)
	_flat = true
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var centre := n * absf(n.dot(h))
		var idx: Array[int] = []
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := centre + u * corner.x * hu + v * corner.y * hv
			idx.append(_vertex(s, xf * p, Vector2((corner.x * hu + hu) * uv_scale, (corner.y * hv + hv) * uv_scale) + uv_offset, weights))
		_tri(s, idx[0], idx[2], idx[1])
		_tri(s, idx[0], idx[3], idx[2])
	_flat = false

## Extrudes a closed 2D outline (counter-clockwise, in the xf's XY plane) by `depth`
## along xf's Z, with flat caps. `bevel_scale` shrinks the cap outlines (a cheap edge
## bevel: blades get a ridge, plates a rim).
func extrude(material: String, xf: Transform3D, outline: PackedVector2Array, depth: float, weights: Dictionary, bevel_scale := 1.0) -> void:
	var s := _surface(material)
	_flat = true
	var n := outline.size()
	var centre := Vector2.ZERO
	for p: Vector2 in outline:
		centre += p
	centre /= n
	for side: float in [-1.0, 1.0]:
		var c := _vertex(s, xf * Vector3(centre.x, centre.y, side * depth * 0.5 * (1.0 if bevel_scale >= 1.0 else 1.6)), centre, weights)
		var ring: Array[int] = []
		for p: Vector2 in outline:
			var q := centre + (p - centre) * bevel_scale
			ring.append(_vertex(s, xf * Vector3(q.x, q.y, side * depth * 0.5), q, weights))
		for i in range(n):
			if side > 0.0:
				_tri(s, c, ring[(i + 1) % n], ring[i])
			else:
				_tri(s, c, ring[i], ring[(i + 1) % n])
	# Side walls, hard-edged.
	for i in range(n):
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var ia := _vertex(s, xf * Vector3(a.x, a.y, -depth * 0.5), Vector2(float(i) / n, 0.0), weights)
		var ib := _vertex(s, xf * Vector3(b.x, b.y, -depth * 0.5), Vector2(float(i + 1) / n, 0.0), weights)
		var ic := _vertex(s, xf * Vector3(b.x, b.y, depth * 0.5), Vector2(float(i + 1) / n, depth), weights)
		var id := _vertex(s, xf * Vector3(a.x, a.y, depth * 0.5), Vector2(float(i) / n, depth), weights)
		_tri(s, ia, ic, ib)
		_tri(s, ia, id, ic)
	_flat = false

## Tapered tube between two points (cylinder when ra == rb).
func tube(material: String, a: Vector3, b: Vector3, ra: float, rb: float, weights: Dictionary, segments := 8, caps := true) -> void:
	var axis := b - a
	if axis.length() < 0.0001:
		return
	var basis := basis_from_y(axis.normalized())
	loft(material, [{"c": a, "x": basis.x, "z": basis.z, "rx": ra, "rz": ra, "w": weights},
		{"c": b, "x": basis.x, "z": basis.z, "rx": rb, "rz": rb, "w": weights}], segments, caps, caps)

## Orthonormal basis whose Y is `y`; Z follows `hint` as closely as possible.
static func basis_from_y(y: Vector3, hint := Vector3.BACK) -> Basis:
	var yy := y.normalized()
	var z := hint - yy * hint.dot(yy)
	if z.length() < 0.001:
		z = Vector3.UP - yy * yy.y if absf(yy.y) < 0.99 else Vector3.BACK
	z = z.normalized()
	return Basis(yy.cross(z), yy, z)

## One ArrayMesh, a surface per material (sorted by id for determinism).
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var ids := _surfaces.keys()
	ids.sort()
	for id: String in ids:
		var st: SurfaceTool = _surfaces[id].st
		st.generate_normals()
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, MaterialLibrary.get_material(id))
		mesh.surface_set_name(mesh.get_surface_count() - 1, id)
	return mesh

func is_empty() -> bool:
	return _surfaces.is_empty()
