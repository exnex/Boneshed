extends "res://scripts/qa/marrow_playthrough.gd"
## Reuse the existing legal-input duel bot after walking the generated approach.
## No position, health, inventory, reward or AI writes in this end-to-end run.
const Shell = preload("res://scenes/first_expedition.tscn")
const Builder = preload("res://scripts/expedition/world_builder.gd")
var shell: Node

func _initialize() -> void:
	output = "res://artifacts/expedition-playthrough"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	shell = Shell.instantiate()
	root.add_child(shell)
	call_deferred("run")

func run() -> void:
	await frame()
	# Default words, replay seed entered through the shipped UI.
	shell.replay_check.button_pressed = true
	shell.seed_edit.text = "1001"
	shell._begin_selection()
	arena = shell.expedition
	await frame()
	await frame()
	await capture("00_arrival")
	var path: Array = arena.layout.path.duplicate(true)
	path[path.size() - 1][1] += 7.0
	for index in path.size():
		var target := Builder.point(path[index])
		var reached := false
		for i in range(1600):
			var offset: Vector3 = target - arena.player.position
			input("move_forward", offset.z < -0.25)
			input("move_back", offset.z > 0.25)
			input("move_left", offset.x < -0.25)
			input("move_right", offset.x > 0.25)
			await frame()
			if Vector2(offset.x, offset.z).length() < 0.5:
				reached = true
				break
		for action: String in ["move_forward", "move_back", "move_left", "move_right"]:
			input(action, false)
		check(reached and arena.player.position.y > -0.1, "walk_module_" + str(index))
		if not reached:
			quit(1)
			return
		if index == 2:
			await capture("00_reliquary")
	check(arena.encounter_started and arena.enemy.enabled, "walking_activates_existing_enemy")
	check(is_instance_valid(arena.world_builder.arena_gate), "walking_seals_arena")
	await super.run()

func capture(label: String) -> void:
	if label == "04_enemy_defeat" and not captures.has(label):
		check(not is_instance_valid(arena.world_builder.arena_gate), "victory_opens_return_route")
	await super.capture(label)
