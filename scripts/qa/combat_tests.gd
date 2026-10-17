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
	# Review fix: a hit must never shorten a lockout the target is already serving.
	a = active_attacker()
	a.tick(a.active_duration)
	var lockout := a.remaining
	a.receive(active_attacker())
	check(a.phase == Rules.Phase.STAGGER and a.remaining >= lockout - 0.0001, "hit_does_not_shorten_recovery")
	a.reset()
	a.phase = Rules.Phase.STAGGER
	a.remaining = 0.35
	a.receive(active_attacker())
	check(a.remaining >= 0.35 - 0.0001, "hit_does_not_shorten_stagger")
	a.reset()
	a.receive(active_attacker())
	check(a.phase == Rules.Phase.STAGGER and is_equal_approx(a.remaining, 0.24), "idle_hit_stagger_unchanged")
	# Independent step sizes must land on the same combat phase and duration.
	a = Rules.new()
	b = Rules.new()
	a.attack(true)
	b.attack(true)
	a.tick(0.93)
	for i in range(93):
		b.tick(0.01)
	check(a.phase == b.phase and absf(a.remaining - b.remaining) < 0.00001, "timing_independent_of_step_size")
	deflection_discipline()
	heavy_interrupts()
	attack_defense_cancels()
	print(JSON.stringify({"suite": "combat", "summary": true, "passed": passed, "failed": failed, "negative": negative}))
	quit(1 if failed else 0)

func attack_defense_cancels() -> void:
	for is_heavy in [false, true]:
		for phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			for defense in ["dodge", "guard"]:
				var actor := Rules.new()
				actor.attack(is_heavy)
				if phase == Rules.Phase.ACTIVE:
					actor.tick((actor.heavy_windup if is_heavy else actor.attack_windup) + 0.01)
				elif phase == Rules.Phase.RECOVERY:
					actor.tick((actor.heavy_windup if is_heavy else actor.attack_windup) + actor.active_duration + 0.01)
				var label: String = defense + "_" + Rules.Phase.keys()[phase] + "_heavy_" + str(is_heavy)
				if defense == "dodge":
					check(actor.dodge() and actor.phase == Rules.Phase.DODGE, "cancel_into_" + label)
					check(actor.receive(active_attacker()) == "evaded" and actor.health == 100.0 and actor.posture == 0.0, "cancel_dodge_iframes_" + label)
				else:
					actor.set_guard(true)
					check(actor.phase == Rules.Phase.IDLE and actor.guarding, "cancel_into_" + label)
					check(actor.receive(active_attacker()) == "deflected" and actor.health == 100.0, "cancel_guard_can_time_deflect_" + label)
				var target := Rules.new()
				check(actor.hit_consumed and not actor.heavy and target.receive(actor) == "invalid" and target.health == 100.0, "cancel_discards_old_hit_" + label)
				actor.tick(2.0)
				check(target.receive(actor) == "invalid" and target.health == 100.0, "cancel_never_resumes_swing_" + label)
	for age in [0.0, 0.15, 0.299, 0.301]:
		var actor := Rules.new()
		actor.dodge()
		actor.tick(age)
		check(actor.receive(active_attacker()) == ("evaded" if age < actor.dodge_duration else "hit"), "dodge_iframe_boundary_" + str(age))
	var actor := Rules.new()
	actor.attack()
	actor.dodge_ready_in = 0.2
	check(not actor.dodge() and actor.phase == Rules.Phase.WINDUP and not actor.hit_consumed, "dodge_on_cooldown_does_not_cancel_attack")
	actor.set_guard(true)
	actor.set_guard(false)
	actor.attack()
	actor.set_guard(true)
	check(actor.guarding and actor.receive(active_attacker()) == "guard", "guard_cancel_cannot_bypass_deflect_rearm")
	for locked_phase in [Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.DEAD, Rules.Phase.DODGE]:
		actor.reset()
		actor.phase = locked_phase
		actor.remaining = 0.2
		actor.set_guard(true)
		check(not actor.guarding and not actor.dodge() and actor.phase == locked_phase, "cannot_defense_cancel_" + Rules.Phase.keys()[locked_phase])

func deflection_discipline() -> void:
	var defender := Rules.new()
	defender.set_guard(true)
	defender.tick(0.05)
	check(defender.receive(active_attacker()) == "deflected", "fresh_precise_press_deflects")
	check(defender.receive(active_attacker()) == "guard", "one_deflection_per_raise")
	defender.set_guard(false)
	defender.set_guard(true)
	check(defender.receive(active_attacker()) == "deflected", "successful_deflect_rearms_next_press")
	defender.reset()
	defender.set_guard(true)
	defender.tick(0.20)
	check(defender.receive(active_attacker()) == "guard", "early_press_blocks_with_chip")
	defender.reset()
	check(defender.receive(active_attacker()) == "hit", "late_press_takes_hit")
	defender.set_guard(true)
	defender.tick(0.25)
	defender.set_guard(true)
	check(defender.guarding and defender.guard_age > defender.deflect_window, "held_during_stagger_returns_as_block_only")
	defender.reset()
	defender.set_guard(true)
	for i in range(120):
		defender.tick(1.0 / 60.0)
		defender.set_guard(true)
	check(defender.receive(active_attacker()) == "guard", "held_guard_never_refreshes_window")
	defender.reset()
	if negative == "toggle":
		defender.deflect_rearm = 0.0
	defender.set_guard(true)
	defender.tick(0.15)
	defender.set_guard(false)
	defender.tick(1.0 / 60.0)
	defender.set_guard(true)
	check(defender.guarding and defender.receive(active_attacker()) == "guard", "rapid_toggle_cannot_refresh_deflect")
	# Each attempted raise extends settling: periodically tapping is not a free retry.
	defender.reset()
	var deflections := 0
	for i in range(12):
		defender.set_guard(true)
		defender.tick(0.15)
		if i > 0 and defender.receive(active_attacker()) == "deflected":
			deflections += 1
		defender.set_guard(false)
		defender.tick(1.0 / 60.0)
		# Avoid a posture break obscuring whether the guard press rearmed.
		defender.posture = 0.0
	check(deflections == 0, "continuous_toggle_stays_in_settling")
	defender.set_guard(false)
	defender.tick(defender.deflect_rearm + 0.001)
	defender.set_guard(true)
	check(defender.receive(active_attacker()) == "deflected", "brief_settling_restores_full_window")
	defender.reset(true)
	defender.set_guard(true)
	check(defender.receive(active_attacker()) == "guard", "guard_held_through_reset_is_block_only")
	for dot in [1.0, 0.0, -0.01, -1.0]:
		defender.reset()
		if negative == "rear":
			defender.guard_arc_cos = -1.0
		defender.set_guard(true)
		var result := defender.receive(active_attacker(), dot)
		check(result == ("deflected" if dot >= 0.0 else "hit"), "guard_arc_dot_" + str(dot))
	defender = Rules.new()
	defender.set_guard(true)
	var attacker := active_attacker()
	var natural_lockout := attacker.remaining + attacker.recovery_duration
	defender.receive(attacker)
	check(attacker.remaining >= natural_lockout, "deflection_preserves_full_punish_window")
	defender.reset()
	defender.set_guard(true)
	defender.tick(0.3)
	attacker = active_attacker()
	var active_remaining := attacker.remaining
	defender.receive(attacker)
	check(attacker.phase == Rules.Phase.ACTIVE and attacker.remaining == active_remaining, "block_preserves_visible_follow_through")

func heavy_interrupts() -> void:
	for heavy_attack in [false, true]:
		for remaining_time in [0.40, 0.20, 0.04]:
			var target := Rules.new()
			target.attack(heavy_attack)
			target.remaining = remaining_time
			if negative == "poise":
				target.commitment_duration = 0.0
			target.receive(active_attacker())
			var should_resist: bool = heavy_attack and remaining_time <= 0.24
			check(target.phase == (Rules.Phase.WINDUP if should_resist else Rules.Phase.STAGGER) and target.health == 82.0 and target.posture == 18.0,
				"heavy_commitment_" + str(heavy_attack) + "_" + str(remaining_time))
	var target := Rules.new()
	target.attack(true)
	target.tick(target.heavy_windup + 0.001)
	target.receive(active_attacker())
	check(target.phase == Rules.Phase.ACTIVE and target.health == 82.0, "heavy_active_resists_light_interrupt")
	target.posture = 90.0
	target.receive(active_attacker())
	check(target.phase == Rules.Phase.BROKEN, "posture_break_overrides_heavy_poise")
	target.reset()
	target.attack(true)
	target.tick(target.heavy_windup + 0.001)
	var defender := Rules.new()
	defender.set_guard(true)
	check(defender.receive(target) == "deflected" and target.phase == Rules.Phase.STAGGER, "heavy_poise_does_not_prevent_deflection")
	target.reset()
	target.attack(true)
	target.remaining = 0.1
	target.health = 10.0
	target.receive(active_attacker())
	check(target.phase == Rules.Phase.DEAD, "death_overrides_heavy_poise")
