extends SceneTree
## Deterministic checks and measurements for the isolated animation lab. Prints one JSON
## line per check plus a summary, like the other suites; exit code 1 on any failure.
## Pure-logic checks need nothing; character checks need the pinned trial asset
## (scripts/tooling/fetch_animation_trial.sh). Metrics are written to --evidence-dir.
## Measures what code can measure (slip, alignment, grip, traces). It cannot judge feel.

const PhaseWarp := preload("res://scripts/animation_lab/phase_warp.gd")
const WeaponTrace := preload("res://scripts/animation_lab/weapon_trace.gd")
const ClipLibrary := preload("res://scripts/animation_lab/clip_library.gd")
const LabCharacter := preload("res://scripts/animation_lab/lab_character.gd")
const LabActor := preload("res://scripts/animation_lab/lab_actor.gd")
const DT := 1.0 / 60.0
## Ball-of-foot joint height that counts as ground contact (rest height is 0.015 m).
const PLANTED_HEIGHT := 0.035
const LAB_SCRIPTS := ["res://scripts/animation_lab/phase_warp.gd", "res://scripts/animation_lab/weapon_trace.gd",
	"res://scripts/animation_lab/clip_library.gd", "res://scripts/animation_lab/lab_character.gd",
	"res://scripts/animation_lab/lab_actor.gd", "res://scripts/animation_lab/extra_limbs.gd",
	"res://scripts/animation_lab/animation_lab.gd"]

var passed := 0
var failed := 0
var metrics := {}
var manifest: Dictionary
## --negative=warp shifts the actor's contact marker 0.1 s late (clip and rules disagree);
## the alignment check must then fail.
var negative := ""

func check(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	print(JSON.stringify({"suite": "animation_lab", "check": label, "passed": condition, "detail": detail}))

func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

func _init() -> void:
	await process_frame
	manifest = ClipLibrary.load_json(ClipLibrary.MANIFEST_PATH)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--negative="):
			negative = arg.get_slice("=", 1)
	test_phase_warp()
	test_timing_sources()
	test_weapon_trace_math()
	test_isolation()
	var trial := ClipLibrary.trial_dir()
	var problems := ClipLibrary.verify_trial(trial)
	check(problems.is_empty(), "trial_asset_present_and_verified", problems)
	if problems.is_empty():
		test_library(trial)
		test_additive(trial)
		test_grip_and_alignment(trial)
		test_traces(trial)
		test_foot_slip(trial)
		test_root_motion(trial)
		await test_four_arms(trial)
	_write_metrics()
	print(JSON.stringify({"suite": "animation_lab", "summary": true, "passed": passed, "failed": failed}))
	quit(1 if failed > 0 else 0)

func _write_metrics() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			var dir := arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(dir)
			var file := FileAccess.open(dir.path_join("animation_lab_metrics.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(metrics, "\t", true) + "\n")

# --- Pure logic -------------------------------------------------------------------

func test_phase_warp() -> void:
	var markers: Dictionary = manifest.clips.slash.markers
	var timing := {"windup": 0.34, "commitment": 0.24, "release": 0.08, "active": 0.16, "recovery": 0.45}
	check(PhaseWarp.validate(markers, timing).is_empty(), "warp_valid_markers")
	var missing := markers.duplicate()
	missing.erase("contact")
	check(PhaseWarp.validate(missing, timing).size() > 0, "warp_rejects_missing_marker")
	var unordered := markers.duplicate()
	unordered.loaded = 0.5
	check(PhaseWarp.validate(unordered, timing).size() > 0, "warp_rejects_unordered_markers")
	check(PhaseWarp.validate(markers, {"windup": 0.2, "commitment": 0.24, "release": 0.08, "active": 0.16, "recovery": 0.45}).size() > 0, "warp_rejects_commitment_longer_than_windup")
	# Key poses land exactly on rule boundaries.
	var boundaries := {0.0: "start", 0.10: "loaded", 0.26: "release", 0.34: "contact", 0.50: "active_end", 0.95: "recovered"}
	for t in boundaries:
		var sample := PhaseWarp.sample(markers, timing, t)
		check(near(sample.clip_time, float(markers[boundaries[t]]), 1e-6), "warp_boundary_%s" % boundaries[t], sample)
	check(PhaseWarp.sample(markers, timing, 0.30).section == "release" and PhaseWarp.sample(markers, timing, 0.34 + 1e-6).section == "active", "warp_sections_follow_combat_stages")
	var previous := -1.0
	var monotonic := true
	for i in 200:
		var clip_time: float = PhaseWarp.sample(markers, timing, i * 0.005).clip_time
		monotonic = monotonic and clip_time >= previous
		previous = clip_time
	check(monotonic, "warp_monotonic")
	check(near(PhaseWarp.sample(markers, timing, 9.0).clip_time, float(markers.recovered), 1e-6), "warp_holds_after_end")
	# CombatState exposes phase + remaining; reconstruct rule time from it.
	check(near(PhaseWarp.rule_time_from_phase("windup", 0.24, timing), 0.10, 1e-6)
		and near(PhaseWarp.rule_time_from_phase("active", 0.16, timing), 0.34, 1e-6)
		and near(PhaseWarp.rule_time_from_phase("recovery", 0.0, timing), 0.95, 1e-6), "warp_from_combat_phase_and_remaining")
	var source := LabActor.resolve_timing(manifest, "source_pacing")
	var unity := true
	for ratio in PhaseWarp.warp_ratios(markers, source).values():
		unity = unity and near(ratio, 1.0, 0.01)
	check(unity, "source_pacing_is_identity_warp", PhaseWarp.warp_ratios(markers, source))
	var knots := PackedVector2Array([Vector2(0, 0), Vector2(0.1, 0.15), Vector2(1.0, 0.65), Vector2(1.3, 1.2)])
	check(near(PhaseWarp.piecewise(knots, 0.05), 0.075, 1e-6) and near(PhaseWarp.piecewise(knots, 2.0), 1.2, 1e-6), "piecewise_map")

func test_timing_sources() -> void:
	var courtyard := LabActor.resolve_timing(manifest, "courtyard_slash")
	var swordsman := LabActor.resolve_timing(manifest, "swordsman_slash")
	check(near(courtyard.windup, 0.34, 1e-6) and near(courtyard.active, 0.16, 1e-6) and near(courtyard.recovery, 0.45, 1e-6), "courtyard_slash_timing_from_catalog", courtyard)
	check(near(swordsman.windup, 0.62, 1e-6) and near(swordsman.recovery, 0.65, 1e-6), "swordsman_override_applied", swordsman)
	var ratios := {}
	for name in ["source_pacing", "courtyard_slash", "swordsman_slash"]:
		ratios[name] = PhaseWarp.warp_ratios(manifest.clips.slash.markers, LabActor.resolve_timing(manifest, name))
	metrics["warp_ratios"] = ratios

func test_weapon_trace_math() -> void:
	check(near(WeaponTrace.segment_distance(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)), 1.0, 1e-6), "segment_distance_parallel")
	check(near(WeaponTrace.segment_distance(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 1), Vector3(0, 1, 1)), 1.0, 1e-6), "segment_distance_crossing")
	check(near(WeaponTrace.segment_distance(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 0)), 3.0, 1e-6), "segment_distance_points")
	# A blade sweeping 1.2 m per tick past a 4 cm pole: point sampling misses, sweeping hits.
	var pole_a := Vector3(0.0, 0.0, -1.0)
	var pole_b := Vector3(0.0, 2.0, -1.0)
	var samples := [
		{"t": 0.0, "live": true, "base": Vector3(-0.2, 1.0, -0.2), "tip": Vector3(-0.6, 1.0, -1.0)},
		{"t": 1.0 / 30.0, "live": true, "base": Vector3(0.2, 1.0, -0.2), "tip": Vector3(0.6, 1.0, -1.0)}]
	check(WeaponTrace.first_contact(samples, pole_a, pole_b, 0.04, false) == -1, "point_sampling_tunnels_thin_target")
	check(WeaponTrace.first_contact(samples, pole_a, pole_b, 0.04, true) == 1, "swept_sampling_catches_thin_target")
	samples[1].live = false
	check(WeaponTrace.first_contact(samples, pole_a, pole_b, 0.04, true) == -1, "rule_window_gates_contact")

func test_isolation() -> void:
	var forbidden := ["scripts/combat/", "scripts/characters/", "scripts/ai/", "hud.gd", "courtyard.gd", "scripts/builds/", "scripts/anatomy/"]
	var clean := true
	var offenders := []
	for path in LAB_SCRIPTS:
		var text := FileAccess.get_file_as_string(path)
		for needle in forbidden:
			if text.contains(needle):
				clean = false
				offenders.append("%s -> %s" % [path, needle])
	check(clean, "lab_references_no_combat_actor_ai_hud_build_or_anatomy_code", offenders)
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/first_expedition.tscn", "playable_entrypoint_selected")

# --- Character checks ---------------------------------------------------------------

func spawn(trial: String, options: Dictionary = {}) -> LabCharacter:
	var character := LabCharacter.new()
	get_root().add_child(character)
	var errors: PackedStringArray = character.setup(trial, options)
	check(errors.is_empty(), "character_setup_%s" % JSON.stringify(options), errors)
	return character

func test_library(trial: String) -> void:
	var character := spawn(trial)
	var skeleton: Skeleton3D = character.skeleton
	check(skeleton.get_bone_count() == 66, "trial_skeleton_bone_count", skeleton.get_bone_count())
	var all := true
	for clip in manifest.clips:
		all = all and character.tree.has_animation(clip)
	check(all, "library_has_every_manifest_clip")
	var loops := true
	for clip in manifest.clips:
		var expected := Animation.LOOP_LINEAR if manifest.clips[clip].loop else Animation.LOOP_NONE
		loops = loops and character.tree.get_animation(clip).loop_mode == expected
	check(loops, "loop_flags_applied")
	var slash: Animation = character.tree.get_animation("slash")
	var marker_ok := true
	for marker in manifest.clips.slash.markers:
		marker_ok = marker_ok and slash.has_marker(marker) and near(slash.get_marker_time(marker), float(manifest.clips.slash.markers[marker]), 1e-4)
	check(marker_ok, "slash_markers_embedded", slash.get_marker_names())
	var bone_only := true
	for clip in manifest.clips:
		var animation: Animation = character.tree.get_animation(clip)
		for track in animation.get_track_count():
			bone_only = bone_only and skeleton.find_bone(ClipLibrary.bone_of(animation, track)) >= 0
	check(bone_only, "library_keeps_only_bone_tracks")
	# Source audit: how many raw trial clips also key a non-bone node (the Armature object).
	var raw := ClipLibrary.load_scene(trial, "base")
	var raw_player := ClipLibrary.source_player(raw)
	var object_tracks := []
	for clip in raw_player.get_animation_list():
		var animation := raw_player.get_animation(clip)
		for track in animation.get_track_count():
			if skeleton.find_bone(ClipLibrary.bone_of(animation, track)) < 0:
				object_tracks.append(clip)
				break
	var raw_count := raw_player.get_animation_list().size()
	raw.free()
	metrics["raw_base_clips_with_non_bone_tracks"] = {"count": object_tracks.size(), "of": raw_count, "clips": object_tracks}
	check(object_tracks.has("Hit_Chest"), "source_audit_finds_armature_track_in_hit_chest", object_tracks.size())
	var in_place := true
	for clip in manifest.clips:
		if manifest.clips[clip].root != "in_place":
			continue
		var animation: Animation = character.tree.get_animation(clip)
		var track := animation.find_track(NodePath("Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D)
		if track >= 0:
			var first: Vector3 = animation.track_get_key_value(track, 0)
			for key in animation.track_get_key_count(track):
				in_place = in_place and (animation.track_get_key_value(track, key) as Vector3).is_equal_approx(first)
	check(in_place, "in_place_clips_hold_root")
	# Loop seams: distance every bone moves between the last and first frame of a loop.
	var seams := {}
	for clip in manifest.clips:
		if manifest.clips[clip].loop:
			seams[clip] = snappedf(_seam(character, clip), 0.0001)
	metrics["loop_seam_max_bone_gap_m"] = seams
	# Defect ledger: clips that declare a loop_seam defect must still show it, the rest must not.
	var ledger_honest := true
	for clip in seams:
		var declared: bool = str(manifest.clips[clip].get("known_defects", [])).contains("loop_seam")
		ledger_honest = ledger_honest and (seams[clip] >= 0.02 if declared else seams[clip] < 0.02)
	check(ledger_honest, "loop_seam_defects_match_manifest_ledger", seams)
	metrics["stride_speeds_mps"] = character.stride_speeds
	character.free()

func _pose(character: LabCharacter, clip: String, time: float) -> Array:
	var player := AnimationPlayer.new()
	character.visual.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	library.add_animation("probe", character.tree.get_animation(clip))
	player.add_animation_library("", library)
	player.play("probe")
	player.seek(time, true)
	var pose := []
	for bone in character.skeleton.get_bone_count():
		pose.append(character.skeleton.get_bone_global_pose(bone).origin)
	player.free()
	return pose

func _seam(character: LabCharacter, clip: String) -> float:
	var animation: Animation = character.tree.get_animation(clip)
	var first := _pose(character, clip, 0.0)
	var last := _pose(character, clip, animation.length - 0.0001)
	var gap := 0.0
	for i in first.size():
		gap = maxf(gap, (first[i] - last[i]).length())
	return gap

func test_additive(trial: String) -> void:
	var character := spawn(trial)
	var skeleton: Skeleton3D = character.skeleton
	var flinch: Animation = character.tree.get_animation("flinch")
	var identity := true
	for track in flinch.get_track_count():
		if flinch.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(ClipLibrary.bone_of(flinch, track))
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		identity = identity and (flinch.track_get_key_value(track, 0) as Quaternion).angle_to(rest) < 2e-3
	check(identity, "additive_clip_first_frame_is_rest")
	# Engine semantics: idle with the additive layer fired at its first frame must equal idle.
	character.set_locomotion(Vector2.ZERO)
	for i in 30:
		character.step(DT)
	var before := _hand_world(character)
	var fired := spawn(trial)
	fired.set_locomotion(Vector2.ZERO)
	for i in 30:
		fired.step(DT)
	fired.flinch()
	fired.step(0.0)
	check(before.distance_to(_hand_world(fired)) < 0.005, "additive_layer_neutral_at_first_frame", before.distance_to(_hand_world(fired)))
	for i in 12:
		fired.step(DT)
		character.step(DT)
	var pelvis := skeleton.find_bone("pelvis")
	var lift := absf((fired.skeleton.global_transform * fired.skeleton.get_bone_global_pose(pelvis).origin).y - (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis).origin).y)
	metrics["flinch_pelvis_height_change_m"] = snappedf(lift, 0.0001)
	check(lift < 0.05, "additive_flinch_keeps_body_grounded", lift)
	var deflection := _hand_world(character).distance_to(_hand_world(fired))
	metrics["flinch_hand_deflection_m"] = snappedf(deflection, 0.0001)
	check(deflection > 0.01, "additive_layer_moves_pose_mid_reaction", deflection)
	character.free()
	fired.free()

func _hand_world(character: LabCharacter) -> Vector3:
	var skeleton: Skeleton3D = character.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_r")).origin

func _run_attack(character: LabCharacter, timing_name: String, velocity := Vector2.ZERO, dt := DT) -> Array:
	var actor := LabActor.new(character)
	if negative == "warp":
		actor.manifest.clips.slash.markers.contact = float(manifest.clips.slash.markers.contact) + 0.1
	actor.schedule([{"at": 0.0, "do": "idle", "velocity": [velocity.x, velocity.y]}, {"at": 0.5, "do": "attack", "timing": timing_name, "velocity": [velocity.x, velocity.y]}])
	var timing := LabActor.resolve_timing(manifest, timing_name)
	var samples := []
	var steps := int(round((0.5 + PhaseWarp.total_duration(timing)) / dt))
	for i in steps:
		actor.step(dt)
		if actor.clock > 0.5 + 1e-6 and str(actor.command.get("do", "")) == "attack":
			var points: Array = character.blade_points()
			var to_local := character.global_transform.affine_inverse()
			var playback: AnimationNodeStateMachinePlayback = character.tree.get("parameters/action/playback")
			samples.append({"t": actor.command_time, "live": actor.blade_live, "section": actor.section,
				"base": to_local * points[0], "tip": to_local * points[1], "world_tip": points[1],
				"clip_position": playback.get_current_play_position(), "attachment_tip": _attachment_tip(character)})
	return samples

func _attachment_tip(character: LabCharacter) -> Vector3:
	var socket: BoneAttachment3D = character.skeleton.get_node("WeaponSocket")
	socket.on_skeleton_update()
	return character.blade_tip.global_position

func test_grip_and_alignment(trial: String) -> void:
	var character := spawn(trial)
	var samples := _run_attack(character, "courtyard_slash")
	var grip_error := 0.0
	var length_error := 0.0
	var blade_length: float = float(manifest.weapon.blade_tip) - float(manifest.weapon.blade_base)
	for sample in samples:
		grip_error = maxf(grip_error, (sample.world_tip as Vector3).distance_to(sample.attachment_tip))
		length_error = maxf(length_error, absf((sample.tip - sample.base).length() - blade_length))
	check(grip_error < 0.002, "weapon_attachment_matches_hand_pose", grip_error)
	check(length_error < 1e-4, "blade_rigid_through_attack", length_error)
	# The clip's contact marker lands on the first live tick (one-tick tolerance).
	var first_live := -1
	for i in samples.size():
		if samples[i].live:
			first_live = i
			break
	var markers: Dictionary = manifest.clips.slash.markers
	var contact_error: float = absf(float(samples[first_live].clip_position) - float(markers.contact)) if first_live >= 0 else 99.0
	metrics["contact_marker_alignment_s"] = snappedf(contact_error, 0.0001)
	check(contact_error <= 0.035, "contact_marker_on_first_live_tick", contact_error)
	var live_ticks := 0
	for sample in samples:
		live_ticks += 1 if sample.live else 0
	check(live_ticks == int(round(0.16 / DT)), "live_ticks_match_rule_active_window", live_ticks)
	# Readability proxy: the blade stays out of the forward hit hemisphere until the rule
	# window opens, and is in it for most of the window. Character space faces -Z.
	var early_forward := 0
	var live_forward := 0
	for sample in samples:
		var forward: float = -((sample.base + sample.tip) * 0.5).z
		if sample.section in ["early", "committed", "release"] and forward > 0.2:
			early_forward += 1
		if sample.live and forward > 0.3:
			live_forward += 1
	check(early_forward == 0, "blade_not_in_front_before_rule_window", early_forward)
	check(live_forward >= int(0.8 * live_ticks), "blade_in_front_during_rule_window", {"forward": live_forward, "live": live_ticks})
	var lowest := 99.0
	for sample in samples:
		lowest = minf(lowest, (sample.world_tip as Vector3).y)
	metrics["slash_lowest_tip_height_m"] = snappedf(lowest, 0.001)
	character.free()

func test_traces(trial: String) -> void:
	var first := spawn(trial)
	var a := _run_attack(first, "courtyard_slash")
	first.free()
	var second := spawn(trial)
	var b := _run_attack(second, "courtyard_slash")
	second.free()
	var deviation := 0.0
	for i in mini(a.size(), b.size()):
		deviation = maxf(deviation, (a[i].tip as Vector3).distance_to(b[i].tip))
	check(a.size() == b.size() and deviation < 1e-4, "baked_trace_reproducible", deviation)
	var baked := WeaponTrace.to_data(a)
	metrics["baked_slash_trace_samples"] = baked.size()
	var peak := 0.0
	for i in range(1, a.size()):
		peak = maxf(peak, (a[i].tip as Vector3).distance_to(a[i - 1].tip) / DT)
	metrics["slash_peak_tip_speed_mps"] = snappedf(peak, 0.01)
	# Thin poles placed on the blade's live arc: compare point sampling at 30 Hz with sweeps.
	var thirty := []
	for i in range(0, a.size(), 2):
		thirty.append(a[i])
	# Ground truth: the same attack evaluated at 240 Hz. Poles sit on the true arc at times
	# between 60 Hz samples, so no method is tested against its own sample points.
	var dense_character := spawn(trial)
	var dense := _run_attack(dense_character, "courtyard_slash", Vector2.ZERO, 1.0 / 240.0)
	dense_character.free()
	var trials := {"placements": 0, "point_30hz": 0, "linear_sweep_30hz": 0, "linear_sweep_baked_60hz": 0}
	for i in dense.size():
		var sample: Dictionary = dense[i]
		if not sample.live or i % 4 != 2:
			continue
		var mid: Vector3 = (sample.base + sample.tip) * 0.5
		var pole_a := Vector3(mid.x, 0.0, mid.z)
		var pole_b := Vector3(mid.x, 2.2, mid.z)
		trials.placements += 1
		trials.point_30hz += 1 if WeaponTrace.first_contact(thirty, pole_a, pole_b, 0.03, false) >= 0 else 0
		trials.linear_sweep_30hz += 1 if WeaponTrace.first_contact(thirty, pole_a, pole_b, 0.03, true) >= 0 else 0
		trials.linear_sweep_baked_60hz += 1 if WeaponTrace.first_contact(a, pole_a, pole_b, 0.03, true) >= 0 else 0
	metrics["thin_pole_trials"] = trials
	# Point sampling tunnels; a linear sweep between sparse samples cuts inside the curved
	# arc (chord error); sweeping a densely evaluated authored trace closes the gap.
	check(trials.point_30hz < trials.placements, "point_sampling_tunnels_on_real_slash", trials)
	check(trials.linear_sweep_baked_60hz == trials.placements, "dense_baked_trace_sweep_hits_every_pole", trials)
	check(trials.linear_sweep_30hz >= trials.point_30hz, "linear_sweep_never_worse_than_points", trials)
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			dir = arg.get_slice("=", 1)
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
		FileAccess.open(dir.path_join("baked_slash_trace.json"), FileAccess.WRITE).store_string(JSON.stringify({"timing": "courtyard_slash", "space": "character-local metres, -Z forward", "samples": baked}, "\t", true) + "\n")

## Mean horizontal world speed of ball-of-foot joints while they touch the ground, over
## `seconds` of motion. The ball joint is the toe-roll pivot, so a planted foot reads ~0.
func _slip(character: LabCharacter, actor: LabActor, seconds: float) -> float:
	var skeleton: Skeleton3D = character.skeleton
	var feet := [skeleton.find_bone("ball_l"), skeleton.find_bone("ball_r")]
	var previous := {}
	var total := 0.0
	var count := 0
	for i in int(round(seconds / DT)):
		actor.step(DT)
		for foot in feet:
			var position: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin
			if previous.has(foot) and position.y < PLANTED_HEIGHT and previous[foot].y < PLANTED_HEIGHT:
				total += Vector2(position.x - previous[foot].x, position.z - previous[foot].z).length() / DT
				count += 1
			previous[foot] = position
	return total / maxi(count, 1)

func test_foot_slip(trial: String) -> void:
	var results := {}
	var matched := spawn(trial)
	var matched_actor := LabActor.new(matched)
	matched_actor.schedule([{"at": 0.0, "do": "move", "velocity": [0.0, 0.9]}])
	_slip(matched, matched_actor, 0.5)
	results["matched_walk_0.9"] = snappedf(_slip(matched, matched_actor, 3.0), 0.001)
	matched.free()
	# Negative control: claim the stride equals the body speed, so the walk plays at its
	# authored rate (scale 1.0) while code moves the body at 1.5 m/s.
	var unmatched := spawn(trial)
	var unmatched_actor := LabActor.new(unmatched)
	unmatched_actor.schedule([{"at": 0.0, "do": "move", "velocity": [0.0, 1.5]}])
	unmatched.stride_speeds.walk_forward = 1.5
	_slip(unmatched, unmatched_actor, 0.5)
	results["unmatched_walk_1.5_rate_1"] = snappedf(_slip(unmatched, unmatched_actor, 3.0), 0.001)
	var fast := spawn(trial)
	var fast_actor := LabActor.new(fast)
	fast_actor.schedule([{"at": 0.0, "do": "move", "velocity": [0.0, 1.5]}])
	_slip(fast, fast_actor, 0.5)
	results["matched_walk_1.5_rate_2"] = snappedf(_slip(fast, fast_actor, 3.0), 0.001)
	fast.free()
	unmatched.free()
	for split in [false, true]:
		var character := spawn(trial, {"split_lower_body": split})
		var actor := LabActor.new(character)
		actor.schedule([{"at": 0.0, "do": "move", "velocity": [0.0, 0.9]}, {"at": 0.5, "do": "attack", "timing": "swordsman_slash", "velocity": [0.0, 0.9]}])
		_slip(character, actor, 0.5)
		results["attack_while_moving_%s" % ("split" if split else "full_body")] = snappedf(_slip(character, actor, 1.4), 0.001)
		character.free()
	metrics["planted_foot_slip_mps"] = results
	# Rate matching removes gross sliding; the residual comes from uneven contact speed in
	# the authored cycle and is the job of foot-lock IK or cleanup, not of playback rate.
	check(results["matched_walk_0.9"] < 0.15 and results["matched_walk_1.5_rate_2"] < 0.15, "matched_walk_limits_residual_slide", results)
	check(results["unmatched_walk_1.5_rate_1"] > 4.0 * results["matched_walk_1.5_rate_2"], "unmatched_rate_slides", results)
	check(results["attack_while_moving_split"] < results["attack_while_moving_full_body"], "upper_lower_split_reduces_slide_while_attacking", results)

func test_root_motion(trial: String) -> void:
	var character := spawn(trial)
	var actor := LabActor.new(character)
	actor.schedule([{"at": 0.0, "do": "dodge", "duration": 1.0}])
	for i in 66:
		actor.step(DT)
	var clip: Animation = character.tree.get_animation("dodge_back")
	var track := clip.find_track(NodePath("Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D)
	var authored: Vector3 = clip.position_track_interpolate(track, clip.length) - clip.position_track_interpolate(track, 0.0)
	var moved: Vector3 = character.root_motion_total
	metrics["dodge_root_motion"] = {"authored_m": snappedf(Vector2(authored.x, authored.z).length(), 0.001), "applied_m": snappedf(Vector2(moved.x, moved.z).length(), 0.001), "applied_local_z": snappedf(moved.z, 0.001)}
	check(near(Vector2(moved.x, moved.z).length(), Vector2(authored.x, authored.z).length(), 0.02) and moved.z > 0.9, "dodge_root_motion_moves_backward_by_authored_distance", metrics.dodge_root_motion)
	# Upgrade tripwire for the engine behaviour documented in ANIMATION_PIPELINE.md.
	var probe := spawn(trial)
	probe.begin_action("dodge_back", 0.0)
	var mixer_sum := Vector3.ZERO
	var t := 0.0
	for i in 60:
		probe.drive_action(t)
		probe.step(DT)
		mixer_sum += probe.tree.get_root_motion_position()
		t += DT
	metrics["observed_mixer_root_motion_with_timeseek"] = [snappedf(mixer_sum.x, 0.001), snappedf(mixer_sum.y, 0.001), snappedf(mixer_sum.z, 0.001)]
	check(mixer_sum.z > 0.9 and authored.z < -0.9, "observation_timeseek_root_motion_sign_inverted_in_4_7_2", metrics.observed_mixer_root_motion_with_timeseek)
	character.free()
	probe.free()

func test_four_arms(trial: String) -> void:
	var human := spawn(trial)
	var four := spawn(trial, {"extra_arms": true})
	var limb_mesh: MeshInstance3D = four.skeleton.get_node("LowerArms")
	check(limb_mesh.get_node_or_null(limb_mesh.skeleton) == four.skeleton and limb_mesh.skin.get_bind_count() == 8, "extra_limb_mesh_bound_to_skeleton")
	check(four.skeleton.get_bone_count() == 74 and four.extra_arm_bones.size() == 8, "four_arm_skeleton_extends_family_rig", four.skeleton.get_bone_count())
	var a := _run_attack(human, "swordsman_slash")
	var b := _run_attack(four, "swordsman_slash")
	var deviation := 0.0
	for i in mini(a.size(), b.size()):
		deviation = maxf(deviation, (a[i].tip as Vector3).distance_to(b[i].tip))
	check(deviation < 1e-4, "shared_bones_play_human_clip_identically", deviation)
	# SkeletonModifier3D output (the IK) exists only inside the skeleton's deferred update:
	# BoneAttachment3D and `skeleton_updated` see it; get_bone_global_pose() outside does not.
	var skeleton: Skeleton3D = four.skeleton
	var sockets := {}
	for side in ["l", "r"]:
		var socket := BoneAttachment3D.new()
		socket.bone_name = "hand_%s_low" % side
		skeleton.add_child(socket)
		sockets[side] = socket
	four.step(DT)
	await process_frame
	await process_frame
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_02")).origin
	var lower_hands := []
	var ik_error := 0.0
	var raw_error := 0.0
	for side in ["l", "r"]:
		var hand: Vector3 = sockets[side].global_position
		lower_hands.append(four.global_transform.affine_inverse() * hand - four.global_transform.affine_inverse() * chest)
		ik_error = maxf(ik_error, hand.distance_to(four.guard_targets[side].global_position))
		var raw := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_%s_low" % side)).origin
		raw_error = maxf(raw_error, raw.distance_to(four.guard_targets[side].global_position))
	metrics["lower_arm_ik_error_m"] = snappedf(ik_error, 0.0001)
	# Character space faces -Z: the IK guard targets sit in front of the torso.
	check(lower_hands[0].z < -0.15 and lower_hands[1].z < -0.15, "lower_hands_held_in_front_of_torso", lower_hands)
	check(ik_error < 0.03, "two_bone_ik_reaches_guard_targets", ik_error)
	check(raw_error > 0.1, "observation_get_bone_global_pose_excludes_modifier_output", raw_error)
	human.free()
	four.free()
