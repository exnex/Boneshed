extends Node

const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var p: Fighter
var e: Fighter
var passed := 0
var failed := 0
var records: Array = []
var output := "res://artifacts/latest"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	var record := {"suite": "graphical", "check": label, "passed": condition}
	records.append(record)
	print(JSON.stringify(record))

func snapshot(label: String) -> void:
	get_tree().paused = true
	# Draw the now-frozen authoritative state before capture.
	arena.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := output.path_join(label + ".png")
	check(image.save_png(path) == OK, "screenshot_" + label)
	var record := {"screenshot": label, "player": state(p), "enemy": state(e), "message": arena.event_text}
	records.append(record)
	print(JSON.stringify(record))
	get_tree().paused = false

func state(actor: Fighter) -> Dictionary:
	return {"health": actor.combat.health, "posture": actor.combat.posture, "phase": Rules.Phase.keys()[actor.combat.phase], "position": [actor.position.x, actor.position.y, actor.position.z], "event": actor.combat.last_event}

func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)

func wait_phase(actor: Fighter, phase: int, limit := 180) -> bool:
	for i in range(limit):
		if actor.combat.phase == phase:
			return true
		await frames(1)
	return false

func close_fixture() -> void:
	arena.reset_encounter()
	e.enabled = false
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	p.yaw = 0.0
	p.locked = true

func run() -> void:
	arena = get_parent()
	p = arena.player
	e = arena.enemy
	e.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if "--defense-cancels-only" in OS.get_cmdline_user_args():
		await defense_cancel_checks()
		finish(0)
		return
	if "--npc-motion-only" in OS.get_cmdline_user_args():
		await attack_steering_checks()
		finish(0)
		return
	if "--attack-movement-only" in OS.get_cmdline_user_args():
		await attack_movement_checks()
		finish(0)
		return
	await frames(12)
	check(p.is_on_floor() and e.is_on_floor(), "actors_grounded")
	await snapshot("01_initial_courtyard")
	var start := p.position
	action("move_forward", true)
	await frames(35)
	action("move_forward", false)
	await frames(6)
	check(p.position.z < start.z - 1.0, "input_moves_player")
	check(Vector2(p.velocity.x, p.velocity.z).length() < 0.1, "movement_stops_responsively")
	var yaw_before: float = p.yaw
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(75.0, 15.0)
	Input.parse_input_event(mouse)
	await frames(2)
	check(absf(p.yaw - yaw_before) > 0.1 and p.camera_pivot.rotation.x < -0.28, "mouse_rotates_camera")
	action("lock_on", true)
	await frames(2)
	action("lock_on", false)
	check(p.locked, "target_lock_input")
	# Collision-aware spring arm: back the camera into the solid perimeter.
	p.position = Vector3(0.0, 0.02, 10.5)
	p.locked = false
	p.yaw = 0.0
	p.pitch = -0.05
	await frames(8)
	check(p.spring.get_hit_length() < p.camera_distance - 1.0, "camera_avoids_wall")
	arena.reset_encounter()
	e.enabled = true
	var distance_before := p.position.distance_to(e.position)
	await frames(80)
	check(p.position.distance_to(e.position) < distance_before - 2.0, "enemy_detects_and_approaches")
	check(await wait_phase(e, Rules.Phase.WINDUP), "enemy_starts_readable_attack")
	await snapshot("02_enemy_windup")
	check(await wait_phase(e, Rules.Phase.RECOVERY), "enemy_completes_active_attack")
	check(p.combat.health < 100.0, "enemy_attack_hits_player")
	# Actual world shape tests, including lateral, behind, range, and obstacle rejection.
	close_fixture()
	p.input_enabled = false
	p.combat.attack()
	check(p.resolve_attack() == "invalid" and e.combat.health == 100.0, "world_windup_no_hit")
	p.combat.tick(p.combat.attack_windup + 0.001)
	e.position.z = -2.0
	check(p.resolve_attack() == "out_of_range" and e.combat.health == 100.0, "world_range_rejection")
	e.position = Vector3(3.0, 0.02, 0.0)
	check(p.resolve_attack() == "out_of_range", "world_lateral_rejection")
	e.position = Vector3(0.0, 0.02, 3.0)
	check(p.resolve_attack() == "out_of_range", "world_behind_rejection")
	e.position = Vector3(0.0, 0.02, 0.0)
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	shape.shape = box
	obstacle.add_child(shape)
	obstacle.position = Vector3(0.0, 1.0, 1.0)
	arena.add_child(obstacle)
	# Keep the attack state stable while the new shape is synchronized.
	p.combat.phase = Rules.Phase.IDLE
	await frames(2)
	check(not p.valid_attack_target(e), "world_obstacle_blocks_hit")
	obstacle.queue_free()
	await frames(2)
	p.combat.phase = Rules.Phase.ACTIVE
	p.combat.hit_consumed = false
	check(p.resolve_attack() == "hit" and e.combat.health == 82.0, "world_valid_active_hit")
	check(p.resolve_attack() == "invalid" and e.combat.health == 82.0, "world_swing_hits_once")
	# Drive guard and deflect through the same input/physics path used by a person.
	p.input_enabled = true
	close_fixture()
	action("guard", true)
	await frames(20)
	e.combat.attack()
	check(await wait_phase(e, Rules.Phase.RECOVERY), "guard_fixture_attack_completes")
	check(p.last_result == "guard" and is_equal_approx(p.combat.health, 97.84) and p.combat.posture > 0.0, "input_guard_mitigates_and_pressures")
	check(p.last_result != "deflected", "held_guard_is_mistimed_deflection")
	action("guard", false)
	await frames(2)
	close_fixture()
	e.combat.attack()
	while e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining > 0.09:
		await frames(1)
	action("guard", true)
	await frames(7)
	check(p.last_result == "deflected" and p.combat.health == 100.0 and e.combat.posture == 42.0, "input_timed_deflection")
	await snapshot("03_successful_deflection")
	action("guard", false)
	await frames(2)
	# Repeated real deflections must accumulate into a break, without synthetic posture.
	for repetition in range(2):
		await wait_phase(e, Rules.Phase.IDLE)
		e.combat.attack()
		while e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining > 0.09:
			await frames(1)
		action("guard", true)
		await frames(7)
		action("guard", false)
		await frames(1)
	check(e.combat.phase == Rules.Phase.BROKEN and e.combat.posture == 100.0, "deflections_accumulate_posture_break")
	await snapshot("04_posture_break")
	var health_before: float = e.combat.health
	action("attack", true)
	await frames(1)
	action("attack", false)
	await frames(28)
	check(is_equal_approx(health_before - e.combat.health, 36.0), "input_attack_punishes_break")
	# Complete the duel with player input. AI remains enabled for this final encounter.
	close_fixture()
	e.enabled = true
	var guard_held := false
	var attack_held := false
	var combat_frames := 0
	while e.combat.phase != Rules.Phase.DEAD and p.combat.phase != Rules.Phase.DEAD and combat_frames < 1800:
		var should_guard: bool = e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining < 0.12 and p.combat.phase == Rules.Phase.IDLE
		if should_guard != guard_held:
			action("guard", should_guard)
			guard_held = should_guard
		var should_attack: bool = p.combat.phase == Rules.Phase.IDLE and not should_guard and e.combat.phase in [Rules.Phase.BROKEN, Rules.Phase.RECOVERY, Rules.Phase.STAGGER]
		if should_attack != attack_held:
			action("attack", should_attack)
			attack_held = should_attack
		await frames(1)
		combat_frames += 1
	action("guard", false)
	action("attack", false)
	check(e.combat.phase == Rules.Phase.DEAD and p.combat.health > 0.0, "input_bot_defeats_live_enemy")
	check(is_equal_approx(e.visual.rotation.z, PI / 2.0), "defeated_pose_matches_rules_immediately")
	await snapshot("05_enemy_defeat")
	# Verify dodge input and reset after a completed encounter.
	action("reset", true)
	await frames(1)
	action("reset", false)
	await frames(3)
	check(p.combat.health == 100.0 and e.combat.health == 100.0 and p.combat.posture == 0.0 and e.combat.posture == 0.0 and e.attack_number == 0 and p.last_result == "" and e.last_result == "" and not p.locked, "input_reset_restores_encounter")
	e.enabled = false
	var dodge_start := p.position
	action("dodge", true)
	await frames(1)
	action("dodge", false)
	check(p.combat.phase == Rules.Phase.DODGE, "input_dodge_starts")
	await frames(20)
	check(p.position.distance_to(dodge_start) > 1.5, "input_dodge_moves_player")
	# Review fix: a dodge out of a run must travel along its input direction. Use a
	# yawed camera so camera-relative directions are not aligned with world axes.
	arena.reset_encounter()
	e.enabled = false
	p.yaw = 0.6
	action("move_forward", true)
	await frames(40)
	action("move_forward", false)
	action("move_back", true)
	action("dodge", true)
	await frames(1)
	action("dodge", false)
	var run_dodge_start := p.position
	var run_dodge_direction := p.dodge_direction
	while p.combat.phase == Rules.Phase.DODGE:
		await frames(1)
	action("move_back", false)
	var travelled := p.position - run_dodge_start
	var along := travelled.dot(run_dodge_direction)
	var off_axis := (travelled - run_dodge_direction * along).length()
	check(along > 1.4, "dodge_out_of_run_keeps_distance")
	check(off_axis < 0.1, "dodge_out_of_run_keeps_direction")
	await frames(20)
	# A player death must also reset; use real enemy attacks against a stationary player.
	close_fixture()
	p.input_enabled = false
	e.enabled = true
	check(await wait_phase(p, Rules.Phase.DEAD, 1800), "live_enemy_can_defeat_player")
	arena.reset_encounter()
	check(p.combat.phase == Rules.Phase.IDLE and p.combat.health == 100.0 and p.velocity == Vector3.ZERO and e.combat.health == 100.0 and e.attack_number == 0, "reset_after_player_death")
	await attack_movement_checks()
	await defense_cancel_checks()
	finish(combat_frames)

func finish(combat_frames: int) -> void:
	var summary := {"suite": "graphical", "summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(), "combat_bot_frames": combat_frames}
	records.append(summary)
	print(JSON.stringify(summary))
	var file := FileAccess.open(output.path_join("graphical.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t") + "\n")
	get_tree().quit(1 if failed else 0)

func attack_movement_checks() -> void:
	# Real input and CharacterBody3D physics across a complete swing, from rest.
	# Sample each phase separately so coasting out of windup cannot mask a root.
	for lock in [false, true]:
		for movement in [["move_forward"], ["move_back"], ["move_right"], ["move_forward", "move_right"]]:
			arena.reset_encounter()
			e.enabled = false
			e.position = Vector3(0.0, 0.02, -8.0)
			p.input_enabled = true
			p.locked = lock
			await frames(2)
			for key in movement:
				action(key, true)
			action("attack", true)
			await frames(1)
			action("attack", false)
			var distance := {Rules.Phase.WINDUP: 0.0, Rules.Phase.ACTIVE: 0.0, Rules.Phase.RECOVERY: 0.0}
			for tick in range(90):
				var phase: int = p.combat.phase
				if phase == Rules.Phase.IDLE:
					break
				var before := p.position
				await frames(1)
				if distance.has(phase) and phase == p.combat.phase:
					distance[phase] += Vector2(p.position.x - before.x, p.position.z - before.z).length()
			for key in movement:
				action(key, false)
			var label := "locked_" + str(lock) + "_" + "_".join(movement)
			check(distance[Rules.Phase.WINDUP] > 0.8, "attack_moves_windup_" + label)
			check(distance[Rules.Phase.ACTIVE] > 0.5, "attack_moves_active_" + label)
			check(distance[Rules.Phase.RECOVERY] > 1.5, "attack_moves_recovery_" + label)
			check(p.combat.phase == Rules.Phase.IDLE, "moving_attack_completes_" + label)
	# Approach from outside reach: movement must carry the real hit volume with it.
	close_fixture()
	p.position.z = 3.6
	action("move_forward", true)
	action("attack", true)
	await frames(1)
	action("attack", false)
	await wait_phase(p, Rules.Phase.IDLE)
	action("move_forward", false)
	check(e.combat.health == 82.0 and p.position.z < 2.2, "moving_attack_carries_hitbox_and_hits_once")
	check(p.position.distance_to(e.position) >= 0.69, "moving_attack_preserves_body_collision")
	# Redirect while the swing is still in preparation; locked attacks can strafe.
	arena.reset_encounter()
	e.enabled = false
	e.position = Vector3(0.0, 0.02, -8.0)
	p.locked = true
	action("move_forward", true)
	action("attack", true)
	await frames(1)
	action("attack", false)
	await frames(7)
	action("move_forward", false)
	action("move_right", true)
	var redirect_start := p.position
	await frames(12)
	action("move_right", false)
	check(p.position.x > redirect_start.x + 0.3 and p.velocity.x > 3.0, "swing_accepts_changed_movement_input")
	# A movement request must not walk out of genuine hit reactions or death.
	for phase in [Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.DEAD]:
		arena.reset_encounter()
		e.enabled = false
		p.combat.phase = phase
		p.combat.remaining = 0.5
		var before := p.position
		action("move_right", true)
		await frames(8)
		action("move_right", false)
		check(absf(p.position.x - before.x) < 0.01, "movement_still_restricted_" + Rules.Phase.keys()[phase])
	await attack_steering_checks()
	arena.reset_encounter()

func attack_steering_checks() -> void:
	for phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
		for mouse_turn in [false, true]:
			arena.reset_encounter()
			e.enabled = false
			e.position = Vector3(0.0, 0.02, -8.0)
			p.locked = false
			action("move_forward", true)
			action("attack", true)
			await frames(1)
			action("attack", false)
			await wait_phase(p, phase)
			if mouse_turn:
				var mouse := InputEventMouseMotion.new()
				mouse.relative = Vector2(-240.0, 0.0)
				if DisplayServer.get_name() == "headless":
					# Headless has no captured mouse; rendered runs feed the real event.
					p.rotate_camera(mouse.relative)
				else:
					Input.parse_input_event(mouse)
			else:
				action("move_forward", false)
				action("move_right", true)
			var old_facing := p.facing
			await frames(4)
			action("move_forward", false)
			action("move_right", false)
			var visual_yaw := atan2(-p.facing.x, -p.facing.z)
			check(old_facing.angle_to(p.facing) > 0.20 and absf(angle_difference(p.visual.rotation.y, visual_yaw)) < 0.001 and p.combat.phase == phase,
				"turn_while_moving_attack_" + Rules.Phase.keys()[phase] + "_mouse_" + str(mouse_turn))
	# Observe a real AI attack, including lateral footwork at its preferred range.
	close_fixture()
	p.input_enabled = false
	p.combat.set_guard(true)
	e.enabled = true
	e.cooldown = 0.0
	await wait_phase(e, Rules.Phase.WINDUP)
	var distance := {Rules.Phase.WINDUP: 0.0, Rules.Phase.ACTIVE: 0.0, Rules.Phase.RECOVERY: 0.0}
	var capture_motion := "--capture-movement" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capture_motion:
		DirAccess.make_dir_recursive_absolute(output.path_join("motion"))
		p.debug_hitboxes = false
		e.debug_hitboxes = false
	for tick in range(160):
		var phase: int = e.combat.phase
		if phase == Rules.Phase.IDLE:
			break
		var before := e.position
		await frames(1)
		if distance.has(phase) and e.combat.phase == phase:
			distance[phase] += Vector2(e.position.x - before.x, e.position.z - before.z).length()
		if capture_motion and tick % 2 == 0:
			await snapshot("motion/frame_%03d" % (tick / 2))
	check(distance[Rules.Phase.WINDUP] > 0.3, "live_npc_moves_in_windup")
	check(distance[Rules.Phase.ACTIVE] > 0.08, "live_npc_moves_in_active_swing")
	check(distance[Rules.Phase.RECOVERY] > 0.3, "live_npc_moves_in_recovery")
	records.append({"npc_attack_travel": distance})
	# Moving target: AI must steer during its swing without snapping instantly.
	close_fixture()
	p.input_enabled = false
	e.enabled = true
	e.combat.attack(true)
	await frames(1)
	p.position = Vector3(2.0, 0.02, 0.0)
	var before_turn := e.facing
	await frames(1)
	check(before_turn.angle_to(e.facing) > 0.01 and before_turn.angle_to(e.facing) <= deg_to_rad(e.attack_turn_speed) / 60.0 + 0.001, "npc_attack_steering_is_responsive_and_capped")
	await frames(5)
	check(before_turn.angle_to(e.facing) > 0.30 and e.combat.phase == Rules.Phase.WINDUP, "npc_tracks_moving_target_during_attack")
	p.input_enabled = true

func defense_cancel_checks() -> void:
	for phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
		for defense in ["dodge", "guard"]:
			close_fixture()
			p.input_enabled = true
			e.position = Vector3(0.0, 0.02, -8.0)
			action("attack", true)
			await frames(1)
			action("attack", false)
			await wait_phase(p, phase)
			# Put both weapons in reach on the cancel tick. Do not let dodge travel
			# hide a damage bug: this must evade an actual hit while stationary.
			e.position = p.position + p.facing * 1.8
			e.facing = -p.facing
			e.combat.attack()
			e.combat.tick(e.combat.attack_windup + 0.001)
			p.dodge_speed = 0.0
			action(defense, true)
			await frames(1)
			var label: String = defense + "_" + Rules.Phase.keys()[phase]
			check((p.combat.phase == Rules.Phase.DODGE if defense == "dodge" else p.combat.guarding), "input_attack_cancel_" + label)
			check(p.combat.health == 100.0 and p.last_result == ("evaded" if defense == "dodge" else "deflected"), "input_cancel_defense_works_" + label)
			check(e.combat.health == 100.0 and p.resolve_attack() == "invalid" and not p.indicator.visible, "input_cancel_removes_hit_and_attack_visual_" + label)
			await frames(35)
			check(e.combat.health == 100.0, "input_cancel_no_delayed_hit_" + label)
			action(defense, false)
			p.dodge_speed = 11.0
			await frames(1)
	# Same-tick requests have deterministic dodge > guard > attack priority.
	close_fixture()
	p.combat.attack()
	action("attack", true)
	action("guard", true)
	action("dodge", true)
	await frames(1)
	check(p.combat.phase == Rules.Phase.DODGE and not p.combat.guarding, "simultaneous_defenses_choose_dodge")
	for key in ["attack", "guard", "dodge"]:
		action(key, false)
	arena.reset_encounter()
