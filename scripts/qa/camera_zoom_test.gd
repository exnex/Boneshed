extends SceneTree
## Live wheel/button input and real spring-arm physics. Enemy AI and duel resolution
## are paused for camera fixtures; combat input/state and player locomotion stay live.
const Playable = preload("res://scenes/salvage_courtyard.tscn")
const PlayerController = preload("res://scripts/characters/player.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var p: PlayerController
var output := "res://artifacts/camera-zoom"
var records: Array[Dictionary] = []
var passed := 0
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output = arg.trim_prefix("--evidence-dir=")
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

func button(index: MouseButton, pressed: bool = true, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.factor = factor
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wheel(index: MouseButton, count: int = 1, factor: float = 1.0) -> void:
	for i in range(count):
		button(index, true, factor)
		button(index, false, factor)

func action(name: String, pressed: bool = true) -> void:
	var event: InputEventKey = InputMap.action_get_events(name)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(name: String) -> void:
	action(name)
	await frames(1)
	action(name, false)
	await frames(1)

func place(point: Vector3 = Vector3(0.0, 0.02, 2.0), enemy_at: Vector3 = Vector3(0.0, 0.02, 0.0)) -> void:
	p.reset_at(point)
	arena.enemy.reset_at(enemy_at)
	arena.enemy.enabled = false
	p.locked = true

func in_frame(actor: Fighter, height: float) -> bool:
	var point := actor.global_position + Vector3.UP * height
	return not p.camera.is_position_behind(point) and root.get_visible_rect().has_point(p.camera.unproject_position(point))

func capture(label: String) -> void:
	var record := {"frame": label, "preferred": p.preferred_camera_distance,
		"requested": p.spring.spring_length, "actual": p.spring.get_hit_length(),
		"pitch": p.pitch, "yaw": p.yaw, "locked": p.locked,
		"player": str(p.position), "enemy": str(arena.enemy.position), "camera": str(p.camera.global_position)}
	records.append(record)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)

func run() -> void:
	await frames(6)
	p = arena.player
	arena.set_physics_process(false)
	arena.enemy.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	place()
	await frames(45)
	check(is_equal_approx(p.preferred_camera_distance, 6.0) and is_equal_approx(p.spring.spring_length, 6.0), "existing_default_distance_preserved")
	await capture("01_default")
	# Exports must affect initialization, rather than accidentally reading defaults.
	var custom := PlayerController.new()
	custom.input_enabled = false
	custom.camera_distance = 4.8
	custom.camera_min_distance = 3.5
	custom.camera_max_distance = 8.0
	custom.camera_zoom_step = 0.4
	custom.camera_zoom_speed = 9.0
	arena.add_child(custom)
	check(is_equal_approx(custom.preferred_camera_distance, 4.8) and is_equal_approx(custom.spring.spring_length, 4.8), "configured_default_initializes_preference_and_arm")
	custom.input_enabled = true
	custom._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	check(is_equal_approx(custom.preferred_camera_distance, 4.4), "configured_wheel_sensitivity_is_used")
	var limit_event := _wheel_event(MOUSE_BUTTON_WHEEL_UP)
	limit_event.factor = 100.0
	custom._unhandled_input(limit_event)
	check(custom.preferred_camera_distance == 3.5, "configured_minimum_is_used")
	limit_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	custom._unhandled_input(limit_event)
	check(custom.preferred_camera_distance == 8.0, "configured_maximum_is_used")
	custom.free()
	p.camera.current = true

	var start := p.preferred_camera_distance
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(p.preferred_camera_distance, start - p.camera_zoom_step), "scroll_up_selects_closer")
	check(is_equal_approx(p.spring.spring_length, start), "wheel_does_not_snap_arm")
	await frames(1)
	check(p.spring.spring_length < start and p.spring.spring_length > p.preferred_camera_distance, "first_tick_interpolates")
	var previous := p.spring.spring_length
	for tick in range(30):
		await frames(1)
		check(p.spring.spring_length <= previous and p.spring.spring_length >= p.preferred_camera_distance, "converges_without_overshoot_" + str(tick))
		previous = p.spring.spring_length
	check(absf(p.spring.spring_length - p.preferred_camera_distance) < 0.003, "responsive_convergence_within_half_second")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(p.preferred_camera_distance, start), "scroll_down_selects_farther")
	wheel(MOUSE_BUTTON_WHEEL_UP, 1, 0.5)
	check(is_equal_approx(p.preferred_camera_distance, start - p.camera_zoom_step * 0.5), "fractional_wheel_factor")
	var selected := p.preferred_camera_distance
	button(MOUSE_BUTTON_WHEEL_DOWN, false)
	wheel(MOUSE_BUTTON_WHEEL_LEFT)
	check(p.preferred_camera_distance == selected, "releases_and_horizontal_wheel_ignored")
	p.input_enabled = false
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(p.preferred_camera_distance == selected, "disabled_input_ignores_zoom")
	p.input_enabled = true

	wheel(MOUSE_BUTTON_WHEEL_UP, 40)
	check(p.preferred_camera_distance == p.camera_min_distance, "minimum_clamp")
	await frames(45)
	check(absf(p.spring.get_hit_length() - p.camera_min_distance) < 0.003, "minimum_remains_third_person")
	for angle: float in [-0.75, -0.32, -0.12, 0.15]:
		p.locked = false
		p.pitch = angle
		await frames(3)
		check(in_frame(p, 0.05) and in_frame(p, 1.95), "minimum_shows_player_across_pitch_" + str(angle))
	p.locked = true
	p.pitch = -0.32
	await frames(45)
	check(in_frame(p, 1.4) and in_frame(arena.enemy, 1.4), "minimum_frames_close_duel")
	await capture("02_close")
	var orbit_start := p.position
	action("move_right")
	for tick in range(30):
		if tick % 10 == 0: wheel(MOUSE_BUTTON_WHEEL_DOWN if tick % 20 == 0 else MOUSE_BUTTON_WHEEL_UP)
		await frames(1)
	action("move_right", false)
	check(p.position.distance_to(orbit_start) > 0.4 and p.locked and in_frame(p, 1.4) and in_frame(arena.enemy, 1.4), "close_strafe_orbit_while_zooming_keeps_both_in_frame")
	place()
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 40)
	check(p.preferred_camera_distance == p.camera_max_distance, "maximum_clamp")
	await frames(45)
	check(absf(p.spring.get_hit_length() - p.camera_max_distance) < 0.003, "maximum_converges")
	check(in_frame(p, 0.05) and in_frame(p, 1.95) and in_frame(arena.enemy, 0.05) and in_frame(arena.enemy, 1.95), "maximum_frames_both_fighters")
	await capture("03_far")

	# Rapid reversal follows the latest selection, with no queued zoom tween.
	wheel(MOUSE_BUTTON_WHEEL_UP, 6)
	await frames(3)
	var before_reversal := p.spring.spring_length
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 6)
	check(p.spring.spring_length == before_reversal, "rapid_input_does_not_snap")
	await frames(1)
	check(p.spring.spring_length > before_reversal and p.spring.spring_length < p.camera_max_distance, "reversal_responds_on_next_tick")
	var expected := p.preferred_camera_distance
	for tick in range(120):
		var index := MOUSE_BUTTON_WHEEL_UP if tick % 3 != 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel(index)
		expected = clampf(expected + (-1.0 if index == MOUSE_BUTTON_WHEEL_UP else 1.0) * p.camera_zoom_step, p.camera_min_distance, p.camera_max_distance)
	await frames(45)
	check(is_equal_approx(p.preferred_camera_distance, expected) and absf(p.spring.spring_length - expected) < 0.003, "rapid_wheel_burst_keeps_latest_clamped_selection")

	# Obstructions may shorten actual distance below the preferred minimum.
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 40)
	await frames(45)
	place(Vector3(0.0, 0.02, 10.5), Vector3(0.0, 0.02, 8.5))
	p.locked = false
	p.pitch = -0.12
	await frames(6)
	check(p.spring.get_hit_length() < 1.5 and p.camera.global_position.z < 11.4, "rear_wall_blocks_camera")
	check(p.preferred_camera_distance == p.camera_max_distance, "wall_does_not_overwrite_preference")
	await capture("04_wall_obstructed")
	wheel(MOUSE_BUTTON_WHEEL_UP, 2)
	selected = p.preferred_camera_distance
	await frames(30)
	check(p.spring.get_hit_length() < 1.5 and selected < p.camera_max_distance, "wheel_changes_preference_while_obstructed")
	place()
	await frames(45)
	check(p.preferred_camera_distance == selected and absf(p.spring.get_hit_length() - selected) < 0.003, "wall_recovery_restores_selected_distance")
	await capture("05_wall_recovered")
	p.locked = false
	p.position = Vector3(11.1, 0.02, 0.0)
	await frames(6)
	check(p.camera_pivot.position.x < 0.5 and p.camera.global_position.x < 11.6, "shoulder_anchor_wall_check_preserved")
	# Put the swept arm through an existing pillar, rather than only a perimeter wall.
	p.position = Vector3(7.8, 0.02, -5.0)
	p.pitch = -0.12
	await frames(6)
	check(p.spring.get_hit_length() < 1.5, "pillar_blocks_zoomed_arm")
	place()
	await frames(45)
	check(absf(p.spring.get_hit_length() - selected) < 0.003, "pillar_recovery_keeps_preference")

	# Zoom does not claim attack/guard events or create combat intents itself.
	wheel(MOUSE_BUTTON_WHEEL_UP, 40)
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(45)
	p.combat.reset()
	button(MOUSE_BUTTON_LEFT)
	await frames(1)
	button(MOUSE_BUTTON_LEFT, false)
	check(p.combat.phase == Rules.Phase.WINDUP, "left_click_still_attacks")
	for phase: int in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
		for tick in range(90):
			if p.combat.phase == phase: break
			await frames(1)
		wheel(MOUSE_BUTTON_WHEEL_DOWN if phase == Rules.Phase.ACTIVE else MOUSE_BUTTON_WHEEL_UP)
		check(p.combat.phase == phase and p.locked, "zoom_preserves_locked_attack_" + str(phase))
		if phase == Rules.Phase.ACTIVE:
			check(in_frame(p, 0.05) and in_frame(p, 1.95) and in_frame(arena.enemy, 1.4), "close_attack_keeps_player_and_enemy_visible")
			await capture("09_close_attack")
	button(MOUSE_BUTTON_RIGHT)
	await frames(1)
	check(p.combat.guarding and not p.combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY], "right_click_still_cancels_to_guard")
	var guard_age := p.combat.guard_age
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(3)
	check(p.combat.guarding and p.combat.guard_age > guard_age and Input.is_action_pressed("guard") and not Input.is_action_pressed("attack"), "zoom_does_not_release_or_refresh_guard")
	await capture("06_locked_guard_zoom")
	button(MOUSE_BUTTON_RIGHT, false)
	await frames(1)
	action("dodge")
	await frames(1)
	action("dodge", false)
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(p.combat.phase == Rules.Phase.DODGE and p.locked, "zoom_during_locked_dodge")
	await frames(40)
	p.combat.reset()
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(1)
	check(p.combat.phase == Rules.Phase.IDLE and not p.combat.guarding, "wheel_alone_never_attacks_or_guards")

	selected = p.preferred_camera_distance
	await tap("lock_on")
	check(not p.locked and p.preferred_camera_distance == selected, "unlock_keeps_zoom")
	await tap("lock_on")
	check(p.locked and p.preferred_camera_distance == selected, "lock_keeps_zoom")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 30.0)
	var yaw_before := p.yaw
	var pitch_before := p.pitch
	# Headless cannot capture the OS pointer; rendered mode exercises real dispatch.
	if DisplayServer.get_name() == "headless": p.rotate_camera(motion.relative)
	else:
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
	var manual_yaw := p.yaw
	wheel(MOUSE_BUTTON_WHEEL_UP)
	await frames(10)
	check(absf(angle_difference(yaw_before, p.yaw)) > 0.2 and p.pitch < pitch_before and absf(angle_difference(p.yaw, manual_yaw)) < 0.001, "zoom_preserves_mouse_orbit_and_lock_override")
	await frames(45)
	var old_position := p.position
	action("move_back")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(15)
	action("move_back", false)
	check(p.position.distance_to(old_position) > 0.3 and p.locked, "backward_movement_while_locked_and_zooming")
	# Enemy behind: retain the old angular-rate cap during zoom and converge again.
	arena.enemy.position = p.position + Vector3(0.0, 0.0, 1.5)
	yaw_before = p.yaw
	wheel(MOUSE_BUTTON_WHEEL_UP)
	await frames(1)
	check(absf(angle_difference(yaw_before, p.yaw)) <= 2.6 / 60.0 + 0.001, "enemy_behind_keeps_lock_turn_cap")
	await frames(180)
	check(in_frame(p, 1.4) and in_frame(arena.enemy, 1.4), "enemy_behind_reframes_at_selected_zoom")
	await capture("07_enemy_behind_reframed")
	# Both approach the lens together under ordinary backward movement.
	place()
	await frames(45)
	old_position = p.position
	action("move_back")
	for tick in range(20):
		arena.enemy.position = p.position + Vector3(0.0, 0.0, -1.5)
		if tick % 4 == 0: wheel(MOUSE_BUTTON_WHEEL_DOWN if tick % 8 == 0 else MOUSE_BUTTON_WHEEL_UP)
		await frames(1)
	action("move_back", false)
	check(p.position.distance_to(old_position) > 0.3 and in_frame(p, 1.4) and in_frame(arena.enemy, 1.4), "both_approaching_camera_remain_framed")

	# Session ownership: resets replace CombatState, not camera/player settings.
	wheel(MOUSE_BUTTON_WHEEL_UP, 40)
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 2)
	await frames(45)
	selected = p.preferred_camera_distance
	var arm_before := p.spring.spring_length
	arena.reset_encounter()
	check(p.preferred_camera_distance == selected and p.spring.spring_length == arm_before, "encounter_reset_preserves_zoom_and_smoothing")
	p.combat.health = 0.0
	p.combat.phase = Rules.Phase.DEAD
	arena.progression.record_loss()
	check(arena.progression.stage == arena.Progression.Stage.FALLEN and p.preferred_camera_distance == selected, "defeat_keeps_zoom")
	arena.set_physics_process(true)
	await tap("reset")
	check(p.combat.health > 0.0 and p.preferred_camera_distance == selected, "retry_input_keeps_zoom")
	arena.set_physics_process(false)
	place()
	# Arrange a one-hit-remaining opponent; resolve a real attack before salvage.
	arena.enemy.combat.health = 1.0
	p.combat.attack()
	p.combat.tick(p.combat.windup_duration() + 0.001)
	arena._resolve_duel()
	check(arena.progression.stage == arena.Progression.Stage.VICTORY, "lethal_contact_opens_real_reward_transaction")
	arena.set_physics_process(true)
	await tap("salvage")
	check(arena.progression.owns("item.marrow_arm") and p.preferred_camera_distance == selected, "salvage_keeps_zoom")
	await tap("equip")
	check(arena.progression.equipped() and p.preferred_camera_distance == selected, "equipment_state_replacement_keeps_zoom")
	await tap("next_duel")
	check(arena.progression.duel_number == 2 and p.preferred_camera_distance == selected, "next_duel_keeps_zoom")
	await tap("signature")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(p.combat.is_signature() and p.locked == false, "zoom_during_equipped_marrow_attack")
	await tap("help")
	await tap("debug")
	check(arena.hud.show_controls and p.debug_hitboxes and arena.enemy.debug_hitboxes, "f1_and_f3_still_work")
	await capture("08_controls")
	var summary := {"summary": true, "passed": passed, "failed": failed, "rendered": DisplayServer.get_name() != "headless"}
	records.append(summary)
	print(JSON.stringify(summary))
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify(records, "\t") + "\n")
	arena.free()
	quit(int(failed > 0))

func _wheel_event(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = true
	return event
