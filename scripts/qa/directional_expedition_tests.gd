extends SceneTree
## Deterministic integration checks for the directional expedition. Everything runs in
## the real scene (shell → controller → lab rules) except the pure rules-state checks.
## Fixture setup may place bodies and choose a soul's lab mode (dummy guard side,
## defend, attack) — as the melee lab's own tests do — but every attack, guard,
## dodge, roll and lunge is an ordinary InputEvent, and every outcome is read back
## from the contact solver's reports, the stamina ledger and the status pipeline.
##
## Run: bash scripts/tooling/test_directional_expedition.sh [new-dir]
const Shell = preload("res://scenes/directional_expedition.tscn")
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Adapter = preload("res://scripts/directional_expedition/directional_adapter.gd")
const ExpState = preload("res://scripts/directional_expedition/expedition_state.gd")
const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
const DT := 1.0 / 60.0
const WORDS := ["drowned", "hollow", "cathedral"]
const SEED := 1001
var output := "res://artifacts/directional-expedition-tests"
var passed := 0
var failed := 0
var results: Array = []
var shell: Node
var e: Node3D
var held := {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	results.append({"check": label, "passed": condition, "detail": _plain(detail)})
	print(JSON.stringify({"check": label, "passed": condition, "detail": _plain(detail)}))

static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[str(key)] = _plain(value[key])
		return out
	if value is Array:
		return value.map(func(v: Variant) -> Variant: return _plain(v))
	if value is float:
		return snappedf(value, 0.0001)
	if value is Vector3 or value is Vector2:
		return str(value)
	return value

func run() -> void:
	adapter_checks()
	signature_state_checks()
	await composition_checks()
	await geometry_checks()
	await stamina_checks()
	await status_checks()
	await ai_checks()
	await encounter_checks()
	await progression_checks()
	await determinism_checks()
	await original_scene_checks()
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t") + "\n")
	print(JSON.stringify({"suite": "directional_expedition", "summary": true, "passed": passed, "failed": failed,
		"engine": Engine.get_version_info().string}))
	quit(1 if failed else 0)

# --- Scene helpers -----------------------------------------------------------------

func start(words: Array = WORDS, seed_value := SEED) -> void:
	if is_instance_valid(shell):
		await stop()
	shell = Shell.instantiate()
	root.add_child(shell)
	await process_frame
	shell.start_expedition(words, seed_value)
	e = shell.session
	e.player.accept_uncaptured_motion = true
	await frames(2)

func stop() -> void:
	release_all()
	await physics_frame
	shell.queue_free()
	shell = null
	e = null
	await process_frame

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func key(action: String, pressed: bool) -> void:
	if held.get(action, false) == pressed:
		return
	held[action] = pressed
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(action: String) -> void:
	key(action, true)
	await physics_frame
	key(action, false)
	await physics_frame

func release_all() -> void:
	for action: String in held.keys():
		key(action, false)

func motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)

## Fixture: stand `distance` m from site `index`'s soul, facing it; the director engages.
func engage(index: int, mode: String, guard := "", distance := 2.0) -> Node:
	var site: Dictionary = e.sites[index]
	if site.area != e.area:
		e._enter(site.area, site.position + Vector3(0, 0, distance), 0.0)
	var approach := Vector3(0.0, 0.0, distance)
	e.player.teleport(site.position + approach + Vector3.UP * 0.05, 0.0)
	await frames(2)
	var soul: Node = site.enemy
	soul.mode = mode
	soul.dummy_guard = guard
	soul.state.set_guard(false)
	await frames(30)
	return soul

## Fixture: re-place both bodies at an exact spacing (rules state untouched).
func place(soul: Node, distance := 2.0) -> void:
	var post: Vector3 = soul.post
	soul.position = post + Vector3.UP * 0.05
	soul.velocity = Vector3.ZERO
	soul.facing = Vector3.BACK
	e.player.teleport(post + Vector3(0, 0.05, distance), 0.0)
	await frames(1)

## LMB press, flick toward `cursor`, hold `hold` frames, release. Returns the first
## contact report the player's blade produced afterwards ({} if none in 90 frames).
func cut(cursor: Vector2, hold := 20) -> Dictionary:
	var before: int = e.events.size()
	key("lab_attack", true)
	await physics_frame
	if cursor != Vector2.ZERO:
		motion(Vector2(cursor.x, -cursor.y) * 70.0)
	await frames(hold)
	key("lab_attack", false)
	for i in 90:
		await physics_frame
		for j in range(before, e.events.size()):
			if e.events[j].attacker == "Pilgrim":
				return e.events[j]
	return {}

func wait_idle(actor: Node, limit := 180) -> void:
	for i in limit:
		if actor.state.phase == State.Phase.IDLE:
			return
		await physics_frame

# --- 1. Shared build data → directional fighters ------------------------------------

func adapter_checks() -> void:
	var adapter = Adapter.load_default()
	check(adapter.ok, "adapter_loads_shared_catalog_lab_items_and_builds", adapter.errors)
	var tuning: Dictionary = adapter.tuning
	var shared_builds: Dictionary = Loadout.read_json("res://data/builds/salvage_courtyard.json")
	check(adapter.builds.player.equipped == shared_builds.player.equipped and adapter.builds.player.profile == shared_builds.player.profile,
		"player_build_is_the_shared_salvage_build", adapter.builds.player)
	var player: Dictionary = adapter.resolve_fighter(adapter.builds.player, ["armor.lab_mail_shirt"], "player")
	check(player.ok and player.weapon.item == "item.notched_sword" and player.stats.max_health == 100.0 and player.stats.move_speed == 5.5,
		"player_weapon_and_profile_stats_from_shared_rules", player.get("stats"))
	# The same derivation every lab fighter uses: costs follow weapon inertia and armor mass.
	var handling := Handling.derive(player.weapon, tuning)
	var derived := CombatResources.derive(handling, "item.notched_sword", ["armor.lab_mail_shirt"], adapter.combat, tuning)
	var expected_attack: float = tuning.attack_cost_base + tuning.attack_cost_per_inertia * handling.inertia + tuning.attack_cost_per_armor_kg * 9.0
	check(is_equal_approx(derived.attack_cost, expected_attack) and is_equal_approx(derived.dodge_cost, tuning.dodge_cost * (1.0 + tuning.evasion_cost_per_armor_kg * 9.0)),
		"stamina_costs_follow_weapon_inertia_and_armor_mass", {"attack": derived.attack_cost, "dodge": derived.dodge_cost})
	var costs := {}
	for variant: Dictionary in adapter.data.encounters.exterior + [adapter.data.encounters.guardian]:
		var soul: Dictionary = adapter.resolve_fighter(adapter.enemy_build(variant, "t." + variant.id), variant.armor, variant.label)
		var h := Handling.derive(soul.weapon, tuning)
		var r := CombatResources.derive(h, str(soul.weapon.item), variant.armor, adapter.combat, tuning)
		costs[variant.id] = {"attack": snappedf(r.attack_cost, 0.01), "roll": snappedf(r.roll_cost, 0.01), "move": snappedf(r.move_scale, 0.001),
			"signature": not soul.signature.is_empty(), "profile": soul.build.profile}
		check(soul.ok and soul.build.profile == "profile.corrupted_swordsman" and soul.stats.move_speed == 2.7, "soul_%s_resolves_from_shared_enemy_profile" % variant.id, costs[variant.id])
		check(soul.signature.is_empty() == not ("item.marrow_arm" in variant.equipped.values()), "soul_%s_lunge_only_if_marrow_arm_equipped" % variant.id)
	check(costs.iron_guardian.attack > costs.sword_vigil.attack and costs.sword_vigil.attack > costs.venom_vigil.attack
		and costs.iron_guardian.move < costs.sword_vigil.move and costs.sword_vigil.move < costs.venom_vigil.move,
		"heavier_weapons_and_armor_cost_more_and_move_slower", costs)
	# Shared legality: a two-handed greatsword cannot be held beside the handless Marrow Arm.
	var illegal: Dictionary = adapter.builds.enemy.duplicate(true)
	illegal.equipped = {"hand_r": "item.lab_greatsword", "arm_l": "item.marrow_arm"}
	check(not adapter.resolve_fighter(illegal, [], "illegal").ok, "shared_grip_rules_reject_two_hander_with_marrow_arm")
	check(not adapter.resolve_fighter(adapter.builds.player, ["armor.lab_mail_shirt", "armor.lab_bog_iron_plate"], "x").ok, "armor_slot_rules_reject_two_torso_items")
	var bad = Adapter.load_default("res://data/builds/catalog.json", "res://data/builds/courtyard.json")
	check(not bad.ok, "invalid_integration_data_fails_closed", bad.errors.slice(0, 1))

func signature_state_checks() -> void:
	var adapter = Adapter.load_default()
	var tuning: Dictionary = adapter.tuning
	var variant: Dictionary = adapter.data.encounters.exterior[1]
	var resolved: Dictionary = adapter.resolve_fighter(adapter.enemy_build(variant, "t.sig"), variant.armor, "sig")
	var h := Handling.derive(resolved.weapon, tuning)
	var r := CombatResources.derive(h, str(resolved.weapon.item), variant.armor, adapter.combat, tuning)
	var s: ExpState = ExpState.new(tuning, h, resolved.stats, r, resolved.signature)
	var sword_length: float = s.h.length
	check(s.has_signature() and s.legal_actions().signature and is_equal_approx(s.signature_cost, r.attack_cost * 1.5), "lunge_is_legal_with_scaled_cost", s.signature_cost)
	check(s.press_signature() and s.stamina.ledger.size() == 1 and s.stamina.ledger[0].action == "signature", "lunge_charged_once_on_press", s.stamina.ledger)
	check(not s.press_attack("overhead") and s.direction == Geometry.THRUST, "lunge_cannot_be_overlapped_by_a_cut")
	s.aim_attack("overhead")
	check(s.direction == Geometry.THRUST, "lunge_cannot_be_redirected")
	s.release_attack()
	var swing_at := -1.0
	var max_reach := 0.0
	var clock := 0.0
	for i in 240:
		s.tick(DT)
		clock += DT
		if s.phase == State.Phase.SWING and swing_at < 0.0:
			swing_at = clock
		max_reach = maxf(max_reach, -Geometry.tip({"hand": s.hand, "dir": s.dir}, s.h.length).z)
		if s.phase == State.Phase.IDLE and swing_at > 0.0:
			break
	check(swing_at >= float(resolved.signature.windup) - DT, "lunge_respects_shared_windup_floor", swing_at)
	check(absf(max_reach - float(resolved.signature.reach)) < 0.05, "lunge_tip_reaches_shared_ability_reach", max_reach)
	check(not s.signature_active and is_equal_approx(s.h.length, sword_length) and s.t == s.base_t, "lunge_restores_sword_handling_after_recovery")
	check(s.stamina.ledger.size() == 1, "lunge_release_and_recovery_never_charge", s.stamina.ledger.size())
	# Cancel by a fresh guard press during the unreleased windup: refund, then sword again.
	s.reset()
	s.press_signature()
	s.tick(DT)
	s.set_guard(true, "high")
	check(not s.signature_active and s.guarding and is_equal_approx(s.h.length, sword_length), "guard_cancels_lunge_and_restores_handling")
	check(s.stamina.ledger.size() == 2 and s.stamina.ledger[1].action == "refund" and is_equal_approx(s.stamina.ledger[1].refund, s.signature_cost * tuning.feint_refund),
		"cancelled_lunge_refunds_like_a_feint", s.stamina.ledger)
	var none := ExpState.new(tuning, h, resolved.stats, r, {})
	check(not none.has_signature() and not none.press_signature() and none.stamina.ledger.is_empty(), "no_lunge_without_the_ability")

# --- 2. Composition: one combat model in the scene --------------------------------

func composition_checks() -> void:
	await start()
	check(e.ok and e.sites.size() >= 2, "directional_expedition_starts", e.sites.size())
	var offenders: Array[String] = []
	var stack: Array[Node] = [shell]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script()
		if script != null and script.resource_path.begins_with("res://scripts/") and (script.resource_path.contains("/characters/") or script.resource_path.contains("/ai/") or script.resource_path.ends_with("courtyard.gd")):
			offenders.append(script.resource_path)
		stack.append_array(node.get_children())
	check(offenders.is_empty(), "no_legacy_fighter_ai_or_courtyard_nodes_in_scene", offenders)
	var fighters: Array = [e.player] + e.sites.map(func(site: Dictionary) -> Node: return site.enemy)
	check(fighters.all(func(f: Node) -> bool: return f.state.get_script() == ExpState), "every_fighter_uses_the_directional_rules_state")
	check(e.progression.get_script().resource_path.ends_with("directional_progression.gd"), "session_uses_directional_progression")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "default_launch_scene_unchanged")
	check(not e.in_duel() and e.opponent == null, "exploration_starts_without_an_engaged_soul")
	var referencing: Array[String] = []
	for dir_path: String in ["res://scripts", "res://scenes"]:
		referencing.append_array(_files_mentioning(dir_path, "directional_expedition"))
	check(referencing.is_empty(), "no_other_scene_or_script_references_the_integration", referencing)

## Game files outside the integration (its own folder and scene) that mention `needle`.
func _files_mentioning(path: String, needle: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(path):
		var full := path.path_join(file)
		if full.get_file().begins_with(needle) or not (file.ends_with(".gd") or file.ends_with(".tscn")):
			continue
		if FileAccess.get_file_as_string(full).contains(needle):
			found.append(full)
	for sub: String in DirAccess.get_directories_at(path):
		# QA scripts may name the integration (the lab's isolation allowlist does).
		if sub != needle and path.path_join(sub) != "res://scripts/qa":
			found.append_array(_files_mentioning(path.path_join(sub), needle))
	return found

# --- 3. Directional geometry decides contact, damage and posture -------------------

func geometry_checks() -> void:
	await start()
	# Sword against sword, as the lab's alignment matrix was measured (fixture variant).
	e.sites[0].variant = e.adapter.exterior_variant(1)
	var soul: Node = await engage(0, "dummy", "")
	check(e.in_duel() and e.opponent == soul and e.player.locked, "approach_engages_vigil_soul")
	var cases := [
		[Vector2(1, 0), "left", "right_to_left", Solver.BLOCK],
		[Vector2(1, 0), "right", "right_to_left", Solver.HIT],
		[Vector2(-1, 0), "right", "left_to_right", Solver.BLOCK],
		[Vector2(-1, 0), "left", "left_to_right", Solver.HIT],
		[Vector2(0, 1), "high", "overhead", Solver.BLOCK],
		[Vector2(0, -1), "high", "thrust", Solver.HIT],
	]
	for case: Array in cases:
		await tap("lab_reset")
		await frames(2)
		soul.dummy_guard = case[1]
		await place(soul)
		await frames(20)
		var health_before: float = soul.state.health
		var report := await cut(case[0])
		var label := "cut_%s_vs_guard_%s_is_%s" % [case[2], case[1], case[3]]
		check(not report.is_empty() and report.direction == case[2] and report.result == case[3], label, {"result": report.get("result", "none"), "point": report.get("point"), "guard": report.get("guard")})
		if report.get("result") == Solver.HIT:
			# Damage is the solver's momentum model, reduced by the soul's armor mitigation.
			var a: State = e.player.state
			var omega: float = report.momentum / a.h.inertia
			var impact: float = sqrt(0.5 * a.h.inertia * omega * omega / a.t.energy_ref) if case[2] != "thrust" else report.momentum / a.t.thrust_momentum_ref
			var expected: float = (a.t.thrust_damage if case[2] == "thrust" else a.t.swing_damage) * impact * (1.0 - soul.state.resources.mitigation)
			check(absf(report.damage - expected) < 0.01 and absf(soul.state.health - (health_before - report.damage)) < 0.01,
				"hit_damage_is_momentum_times_armor_" + case[2], {"damage": report.damage, "expected": expected})
	# Known lab geometry issue (reported, not changed here): the thrust line passes
	# blade + guard radius (0.08 m) beside the centre guard's blade, so that pairing sits
	# exactly on the contact threshold and float rounding decides block vs hit.
	await tap("lab_reset")
	soul.dummy_guard = "center"
	await place(soul)
	await frames(20)
	var thrust := await cut(Vector2(0, -1))
	var lateral: float = absf((thrust.get("point", Vector3.INF) as Vector3).x - soul.global_position.x)
	var threshold: float = e.tuning.blade_radius + e.tuning.guard_radius
	check(thrust.get("direction") == "thrust" and absf(lateral - threshold) < 0.001, "thrust_vs_centre_guard_is_threshold_geometry_known_issue",
		{"result": thrust.get("result"), "lateral": lateral, "threshold": threshold})
	# Lab matrix: the neighbouring 45° guard still blocks a horizontal cut.
	await tap("lab_reset")
	soul.dummy_guard = "high_left"
	await place(soul)
	await frames(20)
	var bypass := await cut(Vector2(1, 0))
	check(bypass.get("result") == Solver.BLOCK, "adjacent_45_degree_guard_also_blocks_as_in_lab_matrix", bypass.get("result"))
	# Out of reach: a full swing at 4 m produces no contact at all.
	await tap("lab_reset")
	soul.dummy_guard = ""
	await place(soul, 4.0)
	await frames(10)
	var miss := await cut(Vector2(1, 0))
	check(miss.is_empty() and soul.state.health == soul.state.max_health, "out_of_reach_swing_never_connects")
	await stop()

# --- 4. Stamina: charged once, by the rules state, for real inputs ------------------

func stamina_checks() -> void:
	await start()
	var p: Node = e.player
	var s: State = p.state
	var r: Dictionary = s.resources
	await tap("lab_attack")
	await frames(1)
	check(s.stamina.ledger.size() == 1 and s.stamina.ledger[0].action == "attack" and is_equal_approx(s.stamina.ledger[0].cost, r.attack_cost),
		"lmb_press_charges_attack_once", s.stamina.ledger)
	await wait_idle(p)
	check(s.stamina.ledger.size() == 1, "release_swing_and_recovery_charge_nothing", s.stamina.ledger.size())
	# Indefinitely held chamber: no drain while held, one charge in total.
	await frames(60)
	var ledger_size: int = s.stamina.ledger.size()
	key("lab_attack", true)
	await frames(1)
	motion(Vector2(0, -70))
	await frames(150)
	check(s.phase == State.Phase.WINDUP and not s.released and s.direction == "overhead" and s.stamina.ledger.size() == ledger_size + 1,
		"held_chamber_waits_indefinitely_with_one_charge", {"phase": State.Phase.keys()[s.phase], "held_seconds": s.hold_time})
	# Re-chambering to the opposite side goes through the forward neutral pose.
	motion(Vector2(0, 140))
	await frames(1)
	var neutral := false
	for i in 60:
		await physics_frame
		neutral = neutral or s.dir.angle_to(Geometry.rest_pose(s.t).dir) < 0.05
	check(neutral and s.direction == "thrust" and s.phase == State.Phase.WINDUP, "redirect_rechambers_through_forward_neutral", s.direction)
	# Feint: a fresh guard press on an unreleased windup refunds half.
	key("lab_guard", true)
	await frames(2)
	var last: Dictionary = s.stamina.ledger[-1]
	check(last.action == "refund" and is_equal_approx(last.refund, r.attack_cost * s.t.feint_refund) and s.phase == State.Phase.IDLE,
		"feint_by_guard_press_refunds_half", last)
	key("lab_guard", false)
	key("lab_attack", false)
	await frames(90)
	for kind: Array in [["lab_dodge", "dodge", r.dodge_cost], ["lab_roll", "roll", r.roll_cost]]:
		ledger_size = s.stamina.ledger.size()
		await tap(kind[0])
		await frames(60)
		var added: Array = s.stamina.ledger.slice(ledger_size)
		check(added.size() == 1 and added[0].action == kind[1] and is_equal_approx(added[0].cost, kind[2]), "%s_key_charges_once" % kind[1], added)
	# Exhaustion: repeated rolls are refused once unaffordable; never negative or partial.
	var minimum := 999.0
	var refusals_before: int = s.stamina.refusals
	for i in 8:
		await tap("lab_roll")
		for j in 50:
			await physics_frame
			minimum = minf(minimum, s.stamina.current)
	check(s.stamina.refusals > refusals_before and minimum >= 0.0, "unaffordable_roll_is_refused_not_overdrawn", {"refusals": s.stamina.refusals - refusals_before, "min": minimum})
	var charges_ok := true
	for entry: Dictionary in s.stamina.ledger:
		charges_ok = charges_ok and (entry.action == "refund" or entry.cost <= s.stamina.max_stamina)
	check(charges_ok, "ledger_contains_only_real_charges")
	# Q before salvage does nothing; the lunge exists only through the build.
	ledger_size = s.stamina.ledger.size()
	await frames(120)
	await tap("signature")
	await frames(5)
	check(s.stamina.ledger.size() == ledger_size and not s.signature_active, "q_without_marrow_arm_does_nothing")
	await stop()

# --- 5. Status: the same pipeline for both sides -----------------------------------

func status_checks() -> void:
	await start()
	var adapter = e.adapter
	var venom: Dictionary = adapter.data.encounters.exterior[0]
	var iron: Dictionary = adapter.data.encounters.guardian
	var soul: Node = await engage(0, "dummy", "")
	# Fixture: hand the pilgrim each status-bearing build in turn (a legal shared build).
	# Each striker at a spacing inside its own reach (knife 1.45 m, greatsword 2.65 m).
	for case: Array in [[venom, "poison", 35.0, 1.2], [iron, "slow", 55.0, 2.0]]:
		var build: Dictionary = adapter.enemy_build(case[0], "fixture.player")
		await tap("lab_reset")
		e.player.equip(e.tuning, adapter.resolve_fighter(build, case[0].armor, case[0].label))
		soul.dummy_guard = "left"
		await place(soul, case[3])
		await frames(20)
		var blocked := await cut(Vector2(1, 0), 30)
		# A greatsword overwhelms a knife's guard (guard break); neither outcome routes status.
		check(blocked.get("result") in [Solver.BLOCK, Solver.GUARD_BREAK] and blocked.get("status", {"x": 1}).is_empty() and soul.state.status.buildup[case[1]] == 0.0,
			"guarded_%s_attack_applies_no_status" % case[1], {"result": blocked.get("result"), "status": blocked.get("status")})
		await wait_idle(e.player)
		soul.dummy_guard = ""
		await place(soul, case[3])
		await frames(30)
		var hit := await cut(Vector2(1, 0), 30)
		var resist: float = soul.state.status.resistance(case[1])
		var expected: float = case[2] * (1.0 - resist)
		check(hit.get("result") == Solver.HIT and absf(float(hit.status.get(case[1], 0.0)) - expected) < 0.001,
			"hit_applies_%s_buildup_after_soul_resistance" % case[1], {"applied": hit.get("status"), "expected": expected, "resistance": resist})
	# Poison activates and ticks on a soul, through the same status clock as the player.
	var build: Dictionary = adapter.enemy_build(venom, "fixture.player")
	await tap("lab_reset")
	e.player.equip(e.tuning, adapter.resolve_fighter(build, venom.armor, venom.label))
	soul.dummy_guard = ""
	for i in 4:
		await place(soul, 1.2)
		await frames(5)
		await cut(Vector2(1, 0) if i % 2 == 0 else Vector2(-1, 0), 12)
		await wait_idle(e.player)
		if soul.state.status.is_active("poison"):
			break
	var poisoned: bool = soul.state.status.is_active("poison")
	var damage_before: float = soul.state.status_damage_taken
	await frames(150)
	var activations: Array = e.status_events.filter(func(ev: Dictionary) -> bool: return ev.effect == "poison" and ev.event == "activated" and ev.fighter == soul.name)
	check(poisoned and not activations.is_empty() and soul.state.status_damage_taken > damage_before, "venom_hits_poison_soul_and_poison_ticks",
		{"activations": activations.size(), "tick_damage": soul.state.status_damage_taken - damage_before})
	check(soul.state.health >= 1.0, "poison_cannot_release_a_soul_by_itself", soul.state.health)
	# A soul's resistance comes only from its armor: plate resists more than mail.
	var plate: Dictionary = CombatResources.derive({"inertia": 1.0}, "", ["armor.lab_bog_iron_plate"], adapter.combat, e.tuning)
	var mail: Dictionary = CombatResources.derive({"inertia": 1.0}, "", ["armor.lab_mail_shirt"], adapter.combat, e.tuning)
	check(plate.resistances.poison > mail.resistances.poison and plate.move_scale < mail.move_scale, "armor_trades_resistance_for_mobility", {"plate": plate.resistances, "mail": mail.resistances})
	await stop()

# --- 6. AI: fair perception, same legality -----------------------------------------

func ai_checks() -> void:
	await start()
	var soul: Node = await engage(0, "defend", "")
	var reaction: float = Loadout.load_tuning().values.ai_reaction_delay
	await place(soul)
	await frames(40)
	var trace_before: int = soul.trace.size()
	var pressed_at: float = soul.clock
	key("lab_attack", true)
	await physics_frame
	var read_at := -1.0
	for i in 60:
		await physics_frame
		for j in range(trace_before, soul.trace.size()):
			if soul.trace[j].event == "read_swing" and read_at < 0.0:
				read_at = soul.trace[j].t
		if read_at >= 0.0:
			break
	key("lab_attack", false)
	check(read_at >= 0.0 and read_at - pressed_at >= reaction - DT - 0.001, "soul_sees_windup_only_after_reaction_delay", {"after": read_at - pressed_at, "delay": reaction})
	await frames(90)
	# Full duel AI against a passive pilgrim: every soul charge is a legal, derived cost.
	soul.mode = "duel"
	e.player.input_enabled = false
	var minimum := 999.0
	for i in 60 * 12:
		await physics_frame
		minimum = minf(minimum, soul.state.stamina.current)
		if e.progression.stage != e.Progression.Stage.DUEL:
			break
	var s: State = soul.state
	var wrong := 0
	var attacks := 0
	for entry: Dictionary in s.stamina.ledger:
		if entry.action == "attack":
			attacks += 1
			wrong += int(not is_equal_approx(entry.cost, s.resources.attack_cost))
		elif entry.action == "signature":
			wrong += int(not is_equal_approx(entry.cost, s.signature_cost))
	check(attacks >= 3 and wrong == 0 and minimum >= 0.0, "soul_pays_its_own_derived_costs", {"attacks": attacks, "wrong": wrong, "min": minimum})
	check(s.stamina.refusals <= 1, "soul_checks_legality_instead_of_spamming_refusals", s.stamina.refusals)
	var hits: Array = e.events.filter(func(c: Dictionary) -> bool: return c.attacker == soul.name and c.result == Solver.HIT)
	check(not hits.is_empty() and e.player.state.health < e.player.state.max_health, "soul_damages_through_the_same_contact_solver", hits.size())
	var source := FileAccess.get_file_as_string("res://scripts/directional_expedition/expedition_opponent.gd")
	check(not source.contains("opponent.state") and not source.contains("Input."), "soul_controller_reads_no_player_state_or_input")
	e.player.input_enabled = true
	await stop()

# --- 7. Encounters: activation, leash, guardian gates, dormancy ----------------------

func encounter_checks() -> void:
	await start()
	var guardian: Node = e.sites[-1].enemy
	var soul: Node = await engage(0, "dummy", "")
	await place(soul)
	await frames(10)
	await cut(Vector2(1, 0))
	await wait_idle(e.player)
	var damaged: float = soul.state.health
	check(damaged < soul.state.max_health, "fixture_damaged_vigil_soul", damaged)
	check(guardian.state.clock == 0.0, "dormant_souls_are_never_stepped", guardian.state.clock)
	e.player.teleport(soul.post + Vector3(0, 0.05, 18.5), 0.0)
	await frames(3)
	check(not e.in_duel() and e.opponent == null and soul.global_position.distance_to(soul.post) < 0.2, "leaving_the_vigil_disengages_the_soul")
	e.player.teleport(soul.post + Vector3(0, 0.05, 3.0), 0.0)
	await frames(3)
	check(e.in_duel() and soul.state.health == damaged, "re_engaging_does_not_heal_the_soul", soul.state.health)
	# Fixture: walk away and step into the dungeon by teleport, then approach the guardian.
	e.player.teleport(soul.post + Vector3(0, 0.05, 18.5), 0.0)
	await frames(3)
	var site: Dictionary = e.sites[-1]
	e._enter("dungeon", e.builder.dungeon_point(e.plan.dungeon.spawn), 0.0)
	await frames(2)
	check(e.builder.gate_closed("gate.guardian_exit") and not e.builder.gate_closed("gate.guardian_entry"), "guardian_vault_sealed_entry_open")
	e.player.teleport(site.position + Vector3(0, 0.05, 3.0), 0.0)
	await frames(3)
	check(e.in_duel() and e.opponent == guardian and e.builder.gate_closed("gate.guardian_entry") and e.builder.gate_closed("gate.guardian_exit"),
		"guardian_engagement_seals_both_doors")
	check(guardian.loadout_label.begins_with("Iron guardian") and guardian.state.resources.armor_mass == 20.0, "guardian_uses_heavy_plate_build", guardian.loadout_label)
	check(guardian.current_move_speed() < 2.7 * 0.8, "plate_slows_the_guardian", guardian.current_move_speed())
	await stop()

# --- 8. Progression: rewards only from a resolved lethal contact -----------------------

func progression_checks() -> void:
	await start()
	var soul: Node = await engage(0, "dummy", "")
	var p: State = e.player.state
	check(not e.progression.record_contact(Solver.BLOCK, p, soul.state), "block_cannot_win")
	check(not e.progression.record_contact(Solver.HIT, p, soul.state), "hit_on_living_soul_cannot_win")
	check(not e.progression.acquire().ok and not e.progression.equip().ok, "salvage_and_equip_require_victory")
	# A debug write of death is not a contact: no reward reaches the progression.
	soul.state.health = 0.0
	soul.state.phase = State.Phase.DEAD
	await frames(10)
	check(e.progression.stage == e.Progression.Stage.DUEL and e.progression.available_rewards().is_empty(), "state_write_death_grants_nothing")
	await tap("lab_reset")
	soul.dummy_guard = ""
	# Real lethal contacts: cut until released.
	for i in 12:
		await place(soul)
		await frames(5)
		await cut(Vector2(1, 0) if i % 2 == 0 else Vector2(-1, 0), 10)
		await wait_idle(e.player)
		if e.sites[0].cleared:
			break
	check(e.sites[0].cleared and e.progression.stage == e.Progression.Stage.VICTORY, "lethal_contact_releases_soul")
	check(e.progression.available_rewards().size() == 1 and e.progression.available_rewards()[0].item == "item.marrow_arm", "victory_offers_marrow_arm_reference")
	await tap("salvage")
	await tap("equip")
	await frames(2)
	check(e.progression.equipped() and e.player.state.has_signature() and e.player.marrow_arm, "f_then_e_equips_arm_and_grants_lunge")
	check(e.progression.builds.player.equipped.get("arm_l") == "item.marrow_arm" and e.adapter.rules.validate(e.progression.builds.player).is_empty(),
		"equipped_build_remains_a_valid_shared_build", e.progression.builds.player.equipped)
	# The lunge through Q (held, released) is one charge and one thrust.
	await frames(120)
	var ledger_size: int = e.player.state.stamina.ledger.size()
	key("signature", true)
	await frames(10)
	check(e.player.state.signature_active and e.player.state.direction == Geometry.THRUST and e.player.state.phase == State.Phase.WINDUP, "q_holds_marrow_lunge_chamber")
	key("signature", false)
	await wait_idle(e.player, 240)
	var added: Array = e.player.state.stamina.ledger.slice(ledger_size)
	check(added.size() == 1 and added[0].action == "signature", "q_lunge_charged_once", added)
	check(not e.player.state.signature_active and e.player.state.h.item == "item.notched_sword", "sword_returns_after_lunge")
	await stop()

# --- 9. Determinism ---------------------------------------------------------------

func determinism_checks() -> void:
	for address: Array in [[WORDS, SEED], [["smoldering", "pallid", "necropolis"], 7], [["frozen", "gilded", "citadel"], 1002]]:
		var a := Plan.generate(address[0], address[1])
		var b := Plan.generate(address[0], address[1])
		check(a.ok and a.plan.fingerprint == b.plan.fingerprint, "plan_replays_%s_%d" % [address[0][0], address[1]], a.plan.fingerprint)
	check(Plan.generate(WORDS, SEED).plan.fingerprint != Plan.generate(WORDS, SEED + 1).plan.fingerprint, "different_seed_different_plan")
	var logs: Array = []
	for run_index in 2:
		await start()
		var soul: Node = await engage(0, "duel", "")
		for i in 6:
			await cut(Vector2(1, 0) if i % 2 == 0 else Vector2(0, 1), 8)
			await frames(25)
		logs.append(e.events.map(func(c: Dictionary) -> String: return JSON.stringify(e._printable(c))))
		logs[-1].append(JSON.stringify(soul.trace))
		await stop()
	check(logs[0] == logs[1] and logs[0].size() > 3, "same_address_seed_and_inputs_replay_identical_duel", logs[0].size())

# --- 10. Original scenes still boot and run ------------------------------------------

func original_scene_checks() -> void:
	for path: String in ["res://scenes/first_expedition.tscn", "res://scenes/expedition_preview.tscn", "res://scenes/melee_lab.tscn"]:
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await frames(5)
		var started := true
		if scene.has_method("start_expedition"):
			started = scene.start_expedition(WORDS, SEED)
		await frames(60)
		check(started and is_instance_valid(scene), "original_scene_runs_" + path.get_file().get_basename())
		scene.queue_free()
		get_root().get_tree().paused = false
		await process_frame
