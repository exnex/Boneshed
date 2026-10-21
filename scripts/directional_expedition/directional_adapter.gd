extends RefCounted
## The single bridge from shared build data to directional combat in the integrated
## expedition. Both the player and every soul go through `resolve_fighter`, which
## uses the melee lab's own adapter path: the shared catalog file is read, the lab
## weapon items are appended in memory, the combined catalog is validated by
## build_catalog.gd and resolved by build_rules.gd, and stamina, mobility, mitigation,
## resistances and status sources are derived from the equipped items by
## combat_resources.gd. Nothing here owns a second health/posture model: the result
## feeds the lab's duelist_state.gd only. Shared data files are never written.
##
## Version note: the shared builds are stamped with the shared catalog version. They
## are first validated against that unmodified catalog, then re-stamped with the
## combined (superset) catalog version so the same item ids resolve with the lab
## weapons available. A build invalid in the shared catalog is rejected.

const Catalog = preload("res://scripts/builds/build_catalog.gd")
const BuildRules = preload("res://scripts/builds/build_rules.gd")
const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const DATA_PATH := "res://data/directional_expedition/encounters.json"
const SCHEMA := "boneshed.directional_expedition.v0"
const SIGNATURE_KEYS := ["windup", "recovery", "reach", "health_damage", "posture_damage"]

var ok := false
var errors: Array = []
var tuning: Dictionary = {}
var rules: BuildRules
var catalog: Catalog
var combat: Dictionary = {}
var data: Dictionary = {}
## Shared builds re-stamped for the combined catalog: {"player", "enemy"}.
var builds: Dictionary = {}

static func load_default(catalog_path := Catalog.CATALOG_PATH, data_path := DATA_PATH) -> RefCounted:
	var adapter = new()
	adapter._load(catalog_path, data_path)
	return adapter

func _load(catalog_path: String, data_path: String) -> void:
	var tuned := Loadout.load_tuning()
	if not tuned.ok:
		_fail(tuned.errors)
		return
	tuning = tuned.values
	var raw: Variant = Loadout.read_json(data_path)
	if not raw is Dictionary or raw.get("schema") != SCHEMA:
		_fail(["missing or invalid directional expedition data: " + data_path])
		return
	data = raw
	var lab := Loadout.lab_from_data(Loadout.read_json(catalog_path), Loadout.read_json(Loadout.WEAPONS_PATH), Loadout.read_json(CombatResources.PATH))
	if not lab.ok:
		_fail(lab.errors)
		return
	rules = lab.rules
	catalog = rules.catalog
	combat = lab.combat
	# The shared builds must be valid in the unmodified shared catalog first.
	var shared := Catalog.new()
	if not shared.load_file(catalog_path):
		_fail(shared.errors)
		return
	var shared_builds: Variant = Loadout.read_json(str(data.get("builds_path", "")))
	if not shared_builds is Dictionary or not shared_builds.has_all(["player", "enemy"]):
		_fail(["shared builds file needs player and enemy"])
		return
	var shared_rules := BuildRules.new(shared)
	for role: String in ["player", "enemy"]:
		var problems: Array = shared_rules.validate(shared_builds[role])
		if not problems.is_empty():
			_fail([{"role": role, "shared_build_errors": problems}])
			return
		var restamped: Dictionary = shared_builds[role].duplicate(true)
		restamped.catalog_version = catalog.version
		builds[role] = restamped
	var problems := _data_errors()
	if not problems.is_empty():
		_fail(problems)
		return
	ok = true

func _fail(found: Array) -> void:
	ok = false
	errors = found

func _data_errors() -> Array:
	var found: Array = []
	var encounters: Variant = data.get("encounters")
	if not data.get("player") is Dictionary or not encounters is Dictionary or not encounters.get("exterior") is Array \
			or encounters.exterior.is_empty() or not encounters.get("guardian") is Dictionary or not data.get("signature") is Dictionary:
		return ["directional expedition data needs player, encounters.exterior[], encounters.guardian and signature"]
	var variants: Array = encounters.exterior + [encounters.guardian]
	found.append_array(CombatResources.armor_errors(combat, data.player.get("armor", [])))
	for variant: Variant in variants:
		if not variant is Dictionary or not variant.get("equipped") is Dictionary or str(variant.get("id", "")) == "":
			found.append("encounter variants need an id and equipped items")
			continue
		found.append_array(CombatResources.armor_errors(combat, variant.get("armor", [])))
		var resolved := resolve_fighter(enemy_build(variant, "validation." + str(variant.id)), variant.get("armor", []), str(variant.get("label", variant.id)))
		if not resolved.ok:
			found.append({"variant": variant.id, "errors": resolved.errors})
	for key: String in ["mass", "balance", "cost_scale"]:
		var value: Variant = data.signature.get(key)
		if not (value is float or value is int) or float(value) <= 0.0:
			found.append("signature.%s must be a positive number" % key)
	return found

## The soul build for an encounter variant: the shared enemy build (profile, schema)
## with the variant's equipped items and a per-site build id.
func enemy_build(variant: Dictionary, build_id: String) -> Dictionary:
	var build: Dictionary = builds.enemy.duplicate(true)
	build.build_id = build_id
	build.equipped = variant.equipped.duplicate(true)
	return build

func exterior_variant(index: int) -> Dictionary:
	var list: Array = data.encounters.exterior
	return list[index % list.size()]

func guardian_variant() -> Dictionary:
	return data.encounters.guardian

## Resolves one fighter through the shared rules. Returns {"ok", "errors", "weapon",
## "stats", "label", "armor", "combat", "signature", "build"}; the same shape the lab's
## duelists consume, plus `signature` ({} unless the build grants the legacy lunge).
func resolve_fighter(build: Dictionary, armor: Array, label: String) -> Dictionary:
	var armor_problems := CombatResources.armor_errors(combat, armor)
	if not armor_problems.is_empty():
		return {"ok": false, "errors": armor_problems}
	var result: Dictionary = rules.resolve(build)
	if not result.ok:
		return {"ok": false, "errors": result.errors}
	var held: Array = result.resolved.equipment.weapons.filter(func(w: Dictionary) -> bool: return not w.natural)
	if held.is_empty():
		return {"ok": false, "errors": ["build holds no weapon: " + str(build.build_id)]}
	var stats := {}
	for stat: String in Loadout.PROFILE_STATS:
		stats[stat] = float(result.resolved.stats[stat])
	return {"ok": true, "errors": [], "weapon": held[0], "stats": stats, "label": label, "id": str(build.build_id),
		"armor": armor.duplicate(), "combat": combat, "signature": _signature(result.resolved), "build": build}

## Directional thrust parameters for the legacy `special` ability, read from the
## shared ability values (never from a controller).
func _signature(resolved: Dictionary) -> Dictionary:
	var id: String = data.signature.ability
	for ability: Dictionary in resolved.abilities:
		if ability.id != id or ability.binding != "special":
			continue
		var effective: Dictionary = ability.effective
		for key: String in SIGNATURE_KEYS:
			if not effective.has(key):
				return {}
		return {"id": id, "name": str(catalog.abilities[id].name), "windup": float(effective.windup),
			"recovery": float(effective.recovery), "reach": float(effective.reach),
			"health_damage": float(effective.health_damage), "posture_damage": float(effective.posture_damage),
			"mass": float(data.signature.mass), "balance": float(data.signature.balance),
			"cost_scale": float(data.signature.cost_scale)}
	return {}

## Both fighters of one encounter must resolve before either is equipped.
func prepare(player_build: Dictionary, enemy: Dictionary, enemy_variant: Dictionary) -> Dictionary:
	var player := resolve_fighter(player_build, data.player.get("armor", []), str(data.player.get("label", "Pilgrim")))
	if not player.ok:
		return {"ok": false, "errors": [{"actor": "player", "errors": player.errors}]}
	var foe := resolve_fighter(enemy, enemy_variant.get("armor", []), str(enemy_variant.get("label", enemy_variant.id)))
	if not foe.ok:
		return {"ok": false, "errors": [{"actor": "enemy", "errors": foe.errors}]}
	return {"ok": true, "errors": [], "player": player, "enemy": foe}
