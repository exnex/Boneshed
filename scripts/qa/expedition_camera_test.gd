extends SceneTree
## Controlled physics/framing fixture in the generated world. Unlike the legal
## input playthrough, this deliberately positions the player and suspends enemy AI.
const Shell = preload("res://scenes/first_expedition.tscn")
const Builder = preload("res://scripts/expedition/world_builder.gd")
var failed := 0
var passed := 0
var output := "res://artifacts/expedition-camera"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func frame(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func check(value: bool, label: String) -> void:
	failed += int(not value)
	passed += int(value)
	print(JSON.stringify({"check": label, "passed": value}))

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)

func run() -> void:
	var shell := Shell.instantiate()
	root.add_child(shell)
	shell.start_expedition(["drowned", "hollow", "cathedral"], 1001)
	var arena: Node3D = shell.expedition
	var player: Fighter = arena.player
	var center := Builder.point(arena.layout.arena)
	player.input_enabled = false
	player.preferred_camera_distance = 7.5
	player.spring.spring_length = 7.5
	player.reset_at(center + Vector3.UP * 0.02)
	await frame()
	arena.enemy.enabled = false
	check(arena.encounter_started, "camera_fixture_activates_arena")
	check(is_equal_approx(player.spring.get_hit_length(), 7.5), "open_arena_allows_selected_distance")
	await capture("09_open_arena_camera")
	player.reset_at(center + Vector3(0, 0.02, 11))
	await frame()
	check(player.spring.get_hit_length() > 0.1 and player.spring.get_hit_length() < 5.0, "portcullis_retracts_camera")
	check(player.preferred_camera_distance == 7.5, "gate_does_not_rewrite_selection")
	await capture("10_portcullis_camera")
	arena.world_builder.set_arena_sealed(false)
	await frame()
	check(is_equal_approx(player.spring.get_hit_length(), 7.5), "open_gate_restores_selected_distance")
	player.reset_at(center + Vector3(10, 0.02, 0))
	player.yaw = PI * 0.5
	await frame()
	check(is_equal_approx(player.spring.get_hit_length(), 7.5), "low_parapet_allows_clear_overlook")
	player.reset_at(center + Vector3(9, 0.02, 7.2))
	player.yaw = PI * 0.5
	await frame()
	check(player.spring.get_hit_length() > 0.1 and player.spring.get_hit_length() < 5.0, "generated_column_retracts_camera")
	await capture("11_column_camera")
	player.preferred_camera_distance = 5.1
	arena.reset_encounter()
	await frame()
	arena.enemy.enabled = false
	check(player.preferred_camera_distance == 5.1, "world_retry_retains_selected_zoom")
	check(player.position.distance_to(center + Vector3(0, 0, 4)) < 0.1, "world_retry_returns_to_clear_arena_spawn")
	var result := {"summary": true, "passed": passed, "failed": failed, "rendered": DisplayServer.get_name() != "headless"}
	FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify(result))
	# Return while a valid contact is queued: the old scene must never query physics
	# or award salvage after the shell removes it from the tree.
	player.reset_at(arena.enemy.position + Vector3(0, 0, 1.8))
	player.combat.attack()
	player.combat.tick(player.combat.attack_windup + 0.001)
	arena._resolve_duel.call_deferred()
	shell.return_to_selection()
	await frame(1)
	shell.free()
	quit(1 if failed else 0)
