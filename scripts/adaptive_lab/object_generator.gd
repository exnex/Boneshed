extends RefCounted
## Constrained structural object generator for the isolated Adaptive Combat Lab.
##
## A recipe is a short list of part templates built from a small primitive vocabulary
## (rod, arc, branch, spike, plate, lump, membrane) with parameter ranges. A seed picks
## concrete values with one named RandomNumberGenerator stream, so recipe + seed always
## yields the same descriptor. The descriptor is the single source of truth: the mesher
## draws it, the analysis measures it and the affordance solver reads only the
## analysis. The display `label` travels with the descriptor for the HUD and is never
## read by analysis, solver, motion or rules (tests swap it to prove that).
##
## Object frame: metres, the first part starts at the origin; +Y is the recipe's main
## axis by convention only — nothing downstream assumes it.

const SCHEMA := "boneshed.adaptive_object.v0"
const DATA_PATH := "res://data/adaptive_lab/objects.json"
const SNAP := 0.0001

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		assert(parsed is Dictionary, "Adaptive lab object data failed to parse")
		_data = parsed
	return _data

static func materials() -> Dictionary:
	return data().materials

static func recipe(id: String) -> Dictionary:
	for r: Dictionary in data().recipes:
		if r.id == id:
			return r
	push_error("Unknown adaptive lab recipe: " + id)
	return {}

static func recipe_ids() -> Array[String]:
	var ids: Array[String] = []
	for r: Dictionary in data().recipes:
		ids.append(r.id)
	return ids

## recipe id + seed → descriptor. `label_override` exists for the label-swap test and
## the lab's relabel key; it changes nothing but the label string.
static func generate(recipe_id: String, seed: int, label_override := "") -> Dictionary:
	var r := recipe(recipe_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [recipe_id, seed])
	var parts: Array = []
	var by_id := {}
	for template: Dictionary in r.parts:
		for part: Dictionary in _realize(template, by_id, rng):
			by_id[part.id] = part
			parts.append(part)
	return {
		"schema": SCHEMA,
		"generator_version": int(data().generator_version),
		"recipe": recipe_id,
		"seed": seed,
		"label": label_override if label_override != "" else str(r.label),
		"parts": parts,
	}

## Structural fingerprint: everything except the label (so relabelling keeps it).
static func fingerprint(descriptor: Dictionary) -> String:
	var structural := descriptor.duplicate(true)
	structural.erase("label")
	return JSON.stringify(structural, "", true).sha256_text().substr(0, 16)

static func _range(rng: RandomNumberGenerator, value: Variant) -> float:
	if value is Array:
		return rng.randf_range(float(value[0]), float(value[1]))
	return float(value)

static func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func to_array(v: Vector3) -> Array:
	return [snappedf(v.x, SNAP), snappedf(v.y, SNAP), snappedf(v.z, SNAP)]

static func from_array(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## Anchor point and the parent's axis for "at": "origin" or [part_id, t].
static func _anchor(template: Dictionary, by_id: Dictionary) -> Array:
	var at: Variant = template.get("at", "origin")
	if at is String:
		return [Vector3.ZERO, Vector3.UP]
	var parent: Dictionary = by_id[at[0]]
	var a := from_array(parent.a)
	var b := from_array(parent.b)
	return [a.lerp(b, float(at[1])), (b - a).normalized()]

static func _bent(rng: RandomNumberGenerator, template: Dictionary, dir: Vector3) -> Vector3:
	if not template.has("bend"):
		return dir.normalized()
	var degrees := _range(rng, template.bend)
	var axis := _vec(template.bend_axis) if template.has("bend_axis") else _random_perpendicular(rng, dir)
	return dir.normalized().rotated(axis.normalized(), deg_to_rad(degrees))

static func _random_perpendicular(rng: RandomNumberGenerator, dir: Vector3) -> Vector3:
	var any := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	var p := any - dir.normalized() * any.dot(dir.normalized())
	return p.normalized() if p.length() > 0.01 else dir.normalized().cross(Vector3.RIGHT).normalized()

static func _rod(id: String, a: Vector3, b: Vector3, radius: float, material: String, extra := {}) -> Dictionary:
	var part := {"id": id, "kind": "rod", "a": to_array(a), "b": to_array(b), "radius": snappedf(radius, SNAP), "material": material}
	part.merge(extra)
	return part

static func _realize(t: Dictionary, by_id: Dictionary, rng: RandomNumberGenerator) -> Array:
	var anchor := _anchor(t, by_id)
	var origin: Vector3 = anchor[0]
	var material: String = t.material
	match str(t.kind):
		"rod":
			var dir := _bent(rng, t, _vec(t.dir))
			var length := _range(rng, t.length)
			var radius := _range(rng, t.radius)
			var a := origin - dir * length * 0.5 if t.get("centered", false) else origin
			return [_rod(t.id, a, a + dir * length, radius, material)]
		"spike":
			var dir := _bent(rng, t, _vec(t.dir))
			var length := _range(rng, t.length)
			return [{"id": t.id, "kind": "spike", "a": to_array(origin), "b": to_array(origin + dir * length),
				"radius": snappedf(_range(rng, t.radius), SNAP), "material": material}]
		"lump":
			var dir := _bent(rng, t, _vec(t.dir))
			var offset := _range(rng, t.get("offset", 0.0))
			var radii := Vector3(_range(rng, t.radii[0]), _range(rng, t.radii[1]), _range(rng, t.radii[2]))
			# The lump sits beyond its anchor along dir: its near surface touches the anchor.
			var centre := origin + dir * (offset + radii.y * 0.6)
			return [{"id": t.id, "kind": "lump", "center": to_array(centre), "axis": to_array(dir), "radii": to_array(radii), "material": material,
				"attach": to_array(origin)}]
		"plate":
			var u := _bent(rng, t, _vec(t.dir))
			var n := _vec(t.normal)
			n = (n - u * n.dot(u)).normalized()
			var v := n.cross(u).normalized()
			var length := _range(rng, t.length)
			var width := _range(rng, t.width)
			return [{"id": t.id, "kind": "plate", "center": to_array(origin + u * length * 0.5), "u": to_array(u), "v": to_array(v),
				"n": to_array(n), "length": snappedf(length, SNAP), "width": snappedf(width, SNAP), "thickness": snappedf(_range(rng, t.thickness), SNAP),
				"bevel_distal": snappedf(_range(rng, t.bevel_distal), SNAP), "bevel_lateral": snappedf(_range(rng, t.bevel_lateral), SNAP),
				"material": material, "attach": to_array(origin)}]
		"membrane":
			var parent: Dictionary = by_id[t.on]
			var pa := from_array(parent.a)
			var pb := from_array(parent.b)
			var span: Array = t.span
			return [{"id": t.id, "kind": "membrane", "a": to_array(pa.lerp(pb, float(span[0]))), "b": to_array(pa.lerp(pb, float(span[1]))),
				"folded_radius": snappedf(_range(rng, t.folded_radius), SNAP), "open_radius": snappedf(_range(rng, t.open_radius), SNAP),
				"ribs": int(_range(rng, t.ribs)), "rib_material": t.rib_material, "material": material}]
		"arc":
			# A straight grip plus a hook curling back from its start (a crook).
			var dir := _vec(t.dir).normalized()
			var straight := _range(rng, t.straight)
			var radius := _range(rng, t.radius)
			var bend_r := _range(rng, t.arc_radius)
			var sweep := deg_to_rad(_range(rng, t.arc_degrees))
			var side := dir.cross(Vector3.BACK).normalized()
			var parts: Array = [_rod(t.id + "_straight", origin, origin + dir * straight, radius, material)]
			var centre := origin + side * bend_r
			var steps := 5
			var previous := origin
			for i in range(1, steps + 1):
				var angle := sweep * float(i) / steps
				var p := centre - side.rotated(Vector3.BACK, angle) * bend_r
				parts.append(_rod("%s_arc_%d" % [t.id, i], previous, p, radius, material, {"hook": true}))
				previous = p
			return parts
		"branch":
			var count := int(round(_range(rng, t.segments)))
			var total := _range(rng, t.length)
			var r0 := _range(rng, t.radius_start)
			var r1 := _range(rng, t.radius_end)
			var dir := _vec(t.dir).normalized()
			var parts: Array = []
			var a := origin
			for i in range(count):
				if i > 0:
					dir = _bent(rng, t, dir)
				var seg_len := total / count * rng.randf_range(0.85, 1.15)
				var b := a + dir * seg_len
				var radius := lerpf(r0, r1, float(i) / maxf(1.0, count - 1.0))
				var id := "%s_%d" % [t.id, i]
				parts.append(_rod(id, a, b, radius, material))
				a = b
			# Alias the last segment so later templates can attach to it by role.
			var last: Dictionary = parts[-1].duplicate()
			last.id = t.id + "_end"
			parts[-1] = last
			return parts
	push_error("Unknown part kind: " + str(t.kind))
	return []
