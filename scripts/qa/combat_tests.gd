extends SceneTree

const Rules = preload("res://scripts/combat/combat_state.gd")
var passed := 0
var failed := 0
var negative := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--negative="):
			negative = arg.get_slice("=", 1)
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	print(JSON.stringify({"suite": "combat", "check": label, "passed": condition, "negative": negative}))

func active_attacker() -> CombatState:
	var attacker := Rules.new()
	attacker.attack()
	attacker.tick(attacker.attack_windup + 0.001)
	return attacker

func run() -> void:
	var a := Rules.new()
	var b := Rules.new()
	check(a.attack(), "idle_can_attack")
	if negative == "phase":
		a.phase = Rules.Phase.ACTIVE
	check(b.receive(a) == "invalid" and b.health == 100.0, "windup_cannot_damage")
	a = active_attacker()
	check(a.phase == Rules.Phase.ACTIVE, "windup_enters_active")
	check(b.receive(a) == "hit" and b.health == 82.0, "active_damage")
	check(b.receive(a) == "invalid" and b.health == 82.0, "one_hit_per_swing")
	a.tick(a.active_duration)
	check(a.phase == Rules.Phase.RECOVERY, "active_enters_recovery")
	check(not a.attack(), "cannot_cancel_recovery")
	a.tick(1.0)
	check(a.phase == Rules.Phase.IDLE, "recovery_returns_idle")
	a = Rules.new()
	a.attack()
	a.tick(0.6)
	check(a.phase == Rules.Phase.RECOVERY and is_equal_approx(a.remaining, 0.35), "phase_overshoot_preserved")
	b.reset()
	b.set_guard(true)
	b.tick(0.3)
	if negative == "guard":
		b.guard_chip = 1.0
	check(b.receive(active_attacker()) == "guard", "late_guard_is_guard_not_deflection")
	check(b.health > 82.0 and b.health < 100.0, "guard_mitigates_damage")
	check(b.posture == 28.0, "guard_creates_posture_pressure")
	b.reset()
	b.set_guard(true)
	b.tick(0.05)
	a = active_attacker()
	if negative == "deflect":
		b.deflect_window = 0.0
	check(b.receive(a) == "deflected" and b.health == 100.0, "timed_deflection")
	check(a.posture == 42.0 and a.phase == Rules.Phase.STAGGER, "deflection_pressures_attacker")
	b.deflect_window = 0.16
	b.reset()
	b.set_guard(true)
	b.tick(0.25)
	check(b.receive(active_attacker()) != "deflected", "mistimed_deflection_fails")
	b.reset()
	b.set_guard(true)
	b.tick(0.3)
	for i in range(4):
		b.receive(active_attacker())
	check(b.phase == Rules.Phase.BROKEN and b.posture == 100.0 and not b.guarding, "repeated_guard_breaks_posture")
	var before := b.health
	var break_before := b.remaining
	b.receive(active_attacker())
	check(is_equal_approx(before - b.health, 36.0), "broken_target_takes_double_damage")
	check(b.remaining == break_before, "punish_does_not_extend_break")
	b.tick(b.break_duration + 0.01)
	check(b.phase == Rules.Phase.IDLE and b.posture == 0.0, "break_recovers")
	b.reset()
	a = Rules.new()
	a.attack(true)
	a.tick(a.heavy_windup + 0.001)
	b.receive(a)
	check(b.health == 68.0, "heavy_attack_damage")
	b.reset()
	check(b.dodge(), "dodge_starts")
	check(b.receive(active_attacker()) == "evaded" and b.health == 100.0, "dodge_evades")
	b.tick(0.31)
	check(not b.dodge(), "dodge_has_cooldown")
	b.tick(0.4)
	check(b.dodge(), "dodge_cooldown_expires")
	b.reset()
	b.add_posture(40.0)
	b.tick(0.5)
	check(b.posture == 40.0, "posture_recovery_delay")
	b.tick(1.5)
	check(b.posture < 40.0, "posture_recovers_when_safe")
	b.reset()
	for i in range(6):
		b.receive(active_attacker())
	check(b.phase == Rules.Phase.DEAD and b.health == 0.0, "target_can_die")
	check(not b.attack() and not b.dodge(), "dead_actor_cannot_act")
	b.reset()
	check(b.health == 100.0 and b.posture == 0.0 and b.phase == Rules.Phase.IDLE and not b.guarding and b.dodge_ready_in == 0.0 and b.last_event == "" and not b.hit_consumed, "reset_restores_combat_state")
	# Independent step sizes must land on the same combat phase and duration.
	a = Rules.new()
	b = Rules.new()
	a.attack(true)
	b.attack(true)
	a.tick(0.93)
	for i in range(93):
		b.tick(0.01)
	check(a.phase == b.phase and absf(a.remaining - b.remaining) < 0.00001, "timing_independent_of_step_size")
	print(JSON.stringify({"suite": "combat", "summary": true, "passed": passed, "failed": failed, "negative": negative}))
	quit(1 if failed else 0)
