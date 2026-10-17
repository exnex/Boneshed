extends Node
## Only the separate Web QA export contains this instrumentation.
## Tests send actual browser keyboard/mouse inputs; commands arrange fixtures.

var arena: Node3D
var callback: JavaScriptObject
var ticks := 0
var attack_on_guard := false
var attack_on_dodge := false
var attack_cancelled := false
var attack_distance := 0.0
var attack_turn := 0.0
var previous_position := Vector3.ZERO
var previous_facing := Vector3.FORWARD
var previous_phase := 0

func _ready() -> void:
	arena = get_parent()
	previous_position = arena.player.position
	previous_facing = arena.player.facing
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
	elif command == "cancel_fixture":
		arena.reset_encounter()
		arena.enemy.enabled = false
		arena.player.position = Vector3(0.0, 0.02, 2.0)
		arena.enemy.position = Vector3(0.0, 0.02, 0.0)
		arena.enemy.facing = Vector3.BACK
		arena.player.locked = true
		# Browser transport latency must not consume the whole test attack before
		# physical Space/RMB arrives. Native tests cover every normal-duration phase.
		arena.player.combat.attack_windup = 4.0
		arena.player.dodge_speed = 0.0 # Prove invulnerability without leaving reach.
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
	elif command == "attack_on_dodge":
		attack_on_dodge = true
	if command in ["reset", "fixture", "cancel_fixture"]:
		attack_on_guard = false
		attack_on_dodge = false
		attack_cancelled = false
		if command != "cancel_fixture":
			arena.player.combat.attack_windup = 0.34
			arena.player.dodge_speed = 11.0
		attack_distance = 0.0
		attack_turn = 0.0
		previous_position = arena.player.position
		previous_facing = arena.player.facing
		previous_phase = 0

func _physics_process(_delta: float) -> void:
	ticks += 1
	if attack_on_dodge and Input.is_action_pressed("dodge"):
		attack_on_dodge = false
		arena.enemy.combat.attack()
		arena.enemy.combat.remaining = 0.04
	if attack_on_guard and Input.is_action_pressed("guard"):
		attack_on_guard = false
		arena.enemy.combat.attack()
		arena.enemy.combat.remaining = 0.08
	var p = arena.player
	var e = arena.enemy
	if previous_phase in [1, 2, 3] and (p.combat.phase == 6 or p.combat.guarding):
		attack_cancelled = true
	# Count only displacement within attack phases, excluding pre-click walking,
	# action boundaries and reset teleports; browser scheduling cannot inflate it.
	if previous_phase in [1, 2, 3] and p.combat.phase == previous_phase:
		attack_distance += Vector2(p.position.x - previous_position.x, p.position.z - previous_position.z).length()
		if p.desired_move.length_squared() > 0.01:
			attack_turn += previous_facing.angle_to(p.facing)
	previous_position = p.position
	previous_facing = p.facing
	previous_phase = p.combat.phase
	var state := {"tick": ticks, "attack_cancelled": attack_cancelled, "attack_distance": attack_distance, "attack_turn": attack_turn, "viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "player": {"facing": [p.facing.x, p.facing.y, p.facing.z], "position": [p.position.x, p.position.y, p.position.z], "health": p.combat.health, "posture": p.combat.posture, "phase": p.combat.phase, "guarding": p.combat.guarding, "guard_age": p.combat.guard_age, "event": p.last_result, "yaw": p.yaw, "pitch": p.pitch, "locked": p.locked}, "enemy": {"health": e.combat.health, "posture": e.combat.posture, "phase": e.combat.phase, "remaining": e.combat.remaining}, "actions": {"attack": Input.is_action_pressed("attack"), "guard": Input.is_action_pressed("guard"), "move_forward": Input.get_action_strength("move_forward")}}
	JavaScriptBridge.eval("window.boneshedState = " + JSON.stringify(state))
