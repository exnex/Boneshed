extends RefCounted
## Lab-only combat resources: loads and validates data/melee_lab/combat_resources.json
## (armor, item traits, status definitions, contact routing, world conditions) and
## derives one fighter's stamina costs, mobility, mitigation, resistances and status
## sources from its *equipped items* (resolved weapon handling + armor ids + traits).
## Every fighter — player, lab opponent, a future Echo — goes through `derive`, so no
## one gets a cost, resistance or source that their equipment does not explain.
##
## Schema gap (documented in docs/MELEE_LAB_COMBAT_RESOURCES.md): the shared build
## catalog has no armor category/slots, element or status fields, and no stamina stat.
## This adapter fills that gap for the lab only and never edits the shared catalog.

const PATH := "res://data/melee_lab/combat_resources.json"
const SCHEMA := "boneshed.melee_lab_combat_resources.v0"
const KINDS := {"damage_over_time": ["tick_interval", "tick_damage"], "impairment": ["move_scale", "handling_scale"]}
const COMMON_EFFECT_KEYS := ["threshold", "decay_per_second", "duration", "immunity_after"]
const WHILE_ACTIVE := ["refresh", "ignore"]
## Contact outcomes from contact_solver.gd that routing must describe.
const OUTCOMES := ["hit", "misaligned", "block", "deflect", "guard_break", "clash", "evaded"]
## Never-negotiable routing: an avoided attack applies no on-hit status.
const ZERO_ROUTES := ["evaded"]
const ROUTES := ["on_hit", "ambient"]
const MAX_RESISTANCE := 0.9
const MAX_MITIGATION := 0.75

static func load_data(path := PATH) -> Dictionary:
	var data: Variant = null
	if FileAccess.file_exists(path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) == OK:
			data = parser.data
	return from_data(data)

## Returns {"ok", "errors", "data"}. `item_ids` are catalog item ids traits may name.
static func from_data(data: Variant, item_ids: Array = []) -> Dictionary:
	var errors := validate(data, item_ids)
	return {"ok": errors.is_empty(), "errors": errors, "data": data if errors.is_empty() else {}}

static func validate(data: Variant, item_ids: Array = []) -> Array[String]:
	var errors: Array[String] = []
	if not data is Dictionary or data.get("schema") != SCHEMA:
		return ["invalid lab combat resources data"]
	for key: String in ["effects", "routing", "traits"]:
		if not data.get(key) is Dictionary:
			errors.append("combat resources need an object: " + key)
	for key: String in ["armor", "world_conditions"]:
		if not data.get(key) is Array:
			errors.append("combat resources need an array: " + key)
	if not errors.is_empty():
		return errors
	for effect: String in data.effects:
		_validate_effect(effect, data.effects[effect], errors)
	for outcome: String in OUTCOMES:
		var scale: Variant = data.routing.get(outcome)
		if not _number(scale) or scale < 0.0 or scale > 1.0:
			errors.append("routing.%s must be a number in 0..1" % outcome)
		elif outcome in ZERO_ROUTES and scale != 0.0:
			errors.append("routing.%s must be 0: avoided attacks never apply on-hit status" % outcome)
	var armor_ids: Array = []
	for armor: Variant in data.armor:
		if not armor is Dictionary or not str(armor.get("id", "")).begins_with("armor.") or str(armor.get("slot", "")) == "":
			errors.append("armor entries need an armor.* id and a slot")
			continue
		armor_ids.append(armor.id)
		if not _number(armor.get("mass")) or armor.mass < 0.0:
			errors.append("%s mass must be a non-negative number" % armor.id)
		if not _number(armor.get("mitigation")) or armor.mitigation < 0.0 or armor.mitigation > MAX_MITIGATION:
			errors.append("%s mitigation must be in 0..%.2f" % [armor.id, MAX_MITIGATION])
		_validate_resistances(armor.id, armor.get("resistances"), data.effects, errors)
	for item: String in data.traits:
		var trait_data: Variant = data.traits[item]
		if not item_ids.is_empty() and item not in item_ids:
			errors.append("trait for unknown item: " + item)
		if not trait_data is Dictionary or not trait_data.get("status_sources") is Array:
			errors.append("trait %s needs status_sources" % item)
			continue
		_validate_sources(item, trait_data.status_sources, data.effects, "on_hit", errors)
	for condition: Variant in data.world_conditions:
		if not condition is Dictionary or not str(condition.get("id", "")).begins_with("world.") or not condition.get("status_sources") is Array:
			errors.append("world conditions need a world.* id and status_sources")
			continue
		_validate_sources(condition.id, condition.status_sources, data.effects, "ambient", errors)
	return errors

static func _validate_effect(effect: String, def: Variant, errors: Array[String]) -> void:
	if not def is Dictionary or not KINDS.has(def.get("kind")):
		errors.append("effect %s needs a supported kind (%s)" % [effect, ", ".join(KINDS.keys())])
		return
	var before := errors.size()
	for key: String in COMMON_EFFECT_KEYS + KINDS[def.kind]:
		if not _number(def.get(key)) or def[key] < 0.0:
			errors.append("effect %s.%s must be a non-negative number" % [effect, key])
	if errors.size() == before:
		if def.threshold <= 0.0 or def.duration <= 0.0:
			errors.append("effect %s needs a positive threshold and duration" % effect)
		if def.kind == "damage_over_time" and def.tick_interval <= 0.0:
			errors.append("effect %s needs a positive tick_interval" % effect)
		if def.kind == "impairment" and (def.move_scale <= 0.0 or def.move_scale > 1.0 or def.handling_scale <= 0.0 or def.handling_scale > 1.0):
			errors.append("effect %s impairment scales must be in (0, 1]: no hard control" % effect)
	if not def.get("while_active") in WHILE_ACTIVE:
		errors.append("effect %s while_active must be refresh or ignore" % effect)
	if def.kind == "damage_over_time" and not def.get("can_kill") is bool:
		errors.append("effect %s can_kill must be a boolean" % effect)

static func _validate_resistances(owner: String, resisted: Variant, effects: Dictionary, errors: Array[String]) -> void:
	if not resisted is Dictionary:
		errors.append("%s resistances must be an object" % owner)
		return
	for effect: String in resisted:
		if not effects.has(effect):
			errors.append("%s resists unknown effect %s" % [owner, effect])
		elif not _number(resisted[effect]) or resisted[effect] < 0.0 or resisted[effect] > MAX_RESISTANCE:
			errors.append("%s resistance to %s must be in 0..%.1f (no immunity)" % [owner, effect, MAX_RESISTANCE])

static func _validate_sources(owner: String, sources: Array, effects: Dictionary, route: String, errors: Array[String]) -> void:
	var amount_key := "buildup" if route == "on_hit" else "buildup_per_second"
	for source: Variant in sources:
		if not source is Dictionary or not effects.has(source.get("effect")) or source.get("route") != route:
			errors.append("%s status source needs a known effect and route %s" % [owner, route])
		elif not _number(source.get(amount_key)) or source[amount_key] <= 0.0:
			errors.append("%s status source %s must be positive" % [owner, amount_key])

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func find_armor(data: Dictionary, id: String) -> Dictionary:
	for armor: Dictionary in data.get("armor", []):
		if armor.id == id:
			return armor
	return {}

static func find_world(data: Dictionary, id: String) -> Dictionary:
	for condition: Dictionary in data.get("world_conditions", []):
		if condition.id == id:
			return condition
	return {}

## Checks a lab loadout's armor list: known ids, one item per armor slot.
static func armor_errors(data: Dictionary, armor_ids: Array) -> Array[String]:
	var errors: Array[String] = []
	var slots := {}
	for id: Variant in armor_ids:
		var armor := find_armor(data, str(id))
		if armor.is_empty():
			errors.append("unknown lab armor: " + str(id))
		elif slots.has(armor.slot):
			errors.append("armor slot occupied twice: " + str(armor.slot))
		else:
			slots[armor.slot] = id
	return errors

## Derives one fighter's resource profile. `handling` is weapon_handling.derive output,
## `striking_item` the catalog id of the weapon that strikes (its traits are the on-hit
## sources), `armor_ids` validated lab armor. `data` may be {} (no armor, no statuses).
static func derive(handling: Dictionary, striking_item: String, armor_ids: Array, data: Dictionary, t: Dictionary) -> Dictionary:
	var mass := 0.0
	var unmitigated := 1.0
	var resistances := {}
	var names: Array[String] = []
	for id: Variant in armor_ids:
		var armor := find_armor(data, str(id))
		if armor.is_empty():
			continue
		names.append(str(armor.name))
		mass += float(armor.mass)
		unmitigated *= 1.0 - float(armor.mitigation)
		for effect: String in armor.resistances:
			resistances[effect] = 1.0 - (1.0 - float(resistances.get(effect, 0.0))) * (1.0 - float(armor.resistances[effect]))
	for effect: String in resistances:
		resistances[effect] = minf(MAX_RESISTANCE, resistances[effect])
	var traits: Dictionary = data.get("traits", {}).get(striking_item, {})
	var evasion_cost: float = 1.0 + t.evasion_cost_per_armor_kg * mass
	return {
		"armor": armor_ids.duplicate(),
		"armor_names": names,
		"armor_mass": mass,
		"mitigation": minf(MAX_MITIGATION, 1.0 - unmitigated),
		"resistances": resistances,
		"element": str(traits.get("element", "")),
		"status_sources": traits.get("status_sources", []).duplicate(true),
		"effects": data.get("effects", {}),
		"routing": data.get("routing", {}),
		"stamina_max": t.stamina_max,
		"stamina_regen": t.stamina_regen * maxf(0.25, 1.0 - t.armor_regen_penalty_per_kg * mass),
		"stamina_regen_delay": t.stamina_regen_delay,
		"stamina_empty_regen_delay": t.stamina_empty_regen_delay,
		"attack_cost": t.attack_cost_base + t.attack_cost_per_inertia * handling.inertia + t.attack_cost_per_armor_kg * mass,
		"dodge_cost": t.dodge_cost * evasion_cost,
		"roll_cost": t.roll_cost * evasion_cost,
		"move_scale": maxf(t.armor_min_move_scale, 1.0 - t.armor_move_penalty_per_kg * mass),
		"evasion_speed_scale": maxf(t.armor_min_move_scale, 1.0 - t.armor_evasion_speed_penalty_per_kg * mass),
	}
