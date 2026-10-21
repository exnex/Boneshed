extends SceneTree
## Deterministic checks for the lab's experimental combat resources: stamina costs by
## build, affordability at the exact boundary, single charging, recovery, feint refunds,
## light versus heavy attack economy, armor mobility, the poison/slow status pipeline,
## contact routing (miss/dodge/block/deflect/guard break/bad angle/clash), world
## conditions, and identical legality for player and AI. Rules are driven directly;
## scene checks step the real lab scene. These prove reachable behaviour and invariants,
## not that the combat feels good.
## --negative=free-feints sets feint_refund to 1 (feint spam must be caught);
## --negative=block-applies-status routes on-hit status through blocks (must be caught).
## Run: bash scripts/tooling/test_melee_lab.sh [new-empty-dir]

const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const Status = preload("res://scripts/melee_lab/status_effects.gd")
const DT := 1.0 / 60.0
const PROFILES := ["evasive", "balanced", "resistant"]
const VENOM := [{"effect": "poison", "route": "on_hit", "buildup": 35.0}]
var tuning: Dictionary
var lab: Dictionary
var negative := ""
var output := "res://artifacts/melee-lab-resources"
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

func run() -> void:
	var loaded := Loadout.load_tuning()
	tuning = loaded.values
	lab = Loadout.load_lab()
	check(loaded.ok and lab.ok and not lab.combat.is_empty(), "combat_resources_load_through_lab_adapter", loaded.errors + lab.errors)
	if not (loaded.ok and lab.ok):
		return finish()
	if negative == "free-feints":
		tuning.feint_refund = 1.0
	if negative == "block-applies-status":
		lab.combat.routing.block = 1.0
	data_checks()
	cost_checks()
	affordability_checks()
	single_charge_checks()
	recovery_checks()
	feint_checks()
	economy_checks()
	status_checks()
	routing_checks()
	legality_checks()
	await scene_checks()
	await ai_checks()
	finish()

func finish() -> void:
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true) + "\n")
	print(JSON.stringify({"suite": "melee_lab_resources", "summary": true, "passed": passed, "failed": failed, "negative": negative, "engine": Engine.get_version_info().string}))
	quit(0 if failed == 0 else 1)

# --- Harness -------------------------------------------------------------------

func tuned(overrides := {}) -> Dictionary:
	var values := tuning.duplicate()
	values.merge(overrides, true)
	return values

## A fighter built exactly as the arena builds one: shared build rules → handling →
## combat resources from the equipped weapon and armor.
func build(id: String, t := tuning, role := "player") -> State:
	var resolved := Loadout.resolve(lab, role, id)
	var hd := Handling.derive(resolved.weapon, t)
	return State.new(t, hd, resolved.stats, CombatResources.derive(hd, resolved.weapon.item, resolved.armor, lab.combat, t))

## A sword fighter (known contact geometry at 2 m) carrying `sources` on its blade, and
## the lab routing table: a fixture for routing checks independent of the knife's reach.
func carrier(sources: Array, t := tuning) -> State:
	var resolved := Loadout.resolve(lab, "player", "sword")
	var hd := Handling.derive(resolved.weapon, t)
	var res := CombatResources.derive(hd, resolved.weapon.item, [], lab.combat, t)
	res.status_sources = sources.duplicate(true)
	return State.new(t, hd, resolved.stats, res)

## An unarmored defender with the lab status definitions and no resistance.
func target(t := tuning) -> State:
	var resolved := Loadout.resolve(lab, "player", "sword")
	var hd := Handling.derive(resolved.weapon, t)
	return State.new(t, hd, resolved.stats, CombatResources.derive(hd, resolved.weapon.item, [], lab.combat, t))

func frames(distance: float) -> Array[Transform3D]:
	return [Transform3D(Basis(), Vector3(0.0, 0.0, distance)), Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)]

func settle_guard(d: State, sector: String, ticks := 40) -> void:
	d.set_guard(true, sector)
	for i in range(ticks):
		d.tick(DT)
	d.guard_age = 99.0

func exchange(a: State, d: State, direction: String, distance := 2.0, limit := 150, each := Callable(), dt := DT) -> Dictionary:
	var xf := frames(distance)
	a.press_attack(direction)
	a.release_attack()
	for tick in range(limit):
		if each.is_valid():
			each.call(tick)
		a.tick(dt)
		d.tick(dt)
		var report := Solver.resolve(a, xf[0], xf[0], d, xf[1], xf[1])
		if report.result != Solver.NONE:
			report.tick = tick
			return report
	return {"result": Solver.NONE, "tick": -1, "status": {}}

func run_until_idle(s: State, limit := 600) -> void:
	for i in range(limit):
		if s.phase == State.Phase.IDLE:
			return
		s.tick(DT)

func charges(s: State, action := "") -> Array:
	return s.stamina.ledger.filter(func(e: Dictionary) -> bool: return e.action != "refund" and (action == "" or e.action == action))

func r2(value: float) -> float:
	return snappedf(value, 0.01)

# --- Data ----------------------------------------------------------------------

func data_checks() -> void:
	var base: Dictionary = Loadout.read_json(CombatResources.PATH)
	var cases := {
		"full_resistance_is_immunity": func(d: Dictionary) -> void: d.armor[2].resistances.poison = 1.0,
		"evaded_routing_must_be_zero": func(d: Dictionary) -> void: d.routing.evaded = 0.5,
		"hard_control_kind_unsupported": func(d: Dictionary) -> void: d.effects.stun = {"kind": "hard_control", "threshold": 100.0, "decay_per_second": 1.0, "duration": 1.0, "immunity_after": 0.0, "while_active": "ignore"},
		"impairment_cannot_reach_zero": func(d: Dictionary) -> void: d.effects.slow.move_scale = 0.0,
		"trait_for_unknown_item": func(d: Dictionary) -> void: d.traits["item.does_not_exist"] = {"status_sources": []},
		"source_for_unknown_effect": func(d: Dictionary) -> void: d.traits["item.lab_venom_knife"].status_sources[0].effect = "burn",
		"negative_armor_mass": func(d: Dictionary) -> void: d.armor[0].mass = -1.0,
	}
	var catalog: Variant = Loadout.read_json("res://data/builds/catalog.json")
	var weapons: Variant = Loadout.read_json(Loadout.WEAPONS_PATH)
	var rejected := {}
	for label: String in cases:
		var bad: Dictionary = base.duplicate(true)
		cases[label].call(bad)
		var outcome := Loadout.lab_from_data(catalog, weapons, bad)
		rejected[label] = not outcome.ok
	check(rejected.values().all(func(v: bool) -> bool: return v), "invalid_combat_resource_data_rejected", rejected)
	var two_torsos: Dictionary = weapons.duplicate(true)
	two_torsos.loadouts[0].armor = ["armor.lab_mail_shirt", "armor.lab_bog_iron_plate"]
	var unknown: Dictionary = weapons.duplicate(true)
	unknown.loadouts[0].armor = ["armor.lab_missing"]
	var slot_result := Loadout.lab_from_data(catalog, two_torsos, base)
	var unknown_result := Loadout.lab_from_data(catalog, unknown, base)
	check(not slot_result.ok and str(slot_result.errors).contains("occupied") and not unknown_result.ok, "armor_slot_conflict_and_unknown_armor_rejected", [slot_result.errors, unknown_result.errors])
	var shared := FileAccess.get_file_as_string("res://data/builds/catalog.json")
	check(not shared.contains("armor.") and not shared.contains("status_sources") and not shared.contains("stamina"), "shared_catalog_file_unchanged_by_resource_data")

# --- Costs by build --------------------------------------------------------------

func cost_checks() -> void:
	var table := {}
	for id: String in ["knife", "sword", "greatsword", "staff"] + PROFILES:
		var s := build(id)
		var r := s.resources
		table[id] = {"attack": r2(r.attack_cost), "dodge": r2(r.dodge_cost), "roll": r2(r.roll_cost), "regen": r2(r.stamina_regen),
			"armor_kg": r.armor_mass, "move_scale": r2(r.move_scale), "evasion_speed_scale": r2(r.evasion_speed_scale),
			"mitigation": r2(r.mitigation), "resist_poison": r2(r.resistances.get("poison", 0.0)), "resist_slow": r2(r.resistances.get("slow", 0.0)),
			"inertia": r2(s.h.inertia), "sources": r.status_sources.map(func(src: Dictionary) -> String: return src.effect)}
	results.build_costs = table
	check(table.knife.attack < table.sword.attack and table.sword.attack < table.greatsword.attack,
		"attack_cost_grows_with_weapon_inertia", {"knife": table.knife.attack, "sword": table.sword.attack, "greatsword": table.greatsword.attack})
	check(table.evasive.attack < table.balanced.attack and table.balanced.attack < table.resistant.attack, "profile_attack_cost_orders_light_balanced_heavy")
	var evasions_ordered: bool = table.evasive.dodge < table.balanced.dodge and table.balanced.dodge < table.resistant.dodge and table.evasive.roll < table.balanced.roll and table.balanced.roll < table.resistant.roll
	check(evasions_ordered, "armor_weight_raises_dodge_and_roll_cost", {"dodge": [table.evasive.dodge, table.balanced.dodge, table.resistant.dodge], "roll": [table.evasive.roll, table.balanced.roll, table.resistant.roll]})
	check(PROFILES.all(func(id: String) -> bool: return table[id].roll > table[id].dodge), "roll_costs_more_than_dodge_for_every_build")
	check(table.evasive.move_scale > table.balanced.move_scale and table.balanced.move_scale > table.resistant.move_scale and table.sword.move_scale == 1.0,
		"armor_weight_lowers_movement_and_unarmored_is_unchanged", {"evasive": table.evasive.move_scale, "balanced": table.balanced.move_scale, "resistant": table.resistant.move_scale, "unarmored": table.sword.move_scale})
	check(table.evasive.regen > table.resistant.regen and table.resistant.mitigation > table.evasive.mitigation and table.resistant.resist_poison > table.evasive.resist_poison,
		"heavy_armor_trades_recovery_for_protection_and_resistance")
	# Same weapon, different armor: the cost difference comes from the equipped armor only.
	var plain := build("sword")
	var mail := build("balanced")
	check(is_equal_approx(mail.resources.attack_cost - plain.resources.attack_cost, tuning.attack_cost_per_armor_kg * 9.0) and is_equal_approx(plain.h.inertia, mail.h.inertia),
		"armor_cost_difference_is_explained_by_armor_mass")
	var opponent_view := build("resistant", tuning, "opponent")
	check(is_equal_approx(opponent_view.resources.attack_cost, build("resistant").resources.attack_cost) and is_equal_approx(opponent_view.resources.roll_cost, build("resistant").resources.roll_cost),
		"player_and_opponent_roles_derive_identical_costs_from_equipment")

# --- Affordability ---------------------------------------------------------------

func affordability_checks() -> void:
	var matrix := {}
	for action: String in ["attack", "dodge", "roll"]:
		matrix[action] = {}
		for level: String in ["full", "exact", "just_below", "low"]:
			var s := build("balanced")
			var cost: float = s.resources[action + "_cost"]
			s.stamina.current = {"full": s.stamina.max_stamina, "exact": cost, "just_below": cost - 0.001, "low": cost * 0.25}[level]
			var before := s.stamina.current
			var started := false
			match action:
				"attack":
					started = s.press_attack("overhead")
				"dodge":
					started = s.dodge()
				"roll":
					started = s.roll()
			var refused_ok: bool = not started and s.stamina.refusals == 1 and s.stamina.last_refusal.action == action and is_equal_approx(s.stamina.current, before) and s.phase == State.Phase.IDLE
			var spent_ok: bool = started and is_equal_approx(s.stamina.current, before - cost) and s.stamina.refusals == 0
			matrix[action][level] = "started" if started else "refused"
			if level in ["full", "exact"] and not spent_ok:
				matrix[action][level] += " (WRONG)"
			if level in ["just_below", "low"] and not refused_ok:
				matrix[action][level] += " (WRONG)"
	results.affordability = matrix
	var correct := true
	for action: String in matrix:
		correct = correct and matrix[action].full == "started" and matrix[action].exact == "started" and matrix[action].just_below == "refused" and matrix[action].low == "refused"
	check(correct, "affordability_boundary_full_exact_below_low", matrix)
	var s := build("resistant")
	s.stamina.current = s.resources.attack_cost - 1.0
	for i in range(5):
		s.press_attack("overhead")
	check(s.stamina.refusals == 5 and charges(s).is_empty() and s.phase == State.Phase.IDLE, "repeated_unaffordable_presses_are_each_refused_without_charge", s.stamina.refusals)
	check(not s.legal_actions().attack and s.legal_actions().guard, "legal_actions_report_unaffordable_attack_but_free_guard")
	# Exhausted fighters keep the free defensive options: guard and deflect still work.
	var a := carrier([])
	var d := build("balanced")
	d.stamina.current = 0.0
	settle_guard(d, "left")
	var block := exchange(a, d, "right_to_left")
	a = carrier([])
	d = build("balanced")
	d.stamina.current = 0.0
	settle_guard(d, "left")
	var at: int = block.tick - 4
	var deflect := exchange(a, d, "right_to_left", 2.0, 150, func(tick: int) -> void:
		if tick == at - 1:
			d.set_guard(false)
		elif tick == at:
			d.set_guard(true, "left"))
	check(block.result == Solver.BLOCK and deflect.result == Solver.DEFLECT, "zero_stamina_fighter_can_still_block_and_deflect", [block.result, deflect.result])

# --- Single charging -------------------------------------------------------------

func single_charge_checks() -> void:
	var s := build("balanced")
	s.press_attack("overhead")
	s.press_attack("overhead")
	s.aim_attack("left_to_right")
	s.release_attack()
	s.release_attack()
	for i in range(30):
		s.tick(DT)
		s.release_attack()
	check(charges(s, "attack").size() == 1 and s.swing_serial <= 1, "press_release_and_redirect_events_charge_one_attack", s.stamina.ledger)
	run_until_idle(s)
	var after_swing := charges(s).size()
	for i in range(5):
		s.release_attack()
		s.tick(DT)
	check(charges(s).size() == after_swing, "stray_release_events_never_charge")
	# Buffered presses during recovery: one charge, when the buffer becomes a windup.
	s = build("balanced")
	s.press_attack("overhead")
	s.release_attack()
	while s.phase != State.Phase.RECOVERY:
		s.tick(DT)
	while s.remaining > 0.12:
		s.tick(DT)
	var during_recovery := charges(s).size()
	for i in range(3):
		s.press_attack("left_to_right")
		s.release_attack()
	var charged_at_press := charges(s).size()
	for i in range(30):
		s.tick(DT)
	check(charged_at_press == during_recovery and charges(s, "attack").size() == 2 and s.direction == "left_to_right", "buffered_attack_charges_once_when_windup_starts", charges(s).size())
	s = build("balanced")
	s.press_attack("overhead")
	s.release_attack()
	while s.phase != State.Phase.RECOVERY:
		s.tick(DT)
	s.press_attack("left_to_right") # Pressed too early: the buffer expires first.
	s.set_guard(true, "high")
	for i in range(60):
		s.tick(DT)
	check(charges(s, "attack").size() == 1, "expired_or_cleared_buffer_never_charges")
	s = build("balanced")
	var first := s.dodge()
	var second := s.dodge()
	s.tick(DT)
	var third := s.roll()
	check(first and not second and not third and charges(s).size() == 1, "evasion_inputs_in_the_same_moment_charge_once")
	# The same scripted inputs charge the same actions at every tick rate.
	var ledgers := {}
	for hz: float in [30.0, 60.0, 120.0]:
		var f := build("evasive")
		var dt := 1.0 / hz
		var time := 0.0
		var pressed := {}
		while time < 3.0:
			for at: float in [0.1, 0.9, 1.6, 2.4]:
				if time >= at and not pressed.has(at):
					pressed[at] = true
					if at == 1.6:
						f.dodge()
					else:
						f.press_attack("")
						f.release_attack()
			f.tick(dt)
			time += dt
		ledgers[str(hz)] = charges(f).map(func(e: Dictionary) -> String: return e.action)
	results.charge_sequence_by_rate = ledgers
	check(ledgers["30.0"] == ledgers["60.0"] and ledgers["60.0"] == ledgers["120.0"], "charge_sequence_independent_of_tick_rate", ledgers)

# --- Recovery ------------------------------------------------------------------

func recovery_checks() -> void:
	var s := build("balanced")
	s.dodge()
	var after := s.stamina.current
	var waited := 0.0
	while waited < tuning.stamina_regen_delay - DT * 1.5:
		s.tick(DT)
		waited += DT
	var before_delay := s.stamina.current
	for i in range(60):
		s.tick(DT)
	var one_second_later := s.stamina.current
	check(is_equal_approx(before_delay, after) and one_second_later > after and one_second_later - after <= s.resources.stamina_regen + 0.5, "no_recovery_before_delay_then_configured_rate",
		{"after": after, "before_delay": before_delay, "1s_later": one_second_later, "rate": s.resources.stamina_regen})
	for i in range(600):
		s.tick(DT)
	check(is_equal_approx(s.stamina.current, s.stamina.max_stamina), "recovery_stops_at_capacity")
	var e := build("balanced")
	e.stamina.current = e.resources.dodge_cost
	e.dodge()
	var normal := build("balanced")
	normal.stamina.current = normal.resources.dodge_cost + 10.0
	normal.dodge()
	for i in range(int(round((tuning.stamina_regen_delay + 0.2) / DT))):
		e.tick(DT)
		normal.tick(DT)
	check(e.stamina.current == 0.0 and normal.stamina.current > 10.0, "emptying_the_pool_delays_recovery_longer", {"emptied": e.stamina.current, "normal": normal.stamina.current})
	# Owner rule: holding a chamber or a guard is not a stamina drain.
	var hold := build("balanced")
	hold.press_attack("right_to_left")
	var paid := hold.stamina.current
	var minimum := paid
	for i in range(240):
		hold.tick(DT)
		minimum = minf(minimum, hold.stamina.current)
	check(hold.phase == State.Phase.WINDUP and not hold.released and minimum >= paid - 1e-6 and charges(hold).size() == 1, "held_chamber_never_drains_or_auto_fires",
		{"paid_to": paid, "lowest": minimum, "after_4s": hold.stamina.current, "phase": hold.phase})
	var guard := build("balanced")
	guard.set_guard(true, "left")
	for i in range(240):
		guard.tick(DT)
	var guard_spent := build("balanced")
	guard_spent.dodge()
	run_until_idle(guard_spent)
	var idle_spent := build("balanced")
	idle_spent.dodge()
	run_until_idle(idle_spent)
	guard_spent.set_guard(true, "high")
	for i in range(90):
		guard_spent.tick(DT)
		idle_spent.tick(DT)
	check(guard.stamina.current == guard.stamina.max_stamina and guard.guarding and is_equal_approx(guard_spent.stamina.current, idle_spent.stamina.current), "held_guard_neither_drains_nor_slows_recovery",
		{"guarding": guard_spent.stamina.current, "idle": idle_spent.stamina.current})

# --- Feints ---------------------------------------------------------------------

func feint_checks() -> void:
	var s := build("balanced")
	var cost: float = s.resources.attack_cost
	s.press_attack("overhead")
	s.tick(DT)
	s.set_guard(true, "high")
	var feint_net := s.stamina.max_stamina - s.stamina.current
	var released := build("balanced")
	released.press_attack("overhead")
	released.release_attack()
	released.tick(DT)
	released.set_guard(true, "high")
	var swing := build("balanced")
	swing.press_attack("overhead")
	swing.release_attack()
	while swing.phase != State.Phase.SWING:
		swing.tick(DT)
	swing.set_guard(true, "high")
	results.feint = {"attack_cost": r2(cost), "unreleased_guard_cancel_net": r2(feint_net),
		"released_windup_cancel_net": r2(released.stamina.max_stamina - released.stamina.current), "swing_cancel_net": r2(swing.stamina.max_stamina - swing.stamina.current)}
	check(is_equal_approx(feint_net, cost * (1.0 - tuning.feint_refund)), "unreleased_feint_refunds_configured_fraction", results.feint)
	check(is_equal_approx(released.stamina.max_stamina - released.stamina.current, cost) and is_equal_approx(swing.stamina.max_stamina - swing.stamina.current, cost),
		"released_or_swinging_cancel_refunds_nothing", results.feint)
	# Interruption is not a feint.
	var hit := build("balanced")
	hit.press_attack("overhead")
	hit.tick(DT)
	hit.stagger(0.3)
	check(is_equal_approx(hit.stamina.max_stamina - hit.stamina.current, cost) and charges(hit).size() == 1, "interrupted_windup_refunds_nothing")
	# The refund of a cancelled feint counts toward a dodge at the boundary.
	var boundary := build("balanced")
	boundary.stamina.current = cost + boundary.resources.dodge_cost - cost * tuning.feint_refund
	boundary.press_attack("overhead")
	boundary.tick(DT)
	var dodged := boundary.dodge()
	var no_refund := build("balanced")
	no_refund.stamina.current = cost + no_refund.resources.dodge_cost - cost * tuning.feint_refund
	no_refund.press_attack("overhead")
	no_refund.release_attack()
	no_refund.tick(DT)
	check(dodged and boundary.stamina.current < 0.01 and not no_refund.dodge(), "feint_refund_counts_toward_dodge_only_before_release",
		{"feint_dodge": dodged, "left": boundary.stamina.current})
	# Feint spam is bounded: windup → guard cancel, as fast as possible, no rest.
	var spam := build("balanced")
	var feints := 0
	for i in range(400):
		spam.set_guard(false)
		if spam.press_attack("overhead"):
			feints += 1
		spam.tick(DT)
		spam.set_guard(true, "high")
		spam.tick(DT)
		spam.tick(DT)
	results.feint.spam_feints_in_400_cycles = feints
	results.feint.spam_refusals = spam.stamina.refusals
	check(spam.stamina.refusals > 0 and feints < 400, "feint_spam_is_bounded_by_stamina", results.feint)

# --- Light versus heavy -----------------------------------------------------------

## Attacks as fast as the rules allow for `seconds`, from full stamina, into the air,
## pressing during recovery (buffered) as a player chaining cuts would.
func barrage(id: String, seconds: float) -> Dictionary:
	var s := build(id)
	var time := 0.0
	var first_refusal := -1.0
	while time < seconds:
		if s.phase in [State.Phase.IDLE, State.Phase.RECOVERY] and s.buffered == "":
			if s.stamina.can_afford(s.resources.attack_cost):
				s.press_attack("")
				s.release_attack()
			elif first_refusal < 0.0:
				first_refusal = time
		s.tick(DT)
		time += DT
	return {"swings": s.swing_serial, "stamina_left": r2(s.stamina.current), "ran_dry_at": r2(first_refusal), "refusals": s.stamina.refusals}

func economy_checks() -> void:
	var runs := {}
	for id: String in PROFILES:
		runs[id] = barrage(id, 10.0)
	var damage := {}
	for id: String in PROFILES:
		var a := build(id)
		var d := target()
		var report := exchange(a, d, "right_to_left", 1.5 if id == "evasive" else 2.0)
		damage[id] = {"result": report.result, "damage": r2(report.get("damage", 0.0)), "per_stamina": r2(report.get("damage", 0.0) / a.resources.attack_cost)}
	results.barrage_10s = runs
	results.single_hit = damage
	check(runs.evasive.swings >= 1.5 * runs.resistant.swings and runs.balanced.swings > runs.resistant.swings, "light_build_attacks_more_often_than_heavy", runs)
	check(runs.resistant.ran_dry_at > 0.0 and (runs.evasive.ran_dry_at < 0.0 or runs.evasive.ran_dry_at > runs.resistant.ran_dry_at), "heavy_build_runs_out_of_stamina_first", runs)
	check(damage.resistant.result == Solver.HIT and damage.evasive.result == Solver.HIT and damage.resistant.damage > 2.0 * damage.evasive.damage, "heavy_hit_lands_much_harder_than_light_hit", damage)
	# Armor mitigation: the same sword cut against light and heavy armor.
	var mitigated := {}
	for id: String in PROFILES:
		var report := exchange(carrier([]), build(id), "right_to_left")
		mitigated[id] = r2(report.get("damage", 0.0))
	results.sword_hit_vs_armor = mitigated
	check(mitigated.evasive > mitigated.balanced and mitigated.balanced > mitigated.resistant, "heavier_armor_mitigates_physical_damage", mitigated)

# --- Status pipeline -------------------------------------------------------------

func status_checks() -> void:
	var runs := {}
	for hz: float in [30.0, 60.0, 120.0]:
		var s := target()
		s.status.add_buildup("poison", 100.0, "test")
		s.status.drain_events()
		var dt := 1.0 / hz
		var time := 0.0
		var ticks := 0
		var expired_at := -1.0
		while time < 8.0:
			s.tick(dt)
			time += dt
			for e: Dictionary in s.status.drain_events():
				ticks += int(e.event == "tick")
				if e.event == "expired":
					expired_at = time
		runs[str(hz)] = {"ticks": ticks, "health": r2(s.health), "expired_at": r2(expired_at)}
	results.poison_by_rate = runs
	var poison: Dictionary = lab.combat.effects.poison
	var expected_ticks := int(round(poison.duration / poison.tick_interval))
	check(runs.values().all(func(r: Dictionary) -> bool: return r.ticks == expected_ticks and is_equal_approx(r.health, 100.0 - expected_ticks * poison.tick_damage)),
		"poison_ticks_exact_count_and_damage_at_30_60_120_hz", runs)
	check(runs.values().all(func(r: Dictionary) -> bool: return absf(r.expired_at - poison.duration) <= 1.0 / 30.0 + 0.01), "poison_expires_after_its_duration", runs)
	var low := target()
	low.health = 2.0
	low.status.add_buildup("poison", 100.0, "test")
	for i in range(int(8.0 / DT)):
		low.tick(DT)
	check(low.phase != State.Phase.DEAD and is_equal_approx(low.health, 1.0), "poison_cannot_kill_when_can_kill_false", low.health)
	var refresh := target()
	refresh.status.add_buildup("poison", 100.0, "test")
	for i in range(int(3.5 / DT)):
		refresh.tick(DT)
	refresh.status.add_buildup("poison", 100.0, "test")
	var ticks := 0
	var time := 3.5
	var end := -1.0
	refresh.status.drain_events()
	while time < 12.0:
		refresh.tick(DT)
		time += DT
		for e: Dictionary in refresh.status.drain_events():
			ticks += int(e.event == "tick")
			if e.event == "expired":
				end = time
	check(absf(end - (3.5 + poison.duration)) < 0.05 and ticks == expected_ticks, "poison_reapplication_refreshes_duration_without_stacking", {"expired_at": end, "ticks_after_refresh": ticks})
	# Buildup: thresholds, decay and resistance.
	var plain := target()
	var plate := build("resistant")
	var a := plain.status.add_buildup("poison", 35.0, "test")
	var b := plate.status.add_buildup("poison", 35.0, "test")
	check(is_equal_approx(a, 35.0) and is_equal_approx(b, 35.0 * (1.0 - 0.6)) and not plain.status.is_active("poison"), "resistance_scales_buildup_before_threshold", {"unarmored": a, "plate": b})
	for i in range(60):
		plain.tick(DT)
	check(is_equal_approx(plain.status.buildup.poison, 35.0 - poison.decay_per_second), "unfilled_buildup_decays", plain.status.buildup.poison)
	# Slow: handling and movement impairment, expiry, restoration and immunity.
	var slow_def: Dictionary = lab.combat.effects.slow
	var slowed := build("balanced")
	var base_accel: float = slowed.h.accel
	var base_move := slowed.move_scale()
	slowed.status.add_buildup("slow", 1000.0, "test")
	slowed.tick(DT)
	var impaired := {"accel": slowed.h.accel / base_accel, "move": slowed.move_scale() / base_move, "guard_shift": slowed.h.guard_shift / slowed.base_h.guard_shift}
	check(is_equal_approx(impaired.accel, slow_def.handling_scale) and is_equal_approx(impaired.move, slow_def.move_scale) and is_equal_approx(impaired.guard_shift, slow_def.handling_scale),
		"slow_impairs_handling_and_movement_by_data_scales", impaired)
	var ignored := slowed.status.add_buildup("slow", 1000.0, "test")
	for i in range(int((slow_def.duration + 0.1) / DT)):
		slowed.tick(DT)
	check(not slowed.status.is_active("slow") and slowed.h == slowed.base_h and is_equal_approx(slowed.move_scale(), base_move) and ignored == 0.0, "slow_expires_and_restores_exact_handling")
	var during_immunity := slowed.status.add_buildup("slow", 1000.0, "test")
	for i in range(int((slow_def.immunity_after + 0.1) / DT)):
		slowed.tick(DT)
	var after_immunity := slowed.status.add_buildup("slow", 20.0, "test")
	check(during_immunity == 0.0 and after_immunity > 0.0, "slow_immunity_window_blocks_chaining", {"during": during_immunity, "after": after_immunity})
	var normal_profile := swing_time(build("balanced"), false)
	var slowed_profile := swing_time(build("balanced"), true)
	results.slow_swing_seconds = {"normal": r2(normal_profile), "slowed": r2(slowed_profile)}
	check(slowed_profile > normal_profile, "slowed_fighter_swings_reach_contact_later", results.slow_swing_seconds)
	# World condition: ambient, resisted by armor, not avoided by dodging.
	var miasma := CombatResources.find_world(lab.combat, "world.lab_toxic_miasma")
	var runner := target()
	var armored := build("resistant")
	runner.dodge()
	for i in range(60):
		runner.receive_ambient(miasma.status_sources, DT, miasma.id)
		armored.receive_ambient(miasma.status_sources, DT, miasma.id)
		runner.tick(DT)
		armored.tick(DT)
	check(runner.status.buildup.poison > 0.0 and armored.status.buildup.poison < runner.status.buildup.poison, "world_condition_reaches_dodging_fighter_and_armor_resists_it",
		{"dodging": r2(runner.status.buildup.poison), "plate": r2(armored.status.buildup.poison)})

func swing_time(s: State, slowed: bool) -> float:
	if slowed:
		s.status.add_buildup("slow", 1000.0, "test")
		s.tick(DT)
	s.press_attack("right_to_left")
	s.release_attack()
	var time := 0.0
	while time < 3.0:
		s.tick(DT)
		time += DT
		if s.phase == State.Phase.SWING and s.theta <= 0.0:
			return time
	return INF

# --- Routing ---------------------------------------------------------------------

func routing_checks() -> void:
	var routed := {}
	var a := carrier(VENOM)
	var d := target()
	var hit := exchange(a, d, "overhead")
	routed.hit = [hit.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	settle_guard(d, "center")
	var glance := exchange(a, d, "overhead")
	routed.misaligned = [glance.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	settle_guard(d, "left")
	var block := exchange(a, d, "right_to_left")
	routed.block = [block.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	settle_guard(d, "left")
	var at: int = block.tick - 4
	var deflect := exchange(a, d, "right_to_left", 2.0, 150, func(tick: int) -> void:
		if tick == at - 1:
			d.set_guard(false)
		elif tick == at:
			d.set_guard(true, "left"))
	routed.deflect = [deflect.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	var dodge := exchange(a, d, "overhead", 2.0, 150, func(tick: int) -> void:
		if tick == 12:
			d.dodge())
	routed.dodge = [dodge.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	var roll := exchange(a, d, "overhead", 2.0, 150, func(tick: int) -> void:
		if tick == 12:
			d.roll())
	routed.roll_early = [roll.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = target()
	var tail := exchange(a, d, "overhead", 2.0, 150, func(tick: int) -> void:
		if tick == 0:
			d.roll())
	routed.roll_tail = [tail.result, r2(d.status.buildup.poison), "roll elapsed %.2f s" % d.roll_elapsed]
	a = carrier(VENOM)
	d = target()
	var miss := exchange(a, d, "overhead", 4.0)
	routed.miss = [miss.result, r2(d.status.buildup.poison)]
	a = carrier(VENOM)
	d = carrier(VENOM)
	d.press_attack("left_to_right")
	d.release_attack()
	var clash := exchange(a, d, "right_to_left")
	routed.clash = [clash.result, r2(d.status.buildup.poison), r2(a.status.buildup.poison)]
	var heavy := build("resistant")
	var light := build("evasive")
	settle_guard(light, "high")
	var guard_break := exchange(heavy, light, "overhead", 2.2)
	routed.guard_break = [guard_break.result, r2(light.status.buildup.slow)]
	var e := build("evasive")
	var victim := target()
	var real := exchange(e, victim, "right_to_left", 1.5)
	routed.venom_knife_hit = [real.result, r2(victim.status.buildup.poison)]
	results.routing = routed
	check(routed.hit[0] == Solver.HIT and routed.hit[1] == 35.0, "hit_applies_full_on_hit_buildup", routed.hit)
	check(routed.misaligned[0] == Solver.MISALIGNED and routed.misaligned[1] == 17.5, "bad_angle_applies_half_buildup", routed.misaligned)
	check(routed.block[0] == Solver.BLOCK and routed.block[1] == 0.0, "blocked_attack_applies_no_status", routed.block)
	check(routed.deflect[0] == Solver.DEFLECT and routed.deflect[1] == 0.0, "deflected_attack_applies_no_status", routed.deflect)
	check(routed.dodge[0] == Solver.EVADED and routed.dodge[1] == 0.0 and routed.roll_early[0] == Solver.EVADED and routed.roll_early[1] == 0.0, "dodged_or_rolled_attack_applies_no_status", [routed.dodge, routed.roll_early])
	check(routed.roll_tail[0] == Solver.HIT and routed.roll_tail[1] > 0.0, "roll_vulnerable_tail_can_be_hit_and_poisoned", routed.roll_tail)
	check(routed.miss[0] == Solver.NONE and routed.miss[1] == 0.0, "missed_attack_applies_no_status", routed.miss)
	check(routed.clash[0] == Solver.CLASH and routed.clash[1] == 0.0 and routed.clash[2] == 0.0, "clashed_blades_apply_no_status", routed.clash)
	check(routed.guard_break[0] == Solver.GUARD_BREAK and routed.guard_break[1] == 0.0, "guard_break_applies_no_on_hit_status", routed.guard_break)
	check(routed.venom_knife_hit[0] == Solver.HIT and routed.venom_knife_hit[1] == 35.0, "evasive_profile_venom_knife_poisons_on_hit", routed.venom_knife_hit)
	# Three clean venom hits poison an unarmored target; plate needs many more.
	var hits := {}
	for id: String in ["sword", "resistant"]:
		var attacker := build("evasive")
		var defender := build(id)
		var count := 0
		while not defender.status.is_active("poison") and count < 20:
			exchange(attacker, defender, "right_to_left", 1.5)
			count += 1
			run_until_idle(attacker)
			defender.health = defender.max_health
			defender.posture = 0.0
			run_until_idle(defender)
		hits[id] = count
	results.venom_hits_to_poison = hits
	check(hits.sword <= 4 and hits.resistant >= hits.sword * 2, "resistant_build_needs_far_more_venom_hits", hits)

# --- Shared legality -------------------------------------------------------------

func legality_checks() -> void:
	# Identical builds under identical inputs produce identical charges and outcomes,
	# whichever role (player or opponent) supplied the profile.
	var player := build("resistant", tuning, "player")
	var ai := build("resistant", tuning, "opponent")
	var sequence: Array[String] = []
	for s: State in [player, ai]:
		var log: Array[String] = []
		for step: String in ["attack", "dodge", "roll", "attack", "attack", "attack", "attack", "roll"]:
			var legal := s.legal_actions()
			var ok := false
			match step:
				"attack":
					ok = s.press_attack("overhead")
					s.release_attack()
				"dodge":
					ok = s.dodge()
				"roll":
					ok = s.roll()
			log.append("%s:%s:%s:%.3f" % [step, legal[step], ok, s.stamina.current])
			run_until_idle(s)
			s.tick(DT * 3.0)
		sequence.append(" ".join(log))
	results.legality_sequence = sequence[0]
	check(sequence[0] == sequence[1], "player_and_opponent_profiles_follow_identical_legality", sequence)
	var lies := 0
	var s := build("balanced")
	for i in range(300):
		var legal := s.legal_actions()
		var refusals := s.stamina.refusals
		if legal.attack:
			s.press_attack("")
			s.release_attack()
			lies += int(s.stamina.refusals != refusals or s.phase != State.Phase.WINDUP)
		s.tick(DT)
	check(lies == 0, "legal_actions_never_promise_a_refused_attack", lies)

# --- Real scene ---------------------------------------------------------------------

func scene_checks() -> void:
	var arena: Node = load("res://scenes/melee_lab.tscn").instantiate()
	arena.manual_step = true
	root.add_child(arena)
	await process_frame
	var player: Node = arena.player
	player.input_enabled = false
	check(player.loadout_id == "balanced" and arena.opponent.loadout_id == "balanced", "lab_starts_with_balanced_profile_for_both", [player.loadout_id, arena.opponent.loadout_id])
	var travel := {}
	for id: String in PROFILES + ["sword"]:
		arena.set_loadouts(id, "balanced")
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		await frames_wait(2)
		travel[id] = await measure(player, func() -> void: player.desired_move = Vector3.RIGHT, 60)
		arena.set_loadouts(id, "balanced")
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		await frames_wait(2)
		travel[id + "_dodge"] = await measure(player, func() -> void: player.try_dodge(Vector3.RIGHT), 50)
		arena.set_loadouts(id, "balanced")
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		await frames_wait(2)
		travel[id + "_roll"] = await measure(player, func() -> void: player.try_roll(Vector3.RIGHT), 50)
	results.travel_metres = travel
	check(travel.evasive > travel.balanced and travel.balanced > travel.resistant and absf(travel.sword - player.move_speed) < 0.6, "armor_slows_measured_walking", travel)
	check(PROFILES.all(func(id: String) -> bool: return travel[id + "_roll"] > travel[id + "_dodge"]), "roll_travels_further_than_dodge_for_every_build", travel)
	check(travel.evasive_roll > travel.resistant_roll and travel.evasive_dodge > travel.resistant_dodge, "heavy_armor_shortens_evasion_travel", travel)
	# Real input events: one charge per click; a refused click keeps the camera.
	arena.set_loadouts("balanced", "balanced")
	arena.opponent.mode = "dummy"
	arena.opponent.position = Vector3(0.0, 0.02, -6.0)
	player.input_enabled = true
	player.accept_uncaptured_motion = true
	arena.manual_step = false
	await frames_wait(5)
	for i in range(3):
		await press_mouse(MOUSE_BUTTON_LEFT, true)
		await frames_wait(3)
		await press_mouse(MOUSE_BUTTON_LEFT, false)
		await frames_wait(70)
	check(charges(player.state, "attack").size() == 3 and player.state.swing_serial == 3, "real_clicks_charge_exactly_one_attack_each", charges(player.state).size())
	player.state.stamina.current = 1.0
	await press_mouse(MOUSE_BUTTON_LEFT, true)
	await frames_wait(2)
	var refused_owner: String = player.aim_owner
	var refused_phase: int = player.state.phase
	await press_mouse(MOUSE_BUTTON_LEFT, false)
	await frames_wait(2)
	check(refused_owner == "" and refused_phase == State.Phase.IDLE and player.state.stamina.last_refusal.get("action") == "attack", "refused_click_is_visible_and_keeps_camera",
		{"owner": refused_owner, "refusal": player.state.stamina.last_refusal})
	player.state.stamina.current = player.state.stamina.max_stamina
	await press_key("lab_roll")
	var rolled: bool = player.state.phase == State.Phase.ROLL
	await frames_wait(60)
	await press_key("lab_dodge")
	var dodged: bool = player.state.phase == State.Phase.DODGE
	check(rolled and dodged and charges(player.state, "roll").size() == 1 and charges(player.state, "dodge").size() == 1, "shift_rolls_and_space_dodges_through_input_map", [rolled, dodged])
	arena.manual_step = true
	player.input_enabled = false
	# The arena records the status lifecycle from a real duel contact.
	arena.set_loadouts("evasive", "balanced")
	arena.opponent.mode = "dummy"
	arena.opponent.dummy_guard = ""
	arena.opponent.position = Vector3(0.0, 0.02, 1.0) # Inside the knife's reach.
	arena.manual_step = false
	for i in range(3):
		arena.player.state.press_attack("right_to_left")
		arena.player.state.release_attack()
		await frames_wait(60)
	arena.manual_step = true
	var lifecycle: Array = arena.status_events.filter(func(e: Dictionary) -> bool: return e.fighter == "Opponent").map(func(e: Dictionary) -> String: return e.event)
	results.arena_status_lifecycle = lifecycle
	check(arena.events.size() >= 1 and "buildup" in lifecycle, "arena_records_status_events_from_real_contacts", {"contacts": arena.events.map(func(e: Dictionary) -> String: return e.result), "status": lifecycle})
	arena.queue_free()
	await process_frame

## Runs `start` once, then 60 Hz physics for `ticks`; returns horizontal displacement.
func measure(actor: Node, start: Callable, ticks: int) -> float:
	var from: Vector3 = actor.global_position
	start.call()
	for i in range(ticks):
		actor.step(DT)
		await physics_frame
	actor.desired_move = Vector3.ZERO
	var offset: Vector3 = actor.global_position - from
	return snappedf(Vector2(offset.x, offset.z).length(), 0.01)

func press_mouse(button: MouseButton, pressed: bool) -> void:
	var action := "lab_attack" if button == MOUSE_BUTTON_LEFT else "lab_guard"
	var event: InputEventMouseButton = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame

func press_key(action: String) -> void:
	var event: InputEventKey = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame

func frames_wait(count: int) -> void:
	for i in range(count):
		await physics_frame

# --- AI --------------------------------------------------------------------------

func ai_checks() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/melee_lab/lab_opponent.gd")
	var reads := RegEx.create_from_string("(opponent|foe)\\.state\\.(stamina|status|resources|self_view|legal_actions)")
	check(reads.search(source) == null, "ai_never_reads_player_stamina_status_or_resources")
	var traces: Array[String] = []
	var summary := {}
	for run_index in range(2):
		var arena: Node = load("res://scenes/melee_lab.tscn").instantiate()
		arena.manual_step = true
		root.add_child(arena)
		await process_frame
		arena.player.input_enabled = false
		# Starved regeneration: the opponent must conserve, not spam refused attacks.
		arena.tuning.stamina_regen = 3.0
		arena.set_loadouts("balanced", "resistant")
		arena.player.state.max_health = 10000.0
		arena.player.state.health = 10000.0
		arena.opponent.mode = "attack"
		arena.opponent.reset_ai()
		arena.manual_step = false
		await frames_wait(60 * 20)
		arena.manual_step = true
		var ai: Node = arena.opponent
		var attacks: int = ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "attack").size()
		var conserve: int = ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "conserve").size()
		var budget: float = ai.state.stamina.max_stamina + ai.state.resources.stamina_regen * 20.0
		summary.starved = {"attacks": attacks, "refusals": ai.state.stamina.refusals, "conserve_events": conserve, "stamina_budget": r2(budget), "attack_cost": r2(ai.state.resources.attack_cost)}
		if run_index == 0:
			check(ai.state.stamina.refusals == 0 and conserve >= 1 and attacks >= 2 and attacks <= int(budget / ai.state.resources.attack_cost) + 1,
				"ai_respects_stamina_without_refused_attempts", summary.starved)
		# Restored regeneration: the same opponent recovers and attacks again.
		arena.tuning.stamina_regen = tuning.stamina_regen
		arena.set_loadouts("balanced", "resistant")
		arena.player.state.max_health = 10000.0
		arena.player.state.health = 10000.0
		arena.opponent.mode = "attack"
		arena.opponent.reset_ai()
		arena.manual_step = false
		await frames_wait(60 * 12)
		arena.manual_step = true
		var recovered: int = ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "recovered").size()
		var normal_attacks: int = ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "attack").size()
		summary.normal = {"attacks": normal_attacks, "refusals": ai.state.stamina.refusals, "recovered_events": recovered}
		# Own impairment: a long slow (test fixture) changes spacing and attack rate.
		var unslowed := await ai_window(arena, false)
		var slowed := await ai_window(arena, true)
		summary.unslowed = unslowed
		summary.slowed = slowed
		if run_index == 0:
			results.ai = summary
			check(summary.normal.refusals == 0 and normal_attacks > attacks * 12 / 20, "ai_recovers_and_resumes_attacking", summary)
			check(slowed.attacks < unslowed.attacks and slowed.mean_distance > unslowed.mean_distance, "ai_reacts_to_its_own_slow_with_spacing_and_patience", {"unslowed": unslowed, "slowed": slowed})
		traces.append(JSON.stringify(ai.trace) + JSON.stringify(summary))
		arena.queue_free()
		await process_frame
	check(traces[0] == traces[1], "resource_aware_ai_replays_identically", traces[0].length())

## Eight seconds of attack mode; `slowed` keeps the opponent under a long slow.
func ai_window(arena: Node, slowed: bool) -> Dictionary:
	arena.set_loadouts("balanced", "balanced")
	arena.player.state.max_health = 10000.0
	arena.player.state.health = 10000.0
	var ai: Node = arena.opponent
	ai.mode = "attack"
	ai.reset_ai()
	if slowed:
		var defs: Dictionary = lab.combat.effects.duplicate(true)
		defs.slow.duration = 100.0
		ai.state.status = Status.new(defs, ai.state.resources.resistances)
		ai.state.status.add_buildup("slow", 1000.0, "fixture")
	var total := 0.0
	arena.manual_step = false
	for i in range(60 * 8):
		await physics_frame
		total += ai.global_position.distance_to(arena.player.global_position)
	arena.manual_step = true
	return {"attacks": ai.trace.filter(func(e: Dictionary) -> bool: return e.event == "attack").size(), "mean_distance": r2(total / (60.0 * 8.0)), "refusals": ai.state.stamina.refusals}
