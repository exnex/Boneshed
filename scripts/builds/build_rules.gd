extends RefCounted
## Pure operations on serialisable builds, shared by player and enemy builds alike.
##
## A build stores only stable ids: a profile, the item in each slot, and the items it
## carries but has not equipped. Abilities are never stored on a build; they are
## derived from equipped items, so salvage cannot introduce a second ability format.
## Every operation returns a new build and leaves its input untouched. On any error the
## original build is returned unchanged. Errors are {"code", ...} records in a fixed
## (slot) order so outputs are deterministic.

const Catalog := preload("res://scripts/builds/build_catalog.gd")

const SCHEMA := "boneshed.build.v0"
const RESOLVED_SCHEMA := "boneshed.resolved_build.v0"
const BUILD_KEYS := ["build_id", "carried", "catalog_version", "equipped", "profile", "schema"]
## Derived values are rounded so floating-point noise never reaches outputs.
const PRECISION := 10000.0

var catalog
var _build_id := RegEx.create_from_string("^[a-z0-9][a-z0-9_.-]*$")

func _init(source_catalog) -> void:
	catalog = source_catalog

func new_build(build_id: String, profile_id: String) -> Dictionary:
	return {"schema": SCHEMA, "build_id": build_id, "catalog_version": catalog.version,
		"profile": profile_id, "equipped": {}, "carried": []}

func validate(build: Variant) -> Array:
	var errors := _validate_shape(build)
	if errors.is_empty():
		_validate_loadout(build, errors)
	return errors

## Returns {"ok", "errors", "resolved"}. Invalid builds never resolve partially.
func resolve(build: Variant) -> Dictionary:
	var errors := validate(build)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "resolved": {}}
	var profile: Dictionary = catalog.profiles[build.profile]
	var equipped := []
	var tags := {}
	var adds := {}
	var muls := {}
	var sources := {}
	for slot in _equipped_slots(build):
		var item_id: String = build.equipped[slot]
		var item: Dictionary = catalog.items[item_id]
		equipped.append({"slot": slot, "item": item_id, "item_fingerprint": catalog.item_fingerprint(item_id)})
		for tag in item.provides_tags:
			tags[tag] = true
		for modifier in item.modifiers:
			if modifier.op == "add":
				adds[modifier.stat] = adds.get(modifier.stat, 0.0) + modifier.value
			else:
				muls[modifier.stat] = muls.get(modifier.stat, 1.0) * modifier.value
			if not sources.has(modifier.stat):
				sources[modifier.stat] = []
			sources[modifier.stat].append({"item": item_id, "op": modifier.op, "value": modifier.value})
	# Fixed order: profile base, then summed adds, then multiplied muls, then clamp.
	var final_stats := {}
	for stat_id in catalog.stat_order:
		var value: float = (profile.stats[stat_id] + adds.get(stat_id, 0.0)) * muls.get(stat_id, 1.0)
		final_stats[stat_id] = _round(clampf(value, catalog.stats[stat_id].min, catalog.stats[stat_id].max))
	var resolved := {
		"schema": RESOLVED_SCHEMA,
		"build_id": build.build_id,
		"profile": build.profile,
		"catalog_version": catalog.version,
		"equipped": equipped,
		"tags": _sorted(tags.keys()),
		"stats": final_stats,
		"stat_sources": sources,
		"abilities": _resolve_abilities(build, final_stats),
		"tradeoffs": _tradeoffs(build),
	}
	resolved["fingerprint"] = Catalog.digest(resolved)
	return {"ok": true, "errors": [], "resolved": resolved}

## Moves one carried item into an empty slot. The result must be a valid build.
func equip(build: Variant, item_id: String, slot: String) -> Dictionary:
	var errors := validate(build)
	if errors.is_empty():
		if not catalog.slots.has(slot):
			errors.append({"code": "unknown_slot", "slot": slot})
		elif not item_id in build.carried:
			errors.append({"code": "not_carried", "item": item_id})
		elif build.equipped.has(slot):
			errors.append({"code": "slot_occupied", "slot": slot, "item": build.equipped[slot]})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build}
	var candidate: Dictionary = build.duplicate(true)
	candidate.carried.erase(item_id)
	candidate.equipped[slot] = item_id
	return _commit(build, candidate)

## Moves the item in a slot back to carried. Fails if another item depends on it.
func unequip(build: Variant, slot: String) -> Dictionary:
	var errors := validate(build)
	if errors.is_empty() and not build.equipped.has(slot):
		errors.append({"code": "slot_empty", "slot": slot})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build}
	var candidate: Dictionary = build.duplicate(true)
	candidate.carried.append(candidate.equipped[slot])
	candidate.equipped.erase(slot)
	return _commit(build, candidate)

## Adds a catalog item to carried. Used by verified salvage; not an inventory system.
func carry(build: Variant, item_id: String) -> Dictionary:
	var errors := validate(build)
	if errors.is_empty() and not catalog.items.has(item_id):
		errors.append({"code": "unknown_item", "item": item_id})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build}
	var candidate: Dictionary = build.duplicate(true)
	candidate.carried.append(item_id)
	return _commit(build, candidate)

## What changed between two resolved builds: stats, abilities, tags, tradeoffs.
func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var stat_changes := {}
	for stat_id in catalog.stat_order:
		if before.stats[stat_id] != after.stats[stat_id]:
			stat_changes[stat_id] = {"before": before.stats[stat_id], "after": after.stats[stat_id],
				"delta": _round(after.stats[stat_id] - before.stats[stat_id])}
	var before_abilities: Array = before.abilities.map(func(a): return a.id)
	var after_abilities: Array = after.abilities.map(func(a): return a.id)
	var before_items: Array = before.equipped.map(func(e): return e.item)
	return {
		"stats": stat_changes,
		"abilities_added": after_abilities.filter(func(id): return not id in before_abilities),
		"abilities_removed": before_abilities.filter(func(id): return not id in after_abilities),
		"tags_added": after.tags.filter(func(t): return not t in before.tags),
		"tags_removed": before.tags.filter(func(t): return not t in after.tags),
		"new_tradeoffs": after.tradeoffs.filter(func(t): return not t.item in before_items),
	}

func to_json(build: Dictionary) -> String:
	return Catalog.canonical_json(build)

## Strict loader: plain JSON only (no engine objects), exact keys, known ids.
func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "errors": [{"code": "malformed_json", "line": parser.get_error_line()}], "build": {}}
	var errors := validate(parser.data)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": {}}
	return {"ok": true, "errors": [], "build": parser.data}

func _commit(original: Dictionary, candidate: Dictionary) -> Dictionary:
	candidate.carried.sort()
	var errors := validate(candidate)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": original}
	return {"ok": true, "errors": [], "build": candidate}

func _validate_shape(build: Variant) -> Array:
	if not build is Dictionary:
		return [{"code": "not_an_object"}]
	var errors := []
	for key in build:
		if not key in BUILD_KEYS:
			errors.append({"code": "unknown_key", "key": str(key)})
	for key in BUILD_KEYS:
		if not build.has(key):
			errors.append({"code": "missing_key", "key": key})
	if not errors.is_empty():
		return errors
	if build.schema != SCHEMA:
		errors.append({"code": "unsupported_schema", "value": str(build.schema)})
	if not build.build_id is String or _build_id.search(build.build_id) == null:
		errors.append({"code": "invalid_build_id"})
	if build.catalog_version != catalog.version:
		errors.append({"code": "catalog_version_mismatch", "value": str(build.catalog_version), "expected": catalog.version})
	if not build.profile is String or not catalog.profiles.has(build.profile):
		errors.append({"code": "unknown_profile", "value": str(build.profile)})
	if not build.equipped is Dictionary:
		errors.append({"code": "invalid_equipped"})
	else:
		for slot in build.equipped:
			if not slot is String or not catalog.slots.has(slot):
				errors.append({"code": "unknown_slot", "slot": str(slot)})
			elif not build.equipped[slot] is String:
				errors.append({"code": "invalid_item_id", "slot": slot})
	if not build.carried is Array or build.carried.any(func(id): return not id is String):
		errors.append({"code": "invalid_carried"})
	return errors

func _validate_loadout(build: Dictionary, errors: Array) -> void:
	for item_id in build.carried:
		if not catalog.items.has(item_id):
			errors.append({"code": "unknown_item", "item": item_id})
	var slots := _equipped_slots(build)
	for slot in slots:
		var item_id: String = build.equipped[slot]
		if not catalog.items.has(item_id):
			errors.append({"code": "unknown_item", "item": item_id, "slot": slot})
		elif catalog.slots[slot].accepts != catalog.items[item_id].category or not slot in catalog.items[item_id].fits_slots:
			errors.append({"code": "wrong_slot", "item": item_id, "slot": slot})
	if not errors.is_empty():
		return
	var providers := {}
	for slot in slots:
		for tag in catalog.items[build.equipped[slot]].provides_tags:
			if not providers.has(tag):
				providers[tag] = []
			providers[tag].append(slot)
	var granted := {}
	var bound := {}
	for slot in slots:
		var item_id: String = build.equipped[slot]
		var item: Dictionary = catalog.items[item_id]
		for tag in item.requires_tags:
			if not providers.has(tag):
				errors.append({"code": "missing_required_tag", "item": item_id, "slot": slot, "tag": tag})
		for tag in item.excludes_tags:
			for other in providers.get(tag, []):
				errors.append({"code": "excluded_tag", "item": item_id, "slot": slot, "tag": tag, "conflicts_with": build.equipped[other]})
		for ability_id in item.grants:
			var ability: Dictionary = catalog.abilities[ability_id]
			if granted.has(ability_id):
				errors.append({"code": "duplicate_ability", "ability": ability_id, "slots": [granted[ability_id], slot]})
				continue
			granted[ability_id] = slot
			if bound.has(ability.binding):
				errors.append({"code": "binding_conflict", "binding": ability.binding, "abilities": [bound[ability.binding], ability_id]})
			else:
				bound[ability.binding] = ability_id
			for tag in ability.requires_tags:
				if not providers.has(tag):
					errors.append({"code": "missing_ability_requirement", "ability": ability_id, "tag": tag})

## The ability definition is shared and unchanged; only `effective` reflects the wielder.
func _resolve_abilities(build: Dictionary, final_stats: Dictionary) -> Array:
	var by_binding := {}
	for slot in _equipped_slots(build):
		var item_id: String = build.equipped[slot]
		for ability_id in catalog.items[item_id].grants:
			var ability: Dictionary = catalog.abilities[ability_id]
			by_binding[ability.binding] = {
				"id": ability_id,
				"fingerprint": catalog.ability_fingerprint(ability_id),
				"binding": ability.binding,
				"module": ability.module,
				"source": {"slot": slot, "item": item_id},
				"effective": {
					"windup": _round(ability.timing.windup * final_stats.windup_scale),
					"active": _round(ability.timing.active),
					"recovery": _round(ability.timing.recovery * final_stats.recovery_scale),
					"health_damage": _round(ability.hit.health_damage),
					"guard_posture": _round(ability.hit.guard_posture),
					"reach": _round(ability.hit.reach),
					"width": _round(ability.hit.width),
				},
			}
	var ordered := []
	for binding in catalog.bindings:
		if by_binding.has(binding):
			ordered.append(by_binding[binding])
	return ordered

func _tradeoffs(build: Dictionary) -> Array:
	var result := []
	for slot in _equipped_slots(build):
		var entry: Dictionary = catalog.tradeoffs(build.equipped[slot]).duplicate(true)
		entry["item"] = build.equipped[slot]
		result.append(entry)
	return result

## Equipped slots in catalog order, so every output is independent of insertion order.
func _equipped_slots(build: Dictionary) -> Array:
	return catalog.slot_order.filter(func(slot): return build.equipped.has(slot))

static func _round(value: float) -> float:
	return round(value * PRECISION) / PRECISION

static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy
