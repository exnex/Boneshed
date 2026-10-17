extends SceneTree
## Deterministic tests for the keyword WorldBlueprint prototype. Prints one JSON line per
## check plus a summary, like combat_tests.gd. Exit code 1 on any failure.

const Gen := preload("res://scripts/worldgen/blueprint_generator.gd")
const Library := preload("res://scripts/worldgen/keyword_library.gd")
const SeedStream := preload("res://scripts/worldgen/seed_stream.gd")
const EXAMPLES_INDEX := "res://docs/worldgen/examples/index.json"
const SAMPLE_SETS := [
	["smoldering", "frozen", "ossuary"],
	["drowned", "hollow", "cathedral"],
	["forgotten", "hollow", "profane"],
	["tempest", "frozen", "towering"],
	["lightless", "sunken", "hollow"],
	["barren", "tempest", "gilded"],
]

var passed := 0
var failed := 0
var gen

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	var record := {"suite": "worldgen", "check": label, "passed": condition}
	if not condition and detail != null:
		record["detail"] = detail
	print(JSON.stringify(record))

func bp(words: Array, world_seed := 1001) -> Dictionary:
	return gen.generate(words, world_seed).blueprint

func run() -> void:
	gen = Gen.new()
	check(gen.library.errors.is_empty(), "library_valid", gen.library.errors)
	check(gen.library.keywords.size() >= 12 and gen.library.keywords.size() <= 20, "vocabulary_is_small_sample")
	test_streams()
	test_repeatability()
	test_seed_variation()
	test_different_words()
	test_ranges()
	test_interactions()
	test_invalid_inputs()
	test_serialization()
	test_isolation()
	print(JSON.stringify({"suite": "worldgen", "summary": true, "passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)

func test_streams() -> void:
	# Reference values from an independent Python FNV-1a / Mulberry32 implementation;
	# mulberry32(0) also matches the published JavaScript reference.
	check(SeedStream.hash32("") == 0x811c9dc5 and SeedStream.hash32("boneshed") == 0x994185c5
		and SeedStream.hash32("Δ hollow") == 0x60215956, "fnv1a_reference_vectors")
	var stream := SeedStream.new("boneshed")
	var values := []
	for i in 4:
		values.append(stream.next_u32())
	check(values == [2210467239, 3789241776, 3087234170, 1163615024], "mulberry32_reference_vectors", values)
	var zero := SeedStream.new("")
	zero.state = 0
	check(zero.next_u32() == 1144304738, "mulberry32_matches_published_zero_seed")
	var unit := SeedStream.new("range")
	var in_range := true
	for i in 1000:
		var f := unit.next_float()
		in_range = in_range and f >= 0.0 and f < 1.0
	check(in_range, "stream_float_in_unit_interval")

func test_repeatability() -> void:
	var other = Gen.new()
	var same := true
	for words in SAMPLE_SETS:
		same = same and Gen.canonical_json(bp(words)) == Gen.canonical_json(other.generate(words, 1001).blueprint)
	check(same, "same_words_same_seed_identical_across_instances")
	check(Gen.canonical_json(bp(SAMPLE_SETS[0], -42)) == Gen.canonical_json(bp(SAMPLE_SETS[0], -42)), "negative_seed_repeatable")

func test_seed_variation() -> void:
	var jitter := float(gen.library.config.axis_jitter)
	for words in SAMPLE_SETS:
		var base := bp(words, 0)
		var fingerprints := {}
		var featured := {}
		var identity_stable := true
		var anchors_stable := true
		var jitter_bounded := true
		var axes_moved := false
		for world_seed in range(0, 32):
			var b := bp(words, world_seed)
			fingerprints[b.fingerprint] = true
			featured[JSON.stringify(b.variation.featured)] = true
			identity_stable = identity_stable and b.identity_fingerprint == base.identity_fingerprint
			for pool in Library.THEME_POOLS:
				anchors_stable = anchors_stable and b.variation.featured[pool][0] == base.identity.theme_tables[pool][0].id
			for axis in Library.AXES:
				var delta := absf(float(b.variation.axes[axis].value) - float(b.identity.axes[axis]))
				jitter_bounded = jitter_bounded and delta <= jitter + 0.0011
				axes_moved = axes_moved or delta > 0.01
		var name := "-".join(words)
		check(fingerprints.size() == 32, "seeds_give_distinct_blueprints:" + name)
		check(identity_stable, "identity_independent_of_seed:" + name)
		check(anchors_stable, "anchor_themes_independent_of_seed:" + name)
		check(jitter_bounded and axes_moved, "seed_jitter_present_and_bounded:" + name)
		check(featured.size() >= 3, "seeds_vary_supporting_themes:" + name, featured.size())

func test_different_words() -> void:
	var biomes := {}
	var identities := {}
	for words in SAMPLE_SETS:
		var b := bp(words)
		biomes[b.identity.biome.primary] = true
		identities[b.identity_fingerprint] = true
	check(identities.size() == SAMPLE_SETS.size(), "different_words_distinct_identity")
	check(biomes.size() >= 5, "contrasting_words_mostly_distinct_biomes", biomes.keys())
	var a := bp(["drowned", "hollow", "cathedral"], 7)
	var b := bp(["barren", "smoldering", "towering"], 7)
	check(a.streams.terrain != b.streams.terrain, "different_words_same_seed_distinct_streams")

## Exhaustive over every unordered combination (560) at one seed, plus a few seeds.
func test_ranges() -> void:
	var ids: Array = gen.library.keywords.keys()
	ids.sort()
	var problems := []
	var count := 0
	var band: Array = gen.library.config.encounter_density_band
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			for k in range(j + 1, ids.size()):
				var result: Dictionary = gen.generate([ids[i], ids[j], ids[k]], count * 7919)
				count += 1
				if not result.ok:
					problems.append(["not_ok", ids[i], ids[j], ids[k]])
					continue
				_check_ranges(result.blueprint, band, problems)
	check(count == 560, "all_combinations_generated", count)
	check(problems.is_empty(), "all_values_within_contract", problems.slice(0, 5))

func _check_ranges(b: Dictionary, band: Array, problems: Array) -> void:
	var where: String = b.address
	for axis in Library.AXES:
		if absf(b.identity.axes[axis]) > 1.0 or absf(b.variation.axes[axis].value) > 1.0:
			problems.append([where, "axis", axis])
		var v: float = b.variation.axes[axis].regional_variance
		if v < 0.0 or v > 1.0:
			problems.append([where, "variance", axis])
	for group in b.generation:
		for key in b.generation[group]:
			var value = b.generation[group][key]
			if value is float and (value < 0.0 or value > 1.0):
				problems.append([where, group, key, value])
	var density: float = b.generation.challenge.encounter_density
	if density < float(band[0]) - 0.001 or density > float(band[1]) + 0.001:
		problems.append([where, "density_band", density])
	for pool in Library.THEME_POOLS:
		var total := 0.0
		for entry in b.identity.theme_tables[pool]:
			total += entry.weight
		if absf(total - 1.0) > 0.02:
			problems.append([where, "table_sum", pool, total])
		var featured: Array = b.variation.featured[pool]
		if featured.size() != int(gen.library.config.featured_counts[pool]) or _has_duplicates(featured):
			problems.append([where, "featured", pool])
	var atmosphere: Array = b.variation.atmosphere
	if atmosphere.size() != int(gen.library.config.atmosphere_count) or _has_duplicates(atmosphere):
		problems.append([where, "atmosphere"])
	if b.provisional != true:
		problems.append([where, "provisional_flag"])

func test_interactions() -> void:
	var conflict := bp(["smoldering", "frozen", "ossuary"])
	check(_interaction_ids(conflict).has("thaw_cycle"), "conflict_rule_fires_for_fire_and_cold")
	check(_tension_axes(conflict).has("temperature"), "opposed_words_create_tension")
	var temperature_variance: float = conflict.variation.axes.temperature.regional_variance
	var age_variance: float = conflict.variation.axes.age.regional_variance
	check(temperature_variance >= 0.6 and age_variance <= 0.15, "contested_axis_gets_patchwork_variance", [temperature_variance, age_variance])
	check(conflict.generation.terrain.patchwork.any(func(p): return p.axis == "temperature"), "patchwork_exposed_to_terrain")

	# Emergent content: neither word carries black_ice, only their pairing.
	var icy := bp(["frozen", "drowned", "hollow"])
	var dry := bp(["frozen", "barren", "hollow"])
	check(_theme_ids(icy, "hazards").has("black_ice") and not _theme_ids(dry, "hazards").has("black_ice"), "synergy_adds_emergent_hazard")

	# Agreement saturates: stronger than any single push but below the additive sum.
	var dark := bp(["lightless", "sunken", "hollow"])
	var light: float = dark.identity.axes.light
	check(light < -0.8 and light > -1.0, "agreement_amplifies_but_saturates", light)

	# Senses depend on the company a word keeps, never on the seed.
	check(_sense(bp(["drowned", "hollow", "cathedral"]), "hollow") == "cavern", "hollow_reads_as_cavern_near_water")
	check(_sense(bp(["forgotten", "hollow", "profane"]), "hollow") == "emptied", "hollow_reads_as_emptied_near_memory")
	check(_sense(bp(["forgotten", "hollow", "profane"]), "forgotten") == "unremembered", "forgotten_reads_as_unremembered")
	check(_sense(bp(["gilded", "forgotten", "ossuary"]), "forgotten") == "ancient", "forgotten_reads_as_ancient_near_bone")
	var tie := bp(["barren", "tempest", "gilded"])
	check(_sense(tie, "gilded") == "treasure" and tie.identity.senses[2].resolution == "tie_primary", "sense_tie_keeps_primary")
	var senses_seed_free := true
	for world_seed in 16:
		senses_seed_free = senses_seed_free and _sense(bp(["forgotten", "hollow", "profane"], world_seed), "hollow") == "emptied"
	check(senses_seed_free, "sense_choice_independent_of_seed")

	# Position matters for emphasis, not for which interactions exist.
	var forward := bp(["profane", "gilded", "hallowed"])
	var reverse := bp(["hallowed", "gilded", "profane"])
	check(forward.identity_fingerprint != reverse.identity_fingerprint, "order_changes_identity")
	check(_interaction_ids(forward) == _interaction_ids(reverse), "order_keeps_interaction_set")
	check(forward.identity.tensions[0].dominant == "hallowed" and reverse.identity.tensions[0].dominant == "profane", "last_word_dominates_close_conflict")

	# A rule needs its tags from two different words: tempest alone has storm and water.
	var custom = Library.new()
	custom.load_files()
	custom.interactions.append({"id": "single_word_probe", "kind": "synergy", "requires": ["storm", "water"],
		"summary": "probe", "effects": {"hazards": {"probe": 1.0}}})
	var probe: Dictionary = Gen.new(custom).generate(["tempest", "barren", "thorned"], 1).blueprint
	check(not _interaction_ids(probe).has("single_word_probe"), "single_word_cannot_trigger_interaction")
	var paired: Dictionary = Gen.new(custom).generate(["tempest", "drowned", "thorned"], 1).blueprint
	check(_interaction_ids(paired).has("single_word_probe"), "two_words_trigger_interaction")

func test_invalid_inputs() -> void:
	var unknown: Dictionary = gen.generate(["frozen", "glimmering", "hollow"], 1)
	check(not unknown.ok and unknown.blueprint.is_empty() and _codes(unknown) == ["unknown_keyword"] and unknown.errors[0].position == 2, "unknown_keyword_rejected")
	check(_codes(gen.generate(["frozen", "frozen", "hollow"], 1)) == ["duplicate_keyword"], "duplicate_keyword_rejected")
	check(_codes(gen.generate(["frozen", " FROZEN ", "hollow"], 1)) == ["duplicate_keyword"], "duplicate_after_normalization_rejected")
	check(_codes(gen.generate(["frozen", "hollow"], 1)) == ["wrong_keyword_count"], "two_keywords_rejected")
	check(_codes(gen.generate(["frozen", "hollow", "drowned", "barren"], 1)) == ["wrong_keyword_count"], "four_keywords_rejected")
	check(_codes(gen.generate([], 1)) == ["wrong_keyword_count"], "no_keywords_rejected")
	check(_codes(gen.generate(["frozen", 7, "hollow"], 1)) == ["invalid_keyword_type"], "non_text_keyword_rejected")
	check(_codes(gen.generate(["frozen", "  ", "hollow"], 1)) == ["empty_keyword"], "empty_keyword_rejected")
	check(_codes(gen.generate(["nope", "nada", "hollow"], 1)) == ["unknown_keyword", "unknown_keyword"], "every_problem_reported")
	var messy: Dictionary = gen.generate([" Frozen", "DROWNED", "hollow"], 9)
	var clean: Dictionary = gen.generate(["frozen", "drowned", "hollow"], 9)
	check(messy.ok and messy.warnings.size() == 2 and Gen.canonical_json(messy.blueprint) == Gen.canonical_json(clean.blueprint), "case_and_space_normalized_with_warning")
	var broken = Library.new()
	broken.load_files("res://data/worldgen/missing.json")
	var refused: Dictionary = Gen.new(broken).generate(["frozen", "drowned", "hollow"], 1)
	check(not refused.ok and _codes(refused) == ["invalid_library"], "invalid_library_refuses_generation")

func test_serialization() -> void:
	var stable := true
	var no_ints := true
	var fingerprint_ok := true
	for words in SAMPLE_SETS:
		var b := bp(words)
		var text := Gen.canonical_json(b)
		stable = stable and Gen.canonical_json(JSON.parse_string(text)) == text
		no_ints = no_ints and not _contains_int(b)
		var copy := b.duplicate(true)
		copy.erase("fingerprint")
		fingerprint_ok = fingerprint_ok and SeedStream.hex32(SeedStream.hash32(Gen.canonical_json(copy))) == b.fingerprint
	check(stable, "json_round_trip_is_byte_identical")
	check(no_ints, "blueprint_has_no_ints_so_parse_cannot_change_types")
	check(fingerprint_ok, "fingerprint_matches_canonical_json")
	# Golden files: committed demo outputs must regenerate exactly.
	var index = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES_INDEX)) if FileAccess.file_exists(EXAMPLES_INDEX) else null
	check(index is Array and index.size() >= 8, "committed_examples_present")
	var mismatches := []
	if index is Array:
		for entry in index:
			var committed = JSON.parse_string(FileAccess.get_file_as_string("res://docs/worldgen/examples/" + entry.file))
			var fresh := bp(entry.keywords, int(entry.world_seed))
			if Gen.canonical_json(committed) != Gen.canonical_json(fresh):
				mismatches.append(entry.file)
	check(mismatches.is_empty(), "committed_examples_regenerate_exactly", mismatches)

func test_isolation() -> void:
	var b := bp(SAMPLE_SETS[1])
	var seeds := {}
	for domain in b.streams:
		seeds[b.streams[domain]] = true
	check(seeds.size() == Gen.GENERATOR_DOMAINS.size(), "domain_streams_distinct")
	check(b.streams.terrain == Gen.stream_seed(SAMPLE_SETS[1], 1001, "terrain"), "domain_stream_reproducible")
	# Consuming more randomness for one purpose must not disturb the others.
	var greedy = Library.new()
	greedy.load_files()
	greedy.config.featured_counts.hazards = 6
	greedy.config.axis_jitter = gen.library.config.axis_jitter
	var g: Dictionary = Gen.new(greedy).generate(SAMPLE_SETS[1], 1001).blueprint
	check(g.variation.axes == b.variation.axes and g.variation.featured.encounters == b.variation.featured.encounters
		and g.variation.atmosphere == b.variation.atmosphere and g.streams == b.streams, "extra_draws_do_not_leak_between_streams")
	check(g.variation.featured.hazards.slice(0, 3) == b.variation.featured.hazards, "extra_draws_extend_not_reshuffle")

func _codes(result: Dictionary) -> Array:
	return result.errors.map(func(e): return e.code)

func _interaction_ids(b: Dictionary) -> Array:
	return b.identity.interactions.map(func(i): return i.id)

func _tension_axes(b: Dictionary) -> Array:
	return b.identity.tensions.map(func(t): return t.axis)

func _theme_ids(b: Dictionary, pool: String) -> Array:
	return b.identity.theme_tables[pool].map(func(t): return t.id)

func _sense(b: Dictionary, keyword: String) -> String:
	for s in b.identity.senses:
		if s.keyword == keyword:
			return s.sense
	return ""

func _has_duplicates(values: Array) -> bool:
	var seen := {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false

func _contains_int(value: Variant) -> bool:
	if value is int:
		return true
	if value is Dictionary:
		for key in value:
			if _contains_int(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_int(item):
				return true
	return false
