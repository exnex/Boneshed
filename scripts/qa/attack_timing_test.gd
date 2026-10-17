extends SceneTree
## Sample authoritative rules and actual procedural weapon transforms at 60 Hz.
## In rendered mode the exact same samples produce a 30 fps release/contact sequence.

const Rules = preload("res://scripts/combat/combat_state.gd")
const Courtyard = preload("res://scenes/courtyard.tscn")
var arena: Node3D
var output := "res://artifacts/attack-timing"
var negative := false
var records: Array = []
var passed := 0
var failed := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg == "--negative=visual":
			negative = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = Courtyard.instantiate()
	root.add_child(arena)
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
	var record := {"check": label, "passed": condition}
	records.append(record)
	print(JSON.stringify(record))

func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(path + ".png")) == OK, "capture_" + path)

func run() -> void:
	var p: Fighter = arena.player
	var e: Fighter = arena.enemy
	e.enabled = false
	p.input_enabled = false
	p.position = Vector3(0.0, 0.02, 2.0)
	e.position = Vector3(0.0, 0.02, 0.0)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	for i in range(5):
		await physics_frame
		await process_frame
	# Freeze world stepping; sample rules at exact increments and query real hit geometry.
	# A held block consumes contact without truncating the enemy's follow-through.
	arena.set_physics_process(false)
	p.set_physics_process(false)
	e.set_physics_process(false)
	p.debug_hitboxes = false
	e.debug_hitboxes = false
	arena.hud.hide()
	for front in [true, false]:
		e.combat.reset()
		p.combat.reset()
		p.facing = Vector3.FORWARD if front else Vector3.BACK
		p.combat.set_guard(true)
		e.combat.attack()
		e.combat.tick(e.combat.attack_windup + 0.001)
		check(e.resolve_attack() == ("deflected" if front else "hit"), "world_guard_front_" + str(front))
	p.facing = Vector3.FORWARD
	for heavy_attack in [false, true]:
		e.combat.reset()
		p.combat.reset()
		p.combat.set_guard(true)
		p.combat.tick(0.3)
		p.flash_time = 0.0
		e.flash_time = 0.0
		e.combat.attack(heavy_attack)
		var kind := "heavy" if heavy_attack else "basic"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join(kind)))
		var duration: float = e.combat.heavy_windup if heavy_attack else e.combat.attack_windup
		var captured := {}
		var active_ticks := 0
		var frame_number := 0
		var samples: Array = []
		var release_positions: Array[Vector3] = []
		for tick in range(ceili((duration + e.combat.active_duration + 0.20) * 60.0)):
			var stage := e.combat.attack_stage()
			e._update_visual(0.0)
			p._update_visual(0.0)
			if negative and stage == "active":
				e.sword_pivot.rotation.y = PI
			var blade_tip: Vector3 = e.sword_pivot.to_global(Vector3(0.0, 0.0, -1.75))
			var forward_reach := (blade_tip - e.global_position).dot(e.facing)
			var result: String = e.resolve_attack()
			p.flash_time = 0.0
			p._update_visual(0.0)
			if stage in ["early", "committed", "release", "recovery"]:
				check(result == "invalid", kind + "_noncontact_tick_" + str(tick))
			if stage == "release":
				release_positions.append(blade_tip)
			if stage == "active":
				active_ticks += 1
				check(forward_reach >= e.attack_range - 0.4 and blade_tip.y > 1.0, kind + "_active_blade_in_hit_volume_" + str(active_ticks))
				if active_ticks == 1:
					check(result == "guard" and absf(forward_reach - e.attack_range) < 0.15, kind + "_first_contact_matches_extended_blade")
				else:
					check(result == "invalid", kind + "_swing_contact_consumed_" + str(active_ticks))
			var pose := {"tick": tick, "time": tick / 60.0, "stage": stage, "phase": e.combat.phase, "remaining": e.combat.remaining,
				"blade_tip": [blade_tip.x, blade_tip.y, blade_tip.z], "sword_rotation": [e.sword_pivot.rotation.x, e.sword_pivot.rotation.y, e.sword_pivot.rotation.z], "result": result}
			samples.append(pose)
			if not captured.has(stage) and (stage != "early" or tick >= 8):
				await capture(kind + "/" + stage)
				captured[stage] = true
			# Two physics ticks per image; includes late windup, release, active, recovery.
			if tick % 2 == 0 and tick / 60.0 >= duration - 0.30:
				await capture(kind + "/frame_%03d" % frame_number)
				frame_number += 1
			e.combat.tick(1.0 / 60.0)
		check(active_ticks >= 9 and active_ticks <= 10, kind + "_active_duration_unchanged")
		check(release_positions.size() >= 4 and release_positions[0].distance_to(release_positions[-1]) > 0.5, kind + "_visible_release_precedes_contact")
		check(captured.has_all(["early", "committed", "release", "active", "recovery"]), kind + "_five_distinct_stages")
		var file := FileAccess.open(output.path_join(kind + "/samples.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(samples, "\t") + "\n")
	var summary := {"summary": true, "passed": passed, "failed": failed, "engine": Engine.get_version_info().string, "rendered": DisplayServer.get_name() != "headless"}
	records.append(summary)
	print(JSON.stringify(summary))
	var file := FileAccess.open(output.path_join("timing.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t") + "\n")
	quit(1 if failed else 0)
