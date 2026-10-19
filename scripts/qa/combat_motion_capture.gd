extends SceneTree
## Close-up, HUD-free renders of attack timelines and hit reactions from two fixed
## cameras: over the defender's shoulder (what the player reads) and side-on (arcs,
## weight and footwork). Only uses fields that exist on main, so the same script
## gives like-for-like before/after evidence. Isolated rule stepping; not a playtest.
const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var output := "res://artifacts/combat-motion"
var scene := "courtyard"
var cameras: Dictionary = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--scene="): scene = arg.trim_prefix("--scene=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = load("res://scenes/%s.tscn" % scene).instantiate()
	root.add_child(arena)
	call_deferred("run")

func capture(label: String) -> void:
	for view: String in cameras:
		cameras[view].current = true
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join(view).path_join(label.get_base_dir())))
		if root.get_texture().get_image().save_png(output.path_join(view).path_join(label + ".png")) != OK:
			quit(1)

func step(actors: Array, seconds: float) -> void:
	for actor: Fighter in actors:
		actor.sync_visual(seconds)
	for actor: Fighter in actors:
		actor.combat.tick(seconds)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	e.enabled = false
	p.input_enabled = false
	await physics_frame
	await process_frame
	arena.set_physics_process(false)
	p.set_physics_process(false)
	e.set_physics_process(false)
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	p.visual.rotation.y = 0.0
	e.visual.rotation.y = PI
	p.debug_hitboxes = false
	e.debug_hitboxes = false
	arena.hud.hide()
	var shoulder := Camera3D.new()
	arena.add_child(shoulder)
	shoulder.fov = 50.0
	shoulder.position = Vector3(1.1, 2.15, 5.0)
	shoulder.look_at(Vector3(0.0, 1.25, 0.3))
	var side := Camera3D.new()
	arena.add_child(side)
	side.fov = 50.0
	side.position = Vector3(-4.6, 1.55, 1.0)
	side.look_at(Vector3(0.0, 1.15, 1.0))
	cameras = {"shoulder": shoulder, "side": side}
	var bindings := ["light", "heavy"]
	if not e.combat.signature.is_empty(): bindings.append("special")
	for binding: String in bindings:
		p.combat.reset()
		e.combat.reset()
		p.flash_time = 0.0
		e.flash_time = 0.0
		p.reaction_time = 0.0
		e.reaction_time = 0.0
		if binding == "special": e.combat.attack_special()
		else: e.combat.attack(binding == "heavy")
		var count := ceili((e.combat.windup_duration() + e.combat.active_duration + e.combat.recovery_duration) * 60.0)
		var stages: Dictionary = {}
		for tick in range(count + 2):
			step([p, e], 1.0 / 60.0)
			var stage := e.combat.attack_stage()
			if not stages.has(stage) and stage != "none" and (stage != "early" or tick > 6):
				await capture(binding + "/stage_" + stage)
				stages[stage] = true
			if tick % 2 == 0: await capture(binding + "/frame_%03d" % (tick / 2))
	for defense: String in ["deflect", "guard", "hit", "break"]:
		p.combat.reset()
		e.combat.reset()
		p.reaction_time = 0.0
		e.reaction_time = 0.0
		p.flash_time = 0.0
		e.flash_time = 0.0
		if defense == "guard":
			p.combat.set_guard(true)
			p.combat.tick(0.3)
		if defense == "break": p.combat.posture = p.combat.max_posture - 1.0
		e.combat.attack()
		# Arrive at contact through the real timeline so the pre-contact pose is live.
		while e.combat.phase == Rules.Phase.WINDUP:
			# A fresh guard press inside the deflection window, as a player would time it.
			if defense == "deflect" and e.combat.remaining <= 0.06 and not p.combat.guarding: p.combat.set_guard(true)
			step([p, e], 1.0 / 60.0)
		var result := e.resolve_attack()
		if result != {"deflect": Rules.DEFLECTED, "guard": Rules.GUARD, "hit": Rules.HIT, "break": Rules.HIT}[defense]: quit(1); return
		for tick in range(30):
			if tick in [0, 2, 4, 6, 9, 13, 18, 24, 29]: await capture("react_%s/frame_%02d" % [defense, tick])
			step([p, e], 1.0 / 60.0)
	print(JSON.stringify({"capture_complete": true, "scene": scene, "engine": Engine.get_version_info().string}))
	arena.free()
	quit()
