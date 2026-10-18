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
	check(not result.ok and not result.errors.is_empty() and result.configs.is_empty() and result.resolved.is_empty(), label, result)

func run() -> void:
	raw = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	builds = JSON.parse_string(FileAccess.get_file_as_string(Adapter.BUILDS_PATH))
	if "--invalid-startup" in OS.get_cmdline_user_args():
		var broken := builds.duplicate(true)
		broken.enemy.profile = "profile.missing"
		write_json("user://gate2-invalid-builds.json", broken)
		var invalid_arena = Courtyard.instantiate()
		invalid_arena.builds_path = "user://gate2-invalid-builds.json"
		root.add_child(invalid_arena) # Production _ready must report the error and quit 1.
		check(invalid_arena.player == null and invalid_arena.enemy == null and invalid_arena.get_child_count() == 0,
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
