extends SceneTree
## Before/after comparison harness (evidence only). Uses only API common to the original
## and new swordsman. To rerun, copy into scripts/qa/ of each checkout and run with
## --headless --fixed-fps 60 --script res://scripts/qa/compare_styles.gd
const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var p: Fighter
var e: Fighter
var held := {}

func _initialize() -> void:
	call_deferred("run")

func press(action: String, pressed := true) -> void:
	if held.get(action, false) == pressed:
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	held[action] = pressed

func release_all() -> void:
	for a: String in held:
		if held[a]:
			press(a, false)

func step(n := 1) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func d() -> float:
	return p.position.distance_to(e.position)

func run() -> void:
	for scene: String in ["courtyard", "salvage_courtyard"]:
		arena = load("res://scenes/%s.tscn" % scene).instantiate()
		root.add_child(arena)
		p = arena.player
		e = arena.enemy
		await step(3)
		var styles := {
			"masher": func(f: int) -> void: press("attack", f % 2 == 0),
			"aggressive": func(f: int) -> void:
				press("move_forward", d() > 1.6)
				press("attack", f % 5 == 0),
			"guarding": func(_f: int) -> void:
				press("move_forward", d() > 1.8)
				press("guard", true),
			"passive": func(_f: int) -> void: pass,
			"retreating": func(_f: int) -> void:
				press("move_back", d() < 2.9)
				press("move_forward", d() > 3.6),
			"skilled": func(_f: int) -> void:
				var ec: Rules = e.combat
				var defend: bool = ec.phase == Rules.Phase.WINDUP and ec.remaining < 0.12 and p.combat.phase == Rules.Phase.IDLE
				press("guard", defend)
				press("attack", p.combat.phase == Rules.Phase.IDLE and not defend and ec.phase in [Rules.Phase.BROKEN, Rules.Phase.RECOVERY, Rules.Phase.STAGGER])
				press("move_forward", d() > 2.0),
			"spacer": func(f: int) -> void:
				var t := f % 100
				press("move_forward", t < 45 and d() > 2.25)
				press("attack", t == 45)
				press("move_back", t >= 50 and t < 90),
			"feinter": func(f: int) -> void:
				var t := f % 70
				press("move_forward", d() > 1.9)
				press("attack", t == 0)
				press("guard", t >= 10 and t < 30),
		}
		for name: String in styles:
			release_all()
			await step(2)
			arena.reset_encounter()
			p.input_enabled = true
			e.enabled = true
			p.position = Vector3(0, 0.02, 3.2 if name == "retreating" else 1.85)
			e.position = Vector3(0, 0.02, 0)
			p.facing = Vector3.FORWARD
			e.facing = Vector3.BACK
			p.yaw = 0.0
			p.locked = true
			var f := 0
			var dodges := 0
			var guard_ticks := 0
			var windups := 0
			var hits_taken := 0
			var hits_dealt := 0
			var se := 0
			var sp := 0
			var last := Rules.Phase.IDLE
			while f < 2400 and e.combat.phase != Rules.Phase.DEAD and p.combat.phase != Rules.Phase.DEAD:
				styles[name].call(f)
				await step(1)
				f += 1
				if e.combat.phase != last:
					dodges += int(e.combat.phase == Rules.Phase.DODGE)
					windups += int(e.combat.phase == Rules.Phase.WINDUP)
					last = e.combat.phase
				guard_ticks += int(e.combat.guarding)
				if e.event_serial > se and e.last_result in ["hit", "punish", "defeated"]:
					hits_taken += 1
				if p.event_serial > sp and p.last_result in ["hit", "punish", "defeated"]:
					hits_dealt += 1
				se = e.event_serial
				sp = p.event_serial
			release_all()
			var winner := "player" if e.combat.phase == Rules.Phase.DEAD else ("enemy" if p.combat.phase == Rules.Phase.DEAD else "timeout")
			print(JSON.stringify({"scene": scene, "style": name, "winner": winner, "seconds": snappedf(f / 60.0, 0.01), "player_health": p.combat.health, "enemy_health": snappedf(e.combat.health, 0.01), "enemy_hits_taken": hits_taken, "enemy_hits_dealt": hits_dealt, "enemy_attacks": windups, "enemy_dodges": dodges, "enemy_guard_seconds": snappedf(guard_ticks / 60.0, 0.01)}))
		release_all()
		await step(1)
		arena.free()
	quit(0)
