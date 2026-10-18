extends RefCounted
## Courtyard-owned session. Builds own inventory/equipment; live CombatState objects
## own combat. Only a resolved lethal contact may open the reward transaction.
## No persistence, global state, fixture victory, or UI-authored reward records.
const Adapter = preload("res://scripts/combat/build_adapter.gd")
const Salvage = preload("res://scripts/builds/salvage.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
enum Stage { DUEL, VICTORY, FALLEN }

var adapter: Adapter
var salvage: Salvage
var builds: Dictionary
var stage: Stage = Stage.DUEL
var duel_number := 1
var _generation := 1
var _states: Dictionary
var _refs: Array = []

func _init(prepared: Dictionary) -> void:
	adapter = prepared.adapter
	salvage = Salvage.new(adapter.catalog, adapter.resolver)
	builds = prepared.builds.duplicate(true)
	_states = prepared.states

func owns(item: String) -> bool:
	return item in builds.player.carried or item in builds.player.equipped.values()

func equipped() -> bool:
	return builds.player.equipped.get("right_arm", "") == "item.marrow_arm"

func available_rewards() -> Array:
	if stage != Stage.VICTORY:
		return []
	return _refs.filter(func(ref: Dictionary) -> bool: return not owns(ref.item)).duplicate(true)

## Called by the encounter immediately after resolving player -> enemy. Merely
## setting DEAD (a debug shortcut) never reaches this boundary with a lethal result.
func record_contact(result: String) -> bool:
	if stage != Stage.DUEL or result != Rules.DEFEATED:
		return false
	var player: Rules = _states.player
	var enemy: Rules = _states.enemy
	if player.phase == Rules.Phase.DEAD or player.health <= 0.0 or enemy.phase != Rules.Phase.DEAD or enemy.health != 0.0:
		return false
	var reward := salvage.rewards({"schema": Salvage.RESULT_SCHEMA,
		"encounter_id": "courtyard.duel.%d" % _generation, "outcome": "victory",
		"victor_build_id": builds.player.build_id, "defeated": builds.enemy.duplicate(true)})
	if not reward.ok:
		return false
	_refs = reward.refs
	stage = Stage.VICTORY
	return true

func record_loss() -> void:
	if stage == Stage.DUEL and _states.player.phase == Rules.Phase.DEAD:
		stage = Stage.FALLEN
		_refs = []

func acquire() -> Dictionary:
	var rewards := available_rewards()
	if rewards.is_empty():
		return _failure("no_unclaimed_victory_reward")
	var transaction: Dictionary = salvage.acquire(builds.player, rewards[0])
	if not transaction.ok:
		return transaction
	# Verify executable builds too; a failed transaction never replaces inventory.
	var candidate := builds.duplicate(true)
	candidate.player = transaction.build
	var prepared := adapter.prepare_encounter(candidate)
	if not prepared.ok:
		return prepared
	builds = candidate
	return {"ok": true, "errors": []}

func equip(item := "item.marrow_arm", slot := "right_arm") -> Dictionary:
	if stage != Stage.VICTORY:
		return _failure("equipment_requires_finished_duel")
	var transaction: Dictionary = adapter.resolver.equip(builds.player, item, slot)
	if not transaction.ok:
		return transaction
	var candidate := builds.duplicate(true)
	candidate.player = transaction.build
	var prepared := adapter.prepare_encounter(candidate)
	if not prepared.ok:
		return prepared
	builds = candidate
	# Prepared states are only attached by the courtyard between encounters.
	return prepared

func begin(next_duel := false) -> Dictionary:
	if next_duel and (stage != Stage.VICTORY or not equipped()):
		return _failure("next_duel_requires_equipped_victory")
	var prepared := adapter.prepare_encounter(builds)
	if not prepared.ok:
		return prepared
	_states = prepared.states
	_generation += 1
	duel_number += int(next_duel)
	stage = Stage.DUEL
	_refs = []
	return prepared

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code}]}
