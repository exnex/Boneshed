extends SceneTree
## Measures real rendered-node transforms, using isolated state fixtures for poses
## and live physics/input for camera obstruction. Mutations must fail named checks.
const Playable = preload("res://scenes/salvage_courtyard.tscn")
const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var observer: Camera3D
var output := "res://artifacts/presentation"
var negative := ""
var passed := 0
var failed := 0
var records: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--negative="): negative = arg.trim_prefix("--negative=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = Playable.instantiate()
	root.add_child(arena)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	var record := {"check": label, "passed": ok}
	records.append(record)
	print(JSON.stringify(record))

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)

func tip(actor: Fighter) -> Vector3:
	return actor.sword_pivot.to_global(Vector3(0.0, 0.0, -1.75))

func run() -> void:
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	e.enabled = false
	p.input_enabled = false
	await frames(6)
	check(not p.debug_hitboxes and not e.debug_hitboxes, "debug_hidden_on_spawn")
	arena.set_physics_process(false)
	p.set_physics_process(false)
	e.set_physics_process(false)
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	p.visual.rotation.y = 0.0
	e.visual.rotation.y = PI
	arena.hud.hide()
	# Side-on observational camera for like-for-like baseline/after evidence.
	observer = Camera3D.new()
	arena.add_child(observer)
	observer.position = Vector3(4.2, 2.9, 4.5)
	observer.look_at(Vector3(0.0, 1.1, 0.8))
	observer.current = true
	var loaded: Dictionary = {}
	for binding: String in ["light", "heavy", "special"]:
		e.combat.reset()
		p.combat.reset()
		e.reaction_time = 0.0
		p.flash_time = 0.0
		if binding == "special": e.combat.attack_special()
		else: e.combat.attack(binding == "heavy")
		var previous := tip(e)
		var max_jump := 0.0
		var active_seen := false
		var active_start := Vector3.ZERO
		var active_end := Vector3.ZERO
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join(binding)))
		for tick in range(ceil((e.combat.windup_duration() + e.combat.active_duration + e.combat.recovery_duration) * 60.0) + 1):
			var before := JSON.stringify([e.combat.phase, e.combat.remaining, e.combat.hit_consumed, e.combat.health, e.combat.posture])
			e.sync_visual(1.0 / 60.0)
			if negative == "pose" and binding == "heavy": e.sword_pivot.position.y = 1.0
			check(before == JSON.stringify([e.combat.phase, e.combat.remaining, e.combat.hit_consumed, e.combat.health, e.combat.posture]), "pose_cannot_change_rules_" + binding + "_" + str(tick))
			var point := tip(e)
			if tick > 0: max_jump = maxf(max_jump, previous.distance_to(point))
			previous = point
			if e.combat.phase == Rules.Phase.WINDUP and e.combat.attack_stage() == "committed":
				loaded[binding] = e.sword_pivot.position
			if e.combat.phase == Rules.Phase.ACTIVE:
				if not active_seen: active_start = point
				active_end = point
				active_seen = true
			e.combat.tick(1.0 / 60.0)
		check(max_jump < 1.25, "no_phase_boundary_weapon_teleport_" + binding)
		if binding != "special":
			check(active_start.distance_to(active_end) > 0.45, "directional_cut_" + binding)
		check(not e.indicator.visible, "no_ground_volume_" + binding)
	check(loaded.heavy.y > loaded.light.y + 0.3 and loaded.heavy.y > 2.0, "heavy_prepares_above_head")
	# Resolve an actual incoming attack, then inspect both combatants' reactions.
	for defense: String in ["deflect", "guard", "hit", "break"]:
		p.combat.reset()
		e.combat.reset()
		p.reaction_time = 0.0
		e.reaction_time = 0.0
		if defense in ["deflect", "guard"]:
			p.combat.set_guard(true)
			if defense == "guard": p.combat.tick(0.3)
		if defense == "break": p.combat.posture = p.combat.max_posture - 1.0
		e.combat.attack()
		e.combat.tick(e.combat.windup_duration() + 0.001)
		var outcome := e.resolve_attack()
		if negative == "reaction":
			e.torso.rotation = Vector3.ZERO
			p.torso.rotation = Vector3.ZERO
			p.impact.hide()
		if defense == "deflect":
			check(outcome == Rules.DEFLECTED and e.combat.phase == Rules.Phase.STAGGER, "deflection_preserves_authoritative_stagger")
			check(e.torso.rotation.x > 0.15 and p.impact.visible and p.impact.global_position.y > 1.0, "deflection_has_visible_recoil_and_contact")
		elif defense == "guard":
			check(outcome == Rules.GUARD and e.combat.phase == Rules.Phase.ACTIVE, "block_preserves_followthrough")
		elif defense == "hit":
			check(outcome == Rules.HIT and p.torso.rotation.x > 0.15, "hit_has_body_recoil")
		else:
			check(p.combat.phase == Rules.Phase.BROKEN and p.head.position.y < 1.5 and p.sword_pivot.position.y < 0.9 and not p.broken_halo.visible, "break_collapses_body_without_halo")
		await capture(defense)
		p.sync_visual(0.4)
		check(not p.impact.visible, "contact_expires_" + defense)
	observer.queue_free()
	p.camera.current = true
	arena.hud.show()
	p.input_enabled = true
	p.set_physics_process(true)
	p.reset_at(Vector3(0.0, 0.02, 2.0))
	e.reset_at(Vector3(0.0, 0.02, 0.0))
	p.locked = true
	await frames(45)
	var a: Vector2 = p.camera.unproject_position(p.global_position + Vector3.UP * 1.4)
	var b: Vector2 = p.camera.unproject_position(e.global_position + Vector3.UP * 1.4)
	check(a.distance_to(b) > 35.0, "lock_separates_close_silhouettes")
	check(root.get_visible_rect().has_point(a) and root.get_visible_rect().has_point(b), "lock_keeps_both_fighters_in_frame")
	await capture("locked")
	var old_yaw: float = p.yaw
	p.rotate_camera(Vector2(120.0, -10000.0))
	check(absf(angle_difference(old_yaw, p.yaw)) > 0.3 and p.pitch <= -0.12, "locked_mouse_is_responsive_and_elevated")
	var manual_yaw: float = p.yaw
	await frames(10)
	check(absf(angle_difference(manual_yaw, p.yaw)) < 0.001, "lock_does_not_fight_manual_orbit")
	p.locked = false
	p.position = Vector3(0.0, 0.02, 10.5)
	p.yaw = 0.0
	p.pitch = -0.12
	await frames(10)
	check(p.spring.get_hit_length() < 4.5, "spring_arm_stops_before_rear_wall")
	await capture("rear_wall")
	p.position = Vector3(11.1, 0.02, 0.0)
	await frames(10)
	check(p.camera_pivot.position.x < 0.5 and p.camera.global_position.x < 11.6, "shoulder_anchor_cannot_cross_side_wall")
	await capture("side_wall")
	p.reset_at(Vector3(0.0, 0.02, 2.0))
	check(p.manual_orbit_time == 0.0 and p.reaction_time == 0.0 and p.gait == 0.0, "reset_clears_presentation_and_camera_state")
	# Drive F3/F1 through the actual input mapping and courtyard callback.
	arena.set_physics_process(true)
	for action: String in ["debug", "help"]:
		var event: InputEventKey = InputMap.action_get_events(action)[0].duplicate()
		event.pressed = true
		Input.parse_input_event(event)
		await frames(1)
		event.pressed = false
		Input.parse_input_event(event)
		await frames(1)
	check(p.debug_hitboxes and e.debug_hitboxes and arena.hud.show_controls, "f3_and_f1_toggle_developer_volumes_and_controls")
	check(arena.progression_prompt().is_empty(), "combat_has_no_explanatory_phase_prompt")
	var summary := {"summary": true, "passed": passed, "failed": failed, "rendered": DisplayServer.get_name() != "headless"}
	records.append(summary)
	print(JSON.stringify(summary))
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify(records, "\t") + "\n")
	arena.free()
	quit(int(failed > 0))
