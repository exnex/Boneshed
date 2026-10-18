extends SceneTree
## Shared-module and progression regression tests. Rule fixtures deliberately step
## combat directly; the separate rendered runner completes the loop by real input.
const Adapter = preload("res://scripts/combat/build_adapter.gd")
const Catalog = preload("res://scripts/builds/build_catalog.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
const Playable = preload("res://scenes/salvage_courtyard.tscn")
var passed := 0
var failed := 0
var arena: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	passed += int(condition)
	failed += int(not condition)
	print(JSON.stringify({"suite": "marrow", "check": label, "passed": condition}))

func fixture() -> void:
	arena.reset_encounter()
	arena.player.set_physics_process(false)
	arena.enemy.set_physics_process(false)
	arena.set_physics_process(false)
	arena.player.position = Vector3(0.0, 0.02, 2.0)
	arena.enemy.position = Vector3(0.0, 0.02, 0.0)
	arena.player.facing = Vector3.FORWARD
	arena.enemy.facing = Vector3.BACK

func victory() -> void:
	# No test-only reward API: defeat through actual attacks and the production
	# encounter resolver, starting with full health and no direct death assignment.
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	while e.combat.phase != Rules.Phase.DEAD:
		p.combat.tick(5.0)
		p.combat.attack()
		p.combat.tick(p.combat.remaining + 0.001)
		arena._resolve_duel()
	check(arena.progression.stage == arena.Progression.Stage.VICTORY, "resolved_lethal_contact_records_victory")

func run() -> void:
	arena = Playable.instantiate()
	root.add_child(arena)
	await physics_frame
	await process_frame
	fixture()
	var session = arena.progression
	check(session.available_rewards().is_empty() and not session.acquire().ok, "no_reward_before_victory")
	check(not session.equip().ok and not session.begin(true).ok, "no_early_equipment_or_second_duel")
	check(not arena.player.combat.attack_special(), "unequipped_player_cannot_lunge")
	# Debug shortcuts and incomplete/reset encounters cannot issue a reward.
	arena.enemy.combat.health = 0.0
	arena.enemy.combat.phase = Rules.Phase.DEAD
	arena._resolve_duel()
	check(session.available_rewards().is_empty() and not session.acquire().ok, "debug_death_without_lethal_contact_grants_nothing")
	fixture()
	arena.enemy.combat.attack_special()
	arena.enemy.combat.tick(arena.enemy.combat.remaining + 0.001)
	arena.reset_encounter()
	check(session.available_rewards().is_empty() and not session.acquire().ok, "reset_discards_incomplete_encounter")
	fixture()
	victory()
	check(session.available_rewards().size() == 1 and arena.progression_prompt().contains("F to salvage"), "victory_exposes_salvage_prompt")
	# Reset before acquiring drops the unclaimed reward; a new win is required.
	fixture()
	check(session.available_rewards().is_empty() and not session.acquire().ok, "reset_revokes_unclaimed_reward")
	victory()
	var before: Dictionary = session.builds.player.duplicate(true)
	check(session.acquire().ok, "victory_acquisition_succeeds")
	check(session.builds.player.carried == ["item.marrow_arm"] and session.builds.player.equipped == before.equipped, "acquisition_updates_inventory_only")
	check(arena.player.combat.signature.is_empty() and not arena.player.combat.attack_special(), "carried_is_not_equipped")
	check(not session.acquire().ok and session.builds.player.carried.size() == 1, "duplicate_claim_rejected")
	var owned: Dictionary = session.builds.duplicate(true)
	check(not session.equip("item.marrow_arm", "main_hand").ok and session.builds == owned, "occupied_slot_failure_is_atomic")
	check(not session.equip("item.unknown", "right_arm").ok and session.builds == owned, "invalid_item_failure_is_atomic")
	var equipped: Dictionary = session.equip()
	check(equipped.ok and session.equipped() and session.builds.player.carried.is_empty(), "equipping_moves_owned_augment")
	var player_ability: Dictionary = equipped.resolved.player.abilities[2]
	var enemy_ability: Dictionary = equipped.resolved.enemy.abilities[2]
	check(player_ability.id == "ability.marrow_lunge" and player_ability.fingerprint == enemy_ability.fingerprint and player_ability.effective == enemy_ability.effective, "both_wielders_share_definition_and_effective_module")
	check(equipped.states.player.deflect_window == 0.16 and equipped.states.enemy.deflect_window == 0.16, "augmentation_preserves_core_deflection")
	arena._start_duel(true)
	check(session.duel_number == 2 and arena.player.combat.signature == arena.enemy.combat.signature and not arena.player.combat.signature.is_empty(), "second_duel_uses_newly_resolved_build")
	check(arena.player.marrow_pivot.visible and session.available_rewards().is_empty(), "equipped_visual_follows_build_and_new_duel_has_no_reward")
	fixture()
	for attacker: Fighter in [arena.enemy, arena.player]:
		var defender: Fighter = attacker.opponent
		for defense: String in ["hit", "guard", "deflect", "dodge", "rear"]:
			attacker.combat.reset()
			defender.combat.reset()
			attacker.combat.attack_special()
			check(attacker.combat.remaining == 0.7 and attacker.combat.attack_stage() == "early", "lunge_windup_" + attacker.name + defense)
			check(attacker.resolve_attack() == Rules.INVALID and defender.combat.health == 100.0, "telegraph_cannot_hit_" + attacker.name + defense)
			attacker.combat.tick(0.47)
			check(attacker.combat.attack_stage() == "committed", "lunge_commitment_" + attacker.name + defense)
			attacker.combat.tick(0.16)
			check(attacker.combat.attack_stage() == "release", "lunge_release_" + attacker.name + defense)
			attacker.combat.tick(0.071)
			if defense in ["guard", "deflect", "rear"]:
				defender.combat.set_guard(true)
				if defense != "deflect":
					defender.combat.tick(0.3)
			if defense == "dodge":
				defender.combat.dodge()
			if defense == "rear":
				defender.facing = attacker.facing
			attacker._update_visual(0.0)
			var result := attacker.resolve_attack()
			var expected := {"hit": Rules.HIT, "guard": Rules.GUARD, "deflect": Rules.DEFLECTED, "dodge": Rules.EVADED, "rear": Rules.HIT}
			check(result == expected[defense], "lunge_defense_" + attacker.name + defense)
			check(attacker.resolve_attack() == Rules.INVALID, "one_contact_per_lunge_" + attacker.name + defense)
			if defense in ["hit", "rear"]:
				check(defender.combat.health == 74.0 and defender.combat.posture == 18.0, "lunge_damage_posture_" + attacker.name + defense)
			elif defense == "guard":
				check(is_equal_approx(defender.combat.health, 96.88) and defender.combat.posture == 45.0, "lunge_block_pressure_" + attacker.name)
			elif defense == "deflect":
				check(attacker.combat.posture == 42.0 and attacker.combat.phase == Rules.Phase.STAGGER and defender.combat.health == 100.0, "lunge_deflect_pressure_" + attacker.name)
			else:
				check(defender.combat.health == 100.0 and defender.combat.posture == 0.0, "lunge_dodge_prevents_damage_" + attacker.name)
			defender.facing = -attacker.facing
		for phase: int in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			for defense: String in ["guard", "dodge"]:
				attacker.combat.reset()
				attacker.combat.attack_special()
				if phase != Rules.Phase.WINDUP:
					attacker.combat.tick(0.701 if phase == Rules.Phase.ACTIVE else 0.901)
				if defense == "guard":
					attacker.combat.set_guard(true)
				else:
					attacker.combat.dodge()
				check(attacker.combat.hit_consumed and not attacker.combat.is_signature() and attacker.resolve_attack() == Rules.INVALID, "lunge_cancel_" + attacker.name + str(phase) + defense)
		# Long/narrow shape actually differs from a sword, for both actors.
		attacker.combat.reset()
		attacker.combat.attack_special()
		defender.position = attacker.position + attacker.facing * 3.3
		check(attacker.valid_attack_target(defender), "lunge_reaches_beyond_sword_" + attacker.name)
		defender.position += attacker.facing * 0.2
		check(not attacker.valid_attack_target(defender), "lunge_rejects_past_tip_" + attacker.name)
		defender.position = attacker.position + attacker.facing * 2.0 + attacker.facing.cross(Vector3.UP) * 0.9
		check(not attacker.valid_attack_target(defender), "lunge_rejects_lateral_target_" + attacker.name)
		fixture()
	# A retained last-attack selection must not let the AI launch an ordinary
	# heavy counter from the lunge's longer reach.
	fixture()
	arena.enemy.enabled = true
	arena.enemy.combat.attack_special()
	arena.enemy.combat.tick(2.0)
	arena.enemy.position = arena.player.position + arena.player.facing * 3.1
	arena.enemy.counter_pending = true
	arena.enemy.cooldown = 0.0
	arena.enemy._physics_process(0.0)
	check(arena.enemy.combat.phase == Rules.Phase.IDLE and arena.enemy.ai_state == "APPROACH", "heavy_counter_approaches_from_signature_only_range")
	fixture()
	arena.enemy.enabled = true
	arena.enemy.cooldown = 0.0
	arena.enemy.position = arena.player.position + arena.player.facing * 1.8
	arena.enemy._physics_process(0.0)
	check(arena.enemy.combat.is_signature() and arena.enemy.combat.phase == Rules.Phase.WINDUP, "equipped_ai_opens_with_predictable_signature")
	fixture()
	arena.enemy.enabled = true
	arena.enemy.attack_number = 1
	arena.enemy.cooldown = 0.0
	arena.enemy.position = arena.player.position + arena.player.facing * 1.8
	arena.enemy._physics_process(0.0)
	check(not arena.enemy.combat.is_signature() and arena.enemy.combat.phase == Rules.Phase.WINDUP, "signature_cycle_keeps_ordinary_attacks")
	# Win and lose another encounter normally without duplicating or losing ownership.
	fixture()
	victory()
	check(session.available_rewards().is_empty() and not session.acquire().ok, "repeat_victory_cannot_duplicate_owned_augment")
	fixture()
	for i in range(4):
		arena.enemy.combat.tick(5.0)
		arena.enemy.combat.attack(true)
		arena.enemy.combat.tick(arena.enemy.combat.remaining + 0.001)
		arena._resolve_duel()
	check(session.stage == arena.Progression.Stage.FALLEN and session.available_rewards().is_empty(), "normal_loss_has_no_salvage")
	fixture()
	check(session.equipped() and not arena.player.combat.signature.is_empty() and arena.player.combat.health == 100.0, "reset_after_loss_retains_valid_progression")
	test_data_validation()
	arena.free()
	print(JSON.stringify({"suite": "marrow", "summary": true, "passed": passed, "failed": failed}))
	quit(1 if failed else 0)

func test_data_validation() -> void:
	var prepared := Adapter.load_encounter(Catalog.CATALOG_PATH, "res://data/builds/salvage_courtyard.json")
	var config: Dictionary = prepared.configs.enemy
	for field: String in config.signature:
		var changed := config.duplicate(true)
		changed.signature[field] = {"windup": 0.93, "active": 0.27, "recovery": 1.1, "health_damage": 31.0, "posture_damage": 29.0, "guard_posture": 52.0, "reach": 3.8, "width": 0.6}[field]
		var state: Rules = Adapter.create_state(changed).state
		state.attack_special()
		check(state.signature[field] == changed.signature[field] and state.signature[field] != config.signature[field], "nondefault_signature_field_applied_" + field)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
		data.abilities[2]["timing" if field in ["windup", "active", "recovery"] else "hit"][field] = changed.signature[field]
		var catalog := Catalog.new()
		catalog.load_data(data)
		var builds: Dictionary = prepared.builds.duplicate(true)
		builds.player.equipped["right_arm"] = "item.marrow_arm"
		var live := Adapter.new(catalog).prepare_encounter(builds)
		check(live.ok and live.states.player.signature[field] == changed.signature[field] and live.states.enemy.signature[field] == changed.signature[field], "catalog_signature_change_reaches_both_actors_" + field)
		for invalid: Variant in [null, "1", true, -1, INF, NAN]:
			var malformed := config.duplicate(true)
			malformed.signature[field] = invalid
			var rejected := Adapter.create_state(malformed)
			check(not rejected.ok and rejected.state == null, "invalid_signature_" + field + str(invalid))
		changed.signature.erase(field)
		check(not Adapter.create_state(changed).ok, "missing_signature_field_" + field)
	for invalid: Variant in [{}, [], null, {"extra": 1}]:
		var changed := config.duplicate(true)
		changed.signature = invalid
		check(not Adapter.create_state(changed).ok, "invalid_signature_shape_" + str(invalid))
	# Incoming defense costs describe the attack being received, independently
	# of whether the defender owns that attack.
	var defender_config: Dictionary = prepared.configs.player.duplicate(true)
	defender_config.combat.guard_posture_overrides["special"] = 9.0
	var defender: Rules = Adapter.create_state(defender_config).state
	defender.set_guard(true)
	defender.tick(0.3)
	var attacker: Rules = prepared.states.enemy
	attacker.attack_special()
	attacker.tick(0.701)
	check(defender.receive(attacker) == Rules.GUARD and defender.posture == 9.0 and defender.signature.is_empty(), "incoming_signature_defense_cost_does_not_require_owning_signature")
	# Equip rollback also covers a build-valid but unexecutable module.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	data.abilities[2].module = "module.unknown"
	var catalog := Catalog.new()
	catalog.load_data(data)
	var builds: Dictionary = prepared.builds.duplicate(true)
	builds.enemy.equipped.erase("right_arm")
	builds.player.carried = ["item.marrow_arm"]
	var adapter := Adapter.new(catalog)
	var initial := adapter.prepare_encounter(builds)
	initial.adapter = adapter
	initial.builds = builds
	var session := preload("res://scripts/combat/duel_progression.gd").new(initial)
	session.stage = session.Stage.VICTORY # Transaction fixture only, not reward evidence.
	var prior := session.builds.duplicate(true)
	check(not session.equip().ok and session.builds == prior, "unexecutable_equipment_rolls_back_inventory")
