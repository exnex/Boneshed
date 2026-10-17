extends Node
## Only the separate Web QA export contains this instrumentation.
## Tests send actual browser keyboard/mouse inputs; commands arrange fixtures.

var arena: Node3D
var callback: JavaScriptObject
var ticks := 0
var attack_on_guard := false

func _ready() -> void:
	arena = get_parent()
	callback = JavaScriptBridge.create_callback(_command)
	JavaScriptBridge.get_interface("window").boneshedCommand = callback

func _command(args: Array) -> void:
	if args.is_empty():
		return
	var command := str(args[0])
	if command == "reset":
		arena.reset_encounter()
	elif command == "fixture":
		attack_on_guard = false
		arena.reset_encounter()
		arena.enemy.enabled = false
		arena.player.position = Vector3(0.0, 0.02, 2.0)
		arena.enemy.position = Vector3(0.0, 0.02, 0.0)
		arena.player.facing = Vector3.FORWARD
		arena.enemy.facing = Vector3.BACK
		arena.player.locked = true
	elif command == "enemy_attack":
		arena.enemy.combat.attack()
	elif command == "enemy_slow_attack":
		arena.enemy.combat.attack(true)
	elif command == "ai_off":
		arena.enemy.enabled = false
	elif command == "ai_on":
		arena.enemy.enabled = true
	elif command == "fresh_attack":
		# The previously sampled tick is no longer active; arrange a fresh incoming
		# attack near the deflection window for timing validation on slow CI renderers.
		arena.enemy.combat.reset()
		arena.enemy.combat.attack()
		arena.enemy.combat.remaining = 0.12
	elif command == "attack_on_guard":
		attack_on_guard = true

func _physics_process(_delta: float) -> void:
	ticks += 1
	if attack_on_guard and Input.is_action_pressed("guard"):
		attack_on_guard = false
		arena.enemy.combat.attack()
		arena.enemy.combat.remaining = 0.08
	var p = arena.player
	var e = arena.enemy
	var state := {"tick": ticks, "viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "player": {"position": [p.position.x, p.position.y, p.position.z], "health": p.combat.health, "posture": p.combat.posture, "phase": p.combat.phase, "guarding": p.combat.guarding, "guard_age": p.combat.guard_age, "event": p.last_result, "yaw": p.yaw, "pitch": p.pitch, "locked": p.locked}, "enemy": {"health": e.combat.health, "posture": e.combat.posture, "phase": e.combat.phase, "remaining": e.combat.remaining}, "actions": {"attack": Input.is_action_pressed("attack"), "guard": Input.is_action_pressed("guard"), "move_forward": Input.get_action_strength("move_forward")}}
	JavaScriptBridge.eval("window.boneshedState = " + JSON.stringify(state))
