extends "res://scripts/melee_lab/duelist_state.gd"
## Directional rules state for every fighter in the integrated expedition: the lab's
## duelist_state.gd unchanged, plus the one thing the shared builds still grant that
## the lab never had — the salvaged Marrow Arm's legacy lunge.
##
## The lunge is not a second combat model. It is an ordinary directional *thrust*
## executed by the bone limb: while it is in flight the state's handling (`h`) and
## tuning (`t`) are swapped for the bone's, so the same windup floor, contact solver,
## guard/deflect/evade rules, stamina ledger and status routing apply. Reach, windup
## floor, recovery, damage and posture come from the shared ability values (via
## directional_adapter.gd); bone mass/balance and the stamina scale are data. The
## swap ends when the thrust leaves windup/swing/recovery for any reason (finished,
## cancelled, interrupted, killed). Unavailable without the ability (no build grant).

const SIGNATURE_PHASES := [Phase.WINDUP, Phase.SWING, Phase.RECOVERY]
const SCALED_KEYS := ["accel", "brake", "guard_shift", "turn_rate", "thrust_accel"]

var signature: Dictionary = {}
var signature_h: Dictionary = {}
var signature_t: Dictionary = {}
var signature_cost := 0.0
var signature_active := false
var signature_serial := 0
var base_t: Dictionary = {}

func _init(tuning: Dictionary, handling: Dictionary, stats := {}, combat := {}, granted := {}) -> void:
	super(tuning, handling, stats, combat)
	base_t = tuning
	_configure_signature(granted)

func _configure_signature(granted: Dictionary) -> void:
	signature = granted.duplicate(true)
	if signature.is_empty():
		return
	# The thrust pose holds the hand 0.25 m + extension ahead of the pivot; the bone's
	# length makes the fully extended tip reach the ability's catalog reach.
	var length := maxf(0.5, float(signature.reach) - (0.25 + float(base_t.thrust_extension)))
	var bone := {"item": signature.id, "class": "natural", "grip": "one_handed",
		"handling": {"length": length, "mass": signature.mass, "balance": signature.balance},
		"defense": {"guard": false, "deflect": false}}
	signature_h = Handling.derive(bone, base_t)
	signature_t = base_t.duplicate()
	signature_t.min_windup = maxf(float(base_t.min_windup), float(signature.windup))
	signature_t.thrust_retract = float(signature.recovery)
	signature_t.thrust_damage = float(signature.health_damage)
	signature_t.hit_posture = float(signature.posture_damage)
	signature_cost = float(resources.attack_cost) * float(signature.cost_scale)

func has_signature() -> bool:
	return not signature_h.is_empty()

## Starts the lunge's windup (a thrust). Charged once, now, like any attack. The
## thrust is committed on `release_attack` like every held chamber.
func press_signature() -> bool:
	if not has_signature() or phase != Phase.IDLE or guarding or guard_delay > 0.0:
		return false
	action_serial += 1
	if not stamina.spend("signature", signature_cost, action_serial, clock):
		return false
	attack_paid = signature_cost
	signature_active = true
	signature_serial += 1
	t = signature_t
	h = _scaled(signature_h, handling_scale)
	_begin_windup(Geometry.THRUST)
	return true

## A lunge cannot be redirected into a sword cut mid-windup.
func aim_attack(requested: String) -> void:
	if signature_active:
		return
	super.aim_attack(requested)

func legal_actions() -> Dictionary:
	var legal := super.legal_actions()
	legal.signature = has_signature() and phase == Phase.IDLE and not guarding and guard_delay <= 0.0 and stamina.can_afford(signature_cost)
	legal.signature_cost = signature_cost
	return legal

func tick(delta: float) -> void:
	super.tick(delta)
	if signature_active and phase not in SIGNATURE_PHASES:
		_end_signature()

func reset() -> void:
	if signature_active:
		_end_signature()
	super.reset()

func _cancel_attack() -> void:
	super._cancel_attack()
	if signature_active:
		_end_signature()

func _set_handling_scale(scale: float) -> void:
	super._set_handling_scale(scale)
	if signature_active:
		h = _scaled(signature_h, handling_scale)

func _end_signature() -> void:
	signature_active = false
	t = base_t
	h = _scaled(base_h, handling_scale)

static func _scaled(source: Dictionary, scale: float) -> Dictionary:
	if is_equal_approx(scale, 1.0):
		return source
	var scaled := source.duplicate()
	for key: String in SCALED_KEYS:
		scaled[key] = source[key] * scale
	return scaled
