extends RefCounted
## Pure operations on serialisable bodies: validate, resolve, check capability
## requirements, apply transformations, and serialise.
##
## A body is a rooted tree of nodes. Each node names a catalog part and the parent
## socket it occupies; the root is always a `core` part that carries every stable
## gameplay anchor. Equipment entries name the exact mounts they occupy. Every
## operation returns a new body and leaves its input untouched; on any error the
## original body is returned unchanged. Errors are {"code", ...} records in a fixed
## (sorted node id) order so outputs are deterministic.

const Catalog := preload("res://scripts/anatomy/anatomy_catalog.gd")

const SCHEMA := "boneshed.anatomy.v0"
const RESOLVED_SCHEMA := "boneshed.resolved_anatomy.v0"
const BODY_KEYS := ["body_id", "catalog_version", "equipment", "nodes", "schema"]
const NODE_KEYS := ["id", "parent", "part", "proportions", "socket"]
const EQUIPMENT_KEYS := ["item", "mounts"]
## Operations that change structure; equipment that no longer fits is displaced after each.
const STRUCTURAL_OPS := ["attach", "detach", "replace", "set_proportion"]
const PRECISION := 10000.0

var catalog
var _body_id := RegEx.create_from_string("^[a-z0-9][a-z0-9_.-]*$")
var _node_id := RegEx.create_from_string("^[a-z][a-z0-9_]*$")

func _init(source_catalog) -> void:
	catalog = source_catalog

func new_body(body_id: String, root_id: String, core_part: String) -> Dictionary:
	return {"schema": SCHEMA, "body_id": body_id, "catalog_version": catalog.version, "equipment": [],
		"nodes": [{"id": root_id, "part": core_part, "parent": "", "socket": "", "proportions": {}}]}

func validate(body: Variant) -> Array:
	var errors := _validate_shape(body)
	if errors.is_empty():
		_validate_graph(body, errors)
	if errors.is_empty():
		var nodes := _index(body)
		var used := {}
		for entry in _equipment_order(body.equipment):
			errors.append_array(_equipment_errors(nodes, entry, used))
	return errors

## Returns {"ok", "errors", "resolved"}. Invalid bodies never resolve partially.
func resolve(body: Variant) -> Dictionary:
	var errors := validate(body)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "resolved": {}}
	var normal := normalize(body)
	var nodes := _index(normal)
	var root: Dictionary = normal.nodes.filter(func(n): return n.parent == "")[0]
	var anchors := {}
	for anchor in catalog.required_anchors:
		anchors[anchor] = root.id
	var capabilities := {}
	var occupied := {}
	for entry in normal.equipment:
		for ref in entry.mounts:
			occupied[ref] = entry.item
	var gameplay_nodes := []
	var visual_nodes := []
	var mounts := []
	var modules := {}
	var kind_counts := {}
	var sides := {"left": [], "right": []}
	var flags := []
	for node in normal.nodes:
		var part: Dictionary = catalog.parts[node.part]
		for capability in part.provides:
			_add_provider(capabilities, capability, node.id)
		var side := _socket_side(nodes, node)
		if sides.has(side):
			sides[side].append(node.part)
		kind_counts[part.kind] = kind_counts.get(part.kind, 0) + 1
		modules[part.animation_module] = true
		for mount in part.mounts:
			var ref: String = node.id + "/" + mount.id
			mounts.append({"mount": ref, "type": mount.type, "occupied_by": occupied.get(ref, "")})
		gameplay_nodes.append({"id": node.id, "part": node.part, "part_fingerprint": catalog.part_gameplay_fingerprint(node.part),
			"kind": part.kind, "parent": node.parent, "socket": node.socket, "side": side,
			"hurt_class": part.gameplay.hurt_class, "reach_class": part.gameplay.reach_class,
			"attack_origin": part.gameplay.attack_origin, "guard": part.gameplay.guard,
			"animation_module": part.animation_module, "proportions": _proportions(part, node, "gameplay")})
		visual_nodes.append({"id": node.id, "part": node.part, "visual": part.visual, "proportions": _proportions(part, node, "visual")})
		if part.gameplay.reach_class in catalog.readability.review_reach:
			flags.append({"flag": "review_reach", "node": node.id, "class": part.gameplay.reach_class})
		if part.gameplay.hurt_class in catalog.readability.review_hurt:
			flags.append({"flag": "review_hurtbox", "node": node.id, "class": part.gameplay.hurt_class})
	var equipment := []
	for entry in normal.equipment:
		var definition: Dictionary = catalog.equipment[entry.item]
		# Equipment capabilities are credited to the node of its first mount.
		var holder: String = entry.mounts[0].get_slice("/", 0)
		for capability in definition.provides:
			_add_provider(capabilities, capability, holder)
		equipment.append({"item": entry.item, "mounts": entry.mounts, "provides": definition.provides, "build_item": definition.build_item})
	for capability in capabilities:
		capabilities[capability].sort()
	var locomotion := _locomotion(capabilities)
	var module: String = catalog.parts[nodes[locomotion.nodes[0]].part].animation_module
	if locomotion.capability != catalog.readability.baseline_locomotion:
		flags.append({"flag": "non_baseline_locomotion", "capability": locomotion.capability})
	var baseline: Dictionary = catalog.readability.baseline_kind_counts
	for kind in _sorted(_union(baseline.keys(), kind_counts.keys())):
		if kind != "core" and int(kind_counts.get(kind, 0)) != int(baseline.get(kind, 0)):
			flags.append({"flag": "non_baseline_count", "kind": kind, "count": kind_counts.get(kind, 0), "baseline": int(baseline.get(kind, 0))})
	sides.left.sort()
	sides.right.sort()
	var asymmetric: bool = sides.left != sides.right
	if asymmetric:
		flags.append({"flag": "asymmetric_silhouette", "left": sides.left, "right": sides.right})
	var gameplay := {
		"tags": _tags(normal),
		"capabilities": capabilities,
		"locomotion": {"capability": locomotion.capability, "node": locomotion.nodes[0], "module": module},
		"nodes": gameplay_nodes,
		"mounts": mounts,
		"equipment": equipment,
		"animation_modules": _sorted(modules.keys()),
		"silhouette": {"kind_counts": kind_counts, "asymmetric": asymmetric},
		"review_flags": flags,
	}
	var resolved := {"schema": RESOLVED_SCHEMA, "body_id": normal.body_id, "catalog_version": catalog.version,
		"anchors": anchors, "gameplay": gameplay, "visual": {"nodes": visual_nodes}}
	# Visual edits change `fingerprint` but never `gameplay_fingerprint`.
	resolved["gameplay_fingerprint"] = Catalog.digest({"anchors": anchors, "gameplay": gameplay})
	resolved["fingerprint"] = Catalog.digest(resolved)
	return {"ok": true, "errors": [], "resolved": resolved}

## Whether a resolved body satisfies one catalog requirement, which nodes satisfy it,
## and where the attack visibly originates. Requirements name capabilities, never slots.
func check_requirement(resolved: Dictionary, requirement_id: String) -> Dictionary:
	if not catalog.requirements.has(requirement_id):
		return {"id": requirement_id, "met": false, "missing": [], "excluded": [], "sources": {}, "origin": {}, "error": "unknown_requirement"}
	var requirement: Dictionary = catalog.requirements[requirement_id]
	var capabilities: Dictionary = resolved.gameplay.capabilities
	var missing := []
	var sources := {}
	for term in requirement.all:
		var have: Array = capabilities.get(term.capability, [])
		sources[term.capability] = have
		if have.size() < term.count:
			missing.append({"capability": term.capability, "need": int(term.count), "have": have.size()})
	var excluded := []
	for capability in requirement.none:
		if capabilities.has(capability):
			excluded.append({"capability": capability, "nodes": capabilities[capability]})
	var met := missing.is_empty() and excluded.is_empty()
	var origin := {}
	if met:
		var node_id: String = sources[requirement.all[0].capability][0]
		var node: Dictionary = resolved.gameplay.nodes.filter(func(n): return n.id == node_id)[0]
		origin = {"node": node_id, "point": node.attack_origin, "animation_module": node.animation_module}
	return {"id": requirement_id, "met": met, "missing": missing, "excluded": excluded, "sources": sources, "origin": origin}

func check_requirements(resolved: Dictionary) -> Array:
	return catalog.requirement_order.map(func(id): return check_requirement(resolved, id))

## Applies a list of operations atomically. Equipment whose mounts disappear or stop
## fitting is displaced (reported, never silently lost or left invalid). Returns
## {"ok", "errors", "body", "report"}: the report lists every removed node, replaced
## part and displaced equipment entry, plus the net equipment/parts released or added.
func transform(body: Variant, ops: Variant) -> Dictionary:
	var errors := validate(body)
	if errors.is_empty() and not ops is Array:
		errors.append({"code": "invalid_ops"})
	if not errors.is_empty():
		return _rejected(body, errors)
	var candidate := normalize(body)
	var report := {"removed_nodes": [], "replaced": [], "displaced": []}
	for i in ops.size():
		var step := _apply(candidate, ops[i], report)
		if not step.is_empty():
			return _rejected(body, step.map(func(e): e["op_index"] = i; return e))
		if ops[i].op in STRUCTURAL_OPS:
			_displace_invalid_equipment(candidate, report)
	candidate = normalize(candidate)
	errors = validate(candidate)
	if not errors.is_empty():
		return _rejected(body, errors.map(func(e): e["stage"] = "result"; return e))
	report.removed_nodes.sort_custom(func(a, b): return a.node < b.node)
	# Net effect, for the build layer: what to move to carried, and what it must supply.
	var before_items: Array = body.equipment.map(func(e): return e.item)
	var after_items: Array = candidate.equipment.map(func(e): return e.item)
	var before_parts: Array = body.nodes.map(func(n): return n.part)
	var after_parts: Array = candidate.nodes.map(func(n): return n.part)
	report["equipment_released"] = _minus(before_items, after_items)
	report["equipment_required"] = _minus(after_items, before_items)
	report["parts_released"] = _minus(before_parts, after_parts)
	report["parts_added"] = _minus(after_parts, before_parts)
	return {"ok": true, "errors": [], "body": candidate, "report": report}

## What changed between two resolved bodies, for summaries and transition planning.
func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var node_ids := func(r): return r.gameplay.nodes.map(func(n): return n.id + ":" + n.part)
	var caps := func(r): return _sorted(r.gameplay.capabilities.keys())
	var b_nodes: Array = node_ids.call(before)
	var a_nodes: Array = node_ids.call(after)
	var b_caps: Array = caps.call(before)
	var a_caps: Array = caps.call(after)
	return {
		"nodes_added": a_nodes.filter(func(n): return not n in b_nodes),
		"nodes_removed": b_nodes.filter(func(n): return not n in a_nodes),
		"capabilities_added": a_caps.filter(func(c): return not c in b_caps),
		"capabilities_removed": b_caps.filter(func(c): return not c in a_caps),
		"modules_added": after.gameplay.animation_modules.filter(func(m): return not m in before.gameplay.animation_modules),
		"modules_removed": before.gameplay.animation_modules.filter(func(m): return not m in after.gameplay.animation_modules),
		"anchors_unchanged": before.anchors == after.anchors,
		"locomotion_changed": before.gameplay.locomotion.capability != after.gameplay.locomotion.capability,
	}

## Canonical form: nodes by id, mounts sorted, equipment by first mount, numbers as floats.
func normalize(body: Dictionary) -> Dictionary:
	var copy: Dictionary = body.duplicate(true)
	for node in copy.nodes:
		for key in node.proportions:
			node.proportions[key] = _round(float(node.proportions[key]))
	copy.nodes.sort_custom(func(a, b): return a.id < b.id)
	for entry in copy.equipment:
		entry.mounts.sort()
	copy.equipment = _equipment_order(copy.equipment)
	return copy

func to_json(body: Dictionary) -> String:
	return Catalog.canonical_json(normalize(body))

## Strict loader: plain JSON only, exact keys, known ids, valid graph and mounts.
func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "errors": [{"code": "malformed_json", "line": parser.get_error_line()}], "body": {}}
	var errors := validate(parser.data)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "body": {}}
	return {"ok": true, "errors": [], "body": normalize(parser.data)}

func _apply(body: Dictionary, op: Variant, report: Dictionary) -> Array:
	if not op is Dictionary or not op.get("op") is String:
		return [{"code": "invalid_op"}]
	var fields := {"attach": ["node", "part", "parent", "socket"], "detach": ["node"], "replace": ["node", "part"],
		"set_proportion": ["node", "key", "value"], "mount": ["item", "mounts"], "unmount": ["mount"]}
	if not fields.has(op.op):
		return [{"code": "unknown_op", "op": op.op}]
	var expected: Array = fields[op.op] + ["op"]
	if _sorted(op.keys()) != _sorted(expected):
		return [{"code": "invalid_op", "op": op.op}]
	var nodes := _index(body)
	match op.op:
		"attach":
			if nodes.has(op.node):
				return [{"code": "node_exists", "node": op.node}]
			if not nodes.has(op.parent):
				return [{"code": "unknown_node", "node": op.parent}]
			if not catalog.parts.has(op.part):
				return [{"code": "unknown_part", "part": op.part}]
			body.nodes.append({"id": op.node, "part": op.part, "parent": op.parent, "socket": op.socket, "proportions": {}})
		"detach":
			if not nodes.has(op.node):
				return [{"code": "unknown_node", "node": op.node}]
			if nodes[op.node].parent == "":
				return [{"code": "cannot_detach_root", "node": op.node}]
			_remove_subtree(body, op.node, report)
		"replace":
			if not nodes.has(op.node):
				return [{"code": "unknown_node", "node": op.node}]
			if not catalog.parts.has(op.part):
				return [{"code": "unknown_part", "part": op.part}]
			# Proportions belong to a part definition; a new part starts at its defaults.
			report.replaced.append({"node": op.node, "from": nodes[op.node].part, "to": op.part})
			nodes[op.node].part = op.part
			nodes[op.node].proportions = {}
			var part: Dictionary = catalog.parts[op.part]
			for child in body.nodes.filter(func(n): return n.parent == op.node):
				var socket := _socket(part, child.socket)
				if socket.is_empty() or not socket.type in catalog.parts[child.part].attaches_to:
					_remove_subtree(body, child.id, report)
		"set_proportion":
			if not nodes.has(op.node):
				return [{"code": "unknown_node", "node": op.node}]
			if not Catalog._number(op.value):
				return [{"code": "invalid_op", "op": op.op}]
			nodes[op.node].proportions[op.key] = op.value
		"mount":
			if not op.mounts is Array or op.mounts.any(func(m): return not m is String):
				return [{"code": "invalid_op", "op": op.op}]
			var used := {}
			for entry in body.equipment:
				for ref in entry.mounts:
					used[ref] = entry.item
			var added := {"item": op.item, "mounts": _sorted(op.mounts)}
			var errors := _equipment_errors(nodes, added, used)
			if not errors.is_empty():
				return errors
			body.equipment.append(added)
		"unmount":
			for entry in body.equipment:
				if op.mount in entry.mounts:
					body.equipment.erase(entry)
					report.displaced.append({"item": entry.item, "mounts": entry.mounts, "reasons": ["unmounted"]})
					return []
			return [{"code": "mount_empty", "mount": op.mount}]
	return []

func _remove_subtree(body: Dictionary, root_id: String, report: Dictionary) -> void:
	var doomed := [root_id]
	var i := 0
	while i < doomed.size():
		for node in body.nodes:
			if node.parent == doomed[i] and not node.id in doomed:
				doomed.append(node.id)
		i += 1
	for node in body.nodes:
		if node.id in doomed:
			report.removed_nodes.append({"node": node.id, "part": node.part})
	body.nodes = body.nodes.filter(func(n): return not n.id in doomed)

## Keeps every equipment entry that still fits and reports the rest as displaced.
func _displace_invalid_equipment(body: Dictionary, report: Dictionary) -> void:
	var nodes := _index(body)
	var used := {}
	var kept := []
	for entry in _equipment_order(body.equipment):
		var trial: Dictionary = used.duplicate()
		var errors := _equipment_errors(nodes, entry, trial)
		if errors.is_empty():
			used = trial
			kept.append(entry)
		else:
			report.displaced.append({"item": entry.item, "mounts": entry.mounts, "reasons": _sorted(Catalog._unique(errors.map(func(e): return e.code)))})
	body.equipment = kept

func _rejected(body: Variant, errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "body": body, "report": {}}

func _validate_shape(body: Variant) -> Array:
	if not body is Dictionary:
		return [{"code": "not_an_object"}]
	var errors := []
	for key in body:
		if not key in BODY_KEYS:
			errors.append({"code": "unknown_key", "key": str(key)})
	for key in BODY_KEYS:
		if not body.has(key):
			errors.append({"code": "missing_key", "key": key})
	if not errors.is_empty():
		return errors
	if body.schema != SCHEMA:
		errors.append({"code": "unsupported_schema", "value": str(body.schema)})
	if not body.body_id is String or _body_id.search(body.body_id) == null:
		errors.append({"code": "invalid_body_id"})
	if body.catalog_version != catalog.version:
		errors.append({"code": "catalog_version_mismatch", "value": str(body.catalog_version), "expected": catalog.version})
	if not body.nodes is Array or body.nodes.is_empty():
		errors.append({"code": "invalid_nodes"})
	else:
		var seen := {}
		for i in body.nodes.size():
			var node = body.nodes[i]
			if not node is Dictionary or _sorted(node.keys()) != NODE_KEYS:
				errors.append({"code": "invalid_node", "index": i})
				continue
			if not node.id is String or _node_id.search(node.id) == null:
				errors.append({"code": "invalid_node_id", "index": i})
				continue
			if seen.has(node.id):
				errors.append({"code": "duplicate_node_id", "node": node.id})
			seen[node.id] = true
			if not node.parent is String or not node.socket is String:
				errors.append({"code": "invalid_node", "index": i})
			if not node.part is String or not catalog.parts.has(node.part):
				errors.append({"code": "unknown_part", "node": node.id, "part": str(node.part)})
			if not node.proportions is Dictionary or node.proportions.values().any(func(v): return not Catalog._number(v)):
				errors.append({"code": "invalid_proportions", "node": node.id})
	if not body.equipment is Array:
		errors.append({"code": "invalid_equipment"})
	else:
		for i in body.equipment.size():
			var entry = body.equipment[i]
			if not entry is Dictionary or _sorted(entry.keys()) != EQUIPMENT_KEYS or not entry.item is String \
					or not entry.mounts is Array or entry.mounts.is_empty() or entry.mounts.any(func(m): return not m is String):
				errors.append({"code": "invalid_equipment", "index": i})
	return errors

func _validate_graph(body: Dictionary, errors: Array) -> void:
	var nodes := _index(body)
	var ids := _sorted(nodes.keys())
	if ids.size() > catalog.limits.max_nodes:
		errors.append({"code": "too_many_nodes", "count": ids.size(), "limit": int(catalog.limits.max_nodes)})
	var roots: Array = ids.filter(func(id): return nodes[id].parent == "")
	if roots.is_empty():
		errors.append({"code": "no_root"})
	elif roots.size() > 1:
		errors.append({"code": "multiple_roots", "nodes": roots})
	var occupied := {}
	for id in ids:
		var node: Dictionary = nodes[id]
		var part: Dictionary = catalog.parts[node.part]
		if node.parent == "":
			if node.socket != "":
				errors.append({"code": "root_has_socket", "node": id})
			if part.kind != "core":
				errors.append({"code": "root_not_core", "node": id, "part": node.part})
			continue
		if part.kind == "core":
			errors.append({"code": "core_not_root", "node": id, "part": node.part})
		if not nodes.has(node.parent):
			errors.append({"code": "unknown_parent", "node": id, "parent": node.parent})
			continue
		var socket := _socket(catalog.parts[nodes[node.parent].part], node.socket)
		if socket.is_empty():
			errors.append({"code": "unknown_socket", "node": id, "parent": node.parent, "socket": node.socket})
		elif not socket.type in part.attaches_to:
			errors.append({"code": "incompatible_socket", "node": id, "part": node.part, "socket": node.socket, "type": socket.type})
		var key: String = node.parent + "/" + node.socket
		if occupied.has(key):
			errors.append({"code": "socket_occupied", "socket": key, "nodes": [occupied[key], id]})
		else:
			occupied[key] = id
	for cycle in _cycles(nodes, ids):
		errors.append({"code": "cycle", "nodes": cycle})
	if roots.size() == 1:
		var depths := _depths(nodes, roots[0])
		for id in ids:
			if not depths.has(id):
				errors.append({"code": "disconnected", "node": id})
			elif depths[id] > catalog.limits.max_depth:
				errors.append({"code": "too_deep", "node": id, "depth": depths[id], "limit": int(catalog.limits.max_depth)})
	_validate_tags(nodes, ids, errors)
	_validate_proportions(nodes, ids, errors)
	var count: int = _locomotion(_part_capabilities(nodes, ids)).nodes.size()
	if count != 1:
		errors.append({"code": "locomotion_count", "count": count})

func _validate_tags(nodes: Dictionary, ids: Array, errors: Array) -> void:
	var carriers := {}
	for id in ids:
		for tag in catalog.parts[nodes[id].part].tags:
			_add_provider(carriers, tag, id)
	for id in ids:
		var part: Dictionary = catalog.parts[nodes[id].part]
		for tag in part.requires_tags:
			if not carriers.has(tag):
				errors.append({"code": "missing_required_tag", "node": id, "tag": tag})
		for tag in part.excludes_tags:
			for other in carriers.get(tag, []):
				if other != id:
					errors.append({"code": "excluded_tag", "node": id, "tag": tag, "conflicts_with": other})

func _validate_proportions(nodes: Dictionary, ids: Array, errors: Array) -> void:
	for id in ids:
		var node: Dictionary = nodes[id]
		var part: Dictionary = catalog.parts[node.part]
		for key in _sorted(node.proportions.keys()):
			var definition := _proportion(part, key)
			if definition.is_empty():
				errors.append({"code": "unknown_proportion", "node": id, "key": key})
			elif node.proportions[key] < definition.min or node.proportions[key] > definition.max:
				errors.append({"code": "proportion_out_of_range", "node": id, "key": key, "value": node.proportions[key],
					"min": definition.min, "max": definition.max})

## Validates one equipment entry against the body; records the mounts it claims in `used`.
func _equipment_errors(nodes: Dictionary, entry: Dictionary, used: Dictionary) -> Array:
	if not catalog.equipment.has(entry.item):
		return [{"code": "unknown_equipment", "item": entry.item}]
	var definition: Dictionary = catalog.equipment[entry.item]
	if entry.mounts.size() != definition.mount_count:
		return [{"code": "mount_count", "item": entry.item, "expected": int(definition.mount_count), "actual": entry.mounts.size()}]
	var errors := []
	var holders := []
	for ref in _sorted(entry.mounts):
		var node_id: String = ref.get_slice("/", 0)
		var mount := {}
		if nodes.has(node_id) and ref.get_slice_count("/") == 2:
			for candidate in catalog.parts[nodes[node_id].part].mounts:
				if candidate.id == ref.get_slice("/", 1):
					mount = candidate
		if mount.is_empty():
			errors.append({"code": "unknown_mount", "item": entry.item, "mount": ref})
			continue
		holders.append(nodes[node_id])
		if not mount.type in definition.mounts_on:
			errors.append({"code": "wrong_mount_type", "item": entry.item, "mount": ref, "type": mount.type})
		if used.has(ref):
			errors.append({"code": "mount_in_use", "item": entry.item, "mount": ref, "occupied_by": used[ref]})
		else:
			used[ref] = entry.item
		for tag in definition.excludes_part_tags:
			if tag in catalog.parts[nodes[node_id].part].tags:
				errors.append({"code": "equipment_excluded", "item": entry.item, "mount": ref, "tag": tag})
	if definition.paired and holders.size() == 2 and not _paired(nodes, holders[0], holders[1]):
		errors.append({"code": "unpaired_mounts", "item": entry.item, "mounts": _sorted(entry.mounts)})
	var capabilities := _part_capabilities(nodes, _sorted(nodes.keys()))
	for capability in definition.requires_capabilities:
		if not capabilities.has(capability):
			errors.append({"code": "equipment_missing_capability", "item": entry.item, "capability": capability})
	return errors

## Two holders form a pair when they hang from the same parent on mirrored sockets
## of the same non-empty pair group (e.g. both upper shoulders).
func _paired(nodes: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	if a.parent != b.parent or a.parent == "" or not nodes.has(a.parent):
		return false
	var parent_part: Dictionary = catalog.parts[nodes[a.parent].part]
	var sa := _socket(parent_part, a.socket)
	var sb := _socket(parent_part, b.socket)
	return not sa.is_empty() and not sb.is_empty() and sa.pair != "" and sa.pair == sb.pair and sa.side != sb.side

func _cycles(nodes: Dictionary, ids: Array) -> Array:
	var found := {}
	for start in ids:
		var path := []
		var current: String = start
		while current != "" and nodes.has(current):
			var at := path.find(current)
			if at >= 0:
				var cycle := _sorted(path.slice(at))
				found[",".join(cycle)] = cycle
				break
			path.append(current)
			current = nodes[current].parent
	var keys := _sorted(found.keys())
	return keys.map(func(k): return found[k])

func _depths(nodes: Dictionary, root: String) -> Dictionary:
	var depths := {root: 0}
	var queue := [root]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for id in _sorted(nodes.keys()):
			if nodes[id].parent == current and not depths.has(id):
				depths[id] = depths[current] + 1
				queue.append(id)
	return depths

func _part_capabilities(nodes: Dictionary, ids: Array) -> Dictionary:
	var capabilities := {}
	for id in ids:
		for capability in catalog.parts[nodes[id].part].provides:
			_add_provider(capabilities, capability, id)
	return capabilities

## The single locomotion provider (validation guarantees exactly one on valid bodies).
func _locomotion(capabilities: Dictionary) -> Dictionary:
	var prefix: String = catalog.readability.locomotion_prefix
	var result := {"capability": "", "nodes": []}
	for capability in _sorted(capabilities.keys()):
		if capability.begins_with(prefix):
			result.nodes.append_array(capabilities[capability])
			result.capability = capability
	return result

func _tags(body: Dictionary) -> Array:
	var tags := {}
	for node in body.nodes:
		for tag in catalog.parts[node.part].tags:
			tags[tag] = true
	return _sorted(tags.keys())

func _socket_side(nodes: Dictionary, node: Dictionary) -> String:
	if node.parent == "" or not nodes.has(node.parent):
		return "center"
	var socket := _socket(catalog.parts[nodes[node.parent].part], node.socket)
	return socket.get("side", "center")

func _proportions(part: Dictionary, node: Dictionary, domain: String) -> Dictionary:
	var values := {}
	for definition in part.proportions:
		if definition.domain == domain:
			values[definition.id] = _round(float(node.proportions.get(definition.id, definition.default)))
	return values

func _equipment_order(entries: Array) -> Array:
	var copy := entries.duplicate()
	copy.sort_custom(func(a, b): return _equipment_key(a) < _equipment_key(b))
	return copy

static func _equipment_key(entry: Dictionary) -> String:
	return "%s|%s" % [entry.mounts[0] if not entry.mounts.is_empty() else "", entry.item]

static func _socket(part: Dictionary, socket_id: String) -> Dictionary:
	for socket in part.sockets:
		if socket.id == socket_id:
			return socket
	return {}

static func _proportion(part: Dictionary, key: String) -> Dictionary:
	for definition in part.proportions:
		if definition.id == key:
			return definition
	return {}

static func _index(body: Dictionary) -> Dictionary:
	var nodes := {}
	for node in body.nodes:
		if not nodes.has(node.id):
			nodes[node.id] = node
	return nodes

static func _add_provider(table: Dictionary, key: String, id: String) -> void:
	if not table.has(key):
		table[key] = []
	if not id in table[key]:
		table[key].append(id)

## Multiset difference, sorted: each element of `b` cancels one equal element of `a`.
static func _minus(a: Array, b: Array) -> Array:
	var rest := a.duplicate()
	for value in b:
		rest.erase(value)
	rest.sort()
	return rest

static func _union(a: Array, b: Array) -> Array:
	return Catalog._unique(a + b)

static func _round(value: float) -> float:
	return round(value * PRECISION) / PRECISION

static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy
