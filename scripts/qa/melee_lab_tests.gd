extends SceneTree
## Deterministic checks for the isolated directional melee lab: data and build reuse,
## direction classification, swing arcs, weapon-dependent handling, defensive alignment,
## swept hit registration, cancels, AI perception fairness, determinism and isolation.
## Rules are driven directly (no physics server); scene checks drive legal input events.
## These prove reachable behaviour and invariants, not that the combat feels good.
## --negative=no-substeps disables swept substeps; --negative=omniscient gives the AI no
## reaction delay. Each must fail its named checks.
## Run: bash scripts/tooling/test_melee_lab.sh [new-empty-dir]

const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
const DT := 1.0 / 60.0
var tuning: Dictionary
var lab: Dictionary
var weapons := {}
var negative := ""
var output := "res://artifacts/melee-lab"
var passed := 0
var failed := 0
var results := {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--negative="):
			negative = arg.trim_prefix("--negative=")
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
	print(JSON.stringify(record))

# --- Harness -------------------------------------------------------------------

func tuned(overrides := {}) -> Dictionary:
	var values := tuning.duplicate()
	values.merge(overrides, true)
	return values

func handling(id: String, t := tuning) -> Dictionary:
	return Handling.derive(weapons[id], t)

func duelist(id: String, t := tuning) -> State:
	return State.new(t, handling(id, t), {"deflect_window": 0.16})

## Attacker at +Z facing -Z; defender at the origin facing the attacker.
func frames(distance: float) -> Array[Transform3D]:
	return [Transform3D(Basis(), Vector3(0.0, 0.0, distance)), Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)]

func settle_guard(d: State, sector: String, ticks := 40) -> void:
	d.set_guard(true, sector)
	for i in range(ticks):
		d.tick(DT)
	d.guard_age = 99.0 # Settled: no longer a fresh press.

## Runs an attack until contact or `limit` ticks. `each(tick)` runs before each tick.
func exchange(a: State, d: State, direction: String, distance := 2.0, limit := 120, each := Callable(), dt := DT, sweep := true) -> Dictionary:
	var xf := frames(distance)
	a.press_attack(direction)
	a.release_attack()
	for tick in range(limit):
		if each.is_valid():
			each.call(tick)
		a.tick(dt)
		d.tick(dt)
		var report := Solver.resolve(a, xf[0], xf[0], d, xf[1], xf[1], sweep and negative != "no-substeps")
		if report.result != Solver.NONE:
			report.tick = tick
			report.time = (tick + 1) * dt
			return report
	return {"result": Solver.NONE, "tick": -1}

## Simulates an unopposed swing; returns time to θ = 0 (straight ahead) and ω there.
func swing_profile(id: String, direction: String, from_direction := "") -> Dictionary:
	var a := duelist(id)
	if from_direction != "":
		a.press_attack(from_direction)
		a.release_attack()
		while a.phase != State.Phase.IDLE:
			a.tick(DT)
	a.press_attack(direction)
	a.release_attack()
	var time := 0.0
	var windup := -1.0
	while time < 3.0:
		a.tick(DT)
		time += DT
		if a.phase == State.Phase.SWING and windup < 0.0:
			windup = time
		if a.phase == State.Phase.SWING and a.theta <= 0.0:
			return {"contact": time, "windup": windup, "omega": a.omega, "momentum": a.momentum()}
		if a.phase == State.Phase.SWING and direction == Geometry.THRUST and a.extension >= tuning.thrust_extension * 0.5:
			return {"contact": time, "windup": windup, "omega": 0.0, "momentum": a.momentum()}
	return {"contact": INF, "windup": windup, "omega": 0.0, "momentum": 0.0}

func correct_guard(direction: String) -> String:
	if direction == Geometry.THRUST:
		return Geometry.CENTER_GUARD
	var c := Geometry.chamber_vector(direction)
	return Geometry.classify_guard(Vector2(-c.x, c.y), 0.0)

# Owner feedback regression: windups and guards are deliberate held stances.
# Previously the one-second max_hold forced an unwanted automatic swing.
func hold_until_release_checks() -> void:
	var a := duelist("sword")
	a.press_attack("right_to_left")
	for i in range(180): # 3 seconds > legacy max_hold (1 second)
		a.tick(DT)
	check(a.phase == State.Phase.WINDUP and not a.released and a.swing_serial == 0,
		"directional_attack_stays_chambered_until_button_release",
		{"phase": a.phase, "elapsed": a.windup_time, "swing_serial": a.swing_serial})
	a.aim_attack("overhead")
	for i in range(90):
		a.tick(DT)
	check(a.phase == State.Phase.WINDUP and a.direction == "overhead" and not a.released,
		"held_chamber_can_redirect_without_auto_firing")
	a.release_attack()
	for i in range(90):
		a.tick(DT)
		if a.swing_serial > 0:
			break
	check(a.swing_serial == 1, "released_chamber_starts_exactly_one_swing")

	var d := duelist("sword")
	d.set_guard(true, "left")
	for i in range(240):
		d.tick(DT)
	check(d.phase == State.Phase.IDLE and d.guarding and d.guard == "left" and d.guard_age > d.deflect_window,
		"directional_guard_remains_held_without_repeated_deflect")
	d.set_guard(true, "high")
	for i in range(90):
		d.tick(DT)
	check(d.guarding and d.guard == "high" and d.guard_age > d.deflect_window,
		"held_guard_can_change_direction_without_refreshing_deflect")
	d.set_guard(false)
	check(not d.guarding, "guard_lowers_only_on_release")

# --- Suites --------------------------------------------------------------------

func run() -> void:
	var loaded := Loadout.load_tuning()
	tuning = loaded.values
	lab = Loadout.load_lab()
	check(loaded.ok and lab.ok, "lab_data_loads", loaded.errors + lab.errors)
	if not (loaded.ok and lab.ok):
		return finish()
	if negative == "omniscient":
		tuning.ai_reaction_delay = 0.0
	data_checks()
	hold_until_release_checks()
	classification_checks()
	arc_checks()
	handling_checks()
	alignment_checks()
	registration_checks()
	cancel_checks()
	await scene_checks()
	await ai_checks()
	isolation_checks()
	finish()

func finish() -> void:
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true) + "\n")
	print(JSON.stringify({"suite": "melee_lab", "summary": true, "passed": passed, "failed": failed, "negative": negative, "engine": Engine.get_version_info().string}))
	quit(0 if failed == 0 else 1)

func data_checks() -> void:
	var ids := {}
	for loadout: Dictionary in lab.loadouts:
		var resolved := Loadout.resolve(lab, "player", loadout.id)
		check(resolved.ok, "loadout_resolves_through_build_rules_" + loadout.id, resolved.errors)
		if resolved.ok:
			weapons[loadout.id] = resolved.weapon
			ids[loadout.id] = resolved.weapon.item
	check(ids.get("sword") == "item.notched_sword" and ids.get("greatsword") == "item.lab_greatsword", "loadouts_use_equipment_weapon_view", ids)
	check(weapons.get("greatsword", {}).get("grips", []) == ["hand_r", "hand_l"], "two_handed_weapon_occupies_both_grips", weapons.get("greatsword", {}).get("grips"))
	var enemy := Loadout.resolve(lab, "opponent", "sword")
	check(enemy.ok and enemy.stats.move_speed > 0.0, "opponent_uses_shared_profile_stats", enemy.get("stats"))
	var shared := FileAccess.get_file_as_string("res://data/builds/catalog.json")
	check(not shared.contains("item.lab_"), "shared_catalog_file_has_no_lab_items")
	# Lab items pass through the same catalog validation as production items.
	var base: Variant = Loadout.read_json("res://data/builds/catalog.json")
	var bad: Dictionary = Loadout.read_json(Loadout.WEAPONS_PATH)
	bad.items[0].weapon.handling.mass = 0.0
	var rejected := Loadout.lab_from_data(base, bad)
	check(not rejected.ok and str(rejected.errors).contains("mass must be positive"), "invalid_lab_weapon_rejected_by_catalog", rejected.errors)
	var mixed := lab.duplicate()
	mixed.loadouts = [{"id": "x", "equipped": {"hand_r": "item.lab_greatsword", "hand_l": "item.lab_long_knife"}}]
	var occupied := Loadout.resolve(mixed, "player", "x")
	check(not occupied.ok and str(occupied.errors).contains("grip_occupied"), "two_hander_with_offhand_weapon_rejected", occupied.errors)
	var tuning_data: Dictionary = Loadout.read_json(Loadout.TUNING_PATH)
	tuning_data.values.max_hold = "long"
	check(not Loadout.tuning_from_data(tuning_data).ok, "non_numeric_tuning_rejected")

func classification_checks() -> void:
	var dz: float = tuning.aim_deadzone
	var cases := {Vector2(1, 0): "right_to_left", Vector2(-1, 0): "left_to_right", Vector2(0, 1): "overhead",
		Vector2(0.7, 0.7): "diag_right", Vector2(-0.7, 0.7): "diag_left", Vector2(0, -1): "thrust",
		Vector2(0.9, -0.3): "right_to_left", Vector2(-0.9, -0.3): "left_to_right", Vector2(0.2, -0.9): "thrust",
		Vector2(0.95, 0.3): "right_to_left", Vector2(0.3, 0.95): "overhead", Vector2(0.45, 0.85): "diag_right", Vector2(0.1, 0.1): ""}
	var wrong := {}
	for cursor: Vector2 in cases:
		var got := Geometry.classify_attack(cursor, dz)
		if got != cases[cursor]:
			wrong[str(cursor)] = got
	check(wrong.is_empty(), "attack_direction_classification", wrong)
	var guards := {Vector2(1, 0): "right", Vector2(0, 1): "high", Vector2(-1, 0): "left", Vector2(0, -1): "center",
		Vector2(0.7, 0.7): "high_right", Vector2(-0.7, 0.7): "high_left", Vector2(0.0, 0.2): ""}
	wrong.clear()
	for cursor: Vector2 in guards:
		if Geometry.classify_guard(cursor, dz) != guards[cursor]:
			wrong[str(cursor)] = Geometry.classify_guard(cursor, dz)
	check(wrong.is_empty(), "guard_sector_classification", wrong)
	var a := duelist("sword")
	var chain: Array[String] = []
	for i in range(3):
		a.press_attack("")
		a.release_attack()
		chain.append(a.direction)
		while a.phase != State.Phase.IDLE:
			a.tick(DT)
	check(chain == ["right_to_left", "left_to_right", "right_to_left"], "tap_without_flick_alternates_follow_up", chain)
	var mirrored := true
	for direction: String in Geometry.SWINGS:
		mirrored = mirrored and Geometry.guard_vector(correct_guard(direction)).is_equal_approx(Vector2(-Geometry.chamber_vector(direction).x, Geometry.chamber_vector(direction).y))
	check(mirrored, "arrival_side_mirrors_attacker_chamber")

func arc_checks() -> void:
	var length: float = weapons.sword.handling.length
	var radius_error := 0.0
	var plane_error := 0.0
	for direction: String in Geometry.SWINGS:
		var normal := Geometry.FORWARD.cross(Geometry.frontal(Geometry.chamber_vector(direction))).normalized()
		for i in range(21):
			var theta := lerpf(Geometry.swing_start(tuning), Geometry.swing_end(direction, tuning), i / 20.0)
			var pose := Geometry.swing_pose(direction, theta, tuning)
			var tip := Geometry.tip(pose, length)
			radius_error = maxf(radius_error, absf(tip.distance_to(Geometry.pivot(tuning)) - (tuning.arm_reach + length)))
			plane_error = maxf(plane_error, absf((tip - Geometry.pivot(tuning)).dot(normal)))
	check(radius_error < 1e-4, "swing_tip_stays_at_reach_radius", radius_error)
	check(plane_error < 1e-4, "swing_stays_in_its_plane", plane_error)
	var start := Geometry.swing_pose("right_to_left", Geometry.swing_start(tuning), tuning)
	check(start.dir.dot(Geometry.FORWARD) < 0.0 and start.dir.x > 0.9, "right_chamber_starts_behind_on_the_right", start.dir)
	var end := Geometry.swing_pose("right_to_left", Geometry.swing_end("right_to_left", tuning), tuning)
	check(end.dir.x < -0.9, "right_to_left_ends_on_the_left", end.dir)
	var lowest := INF
	for id: String in weapons:
		var tip := Geometry.tip(Geometry.swing_pose("overhead", Geometry.swing_end("overhead", tuning), tuning), weapons[id].handling.length)
		lowest = minf(lowest, tip.y)
	check(lowest > 0.0, "overhead_stops_above_ground_for_every_weapon", lowest)
	var horizontal := Geometry.tip(Geometry.swing_pose("left_to_right", 0.0, tuning), length)
	check(absf(horizontal.y - tuning.pivot_height) < 1e-4 and horizontal.z < -2.0, "horizontal_cut_at_chest_height_straight_ahead", horizontal)
	var thrust := Geometry.tip(Geometry.thrust_pose(tuning.thrust_extension, tuning), length)
	check(absf(thrust.x) < 0.1 and thrust.z < -2.5, "thrust_extends_along_forward", thrust)
	var a := duelist("sword")
	a.press_attack("right_to_left")
	a.release_attack()
	var live_early := false
	var live_seen := false
	while a.phase in [State.Phase.WINDUP, State.Phase.SWING]:
		a.tick(DT)
		if a.phase == State.Phase.SWING:
			live_early = live_early or (a.is_live() and a.theta > Geometry.swing_live(tuning) + 1e-6)
			live_seen = live_seen or a.is_live()
		if a.phase == State.Phase.WINDUP:
			live_early = live_early or a.is_live()
	check(live_seen and not live_early, "blade_live_only_inside_live_arc")

func handling_checks() -> void:
	var h := {}
	for id: String in weapons:
		h[id] = handling(id)
	check(h.knife.inertia < h.sword.inertia and h.sword.inertia < h.staff.inertia and h.staff.inertia < h.greatsword.inertia,
		"inertia_orders_knife_sword_staff_greatsword", {"knife": h.knife.inertia, "sword": h.sword.inertia, "staff": h.staff.inertia, "greatsword": h.greatsword.inertia})
	var profiles := {}
	for id: String in ["knife", "sword", "greatsword"]:
		profiles[id] = swing_profile(id, "right_to_left")
	results.swing_profiles = profiles
	check(profiles.knife.contact < profiles.sword.contact and profiles.sword.contact < profiles.greatsword.contact,
		"heavier_weapon_reaches_contact_later", profiles)
	check(profiles.knife.momentum < profiles.sword.momentum and profiles.sword.momentum < profiles.greatsword.momentum,
		"heavier_weapon_carries_more_momentum", profiles)
	check(profiles.sword.contact <= 0.45, "sword_cut_contacts_within_0_45s_from_rest", profiles.sword.contact)
	var follow := swing_profile("sword", "left_to_right", "right_to_left")
	var repeat := swing_profile("sword", "right_to_left", "right_to_left")
	var heavy_repeat := swing_profile("greatsword", "right_to_left", "right_to_left")
	var heavy_follow := swing_profile("greatsword", "left_to_right", "right_to_left")
	results.direction_change = {"sword_follow_up": follow.windup, "sword_repeat": repeat.windup, "greatsword_follow_up": heavy_follow.windup, "greatsword_repeat": heavy_repeat.windup}
	check(follow.windup < repeat.windup, "follow_up_cut_prepares_faster_than_repeat", results.direction_change)
	check(heavy_repeat.windup - heavy_follow.windup > repeat.windup - follow.windup, "direction_change_costs_more_with_heavier_weapon", results.direction_change)
	check(follow.windup >= tuning.min_windup - 1e-6, "windup_never_below_readability_floor", follow.windup)
	var one_handed: Dictionary = weapons.greatsword.duplicate(true)
	one_handed.grip = "one_handed"
	var one := Handling.derive(one_handed, tuning)
	check(one.accel < h.greatsword.accel and one.guard_strength < h.greatsword.guard_strength, "two_handed_grip_adds_torque_and_guard_strength", {"two": h.greatsword.accel, "one": one.accel})
	var recover := {}
	for id: String in ["knife", "sword", "greatsword"]:
		var a := duelist(id)
		a.press_attack("overhead")
		a.release_attack()
		while a.phase != State.Phase.RECOVERY:
			a.tick(DT)
		recover[id] = a.remaining
	check(recover.knife < recover.sword and recover.sword < recover.greatsword, "missed_swing_recovery_grows_with_momentum", recover)
	var shift := {}
	for id: String in ["knife", "sword", "greatsword"]:
		var d := duelist(id)
		d.set_guard(true, "high")
		var ticks := 0
		while d.dir.angle_to(Geometry.guard_pose("high", tuning).dir) > 0.01 and ticks < 120:
			d.tick(DT)
			ticks += 1
		shift[id] = ticks * DT
	results.guard_raise_seconds = shift
	check(shift.knife < shift.sword and shift.sword < shift.greatsword and shift.greatsword <= 0.3, "guard_raise_time_grows_with_inertia_but_stays_fast", shift)
	check(h.greatsword.turn_rate < h.sword.turn_rate, "heavier_weapon_limits_turning_while_attacking", {"sword": h.sword.turn_rate, "greatsword": h.greatsword.turn_rate})

func alignment_checks() -> void:
	var matrix := {}
	var correct_blocks := true
	var opposite_fails := true
	for direction: String in Geometry.DIRECTIONS:
		matrix[direction] = {}
		for sector: String in Geometry.GUARDS.keys() + [Geometry.CENTER_GUARD]:
			var a := duelist("sword")
			var d := duelist("sword")
			settle_guard(d, sector)
			var report := exchange(a, d, direction)
			matrix[direction][sector] = report.result
		var right_side: String = matrix[direction][correct_guard(direction)]
		correct_blocks = correct_blocks and right_side == Solver.BLOCK
		var opposite := "left" if correct_guard(direction) in ["right", "high_right"] else ("right" if correct_guard(direction) in ["left", "high_left"] else ("center" if correct_guard(direction) == "high" else "high"))
		opposite_fails = opposite_fails and matrix[direction][opposite] in [Solver.HIT, Solver.MISALIGNED]
	results.alignment_matrix = matrix
	check(correct_blocks, "aligned_guard_blocks_every_direction", matrix)
	check(opposite_fails, "opposite_guard_fails_every_direction", matrix)
	var a := duelist("sword")
	var d := duelist("sword")
	var unguarded := exchange(a, d, "overhead")
	check(unguarded.result == Solver.HIT and unguarded.damage > 0.0 and not unguarded.guard_bypassed, "unguarded_cut_hits", unguarded.get("damage"))
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "right")
	var bypass := exchange(a, d, "right_to_left")
	check(bypass.result == Solver.HIT and bypass.guard_bypassed, "guard_on_wrong_side_is_bypassed", bypass.result)
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "center")
	var glance := exchange(a, d, "overhead")
	check(glance.result == Solver.MISALIGNED and glance.alignment > tuning.block_align_deg and glance.damage > 0.0 and glance.damage < unguarded.damage, "touched_guard_at_bad_angle_is_misaligned", glance)
	# Deflection: time a fresh press just before measured contact.
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "left")
	var block := exchange(a, d, "right_to_left")
	var press_tick: int = block.tick - 4
	for offset: Array in [["deflect", 4], ["early", 4 + int(ceil(0.16 / DT)) + 2]]:
		a = duelist("sword")
		d = duelist("sword")
		settle_guard(d, "left")
		d.deflect_ready_in = 0.0
		var at: int = block.tick - offset[1]
		var report := exchange(a, d, "right_to_left", 2.0, 120, func(tick: int) -> void:
			if tick == at - 1:
				d.set_guard(false)
			elif tick == at:
				d.set_guard(true, "left"))
		results["timed_press_" + offset[0]] = report.result
		if offset[0] == "deflect":
			check(report.result == Solver.DEFLECT and a.phase == State.Phase.RECOIL and a.posture > 0.0, "fresh_aligned_press_deflects", report.result)
		else:
			check(report.result == Solver.BLOCK, "press_outside_window_only_blocks", report.result)
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "high_left")
	var adjacent := exchange(a, d, "right_to_left", 2.0, 120, func(tick: int) -> void:
		if tick == press_tick - 1:
			d.set_guard(false)
		elif tick == press_tick:
			d.set_guard(true, "high_left"))
	check(adjacent.result == Solver.BLOCK and adjacent.alignment > tuning.deflect_align_deg, "fresh_press_45_degrees_off_blocks_not_deflects", adjacent.get("alignment"))
	a = duelist("staff")
	a = duelist("sword")
	d = duelist("staff")
	settle_guard(d, "left")
	var staff := exchange(a, d, "right_to_left", 2.0, 120, func(tick: int) -> void:
		if tick == press_tick - 1:
			d.set_guard(false)
		elif tick == press_tick:
			d.set_guard(true, "left"))
	check(staff.result == Solver.BLOCK, "weapon_without_deflect_capability_only_blocks", staff.result)
	a = duelist("greatsword")
	d = duelist("knife")
	settle_guard(d, "high")
	var overwhelm := exchange(a, d, "overhead", 2.2)
	check(overwhelm.result == Solver.GUARD_BREAK and d.phase == State.Phase.BROKEN, "heavy_blow_overwhelms_light_guard", overwhelm.get("posture"))
	a = duelist("sword")
	d = duelist("greatsword")
	settle_guard(d, "high")
	var strong := exchange(a, d, "overhead")
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "high")
	var normal := exchange(a, d, "overhead")
	check(strong.result == Solver.BLOCK and normal.result == Solver.BLOCK and strong.posture < normal.posture, "heavier_two_handed_guard_absorbs_more", {"greatsword": strong.posture, "sword": normal.posture})
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "high")
	var outcomes: Array[String] = []
	for i in range(6):
		var report := exchange(a, d, "overhead")
		outcomes.append(report.result)
		while a.phase != State.Phase.IDLE:
			a.tick(DT)
			d.tick(DT)
		if report.result == Solver.GUARD_BREAK:
			break
	check(outcomes[-1] == Solver.GUARD_BREAK and outcomes.size() > 2, "repeated_blocks_accumulate_into_guard_break", outcomes)
	var hit_after_break := exchange(a, d, "overhead")
	check(hit_after_break.result == Solver.HIT and hit_after_break.damage > unguarded.damage * 1.5, "broken_guard_takes_punish_damage", hit_after_break.get("damage"))
	# Attacked from behind: the guard is in front of the defender.
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "left")
	var xf := frames(2.0)
	var behind := Transform3D(Basis(), Vector3.ZERO)
	a.press_attack("right_to_left")
	a.release_attack()
	var rear := {"result": Solver.NONE}
	for tick in range(120):
		a.tick(DT)
		d.tick(DT)
		rear = Solver.resolve(a, xf[0], xf[0], d, behind, behind, negative != "no-substeps")
		if rear.result != Solver.NONE:
			break
	check(rear.result == Solver.HIT, "guard_does_not_cover_the_back", rear.result)
	a = duelist("sword")
	d = duelist("sword")
	var dodged := exchange(a, d, "overhead", 2.0, 120, func(tick: int) -> void:
		if tick == 12:
			d.dodge())
	check(dodged.result == Solver.EVADED, "dodge_invulnerability_evades", dodged.result)
	a = duelist("sword")
	d = duelist("sword")
	# The defender's left-to-right travels the same world way as the attacker's
	# right-to-left, so the two blades sweep across each other.
	d.press_attack("left_to_right")
	d.release_attack()
	var clash := exchange(a, d, "right_to_left")
	check(clash.result == Solver.CLASH and a.phase == State.Phase.RECOIL and d.phase == State.Phase.RECOIL, "crossing_live_blades_clash", clash.result)

func registration_checks() -> void:
	# A guard-thin target at extreme blade speed: one tick moves the tip ~1.3 m.
	var fast := tuned({"max_angular_speed": 80.0, "torque_one_handed": 4000.0})
	var a := duelist("sword", fast)
	var d := duelist("sword", fast)
	settle_guard(d, "left")
	var swept := exchange(a, d, "right_to_left", 2.0, 120, Callable(), DT, true)
	var weapon_contacts := [Solver.BLOCK, Solver.DEFLECT, Solver.GUARD_BREAK]
	check(swept.result in weapon_contacts and swept.substeps > 10, "fast_blade_cannot_tunnel_through_guard", {"result": swept.result, "substeps": swept.get("substeps")})
	a = duelist("sword", fast)
	d = duelist("sword", fast)
	settle_guard(d, "left")
	var end_only := exchange(a, d, "right_to_left", 2.0, 120, Callable(), DT, false)
	results.end_pose_only_result = end_only.result
	check(end_only.result not in weapon_contacts, "control_end_pose_only_would_tunnel", end_only.result)
	a = duelist("sword")
	d = duelist("sword")
	settle_guard(d, "left")
	var report := exchange(a, d, "right_to_left")
	var xf := frames(2.0)
	var blade := Solver.closest_points(report.point, report.point, xf[0] * a.pose_at(1.0).hand, xf[0] * Geometry.tip(a.pose_at(1.0), a.h.length))
	var guard := Solver.closest_points(report.point, report.point, xf[1] * d.hand, xf[1] * Geometry.tip({"hand": d.hand, "dir": d.dir}, d.h.length))
	check(blade.distance <= tuning.blade_radius + tuning.guard_radius + 0.06 and guard.distance < 1e-3, "contact_point_on_drawn_weapons", {"blade": blade.distance, "guard": guard.distance})
	var reach := {}
	for case: Array in [["sword", 3.2], ["sword", 2.4], ["knife", 2.2], ["knife", 1.5], ["greatsword", 2.9]]:
		a = duelist(case[0])
		d = duelist("sword")
		reach["%s@%.1f" % case] = exchange(a, d, "right_to_left", case[1]).result
	results.reach = reach
	check(reach["sword@3.2"] == Solver.NONE and reach["knife@2.2"] == Solver.NONE and reach["sword@2.4"] == Solver.HIT and reach["knife@1.5"] == Solver.HIT and reach["greatsword@2.9"] == Solver.HIT,
		"reach_follows_weapon_length", reach)
	var rates := {}
	for hz: float in [60.0, 120.0, 30.0]:
		a = duelist("sword")
		d = duelist("sword")
		settle_guard(d, "left")
		var r := exchange(a, d, "right_to_left", 2.0, int(hz * 2), Callable(), 1.0 / hz)
		rates[str(hz)] = {"result": r.result, "time": r.get("time", -1.0)}
	check(rates["60.0"].result == rates["120.0"].result and rates["30.0"].result == rates["60.0"].result and absf(rates["60.0"].time - rates["120.0"].time) <= 1.0 / 30.0,
		"outcome_independent_of_tick_rate", rates)
	var runs: Array[String] = []
	for i in range(2):
		var log: Array = []
		a = duelist("sword")
		d = duelist("greatsword")
		for direction: String in ["overhead", "diag_left", "thrust", "right_to_left"]:
			settle_guard(d, "high", 5)
			var r := exchange(a, d, direction)
			log.append([r.result, snappedf(r.get("time", -1.0), 0.0001), snappedf(d.posture, 0.0001), snappedf(d.health, 0.0001)])
			while a.phase != State.Phase.IDLE or d.phase != State.Phase.IDLE:
				a.tick(DT)
				d.tick(DT)
		runs.append(JSON.stringify(log))
	check(runs[0] == runs[1], "exchange_sequence_is_deterministic", runs[0])

func cancel_checks() -> void:
	var a := duelist("sword")
	a.press_attack("overhead")
	a.tick(DT)
	a.set_guard(true, "high")
	check(a.phase == State.Phase.IDLE and a.guarding and a.guard_delay == 0.0 and a.guard_age == 0.0, "guard_press_cancels_windup_instantly")
	a = duelist("greatsword")
	var d := duelist("sword")
	var xf := frames(2.0)
	a.press_attack("right_to_left")
	a.release_attack()
	while a.phase != State.Phase.SWING or a.omega < 8.0:
		a.tick(DT)
	a.set_guard(true, "high")
	var delay := a.guard_delay
	var contact := false
	for i in range(60):
		a.tick(DT)
		d.tick(DT)
		contact = contact or Solver.resolve(a, xf[0], xf[0], d, xf[1], xf[1]).result != Solver.NONE
	check(not contact and delay > 0.0 and delay <= tuning.cancel_brake_cap + 1e-6, "guard_cancels_swing_after_bounded_brake", delay)
	for from_phase: int in [State.Phase.WINDUP, State.Phase.SWING, State.Phase.RECOVERY]:
		a = duelist("sword")
		a.press_attack("left_to_right")
		a.release_attack()
		while a.phase != from_phase:
			a.tick(DT)
		check(a.dodge() and a.phase == State.Phase.DODGE and a.hit_consumed, "dodge_cancels_" + State.Phase.keys()[from_phase].to_lower() + "_immediately")
	a = duelist("sword")
	a.dodge()
	a.tick(DT)
	check(not a.dodge(), "dodge_cooldown_prevents_chain")
	d = duelist("sword")
	d.set_guard(true, "high")
	for i in range(30):
		d.tick(DT)
	var held_age := d.guard_age
	d.set_guard(false)
	d.tick(DT)
	d.set_guard(true, "high") # A legitimate fresh press (rearm has elapsed)...
	for i in range(3):
		d.tick(DT)
	d.set_guard(false)
	d.tick(DT)
	d.set_guard(true, "high") # ...but pressing again inside the rearm cannot.
	var spam_age := d.guard_age
	check(held_age > d.deflect_window and spam_age > d.deflect_window, "held_or_spammed_guard_cannot_deflect", {"held": held_age, "repress": spam_age})
	a = duelist("sword")
	a.press_attack("overhead")
	a.release_attack()
	while a.phase != State.Phase.RECOVERY or a.remaining > 0.15:
		a.tick(DT)
	var buffered := a.press_attack("left_to_right")
	a.release_attack()
	var started := false
	for i in range(60):
		a.tick(DT)
		if a.phase == State.Phase.WINDUP:
			started = a.direction == "left_to_right"
			break
	check(not buffered and started, "attack_pressed_during_recovery_buffers_into_next_cut")
	a = duelist("sword")
	a.press_attack("right_to_left")
	for i in range(4):
		a.tick(DT)
	a.aim_attack("overhead")
	a.release_attack()
	while a.phase == State.Phase.WINDUP:
		a.tick(DT)
	check(a.direction == "overhead", "unreleased_windup_can_redirect")

## Legal input events through the real scene: aim ownership and camera separation.
func scene_checks() -> void:
	var arena: Node = load("res://scenes/melee_lab.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	await physics_frame
	var player: Node = arena.player
	player.accept_uncaptured_motion = true
	arena.opponent.mode = "dummy"
	var yaw_before: float = player.camera_yaw
	player.locked = false
	await press_mouse(MOUSE_BUTTON_LEFT, true)
	motion(Vector2(0, -60))
	await frames_wait(2)
	var aimed: String = player.state.direction
	var yaw_while_aiming: float = player.camera_yaw
	await press_mouse(MOUSE_BUTTON_LEFT, false)
	await frames_wait(40)
	check(aimed == "overhead" and is_equal_approx(yaw_while_aiming, yaw_before), "held_attack_mouse_aims_without_turning_camera", {"aimed": aimed, "yaw": yaw_while_aiming - yaw_before})
	motion(Vector2(80, 0))
	await frames_wait(1)
	check(not is_equal_approx(player.camera_yaw, yaw_before) and player.aim_owner == "", "free_mouse_returns_to_camera", player.camera_yaw - yaw_before)
	await frames_wait(30)
	await press_mouse(MOUSE_BUTTON_RIGHT, true)
	motion(Vector2(70, 0))
	await frames_wait(3)
	check(player.state.guarding and player.state.guard == "right", "held_guard_mouse_aims_guard_side", player.state.guard)
	await press_mouse(MOUSE_BUTTON_RIGHT, false)
	await frames_wait(10)
	arena.reset_duel()
	await frames_wait(2)
	await press_mouse(MOUSE_BUTTON_LEFT, true)
	await press_mouse(MOUSE_BUTTON_LEFT, false)
	await frames_wait(2)
	check(player.state.phase == State.Phase.WINDUP and player.state.direction == "right_to_left", "tap_starts_follow_up_cut_immediately", player.state.direction)
	arena.queue_free()
	await process_frame

## Duplicates the lab's own mapped event, exactly as a real click arrives.
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

## Perception fairness and determinism, stepping the arena manually.
func ai_checks() -> void:
	var traces: Array[String] = []
	for run_index in range(2):
		var arena: Node = load("res://scenes/melee_lab.tscn").instantiate()
		arena.manual_step = true # Paused while configured; stepped by real physics frames below.
		root.add_child(arena)
		await process_frame
		arena.tuning.merge(tuning, true) # Apply negative-control overrides.
		arena.player.input_enabled = false
		var ai: Node = arena.opponent
		ai.reset_ai()
		await fairness_run(arena, run_index == 0)
		ai.mode = "duel"
		arena.reset_duel()
		arena.player.state.max_health = 10000.0
		arena.player.state.health = 10000.0
		var used := {}
		var repeats := 0
		arena.manual_step = false
		await frames_wait(60 * 30)
		arena.manual_step = true
		for entry: Dictionary in ai.trace:
			if entry.event == "attack":
				used[entry.direction] = used.get(entry.direction, 0) + 1
		var attacks: Array = ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "attack")
		for i in range(2, attacks.size()):
			repeats += int(attacks[i].direction == attacks[i - 1].direction and attacks[i].direction == attacks[i - 2].direction)
		if run_index == 0:
			results.ai_attack_directions = used
			check(used.size() >= 5 and repeats == 0, "ai_attacks_vary_direction_without_triple_repeats", used)
			check(arena.events.size() > 10, "ai_duel_produces_contacts_against_idle_player", arena.events.size())
		traces.append(JSON.stringify(ai.trace) + JSON.stringify(arena.events.map(func(e: Dictionary) -> String: return "%s:%s:%.4f" % [e.attacker, e.result, e.at])))
		arena.queue_free()
		await process_frame
	check(traces[0] == traces[1], "ai_duel_replays_identically", traces[0].length())

func fairness_run(arena: Node, report: bool) -> void:
	var ai: Node = arena.opponent
	var p: State = arena.player.state
	ai.mode = "defend"
	arena.tuning.ai_guard_accuracy = 1.0
	arena.tuning.ai_deflect_attempt = 0.0
	arena.reset_duel()
	arena.manual_step = false
	await frames_wait(30)
	var delay: float = arena.tuning.ai_reaction_delay
	var start: float = arena.clock
	p.press_attack("right_to_left")
	var first_answer := -1.0
	var redirect_at := -1.0
	var second_answer := -1.0
	for i in range(40):
		if i == 14:
			p.aim_attack("left_to_right")
			redirect_at = arena.clock
		await physics_frame
		if first_answer < 0.0 and ai.state.guarding and ai.state.guard == "left":
			first_answer = arena.clock
		if redirect_at >= 0.0 and second_answer < 0.0 and ai.state.guard == "right":
			second_answer = arena.clock
	arena.manual_step = true
	p.reset()
	if not report:
		return
	results.ai_fairness = {"reaction_delay": delay, "first_answer_after": first_answer - start, "redirect_answer_after": second_answer - redirect_at}
	# The shipped tuning's delay is the bound, whatever this run was configured with.
	var minimum: float = Loadout.load_tuning().values.ai_reaction_delay
	check(first_answer - start >= minimum - 0.001, "ai_guard_waits_for_reaction_delay", results.ai_fairness)
	check(second_answer - redirect_at >= minimum - 0.001, "late_redirect_is_seen_only_after_delay", results.ai_fairness)

func isolation_checks() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "default_launch_scene_unchanged")
	var offenders: Array[String] = []
	for dir_path: String in ["res://scripts", "res://scenes"]:
		offenders.append_array(_referencing(dir_path))
	check(offenders.is_empty(), "no_production_file_references_the_lab", offenders)

func _referencing(path: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(path):
		var full := path.path_join(file)
		if full.contains("melee_lab") or not (file.ends_with(".gd") or file.ends_with(".tscn")):
			continue
		if FileAccess.get_file_as_string(full).contains("melee_lab"):
			found.append(full)
	for sub: String in DirAccess.get_directories_at(path):
		if sub != "melee_lab":
			found.append_array(_referencing(path.path_join(sub)))
	return found
