extends RefCounted
## Loads and validates the prototype keyword vocabulary and interaction rules.
## Validation problems are collected in `errors` rather than pushed to the engine log,
## so tests can assert on them.

const AXES := ["temperature", "moisture", "light", "enclosure", "elevation", "order", "vitality", "stillness", "sanctity", "age"]
const THEME_POOLS := ["hazards", "encounters", "discoveries"]
const KEYWORDS_PATH := "res://data/worldgen/keywords.json"
const RULES_PATH := "res://data/worldgen/rules.json"
## Selection grammar only; these roles never change semantic effects or weights.
const SLOT_ROLES := ["environment_adjective", "quality_adjective", "noun"]

var data_version := ""
var keywords := {}
var interactions: Array = []
var biomes: Array = []
var config := {}
var errors: Array[String] = []

func load_files(keywords_path := KEYWORDS_PATH, rules_path := RULES_PATH) -> bool:
	errors.clear()
	var vocabulary = _read_json(keywords_path)
	var rules = _read_json(rules_path)
	if not (vocabulary is Dictionary and rules is Dictionary):
		return false
	data_version = str(vocabulary.get("data_version", ""))
	if data_version != str(rules.get("data_version", "")):
		errors.append("data_version differs between keyword and rule files")
	config = rules.get("config", {})
	interactions = rules.get("interactions", [])
	biomes = rules.get("biomes", [])
	keywords.clear()
	for entry in vocabulary.get("keywords", []):
		var id := str(entry.get("id", ""))
		if id.is_empty() or id != id.to_lower().strip_edges():
			errors.append("keyword id must be lowercase and non-empty: '%s'" % id)
		elif keywords.has(id):
			errors.append("duplicate keyword id '%s'" % id)
		keywords[id] = entry
	_validate()
	return errors.is_empty()

func has_keyword(id: String) -> bool:
	return keywords.has(id)

## Older recorded addresses may use any catalog word in any position.
## The legacy entry marker records original vocabulary membership only.
func keywords_for_slot(slot: int, legacy := false) -> Array[String]:
	var ids: Array[String] = []
	if slot < 0 or slot >= SLOT_ROLES.size():
		return ids
	for id: String in keywords:
		var offered: bool = legacy or SLOT_ROLES[slot] in keywords[id].roles
		if offered:
			ids.append(id)
	ids.sort()
	return ids

func is_grammatical(words: Array) -> bool:
	if words.size() != SLOT_ROLES.size():
		return false
	var seen: Dictionary = {}
	for slot in words.size():
		if not (words[slot] is String or words[slot] is StringName):
			return false
		var id := String(words[slot]).strip_edges().to_lower()
		if not has_keyword(id) or seen.has(id) or SLOT_ROLES[slot] not in keywords[id].roles:
			return false
		seen[id] = true
	return true

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing data file %s" % path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		errors.append("%s is not a JSON object" % path)
	return parsed

func _validate() -> void:
	var known_tags := {}
	for id in keywords:
		var roles: Variant = keywords[id].get("roles")
		if not roles is Array or roles.size() != 1:
			errors.append("%s must belong to exactly one selectable slot; vocabulary overlap is forbidden" % id)
		elif roles[0] not in SLOT_ROLES:
			errors.append("%s has an invalid grammatical role" % id)
		if not keywords[id].get("legacy") is bool:
			errors.append("%s needs a boolean legacy marker" % id)
		var senses: Array = keywords[id].get("senses", [])
		if senses.is_empty():
			errors.append("%s has no senses" % id)
		var sense_ids := {}
		for sense in senses:
			var where := "%s/%s" % [id, sense.get("id", "?")]
			if sense_ids.has(sense.get("id")):
				errors.append("%s: duplicate sense id" % where)
			sense_ids[sense.get("id")] = true
			if sense.get("tags", []).is_empty():
				errors.append("%s: needs at least one tag" % where)
			for tag in sense.get("tags", []):
				known_tags[tag] = true
			_validate_effects(sense, where)
	for slot in SLOT_ROLES.size():
		if not keywords.values().any(func(entry: Dictionary) -> bool: return entry.get("roles") is Array and SLOT_ROLES[slot] in entry.roles):
			errors.append("selectable slot %s has no keywords" % SLOT_ROLES[slot])
	for id in keywords:
		for sense in keywords[id].get("senses", []):
			for tag in sense.get("resonates_with", []):
				if not known_tags.has(tag):
					errors.append("%s/%s resonates with unknown tag '%s'" % [id, sense.get("id"), tag])
	var rule_ids := {}
	for rule in interactions:
		var rule_id := str(rule.get("id", ""))
		if rule_ids.has(rule_id):
			errors.append("duplicate interaction '%s'" % rule_id)
		rule_ids[rule_id] = true
		if not rule.get("kind") in ["synergy", "conflict"]:
			errors.append("%s: kind must be synergy or conflict" % rule_id)
		var requires: Array = rule.get("requires", [])
		if requires.size() < 2 or requires.size() > 3:
			errors.append("%s: requires 2 or 3 tags" % rule_id)
		for tag in requires:
			if not known_tags.has(tag):
				errors.append("%s requires unknown tag '%s'" % [rule_id, tag])
		_validate_effects(rule.get("effects", {}), "interaction " + rule_id)
	for biome in biomes:
		_validate_axes(biome.get("prototype", {}), "biome " + str(biome.get("id")))
	var weights: Array = config.get("position_weights", [])
	if weights.size() != 3:
		errors.append("config.position_weights needs three entries")
	for weight in weights:
		if float(weight) <= 0.0 or float(weight) > 1.0:
			errors.append("position weights must be in (0, 1]")
	for axis in AXES:
		if config.get("axis_poles", {}).get(axis, []).size() != 2:
			errors.append("config.axis_poles.%s needs two pole names" % axis)

func _validate_effects(effects: Dictionary, where: String) -> void:
	_validate_axes(effects.get("axes", {}), where)
	for pool in THEME_POOLS:
		for theme in effects.get(pool, {}):
			var weight := float(effects[pool][theme])
			if weight <= 0.0 or weight > 1.0:
				errors.append("%s: %s.%s weight %s outside (0, 1]" % [where, pool, theme, weight])
	for descriptor in effects.get("atmosphere", []):
		if not descriptor is String or descriptor.is_empty():
			errors.append("%s: atmosphere descriptors must be non-empty strings" % where)

func _validate_axes(axes: Dictionary, where: String) -> void:
	for axis in axes:
		if not axis in AXES:
			errors.append("%s: unknown axis '%s'" % [where, axis])
		elif absf(float(axes[axis])) > 1.0:
			errors.append("%s: axis %s outside [-1, 1]" % [where, axis])
