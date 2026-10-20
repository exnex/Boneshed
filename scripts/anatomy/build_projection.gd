extends RefCounted
## Proposed, read-only bridge from a resolved anatomy to the shared-build and combat
## layers. Nothing in the build or combat code calls this yet.
##
## The shared build catalog is passed in and only read (duck-typed: `version`,
## `items`, `abilities`). This is the only anatomy script that knows the build's
## `hand_r` / `hand_l` grips and `arm_r` / `arm_l` body slots; they are treated as a
## lossy view of a body, not as anatomical limits.

const SCHEMA := "boneshed.anatomy_combat_view.v0"
## Build body slots for parts that carry a build item, by the side they hang from.
const LEGACY_SIDE_SLOTS := {"left": "arm_l", "right": "arm_r"}
## Build grip slots for equipment, by the side of the limb holding its first mount.
const LEGACY_GRIP_SLOTS := {"left": "hand_l", "right": "hand_r"}
## Parts the legacy build assumes implicitly; any other part is anatomy-only.
const LEGACY_IMPLICIT_PARTS := ["part.biped_legs", "part.human_arm", "part.human_head", "part.humanoid_torso"]

var anatomy
var builds
var rules

func _init(anatomy_catalog, build_catalog, anatomy_rules) -> void:
	anatomy = anatomy_catalog
	builds = build_catalog
	rules = anatomy_rules

## What the current slot-based build would hold for this body. `lossless` is true only
## when the legacy build can express the whole body.
func legacy_slots(resolved: Dictionary) -> Dictionary:
	var equipped := {}
	var unrepresented := []
	var anatomy_only := []
	if builds.version != anatomy.build_catalog_version:
		unrepresented.append({"reason": "build_catalog_version_mismatch", "expected": anatomy.build_catalog_version, "actual": builds.version})
	var sides := {}
	for node in resolved.gameplay.nodes:
		sides[node.id] = node.side
	for entry in resolved.gameplay.equipment:
		var holder: String = sides.get(str(entry.mounts[0]).get_slice("/", 0), "") if not entry.mounts.is_empty() else ""
		_place(equipped, unrepresented, entry.build_item, LEGACY_GRIP_SLOTS.get(holder, ""), {"item": entry.item})
	for node in resolved.gameplay.nodes:
		var part: Dictionary = anatomy.parts[node.part]
		if not part.build_item.is_empty():
			_place(equipped, unrepresented, part.build_item, LEGACY_SIDE_SLOTS.get(node.side, ""), {"node": node.id})
		elif not node.part in LEGACY_IMPLICIT_PARTS:
			anatomy_only.append(node.id)
	return {"ok": unrepresented.is_empty(), "equipped": equipped, "unrepresented": unrepresented,
		"anatomy_only_nodes": anatomy_only, "lossless": unrepresented.is_empty() and anatomy_only.is_empty()}

## Net build-item changes of a transformation. `to_carried` would move to the build's
## `carried` list (nothing is destroyed); `from_carried` must already be carried.
func build_item_changes(report: Dictionary) -> Dictionary:
	var collect := func(equipment_ids: Array, part_ids: Array) -> Array:
		var items: Array = equipment_ids.map(func(id): return anatomy.equipment[id].build_item) \
			+ part_ids.map(func(id): return anatomy.parts[id].build_item)
		items = items.filter(func(item): return not item.is_empty())
		items.sort()
		return items
	return {"to_carried": collect.call(report.get("equipment_released", []), report.get("parts_released", [])),
		"from_carried": collect.call(report.get("equipment_required", []), report.get("parts_added", []))}

## The proposed anatomy → combat contract for one body and a list of ability ids.
func combat_view(resolved: Dictionary, ability_ids: Array) -> Dictionary:
	var gameplay: Dictionary = resolved.gameplay
	var attacks := []
	for ability_id in ability_ids:
		var check: Dictionary = rules.check_requirement(resolved, ability_id)
		var definition: Dictionary = builds.abilities.get(ability_id, {})
		attacks.append({"ability": ability_id, "met": check.met, "origin": check.origin,
			"missing": check.missing, "excluded": check.excluded,
			"attack_module": definition.get("module", ""), "binding": definition.get("binding", "")})
	return {
		"schema": SCHEMA,
		"body_id": resolved.body_id,
		"gameplay_fingerprint": resolved.gameplay_fingerprint,
		"anchors": resolved.anchors,
		"locomotion": gameplay.locomotion,
		"guard": {"facing_node": resolved.anchors.facing,
			"guarding_nodes": gameplay.nodes.filter(func(n): return n.guard == "front").map(func(n): return n.id)},
		"hurt_volumes": gameplay.nodes.map(func(n): return {"node": n.id, "class": n.hurt_class}),
		"attacks": attacks,
		"animation_modules": gameplay.animation_modules,
		"review_flags": gameplay.review_flags,
	}

func _place(equipped: Dictionary, unrepresented: Array, build_item: String, preferred: String, source: Dictionary) -> void:
	var record := source.duplicate()
	if build_item.is_empty():
		record["reason"] = "no_build_item"
		unrepresented.append(record)
		return
	if not builds.items.has(build_item):
		record["reason"] = "unknown_build_item"
		unrepresented.append(record)
		return
	var fits: Array = builds.items[build_item].fits_slots
	var slot: String = preferred if not preferred.is_empty() else (fits[0] if fits.size() == 1 else "")
	if slot.is_empty() or not slot in fits:
		record["reason"] = "no_matching_legacy_slot"
	elif equipped.has(slot):
		record["reason"] = "legacy_slot_taken"
	else:
		equipped[slot] = build_item
		return
	record["build_item"] = build_item
	unrepresented.append(record)
