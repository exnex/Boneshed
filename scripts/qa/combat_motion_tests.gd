extends SceneTree
## Presentation regression checks for the key-pose combat animation layer.
## Pure sampler checks, then real fighters in both courtyard scenes stepped by rule
## time. Every scene check also asserts that rendering a pose leaves rules untouched.
## --negative=contact renders the blade 0.06 s late; --negative=hold strips the
## anticipation holds. Each must fail its named check.
const Rules = preload("res://scripts/combat/combat_state.gd")
const Sampler = preload("res://scripts/characters/presentation/pose_sampler.gd")
const Keys = preload("res://scripts/characters/presentation/attack_pose_keys.gd")
const Fx = preload("res://scripts/characters/presentation/combat_fx.gd")
const Visual = preload("res://scripts/characters/fighter_visual.gd")
const TIP := 1.75
var negative := ""
var passed := 0
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--negative="): negative = arg.trim_prefix("--negative=")
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = null) -> void:
	passed += int(ok)
	failed += int(not ok)
	var record := {"check": label, "passed": ok}
	if detail != null: record.detail = detail
	print(JSON.stringify(record))

func run() -> void:
	pure_checks()
	for scene: String in ["courtyard", "salvage_courtyard"]:
		var arena: Node3D = load("res://scenes/%s.tscn" % scene).instantiate()
		root.add_child(arena)
		for i in range(3):
			await physics_frame
		await scene_checks(arena, scene)
		arena.free()
	print(JSON.stringify({"summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string}))
	quit(int(failed > 0))

func timing(windup: float, active := 0.16, recovery := 0.45) -> Dictionary:
	return {"windup": windup, "commitment": 0.24, "release": 0.08, "active": active, "recovery": recovery}

func tip_of(pose: Dictionary) -> Vector3:
	return Sampler.blade_points(pose)[1]

func pure_checks() -> void:
	for binding: String in ["light", "heavy", "special"]:
		var keys := Sampler.track(binding)
		var ordered := true
		for i in range(1, keys.size()):
			ordered = ordered and keys[i].t > keys[i - 1].t
			for channel: String in Sampler.CHANNELS:
				ordered = ordered and keys[i].has(channel)
		check(ordered and keys[0].t == 0.0 and keys[-1].t == 5.0, "keys_ordered_complete_" + binding)
		var markers_held := true
		for key: Dictionary in keys:
			if key.t in [0.0, 1.0, 2.0, 5.0]: markers_held = markers_held and key.get("hold", false)
		check(markers_held, "anticipation_and_rest_keys_hold_" + binding)
	# Rule boundaries land on the authored markers for every supported timing.
	for t: Dictionary in [timing(0.34), timing(0.62), timing(0.85), timing(0.7, 0.2, 0.8)]:
		var ok := true
		for marker: float in [1.0, 2.0, 3.0, 4.0]:
			var rule: float = [t.windup - t.commitment, t.windup - t.release, t.windup, t.windup + t.active][int(marker) - 1]
			ok = ok and absf(Sampler.clip_time(t, rule) - marker) < 0.0001
		check(ok, "rule_boundaries_hit_markers_windup_" + str(t.windup))
	# Contact: every sword tip sample in ACTIVE is in the forward volume, above 1 m.
	for binding: String in ["light", "heavy"]:
		for windup: float in [0.34, 0.62, 0.85]:
			var t := timing(windup)
			var worst := INF
			var lowest := INF
			for i in range(17):
				var tip := tip_of(Sampler.attack_pose(binding, t, windup + t.active * i / 16.0))
				worst = minf(worst, -tip.z)
				lowest = minf(lowest, tip.y)
			var contact := -tip_of(Sampler.attack_pose(binding, t, windup)).z
			check(absf(contact - 2.35) < 0.1 and worst >= 1.95 and lowest > 1.0, "active_arc_stays_in_hit_volume_%s_%s" % [binding, windup], [contact, worst, lowest])
			# The committed hold keeps the blade out of the forward volume until release.
			var safe := true
			for i in range(11):
				safe = safe and -tip_of(Sampler.attack_pose(binding, t, windup - t.commitment + (t.commitment - t.release) * i / 10.0)).z < 1.4
			check(safe, "blade_out_of_volume_during_committed_hold_%s_%s" % [binding, windup])
	# Readable anticipation: the committed hold moves far less than the release.
	for binding: String in ["light", "heavy"]:
		var t := timing(0.62)
		var keys: Array = Sampler.track(binding)
		if negative == "hold":
			keys = keys.map(func(k: Dictionary) -> Dictionary: var c := k.duplicate(); c.erase("hold"); return c)
		var hold_speed := 0.0
		for i in range(10):
			var a := tip_of(Sampler.sample_track(keys, 1.0 + i / 10.0))
			var b := tip_of(Sampler.sample_track(keys, 1.0 + (i + 1) / 10.0))
			hold_speed = maxf(hold_speed, a.distance_to(b) / (t.commitment - t.release) * 10.0)
		var release_travel := tip_of(Sampler.sample_track(keys, 2.0)).distance_to(tip_of(Sampler.sample_track(keys, 3.0)))
		# Tip speed (metres per clip unit) arriving at `loaded`: a hold decelerates into it.
		var arrive := tip_of(Sampler.sample_track(keys, 0.95)).distance_to(tip_of(Sampler.sample_track(keys, 1.0))) / 0.05
		check(hold_speed < 0.25 * release_travel / t.release and arrive < 0.7, "loaded_hold_is_visible_" + binding, [hold_speed, release_travel / t.release, arrive])
	check(Sampler.attack_pose("heavy", timing(0.85), 0.85 - 0.1).hand.y > Sampler.attack_pose("light", timing(0.34), 0.34 - 0.1).hand.y + 0.4, "heavy_loads_overhead_light_to_side")
	var mirrored := Sampler.mirror(Sampler.attack_pose("light", timing(0.34), 0.4))
	var original := Sampler.attack_pose("light", timing(0.34), 0.4)
	check(absf(tip_of(mirrored).z - tip_of(original).z) < 0.0001 and absf(tip_of(mirrored).x + tip_of(original).x) < 0.0001, "mirror_is_exact_reflection")
	check(is_equal_approx(Sampler.reaction_envelope(0.0), 1.0) and Sampler.reaction_envelope(Sampler.REACTION_SECONDS) == 0.0
		and absf(Sampler.reaction_envelope(0.12)) < 0.25, "reaction_snaps_then_settles")
	var elbow := Sampler.two_bone(Vector3.ZERO, Vector3(0.5, 0.0, 0.0), 0.4, 0.4, Vector3.DOWN)
	check(absf(elbow.length() - 0.4) < 0.0001 and absf(elbow.distance_to(Vector3(0.5, 0.0, 0.0)) - 0.4) < 0.0001 and elbow.y < 0.0, "two_bone_keeps_lengths_and_pole")

func rules_snapshot(state: Rules) -> String:
	return JSON.stringify([state.phase, state.remaining, state.hit_consumed, state.health, state.posture, state.guarding, state.guard_age, state.attack_binding])

func scene_checks(arena: Node3D, scene: String) -> void:
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	e.enabled = false
	p.input_enabled = false
	arena.set_physics_process(false)
	p.set_physics_process(false)
	e.set_physics_process(false)
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	p.visual.rotation.y = 0.0
	e.visual.rotation.y = PI
	var untouched := true
	var bindings := ["light", "heavy"]
	if not e.combat.signature.is_empty(): bindings.append("special")
	for binding: String in bindings:
		p.combat.reset()
		e.combat.reset()
		e.reaction_time = 0.0
		if binding == "special": e.combat.attack_special()
		else: e.combat.attack(binding == "heavy")
		var ticks := ceili((e.combat.windup_duration() + e.combat.active_duration + e.combat.recovery_duration) * 60.0)
		var active := 0
		var first_reach := 0.0
		var in_volume := true
		var bone_exact := true
		var glint_ok := true
		var glint_seen := false
		var trail_ok := true
		var trail_live := false
		var legs_rigid := true
		var arm_stretch := 0.0
		var active_end := e.combat.windup_duration() + e.combat.active_duration
		for tick in range(ticks + 1):
			var before := rules_snapshot(e.combat)
			e.sync_visual(1.0 / 60.0)
			untouched = untouched and before == rules_snapshot(e.combat)
			var now := Sampler.attack_rule_time(e.combat)
			if negative == "contact" and e.combat.phase == Rules.Phase.ACTIVE and binding != "special":
				var late := Sampler.attack_pose(binding, Sampler.timing_of(e.combat), now - 0.06)
				late = Sampler.mirror(late) if not e.combat.signature.is_empty() else late
				e.sword_pivot.position = late.hand
				e.sword_pivot.rotation = late.blade
			var tip := e.sword_pivot.to_global(Vector3(0.0, 0.0, -TIP))
			var reach := (tip - e.global_position).dot(e.facing)
			if e.combat.phase == Rules.Phase.ACTIVE:
				active += 1
				if binding == "special":
					var bone := (e.marrow_bone.to_global(Vector3(0.0, 0.0, -0.5)) - e.global_position).dot(e.facing)
					bone_exact = bone_exact and absf(bone - float(e.combat.signature.reach)) < 0.02
				else:
					if active == 1: first_reach = reach
					in_volume = in_volume and reach >= e.attack_range - 0.4 and tip.y > 1.0
			var glint: MeshInstance3D = e.visual.get_node("Glint")
			var committed := e.combat.phase == Rules.Phase.WINDUP and e.combat.attack_stage() != "early"
			glint_ok = glint_ok and (not glint.visible or committed)
			glint_seen = glint_seen or glint.visible
			var trail: ImmediateMesh = e.visual.get_node("BladeTrail").mesh
			var has_trail := trail.get_surface_count() > 0
			var may_trail := binding != "special" and now >= e.combat.windup_duration() - e.combat.release_duration and now < active_end + Fx.TRAIL_FADE
			trail_ok = trail_ok and (not has_trail or may_trail)
			trail_live = trail_live or (has_trail and e.combat.phase == Rules.Phase.ACTIVE)
			for i in range(2):
				legs_rigid = legs_rigid and absf(e.thighs[i].scale.y - Visual.LEG_UPPER) < 0.002 and absf(e.shins[i].scale.y - Visual.LEG_LOWER) < 0.002
			arm_stretch = maxf(arm_stretch, e.forearm.scale.y - Visual.ARM_LOWER)
			e.combat.tick(1.0 / 60.0)
		var tag := scene + "_" + binding
		if binding == "special":
			check(active > 0 and bone_exact, "bone_tip_on_rule_reach_every_active_tick_" + tag)
		else:
			check(absf(first_reach - e.attack_range) < 0.15, "first_active_tick_at_contact_pose_" + tag, first_reach)
			check(in_volume, "active_blade_stays_in_hit_volume_" + tag)
			check(trail_ok and trail_live, "trail_only_from_release_through_active_" + tag)
		check(glint_ok and glint_seen, "glint_only_in_committed_stage_" + tag)
		check(legs_rigid and arm_stretch < 0.12, "limbs_keep_length_" + tag, arm_stretch)
	# A cancel mid-swing leaves no trail: cues are recomputed from rules every frame.
	e.combat.reset()
	e.combat.attack()
	e.combat.tick(e.combat.windup_duration() + 0.05)
	e.sync_visual(1.0 / 60.0)
	var had_trail: bool = e.visual.get_node("BladeTrail").mesh.get_surface_count() > 0
	e.combat.dodge()
	e.sync_visual(1.0 / 60.0)
	check(had_trail and e.visual.get_node("BladeTrail").mesh.get_surface_count() == 0 and not e.visual.get_node("Glint").visible, "cancel_clears_trail_" + scene)
	# Reactions: impact reads on the resolving frame; a poised heavy keeps its blade path.
	p.combat.reset()
	e.combat.reset()
	p.reaction_time = 0.0
	e.combat.attack()
	e.combat.tick(e.combat.windup_duration() + 0.001)
	var outcome := e.resolve_attack()
	check(outcome == Rules.HIT and p.torso.rotation.x > 0.35 and p.get_node("HitMark").visible, "hit_snaps_chest_and_marks_contact_" + scene)
	p.sync_visual(Sampler.REACTION_SECONDS)
	check(not p.get_node("HitMark").visible and p.torso.rotation.x < 0.3, "hit_reaction_expires_" + scene)
	p.combat.reset()
	e.combat.reset()
	p.combat.attack(true)
	p.combat.tick(p.combat.heavy_windup - 0.05)
	p.reaction_time = 0.0
	p.sync_visual(0.0)
	var poised_hand := p.sword_pivot.position
	e.combat.attack()
	e.combat.tick(e.combat.windup_duration() + 0.001)
	e.facing = Vector3.BACK
	outcome = e.resolve_attack()
	check(outcome == Rules.HIT and p.combat.phase == Rules.Phase.WINDUP and p.sword_pivot.position.is_equal_approx(poised_hand) and p.torso.rotation.x > 0.2,
		"poised_heavy_body_flinches_blade_holds_" + scene)
	# Crossfade: exact on zero-delta refresh, eased with time, exact after the fade.
	p.combat.reset()
	p.reaction_time = 0.0
	p.sync_visual(0.5)
	p.combat.set_guard(true)
	p.sync_visual(1.0 / 60.0)
	var eased := p.sword_pivot.position
	p.sync_visual(Visual.FADE_SECONDS)
	var guard := Keys.GUARD.hand if p.combat.signature.is_empty() else Vector3(-Keys.GUARD.hand.x, Keys.GUARD.hand.y, Keys.GUARD.hand.z)
	check(not eased.is_equal_approx(guard) and p.sword_pivot.position.is_equal_approx(guard), "guard_raise_eases_then_settles_" + scene)
	p.combat.set_guard(false)
	p.sync_visual(0.0)
	check(untouched, "pose_sampling_never_changes_rules_" + scene)
