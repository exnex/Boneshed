class_name CombatState
extends RefCounted
## Shared, presentation-independent rules. All durations are seconds.
## Every mechanic here is provisional tuning for the first duel.

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY, STAGGER, BROKEN, DODGE, DEAD }

var max_health := 100.0
var max_posture := 100.0
var health := 100.0
var posture := 0.0
var phase: Phase = Phase.IDLE
var remaining := 0.0
var guarding := false
var guard_age := 99.0
var guard_input_held := false
var deflect_ready_in := 0.0
var hit_consumed := false
var heavy := false
var attack_windup := 0.34
var heavy_windup := 0.85
var active_duration := 0.16
var recovery_duration := 0.45
var deflect_window := 0.16
var deflect_rearm := 0.32
var guard_arc_cos := 0.0 # Front hemisphere, including the side boundary.
var commitment_duration := 0.24
var release_duration := 0.08 # Final windup: blade accelerates before contact.
var guard_chip := 0.12
var guard_posture := 28.0
var deflect_posture := 42.0
var break_duration := 2.2
var dodge_duration := 0.30
var dodge_cooldown := 0.65
var dodge_ready_in := 0.0
var posture_recovery_delay := 1.5
var since_pressure := 0.0
var last_event := ""

func reset(guard_held := false) -> void:
	health = max_health
	posture = 0.0
	phase = Phase.IDLE
	remaining = 0.0
	guarding = false
	guard_age = 99.0
	guard_input_held = guard_held
	deflect_ready_in = 0.0
	hit_consumed = false
	heavy = false
	dodge_ready_in = 0.0
	since_pressure = 0.0
	last_event = ""

func set_guard(held: bool, allow_deflect := true) -> void:
	# Track input even while unable to guard. Holding through an action only blocks;
	# it cannot manufacture a fresh deflection when the actor returns to idle.
	var pressed := held and not guard_input_held
	guard_input_held = held
	if pressed:
		_cancel_attack()
	var allowed := phase == Phase.IDLE
	if pressed:
		guard_age = 0.0 if allowed and allow_deflect and deflect_ready_in <= 0.0 else 99.0
		# Every unsuccessful re-press restarts settling. Guard itself stays available.
		deflect_ready_in = deflect_rearm
	guarding = held and allowed
	if not guarding:
		guard_age = 99.0

func attack_stage() -> String:
	if phase == Phase.WINDUP:
		if remaining <= release_duration:
			return "release"
		return "committed" if remaining <= commitment_duration else "early"
	return "active" if phase == Phase.ACTIVE else ("recovery" if phase == Phase.RECOVERY else "none")

func resists_interrupt() -> bool:
	# Shared by both forms. Health, posture, death and deflection still apply.
	return heavy and (phase == Phase.ACTIVE or (phase == Phase.WINDUP and remaining <= commitment_duration))

func attack(is_heavy := false) -> bool:
	if phase != Phase.IDLE or guarding:
		return false
	heavy = is_heavy
	hit_consumed = false
	phase = Phase.WINDUP
	remaining = heavy_windup if heavy else attack_windup
	return true

func dodge() -> bool:
	if phase not in [Phase.IDLE, Phase.WINDUP, Phase.ACTIVE, Phase.RECOVERY] or dodge_ready_in > 0.0:
		return false
	_cancel_attack()
	guarding = false
	guard_age = 99.0
	phase = Phase.DODGE
	remaining = dodge_duration
	dodge_ready_in = dodge_cooldown
	return true

func _cancel_attack() -> void:
	if phase not in [Phase.WINDUP, Phase.ACTIVE, Phase.RECOVERY]:
		return
	# Discard the old swing before deferred hit resolution, including a swing
	# already in its active window. A later action starts a new swing explicitly.
	phase = Phase.IDLE
	remaining = 0.0
	hit_consumed = true
	heavy = false

func tick(delta: float) -> void:
	guard_age += delta
	deflect_ready_in = maxf(0.0, deflect_ready_in - delta)
	dodge_ready_in = maxf(0.0, dodge_ready_in - delta)
	since_pressure += delta
	if phase == Phase.IDLE:
		if not guarding and since_pressure > posture_recovery_delay:
			posture = maxf(0.0, posture - 12.0 * delta)
		return
	if phase == Phase.DEAD:
		return
	remaining -= delta
	# Carry overshoot through each phase: timing is independent of render FPS.
	while remaining <= 0.0 and phase != Phase.IDLE:
		match phase:
			Phase.WINDUP:
				phase = Phase.ACTIVE
				remaining += active_duration
			Phase.ACTIVE:
				phase = Phase.RECOVERY
				remaining += recovery_duration
			_:
				if phase == Phase.BROKEN:
					posture = 0.0
				phase = Phase.IDLE
				remaining = 0.0

func add_posture(amount: float) -> void:
	posture = minf(max_posture, posture + amount)
	since_pressure = 0.0
	if posture >= max_posture and phase not in [Phase.DEAD, Phase.BROKEN]:
		phase = Phase.BROKEN
		remaining = break_duration
		guarding = false
		last_event = "POSTURE BREAK"

func receive(attacker: CombatState, incoming_facing_dot := 1.0) -> String:
	if attacker.phase != Phase.ACTIVE or attacker.hit_consumed or phase == Phase.DEAD:
		return "invalid"
	attacker.hit_consumed = true
	if phase == Phase.DODGE:
		last_event = "EVADED"
		return "evaded"
	var damage := 32.0 if attacker.heavy else 18.0
	var protected := guarding and incoming_facing_dot >= guard_arc_cos
	if protected and guard_age <= deflect_window:
		attacker.add_posture(deflect_posture)
		if attacker.phase != Phase.BROKEN:
			var punish_time := attacker.remaining + attacker.recovery_duration
			attacker.phase = Phase.STAGGER
			attacker.remaining = maxf(0.35, punish_time)
		deflect_ready_in = 0.0 # A successful read earns the next attempt immediately.
		guard_age = 99.0 # One deflection per raise, even against multiple attackers.
		last_event = "DEFLECTION"
		return "deflected"
	if protected:
		health = maxf(0.0, health - damage * guard_chip)
		add_posture(guard_posture * (1.5 if attacker.heavy else 1.0))
		# A block consumes this hit but preserves the attack's normal follow-through.
		last_event = "GUARD"
	else:
		var vulnerable := phase == Phase.BROKEN
		var poised := resists_interrupt()
		health = maxf(0.0, health - damage * (2.0 if vulnerable else 1.0))
		if not vulnerable and not poised:
			# A hit never shortens a recovery or stagger already being served.
			var lockout := remaining if phase in [Phase.RECOVERY, Phase.STAGGER] else 0.0
			phase = Phase.STAGGER
			remaining = maxf(0.24, lockout)
		guarding = false
		add_posture(18.0)
		last_event = "PUNISH" if vulnerable else "HIT"
	if health <= 0.0:
		phase = Phase.DEAD
		guarding = false
		last_event = "DEFEATED"
	return last_event.to_lower()
