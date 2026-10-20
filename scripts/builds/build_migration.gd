extends RefCounted
## Upgrades builds recorded against an older catalog to the current one, or reports
## why it cannot. Pure: the input is never modified, and the result is validated by
## the same build rules as any other build.
##
## Catalog 0.3.0 used `main_hand` / `left_arm` / `right_arm`. Slots are now anatomical:
## `hand_r` / `hand_l` grips carried by `arm_r` / `arm_l`. The 0.3.0 Marrow Arm sat in
## `right_arm` only so the sword could be drawn in the left hand; the item now fits the
## left arm alone, so a body modification that no longer fits its renamed slot moves to
## the one same-part slot it does fit, and the move is reported. Weapons never move.

const SLOT_RENAMES := {"0.3.0": {"main_hand": "hand_r", "left_arm": "arm_l", "right_arm": "arm_r"}}

var rules

func _init(build_rules) -> void:
	rules = build_rules

## Returns {"ok", "errors", "build", "changes"}. A current build passes through.
func migrate(build: Variant) -> Dictionary:
	if not build is Dictionary or not build.get("catalog_version") is String:
		return {"ok": false, "errors": [{"code": "not_a_build"}], "build": build, "changes": []}
	var catalog = rules.catalog
	if build.catalog_version == catalog.version:
		var errors: Array = rules.validate(build)
		return {"ok": errors.is_empty(), "errors": errors, "build": build, "changes": []}
	if not SLOT_RENAMES.has(build.catalog_version) or not build.get("equipped") is Dictionary:
		return {"ok": false, "errors": [{"code": "unsupported_catalog_version", "value": build.catalog_version}], "build": build, "changes": []}
	var renames: Dictionary = SLOT_RENAMES[build.catalog_version]
	var candidate: Dictionary = build.duplicate(true)
	var changes := []
	var equipped := {}
	var errors := []
	var legacy_slots: Array = build.equipped.keys()
	legacy_slots.sort()
	for legacy in legacy_slots:
		var item_id = build.equipped[legacy]
		var slot: String = renames.get(legacy, "")
		if slot.is_empty():
			errors.append({"code": "unknown_legacy_slot", "slot": str(legacy)})
			continue
		var target := _relocation(item_id, slot)
		if target != slot:
			changes.append({"code": "relocated", "item": item_id, "from": slot, "to": target})
			slot = target
		if equipped.has(slot):
			errors.append({"code": "migration_conflict", "slot": slot, "items": [equipped[slot], item_id]})
			continue
		equipped[slot] = item_id
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build, "changes": []}
	candidate.equipped = equipped
	candidate.catalog_version = catalog.version
	errors = rules.validate(candidate)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build, "changes": []}
	return {"ok": true, "errors": [], "build": candidate, "changes": changes}

## A body modification that does not fit its renamed slot moves to the only slot of
## the same part it fits. Anything else stays and is judged by normal validation.
func _relocation(item_id: Variant, slot: String) -> String:
	var catalog = rules.catalog
	if not item_id is String or not catalog.items.has(item_id) or not catalog.slots.has(slot):
		return slot
	var item: Dictionary = catalog.items[item_id]
	if item.category != "body_mod" or slot in item.fits_slots:
		return slot
	var same_part: Array = item.fits_slots.filter(func(s): return catalog.slots[s].kind == "body" and catalog.slots[s].part == catalog.slots[slot].get("part", ""))
	return same_part[0] if same_part.size() == 1 else slot
