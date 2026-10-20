extends SceneTree
## Deterministic tests for the anatomy prototype. Prints one JSON line per check plus
## a summary, like the other suites. Exit code 1 on any failure. Independent of
## combat, the courtyard and worldgen; reads (never edits) the shared build catalog.

const AnatomyCatalog := preload("res://scripts/anatomy/anatomy_catalog.gd")
const AnatomyRules := preload("res://scripts/anatomy/anatomy_rules.gd")
const BuildProjection := preload("res://scripts/anatomy/build_projection.gd")
const BuildCatalog := preload("res://scripts/builds/build_catalog.gd")
const BuildRules := preload("res://scripts/builds/build_rules.gd")
const SalvageFlow := preload("res://scripts/qa/salvage_flow_fixture.gd")
const Fixture := preload("res://scripts/qa/anatomy_fixture.gd")
const EXAMPLE_FLOW := "res://docs/anatomy/examples/flow.json"
const LIVE_BUILDS := "res://data/builds/courtyard.json"
const CORE_SCRIPTS := ["res://scripts/anatomy/anatomy_catalog.gd", "res://scripts/anatomy/anatomy_rules.gd"]
const LEGACY_SLOTS := ["hand_r", "hand_l", "arm_r", "arm_l"]

## Test-only definitions layered onto the real catalog. Never shipped as content.
const FIXTURE_PARTS := [
	{"id": "part.test_wide_torso", "name": "Test Wide Torso", "kind": "core", "attaches_to": [],
		"sockets": [
			{"id": "hips_a", "type": "hips", "side": "center", "pair": ""},
			{"id": "hips_b", "type": "hips", "side": "center", "pair": ""},
			{"id": "s1_l", "type": "shoulder", "side": "left", "pair": "one"}, {"id": "s1_r", "type": "shoulder", "side": "right", "pair": "one"},
			{"id": "s2_l", "type": "shoulder", "side": "left", "pair": "two"}, {"id": "s2_r", "type": "shoulder", "side": "right", "pair": "two"},
			{"id": "s3_l", "type": "shoulder", "side": "left", "pair": "three"}, {"id": "s3_r", "type": "shoulder", "side": "right", "pair": "three"}],
		"mounts": [], "anchors": ["camera_focus", "core_hurtbox", "facing", "movement_root"],
		"provides": [], "tags": ["frame.augmented_spine"], "requires_tags": [], "excludes_tags": [], "proportions": [],
		"animation_module": "anim.core_upright", "build_item": "",
		"gameplay": {"hurt_class": "standard", "reach_class": "none", "attack_origin": "", "guard": "none"}, "visual": {}},
	{"id": "part.test_hollow_claw", "name": "Test Hollow Claw", "kind": "arm", "attaches_to": ["shoulder"],
		"sockets": [], "mounts": [], "anchors": [], "provides": ["strike.thrust"], "tags": ["corruption.hollow"],
		"requires_tags": [], "excludes_tags": [], "proportions": [], "animation_module": "anim.arm_standard", "build_item": "",
		"gameplay": {"hurt_class": "small", "reach_class": "short", "attack_origin": "claw", "guard": "front"}, "visual": {}},
	{"id": "part.test_jointed_arm", "name": "Test Jointed Arm", "kind": "arm", "attaches_to": ["shoulder"],
		"sockets": [{"id": "forearm", "type": "shoulder", "side": "center", "pair": ""}], "mounts": [], "anchors": [],
		"provides": [], "tags": [], "requires_tags": [], "excludes_tags": [], "proportions": [],
		"animation_module": "anim.arm_standard", "build_item": "",
		"gameplay": {"hurt_class": "small", "reach_class": "standard", "attack_origin": "", "guard": "front"}, "visual": {}},
]
const FIXTURE_EQUIPMENT := [
	{"id": "equip.test_lens", "name": "Test Lens", "build_item": "", "fixture": true, "mounts_on": ["grip", "light_grip"],
		"mount_count": 1, "paired": false, "provides": [], "requires_capabilities": ["sense.sight"], "excludes_part_tags": []},
	{"id": "equip.test_heavy_charm", "name": "Test Heavy Charm", "build_item": "", "fixture": true, "mounts_on": ["light_grip"],
		"mount_count": 1, "paired": false, "provides": [], "requires_capabilities": [], "excludes_part_tags": ["limb.auxiliary"]},
]
const FIXTURE_REQUIREMENTS := [
	{"id": "probe.test_no_marrow", "fixture": true, "all": [{"capability": "grasp", "count": 1}], "none": ["limb.marrow"]},
]

var passed := 0
var failed := 0
var raw: Dictionary
var catalog
var rules
var fixture
var fixture_rules
var builds
var build_rules
var projection
var examples := {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	var record := {"suite": "anatomy", "check": label, "passed": condition}
	if not condition and detail != null:
		record["detail"] = detail
	print(JSON.stringify(record))

func run() -> void:
	raw = JSON.parse_string(FileAccess.get_file_as_string(AnatomyCatalog.CATALOG_PATH))
	catalog = AnatomyCatalog.new()
	check(catalog.load_file(), "catalog_valid", catalog.errors)
	rules = AnatomyRules.new(catalog)
	fixture = AnatomyCatalog.new()
	check(fixture.load_data(_fixture_data()), "fixture_catalog_valid", fixture.errors)
	fixture_rules = AnatomyRules.new(fixture)
	builds = BuildCatalog.new()
	check(builds.load_file(), "build_catalog_loads_unchanged", builds.errors)
	build_rules = BuildRules.new(builds)
	projection = BuildProjection.new(catalog, builds, rules)
	for body in Fixture.load_examples():
		examples[body.body_id] = body
	test_catalog()
	test_catalog_validation()
	test_examples()
	test_shape_validation()
	test_graph_validation()
	test_attachment_compatibility()
	test_asymmetry_and_extra_limbs()
	test_equipment()
	test_requirements()
	test_transformations()
	test_build_contract()
	test_serialization()
	test_reproducibility()
	test_isolation()
	print(JSON.stringify({"suite": "anatomy", "summary": true, "passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)

func _fixture_data() -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	data.parts.append_array(FIXTURE_PARTS.duplicate(true))
	data.equipment.append_array(FIXTURE_EQUIPMENT.duplicate(true))
	data.requirements.append_array(FIXTURE_REQUIREMENTS.duplicate(true))
	return data

func _codes(errors: Array) -> Array:
	return errors.map(func(e): return e.code)

func _body(id: String) -> Dictionary:
	return examples[id].duplicate(true)

func _node(body: Dictionary, id: String) -> Dictionary:
	for node in body.nodes:
		if node.id == id:
			return node
	return {}

func _add(body: Dictionary, id: String, part: String, parent: String, socket: String) -> Dictionary:
	body.nodes.append({"id": id, "part": part, "parent": parent, "socket": socket, "proportions": {}})
	return body

func _resolved(body: Dictionary, r = null) -> Dictionary:
	return (r if r != null else rules).resolve(body).resolved

func _requirement(body: Dictionary, id: String, r = null) -> Dictionary:
	var with: Variant = r if r != null else rules
	return with.check_requirement(with.resolve(body).resolved, id)

## Validation of a body that differs from `base` by `mutate`; returns the error codes.
func _invalid(base: String, mutate: Callable, r = null) -> Array:
	var body := _body(base)
	mutate.call(body)
	return _codes((r if r != null else rules).validate(body))

func test_catalog() -> void:
	check(catalog.version == "0.1.0" and catalog.fingerprint.length() == 16, "catalog_version_and_fingerprint")
	check(catalog.parts.size() == 11 and catalog.equipment.size() == 3 and catalog.requirements.size() == 6, "catalog_is_small_curated_sample")
	check(catalog.parts["part.marrow_arm"].is_read_only() and catalog.parts["part.marrow_arm"].gameplay.is_read_only()
		and catalog.parts["part.humanoid_torso"].sockets[0].is_read_only(), "definitions_frozen_deeply")
	var other = AnatomyCatalog.new()
	other.load_file()
	check(other.fingerprint == catalog.fingerprint and other.part_fingerprint("part.marrow_arm") == catalog.part_fingerprint("part.marrow_arm"),
		"fingerprints_stable_across_instances")
	var restyled: Dictionary = raw.duplicate(true)
	restyled.parts[4].visual.material_hint = "steel"
	var visual_only = AnatomyCatalog.new()
	check(visual_only.load_data(restyled) and restyled.parts[4].id == "part.human_arm", "visual_edit_still_valid", visual_only.errors)
	check(visual_only.part_gameplay_fingerprint("part.human_arm") == catalog.part_gameplay_fingerprint("part.human_arm")
		and visual_only.part_fingerprint("part.human_arm") != catalog.part_fingerprint("part.human_arm"), "visual_edit_keeps_gameplay_fingerprint")
	for part in catalog.parts.values():
		if part.kind == "core":
			check(part.anchors == catalog.required_anchors, "core_carries_all_anchors:" + part.id)

func test_catalog_validation() -> void:
	var cases := {
		"unknown_catalog_key": func(d): d["extra"] = 1,
		"core_missing_anchor": func(d): d.parts[0].anchors = ["facing"],
		"limb_with_anchor": func(d): d.parts[4].anchors = ["facing"],
		"unknown_socket_type": func(d): d.parts[4].attaches_to = ["wing"],
		"unknown_capability": func(d): d.parts[4].provides = ["grasp", "telekinesis"],
		"rear_guard_forbidden": func(d): d.parts[4].gameplay.guard = "rear",
		"striker_without_origin": func(d): d.parts[5].gameplay.attack_origin = "",
		"gameplay_key_in_visual": func(d): d.parts[4].visual["hurt_class"] = "large",
		"unknown_hurt_class": func(d): d.parts[4].gameplay.hurt_class = "huge",
		"paired_needs_two_mounts": func(d): d.equipment[1].mount_count = 1,
		"unsatisfiable_requirement": func(d): d.capabilities.append("wing.flight"); d.capabilities.sort(); d.requirements[0].all = [{"capability": "wing.flight", "count": 1}],
		"owner_key": func(d): d.parts[4]["player_only"] = true,
		"unknown_animation_module": func(d): d.parts[4].animation_module = "anim.generated",
		"proportion_range_inverted": func(d): d.parts[4].proportions[1].min = 2.0,
		"unsorted_capabilities": func(d): d.capabilities.reverse(),
		"duplicate_part": func(d): d.parts.append(d.parts[4].duplicate(true)),
		"fractional_count": func(d): d.requirements[4].all[0].count = 2.5,
		"wrong_schema": func(d): d.schema = "boneshed.anatomy_catalog.v9",
	}
	for label in cases:
		var data: Dictionary = raw.duplicate(true)
		cases[label].call(data)
		var bad = AnatomyCatalog.new()
		check(not bad.load_data(data) and not bad.errors.is_empty(), "malformed_catalog_rejected:" + label)

func test_examples() -> void:
	check(examples.keys() == ["body.humanoid_fighter", "body.marrow_replacement", "body.four_armed", "body.carapace_brute"], "four_example_bodies")
	for id in examples:
		check(rules.validate(examples[id]).is_empty(), "example_valid:" + id, rules.validate(examples[id]))
		var resolved := _resolved(examples[id])
		check(resolved.anchors.values().all(func(n): return n == "torso"), "anchors_on_core:" + id)
		check(resolved.gameplay.locomotion.node == "legs", "single_locomotion_provider:" + id)

func test_shape_validation() -> void:
	var cases := {
		"not_an_object": [[1], ["not_an_object"]],
		"unknown_key": [func(b): b["script"] = "res://x.gd", ["unknown_key"]],
		"missing_key": [func(b): b.erase("equipment"), ["missing_key"]],
		"unsupported_schema": [func(b): b.schema = "boneshed.anatomy.v9", ["unsupported_schema"]],
		"invalid_body_id": [func(b): b.body_id = "Bad Id", ["invalid_body_id"]],
		"catalog_version_mismatch": [func(b): b.catalog_version = "9.9.9", ["catalog_version_mismatch"]],
		"invalid_nodes": [func(b): b.nodes = [], ["invalid_nodes"]],
		"invalid_node": [func(b): b.nodes[0]["extra"] = 1, ["invalid_node"]],
		"invalid_node_id": [func(b): b.nodes[0].id = "Arm-L", ["invalid_node_id"]],
		"unknown_part": [func(b): b.nodes[0].part = "part.wing", ["unknown_part"]],
		"invalid_proportions": [func(b): b.nodes[0].proportions = {"length": "long"}, ["invalid_proportions"]],
		"invalid_equipment": [func(b): b.equipment[0].mounts = [], ["invalid_equipment"]],
	}
	for label in cases:
		var codes: Array
		if cases[label][0] is Array:
			codes = _codes(rules.validate(cases[label][0]))
		else:
			codes = _invalid("body.humanoid_fighter", cases[label][0])
		check(cases[label][1].all(func(c): return c in codes), "shape_rejected:" + label, codes)

func test_graph_validation() -> void:
	var codes := _invalid("body.humanoid_fighter", func(b): _add(_add(b, "loop_a", "part.human_arm", "loop_b", "x"), "loop_b", "part.human_arm", "loop_a", "x"))
	check("cycle" in codes and "disconnected" in codes, "cycle_detected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _add(b, "self", "part.human_arm", "self", "x"))
	check("cycle" in codes, "self_parent_cycle_detected", codes)
	var cycle_errors: Array = rules.validate(_add(_add(_body("body.humanoid_fighter"), "loop_a", "part.human_arm", "loop_b", "x"), "loop_b", "part.human_arm", "loop_a", "x"))
	check(cycle_errors.filter(func(e): return e.code == "cycle").map(func(e): return e.nodes) == [["loop_a", "loop_b"]], "cycle_reported_once_with_members")
	codes = _invalid("body.humanoid_fighter", func(b): _add(b, "floating_arm", "part.human_arm", "", ""))
	check("multiple_roots" in codes and "root_not_core" in codes, "disconnected_root_limb_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "arm_l").parent = "ghost")
	check("unknown_parent" in codes, "limb_with_missing_parent_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "torso").parent = "arm_l"; _node(b, "torso").socket = "grip")
	check("no_root" in codes and "cycle" in codes, "rootless_body_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): b.nodes.append(b.nodes[0].duplicate(true)))
	check(codes == ["duplicate_node_id"], "duplicate_identifier_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "torso").socket = "neck")
	check("root_has_socket" in codes, "root_with_socket_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "head").part = "part.humanoid_torso")
	check("core_not_root" in codes, "second_core_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "arm_l").socket = "elbow")
	check("unknown_socket" in codes, "unknown_socket_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "legs").part = "part.human_arm"; _node(b, "arm_l").part = "part.biped_legs")
	check("incompatible_socket" in codes, "incompatible_socket_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "arm_l").socket = "shoulder_r")
	check("socket_occupied" in codes, "occupied_socket_rejected", codes)
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "torso").part = "part.human_head")
	check("root_not_core" in codes, "non_core_root_rejected", codes)
	# Engineering guard rails only; not a decided body limit.
	var tight: Dictionary = raw.duplicate(true)
	tight.limits = {"max_nodes": 4, "max_depth": 1}
	tight.parts.append_array(FIXTURE_PARTS.duplicate(true))
	var tight_catalog = AnatomyCatalog.new()
	tight_catalog.load_data(tight)
	var tight_rules = AnatomyRules.new(tight_catalog)
	check("too_many_nodes" in _codes(tight_rules.validate(_body("body.humanoid_fighter"))), "node_limit_enforced")
	var deep := _body("body.humanoid_fighter")
	_node(deep, "arm_l").part = "part.test_jointed_arm"
	deep.equipment = []
	_add(deep, "forearm_l", "part.human_arm", "arm_l", "forearm")
	check(fixture_rules.validate(deep).is_empty() and "too_deep" in _codes(tight_rules.validate(deep)), "nested_limb_valid_and_depth_limit_enforced", fixture_rules.validate(deep))
	var shuffled := _body("body.four_armed")
	_node(shuffled, "arm_l").socket = "elbow"
	_node(shuffled, "legs").parent = "ghost"
	var reversed: Dictionary = shuffled.duplicate(true)
	reversed.nodes.reverse()
	check(rules.validate(shuffled) == rules.validate(reversed), "error_order_independent_of_node_order")
	var original := _body("body.humanoid_fighter")
	var copy: Dictionary = original.duplicate(true)
	rules.validate(original)
	rules.resolve(original)
	check(original == copy, "validation_does_not_mutate_input")

func test_attachment_compatibility() -> void:
	var codes := _invalid("body.humanoid_fighter", func(b): _node(b, "arm_l").part = "part.auxiliary_arm")
	check("missing_required_tag" in codes, "auxiliary_arm_needs_augmented_spine", codes)
	var aux := _body("body.four_armed")
	check(rules.validate(aux).is_empty(), "auxiliary_arm_fits_augmented_spine")
	codes = _invalid("body.humanoid_fighter", func(b): _node(b, "arm_r").part = "part.carapace_arm")
	check("incompatible_socket" in codes and "missing_required_tag" in codes, "carapace_arm_needs_great_shoulder_and_frame", codes)
	var errors: Array = fixture_rules.validate(_with_node_part(_body("body.marrow_replacement"), "arm_r", "part.test_hollow_claw", true))
	check(errors.any(func(e): return e.code == "excluded_tag" and e.node == "arm_l" and e.conflicts_with == "arm_r" and e.tag == "corruption.hollow"),
		"corruption_lineages_exclude_each_other", errors)
	check(fixture_rules.validate(_with_node_part(_body("body.humanoid_fighter"), "arm_l", "part.test_hollow_claw", true)).is_empty(), "exclusion_only_applies_when_both_present")

func _with_node_part(body: Dictionary, node_id: String, part: String, drop_equipment := false) -> Dictionary:
	_node(body, node_id).part = part
	if drop_equipment:
		body.equipment = body.equipment.filter(func(e): return not e.mounts.any(func(m): return m.begins_with(node_id + "/")))
	return body

func test_asymmetry_and_extra_limbs() -> void:
	var symmetric := {"body.humanoid_fighter": false, "body.marrow_replacement": true, "body.four_armed": false, "body.carapace_brute": true}
	for id in symmetric:
		check(_resolved(examples[id]).gameplay.silhouette.asymmetric == symmetric[id], "asymmetry_detected:" + id)
	var brute := _resolved(examples["body.carapace_brute"])
	check(brute.gameplay.nodes.filter(func(n): return n.id == "torso")[0].proportions == {"height": 1.15}
		and brute.visual.nodes.filter(func(n): return n.id == "torso")[0].proportions == {"lean": 0.15}, "proportions_split_by_domain_with_defaults")
	var flags: Array = brute.gameplay.review_flags.map(func(f): return f.flag)
	check(["asymmetric_silhouette", "non_baseline_locomotion", "review_hurtbox", "review_reach"].all(func(f): return f in flags), "extreme_form_flagged_for_review", flags)
	check(_resolved(examples["body.humanoid_fighter"]).gameplay.review_flags.is_empty(), "baseline_form_has_no_flags")
	var four := _resolved(examples["body.four_armed"])
	check(four.gameplay.silhouette.kind_counts.arm == 4, "four_arms_counted")
	check(four.gameplay.capabilities.grasp == ["arm_l", "arm_r"] and four.gameplay.capabilities["grasp.light"] == ["arm_lower_l", "arm_lower_r"],
		"extra_limbs_have_differing_capabilities")
	check(four.gameplay.capabilities["guard.parry"].size() == 4, "parry_capability_counts_every_limb")
	var six := _body("body.four_armed")
	_node(six, "torso").part = "part.test_wide_torso"
	for pair in [["arm_l", "s1_l"], ["arm_r", "s1_r"], ["arm_lower_l", "s2_l"], ["arm_lower_r", "s2_r"], ["legs", "hips_a"]]:
		_node(six, pair[0]).socket = pair[1]
	six.nodes = six.nodes.filter(func(n): return n.id != "head")
	_add(_add(six, "arm_third_l", "part.human_arm", "torso", "s3_l"), "arm_third_r", "part.human_arm", "torso", "s3_r")
	var six_resolved := _resolved(six, fixture_rules)
	check(fixture_rules.validate(six).is_empty() and six_resolved.gameplay.silhouette.kind_counts.arm == 6
		and six_resolved.gameplay.capabilities.grasp.size() == 4, "six_arms_without_schema_change", fixture_rules.validate(six))
	var one_armed: Dictionary = rules.transform(_body("body.humanoid_fighter"), [{"op": "detach", "node": "arm_l"}])
	check(one_armed.ok and _resolved(one_armed.body).gameplay.silhouette.asymmetric and _resolved(one_armed.body).gameplay.capabilities.grasp == ["arm_r"],
		"one_armed_form_valid_and_asymmetric")
	var two_legs := six.duplicate(true)
	_add(two_legs, "legs_b", "part.biped_legs", "torso", "hips_b")
	var errors: Array = fixture_rules.validate(two_legs)
	check(errors.any(func(e): return e.code == "locomotion_count" and e.count == 2), "two_locomotion_providers_rejected", errors)

func test_equipment() -> void:
	var four := _resolved(examples["body.four_armed"])
	check(four.gameplay.mounts.map(func(m): return [m.mount, m.occupied_by]) == [["arm_l/grip", ""], ["arm_lower_l/light_grip", "equip.fixture_buckler"],
		["arm_lower_r/light_grip", ""], ["arm_r/grip", "equip.notched_sword"]], "mount_points_listed_with_occupants")
	var cases := {
		"unknown_equipment": func(b): b.equipment[0].item = "equip.missing",
		"wrong_mount_type": func(b): b.equipment[1].mounts = ["arm_lower_r/light_grip"],
		"unknown_mount": func(b): b.equipment[1].mounts = ["arm_lower_r/grip"],
		"mount_in_use": func(b): b.equipment.append({"item": "equip.fixture_buckler", "mounts": ["arm_r/grip"]}),
		"mount_count": func(b): b.equipment[1] = {"item": "equip.fixture_greatsword", "mounts": ["arm_r/grip"]},
		"unpaired_mounts": func(b): b.equipment = [{"item": "equip.fixture_greatsword", "mounts": ["arm_l/grip", "arm_lower_r/light_grip"]}],
	}
	for code in cases:
		var codes := _invalid("body.four_armed", cases[code])
		check(code in codes, "equipment_rejected:" + code, codes)
	var two_handed := _body("body.humanoid_fighter")
	two_handed.equipment = [{"item": "equip.fixture_greatsword", "mounts": ["arm_r/grip", "arm_l/grip"]}]
	check(rules.validate(two_handed).is_empty(), "paired_mounts_accept_two_handed")
	var excluded := _body("body.four_armed")
	excluded.equipment.append({"item": "equip.test_heavy_charm", "mounts": ["arm_lower_r/light_grip"]})
	check("equipment_excluded" in _codes(fixture_rules.validate(excluded)), "equipment_excluded_by_part_tag")
	var blind := _body("body.humanoid_fighter")
	blind.nodes = blind.nodes.filter(func(n): return n.id != "head")
	check(rules.validate(blind).is_empty(), "headless_body_valid")
	blind.equipment.append({"item": "equip.test_lens", "mounts": ["arm_l/grip"]})
	check("equipment_missing_capability" in _codes(fixture_rules.validate(blind)), "equipment_capability_requirement_enforced")
	var seen := _body("body.humanoid_fighter")
	seen.equipment.append({"item": "equip.test_lens", "mounts": ["arm_l/grip"]})
	check(fixture_rules.validate(seen).is_empty(), "equipment_capability_requirement_satisfied")

func test_requirements() -> void:
	var expected := {
		"body.humanoid_fighter": ["attack.heavy_slash", "attack.slash"],
		"body.marrow_replacement": ["ability.marrow_lunge", "attack.heavy_slash", "attack.slash"],
		"body.four_armed": ["attack.heavy_slash", "attack.slash", "probe.multi_parry"],
		"body.carapace_brute": ["attack.heavy_slash", "attack.slash", "probe.anchored_crush"],
	}
	for id in expected:
		var met: Array = rules.check_requirements(_resolved(examples[id])).filter(func(r): return r.met).map(func(r): return r.id)
		check(met == expected[id], "requirements_resolved:" + id, met)
	var lunge := _requirement(examples["body.marrow_replacement"], "ability.marrow_lunge")
	check(lunge.origin == {"node": "arm_l", "point": "bone_tip", "animation_module": "anim.arm_marrow"}, "lunge_origin_is_marrow_limb", lunge.origin)
	var slash := _requirement(examples["body.marrow_replacement"], "attack.slash")
	check(slash.origin.node == "arm_r" and slash.origin.point == "grip", "slash_origin_follows_the_sword", slash.origin)
	var missing := _requirement(examples["body.humanoid_fighter"], "probe.multi_parry")
	check(not missing.met and missing.missing == [{"capability": "guard.parry", "need": 3, "have": 2}], "missing_capability_reported_with_counts")
	var excluded := _requirement(examples["body.marrow_replacement"], "probe.test_no_marrow", fixture_rules)
	check(not excluded.met and excluded.missing.is_empty() and excluded.excluded == [{"capability": "limb.marrow", "nodes": ["arm_l"]}], "excluded_capability_blocks_requirement")
	check(_requirement(examples["body.humanoid_fighter"], "probe.test_no_marrow", fixture_rules).met, "exclusion_absent_requirement_met")
	check(rules.check_requirement(_resolved(examples["body.humanoid_fighter"]), "ability.unknown").get("error") == "unknown_requirement", "unknown_requirement_reported")
	var two_handed := _body("body.humanoid_fighter")
	two_handed.equipment = [{"item": "equip.fixture_greatsword", "mounts": ["arm_l/grip", "arm_r/grip"]}]
	check(_requirement(two_handed, "probe.two_handed_grip").met, "two_handed_requirement_met_by_paired_grip")
	var text := AnatomyCatalog.canonical_json(raw.requirements)
	check(LEGACY_SLOTS.all(func(s): return not text.contains(s)), "requirements_reference_capabilities_not_slots")
	check(builds.abilities.keys().all(func(id): return catalog.requirements.has(id)), "every_shared_build_ability_has_a_capability_requirement")

func test_transformations() -> void:
	var result := Fixture.run(catalog, builds)
	check(result.ok, "fixture_flow_ok", result.errors)
	for t in result.flow.transformations:
		check(t.matches_expected and rules.validate(t.body).is_empty() and t.diff.anchors_unchanged, "transformation_valid:" + t.id)
	for r in result.flow.rejected:
		check(r.body_unchanged, "rejected_atomically:" + r.id, r.codes)
	var source := _body("body.humanoid_fighter")
	var copy: Dictionary = source.duplicate(true)
	var corrupted: Dictionary = rules.transform(source, Fixture.TRANSFORMATIONS[0].ops)
	check(source == copy and corrupted.ok, "transform_does_not_mutate_input")
	var half: Dictionary = rules.transform(source, [{"op": "replace", "node": "arm_r", "part": "part.marrow_arm"}])
	check(half.ok and half.report.displaced == [{"item": "equip.notched_sword", "mounts": ["arm_r/grip"], "reasons": ["unknown_mount"]}]
		and half.body.equipment.is_empty() and half.report.equipment_released == ["equip.notched_sword"], "incompatible_equipment_displaced_not_lost")
	var greatsword: Dictionary = rules.transform(source, Fixture.TRANSFORMATIONS[2].ops)
	check(greatsword.report.equipment_released == ["equip.notched_sword"] and greatsword.report.equipment_required == ["equip.fixture_greatsword"],
		"net_equipment_changes_reported")
	var corrupt_holder: Dictionary = rules.transform(greatsword.body, Fixture.TRANSFORMATIONS[3].ops)
	check(corrupt_holder.ok and corrupt_holder.body.equipment.is_empty() and corrupt_holder.report.displaced[0].item == "equip.fixture_greatsword",
		"two_handed_grip_displaced_when_one_hand_is_lost")
	var brute: Dictionary = rules.transform(_body("body.four_armed"), Fixture.TRANSFORMATIONS[5].ops)
	check(brute.report.removed_nodes.map(func(r): return r.node) == ["arm_lower_l", "arm_lower_r", "arm_r"]
		and _node(brute.body, "arm_l").part == "part.human_arm", "core_replacement_keeps_compatible_children_only")
	var nested := _body("body.humanoid_fighter")
	_node(nested, "arm_l").part = "part.test_jointed_arm"
	_add(nested, "forearm_l", "part.human_arm", "arm_l", "forearm")
	nested.equipment.append({"item": "equip.fixture_buckler", "mounts": ["forearm_l/grip"]})
	var detached: Dictionary = fixture_rules.transform(nested, [{"op": "detach", "node": "arm_l"}])
	check(detached.ok and detached.report.removed_nodes.map(func(r): return r.node) == ["arm_l", "forearm_l"]
		and detached.report.displaced[0].item == "equip.fixture_buckler", "detach_removes_subtree_and_displaces_its_equipment", detached.errors)
	var failing: Dictionary = rules.transform(source, [{"op": "replace", "node": "arm_r", "part": "part.marrow_arm"}, {"op": "detach", "node": "legs"}])
	check(not failing.ok and failing.body == source and failing.errors.all(func(e): return e.get("stage") == "result"), "late_failure_rolls_back_everything")
	var op_cases := {
		"invalid_ops": "not a list",
		"unknown_op": [{"op": "regrow"}],
		"invalid_op": [{"op": "detach"}],
		"node_exists": [{"op": "attach", "node": "arm_l", "part": "part.human_arm", "parent": "torso", "socket": "shoulder_l"}],
		"unknown_node": [{"op": "detach", "node": "wing"}],
		"unknown_part": [{"op": "replace", "node": "arm_l", "part": "part.wing"}],
		"mount_empty": [{"op": "unmount", "mount": "arm_l/grip"}],
		"cannot_detach_root": [{"op": "detach", "node": "torso"}],
	}
	for code in op_cases:
		var attempt: Dictionary = rules.transform(source, op_cases[code])
		check(not attempt.ok and code in _codes(attempt.errors) and attempt.body == source, "bad_op_rejected:" + code, attempt.errors)
	check(rules.transform({"schema": "x"}, []).ok == false, "invalid_source_body_cannot_transform")
	var again: Dictionary = rules.transform(source, Fixture.TRANSFORMATIONS[4].ops)
	check(rules.to_json(again.body) == rules.to_json(rules.transform(source, Fixture.TRANSFORMATIONS[4].ops).body), "transformation_deterministic")

func test_build_contract() -> void:
	var player: Dictionary = SalvageFlow.player_build(build_rules)
	var soul: Dictionary = SalvageFlow.corrupted_soul_build(build_rules)
	var human: Dictionary = projection.legacy_slots(_resolved(examples["body.humanoid_fighter"]))
	check(human.lossless and human.equipped == player.equipped, "humanoid_projects_to_current_player_build", human)
	var marrow: Dictionary = projection.legacy_slots(_resolved(examples["body.marrow_replacement"]))
	check(marrow.lossless and marrow.equipped == soul.equipped, "marrow_body_projects_to_current_soul_build", marrow)
	# The live courtyard actors (read as data only) are both humanoid sword wielders.
	var live: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LIVE_BUILDS))
	for actor in ["player", "enemy"]:
		var projected: Dictionary = live[actor].duplicate(true)
		projected.equipped = human.equipped
		check(build_rules.validate(live[actor]).is_empty() and human.equipped == live[actor].equipped
			and build_rules.resolve(projected).ok, "humanoid_projects_to_live_build:" + actor, live[actor])
	for id in examples:
		var view: Dictionary = projection.legacy_slots(_resolved(examples[id]))
		var build: Dictionary = build_rules.new_build("projection.check", "profile.duelist")
		build.equipped = view.equipped
		check(build_rules.validate(build).is_empty(), "projection_is_a_valid_shared_build:" + id, build_rules.validate(build))
	var four: Dictionary = projection.legacy_slots(_resolved(examples["body.four_armed"]))
	check(not four.lossless and "arm_lower_l" in four.anatomy_only_nodes, "extra_limbs_flagged_as_anatomy_only")
	var corrupt: Dictionary = rules.transform(_body("body.humanoid_fighter"), Fixture.TRANSFORMATIONS[0].ops)
	check(projection.build_item_changes(corrupt.report) == {"to_carried": [], "from_carried": ["item.marrow_arm"]}, "transformation_needs_salvaged_item_carried")
	var revert: Dictionary = rules.transform(_body("body.marrow_replacement"), Fixture.TRANSFORMATIONS[1].ops)
	check(projection.build_item_changes(revert.report) == {"to_carried": ["item.marrow_arm"], "from_carried": []}, "reverting_returns_augment_to_carried")
	var view: Dictionary = projection.combat_view(_resolved(examples["body.carapace_brute"]), ["attack.slash", "ability.marrow_lunge"])
	check(view.anchors.facing == "torso" and view.guard.facing_node == "torso" and view.locomotion.module == "anim.locomotion_digitigrade",
		"combat_view_has_stable_anchors_and_curated_locomotion")
	check(view.attacks[0].met and view.attacks[0].attack_module == "module.slash_basic" and view.attacks[0].origin.node == "arm_l"
		and not view.attacks[1].met, "combat_view_resolves_attack_origins_and_modules")
	check(view.hurt_volumes.size() == 6 and view.hurt_volumes.all(func(h): return h["class"] in catalog.classes.hurt), "combat_view_lists_hurt_volume_classes")
	for part in catalog.parts.values():
		if not part.build_item.is_empty():
			check(builds.items.has(part.build_item), "part_build_item_exists:" + part.id)
	for entry in catalog.equipment.values():
		check(entry.build_item.is_empty() == entry.fixture and (entry.build_item.is_empty() or builds.items.has(entry.build_item)), "equipment_build_link:" + entry.id)

func test_serialization() -> void:
	for id in examples:
		var text: String = rules.to_json(examples[id])
		var loaded: Dictionary = rules.from_json(text)
		check(loaded.ok and rules.to_json(loaded.body) == text, "json_round_trip:" + id)
		check(_resolved(loaded.body).fingerprint == _resolved(examples[id]).fingerprint, "round_trip_resolves_identically:" + id)
	check(rules.to_json(examples["body.marrow_replacement"]) == '{"body_id":"body.marrow_replacement","catalog_version":"0.1.0","equipment":[{"item":"equip.notched_sword","mounts":["arm_r/grip"]}],"nodes":[{"id":"arm_l","parent":"torso","part":"part.marrow_arm","proportions":{},"socket":"shoulder_l"},{"id":"arm_r","parent":"torso","part":"part.human_arm","proportions":{},"socket":"shoulder_r"},{"id":"head","parent":"torso","part":"part.human_head","proportions":{},"socket":"neck"},{"id":"legs","parent":"torso","part":"part.biped_legs","proportions":{},"socket":"hips"},{"id":"torso","parent":"","part":"part.humanoid_torso","proportions":{},"socket":""}],"schema":"boneshed.anatomy.v0"}',
		"canonical_body_json_exact")
	var shuffled := _body("body.four_armed")
	shuffled.nodes.reverse()
	shuffled.equipment.reverse()
	check(rules.to_json(shuffled) == rules.to_json(examples["body.four_armed"]) and _resolved(shuffled).fingerprint == _resolved(examples["body.four_armed"]).fingerprint,
		"order_independent_serialization")
	check("malformed_json" in _codes(rules.from_json("{not json").errors), "malformed_json_rejected")
	check("not_an_object" in _codes(rules.from_json("[1, 2]").errors), "non_object_json_rejected")
	var injected: String = rules.to_json(examples["body.humanoid_fighter"]).replace('"schema"', '"script":"res://evil.gd","schema"')
	check("unknown_key" in _codes(rules.from_json(injected).errors) and rules.from_json(injected).body.is_empty(), "unexpected_fields_rejected")
	var object_like: String = rules.to_json(examples["body.humanoid_fighter"]).replace('"part.human_head"', '{"type":"Resource","path":"res://x.tres"}')
	check("unknown_part" in _codes(rules.from_json(object_like).errors), "object_shaped_values_rejected")
	var bulky := _body("body.humanoid_fighter")
	_node(bulky, "arm_r").proportions = {"bulk": 1.3}
	var longer := _body("body.humanoid_fighter")
	_node(longer, "arm_r").proportions = {"length": 1.1}
	var base := _resolved(examples["body.humanoid_fighter"])
	check(_resolved(bulky).gameplay_fingerprint == base.gameplay_fingerprint and _resolved(bulky).fingerprint != base.fingerprint, "visual_proportion_keeps_gameplay_fingerprint")
	check(_resolved(longer).gameplay_fingerprint != base.gameplay_fingerprint, "gameplay_proportion_changes_gameplay_fingerprint")
	var explicit_default := _body("body.humanoid_fighter")
	_node(explicit_default, "arm_r").proportions = {"length": 1}
	check(_resolved(explicit_default).gameplay_fingerprint == base.gameplay_fingerprint, "explicit_default_equals_implicit_default_in_gameplay")

func test_reproducibility() -> void:
	var first := Fixture.run(catalog, builds)
	var other = AnatomyCatalog.new()
	other.load_file()
	var second := Fixture.run(other, builds)
	check(JSON.stringify(first.flow, "\t", true) == JSON.stringify(second.flow, "\t", true), "flow_identical_across_instances")
	check(FileAccess.get_file_as_string(EXAMPLE_FLOW) == JSON.stringify(first.flow, "\t", true) + "\n", "flow_matches_committed_example")
	var resolved := _resolved(examples["body.carapace_brute"])
	var expected: String = resolved.fingerprint
	resolved.erase("fingerprint")
	check(AnatomyCatalog.digest(resolved) == expected, "resolved_fingerprint_reproducible")

## The anatomy core must stay standalone; only the projection may read shared builds.
func test_isolation() -> void:
	var forbidden := ["res://scripts/combat", "res://scripts/characters", "res://scripts/ai", "res://scenes", "courtyard", "worldgen", "CombatState", "Node"]
	for path in CORE_SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		check((forbidden + ["res://scripts/builds"] + LEGACY_SLOTS).all(func(f): return not source.contains(f)), "core_isolated:" + path.get_file())
	var adapter := FileAccess.get_file_as_string("res://scripts/anatomy/build_projection.gd")
	check(forbidden.all(func(f): return not adapter.contains(f)) and not adapter.contains("preload"), "projection_reads_builds_without_combat_or_preload")
	check(catalog.build_catalog_version == builds.version, "anatomy_targets_current_build_catalog")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "playable_entrypoint_selected")
