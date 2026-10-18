extends RefCounted
## The only bridge from validated, resolved build data to the courtyard rules.
## No input, AI, animation, movement integration or node creation belongs here.

const Catalog = preload("res://scripts/builds/build_catalog.gd")
const BuildRules = preload("res://scripts/builds/build_rules.gd")
const CombatRules = preload("res://scripts/combat/combat_state.gd")
const BUILDS_PATH := "res://data/builds/courtyard.json"
const ACTOR_STATS := ["max_health", "max_posture", "deflect_window", "guard_chip",
	"posture_recovery_rate", "posture_recovery_delay", "deflect_posture"]
const AttackModules = preload("res://scripts/combat/attack_modules.gd")
const MODULES := AttackModules.MODULES
const COMBAT_FIELDS := ACTOR_STATS + ["guard_posture_overrides", "attack_windup", "heavy_windup",
	"light_active_duration", "heavy_active_duration", "light_recovery_duration", "heavy_recovery_duration",
	"light_damage", "heavy_damage", "light_hit_posture", "heavy_hit_posture",
	"light_guard_posture", "heavy_guard_posture"]
var catalog: Catalog
var resolver: BuildRules

func _init(source_catalog: Catalog) -> void:
	catalog = source_catalog
	resolver = BuildRules.new(catalog)

static func failure(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "configs": {}, "resolved": {}, "states": {}}

static func load_encounter(catalog_path := Catalog.CATALOG_PATH, builds_path := BUILDS_PATH) -> Dictionary:
	var source := Catalog.new()
	if not source.load_file(catalog_path):
		return failure(source.errors)
	if not FileAccess.file_exists(builds_path):
		return failure(["missing encounter builds file: " + builds_path])
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(builds_path)) != OK:
		return failure(["invalid encounter builds JSON: " + builds_path])
	var adapter := new(source)
	var prepared := adapter.prepare_encounter(parser.data)
	if prepared.ok:
		prepared.adapter = adapter
		prepared.builds = parser.data
	return prepared

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
	var states := {}
	for actor in ["player", "enemy"]:
		var result: Dictionary = resolver.resolve(builds[actor])
		if not result.ok:
			return failure([{"actor": actor, "build_errors": result.errors}])
		var translated := _from_resolved(result.resolved)
		if not translated.ok:
			return failure([{"actor": actor, "compatibility_errors": translated.errors}])
		var constructed := create_state(translated.config)
		if not constructed.ok:
			return failure([{"actor": actor, "state_errors": constructed.errors}])
		states[actor] = constructed.state
		configs[actor] = translated.config
		resolved[actor] = result.resolved
	return {"ok": true, "errors": [], "configs": configs, "resolved": resolved, "states": states}

## Private: only called on a fresh successful resolution, never on saved or
## caller-supplied effective values. Unsupported abilities fail instead of vanishing.
func _from_resolved(resolved: Dictionary) -> Dictionary:
	for stat in ACTOR_STATS + ["move_speed"]:
		var value: Variant = resolved.stats[stat]
		if not _nonnegative_number(value):
			return {"ok": false, "errors": ["invalid resolved courtyard stat: " + stat]}
	if resolved.stats.max_health <= 0.0 or resolved.stats.max_posture <= 0.0 or resolved.stats.guard_chip > 1.0:
		return {"ok": false, "errors": ["invalid courtyard health, posture or chip range"]}
	var attacks := {}
	for ability in resolved.abilities:
		if not MODULES.has(ability.binding) or ability.module != MODULES[ability.binding]:
			return {"ok": false, "errors": ["unsupported courtyard ability: " + ability.id]}
		var attack: Dictionary = ability.effective
		for key in attack:
			if not _nonnegative_number(attack[key]):
				return {"ok": false, "errors": ["invalid resolved attack value: " + ability.id + "." + key]}
		# Curated modules own supported shape bounds; both the runtime query and
		# presentation consume the validated signature dimensions.
		if not AttackModules.shape_supported(ability.binding, attack.reach, attack.width):
			return {"ok": false, "errors": ["unsupported module hit shape: " + ability.id]}
		if attack.windup <= 0.24 or attack.active <= 0.0 or attack.recovery <= 0.0:
			return {"ok": false, "errors": ["unsupported module timing: " + ability.id]}
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
	var config := {"combat": state, "move_speed": resolved.stats.move_speed}
	if attacks.has("special"):
		config.signature = attacks.special.duplicate(true)
	return {"ok": true, "errors": [], "config": config}

## Validate configuration before allocating a state, then check every target before
## assignment. No error result owns a partial state. Godot can defer checking typed
## member assignments until execution.
static func create_state(config: Variant) -> Dictionary:
	var errors := _config_errors(config)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "state": null}
	var values: Dictionary = config.combat
	var state: CombatRules = CombatRules.new()
	for field: String in COMBAT_FIELDS:
		if field not in state:
			return {"ok": false, "errors": [{"code": "missing_state_property", "field": field}], "state": null}
		if typeof(state.get(field)) != (TYPE_DICTIONARY if field == "guard_posture_overrides" else TYPE_FLOAT):
			return {"ok": false, "errors": [{"code": "invalid_state_property_type", "field": field}], "state": null}
	state.max_health = values.max_health
	state.max_posture = values.max_posture
	state.deflect_window = values.deflect_window
	state.guard_chip = values.guard_chip
	state.posture_recovery_rate = values.posture_recovery_rate
	state.posture_recovery_delay = values.posture_recovery_delay
	state.deflect_posture = values.deflect_posture
	state.attack_windup = values.attack_windup
	state.heavy_windup = values.heavy_windup
	state.light_active_duration = values.light_active_duration
	state.heavy_active_duration = values.heavy_active_duration
	state.light_recovery_duration = values.light_recovery_duration
	state.heavy_recovery_duration = values.heavy_recovery_duration
	state.light_damage = values.light_damage
	state.heavy_damage = values.heavy_damage
	state.light_hit_posture = values.light_hit_posture
	state.heavy_hit_posture = values.heavy_hit_posture
	state.light_guard_posture = values.light_guard_posture
	state.heavy_guard_posture = values.heavy_guard_posture
	# Binding-keyed defense costs remain data, never Object property names.
	state.guard_posture_overrides = values.guard_posture_overrides.duplicate(true)
	if config.has("signature"):
		state.signature = config.signature.duplicate(true)
		state.signature.make_read_only()
	state.reset()
	return {"ok": true, "errors": [], "state": state}

static func _nonnegative_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value >= 0.0

static func _config_errors(config: Variant) -> Array:
	if not config is Dictionary:
		return [{"code": "invalid_state_config"}]
	for field: Variant in config:
		if field not in ["combat", "move_speed", "signature"]:
			return [{"code": "unknown_config_field", "field": str(field)}]
	if not config.has_all(["combat", "move_speed"]) or not config.combat is Dictionary:
		return [{"code": "invalid_state_config"}]
	if not _nonnegative_number(config.move_speed):
		return [{"code": "invalid_parameter_value", "field": "move_speed"}]
	if config.has("signature"):
		var signature_errors := AttackModules.signature_errors(config.signature)
		if not signature_errors.is_empty():
			return signature_errors
	var values: Dictionary = config.combat
	for field: Variant in values:
		if field not in COMBAT_FIELDS:
			return [{"code": "unknown_combat_parameter", "field": str(field)}]
	for field: String in COMBAT_FIELDS:
		if not values.has(field):
			return [{"code": "missing_combat_parameter", "field": field}]
		if field != "guard_posture_overrides" and not _nonnegative_number(values[field]):
			return [{"code": "invalid_parameter_value", "field": field}]
	for field: String in ["max_health", "max_posture", "light_active_duration", "heavy_active_duration",
		"light_recovery_duration", "heavy_recovery_duration"]:
		if values[field] <= 0.0:
			return [{"code": "unsupported_parameter_value", "field": field}]
	for field: String in ["attack_windup", "heavy_windup"]:
		if values[field] <= 0.24:
			return [{"code": "unsupported_parameter_value", "field": field}]
	if values.guard_chip > 1.0:
		return [{"code": "unsupported_parameter_value", "field": "guard_chip"}]
	if not values.guard_posture_overrides is Dictionary:
		return [{"code": "invalid_guard_posture_overrides"}]
	for binding: Variant in values.guard_posture_overrides:
		if not MODULES.has(binding) or not _nonnegative_number(values.guard_posture_overrides[binding]):
			return [{"code": "invalid_guard_posture_override", "binding": str(binding)}]
	return []
