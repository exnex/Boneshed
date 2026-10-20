extends SceneTree
## Deterministic tests for the shared build / salvage prototype. Prints one JSON line
## per check plus a summary, like the other suites. Exit code 1 on any failure.
## Independent of combat, the courtyard and worldgen.

const Catalog := preload("res://scripts/builds/build_catalog.gd")
const Rules := preload("res://scripts/builds/build_rules.gd")
const Salvage := preload("res://scripts/builds/salvage.gd")
const Migration := preload("res://scripts/builds/build_migration.gd")
const Flow := preload("res://scripts/qa/salvage_flow_fixture.gd")
const EXAMPLE_FLOW := "res://docs/salvage/examples/flow.json"
## Catalog 0.3.0 courtyard builds exactly as recorded on main before the slot change.
const LEGACY_BUILDS := "res://scripts/qa/fixtures/builds_v0_3_0.json"
const CURRENT_BUILDS := "res://data/builds/salvage_courtyard.json"
const LIBRARY_SCRIPTS := ["res://scripts/builds/build_catalog.gd", "res://scripts/builds/build_rules.gd", "res://scripts/builds/salvage.gd", "res://scripts/builds/build_migration.gd"]

## Test-only definitions layered onto the real catalog. Never shipped as content.
const FIXTURE_ABILITIES := [
	{"id": "ability.test_hook", "name": "Test Hook", "binding": "special", "tags": ["melee"], "requires_tags": ["body.hook"],
		"module": "module.test", "telegraph": "test", "timing": {"windup": 0.5, "active": 0.1, "recovery": 0.5},
		"hit": {"health_damage": 10, "guard_posture": 10, "posture_damage": 18, "reach": 2.0, "width": 1.0}},
]
const FIXTURE_ITEMS := [
	{"id": "item.test_greatsword", "name": "Test Greatsword", "category": "weapon", "fits_slots": ["hand_r", "hand_l"],
		"provides_tags": ["wield.blade", "grip.two_handed"], "requires_tags": [], "excludes_tags": [],
		"grants": ["attack.slash", "attack.heavy_slash"], "modifiers": [], "salvageable": false, "notes": "test",
		"weapon": {"class": "blade", "grip": "two_handed", "reach": "long", "weight": "heavy",
			"handling": {"length": 2.1, "mass": 3.2, "balance": 0.3}, "defense": {"guard": true, "deflect": true}}},
	{"id": "item.test_buckler", "name": "Test Buckler", "category": "weapon", "fits_slots": ["hand_l"],
		"provides_tags": ["guard.shield"], "requires_tags": [], "excludes_tags": [], "grants": [], "modifiers": [],
		"salvageable": false, "notes": "test",
		"weapon": {"class": "shield", "grip": "one_handed", "reach": "short", "weight": "light",
			"handling": {"length": 0.5, "mass": 2.0, "balance": 0.0}, "defense": {"guard": true, "deflect": true}}},
	{"id": "item.test_dagger", "name": "Test Dagger", "category": "weapon", "fits_slots": ["hand_r", "hand_l"],
		"provides_tags": ["wield.dagger"], "requires_tags": [], "excludes_tags": [], "grants": [], "modifiers": [],
		"salvageable": false, "notes": "test",
		"weapon": {"class": "blade", "grip": "one_handed", "reach": "short", "weight": "light",
			"handling": {"length": 0.45, "mass": 0.4, "balance": 0.1}, "defense": {"guard": false, "deflect": true}}},
	{"id": "item.test_right_marrow_arm", "name": "Test Right Marrow Arm", "category": "body_mod", "fits_slots": ["arm_r"],
		"provides_tags": ["body.marrow_arm"], "requires_tags": [], "excludes_tags": [], "grants": ["ability.marrow_lunge"],
		"modifiers": [{"stat": "deflect_window", "op": "add", "value": -0.05}], "salvageable": true, "notes": "test",
		"anatomy": {"part": "arm", "grip": false}},
	{"id": "item.test_hook_arm", "name": "Test Hook Arm", "category": "body_mod", "fits_slots": ["arm_r"],
		"provides_tags": ["body.hook"], "requires_tags": [], "excludes_tags": [], "grants": ["ability.test_hook"],
		"modifiers": [{"stat": "move_speed", "op": "add", "value": -0.5}], "salvageable": true, "notes": "test",
		"anatomy": {"part": "arm", "grip": false}},
	{"id": "item.test_brace", "name": "Test Brace", "category": "body_mod", "fits_slots": ["arm_r"],
		"provides_tags": [], "requires_tags": ["body.marrow_arm"], "excludes_tags": [], "grants": [],
		"modifiers": [{"stat": "max_posture", "op": "add", "value": 30}, {"stat": "move_speed", "op": "mul", "value": 0.8}],
		"salvageable": false, "notes": "test", "anatomy": {"part": "arm", "grip": true}},
	{"id": "item.test_crush_arm", "name": "Test Crush Arm", "category": "body_mod", "fits_slots": ["arm_r"],
		"provides_tags": [], "requires_tags": [], "excludes_tags": [], "grants": [],
		"modifiers": [{"stat": "max_posture", "op": "add", "value": -500}], "salvageable": false, "notes": "test",
		"anatomy": {"part": "arm", "grip": true}},
	# Replacement arm that keeps a working hand: anatomy changes, grips do not.
	{"id": "item.test_grafted_arm", "name": "Test Grafted Arm", "category": "body_mod", "fits_slots": ["arm_l", "arm_r"],
		"provides_tags": ["body.grafted"], "requires_tags": [], "excludes_tags": [], "grants": [],
		"modifiers": [{"stat": "move_speed", "op": "add", "value": -0.3}], "salvageable": true, "notes": "test",
		"anatomy": {"part": "arm", "grip": true}},
	# A body modification that is explicitly also a natural weapon. It grants no attack.
	{"id": "item.test_bone_claw", "name": "Test Bone Claw", "category": "body_mod", "fits_slots": ["arm_r"],
		"provides_tags": ["body.claw"], "requires_tags": [], "excludes_tags": [], "grants": [], "modifiers": [],
		"salvageable": true, "notes": "test",
		"anatomy": {"part": "arm", "grip": false, "natural_weapon": {"class": "natural", "reach": "short", "weight": "light",
			"handling": {"length": 0.6, "mass": 1.0, "balance": 0.5}, "defense": {"guard": false, "deflect": false}}}},
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
	test_grips_and_mounts()
	test_weapon_versus_anatomical_replacement()
	test_body_modifications_are_not_weapons()
	test_unusual_anatomy()
	test_duplicates_and_conflicts()
	test_equip_unequip()
	test_stats_and_tradeoffs()
	test_salvage()
	test_serialization()
	test_reproducibility()
	test_migration()
	test_isolation()
	print(JSON.stringify({"suite": "builds", "summary": true, "passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)

func _fixture_data() -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	data.abilities.append_array(FIXTURE_ABILITIES.duplicate(true))
	data.items.append_array(FIXTURE_ITEMS.duplicate(true))
	# The test hook is another special-binding body-mod ability, so it is legacy too.
	data.legacy_abilities.append("ability.test_hook")
	return data

## A four-armed fixture body: a second, lower arm pair with its own paired grips.
## Proves grips, limbs and pairs are data rather than an assumed two hands.
func _four_armed_data() -> Dictionary:
	var data := _fixture_data()
	data.slots.append_array([
		{"id": "hand_lower_r", "kind": "grip", "side": "right", "limb": "arm_lower_r", "pair": "hand_lower_l"},
		{"id": "hand_lower_l", "kind": "grip", "side": "left", "limb": "arm_lower_l", "pair": "hand_lower_r"},
		{"id": "arm_lower_r", "kind": "body", "side": "right", "part": "arm"},
		{"id": "arm_lower_l", "kind": "body", "side": "left", "part": "arm"}])
	for item in data.items:
		if item.id in ["item.test_greatsword", "item.test_buckler"]:
			item.fits_slots.append_array(["hand_lower_r", "hand_lower_l"])
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
	check(catalog.version == "0.4.0" and catalog.fingerprint.length() == 16, "catalog_version_and_fingerprint")
	check(catalog.items["item.notched_sword"].category == "weapon" and catalog.items["item.marrow_arm"].category == "body_mod"
		and catalog.items["item.marrow_arm"].fits_slots == ["arm_l"] and catalog.items["item.marrow_arm"].anatomy == {"part": "arm", "grip": false},
		"marrow_arm_is_a_handless_left_arm_body_modification")
	check(catalog.hands_required("item.notched_sword") == 1 and catalog.hands_required("item.marrow_arm") == 0
		and catalog.slots.hand_r.limb == "arm_r" and catalog.slots.hand_l.limb == "arm_l" and catalog.slots.hand_r.pair == "hand_l",
		"grips_belong_to_limbs_and_pair_explicitly")
	check(catalog.legacy_abilities == ["ability.marrow_lunge"], "marrow_lunge_is_the_only_legacy_ability")
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
		"cannot fit grip slot": func(d): d.items[1].fits_slots = ["hand_r"],
		"cannot fit body slot": func(d): d.items[0].fits_slots = ["arm_r"],
		"without an explicit disadvantage": func(d): d.items[1].modifiers = []; d.items[1].excludes_tags = []; d.items[1].anatomy.grip = true,
		"granting non-legacy ability": func(d): d.items[1].grants = ["attack.slash"],
		"weapon granting legacy ability": func(d): d.items[0].grants = ["ability.marrow_lunge"],
		"special binding but is not a legacy ability": func(d): d.legacy_abilities = [],
		"legacy ability 'ability.gone' is unknown": func(d): d.legacy_abilities.append("ability.gone"),
		"has unknown grip": func(d): d.items[0].weapon.grip = "three_handed",
		"has invalid class": func(d): d.items[0].weapon["class"] = "natural",
		"has unknown reach class": func(d): d.items[0].weapon.reach = "infinite",
		"handling.balance must be within": func(d): d.items[0].weapon.handling.balance = 1.5,
		"handling length and mass must be positive": func(d): d.items[0].weapon.handling.mass = 0,
		"weapon handling.length must be a non-negative": func(d): d.items[0].weapon.handling.length = -1,
		"defense values must be true or false": func(d): d.items[0].weapon.defense.guard = 1,
		"weapon must be an object": func(d): d.items[0].erase("weapon"),
		"anatomy must be an object": func(d): d.items[1].erase("anatomy"),
		"has unknown key 'weapon'": func(d): d.items[1]["weapon"] = d.items[0].weapon.duplicate(true),
		"anatomy grip must be true or false": func(d): d.items[1].anatomy.grip = "no",
		"natural_weapon has invalid class": func(d): d.items[1].anatomy["natural_weapon"] = {"class": "blade", "reach": "long", "weight": "light",
			"handling": {"length": 1.0, "mass": 1.0, "balance": 0.5}, "defense": {"guard": false, "deflect": false}},
		"is two-handed but grip 'hand_t' has no pair": func(d): d.slots.append({"id": "hand_t", "kind": "grip", "side": "center", "limb": "arm_r", "pair": ""}); d.items[0].weapon.grip = "two_handed"; d.items[0].fits_slots = ["hand_t"],
		"replaces part 'arm', not slot 'tail'": func(d): d.equipment_classes.body_parts.append("tail"); d.slots.append({"id": "tail", "kind": "body", "side": "center", "part": "tail"}); d.items[1].fits_slots = ["tail"],
		"pair must be a different grip that pairs back": func(d): d.slots[1].pair = "",
		"limb must be a body slot": func(d): d.slots[0].limb = "hand_l",
		"pairs with a grip on the same limb": func(d): d.slots[1].limb = "arm_r",
		"has unknown kind": func(d): d.slots[0].kind = "socket",
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
	var on_player: Dictionary = rules.equip(swapped, "item.marrow_arm", "arm_l")
	check(on_player.ok, "enemy_augment_fits_player_profile")
	# Same item, same rules: the player's resolved arm equals the corrupted soul's.
	var soul_arm: Array = b.equipment.body.filter(func(p): return p.slot == "arm_l")
	var player_arm: Array = _resolved(on_player.build).equipment.body.filter(func(p): return p.slot == "arm_l")
	check(soul_arm == player_arm and soul_arm[0].item == "item.marrow_arm" and not soul_arm[0].grip, "same_body_modification_rules_for_player_and_enemy")
	check(a.equipment.weapons == b.equipment.weapons and a.equipment.weapons[0].side == "right", "same_weapon_rules_for_player_and_enemy")

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
		"invalid_item_id": func(b): b.equipped.hand_r = 7,
		"invalid_carried": func(b): b.carried = [1],
		"unknown_item": func(b): b.equipped.hand_r = "item.missing",
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
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"hand_r": "item.marrow_arm"}))), "body_mod_in_grip_rejected")
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"arm_r": "item.marrow_arm"}))), "left_marrow_arm_in_right_arm_rejected")
	check("wrong_slot" in _codes(rules.validate(_raw_equipped_real({"arm_r": "item.notched_sword"}))), "weapon_in_body_slot_rejected")
	var two_handed := _raw_equipped({"hand_r": "item.test_greatsword", "arm_l": "item.marrow_arm"})
	var errors = fixture_rules.validate(two_handed)
	check(errors == [{"code": "grip_unavailable", "item": "item.test_greatsword", "slot": "hand_l", "limb": "arm_l", "blocked_by": "item.marrow_arm"}],
		"marrow_arm_rejects_two_handed_grip", errors)
	var build := _fixture_build(["item.test_greatsword", "item.marrow_arm"], [["hand_r", "item.test_greatsword"]])
	var attempt: Dictionary = fixture_rules.equip(build, "item.marrow_arm", "arm_l")
	check(not attempt.ok and "grip_unavailable" in _codes(attempt.errors) and attempt.build == build, "equip_conflict_rejected_build_unchanged")
	var handless := _raw_equipped_real({"hand_l": "item.notched_sword", "arm_l": "item.marrow_arm"})
	check(rules.validate(handless) == [{"code": "grip_unavailable", "item": "item.notched_sword", "slot": "hand_l", "limb": "arm_l", "blocked_by": "item.marrow_arm"}],
		"weapon_cannot_be_held_by_handless_limb")
	var sword_left: Dictionary = _fixture_build(["item.notched_sword", "item.marrow_arm"], [["hand_l", "item.notched_sword"]])
	var blocked: Dictionary = fixture_rules.equip(sword_left, "item.marrow_arm", "arm_l")
	check(not blocked.ok and blocked.build == sword_left and "grip_unavailable" in _codes(blocked.errors), "replacing_the_holding_arm_rejected_atomically")
	var brace := _raw_equipped({"arm_r": "item.test_brace"})
	check("missing_required_tag" in _codes(fixture_rules.validate(brace)), "augment_requirement_enforced")
	var naked_lunge := _raw_equipped({"arm_r": "item.test_right_marrow_arm"})
	check(fixture_rules.validate(naked_lunge).is_empty(), "item_supplies_own_ability_requirement")

## One- and two-handed grips, shields and occupied mounts.
func test_grips_and_mounts() -> void:
	var great := _resolved(_raw_equipped({"hand_r": "item.test_greatsword"}), fixture_rules)
	check(great.equipment.weapons.size() == 1 and great.equipment.weapons[0].grips == ["hand_r", "hand_l"]
		and great.equipment.grips.map(func(g): return g.held_by) == ["item.test_greatsword", "item.test_greatsword"], "two_handed_weapon_occupies_paired_grip", great.equipment)
	var occupied: Array = fixture_rules.validate(_raw_equipped({"hand_r": "item.test_greatsword", "hand_l": "item.test_buckler"}))
	check(occupied == [{"code": "grip_occupied", "item": "item.test_greatsword", "slot": "hand_l", "conflicts_with": "item.test_buckler"}], "two_handed_conflicts_with_off_hand_item", occupied)
	var twice: Array = fixture_rules.validate(_raw_equipped({"hand_r": "item.test_greatsword", "hand_l": "item.test_greatsword"}))
	check(_codes(twice) == ["grip_occupied", "grip_occupied"], "two_handed_weapon_recorded_in_both_grips_rejected", twice)
	var held := _fixture_build(["item.test_greatsword", "item.test_buckler"], [["hand_r", "item.test_greatsword"]])
	var shield_attempt: Dictionary = fixture_rules.equip(held, "item.test_buckler", "hand_l")
	check(not shield_attempt.ok and shield_attempt.build == held and "grip_occupied" in _codes(shield_attempt.errors), "occupied_pair_grip_rejects_equip_atomically")
	var sword_and_board := _resolved(_raw_equipped({"hand_r": "item.notched_sword", "hand_l": "item.test_buckler"}), fixture_rules)
	check(not sword_and_board.is_empty() and sword_and_board.equipment.weapons.map(func(w): return [w.item, w.side, w["class"], w.grip])
		== [["item.notched_sword", "right", "blade", "one_handed"], ["item.test_buckler", "left", "shield", "one_handed"]], "one_handed_weapon_with_shield")
	check(sword_and_board.equipment.capabilities.weapon == ["guard.shield", "wield.blade"] and sword_and_board.equipment.capabilities.body.is_empty(), "weapon_capabilities_separate_from_body")
	var dual := _raw_equipped({"hand_r": "item.notched_sword", "hand_l": "item.test_dagger"})
	check(fixture_rules.validate(dual).is_empty(), "two_one_handed_weapons_share_the_hands")
	check(not fixture_rules.validate(_raw_equipped({"hand_r": "item.notched_sword", "hand_l": "item.notched_sword"})).is_empty(), "duplicate_weapon_abilities_still_rejected")
	var marrow := _resolved(_soul())
	check(marrow.equipment.grips == [{"slot": "hand_r", "limb": "arm_r", "side": "right", "available": true, "held_by": "item.notched_sword"},
		{"slot": "hand_l", "limb": "arm_l", "side": "left", "available": false, "held_by": ""}], "marrow_soul_grips_resolved", marrow.equipment.grips)
	check(marrow.equipment.body.map(func(p): return [p.slot, p.item, p.grip]) == [["arm_r", "", true], ["arm_l", "item.marrow_arm", false]]
		and marrow.equipment.weapons.map(func(w): return [w.item, w.slot, w.side]) == [["item.notched_sword", "hand_r", "right"]], "marrow_left_sword_right_resolved")
	check(marrow.equipment.weapons[0].handling == {"length": 1.8, "mass": 1.4, "balance": 0.25} and marrow.equipment.weapons[0].reach == "medium"
		and marrow.equipment.weapons[0].defense == {"guard": true, "deflect": true}, "weapon_physical_profile_resolved_for_future_combat")

## Weapons swap within a grip and leave anatomy alone; body modifications swap a part
## and change which grips exist, leaving weapons alone.
func test_weapon_versus_anatomical_replacement() -> void:
	var armed := _fixture_build(["item.notched_sword", "item.test_dagger", "item.marrow_arm", "item.test_grafted_arm"], [["hand_r", "item.notched_sword"]])
	var before := _resolved(armed, fixture_rules)
	var swapped: Dictionary = fixture_rules.replace(armed, "item.test_dagger", "hand_r")
	var after_weapon := _resolved(swapped.build, fixture_rules)
	check(swapped.ok and swapped.build.equipped == {"hand_r": "item.test_dagger"} and "item.notched_sword" in swapped.build.carried
		and after_weapon.equipment.body == before.equipment.body and after_weapon.abilities.is_empty(), "weapon_replacement_changes_grip_not_anatomy")
	var grafted: Dictionary = fixture_rules.equip(armed, "item.marrow_arm", "arm_l")
	var after_body := _resolved(grafted.build, fixture_rules)
	check(grafted.ok and after_body.equipment.weapons == before.equipment.weapons and after_body.equipment.grips[1].available == false
		and after_body.equipment.body[1].item == "item.marrow_arm", "anatomical_replacement_changes_part_and_grips_not_weapons")
	var regrown: Dictionary = fixture_rules.replace(grafted.build, "item.test_grafted_arm", "arm_l")
	check(regrown.ok and regrown.build.equipped.arm_l == "item.test_grafted_arm" and "item.marrow_arm" in regrown.build.carried
		and _resolved(regrown.build, fixture_rules).equipment.grips[1].available, "replacing_a_body_mod_restores_the_grip_it_provides")
	var both_hands: Dictionary = fixture_rules.equip(regrown.build, "item.test_dagger", "hand_l")
	check(both_hands.ok, "grafted_arm_with_a_hand_can_hold_a_weapon")
	check(not fixture_rules.replace(armed, "item.missing", "hand_r").ok and not fixture_rules.replace(armed, "item.test_dagger", "tail").ok, "replace_requires_carried_item_and_known_slot")
	var wrong: Dictionary = fixture_rules.replace(armed, "item.marrow_arm", "hand_r")
	check(not wrong.ok and wrong.build == armed and "wrong_slot" in _codes(wrong.errors), "replace_body_mod_into_grip_rejected_atomically")

## Body modifications grant no attack unless explicitly declared; only the catalog's
## legacy demonstration (Marrow Lunge) is a body-mod ability.
func test_body_modifications_are_not_weapons() -> void:
	var grafted := _resolved(_raw_equipped({"arm_l": "item.test_grafted_arm"}), fixture_rules)
	check(grafted.abilities.is_empty() and grafted.equipment.weapons.is_empty() and grafted.equipment.capabilities.body == ["body.grafted"], "body_mod_is_not_automatically_an_attack")
	var claw := _resolved(_raw_equipped({"arm_r": "item.test_bone_claw", "hand_l": "item.notched_sword"}), fixture_rules)
	var natural: Array = claw.equipment.weapons.filter(func(w): return w.natural)
	check(natural.size() == 1 and natural[0].item == "item.test_bone_claw" and natural[0].slot == "arm_r" and natural[0].grips.is_empty()
		and natural[0]["class"] == "natural" and claw.equipment.body[0].natural_weapon, "natural_weapon_is_explicit_body_property")
	check(claw.abilities.map(func(a): return a.source.item) == ["item.notched_sword", "item.notched_sword"], "natural_weapon_grants_no_special_attack")
	var lunge := _ability(_resolved(_soul()), "ability.marrow_lunge")
	check(lunge.source == {"slot": "arm_l", "item": "item.marrow_arm"} and lunge.binding == "special" and "ability.marrow_lunge" in catalog.legacy_abilities
		and not _resolved(_soul()).equipment.body[1].natural_weapon, "marrow_lunge_is_isolated_legacy_grant")

## A second arm pair with its own grips needs only new slot data.
func test_unusual_anatomy() -> void:
	var four = Catalog.new()
	check(four.load_data(_four_armed_data()), "four_armed_fixture_catalog_valid", four.errors)
	var four_rules = Rules.new(four)
	var build: Dictionary = four_rules.new_build("fixture.four", "profile.duelist")
	build.equipped = {"hand_r": "item.notched_sword", "arm_l": "item.marrow_arm", "hand_lower_r": "item.test_greatsword"}
	check("duplicate_ability" in _codes(four_rules.validate(build)), "extra_hands_do_not_bypass_ability_rules")
	build.equipped = {"hand_r": "item.notched_sword", "arm_l": "item.marrow_arm", "hand_lower_l": "item.test_buckler"}
	var resolved: Dictionary = four_rules.resolve(build)
	check(resolved.ok and resolved.resolved.equipment.grips.size() == 4
		and resolved.resolved.equipment.grips.filter(func(g): return g.available).size() == 3, "four_arms_resolve_four_grips", resolved.errors)
	build.equipped = {"arm_l": "item.marrow_arm", "hand_lower_r": "item.test_greatsword"}
	check(four_rules.validate(build).is_empty() and four_rules.resolve(build).resolved.equipment.weapons[0].grips == ["hand_lower_r", "hand_lower_l"],
		"two_handed_grip_on_lower_pair_while_upper_left_is_handless")
	build.equipped = {"hand_r": "item.test_greatsword", "arm_l": "item.marrow_arm"}
	check(_codes(four_rules.validate(build)) == ["grip_unavailable"], "two_handed_needs_its_declared_pair_not_any_free_hand")

func _raw_equipped_real(equipped: Dictionary) -> Dictionary:
	var build: Dictionary = rules.new_build("fixture.raw", "profile.duelist")
	build.equipped = equipped
	return build

func test_duplicates_and_conflicts() -> void:
	var twin := _raw_equipped({"arm_l": "item.marrow_arm", "arm_r": "item.test_right_marrow_arm"})
	var errors = fixture_rules.validate(twin)
	check(errors.size() == 1 and errors[0].code == "duplicate_ability" and errors[0].ability == "ability.marrow_lunge"
		and errors[0].slots == ["arm_r", "arm_l"], "duplicate_signature_ability_rejected", errors)
	var clash := _raw_equipped({"arm_r": "item.test_hook_arm", "arm_l": "item.marrow_arm"})
	errors = fixture_rules.validate(clash)
	check(errors.size() == 1 and errors[0].code == "binding_conflict" and errors[0].binding == "special"
		and errors[0].abilities == ["ability.test_hook", "ability.marrow_lunge"], "binding_conflict_rejected", errors)
	var reversed := {"arm_l": "item.marrow_arm", "arm_r": "item.test_hook_arm"}
	check(fixture_rules.validate(_raw_equipped(reversed)) == errors, "conflict_errors_independent_of_insertion_order")

func test_equip_unequip() -> void:
	var empty: Dictionary = rules.new_build("player.eq", "profile.duelist")
	check(rules.validate(empty).is_empty() and _resolved(empty).abilities.is_empty(), "empty_build_valid_without_abilities")
	var not_carried: Dictionary = rules.equip(empty, "item.notched_sword", "hand_r")
	check(not not_carried.ok and "not_carried" in _codes(not_carried.errors), "equip_requires_carried_item")
	var carried: Dictionary = rules.carry(empty, "item.notched_sword").build
	var snapshot := Catalog.canonical_json(carried)
	var equipped: Dictionary = rules.equip(carried, "item.notched_sword", "hand_r")
	check(equipped.ok and equipped.build.equipped == {"hand_r": "item.notched_sword"} and equipped.build.carried.is_empty(), "equip_moves_item_to_slot")
	check(Catalog.canonical_json(carried) == snapshot, "equip_does_not_mutate_input")
	check("unknown_slot" in _codes(rules.equip(carried, "item.notched_sword", "tail").errors), "equip_unknown_slot_rejected")
	var again: Dictionary = rules.carry(equipped.build, "item.notched_sword").build
	check("slot_occupied" in _codes(rules.equip(again, "item.notched_sword", "hand_r").errors), "equip_occupied_slot_rejected")
	var removed: Dictionary = rules.unequip(equipped.build, "hand_r")
	check(removed.ok and Catalog.canonical_json(removed.build) == snapshot, "unequip_round_trip_restores_build")
	check("slot_empty" in _codes(rules.unequip(removed.build, "hand_r").errors), "unequip_empty_slot_rejected")
	var armed := _player()
	check(_ability(_resolved(rules.unequip(armed, "hand_r").build), "attack.slash").is_empty(), "unequip_removes_granted_abilities")
	var braced := _fixture_build(["item.marrow_arm", "item.test_brace"], [["arm_l", "item.marrow_arm"], ["arm_r", "item.test_brace"]])
	var blocked: Dictionary = fixture_rules.unequip(braced, "arm_l")
	check(not blocked.ok and "missing_required_tag" in _codes(blocked.errors) and blocked.build == braced, "unequip_blocked_by_dependent_item", blocked.errors)
	check(fixture_rules.unequip(fixture_rules.unequip(braced, "arm_r").build, "arm_l").ok, "unequip_dependent_first_succeeds")

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
	check(tradeoff.item == "item.marrow_arm" and tradeoff.advantages.size() == 1 and tradeoff.disadvantages == [{"kind": "removes_grip", "part": "arm"}], "tradeoff_explicit_both_sides", tradeoff)
	check(catalog.tradeoffs("item.notched_sword").disadvantages.is_empty(), "ordinary_weapon_has_no_forced_drawback")
	var braced := _resolved(_fixture_build(["item.marrow_arm", "item.test_brace"], [["arm_l", "item.marrow_arm"], ["arm_r", "item.test_brace"]]), fixture_rules)
	check(braced.stats.max_posture == 130.0 and braced.stats.move_speed == 4.4 and braced.stats.deflect_window == 0.16, "add_then_mul_modifiers", braced.stats)
	check(braced.stat_sources.move_speed == [{"item": "item.test_brace", "op": "mul", "value": 0.8}], "stat_sources_traceable")
	var crushed := _resolved(_raw_equipped({"arm_r": "item.test_crush_arm"}), fixture_rules)
	check(crushed.stats.max_posture == 1.0, "stats_clamped_to_catalog_range", crushed.stats)
	var a := _raw_equipped({"arm_r": "item.test_brace", "arm_l": "item.marrow_arm"})
	var b := _raw_equipped({"arm_l": "item.marrow_arm", "arm_r": "item.test_brace"})
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
	broken_soul.equipped.arm_l = "item.missing"
	check("invalid_defeated_build" in _codes(salvage.rewards(Salvage.victory_fixture("fixture.x", player, broken_soul)).errors), "invalid_defeated_build_yields_nothing")
	check(salvage.rewards(Salvage.victory_fixture("fixture.x", soul, player)).refs.is_empty(), "ordinary_gear_not_salvaged")
	check(salvage.verify(ref).is_empty(), "genuine_ref_verifies")
	var tampering := {
		"fingerprint_mismatch": func(r): r.item_fingerprint = "0000000000000000",
		"ability_mismatch": func(r): r.abilities.append({"id": "attack.heavy_slash", "fingerprint": catalog.ability_fingerprint("attack.heavy_slash")}),
		"ref_id_mismatch": func(r): r.source.slot = "arm_r",
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
	var equipped: Dictionary = rules.equip(acquired.build, "item.marrow_arm", "arm_l")
	check(equipped.ok and _ability(_resolved(equipped.build), "ability.marrow_lunge").source == {"slot": "arm_l", "item": "item.marrow_arm"},
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
	check(rules.to_json(_soul()) == '{"build_id":"soul.marrow_swordsman","carried":[],"catalog_version":"0.4.0","equipped":{"arm_l":"item.marrow_arm","hand_r":"item.notched_sword"},"profile":"profile.corrupted_swordsman","schema":"boneshed.build.v0"}',
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

## Catalog 0.3.0 builds upgrade deterministically; the Marrow Arm moves to the left.
func test_migration() -> void:
	var migration = Migration.new(rules)
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_BUILDS))
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CURRENT_BUILDS))
	var snapshot := Catalog.canonical_json(legacy)
	for actor in ["player", "enemy"]:
		var result: Dictionary = migration.migrate(legacy[actor])
		check(result.ok and Catalog.canonical_json(result.build) == Catalog.canonical_json(current[actor]), "legacy_0_3_0_build_migrates_exactly:" + actor, result)
	check(migration.migrate(legacy.enemy).changes == [{"code": "relocated", "item": "item.marrow_arm", "from": "arm_r", "to": "arm_l"}]
		and migration.migrate(legacy.player).changes.is_empty(), "migration_reports_marrow_relocation")
	check(Catalog.canonical_json(legacy) == snapshot, "migration_does_not_mutate_input")
	var passthrough: Dictionary = migration.migrate(current.enemy)
	check(passthrough.ok and passthrough.build == current.enemy and passthrough.changes.is_empty(), "current_build_passes_through")
	var conflict: Dictionary = legacy.enemy.duplicate(true)
	conflict.equipped["left_arm"] = "item.marrow_arm"
	check("migration_conflict" in _codes(migration.migrate(conflict).errors), "legacy_relocation_conflict_rejected")
	var future: Dictionary = legacy.enemy.duplicate(true)
	future.catalog_version = "0.1.0"
	check("unsupported_catalog_version" in _codes(migration.migrate(future).errors), "unknown_catalog_version_rejected")
	var unknown: Dictionary = legacy.player.duplicate(true)
	unknown.equipped["tail"] = "item.notched_sword"
	check("unknown_legacy_slot" in _codes(migration.migrate(unknown).errors), "unknown_legacy_slot_rejected")

## The library must stay standalone: no live combat, scene, AI or worldgen references.
func test_isolation() -> void:
	for path in LIBRARY_SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		var clean := true
		for forbidden in ["res://scripts/combat", "res://scripts/characters", "res://scripts/ai", "res://scenes", "courtyard", "worldgen", "CombatState", "Node"]:
			clean = clean and not source.contains(forbidden)
		check(clean, "library_isolated:" + path.get_file())
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "playable_entrypoint_selected")
