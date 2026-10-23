extends RefCounted
## Measures a structural object descriptor (object_generator.gd). Pure maths on the
## descriptor's parts; it never sees the label. Output:
##   mass, com, extent        physical totals (kg, m)
##   samples                  point masses for inertia about any pivot
##   grips                    hand-centre candidates on graspable rods with clearance
##   features                 contact features: point / edge / face / end / mass, each
##                            with a local position, outward normal, contact radius,
##                            sharpness, hardness and damage channel
##   covers                   surfaces that can shield the wielder
## All positions are in the object frame, so whoever places the object (motion, mesh,
## contact) transforms the same numbers.

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")

## A rod can be grasped when its radius fits a closed human-scale hand (provisional).
const GRASP_RADIUS_MIN := 0.012
const GRASP_RADIUS_MAX := 0.026
## Half the width of a hand along the handle and the clearance it needs around it.
const HAND_HALF_WIDTH := 0.04
const HAND_CLEARANCE := 0.045
const GRIP_STEP := 0.02
## A cutting edge or point needs at least this sharpness; below it the feature is blunt.
const SHARP_MIN := 0.25

static func v(a: Array) -> Vector3:
	return Gen.from_array(a)

static func analyse(descriptor: Dictionary) -> Dictionary:
	var mats: Dictionary = Gen.materials()
	var parts: Array = descriptor.parts
	var samples: Array = []
	for part: Dictionary in parts:
		samples.append_array(_mass_samples(part, mats))
	var mass := 0.0
	var com := Vector3.ZERO
	for s: Array in samples:
		mass += float(s[1])
		com += (s[0] as Vector3) * float(s[1])
	com /= maxf(mass, 0.0001)
	var points := surface_points(parts)
	var result := {
		"mass": mass,
		"com": com,
		"samples": samples,
		"points": points,
		"extent": _extent(points),
		"grips": _grips(parts),
		"features": _features(parts, mats),
		"covers": _covers(parts, mats),
		"probes": probes(parts),
		"articulated": [],
		"source": "v0",
	}
	result.intervals = intervals(result.grips)
	return result

## Contiguous grip candidates on one rod → one interval of hand-centre positions, the
## same shape lab_analysis.gd produces from the Lab's declared grip intervals.
static func intervals(grips: Array) -> Array:
	var out: Array = []
	var current: Dictionary = {}
	for g: Dictionary in grips:
		if not current.is_empty() and current.part == g.part and float(g.s) - float(current.last_s) <= GRIP_STEP * 1.05:
			current.hi = g.point
			current.last_s = g.s
			continue
		if not current.is_empty():
			out.append(_close_interval(current))
		current = {"part": g.part, "lo": g.point, "hi": g.point, "last_s": g.s, "axis": g.axis, "radius": g.radius}
	if not current.is_empty():
		out.append(_close_interval(current))
	return out

static func _close_interval(c: Dictionary) -> Dictionary:
	var axis: Vector3 = c.axis
	return {"id": "%s@%.2f" % [c.part, float(c.last_s)], "part": c.part, "a": (c.lo as Vector3) - axis * HAND_HALF_WIDTH,
		"b": (c.hi as Vector3) + axis * HAND_HALF_WIDTH, "axis": axis, "radius": c.radius, "lo": c.lo, "hi": c.hi, "usable": true, "reasons": []}

static func inertia_about(analysis: Dictionary, pivot: Vector3) -> float:
	var total := 0.0
	for s: Array in analysis.samples:
		total += float(s[1]) * (s[0] as Vector3).distance_squared_to(pivot)
	return total

## Furthest projection of the object's surface along `dir` from `origin`.
static func reach_along(analysis: Dictionary, origin: Vector3, dir: Vector3) -> float:
	var best := -INF
	for p: Vector3 in analysis.points:
		best = maxf(best, (p - origin).dot(dir))
	return best

static func _extent(points: Array) -> float:
	var best := 0.0
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			best = maxf(best, (points[i] as Vector3).distance_to(points[j]))
	return best

## Coarse surface point cloud (for extents and "is anything beyond this feature").
static func surface_points(parts: Array) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		match str(part.kind):
			"rod", "spike", "membrane":
				var a := v(part.a)
				var b := v(part.b)
				for i in range(5):
					out.append(a.lerp(b, i / 4.0))
			"plate":
				var c := v(part.center)
				var u := v(part.u) * float(part.length) * 0.5
				var w := v(part.v) * float(part.width) * 0.5
				for su: float in [-1.0, 0.0, 1.0]:
					for sw: float in [-1.0, 0.0, 1.0]:
						out.append(c + u * su + w * sw)
			"lump":
				var c := v(part.center)
				var r := v(part.radii)
				var basis := _lump_basis(part)
				out.append(c)
				for axis in range(3):
					for sgn: float in [-1.0, 1.0]:
						var local := Vector3.ZERO
						local[axis] = r[axis] * sgn
						out.append(c + basis * local)
	return out

static func _lump_basis(part: Dictionary) -> Basis:
	var y := v(part.axis).normalized()
	var hint := Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(hint).normalized()
	return Basis(x, y, x.cross(y).normalized())

static func _density(mats: Dictionary, id: String) -> float:
	return float(mats[id].density)

static func _mass_samples(part: Dictionary, mats: Dictionary) -> Array:
	var out: Array = []
	match str(part.kind):
		"rod":
			var a := v(part.a)
			var b := v(part.b)
			var r: float = part.radius
			var m := PI * r * r * a.distance_to(b) * _density(mats, part.material)
			for i in range(8):
				out.append([a.lerp(b, (i + 0.5) / 8.0), m / 8.0])
		"spike":
			var a := v(part.a)
			var b := v(part.b)
			var r: float = part.radius
			var m := PI * r * r * a.distance_to(b) / 3.0 * _density(mats, part.material)
			# A cone's mass sits towards its base.
			for t: float in [0.1, 0.3, 0.55]:
				out.append([a.lerp(b, t), m / 3.0])
		"plate":
			var c := v(part.center)
			var m := float(part.length) * float(part.width) * float(part.thickness) * _density(mats, part.material)
			for su: float in [-0.33, 0.0, 0.33]:
				for sw: float in [-0.33, 0.0, 0.33]:
					out.append([c + v(part.u) * su * float(part.length) + v(part.v) * sw * float(part.width), m / 9.0])
		"lump":
			var r := v(part.radii)
			var m := 4.0 / 3.0 * PI * r.x * r.y * r.z * _density(mats, part.material)
			var basis := _lump_basis(part)
			out.append([v(part.center), m * 0.4])
			for axis in range(3):
				for sgn: float in [-1.0, 1.0]:
					var local := Vector3.ZERO
					local[axis] = r[axis] * sgn * 0.7
					out.append([v(part.center) + basis * local, m * 0.1])
		"membrane":
			var a := v(part.a)
			var b := v(part.b)
			var length := a.distance_to(b)
			var cloth := TAU * float(part.folded_radius) * length * _density(mats, part.material)
			var ribs := int(part.ribs) * PI * 0.0015 * 0.0015 * float(part.open_radius) * 1.1 * _density(mats, part.rib_material)
			for i in range(4):
				out.append([a.lerp(b, (i + 0.5) / 4.0), (cloth + ribs) / 4.0])
	return out

## Distance from a point to a part's surface (negative inside), approximate for
## plates and lumps; used for hand clearance and free-end detection.
static func distance_to_part(p: Vector3, part: Dictionary) -> float:
	match str(part.kind):
		"rod", "spike":
			return segment_distance(p, v(part.a), v(part.b)) - float(part.radius)
		"membrane":
			return segment_distance(p, v(part.a), v(part.b)) - float(part.folded_radius)
		"plate":
			var local := p - v(part.center)
			var du := maxf(0.0, absf(local.dot(v(part.u))) - float(part.length) * 0.5)
			var dv := maxf(0.0, absf(local.dot(v(part.v))) - float(part.width) * 0.5)
			var dn := maxf(0.0, absf(local.dot(v(part.n))) - float(part.thickness) * 0.5)
			return Vector3(du, dv, dn).length()
		"lump":
			var r := v(part.radii)
			return p.distance_to(v(part.center)) - maxf(r.x, maxf(r.y, r.z))
	return INF

static func segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func graspable(part: Dictionary) -> bool:
	return part.kind == "rod" and float(part.radius) >= GRASP_RADIUS_MIN and float(part.radius) <= GRASP_RADIUS_MAX

## Hand-centre candidates: points on graspable rods where a hand's width fits on the
## same rod and nothing non-graspable is within the hand's clearance.
static func _grips(parts: Array) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		if not graspable(part):
			continue
		var a := v(part.a)
		var b := v(part.b)
		var length := a.distance_to(b)
		var axis := (b - a).normalized()
		var s := HAND_HALF_WIDTH
		while s <= length - HAND_HALF_WIDTH + 0.0001:
			var point := a + axis * s
			var clear := true
			for other: Dictionary in parts:
				if other.id == part.id or graspable(other):
					continue
				for probe: float in [-HAND_HALF_WIDTH, 0.0, HAND_HALF_WIDTH]:
					if distance_to_part(point + axis * probe, other) < HAND_CLEARANCE:
						clear = false
			if clear:
				out.append({"part": part.id, "s": snappedf(s, 0.0001), "point": point, "axis": axis, "radius": float(part.radius)})
			s += GRIP_STEP
	return out

static func _free_end(p: Vector3, own: Dictionary, parts: Array) -> bool:
	for other: Dictionary in parts:
		if other.id != own.id and distance_to_part(p, other) < 0.02:
			return false
	return true

static func _channel(kind: String, sharpness: float) -> String:
	if sharpness < SHARP_MIN:
		return "blunt"
	return "pierce" if kind == "point" else ("cut" if kind == "edge" else "blunt")

static func _feature(id: String, part: Dictionary, kind: String, pos: Vector3, normal: Vector3, radius: float, sharpness: float,
		hardness: float, area: float, half_extent := Vector3.ZERO, omni := false) -> Dictionary:
	return {"id": id, "part": part.id, "kind": kind, "pos": pos, "normal": normal.normalized(), "radius": radius,
		"half_extent": half_extent, "sharpness": snappedf(sharpness, 0.0001), "hardness": hardness, "area": area,
		"omni": omni, "channel": _channel(kind, sharpness), "soft": false, "part_axis": _part_axis(part)}

static func _part_axis(part: Dictionary) -> Vector3:
	match str(part.kind):
		"rod", "spike", "membrane":
			return (v(part.b) - v(part.a)).normalized()
		"plate":
			return v(part.u)
		"lump":
			return v(part.axis).normalized()
	return Vector3.UP

static func _features(parts: Array, mats: Dictionary) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		var hardness: float = mats[part.material].hardness
		match str(part.kind):
			"rod":
				var a := v(part.a)
				var b := v(part.b)
				var r: float = part.radius
				for end: Array in [[a, a - b, "_a"], [b, b - a, "_b"]]:
					if _free_end(end[0], part, parts):
						out.append(_feature(part.id + end[2], part, "end", end[0], end[1], r + 0.015, 0.0, hardness, PI * r * r))
			"spike":
				var a := v(part.a)
				var b := v(part.b)
				# Sharpness grows with taper (length/base radius), capped by what the material holds.
				var taper := clampf(a.distance_to(b) / (float(part.radius) * 7.0), 0.0, 1.0)
				out.append(_feature(part.id + "_tip", part, "point", b, b - a, 0.03, hardness * taper, hardness, 0.0005))
			"plate":
				var c := v(part.center)
				var u := v(part.u)
				var w := v(part.v)
				var n := v(part.n)
				var half_l := float(part.length) * 0.5
				var half_w := float(part.width) * 0.5
				var edge_r := float(part.thickness) * 0.5 + 0.015
				out.append(_feature(part.id + "_edge_distal", part, "edge", c + u * half_l, u, edge_r,
					float(part.bevel_distal) * hardness, hardness, 0.0, w * half_w))
				for side: float in [-1.0, 1.0]:
					out.append(_feature(part.id + ("_edge_left" if side < 0.0 else "_edge_right"), part, "edge", c + w * half_w * side, w * side,
						edge_r, float(part.bevel_lateral) * hardness, hardness, 0.0, u * half_l * 0.8))
					out.append(_feature(part.id + ("_face_back" if side < 0.0 else "_face_front"), part, "face", c, n * side,
						minf(half_l, half_w) * 0.9, 0.0, hardness, float(part.length) * float(part.width)))
			"lump":
				var r := v(part.radii)
				var radius := maxf(r.x, maxf(r.y, r.z))
				out.append(_feature(part.id + "_mass", part, "mass", v(part.center), v(part.axis), radius, 0.0, hardness,
					PI * radius * radius, Vector3.ZERO, true))
			"membrane":
				var a := v(part.a)
				var b := v(part.b)
				# Folded canopy: a soft bundle; striking with it is possible but weak.
				out.append(_feature(part.id + "_bundle", part, "mass", a.lerp(b, 0.6), b - a, float(part.folded_radius) + 0.01, 0.0,
					hardness, 0.0, Vector3.ZERO, true))
	return out

## Shielding surfaces. A membrane deploys around its axis; plates and lumps shield by
## their presented area. `deploy` marks a cover that changes shape when raised.
static func _covers(parts: Array, mats: Dictionary) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		var hardness: float = mats[part.material].hardness
		match str(part.kind):
			"membrane":
				var a := v(part.a)
				var b := v(part.b)
				var r: float = part.open_radius
				# Opened, the ribs carry the load: half their material's hardness.
				var ribs: float = mats[part.rib_material].hardness
				out.append({"part": part.id, "kind": "membrane", "center": a.lerp(b, 0.8), "normal": (b - a).normalized(), "radius": r,
					"area": PI * r * r, "hardness": maxf(hardness, ribs * 0.5), "deploy": true})
			"plate":
				var area := float(part.length) * float(part.width)
				out.append({"part": part.id, "kind": "plate", "center": v(part.center), "normal": v(part.n), "radius": sqrt(area / PI),
					"area": area, "hardness": hardness, "deploy": false})
			"lump":
				var r := v(part.radii)
				var radius := (r.x + r.z) * 0.5
				out.append({"part": part.id, "kind": "lump", "center": v(part.center), "normal": v(part.axis), "radius": radius,
					"area": PI * radius * radius, "hardness": hardness, "deploy": false})
	return out

## Probe points (object frame) with radii, for body-intrusion checks in motion.
static func probes(parts: Array) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		var radius := _part_probe_radius(part)
		for p: Vector3 in _part_probe_points(part):
			out.append([p, radius])
	return out

static func _part_probe_points(part: Dictionary) -> Array:
	var out: Array = []
	match str(part.kind):
		"rod", "spike", "membrane":
			var a := v(part.a)
			var b := v(part.b)
			var n := maxi(2, int(a.distance_to(b) / 0.05) + 1)
			for i in range(n):
				out.append(a.lerp(b, float(i) / (n - 1)))
		"plate", "lump":
			out.append(v(part.center))
	return out

static func _part_probe_radius(part: Dictionary) -> float:
	match str(part.kind):
		"rod", "spike":
			return float(part.radius)
		"membrane":
			return float(part.folded_radius)
		"plate":
			return minf(float(part.length), float(part.width)) * 0.4
		"lump":
			var r := v(part.radii)
			return minf(r.x, minf(r.y, r.z))
	return 0.0
