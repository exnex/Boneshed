extends Node3D
## Adaptive Combat Lab — isolated, separately selectable experiment
## (scenes/adaptive_combat_lab.tscn). One player and one corrupted soul fight with
## procedurally structured objects; the same input produces whatever the shared
## affordance solver derives from each object's structure and each fighter's body.
## Nothing here is read by the default game, the expedition scenes or the other labs.
##
## Order each physics tick: intents (input / AI) → both fighters step → separation →
## contact resolution both ways. Presentation syncs in _process.

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Bodies = preload("res://scripts/adaptive_lab/body_plans.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const AdaptiveFighter = preload("res://scripts/adaptive_lab/adaptive_fighter.gd")
const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const Actor = preload("res://scripts/adaptive_lab/adaptive_actor.gd")
const LabInput = preload("res://scripts/adaptive_lab/adaptive_input.gd")
const Hud = preload("res://scripts/adaptive_lab/adaptive_hud.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const AI_SEED := 7301
const START_DISTANCE := 3.2

var player: AdaptiveFighter
var soul: AdaptiveFighter
var ai: AI
var player_actor: Actor
var soul_actor: Actor
var camera: Camera3D
var hud: Hud
## Per side: recipe index, seed (or -1 for the recipe's seed list), seed index, label override, marrow arm.
var loadout := {
	"player": {"recipe": 2, "seed_index": 0, "seed": -1, "label": "", "marrow": false, "body": "pilgrim"},
	"soul": {"recipe": 0, "seed_index": 0, "seed": -1, "label": "", "marrow": false, "body": "corrupted"},
}
## When valid, replaces keyboard/mouse for the player / the AI for the soul:
## Callable(lab) -> intent (tests and capture scripts).
var player_driver: Callable
var soul_driver: Callable
var paused := false
var camera_yaw := 0.0
## Capture scripts may pin the camera: {"position": Vector3, "target": Vector3}.
var fixed_camera: Dictionary = {}
var _solve_cache := {}
var _fresh_rng := RandomNumberGenerator.new()
var _label_cycle := 0

func _ready() -> void:
	LabInput.install()
	_fresh_rng.randomize()
	MaterialLibrary.set_texture_size(256, 512)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			loadout.player.recipe = Gen.recipe_ids().find(arg.trim_prefix("--player="))
		elif arg.begins_with("--soul="):
			loadout.soul.recipe = Gen.recipe_ids().find(arg.trim_prefix("--soul="))
		elif arg == "--player-marrow":
			loadout.player.marrow = true
	_build_arena()
	player = AdaptiveFighter.new("player")
	soul = AdaptiveFighter.new("soul")
	ai = AI.new(AI_SEED)
	_equip("player")
	_equip("soul")
	player_actor = Actor.new()
	player_actor.name = "PlayerActor"
	add_child(player_actor)
	player_actor.setup(player, "pilgrim")
	soul_actor = Actor.new()
	soul_actor.name = "SoulActor"
	add_child(soul_actor)
	soul_actor.setup(soul, "corrupted")
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.current = true
	add_child(camera)
	hud = Hud.new()
	add_child(hud)
	reset_duel()
	print("BONESHED_ADAPTIVE_READY")

func descriptor_for(side: String) -> Dictionary:
	var l: Dictionary = loadout[side]
	var id: String = Gen.recipe_ids()[l.recipe]
	var seed: int = l.seed if int(l.seed) >= 0 else int(Gen.recipe(id).seeds[int(l.seed_index) % (Gen.recipe(id).seeds as Array).size()])
	return Gen.generate(id, seed, l.label)

func body_for(side: String) -> Dictionary:
	var l: Dictionary = loadout[side]
	return Bodies.build(l.body, ["marrow_arm"] if l.marrow else [])

## Solves through a cache keyed by structure + body; relabelled descriptors hit the
## same entry, which is exactly the claim the label-swap test verifies uncached.
func _equip(side: String) -> void:
	var descriptor := descriptor_for(side)
	var body := body_for(side)
	var key := "%s|%s|%s" % [Gen.fingerprint(descriptor), body.id, ",".join(body.modifications)]
	if not _solve_cache.has(key):
		_solve_cache[key] = Solver.solve(descriptor, body)
	var f: AdaptiveFighter = player if side == "player" else soul
	f.equip(descriptor, body, _solve_cache[key])

func reset_duel() -> void:
	for f: AdaptiveFighter in [player, soul]:
		f.reset_state()
		f.events.clear()
		f.clock = 0.0
	player.position = Vector3(0.0, 0.0, START_DISTANCE * 0.5)
	soul.position = Vector3(0.0, 0.0, -START_DISTANCE * 0.5)
	player.yaw = 0.0
	soul.yaw = PI
	camera_yaw = 0.0
	if player_actor != null:
		player_actor.rebuild()
		soul_actor.rebuild()
	if hud != null:
		hud.set_banner("")

func _physics_process(delta: float) -> void:
	if paused:
		return
	step(delta)

## One rules tick (tests call this directly or via the physics loop).
func step(delta: float) -> void:
	var player_intent: Dictionary = player_driver.call(self) if player_driver.is_valid() else LabInput.read(camera_yaw)
	var soul_intent: Dictionary = soul_driver.call(self) if soul_driver.is_valid() else ai.intent(soul, player, delta)
	player.step(player_intent, soul.position, delta)
	soul.step(soul_intent, player.position, delta)
	AdaptiveFighter.separate(player, soul)
	AdaptiveFighter.resolve(player, soul, delta)
	AdaptiveFighter.resolve(soul, player, delta)

func _process(delta: float) -> void:
	if player_actor == null:
		return
	player_actor.sync(delta)
	soul_actor.sync(delta)
	_update_camera(delta)
	_update_hud()

func _update_camera(delta: float) -> void:
	if not fixed_camera.is_empty():
		camera.position = fixed_camera.position
		camera.look_at(fixed_camera.target, Vector3.UP)
		return
	var to_soul := soul.position - player.position
	to_soul.y = 0.0
	if to_soul.length() > 0.3:
		var desired := atan2(-to_soul.x, -to_soul.z)
		camera_yaw = lerp_angle(camera_yaw, desired, 1.0 - exp(-delta * 4.0)) if delta > 0.0 else desired
	var back := Basis(Vector3.UP, camera_yaw) * Vector3(0.75, 2.1, 4.1)
	camera.position = player.position + back
	var focus := player.position.lerp(soul.position, 0.45) + Vector3(0.0, 1.05, 0.0)
	camera.look_at(focus, Vector3.UP)

func _update_hud() -> void:
	hud.update_fighter("player", "PILGRIM (you) — state %s" % player.state, player, "")
	hud.update_fighter("soul", "CORRUPTED SOUL — AI %s — state %s" % [ai.mode, soul.state], soul, "")
	var lines: Array[String] = []
	var merged: Array = player.events + soul.events
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	for e: Dictionary in merged.slice(maxi(0, merged.size() - 6)):
		lines.append(_event_text(e))
	hud.set_log(lines)
	if player.state == "dead" or soul.state == "dead":
		hud.set_banner(("The soul is released." if soul.state == "dead" else "You fall.") + "  R to reset")

static func _event_text(e: Dictionary) -> String:
	var who: String = "you" if e.who == "player" else "soul"
	match str(e.kind):
		"attack":
			return "%.1fs %s: %s → %s (%s via %s)" % [e.t, who, e.detail.input, e.detail.archetype, e.detail.channel, e.detail.feature]
		"contact":
			return "%.1fs %s: %s with %s" % [e.t, who, e.detail.outcome, e.detail.feature]
		"light_unsupported", "heavy_unsupported", "guard_unsupported":
			return "%.1fs %s: %s — %s" % [e.t, who, e.kind, str(e.detail).substr(0, 90)]
	return "%.1fs %s: %s" % [e.t, who, e.kind]

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.physical_keycode
	if code >= KEY_1 and code <= KEY_5:
		select_recipe("player", code - KEY_1)
	elif code >= KEY_6 and code <= KEY_9:
		select_recipe("soul", code - KEY_6)
	elif code == KEY_0:
		select_recipe("soul", 4)
	elif code == KEY_V:
		next_seed("player", key.shift_pressed)
	elif code == KEY_C:
		next_seed("soul", key.shift_pressed)
	elif code == KEY_B:
		toggle_marrow("player")
	elif code == KEY_N:
		toggle_marrow("soul")
	elif code == KEY_G:
		relabel("player")
	elif code == KEY_M:
		ai.mode = AI.MODES[(AI.MODES.find(ai.mode) + 1) % AI.MODES.size()]
	elif code == KEY_R:
		reset_duel()
	elif code == KEY_T:
		for actor: Actor in [player_actor, soul_actor]:
			actor.show_trail = not actor.show_trail
	elif code == KEY_F3:
		for actor: Actor in [player_actor, soul_actor]:
			actor.show_debug = not actor.show_debug
	elif code == KEY_F4:
		Engine.time_scale = 0.3 if Engine.time_scale > 0.5 else 1.0
	elif code == KEY_H:
		hud.help_label.visible = not hud.help_label.visible

func select_recipe(side: String, index: int) -> void:
	loadout[side].recipe = index
	loadout[side].seed = -1
	loadout[side].seed_index = 0
	loadout[side].label = ""
	_equip(side)
	reset_duel()

func next_seed(side: String, fresh: bool) -> void:
	if fresh:
		# A brand-new instance: the only unpredictable seed in the lab, shown on the HUD.
		loadout[side].seed = _fresh_rng.randi_range(10000, 99999)
	else:
		loadout[side].seed = -1
		loadout[side].seed_index += 1
	_equip(side)
	reset_duel()

func toggle_marrow(side: String) -> void:
	loadout[side].marrow = not loadout[side].marrow
	_equip(side)
	reset_duel()

## Gives the player's object another recipe's display label. Structure and therefore
## every capability stay identical (same fingerprint, same solver result).
func relabel(side: String) -> void:
	_label_cycle += 1
	var recipes: Array = Gen.data().recipes
	loadout[side].label = str(recipes[(loadout[side].recipe + _label_cycle) % recipes.size()].label)
	_equip(side)
	var f: AdaptiveFighter = player if side == "player" else soul
	f.log_event("relabelled", loadout[side].label)

func _build_arena() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.11, 0.13)
	env.fog_density = 0.035
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(0.85, 0.88, 1.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	floor.mesh = plane
	var floor_mat: StandardMaterial3D = MaterialLibrary.get_material("stone_floor").duplicate()
	floor_mat.uv1_scale = Vector3(5.0, 5.0, 1.0)
	floor.material_override = floor_mat
	add_child(floor)
	var wall: StandardMaterial3D = MaterialLibrary.get_material("stone_wall")
	for i in range(8):
		var angle := TAU * i / 8.0
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 3.2, 0.7)
		pillar.mesh = box
		pillar.material_override = wall
		pillar.position = Vector3(cos(angle) * 6.5, 1.6, sin(angle) * 6.5)
		add_child(pillar)
		if i % 2 == 0:
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.62, 0.3)
			fire.light_energy = 1.6
			fire.omni_range = 6.0
			fire.position = Vector3(cos(angle) * 5.9, 2.2, sin(angle) * 5.9)
			add_child(fire)
