extends RefCounted
## Pure operations on serialisable builds, shared by player and enemy builds alike.
##
## A build stores only stable ids: a profile, the item in each slot, and the items it
## carries but has not equipped. Abilities are never stored on a build; they are
## derived from equipped items, so salvage cannot introduce a second ability format.
## Every operation returns a new build and leaves its input untouched. On any error the
## original build is returned unchanged. Errors are {"code", ...} records in a fixed
## (slot) order so outputs are deterministic.
##
## The build shape is unchanged from v0: `equipped` maps a slot id to one item id.
## A two-handed weapon is stored once, in the grip it is held from; the paired grip it
## also occupies is derived. A body slot without an item is the natural part.

const Catalog := preload("res://scripts/builds/build_catalog.gd")

const SCHEMA := "boneshed.build.v0"
const RESOLVED_SCHEMA := "boneshed.resolved_build.v1"
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
	var errors := validate(build) if catalog.errors.is_empty() and not catalog.fingerprint.is_empty() else [{"code": "invalid_catalog"}]
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
		"equipment": _equipment(build),
	}
	resolved["guard_posture_overrides"] = profile.get("guard_posture_overrides", {}).duplicate(true)
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

## Atomically swaps the item in a slot for a carried one; the old item becomes carried.
## Weapon replacement and anatomical replacement share this operation; the slot kind
## decides which rules apply. An empty slot behaves like `equip`.
func replace(build: Variant, item_id: String, slot: String) -> Dictionary:
	var errors := validate(build)
	if errors.is_empty():
		if not catalog.slots.has(slot):
			errors.append({"code": "unknown_slot", "slot": slot})
		elif not item_id in build.carried:
			errors.append({"code": "not_carried", "item": item_id})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build}
	var candidate: Dictionary = build.duplicate(true)
	candidate.carried.erase(item_id)
	if candidate.equipped.has(slot):
		candidate.carried.append(candidate.equipped[slot])
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
		elif Catalog.SLOT_ACCEPTS[catalog.slots[slot].kind] != catalog.items[item_id].category or not slot in catalog.items[item_id].fits_slots:
			errors.append({"code": "wrong_slot", "item": item_id, "slot": slot})
	if not errors.is_empty():
		return
	_validate_grips(build, slots, errors)
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

## A weapon needs a hand on each grip it occupies, and a two-handed weapon needs its
## pair grip free. Limbs replaced by a handless body modification have no grip.
func _validate_grips(build: Dictionary, slots: Array, errors: Array) -> void:
	for slot in slots:
		var item_id: String = build.equipped[slot]
		if catalog.items[item_id].category != "weapon":
			continue
		var needed := [slot]
		if catalog.hands_required(item_id) == 2:
			needed.append(catalog.slots[slot].pair)
		for grip in needed:
			var limb: String = catalog.slots[grip].limb
			var limb_item: String = build.equipped.get(limb, "")
			if not catalog.keeps_grip(limb_item):
				errors.append({"code": "grip_unavailable", "item": item_id, "slot": grip, "limb": limb, "blocked_by": limb_item})
			elif grip != slot and build.equipped.has(grip):
				errors.append({"code": "grip_occupied", "item": item_id, "slot": grip, "conflicts_with": build.equipped[grip]})

## Gameplay-facing equipment view, in slot order: what each anatomical part is, which
## grips exist and what holds them, and the physical profile of every weapon,
## including explicitly declared natural weapons. Combat and presentation read this
## instead of inferring anatomy from abilities.
func _equipment(build: Dictionary) -> Dictionary:
	var body := []
	var grips := []
	var weapons := []
	var natural := []
	var held := {}
	var capabilities := {"weapon": {}, "body": {}}
	for slot in catalog.slot_order:
		var item_id: String = build.equipped.get(slot, "")
		if catalog.slots[slot].kind == "grip" and not item_id.is_empty():
			held[slot] = item_id
			if catalog.hands_required(item_id) == 2:
				held[catalog.slots[slot].pair] = item_id
	for slot in catalog.slot_order:
		var definition: Dictionary = catalog.slots[slot]
		var item_id: String = build.equipped.get(slot, "")
		var item: Dictionary = catalog.items.get(item_id, {})
		for tag in item.get("provides_tags", []):
			capabilities["weapon" if item.category == "weapon" else "body"][tag] = true
		if definition.kind == "body":
			body.append({"slot": slot, "part": definition.part, "side": definition.side, "item": item_id,
				"grip": catalog.keeps_grip(item_id), "natural_weapon": not item.is_empty() and item.anatomy.has("natural_weapon")})
			if not item.is_empty() and item.anatomy.has("natural_weapon"):
				natural.append(_weapon_view(item_id, item.anatomy.natural_weapon, slot, definition.side, [], true))
		else:
			grips.append({"slot": slot, "limb": definition.limb, "side": definition.side,
				"available": catalog.keeps_grip(build.equipped.get(definition.limb, "")), "held_by": held.get(slot, "")})
			if not item_id.is_empty():
				var occupied := [slot] if catalog.hands_required(item_id) == 1 else [slot, definition.pair]
				weapons.append(_weapon_view(item_id, item.weapon, slot, definition.side, occupied, false))
	return {"body": body, "grips": grips, "weapons": weapons + natural,
		"capabilities": {"weapon": _sorted(capabilities.weapon.keys()), "body": _sorted(capabilities.body.keys())}}

func _weapon_view(item_id: String, profile: Dictionary, slot: String, side: String, occupied: Array, is_natural: bool) -> Dictionary:
	return {"item": item_id, "slot": slot, "side": side, "grips": occupied, "natural": is_natural,
		"class": profile["class"], "grip": profile.get("grip", ""), "reach": profile.reach, "weight": profile.weight,
		"handling": profile.handling.duplicate(true), "defense": profile.defense.duplicate(true)}

## The ability definition is shared and unchanged; only `effective` reflects the wielder.
func _resolve_abilities(build: Dictionary, final_stats: Dictionary) -> Array:
	var by_binding := {}
	for slot in _equipped_slots(build):
		var item_id: String = build.equipped[slot]
		for ability_id in catalog.items[item_id].grants:
			var ability: Dictionary = catalog.abilities[ability_id]
			var effective: Dictionary = ability.timing.duplicate(true)
			effective.merge(ability.hit, true)
			effective.merge(catalog.profiles[build.profile].get("ability_overrides", {}).get(ability_id, {}), true)
			effective.windup *= final_stats.windup_scale
			effective.recovery *= final_stats.recovery_scale
			for key in effective:
				effective[key] = _round(effective[key])
			by_binding[ability.binding] = {
				"id": ability_id,
				"fingerprint": catalog.ability_fingerprint(ability_id),
				"binding": ability.binding,
				"module": ability.module,
				"source": {"slot": slot, "item": item_id},
				"effective": effective,
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
