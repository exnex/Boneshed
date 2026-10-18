extends SceneTree
## Integration tests: real scene configuration, independent pre-integration trace,
## controlled data changes, unsupported content and all-or-nothing preparation.
const Catalog = preload("res://scripts/builds/build_catalog.gd")
const BuildRules = preload("res://scripts/builds/build_rules.gd")
const Adapter = preload("res://scripts/combat/build_adapter.gd")
const Courtyard = preload("res://scenes/courtyard.tscn")
const Snapshot = preload("res://scripts/qa/combat_build_snapshot.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
var passed := 0
var failed := 0
var raw: Dictionary
var builds: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String, detail: Variant = null) -> void:
	passed += int(condition)
	failed += int(not condition)
	print(JSON.stringify({"suite": "combat_builds", "check": label, "passed": condition, "detail": detail if not condition else null}))

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))

func catalog_for(data: Dictionary):
	var catalog = Catalog.new()
	catalog.load_data(data)
	return catalog

func rejected(result: Dictionary, label: String) -> void:
	check(not result.ok and not result.errors.is_empty() and result.configs.is_empty() and result.resolved.is_empty() and result.states.is_empty(), label, result)

func run() -> void:
	raw = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	builds = JSON.parse_string(FileAccess.get_file_as_string(Adapter.BUILDS_PATH))
	if "--invalid-startup" in OS.get_cmdline_user_args() or "--invalid-state-startup" in OS.get_cmdline_user_args():
		var broken := builds.duplicate(true)
		broken.enemy.profile = "profile.missing"
		write_json("user://gate2-invalid-builds.json", broken)
		var invalid_arena = Courtyard.instantiate()
		invalid_arena.builds_path = "user://gate2-invalid-builds.json"
		if "--invalid-state-startup" in OS.get_cmdline_user_args():
			var data := raw.duplicate(true)
			data.profiles[1].guard_posture_overrides.special = 1
			write_json("user://adapter-invalid-state-catalog.json", data)
			invalid_arena.catalog_path = "user://adapter-invalid-state-catalog.json"
			invalid_arena.builds_path = Adapter.BUILDS_PATH
		root.add_child(invalid_arena) # Production _ready must report the error and quit 1.
		check(invalid_arena.player == null and invalid_arena.enemy == null and invalid_arena.get_child_count() == 0 and not InputMap.has_action("attack") and not invalid_arena.is_physics_processing(),
			"invalid_startup_creates_no_fighters_or_world")
		return
	var catalog = catalog_for(raw)
	var adapter = Adapter.new(catalog)
	check(catalog.errors.is_empty(), "integration_catalog_valid")
	var prepared: Dictionary = adapter.prepare_encounter(builds)
	check(prepared.ok, "both_actor_builds_prepare", prepared.errors)
	var arena = Courtyard.instantiate()
	root.add_child(arena)
	var baseline = FileAccess.get_file_as_string("res://scripts/qa/fixtures/combat_runtime_baseline.json")
	check(JSON.stringify(Snapshot.collect(arena), "\t", true) + "\n" == baseline, "runtime_matches_pre_integration_trace")
	# The exact same resolver object handles both builds; the live scene agrees with
	# direct resolution, including identity, source items and effective values.
	for actor in ["player", "enemy"]:
		var direct: Dictionary = adapter.resolver.resolve(builds[actor])
		check(direct.resolved == arena.resolved_builds[actor], actor + "_uses_shared_resolver")
		check(arena.get(actor).combat.max_health == 100.0 and arena.get(actor).combat.max_posture == 100.0, actor + "_health_posture_unchanged")
	check(arena.resolved_builds.player.abilities[0].fingerprint == arena.resolved_builds.enemy.abilities[0].fingerprint, "both_share_same_sword_definition")
	check(arena.player.move_speed == 5.5 and arena.enemy.move_speed == 2.7, "movement_speeds_unchanged")
	check(arena.enemy.combat.attack_windup == 0.62 and arena.enemy.combat.heavy_windup == 0.85, "enemy_per_attack_timing_preserved")
	arena.free()
	test_data_changes()
	test_rejection(adapter)
	test_every_parameter(adapter)
	test_config_rejection(adapter)
	test_deflection_window_effect(adapter)
	print(JSON.stringify({"suite": "combat_builds", "summary": true, "passed": passed, "failed": failed}))
	quit(1 if failed else 0)

func test_data_changes() -> void:
	var changed := raw.duplicate(true)
	changed.profiles[0].stats.max_health = 137
	changed.profiles[0].stats.move_speed = 6.25
	changed.profiles[0].stats.posture_recovery_rate = 20
	changed.profiles[0].stats.deflect_posture = 35
	changed.abilities[0].hit.health_damage = 23
	changed.abilities[0].hit.posture_damage = 21
	changed.abilities[0].hit.guard_posture = 31
	changed.abilities[0].timing.active = 0.21
	changed.abilities[0].timing.windup = 0.44
	changed.profiles[1].ability_overrides["attack.slash"].recovery = 0.72
	changed.profiles[1].ability_overrides["attack.heavy_slash"]["health_damage"] = 39
	write_json("user://gate2-changed-catalog.json", changed)
	var arena = Courtyard.instantiate()
	arena.catalog_path = "user://gate2-changed-catalog.json"
	root.add_child(arena)
	var p = arena.player.combat
	var e = arena.enemy.combat
	check(p.health == 137 and p.max_health == 137 and arena.player.move_speed == 6.25, "data_change_reaches_live_health_and_movement")
	p.attack()
	check(p.remaining == 0.44 and e.attack_windup == 0.62, "base_windup_changes_without_overwriting_form_override")
	p.tick(p.attack_windup + 0.001)
	check(e.receive(p) == "hit" and e.health == 77 and e.posture == 21, "data_change_reaches_live_hit_damage_and_posture")
	check(p.active_duration == 0.21, "light_active_data_is_consumed")
	p.tick(0.17)
	check(p.phase == Rules.Phase.ACTIVE, "changed_light_active_duration_changes_phase_transition")
	p.reset()
	p.attack(true)
	check(p.active_duration == 0.16 and p.recovery_duration == 0.45, "heavy_timing_independent_of_light")
	p.tick(p.heavy_windup + 0.17)
	check(p.phase == Rules.Phase.RECOVERY and is_equal_approx(p.remaining, 0.44), "heavy_phase_transition_uses_its_own_active_duration")
	e.reset()
	e.attack()
	check(e.recovery_duration == 0.72, "profile_override_reaches_runtime_recovery")
	e.tick(e.attack_windup + e.active_duration + 0.001)
	check(e.phase == Rules.Phase.RECOVERY and is_equal_approx(e.remaining, 0.719), "profile_recovery_override_changes_phase_transition")
	e.reset()
	e.attack(true)
	e.tick(e.heavy_windup + 0.001)
	p.reset()
	check(p.receive(e) == "hit" and p.health == 98 and e.recovery_duration == 0.65, "per_actor_heavy_override_reaches_runtime")
	p.reset()
	p.posture = 60
	p.tick(2.0)
	check(p.posture == 20, "posture_recovery_data_is_consumed")
	# Changed shared pressure affects ordinary defense, while the braced form keeps
	# its explicit incoming cost. Heavy and light can differ without global scales.
	p.reset()
	e.reset()
	p.set_guard(true)
	p.tick(0.3)
	e.attack()
	e.tick(e.attack_windup + 0.001)
	check(p.receive(e) == "guard" and p.posture == 31, "incoming_ability_guard_pressure_is_consumed")
	e.reset()
	p.reset()
	e.set_guard(true)
	e.tick(0.3)
	p.attack()
	p.tick(p.attack_windup + 0.001)
	check(e.receive(p) == "guard" and e.posture == 10, "form_block_cost_remains_explicit")
	p.reset()
	e.reset()
	p.set_guard(true)
	e.attack()
	e.tick(e.attack_windup + 0.001)
	check(p.receive(e) == "deflected" and e.posture == 35, "deflection_posture_data_is_consumed")
	arena.free()
	# Timing overrides are base values, then wielder scales apply once.
	changed.profiles[1].stats.windup_scale = 2
	var scaled = Adapter.new(catalog_for(changed)).prepare_encounter(builds)
	check(scaled.ok and scaled.configs.enemy.combat.attack_windup == 1.24 and scaled.configs.enemy.combat.heavy_windup == 1.7,
		"overrides_then_scales_share_one_resolution_order")

func test_rejection(adapter) -> void:
	var bad_builds := builds.duplicate(true)
	bad_builds.enemy.profile = "profile.missing"
	rejected(adapter.prepare_encounter(bad_builds), "invalid_second_actor_returns_no_partial_configs")
	bad_builds = builds.duplicate(true)
	bad_builds.player.catalog_version = "stale"
	rejected(adapter.prepare_encounter(bad_builds), "stale_build_rejected")
	bad_builds = builds.duplicate(true)
	bad_builds.enemy.equipped["right_arm"] = "item.marrow_arm"
	rejected(adapter.prepare_encounter(bad_builds), "unimplemented_lunge_cannot_start_gameplay")
	bad_builds = builds.duplicate(true)
	bad_builds.enemy.equipped = {}
	rejected(adapter.prepare_encounter(bad_builds), "missing_attacks_rejected")
	rejected(adapter.prepare_encounter({"player": builds.player}), "missing_actor_rejected")
	var invalid_catalogs := {
		"unknown_override_ability": func(d): d.profiles[1].ability_overrides["ability.missing"] = {"windup": 0.5},
		"unknown_override_field": func(d): d.profiles[1].ability_overrides["attack.slash"]["speed"] = 2,
		"non_numeric_override": func(d): d.profiles[1].ability_overrides["attack.slash"].windup = "slow",
		"zero_override_timing": func(d): d.profiles[1].ability_overrides["attack.slash"].windup = 0,
		"negative_override_damage": func(d): d.profiles[1].ability_overrides["attack.slash"]["health_damage"] = -1,
		"malformed_stat_range": func(d): d.stats[0].min = "bad",
		"malformed_provided_tags": func(d): d.items[0].provides_tags = 7,
		"malformed_bindings": func(d): d.bindings = "light",
		"duplicate_bindings": func(d): d.bindings.append("light"),
		"malformed_item_slots": func(d): d.items[0].fits_slots = {},
		"malformed_ability_requirements": func(d): d.abilities[0].requires_tags = 7,
		"non_text_module": func(d): d.abilities[0].module = 7,
		"non_finite_override": func(d): d.profiles[1].ability_overrides["attack.slash"].windup = INF,
		"invalid_defense_binding": func(d): d.profiles[1].guard_posture_overrides["kick"] = 1,
		"negative_defense_cost": func(d): d.profiles[1].guard_posture_overrides.light = -1,
	}
	for label in invalid_catalogs:
		var data := raw.duplicate(true)
		invalid_catalogs[label].call(data)
		var catalog = catalog_for(data)
		check(not catalog.errors.is_empty(), "catalog_rejects_" + label)
		rejected(Adapter.new(catalog).prepare_encounter(builds), "no_resolution_for_" + label)
	var incompatible := {
		"overflowing_effective_value": func(d): d.abilities[0].hit.health_damage = 1e308,
		"unknown_module": func(d): d.abilities[0].module = "module.unknown",
		"unintegrated_hit_shape": func(d): d.abilities[0].hit.reach = 3.0,
		"too_short_pose_timing": func(d): d.abilities[0].timing.windup = 0.24,
		"rounded_zero_active": func(d): d.abilities[0].timing.active = 0.00001,
		"missing_runtime_stat": func(d):
			d.stats = d.stats.filter(func(s): return s.id != "deflect_posture")
			for profile in d.profiles: profile.stats.erase("deflect_posture"),
	}
	for label in incompatible:
		var data := raw.duplicate(true)
		incompatible[label].call(data)
		var catalog = catalog_for(data)
		check(catalog.errors.is_empty(), "valid_catalog_for_" + label, catalog.errors)
		rejected(Adapter.new(catalog).prepare_encounter(builds), "compatibility_rejects_" + label)
	var reused = catalog_for(raw)
	var invalid_reload := raw.duplicate(true)
	invalid_reload.profiles[0].stats.max_health = -1
	check(not reused.load_data(invalid_reload), "invalid_reload_replaces_frozen_tables_safely")
	rejected(Adapter.new(reused).prepare_encounter(builds), "invalid_reload_cannot_reuse_previous_valid_catalog")
	var bad_scene = Courtyard.instantiate()
	bad_scene.builds_path = "user://missing-gate2-builds.json"
	rejected(bad_scene.prepare_builds(), "missing_build_file_rejected_before_scene_init")
	check(bad_scene.player == null and bad_scene.enemy == null and bad_scene.get_child_count() == 0, "prepare_failure_has_no_fighter_side_effects")
	bad_scene.free()

# Every case starts from a fresh valid resolution. The changed value must differ
# from both that resolution and CombatState's defaults, for both actor profiles.
func parameter_cases() -> Array:
	return [
		["max_health", "stat", "max_health", 137.0],
		["max_posture", "stat", "max_posture", 143.0],
		["deflect_window", "stat", "deflect_window", 0.11],
		["guard_chip", "stat", "guard_chip", 0.23],
		["posture_recovery_rate", "stat", "posture_recovery_rate", 19.0],
		["posture_recovery_delay", "stat", "posture_recovery_delay", 2.25],
		["deflect_posture", "stat", "deflect_posture", 37.0],
		["attack_windup", "light", "windup", 0.47],
		["heavy_windup", "heavy", "windup", 1.13],
		["light_active_duration", "light", "active", 0.22],
		["heavy_active_duration", "heavy", "active", 0.27],
		["light_recovery_duration", "light", "recovery", 0.53],
		["heavy_recovery_duration", "heavy", "recovery", 0.76],
		["light_damage", "light", "health_damage", 23.0],
		["heavy_damage", "heavy", "health_damage", 39.0],
		["light_hit_posture", "light", "posture_damage", 25.0],
		["heavy_hit_posture", "heavy", "posture_damage", 33.0],
		["light_guard_posture", "light", "guard_posture", 31.0],
		["heavy_guard_posture", "heavy", "guard_posture", 49.0],
		["guard_posture_overrides", "overrides", "", {"light": 7.0, "heavy": 19.0}],
	]

func construction_rejected(config: Variant, code: String, field := "") -> bool:
	var result := Adapter.create_state(config)
	return not result.ok and result.state == null and not result.errors.is_empty() \
		and result.errors[0].code == code and (field.is_empty() or result.errors[0].get("field") == field)

func test_every_parameter(adapter) -> void:
	var cases := parameter_cases()
	var fields: Array = cases.map(func(c): return c[0])
	var prepared: Dictionary = adapter.prepare_encounter(builds)
	var configured: Array = prepared.configs.player.combat.keys().map(func(f): return str(f))
	fields.sort()
	configured.sort()
	check(fields == configured and fields.size() == 20, "parameter_matrix_covers_entire_combat_config", {"expected": fields, "actual": configured})
	var defaults := Rules.new()
	for actor in ["player", "enemy"]:
		for entry in cases:
			var field: String = entry[0]
			var resolved: Dictionary = adapter.resolver.resolve(builds[actor]).resolved
			var original: Dictionary = adapter._from_resolved(resolved).config
			check(original.combat[field] != entry[3] and defaults.get(field) != entry[3],
				"parameter_fixture_differs_" + field + "_" + actor)
			if entry[1] == "stat":
				resolved.stats[entry[2]] = entry[3]
			elif entry[1] == "overrides":
				resolved.guard_posture_overrides = entry[3].duplicate(true)
			else:
				for ability in resolved.abilities:
					if ability.binding == entry[1]:
						ability.effective[entry[2]] = entry[3]
			var translated: Dictionary = adapter._from_resolved(resolved)
			var result := Adapter.create_state(translated.config)
			check(result.ok and result.errors.is_empty() and result.state.get(field) == entry[3],
				"parameter_applied_" + field + "_" + actor, result.errors)
			check(result.ok and result.state.health == translated.config.combat.max_health,
				"parameter_state_reset_" + field + "_" + actor)
			# Exercise the production catalog -> resolver -> preparation -> scene path
			# separately, including per-profile overrides for every attack value.
			var data := raw.duplicate(true)
			var profile: Dictionary = data.profiles[0 if actor == "player" else 1]
			if entry[1] == "stat":
				profile.stats[entry[2]] = entry[3]
			elif entry[1] == "overrides":
				profile.guard_posture_overrides = entry[3].duplicate(true)
			else:
				var id := "attack.slash" if entry[1] == "light" else "attack.heavy_slash"
				if not profile.has("ability_overrides"):
					profile.ability_overrides = {}
				if not profile.ability_overrides.has(id):
					profile.ability_overrides[id] = {}
				profile.ability_overrides[id][entry[2]] = entry[3]
			write_json("user://adapter-parameter-catalog.json", data)
			var live_arena = Courtyard.instantiate()
			live_arena.catalog_path = "user://adapter-parameter-catalog.json"
			root.add_child(live_arena)
			check(live_arena.get(actor).combat.get(field) == entry[3], "parameter_live_" + field + "_" + actor)
			live_arena.free()
			var missing: Dictionary = translated.config.duplicate(true)
			missing.combat.erase(field)
			check(construction_rejected(missing, "missing_combat_parameter", field),
				"parameter_missing_rejected_" + field + "_" + actor)
			missing.combat[field + "_typo"] = entry[3]
			check(construction_rejected(missing, "unknown_combat_parameter", field + "_typo"),
				"parameter_renamed_rejected_" + field + "_" + actor)
		# Movement belongs to Fighter, and must also change through the live path.
		var data := raw.duplicate(true)
		var index := 0 if actor == "player" else 1
		data.profiles[index].stats.move_speed = 6.25
		write_json("user://adapter-movement-catalog.json", data)
		var arena = Courtyard.instantiate()
		arena.catalog_path = "user://adapter-movement-catalog.json"
		root.add_child(arena)
		check(arena.get(actor).move_speed == 6.25, "parameter_applied_move_speed_" + actor)
		arena.free()
	# Runtime state and prepared JSON must not alias mutable defense dictionaries.
	var config: Dictionary = prepared.configs.enemy
	var first := Adapter.create_state(config)
	var second := Adapter.create_state(config)
	first.state.guard_posture_overrides.light = 99.0
	check(config.combat.guard_posture_overrides.light == 10 and second.state.guard_posture_overrides.get("light") == 10,
		"defense_overrides_are_owned_by_each_state")
	check(prepared.states.player != prepared.states.enemy and prepared.states.player.health == 100,
		"preparation_constructs_distinct_reset_states")

func test_config_rejection(adapter) -> void:
	var config: Dictionary = adapter.prepare_encounter(builds).configs.player
	for entry in parameter_cases():
		var field: String = entry[0]
		if field == "guard_posture_overrides":
			continue
		for invalid in [null, "1", true, [], {}, -1.0, INF, -INF, NAN]:
			var changed := config.duplicate(true)
			changed.combat[field] = invalid
			check(construction_rejected(changed, "invalid_parameter_value", field),
				"invalid_value_" + field + "_" + str(typeof(invalid)) + "_" + str(invalid))
	for field in ["max_health", "max_posture", "light_active_duration", "heavy_active_duration",
		"light_recovery_duration", "heavy_recovery_duration", "attack_windup", "heavy_windup", "guard_chip"]:
		var changed := config.duplicate(true)
		changed.combat[field] = 1.01 if field == "guard_chip" else (0.24 if "windup" in field else 0.0)
		check(construction_rejected(changed, "unsupported_parameter_value", field), "unsupported_range_" + field)
	for invalid in [null, [], "costs", 7]:
		var changed := config.duplicate(true)
		changed.combat.guard_posture_overrides = invalid
		check(construction_rejected(changed, "invalid_guard_posture_overrides"), "invalid_override_shape_" + str(invalid))
	for invalid in [{"special": 1}, {"ligth": 1}, {"light": -1}, {"heavy": INF}, {"light": NAN}, {"heavy": true}, {"light": "1"}]:
		var changed := config.duplicate(true)
		changed.combat.guard_posture_overrides = invalid
		check(construction_rejected(changed, "invalid_guard_posture_override"), "invalid_override_" + str(invalid))
	for invalid in [null, [], {}, {"combat": []}, {"combat": config.combat}]:
		check(construction_rejected(invalid, "invalid_state_config"), "invalid_config_shape_" + str(invalid))
	for field in ["health", "active_duration", "deflect_widnow"]:
		var changed := config.duplicate(true)
		changed.combat[field] = 1
		check(construction_rejected(changed, "unknown_combat_parameter", field), "non_parameter_rejected_" + field)
	var extra := config.duplicate(true)
	extra.unexpected = 1
	check(construction_rejected(extra, "unknown_config_field", "unexpected"), "unknown_outer_config_field")
	for invalid in [null, true, "fast", -1, INF, NAN]:
		var changed := config.duplicate(true)
		changed.move_speed = invalid
		check(construction_rejected(changed, "invalid_parameter_value", "move_speed"), "invalid_move_speed_" + str(invalid))
	# Zero is supported for pressure, chip, recovery rate/delay, window and movement.
	var zero := config.duplicate(true)
	for field in ["deflect_window", "guard_chip", "posture_recovery_rate", "posture_recovery_delay",
		"deflect_posture", "light_damage", "heavy_damage", "light_hit_posture", "heavy_hit_posture",
		"light_guard_posture", "heavy_guard_posture"]:
		zero.combat[field] = 0
	zero.move_speed = 0
	zero.combat.guard_posture_overrides = {"light": 0, "heavy": 0}
	check(Adapter.create_state(zero).ok, "supported_zero_values_not_overrestricted")
	# A catalog can define a binding the courtyard cannot execute. State-validation
	# errors on the second actor must discard the already constructed first actor.
	var data := raw.duplicate(true)
	data.profiles[1].guard_posture_overrides.special = 1
	var catalog = catalog_for(data)
	check(catalog.errors.is_empty(), "catalog_valid_with_non_courtyard_defense_binding")
	var rejected_encounter: Dictionary = Adapter.new(catalog).prepare_encounter(builds)
	rejected(rejected_encounter, "state_validation_failure_discards_both_actors")
	check(rejected_encounter.errors[0].actor == "enemy" and rejected_encounter.errors[0].state_errors[0].code == "invalid_guard_posture_override",
		"state_validation_error_propagates_actor_and_cause")

func test_deflection_window_effect(adapter) -> void:
	var resolved: Dictionary = adapter.resolver.resolve(builds.player).resolved
	resolved.stats.deflect_window = 0.11
	var config: Dictionary = adapter._from_resolved(resolved).config
	var defender = Adapter.create_state(config).state
	var attacker := Rules.new()
	defender.set_guard(true)
	defender.tick(0.13)
	attacker.attack()
	attacker.tick(attacker.remaining + 0.001)
	check(defender.receive(attacker) == "guard" and defender.health < defender.max_health,
		"changed_deflect_window_affects_live_defense")
