extends Node3D
## Adaptive Combat Lab — isolated, separately selectable experiment
## (scenes/adaptive_combat_lab.tscn). One player and one corrupted soul fight with
## physically structured objects. The primary objects are the Research Lab's own
## generated exports (`lab.boneshed.object_export.v1`, vendored and verified by
## lab_import.gd); the game's earlier GDScript generator stays selectable as a
## comparison/fallback source. The same input produces whatever the shared affordance
## solver derives from each object's structure and each fighter's body.
## Nothing here is read by the default game, the expedition scenes or the other labs.
##
## Order each physics tick: intents (input / AI) → both fighters step → separation →
## contact resolution both ways. Presentation, camera and HUD sync in _process.

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const Bodies = preload("res://scripts/adaptive_lab/body_plans.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const AdaptiveFighter = preload("res://scripts/adaptive_lab/adaptive_fighter.gd")
const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const Actor = preload("res://scripts/adaptive_lab/adaptive_actor.gd")
const LabInput = preload("res://scripts/adaptive_lab/adaptive_input.gd")
const Hud = preload("res://scripts/adaptive_lab/adaptive_hud.gd")
const OrbitCamera = preload("res://scripts/adaptive_lab/adaptive_camera.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const AI_SEED := 7301
const START_DISTANCE := 3.2
const MOD := "marrow_graft"

var player: AdaptiveFighter
var soul: AdaptiveFighter
var ai: AI
var player_actor: Actor
var soul_actor: Actor
var orbit: OrbitCamera
var camera: Camera3D
var hud: Hud
## Per side: object source ("lab" import index into the verified bundle, or "v0"
## generator recipe/seed for comparison), name override, body modification.
var loadout := {
	"player": {"source": "lab", "lab": 1, "recipe": 0, "seed_index": 0, "seed": -1, "label": "", "graft": false, "body": "pilgrim"},
	"soul": {"source": "lab", "lab": 4, "recipe": 0, "seed_index": 0, "seed": -1, "label": "", "graft": false, "body": "corrupted"},
}
## When valid, replaces keyboard/mouse for the player / the AI for the soul:
## Callable(lab) -> intent (tests and capture scripts).
var player_driver: Callable
var soul_driver: Callable
var paused := false
## Capture scripts may pin the camera: {"position": Vector3, "target": Vector3}.
var fixed_camera: Dictionary = {}
var _solve_cache := {}
var _fresh_rng := RandomNumberGenerator.new()
var _label_cycle := 0
var _bundle: Dictionary

func _ready() -> void:
	LabInput.install()
	_fresh_rng.randomize()
	MaterialLibrary.set_texture_size(256, 512)
	_bundle = Imp.load_bundle()
	if not _bundle.ok or Imp.accepted_paths().is_empty():
		push_error("Adaptive lab: Lab export bundle failed verification: %s" % str(_bundle.errors))
		for side: String in ["player", "soul"]:
			loadout[side].source = "v0"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			_select_from_arg("player", arg.trim_prefix("--player="))
		elif arg.begins_with("--soul="):
			_select_from_arg("soul", arg.trim_prefix("--soul="))
		elif arg == "--player-graft":
			loadout.player.graft = true
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
	orbit = OrbitCamera.new()
	orbit.name = "OrbitCamera"
	add_child(orbit)
	camera = orbit.camera
	hud = Hud.new()
	add_child(hud)
	reset_duel()
	print("BONESHED_ADAPTIVE_LAB_IMPORT accepted=%d rejected=%d manifest=%s" % [Imp.accepted_paths().size(), _bundle.rejected.size(),
		str(_bundle.manifest_sha256).substr(0, 12)])
	print("BONESHED_ADAPTIVE_READY")

## Command-line object choice: a bundle path ("objects/shovel.json") or "v0:<recipe>".
func _select_from_arg(side: String, value: String) -> void:
	if value.begins_with("v0:"):
		loadout[side].source = "v0"
		loadout[side].recipe = maxi(0, Gen.recipe_ids().find(value.trim_prefix("v0:")))
	else:
		var index := Imp.accepted_paths().find(value)
		if index >= 0:
			loadout[side].source = "lab"
			loadout[side].lab = index

func lab_paths() -> Array[String]:
	return Imp.accepted_paths()

func descriptor_for(side: String) -> Dictionary:
	var l: Dictionary = loadout[side]
	if l.source == "lab":
		var obj: Dictionary = (_bundle.objects[lab_paths()[int(l.lab) % lab_paths().size()]] as Dictionary).duplicate(true)
		if l.label != "":
			obj.label = l.label
			obj.original.descriptor.name = l.label
		return obj
	var id: String = Gen.recipe_ids()[l.recipe]
	var seed: int = l.seed if int(l.seed) >= 0 else int(Gen.recipe(id).seeds[int(l.seed_index) % (Gen.recipe(id).seeds as Array).size()])
	return Gen.generate(id, seed, l.label)

func body_for(side: String) -> Dictionary:
	var l: Dictionary = loadout[side]
	return Bodies.build(l.body, [MOD] if l.graft else [])

## Solves through a cache keyed by structure + body; renamed objects hit the same
## entry, which is exactly the claim the name-swap test verifies uncached.
func _equip(side: String) -> void:
	var descriptor := descriptor_for(side)
	var body := body_for(side)
	var key := "%s|%s|%s" % [Solver.structure_hash(descriptor), body.id, ",".join(body.modifications)]
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
	if orbit != null:
		orbit.reset(0.0)
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
	var player_intent: Dictionary
	if player_driver.is_valid():
		player_intent = player_driver.call(self)
	else:
		player_intent = LabInput.read(orbit.move_basis() if orbit != null else Basis.IDENTITY)
		player_intent.face = LabInput.facing(player_intent, orbit.locked if orbit != null else true, player.position, player.forward(), soul.position)
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
		camera.global_position = fixed_camera.position
		camera.look_at(fixed_camera.target, Vector3.UP)
		return
	# The spring arm owns the camera's placement; clear any pinned-view orientation.
	camera.rotation = Vector3.ZERO
	orbit.update(delta, player.position, soul.position, soul.state != "dead")

func _update_hud() -> void:
	hud.update_fighters(player, soul, "Corrupted soul · %s%s" % [ai.mode, " · graft" if loadout.soul.graft else ""])
	var lines: Array[String] = []
	var merged: Array = player.events + soul.events
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	for e: Dictionary in merged.slice(maxi(0, merged.size() - 12)):
		lines.append(_event_text(e))
	hud.set_log(lines)
	var reticle: Variant = null
	if orbit.locked and fixed_camera.is_empty():
		var p := soul.position + Vector3(0.0, 1.25, 0.0)
		if not camera.is_position_behind(p):
			reticle = camera.unproject_position(p)
	hud.set_reticle(reticle)
	if player.state == "dead" or soul.state == "dead":
		hud.set_banner(("The soul is released." if soul.state == "dead" else "You fall.") + "  R to reset")

static func _event_text(e: Dictionary) -> String:
	var who: String = "you" if e.who == "player" else "soul"
	match str(e.kind):
		"attack":
			return "%.1fs %s: %s → %s (%s via %s, step %+.2f m)" % [e.t, who, e.detail.input, e.detail.archetype, e.detail.channel, e.detail.feature, e.detail.spacing]
		"contact":
			return "%.1fs %s: %s with %s" % [e.t, who, e.detail.outcome, e.detail.feature]
		"whiff":
			return "%.1fs %s: whiff (%s, closest %.2f m)" % [e.t, who, e.detail.action, e.detail.closest]
		"light_unsupported", "heavy_unsupported", "guard_unsupported":
			return "%.1fs %s: %s — %s" % [e.t, who, e.kind, str(e.detail).substr(0, 90)]
	return "%.1fs %s: %s" % [e.t, who, e.kind]

func _unhandled_input(event: InputEvent) -> void:
	if orbit != null and orbit.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and fixed_camera.is_empty() \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("alab_lock"):
		orbit.toggle_lock()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.physical_keycode
	if code >= KEY_1 and code <= KEY_6:
		select_lab("soul" if key.shift_pressed else "player", code - KEY_1)
	elif code == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif code == KEY_O:
		toggle_source("player")
	elif code == KEY_V:
		next_seed("player", key.shift_pressed)
	elif code == KEY_B:
		toggle_graft("player")
	elif code == KEY_N:
		toggle_graft("soul")
	elif code == KEY_G:
		relabel("player")
	elif code == KEY_M:
		ai.mode = AI.MODES[(AI.MODES.find(ai.mode) + 1) % AI.MODES.size()]
	elif code == KEY_R:
		reset_duel()
	elif code == KEY_T:
		for actor: Actor in [player_actor, soul_actor]:
			actor.show_trail = not actor.show_trail
	elif code == KEY_F2:
		hud.toggle("stats")
	elif code == KEY_F3:
		for actor: Actor in [player_actor, soul_actor]:
			actor.show_debug = not actor.show_debug
	elif code == KEY_F4:
		Engine.time_scale = 0.3 if Engine.time_scale > 0.5 else 1.0
	elif code == KEY_F5:
		hud.toggle("log")
	elif code == KEY_F6:
		for actor: Actor in [player_actor, soul_actor]:
			actor.show_paths = not actor.show_paths
	elif code == KEY_H:
		hud.toggle("help")

## Lab-import object `index` (manifest order); in comparison mode, a v0 recipe.
func select_lab(side: String, index: int) -> void:
	if loadout[side].source == "v0":
		loadout[side].recipe = clampi(index, 0, Gen.recipe_ids().size() - 1)
		loadout[side].seed = -1
		loadout[side].seed_index = 0
	else:
		loadout[side].lab = clampi(index, 0, lab_paths().size() - 1)
	loadout[side].label = ""
	_equip(side)
	reset_duel()

func toggle_source(side: String) -> void:
	loadout[side].source = "v0" if loadout[side].source == "lab" else ("lab" if _bundle.ok else "v0")
	loadout[side].label = ""
	_equip(side)
	reset_duel()

func next_seed(side: String, fresh: bool) -> void:
	if loadout[side].source != "v0":
		return
	if fresh:
		# A brand-new comparison instance: the only unpredictable seed in the lab.
		loadout[side].seed = _fresh_rng.randi_range(10000, 99999)
	else:
		loadout[side].seed = -1
		loadout[side].seed_index += 1
	_equip(side)
	reset_duel()

func toggle_graft(side: String) -> void:
	loadout[side].graft = not loadout[side].graft
	_equip(side)
	reset_duel()

## Gives the player's object another display name. Structure and therefore every
## capability stay identical (same fingerprint, same solver result).
func relabel(side: String) -> void:
	_label_cycle += 1
	var names := ["Bone spear of the drowned", "Executioner's greataxe", "Tower shield", "Umbrella", "Shovel", "Rusted sword"]
	loadout[side].label = names[_label_cycle % names.size()]
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
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(16.0, 0.2, 16.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.1, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
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
		# Camera-only collision (the fighters never collide with the arena).
		var body := StaticBody3D.new()
		body.name = "PillarBody%d" % i
		var shape := CollisionShape3D.new()
		var collider := BoxShape3D.new()
		collider.size = box.size
		shape.shape = collider
		body.add_child(shape)
		body.position = pillar.position
		add_child(body)
		if i % 2 == 0:
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.62, 0.3)
			fire.light_energy = 1.6
			fire.omni_range = 6.0
			fire.position = Vector3(cos(angle) * 5.9, 2.2, sin(angle) * 5.9)
			add_child(fire)
