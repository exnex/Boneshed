extends SceneTree
## Rendered evidence for the Adaptive Combat Lab (scenes/adaptive_combat_lab.tscn):
## stills of every demonstration object in ready / light-contact / heavy-loaded /
## guard poses (with and without the grip/contact overlay), body-modification and
## label-swap pairs, and frame sequences for short clips. The lab's own rules and
## presentation run unchanged; the script only scripts the player's intent, pins
## the camera and steps the rules by hand at 60 Hz.
## Run (needs a display; the runner uses xvfb-run):
##   godot --path . --script res://scripts/qa/adaptive_lab_capture.gd -- --evidence-dir=<dir> [--set=stills|clips|all]

const Gen = preload("res://scripts/adaptive_lab/object_generator.gd")
const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const DT := 1.0 / 60.0

var lab: Node
var output := "res://artifacts/adaptive-lab-capture"
var which := "all"
var written: Array[String] = []
var script_queue: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		elif arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	lab = load("res://scenes/adaptive_combat_lab.tscn").instantiate()
	root.add_child.call_deferred(lab)
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	lab.paused = true
	lab.ai.mode = "passive"
	lab.player_driver = func(_l: Node) -> Dictionary: return _next_intent()
	if which in ["stills", "all"]:
		await stills()
	if which in ["clips", "all"]:
		await clips()
	print(JSON.stringify({"suite": "adaptive_lab_capture", "summary": true, "failed": 0, "files": written.size(),
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()}))
	quit(0)

# --- Scripted intent ------------------------------------------------------------------

func _next_intent() -> Dictionary:
	var intent := {"move": Vector3.ZERO, "light": false, "heavy": false, "guard": false, "dodge": false}
	if script_queue.is_empty():
		return intent
	var head: Array = script_queue[0]
	head[1] = int(head[1]) - 1
	match str(head[0]):
		"light", "heavy", "dodge":
			intent[head[0]] = head[1] == int(head[2]) - 1
		"guard":
			intent.guard = true
		"move":
			intent.move = head[3]
	if int(head[1]) <= 0:
		script_queue.pop_front()
	return intent

## Queue entries: [kind, frames] — a press lasts one tick then idles for the rest.
func queue(entries: Array) -> void:
	script_queue.clear()
	for e: Array in entries:
		script_queue.append([e[0], e[1], e[1], e[2] if e.size() > 2 else Vector3.ZERO])

func setup(player_recipe: int, soul_recipe: int, player_marrow := false, label := "") -> void:
	lab.loadout.player.recipe = player_recipe
	lab.loadout.player.marrow = player_marrow
	lab.loadout.player.label = label
	lab.loadout.player.seed = -1
	lab.loadout.player.seed_index = 0
	lab.loadout.soul.recipe = soul_recipe
	lab._equip("player")
	lab._equip("soul")
	lab.reset_duel()

func side_camera(distance := 3.0) -> void:
	var p: Vector3 = lab.player.position
	lab.fixed_camera = {"position": p + Vector3(distance, 1.35, -0.75), "target": p + Vector3(0.0, 1.05, -0.75)}

func three_quarter_camera() -> void:
	var p: Vector3 = lab.player.position
	lab.fixed_camera = {"position": p + Vector3(2.6, 1.9, 1.9), "target": p + Vector3(-0.2, 1.0, -1.1)}

func tick(frames: int, capture_dir := "") -> void:
	for i in range(frames):
		lab.step(DT)
		await process_frame
		if capture_dir != "":
			_save(capture_dir.path_join("frame_%04d.png" % _frame_index(capture_dir)))

var _frames := {}
func _frame_index(dir: String) -> int:
	_frames[dir] = int(_frames.get(dir, -1)) + 1
	return _frames[dir]

func _save(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	root.get_viewport().get_texture().get_image().save_png(path)
	written.append(path)

func still(name: String) -> void:
	await process_frame
	await process_frame
	_save(output.path_join("stills").path_join(name + ".png"))

## Advances the player's current attack to rule time t (rules only; soul idle and far).
func hold_attack(kind: String, index: int, t: float) -> bool:
	lab.player.reset_state()
	if not lab.player._start_attack(kind, index):
		return false
	while lab.player.state_time + DT <= t:
		lab.player.step({}, lab.soul.position, DT)
	return lab.player.state == "attack"

# --- Stills ------------------------------------------------------------------------

func stills() -> void:
	var ids := Gen.recipe_ids()
	for r in range(ids.size()):
		var name: String = ids[r].trim_prefix("demo.")
		setup(r, 0)
		# Overview with the HUD: what the solver derived and why moves are missing.
		lab.fixed_camera = {}
		lab.hud.visible = true
		await still("%s_hud" % name)
		lab.hud.visible = false
		lab.soul.position = Vector3(0.0, 0.0, -6.0)
		side_camera()
		for debug: bool in [false, true]:
			for actor: Node in [lab.player_actor, lab.soul_actor]:
				actor.show_debug = debug
			var suffix := "_overlay" if debug else ""
			lab.player.reset_state()
			await still("%s_ready%s" % [name, suffix])
			if not (lab.player.caps.light as Array).is_empty():
				var act: Dictionary = lab.player.caps.light[0]
				if hold_attack("light", 0, float(act.windup) + float(act.active) * 0.5):
					await still("%s_light_contact%s" % [name, suffix])
			if lab.player.caps.heavy != null:
				if hold_attack("heavy", 0, float(lab.player.caps.heavy.windup) * 0.98):
					await still("%s_heavy_loaded%s" % [name, suffix])
			if lab.player.caps.guard != null:
				lab.player.reset_state()
				for i in range(30):
					lab.player.step({"guard": true}, lab.soul.position, DT)
				await still("%s_guard%s" % [name, suffix])
		for actor: Node in [lab.player_actor, lab.soul_actor]:
			actor.show_debug = false
	# Body modification: the same objects for a body whose left arm is a handless Marrow Arm.
	for r: int in [0, 2, 4]:
		var name: String = ids[r].trim_prefix("demo.")
		setup(r, 0, true)
		lab.soul.position = Vector3(0.0, 0.0, -6.0)
		side_camera()
		lab.player.reset_state()
		await still("%s_marrow_ready" % name)
		if not (lab.player.caps.light as Array).is_empty():
			var act: Dictionary = lab.player.caps.light[0]
			if hold_attack("light", 0, float(act.windup) + float(act.active) * 0.5):
				await still("%s_marrow_light_contact" % name)
	# Label swap: the umbrella-like structure under another recipe's label, same pose and rules.
	lab.hud.visible = true
	for label: String in ["", "Bone spear of the drowned"]:
		setup(1, 0, false, label)
		lab.soul.position = Vector3(0.0, 0.0, -6.0)
		side_camera()
		var act: Dictionary = lab.player.caps.light[0]
		hold_attack("light", 0, float(act.windup) + float(act.active) * 0.5)
		await still("label_swap_%s" % ("original" if label == "" else "relabelled"))
	lab.fixed_camera = {}

# --- Clips -------------------------------------------------------------------------

func clips() -> void:
	var ids := Gen.recipe_ids()
	lab.hud.visible = true
	# Same inputs, every object: light ×3 (chain), heavy, held guard.
	for r in range(ids.size()):
		var name: String = ids[r].trim_prefix("demo.")
		setup(r, 0)
		lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.3)
		three_quarter_camera()
		queue([["light", 14], ["light", 14], ["light", 60], ["heavy", 100], ["guard", 50], ["move", 30]])
		await tick(270, output.path_join("clip_inputs_" + name))
	# Body modification: the pole with two hands, then with the Marrow Arm.
	for marrow: bool in [false, true]:
		setup(2, 0, marrow)
		lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.3)
		three_quarter_camera()
		queue([["light", 14], ["light", 14], ["light", 60], ["heavy", 100]])
		await tick(200, output.path_join("clip_body_mod_%s" % ("marrow_arm" if marrow else "two_hands")))
	# Defence: the soul attacks; the umbrella-holder deploys its canopy (fresh press = deflect).
	setup(1, 0)
	lab.ai.mode = "aggressive"
	lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.0)
	three_quarter_camera()
	queue([["guard", 240]])
	await tick(240, output.path_join("clip_umbrella_guard"))
	# A short AI-versus-AI duel (both sides use the same rules and AI), follow camera.
	setup(2, 3)
	lab.fixed_camera = {}
	lab.ai.mode = "aggressive"
	var mirror := AI.new(4242)
	lab.player_driver = func(l: Node) -> Dictionary: return mirror.intent(l.player, l.soul, DT)
	await tick(480, output.path_join("clip_duel"))
	lab.player_driver = func(_l: Node) -> Dictionary: return _next_intent()
	lab.ai.mode = "passive"
