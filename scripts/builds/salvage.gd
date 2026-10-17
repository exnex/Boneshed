extends RefCounted
## Turns a won encounter into salvage references, and verifies a reference before a
## build may carry the item it names.
##
## A salvage reference is a pointer, not a copy: it holds the catalog item id and the
## fingerprints of that item and of the abilities it grants. Acquiring it adds the same
## item id to a build, so the player resolves the very ability definition the enemy
## used. References are re-verified against the catalog on acquisition; a reference
## whose fingerprints, item or ability list do not match is rejected. In the real game
## rewards must be issued and claimed server-side; this prototype has no persistence,
## so it cannot prevent a valid reference from being claimed twice.

const Catalog := preload("res://scripts/builds/build_catalog.gd")

const RESULT_SCHEMA := "boneshed.encounter_result.v0"
const REF_SCHEMA := "boneshed.salvage_ref.v0"
const RESULT_KEYS := ["defeated", "encounter_id", "outcome", "schema", "victor_build_id"]
const REF_KEYS := ["abilities", "catalog_version", "item", "item_fingerprint", "ref_id", "schema", "source"]
const SOURCE_KEYS := ["build_id", "encounter_id", "slot"]

var catalog
var builds

func _init(source_catalog, build_rules) -> void:
	catalog = source_catalog
	builds = build_rules

## TEST FIXTURE ONLY: stands in for a finished duel. Nothing here simulates combat.
static func victory_fixture(encounter_id: String, victor: Dictionary, defeated: Dictionary) -> Dictionary:
	return {"schema": RESULT_SCHEMA, "encounter_id": encounter_id, "outcome": "victory",
		"victor_build_id": victor.build_id, "defeated": defeated.duplicate(true)}

## Returns {"ok", "errors", "refs"}: one reference per salvageable item the defeated
## build had equipped, in catalog slot order.
func rewards(result: Variant) -> Dictionary:
	var errors := []
	if not result is Dictionary or _sorted(result.keys()) != RESULT_KEYS:
		errors.append({"code": "invalid_result"})
	elif result.schema != RESULT_SCHEMA:
		errors.append({"code": "unsupported_schema", "value": str(result.schema)})
	elif result.outcome != "victory":
		errors.append({"code": "no_victory", "outcome": str(result.outcome)})
	else:
		for error in builds.validate(result.defeated):
			errors.append({"code": "invalid_defeated_build", "cause": error})
		if errors.is_empty() and result.victor_build_id == result.defeated.build_id:
			errors.append({"code": "self_defeat"})
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "refs": []}
	var refs := []
	for slot in catalog.slot_order:
		var item_id: String = result.defeated.equipped.get(slot, "")
		if not item_id.is_empty() and catalog.items[item_id].salvageable:
			refs.append(_reference(result.encounter_id, result.defeated.build_id, slot, item_id))
	return {"ok": true, "errors": [], "refs": refs}

## Empty array when the reference matches the current catalog exactly.
func verify(ref: Variant) -> Array:
	if not ref is Dictionary or _sorted(ref.keys()) != REF_KEYS:
		return [{"code": "invalid_ref"}]
	if ref.schema != REF_SCHEMA:
		return [{"code": "unsupported_schema", "value": str(ref.schema)}]
	if not ref.source is Dictionary or _sorted(ref.source.keys()) != SOURCE_KEYS:
		return [{"code": "invalid_ref_source"}]
	if ref.catalog_version != catalog.version:
		return [{"code": "catalog_version_mismatch", "value": str(ref.catalog_version)}]
	if not ref.item is String or not catalog.items.has(ref.item):
		return [{"code": "unknown_item", "item": str(ref.item)}]
	if not catalog.items[ref.item].salvageable:
		return [{"code": "not_salvageable", "item": ref.item}]
	var errors := []
	var expected := _reference(str(ref.source.encounter_id), str(ref.source.build_id), str(ref.source.slot), ref.item)
	if ref.item_fingerprint != expected.item_fingerprint:
		errors.append({"code": "fingerprint_mismatch", "item": ref.item})
	if Catalog.canonical_json(ref.abilities) != Catalog.canonical_json(expected.abilities):
		errors.append({"code": "ability_mismatch", "item": ref.item})
	if ref.ref_id != expected.ref_id:
		errors.append({"code": "ref_id_mismatch"})
	return errors

## Returns {"ok", "errors", "build"}. The build gains the referenced item id in
## `carried`; equipping it is a separate, validated step.
func acquire(build: Variant, ref: Variant) -> Dictionary:
	var errors := verify(ref)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "build": build}
	return builds.carry(build, ref.item)

func _reference(encounter_id: String, build_id: String, slot: String, item_id: String) -> Dictionary:
	var abilities := []
	for ability_id in catalog.items[item_id].grants:
		abilities.append({"id": ability_id, "fingerprint": catalog.ability_fingerprint(ability_id)})
	return {
		"schema": REF_SCHEMA,
		"ref_id": Catalog.digest([encounter_id, build_id, slot, item_id]),
		"catalog_version": catalog.version,
		"item": item_id,
		"item_fingerprint": catalog.item_fingerprint(item_id),
		"abilities": abilities,
		"source": {"encounter_id": encounter_id, "build_id": build_id, "slot": slot},
	}

static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy
