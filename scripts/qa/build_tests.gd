extends SceneTree
## Deterministic tests for the shared build / salvage prototype. Prints one JSON line
## per check plus a summary, like the other suites. Exit code 1 on any failure.
## Independent of combat, the courtyard and worldgen.

const Catalog := preload("res://scripts/builds/build_catalog.gd")
const Rules := preload("res://scripts/builds/build_rules.gd")
const Salvage := preload("res://scripts/builds/salvage.gd")
const Flow := preload("res://scripts/qa/salvage_flow_fixture.gd")
const EXAMPLE_FLOW := "res://docs/salvage/examples/flow.json"
const LIBRARY_SCRIPTS := ["res://scripts/builds/build_catalog.gd", "res://scripts/builds/build_rules.gd", "res://scripts/builds/salvage.gd"]

## Test-only definitions layered onto the real catalog. Never shipped as content.
const FIXTURE_ABILITIES := [
	{"id": "ability.test_hook", "name": "Test Hook", "binding": "special", "tags": ["melee"], "requires_tags": ["body.hook"],
		"module": "module.test", "telegraph": "test", "timing": {"windup": 0.5, "active": 0.1, "recovery": 0.5},
		"hit": {"health_damage": 10, "guard_posture": 10, "posture_damage": 18, "reach": 2.0, "width": 1.0}},
]
const FIXTURE_ITEMS := [
	{"id": "item.test_greatsword", "name": "Test Greatsword", "category": "weapon", "fits_slots": ["main_hand"],
		"provides_tags": ["wield.blade", "grip.two_handed"], "requires_tags": [], "excludes_tags": [],
		"grants": ["attack.slash", "attack.heavy_slash"], "modifiers": [], "salvageable": false, "notes": "test"},
	{"id": "item.test_left_marrow_arm", "name": "Test Left Marrow Arm", "category": "augment", "fits_slots": ["left_arm"],
		"provides_tags": ["body.marrow_arm"], "requires_tags": [], "excludes_tags": [], "grants": ["ability.marrow_lunge"],
		"modifiers": [{"stat": "deflect_window", "op": "add", "value": -0.05}], "salvageable": true, "notes": "test"},
	{"id": "item.test_hook_arm", "name": "Test Hook Arm", "category": "augment", "fits_slots": ["left_arm"],
		"provides_tags": ["body.hook"], "requires_tags": [], "excludes_tags": [], "grants": ["ability.test_hook"],
		"modifiers": [{"stat": "move_speed", "op": "add", "value": -0.5}], "salvageable": true, "notes": "test"},
	{"id": "item.test_brace", "name": "Test Brace", "category": "augment", "fits_slots": ["left_arm"],
		"provides_tags": [], "requires_tags": ["body.marrow_arm"], "excludes_tags": [], "grants": [],
		"modifiers": [{"stat": "max_posture", "op": "add", "value": 30}, {"stat": "move_speed", "op": "mul", "value": 0.8}],
		"salvageable": false, "notes": "test"},
	{"id": "item.test_crush_arm", "name": "Test Crush Arm", "category": "augment", "fits_slots": ["left_arm"],
		"provides_tags": [], "requires_tags": [], "excludes_tags": [], "grants": [],
		"modifiers": [{"stat": "max_posture", "op": "add", "value": -500}], "salvageable": false, "notes": "test"},
]

var passed := 0
var failed := 0
var raw: Dictionary
var catalog
var rules
var salvage
var fixture
var fixture_rules

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	var record := {"suite": "builds", "check": label, "passed": condition}
	if not condition and detail != null:
		record["detail"] = detail
	print(JSON.stringify(record))

func run() -> void:
	raw = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	catalog = Catalog.new()
	check(catalog.load_file(), "catalog_valid", catalog.errors)
	rules = Rules.new(catalog)
	salvage = Salvage.new(catalog, rules)
	fixture = Catalog.new()
	check(fixture.load_data(_fixture_data()), "fixture_catalog_valid", fixture.errors)
	fixture_rules = Rules.new(fixture)
	test_catalog()
	test_catalog_validation()
	test_shared_compatibility()
	test_identity()
	test_build_validation()
	test_invalid_combinations()
	test_duplicates_and_conflicts()
	test_equip_unequip()
	test_stats_and_tradeoffs()
	test_salvage()
	test_serialization()
	test_reproducibility()
	test_isolation()
	print(JSON.stringify({"suite": "builds", "summary": true, "passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)

func _fixture_data() -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	data.abilities.append_array(FIXTURE_ABILITIES.duplicate(true))
	data.items.append_array(FIXTURE_ITEMS.duplicate(true))
	return data

func _codes(errors: Array) -> Array:
	return errors.map(func(e): return e.code)

func _player(r = null) -> Dictionary:
	return Flow.player_build(r if r != null else rules)

func _soul(r = null) -> Dictionary:
	return Flow.corrupted_soul_build(r if r != null else rules)

func _resolved(build: Dictionary, r = null) -> Dictionary:
	return (r if r != null else rules).resolve(build).resolved

func _ability(resolved: Dictionary, id: String) -> Dictionary:
	for ability in resolved.abilities:
		if ability.id == id:
			return ability
	return {}

## A build carrying the given fixture items, with the listed slot → item equips applied.
func _fixture_build(carried: Array, equips: Array) -> Dictionary:
	var build: Dictionary = fixture_rules.new_build("fixture.build", "profile.duelist")
	for item_id in carried:
		build = fixture_rules.carry(build, item_id).build
	for pair in equips:
		var step: Dictionary = fixture_rules.equip(build, pair[1], pair[0])
		check(step.ok, "fixture_equip:%s" % pair[1], step.errors)
		build = step.build
	return build

func _raw_equipped(equipped: Dictionary) -> Dictionary:
	var build: Dictionary = fixture_rules.new_build("fixture.raw", "profile.duelist")
	build.equipped = equipped
	return build

func test_catalog() -> void:
	check(catalog.version == "0.3.0" and catalog.fingerprint.length() == 16, "catalog_version_and_fingerprint")
	check(catalog.abilities.size() == 3 and catalog.items.size() == 2 and catalog.profiles.size() == 2, "catalog_is_small_curated_sample")
	check(catalog.items["item.marrow_arm"].is_read_only() and catalog.items["item.marrow_arm"].modifiers.is_read_only()
		and catalog.abilities["ability.marrow_lunge"].timing.is_read_only(), "definitions_frozen_deeply")
	var other = Catalog.new()
	other.load_file()
	check(other.fingerprint == catalog.fingerprint and other.ability_fingerprint("ability.marrow_lunge") == catalog.ability_fingerprint("ability.marrow_lunge"),
		"fingerprints_stable_across_instances")
	check(str(raw.get("provisional", "")).contains("provisional") or str(raw.get("provisional", "")).contains("placeholder"), "catalog_marked_provisional")

func _catalog_errors(mutate: Callable) -> Array[String]:
	var data: Dictionary = _fixture_data()
	mutate.call(data)
	var probe = Catalog.new()
	probe.load_data(data)
	return probe.errors

func _has_error(errors: Array[String], fragment: String) -> bool:
	return errors.any(func(e): return e.contains(fragment))

func test_catalog_validation() -> void:
	var cases := {
		"duplicate ability id": func(d): d.abilities.append(d.abilities[0].duplicate(true)),
		"grants unknown ability": func(d): d.items[0].grants.append("ability.missing"),
		"modifies unknown stat": func(d): d.items[1].modifiers.append({"stat": "luck", "op": "add", "value": 1}),
		"op must be add or mul": func(d): d.items[1].modifiers = [{"stat": "deflect_window", "op": "set", "value": -0.05}],
		"fits unknown slot": func(d): d.items[1].fits_slots = ["tail"],
		"cannot fit weapon slot": func(d): d.items[1].fits_slots = ["main_hand"],
		"without an explicit disadvantage": func(d): d.items[1].modifiers = []; d.items[1].excludes_tags = [],
		"names an owner": func(d): d.abilities[2]["owner"] = "enemy",
		"unknown key": func(d): d.abilities[0]["damage"] = 5,
		"invalid ability id": func(d): d.abilities[0].id = "Slash",
		"must define exactly the catalog stats": func(d): d.profiles[0].stats.erase("move_speed"),
		"unknown binding": func(d): d.abilities[0].binding = "kick",
		"that no item provides": func(d): d.abilities[0].requires_tags = ["wield.whip"],
		"must be a positive number": func(d): d.abilities[0].timing.windup = 0,
		"must be non-neutral": func(d): d.items[1].modifiers = [{"stat": "deflect_window", "op": "add", "value": 0}],
		"unsupported catalog schema": func(d): d.schema = "other",
	}
	for fragment in cases:
		var errors := _catalog_errors(cases[fragment])
		check(_has_error(errors, fragment), "catalog_rejects:" + fragment, errors)

## Player and enemy are the same data shape, validated and resolved by the same code.
func test_shared_compatibility() -> void:
	var player := _player()
	var soul := _soul()
	check(rules.validate(player).is_empty() and rules.validate(soul).is_empty(), "player_and_enemy_builds_valid")
	check(player.keys() == soul.keys(), "player_and_enemy_share_build_schema")
	var a := _resolved(player)
	var b := _resolved(soul)
	check(a.keys() == b.keys() and a.stats.keys() == b.stats.keys(), "player_and_enemy_share_resolved_schema")
	check(_ability(a, "attack.slash").fingerprint == _ability(b, "attack.slash").fingerprint, "shared_weapon_same_ability_definition")
	check(b.stats.max_posture == 100.0 and b.stats.move_speed == 2.7, "enemy_form_matches_courtyard_posture_and_movement")
	check(not player.has("abilities") and not soul.has("abilities"), "builds_store_no_ability_copies")
	# An enemy-only body part fits a player profile and vice versa: nothing is owner-gated.
	var swapped: Dictionary = rules.new_build("soul.as.duelist", "profile.duelist")
	swapped = rules.carry(swapped, "item.marrow_arm").build
	check(rules.equip(swapped, "item.marrow_arm", "right_arm").ok, "enemy_augment_fits_player_profile")

func test_identity() -> void:
	var lunge := "ability.marrow_lunge"
	var before = Catalog.digest(catalog.abilities[lunge])
	var result := Flow.run(catalog)
	check(result.ok, "flow_runs", result.errors)
	var identity: Dictionary = result.flow.identity
	var fp: String = catalog.ability_fingerprint(lunge)
	check(identity.enemy_fingerprint == fp and identity.ref_fingerprint == fp and identity.player_fingerprint == fp,
		"signature_fingerprint_preserved_enemy_ref_player", identity)
	check(Catalog.digest(catalog.abilities[lunge]) == before, "flow_does_not_mutate_definition")
	check(_ability(result.flow.step_2_corrupted_soul_build.resolved, "attack.slash").effective.windup == 0.62
		and _ability(result.flow.step_1_player_build.resolved, "attack.slash").effective.windup == 0.34
		and identity.enemy_effective.reach == identity.player_effective.reach, "wielder_changes_effective_not_definition")
	for key in Catalog.OWNER_KEYS:
		check(not catalog.abilities[lunge].has(key) and not catalog.items["item.marrow_arm"].has(key), "no_owner_field:" + key)

func test_build_validation() -> void:
	var base := _player()
	var cases := {
		"not_an_object": "build",
		"unknown_key": func(b): b["abilities"] = [],
		"missing_key": func(b): b.erase("carried"),
		"unsupported_schema": func(b): b.schema = "boneshed.build.v9",
		"invalid_build_id": func(b): b.build_id = "Player One",
		"catalog_version_mismatch": func(b): b.catalog_version = "0.0.9",
		"unknown_profile": func(b): b.profile = "profile.god",
		"unknown_slot": func(b): b.equipped["tail"] = "item.notched_sword",
		"invalid_item_id": func(b): b.equipped.main_hand = 7,
		"invalid_carried": func(b): b.carried = [1],
		"unknown_item": func(b): b.equipped.main_hand = "item.missing",
	}
	for code in cases:
		var candidate: Variant = base.duplicate(true)
		if cases[code] is Callable:
			cases[code].call(candidate)
		else:
			candidate = cases[code]
		var errors = rules.validate(candidate)
		check(code in _codes(errors), "build_rejects:" + code, errors)
		check(not rules.resolve(candidate).ok and rules.resolve(candidate).resolved.is_empty(), "invalid_build_never_resolves:" + code)

func test_invalid_combinations() -> void:
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"main_hand": "item.marrow_arm"}))), "augment_in_weapon_slot_rejected")
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"left_arm": "item.marrow_arm"}))), "right_arm_augment_in_left_arm_rejected")
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"right_arm": "item.notched_sword"}))), "weapon_in_body_slot_rejected")
	var two_handed := _raw_equipped({"main_hand": "item.test_greatsword", "right_arm": "item.marrow_arm"})
	var errors = fixture_rules.validate(two_handed)
	check(errors.size() == 1 and errors[0].code == "excluded_tag" and errors[0].tag == "grip.two_handed"
		and errors[0].conflicts_with == "item.test_greatsword", "marrow_arm_rejects_two_handed_grip", errors)
	var build := _fixture_build(["item.test_greatsword", "item.marrow_arm"], [["main_hand", "item.test_greatsword"]])
	var attempt: Dictionary = fixture_rules.equip(build, "item.marrow_arm", "right_arm")
	check(not attempt.ok and "excluded_tag" in _codes(attempt.errors) and attempt.build == build, "equip_conflict_rejected_build_unchanged")
	var brace := _raw_equipped({"left_arm": "item.test_brace"})
	check("missing_required_tag" in _codes(fixture_rules.validate(brace)), "augment_requirement_enforced")
	var naked_lunge := _raw_equipped({"left_arm": "item.test_left_marrow_arm"})
	check(fixture_rules.validate(naked_lunge).is_empty(), "item_supplies_own_ability_requirement")

func _raw_equipped_real(equipped: Dictionary) -> Dictionary:
	var build: Dictionary = rules.new_build("fixture.raw", "profile.duelist")
	build.equipped = equipped
	return build

func test_duplicates_and_conflicts() -> void:
	var twin := _raw_equipped({"left_arm": "item.test_left_marrow_arm", "right_arm": "item.marrow_arm"})
	var errors = fixture_rules.validate(twin)
	check(errors.size() == 1 and errors[0].code == "duplicate_ability" and errors[0].ability == "ability.marrow_lunge"
		and errors[0].slots == ["left_arm", "right_arm"], "duplicate_signature_ability_rejected", errors)
	var clash := _raw_equipped({"left_arm": "item.test_hook_arm", "right_arm": "item.marrow_arm"})
	errors = fixture_rules.validate(clash)
	check(errors.size() == 1 and errors[0].code == "binding_conflict" and errors[0].binding == "special"
		and errors[0].abilities == ["ability.test_hook", "ability.marrow_lunge"], "binding_conflict_rejected", errors)
	var reversed := {"right_arm": "item.marrow_arm", "left_arm": "item.test_hook_arm"}
	check(fixture_rules.validate(_raw_equipped(reversed)) == errors, "conflict_errors_independent_of_insertion_order")

func test_equip_unequip() -> void:
	var empty: Dictionary = rules.new_build("player.eq", "profile.duelist")
	check(rules.validate(empty).is_empty() and _resolved(empty).abilities.is_empty(), "empty_build_valid_without_abilities")
	var not_carried: Dictionary = rules.equip(empty, "item.notched_sword", "main_hand")
	check(not not_carried.ok and "not_carried" in _codes(not_carried.errors), "equip_requires_carried_item")
	var carried: Dictionary = rules.carry(empty, "item.notched_sword").build
	var snapshot := Catalog.canonical_json(carried)
	var equipped: Dictionary = rules.equip(carried, "item.notched_sword", "main_hand")
	check(equipped.ok and equipped.build.equipped == {"main_hand": "item.notched_sword"} and equipped.build.carried.is_empty(), "equip_moves_item_to_slot")
	check(Catalog.canonical_json(carried) == snapshot, "equip_does_not_mutate_input")
	check("unknown_slot" in _codes(rules.equip(carried, "item.notched_sword", "tail").errors), "equip_unknown_slot_rejected")
	var again: Dictionary = rules.carry(equipped.build, "item.notched_sword").build
	check("slot_occupied" in _codes(rules.equip(again, "item.notched_sword", "main_hand").errors), "equip_occupied_slot_rejected")
	var removed: Dictionary = rules.unequip(equipped.build, "main_hand")
	check(removed.ok and Catalog.canonical_json(removed.build) == snapshot, "unequip_round_trip_restores_build")
	check("slot_empty" in _codes(rules.unequip(removed.build, "main_hand").errors), "unequip_empty_slot_rejected")
	var armed := _player()
	check(_ability(_resolved(rules.unequip(armed, "main_hand").build), "attack.slash").is_empty(), "unequip_removes_granted_abilities")
	var braced := _fixture_build(["item.marrow_arm", "item.test_brace"], [["right_arm", "item.marrow_arm"], ["left_arm", "item.test_brace"]])
	var blocked: Dictionary = fixture_rules.unequip(braced, "right_arm")
	check(not blocked.ok and "missing_required_tag" in _codes(blocked.errors) and blocked.build == braced, "unequip_blocked_by_dependent_item", blocked.errors)
	check(fixture_rules.unequip(fixture_rules.unequip(braced, "left_arm").build, "right_arm").ok, "unequip_dependent_first_succeeds")

func test_stats_and_tradeoffs() -> void:
	var player := _resolved(_player())
	check(player.stats == {"max_health": 100.0, "max_posture": 100.0, "move_speed": 5.5, "deflect_window": 0.16,
		"guard_chip": 0.12, "posture_recovery_rate": 12.0, "posture_recovery_delay": 1.5, "deflect_posture": 42.0, "windup_scale": 1.0, "recovery_scale": 1.0}, "player_base_stats_match_courtyard", player.stats)
	var slash: Dictionary = _ability(player, "attack.slash").effective
	check(slash.windup == 0.34 and slash.active == 0.16 and slash.recovery == 0.45 and slash.health_damage == 18.0, "slash_matches_courtyard_light_attack")
	var flow: Dictionary = Flow.run(catalog).flow
	var change: Dictionary = flow.step_7_change
	check(change.abilities_added == ["ability.marrow_lunge"] and change.abilities_removed.is_empty(), "augment_adds_signature_capability")
	check(change.stats.is_empty() and flow.step_6_resolved_player.stats.deflect_window == 0.16,
		"augment_preserves_deflection_window", change.stats)
	check(_ability(flow.step_6_resolved_player, "ability.marrow_lunge").effective.reach > slash.reach, "signature_reach_exceeds_slash")
	var tradeoff: Dictionary = change.new_tradeoffs[0]
	check(tradeoff.item == "item.marrow_arm" and tradeoff.advantages.size() == 1 and tradeoff.disadvantages.size() == 1, "tradeoff_explicit_both_sides", tradeoff)
	check(catalog.tradeoffs("item.notched_sword").disadvantages.is_empty(), "ordinary_weapon_has_no_forced_drawback")
	var braced := _resolved(_fixture_build(["item.marrow_arm", "item.test_brace"], [["right_arm", "item.marrow_arm"], ["left_arm", "item.test_brace"]]), fixture_rules)
	check(braced.stats.max_posture == 130.0 and braced.stats.move_speed == 4.4 and braced.stats.deflect_window == 0.16, "add_then_mul_modifiers", braced.stats)
	check(braced.stat_sources.move_speed == [{"item": "item.test_brace", "op": "mul", "value": 0.8}], "stat_sources_traceable")
	var crushed := _resolved(_raw_equipped({"left_arm": "item.test_crush_arm"}), fixture_rules)
	check(crushed.stats.max_posture == 1.0, "stats_clamped_to_catalog_range", crushed.stats)
	var a := _raw_equipped({"left_arm": "item.test_brace", "right_arm": "item.marrow_arm"})
	var b := _raw_equipped({"right_arm": "item.marrow_arm", "left_arm": "item.test_brace"})
	check(_resolved(a, fixture_rules).fingerprint == _resolved(b, fixture_rules).fingerprint, "resolution_independent_of_slot_insertion_order")

func test_salvage() -> void:
	var player := _player()
	var soul := _soul()
	var reward: Dictionary = salvage.rewards(Salvage.victory_fixture("fixture.marrow_duel", player, soul))
	check(reward.ok and reward.refs.size() == 1 and reward.refs[0].item == "item.marrow_arm", "victory_yields_signature_ref", reward)
	var ref: Dictionary = reward.refs[0]
	check(ref.keys().size() == Salvage.REF_KEYS.size() and not ref.has("stats") and not ref.has("modifiers") and not ref.has("timing"),
		"ref_is_reference_not_copy")
	check(ref.abilities == [{"id": "ability.marrow_lunge", "fingerprint": catalog.ability_fingerprint("ability.marrow_lunge")}]
		and ref.item_fingerprint == catalog.item_fingerprint("item.marrow_arm"), "ref_points_at_catalog_definitions")
	check(salvage.rewards(Salvage.victory_fixture("fixture.marrow_duel", player, soul)).refs == reward.refs, "rewards_deterministic")
	check(salvage.rewards(Salvage.victory_fixture("fixture.other_duel", player, soul)).refs[0].ref_id != ref.ref_id, "ref_id_scoped_to_encounter")
	var defeat := Salvage.victory_fixture("fixture.marrow_duel", player, soul)
	defeat.outcome = "defeat"
	check("no_victory" in _codes(salvage.rewards(defeat).errors) and salvage.rewards(defeat).refs.is_empty(), "defeat_yields_nothing")
	check("self_defeat" in _codes(salvage.rewards(Salvage.victory_fixture("fixture.x", soul, soul)).errors), "self_defeat_yields_nothing")
	var broken_soul := soul.duplicate(true)
	broken_soul.equipped.right_arm = "item.missing"
	check("invalid_defeated_build" in _codes(salvage.rewards(Salvage.victory_fixture("fixture.x", player, broken_soul)).errors), "invalid_defeated_build_yields_nothing")
	check(salvage.rewards(Salvage.victory_fixture("fixture.x", soul, player)).refs.is_empty(), "ordinary_gear_not_salvaged")
	check(salvage.verify(ref).is_empty(), "genuine_ref_verifies")
	var tampering := {
		"fingerprint_mismatch": func(r): r.item_fingerprint = "0000000000000000",
		"ability_mismatch": func(r): r.abilities.append({"id": "attack.heavy_slash", "fingerprint": catalog.ability_fingerprint("attack.heavy_slash")}),
		"ref_id_mismatch": func(r): r.source.slot = "left_arm",
		"not_salvageable": func(r): r.item = "item.notched_sword",
		"unknown_item": func(r): r.item = "item.missing",
		"catalog_version_mismatch": func(r): r.catalog_version = "9.9.9",
		"invalid_ref": func(r): r["bonus"] = true,
	}
	for code in tampering:
		var forged: Dictionary = ref.duplicate(true)
		tampering[code].call(forged)
		var attempt: Dictionary = salvage.acquire(player, forged)
		check(not attempt.ok and code in _codes(attempt.errors) and attempt.build == player, "tampered_ref_rejected:" + code, attempt.errors)
	var acquired: Dictionary = salvage.acquire(player, ref)
	check(acquired.ok and acquired.build.carried == ["item.marrow_arm"] and acquired.build.equipped == player.equipped, "acquire_carries_item_only")
	var equipped: Dictionary = rules.equip(acquired.build, "item.marrow_arm", "right_arm")
	check(equipped.ok and _ability(_resolved(equipped.build), "ability.marrow_lunge").source == {"slot": "right_arm", "item": "item.marrow_arm"},
		"salvaged_item_equips_and_grants_ability")
	var stale = Catalog.new()
	var changed: Dictionary = raw.duplicate(true)
	changed.abilities[2].hit.reach = 3.6
	stale.load_data(changed)
	var stale_salvage = Salvage.new(stale, Rules.new(stale))
	check("ability_mismatch" in _codes(stale_salvage.verify(ref)), "ref_rejected_after_definition_changes")

func test_serialization() -> void:
	for build in [_player(), _soul(), rules.new_build("empty.build", "profile.duelist")]:
		var text: String = rules.to_json(build)
		var loaded: Dictionary = rules.from_json(text)
		check(loaded.ok and rules.to_json(loaded.build) == text, "json_round_trip:" + build.build_id)
		check(_resolved(loaded.build).fingerprint == _resolved(build).fingerprint, "round_trip_resolves_identically:" + build.build_id)
	check(rules.to_json(_soul()) == '{"build_id":"soul.marrow_swordsman","carried":[],"catalog_version":"0.3.0","equipped":{"main_hand":"item.notched_sword","right_arm":"item.marrow_arm"},"profile":"profile.corrupted_swordsman","schema":"boneshed.build.v0"}',
		"canonical_build_json_exact")
	check("malformed_json" in _codes(rules.from_json("{not json").errors), "malformed_json_rejected")
	check("not_an_object" in _codes(rules.from_json("[1, 2]").errors), "non_object_json_rejected")
	var injected = rules.to_json(_player()).replace('"carried":[]', '"carried":[],"script":"res://evil.gd"')
	check("unknown_key" in _codes(rules.from_json(injected).errors) and rules.from_json(injected).build.is_empty(), "unexpected_fields_rejected")
	var object_like = rules.to_json(_player()).replace('"profile.duelist"', '{"type":"Resource","path":"res://x.tres"}')
	check("unknown_profile" in _codes(rules.from_json(object_like).errors), "object_shaped_values_rejected")
	var ref: Dictionary = salvage.rewards(Salvage.victory_fixture("fixture.marrow_duel", _player(), _soul())).refs[0]
	check(salvage.verify(JSON.parse_string(Catalog.canonical_json(ref))).is_empty(), "ref_survives_json_round_trip")

func test_reproducibility() -> void:
	var first := Flow.run(catalog)
	var other = Catalog.new()
	other.load_file()
	var second := Flow.run(other)
	check(JSON.stringify(first.flow, "\t", true) == JSON.stringify(second.flow, "\t", true), "flow_identical_across_instances")
	var committed := FileAccess.get_file_as_string(EXAMPLE_FLOW)
	check(committed == JSON.stringify(first.flow, "\t", true) + "\n", "flow_matches_committed_example")
	var resolved := _resolved(_soul())
	var expected_fingerprint: String = resolved.fingerprint
	resolved.erase("fingerprint")
	check(Catalog.digest(resolved) == expected_fingerprint, "resolved_fingerprint_reproducible")

## The library must stay standalone: no live combat, scene, AI or worldgen references.
func test_isolation() -> void:
	for path in LIBRARY_SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		var clean := true
		for forbidden in ["res://scripts/combat", "res://scripts/characters", "res://scripts/ai", "res://scenes", "courtyard", "worldgen", "CombatState", "Node"]:
			clean = clean and not source.contains(forbidden)
		check(clean, "library_isolated:" + path.get_file())
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "playable_entrypoint_selected")
