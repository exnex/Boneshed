extends RefCounted
## The only bridge from validated, resolved build data to the courtyard rules.
## No input, AI, animation, movement integration or node creation belongs here.

const Catalog = preload("res://scripts/builds/build_catalog.gd")
const BuildRules = preload("res://scripts/builds/build_rules.gd")
const CombatRules = preload("res://scripts/combat/combat_state.gd")
const BUILDS_PATH := "res://data/builds/courtyard.json"
const ACTOR_STATS := ["max_health", "max_posture", "deflect_window", "guard_chip",
	"posture_recovery_rate", "posture_recovery_delay", "deflect_posture"]
const MODULES := {"light": "module.slash_basic", "heavy": "module.slash_heavy"}
var catalog
var resolver

func _init(source_catalog) -> void:
	catalog = source_catalog
	resolver = BuildRules.new(catalog)

static func failure(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "configs": {}, "resolved": {}}

static func load_encounter(catalog_path := Catalog.CATALOG_PATH, builds_path := BUILDS_PATH) -> Dictionary:
	var source = Catalog.new()
	if not source.load_file(catalog_path):
		return failure(source.errors)
	if not FileAccess.file_exists(builds_path):
		return failure(["missing encounter builds file: " + builds_path])
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(builds_path)) != OK:
		return failure(["invalid encounter builds JSON: " + builds_path])
	return new(source).prepare_encounter(parser.data)

## Transaction boundary: both actors must resolve and be executable before either
## fighter can be created. Never return the first actor's partial configuration.
func prepare_encounter(builds: Variant) -> Dictionary:
	if not builds is Dictionary or builds.size() != 2 or not builds.has_all(["player", "enemy"]):
		return failure(["encounter builds must contain exactly player and enemy"])
	if not catalog.errors.is_empty() or catalog.fingerprint.is_empty():
		return failure(["invalid or unloaded catalog"])
	for stat in ACTOR_STATS + ["move_speed", "windup_scale", "recovery_scale"]:
		if not catalog.stats.has(stat):
			return failure(["courtyard catalog missing stat: " + stat])
	var configs := {}
	var resolved := {}
	for actor in ["player", "enemy"]:
		var result: Dictionary = resolver.resolve(builds[actor])
		if not result.ok:
			return failure([{"actor": actor, "build_errors": result.errors}])
		var translated := _from_resolved(result.resolved)
		if not translated.ok:
			return failure([{"actor": actor, "compatibility_errors": translated.errors}])
		configs[actor] = translated.config
		resolved[actor] = result.resolved
	return {"ok": true, "errors": [], "configs": configs, "resolved": resolved}

## Private: only called on a fresh successful resolution, never on saved or
## caller-supplied effective values. Unsupported abilities fail instead of vanishing.
func _from_resolved(resolved: Dictionary) -> Dictionary:
	for stat in ACTOR_STATS + ["move_speed"]:
		var value = resolved.stats[stat]
		if not is_finite(value) or value < 0.0:
			return {"ok": false, "errors": ["invalid resolved courtyard stat: " + stat]}
	if resolved.stats.max_health <= 0.0 or resolved.stats.max_posture <= 0.0 or resolved.stats.guard_chip > 1.0:
		return {"ok": false, "errors": ["invalid courtyard health, posture or chip range"]}
	var attacks := {}
	for ability in resolved.abilities:
		if not MODULES.has(ability.binding) or ability.module != MODULES[ability.binding]:
			return {"ok": false, "errors": ["unsupported courtyard ability: " + ability.id]}
		var attack: Dictionary = ability.effective
		for key in attack:
			if not is_finite(attack[key]) or attack[key] < 0.0:
				return {"ok": false, "errors": ["invalid resolved attack value: " + ability.id + "." + key]}
		# The curated sword presentation and physics volume still own their shape.
		# A future module must integrate its own geometry before it can run here.
		if attack.reach != 2.35 or attack.width != 1.6:
			return {"ok": false, "errors": ["unsupported sword hit shape: " + ability.id]}
		if attack.windup <= 0.24 or attack.active <= 0.0 or attack.recovery <= 0.0:
			return {"ok": false, "errors": ["unsupported sword timing: " + ability.id]}
		attacks[ability.binding] = attack
	if not attacks.has_all(["light", "heavy"]):
		return {"ok": false, "errors": ["courtyard requires light and heavy sword modules"]}
	var state := {}
	for stat in ACTOR_STATS:
		state[stat] = resolved.stats[stat]
	state.guard_posture_overrides = resolved.guard_posture_overrides.duplicate(true)
	for binding in ["light", "heavy"]:
		var attack: Dictionary = attacks[binding]
		state["attack_windup" if binding == "light" else "heavy_windup"] = attack.windup
		state[binding + "_active_duration"] = attack.active
		state[binding + "_recovery_duration"] = attack.recovery
		state[binding + "_damage"] = attack.health_damage
		state[binding + "_hit_posture"] = attack.posture_damage
		state[binding + "_guard_posture"] = attack.guard_posture
	return {"ok": true, "errors": [], "config": {"combat": state, "move_speed": resolved.stats.move_speed}}

## Only prepared configurations reach this function. Set every parameter on a new
## state before resetting its health; no existing fighter can be partly reconfigured.
static func create_state(config: Dictionary) -> CombatState:
	var state := CombatRules.new()
	for field in config.combat:
		state.set(field, config.combat[field].duplicate(true) if config.combat[field] is Dictionary else config.combat[field])
	state.reset()
	return state
