extends RefCounted
## Expedition session for directional combat: owns the player's build (inventory and
## equipment) and the stage of the current encounter. It mirrors the transaction
## rules of combat/duel_progression.gd — rewards only from a resolved lethal contact,
## salvage verified against the catalog, equip only after a finished duel, failed
## transactions never replace the build — but reads the directional rules state
## (duelist_state.gd) instead of CombatState, so no fighter carries two models.
## No persistence, global state, fixture victory or UI-authored reward records.

const Adapter = preload("res://scripts/directional_expedition/directional_adapter.gd")
const Salvage = preload("res://scripts/builds/salvage.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
enum Stage { DUEL, VICTORY, FALLEN, IDLE }
## Contact outcomes that deal damage and can therefore end a duel.
const LETHAL := [Solver.HIT, Solver.MISALIGNED]

var adapter: Adapter
var salvage: Salvage
var builds: Dictionary
var stage: Stage = Stage.IDLE
var encounter_id := ""
var enemy_build: Dictionary = {}
var enemy_variant: Dictionary = {}
var _generation := 0
var _refs: Array = []
var history: Array[Dictionary] = []

func _init(source: Adapter) -> void:
	adapter = source
	salvage = Salvage.new(adapter.catalog, adapter.rules)
	builds = {"player": adapter.builds.player.duplicate(true)}

func owns(item: String) -> bool:
	return item in builds.player.carried or item in builds.player.equipped.values()

func equipped(item := "item.marrow_arm") -> bool:
	return item in builds.player.equipped.values()

func available_rewards() -> Array:
	if stage != Stage.VICTORY:
		return []
	return _refs.filter(func(ref: Dictionary) -> bool: return not owns(ref.item)).duplicate(true)

## Resolves the current player build alone (exploration between encounters).
func player_fighter() -> Dictionary:
	var data: Dictionary = adapter.data.player
	return adapter.resolve_fighter(builds.player, data.get("armor", []), str(data.get("label", "Pilgrim")))

## Starts an encounter against `variant` (an encounters.json entry). Returns the
## adapter's prepared fighters; nothing changes when it fails.
func begin(site_id: String, variant: Dictionary) -> Dictionary:
	var build := adapter.enemy_build(variant, "expedition." + site_id)
	var prepared := adapter.prepare(builds.player, build, variant)
	if not prepared.ok:
		return prepared
	_generation += 1
	encounter_id = "expedition.%s.%d" % [site_id, _generation]
	enemy_build = build
	enemy_variant = variant.duplicate(true)
	stage = Stage.DUEL
	_refs = []
	return prepared

## Called by the encounter immediately after a player → enemy contact resolves.
## Only a damaging contact that left the enemy dead and the player alive wins.
func record_contact(result: String, player: State, enemy: State) -> bool:
	if stage != Stage.DUEL or result not in LETHAL:
		return false
	if player.phase == State.Phase.DEAD or player.health <= 0.0 or enemy.phase != State.Phase.DEAD or enemy.health != 0.0:
		return false
	var reward := salvage.rewards({"schema": Salvage.RESULT_SCHEMA, "encounter_id": encounter_id, "outcome": "victory",
		"victor_build_id": builds.player.build_id, "defeated": enemy_build.duplicate(true)})
	if not reward.ok:
		return false
	_refs = reward.refs
	stage = Stage.VICTORY
	history.append({"encounter": encounter_id, "outcome": "victory", "refs": _refs.map(func(ref: Dictionary) -> String: return ref.item)})
	return true

func record_loss(player: State) -> void:
	if stage == Stage.DUEL and player.phase == State.Phase.DEAD:
		stage = Stage.FALLEN
		_refs = []
		history.append({"encounter": encounter_id, "outcome": "fallen"})

## Leaving an exterior soul's vigil ends the engagement without a result.
func disengage() -> void:
	if stage == Stage.DUEL:
		stage = Stage.IDLE
		history.append({"encounter": encounter_id, "outcome": "disengaged"})

func acquire() -> Dictionary:
	var rewards := available_rewards()
	if rewards.is_empty():
		return _failure("no_unclaimed_victory_reward")
	var transaction: Dictionary = salvage.acquire(builds.player, rewards[0])
	if not transaction.ok:
		return transaction
	return _commit(transaction.build)

func equip(item := "item.marrow_arm", slot := "arm_l") -> Dictionary:
	if stage != Stage.VICTORY:
		return _failure("equipment_requires_finished_duel")
	var transaction: Dictionary = adapter.rules.equip(builds.player, item, slot)
	if not transaction.ok:
		return transaction
	return _commit(transaction.build)

## A changed build must still resolve into an executable directional fighter.
func _commit(candidate: Dictionary) -> Dictionary:
	var data: Dictionary = adapter.data.player
	var fighter := adapter.resolve_fighter(candidate, data.get("armor", []), str(data.get("label", "Pilgrim")))
	if not fighter.ok:
		return fighter
	builds.player = candidate
	return {"ok": true, "errors": [], "player": fighter}

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code}]}
