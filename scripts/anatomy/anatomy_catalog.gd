extends RefCounted
## Loads, validates and freezes the provisional anatomy catalog: socket and mount
## types, capabilities, curated animation modules, body parts, the equipment that
## mounts on them, and capability requirements for abilities.
##
## Parts form a body graph through typed sockets. Only a `core` part may be the root
## and it always carries every stable gameplay anchor (movement, camera, facing, core
## hurtbox), so limbs can change without moving the combat reference frame. Gameplay
## and visual metadata are separate keys so presentation can change without touching
## gameplay identity. Standalone: no shared-build, combat, scene or world-generation dependency.

const SCHEMA := "boneshed.anatomy_catalog.v0"
const CATALOG_PATH := "res://data/anatomy/catalog.json"
const KINDS := ["arm", "core", "head", "legs", "tail"]
const SIDES := ["center", "left", "right"]
const DOMAINS := ["gameplay", "visual"]
## A body has one facing; no part may guard behind or around it in v0.
const GUARDS := ["front", "none"]
const OWNER_KEYS := ["owner", "controller", "faction", "player_only", "enemy_only"]
const CATALOG_KEYS := ["animation_modules", "build_catalog_version", "capabilities", "catalog_version", "classes", "equipment", "limits", "mount_types", "parts", "provisional", "readability", "required_anchors", "requirements", "schema", "socket_types"]
const LIMIT_KEYS := ["max_depth", "max_nodes"]
const CLASS_KEYS := ["hurt", "reach"]
const READABILITY_KEYS := ["baseline_kind_counts", "baseline_locomotion", "locomotion_prefix", "offense_prefix", "review_hurt", "review_reach"]
const MODULE_KEYS := ["id", "kind", "notes"]
const PART_KEYS := ["anchors", "animation_module", "attaches_to", "build_item", "excludes_tags", "gameplay", "id", "kind", "mounts", "name", "proportions", "provides", "requires_tags", "sockets", "tags", "visual"]
const SOCKET_KEYS := ["id", "pair", "side", "type"]
const MOUNT_KEYS := ["id", "type"]
const PROPORTION_KEYS := ["default", "domain", "id", "max", "min"]
const GAMEPLAY_KEYS := ["attack_origin", "guard", "hurt_class", "reach_class"]
const EQUIPMENT_KEYS := ["build_item", "excludes_part_tags", "fixture", "id", "mount_count", "mounts_on", "name", "paired", "provides", "requires_capabilities"]
const REQUIREMENT_KEYS := ["all", "fixture", "id", "none"]
const TERM_KEYS := ["capability", "count"]

var version := ""
var build_catalog_version := ""
## Digest of the canonical catalog; changes whenever any definition changes.
var fingerprint := ""
var limits := {}
var required_anchors: Array = []
var classes := {}
var readability := {}
var socket_types: Array = []
var mount_types: Array = []
var capabilities: Array = []
var modules := {}
var parts := {}
var equipment := {}
var requirements := {}
var requirement_order: Array = []
var errors: Array[String] = []

var _def_id := RegEx.create_from_string("^[a-z]+(\\.[a-z0-9_]+)+$")
var _plain_id := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$")

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
	for table in [modules, parts, equipment, requirements]:
		table.clear()
	requirement_order.clear()
	var source: Dictionary = data.duplicate(true)
	_keys(source, CATALOG_KEYS, "catalog")
	if source.get("schema") != SCHEMA:
		errors.append("unsupported catalog schema '%s'" % str(source.get("schema")))
		return false
	version = str(source.get("catalog_version", ""))
	build_catalog_version = str(source.get("build_catalog_version", ""))
	if version.is_empty():
		errors.append("catalog_version is empty")
	limits = _object(source, "limits", LIMIT_KEYS)
	classes = _object(source, "classes", CLASS_KEYS)
	readability = _object(source, "readability", READABILITY_KEYS)
	required_anchors = _id_list(source.get("required_anchors"), "required_anchors")
	socket_types = _id_list(source.get("socket_types"), "socket_types")
	mount_types = _id_list(source.get("mount_types"), "mount_types")
	capabilities = _id_list(source.get("capabilities"), "capabilities")
	_index(source.get("animation_modules", []), modules, [], "animation module")
	_index(source.get("parts", []), parts, [], "part")
	_index(source.get("equipment", []), equipment, [], "equipment")
	_index(source.get("requirements", []), requirements, requirement_order, "requirement")
	requirement_order.sort()
	_validate_settings()
	_validate_modules()
	_validate_parts()
	_validate_equipment()
	_validate_requirements()
	_reject_owner_keys(source, "catalog")
	for value in [limits, classes, readability, required_anchors, socket_types, mount_types, capabilities, modules, parts, equipment, requirements]:
		_freeze(value)
	fingerprint = digest(source)
	return errors.is_empty()

func part_fingerprint(id: String) -> String:
	return digest(parts[id]) if parts.has(id) else ""

## Fingerprint of only the gameplay-relevant fields of a part, so visual edits
## (silhouette, materials, visual-domain proportions) never change gameplay identity.
func part_gameplay_fingerprint(id: String) -> String:
	if not parts.has(id):
		return ""
	var part: Dictionary = parts[id]
	var view := {}
	for key in PART_KEYS:
		if key != "visual" and key != "name":
			view[key] = part[key]
	view["proportions"] = part.proportions.filter(func(p): return p.domain == "gameplay")
	return digest(view)

static func canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true)

static func digest(value: Variant) -> String:
	return canonical_json(value).sha256_text().substr(0, 16)

func _validate_settings() -> void:
	for key in LIMIT_KEYS:
		if not _count(limits.get(key)):
			errors.append("limits.%s must be a positive integer" % key)
	for key in CLASS_KEYS:
		# Classes are ordered smallest to largest, so they are not required to be sorted.
		if _id_list(classes.get(key), "classes." + key, false).is_empty():
			errors.append("classes.%s must list at least one class" % key)
	for key in ["locomotion_prefix", "offense_prefix"]:
		if not readability.get(key) is String or str(readability.get(key)).is_empty():
			errors.append("readability.%s must be text" % key)
	if not readability.get("baseline_locomotion") in capabilities:
		errors.append("readability.baseline_locomotion is not a known capability")
	for pair in [["review_reach", "reach"], ["review_hurt", "hurt"]]:
		var listed = readability.get(pair[0])
		if not listed is Array or listed.any(func(c): return not c in classes.get(pair[1], [])):
			errors.append("readability.%s must list known %s classes" % pair)
	var counts = readability.get("baseline_kind_counts")
	if not counts is Dictionary or counts.keys().any(func(k): return not k in KINDS) or counts.values().any(func(v): return not _count(v)):
		errors.append("readability.baseline_kind_counts must map part kinds to positive integers")
	if required_anchors.is_empty():
		errors.append("required_anchors must not be empty")

func _validate_modules() -> void:
	for id in modules:
		_keys(modules[id], MODULE_KEYS, "animation module " + id)
		if not modules[id].get("kind") in ["appendage", "core", "head", "limb", "locomotion"]:
			errors.append("animation module %s has unknown kind" % id)

func _validate_parts() -> void:
	for id in _sorted(parts.keys()):
		var part: Dictionary = parts[id]
		var where: String = "part " + id
		_keys(part, PART_KEYS, where)
		if not part.get("kind") in KINDS:
			errors.append("%s has unknown kind" % where)
		for field in ["attaches_to", "anchors", "provides", "tags", "requires_tags", "excludes_tags"]:
			_tag_list(part, field, where)
		var core: bool = part.get("kind") == "core"
		if core and (not part.get("attaches_to", []).is_empty() or _sorted(part.get("anchors", [])) != _sorted(required_anchors)):
			errors.append("%s is a core: it attaches to nothing and carries exactly the required anchors" % where)
		if not core and (part.get("attaches_to", []).is_empty() or not part.get("anchors", []).is_empty()):
			errors.append("%s must attach to a socket type and carry no anchors" % where)
		for type in part.get("attaches_to", []):
			if not type in socket_types:
				errors.append("%s attaches to unknown socket type '%s'" % [where, type])
		for capability in part.get("provides", []):
			if not capability in capabilities:
				errors.append("%s provides unknown capability '%s'" % [where, capability])
		for tag in part.get("excludes_tags", []):
			if tag in part.get("tags", []):
				errors.append("%s excludes a tag it carries" % where)
		_entries(part.get("sockets"), SOCKET_KEYS, where + " socket", _check_socket)
		_entries(part.get("mounts"), MOUNT_KEYS, where + " mount", _check_mount)
		_entries(part.get("proportions"), PROPORTION_KEYS, where + " proportion", _check_proportion)
		if not modules.has(str(part.get("animation_module"))):
			errors.append("%s uses unknown animation module" % where)
		if not part.get("build_item") is String:
			errors.append("%s build_item must be text (may be empty)" % where)
		_validate_gameplay(part, where)
		if not part.get("visual") is Dictionary:
			errors.append("%s visual must be an object" % where)
		else:
			for key in part.visual:
				if key in GAMEPLAY_KEYS or key in ["anchors", "provides", "mounts", "sockets"]:
					errors.append("%s visual metadata contains gameplay key '%s'" % [where, key])

func _validate_gameplay(part: Dictionary, where: String) -> void:
	var gameplay = part.get("gameplay")
	if not gameplay is Dictionary:
		errors.append("%s gameplay must be an object" % where)
		return
	_keys(gameplay, GAMEPLAY_KEYS, where + " gameplay")
	if not gameplay.get("hurt_class") in classes.get("hurt", []):
		errors.append("%s has unknown hurt class" % where)
	if not gameplay.get("reach_class") in classes.get("reach", []):
		errors.append("%s has unknown reach class" % where)
	if not gameplay.get("guard") in GUARDS:
		errors.append("%s guard must be front or none (one facing per body)" % where)
	if not gameplay.get("attack_origin") is String:
		errors.append("%s attack_origin must be text" % where)
	# Readability rule: anything that can strike declares where its attack visibly starts.
	var offensive: bool = part.get("provides", []).any(func(c): return str(c).begins_with(str(readability.get("offense_prefix", "strike."))))
	if (offensive or not part.get("mounts", []).is_empty()) and str(gameplay.get("attack_origin", "")).is_empty():
		errors.append("%s can strike or hold equipment but declares no attack origin" % where)

func _validate_equipment() -> void:
	for id in _sorted(equipment.keys()):
		var entry: Dictionary = equipment[id]
		var where: String = "equipment " + id
		_keys(entry, EQUIPMENT_KEYS, where)
		for field in ["mounts_on", "provides", "requires_capabilities", "excludes_part_tags"]:
			_tag_list(entry, field, where)
		for type in entry.get("mounts_on", []):
			if not type in mount_types:
				errors.append("%s mounts on unknown type '%s'" % [where, type])
		for field in ["provides", "requires_capabilities"]:
			for capability in entry.get(field, []):
				if not capability in capabilities:
					errors.append("%s %s unknown capability '%s'" % [where, field, capability])
		if not _count(entry.get("mount_count")):
			errors.append("%s mount_count must be a positive integer" % where)
		if not entry.get("paired") is bool or not entry.get("fixture") is bool or not entry.get("build_item") is String:
			errors.append("%s paired and fixture must be booleans and build_item text" % where)
		elif entry.paired and entry.get("mount_count") != 2:
			errors.append("%s is paired so it needs exactly two mounts" % where)

func _validate_requirements() -> void:
	var available := {}
	for part in parts.values():
		for capability in part.get("provides", []):
			available[capability] = true
	for entry in equipment.values():
		for capability in entry.get("provides", []):
			available[capability] = true
	for id in requirement_order:
		var requirement: Dictionary = requirements[id]
		var where: String = "requirement " + id
		_keys(requirement, REQUIREMENT_KEYS, where)
		if not requirement.get("fixture") is bool:
			errors.append("%s fixture must be a boolean" % where)
		_tag_list(requirement, "none", where)
		_entries(requirement.get("all"), TERM_KEYS, where + " term", _check_term.bind(available))
		if requirement.get("all") is Array and requirement.all.is_empty():
			errors.append("%s needs at least one capability term" % where)
		for capability in requirement.get("none", []):
			if not capability in capabilities:
				errors.append("%s excludes unknown capability '%s'" % [where, capability])

func _check_socket(socket: Dictionary, at: String) -> void:
	if not socket.get("type") in socket_types:
		errors.append("%s has unknown type" % at)
	if not socket.get("side") in SIDES or not socket.get("pair") is String:
		errors.append("%s needs a known side and a pair group (may be empty)" % at)

func _check_mount(mount: Dictionary, at: String) -> void:
	if not mount.get("type") in mount_types:
		errors.append("%s has unknown type" % at)

func _check_proportion(p: Dictionary, at: String) -> void:
	if not (_number(p.get("min")) and _number(p.get("max")) and _number(p.get("default"))) or not (p.min <= p.default and p.default <= p.max):
		errors.append("%s needs numeric min <= default <= max" % at)
	if not p.get("domain") in DOMAINS:
		errors.append("%s domain must be gameplay or visual" % at)

func _check_term(term: Dictionary, at: String, available: Dictionary) -> void:
	if not _count(term.get("count")):
		errors.append("%s count must be a positive integer" % at)
	if not available.has(term.get("capability")):
		errors.append("%s needs capability '%s' that no part or equipment provides" % [at, str(term.get("capability"))])

func _object(source: Dictionary, key: String, expected: Array) -> Dictionary:
	var value = source.get(key)
	if not value is Dictionary:
		errors.append("%s must be an object" % key)
		return {}
	_keys(value, expected, key)
	return value

func _id_list(values: Variant, where: String, sorted := true) -> Array:
	if not values is Array or values.any(func(v): return not v is String or _plain_id.search(v) == null):
		errors.append("%s must be a list of ids" % where)
		return []
	if (sorted and _sorted(values) != values) or values.size() != _unique(values).size():
		errors.append("%s must be sorted and unique" % where)
	return values

func _entries(values: Variant, expected: Array, where: String, check: Callable) -> void:
	if not values is Array:
		errors.append("%s list must be an array" % where)
		return
	var seen := {}
	for entry in values:
		if not entry is Dictionary:
			errors.append("%s must be an object" % where)
			continue
		_keys(entry, expected, where)
		var at := "%s '%s'" % [where, str(entry.get("id", entry.get("capability", "")))]
		var key := str(entry.get("id", entry.get("capability", "")))
		if seen.has(key):
			errors.append("%s is repeated" % at)
		seen[key] = true
		check.call(entry, at)

func _index(entries: Variant, table: Dictionary, order: Array, kind: String) -> void:
	if not entries is Array:
		errors.append("%s list must be an array" % kind)
		return
	for entry in entries:
		if not entry is Dictionary:
			errors.append("%s entry must be an object" % kind)
			continue
		var id := str(entry.get("id", ""))
		if _def_id.search(id) == null:
			errors.append("invalid %s id '%s'" % [kind, id])
		elif table.has(id):
			errors.append("duplicate %s id '%s'" % [kind, id])
		else:
			table[id] = entry
			order.append(id)

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

## JSON numbers arrive as floats; a count is any whole, positive number.
static func _count(value: Variant) -> bool:
	return _number(value) and value >= 1 and value == floor(value)

static func _unique(values: Array) -> Array:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen.keys()

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
