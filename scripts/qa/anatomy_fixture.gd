extends RefCounted
## The isolated anatomy demonstration as one deterministic function: four example
## bodies, transformations between them, and rejected configurations. Used by
## anatomy_demo.gd (writes the committed example) and by anatomy_tests.gd.
## No scene, combat state, AI or courtyard code is touched.

const AnatomyCatalog := preload("res://scripts/anatomy/anatomy_catalog.gd")
const AnatomyRules := preload("res://scripts/anatomy/anatomy_rules.gd")
const BuildProjection := preload("res://scripts/anatomy/build_projection.gd")

const EXAMPLES_PATH := "res://data/anatomy/example_bodies.json"
const BUILD_ABILITIES := ["attack.slash", "attack.heavy_slash", "ability.marrow_lunge"]

## `from` names an example body or an earlier transformation; `expect` an example body
## whose nodes and equipment the result must match exactly.
const TRANSFORMATIONS := [
	{"id": "t.corrupt_right_arm", "from": "body.humanoid_fighter", "expect": "body.marrow_replacement", "ops": [
		{"op": "replace", "node": "arm_r", "part": "part.marrow_arm"},
		{"op": "mount", "item": "equip.notched_sword", "mounts": ["arm_l/grip"]}]},
	{"id": "t.revert_marrow_arm", "from": "body.marrow_replacement", "expect": "body.humanoid_fighter", "ops": [
		{"op": "replace", "node": "arm_r", "part": "part.human_arm"},
		{"op": "unmount", "mount": "arm_l/grip"},
		{"op": "mount", "item": "equip.notched_sword", "mounts": ["arm_r/grip"]}]},
	{"id": "t.take_two_handed_grip", "from": "body.humanoid_fighter", "expect": "", "ops": [
		{"op": "unmount", "mount": "arm_r/grip"},
		{"op": "mount", "item": "equip.fixture_greatsword", "mounts": ["arm_l/grip", "arm_r/grip"]}]},
	{"id": "t.corrupt_two_handed_holder", "from": "t.take_two_handed_grip", "expect": "", "ops": [
		{"op": "replace", "node": "arm_r", "part": "part.marrow_arm"}]},
	{"id": "t.grow_second_arm_pair", "from": "body.humanoid_fighter", "expect": "body.four_armed", "ops": [
		{"op": "replace", "node": "torso", "part": "part.spined_torso"},
		{"op": "attach", "node": "arm_lower_l", "part": "part.auxiliary_arm", "parent": "torso", "socket": "lower_shoulder_l"},
		{"op": "attach", "node": "arm_lower_r", "part": "part.auxiliary_arm", "parent": "torso", "socket": "lower_shoulder_r"},
		{"op": "mount", "item": "equip.fixture_buckler", "mounts": ["arm_lower_l/light_grip"]}]},
	{"id": "t.become_carapace_brute", "from": "body.four_armed", "expect": "body.carapace_brute", "ops": [
		{"op": "replace", "node": "torso", "part": "part.lopsided_torso"},
		{"op": "set_proportion", "node": "torso", "key": "height", "value": 1.15},
		{"op": "attach", "node": "arm_great", "part": "part.carapace_arm", "parent": "torso", "socket": "great_shoulder_r"},
		{"op": "set_proportion", "node": "arm_great", "key": "length", "value": 1.3},
		{"op": "attach", "node": "tail", "part": "part.counterweight_tail", "parent": "torso", "socket": "tail"},
		{"op": "replace", "node": "legs", "part": "part.digitigrade_legs"},
		{"op": "mount", "item": "equip.notched_sword", "mounts": ["arm_l/grip"]}]},
]

## Each must be rejected atomically with at least the listed error codes.
const REJECTED := [
	{"id": "r.second_locomotion_on_tail", "from": "body.carapace_brute", "codes": ["incompatible_socket", "locomotion_count"], "ops": [
		{"op": "attach", "node": "legs_extra", "part": "part.biped_legs", "parent": "torso", "socket": "tail"}]},
	{"id": "r.auxiliary_arm_on_standard_frame", "from": "body.humanoid_fighter", "codes": ["missing_required_tag"], "ops": [
		{"op": "detach", "node": "arm_l"},
		{"op": "attach", "node": "arm_aux", "part": "part.auxiliary_arm", "parent": "torso", "socket": "shoulder_l"}]},
	{"id": "r.sword_in_handless_marrow_arm", "from": "body.marrow_replacement", "codes": ["unknown_mount"], "ops": [
		{"op": "unmount", "mount": "arm_l/grip"},
		{"op": "mount", "item": "equip.notched_sword", "mounts": ["arm_r/grip"]}]},
	{"id": "r.two_handed_across_unpaired_arms", "from": "body.four_armed", "codes": ["unpaired_mounts", "wrong_mount_type"], "ops": [
		{"op": "unmount", "mount": "arm_r/grip"},
		{"op": "mount", "item": "equip.fixture_greatsword", "mounts": ["arm_lower_r/light_grip", "arm_r/grip"]}]},
	{"id": "r.mount_already_in_use", "from": "body.four_armed", "codes": ["mount_in_use"], "ops": [
		{"op": "mount", "item": "equip.fixture_buckler", "mounts": ["arm_r/grip"]}]},
	{"id": "r.remove_only_legs", "from": "body.humanoid_fighter", "codes": ["locomotion_count"], "ops": [
		{"op": "detach", "node": "legs"}]},
	{"id": "r.arm_beyond_proportion_range", "from": "body.humanoid_fighter", "codes": ["proportion_out_of_range"], "ops": [
		{"op": "set_proportion", "node": "arm_r", "key": "length", "value": 3.0}]},
	{"id": "r.detach_core", "from": "body.humanoid_fighter", "codes": ["cannot_detach_root"], "ops": [
		{"op": "detach", "node": "torso"}]},
]

static func load_examples() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES_PATH))
	return data.bodies if data is Dictionary and data.get("bodies") is Array else []

## Same anatomy and equipment, ignoring body id.
static func same_form(rules, a: Dictionary, b: Dictionary) -> bool:
	var na: Dictionary = rules.normalize(a)
	var nb: Dictionary = rules.normalize(b)
	return AnatomyCatalog.canonical_json([na.nodes, na.equipment]) == AnatomyCatalog.canonical_json([nb.nodes, nb.equipment])

## Returns {"ok", "errors", "flow"}. `flow` records every example and transformation.
static func run(anatomy, builds) -> Dictionary:
	var rules = AnatomyRules.new(anatomy)
	var projection = BuildProjection.new(anatomy, builds, rules)
	var errors := []
	var bodies := {}
	var examples := []
	for body in load_examples():
		var result: Dictionary = rules.resolve(body)
		if not result.ok:
			errors.append({"code": "example_invalid", "body": body.get("body_id"), "errors": result.errors})
			continue
		bodies[body.body_id] = rules.normalize(body)
		examples.append(_describe(rules, projection, bodies[body.body_id], result.resolved))
	var transformations := []
	for spec in TRANSFORMATIONS:
		if not bodies.has(spec.from):
			errors.append({"code": "missing_source", "transformation": spec.id})
			continue
		var before: Dictionary = rules.resolve(bodies[spec.from]).resolved
		var result: Dictionary = rules.transform(bodies[spec.from], spec.ops)
		if not result.ok:
			errors.append({"code": "transformation_failed", "transformation": spec.id, "errors": result.errors})
			continue
		bodies[spec.id] = result.body
		var after: Dictionary = rules.resolve(result.body).resolved
		var matches: bool = spec.expect.is_empty() or same_form(rules, result.body, bodies[spec.expect])
		if not matches:
			errors.append({"code": "unexpected_result", "transformation": spec.id})
		transformations.append({"id": spec.id, "from": spec.from, "expect": spec.expect, "matches_expected": matches,
			"ops": spec.ops, "report": result.report, "build_items": projection.build_item_changes(result.report),
			"diff": rules.diff(before, after), "body": result.body,
			"requirements_met": rules.check_requirements(after).filter(func(r): return r.met).map(func(r): return r.id),
			"legacy_slots": projection.legacy_slots(after)})
	var rejected := []
	for spec in REJECTED:
		var source: Dictionary = bodies.get(spec.from, {})
		var result: Dictionary = rules.transform(source, spec.ops)
		var codes: Array = AnatomyRules._sorted(AnatomyCatalog._unique(result.errors.map(func(e): return e.code)))
		var as_expected: bool = not result.ok and spec.codes.all(func(c): return c in codes) \
			and rules.to_json(result.body) == rules.to_json(source)
		if not as_expected:
			errors.append({"code": "rejection_mismatch", "case": spec.id, "codes": codes})
		rejected.append({"id": spec.id, "from": spec.from, "ops": spec.ops, "codes": codes, "body_unchanged": as_expected, "errors": result.errors})
	var flow := {
		"catalog": {"version": anatomy.version, "fingerprint": anatomy.fingerprint,
			"build_catalog_version": builds.version, "build_catalog_fingerprint": builds.fingerprint},
		"examples": examples,
		"transformations": transformations,
		"rejected": rejected,
	}
	return {"ok": errors.is_empty(), "errors": errors, "flow": flow}

static func _describe(rules, projection, body: Dictionary, resolved: Dictionary) -> Dictionary:
	return {
		"body": body,
		"gameplay_fingerprint": resolved.gameplay_fingerprint,
		"fingerprint": resolved.fingerprint,
		"anchors": resolved.anchors,
		"silhouette": resolved.gameplay.silhouette,
		"capabilities": resolved.gameplay.capabilities,
		"mounts": resolved.gameplay.mounts,
		"requirements": rules.check_requirements(resolved),
		"combat_view": projection.combat_view(resolved, BUILD_ABILITIES),
		"legacy_slots": projection.legacy_slots(resolved),
	}

static func summary(flow: Dictionary) -> String:
	var lines := ["# Anatomy examples (generated)", "",
		"Generated by `scripts/qa/anatomy_demo.gd` from anatomy catalog %s (`%s`). Do not edit by hand;" % [flow.catalog.version, flow.catalog.fingerprint],
		"`bash scripts/tooling/test_anatomy.sh` regenerates this file and fails if it differs.",
		"These are architectural fixtures, not character classes. All values are provisional.", "",
		"## Example bodies", "",
		"| Body | Parts by kind | Capabilities (providers) | Mounts → equipment | Requirements met | Review flags | Legacy slot view |",
		"| --- | --- | --- | --- | --- | --- | --- |"]
	for example in flow.examples:
		var caps := []
		for capability in AnatomyRules._sorted(example.capabilities.keys()):
			caps.append("%s ×%d" % [capability, example.capabilities[capability].size()])
		var mounts: Array = example.mounts.map(func(m): return "%s → %s" % [m.mount, m.occupied_by if m.occupied_by != "" else "empty"])
		var met: Array = example.requirements.filter(func(r): return r.met).map(func(r): return "`%s`" % r.id)
		var flags: Array = example.combat_view.review_flags.map(func(f): return f.flag + ((":" + str(f.get("node", f.get("kind", "")))) if f.has("node") or f.has("kind") else ""))
		var legacy: Dictionary = example.legacy_slots
		lines.append("| `%s` | %s | %s | %s | %s | %s | %s%s |" % [example.body.body_id, _kv(example.silhouette.kind_counts),
			", ".join(caps), "<br>".join(mounts), ", ".join(met), ", ".join(flags) if not flags.is_empty() else "none",
			AnatomyCatalog.canonical_json(legacy.equipped), "" if legacy.lossless else " (lossy: %s)" % ", ".join(legacy.anatomy_only_nodes + legacy.unrepresented.map(func(u): return "%s %s" % [u.get("item", u.get("node", "")), u.reason]))])
	lines.append_array(["", "## Requirement checks", "", "| Body | Requirement | Met | Origin node / point | Missing or excluded |", "| --- | --- | --- | --- | --- |"])
	for example in flow.examples:
		for check in example.requirements:
			var why: Array = check.missing.map(func(m): return "%s %d/%d" % [m.capability, m.have, m.need]) + check.excluded.map(func(e): return "excluded %s" % e.capability)
			var origin: String = "%s / %s" % [check.origin.node, check.origin.point] if check.met else "—"
			lines.append("| `%s` | `%s` | %s | %s | %s |" % [example.body.body_id, check.id, "yes" if check.met else "no", origin, ", ".join(why) if not why.is_empty() else "—"])
	lines.append_array(["", "## Transformations", "", "| Transformation | From | Matches | Removed nodes | Displaced equipment (reason) | Build items → carried | Build items ← carried | Capabilities +/− | Anchors unchanged |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"])
	for t in flow.transformations:
		var displaced: Array = t.report.displaced.map(func(d): return "%s (%s)" % [d.item, ", ".join(d.reasons)])
		var removed: Array = t.report.removed_nodes.map(func(r): return r.node)
		var caps: String = " ".join(t.diff.capabilities_added.map(func(c): return "+" + c) + t.diff.capabilities_removed.map(func(c): return "−" + c))
		lines.append("| `%s` | `%s` | %s | %s | %s | %s | %s | %s | %s |" % [t.id, t.from, ("`%s`" % t.expect) if t.expect != "" else "—",
			_list(removed), _list(displaced, "<br>"), _list(t.build_items.to_carried), _list(t.build_items.from_carried),
			caps if caps != "" else "—", "yes" if t.diff.anchors_unchanged else "no"])
	lines.append_array(["", "## Rejected configurations (body returned unchanged)", "", "| Case | From | Error codes | Unchanged |", "| --- | --- | --- | --- |"])
	for r in flow.rejected:
		lines.append("| `%s` | `%s` | %s | %s |" % [r.id, r.from, ", ".join(r.codes.map(func(c): return "`%s`" % c)), "yes" if r.body_unchanged else "**no**"])
	return "\n".join(lines) + "\n"

static func _list(values: Array, separator := ", ") -> String:
	return separator.join(values) if not values.is_empty() else "—"

static func _kv(values: Dictionary) -> String:
	var parts := []
	for key in AnatomyRules._sorted(values.keys()):
		parts.append("%s %s" % [key, str(values[key])])
	return ", ".join(parts)
