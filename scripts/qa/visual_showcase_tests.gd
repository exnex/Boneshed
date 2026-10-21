extends SceneTree
## Checks for the isolated visual showcase (scenes/visual_showcase.tscn). They prove
## structural and geometric invariants of the presentation and that it leaves combat
## outcomes unchanged — not that it looks good or that combat feels good.
##   rig and skin integrity · sockets · drawn weapon == contact segment · fist on grip
##   · two-handed grips · chamber redirection through neutral (real mouse input) ·
##   guard, dodge, roll, hit, posture and death presentation · equipment swapping through
##   the shared build rules · identical contact logs versus the melee lab.
## Run: bash scripts/tooling/test_visual_showcase.sh [new-empty-dir]

const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const CharacterBuilder = preload("res://scripts/visual_showcase/character_builder.gd")
const WeaponBuilder = preload("res://scripts/visual_showcase/weapon_builder.gd")
const PoseSolver = preload("res://scripts/visual_showcase/pose_solver.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const CryptBuilder = preload("res://scripts/visual_showcase/crypt_builder.gd")
const Showcase = preload("res://scripts/visual_showcase/showcase.gd")
const DT := 1.0 / 60.0
## Grip placement tolerance (m): IK precision; the weapon itself is exact.
const GRIP_TOLERANCE := 0.005
## Largest accepted arm stretch (1 = no stretch) anywhere in the sweep.
const MAX_STRETCH := 1.03
const TRIANGLE_BUDGET := 20000

var tuning: Dictionary
var lab: Dictionary
var output := "res://artifacts/visual-showcase"
var passed := 0
var failed := 0
var results := {}

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
	MaterialLibrary.set_texture_size(64)
	tuning = Loadout.load_tuning().values
	lab = Loadout.load_lab()
	rig_checks()
	skin_checks()
	weapon_checks()
	grip_sweep_checks()
	presentation_checks()
	data_checks()
	await scene_socket_checks()
	await input_chamber_checks()
	await equipment_swap_checks()
	await outcome_equivalence_checks()
	isolation_checks()
	finish()

func finish() -> void:
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true) + "\n")
	print(JSON.stringify({"suite": "visual_showcase", "summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string}))
	quit(0 if failed == 0 else 1)

# --- Rig ---------------------------------------------------------------------------

func rig_checks() -> void:
	for preset: Dictionary in [Rig.PILGRIM, Rig.CORRUPTED]:
		var name: String = preset.name
		var names := {}
		var topological := true
		for i in range(Rig.BONES.size()):
			var entry: Array = Rig.BONES[i]
			names[entry[0]] = i
			if entry[1] != "" and (not names.has(entry[1])):
				topological = false
		check(names.size() == 22 and topological, "rig_%s_22_bones_parents_before_children" % name, names.size())
		var globals := Rig.rest_globals(preset)
		var short: Array[String] = []
		var misaimed: Array[String] = []
		for bone: String in Rig.TAILS:
			var length := Rig.bone_length(preset, bone)
			if length < 0.02:
				short.append(bone)
			var tail: Vector3 = Rig.joints(preset)[Rig.TAILS[bone]]
			var xf: Transform3D = globals[bone]
			if xf.basis.y.dot((tail - xf.origin).normalized()) < 0.999 or not xf.basis.is_conformal():
				misaimed.append(bone)
		check(short.is_empty() and misaimed.is_empty(), "rig_%s_bones_have_length_and_aim_at_tails" % name, {"short": short, "misaimed": misaimed})
		var asymmetric: Array[String] = []
		var j := Rig.joints(preset)
		for key: String in j:
			if key.ends_with("_l") or key.contains("_l_"):
				var mirror := key.replace("_l", "_r")
				var a: Vector3 = j[key]
				var b: Vector3 = j[mirror]
				if a.distance_to(Vector3(-b.x, b.y, b.z)) > 0.001:
					asymmetric.append(key)
		check(asymmetric.is_empty(), "rig_%s_left_right_mirror_symmetric" % name, asymmetric)
		var skeleton := Rig.build_skeleton(preset)
		var rest_ok := skeleton.get_bone_count() == Rig.BONES.size()
		for i in range(skeleton.get_bone_count()):
			var global := skeleton.get_bone_global_rest(i)
			if global.origin.distance_to((globals[skeleton.get_bone_name(i)] as Transform3D).origin) > 0.0001:
				rest_ok = false
		check(rest_ok, "rig_%s_skeleton_rest_matches_definition" % name)
		var sockets_ok := true
		for child: Node in skeleton.get_children():
			if child is BoneAttachment3D and skeleton.find_bone((child as BoneAttachment3D).bone_name) < 0:
				sockets_ok = false
		var socket_count := skeleton.get_children().filter(func(c: Node) -> bool: return c is BoneAttachment3D).size()
		check(sockets_ok and socket_count == Rig.SOCKETS.size(), "rig_%s_every_socket_bound_to_existing_bone" % name, socket_count)
		skeleton.free()
	# Proportions: stature and limb ratios inside human ranges (pilgrim), elongated soul.
	var pj := Rig.joints(Rig.PILGRIM)
	var stature: float = (pj.head_top as Vector3).y
	var arm: float = Rig.bone_length(Rig.PILGRIM, "upperarm_r") + Rig.bone_length(Rig.PILGRIM, "lowerarm_r")
	var leg: float = (pj.thigh_r as Vector3).y
	var cj := Rig.joints(Rig.CORRUPTED)
	check(stature > 1.72 and stature < 1.9 and arm / stature > 0.3 and arm / stature < 0.36 and leg / stature > 0.48 and leg / stature < 0.56,
		"rig_pilgrim_human_proportions", {"stature": snappedf(stature, 0.001), "arm_ratio": snappedf(arm / stature, 0.001), "leg_ratio": snappedf(leg / stature, 0.001)})
	check((cj.head_top as Vector3).y > stature and Rig.bone_length(Rig.CORRUPTED, "lowerarm_r") > Rig.bone_length(Rig.PILGRIM, "lowerarm_r"),
		"rig_corrupted_taller_and_longer_armed", snappedf((cj.head_top as Vector3).y, 0.001))

# --- Skin ------------------------------------------------------------------------------

func _configurations() -> Array:
	var out: Array = []
	for kind: String in ["pilgrim", "corrupted"]:
		for armor: Array in [[], ["armor.lab_cloth_wraps"], ["armor.lab_mail_shirt"], ["armor.lab_bog_iron_plate"]]:
			for marrow: bool in [false, true]:
				if kind == "pilgrim" and marrow:
					continue
				out.append({"kind": kind, "armor": armor, "marrow_arm": marrow})
	return out

func skin_checks() -> void:
	var bad_weights: Array[String] = []
	var bad_bones: Array[String] = []
	var budgets := {}
	var layer_names := {}
	var rigid_plate := 0
	for config: Dictionary in _configurations():
		var preset: Dictionary = Rig.CORRUPTED if config.kind == "corrupted" else Rig.PILGRIM
		var built: Dictionary = CharacterBuilder.new(preset, config.kind).build(config)
		var key := "%s/%s/%s" % [config.kind, ",".join(config.armor), config.marrow_arm]
		budgets[key] = built.triangles
		layer_names[key] = built.layers.keys()
		for layer_name: String in built.layers:
			var mesh: ArrayMesh = (built.layers[layer_name] as MeshInstance3D).mesh
			for s in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(s)
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				if bones.size() != count * 4 or weights.size() != count * 4:
					bad_weights.append(key + ":" + layer_name)
					continue
				for v in range(count):
					var total := weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3]
					if absf(total - 1.0) > 0.002:
						bad_weights.append("%s:%s:%d" % [key, layer_name, v])
						break
					for k in range(4):
						if bones[v * 4 + k] < 0 or bones[v * 4 + k] >= Rig.BONES.size():
							bad_bones.append(key)
				if mesh.surface_get_name(s).begins_with("plate"):
					var single := true
					for v in range(count):
						if weights[v * 4] < 0.999:
							single = false
							break
					rigid_plate += int(single)
		(built.root as Node).free()
	check(bad_weights.is_empty(), "skin_weights_normalised_4_influences", bad_weights.slice(0, 5))
	check(bad_bones.is_empty(), "skin_bone_indices_valid", bad_bones.slice(0, 5))
	var over: Array = budgets.keys().filter(func(k: String) -> bool: return budgets[k] > TRIANGLE_BUDGET)
	check(over.is_empty(), "character_triangle_budget_%d" % TRIANGLE_BUDGET, budgets)
	results["character_triangles"] = budgets
	check(rigid_plate > 0, "plate_surfaces_are_rigid_single_bone", rigid_plate)
	var plate_key := "pilgrim/armor.lab_bog_iron_plate/false"
	var marrow_key := "corrupted//true"
	check("Armor_lab_bog_iron_plate" in layer_names.get(plate_key, []) and "Module_marrow_arm" in layer_names.get(marrow_key, []) and
		not "Module_marrow_arm" in layer_names.get("corrupted//false", []), "modular_layers_match_equipment", {"plate": layer_names.get(plate_key), "marrow": layer_names.get(marrow_key)})

# --- Weapons ---------------------------------------------------------------------------

func _weapon_items() -> Dictionary:
	var out := {}
	var combined: Array = Loadout.read_json("res://data/builds/catalog.json").items + Loadout.read_json(Loadout.WEAPONS_PATH).items
	for item: Dictionary in combined:
		if item.get("category") == "weapon":
			var view := {"item": item.id, "class": item.weapon["class"], "grip": item.weapon.grip, "handling": item.weapon.handling, "defense": item.weapon.defense}
			out[item.id] = Handling.derive(view, tuning)
	return out

func weapon_checks() -> void:
	var items := _weapon_items()
	var tips := {}
	var ok := true
	for item: String in items:
		var h: Dictionary = items[item]
		var built := WeaponBuilder.build(item, h.length, h.two_handed, false)
		var node: Node3D = built.node
		var aabb := AABB()
		for child: Node in node.get_children():
			if child is MeshInstance3D:
				aabb = aabb.merge((child as MeshInstance3D).get_aabb()) if aabb.size != Vector3.ZERO else (child as MeshInstance3D).get_aabb()
		var tip: Vector3 = (node.get_node("tip") as Marker3D).position
		var far_end := aabb.position.z
		tips[item] = {"length": h.length, "mesh_tip_z": snappedf(far_end, 0.0001), "marker": tip}
		# The mesh reaches the rules tip (within 2 mm) and never beyond it.
		if absf(far_end + h.length) > 0.002 or tip.distance_to(Vector3(0, 0, -h.length)) > 0.00001:
			ok = false
		node.free()
	check(ok, "weapon_mesh_tip_equals_rules_length", tips)

## Drives each weapon through every chamber, swing and guard and solves the pose each
## tick. The drawn weapon must be the rules segment exactly; the fist must sit on it.
func grip_sweep_checks() -> void:
	var items := _weapon_items()
	var max_error := 0.0
	var max_left := 0.0
	var max_stretch := 1.0
	var weapon_mismatch := 0.0
	var worst := ""
	var samples := 0
	var two_hand_samples := 0
	var two_hand_on := 0
	for item: String in ["item.lab_long_knife", "item.notched_sword", "item.lab_greatsword"]:
		for kind: String in ["pilgrim", "corrupted"]:
			var preset: Dictionary = Rig.CORRUPTED if kind == "corrupted" else Rig.PILGRIM
			var plans: Array = []
			for direction: String in Geometry.DIRECTIONS:
				plans.append(["attack", direction])
			for guard: String in ["right", "high_right", "high", "high_left", "left", "center"]:
				plans.append(["guard", guard])
			plans.append(["redirect", "left_to_right"])
			for plan: Array in plans:
				var state := State.new(tuning, items[item], {})
				var solver := PoseSolver.new(preset)
				for tick in range(150):
					if tick == 2:
						if plan[0] == "guard":
							state.set_guard(true, plan[1])
						elif plan[0] == "redirect":
							state.press_attack("right_to_left")
						else:
							state.press_attack(plan[1])
					if plan[0] == "redirect" and tick == 40:
						state.aim_attack("left_to_right")
					if plan[0] != "guard" and tick == 80:
						state.release_attack()
					state.tick(DT)
					var pose := solver.solve(_view(state), DT)
					var bones: Dictionary = pose.bones
					var grip := Rig.socket_global(bones, "grip_r").origin
					var error := grip.distance_to(state.hand)
					var weapon: Transform3D = pose.weapon
					var mismatch := maxf(weapon.origin.distance_to(state.hand), (weapon.basis * Vector3(0, 0, -(state.h.length as float))).distance_to(state.dir * state.h.length))
					weapon_mismatch = maxf(weapon_mismatch, mismatch)
					if error > max_error:
						max_error = error
						worst = "%s/%s/%s/%s tick %d" % [item, kind, plan[0], plan[1], tick]
					if solver.stretch_r > max_stretch:
						results["worst_stretch"] = "%s/%s/%s/%s tick %d phase %d hand %s" % [item, kind, plan[0], plan[1], tick, state.phase, state.hand]
					max_stretch = maxf(max_stretch, solver.stretch_r)
					if state.h.two_handed:
						if solver.stretch_l > max_stretch:
							results["worst_stretch"] = "L %s/%s/%s/%s tick %d phase %d hand %s" % [item, kind, plan[0], plan[1], tick, state.phase, state.hand]
						var left := Rig.socket_global(bones, "grip_l").origin
						two_hand_samples += 1
						if solver.two_hand_contact:
							two_hand_on += 1
							max_left = maxf(max_left, left.distance_to(state.hand - state.dir * PoseSolver.SECOND_HAND))
						max_stretch = maxf(max_stretch, solver.stretch_l)
					samples += 1
	results.grip_sweep = {"samples": samples, "max_grip_error_m": snappedf(max_error, 0.00001), "worst": worst,
		"max_left_grip_error_m": snappedf(max_left, 0.00001), "two_hands_on_hilt_fraction": snappedf(float(two_hand_on) / maxf(1.0, two_hand_samples), 0.001), "max_stretch": snappedf(max_stretch, 0.0001), "max_weapon_mismatch_m": weapon_mismatch}
	check(weapon_mismatch < 0.00001, "drawn_weapon_equals_rules_segment_every_tick", {"samples": samples, "max_mismatch_m": weapon_mismatch})
	check(max_error < GRIP_TOLERANCE, "right_fist_on_grip_all_weapons_directions_guards", results.grip_sweep)
	check(max_left < GRIP_TOLERANCE and two_hand_on > two_hand_samples * 0.6, "two_handed_second_fist_on_grip_when_reachable",
		{"error": max_left, "on_hilt": two_hand_on, "samples": two_hand_samples})
	check(max_stretch <= MAX_STRETCH, "arm_reach_within_stretch_limit", {"max": max_stretch, "worst": results.get("worst_stretch", "")})

func _view(state: State, extra := {}) -> Dictionary:
	var progress := 0.0
	if state.phase == State.Phase.DODGE:
		progress = 1.0 - state.remaining / state.t.dodge_duration
	elif state.phase == State.Phase.ROLL:
		progress = state.roll_elapsed / state.t.roll_duration
	var view := {"phase": state.phase, "hand": state.hand, "dir": state.dir, "direction": state.direction, "guarding": state.guarding,
		"guard": state.guard, "two_handed": state.h.two_handed, "inertia": state.h.inertia, "omega": state.omega,
		"velocity": Vector3.ZERO, "dodge_dir": Vector3.BACK, "progress": clampf(progress, 0.0, 1.0),
		"posture": state.posture / state.max_posture, "look": Vector3(0, 1.5, -2.5), "released": state.released}
	view.merge(extra, true)
	return view

# --- Presentation of guard, dodge, roll, hit, posture, death --------------------------------

func presentation_checks() -> void:
	var items := _weapon_items()
	var sword: Dictionary = items["item.notched_sword"]
	# Guard: the blade's edge faces the guarded side; the stance lowers.
	var facing := {}
	var faces_ok := true
	for guard: String in ["right", "high_right", "high", "high_left", "left"]:
		var state := State.new(tuning, sword, {})
		var solver := PoseSolver.new(Rig.PILGRIM)
		state.set_guard(true, guard)
		for i in range(60):
			state.tick(DT)
			solver.solve(_view(state), DT)
		var side := Geometry.frontal(Geometry.guard_vector(guard))
		var along := absf(solver.edge_axis.dot((side - state.dir * side.dot(state.dir)).normalized()))
		facing[guard] = snappedf(along, 0.001)
		faces_ok = faces_ok and along > 0.95
	check(faces_ok, "guard_edge_faces_guarded_side", facing)
	var idle := PoseSolver.new(Rig.PILGRIM)
	var guard_solver := PoseSolver.new(Rig.PILGRIM)
	var s_idle := State.new(tuning, sword, {})
	var s_guard := State.new(tuning, sword, {})
	s_guard.set_guard(true, "high")
	var pelvis_idle := 0.0
	var pelvis_guard := 0.0
	for i in range(90):
		s_idle.tick(DT)
		s_guard.tick(DT)
		pelvis_idle = (idle.solve(_view(s_idle), DT).bones.pelvis as Transform3D).origin.y
		pelvis_guard = (guard_solver.solve(_view(s_guard), DT).bones.pelvis as Transform3D).origin.y
	check(pelvis_guard < pelvis_idle - 0.02, "held_guard_lowers_stance", {"idle": snappedf(pelvis_idle, 0.001), "guard": snappedf(pelvis_guard, 0.001)})

	# Dodge: the body leans and shifts toward the dodge; the weapon stays the rules pose.
	var dodge_state := State.new(tuning, sword, {})
	var dodge_solver := PoseSolver.new(Rig.PILGRIM)
	dodge_state.dodge()
	var max_shift := 0.0
	var dodge_exact := true
	while dodge_state.phase == State.Phase.DODGE:
		dodge_state.tick(DT)
		var pose := dodge_solver.solve(_view(dodge_state, {"dodge_dir": Vector3.RIGHT}), DT)
		max_shift = maxf(max_shift, (pose.bones.pelvis as Transform3D).origin.x)
		dodge_exact = dodge_exact and (pose.weapon as Transform3D).origin.distance_to(dodge_state.hand) < 0.00001
	check(max_shift > 0.03 and dodge_exact, "dodge_shifts_body_toward_dodge_weapon_exact", snappedf(max_shift, 0.001))

	# Roll: a full tumble (the head passes below the pelvis), the weapon is free only
	# during ROLL and is back on the rules pose from the first tick after it.
	var roll_state := State.new(tuning, sword, {})
	var roll_solver := PoseSolver.new(Rig.PILGRIM)
	roll_state.roll()
	var inverted := false
	var free_outside := false
	var ticks := 0
	while ticks < 90:
		roll_state.tick(DT)
		var pose := roll_solver.solve(_view(roll_state, {"dodge_dir": Vector3.BACK}), DT)
		if roll_state.phase == State.Phase.ROLL:
			if (pose.bones.head as Transform3D).origin.y < (pose.bones.pelvis as Transform3D).origin.y:
				inverted = true
		else:
			if pose.weapon_free or (pose.weapon as Transform3D).origin.distance_to(roll_state.hand) > 0.00001:
				free_outside = true
		ticks += 1
	check(inverted, "roll_tumbles_body", inverted)
	check(not free_outside, "weapon_free_only_during_roll", free_outside)

	# Hit reaction: a kick moves the trunk away from the blow and settles.
	var hit_solver := PoseSolver.new(Rig.PILGRIM)
	var calm_solver := PoseSolver.new(Rig.PILGRIM)
	var hit_state := State.new(tuning, sword, {})
	for i in range(60):
		hit_state.tick(DT)
		hit_solver.solve(_view(hit_state), DT)
		calm_solver.solve(_view(hit_state), DT)
	hit_solver.kick(Vector3.BACK, 1.0)
	var peak := 0.0
	var offset := 0.0
	for i in range(150):
		hit_state.tick(DT)
		var kicked := (hit_solver.solve(_view(hit_state), DT).bones.head as Transform3D).origin
		var calm := (calm_solver.solve(_view(hit_state), DT).bones.head as Transform3D).origin
		offset = kicked.z - calm.z
		peak = maxf(peak, offset)
	check(peak > 0.03 and absf(offset) < 0.01, "hit_kick_recoils_and_settles", {"peak": snappedf(peak, 0.001), "final": snappedf(offset, 0.001)})

	# Posture damage reads as a lower, more hunched stance.
	var tired := PoseSolver.new(Rig.PILGRIM)
	var fresh := PoseSolver.new(Rig.PILGRIM)
	var s := State.new(tuning, sword, {})
	var low := 0.0
	var high := 0.0
	for i in range(90):
		high = (fresh.solve(_view(s), DT).bones.pelvis as Transform3D).origin.y
		low = (tired.solve(_view(s, {"posture": 0.9}), DT).bones.pelvis as Transform3D).origin.y
	check(low < high - 0.02, "posture_damage_lowers_stance", {"fresh": snappedf(high, 0.001), "near_break": snappedf(low, 0.001)})

	# Death / release: the body falls and lies low; the weapon lands on the floor.
	var dead := State.new(tuning, sword, {})
	var dead_solver := PoseSolver.new(Rig.CORRUPTED)
	dead.take_damage(1000.0)
	var pose_dead: Dictionary = {}
	for i in range(120):
		pose_dead = dead_solver.solve(_view(dead), DT)
	check((pose_dead.bones.head as Transform3D).origin.y < 0.6 and (pose_dead.weapon as Transform3D).origin.y < 0.1,
		"death_body_falls_and_weapon_lands", {"head_y": snappedf((pose_dead.bones.head as Transform3D).origin.y, 0.001), "weapon_y": snappedf((pose_dead.weapon as Transform3D).origin.y, 0.001)})

	# The drawn torso stays near the hurt capsule (visual-to-contact mapping) outside
	# roll and death, across a swing of every weapon.
	var worst := 0.0
	for item: String in ["item.lab_long_knife", "item.notched_sword", "item.lab_greatsword"]:
		for direction: String in Geometry.DIRECTIONS:
			var st := State.new(tuning, items[item], {})
			var sv := PoseSolver.new(Rig.PILGRIM)
			st.press_attack(direction)
			st.release_attack()
			for i in range(90):
				st.tick(DT)
				var bones: Dictionary = sv.solve(_view(st), DT).bones
				for bone: String in ["pelvis", "spine_02", "spine_03"]:
					var o: Vector3 = (bones[bone] as Transform3D).origin
					worst = maxf(worst, Vector2(o.x, o.z).length())
	check(worst < tuning.body_radius, "trunk_inside_hurt_capsule_radius", {"max_horizontal_m": snappedf(worst, 0.001), "capsule_radius": tuning.body_radius})
	results.trunk_offset_max = worst

func data_checks() -> void:
	var loaded := Showcase.load_showcase()
	check(loaded.ok, "showcase_data_valid", loaded.errors)
	var layout := CryptBuilder.load_layout()
	check(layout.ok and layout.data.pieces.size() > 50, "crypt_layout_valid", {"errors": layout.errors, "pieces": layout.data.pieces.size() if layout.ok else 0})
	# Same layout → identical geometry (determinism for future generated rooms).
	var a := CryptBuilder.build_geometry(layout.data)
	var b := CryptBuilder.build_geometry(layout.data)
	var ma: ArrayMesh = a.kit.commit()
	var mb: ArrayMesh = b.kit.commit()
	var same := ma.get_surface_count() == mb.get_surface_count()
	for i in range(ma.get_surface_count()):
		same = same and ma.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] == mb.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	check(same and a.collision.size() == b.collision.size(), "crypt_assembly_deterministic", {"surfaces": ma.get_surface_count(), "triangles": a.kit.triangle_count})
	results.crypt = {"pieces": layout.data.pieces.size(), "triangles": a.kit.triangle_count, "surfaces": ma.get_surface_count(), "collision_boxes": a.collision.size()}
	# Duel floor clear: no collision box intrudes within 4.5 m of the duel centre.
	var intruders: Array = a.collision.filter(func(entry: Array) -> bool:
		var xf: Transform3D = entry[0]
		var size: Vector3 = entry[1]
		var top: float = xf.origin.y + size.y * 0.5
		return top > 0.05 and Vector2(xf.origin.x, xf.origin.z - 0.9).length() < 4.0)
	check(intruders.is_empty(), "duel_floor_clear_of_collision", intruders.size())

# --- Scene (engine path) ---------------------------------------------------------------------

func _arena(environment := true) -> Node:
	var arena: Node = load("res://scenes/visual_showcase.tscn").instantiate()
	arena.build_environment = environment
	arena.manual_step = true
	root.add_child(arena)
	await process_frame
	await process_frame
	return arena

## The engine's BoneAttachment3D sockets (after the SkeletonModifier3D ran) agree with
## the rules grip in world space.
func scene_socket_checks() -> void:
	var arena: Node = await _arena(false)
	arena.opponent.mode = "dummy"
	var player: Node = arena.player
	player.state.press_attack("overhead")
	var worst := 0.0
	var tip_worst := 0.0
	for i in range(70):
		if i == 40:
			player.state.release_attack()
		arena.advance(DT)
		await process_frame
		await process_frame
		var skeleton: Skeleton3D = player.visual.skeleton
		var socket: Marker3D = skeleton.get_node("socket_grip_r/point")
		var rules_world: Vector3 = player.xform() * player.state.hand
		worst = maxf(worst, socket.global_position.distance_to(rules_world))
		var tip: Marker3D = player.visual.weapon_node.get_node("tip")
		var rules_tip: Vector3 = player.xform() * Geometry.tip({"hand": player.state.hand, "dir": player.state.dir}, player.state.h.length)
		tip_worst = maxf(tip_worst, tip.global_position.distance_to(rules_tip))
	check(worst < 0.01, "engine_grip_socket_on_rules_hand", snappedf(worst, 0.00001))
	check(tip_worst < 0.0005, "engine_weapon_tip_on_rules_tip", snappedf(tip_worst, 0.00001))
	results.engine_socket = {"grip_error_m": worst, "tip_error_m": tip_worst}
	arena.queue_free()
	await process_frame

## Real mouse input: chamber right, flick to the left side; the presentation follows
## the rules' forward-neutral re-chamber (never swinging behind the body) and the fist
## stays on the grip throughout.
func input_chamber_checks() -> void:
	var arena: Node = await _arena(false)
	arena.manual_step = false
	var player: Node = arena.player
	player.accept_uncaptured_motion = true
	arena.opponent.mode = "dummy"
	await press_mouse(MOUSE_BUTTON_LEFT, true)
	motion(Vector2(60, 0))
	await frames_wait(30)
	var first: String = player.state.direction
	motion(Vector2(-120, 0))
	var behind := 0.0
	var neutral_seen := false
	var grip_error := 0.0
	var directions: Array[String] = []
	for i in range(60):
		await physics_frame
		await process_frame
		var s: State = player.state
		if not directions.has(s.direction):
			directions.append(s.direction)
		neutral_seen = neutral_seen or s.rechamber_to_neutral
		behind = maxf(behind, Geometry.tip({"hand": s.hand, "dir": s.dir}, s.h.length).z)
		var pose: Dictionary = player.visual.last_pose
		var drawn_from: Vector3 = player.visual.last_view.hand
		grip_error = maxf(grip_error, Rig.socket_global(pose.bones, "grip_r").origin.distance_to(drawn_from))
	await press_mouse(MOUSE_BUTTON_LEFT, false)
	await frames_wait(40)
	check(first == "right_to_left" and directions.has("left_to_right") and neutral_seen, "mouse_flick_rechambers_through_neutral",
		{"first": first, "seen": directions, "neutral": neutral_seen})
	check(behind < 1.2 and grip_error < GRIP_TOLERANCE, "drawn_rechamber_stays_in_front_fist_on_grip",
		{"max_tip_z": snappedf(behind, 0.001), "grip_error": snappedf(grip_error, 0.00001)})
	check(player.state.last_swung == "left_to_right", "released_redirected_cut_swings_aimed_side", player.state.last_swung)
	arena.queue_free()
	await process_frame

func press_mouse(button: MouseButton, pressed: bool) -> void:
	var action := "lab_attack" if button == MOUSE_BUTTON_LEFT else "lab_guard"
	var event: InputEventMouseButton = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame

func motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)

func frames_wait(count: int) -> void:
	for i in range(count):
		await physics_frame

## Equipment swapping goes through the lab adapter and the shared build rules; rules
## state is derived exactly as for the same items in the melee lab.
func equipment_swap_checks() -> void:
	var arena: Node = await _arena(false)
	var player: Node = arena.player
	var seen := {}
	var derived_ok := true
	var nodes_before := -1
	for weapon: String in Showcase.WEAPON_KEYS:
		for armor: String in Showcase.ARMOR_KEYS:
			var accepted: bool = arena.select("player", {"weapon": weapon, "armor": armor})
			await process_frame
			await process_frame
			var visual: Node = player.visual
			var resolved := Loadout.resolve(arena.lab, "player", Showcase.loadout_id(arena.selection.player))
			var expected := CombatResources.derive(Handling.derive(resolved.weapon, arena.tuning), str(resolved.weapon.item), resolved.armor, resolved.combat, arena.tuning)
			derived_ok = derived_ok and accepted and is_equal_approx(player.state.resources.attack_cost, expected.attack_cost) and \
				is_equal_approx(player.state.resources.mitigation, expected.mitigation) and player.state.h.item == str(resolved.weapon.item)
			var layers: Array = visual.skeleton.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D).map(func(n: Node) -> String: return n.name)
			seen["%s.%s" % [weapon, armor]] = {"layers": layers, "triangles": visual.triangles, "weapon": visual.weapon_node.get_child(0).name,
				"weapon_triangles": visual.weapon_triangles, "attack_cost": snappedf(player.state.resources.attack_cost, 0.01)}
			if nodes_before < 0:
				nodes_before = _count(arena)
	check(derived_ok, "swapped_equipment_derives_lab_rules_state", seen.size())
	var armored := seen["heavy.plate"].layers as Array
	var bare := seen["light.none"].layers as Array
	check("Armor_lab_bog_iron_plate" in armored and not "Armor_lab_bog_iron_plate" in bare and seen["heavy.plate"].triangles > seen["light.none"].triangles,
		"armor_layers_follow_selection", {"plate": armored, "none": bare})
	check(absf(_count(arena) - nodes_before) <= 2, "swapping_leaks_no_nodes", {"first": nodes_before, "last": _count(arena)})
	results.equipment = seen
	# The shared grip rule: a two-handed greatsword is rejected beside the handless arm.
	arena.select("opponent", {"weapon": "medium", "marrow_arm": true})
	var rejected: bool = not arena.select("opponent", {"weapon": "heavy"})
	check(rejected and arena.selection.opponent.weapon == "medium", "greatsword_with_marrow_arm_rejected_by_build_rules", arena.notice)
	var accepted_marrow: bool = arena.select("opponent", {"weapon": "light", "marrow_arm": true})
	await process_frame
	var module_layers: Array = arena.opponent.visual.skeleton.get_children().map(func(n: Node) -> String: return n.name)
	check(accepted_marrow and "Module_marrow_arm" in module_layers, "marrow_arm_module_attached_when_equipped", module_layers)
	arena.queue_free()
	await process_frame

func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _count(child)
	return total

## The same scripted exchanges and a seeded AI duel produce byte-identical contact logs
## in the melee lab and in the showcase (both stepped manually with the same inputs,
## with a rendered/processed frame between ticks so the presentation runs as in play).
func outcome_equivalence_checks() -> void:
	var logs: Array[String] = []
	for scene: String in ["res://scenes/melee_lab.tscn", "res://scenes/visual_showcase.tscn"]:
		var arena: Node = load(scene).instantiate()
		arena.manual_step = true
		root.add_child(arena)
		await process_frame
		var lines: Array[String] = []
		arena.player.input_enabled = false # Scripted player (the controller would clear the guard).
		for pairing: Array in [["balanced", "balanced"], ["resistant", "evasive"], ["knife", "greatsword"]]:
			arena.set_loadouts(pairing[0], pairing[1])
			arena.opponent.mode = "duel"
			arena.opponent.reset_ai()
			var script := [[10, "press", "right_to_left"], [40, "release", ""], [120, "press", "overhead"], [150, "release", ""],
				[230, "guard", "high"], [300, "unguard", ""], [330, "roll", ""], [380, "press", "thrust"], [400, "release", ""]]
			for tick in range(600):
				for step: Array in script:
					if step[0] == tick:
						match step[1]:
							"press":
								arena.player.state.press_attack(step[2])
							"release":
								arena.player.state.release_attack()
							"guard":
								arena.player.state.set_guard(true, step[2])
							"unguard":
								arena.player.state.set_guard(false)
							"roll":
								arena.player.try_roll(Vector3.BACK)
				arena.advance(DT)
				# Presentation runs every frame between ticks, as in play.
				await process_frame
			for e: Dictionary in arena.events:
				lines.append("%s %s>%s %s dmg=%.4f post=%.4f hp=%.4f" % [e.at, e.attacker, e.defender, e.result, e.damage, e.posture, e.defender_health])
			lines.append("end %s hp %.4f/%.4f stamina %.4f/%.4f" % [pairing, arena.player.state.health, arena.opponent.state.health,
				arena.player.state.stamina.current, arena.opponent.state.stamina.current])
		logs.append("\n".join(lines))
		arena.queue_free()
		await process_frame
	var file := FileAccess.open(output.path_join("outcomes_lab.txt"), FileAccess.WRITE)
	file.store_string(logs[0] + "\n")
	file = FileAccess.open(output.path_join("outcomes_showcase.txt"), FileAccess.WRITE)
	file.store_string(logs[1] + "\n")
	var contacts := logs[0].count(">")
	check(logs[0] == logs[1] and contacts >= 6, "combat_outcomes_identical_to_melee_lab", {"contacts": contacts})

func isolation_checks() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "default_launch_scene_unchanged")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "project_renderer_still_gl_compatibility")
	var offenders: Array[String] = []
	for dir_path: String in ["res://scripts/combat", "res://scripts/characters", "res://scripts/ai", "res://scripts/expedition", "res://scripts/melee_lab",
			"res://scripts/directional_expedition", "res://scripts/expedition_preview"]:
		for file: String in DirAccess.get_files_at(dir_path):
			if file.ends_with(".gd") and FileAccess.get_file_as_string(dir_path.path_join(file)).contains("visual_showcase"):
				offenders.append(dir_path.path_join(file))
	check(offenders.is_empty(), "no_game_or_lab_script_references_the_showcase", offenders)
