extends "res://scripts/melee_lab/lab_opponent.gd"
## A soul in the expedition: the melee lab's opponent controller unchanged (delayed
## perception of drawn cues only, seeded choices, stamina-legal intents, slowed
## footwork), in "duel" mode. Additions only:
##   - The expedition rules state, so a soul whose build grants the Marrow Lunge may
##     use it — through the same `legal_actions()` check and stamina cost as the
##     player, never as a free or hidden action.
##   - Dormancy: the director calls `control`/`step` only while this soul's site is
##     engaged; otherwise it stands at its post and is never resolved for contact.

const ExpeditionState = preload("res://scripts/directional_expedition/expedition_state.gd")
const ExpeditionVisual = preload("res://scripts/directional_expedition/expedition_visual.gd")
const ExpeditionDuelist = preload("res://scripts/directional_expedition/expedition_duelist.gd")
## Provisional: chance to open with the lunge when in its reach and out of sword reach.
const SIGNATURE_CHANCE := 0.4

var marrow_arm := false
var post := Vector3.ZERO

func _ready() -> void:
	super._ready()
	visual = ExpeditionDuelist.swap_visual(self, visual, ExpeditionVisual)

func equip(lab_tuning: Dictionary, resolved: Dictionary) -> void:
	super.equip(lab_tuning, resolved)
	state = ExpeditionDuelist.state_for(lab_tuning, state, resolved, ExpeditionState)
	marrow_arm = ExpeditionDuelist.has_marrow_arm(resolved)
	if is_instance_valid(visual):
		visual.rebuild()

func _attack(view: Dictionary, delta: float) -> void:
	if mode == "duel" and state.phase == State.Phase.IDLE and not state.guarding and cooldown <= 0.0 and not counter_ready and _try_signature():
		return
	super._attack(view, delta)

## The lunge reaches past the sword: only worth it beyond sword reach, inside its own.
func _try_signature() -> bool:
	var legal: Dictionary = state.legal_actions()
	if not legal.signature or state.stamina.current < legal.signature_cost + tuning.ai_stamina_margin:
		return false
	var distance := global_position.distance_to(opponent.global_position)
	if distance <= state.base_h.reach + 0.3 or distance > float(state.signature.reach):
		return false
	cooldown = tuning.ai_attack_interval + rng.randf() * 0.5
	if rng.randf() >= SIGNATURE_CHANCE or not state.press_signature():
		return false
	hold_for = 0.0
	_log("signature", {"distance": snappedf(distance, 0.001)})
	return true
