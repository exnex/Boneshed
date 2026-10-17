extends SceneTree
## Adversarial combat probe. Drives the real courtyard scene with action input and
## records measurements. It characterizes behavior; it does not assert design goals.
## Run: bash scripts/tooling/probe.sh [new-empty-dir]

const Rules = preload("res://scripts/combat/combat_state.gd")
const Courtyard = preload("res://scenes/courtyard.tscn")
var arena: Node3D
var p: Fighter
var e: Fighter
var output := "res://artifacts/probe"
var records: Array = []
var tally := {}
var seen_p := 0
var seen_e := 0
var enemy_attacks := 0
var enemy_interrupted := 0
var only: PackedStringArray = []
var last_e_phase := 0
var held := {}
var negative := ""
var failed := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		if arg.begins_with("--negative="):
			negative = arg.trim_prefix("--negative=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = Courtyard.instantiate()
	root.add_child(arena)
	call_deferred("run")

func record(scenario: String, data: Dictionary) -> void:
	data["scenario"] = scenario
	records.append(data)
	print(JSON.stringify(data))

func press(action: String, pressed := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	held[action] = pressed

func release_all() -> void:
	for action in held:
		if held[action]:
			press(action, false)

func step(count := 1) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
		_observe()

func _observe() -> void:
	# Reset zeroes the serials; count only new combat events.
	if p.event_serial > seen_p:
		tally["player_" + p.last_result] = tally.get("player_" + p.last_result, 0) + 1
	seen_p = p.event_serial
	if e.event_serial > seen_e:
		tally["enemy_" + e.last_result] = tally.get("enemy_" + e.last_result, 0) + 1
	seen_e = e.event_serial
	var phase: int = e.combat.phase
	if phase != last_e_phase:
		if phase == Rules.Phase.WINDUP:
			enemy_attacks += 1
		elif last_e_phase == Rules.Phase.WINDUP and phase in [Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.DEAD] and not e.combat.hit_consumed:
			# Hit during windup; a deflected swing has already consumed its hit.
			enemy_interrupted += 1
		last_e_phase = phase
	if p.combat.phase == Rules.Phase.BROKEN:
		tally["player_broken_frames"] = tally.get("player_broken_frames", 0) + 1
	if e.combat.phase == Rules.Phase.BROKEN:
		tally["enemy_broken_frames"] = tally.get("enemy_broken_frames", 0) + 1

func fresh(enemy_ai := false) -> void:
	release_all()
	await step(2)
	arena.reset_encounter()
	p.input_enabled = true
	p.dodge_speed = 11.0
	e.enabled = enemy_ai
	e.defense_enabled = negative != "defense"
	tally = {}
	enemy_attacks = 0
	enemy_interrupted = 0
	seen_p = 0
	seen_e = 0
	last_e_phase = Rules.Phase.IDLE

func place(player_at: Vector3, enemy_at: Vector3, lock := true) -> void:
	p.position = player_at
	e.position = enemy_at
	p.velocity = Vector3.ZERO
	e.velocity = Vector3.ZERO
	var toward := enemy_at - player_at
	toward.y = 0.0
	p.facing = toward.normalized()
	e.facing = -toward.normalized()
	p.yaw = atan2(-p.facing.x, -p.facing.z)
	p.locked = lock

func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	paused = true
	arena.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	paused = false

func run() -> void:
	p = arena.player
	e = arena.enemy
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await step(10)
	if only.is_empty() or "dodge_momentum" in only:
		await dodge_momentum()
	if only.is_empty() or "dodge_into_enemy" in only:
		await dodge_into_enemy()
	if only.is_empty() or "dodge_into_walls" in only:
		await dodge_into_walls()
	if only.is_empty() or "evasion_windows" in only:
		await evasion_windows()
	if only.is_empty() or "deflect_from_behind" in only:
		await deflect_from_behind()
	if only.is_empty() or "preheld_guard" in only:
		await preheld_guard()
	if only.is_empty() or "guard_attack_conflict" in only:
		await guard_attack_conflict()
	if only.is_empty() or "recovery_shortening" in only:
		await recovery_shortening()
	if only.is_empty() or "simultaneous_attacks" in only:
		await simultaneous_attacks()
	if only.is_empty() or "locked_homing" in only:
		await locked_homing()
	if only.is_empty() or "hitbox_edges" in only:
		await hitbox_edges()
	if only.is_empty() or "live_strategies" in only:
		await live_strategies()
	if "iteration2_regressions" in only:
		await iteration2_regressions()
	if only.is_empty() or "enemy_pathing" in only:
		await enemy_pathing()
	if only.is_empty() or "enemy_reactions" in only:
		await enemy_reactions()
	if only.is_empty() or "camera_checks" in only:
		await camera_checks()
	if only.is_empty() or "reset_checks" in only:
		await reset_checks()
	if only.is_empty() or "tick_rates" in only:
		await tick_rates()
	var file := FileAccess.open(output.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t") + "\n")
	print(JSON.stringify({"probe_summary": true, "records": records.size(), "failed": failed, "engine": Engine.get_version_info().string}))
	quit(1 if failed else 0)

# --- Dodge ------------------------------------------------------------------

func measure_dodge(label: String, run_frames: int, run_action: String, dodge_action: String) -> void:
	await fresh()
	place(Vector3(0.0, 0.02, 4.0), Vector3(6.0, 0.02, -8.0), false)
	p.facing = Vector3.FORWARD
	if run_action != "":
		press(run_action)
		await step(run_frames)
		press(run_action, false)
	var start := p.position
	var speed_before := Vector2(p.velocity.x, p.velocity.z).length()
	if dodge_action != "":
		press(dodge_action)
	press("dodge")
	await step(1)
	press("dodge", false)
	var peak := 0.0
	var dodge_frames := 1
	while p.combat.phase == Rules.Phase.DODGE:
		peak = maxf(peak, Vector2(p.velocity.x, p.velocity.z).length())
		await step(1)
		dodge_frames += 1
	var at_iframe_end := p.position - start
	if dodge_action != "":
		press(dodge_action, false)
	var slide := 0
	while Vector2(p.velocity.x, p.velocity.z).length() > 0.05 and slide < 120:
		await step(1)
		slide += 1
	var total := p.position - start
	record("dodge_momentum", {"case": label, "speed_before": snappedf(speed_before, 0.01), "dodge_direction": vec(p.dodge_direction), "displacement_during_iframes": vec(at_iframe_end), "post_dodge_slide_frames": slide, "total_displacement": vec(total), "peak_speed": snappedf(peak, 0.01), "configured_dodge_speed": p.dodge_speed, "dodge_frames": dodge_frames})

func dodge_momentum() -> void:
	await measure_dodge("standstill_backstep", 0, "", "")
	await measure_dodge("standstill_back_input", 0, "", "move_back")
	await measure_dodge("run_forward_then_dodge_back", 40, "move_forward", "move_back")
	await measure_dodge("run_forward_then_dodge_right", 40, "move_forward", "move_right")
	await measure_dodge("run_forward_then_dodge_forward", 40, "move_forward", "move_forward")

func dodge_into_enemy() -> void:
	for lateral in [0.0, 0.15, 0.3, 0.45, 0.6]:
		for hold_forward in [false, true]:
			await fresh()
			place(Vector3(lateral, 0.02, 1.85), Vector3(0.0, 0.02, 0.0), false)
			p.facing = Vector3.FORWARD
			p.yaw = 0.0 # world -Z, so the lateral offset is real
			press("move_forward")
			press("dodge")
			await step(1)
			press("dodge", false)
			if not hold_forward:
				press("move_forward", false)
			var min_distance := 99.0
			for i in range(50):
				var flat := Vector2(p.position.x - e.position.x, p.position.z - e.position.z)
				min_distance = minf(min_distance, flat.length())
				await step(1)
			press("move_forward", false)
			record("dodge_into_enemy", {"start_lateral": lateral, "hold_forward_after": hold_forward, "min_center_distance": snappedf(min_distance, 0.001), "capsule_contact_distance": 0.7, "player_final": vec(p.position), "enemy_final": vec(e.position), "ended_past_enemy": p.position.z < e.position.z})

func dodge_into_walls() -> void:
	var cases := [["perimeter_wall", Vector3(0.0, 0.02, 10.6), Vector3.BACK], ["corner", Vector3(10.6, 0.02, 10.6), Vector3(1, 0, 1).normalized()], ["pillar", Vector3(9.0, 0.02, 5.0), Vector3.FORWARD]]
	for item in cases:
		await fresh()
		place(item[1], Vector3(-6.0, 0.02, -6.0), false)
		p.facing = -item[2]
		var max_reach := -99.0
		press("dodge")
		await step(1)
		press("dodge", false)
		for i in range(40):
			max_reach = maxf(max_reach, (p.position - item[1]).dot(item[2]))
			await step(1)
		record("dodge_into_wall", {"case": item[0], "start": vec(item[1]), "max_travel_into_obstacle": snappedf(max_reach, 0.001), "final": vec(p.position), "inside_arena": absf(p.position.x) < 11.6 and absf(p.position.z) < 11.6})
	# Cornered by the live enemy: can a sideways dodge escape along the wall?
	await fresh(true)
	place(Vector3(10.9, 0.02, 10.9), Vector3(9.4, 0.02, 9.4))
	await step(5)
	press("move_left")
	press("dodge")
	await step(1)
	press("dodge", false)
	await step(30)
	press("move_left", false)
	record("dodge_cornered", {"player_final": vec(p.position), "escaped_distance": snappedf(p.position.distance_to(Vector3(10.9, 0.02, 10.9)), 0.01), "player_health": p.combat.health})

# --- Timing windows --------------------------------------------------------

func timing_outcome(input: String, press_frame: int, dodge_speed: float) -> String:
	await fresh()
	place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0))
	p.dodge_speed = dodge_speed
	await step(1)
	e.combat.attack()
	var frame := 0
	var active_frame := -1
	while e.combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE] and frame < 120:
		if frame == press_frame:
			press(input)
		if frame == press_frame + 1 and input == "dodge":
			press(input, false)
		await step(1)
		frame += 1
		if e.combat.phase == Rules.Phase.ACTIVE and active_frame < 0:
			active_frame = frame
	release_all()
	return p.last_result if p.last_result != "" else "no_contact"

func evasion_windows() -> void:
	# Frame indices count from enemy attack start; ACTIVE begins on frame 38.
	for input in [["guard", 11.0, "deflect_or_guard"], ["dodge", 0.0, "dodge_iframes_only"], ["dodge", 11.0, "dodge_with_backstep_movement"]]:
		var outcomes := {}
		for press_frame in range(14, 46):
			outcomes[str(press_frame)] = await timing_outcome(input[0], press_frame, input[1])
		var success := []
		for k in outcomes:
			if outcomes[k] in ["deflected", "evaded", "no_contact"]:
				success.append(int(k))
		record("timing_window", {"case": input[2], "active_starts_frame": 38, "successful_press_frames": success, "successful_count": success.size(), "outcomes": outcomes})

func deflect_from_behind() -> void:
	for timed in [true, false]:
		await fresh()
		place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0), false)
		p.facing = Vector3.BACK
		await step(1)
		if not timed:
			press("guard")
			await step(30)
		e.combat.attack()
		while e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining > 0.09:
			await step(1)
		press("guard")
		await step(12)
		release_all()
		record("guard_from_behind", {"timed_press": timed, "player_facing": vec(p.facing), "result": p.last_result, "player_health": p.combat.health, "enemy_posture": e.combat.posture})

func preheld_guard() -> void:
	# Guard pressed once during the player's own whiffed attack and held: when the
	# player returns to IDLE the guard rises automatically with a fresh deflect window.
	await fresh()
	place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0), false)
	p.facing = Vector3.BACK
	await step(1)
	press("attack")
	await step(1)
	press("attack", false)
	await step(2)
	press("guard")
	var frame := 0
	var idle_frame := -1
	while frame < 100 and p.last_result == "":
		if frame == 20:
			e.combat.attack()
		await step(1)
		frame += 1
		if idle_frame < 0 and p.combat.phase == Rules.Phase.IDLE:
			idle_frame = frame
			p.facing = Vector3.FORWARD # Incoming contact is frontal; isolate pre-held guard.
	release_all()
	record("preheld_guard", {"guard_presses": 1, "guard_pressed_during": "own attack windup", "player_idle_frame": idle_frame, "result": p.last_result, "player_health": p.combat.health})

func guard_attack_conflict() -> void:
	await fresh()
	place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0))
	press("guard")
	await step(5)
	press("attack")
	await step(1)
	press("attack", false)
	var while_guarding: int = p.combat.phase
	press("guard", false)
	press("attack")
	await step(1)
	press("attack", false)
	var same_frame_release: int = p.combat.phase
	await step(70)
	# Attack pressed during own recovery is dropped: no buffer.
	await fresh()
	place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 8.0))
	press("attack")
	await step(1)
	press("attack", false)
	while p.combat.phase != Rules.Phase.RECOVERY:
		await step(1)
	while p.combat.remaining > 0.08:
		await step(1)
	press("attack")
	await step(1)
	press("attack", false)
	await step(8)
	record("input_conflicts", {"attack_while_guard_held_phase": Rules.Phase.keys()[while_guarding], "release_guard_and_attack_same_frame_phase": Rules.Phase.keys()[same_frame_release], "attack_pressed_5_frames_before_recovery_end_phase_after": Rules.Phase.keys()[p.combat.phase]})

# --- Attacks -----------------------------------------------------------------

func recovery_shortening() -> void:
	for hit in [false, true]:
		await fresh()
		place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0))
		e.facing = Vector3.FORWARD # enemy swings away and whiffs
		p.input_enabled = false
		await step(1)
		e.combat.attack()
		var frame := 0
		var recovery_start := -1
		var idle_at := -1
		while frame < 150:
			if hit and frame == 28:
				p.combat.attack()
			await step(1)
			frame += 1
			if recovery_start < 0 and e.combat.phase in [Rules.Phase.RECOVERY, Rules.Phase.STAGGER]:
				recovery_start = frame
			if recovery_start >= 0 and e.combat.phase == Rules.Phase.IDLE:
				idle_at = frame
				break
		record("recovery_after_whiff", {"punished_by_hit": hit, "enemy_lockout_frames_after_active": idle_at - recovery_start, "result": e.last_result})

func simultaneous_attacks() -> void:
	for offset in range(-3, 4):
		await fresh()
		place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0))
		p.input_enabled = false
		await step(1)
		e.combat.attack()
		# Player windup is 21 ticks, enemy 38; offset 0 makes both ACTIVE on one tick.
		var player_start := 17 + offset
		for frame in range(80):
			if frame == player_start:
				p.combat.attack()
			await step(1)
		record("simultaneous_attacks", {"player_active_offset_ticks": offset, "player_health": p.combat.health, "enemy_health": e.combat.health, "player_result": p.last_result, "enemy_result": e.last_result})

func locked_homing() -> void:
	for lock in [true, false]:
		await fresh()
		place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0), lock)
		press("attack")
		await step(1)
		press("attack", false)
		await step(5)
		# Target relocates behind the attacker mid-windup.
		e.position = Vector3(0.0, 0.02, 3.6)
		await step(40)
		record("facing_during_attack", {"locked": lock, "enemy_moved_behind_during_windup": true, "enemy_result": e.last_result, "enemy_health": e.combat.health})

func hitbox_edges() -> void:
	# Box spans forward 0..2.35 from the attacker origin; lateral includes the target radius
	# but forward reach does not.
	var cases := [["forward_2.30", Vector3(0, 0.02, -2.30)], ["forward_2.50_capsule_overlaps_box", Vector3(0, 0.02, -2.50)], ["lateral_1.10_forward_1.0", Vector3(1.10, 0.02, -1.0)], ["lateral_1.20_forward_1.0", Vector3(1.20, 0.02, -1.0)], ["side_by_side_touching_behind_origin", Vector3(0.7, 0.02, 0.05)]]
	for item in cases:
		await fresh()
		place(Vector3(0.0, 0.02, 0.0), item[1], false)
		p.facing = Vector3.FORWARD
		p.input_enabled = false
		await step(1)
		p.combat.attack()
		p.combat.tick(p.combat.attack_windup + 0.001)
		record("hitbox_edge", {"case": item[0], "target_center": vec(item[1]), "result": p.resolve_attack()})
	# Single centre-line ray: a pillar edge hides the centre but not the body edge.
	await fresh()
	place(Vector3(8.5, 0.02, 3.95), Vector3(8.5, 0.02, 2.05), false)
	p.facing = Vector3.FORWARD
	p.input_enabled = false
	await step(2)
	p.combat.attack()
	p.combat.tick(p.combat.attack_windup + 0.001)
	record("hitbox_edge", {"case": "target_partially_behind_pillar", "player": vec(p.position), "target": vec(e.position), "result": p.resolve_attack()})

# --- Live AI strategies -----------------------------------------------------

func live(label: String, policy: Callable, limit := 2400, distance := -1.0) -> Dictionary:
	await fresh(true)
	if distance > 0.0:
		place(Vector3(0.0, 0.02, distance), Vector3(0.0, 0.02, 0.0))
	p.locked = true
	var frame := 0
	while frame < limit and e.combat.phase != Rules.Phase.DEAD and p.combat.phase != Rules.Phase.DEAD:
		policy.call(frame)
		await step(1)
		frame += 1
	release_all()
	var data := {"strategy": label, "frames": frame, "seconds": snappedf(frame / 60.0, 0.01), "winner": "player" if e.combat.phase == Rules.Phase.DEAD else ("enemy" if p.combat.phase == Rules.Phase.DEAD else "timeout"), "player_health": p.combat.health, "enemy_health": e.combat.health, "enemy_attacks_started": enemy_attacks, "enemy_attacks_interrupted_in_windup": enemy_interrupted, "events": tally.duplicate()}
	record("live_strategy", data)
	return data

func regression(condition: bool, label: String) -> void:
	if not condition:
		failed += 1
	record("iteration2_regression", {"check": label, "passed": condition, "negative": negative})

func skilled_policy(_frame: int) -> void:
	var defend: bool = e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining < 0.12 and p_idle()
	if held.get("guard", false) != defend:
		press("guard", defend)
	var punish: bool = p_idle() and not defend and e.combat.phase in [Rules.Phase.BROKEN, Rules.Phase.RECOVERY, Rules.Phase.STAGGER]
	if held.get("attack", false) != punish:
		press("attack", punish)

func iteration2_regressions() -> void:
	# Legal press/release inputs, real scene/AI/hit resolution, no synthetic damage.
	for distance in [1.2, 1.85, 2.2]:
		for period in [2, 5]:
			var outcome := await live("attack_only_%.2f_period_%d" % [distance, period], func(f): mash("attack", f, period), 2400, distance)
			regression(outcome.winner == "enemy", "attack_only_loses_%.2f_period_%d" % [distance, period])
	var toggle := await live("blind_toggle_and_break_punish", func(f):
		if e.combat.phase == Rules.Phase.BROKEN:
			if held.get("guard", false):
				press("guard", false)
			mash("attack", f)
		else:
			var want: bool = f % 10 != 9
			if held.get("guard", false) != want:
				press("guard", want))
	regression(toggle.winner == "enemy" and toggle.events.get("player_deflected", 0) < 2, "blind_toggle_loses_without_repeated_deflections")
	var skilled := await live("skilled_deflect_punish", skilled_policy, 2400, 1.85)
	regression(skilled.winner == "player" and skilled.player_health == 100.0 and skilled.events.get("player_deflected", 0) >= 2, "skilled_deflect_punish_wins_untouched")

func mash(action: String, frame: int, period := 2) -> void:
	var want := frame % period == 0
	if held.get(action, false) != want:
		press(action, want)

func p_idle() -> bool:
	return p.combat.phase == Rules.Phase.IDLE

func live_strategies() -> void:
	await live("stationary_no_input", func(_f): pass)
	await live("hold_guard_forever", func(f): if f == 0: press("guard"))
	await live("mash_attack_only", func(f): mash("attack", f))
	await live("guard_toggle_9_on_1_off", func(f):
		var want: bool = f % 10 != 9
		if held.get("guard", false) != want:
			press("guard", want))
	await live("guard_toggle_9_on_1_off_attack_when_broken", func(f):
		if e.combat.phase == Rules.Phase.BROKEN:
			if held.get("guard", false):
				press("guard", false)
			mash("attack", f)
		else:
			var want: bool = f % 10 != 9
			if held.get("guard", false) != want:
				press("guard", want))
	await live("sidestep_windup_then_punish", func(f):
		var dist := p.position.distance_to(e.position)
		var side := e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining < 0.45
		var punish := e.combat.phase in [Rules.Phase.RECOVERY, Rules.Phase.STAGGER, Rules.Phase.BROKEN]
		if held.get("move_right", false) != side:
			press("move_right", side)
		var close_in := punish and dist > 1.9
		if held.get("move_forward", false) != close_in:
			press("move_forward", close_in)
		if punish and not close_in:
			mash("attack", f)
		elif held.get("attack", false):
			press("attack", false))
	await live("backstep_windup_then_punish", func(f):
		var dist := p.position.distance_to(e.position)
		var back := e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining < 0.4
		var fwd := e.combat.phase in [Rules.Phase.RECOVERY, Rules.Phase.STAGGER] and dist > 1.6
		if held.get("move_back", false) != back:
			press("move_back", back)
		if held.get("move_forward", false) != fwd:
			press("move_forward", fwd)
		if e.combat.phase in [Rules.Phase.RECOVERY, Rules.Phase.STAGGER, Rules.Phase.BROKEN] and dist < 2.2:
			mash("attack", f)
		elif held.get("attack", false):
			press("attack", false))
	await live("dodge_whenever_ready_no_attack", func(f): mash("dodge", f, 4), 1800)

# --- AI ----------------------------------------------------------------------

func enemy_pathing() -> void:
	var cases := [["player_behind_pillar", Vector3(9.0, 0.02, 4.6), Vector3(9.0, 0.02, -1.0)], ["player_behind_brazier", Vector3(7.0, 0.02, 7.2), Vector3(7.0, 0.02, 2.0)], ["player_behind_low_block", Vector3(7.3, 0.02, -9.2), Vector3(7.3, 0.02, -3.0)]]
	for item in cases:
		await fresh(true)
		place(item[1], item[2], false)
		p.input_enabled = false
		var min_distance := 99.0
		for i in range(600):
			min_distance = minf(min_distance, p.position.distance_to(e.position))
			await step(1)
		record("enemy_pathing", {"case": item[0], "enemy_final": vec(e.position), "min_distance": snappedf(min_distance, 0.01), "ai_state": e.ai_state, "enemy_attacks_started": enemy_attacks, "player_health": p.combat.health})

func enemy_reactions() -> void:
	# Turn speed: the player appears behind an idle enemy; count ticks until it faces them.
	await fresh(true)
	place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0), false)
	p.input_enabled = false
	await step(2)
	p.position = Vector3(0.0, 0.02, -1.8)
	var ticks := 0
	while ticks < 120:
		await step(1)
		ticks += 1
		var toward := (p.position - e.position) * Vector3(1, 0, 1)
		if e.facing.dot(toward.normalized()) > 0.99:
			break
	record("enemy_turn", {"ticks_to_face_player_behind": ticks, "enemy_facing": vec(e.facing)})
	# After a posture break the AI resumes with whatever attack cooldown was left over.
	await fresh(true)
	place(Vector3(0.0, 0.02, 1.8), Vector3(0.0, 0.02, 0.0))
	p.input_enabled = false
	await step(1)
	var leftover: float = e.cooldown
	e.combat.add_posture(100.0)
	var frame := 0
	var idle_frame := -1
	var windup_frame := -1
	while frame < 400 and windup_frame < 0:
		await step(1)
		frame += 1
		if idle_frame < 0 and e.combat.phase == Rules.Phase.IDLE:
			idle_frame = frame
		if e.combat.phase == Rules.Phase.WINDUP:
			windup_frame = frame
	record("enemy_after_break", {"cooldown_left_when_broken": snappedf(leftover, 0.01), "break_ticks": idle_frame, "ticks_from_break_end_to_next_windup": windup_frame - idle_frame})

# --- Camera ------------------------------------------------------------------

func occlusion() -> Dictionary:
	var cam: Camera3D = p.camera
	var enemy_chest := cam.unproject_position(e.global_position + Vector3.UP * 1.2)
	var enemy_feet := cam.unproject_position(e.global_position + Vector3.UP * 0.05)
	var player_chest := cam.unproject_position(p.global_position + Vector3.UP * 1.2)
	var player_edge := cam.unproject_position(p.global_position + Vector3.UP * 1.2 + cam.global_basis.x * 0.4)
	var half_width := player_chest.distance_to(player_edge)
	var segment_start := cam.global_position
	var head := p.global_position + Vector3.UP * 1.6
	var closest := Geometry3D.get_closest_point_to_segment(e.global_position + Vector3.UP * 1.0, segment_start, head)
	var camera_to_enemy_axis := Vector2(cam.global_position.x - e.global_position.x, cam.global_position.z - e.global_position.z).length()
	return {"spring_length": snappedf(p.spring.get_hit_length(), 0.01), "enemy_chest_px": [roundi(enemy_chest.x), roundi(enemy_chest.y)], "player_chest_px": [roundi(player_chest.x), roundi(player_chest.y)], "player_half_width_px": roundi(half_width), "enemy_chest_hidden_behind_player": absf(enemy_chest.x - player_chest.x) < half_width and enemy_chest.y < player_chest.y + half_width * 3.0, "enemy_feet_px": [roundi(enemy_feet.x), roundi(enemy_feet.y)], "enemy_blocks_view_of_player": closest.distance_to(e.global_position + Vector3.UP * 1.0) < 0.35, "camera_inside_enemy_capsule": camera_to_enemy_axis < 0.35 and cam.global_position.y < e.global_position.y + 1.8}

func camera_checks() -> void:
	for distance in [1.85, 3.0, 5.0]:
		await fresh()
		place(Vector3(0.0, 0.02, distance), Vector3(0.0, 0.02, 0.0))
		await step(30)
		var data := occlusion()
		data["distance"] = distance
		record("camera_framing_locked", data)
		if distance == 1.85:
			e.combat.attack()
			await step(20)
			await shot("probe_close_range_windup_occlusion")
	# Enemy between camera and player (free camera, player walked past it).
	await fresh()
	place(Vector3(0.0, 0.02, 0.0), Vector3(0.6, 0.02, 3.2), false)
	p.facing = Vector3.FORWARD
	p.yaw = 0.0
	await step(10)
	var behind := occlusion()
	behind["case"] = "enemy_behind_player_free_camera"
	record("camera_enemy_behind", behind)
	await shot("probe_enemy_between_camera_and_player")
	# Backed into a corner while locked on.
	await fresh()
	place(Vector3(10.9, 0.02, 10.9), Vector3(9.0, 0.02, 9.0))
	await step(40)
	var corner := occlusion()
	corner["case"] = "player_cornered_locked"
	corner["camera_to_player_head"] = snappedf(p.camera.global_position.distance_to(p.global_position + Vector3.UP * 1.6), 0.01)
	record("camera_corner", corner)
	await shot("probe_cornered_camera")
	# Lock-on validity: through a pillar, at range, and after death.
	await fresh()
	place(Vector3(9.0, 0.02, 4.6), Vector3(9.0, 0.02, 1.4), false)
	press("lock_on")
	await step(2)
	press("lock_on", false)
	var through_pillar: bool = p.locked
	e.combat.health = 1.0
	e.combat.phase = Rules.Phase.DEAD
	await step(2)
	record("lock_on", {"lock_acquired_through_pillar": through_pillar, "lock_has_range_limit": false, "still_locked_after_enemy_death": p.locked})
	# Mouse release, then a click to recapture: does the click also swing?
	await fresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await step(1)
	press("attack")
	await step(1)
	press("attack", false)
	record("mouse_recapture_click", {"phase_after_recapture_click": Rules.Phase.keys()[p.combat.phase], "mouse_mode_after": Input.mouse_mode})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await step(60)

# --- Reset -------------------------------------------------------------------

func reset_now() -> void:
	press("reset")
	await step(1)
	press("reset", false)

func reset_state() -> Dictionary:
	return {"player_phase": Rules.Phase.keys()[p.combat.phase], "enemy_phase": Rules.Phase.keys()[e.combat.phase], "player_health": p.combat.health, "enemy_health": e.combat.health, "player_posture": p.combat.posture, "enemy_posture": e.combat.posture, "player_pos": vec(p.position), "enemy_pos": vec(e.position), "player_guard_age": snappedf(p.combat.guard_age, 0.001), "player_guarding": p.combat.guarding, "enemy_pose_rot_z": snappedf(e.visual.rotation.z, 0.001), "player_pose_rot_z": snappedf(p.visual.rotation.z, 0.001), "impact_visible": e.impact.visible or p.impact.visible}

func reset_checks() -> void:
	var cases := ["enemy_active_in_range", "player_dodging", "enemy_deflect_stagger", "enemy_dead", "player_dead", "enemy_broken", "reset_spam_10", "guard_held_through_reset"]
	for label in cases:
		await fresh(label != "enemy_dead")
		place(Vector3(0.0, 0.02, 1.8), Vector3(0.0, 0.02, 0.0))
		await step(1)
		match label:
			"enemy_active_in_range":
				e.combat.attack()
				while e.combat.phase != Rules.Phase.WINDUP or e.combat.remaining > 0.02:
					await step(1)
			"player_dodging":
				press("dodge")
				await step(3)
				press("dodge", false)
			"enemy_deflect_stagger":
				e.combat.attack()
				while e.combat.phase == Rules.Phase.WINDUP and e.combat.remaining > 0.09:
					await step(1)
				press("guard")
				await step(7)
			"enemy_dead":
				e.combat.health = 0.0
				e.combat.phase = Rules.Phase.DEAD
				await step(2)
			"player_dead":
				p.combat.health = 0.0
				p.combat.phase = Rules.Phase.DEAD
				await step(2)
			"enemy_broken":
				e.combat.add_posture(100.0)
				await step(2)
			"guard_held_through_reset":
				press("guard")
				await step(30)
		var before := reset_state()
		if label == "reset_spam_10":
			e.combat.attack()
			for i in range(10):
				await reset_now()
		else:
			await reset_now()
		var after := reset_state()
		await step(5)
		var later := reset_state()
		record("reset", {"case": label, "before": before, "after_reset_frame": after, "five_frames_later": later, "events_in_scenario": tally.duplicate()})

# --- Tick rates ----------------------------------------------------------------

func tick_rates() -> void:
	for hz in [30, 60, 120, 240]:
		Engine.physics_ticks_per_second = hz
		await fresh()
		place(Vector3(0.0, 0.02, 4.0), Vector3(6.0, 0.02, -8.0), false)
		p.facing = Vector3.FORWARD
		var start := p.position
		Input.action_press("dodge")
		await physics_frame
		await physics_frame
		Input.action_release("dodge")
		var ticks := 0
		while ticks < hz * 2:
			await physics_frame
			ticks += 1
		var dodge_distance := p.position.distance_to(start)
		# Deflect window in ticks: guard pressed k ticks before enemy ACTIVE.
		var deflect_ticks := 0
		for lead in range(0, int(hz * 0.3)):
			await fresh()
			place(Vector3(0.0, 0.02, 2.0), Vector3(0.0, 0.02, 0.0))
			await physics_frame
			e.combat.attack()
			var t := 0
			while e.combat.phase == Rules.Phase.WINDUP:
				# Press when the remaining windup is about lead ticks long.
				if not Input.is_action_pressed("guard") and e.combat.remaining <= float(lead) / hz:
					Input.action_press("guard")
				await physics_frame
				t += 1
			for i in range(int(hz * 0.2)):
				await physics_frame
			Input.action_release("guard")
			if p.last_result == "deflected":
				deflect_ticks += 1
		record("tick_rate", {"physics_hz": hz, "standstill_dodge_distance": snappedf(dodge_distance, 0.001), "deflect_success_leads": deflect_ticks, "deflect_window_seconds_effective": snappedf(float(deflect_ticks) / hz, 0.001)})
	Engine.physics_ticks_per_second = 60
