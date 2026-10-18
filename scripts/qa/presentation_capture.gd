extends SceneTree
## Like-for-like, HUD-free curated pose captures. Runs on main and this branch.
## Isolated state stepping, not a claim of human play or real AI combat.
const Playable = preload("res://scenes/salvage_courtyard.tscn")
const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var observer: Camera3D
var output := "res://artifacts/presentation-capture"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = Playable.instantiate()
	root.add_child(arena)
	call_deferred("run")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if error != OK: quit(1)

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
	observer = Camera3D.new()
	arena.add_child(observer)
	observer.position = Vector3(4.2, 2.9, 4.5)
	observer.look_at(Vector3(0.0, 1.1, 0.8))
	observer.current = true
	for binding: String in ["light", "heavy", "special"]:
		p.combat.reset()
		e.combat.reset()
		p.flash_time = 0.0
		e.flash_time = 0.0
		if binding == "special": e.combat.attack_special()
		else: e.combat.attack(binding == "heavy")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join(binding)))
		var count := ceili((e.combat.windup_duration() + e.combat.active_duration + e.combat.recovery_duration) * 60.0)
		var stages: Dictionary = {}
		for tick in range(count + 1):
			e.sync_visual(1.0 / 60.0)
			p.sync_visual(1.0 / 60.0)
			var stage := e.combat.attack_stage()
			if not stages.has(stage) and stage != "none" and (stage != "early" or tick > 6):
				await capture(binding + "/" + stage)
				stages[stage] = true
			if tick % 2 == 0: await capture(binding + "/frame_%03d" % (tick / 2))
			e.combat.tick(1.0 / 60.0)
	for defense: String in ["deflect", "hit", "break"]:
		p.combat.reset()
		e.combat.reset()
		if defense == "deflect": p.combat.set_guard(true)
		if defense == "break": p.combat.posture = p.combat.max_posture - 1.0
		e.combat.attack()
		e.combat.tick(e.combat.windup_duration() + 0.001)
		e.resolve_attack()
		for tick in range(24):
			p.sync_visual(1.0 / 60.0)
			e.sync_visual(1.0 / 60.0)
			if tick == 0: await capture(defense)
			p.combat.tick(1.0 / 60.0)
			e.combat.tick(1.0 / 60.0)
	print(JSON.stringify({"capture_complete": true, "engine": Engine.get_version_info().string}))
	arena.free()
	quit()
