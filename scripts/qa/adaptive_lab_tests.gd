extends SceneTree
## Checks for the isolated Adaptive Combat Lab 2 (scenes/adaptive_combat_lab.tscn).
## They prove structural invariants of the import → analysis → affordance → motion →
## rules → presentation pipeline on the Research Lab's real exported objects, and that
## real input reaches it — not that combat feels good. Groups:
##   1 Lab fixture ingestion & provenance   2 structural & grip mapping
##   3 name/label/assembly invariance       4 geometry → different legal attacks
##   5 same inputs → different combos      6 grip IK & contact-path agreement
##   7 registered hits & legitimate misses  8 camera & lock-on
##   9 clean default HUD                   10 body modification benefit & drawback
##  11 player/enemy parity                 12 determinism & performance
##  13 (Web export: runner) · v0 comparison generator · isolation
## Run: bash scripts/tooling/test_adaptive_lab.sh [new-empty-dir]

const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const StrictJson = preload("res://scripts/adaptive_lab/strict_json.gd")
const LabAnalysis = preload("res://scripts/adaptive_lab/lab_analysis.gd")
const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Bodies = preload("res://scripts/adaptive_lab/body_plans.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const AdaptiveFighter = preload("res://scripts/adaptive_lab/adaptive_fighter.gd")
const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const LabMesher = preload("res://scripts/adaptive_lab/lab_mesher.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const DT := 1.0 / 60.0
const GRIP_TOLERANCE := 0.02
const MAX_STRETCH := 1.035
const DECOY_NAMES := ["Bone spear of the drowned", "Executioner's greataxe", "Tower shield", "Umbrella", "Shovel", "Rusted sword"]
const UMBRELLA := "objects/umbrella.json"
const SHOVEL := "objects/shovel.json"
const POLE := "objects/double-ended.json"
const ORGANIC := "objects/organic.json"
const HINGED := "objects/hinged.json"
const AWKWARD := "objects/awkward.json"
## Expected rejection reason (substring) per invalid Lab fixture.
const INVALID := {"invalid/forged-mass.json": "physical metadata", "invalid/forged-provenance.json": "provenance",
	"invalid/forged-recipe-with-valid-hash.json": "Lab-verified", "invalid/missing-material.json": "material",
	"invalid/missing-parent.json": "parent", "invalid/numeric-seed.json": "decimal string", "invalid/reversed-grip.json": "interval",
	"invalid/unknown-field.json": "unknown field", "invalid/unknown-version.json": "schema_version"}

var output := "res://artifacts/adaptive-lab"
var passed := 0
var failed := 0
var results := {}
var bundle: Dictionary
var paths: Array[String] = []
var pilgrim: Dictionary
var corrupted: Dictionary
var grafted: Dictionary
var caps_cache := {}
var timings := {}

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
	var t0 := Time.get_ticks_usec()
	bundle = Imp.load_bundle()
	timings.bundle_import_ms = (Time.get_ticks_usec() - t0) / 1000.0
	paths = Imp.accepted_paths()
	pilgrim = Bodies.build("pilgrim")
	corrupted = Bodies.build("corrupted")
	grafted = Bodies.build("pilgrim", ["marrow_graft"])
	ingestion_checks()
	mapping_checks()
	invariance_checks()
	geometry_checks()
	await combo_checks()
	motion_checks()
	await scene_contact_checks()
	rules_checks()
	await camera_checks()
	await hud_checks()
	body_mod_checks()
	parity_checks()
	v0_comparison_checks()
	determinism_checks()
	performance_checks()
	isolation_checks()
	finish()

func finish() -> void:
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true) + "\n")
	print(JSON.stringify({"suite": "adaptive_lab", "summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string}))
	quit(0 if failed == 0 else 1)

func obj(path: String) -> Dictionary:
	return bundle.objects[path]

func caps_for(path: String, body: Dictionary) -> Dictionary:
	var key := "%s|%s|%s" % [path, body.id, ",".join(body.modifications)]
	if not caps_cache.has(key):
		var t0 := Time.get_ticks_usec()
		caps_cache[key] = Solver.solve(obj(path), body)
		timings["solve_ms:" + key] = (Time.get_ticks_usec() - t0) / 1000.0
	return caps_cache[key]

## Capability set as comparable text (Vector3s print deterministically).
static func canon(caps: Dictionary) -> String:
	var copy := caps.duplicate(true)
	copy.erase("object_fingerprint")
	return JSON.stringify(copy, "", true)

static func signature(act: Variant) -> String:
	if act == null:
		return "none"
	return "%s|%s|%s" % [act.archetype, act.feature.kind, act.channel]

static func move_set(caps: Dictionary) -> String:
	var parts: Array[String] = []
	for act: Dictionary in caps.light:
		parts.append(signature(act))
	parts.append("H:" + signature(caps.heavy))
	parts.append("G:" + (str(caps.guard.kind) if caps.guard != null else "none"))
	return " > ".join(parts)

# --- 1. Ingestion and provenance ---------------------------------------------------------

func ingestion_checks() -> void:
	var p := Imp.pin()
	var manifest_sha := Imp.sha256_bytes(FileAccess.get_file_as_bytes(Imp.bundle_path("manifest.json")))
	check(bundle.ok and manifest_sha == p.manifest_sha256 and p.source_merge_commit == "64bc5124d7307a8e010212c7f686e1a8065b0cbe"
		and p.contract == "lab.boneshed.object_export.v1", "bundle_manifest_matches_the_pinned_lab_commit_and_checksum",
		{"manifest_sha256": manifest_sha, "lab_commit": p.source_merge_commit, "errors": bundle.errors})
	# Every manifest entry's raw bytes match; tampering one byte is caught.
	var manifest: Dictionary = StrictJson.decode(FileAccess.get_file_as_string(Imp.bundle_path("manifest.json"))).value
	var all_match := true
	for entry: Dictionary in manifest.files + manifest.support:
		all_match = all_match and Imp.sha256_bytes(FileAccess.get_file_as_bytes(Imp.bundle_path(entry.path))) == entry.sha256
	var tampered := Imp.import_file("objects/shovel.json", "0".repeat(64))
	check(all_match and (manifest.files as Array).size() == 15 and not tampered.ok and str(tampered.errors).contains("checksum"),
		"every_bundle_file_matches_its_manifest_checksum_and_tampering_is_rejected", {"files": (manifest.files as Array).size()})
	# Six accepted (all `accept` entries), nine rejected for the reason the Lab names.
	var accepted_ok := true
	for path: String in bundle.order:
		var expect: String = bundle.expectations[path]
		accepted_ok = accepted_ok and (expect == "accept") == bundle.objects.has(path)
	var reasons := {}
	var reasons_ok := true
	for path: String in INVALID:
		var errors: Array = bundle.rejected.get(path, [])
		reasons[path] = errors
		reasons_ok = reasons_ok and str(errors).contains(INVALID[path])
	check(accepted_ok and paths.size() == 6 and bundle.rejected.size() == 9 and reasons_ok,
		"six_lab_objects_accepted_and_nine_invalid_exports_rejected_for_their_reason", reasons)
	# Native digest and physical block equal the Lab's (recomputed, not trusted).
	var digests := {}
	var digest_ok := true
	var physical_ok := true
	for path: String in paths:
		var text := FileAccess.get_file_as_string(Imp.bundle_path(path))
		var record: Dictionary = StrictJson.decode(text).value
		var hydrated: Dictionary = (record.descriptor as Dictionary).duplicate(true)
		hydrated.recipe.seed = str(hydrated.recipe.seed).to_int()
		var mine := Imp.sha256_text(StrictJson.canonical(hydrated))
		digests[path] = mine
		digest_ok = digest_ok and mine == record.descriptor_sha256
		physical_ok = physical_ok and StrictJson.canonical(Imp.physical_properties(record.descriptor)) == StrictJson.canonical(record.physical)
	check(digest_ok, "game_recomputes_the_lab_descriptor_digest_exactly", digests)
	check(physical_ok, "game_recomputes_the_lab_physical_block_exactly")
	# Identity and provenance preserved; nothing truncated.
	var keep := true
	var detail := {}
	for path: String in paths:
		var o := obj(path)
		var record: Dictionary = StrictJson.decode(FileAccess.get_file_as_string(Imp.bundle_path(path))).value
		keep = keep and o.id == record.descriptor.id and o.seed_text == "20261022" and o.seed == 20261022 and o.revision == 1 \
			and o.source.file_sha256 == Imp.sha256_bytes(FileAccess.get_file_as_bytes(Imp.bundle_path(path))) \
			and StrictJson.canonical(o.original) == StrictJson.canonical(record) and o.provenance.generator_source_commit == p.generator_source_commit \
			and o.physical.inertia_proxy_text.xx == record.physical.inertia_proxy_g_mm2.xx
		detail[path] = {"id": str(o.id).substr(0, 40), "assembly": o.assembly}
	check(keep, "ids_seeds_revisions_provenance_and_original_bytes_are_preserved", detail)
	# Strict decoder: exact 64-bit integers, duplicate keys and out-of-range values refused.
	var max_seed := StrictJson.decode("{\"s\":9223372036854775807}")
	var over := StrictJson.decode("{\"s\":9223372036854775808}")
	var dup := StrictJson.decode("{\"a\":1,\"a\":2}")
	var flt := StrictJson.decode("{\"a\":1.5}")
	check(max_seed.ok and max_seed.value.s == 9223372036854775807 and not over.ok and not dup.ok and flt.ok and flt.has_float,
		"strict_decoder_keeps_64_bit_integers_and_rejects_duplicates_and_overflow")
	# Edited geometry with a stale digest is refused; so is a renamed record.
	var text := FileAccess.get_file_as_string(Imp.bundle_path(SHOVEL))
	var edited := Imp.import_text(text.replace("\"mass_g\": 1291", "\"mass_g\": 1290"))
	var renamed := Imp.import_text(text.replace("\"name\": \"Anonymous assembly\"", "\"name\": \"Great Shovel\""))
	check(not edited.ok and not renamed.ok and str(renamed.errors).contains("digest"), "hand_edited_or_renamed_exports_fail_verification",
		{"edited": edited.errors, "renamed": renamed.errors})
	# Support classification: what is exact and what is approximated, never dropped.
	var statuses := {}
	for path: String in paths:
		for note: Dictionary in obj(path).support:
			statuses["%s %s" % [path.get_file(), note.feature]] = note.status
	var hinge := false
	var soft := false
	var ellip := false
	for k: String in statuses:
		hinge = hinge or (k.contains("hinge") and statuses[k] == "approximated")
		soft = soft or (k.contains("compliant") and statuses[k] == "approximated")
		ellip = ellip or (k.begins_with("awkward") and k.contains(":rod") and statuses[k] == "approximated")
	check(hinge and soft and ellip, "hinges_compliant_materials_and_elliptical_rods_are_marked_approximated", statuses)

# --- 2. Structural and grip mapping ------------------------------------------------------

func mapping_checks() -> void:
	# SI conversion against the Lab's reference projection formula (object_compatibility.py).
	var ok := true
	var worst := 0.0
	for path: String in paths:
		var o := obj(path)
		var raw: Dictionary = o.original.descriptor
		for i in range((raw.parts as Array).size()):
			var rp: Dictionary = raw.parts[i]
			var cp: Dictionary = o.parts[i]
			var axis: int = rp.axis
			var a := Vector3(int(rp.center_mm[0]), int(rp.center_mm[1]), int(rp.center_mm[2])) * 0.001
			a[axis] -= int(rp.size_mm[axis]) * 0.001 / 2.0
			worst = maxf(worst, a.distance_to(cp.a))
			ok = ok and cp.id == rp.id and is_equal_approx(float(cp.limits.y), int(rp.limit_mdeg[1]) * PI / 180000.0) \
				and is_equal_approx(float(cp.edge_radius), int(rp.edge_radius_um) * 1e-6)
		for g in range((raw.grips as Array).size()):
			var rg: Dictionary = raw.grips[g]
			var part: Dictionary = {}
			for rp: Dictionary in raw.parts:
				if rp.id == rg.part:
					part = rp
			var axis: int = part.axis
			var start := Vector3(int(part.center_mm[0]), int(part.center_mm[1]), int(part.center_mm[2])) * 0.001
			start[axis] += (int(rg.start_permille) / 1000.0 - 0.5) * int(part.size_mm[axis]) * 0.001
			worst = maxf(worst, start.distance_to(o.grips[g].a))
	check(ok and worst < 1e-6, "lab_parts_and_grip_intervals_convert_with_the_lab_reference_projection", {"max_error_m": worst})
	# Analysis mass equals the Lab mass; game inertia vs the Lab's envelope proxy is
	# reported (different assumptions: point samples vs box envelopes).
	var mass_ok := true
	var inertia := {}
	for path: String in paths:
		var an := LabAnalysis.analyse(obj(path))
		var total := 0.0
		var com := Vector3.ZERO
		for s: Array in an.samples:
			total += float(s[1])
			com += (s[0] as Vector3) * float(s[1])
		com /= total
		mass_ok = mass_ok and absf(total - float(obj(path).physical.mass)) < 1e-6 and com.distance_to(obj(path).physical.com) < 0.005
		var about_com := 0.0
		for s: Array in an.samples:
			var d: Vector3 = (s[0] as Vector3) - com
			about_com += float(s[1]) * (d.x * d.x + d.z * d.z)
		var lab_yy: float = obj(path).physical.inertia_proxy.yy
		var lab_xx: float = obj(path).physical.inertia_proxy.xx
		inertia[path] = {"game_about_com_vertical": snappedf(about_com, 0.0001), "lab_proxy_xx": snappedf(lab_xx, 0.0001), "lab_proxy_yy": snappedf(lab_yy, 0.0001)}
	check(mass_ok, "analysis_mass_and_centre_match_the_lab_physical_block", inertia)
	# Grips: only the declared intervals; every hold's hands inside them.
	var grip_ok := true
	var grip_detail := {}
	for path: String in paths:
		var caps := caps_for(path, pilgrim)
		if caps.unarmed:
			continue
		var hold: Dictionary = caps.hold
		for hand: String in hold.grips:
			var iv: Dictionary = hold.intervals[hand]
			var p: Vector3 = hold.grips[hand]
			# Against the Lab's own declared interval (raw permille → metres), not the
			# analysis' copy: the hand centre sits a palm half-width inside it.
			var declared: Dictionary = {}
			for g: Dictionary in obj(path).grips:
				if g.id == iv.id:
					declared = g
			grip_ok = grip_ok and not declared.is_empty()
			if declared.is_empty():
				continue
			var a: Vector3 = declared.a
			var b: Vector3 = declared.b
			var axis := (b - a).normalized()
			var along := (p - a).dot(axis)
			var off := ((p - a) - axis * along).length()
			grip_ok = grip_ok and along >= LabAnalysis.HAND_HALF_WIDTH - 0.0005 and along <= a.distance_to(b) - LabAnalysis.HAND_HALF_WIDTH + 0.0005 and off < 0.0005
		grip_detail[path] = hold.id
	check(grip_ok, "holds_use_only_the_lab_declared_grip_intervals", grip_detail)
	# Awkward: valid data, imported and drawn, never held.
	var awkward := caps_for(AWKWARD, pilgrim)
	var mesh := LabMesher.build(obj(AWKWARD))
	check(awkward.unarmed and awkward.grip_candidates == 0 and int(mesh.triangles) > 0 and _has_code(awkward, "no_graspable_region"),
		"zero_grip_object_imports_and_draws_but_is_never_held", {"triangles": mesh.triangles})
	(mesh.node as Node).free()
	# Hinged panel: unlocked → no contact feature, no cover; drawn under its own pivot.
	var an := LabAnalysis.analyse(obj(HINGED))
	var panel_features := (an.features as Array).filter(func(f: Dictionary) -> bool: return f.part == "panel")
	var panel_covers := (an.covers as Array).filter(func(c: Dictionary) -> bool: return c.part == "panel")
	var hinged_mesh := LabMesher.build(obj(HINGED))
	check(panel_features.is_empty() and panel_covers.is_empty() and (hinged_mesh.articulated as Array).size() == 1,
		"unlocked_hinged_panel_never_gains_rigid_contact_or_cover", {"articulated": (an.articulated as Array).size()})
	(hinged_mesh.node as Node).free()
	# Compliant canopy: posture-pushing faces only (soft), never a cut or pierce.
	var umb := LabAnalysis.analyse(obj(UMBRELLA))
	var soft_ok := true
	for f: Dictionary in umb.features:
		if f.part == "membrane":
			soft_ok = soft_ok and f.soft and f.channel == "blunt"
	check(soft_ok and (umb.covers as Array).any(func(c: Dictionary) -> bool: return c.kind == "canopy"),
		"compliant_canopy_guards_and_pushes_but_never_cuts")

# --- 3. Invariance --------------------------------------------------------------------

func invariance_checks() -> void:
	var same := true
	var detail := {}
	for path: String in paths:
		for body: Dictionary in [pilgrim, corrupted]:
			var base := canon(caps_for(path, body))
			for name: String in DECOY_NAMES:
				var o := obj(path).duplicate(true)
				o.label = name
				o.original.descriptor.name = name
				o.original.descriptor.description = name + " of legend"
				# Generation provenance must not dispatch combat either.
				o.assembly = (int(o.assembly) + 3) % 7
				o.original.descriptor.recipe.assembly = o.assembly
				o.source.path = "objects/%s.json" % name.to_lower().replace(" ", "_")
				var c := Solver.solve(o, body)
				same = same and canon(c) == base and c.object_fingerprint == caps_for(path, body).object_fingerprint
		detail[path] = move_set(caps_for(path, pilgrim))
	check(same, "names_descriptions_assembly_and_filenames_never_change_capabilities", detail)
	# Source scan: decision code never reads names, labels, assembly or file paths.
	var leaks: Array[String] = []
	for file: String in ["affordance_solver.gd", "lab_analysis.gd", "object_analysis.gd", "motion_library.gd", "adaptive_fighter.gd", "adaptive_ai.gd"]:
		var text := FileAccess.get_file_as_string("res://scripts/adaptive_lab/" + file)
		for token: String in [".label", "\"label\"", ".name", "\"name\"", ".assembly", "\"assembly\"", ".description", "source.path", ".json\""]:
			for line: String in text.split("\n"):
				if line.contains(token) and not line.strip_edges().begins_with("##") and not line.strip_edges().begins_with("#"):
					leaks.append("%s: %s" % [file, line.strip_edges().substr(0, 80)])
	check(leaks.is_empty(), "solver_analysis_motion_rules_and_ai_never_read_names_or_provenance", leaks)

# --- 4. Geometry → different legal attacks ---------------------------------------------

func geometry_checks() -> void:
	var sets := {}
	var distinct := {}
	for path: String in paths:
		sets[path] = move_set(caps_for(path, pilgrim))
		distinct[sets[path]] = true
	check(distinct.size() == paths.size(), "every_lab_object_resolves_to_a_distinct_move_set", sets)
	# Required behaviours, each from measured structure.
	var pole := caps_for(POLE, pilgrim)
	var shovel := caps_for(SHOVEL, pilgrim)
	var umbrella := caps_for(UMBRELLA, pilgrim)
	var hinged := caps_for(HINGED, pilgrim)
	var organic := caps_for(ORGANIC, pilgrim)
	var awkward := caps_for(AWKWARD, pilgrim)
	var pole_ends := {}
	for act: Dictionary in pole.light:
		pole_ends[act.archetype == "rear"] = true
	check(pole_ends.size() == 2 and pole.heavy.archetype == "windmill" and (pole.heavy.windows_abs as Array).size() == 2
		and pole.heavy.feature.id != pole.heavy.rear_feature.id, "two_ended_object_alternates_ends_and_strikes_both_in_its_windmill",
		{"light": move_set(pole)})
	check(shovel.physics.head > 0.5 and shovel.heavy.archetype == "overhead" and hinged.heavy.archetype == "lunge"
		and hinged.heavy.channel == "pierce" and shovel.physics.inertia > 3.0 * hinged.physics.inertia,
		"heavy_offset_head_chops_while_light_pointed_shaft_lunges",
		{"shovel": [shovel.heavy.archetype, shovel.physics.head, shovel.physics.inertia], "hinged": [hinged.heavy.archetype, hinged.physics.inertia]})
	var umbrella_archetypes := {}
	for act: Dictionary in umbrella.light:
		umbrella_archetypes[act.archetype] = act.feature.get("soft", false)
	check(umbrella_archetypes.has("bash") and umbrella_archetypes.bash and umbrella.guard.kind == "canopy_cover"
		and _has_code(umbrella, "thrust_rejected"), "umbrella_bashes_and_guards_with_its_canopy_and_cannot_thrust_through_it",
		{"light": move_set(umbrella)})
	var hooks: Array = (organic.light as Array) + (organic.heavy_after as Array)
	hooks = hooks.filter(func(a: Variant) -> bool: return a != null and a.archetype == "hook")
	var no_hook_elsewhere := true
	for path: String in [UMBRELLA, SHOVEL, POLE, HINGED]:
		var c := caps_for(path, pilgrim)
		no_hook_elsewhere = no_hook_elsewhere and _has_code(c, "hook_rejected")
	check(not hooks.is_empty() and float(hooks[0].pull) > 0.0 and no_hook_elsewhere,
		"one_sided_branch_grants_a_hook_that_pulls", move_set(organic))
	var awkward_damage := 0.0
	for act: Dictionary in awkward.light:
		awkward_damage = maxf(awkward_damage, float(act.damage))
	check(awkward.unarmed and awkward_damage < 7.0 and awkward.heavy.archetype == "barge", "awkward_unholdable_object_leaves_only_bare_handed_options",
		{"max_light_damage": awkward_damage})
	# Structure edits change what is legal (tests edit converted geometry directly).
	var no_tip := obj(ORGANIC).duplicate(true)
	no_tip.parts = (no_tip.parts as Array).filter(func(p: Dictionary) -> bool: return p.id != "tip")
	var c1 := Solver.solve(no_tip, pilgrim)
	var pierce_left := (c1.features as Array).any(func(f: Dictionary) -> bool: return f.channel == "pierce")
	var locked := obj(HINGED).duplicate(true)
	for p: Dictionary in locked.parts:
		if p.id == "panel":
			p.articulated = false
			p.rigid = true
	var panel_edges := (LabAnalysis.analyse(locked).features as Array).filter(func(f: Dictionary) -> bool: return f.part == "panel" and f.channel == "cut")
	var one_grip := obj(SHOVEL).duplicate(true)
	one_grip.grips = [one_grip.grips[1]]
	var c3 := Solver.solve(one_grip, pilgrim)
	check(not pierce_left and not panel_edges.is_empty() and c3.hold != null and c3.hold.id != shovel.hold.id,
		"editing_structure_changes_legal_attacks", {"organic_without_tip": move_set(c1), "locked_hinge_cut_edges": panel_edges.size(),
			"shovel_one_interval_hold": c3.hold.id if c3.hold != null else null})

func _has_code(caps: Dictionary, code: String) -> bool:
	for r: Dictionary in caps.rejections:
		if r.code == code:
			return true
	return false

# --- 5. Same inputs → visibly different combos ------------------------------------------

## Drives the live scene with the SAME input script and returns the event sequence
## and a motion trace (feature path, hands, torso, root) for the player.
func scripted_run(path: String) -> Dictionary:
	var lab := await make_lab(path, HINGED)
	lab.paused = true
	lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.2)
	var script := {1: "light", 17: "light", 33: "light", 110: "heavy", 215: "light", 232: "heavy"}
	# (Lambdas capture locals by value: keep the tick counter in a shared Dictionary.)
	var clock := {"n": 0}
	lab.player_driver = func(_l: Node) -> Dictionary:
		clock.n += 1
		return {script.get(clock.n, "none"): true}
	var trace: Array = []
	for k in range(330):
		lab.step(DT)
		if lab.player.state == "attack":
			var f := Motion.window_feature(lab.player.action, maxi(0, int(lab.player.pose.window)))
			var world: Transform3D = lab.player.xform() * (lab.player.pose.object as Transform3D)
			trace.append({"t": k, "id": lab.player.action.id, "phase": lab.player.pose.phase, "feature": world * (f.pos as Vector3),
				"yaw": lab.player.pose.yaw, "lean": lab.player.pose.lean, "crouch": lab.player.pose.get("crouch", 0.0)})
	var events: Array = []
	for e: Dictionary in lab.player.events:
		if e.kind == "attack":
			events.append("%s:%s" % [e.detail.input, e.detail.archetype])
	lab.queue_free()
	await process_frame
	return {"events": events, "trace": trace}

## Windup end, path and recovery of the first light and the neutral heavy, as numbers.
static func motion_signature(caps: Dictionary, body: Dictionary) -> Dictionary:
	var out := {}
	for entry: Array in [["light", caps.light[0]], ["heavy", caps.heavy]]:
		var act: Dictionary = entry[1]
		var w: float = act.windup
		var a: float = act.active
		var r: float = act.recovery
		var feature := Motion.window_feature(act, 0)
		var loaded := Motion.sample(act, w * 0.999, body)
		var mid := Motion.sample(act, w + a * 0.5, body)
		var rec := Motion.sample(act, w + a + r * 0.35, body)
		var path: Array = []
		for i in range(7):
			var p := Motion.sample(act, w + a * i / 6.0, body)
			path.append((p.object as Transform3D) * (feature.pos as Vector3))
		out[entry[0]] = {"loaded_feature": (loaded.object as Transform3D) * (feature.pos as Vector3), "loaded_yaw": loaded.yaw,
			"loaded_lean": loaded.lean, "contact_feature": (mid.object as Transform3D) * (feature.pos as Vector3),
			"recovery_feature": (rec.object as Transform3D) * (feature.pos as Vector3), "path": path,
			"root": Motion.root_at(act.keys, w + a), "surface": feature.kind, "hands": loaded.hands.keys()}
	return out

static func path_distance(a: Array, b: Array) -> float:
	var total := 0.0
	for i in range(a.size()):
		total += (a[i] as Vector3).distance_to(b[i])
	return total / a.size()

func combo_checks() -> void:
	var runs := {}
	for path: String in [UMBRELLA, SHOVEL, POLE, HINGED, ORGANIC]:
		runs[path] = await scripted_run(path)
	var sequences := {}
	for path: String in runs:
		sequences[path] = ", ".join(runs[path].events)
	var distinct := {}
	for path: String in sequences:
		distinct[sequences[path]] = true
	check(distinct.size() == sequences.size() and (runs[POLE].events as Array).size() >= 5,
		"same_input_script_produces_different_combo_sequences", sequences)
	# Pairwise motion differences: windup pose, attack path, body motion, surface, recovery.
	var sigs := {}
	for path: String in [UMBRELLA, SHOVEL, POLE, HINGED]:
		sigs[path] = motion_signature(caps_for(path, pilgrim), pilgrim)
	var pairs := {}
	var all_differ := true
	var keys := sigs.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Dictionary = sigs[keys[i]]
			var b: Dictionary = sigs[keys[j]]
			var windup := 0.0
			var path_d := 0.0
			var body_d := 0.0
			var recovery := 0.0
			var surfaces := 0
			for kind: String in ["light", "heavy"]:
				windup = maxf(windup, (a[kind].loaded_feature as Vector3).distance_to(b[kind].loaded_feature))
				path_d = maxf(path_d, path_distance(a[kind].path, b[kind].path))
				body_d = maxf(body_d, absf(float(a[kind].loaded_yaw) - float(b[kind].loaded_yaw)) + absf(float(a[kind].loaded_lean) - float(b[kind].loaded_lean))
					+ absf(float(a[kind].root) - float(b[kind].root)))
				recovery = maxf(recovery, (a[kind].recovery_feature as Vector3).distance_to(b[kind].recovery_feature))
				surfaces += int(a[kind].surface != b[kind].surface)
			var differ := windup > 0.25 and path_d > 0.2 and body_d > 0.15 and recovery > 0.2
			all_differ = all_differ and differ
			pairs["%s vs %s" % [str(keys[i]).get_file(), str(keys[j]).get_file()]] = {"windup_m": snappedf(windup, 0.01), "path_m": snappedf(path_d, 0.01),
				"body": snappedf(body_d, 0.01), "recovery_m": snappedf(recovery, 0.01), "surfaces_differ": surfaces}
	check(all_differ, "windup_path_body_and_recovery_differ_pairwise_across_four_objects", pairs)
	# Physics shaping: the heavy head carries further (overshoot, sag) than the light point.
	var shovel_heavy: Dictionary = caps_for(SHOVEL, pilgrim).heavy
	var pole_light: Dictionary = caps_for(POLE, pilgrim).light[0]
	check(float(shovel_heavy.heft) > 3.0 * float(pole_light.heft) and float(shovel_heavy.windup) > 2.0 * float(pole_light.windup)
		and Motion.archetype(shovel_heavy.archetype).axis != null, "heft_shapes_tempo_overshoot_and_recovery",
		{"shovel_heft": shovel_heavy.heft, "pole_heft": pole_light.heft, "windups": [shovel_heavy.windup, pole_light.windup]})
	# Combo transitions depend on affordances: finishers follow the chain's exit side.
	var finisher_varies := false
	for path: String in paths:
		var c := caps_for(path, pilgrim)
		var kinds := {}
		for h: Variant in c.heavy_after:
			kinds[h.archetype if h != null else "none"] = true
		finisher_varies = finisher_varies or kinds.size() > 1
	var light_then_heavy: Array = (runs[POLE].events as Array).filter(func(e: String) -> bool: return e.begins_with("heavy"))
	check(finisher_varies and light_then_heavy.size() >= 2, "heavy_after_a_light_uses_the_combo_graph_finisher",
		{"pole_heavies": light_then_heavy})

# --- 6. Motion: grips, IK, validation ---------------------------------------------------

func motion_checks() -> void:
	var worst_reach := 0.0
	var worst_pen := 0.0
	var slide_ok := true
	var count := 0
	for body: Dictionary in [pilgrim, corrupted, grafted]:
		for path: String in paths:
			var caps := caps_for(path, body)
			if caps.unarmed:
				continue
			var acts: Array = (caps.light as Array).duplicate()
			acts.append(caps.heavy)
			for act: Dictionary in acts:
				var total: float = float(act.windup) + float(act.active) + float(act.recovery)
				for i in range(25):
					var pose := Motion.sample(act, total * i / 24.0, body)
					worst_reach = maxf(worst_reach, pose.reach_excess)
					worst_pen = maxf(worst_pen, pose.penetration)
					count += 1
					var hold: Dictionary = caps.hold
					for hand: String in hold.grips:
						var iv: Dictionary = hold.intervals[hand]
						var g := Motion.slid_grip(hold, hand, pose.slide)
						var t := (g - (iv.lo as Vector3)).dot(iv.axis) / maxf((iv.lo as Vector3).distance_to(iv.hi), 0.0001)
						slide_ok = slide_ok and t >= -0.001 and t <= 1.001
	check(worst_reach <= Motion.REACH_LIMIT and worst_pen <= Motion.PENETRATION_LIMIT and count > 300,
		"every_chain_and_heavy_motion_keeps_grips_reachable_and_the_object_out_of_the_wielder",
		{"samples": count, "worst_reach_excess_m": snappedf(worst_reach, 0.0001), "worst_penetration_m": snappedf(worst_pen, 0.0001)})
	check(slide_ok, "hands_slide_only_inside_their_declared_intervals")
	# Feature moves rigidly with the grips (one rigid placement of one descriptor).
	var rigid := 0.0
	for path: String in [SHOVEL, POLE, UMBRELLA]:
		var act: Dictionary = caps_for(path, pilgrim).light[0]
		var hold: Dictionary = act.hold
		var local: float = ((act.feature.pos as Vector3) - (hold.grips.hand_r as Vector3)).length()
		for i in range(12):
			var pose := Motion.sample(act, (float(act.windup) + float(act.active)) * i / 11.0, pilgrim)
			var world: Vector3 = (pose.object as Transform3D) * (act.feature.pos as Vector3)
			var hand_local := Motion.slid_grip(hold, "hand_r", pose.slide)
			var expected := ((act.feature.pos as Vector3) - hand_local).length()
			rigid = maxf(rigid, absf(world.distance_to(pose.hands.hand_r) - expected))
			local = expected
	check(rigid < 0.0005, "contact_feature_moves_rigidly_with_the_gripped_object", {"max_error_m": rigid})

# --- 6b/7. Scene: drawn geometry equals contact; hits and misses ------------------------

func make_lab(player: String, soul: String, graft := false) -> Node:
	var lab: Node = load("res://scenes/adaptive_combat_lab.tscn").instantiate()
	lab.loadout.player.source = "lab"
	lab.loadout.player.lab = Imp.accepted_paths().find(player)
	lab.loadout.player.graft = graft
	lab.loadout.soul.source = "lab"
	lab.loadout.soul.lab = Imp.accepted_paths().find(soul)
	root.add_child(lab)
	await process_frame
	lab.ai.mode = "passive"
	return lab

func scene_contact_checks() -> void:
	var worst := 0.0
	var worst_hand := 0.0
	var hits := 0
	var detail := {}
	for path: String in [UMBRELLA, SHOVEL, POLE, ORGANIC, HINGED]:
		var lab := await make_lab(path, HINGED)
		lab.paused = true
		lab.soul.position = lab.player.position + Vector3(0, 0, -1.9)
		var clock := {"n": 0}
		lab.player_driver = func(_l: Node) -> Dictionary:
			clock.n += 1
			return {"heavy": clock.n == 1}
		for k in range(120):
			lab.step(DT)
			await process_frame
			if lab.player.state == "attack":
				var drawn: Transform3D = lab.player_actor.object_node.global_transform
				var rules: Transform3D = lab.player.xform() * (lab.player.pose.object as Transform3D)
				var f := Motion.window_feature(lab.player.action, maxi(0, int(lab.player.pose.window)))
				worst = maxf(worst, (drawn * (f.pos as Vector3)).distance_to(rules * (f.pos as Vector3)))
				var cap: Array = lab.player.contact_at(lab.player.state_time, maxi(0, int(lab.player.pose.window)))
				var centre: Vector3 = ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5
				worst = maxf(worst, centre.distance_to(drawn * (f.pos as Vector3)))
				var bones: Dictionary = lab.player_actor.last_result.bones
				for hand: String in lab.player.pose.hands:
					var socket := "grip_r" if hand == "hand_r" else "grip_l"
					var drawn_grip: Vector3 = lab.player_actor.global_transform * Rig.socket_global(bones, socket).origin
					worst_hand = maxf(worst_hand, drawn_grip.distance_to(lab.player.xform() * (lab.player.pose.hands[hand] as Vector3)))
		var contacts: Array = lab.player.events.filter(func(e: Dictionary) -> bool: return e.kind == "contact")
		hits += int(not contacts.is_empty())
		detail[path] = contacts.size()
		lab.queue_free()
		await process_frame
	check(worst < 0.0005 and hits == 5, "drawn_object_feature_equals_the_rules_contact_capsule_at_every_frame",
		{"max_error_m": snappedf(worst, 0.000001), "heavies_connected": detail})
	check(worst_hand < GRIP_TOLERANCE, "drawn_fists_hold_the_rules_grip_points", {"max_error_m": snappedf(worst_hand, 0.0001)})

## Pure-rules duel helpers.
func pair(attacker_path: String, defender_path: String, distance: float, a_body := pilgrim, d_body := corrupted) -> Array:
	var a := AdaptiveFighter.new("player")
	var d := AdaptiveFighter.new("soul")
	a.equip(obj(attacker_path), a_body, caps_for(attacker_path, a_body))
	d.equip(obj(defender_path), d_body, caps_for(defender_path, d_body))
	a.position = Vector3(0, 0, distance * 0.5)
	d.position = Vector3(0, 0, -distance * 0.5)
	d.yaw = PI
	return [a, d]

func run_ticks(a: AdaptiveFighter, b: AdaptiveFighter, ticks: int, ia: Callable, ib: Callable) -> void:
	for t in range(ticks):
		a.step(ia.call(t), b.position, DT)
		b.step(ib.call(t), a.position, DT)
		AdaptiveFighter.separate(a, b)
		AdaptiveFighter.resolve(a, b, DT)
		AdaptiveFighter.resolve(b, a, DT)

func idle(_t: int) -> Dictionary:
	return {}

func outcome(a: AdaptiveFighter) -> String:
	for e: Dictionary in a.events:
		if e.kind == "contact":
			return str(e.detail.outcome)
		if e.kind in ["whiff", "evaded"]:
			return str(e.kind)
	return "none"

func rules_checks() -> void:
	# Heavy-miss regression: every heavy connects from close range to its planned
	# spacing (Lab 1 stepped back a full step when the target was "too close").
	var table := {}
	var all_hit := true
	for path: String in [UMBRELLA, SHOVEL, POLE, ORGANIC, HINGED]:
		var heavy: Dictionary = caps_for(path, pilgrim).heavy
		var row := {}
		var d := 0.9
		var far := float(heavy.reach) + float(heavy.root_contact) + AdaptiveFighter.BODY_RADIUS
		while d <= far:
			var duo := pair(path, HINGED, d)
			run_ticks(duo[0], duo[1], 150, func(t: int) -> Dictionary: return {"heavy": t == 0}, idle)
			row["%.1f" % d] = outcome(duo[0])
			all_hit = all_hit and row["%.1f" % d] == "hit"
			d += 0.2
		table[path.get_file()] = row
	check(all_hit, "every_heavy_connects_from_close_range_out_to_its_reach", table)
	# Legitimate misses: out of reach → whiff (closest gap reported); dodge → evaded;
	# active window only.
	var far_pair := pair(SHOVEL, HINGED, 4.5)
	run_ticks(far_pair[0], far_pair[1], 150, func(t: int) -> Dictionary: return {"heavy": t == 0}, idle)
	var whiff: Array = far_pair[0].events.filter(func(e: Dictionary) -> bool: return e.kind == "whiff")
	# Dodge (toward the attacker, staying in range) just before the measured contact.
	# A lunge travels onto a target that backsteps just before contact: the blade
	# reaches it during its invulnerability frames.
	var dry := pair(HINGED, SHOVEL, 2.0)
	run_ticks(dry[0], dry[1], 150, func(t: int) -> Dictionary: return {"heavy": t == 0}, idle)
	var contact_t := 0.0
	for e: Dictionary in dry[0].events:
		if e.kind == "contact":
			contact_t = float(e.detail.rule_time)
	# The dodging defender is pinned in place (as against a wall) so that only the
	# invulnerability frames, not distance, decide the outcome.
	var dodge_pair := pair(HINGED, SHOVEL, 2.0)
	var dodge_at := int((contact_t - 0.06) / DT)
	var pin: Vector3 = dodge_pair[1].position
	for t in range(150):
		dodge_pair[0].step({"heavy": t == 0}, dodge_pair[1].position, DT)
		dodge_pair[1].step({"dodge": t == dodge_at}, dodge_pair[0].position, DT)
		dodge_pair[1].position = pin
		AdaptiveFighter.resolve(dodge_pair[0], dodge_pair[1], DT)
	check(outcome(far_pair[0]) == "whiff" and float(whiff[0].detail.closest) > 0.3 and outcome(dodge_pair[0]) == "evaded",
		"out_of_reach_heavies_whiff_and_dodged_heavies_are_evaded", {"far": outcome(far_pair[0]), "closest_m": whiff[0].detail.closest if not whiff.is_empty() else null,
			"dodged": outcome(dodge_pair[0])})
	var only_active := true
	for path: String in [SHOVEL, POLE]:
		var duo := pair(path, HINGED, 1.6)
		var a: AdaptiveFighter = duo[0]
		run_ticks(a, duo[1], 120, func(t: int) -> Dictionary: return {"light": t == 0}, idle)
		for e: Dictionary in a.events:
			if e.kind == "contact":
				var w: Dictionary = a.caps.light[0].windows_abs[int(e.detail.window)]
				only_active = only_active and float(e.detail.rule_time) >= float(w.t0) - 1e-6 and float(e.detail.rule_time) <= float(w.t1) + 1e-6
	check(only_active, "contact_registers_only_inside_contact_windows")
	# Windmill: both ends land in one action (two windows, two contacts).
	var mill := pair(POLE, HINGED, 1.4)
	run_ticks(mill[0], mill[1], 120, func(t: int) -> Dictionary: return {"heavy": t == 0}, idle)
	var mill_contacts: Array = mill[0].events.filter(func(e: Dictionary) -> bool: return e.kind == "contact")
	check(mill_contacts.size() == 2 and int(mill_contacts[0].detail.window) == 0 and int(mill_contacts[1].detail.window) == 1,
		"windmill_lands_with_the_lead_end_then_the_rear_end", mill_contacts.map(func(e: Dictionary) -> String: return "%s/%s" % [e.detail.feature, e.detail.outcome]))
	# Hook pulls; block, deflect, posture break and punish follow from timing.
	var hook_pair := pair(ORGANIC, HINGED, 1.8)
	var before: float = (hook_pair[0].position as Vector3).distance_to(hook_pair[1].position)
	var hook_index := -1
	var after: Array = caps_for(ORGANIC, pilgrim).heavy_after
	for i in range(after.size()):
		if after[i] != null and after[i].archetype == "hook" and hook_index < 0:
			hook_index = i
	var a_hook: AdaptiveFighter = hook_pair[0]
	a_hook._start_attack("heavy", hook_index, hook_pair[1].position)
	run_ticks(a_hook, hook_pair[1], 60, idle, idle)
	var pulled := a_hook.events.any(func(e: Dictionary) -> bool: return e.kind == "contact" and e.detail.get("pulled", false))
	check(hook_index >= 0 and pulled, "hook_contact_drags_the_defender_toward_the_attacker", {"start_distance": before})
	var dry_g := pair(SHOVEL, UMBRELLA, 1.7)
	run_ticks(dry_g[0], dry_g[1], 150, func(t: int) -> Dictionary: return {"heavy": t == 0}, idle)
	for e: Dictionary in dry_g[0].events:
		if e.kind == "contact":
			contact_t = float(e.detail.rule_time)
	var g := pair(SHOVEL, UMBRELLA, 1.7)
	var held_from := maxi(0, int((float(caps_for(SHOVEL, pilgrim).heavy.windup) - 0.3) / DT))
	run_ticks(g[0], g[1], 140, func(t: int) -> Dictionary: return {"heavy": t == 0}, func(t: int) -> Dictionary: return {"guard": t >= held_from})
	var press_at := int((contact_t - 0.05) / DT)
	var df := pair(SHOVEL, UMBRELLA, 1.7)
	run_ticks(df[0], df[1], 140, func(t: int) -> Dictionary: return {"heavy": t == 0}, func(t: int) -> Dictionary: return {"guard": t >= press_at})
	check(outcome(g[0]) == "blocked" and outcome(df[0]) == "deflected", "held_guard_blocks_and_a_fresh_press_deflects", [outcome(g[0]), outcome(df[0])])

# --- 8. Camera ----------------------------------------------------------------------------

func send_key(code: Key, pressed := true, shift := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)

func camera_checks() -> void:
	var lab := await make_lab(SHOVEL, HINGED)
	var orbit: Node = lab.orbit
	await process_frame
	var start_yaw: float = orbit.yaw
	# Unlocked: the opponent walks around; the camera does not follow.
	lab.paused = true
	for k in range(90):
		lab.soul.position = lab.player.position + Vector3(sin(k * 0.05) * 3.0, 0.0, -cos(k * 0.05) * 3.0)
		lab.step(DT)
		await process_frame
	var unlocked_drift: float = absf(angle_difference(start_yaw, orbit.yaw))
	# Real input: Q toggles lock; locked, the camera turns to frame the target.
	send_key(KEY_Q)
	await process_frame
	send_key(KEY_Q, false)
	var locked: bool = orbit.locked
	for k in range(90):
		await process_frame
	var to: Vector3 = lab.soul.position - lab.player.position
	var target_yaw := atan2(-to.x, -to.z) + 0.15
	var locked_error: float = absf(angle_difference(orbit.yaw, target_yaw))
	# Manual override while locked: orbiting holds for a moment before tracking resumes.
	orbit.orbit(Vector2(250.0, 0.0))
	var overridden: float = orbit.yaw
	await process_frame
	await process_frame
	var held: bool = absf(angle_difference(overridden, orbit.yaw)) < 0.02
	check(unlocked_drift < 1e-4 and locked and locked_error < 0.1 and held, "camera_is_free_unless_locked_and_lock_on_tracks_with_manual_override",
		{"unlocked_drift": unlocked_drift, "locked_error": snappedf(locked_error, 0.001), "override_held": held})
	# Wheel zoom (real events) smooths toward the new distance within limits.
	var before: float = orbit.preferred_distance
	for k in range(3):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.factor = 1.0
		Input.parse_input_event(wheel)
		await process_frame
	for k in range(30):
		await process_frame
	var zoomed: float = orbit.preferred_distance
	check(zoomed < before and absf(orbit.spring.spring_length - zoomed) < 0.05 and zoomed >= orbit.MIN_DISTANCE, "wheel_zoom_is_smooth_and_bounded",
		{"before": before, "after": zoomed, "arm": orbit.spring.spring_length})
	# Camera collision: a pillar between the player and the camera shortens the arm.
	orbit.locked = false
	lab.player.position = Vector3(cos(0.0) * 6.5 - 1.6, 0.0, sin(0.0) * 6.5)
	orbit.yaw = PI * 0.5
	orbit.pitch = -0.1
	orbit.preferred_distance = 5.0
	for k in range(30):
		await physics_frame
		await process_frame
	var hit_length: float = orbit.spring.get_hit_length()
	check(hit_length < 4.0, "spring_arm_retracts_in_front_of_a_pillar", {"hit_length": hit_length})
	# Movement is camera-relative and unlocked attacks follow the stick (soft aim).
	orbit.yaw = PI * 0.5
	lab.player.position = Vector3.ZERO
	lab.soul.position = Vector3(0, 0, -8)
	var intent: Dictionary = lab.LabInput.read(orbit.move_basis())
	var basis_forward: Vector3 = orbit.move_basis() * Vector3(0, 0, -1)
	var face: Variant = lab.LabInput.facing({"move": basis_forward, "light": true}, false, Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -8))
	var face_locked: Variant = lab.LabInput.facing({"move": basis_forward}, true, Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -8))
	check(basis_forward.distance_to(Vector3(-1, 0, 0)) < 0.001 and face is Vector3 and (face as Vector3).distance_to(basis_forward) < 0.001 and face_locked == null
		and intent.move == Vector3.ZERO, "movement_is_camera_relative_and_facing_follows_lock_state", {"forward": basis_forward})
	lab.queue_free()
	await process_frame

# --- 9. Clean default HUD -----------------------------------------------------------

func hud_checks() -> void:
	var lab := await make_lab(SHOVEL, HINGED)
	await process_frame
	await process_frame
	var hud: CanvasLayer = lab.hud
	var hidden: bool = not hud.stats_root.visible and not hud.log_root.visible and not hud.help_label.visible
	var area := 0.0
	var screen := Vector2(1280, 720)
	for c: Control in [hud.player_hp, hud.player_posture, hud.equipment, hud.soul_hp, hud.soul_posture, hud.soul_name, hud.hint]:
		if c.is_visible_in_tree():
			area += c.get_global_rect().size.x * c.get_global_rect().size.y
	var lines: int = (hud.equipment.text as String).split("\n").size()
	var debug_off: bool = not lab.player_actor.show_debug and not lab.player_actor.show_paths
	send_key(KEY_F2)
	await process_frame
	send_key(KEY_F5)
	await process_frame
	send_key(KEY_H)
	await process_frame
	var shown: bool = hud.stats_root.visible and hud.log_root.visible and hud.help_label.visible
	check(hidden and debug_off and lines == 1 and area / (screen.x * screen.y) < 0.06 and shown,
		"default_hud_is_minimal_and_debug_layers_appear_only_on_toggle",
		{"default_area_fraction": snappedf(area / (screen.x * screen.y), 0.0001), "equipment": hud.equipment.text, "toggles_show": shown})
	lab.queue_free()
	await process_frame

# --- 10. Body modification ------------------------------------------------------------

func body_mod_checks() -> void:
	# Keeps the hand: the same holds and moves for every object.
	var same := true
	for path: String in paths:
		var a := caps_for(path, pilgrim)
		var b := caps_for(path, grafted)
		same = same and move_set(a) == move_set(b) and ((a.hold.id if a.hold != null else "") == (b.hold.id if b.hold != null else ""))
	check(same and "hand_l" in grafted.hands, "graft_keeps_ordinary_hand_function_and_every_hold")
	# Benefit: regeneration after the delay.
	var r := pair(SHOVEL, HINGED, 4.0, grafted, corrupted)
	var a: AdaptiveFighter = r[0]
	a.hp = 50.0
	a.since_hurt = 0.0
	run_ticks(a, r[1], 60 * 5, idle, idle)
	var plain := pair(SHOVEL, HINGED, 4.0)
	plain[0].hp = 50.0
	plain[0].since_hurt = 0.0
	run_ticks(plain[0], plain[1], 60 * 5, idle, idle)
	check(a.hp > 55.0 and is_equal_approx(plain[0].hp, 50.0), "graft_regenerates_health_after_a_delay", {"grafted_hp": snappedf(a.hp, 0.01), "plain_hp": plain[0].hp})
	# Drawbacks: the same hit costs more health, more posture and a longer stagger.
	var taken := {}
	for body_case: Array in [["plain", corrupted], ["graft", Bodies.build("corrupted", ["marrow_graft"])]]:
		var duo := pair(SHOVEL, HINGED, 1.7, pilgrim, body_case[1])
		run_ticks(duo[0], duo[1], 50, func(t: int) -> Dictionary: return {"light": t == 0}, idle)
		var d: AdaptiveFighter = duo[1]
		taken[body_case[0]] = {"hp_lost": snappedf(100.0 - d.hp, 0.01), "posture": snappedf(d.posture, 0.01), "stagger": d.stagger_for}
	check(float(taken.graft.hp_lost) > float(taken.plain.hp_lost) * 1.2 and float(taken.graft.posture) > float(taken.plain.posture) * 1.3
		and float(taken.graft.stagger) > float(taken.plain.stagger), "graft_takes_more_damage_posture_and_stagger", taken)
	# Genuine anatomy still restricts: a limb without a hand cannot two-hand.
	var handless := Bodies.build("pilgrim", ["handless_limb_example"])
	var hc := Solver.solve(obj(POLE), handless)
	check(hc.hold != null and (hc.hold.hands as Array).size() == 1 and not "hand_l" in handless.hands and _has_code(hc, "two_hand_requires_missing_hand"),
		"anatomy_without_a_hand_still_restricts_grips", move_set(hc))

# --- 11. Parity -----------------------------------------------------------------------

func parity_checks() -> void:
	var same := true
	for path: String in paths:
		var p := AdaptiveFighter.new("player")
		var s := AdaptiveFighter.new("soul")
		p.equip(obj(path), corrupted)
		s.equip(obj(path), corrupted)
		same = same and canon(p.caps) == canon(s.caps)
	# The soul with the graft regenerates and suffers the same way (shared rules).
	var duo := pair(HINGED, SHOVEL, 4.0, pilgrim, Bodies.build("corrupted", ["marrow_graft"]))
	duo[1].hp = 40.0
	duo[1].since_hurt = 0.0
	run_ticks(duo[0], duo[1], 300, idle, idle)
	# The AI only issues intents; an unsupported heavy for the soul is refused.
	var ai_pair := pair(SHOVEL, AWKWARD, 1.5)
	var ai := AI.new(5)
	run_ticks(ai_pair[0], ai_pair[1], 240, idle, func(_t: int) -> Dictionary: return ai.intent(ai_pair[1], ai_pair[0], DT))
	check(same and float(duo[1].hp) > 45.0, "player_and_soul_share_capabilities_and_modification_rules", {"soul_regenerated_to": snappedf(duo[1].hp, 0.01)})

# --- v0 comparison generator ----------------------------------------------------------

func v0_comparison_checks() -> void:
	var ok := true
	var detail := {}
	for id: String in Gen.recipe_ids():
		var d := Gen.generate(id, int(Gen.recipe(id).seeds[0]))
		var again := Gen.generate(id, int(Gen.recipe(id).seeds[0]))
		var c := Solver.solve(d, pilgrim)
		ok = ok and JSON.stringify(d) == JSON.stringify(again) and c.object_source == "v0"
		detail[id] = move_set(c)
	check(ok, "v0_generator_remains_a_deterministic_comparison_source_through_the_same_solver", detail)

# --- 12. Determinism and performance ---------------------------------------------------

func ai_duel_log(seed: int) -> String:
	var duo := pair(POLE, ORGANIC, 3.0)
	var a: AdaptiveFighter = duo[0]
	var b: AdaptiveFighter = duo[1]
	var ai_a := AI.new(seed)
	var ai_b := AI.new(seed + 1)
	run_ticks(a, b, 60 * 20, func(_t: int) -> Dictionary: return ai_a.intent(a, b, DT), func(_t: int) -> Dictionary: return ai_b.intent(b, a, DT))
	return JSON.stringify(a.events + b.events, "", true) + "|%.6f|%.6f" % [a.hp, b.hp]

func determinism_checks() -> void:
	var first := ai_duel_log(11)
	var second := ai_duel_log(11)
	var other := ai_duel_log(12)
	var file := FileAccess.open(output.path_join("duel_log.json"), FileAccess.WRITE)
	file.store_string(first + "\n")
	var fresh := Solver.solve(obj(SHOVEL), pilgrim)
	check(first == second and first != other and canon(fresh) == canon(caps_for(SHOVEL, pilgrim)),
		"same_seed_duels_and_solves_replay_identically", {"log_bytes": first.length()})

func performance_checks() -> void:
	var worst := 0.0
	var per := {}
	for k: String in timings:
		if k.begins_with("solve_ms:"):
			worst = maxf(worst, float(timings[k]))
			per[k.trim_prefix("solve_ms:")] = snappedf(float(timings[k]), 0.1)
	var t0 := Time.get_ticks_usec()
	var a := pair(SHOVEL, POLE, 2.0)
	for k in range(600):
		a[0].step({"light": k % 40 == 0}, a[1].position, DT)
		a[1].step({}, a[0].position, DT)
		AdaptiveFighter.resolve(a[0], a[1], DT)
	var tick_us := (Time.get_ticks_usec() - t0) / 600.0
	# Timings vary by machine; they are recorded, and only gross regressions fail.
	check(worst < 3000.0 and tick_us < 4000.0, "solver_and_rules_tick_costs_are_recorded_and_bounded",
		{"bundle_import_ms": snappedf(float(timings.bundle_import_ms), 0.1), "worst_solve_ms": snappedf(worst, 0.1), "rules_tick_us": snappedf(tick_us, 1.0),
			"per_object_body_ms": per, "note": "llvmpipe/cloud CPU; results vary by machine"})

# --- Isolation ------------------------------------------------------------------------

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
