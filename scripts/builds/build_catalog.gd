extends RefCounted
## Loads, validates and freezes the provisional shared build catalog: stats, slots,
## base profiles, ability definitions and the items that carry them.
##
## Equipment semantics: a `body` slot is an anatomical part (an arm) and accepts only
## `body_mod` items, which replace that part. A `grip` slot is a hand carried by a body
## slot (its `limb`) and accepts only `weapon` items. A grip exists only while its limb
## has a hand: a body modification declares `anatomy.grip`. Two-handed weapons also
## occupy the grip's declared `pair`. Grips, limbs and pairs are data, so a body with
## more (or fewer) hands needs new slots, not new rules. Body modifications are not
## weapons and grant no attacks by default; striking limbs say so explicitly with
## `anatomy.natural_weapon`. The only body-modification ability is the catalog-listed
## legacy demonstration (`legacy_abilities`), kept so the first playable still works.
##
## The same definitions serve player and enemy builds. No definition names an owner;
## a build only references definitions by stable id. After loading, every definition
## is read-only so no consumer (combatant, salvage, UI) can mutate shared data.
## Validation problems are collected in `errors` so tests can assert on them.

const SCHEMA := "boneshed.build_catalog.v1"
const CATALOG_PATH := "res://data/builds/catalog.json"
const CATEGORIES := ["weapon", "body_mod"]
## Which item category each slot kind accepts.
const SLOT_ACCEPTS := {"grip": "weapon", "body": "body_mod"}
const SIDES := ["left", "right", "center"]
const OPS := ["add", "mul"]
## Keys that would tie a definition to one kind of wielder. Never allowed anywhere.
const OWNER_KEYS := ["owner", "controller", "faction", "player_only", "enemy_only"]
const CATALOG_KEYS := ["abilities", "bindings", "catalog_version", "equipment_classes", "items", "legacy_abilities", "profiles", "provisional", "schema", "slots", "stats"]
const STAT_KEYS := ["better", "id", "max", "min"]
const SLOT_KEYS := {"grip": ["id", "kind", "limb", "pair", "side"], "body": ["id", "kind", "part", "side"]}
const CLASS_KEYS := ["body_parts", "grips", "reach_classes", "weapon_classes", "weight_classes"]
const PROFILE_KEYS := ["id", "name", "notes", "stats"]
const ABILITY_KEYS := ["binding", "hit", "id", "module", "name", "requires_tags", "tags", "telegraph", "timing"]
const TIMING_KEYS := ["active", "recovery", "windup"]
const HIT_KEYS := ["guard_posture", "health_damage", "posture_damage", "reach", "width"]
const ITEM_KEYS := ["category", "excludes_tags", "fits_slots", "grants", "id", "modifiers", "name", "notes", "provides_tags", "requires_tags", "salvageable"]
## Exactly one of these per item, matching its category.
const CATEGORY_KEYS := {"weapon": "weapon", "body_mod": "anatomy"}
## Physical description the directional-melee prototype will read. Classes are names
## from `equipment_classes`; handling is metres, kilograms and a 0..1 balance point
## measured from the grip toward the tip.
const WEAPON_KEYS := ["class", "defense", "grip", "handling", "reach", "weight"]
const NATURAL_WEAPON_KEYS := ["class", "defense", "handling", "reach", "weight"]
const HANDLING_KEYS := ["balance", "length", "mass"]
const DEFENSE_KEYS := ["deflect", "guard"]
const ANATOMY_KEYS := ["grip", "part"]
const NATURAL_CLASS := "natural"
const MODIFIER_KEYS := ["op", "stat", "value"]

var version := ""
## Digest of the canonical catalog; changes whenever any definition changes.
var fingerprint := ""
var stats := {}
var stat_order: Array = []
var slots := {}
var slot_order: Array = []
var bindings: Array = []
var classes := {}
var legacy_abilities: Array = []
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
	stats = {}
	stat_order = []
	slots = {}
	slot_order = []
	bindings = []
	classes = {}
	legacy_abilities = []
	profiles = {}
	abilities = {}
	items = {}
	fingerprint = ""
	version = ""
	var source: Dictionary = data.duplicate(true)
	_reject_owner_keys(source, "catalog")
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
	if not source.get("bindings") is Array:
		errors.append("bindings must be an array")
	else:
		bindings = source.bindings
	if not source.get("equipment_classes") is Dictionary:
		errors.append("equipment_classes must be an object")
	else:
		classes = source.equipment_classes
	if not source.get("legacy_abilities") is Array:
		errors.append("legacy_abilities must be an array")
	else:
		legacy_abilities = source.legacy_abilities
	# Downstream validation uses earlier tables. Stop on malformed prerequisites
	# rather than indexing invalid values while reporting a later definition.
	for validate_table in [_validate_stats, _validate_classes, _validate_slots, _validate_profiles, _validate_abilities, _validate_items]:
		if not errors.is_empty():
			return false
		validate_table.call()
	for table in [stats, slots, profiles, abilities, items, classes]:
		_freeze(table)
	_freeze(bindings)
	_freeze(legacy_abilities)
	fingerprint = digest(source)
	return errors.is_empty()

## Stable digest of a definition. Same definition → same digest across runs and machines.
func ability_fingerprint(id: String) -> String:
	return digest(abilities[id]) if abilities.has(id) else ""

func item_fingerprint(id: String) -> String:
	return digest(items[id]) if items.has(id) else ""

## Grips a weapon occupies when held: 1 or 2. Zero for anything that is not a weapon.
func hands_required(item_id: String) -> int:
	var item: Dictionary = items.get(item_id, {})
	return int(classes.grips[item.weapon.grip]) if item.get("category") == "weapon" else 0

## True when the body-slot item (or the natural part, for "") keeps the limb's hand.
func keeps_grip(body_item_id: String) -> bool:
	return body_item_id.is_empty() or bool(items[body_item_id].anatomy.grip)

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
	# A replacement limb without a hand removes that limb's grip, and with it any
	# two-handed grip that needed the pair.
	if item.category == "body_mod" and not item.anatomy.grip:
		disadvantages.append({"kind": "removes_grip", "part": item.anatomy.part})
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

func _validate_classes() -> void:
	_keys(classes, CLASS_KEYS, "equipment_classes")
	for key in ["body_parts", "reach_classes", "weapon_classes", "weight_classes"]:
		var names = classes.get(key)
		if not names is Array or names.is_empty() or names.any(func(n): return not n is String or _plain_id.search(n) == null):
			errors.append("equipment_classes.%s must be a nonempty list of plain ids" % key)
	if not NATURAL_CLASS in classes.get("weapon_classes", []):
		errors.append("equipment_classes.weapon_classes must include '%s'" % NATURAL_CLASS)
	var grips = classes.get("grips")
	if not grips is Dictionary or grips.is_empty():
		errors.append("equipment_classes.grips must be a nonempty object")
	else:
		for grip in grips:
			if not _number(grips[grip]) or not (grips[grip] == 1 or grips[grip] == 2):
				errors.append("grip %s must need 1 or 2 hands" % str(grip))

func _validate_slots() -> void:
	for id in slot_order:
		var slot: Dictionary = slots[id]
		if not slot.get("kind") in SLOT_ACCEPTS:
			errors.append("slot %s has unknown kind" % id)
			continue
		_keys(slot, SLOT_KEYS[slot.kind], "slot " + id)
		if not slot.get("side") in SIDES:
			errors.append("slot %s has unknown side" % id)
		if slot.kind == "body" and not slot.get("part") in classes.get("body_parts", []):
			errors.append("slot %s has unknown body part" % id)
	if not errors.is_empty():
		return
	for id in slot_order:
		var slot: Dictionary = slots[id]
		if slot.kind != "grip":
			continue
		if not slots.has(str(slot.limb)) or slots[slot.limb].kind != "body":
			errors.append("grip %s limb must be a body slot" % id)
		var pair := str(slot.pair)
		if pair.is_empty():
			continue
		if pair == id or not slots.has(pair) or slots[pair].kind != "grip" or slots[pair].pair != id:
			errors.append("grip %s pair must be a different grip that pairs back" % id)
		elif slots[pair].limb == slot.limb:
			errors.append("grip %s pairs with a grip on the same limb" % id)
	var seen := {}
	for binding in bindings:
		if seen.has(binding):
			errors.append("duplicate binding '%s'" % str(binding))
		seen[binding] = true
		if not binding is String or _plain_id.search(binding) == null:
			errors.append("invalid binding '%s'" % str(binding))

func _validate_profiles() -> void:
	for id in profiles:
		var profile: Dictionary = profiles[id]
		_keys(profile, PROFILE_KEYS, "profile " + id, ["ability_overrides", "guard_posture_overrides"])
		var values = profile.get("stats", {})
		if not values is Dictionary or _sorted(values.keys()) != _sorted(stat_order):
			errors.append("profile %s must define exactly the catalog stats" % id)
			continue
		for stat_id in values:
			if not _number(values[stat_id]) or values[stat_id] < stats[stat_id].min or values[stat_id] > stats[stat_id].max:
				errors.append("profile %s stat %s out of range" % [id, stat_id])

		var overrides = profile.get("ability_overrides", {})
		if not overrides is Dictionary:
			errors.append("profile %s ability_overrides must be an object" % id)
		else:
			for ability_id in overrides:
				if not abilities.has(ability_id):
					errors.append("profile %s overrides unknown ability %s" % [id, ability_id])
				var values_override = overrides[ability_id]
				if not values_override is Dictionary or values_override.is_empty():
					errors.append("profile %s ability override must be a nonempty object" % id)
					continue
				for key in values_override:
					var value = values_override[key]
					if not key in TIMING_KEYS + HIT_KEYS or not _number(value) or value < 0.0 or (key in TIMING_KEYS and value == 0.0):
						errors.append("profile %s invalid ability override %s.%s" % [id, ability_id, key])
		var defense = profile.get("guard_posture_overrides", {})
		if not defense is Dictionary:
			errors.append("profile %s guard_posture_overrides must be an object" % id)
		else:
			for binding in defense:
				if not binding in bindings or not _number(defense[binding]) or defense[binding] < 0.0:
					errors.append("profile %s invalid guard posture override %s" % [id, binding])

func _validate_abilities() -> void:
	var provided := {}
	for item in items.values():
		if not item.get("provides_tags") is Array:
			errors.append("item provides_tags must be an array")
			continue
		for tag in item.provides_tags:
			provided[tag] = true
	for id in abilities:
		var ability: Dictionary = abilities[id]
		var where: String = "ability " + id
		_keys(ability, ABILITY_KEYS, where)
		if not ability.get("binding") in bindings:
			errors.append("%s has unknown binding" % where)
		if not ability.get("module") is String or _def_id.search(ability.module) == null:
			errors.append("%s needs a valid module id" % where)
		_tag_list(ability, "tags", where)
		_tag_list(ability, "requires_tags", where)
		if ability.get("binding") == "special" and not id in legacy_abilities:
			errors.append("%s uses the special binding but is not a legacy ability" % where)
		if not ability.get("requires_tags") is Array:
			continue
		for tag in ability.requires_tags:
			if not provided.has(tag):
				errors.append("%s requires tag '%s' that no item provides" % [where, tag])
		_numbers(ability.get("timing"), TIMING_KEYS, where + " timing", true)
		_numbers(ability.get("hit"), HIT_KEYS, where + " hit", false)

func _validate_items() -> void:
	for ability_id in legacy_abilities:
		if not ability_id is String or not abilities.has(ability_id):
			errors.append("legacy ability '%s' is unknown" % str(ability_id))
	for id in items:
		var item: Dictionary = items[id]
		var where: String = "item " + id
		var category = item.get("category")
		_keys(item, ITEM_KEYS, where, [CATEGORY_KEYS.get(category, "")])
		if not category in CATEGORIES:
			errors.append("%s has unknown category" % where)
			continue
		var before_physical := errors.size()
		if category == "weapon":
			_validate_weapon(item.get("weapon"), where + " weapon", WEAPON_KEYS)
		else:
			_validate_anatomy(item.get("anatomy"), where + " anatomy")
		var physical_ok := errors.size() == before_physical
		if not item.get("salvageable") is bool:
			errors.append("%s salvageable must be true or false" % where)
		var before_lists := errors.size()
		for field in ["fits_slots", "provides_tags", "requires_tags", "excludes_tags", "grants"]:
			_tag_list(item, field, where)
		if errors.size() != before_lists:
			continue
		if item.get("fits_slots", []).is_empty():
			errors.append("%s fits no slot" % where)
		for slot_id in item.get("fits_slots", []):
			if not slots.has(slot_id):
				errors.append("%s fits unknown slot '%s'" % [where, slot_id])
			elif SLOT_ACCEPTS[slots[slot_id].kind] != category:
				errors.append("%s cannot fit %s slot '%s'" % [where, slots[slot_id].kind, slot_id])
			elif physical_ok and category == "body_mod" and slots[slot_id].part != item.anatomy.part:
				errors.append("%s replaces part '%s', not slot '%s'" % [where, item.anatomy.part, slot_id])
			elif physical_ok and category == "weapon" and hands_required(id) == 2 and str(slots[slot_id].pair).is_empty():
				errors.append("%s is two-handed but grip '%s' has no pair" % [where, slot_id])
		for ability_id in item.get("grants", []):
			if not abilities.has(ability_id):
				errors.append("%s grants unknown ability '%s'" % [where, ability_id])
			elif category == "body_mod" and not ability_id in legacy_abilities:
				# Body modifications change anatomy; they never imply a special attack.
				errors.append("%s is a body modification granting non-legacy ability '%s'" % [where, ability_id])
			elif category == "weapon" and ability_id in legacy_abilities:
				errors.append("%s is a weapon granting legacy ability '%s'" % [where, ability_id])
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
		# Provisional rule: a body modification is never a pure upgrade.
		if category == "body_mod" and modifiers_valid and errors.is_empty() and tradeoffs(id).disadvantages.is_empty():
			errors.append("%s is a body modification without an explicit disadvantage" % where)

func _validate_weapon(weapon: Variant, where: String, keys: Array) -> void:
	if not weapon is Dictionary:
		errors.append("%s must be an object" % where)
		return
	_keys(weapon, keys, where)
	var natural := keys == NATURAL_WEAPON_KEYS
	if not weapon.get("class") in classes.weapon_classes or (weapon.get("class") == NATURAL_CLASS) != natural:
		errors.append("%s has invalid class" % where)
	if not natural and not classes.grips.has(str(weapon.get("grip"))):
		errors.append("%s has unknown grip" % where)
	if not weapon.get("reach") in classes.reach_classes:
		errors.append("%s has unknown reach class" % where)
	if not weapon.get("weight") in classes.weight_classes:
		errors.append("%s has unknown weight class" % where)
	var before := errors.size()
	_numbers(weapon.get("handling"), HANDLING_KEYS, where + " handling", false)
	if errors.size() == before and (weapon.handling.length == 0.0 or weapon.handling.mass == 0.0):
		errors.append("%s handling length and mass must be positive" % where)
	if errors.size() == before and weapon.handling.balance > 1.0:
		errors.append("%s handling.balance must be within 0..1" % where)
	var defense = weapon.get("defense")
	if not defense is Dictionary:
		errors.append("%s defense must be an object" % where)
	else:
		_keys(defense, DEFENSE_KEYS, where + " defense")
		if defense.values().any(func(v): return not v is bool):
			errors.append("%s defense values must be true or false" % where)

func _validate_anatomy(anatomy: Variant, where: String) -> void:
	if not anatomy is Dictionary:
		errors.append("%s must be an object" % where)
		return
	_keys(anatomy, ANATOMY_KEYS, where, ["natural_weapon"])
	if not anatomy.get("part") in classes.body_parts:
		errors.append("%s has unknown body part" % where)
	if not anatomy.get("grip") is bool:
		errors.append("%s grip must be true or false" % where)
	if anatomy.has("natural_weapon"):
		_validate_weapon(anatomy.natural_weapon, where + " natural_weapon", NATURAL_WEAPON_KEYS)

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

func _keys(entry: Dictionary, expected: Array, where: String, optional: Array = []) -> void:
	for key in entry:
		if not key in expected and not key in optional:
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
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

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
