extends SceneTree
## Run against either checkout. Uses only the pre-integration public combat API.
## The committed fixture was captured on main 4c651e3 with the pinned engine.
const Courtyard = preload("res://scenes/courtyard.tscn")
const Rules = preload("res://scripts/combat/combat_state.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var arena = Courtyard.instantiate()
	root.add_child(arena)
	var output := "res://artifacts/combat-runtime.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(collect(arena), "\t", true) + "\n")
	arena.free()
	quit()

static func state(actor) -> Dictionary:
	return {"health": actor.health, "posture": actor.posture, "phase": actor.phase,
		"remaining": snappedf(actor.remaining, 0.0001), "guarding": actor.guarding,
		"hit_consumed": actor.hit_consumed, "event": actor.last_event}

static func collect(arena) -> Dictionary:
	var result := {}
	for actor_name in ["player", "enemy"]:
		var fighter = arena.get(actor_name)
		var attacker = fighter.combat
		var defender = fighter.opponent.combat
		var config := {"move_speed": fighter.move_speed}
		for field in ["max_health", "max_posture", "deflect_window", "deflect_rearm", "guard_chip", "deflect_posture",
			"posture_recovery_delay", "commitment_duration", "release_duration", "dodge_duration", "dodge_cooldown", "break_duration"]:
			config[field] = attacker.get(field)
		result[actor_name] = {"config": config, "attacks": {}}
		for heavy_attack in [false, true]:
			attacker.reset()
			attacker.attack(heavy_attack)
			var attack := {"windup": attacker.remaining, "active": attacker.active_duration, "recovery": attacker.recovery_duration}
			var transitions := [state(attacker)]
			for tick in range(120):
				var before = attacker.phase
				attacker.tick(1.0 / 60.0)
				if attacker.phase != before:
					var entry := state(attacker)
					entry["tick"] = tick + 1
					transitions.append(entry)
			attack["transitions"] = transitions
			var contacts := {}
			for defense in ["hit", "guard", "deflect", "rear", "dodge", "broken"]:
				attacker.reset()
				defender.reset()
				attacker.attack(heavy_attack)
				attacker.tick(attacker.remaining + 0.001)
				if defense in ["guard", "deflect", "rear"]:
					defender.set_guard(true)
					if defense == "guard":
						defender.tick(0.3)
				elif defense == "dodge":
					defender.dodge()
				elif defense == "broken":
					defender.add_posture(defender.max_posture)
				var event = defender.receive(attacker, -1.0 if defense == "rear" else 1.0)
				contacts[defense] = {"result": event, "attacker": state(attacker), "defender": state(defender)}
			attack["contacts"] = contacts
			result[actor_name].attacks["heavy" if heavy_attack else "light"] = attack
		attacker.reset()
		attacker.posture = 60.0
		attacker.tick(2.0)
		result[actor_name]["posture_after_2s"] = attacker.posture
	return result
