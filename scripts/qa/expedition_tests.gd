extends SceneTree
const Layout = preload("res://scripts/expedition/expedition_layout.gd")
const Blueprint = preload("res://scripts/worldgen/blueprint_generator.gd")
const Builder = preload("res://scripts/expedition/world_builder.gd")
const Shell = preload("res://scenes/first_expedition.tscn")
const ENVIRONMENT := 1
const ADDRESSES := [["drowned", "hollow", "cathedral"], ["frozen", "tempest", "towering"],
	["smoldering", "frozen", "ossuary"], ["hallowed", "gilded", "profane"],
	["thorned", "sunken", "forgotten"], ["barren", "lightless", "hollow"]]
const GRAMMAR_ADDRESSES := [["ashen", "silent", "sanctuary"], ["moonlit", "thorned", "garden"],
	["weeping", "forgotten", "requiem"], ["frozen", "gilded", "citadel"],
	["smoldering", "pallid", "necropolis"], ["veiled", "sunken", "dream"]]
var failed := 0
var passed := 0
var output := "res://artifacts/expedition-tests"
var rendered := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	rendered = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(value: bool, label: String) -> void:
	failed += int(not value)
	passed += int(value)
	print(JSON.stringify({"check": label, "passed": value}))

func frame(count := 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func run() -> void:
	for sample: Array in [[ADDRESSES[0], 1001, "1c1b4200"], [ADDRESSES[0], 1002, "d664f126"], [ADDRESSES[2], 1001, "bc579f56"], [ADDRESSES[2], 1002, "e7dba621"]]:
		check(Layout.generate(sample[0], sample[1]).layout.fingerprint == sample[2], "golden_%s_%d" % [sample[0][0], sample[1]])
	var signatures: Dictionary = {}
	for words: Array in ADDRESSES:
		var identity: Dictionary = Layout.generate(words, 0).layout.identity
		var variants: Dictionary = {}
		for seed_value in range(32):
			var a: Dictionary = Layout.generate(words, seed_value).layout
			var b: Dictionary = Layout.generate(words, seed_value).layout
			check(Blueprint.canonical_json(a) == Blueprint.canonical_json(b), "deterministic_%s_%d" % [words[0], seed_value])
			check(a.identity == identity, "stable_identity_%s_%d" % [words[0], seed_value])
			check(connected(a) and route_supported(a), "connected_route_%s_%d" % [words[0], seed_value])
			variants[str(a.modules)] = true
			signatures[a.fingerprint] = true
		check(variants.size() >= 12, "seed_changes_geometry_" + words[0])
	check(not Layout.generate(["drowned", "drowned", "hollow"], 1).ok, "duplicates_rejected_without_layout")
	check(not Layout.generate(["unknown", "hollow", "cathedral"], 1).ok, "unsupported_rejected_without_layout")
	# Exercise new vocabulary through the existing builder as well as legacy fixtures.
	# Physics fixtures inspect the actual built shapes, not a second layout model.
	for words: Array in ADDRESSES + GRAMMAR_ADDRESSES:
		for seed_value in [1, 1001, 1002]:
			var layout: Dictionary = Layout.generate(words, seed_value).layout
			var world := Builder.new()
			world.layout = layout
			root.add_child(world)
			await frame(2)
			check(physics_route(world, layout), "capsule_route_%s_%d" % [words[0], seed_value])
			check(physics_arena(world, layout), "clear_arena_%s_%d" % [words[0], seed_value])
			check(physics_boundary(world, layout), "solid_boundaries_%s_%d" % [words[0], seed_value])
			world.set_arena_sealed(true)
			await frame(2)
			var gate := Builder.point(layout.arena) + Vector3(0, 1, 14)
			var ray := PhysicsRayQueryParameters3D.create(gate - Vector3(0, 0, 1), gate + Vector3(0, 0, 1), ENVIRONMENT)
			var blocked: bool = not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			world.set_arena_sealed(false)
			await frame(2)
			check(blocked and world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "arena_gate_%s_%d" % [words[0], seed_value])
			world.free()
	var shell := Shell.instantiate()
	root.add_child(shell)
	await frame(2)
	await capture("01_selection")
	# Equal menu indices now select distinct words from separate vocabularies.
	shell.choices[1].select(shell.choices[0].selected)
	check(shell.choices[0].get_item_text(shell.choices[0].selected) != shell.choices[1].get_item_text(shell.choices[1].selected), "ui_equal_indices_are_distinct_words")
	select_words(shell, ADDRESSES[0])
	shell.replay_check.button_pressed = true
	shell.seed_edit.text = "4294967296"
	shell._begin_selection()
	check(shell.expedition == null, "ui_out_of_range_seed")
	shell.seed_edit.text = "1001"
	shell.begin_button.grab_focus()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await frame()
	enter.pressed = false
	Input.parse_input_event(enter)
	await frame(3)
	check(shell.expedition.layout.blueprint.input.world_seed == "1001" and shell.canvas.layer > shell.expedition.hud.get_parent().layer, "ui_seed_replay_and_menu_overlay")
	check(not shell.expedition.enemy.enabled and not shell.expedition.encounter_started, "soul_waits_for_arrival")
	await capture("02_drowned_arrival")
	# Controlled reset fixture; the separate playthrough never writes positions.
	shell.expedition.player.reset_at(Builder.point(shell.expedition.layout.arena) + Vector3(0, 0.02, 4))
	await frame(2)
	check(shell.expedition.enemy.enabled and is_instance_valid(shell.expedition.world_builder.arena_gate), "arrival_seals_readable_arena")
	shell.expedition.player.preferred_camera_distance = 4.0
	shell.expedition.reset_encounter()
	check(shell.expedition.player.position.distance_to(Builder.point(shell.expedition.layout.arena) + Vector3(0, 0.02, 4)) < 0.01 and shell.expedition.player.preferred_camera_distance == 4.0, "retry_at_arena_preserves_zoom")
	var original: String = shell.expedition.layout.fingerprint
	var before: float = shell.expedition.encounter_time
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await frame(3)
	check(paused and shell.pause_panel.visible and shell.expedition.encounter_time == before, "escape_pauses_entire_encounter")
	await capture("03_pause")
	shell.restart_expedition()
	await frame(3)
	check(not paused and shell.expedition.layout.fingerprint == original and not shell.expedition.encounter_started, "restart_replays_layout_fresh_session")
	check(not shell.expedition.progression.owns("item.marrow_arm"), "restart_initial_inventory")
	shell.return_to_selection()
	await frame(2)
	check(shell.expedition == null and shell.selection.visible and not paused, "return_destroys_session")
	shell.replay_check.button_pressed = false
	shell._begin_selection()
	var fresh: int = shell.last_request.seed
	shell.return_to_selection()
	shell._begin_selection()
	check(fresh != shell.last_request.seed, "new_expeditions_use_fresh_entropy")
	# Fixed camera fixtures for comparing address identity and seeded geography.
	for i in range(4):
		var words: Array = ADDRESSES[i if i < 3 else 0]
		shell.start_expedition(words, 1001 if i < 3 else 1002)
		await frame(2)
		var expedition: Node3D = shell.expedition
		var camera := Camera3D.new()
		expedition.add_child(camera)
		var middle := Builder.point(expedition.layout.modules[1].center) * Layout.CELL
		camera.position = middle + Vector3(26, 26, 34)
		camera.look_at(middle + Vector3(0, 0, -10))
		camera.current = true
		await frame(2)
		await capture("0%d_%s_overview" % [4 + i, words[0]])
		if i == 2:
			camera.position = middle + Vector3(0, 5, 12)
			camera.look_at(middle + Vector3(0, 1, -3))
			await frame(2)
			await capture("08_fire_ice_reliquary")
	shell.return_to_selection()
	shell.free()
	var summary := {"summary": true, "passed": passed, "failed": failed, "unique_layouts": signatures.size(), "engine": Engine.get_version_info().string, "rendered": rendered}
	FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t") + "\n")
	print(JSON.stringify(summary))
	quit(1 if failed else 0)

func select_words(shell: Node, words: Array) -> void:
	for i in 3:
		var choice: OptionButton = shell.choices[i]
		for j in choice.item_count:
			if choice.get_item_text(j).to_lower() == words[i]:
				choice.select(j)

func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)

func connected(layout: Dictionary) -> bool:
	var remaining: Dictionary = {}
	for tile: Array in layout.tiles:
		remaining[Vector2i(tile[0], tile[1])] = true
	var frontier: Array = [Vector2i.ZERO]
	remaining.erase(Vector2i.ZERO)
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if remaining.has(current + step):
				remaining.erase(current + step)
				frontier.append(current + step)
	return remaining.is_empty()

func route_supported(layout: Dictionary) -> bool:
	var cells: Dictionary = {}
	for tile: Array in layout.tiles:
		cells[Vector2i(tile[0], tile[1])] = true
	for i in range(1, layout.path.size()):
		var start := Builder.point(layout.path[i - 1])
		var end := Builder.point(layout.path[i])
		for j in range(int(start.distance_to(end)) + 1):
			var location := start.move_toward(end, j)
			if not cells.has(Vector2i(roundi(location.x / 4.0), roundi(location.z / 4.0))):
				return false
	return true

func physics_route(world: Node3D, layout: Dictionary) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = ENVIRONMENT
	for i in range(1, layout.path.size()):
		var start := Builder.point(layout.path[i - 1]) + Vector3.UP
		var end := Builder.point(layout.path[i]) + Vector3.UP
		query.transform = Transform3D(Basis.IDENTITY, start)
		query.motion = end - start
		var result := world.get_world_3d().direct_space_state.cast_motion(query)
		if result[0] < 1.0:
			return false
		for j in range(int(start.distance_to(end)) + 1):
			var p := start.move_toward(end, j)
			var ray := PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 2, ENVIRONMENT)
			if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				return false
	return true

func physics_arena(world: Node3D, layout: Dictionary) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 7, 20)
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, Builder.point(layout.arena) + Vector3.UP * 3.6)
	query.collision_mask = ENVIRONMENT
	return world.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func physics_boundary(world: Node3D, layout: Dictionary) -> bool:
	for edge: Array in layout.edges:
		var start := Vector3(edge[0] * 4.0, 0.7, edge[1] * 4.0)
		var end := start + Vector3(edge[2] * 3.0, 0, edge[3] * 3.0)
		if world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, ENVIRONMENT)).is_empty():
			return false
	return true
