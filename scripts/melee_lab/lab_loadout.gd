extends RefCounted
## Lab-only bridge from the shared build foundation to directional melee. The shared
## catalog file is read, never written: lab weapon items are appended in memory and the
## combined catalog goes through the same catalog validation and BuildRules resolution
## as production builds. The lab then reads `resolved.equipment.weapons`, exactly the
## view EQUIPMENT_FOUNDATION.md §5 reserves for directional melee. Nothing in
## production references this file.

const Catalog = preload("res://scripts/builds/build_catalog.gd")
const BuildRules = preload("res://scripts/builds/build_rules.gd")
const WEAPONS_PATH := "res://data/melee_lab/weapons.json"
const TUNING_PATH := "res://data/melee_lab/tuning.json"
const WEAPONS_SCHEMA := "boneshed.melee_lab_weapons.v0"
const TUNING_SCHEMA := "boneshed.melee_lab_tuning.v0"
## Profile stats the lab consumes; everything else about the duel is lab tuning.
const PROFILE_STATS := ["max_health", "max_posture", "move_speed", "deflect_window", "posture_recovery_rate", "posture_recovery_delay"]

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data

## Returns {"ok", "errors", "values"}. Every value must be a finite number.
static func load_tuning(path := TUNING_PATH) -> Dictionary:
	return tuning_from_data(read_json(path))

static func tuning_from_data(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("schema") != TUNING_SCHEMA or not data.get("values") is Dictionary:
		return {"ok": false, "errors": ["invalid lab tuning data"], "values": {}}
	var values: Dictionary = data.values
	for key: Variant in values:
		var value: Variant = values[key]
		if not (value is float or value is int) or not is_finite(float(value)):
			return {"ok": false, "errors": ["lab tuning value is not a finite number: " + str(key)], "values": {}}
	var floats := {}
	for key: String in values:
		floats[key] = float(values[key])
	return {"ok": true, "errors": [], "values": floats}

## Returns {"ok", "errors", "rules", "loadouts", "profiles"}.
static func load_lab(catalog_path := Catalog.CATALOG_PATH, weapons_path := WEAPONS_PATH) -> Dictionary:
	return lab_from_data(read_json(catalog_path), read_json(weapons_path))

static func lab_from_data(base: Variant, lab: Variant) -> Dictionary:
	if not base is Dictionary:
		return _failure(["missing or invalid shared catalog"])
	if not lab is Dictionary or lab.get("schema") != WEAPONS_SCHEMA:
		return _failure(["missing or invalid lab weapons data"])
	if not lab.get("items") is Array or not lab.get("loadouts") is Array or not lab.get("profiles") is Dictionary:
		return _failure(["lab weapons file needs items, loadouts and profiles"])
	var combined: Dictionary = base.duplicate(true)
	combined.items = combined.items + lab.items.duplicate(true)
	combined.catalog_version = str(lab.get("catalog_version", ""))
	var catalog := Catalog.new()
	if not catalog.load_data(combined):
		return _failure(catalog.errors)
	return {"ok": true, "errors": [], "rules": BuildRules.new(catalog), "loadouts": lab.loadouts.duplicate(true),
		"profiles": lab.profiles.duplicate(true)}

## Resolves one actor through the shared build rules. Returns {"ok", "errors", "weapon",
## "stats", "label"} where `weapon` is the first held (non-natural) weapon view.
static func resolve(lab: Dictionary, role: String, loadout_id: String) -> Dictionary:
	var loadout: Dictionary = {}
	for candidate: Dictionary in lab.loadouts:
		if candidate.get("id") == loadout_id:
			loadout = candidate
	if loadout.is_empty() or not lab.profiles.has(role):
		return {"ok": false, "errors": ["unknown lab loadout or role: %s/%s" % [role, loadout_id]]}
	var rules: BuildRules = lab.rules
	var build: Dictionary = rules.new_build("melee_lab." + role, lab.profiles[role])
	build.equipped = loadout.equipped.duplicate(true)
	var result: Dictionary = rules.resolve(build)
	if not result.ok:
		return {"ok": false, "errors": result.errors}
	var held: Array = result.resolved.equipment.weapons.filter(func(w: Dictionary) -> bool: return not w.natural)
	if held.is_empty():
		return {"ok": false, "errors": ["lab loadout holds no weapon: " + loadout_id]}
	var stats := {}
	for stat: String in PROFILE_STATS:
		stats[stat] = float(result.resolved.stats[stat])
	return {"ok": true, "errors": [], "weapon": held[0], "stats": stats, "label": str(loadout.get("label", loadout_id))}

static func _failure(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "rules": null, "loadouts": [], "profiles": {}}
