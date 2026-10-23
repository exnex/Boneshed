extends RefCounted
## Versioned Research Lab → Boneshed import boundary (`lab.boneshed.object_export.v1`).
##
## Reads the vendored, byte-identical Lab export bundle (data/adaptive_lab/lab_export_v1)
## and the game-side pin (data/adaptive_lab/lab_import_pin.json). Nothing is
## re-authored here: every imported object is the Lab's own generated definition.
##
## Verification, in order (any failure rejects the record; nothing is partially used):
##   1. the manifest's raw SHA-256 equals the pinned value, and every bundle file's raw
##      SHA-256 equals its manifest entry;
##   2. strict decoding (exact integers, no duplicate keys, no floats);
##   3. closed field sets, types, ranges and enums of the export and descriptor;
##   4. the Lab's structural rules (unique ids, exact material references, one root,
##      existing parents, no cycles, anchors inside parts, attachment overlap,
##      cardinal joint axes, ordered limits, round-primitive axis, grip intervals);
##   5. the descriptor digest recomputed natively (Lab canonical JSON → SHA-256);
##   6. the derived physical block recomputed natively with the Lab's integer formula;
##   7. provenance equal to the pinned generator source cohort;
##   8. (id, digest) present among the records the Lab `check` accepted at the pinned
##      commit — the game cannot re-run the Lab generator, so recipe authenticity is
##      transported, not re-derived (documented in ADAPTIVE_COMBAT_LAB.md).
##
## Conversion: Lab object frame is right-handed +Y up, −Z forward, which is Godot's, so
## only units change (mm → m, µm → m, mdeg → rad, MPa/kPa → Pa, g → kg). Original
## lexical values (decimal seed, inertia strings, full ids, raw bytes' hash) are kept.
## The record's `name` is UI text only; nothing downstream reads it for behaviour.

const StrictJson = preload("res://scripts/adaptive_lab/strict_json.gd")
const PIN_PATH := "res://data/adaptive_lab/lab_import_pin.json"
const CONTRACT := "lab.boneshed.object_export.v1"
const OBJECT_SCHEMA := "lab.boneshed.object.v1"
const PRODUCER := "lab.boneshed.object_export.v1"
## Lab rigidity thresholds (objects.py `_rigid`): softer or more fragile parts cannot
## carry a rigid contact or a grasp.
const RIGID_STIFFNESS_MPA := 1000
const RIGID_TOUGHNESS_KPA := 5000
## Lab edge criterion (objects.py `edge_sweep`): a thin box with a fine edge radius.
const EDGE_MAX_THICKNESS_MM := 4
const EDGE_MAX_RADIUS_UM := 250

const ENVELOPE_KEYS := ["schema", "schema_version", "schema_uri", "descriptor", "descriptor_sha256", "physical", "provenance"]
const DESCRIPTOR_KEYS := ["id", "revision", "schema", "source_pack", "catalog_sha256", "recipe", "name", "description",
	"materials", "parts", "grips"]
const MATERIAL_KEYS := ["id", "revision", "density_kg_m3", "stiffness_mpa", "toughness_kpa", "color_rgb"]
const PART_KEYS := ["id", "parent", "joint", "locked", "material", "shape", "center_mm", "size_mm", "axis", "edge_radius_um",
	"joint_anchor_mm", "joint_axis", "limit_mdeg"]
const GRIP_KEYS := ["id", "part", "start_permille", "end_permille"]
const PHYSICAL_KEYS := ["mass_g", "center_of_mass_mm", "inertia_proxy_g_mm2", "parts"]
const INERTIA_KEYS := ["xx", "yy", "zz", "xy", "xz", "yz"]

static var _pin: Dictionary = {}
static var _bundle_cache: Dictionary = {}

static func pin() -> Dictionary:
	if _pin.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIN_PATH))
		assert(parsed is Dictionary, "Lab import pin failed to parse")
		_pin = parsed
	return _pin

static func bundle_path(rel: String) -> String:
	return str(pin().bundle_dir).path_join(rel)

static func sha256_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func sha256_text(text: String) -> String:
	return sha256_bytes(text.to_ascii_buffer())

# --- Bundle --------------------------------------------------------------------------

## Verifies the whole vendored bundle against the pin and imports every file listed in
## the manifest. Returns {ok, errors, manifest_sha256, objects: {path: imported},
## rejected: {path: [errors]}, expectations: {path: "accept"|"reject"}}. Cached.
static func load_bundle() -> Dictionary:
	if not _bundle_cache.is_empty():
		return _bundle_cache
	var p := pin()
	var out := {"ok": true, "errors": [], "manifest_sha256": "", "objects": {}, "rejected": {}, "expectations": {}, "order": []}
	var manifest_bytes := FileAccess.get_file_as_bytes(bundle_path("manifest.json"))
	out.manifest_sha256 = sha256_bytes(manifest_bytes)
	if manifest_bytes.is_empty() or out.manifest_sha256 != str(p.manifest_sha256):
		out.ok = false
		out.errors.append("manifest checksum differs from pin (%s)" % out.manifest_sha256)
		_bundle_cache = out
		return out
	var decoded := StrictJson.decode(manifest_bytes.get_string_from_utf8())
	var manifest: Variant = decoded.value
	if not decoded.ok or not manifest is Dictionary or manifest.get("schema") != p.manifest_schema or manifest.get("contract") != CONTRACT \
			or manifest.get("catalog_sha256") != p.catalog_sha256:
		out.ok = false
		out.errors.append("manifest header invalid")
		_bundle_cache = out
		return out
	for entry: Dictionary in manifest.get("support", []):
		if sha256_bytes(FileAccess.get_file_as_bytes(bundle_path(entry.path))) != entry.sha256:
			out.ok = false
			out.errors.append("support checksum mismatch: " + str(entry.path))
	for entry: Dictionary in manifest.get("files", []):
		var path: String = entry.path
		out.order.append(path)
		out.expectations[path] = entry.expect
		var result := import_file(path, str(entry.sha256))
		if result.ok:
			out.objects[path] = result.object
		else:
			out.rejected[path] = result.errors
	_bundle_cache = out
	return out

## Imported objects whose manifest entry the game accepted, in manifest order.
static func accepted_paths() -> Array[String]:
	var bundle := load_bundle()
	var out: Array[String] = []
	for path: String in bundle.order:
		if bundle.objects.has(path):
			out.append(path)
	return out

## Reads one bundle file and imports it, first checking its raw bytes against the
## manifest's checksum (pass "" to skip, e.g. for test-only mutated copies).
static func import_file(rel_path: String, expected_sha := "") -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(bundle_path(rel_path))
	var file_sha := sha256_bytes(bytes)
	if bytes.is_empty():
		return {"ok": false, "errors": ["unreadable file"], "object": {}}
	if expected_sha != "" and file_sha != expected_sha:
		return {"ok": false, "errors": ["file checksum mismatch"], "object": {}}
	return import_text(bytes.get_string_from_utf8(), {"path": rel_path, "file_sha256": file_sha})

## Imports export JSON text. source: {path, file_sha256} kept as provenance.
static func import_text(text: String, source: Dictionary = {}) -> Dictionary:
	var decoded := StrictJson.decode(text)
	if not decoded.ok:
		return {"ok": false, "errors": ["strict decode: " + str(decoded.error)], "object": {}}
	if decoded.has_float:
		return {"ok": false, "errors": ["non-integer number in export"], "object": {}}
	var errors := validate_export(decoded.value)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "object": {}}
	return {"ok": true, "errors": [], "object": convert_export(decoded.value, source)}

# --- Validation ----------------------------------------------------------------------

static func _closed(value: Variant, keys: Array, where: String, errors: Array) -> bool:
	if not value is Dictionary:
		errors.append("%s: expected object" % where)
		return false
	for k: String in value:
		if not k in keys:
			errors.append("%s: unknown field '%s'" % [where, k])
	for k: String in keys:
		if not (value as Dictionary).has(k):
			errors.append("%s: missing field '%s'" % [where, k])
	return errors.is_empty()

static func _int(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= low and int(value) <= high

static func _ivec(value: Variant, n: int, low: int, high: int) -> bool:
	if not value is Array or (value as Array).size() != n:
		return false
	for x: Variant in value:
		if not _int(x, low, high):
			return false
	return true

static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (value as String).length() >= 1 and (value as String).length() <= 256

static func _id(value: Variant) -> bool:
	if not _text(value):
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*(?:[.][a-z0-9_]+)*$")
	return re.search(value) != null

static func _sha(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var re := RegEx.new()
	re.compile("^[a-f0-9]{64}$")
	return re.search(value) != null

static func _bounds(part: Dictionary) -> Array:
	var lo := []
	var hi := []
	for i in range(3):
		lo.append(2 * int(part.center_mm[i]) - int(part.size_mm[i]))
		hi.append(2 * int(part.center_mm[i]) + int(part.size_mm[i]))
	return [lo, hi]

static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var ba := _bounds(a)
	var bb := _bounds(b)
	for i in range(3):
		if not (ba[0][i] <= bb[1][i] and bb[0][i] <= ba[1][i]):
			return false
	return true

static func _anchor_inside(anchor: Array, part: Dictionary) -> bool:
	var b := _bounds(part)
	for i in range(3):
		if not (b[0][i] <= 2 * int(anchor[i]) and 2 * int(anchor[i]) <= b[1][i]):
			return false
	return true

## Returns a list of error strings (empty = valid). Mirrors the Lab's closed schema and
## structural validator for the fields this contract defines.
static func validate_export(record: Variant) -> Array:
	var p := pin()
	var errors: Array = []
	if not _closed(record, ENVELOPE_KEYS, "export", errors):
		return errors
	if record.schema != CONTRACT:
		errors.append("unsupported contract '%s'" % str(record.schema))
	if not _int(record.schema_version, 1, 1):
		errors.append("unsupported schema_version %s" % str(record.schema_version))
	if record.schema_uri != p.schema_uri:
		errors.append("unsupported schema_uri")
	if not _sha(record.descriptor_sha256):
		errors.append("descriptor_sha256 malformed")
	var d: Variant = record.descriptor
	if not _closed(d, DESCRIPTOR_KEYS, "descriptor", errors):
		return errors
	if d.schema != OBJECT_SCHEMA:
		errors.append("descriptor schema '%s'" % str(d.schema))
	if not _id(d.id) or not str(d.id).begins_with("object."):
		errors.append("descriptor id malformed")
	if not _int(d.revision, 1, 1000000):
		errors.append("descriptor revision")
	if _closed(d.source_pack, ["id", "revision"], "source_pack", errors) and (not _id(d.source_pack.id) or not _int(d.source_pack.revision, 1, 1000000)):
		errors.append("source_pack ref")
	if d.catalog_sha256 != p.catalog_sha256:
		errors.append("catalog digest differs from pin")
	if not _text(d.name) or not _text(d.description):
		errors.append("name/description must be text")
	if _closed(d.recipe, ["generator", "seed", "assembly"], "recipe", errors):
		if d.recipe.generator != p.generator:
			errors.append("unsupported generator")
		var re := RegEx.new()
		re.compile("^(0|[1-9][0-9]{0,18})$")
		if typeof(d.recipe.seed) != TYPE_STRING or re.search(d.recipe.seed) == null:
			errors.append("seed must be a decimal string")
		elif str(d.recipe.seed).length() == 19 and str(d.recipe.seed) > "9223372036854775807":
			errors.append("seed outside signed 64-bit range")
		if not _int(d.recipe.assembly, 0, 6):
			errors.append("recipe assembly")
	if not errors.is_empty():
		return errors
	# Materials.
	var materials := {}
	if not d.materials is Array or (d.materials as Array).size() < 1 or (d.materials as Array).size() > 8:
		errors.append("materials count")
		return errors
	for m: Variant in d.materials:
		if not _closed(m, MATERIAL_KEYS, "material", errors):
			return errors
		if not _id(m.id) or not _int(m.revision, 1, 1000000) or not _int(m.density_kg_m3, 1, 25000) or not _int(m.stiffness_mpa, 0, 250000) \
				or not _int(m.toughness_kpa, 0, 1000000) or not _ivec(m.color_rgb, 3, 0, 255):
			errors.append("material %s fields" % str(m.get("id")))
		if materials.has(m.id):
			errors.append("duplicate material")
		materials[m.id] = m
	# Parts.
	if not d.parts is Array or (d.parts as Array).size() < 1 or (d.parts as Array).size() > 32:
		errors.append("parts count")
		return errors
	var parts := {}
	for part: Variant in d.parts:
		if not _closed(part, PART_KEYS, "part", errors):
			return errors
		if not _id(part.id) or not _id(part.parent) or not part.joint in ["fixed", "hinge", "flex"] or typeof(part.locked) != TYPE_BOOL \
				or not part.shape in ["box", "rod", "ellipsoid", "cone"] or not _ivec(part.center_mm, 3, -1000000, 1000000) \
				or not _ivec(part.size_mm, 3, 1, 10000) or not _int(part.axis, 0, 2) or not _int(part.edge_radius_um, 1, 100000) \
				or not _ivec(part.joint_anchor_mm, 3, -1000000, 1000000) or not _ivec(part.joint_axis, 3, -1, 1) \
				or not _ivec(part.limit_mdeg, 2, -180000, 180000):
			errors.append("part %s fields" % str(part.get("id")))
			return errors
		if not _closed(part.material, ["id", "revision"], "part.material", errors):
			return errors
		if parts.has(part.id):
			errors.append("duplicate part")
		parts[part.id] = part
	var roots := 0
	for part: Dictionary in parts.values():
		var m: Variant = materials.get(part.material.id)
		if m == null or int(m.revision) != int(part.material.revision):
			errors.append("missing material revision for part %s" % part.id)
		if not _anchor_inside(part.joint_anchor_mm, part):
			errors.append("joint anchor outside part %s" % part.id)
		var ax: Array = part.joint_axis
		if int(ax[0]) * int(ax[0]) + int(ax[1]) * int(ax[1]) + int(ax[2]) * int(ax[2]) != 1:
			errors.append("joint axis not cardinal (%s)" % part.id)
		if int(part.limit_mdeg[0]) > int(part.limit_mdeg[1]):
			errors.append("reversed joint limits (%s)" % part.id)
		var size: Array = part.size_mm
		if part.shape != "box" and int(size[part.axis]) != maxi(int(size[0]), maxi(int(size[1]), int(size[2]))):
			errors.append("round primitive axis must be longest (%s)" % part.id)
		if part.parent == "none":
			roots += 1
		else:
			if not parts.has(part.parent) or part.parent == part.id:
				errors.append("missing/self parent (%s)" % part.id)
				continue
			if not _overlap(part, parts[part.parent]):
				errors.append("disconnected attachment (%s)" % part.id)
			if not _anchor_inside(part.joint_anchor_mm, parts[part.parent]):
				errors.append("joint anchor outside parent (%s)" % part.id)
	if roots != 1:
		errors.append("need one connected root")
	if not errors.is_empty():
		return errors
	for part: Dictionary in parts.values():
		var seen := {}
		var cursor := part
		while cursor.parent != "none":
			if seen.has(cursor.id):
				errors.append("cyclic parts")
				return errors
			seen[cursor.id] = true
			cursor = parts[cursor.parent]
	# Grips.
	if not d.grips is Array or (d.grips as Array).size() > 8:
		errors.append("grips count")
		return errors
	var grip_ids := {}
	for g: Variant in d.grips:
		if not _closed(g, GRIP_KEYS, "grip", errors):
			return errors
		if not _id(g.id) or not _id(g.part) or not _int(g.start_permille, 0, 1000) or not _int(g.end_permille, 0, 1000):
			errors.append("grip fields")
			continue
		if grip_ids.has(g.id):
			errors.append("duplicate grip")
		grip_ids[g.id] = true
		if not parts.has(g.part):
			errors.append("grip missing part")
		elif not parts[g.part].shape in ["rod", "box"]:
			errors.append("grasp intervals require prismatic support")
		if int(g.start_permille) >= int(g.end_permille):
			errors.append("empty/reversed grasp interval (%s)" % g.id)
	if not errors.is_empty():
		return errors
	# Digest over the hydrated descriptor (decimal seed → integer).
	var hydrated: Dictionary = (d as Dictionary).duplicate(true)
	hydrated.recipe.seed = str(d.recipe.seed).to_int()
	if sha256_text(StrictJson.canonical(hydrated)) != record.descriptor_sha256:
		errors.append("descriptor digest mismatch")
	# Derived physical block.
	var physical: Variant = record.physical
	if _closed(physical, PHYSICAL_KEYS, "physical", errors):
		if StrictJson.canonical(physical) != StrictJson.canonical(physical_properties(d)):
			errors.append("derived physical metadata mismatch")
	# Provenance cohort.
	if _closed(record.provenance, ["repository", "generator_source_commit", "producer", "sources"], "provenance", errors):
		var prov: Dictionary = record.provenance
		if prov.repository != p.source_repository or prov.generator_source_commit != p.generator_source_commit or prov.producer != PRODUCER:
			errors.append("unsupported source provenance")
		elif StrictJson.canonical(prov.sources) != StrictJson.canonical(_pin_sources()):
			errors.append("unsupported source provenance (source cohort hash)")
	if not errors.is_empty():
		return errors
	# Lab-verified registry (recipe authenticity, which only the Lab generator can re-derive).
	var registered := false
	for entry: Dictionary in p.lab_verified_records:
		if entry.id == d.id and entry.descriptor_sha256 == record.descriptor_sha256:
			registered = true
	if not registered:
		errors.append("record not among Lab-verified generated records (recipe not re-derivable in game)")
	return errors

static func _pin_sources() -> Array:
	var out: Array = []
	for s: Dictionary in pin().accepted_source_cohort:
		out.append({"path": s.path, "sha256": s.sha256})
	return out

## Python-style floor division for ints (GDScript truncates toward zero).
static func floordiv(a: int, b: int) -> int:
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q

## The Lab's `objects.properties`, in exact integer arithmetic: solid-volume mass,
## centre of mass and envelope inertia proxy. Inertia values travel as decimal text.
static func physical_properties(d: Dictionary) -> Dictionary:
	var materials := {}
	for m: Dictionary in d.materials:
		materials[m.id] = m
	var factors := {"box": [1, 1], "rod": [3141593, 4000000], "ellipsoid": [3141593, 6000000], "cone": [3141593, 12000000]}
	var rows: Array = []
	var sizes := {}
	for part: Dictionary in d.parts:
		var s: Array = part.size_mm
		sizes[part.id] = s
		var volume: int = int(s[0]) * int(s[1]) * int(s[2])
		var f: Array = factors[part.shape]
		volume = floordiv(volume * int(f[0]), int(f[1]))
		var mass := maxi(1, floordiv(volume * int(materials[part.material.id].density_kg_m3), 1000000))
		var center := [int(part.center_mm[0]), int(part.center_mm[1]), int(part.center_mm[2])]
		if part.shape == "cone":
			center[part.axis] -= floordiv(int(s[part.axis]), 4)
		rows.append({"id": part.id, "mass_g": mass, "volume_mm3": volume, "center_mm": center})
	var total := 0
	for r: Dictionary in rows:
		total += int(r.mass_g)
	var com := []
	for i in range(3):
		var acc := 0
		for r: Dictionary in rows:
			acc += int(r.mass_g) * int(r.center_mm[i])
		com.append(floordiv(acc, total))
	var tensor := {"xx": 0, "yy": 0, "zz": 0, "xy": 0, "xz": 0, "yz": 0}
	for r: Dictionary in rows:
		var size: Array = sizes[r.id]
		var m: int = r.mass_g
		var off := [int(r.center_mm[0]) - int(com[0]), int(r.center_mm[1]) - int(com[1]), int(r.center_mm[2]) - int(com[2])]
		var diag := ["xx", "yy", "zz"]
		for i in range(3):
			var j := (i + 1) % 3
			var k := (i + 2) % 3
			tensor[diag[i]] += floordiv(m * (int(size[j]) * int(size[j]) + int(size[k]) * int(size[k])), 12) + m * (off[j] * off[j] + off[k] * off[k])
		for entry: Array in [["xy", 0, 1], ["xz", 0, 2], ["yz", 1, 2]]:
			tensor[entry[0]] -= m * off[entry[1]] * off[entry[2]]
	var text := {}
	for k: String in tensor:
		text[k] = str(tensor[k])
	return {"mass_g": total, "center_of_mass_mm": com, "inertia_proxy_g_mm2": text, "parts": rows}

# --- Conversion ----------------------------------------------------------------------

static func mm(a: Array) -> Vector3:
	return Vector3(int(a[0]), int(a[1]), int(a[2])) * 0.001

static func axis_vector(axis: int) -> Vector3:
	var v := Vector3.ZERO
	v[axis] = 1.0
	return v

## Whether a part and every ancestor can carry rigid load (Lab `_rigid`).
static func rigid_chain(part_id: String, parts: Dictionary, materials: Dictionary) -> bool:
	var cursor: Dictionary = parts[part_id]
	while true:
		var m: Dictionary = materials[cursor.material.id]
		if int(m.stiffness_mpa) < RIGID_STIFFNESS_MPA or int(m.toughness_kpa) < RIGID_TOUGHNESS_KPA or cursor.joint == "flex" \
				or (cursor.joint == "hinge" and not cursor.locked):
			return false
		if cursor.parent == "none":
			return true
		cursor = parts[cursor.parent]
	return false

## Game-side, explicitly approximate hardness in 0..1 from stiffness (log scale; the
## Lab defines no hardness). Used only for damage scaling and guard absorption.
static func game_hardness(stiffness_mpa: int) -> float:
	return clampf(log(maxf(float(stiffness_mpa), 1.0)) / log(200000.0), 0.0, 1.0)

## Validated export → imported object (game representation, original preserved).
static func convert_export(record: Dictionary, source: Dictionary) -> Dictionary:
	var d: Dictionary = record.descriptor
	var raw_materials := {}
	var materials := {}
	for m: Dictionary in d.materials:
		raw_materials[m.id] = m
		materials[m.id] = {"id": m.id, "revision": int(m.revision), "density_kg_m3": int(m.density_kg_m3),
			"stiffness_pa": int(m.stiffness_mpa) * 1000000.0, "toughness_pa": int(m.toughness_kpa) * 1000.0,
			"stiffness_mpa": int(m.stiffness_mpa), "toughness_kpa": int(m.toughness_kpa),
			"color": Color(int(m.color_rgb[0]) / 255.0, int(m.color_rgb[1]) / 255.0, int(m.color_rgb[2]) / 255.0),
			"rigid_material": int(m.stiffness_mpa) >= RIGID_STIFFNESS_MPA and int(m.toughness_kpa) >= RIGID_TOUGHNESS_KPA,
			"hardness": game_hardness(int(m.stiffness_mpa))}
	var raw_parts := {}
	for part: Dictionary in d.parts:
		raw_parts[part.id] = part
	var phys_rows := {}
	for r: Dictionary in record.physical.parts:
		phys_rows[r.id] = r
	var parts: Array = []
	var support: Array = []
	for part: Dictionary in d.parts:
		var axis: int = part.axis
		var size := mm(part.size_mm)
		var center := mm(part.center_mm)
		var av := axis_vector(axis)
		var t := [(axis + 1) % 3, (axis + 2) % 3]
		var rigid := rigid_chain(part.id, raw_parts, raw_materials)
		var converted := {
			"id": part.id, "shape": part.shape, "center": center, "size": size, "axis": axis, "axis_vec": av,
			"a": center - av * size[axis] * 0.5, "b": center + av * size[axis] * 0.5,
			"transverse_axes": t, "radii": Vector2(size[t[0]] * 0.5, size[t[1]] * 0.5),
			"material": part.material.id, "parent": part.parent, "joint": part.joint, "locked": part.locked,
			"anchor": mm(part.joint_anchor_mm), "joint_axis": Vector3(int(part.joint_axis[0]), int(part.joint_axis[1]), int(part.joint_axis[2])),
			"limits": Vector2(int(part.limit_mdeg[0]), int(part.limit_mdeg[1])) * PI / 180000.0,
			"edge_radius": int(part.edge_radius_um) * 1e-6, "edge_radius_um": int(part.edge_radius_um),
			"size_mm": part.size_mm.duplicate(), "rigid": rigid,
			"mass": int(phys_rows[part.id].mass_g) * 0.001, "mass_center": mm(phys_rows[part.id].center_mm),
			"articulated": part.joint == "flex" or (part.joint == "hinge" and not part.locked),
		}
		parts.append(converted)
		support.append_array(_support_notes(converted, materials))
	var grips: Array = []
	for g: Dictionary in d.grips:
		var part: Dictionary = raw_parts[g.part]
		var axis: int = part.axis
		var c := mm(part.center_mm)
		var length := int(part.size_mm[axis]) * 0.001
		var av := axis_vector(axis)
		grips.append({"id": g.id, "part": g.part, "start_permille": int(g.start_permille), "end_permille": int(g.end_permille),
			"a": c + av * length * (int(g.start_permille) / 1000.0 - 0.5), "b": c + av * length * (int(g.end_permille) / 1000.0 - 0.5)})
	if grips.is_empty():
		support.append({"feature": "grips", "status": "supported", "detail": "no declared grip interval: imported and drawn, never held"})
	var inertia_text: Dictionary = record.physical.inertia_proxy_g_mm2
	var inertia := {}
	for k: String in INERTIA_KEYS:
		inertia[k] = str(inertia_text[k]).to_int() * 1e-9
	return {
		"schema": CONTRACT,
		"schema_version": 1,
		"source": source.merged({"manifest_sha256": pin().manifest_sha256, "lab_commit": pin().source_merge_commit,
			"descriptor_sha256": record.descriptor_sha256}),
		"original": record.duplicate(true),
		"id": d.id,
		"revision": int(d.revision),
		"seed_text": str(d.recipe.seed),
		"seed": str(d.recipe.seed).to_int(),
		"assembly": int(d.recipe.assembly),
		"generator": d.recipe.generator,
		"source_pack": d.source_pack.duplicate(),
		"catalog_sha256": d.catalog_sha256,
		"label": d.name,
		"description": d.description,
		"materials": materials,
		"parts": parts,
		"grips": grips,
		"physical": {"mass": int(record.physical.mass_g) * 0.001, "com": mm(record.physical.center_of_mass_mm),
			"inertia_proxy": inertia, "inertia_proxy_text": inertia_text.duplicate()},
		"provenance": record.provenance.duplicate(true),
		"support": support,
	}

static func _support_notes(part: Dictionary, materials: Dictionary) -> Array:
	var out: Array = []
	var id: String = part.id
	match str(part.shape):
		"box":
			out.append({"feature": id + ":box", "status": "supported", "detail": "exact box mesh and box contact extents"})
		"rod":
			var r: Vector2 = part.radii
			if is_equal_approx(r.x, r.y):
				out.append({"feature": id + ":rod", "status": "supported", "detail": "circular cylinder, exact"})
			else:
				out.append({"feature": id + ":rod", "status": "approximated", "detail": "elliptical cylinder drawn exactly; contact capsule uses the larger transverse radius"})
		"cone":
			out.append({"feature": id + ":cone", "status": "supported", "detail": "elliptical cone drawn exactly (base at −axis); contact uses the tip and a tapered capsule"})
		"ellipsoid":
			out.append({"feature": id + ":ellipsoid", "status": "approximated", "detail": "ellipsoid drawn exactly; contact is a sphere of the largest semi-axis"})
	var mat: Dictionary = materials[part.material]
	if not mat.rigid_material:
		out.append({"feature": id + ":compliant_material", "status": "approximated", "detail": "compliant/fragile material (Lab rigidity rule): mass, cover and drawing only; no damage contact, no grasp"})
	if part.articulated:
		out.append({"feature": id + ":" + str(part.joint), "status": "approximated", "detail": "unlocked joint: presentation-only swing within limits; excluded from rigid contact, cover and grasp"})
	elif part.joint == "hinge":
		out.append({"feature": id + ":hinge_locked", "status": "supported", "detail": "locked hinge treated as fixed in the realized pose"})
	return out
