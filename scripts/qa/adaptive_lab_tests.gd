extends SceneTree
## Checks for the isolated Adaptive Combat Lab (scenes/adaptive_combat_lab.tscn). They
## prove structural invariants of the generation → analysis → affordance → motion →
## rules pipeline and that real input reaches it — not that combat feels good.
##   determinism · labels never change behaviour · structure does · grips on generated
##   graspable regions · hands on grips through every motion · contact = visible
##   geometry · weight/size → timing/reach · unsupported moves never granted · body
##   modification changes grips · player/enemy parity · real input → attacks, chains,
##   heavy, guard, deflect, dodge, posture · negative (rejected) configurations ·
##   isolation from every other scene.
## Run: bash scripts/tooling/test_adaptive_lab.sh [new-empty-dir]

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")
const Bodies = preload("res://scripts/adaptive_lab/body_plans.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const AdaptiveFighter = preload("res://scripts/adaptive_lab/adaptive_fighter.gd")
const AdaptivePose = preload("res://scripts/adaptive_lab/adaptive_pose.gd")
const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const Mesher = preload("res://scripts/adaptive_lab/object_mesher.gd")
const LabInput = preload("res://scripts/adaptive_lab/adaptive_input.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const DT := 1.0 / 60.0
## IK: grip socket within this of the generated grip point (m).
const GRIP_TOLERANCE := 0.02
const MAX_STRETCH := 1.035
## Labels used for swaps include weapon words a name-based system would key on.
const DECOY_LABELS := ["Bone spear of the drowned", "Executioner's greataxe", "Tower shield", "Umbrella", "Rusted sword", ""]
const SHOVEL := 0
const UMBRELLA := 1
const POLE := 2
const ORGANIC := 3
const AWKWARD := 4

var output := "res://artifacts/adaptive-lab"
var passed := 0
var failed := 0
var results := {}
var ids: Array[String] = []
var pilgrim: Dictionary
var corrupted: Dictionary
var marrow: Dictionary
var caps_cache := {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = null) -> void:
	passed += int(ok)
	failed += int(not ok)
	var record := {"check": label, "passed": ok}
	if detail != null:
		record.detail = detail
	results[label] = record
	print(JSON.stringify(record))

func run() -> void:
	MaterialLibrary.set_texture_size(32, 32)
	MaterialLibrary.use_disk_cache = false
	ids = Gen.recipe_ids()
	pilgrim = Bodies.build("pilgrim")
	corrupted = Bodies.build("corrupted")
	marrow = Bodies.build("pilgrim", ["marrow_arm"])
	generation_checks()
	label_checks()
	structure_checks()
	affordance_checks()
	grip_checks()
	motion_checks()
	timing_checks()
	body_mod_checks()
	negative_checks()
	parity_checks()
	rules_checks()
	await scene_input_checks()
	await scene_contact_checks()
	await scene_defence_checks()
	determinism_replay_checks()
	performance_checks()
	isolation_checks()
	finish()

func finish() -> void:
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true) + "\n")
	print(JSON.stringify({"suite": "adaptive_lab", "summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string}))
	quit(0 if failed == 0 else 1)

func descriptor(index: int, seed_index := 0, label := "") -> Dictionary:
	var r := Gen.recipe(ids[index])
	return Gen.generate(ids[index], int(r.seeds[seed_index]), label)

func caps_for(index: int, body: Dictionary, seed_index := 0) -> Dictionary:
	var key := "%d|%d|%s|%s" % [index, seed_index, body.id, ",".join(body.modifications)]
	if not caps_cache.has(key):
		caps_cache[key] = Solver.solve(descriptor(index, seed_index), body)
	return caps_cache[key]

## Capability set as comparable text (Vector3s print deterministically).
static func canon(caps: Dictionary) -> String:
	return JSON.stringify(caps, "", true)

static func signature(act: Variant) -> String:
	if act == null:
		return "none"
	return "%s|%s|%s|%d" % [act.archetype, act.feature.id, act.channel, (act.hold.hands as Array).size()]

# --- Generation ----------------------------------------------------------------------

func generation_checks() -> void:
	var same := true
	var distinct := true
	var structural_only := true
	var detail := {}
	for i in range(ids.size()):
		var seeds: Array = Gen.recipe(ids[i]).seeds
		var prints: Array[String] = []
		for s in range(seeds.size()):
			var a := descriptor(i, s)
			var b := descriptor(i, s)
			same = same and JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
			prints.append(Gen.fingerprint(a))
			for part: Dictionary in a.parts:
				for key: String in part:
					if key in ["actions", "attacks", "moves", "grants", "class", "archetype"]:
						structural_only = false
		var unique := {}
		for f: String in prints:
			unique[f] = true
		distinct = distinct and unique.size() == seeds.size()
		var masses: Array = []
		for s in range(seeds.size()):
			masses.append(snappedf(Analysis.analyse(descriptor(i, s)).mass, 0.001))
		detail[ids[i]] = {"fingerprints": prints, "mass_kg": masses}
	check(same, "generation_same_recipe_and_seed_is_identical")
	check(distinct, "generation_each_seed_gives_a_distinct_structure", detail)
	check(structural_only, "descriptors_carry_structure_not_move_lists")
	var recipe_text := FileAccess.get_file_as_string(Gen.DATA_PATH)
	check(not recipe_text.contains("\"actions\"") and not recipe_text.contains("\"attacks\"") and not recipe_text.contains("\"grants\""),
		"recipe_data_declares_no_moves")

# --- Labels never change behaviour -----------------------------------------------------

func label_checks() -> void:
	var all_same := true
	var detail := {}
	for i in range(ids.size()):
		for body: Dictionary in [pilgrim, marrow]:
			var reference := canon(Solver.solve(descriptor(i), body))
			for label: String in DECOY_LABELS:
				var relabelled := descriptor(i, 0, label)
				var ok := canon(Solver.solve(relabelled, body)) == reference and Gen.fingerprint(relabelled) == Gen.fingerprint(descriptor(i))
				all_same = all_same and ok
				if not ok:
					detail["%s/%s" % [ids[i], label]] = "changed"
	check(all_same, "label_swap_never_changes_capabilities_or_fingerprint", detail if not detail.is_empty() else {"objects": ids.size(), "labels": DECOY_LABELS.size(), "bodies": 2})
	var offenders: Array[String] = []
	for file: String in ["affordance_solver.gd", "object_analysis.gd", "motion_library.gd", "adaptive_fighter.gd", "adaptive_ai.gd", "body_plans.gd", "adaptive_pose.gd"]:
		var text := FileAccess.get_file_as_string("res://scripts/adaptive_lab/" + file)
		# Comments may mention labels; code must not read one.
		for line: String in text.split("\n"):
			var code := line.get_slice("##", 0).get_slice("#", 0)
			if code.contains(".label") or code.contains("\"label\""):
				offenders.append(file)
	check(offenders.is_empty(), "rules_solver_motion_and_ai_never_read_labels", offenders)
	# The live lab: relabelling the player's object keeps the very same capability set.
	var a := Solver.solve(descriptor(UMBRELLA, 0, "Bone spear of the drowned"), pilgrim)
	check(a.heavy != null and a.heavy.archetype == "thrust" and a.heavy.feature.kind == "point" and canon(a) == canon(caps_for(UMBRELLA, pilgrim)),
		"umbrella_called_spear_still_thrusts_with_its_ferrule_point_only")

# --- Structure changes behaviour ----------------------------------------------------

func structure_checks() -> void:
	# Remove the umbrella's ferrule: the only pointed feature is gone, so no pierce remains.
	var d := descriptor(UMBRELLA)
	d.parts = d.parts.filter(func(p: Dictionary) -> bool: return p.id != "ferrule")
	var without := Solver.solve(d, pilgrim)
	var channels: Array = []
	for act: Dictionary in without.light + ([without.heavy] if without.heavy != null else []):
		channels.append(act.channel)
	check(not "pierce" in channels and canon(without) != canon(caps_for(UMBRELLA, pilgrim)), "removing_the_ferrule_removes_every_pierce_attack", channels)
	# Give the pole a sharpened spike in place of one cap: a pierce thrust appears.
	var pole := descriptor(POLE)
	var cap: Dictionary = {}
	for part: Dictionary in pole.parts:
		if part.id == "cap_high":
			cap = part
	var top := Analysis.v(cap.attach)
	pole.parts = pole.parts.filter(func(p: Dictionary) -> bool: return p.id != "cap_high")
	pole.parts.append({"id": "spike", "kind": "spike", "a": Gen.to_array(top), "b": Gen.to_array(top + Vector3(0, 0.22, 0)), "radius": 0.014, "material": "steel"})
	var spear := Solver.solve(pole, pilgrim)
	var pierce := false
	for act: Dictionary in spear.light + ([spear.heavy] if spear.heavy != null else []):
		pierce = pierce or act.channel == "pierce"
	check(pierce, "adding_a_sharp_point_adds_a_pierce_attack", signature(spear.heavy))
	# Dull the shovel's distal edge: its jab stops cutting and becomes blunt.
	var dull := descriptor(SHOVEL)
	for part: Dictionary in dull.parts:
		if part.kind == "plate":
			part.bevel_distal = 0.0
	var blunt := Solver.solve(dull, pilgrim)
	var cut := false
	for act: Dictionary in blunt.light + ([blunt.heavy] if blunt.heavy != null else []):
		cut = cut or act.channel == "cut"
	check(not cut, "dulling_the_plate_edge_removes_cutting", signature(blunt.heavy))

# --- Affordances ---------------------------------------------------------------------

func affordance_checks() -> void:
	var lights := {}
	var heavies := {}
	var detail := {}
	for i in range(ids.size()):
		var caps := caps_for(i, pilgrim)
		var first: String = signature(caps.light[0]) if not (caps.light as Array).is_empty() else "none"
		lights[first] = true
		heavies[signature(caps.heavy)] = true
		detail[ids[i]] = {"light": first, "heavy": signature(caps.heavy), "guard": caps.guard.kind if caps.guard != null else "none"}
	check(lights.size() == ids.size(), "same_light_input_resolves_differently_for_every_structure", detail)
	check(heavies.size() >= 4, "heavy_input_resolves_to_at_least_four_different_actions", heavies.keys())
	var shovel := caps_for(SHOVEL, pilgrim)
	var shovel_pierce := false
	for act: Dictionary in shovel.light + [shovel.heavy]:
		shovel_pierce = shovel_pierce or act.channel == "pierce"
	check(not shovel_pierce and shovel.light[0].feature.kind == "edge", "broad_plate_jabs_with_its_edge_and_never_pierces", signature(shovel.light[0]))
	var umbrella := caps_for(UMBRELLA, pilgrim)
	check(umbrella.guard != null and umbrella.guard.kind == "deploy_cover" and (umbrella.hold.hands as Array).size() == 1,
		"ribbed_canopy_is_held_by_its_handle_and_deploys_as_a_cover", umbrella.guard.kind if umbrella.guard != null else null)
	var pole := caps_for(POLE, pilgrim)
	var chain: Array = pole.light
	var lead: Dictionary = chain[0]
	var rear: Dictionary = chain[1]
	var axis: Vector3 = pole.hold.axis
	var opposite := ((lead.feature.pos as Vector3) - (pole.hold.center as Vector3)).dot(axis) > 0.0 and ((rear.feature.pos as Vector3) - (pole.hold.center as Vector3)).dot(axis) < 0.0
	check(pole.hold.spread and lead.archetype == "alternate" and rear.rear and opposite, "double_ended_pole_spread_grip_alternates_ends",
		{"span": pole.hold.span, "chain": [signature(chain[0]), signature(chain[1]), signature(chain[2])]})
	var organic := caps_for(ORGANIC, pilgrim)
	var organic_parts := {}
	for act: Dictionary in organic.light + [organic.heavy]:
		organic_parts[act.feature.part] = true
	check(organic_parts.has("thorn") or organic_parts.has("knot"), "organic_object_strikes_with_its_grown_features", organic_parts.keys())
	var awkward := caps_for(AWKWARD, pilgrim)
	var only_shove := true
	for act: Dictionary in awkward.light:
		only_shove = only_shove and act.archetype == "shove"
	var roll_reason := false
	for r: Dictionary in awkward.rejections:
		roll_reason = roll_reason or str(r.detail).contains("roll_torque")
	check(awkward.heavy == null and only_shove and roll_reason, "awkward_offset_mass_is_limited_to_shoving", awkward.rejections.slice(0, 4))
	var thrusts_need_alignment := true
	for i in range(ids.size()):
		var caps := caps_for(i, pilgrim)
		for act: Dictionary in caps.light + ([caps.heavy] if caps.heavy != null else []):
			if act.archetype == "thrust":
				var a: Vector3 = act.a_local
				thrusts_need_alignment = thrusts_need_alignment and (act.feature.omni or (act.feature.normal as Vector3).dot(a) >= 0.75)
	check(thrusts_need_alignment, "every_thrust_leads_with_a_forward_facing_feature")

# --- Grips ---------------------------------------------------------------------------

func grip_checks() -> void:
	var worst := 0.0
	var all_graspable := true
	var span_ok := true
	for i in range(ids.size()):
		var d := descriptor(i)
		for body: Dictionary in [pilgrim, corrupted, marrow]:
			var caps := caps_for(i, body)
			if caps.hold == null:
				continue
			var hold: Dictionary = caps.hold
			for hand: String in hold.grips:
				all_graspable = all_graspable and hand in body.hands
				var point: Vector3 = hold.grips[hand]
				var best := INF
				for part: Dictionary in d.parts:
					if Analysis.graspable(part):
						best = minf(best, Analysis.segment_distance(point, Analysis.v(part.a), Analysis.v(part.b)))
				worst = maxf(worst, best)
			if (hold.hands as Array).size() == 2:
				span_ok = span_ok and float(hold.span) <= float(body.max_grip_span) + 0.0001 and float(hold.span) >= float(body.min_grip_span) - 0.0001
	check(worst < 0.0005 and all_graspable, "every_grip_is_on_a_generated_graspable_rod_held_by_an_existing_hand", {"max_off_axis_m": snappedf(worst, 0.00001)})
	check(span_ok, "two_hand_grip_spans_respect_anatomy")
	# Longer arms permit wider two-hand placements on the same pole.
	var pole_d := descriptor(POLE)
	var spans := {}
	for body: Dictionary in [pilgrim, corrupted]:
		var rejected: Array = []
		var holds := Solver._holds(Analysis.analyse(pole_d), body, rejected)
		var widest := 0.0
		for h: Dictionary in holds:
			widest = maxf(widest, float(h.span))
		spans[body.id] = snappedf(widest, 0.001)
	check(float(spans.corrupted) > float(spans.pilgrim), "longer_arms_allow_wider_grips", spans)

# --- Motion: hands on grips, no self-intersection, contact rigidly attached -----------

func motion_checks() -> void:
	var worst_grip := 0.0
	var worst_stretch := 1.0
	var worst_pen := 0.0
	var samples := 0
	for i in range(ids.size()):
		for body: Dictionary in [pilgrim, corrupted, marrow]:
			var caps := caps_for(i, body)
			if caps.hold == null:
				continue
			var solver := AdaptivePose.new(body)
			var actions: Array = caps.light + ([caps.heavy] if caps.heavy != null else [])
			for act: Dictionary in actions:
				var total: float = act.windup + act.active + act.recovery
				for k in range(25):
					var pose := Motion.sample(act, total * k / 24.0, body)
					var result := solver.solve({"pose": pose, "hold": caps.hold, "a_local": act.a_local, "state": "attack"}, DT)
					for hand: String in pose.hands:
						var socket := "grip_r" if hand == "hand_r" else "grip_l"
						var from_rig: Vector3 = Rig.socket_global(result.bones, socket).origin
						worst_grip = maxf(worst_grip, from_rig.distance_to(pose.hands[hand]))
					for side: String in result.stretch:
						worst_stretch = maxf(worst_stretch, float(result.stretch[side]))
					worst_pen = maxf(worst_pen, float(pose.penetration))
					samples += 1
			if caps.guard != null:
				var gp := Motion.guard_pose(caps.guard, body)
				worst_pen = maxf(worst_pen, float(gp.penetration))
	check(worst_grip < GRIP_TOLERANCE and worst_stretch <= MAX_STRETCH, "hands_stay_on_generated_grips_through_every_motion",
		{"max_socket_error_m": snappedf(worst_grip, 0.0001), "max_arm_stretch": snappedf(worst_stretch, 0.0001), "samples": samples})
	check(worst_pen <= Motion.PENETRATION_LIMIT, "validated_motions_keep_objects_out_of_the_wielder", {"max_penetration_m": snappedf(worst_pen, 0.0001)})
	# The hands and the contact feature are one rigid transform of the descriptor.
	var caps := caps_for(SHOVEL, pilgrim)
	var act: Dictionary = caps.light[0]
	var rigid := 0.0
	var base_gap := (act.feature.pos as Vector3).distance_to(caps.hold.grips.hand_r)
	for k in range(20):
		var pose := Motion.sample(act, (act.windup + act.active) * k / 19.0, pilgrim)
		var cap := Motion.contact_capsule(act.feature, pose.object)
		var centre: Vector3 = ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5
		rigid = maxf(rigid, absf(centre.distance_to(pose.hands.hand_r) - base_gap))
	check(rigid < 0.0001, "contact_feature_moves_rigidly_with_the_gripped_object", snappedf(rigid, 0.000001))
	# Distinct trajectories: the light strike's feature path differs per structure.
	var paths: Array = []
	for i in range(ids.size()):
		var c := caps_for(i, pilgrim)
		var a: Dictionary = c.light[0]
		var path: Array = []
		for k in range(8):
			var pose := Motion.sample(a, a.windup + a.active * k / 7.0, pilgrim)
			var cap2 := Motion.contact_capsule(a.feature, pose.object)
			path.append(((cap2[0] as Vector3) + (cap2[1] as Vector3)) * 0.5)
		paths.append(path)
	var min_diff := INF
	for x in range(paths.size()):
		for y in range(x + 1, paths.size()):
			var diff := 0.0
			for k in range(8):
				diff += (paths[x][k] as Vector3).distance_to(paths[y][k])
			min_diff = minf(min_diff, diff / 8.0)
	check(min_diff > 0.1, "light_strike_paths_differ_between_structures", {"min_mean_path_difference_m": snappedf(min_diff, 0.001)})

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")

# --- Weight and dimensions ------------------------------------------------------------

func scaled_pole(cap_scale: float, length_scale: float) -> Dictionary:
	var d := descriptor(POLE)
	for part: Dictionary in d.parts:
		if part.kind == "lump":
			part.radii = Gen.to_array(Analysis.v(part.radii) * cap_scale)
		if part.kind == "rod":
			part.b = Gen.to_array(Analysis.v(part.a) + (Analysis.v(part.b) - Analysis.v(part.a)) * length_scale)
	if length_scale != 1.0:
		for part: Dictionary in d.parts:
			if part.id == "cap_high":
				var rod: Dictionary = d.parts[0]
				var shift := Analysis.v(rod.b) - Analysis.v(part.attach)
				part.center = Gen.to_array(Analysis.v(part.center) + shift)
				part.attach = rod.b
	return d

func timing_checks() -> void:
	var light := Solver.solve(scaled_pole(1.0, 1.0), pilgrim)
	var heavy := Solver.solve(scaled_pole(1.2, 1.0), pilgrim)
	# Same hold, same archetype and feature: only the measured mass and inertia differ.
	var hold: Dictionary = light.hold
	var light_an := Analysis.analyse(scaled_pole(1.0, 1.0))
	var heavy_an := Analysis.analyse(scaled_pole(1.2, 1.0))
	var before := {}
	for act: Dictionary in Solver._candidates(hold, light_an, pilgrim).actions:
		before[act.id] = act
	var compared := {}
	var slower := true
	for act: Dictionary in Solver._candidates(hold, heavy_an, pilgrim).actions:
		if before.has(act.id) and act.archetype != "shove":
			var a: Dictionary = before[act.id]
			compared[act.id] = {"windup": [a.windup, act.windup], "recovery": [a.recovery, act.recovery]}
			slower = slower and act.windup > a.windup and act.recovery > a.recovery
	check(float(heavy.mass) > float(light.mass) and compared.size() >= 2 and slower, "heavier_ends_slow_windup_and_recovery",
		{"mass": [light.mass, heavy.mass], "same_actions": compared})
	var short := Solver.solve(descriptor(SHOVEL), pilgrim)
	var umbrella := caps_for(UMBRELLA, pilgrim)
	check(float(short.light[0].load) != float(umbrella.light[0].load), "different_structures_load_the_body_differently",
		{"shovel_load": short.light[0].load, "umbrella_load": umbrella.light[0].load})
	var longer := Solver.solve(scaled_pole(1.0, 1.15), pilgrim)
	var reach_a: float = light.heavy.get("reach", 0.0)
	var reach_b: float = longer.heavy.get("reach", 0.0)
	check(float(longer.extent) > float(light.extent) and reach_b > reach_a, "longer_object_reaches_further", {"extent": [light.extent, longer.extent], "heavy_reach": [reach_a, reach_b]})

# --- Body modification ---------------------------------------------------------------

func body_mod_checks() -> void:
	var detail := {}
	var no_left := true
	for i in range(ids.size()):
		var caps := caps_for(i, marrow)
		if caps.hold != null:
			no_left = no_left and not "hand_l" in caps.hold.hands
		detail[ids[i]] = {"two_hands": signature(caps_for(i, pilgrim).light[0]) if not (caps_for(i, pilgrim).light as Array).is_empty() else "none",
			"marrow_arm": signature(caps.light[0]) if not (caps.light as Array).is_empty() else "none"}
	check(no_left, "handless_marrow_arm_never_grips", detail)
	var pole := caps_for(POLE, marrow)
	var reason := false
	for r: Dictionary in pole.rejections:
		reason = reason or r.code == "two_hand_requires_missing_hand"
	check(pole.light[0].archetype != "alternate" and reason, "marrow_arm_turns_the_pole_from_alternating_ends_to_one_hand_thrusts", signature(pole.light[0]))
	var kiln := caps_for(AWKWARD, marrow)
	check(not kiln.usable and kiln.hold == null and (kiln.light as Array).is_empty() and kiln.heavy == null and kiln.guard == null,
		"marrow_arm_cannot_wield_the_offset_mass_at_all", kiln.rejections)
	var shovel_two := caps_for(SHOVEL, pilgrim)
	var shovel_one := caps_for(SHOVEL, marrow)
	check(shovel_one.light[0].windup > shovel_two.light[0].windup, "one_handed_grip_on_the_same_shovel_is_slower",
		{"two_hands": shovel_two.light[0].windup, "one_hand": shovel_one.light[0].windup})

# --- Negative configurations ----------------------------------------------------------

func negative_checks() -> void:
	var plate_only := {"schema": Gen.SCHEMA, "generator_version": 1, "recipe": "test.plate_only", "seed": 1, "label": "Sword",
		"parts": [{"id": "slab", "kind": "plate", "center": [0, 0.2, 0], "u": [0, 1, 0], "v": [1, 0, 0], "n": [0, 0, 1], "length": 0.4, "width": 0.3,
			"thickness": 0.01, "bevel_distal": 1.0, "bevel_lateral": 1.0, "material": "steel", "attach": [0, 0, 0]}]}
	var caps := Solver.solve(plate_only, pilgrim)
	check(not caps.usable and _has_code(caps, "no_graspable_region"), "no_graspable_region_is_rejected_even_if_named_sword", caps.rejections)
	var thick := {"schema": Gen.SCHEMA, "generator_version": 1, "recipe": "test.thick_log", "seed": 1, "label": "Spear",
		"parts": [{"id": "log", "kind": "rod", "a": [0, 0, 0], "b": [0, 1.4, 0], "radius": 0.09, "material": "hardwood"}]}
	caps = Solver.solve(thick, pilgrim)
	check(not caps.usable and _has_code(caps, "no_graspable_region"), "too_thick_to_grasp_is_rejected", caps.rejections)
	var anvil := {"schema": Gen.SCHEMA, "generator_version": 1, "recipe": "test.anvil", "seed": 1, "label": "Hammer",
		"parts": [{"id": "handle", "kind": "rod", "a": [0, 0, 0], "b": [0, 0.5, 0], "radius": 0.018, "material": "hardwood"},
			{"id": "block", "kind": "lump", "center": [0, 0.75, 0], "axis": [0, 1, 0], "radii": [0.2, 0.2, 0.2], "material": "forged_iron", "attach": [0, 0.5, 0]}]}
	caps = Solver.solve(anvil, pilgrim)
	check(not caps.usable and (_has_code(caps, "mass_exceeds_two_hands") or _has_code(caps, "static_torque_exceeds_two_hands")),
		"too_much_mass_for_the_anatomy_is_rejected", {"mass": caps.mass, "rejections": caps.rejections})
	var rod := {"schema": Gen.SCHEMA, "generator_version": 1, "recipe": "test.bare_rod", "seed": 1, "label": "Spear",
		"parts": [{"id": "rod", "kind": "rod", "a": [0, 0, 0], "b": [0, 0.3, 0], "radius": 0.016, "material": "hardwood"}]}
	caps = Solver.solve(rod, pilgrim)
	var pierce := false
	for act: Dictionary in caps.light + ([caps.heavy] if caps.heavy != null else []):
		pierce = pierce or act.channel != "blunt"
	check(not pierce, "a_blunt_stick_named_spear_gets_no_pierce_or_cut", [signature(caps.heavy)])
	# Motion validation rejects an action that would pass the object through the body.
	var pole := caps_for(POLE, pilgrim)
	var bad: Dictionary = pole.light[0].duplicate()
	var hold: Dictionary = (bad.hold as Dictionary).duplicate()
	hold.probes = [[hold.center, 0.05]] + (hold.probes as Array)
	var pinned := {}
	for hand: String in hold.grips:
		pinned[hand] = (hold.grips[hand] as Vector3) + (hold.axis as Vector3) * 5.0
	hold.grips = pinned
	bad.hold = hold
	var verdict := Motion.validate(bad, pilgrim)
	check(not verdict.ok, "motion_validation_rejects_unreachable_grips", {"reach_excess": snappedf(verdict.reach_excess, 0.001)})

func _has_code(caps: Dictionary, code: String) -> bool:
	for r: Dictionary in caps.rejections:
		if r.code == code:
			return true
	return false

# --- Parity --------------------------------------------------------------------------

func parity_checks() -> void:
	var same := true
	for i in range(ids.size()):
		var as_player := AdaptiveFighter.new("player")
		var as_enemy := AdaptiveFighter.new("soul")
		as_player.equip(descriptor(i), corrupted)
		as_enemy.equip(descriptor(i), corrupted)
		same = same and canon(as_player.caps) == canon(as_enemy.caps)
	check(same, "player_and_enemy_get_identical_capabilities_for_the_same_object_and_body")
	var soul := AdaptiveFighter.new("soul")
	soul.equip(descriptor(AWKWARD), corrupted)
	var foe := AdaptiveFighter.new("player")
	foe.equip(descriptor(SHOVEL), pilgrim)
	foe.position = Vector3(0, 0, 1.0)
	var ai := AI.new(5)
	var heavy_attacks := 0
	var unsupported := 0
	for t in range(60 * 30):
		var intent := ai.intent(soul, foe, DT)
		intent.heavy = intent.heavy or t % 90 == 0
		soul.step(intent, foe.position, DT)
		foe.step({}, soul.position, DT)
		if soul.state == "attack" and soul.action.heavy:
			heavy_attacks += 1
	for e: Dictionary in soul.events:
		if e.kind == "heavy_unsupported":
			unsupported += 1
	check(heavy_attacks == 0 and unsupported > 0, "enemy_requests_for_unsupported_heavy_are_refused_by_the_same_rules", {"refused": unsupported})

# --- Rules (deterministic, no scene) --------------------------------------------------

func duel(player_index: int, soul_index: int) -> Array:
	var a := AdaptiveFighter.new("player")
	var b := AdaptiveFighter.new("soul")
	a.equip(descriptor(player_index), pilgrim)
	b.equip(descriptor(soul_index), corrupted)
	a.position = Vector3(0, 0, 1.6)
	b.position = Vector3(0, 0, -1.6)
	b.yaw = PI
	return [a, b]

func run_ticks(a: AdaptiveFighter, b: AdaptiveFighter, ticks: int, ia: Callable, ib: Callable) -> Array:
	var contacts: Array = []
	for t in range(ticks):
		a.step(ia.call(t), b.position, DT)
		b.step(ib.call(t), a.position, DT)
		AdaptiveFighter.separate(a, b)
		for pair: Array in [[a, b], [b, a]]:
			var r := AdaptiveFighter.resolve(pair[0], pair[1], DT)
			if not r.is_empty():
				contacts.append(r)
	return contacts

func idle(_t: int) -> Dictionary:
	return {}

func rules_checks() -> void:
	# Damage only inside the active window, for every object's light and heavy.
	var outside := 0
	var hits := 0
	var detail := {}
	for i in range(ids.size()):
		var caps := caps_for(i, pilgrim)
		for kind: String in ["light", "heavy"]:
			var act: Variant = caps.light[0] if kind == "light" and not (caps.light as Array).is_empty() else caps.heavy
			if act == null:
				continue
			var pair := duel(i, SHOVEL)
			var a: AdaptiveFighter = pair[0]
			var b: AdaptiveFighter = pair[1]
			b.position = a.position + Vector3(0, 0, -minf(float(act.reach) - 0.15, 1.6))
			var press := func(t: int) -> Dictionary: return {kind: t == 0}
			var contacts := run_ticks(a, b, 120, press, idle)
			for c: Dictionary in contacts:
				if c.attacker == "player":
					hits += 1
					if float(c.rule_time) < float(act.windup) - 0.0001 or float(c.rule_time) > float(act.windup) + float(act.active) + 0.0001:
						outside += 1
			detail["%s/%s" % [ids[i], kind]] = contacts.size()
	check(outside == 0 and hits >= 8, "contact_only_inside_rule_active_windows_and_every_attack_connects_in_reach", {"hits": hits, "outside": outside, "per_attack": detail})
	# Guard / deflect / block / posture break / punish / dodge.
	var outcomes := {}
	for mode: String in ["none", "early_guard", "fresh_deflect", "dodge"]:
		var pair := duel(UMBRELLA, SHOVEL)
		var a: AdaptiveFighter = pair[0]
		var b: AdaptiveFighter = pair[1]
		b.position = a.position + Vector3(0, 0, -1.1)
		var act: Dictionary = b.caps.light[0]
		var press_at := int(round((float(act.windup) - 0.05) / DT))
		var defend := func(t: int) -> Dictionary:
			match mode:
				"early_guard":
					return {"guard": true}
				"fresh_deflect":
					return {"guard": t >= press_at}
				"dodge":
					return {"dodge": t == press_at - 2, "move": Vector3.RIGHT}
			return {}
		var attack := func(t: int) -> Dictionary: return {"light": t == 0}
		var contacts := run_ticks(a, b, 60, defend, attack)
		outcomes[mode] = contacts[0].outcome if not contacts.is_empty() else ("evaded" if b.events.any(func(e: Dictionary) -> bool: return e.kind == "evaded") else "none")
	check(outcomes.none == "hit" and outcomes.early_guard == "blocked" and outcomes.fresh_deflect == "deflected" and outcomes.dodge == "evaded",
		"hit_block_deflect_and_dodge_resolve_from_timing", outcomes)
	# Posture: repeated blocked heavies break the guard; the next hit is a punish.
	var pair := duel(POLE, SHOVEL)
	var a2: AdaptiveFighter = pair[0]
	var b2: AdaptiveFighter = pair[1]
	b2.position = a2.position + Vector3(0, 0, -1.2)
	var broke_at := -1
	var heavy_period := int(ceil((float(b2.caps.heavy.windup) + float(b2.caps.heavy.active) + float(b2.caps.heavy.recovery)) / DT)) + 2
	var contacts2 := run_ticks(a2, b2, heavy_period * 9, func(t: int) -> Dictionary: return {"guard": a2.state != "broken"},
		func(t: int) -> Dictionary: return {"heavy": t % heavy_period == 0 and a2.state != "broken", "light": a2.state == "broken" and t % 6 == 0})
	var kinds: Array = []
	for c: Dictionary in contacts2:
		kinds.append(c.outcome)
	for e: Dictionary in a2.events:
		if e.kind == "posture_broken" and broke_at < 0:
			broke_at = kinds.size()
	check(kinds.has("blocked") and a2.events.any(func(e: Dictionary) -> bool: return e.kind == "posture_broken") and kinds.has("punish"),
		"blocked_heavies_break_posture_and_open_a_punish", kinds)

# --- Scene: real input ------------------------------------------------------------------

func make_lab(player_recipe: int, soul_recipe: int, player_marrow := false) -> Node:
	var lab: Node = load("res://scenes/adaptive_combat_lab.tscn").instantiate()
	lab.loadout.player.recipe = player_recipe
	lab.loadout.player.marrow = player_marrow
	lab.loadout.soul.recipe = soul_recipe
	root.add_child(lab)
	await process_frame
	lab.ai.mode = "passive"
	return lab

func press(action: String, pressed: bool) -> void:
	var event: InputEvent = null
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventMouseButton:
			event = e.duplicate()
	if event == null:
		event = InputMap.action_get_events(action)[0].duplicate()
	if event is InputEventMouseButton:
		(event as InputEventMouseButton).pressed = pressed
	else:
		(event as InputEventKey).pressed = pressed
	Input.parse_input_event(event)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func tap(action: String) -> void:
	press(action, true)
	await physics_frame
	await physics_frame
	press(action, false)

func scene_input_checks() -> void:
	var detail := {}
	var started := {}
	var latency_ok := true
	for i in range(ids.size()):
		var lab: Node = await make_lab(i, SHOVEL)
		await frames(3)
		press("alab_light", true)
		var ticks := 0
		while lab.player.state != "attack" and ticks < 6:
			await physics_frame
			ticks += 1
		press("alab_light", false)
		latency_ok = latency_ok and ticks <= 2
		var first: String = lab.player.action.get("id", "none") if lab.player.state == "attack" else "none"
		started[first] = true
		var expected: String = lab.player.caps.light[0].id if not (lab.player.caps.light as Array).is_empty() else "none"
		detail[ids[i]] = {"started": first, "expected": expected, "ticks": ticks}
		latency_ok = latency_ok and first == expected
		lab.queue_free()
		await process_frame
	check(latency_ok and started.size() == ids.size(), "real_mouse_press_starts_the_object_specific_light_attack_within_two_ticks", detail)
	# Chain: three presses on the pole → lead end, rear end, lead end.
	var lab: Node = await make_lab(POLE, SHOVEL)
	await frames(3)
	# Press again late in each strike, the way a player chains.
	for k in range(3):
		var serial: int = lab.player.attack_serial
		await tap("alab_light")
		var waited := 0
		while waited < 90 and lab.player.attack_serial == serial:
			await physics_frame
			waited += 1
		while waited < 180 and lab.player.state == "attack" and lab.player.state_time < float(lab.player.action.windup) + float(lab.player.action.active):
			await physics_frame
			waited += 1
	await frames(60)
	var chain: Array = []
	for e: Dictionary in lab.player.events:
		if e.kind == "attack":
			chain.append("%s:%d" % [e.detail.action, e.detail.index])
	check(chain.size() == 3 and str(chain[1]).contains(":rear") and not str(chain[0]).contains(":rear"), "repeated_light_presses_chain_through_alternating_ends", chain)
	# Heavy via the middle mouse button; guard via the right button.
	await tap("alab_heavy")
	await frames(2)
	var heavy_started: bool = lab.player.state == "attack" and lab.player.action.heavy
	await frames(90)
	press("alab_guard", true)
	await frames(4)
	var guarding: bool = lab.player.state == "guard"
	press("alab_guard", false)
	await frames(2)
	check(heavy_started and guarding, "middle_button_heavy_and_right_button_guard_reach_the_rules", {"heavy": heavy_started, "guard": guarding})
	lab.queue_free()
	await process_frame
	# Unsupported heavy: the kiln weight logs a refusal and does nothing.
	lab = await make_lab(AWKWARD, SHOVEL)
	await frames(3)
	await tap("alab_heavy")
	await frames(3)
	var refused: bool = lab.player.events.any(func(e: Dictionary) -> bool: return e.kind == "heavy_unsupported")
	check(refused and lab.player.state == "idle", "heavy_input_on_an_object_without_a_heavy_does_nothing_and_says_why", lab.player.events.slice(-1))
	# Relabel key in the live scene keeps the capability set.
	var before := canon(lab.player.caps)
	lab.relabel("player")
	var relabelled: String = lab.player.descriptor.label
	check(canon(lab.player.caps) == before and relabelled != Gen.recipe(ids[AWKWARD]).label, "live_relabel_keeps_capabilities", relabelled)
	lab.queue_free()
	await process_frame
	# Body modification toggle in the live scene changes the hold.
	lab = await make_lab(POLE, SHOVEL)
	var two: int = (lab.player.caps.hold.hands as Array).size()
	lab.toggle_marrow("player")
	var one: int = (lab.player.caps.hold.hands as Array).size()
	check(two == 2 and one == 1 and lab.player_actor.character.get_node_or_null("Skeleton3D/Module_marrow_arm") != null,
		"live_marrow_arm_toggle_rebuilds_body_and_regrips", {"hands_before": two, "hands_after": one})
	lab.queue_free()
	await process_frame

# --- Scene: contact agrees with the drawn object ---------------------------------------

func scene_contact_checks() -> void:
	var worst := 0.0
	var worst_hand := 0.0
	var inside_mesh := true
	var hits := 0
	for i in range(ids.size()):
		var lab: Node = await make_lab(i, SHOVEL)
		lab.paused = true
		var act: Variant = lab.player.caps.light[0] if not (lab.player.caps.light as Array).is_empty() else null
		if act == null:
			lab.queue_free()
			continue
		lab.soul.position = lab.player.position + Vector3(0, 0, -minf(float(act.reach) - 0.15, 1.6))
		var n := 0
		lab.player_driver = func(_l: Node) -> Dictionary:
			n += 1
			return {"light": n == 1}
		var mesh_aabb := AABB()
		for k in range(80):
			lab.step(DT)
			await process_frame
			var events: Array = lab.player.events.filter(func(e: Dictionary) -> bool: return e.kind == "contact")
			if lab.player.state == "attack":
				# Drawn object node vs rules: feature position and grips.
				var drawn: Transform3D = lab.player_actor.object_node.global_transform
				var rules: Transform3D = lab.player.xform() * (lab.player.pose.object as Transform3D)
				worst = maxf(worst, (drawn * (act.feature.pos as Vector3)).distance_to(rules * (act.feature.pos as Vector3)))
				# The capsule the rules sweep for damage, centred on the drawn feature.
				var cap: Array = lab.player.contact_at(lab.player.state_time)
				var centre: Vector3 = ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5
				worst = maxf(worst, centre.distance_to(drawn * (act.feature.pos as Vector3)))
				var bones: Dictionary = lab.player_actor.last_result.bones
				for hand: String in lab.player.pose.hands:
					var socket := "grip_r" if hand == "hand_r" else "grip_l"
					var drawn_grip: Vector3 = lab.player_actor.global_transform * Rig.socket_global(bones, socket).origin
					worst_hand = maxf(worst_hand, drawn_grip.distance_to(rules * (lab.player.caps.hold.grips[hand] as Vector3)))
			if not events.is_empty():
				hits += 1
				var structure: MeshInstance3D = lab.player_actor.object_node.get_node("Structure")
				mesh_aabb = structure.get_aabb().grow(float(act.feature.radius))
				inside_mesh = inside_mesh and mesh_aabb.has_point(act.feature.pos)
				break
		lab.queue_free()
		await process_frame
	check(worst < 0.0005 and hits >= 4 and inside_mesh, "drawn_object_feature_equals_rules_contact_feature_at_every_frame",
		{"max_error_m": snappedf(worst, 0.000001), "hits": hits, "feature_inside_drawn_mesh": inside_mesh})
	check(worst_hand < GRIP_TOLERANCE, "drawn_fists_hold_the_rules_grip_points", {"max_error_m": snappedf(worst_hand, 0.0001)})

# --- Scene: AI defence and canopy ------------------------------------------------------

func scene_defence_checks() -> void:
	var lab: Node = await make_lab(UMBRELLA, SHOVEL)
	lab.paused = true
	lab.player_driver = func(_l: Node) -> Dictionary: return {"guard": true}
	for k in range(20):
		lab.step(DT)
		await process_frame
	var canopy: Node3D = lab.player_actor.canopy
	var open: MeshInstance3D = canopy.get_node("Open")
	var radius: float = float(canopy.get_meta("open_radius")) * open.scale.x
	check(lab.player.state == "guard" and open.visible and absf(radius - float(canopy.get_meta("open_radius"))) < 0.001,
		"umbrella_guard_visibly_deploys_its_generated_canopy", {"drawn_radius": snappedf(radius, 0.001)})
	lab.queue_free()
	await process_frame

# --- Determinism of whole duels ----------------------------------------------------------

func ai_duel_log(seed: int) -> String:
	var pair := duel(POLE, ORGANIC)
	var a: AdaptiveFighter = pair[0]
	var b: AdaptiveFighter = pair[1]
	var ai_a := AI.new(seed)
	var ai_b := AI.new(seed + 1)
	run_ticks(a, b, 60 * 20, func(_t: int) -> Dictionary: return ai_a.intent(a, b, DT), func(_t: int) -> Dictionary: return ai_b.intent(b, a, DT))
	return JSON.stringify(a.events + b.events, "", true) + "|%.6f|%.6f" % [a.hp, b.hp]

func determinism_replay_checks() -> void:
	var first := ai_duel_log(11)
	var second := ai_duel_log(11)
	var other := ai_duel_log(12)
	check(first == second and first != other, "ai_duels_replay_identically_from_the_same_seed", {"log_sha": first.sha256_text().substr(0, 12)})
	var file := FileAccess.open(output.path_join("duel_log.json"), FileAccess.WRITE)
	file.store_string(first + "\n")

# --- Performance (llvmpipe/cloud numbers, scoped) -----------------------------------------

func performance_checks() -> void:
	var worst_solve := 0
	for i in range(ids.size()):
		var t0 := Time.get_ticks_usec()
		Solver.solve(descriptor(i, 1), pilgrim)
		worst_solve = maxi(worst_solve, Time.get_ticks_usec() - t0)
	var pair := duel(POLE, SHOVEL)
	var a: AdaptiveFighter = pair[0]
	var b: AdaptiveFighter = pair[1]
	var ai_a := AI.new(1)
	var ai_b := AI.new(2)
	var t1 := Time.get_ticks_usec()
	run_ticks(a, b, 600, func(_t: int) -> Dictionary: return ai_a.intent(a, b, DT), func(_t: int) -> Dictionary: return ai_b.intent(b, a, DT))
	var per_tick := float(Time.get_ticks_usec() - t1) / 600.0
	# Timings vary run to run, so they go to metrics.json, not results.json (replayed).
	var metrics := {"worst_solve_ms": worst_solve / 1000, "rules_tick_us_two_fighters": snappedf(per_tick, 0.1),
		"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name()}
	print(JSON.stringify({"metrics": metrics}))
	var file := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t", true) + "\n")
	check(worst_solve < 3000000 and per_tick < 4000.0, "solver_and_rules_fit_a_lab_budget")

# --- Isolation ---------------------------------------------------------------------------

func isolation_checks() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "default_launch_scene_unchanged")
	var offenders: Array[String] = []
	for dir_path: String in ["res://scripts", "res://scenes"]:
		offenders.append_array(_referencing(dir_path))
	check(offenders.is_empty(), "nothing_outside_the_lab_references_it", offenders)
	var lab_text := ""
	for file: String in DirAccess.get_files_at("res://scripts/adaptive_lab"):
		if file.ends_with(".gd"):
			lab_text += FileAccess.get_file_as_string("res://scripts/adaptive_lab".path_join(file))
	check(not lab_text.contains("melee" + "_lab") and not lab_text.contains("res://scripts/combat") and not lab_text.contains("directional_expedition"),
		"lab_reuses_only_the_showcase_rig_and_materials")

func _referencing(path: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(path):
		var full := path.path_join(file)
		if full.begins_with("res://scripts/adaptive_lab") or full.begins_with("res://scripts/qa/adaptive_lab_") or full == "res://scenes/adaptive_combat_lab.tscn":
			continue
		if (file.ends_with(".gd") or file.ends_with(".tscn")) and FileAccess.get_file_as_string(full).contains("adaptive_"):
			found.append(full)
	for sub: String in DirAccess.get_directories_at(path):
		found.append_array(_referencing(path.path_join(sub)))
	return found
