extends SceneTree
## Rendered evidence for the Adaptive Combat Lab (scenes/adaptive_combat_lab.tscn).
## The lab's own rules and presentation run unchanged; this script only scripts the
## player's intent, pins the camera and steps the rules by hand at 60 Hz.
## Sets:
##   compare  the SAME input sequence (light ×3, pause, heavy, light → heavy finisher)
##            on each imported Research Lab object, from the same side camera, with
##            the soul as a passive target → one frame sequence per object (the runner
##            encodes MP4s and a side-by-side grid video);
##   poses    key-pose stills (windup / contact / recovery of each chain step and the
##            heavy) per object, for contact sheets;
##   gameplay default HUD + orbit camera + lock-on in an AI duel; the same with every
##            debug layer on; the graft's regeneration; the heavy-miss diagnostic view.
## Run (needs a display; the runner uses xvfb-run):
##   godot --path . --script res://scripts/qa/adaptive_lab_capture.gd -- --evidence-dir=<dir> [--set=compare|poses|gameplay|all]

const AI = preload("res://scripts/adaptive_lab/adaptive_ai.gd")
const DT := 1.0 / 60.0
## Same inputs for every object (frame counts at 60 Hz).
const SEQUENCE := [["light", 1], ["idle", 15], ["light", 1], ["idle", 15], ["light", 1], ["idle", 70],
	["heavy", 1], ["idle", 95], ["light", 1], ["idle", 16], ["heavy", 1], ["idle", 90]]

var lab: Node
var output := "res://artifacts/adaptive-lab-capture"
var which := "all"
var written: Array[String] = []
var script_queue: Array = []
var manifest := {}

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
	if which in ["compare", "all"]:
		await compare()
	if which in ["poses", "all"]:
		await poses()
	if which in ["gameplay", "all"]:
		await gameplay()
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
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
			intent[head[0]] = true
		"guard":
			intent.guard = true
		"move":
			intent.move = head[2]
	if int(head[1]) <= 0:
		script_queue.pop_front()
	return intent

func queue(entries: Array) -> void:
	script_queue.clear()
	for e: Array in entries:
		script_queue.append([e[0], e[1], e[2] if e.size() > 2 else Vector3.ZERO])

func setup(player_lab: int, soul_lab: int, graft := false) -> void:
	lab.loadout.player.source = "lab"
	lab.loadout.player.lab = player_lab
	lab.loadout.player.graft = graft
	lab.loadout.player.label = ""
	lab.loadout.soul.source = "lab"
	lab.loadout.soul.lab = soul_lab
	lab._equip("player")
	lab._equip("soul")
	lab.reset_duel()

func side_camera(distance := 3.4) -> void:
	var p: Vector3 = lab.player.position
	lab.fixed_camera = {"position": p + Vector3(distance, 1.45, -0.85), "target": p + Vector3(0.0, 1.0, -0.85)}

func tick(frames: int, capture_dir := "", every := 1) -> void:
	for i in range(frames):
		lab.step(DT)
		await process_frame
		if capture_dir != "" and i % every == 0:
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

func object_name(index: int) -> String:
	return (lab.lab_paths()[index] as String).get_file().get_basename()

func _sequence_frames() -> int:
	var n := 0
	for e: Array in SEQUENCE:
		n += int(e[1])
	return n

# --- Same-input comparison ---------------------------------------------------------

func compare() -> void:
	var count: int = lab.lab_paths().size()
	for i in range(count):
		setup(i, 4)
		lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.2)
		lab.soul.yaw = 0.0
		for actor: Node in [lab.player_actor, lab.soul_actor]:
			actor.show_trail = true
		side_camera()
		lab.hud.visible = false
		queue(SEQUENCE)
		var name := object_name(i)
		lab.player.events.clear()
		await tick(_sequence_frames() + 20, output.path_join("clip_compare_" + name))
		var attacks: Array = []
		for e: Dictionary in lab.player.events:
			if e.kind == "attack":
				attacks.append("%s:%s" % [e.detail.input, e.detail.archetype])
			elif e.kind in ["contact", "whiff"]:
				attacks.append(e.kind if e.kind == "whiff" else "contact:" + str(e.detail.outcome))
		manifest["compare_" + name] = {"object": lab.lab_paths()[i], "sequence": attacks, "frames": _frames.get(output.path_join("clip_compare_" + name), 0) + 1}
	lab.hud.visible = true
	lab.fixed_camera = {}

# --- Key poses ------------------------------------------------------------------------

## Advances a fresh attack to rule time t (rules only; the soul far away).
func hold_attack(kind: String, index: int, t: float) -> bool:
	lab.player.reset_state()
	if not lab.player._start_attack(kind, index, lab.soul.position):
		return false
	while lab.player.state_time + DT <= t:
		lab.player.step({}, lab.soul.position, DT)
	return lab.player.state == "attack"

func poses() -> void:
	lab.hud.visible = false
	for i in range(lab.lab_paths().size()):
		var name := object_name(i)
		setup(i, 4)
		lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -2.0)
		side_camera()
		lab.player.reset_state()
		await still("%s_00_ready" % name)
		var steps: Array = []
		for k in range((lab.player.caps.light as Array).size()):
			steps.append(["light", k, lab.player.caps.light[k]])
		if lab.player.caps.heavy != null:
			steps.append(["heavy", -1, lab.player.caps.heavy])
		for s: Array in steps:
			var act: Dictionary = s[2]
			var w: float = act.windup
			var a: float = act.active
			for entry: Array in [["1windup", w * 0.97], ["2contact", w + a * 0.5], ["3recovery", w + a + float(act.recovery) * 0.35]]:
				if hold_attack(s[0], s[1], entry[1]):
					await still("%s_%s%d_%s_%s" % [name, s[0], s[1] + 1, act.archetype, entry[0]])
		if lab.player.caps.guard != null:
			lab.player.reset_state()
			for k in range(30):
				lab.player.step({"guard": true}, lab.soul.position, DT)
			await still("%s_9_guard_%s" % [name, lab.player.caps.guard.kind])
	lab.hud.visible = true
	lab.fixed_camera = {}

# --- Gameplay views ----------------------------------------------------------------

func gameplay() -> void:
	# Default HUD, orbit camera locked on, an AI-versus-AI duel (same rules both sides).
	setup(1, 4)
	lab.fixed_camera = {}
	lab.orbit.locked = true
	lab.ai.mode = "aggressive"
	var mirror := AI.new(4242)
	lab.player_driver = func(l: Node) -> Dictionary: return mirror.intent(l.player, l.soul, DT)
	await tick(420, output.path_join("clip_gameplay_default_hud"), 1)
	# The same duel moment with every debug layer on.
	lab.hud.toggle("stats")
	lab.hud.toggle("log")
	lab.hud.toggle("help")
	for actor: Node in [lab.player_actor, lab.soul_actor]:
		actor.show_debug = true
		actor.show_paths = true
	await tick(180, output.path_join("clip_gameplay_debug_layers"), 1)
	lab.hud.toggle("stats")
	lab.hud.toggle("log")
	lab.hud.toggle("help")
	for actor: Node in [lab.player_actor, lab.soul_actor]:
		actor.show_debug = false
		actor.show_paths = false
	# Free orbit, unlocked: the camera circles while the fighters stand.
	lab.player_driver = func(_l: Node) -> Dictionary: return _next_intent()
	lab.ai.mode = "passive"
	setup(0, 2)
	lab.orbit.locked = false
	for k in range(150):
		lab.orbit.orbit(Vector2(9.0, 0.6 if k < 75 else -0.6))
		if k == 60:
			lab.orbit.zoom(-3.0)
		if k == 110:
			lab.orbit.zoom(4.0)
		await tick(1, output.path_join("clip_camera_orbit_zoom"), 1)
	# Marrow graft: hands kept, regeneration after a hit (green glow), more damage taken.
	setup(2, 1, true)
	lab.orbit.locked = true
	lab.player.hp = 55.0
	lab.player.since_hurt = 0.0
	await tick(200, output.path_join("clip_graft_regeneration"), 2)
	# Heavy-miss diagnostic view: close-range heavy with grip/contact overlay and the
	# planned contact path, slow (every frame), side camera.
	setup(1, 4)
	lab.soul.position = lab.player.position + Vector3(0.0, 0.0, -1.15)
	side_camera(3.0)
	for actor: Node in [lab.player_actor, lab.soul_actor]:
		actor.show_debug = true
		actor.show_paths = true
	lab.hud.visible = false
	queue([["heavy", 1], ["idle", 110]])
	await tick(110, output.path_join("clip_heavy_close_overlay"), 1)
	for actor: Node in [lab.player_actor, lab.soul_actor]:
		actor.show_debug = false
		actor.show_paths = false
	lab.hud.visible = true
	lab.fixed_camera = {}
