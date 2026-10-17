extends RefCounted
## Loads, validates and freezes the provisional shared build catalog: stats, slots,
## base profiles, ability definitions and the items that carry them.
##
## The same definitions serve player and enemy builds. No definition names an owner;
## a build only references definitions by stable id. After loading, every definition
## is read-only so no consumer (combatant, salvage, UI) can mutate shared data.
## Validation problems are collected in `errors` so tests can assert on them.

const SCHEMA := "boneshed.build_catalog.v0"
const CATALOG_PATH := "res://data/builds/catalog.json"
const CATEGORIES := ["weapon", "augment"]
const OPS := ["add", "mul"]
## Keys that would tie a definition to one kind of wielder. Never allowed anywhere.
const OWNER_KEYS := ["owner", "controller", "faction", "player_only", "enemy_only"]
const CATALOG_KEYS := ["abilities", "bindings", "catalog_version", "items", "profiles", "provisional", "schema", "slots", "stats"]
const STAT_KEYS := ["better", "id", "max", "min"]
const SLOT_KEYS := ["accepts", "id"]
const PROFILE_KEYS := ["id", "name", "notes", "stats"]
const ABILITY_KEYS := ["binding", "hit", "id", "module", "name", "requires_tags", "tags", "telegraph", "timing"]
const TIMING_KEYS := ["active", "recovery", "windup"]
const HIT_KEYS := ["guard_posture", "health_damage", "reach", "width"]
const ITEM_KEYS := ["category", "excludes_tags", "fits_slots", "grants", "id", "modifiers", "name", "notes", "provides_tags", "requires_tags", "salvageable"]
const MODIFIER_KEYS := ["op", "stat", "value"]

var version := ""
## Digest of the canonical catalog; changes whenever any definition changes.
var fingerprint := ""
var stats := {}
var stat_order: Array = []
var slots := {}
var slot_order: Array = []
var bindings: Array = []
var profiles := {}
var abilities := {}
var items := {}
var errors: Array[String] = []

var _def_id := RegEx.create_from_string("^[a-z]+(\\.[a-z0-9_]+)+$")
var _plain_id := RegEx.create_from_string("^[a-z][a-z0-9_]*$")

func load_file(path := CATALOG_PATH) -> bool:
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("missing catalog file %s" % path)
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("%s is not a JSON object" % path)
		return false
	return load_data(parser.data)

## Accepts raw parsed data (tests pass fixture catalogs built in memory).
func load_data(data: Dictionary) -> bool:
	errors.clear()
	stats.clear()
	stat_order.clear()
	slots.clear()
	slot_order.clear()
	bindings.clear()
	profiles.clear()
	abilities.clear()
	items.clear()
	var source: Dictionary = data.duplicate(true)
	_keys(source, CATALOG_KEYS, "catalog")
	if source.get("schema") != SCHEMA:
		errors.append("unsupported catalog schema '%s'" % str(source.get("schema")))
		return false
	version = str(source.get("catalog_version", ""))
	if version.is_empty():
		errors.append("catalog_version is empty")
	_index(source.get("stats", []), stats, stat_order, "stat", _plain_id)
	_index(source.get("slots", []), slots, slot_order, "slot", _plain_id)
	_index(source.get("profiles", []), profiles, [], "profile", _def_id)
	_index(source.get("abilities", []), abilities, [], "ability", _def_id)
	_index(source.get("items", []), items, [], "item", _def_id)
	bindings = source.get("bindings", []) if source.get("bindings") is Array else []
	_validate_stats()
	_validate_slots()
	_validate_profiles()
	_validate_abilities()
	_validate_items()
	_reject_owner_keys(source, "catalog")
	for table in [stats, slots, profiles, abilities, items]:
		_freeze(table)
	_freeze(bindings)
	fingerprint = digest(source)
	return errors.is_empty()

## Stable digest of a definition. Same definition → same digest across runs and machines.
func ability_fingerprint(id: String) -> String:
	return digest(abilities[id]) if abilities.has(id) else ""

func item_fingerprint(id: String) -> String:
	return digest(items[id]) if items.has(id) else ""

## Explicit advantages and disadvantages, derived from data rather than hand-written
## text so they cannot drift from what the item actually does.
func tradeoffs(item_id: String) -> Dictionary:
	var item: Dictionary = items[item_id]
	var advantages := []
	var disadvantages := []
	for ability_id in item.grants:
		advantages.append({"kind": "grants_ability", "ability": ability_id})
	for modifier in item.modifiers:
		var entry := {"kind": "stat", "stat": modifier.stat, "op": modifier.op, "value": modifier.value}
		if _beneficial(modifier):
			advantages.append(entry)
		else:
			disadvantages.append(entry)
	for tag in item.excludes_tags:
		disadvantages.append({"kind": "excludes_tag", "tag": tag})
	return {"advantages": advantages, "disadvantages": disadvantages}

static func canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true)

static func digest(value: Variant) -> String:
	return canonical_json(value).sha256_text().substr(0, 16)

func _beneficial(modifier: Dictionary) -> bool:
	var higher_is_better: bool = stats[modifier.stat].better == "higher"
	var raises: bool = modifier.value > 0.0 if modifier.op == "add" else modifier.value > 1.0
	return raises == higher_is_better

func _index(entries: Variant, table: Dictionary, order: Array, kind: String, pattern: RegEx) -> void:
	if not entries is Array:
		errors.append("%s list must be an array" % kind)
		return
	for entry in entries:
		if not entry is Dictionary:
			errors.append("%s entry must be an object" % kind)
			continue
		var id := str(entry.get("id", ""))
		if pattern.search(id) == null:
			errors.append("invalid %s id '%s'" % [kind, id])
		elif table.has(id):
			errors.append("duplicate %s id '%s'" % [kind, id])
		else:
			table[id] = entry
			order.append(id)

func _validate_stats() -> void:
	for id in stat_order:
		var stat: Dictionary = stats[id]
		_keys(stat, STAT_KEYS, "stat " + id)
		if not (_number(stat.get("min")) and _number(stat.get("max"))) or stat.get("min", 0) > stat.get("max", 0):
			errors.append("stat %s needs numeric min <= max" % id)
		if not stat.get("better") in ["higher", "lower"]:
			errors.append("stat %s better must be 'higher' or 'lower'" % id)

func _validate_slots() -> void:
	for id in slot_order:
		_keys(slots[id], SLOT_KEYS, "slot " + id)
		if not slots[id].get("accepts") in CATEGORIES:
			errors.append("slot %s accepts unknown category" % id)
	for binding in bindings:
		if not binding is String or _plain_id.search(binding) == null:
			errors.append("invalid binding '%s'" % str(binding))

func _validate_profiles() -> void:
	for id in profiles:
		var profile: Dictionary = profiles[id]
		_keys(profile, PROFILE_KEYS, "profile " + id)
		var values = profile.get("stats", {})
		if not values is Dictionary or _sorted(values.keys()) != _sorted(stat_order):
			errors.append("profile %s must define exactly the catalog stats" % id)
			continue
		for stat_id in values:
			if not _number(values[stat_id]) or values[stat_id] < stats[stat_id].min or values[stat_id] > stats[stat_id].max:
				errors.append("profile %s stat %s out of range" % [id, stat_id])

func _validate_abilities() -> void:
	var provided := {}
	for item in items.values():
		for tag in item.get("provides_tags", []):
			provided[tag] = true
	for id in abilities:
		var ability: Dictionary = abilities[id]
		var where: String = "ability " + id
		_keys(ability, ABILITY_KEYS, where)
		if not ability.get("binding") in bindings:
			errors.append("%s has unknown binding" % where)
		_tag_list(ability, "tags", where)
		_tag_list(ability, "requires_tags", where)
		for tag in ability.get("requires_tags", []):
			if not provided.has(tag):
				errors.append("%s requires tag '%s' that no item provides" % [where, tag])
		_numbers(ability.get("timing"), TIMING_KEYS, where + " timing", true)
		_numbers(ability.get("hit"), HIT_KEYS, where + " hit", false)

func _validate_items() -> void:
	for id in items:
		var item: Dictionary = items[id]
		var where: String = "item " + id
		_keys(item, ITEM_KEYS, where)
		if not item.get("category") in CATEGORIES:
			errors.append("%s has unknown category" % where)
		if not item.get("salvageable") is bool:
			errors.append("%s salvageable must be true or false" % where)
		for field in ["fits_slots", "provides_tags", "requires_tags", "excludes_tags", "grants"]:
			_tag_list(item, field, where)
		if item.get("fits_slots", []).is_empty():
			errors.append("%s fits no slot" % where)
		for slot_id in item.get("fits_slots", []):
			if not slots.has(slot_id):
				errors.append("%s fits unknown slot '%s'" % [where, slot_id])
			elif slots[slot_id].accepts != item.get("category"):
				errors.append("%s cannot fit %s slot '%s'" % [where, slots[slot_id].accepts, slot_id])
		for ability_id in item.get("grants", []):
			if not abilities.has(ability_id):
				errors.append("%s grants unknown ability '%s'" % [where, ability_id])
		for tag in item.get("excludes_tags", []):
			if tag in item.get("provides_tags", []):
				errors.append("%s excludes a tag it provides" % where)
		var modifiers = item.get("modifiers", [])
		if not modifiers is Array:
			errors.append("%s modifiers must be an array" % where)
			continue
		var modifiers_valid := true
		for modifier in modifiers:
			if not _valid_modifier(modifier, where):
				modifiers_valid = false
		# Provisional rule: an augment is never a pure upgrade.
		if item.get("category") == "augment" and modifiers_valid and errors.is_empty() and tradeoffs(id).disadvantages.is_empty():
			errors.append("%s is an augment without an explicit disadvantage" % where)

func _valid_modifier(modifier: Variant, where: String) -> bool:
	if not modifier is Dictionary:
		errors.append("%s modifier must be an object" % where)
		return false
	var before := errors.size()
	_keys(modifier, MODIFIER_KEYS, where + " modifier")
	if not stats.has(str(modifier.get("stat"))):
		errors.append("%s modifies unknown stat '%s'" % [where, str(modifier.get("stat"))])
	if not modifier.get("op") in OPS:
		errors.append("%s modifier op must be add or mul" % where)
	elif not _number(modifier.get("value")):
		errors.append("%s modifier value must be a number" % where)
	elif (modifier.op == "add" and modifier.value == 0.0) or (modifier.op == "mul" and modifier.value <= 0.0) or (modifier.op == "mul" and modifier.value == 1.0):
		errors.append("%s modifier must be non-neutral (mul > 0)" % where)
	return errors.size() == before

func _numbers(value: Variant, keys: Array, where: String, positive: bool) -> void:
	if not value is Dictionary:
		errors.append("%s must be an object" % where)
		return
	_keys(value, keys, where)
	for key in keys:
		var n = value.get(key)
		if not _number(n) or n < 0.0 or (positive and n == 0.0):
			errors.append("%s.%s must be a %s number" % [where, key, "positive" if positive else "non-negative"])

func _tag_list(entry: Dictionary, field: String, where: String) -> void:
	var values = entry.get(field)
	if not values is Array:
		errors.append("%s.%s must be an array" % [where, field])
		return
	var seen := {}
	for value in values:
		if not value is String or value.is_empty():
			errors.append("%s.%s entries must be text" % [where, field])
		elif seen.has(value):
			errors.append("%s.%s repeats '%s'" % [where, field, value])
		seen[value] = true

func _keys(entry: Dictionary, expected: Array, where: String) -> void:
	for key in entry:
		if not key in expected:
			errors.append("%s has unknown key '%s'" % [where, str(key)])
	for key in expected:
		if not entry.has(key):
			errors.append("%s is missing key '%s'" % [where, key])

func _reject_owner_keys(value: Variant, where: String) -> void:
	if value is Dictionary:
		for key in value:
			if key in OWNER_KEYS:
				errors.append("%s names an owner via '%s'; definitions must be owner-independent" % [where, key])
			_reject_owner_keys(value[key], where)
	elif value is Array:
		for entry in value:
			_reject_owner_keys(entry, where)

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]

static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for entry in value:
			_freeze(entry)
		value.make_read_only()
