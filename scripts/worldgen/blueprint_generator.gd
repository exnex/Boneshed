extends RefCounted
## Turns three keyword ids and a world seed into a provisional WorldBlueprint.
##
## Two layers, kept separate on purpose:
## - identity: senses, resolved axes, biome, tensions, interactions and theme tables.
##   Depends only on the words (and their order), never on the seed.
## - variation: bounded axis jitter, featured theme picks, atmosphere descriptors and
##   the derived generation parameters. Seeded, one named stream per purpose.
## Downstream generators receive their own stream seeds and never share randomness.
## All mechanics and numbers are prototype values awaiting human approval.

const Library := preload("res://scripts/worldgen/keyword_library.gd")
const SeedStream := preload("res://scripts/worldgen/seed_stream.gd")

const SCHEMA_VERSION := "0.1.0"
const STREAM_NAMESPACE := "boneshed.worldgen.v0"
## Stream seeds handed to future generators. Adding a domain must not alter others.
const GENERATOR_DOMAINS := ["terrain", "structure", "encounters", "hazards", "discoveries", "atmosphere"]

var library

func _init(source_library = null) -> void:
	library = source_library
	if library == null:
		library = Library.new()
		library.load_files()

## Returns {"ok", "errors", "warnings", "blueprint"}. On any error the blueprint is empty;
## invalid input never produces a partial world.
func generate(words: Array, world_seed: int) -> Dictionary:
	var result := {"ok": false, "errors": [], "warnings": [], "blueprint": {}}
	if not library.errors.is_empty():
		result.errors.append({"code": "invalid_library", "message": "; ".join(library.errors)})
		return result
	var ids := _validate_words(words, result)
	if not result.errors.is_empty():
		return result
	result.blueprint = _build(ids, world_seed)
	result.ok = true
	return result

func _validate_words(words: Array, result: Dictionary) -> Array:
	var ids := []
	if words.size() != 3:
		result.errors.append({"code": "wrong_keyword_count", "message": "expected exactly 3 keywords, got %d" % words.size()})
		return ids
	var seen := {}
	for i in words.size():
		var raw = words[i]
		var position := i + 1
		if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:
			result.errors.append({"code": "invalid_keyword_type", "position": position, "message": "keyword must be text"})
			continue
		var id := String(raw).strip_edges().to_lower()
		if id.is_empty():
			result.errors.append({"code": "empty_keyword", "position": position, "message": "keyword is empty"})
			continue
		if id != String(raw):
			result.warnings.append({"code": "normalized_keyword", "position": position, "value": String(raw), "normalized": id})
		if not library.has_keyword(id):
			result.errors.append({"code": "unknown_keyword", "position": position, "value": id, "message": "not in the vocabulary"})
		elif seen.has(id):
			result.errors.append({"code": "duplicate_keyword", "position": position, "value": id, "message": "each keyword may appear once"})
		seen[id] = true
		ids.append(id)
	return ids

func _build(ids: Array, world_seed: int) -> Dictionary:
	var config: Dictionary = library.config
	var weights: Array = config.position_weights
	var senses := _resolve_senses(ids, weights)
	var contributions := []
	for i in 3:
		contributions.append({"weight": float(weights[i]), "effects": senses[i].sense, "source": ids[i]})
	var interactions := _match_interactions(ids, senses, weights)
	for interaction in interactions:
		contributions.append({"weight": interaction.strength, "effects": interaction.rule.effects, "source": interaction.rule.id})

	var resolved := _resolve_axes(contributions, config)
	var identity_axes: Dictionary = resolved.values
	var theme_tables := {}
	var theme_raw_totals := {}
	for pool in Library.THEME_POOLS:
		var table := _theme_table(contributions, pool)
		theme_tables[pool] = table.entries
		theme_raw_totals[pool] = table.raw_total

	var identity := {
		"senses": senses.map(func(s): return s.record),
		"axes": _rounded_dict(identity_axes),
		"biome": _rank_biomes(identity_axes),
		"tensions": resolved.tensions,
		"interactions": interactions.map(func(m): return {
			"id": m.rule.id, "kind": m.rule.kind, "summary": m.rule.summary,
			"strength": _r(m.strength), "sources": m.sources}),
		"theme_tables": theme_tables,
	}

	var seed_root := "%s|%s|%d" % [STREAM_NAMESPACE, ",".join(ids), world_seed]
	var axis_stream := SeedStream.new(seed_root + "|blueprint.axes")
	var jitter := float(config.axis_jitter)
	var final_axes := {}
	var variation_axes := {}
	for axis in Library.AXES:
		final_axes[axis] = clampf(identity_axes[axis] + axis_stream.range_float(-jitter, jitter), -1.0, 1.0)
		variation_axes[axis] = {"value": _r(final_axes[axis]), "regional_variance": _r(resolved.variance[axis])}
	var featured := {}
	for pool in Library.THEME_POOLS:
		featured[pool] = _feature(theme_tables[pool], int(config.featured_counts[pool]), SeedStream.new(seed_root + "|blueprint." + pool))
	var streams := {}
	for domain in GENERATOR_DOMAINS:
		streams[domain] = stream_seed(ids, world_seed, domain)

	var blueprint := {
		"schema_version": SCHEMA_VERSION,
		"data_version": library.data_version,
		"provisional": true,
		"address": " ".join(ids.map(func(id): return String(id).capitalize())),
		"input": {"keywords": ids, "world_seed": str(world_seed)},
		"identity": identity,
		"identity_fingerprint": SeedStream.hex32(SeedStream.hash32(canonical_json(identity))),
		"variation": {
			"axes": variation_axes,
			"featured": featured,
			"atmosphere": _atmosphere(senses, interactions, weights, int(config.atmosphere_count), SeedStream.new(seed_root + "|blueprint.atmosphere")),
		},
		"generation": _generation_parameters(final_axes, resolved.tensions, resolved.variance, theme_raw_totals.hazards, config),
		"streams": streams,
	}
	blueprint["fingerprint"] = SeedStream.hex32(SeedStream.hash32(canonical_json(blueprint)))
	return blueprint

## Seed for a downstream generator's own stream. Depends on words, seed and domain only.
static func stream_seed(ids: Array, world_seed: int, domain: String) -> String:
	return SeedStream.hex32(SeedStream.hash32("%s|%s|%d|domain.%s" % [STREAM_NAMESPACE, ",".join(ids), world_seed, domain]))

static func canonical_json(data: Variant) -> String:
	return JSON.stringify(data, "", true)

## A sense resonates when its listed tags appear among any sense of the OTHER keywords,
## weighted by their position. Ties keep the first-listed (primary) sense. The seed is
## never consulted, so a word's meaning is stable for a given combination.
func _resolve_senses(ids: Array, weights: Array) -> Array:
	var context := []
	for id in ids:
		var tags := {}
		for sense in library.keywords[id].senses:
			for tag in sense.tags:
				tags[tag] = true
		context.append(tags)
	var resolved := []
	for i in 3:
		var options: Array = library.keywords[ids[i]].senses
		var scores := {}
		var best := 0
		var best_score := -1.0
		for s in options.size():
			var score := 0.0
			for j in 3:
				if j != i:
					for tag in options[s].get("resonates_with", []):
						if context[j].has(tag):
							score += float(weights[j])
			scores[options[s].id] = _r(score)
			if score > best_score + 0.000001:
				best = s
				best_score = score
		var how := "only_sense"
		if options.size() > 1:
			how = "context"
			for s in options.size():
				if s != best and absf(float(scores[options[s].id]) - best_score) < 0.000001:
					how = "tie_primary"
		resolved.append({"sense": options[best], "record": {
			"keyword": ids[i], "position": str(i + 1), "sense": options[best].id,
			"gloss": options[best].gloss, "resolution": how, "scores": scores}})
	return resolved

## Each rule needs its tags supplied by DIFFERENT keywords, so a single word cannot
## trigger an interaction on its own. Strength is the mean weight of the matched positions.
func _match_interactions(ids: Array, senses: Array, weights: Array) -> Array:
	var matched := []
	for rule in library.interactions:
		var best := _assign(rule.requires, 0, senses, [])
		if best.is_empty():
			continue
		var strength := 0.0
		var sources := []
		for position in best:
			strength += float(weights[position])
		best.sort()
		for position in best:
			sources.append(ids[position])
		matched.append({"rule": rule, "strength": strength / best.size(), "sources": sources})
	matched.sort_custom(func(a, b): return a.rule.id < b.rule.id)
	return matched

## Highest-position assignment of required tags to distinct keywords, or [] if none.
func _assign(requires: Array, index: int, senses: Array, used: Array) -> Array:
	if index == requires.size():
		return used.duplicate()
	var best := []
	var best_sum := -1
	for position in range(2, -1, -1):
		if position in used or not requires[index] in senses[position].sense.tags:
			continue
		var candidate := _assign(requires, index + 1, senses, used + [position])
		if not candidate.is_empty():
			var total: int = candidate.reduce(func(acc, p): return acc + p, 0)
			if total > best_sum:
				best = candidate
				best_sum = total
	return best

## Per axis, positive and negative pushes combine separately as 1 - prod(1 - c), so
## agreement saturates toward the pole instead of summing past it. When both sides are
## strong the axis is contested: recorded as a tension resolved by regional patchwork.
func _resolve_axes(contributions: Array, config: Dictionary) -> Dictionary:
	var values := {}
	var variance := {}
	var tensions := []
	var threshold := float(config.contest_threshold)
	for axis in Library.AXES:
		var keep_positive := 1.0
		var keep_negative := 1.0
		for contribution in contributions:
			var push: float = float(contribution.effects.get("axes", {}).get(axis, 0.0)) * contribution.weight
			if push > 0.0:
				keep_positive *= 1.0 - push
			elif push < 0.0:
				keep_negative *= 1.0 + push
		var positive := 1.0 - keep_positive
		var negative := 1.0 - keep_negative
		values[axis] = positive - negative
		variance[axis] = clampf(0.1 + 1.2 * minf(positive, negative), 0.0, 1.0)
		if positive >= threshold and negative >= threshold:
			var poles: Array = config.axis_poles[axis]
			var dominant := "balanced"
			if values[axis] >= 0.1:
				dominant = poles[1]
			elif values[axis] <= -0.1:
				dominant = poles[0]
			tensions.append({"axis": axis, "poles": poles, "dominant": dominant,
				"strength": _r(minf(positive, negative)), "resolution": "patchwork"})
	return {"values": values, "variance": variance, "tensions": tensions}

func _theme_table(contributions: Array, pool: String) -> Dictionary:
	var totals := {}
	for contribution in contributions:
		var themes: Dictionary = contribution.effects.get(pool, {})
		for theme in themes:
			totals[theme] = totals.get(theme, 0.0) + float(themes[theme]) * contribution.weight
	var raw_total := 0.0
	var entries := []
	for theme in totals:
		raw_total += totals[theme]
		entries.append({"id": theme, "weight": totals[theme]})
	entries.sort_custom(func(a, b): return a.weight > b.weight or (a.weight == b.weight and a.id < b.id))
	for entry in entries:
		entry.weight = _r(entry.weight / raw_total)
	return {"entries": entries, "raw_total": raw_total}

## The top theme is always featured (identity anchor); the rest are seeded weighted
## picks without replacement, so seeds vary the supporting cast but not the headline.
func _feature(table: Array, count: int, stream) -> Array:
	if table.is_empty():
		return []
	var picks := [table[0].id]
	var pool := table.slice(1)
	while picks.size() < count and not pool.is_empty():
		var index: int = stream.pick_weighted(pool)
		picks.append(pool[index].id)
		pool.remove_at(index)
	return picks

## One descriptor from each triggered interaction comes first (so combinations read as
## more than their parts), then seeded picks from the words, weighted by position.
func _atmosphere(senses: Array, interactions: Array, weights: Array, count: int, stream) -> Array:
	var chosen := []
	for interaction in interactions:
		var options: Array = interaction.rule.effects.get("atmosphere", [])
		if not options.is_empty() and chosen.size() < count:
			chosen.append(options[int(stream.next_float() * options.size())])
	var pool := []
	for i in 3:
		for descriptor in senses[i].sense.get("atmosphere", []):
			if not descriptor in chosen:
				pool.append({"id": descriptor, "weight": float(weights[i])})
	while chosen.size() < count and not pool.is_empty():
		var index: int = stream.pick_weighted(pool)
		chosen.append(pool[index].id)
		pool.remove_at(index)
	return chosen

func _rank_biomes(axes: Dictionary) -> Dictionary:
	var ranked := []
	for biome in library.biomes:
		var prototype: Dictionary = biome.prototype
		var distance := 0.0
		for axis in prototype:
			distance += pow(axes[axis] - float(prototype[axis]), 2)
		ranked.append({"id": biome.id, "label": biome.label, "affinity": 1.0 - sqrt(distance / prototype.size()) / 2.0})
	ranked.sort_custom(func(a, b): return a.affinity > b.affinity or (a.affinity == b.affinity and a.id < b.id))
	var top := ranked.slice(0, 3)
	for entry in top:
		entry.affinity = _r(entry.affinity)
	return {"primary": top[0].id, "secondary": top[1].id, "ranking": top}

## Normalized 0..1 hints for future generators. Formulas are provisional placeholders
## chosen to be monotonic and explainable, not tuned.
func _generation_parameters(a: Dictionary, tensions: Array, variance: Dictionary, hazard_total: float, config: Dictionary) -> Dictionary:
	var cold := _neg(a.temperature)
	var wet := clampf((a.moisture + 0.3) / 1.3, 0.0, 1.0)
	var relief := _c01(0.2 + 0.5 * absf(a.elevation) + 0.15 * _neg(a.order) + 0.15 * _neg(a.stillness))
	var water := wet * (1.0 - 0.7 * cold)
	var ice := wet * cold
	var vegetation := _c01(_n(a.vitality) * (0.4 + 0.6 * wet) * (1.0 - 0.6 * cold))
	var tightness := _n(a.enclosure)
	var light := _n(a.light)
	var fog := _c01(0.1 + 0.35 * _pos(a.moisture) + 0.25 * _pos(a.stillness) + 0.2 * _neg(a.light) + 0.1 * _pos(a.age))
	var hazard_pressure := _c01(hazard_total / float(config.hazard_saturation))
	var band: Array = config.encounter_density_band
	var liveliness := _c01(0.5 + 0.3 * _neg(a.stillness) - 0.3 * _pos(a.stillness) + 0.2 * _pos(a.vitality))
	return {
		"terrain": {
			"elevation_bias": _r(_n(a.elevation)),
			"relief": _r(relief),
			"water_coverage": _r(water),
			"ice_coverage": _r(ice),
			"vegetation": _r(vegetation),
			"architecture_density": _r(_c01(0.15 + 0.7 * _pos(a.order) + 0.15 * _pos(a.age))),
			"ruin_level": _r(_c01(0.35 + 0.45 * _pos(a.age) + 0.2 * _neg(a.vitality))),
			"subterranean_ratio": _r(_c01(0.6 * _pos(a.enclosure) + 0.4 * _neg(a.elevation))),
			"patchwork": tensions.map(func(t): return {"axis": t.axis, "regional_variance": _r(variance[t.axis])}),
		},
		"structure": {
			"passage_tightness": _r(tightness),
			"verticality": _r(_c01(0.2 + 0.8 * absf(a.elevation))),
			"interior_ratio": _r(_c01(0.5 * _pos(a.order) + 0.5 * _pos(a.enclosure))),
		},
		"atmosphere": {
			"light_level": _r(light),
			"fog_density": _r(fog),
			"precipitation": _r(_c01(1.4 * _pos(a.moisture) * _neg(a.stillness) + 0.3 * cold * _pos(a.moisture))),
			"wind": _r(_c01(0.1 + 0.7 * _neg(a.stillness) + 0.2 * _pos(a.elevation))),
			"color_temperature": _r(_n(a.temperature)),
			"silence": _r(_n(a.stillness)),
			"corruption_tint": _r(_neg(a.sanctity)),
		},
		"challenge": {
			"visibility": _r(_c01(light * (1.0 - 0.6 * fog) + 0.1)),
			"ambush_tendency": _r(_c01(0.45 * tightness + 0.35 * (1.0 - light) + 0.2 * fog)),
			"encounter_density": _r(lerpf(float(band[0]), float(band[1]), liveliness)),
			"hazard_pressure": _r(hazard_pressure),
			"traversal_difficulty": _r(_c01(0.3 * relief + 0.3 * hazard_pressure + 0.2 * vegetation + 0.2 * _c01(water + ice))),
		},
	}

## Human-readable digest of a blueprint.
static func summarize(blueprint: Dictionary) -> String:
	var identity: Dictionary = blueprint.identity
	var lines := ["%s  (seed %s)" % [blueprint.address.to_upper(), blueprint.input.world_seed]]
	var biome: Dictionary = identity.biome
	lines.append("  Biome: %s, bleeding into %s" % [biome.ranking[0].label, biome.ranking[1].label])
	lines.append("  Senses: " + ", ".join(identity.senses.map(func(s): return "%s=%s (%s)" % [s.keyword, s.sense, s.resolution])))
	for tension in identity.tensions:
		lines.append("  Tension: %s contested (%s vs %s), dominant %s -> %s" % [tension.axis, tension.poles[0], tension.poles[1], tension.dominant, tension.resolution])
	for interaction in identity.interactions:
		lines.append("  Interaction: %s [%s] %s" % [interaction.id, interaction.kind, interaction.summary])
	var variation: Dictionary = blueprint.variation
	lines.append("  Atmosphere: " + ", ".join(variation.atmosphere))
	for pool in Library.THEME_POOLS:
		lines.append("  %s: %s" % [pool.capitalize(), ", ".join(variation.featured[pool])])
	var terrain: Dictionary = blueprint.generation.terrain
	var challenge: Dictionary = blueprint.generation.challenge
	lines.append("  Terrain: relief %s, water %s, ice %s, architecture %s, ruin %s, underground %s" % [
		terrain.relief, terrain.water_coverage, terrain.ice_coverage, terrain.architecture_density, terrain.ruin_level, terrain.subterranean_ratio])
	lines.append("  Challenge: visibility %s, ambush %s, density %s, hazards %s, traversal %s" % [
		challenge.visibility, challenge.ambush_tendency, challenge.encounter_density, challenge.hazard_pressure, challenge.traversal_difficulty])
	lines.append("  identity %s  fingerprint %s" % [blueprint.identity_fingerprint, blueprint.fingerprint])
	return "\n".join(lines)

## Rounds to 3 decimals and removes negative zero so serialized text is stable.
static func _r(value: float) -> float:
	var rounded := snappedf(value, 0.001)
	return 0.0 if absf(rounded) < 0.0005 else rounded

static func _rounded_dict(values: Dictionary) -> Dictionary:
	var out := {}
	for key in values:
		out[key] = _r(values[key])
	return out

static func _c01(value: float) -> float:
	return clampf(value, 0.0, 1.0)

static func _n(value: float) -> float:
	return (value + 1.0) * 0.5

static func _pos(value: float) -> float:
	return maxf(value, 0.0)

static func _neg(value: float) -> float:
	return maxf(-value, 0.0)
