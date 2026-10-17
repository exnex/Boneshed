extends Node3D

const Player = preload("res://scripts/characters/player.gd")
const Swordsman = preload("res://scripts/ai/swordsman.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
var player: Fighter
var enemy: Fighter
var hud: Control
var event_text := "Enter the circle. Face the corrupted soul."
var event_time := 0.0
var encounter_time := 0.0
var qa_mode := false

func _ready() -> void:
	_setup_input()
	_build_courtyard()
	player = Player.new()
	player.name = "Pilgrim"
	add_child(player)
	enemy = Swordsman.new()
	enemy.name = "CorruptedSwordsman"
	add_child(enemy)
	player.opponent = enemy
	enemy.opponent = player
	reset_encounter()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	hud.set_script(preload("res://scripts/hud.gd"))
	hud.arena = self
	canvas.add_child(hud)
	qa_mode = "--qa" in OS.get_cmdline_user_args()
	if qa_mode:
		var qa := Node.new()
		qa.set_script(load("res://scripts/qa/graphical_test.gd"))
		add_child(qa)
	elif OS.has_feature("web_qa"):
		var probe := Node.new()
		probe.set_script(load("res://scripts/qa/web_probe.gd"))
		add_child(probe)
	elif not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.has_feature("web"):
		print("BONESHED_WEB_READY")

func _physics_process(delta: float) -> void:
	encounter_time += delta
	event_time = maxf(0.0, event_time - delta)
	# Resolve after both actors tick/move (deferred), with a fixed player-first tie rule.
	_resolve_duel.call_deferred()
	if Input.is_action_just_pressed("reset"):
		reset_encounter()
	if Input.is_action_just_pressed("debug"):
		player.debug_hitboxes = not player.debug_hitboxes
		enemy.debug_hitboxes = player.debug_hitboxes

func _resolve_duel() -> void:
	for fighter in [player, enemy]:
		var result: String = fighter.resolve_attack()
		if result not in ["invalid", "out_of_range"]:
			event_text = "%s · %s" % [fighter.opponent.name, fighter.opponent.combat.last_event]
			event_time = 1.3

func reset_encounter() -> void:
	player.reset_at(Vector3(0.0, 0.02, 4.0))
	enemy.reset_at(Vector3(0.0, 0.02, -3.0))
	encounter_time = 0.0
	event_text = "Enter the circle. Face the corrupted soul."
	event_time = 3.0

func _setup_input() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "dodge": KEY_SPACE, "lock_on": KEY_TAB, "reset": KEY_R, "release_mouse": KEY_ESCAPE, "debug": KEY_F3}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	for action in {"attack": MOUSE_BUTTON_LEFT, "guard": MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, event)

func _block(point: Vector3, size: Vector3, color: Color, collision := true) -> void:
	Fighter.mesh_part(self, BoxMesh.new(), point, size, Fighter.material(color))
	if collision:
		var body := StaticBody3D.new()
		body.position = point
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)

func _build_courtyard() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("26353c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("a2bec5")
	world.environment.ambient_light_energy = 0.35
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.fog_enabled = true
	world.environment.fog_light_color = Color("384c52")
	world.environment.fog_density = 0.009
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_color = Color("ead5b5")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	_block(Vector3(0.0, -0.3, 0.0), Vector3(24.0, 0.6, 24.0), Color("424d50"))
	# Slightly inset joints make the courtyard readable without imported textures.
	for x in range(-6, 6):
		for z in range(-6, 6):
			var tone := 0.015 * float(posmod(x * 7 + z * 3, 5))
			_block(Vector3(x * 2.0 + 1.0, 0.004, z * 2.0 + 1.0), Vector3(1.96, 0.012, 1.96), Color(0.24 + tone, 0.29 + tone, 0.30 + tone), false)
	for side in [-1.0, 1.0]:
		_block(Vector3(side * 12.0, 1.2, 0.0), Vector3(0.8, 2.4, 24.0), Color("374349"))
		_block(Vector3(0.0, 1.2, side * 12.0), Vector3(24.0, 2.4, 0.8), Color("374349"))
		for z in [-9.0, -3.0, 3.0, 9.0]:
			var height := 4.0 if z < 0.0 else 2.6
			_block(Vector3(side * 9.0, height / 2.0, z), Vector3(1.1, height, 1.1), Color("586267"))
			_block(Vector3(side * 9.0, height + 0.1, z), Vector3(1.4, 0.25, 1.4), Color("667071"))
		_block(Vector3(side * 7.3, 0.25, -7.0), Vector3(1.8, 0.5, 2.4), Color("4d595b"))
		# Warm braziers against a desaturated courtyard.
		for z in [-6.0, 6.0]:
			_block(Vector3(side * 7.0, 0.75, z), Vector3(0.55, 1.5, 0.55), Color("30383a"))
			Fighter.mesh_part(self, SphereMesh.new(), Vector3(side * 7.0, 1.6, z), Vector3(0.38, 0.5, 0.38), Fighter.material(Color("f3b467"), true))
			var light := OmniLight3D.new()
			light.position = Vector3(side * 7.0, 2.2, z)
			light.light_color = Color("f8aa65")
			light.omni_range = 5.0
			light.light_energy = 2.5
			add_child(light)
	# Broken gate and distant buttresses frame the duel.
	for x in [-4.0, 4.0]:
		_block(Vector3(x, 3.0, -10.0), Vector3(1.6, 6.0, 1.5), Color("526066"))
	_block(Vector3(-1.6, 5.5, -10.0), Vector3(3.6, 0.8, 1.5), Color("526066"))
	for index in range(8):
		_block(Vector3(-7.0 + index * 1.8, 0.18, -8.2 + (index % 3) * 0.7), Vector3(0.5, 0.36, 0.8), Color("697070"))
	var ring := TorusMesh.new()
	ring.inner_radius = 5.9
	ring.outer_radius = 6.0
	ring.rings = 64
	Fighter.mesh_part(self, ring, Vector3(0.0, 0.025, 0.0), Vector3(1.0, 0.025, 1.0), Fighter.material(Color("a39370")))
