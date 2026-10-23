extends RefCounted
## Measures an imported Research Lab object (lab_import.gd) into the same analysis
## shape object_analysis.gd produces for the game's own v0 descriptors, so the shared
## affordance solver, motion and rules consume either. Pure maths on the converted
## parts, materials, declared grip intervals and the Lab's verified per-part masses.
## It never reads the record's name, filename, assembly number or id.
##
## Where the Lab defines a rule, the same rule is applied to the same fields:
##   - rigidity (objects.py `_rigid`): stiffness ≥ 1000 MPa, toughness ≥ 5000 kPa, no
##     flex joint, no unlocked hinge, up the parent chain → only rigid parts carry
##     damage contact or a grasp;
##   - cutting edge (`edge_sweep`): box thinner than 4 mm with edge radius ≤ 250 µm;
##   - point (`point_thrust`): cone tip whose base width × 4 ≤ its length;
##   - guard surface (`block`): second × third largest size ≥ 6000 mm²;
##   - grasp: only the Lab's declared intervals, never resampled rods.
## Game-only, explicitly approximate choices are marked APPROX below and listed in
## docs/ADAPTIVE_COMBAT_LAB.md.

const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const HAND_HALF_WIDTH := 0.04
const GRASP_RADIUS_MIN := 0.012
const GRASP_RADIUS_MAX := 0.026
const BLOCK_AREA := 0.006
const PLATE_MAX_THICKNESS := 0.006
const BAR_MAX_SECTION := 0.03

static func analyse(obj: Dictionary) -> Dictionary:
	var parts: Array = obj.parts
	var by_id := {}
	for p: Dictionary in parts:
		by_id[p.id] = p
	var samples: Array = []
	for p: Dictionary in parts:
		samples.append_array(_mass_samples(p))
	var points: Array = []
	for p: Dictionary in parts:
		points.append_array(_surface_points(p))
	var result := {
		"source": "lab",
		"mass": float(obj.physical.mass),
		"com": obj.physical.com,
		"samples": samples,
		"points": points,
		"extent": _extent(points),
		"intervals": _intervals(obj, by_id),
		"features": _features(obj, parts),
		"covers": _covers(obj, by_id),
		"probes": _probes(parts),
		"articulated": _articulated(parts),
		"parts": parts,
	}
	result.grips = _grip_markers(result.intervals)
	return result

static func _extent(points: Array) -> float:
	var best := 0.0
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			best = maxf(best, (points[i] as Vector3).distance_to(points[j]))
	return best

static func _tangents(p: Dictionary) -> Array:
	var t: Array = p.transverse_axes
	return [Imp.axis_vector(t[0]), Imp.axis_vector(t[1])]

## Point-mass samples carrying the Lab's verified per-part mass (they sum to it).
static func _mass_samples(p: Dictionary) -> Array:
	var out: Array = []
	var m: float = p.mass
	match str(p.shape):
		"rod":
			for i in range(8):
				out.append([(p.a as Vector3).lerp(p.b, (i + 0.5) / 8.0), m / 8.0])
		"cone":
			# Base at −axis; samples average to the quarter-height mass centroid.
			for t: float in [0.05, 0.2, 0.5]:
				out.append([(p.a as Vector3).lerp(p.b, t), m / 3.0])
		"box":
			var s: Vector3 = p.size
			var dims := [0, 1, 2]
			dims.sort_custom(func(x: int, y: int) -> bool: return s[x] > s[y])
			for su: float in [-0.33, 0.0, 0.33]:
				for sv: float in [-0.33, 0.0, 0.33]:
					var off := Vector3.ZERO
					off[dims[0]] = su * s[dims[0]]
					off[dims[1]] = sv * s[dims[1]]
					out.append([(p.center as Vector3) + off, m / 9.0])
		"ellipsoid":
			out.append([p.center, m * 0.4])
			for axis in range(3):
				for sgn: float in [-1.0, 1.0]:
					var off := Vector3.ZERO
					off[axis] = (p.size as Vector3)[axis] * 0.5 * sgn * 0.7
					out.append([(p.center as Vector3) + off, m * 0.1])
	return out

static func _surface_points(p: Dictionary) -> Array:
	var out: Array = []
	var c: Vector3 = p.center
	var h: Vector3 = (p.size as Vector3) * 0.5
	match str(p.shape):
		"box":
			for sx: float in [-1.0, 0.0, 1.0]:
				for sy: float in [-1.0, 0.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						out.append(c + Vector3(h.x * sx, h.y * sy, h.z * sz))
		"rod", "cone":
			var tg := _tangents(p)
			var r: Vector2 = p.radii
			for i in range(5):
				var on := (p.a as Vector3).lerp(p.b, i / 4.0)
				var shrink := 1.0 - (i / 4.0 if p.shape == "cone" else 0.0)
				for sgn: float in [-1.0, 1.0]:
					out.append(on + (tg[0] as Vector3) * r.x * sgn * shrink)
					out.append(on + (tg[1] as Vector3) * r.y * sgn * shrink)
		"ellipsoid":
			out.append(c)
			for axis in range(3):
				for sgn: float in [-1.0, 1.0]:
					var off := Vector3.ZERO
					off[axis] = h[axis] * sgn
					out.append(c + off)
	return out

## Inside another part's axis-aligned envelope (Lab `_point_clear` with radius r).
static func _inside(point: Vector3, p: Dictionary, r := 0.0) -> bool:
	var h: Vector3 = (p.size as Vector3) * 0.5
	var d := (point - (p.center as Vector3)).abs()
	return d.x <= h.x + r and d.y <= h.y + r and d.z <= h.z + r

static func _occluded(point: Vector3, own: Dictionary, parts: Array, r := 0.0) -> bool:
	for other: Dictionary in parts:
		if other.id != own.id and _inside(point, other, r):
			return true
	return false

## Declared grip intervals → hand-centre limits (a hand's half width inside each end),
## only on rigid supports of graspable radius with hand clearance.
static func _intervals(obj: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = []
	for g: Dictionary in obj.grips:
		var p: Dictionary = by_id[g.part]
		var a: Vector3 = g.a
		var b: Vector3 = g.b
		var axis := (b - a).normalized()
		var r: Vector2 = p.radii
		var radius := maxf(r.x, r.y)
		var reasons: Array = []
		if not p.rigid:
			reasons.append("unstable_grasp_support")
		if p.shape == "rod" and (radius < GRASP_RADIUS_MIN or radius > GRASP_RADIUS_MAX):
			reasons.append("grip_diameter")
		if p.shape == "box":
			reasons.append("box_grip_not_supported_by_game_hand_model")
		var lo := a + axis * HAND_HALF_WIDTH
		var hi := b - axis * HAND_HALF_WIDTH
		if (hi - lo).dot(axis) < 0.0:
			reasons.append("grip_interval_shorter_than_palm")
		out.append({"id": g.id, "part": g.part, "a": a, "b": b, "axis": axis, "radius": radius, "lo": lo, "hi": hi,
			"usable": reasons.is_empty(), "reasons": reasons})
	return out

## Debug markers for the overlay: hand-centre samples along each usable interval.
static func _grip_markers(intervals: Array) -> Array:
	var out: Array = []
	for iv: Dictionary in intervals:
		if not iv.usable:
			continue
		for i in range(5):
			var point := (iv.lo as Vector3).lerp(iv.hi, i / 4.0)
			out.append({"part": iv.part, "s": i / 4.0, "point": point, "axis": iv.axis, "radius": iv.radius})
	return out

static func _channel(kind: String, sharp: bool) -> String:
	if not sharp:
		return "blunt"
	return "pierce" if kind == "point" else "cut"

static func _feature(id: String, p: Dictionary, kind: String, pos: Vector3, normal: Vector3, radius: float, sharpness: float,
		hardness: float, area: float, half_extent := Vector3.ZERO, omni := false, extra := {}) -> Dictionary:
	var f := {"id": id, "part": p.id, "kind": kind, "pos": pos, "normal": normal.normalized(), "radius": radius,
		"half_extent": half_extent, "sharpness": snappedf(sharpness, 0.0001), "hardness": hardness, "area": area,
		"omni": omni, "channel": _channel(kind, sharpness > 0.0), "soft": false, "part_axis": p.axis_vec}
	f.merge(extra, true)
	return f

static func _features(obj: Dictionary, parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		var mat: Dictionary = obj.materials[p.material]
		var hardness: float = mat.hardness
		var r: Vector2 = p.radii
		var size: Vector3 = p.size
		if not p.rigid:
			# A compliant membrane carried by a rigid parent can still push (posture
			# only, no damage): the Lab rejects it as a damage contact, and so do we.
			if p.shape == "box" and not p.articulated and p.parent != "none" and _min_dim(size) <= PLATE_MAX_THICKNESS:
				var parent_rigid := false
				for q: Dictionary in parts:
					if q.id == p.parent:
						parent_rigid = q.rigid
				if parent_rigid:
					var n := _thin_axis_vec(size)
					var area := _area(size)
					for sgn: float in [-1.0, 1.0]:
						out.append(_feature(p.id + ("_face_pos" if sgn > 0.0 else "_face_neg"), p, "face", p.center, n * sgn,
							sqrt(area / PI) * 0.8, 0.0, hardness, area, Vector3.ZERO, false, {"soft": true}))
			continue
		match str(p.shape):
			"rod":
				var rr := maxf(r.x, r.y)
				for end: Array in [[p.a, (p.a as Vector3) - (p.b as Vector3), "_a"], [p.b, (p.b as Vector3) - (p.a as Vector3), "_b"]]:
					if not _occluded(end[0], p, parts):
						# APPROX: an elliptical end uses its larger radius.
						out.append(_feature(p.id + end[2], p, "end", end[0], end[1], rr + 0.015, 0.0, hardness, PI * rr * rr))
			"cone":
				var width := maxf(size[p.transverse_axes[0]], size[p.transverse_axes[1]])
				var length: float = size[p.axis]
				var tip: Vector3 = p.b
				if not _occluded(tip, p, parts):
					if width * 4.0 <= length:
						# APPROX sharpness: taper beyond the Lab's 4:1 threshold, scaled by hardness.
						var taper := clampf(0.3 + (length / width - 4.0) / 6.0, 0.3, 1.0)
						out.append(_feature(p.id + "_tip", p, "point", tip, p.axis_vec, 0.03, taper * (0.5 + 0.5 * hardness), hardness, 0.0005))
					else:
						out.append(_feature(p.id + "_tip", p, "end", tip, p.axis_vec, width * 0.5 + 0.015, 0.0, hardness, width * width))
			"box":
				var dims := [0, 1, 2]
				dims.sort_custom(func(x: int, y: int) -> bool: return size[x] > size[y])
				if size[dims[2]] <= PLATE_MAX_THICKNESS and size[dims[1]] >= 0.05:
					# Plate: two faces and its free edges.
					var n := Imp.axis_vector(dims[2])
					var area := _area(size)
					var fine := int(p.size_mm[dims[2]]) <= Imp.EDGE_MAX_THICKNESS_MM and int(p.edge_radius_um) <= Imp.EDGE_MAX_RADIUS_UM
					for sgn: float in [-1.0, 1.0]:
						out.append(_feature(p.id + ("_face_pos" if sgn > 0.0 else "_face_neg"), p, "face", p.center, n * sgn,
							minf(size[dims[0]], size[dims[1]]) * 0.45, 0.0, hardness, area))
					for e in range(2):
						var along: int = dims[e]
						var other: int = dims[1 - e]
						for sgn: float in [-1.0, 1.0]:
							var normal := Imp.axis_vector(along) * sgn
							var mid: Vector3 = (p.center as Vector3) + normal * size[along] * 0.5
							if _occluded(mid, p, parts):
								continue
							var half := Imp.axis_vector(other) * size[other] * 0.45
							var sharp := (0.55 + 0.45 * hardness) if fine else 0.0
							out.append(_feature("%s_edge_%s%s" % [p.id, "xyz"[along], "p" if sgn > 0.0 else "n"], p, "edge", mid, normal,
								size[dims[2]] * 0.5 + 0.015, sharp, hardness, 0.0, half))
				elif size[dims[1]] <= BAR_MAX_SECTION:
					# Bar: a box rod; its free ends strike.
					var axis := Imp.axis_vector(dims[0])
					for sgn: float in [-1.0, 1.0]:
						var end: Vector3 = (p.center as Vector3) + axis * sgn * size[dims[0]] * 0.5
						if not _occluded(end, p, parts):
							out.append(_feature("%s_end_%s" % [p.id, "p" if sgn > 0.0 else "n"], p, "end", end, axis * sgn,
								size[dims[1]] * 0.5 + 0.015, 0.0, hardness, size[dims[1]] * size[dims[2]]))
				else:
					out.append(_feature(p.id + "_mass", p, "mass", p.center, Imp.axis_vector(dims[0]), size[dims[0]] * 0.5, 0.0, hardness,
						size[dims[0]] * size[dims[1]], Vector3.ZERO, true))
			"ellipsoid":
				# APPROX: contact is a sphere of the largest semi-axis.
				var radius := maxf(size.x, maxf(size.y, size.z)) * 0.5
				out.append(_feature(p.id + "_mass", p, "mass", p.center, p.axis_vec, radius, 0.0, hardness, PI * radius * radius, Vector3.ZERO, true))
	return out

static func _min_dim(s: Vector3) -> float:
	return minf(s.x, minf(s.y, s.z))

static func _thin_axis_vec(s: Vector3) -> Vector3:
	var axis := 0
	for i in range(3):
		if s[i] < s[axis]:
			axis = i
	return Imp.axis_vector(axis)

static func _area(s: Vector3) -> float:
	var v := [s.x, s.y, s.z]
	v.sort()
	return float(v[1]) * float(v[2])

## Guard surfaces: broad boxes (Lab block area) that are rigid, or compliant but
## carried by a rigid parent (a canopy on ribs). Articulated parts never guard.
static func _covers(obj: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in obj.parts:
		if p.shape != "box" or p.articulated:
			continue
		var size: Vector3 = p.size
		var area := _area(size)
		if area < BLOCK_AREA or _min_dim(size) > PLATE_MAX_THICKNESS:
			continue
		var hardness: float = obj.materials[p.material].hardness
		var soft: bool = not p.rigid
		if soft:
			if p.parent == "none" or not by_id[p.parent].rigid:
				continue
			# APPROX: a canopy's load is carried by its rigid ribs at half their hardness.
			hardness = maxf(hardness, float(obj.materials[by_id[p.parent].material].hardness) * 0.5)
		out.append({"part": p.id, "kind": "canopy" if soft else "plate", "center": p.center, "normal": _thin_axis_vec(size),
			"radius": sqrt(area / PI), "area": area, "hardness": hardness, "deploy": false, "soft": soft})
	return out

static func _probes(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		var r: Vector2 = p.radii
		match str(p.shape):
			"rod", "cone":
				var n := maxi(2, int((p.a as Vector3).distance_to(p.b) / 0.05) + 1)
				for i in range(n):
					out.append([(p.a as Vector3).lerp(p.b, float(i) / (n - 1)), maxf(r.x, r.y)])
			"box":
				var s: Vector3 = p.size
				var dims := [0, 1, 2]
				dims.sort_custom(func(x: int, y: int) -> bool: return s[x] > s[y])
				var radius: float = s[dims[2]] * 0.5 + minf(s[dims[1]], 0.06) * 0.5
				for su: float in [-0.5, 0.0, 0.5]:
					for sv: float in ([-0.5, 0.0, 0.5] if s[dims[1]] > 0.05 else [0.0]):
						var off := Vector3.ZERO
						off[dims[0]] = su * s[dims[0]]
						off[dims[1]] = sv * s[dims[1]]
						out.append([(p.center as Vector3) + off, radius])
			"ellipsoid":
				out.append([p.center, minf((p.size as Vector3).x, minf((p.size as Vector3).y, (p.size as Vector3).z)) * 0.5])
	return out

## Unlocked hinges / flex parts for presentation-only secondary motion.
static func _articulated(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		if p.articulated:
			out.append({"part": p.id, "anchor": p.anchor, "axis": p.joint_axis, "limits": p.limits, "mass": p.mass, "center": p.center,
				"joint": p.joint})
	return out
