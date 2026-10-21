extends SceneTree
## Deterministic fixtures for the expedition-preview pipeline: golden fingerprints,
## repeatability, seed variation, keyword identity/contrast, legacy addresses,
## validator negative controls, and physics checks of the actually built geometry.
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Validator = preload("res://scripts/expedition_preview/plan_validator.gd")
const Builder = preload("res://scripts/expedition_preview/preview_builder.gd")
const Blueprint = preload("res://scripts/worldgen/blueprint_generator.gd")
const Modules = preload("res://scripts/combat/attack_modules.gd")
const ADDRESSES := [["drowned", "hollow", "cathedral"], ["ashen", "silent", "sanctuary"],
	["moonlit", "thorned", "garden"], ["weeping", "forgotten", "requiem"],
	["frozen", "gilded", "citadel"], ["smoldering", "pallid", "necropolis"]]
const LEGACY := [["tempest", "frozen", "towering"], ["smoldering", "frozen", "ossuary"], ["veiled", "sunken", "dream"]]
const GOLDEN := [[["drowned", "hollow", "cathedral"], 1001, "7f003420"], [["drowned", "hollow", "cathedral"], 1002, "0a90a3d5"],
	[["smoldering", "pallid", "necropolis"], 7, "310b0809"]]
const SEEDS := 24
const TAG_LANDMARKS := {"cold": "rime_obelisks", "fire": "ember_pyre", "water": "drowned_basin", "wealth": "gilded_idol", "bone": "rib_arch"}
var failed := 0
var passed := 0
var output := "res://artifacts/expedition-preview-tests"
var rendered := false
var metrics: Dictionary = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	rendered = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(value: bool, label: String, detail: Variant = null) -> void:
	failed += int(not value)
	passed += int(value)
	var record := {"check": label, "passed": value}
	if not value and detail != null:
		record["detail"] = detail
	print(JSON.stringify(record))

func frame(count := 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func run() -> void:
	for sample: Array in GOLDEN:
		var fingerprint: String = Plan.generate(sample[0], sample[1]).plan.fingerprint
		print(JSON.stringify({"golden": sample[0], "seed": sample[1], "fingerprint": fingerprint}))
		check(fingerprint == sample[2], "golden_%s_%d" % [sample[0][0], sample[1]], fingerprint)
	_structure()
	_legacy()
	_negative_controls()
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/first_expedition.tscn", "default_scene_unchanged")
	check(load("res://scenes/expedition_preview.tscn") is PackedScene, "preview_scene_separately_selectable")
	for fixture: Array in [[ADDRESSES[0], 1001], [ADDRESSES[5], 7], [ADDRESSES[2], 3]]:
		await _physics(fixture[0], fixture[1])
	var summary := {"summary": true, "passed": passed, "failed": failed, "rendered": rendered, "metrics": metrics,
		"engine": Engine.get_version_info().string}
	var file := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t") + "\n")
	print(JSON.stringify(summary))
	quit(1 if failed else 0)

func _structure() -> void:
	var landmark_counts := {}
	var tag_sets := {}
	var total_usec := 0
	var plans := 0
	var region_counts: Array = []
	var room_counts: Array = []
	for words: Array in ADDRESSES:
		var identity: Dictionary = {}
		var region_shapes := {}
		var dungeon_shapes := {}
		var fingerprints := {}
		var counts := {}
		for seed_value in SEEDS:
			var started := Time.get_ticks_usec()
			var a: Dictionary = Plan.generate(words, seed_value)
			total_usec += Time.get_ticks_usec() - started
			plans += 1
			var b: Dictionary = Plan.generate(words, seed_value)
			var label := "%s_%d" % [words[0], seed_value]
			check(a.ok and a.errors.is_empty(), "valid_" + label, a.errors)
			check(Blueprint.canonical_json(a.plan) == Blueprint.canonical_json(b.plan), "deterministic_" + label)
			if identity.is_empty():
				identity = a.plan.identity
			check(a.plan.identity == identity, "stable_identity_" + label)
			var regions: Array = a.plan.world.regions
			check(regions[0].biome == a.plan.identity.biome, "arrival_uses_primary_biome_" + label)
			region_shapes[JSON.stringify([regions.map(func(r: Dictionary) -> Array: return [r.slot, r.template, r.level]), a.plan.world.bridges.map(func(x: Dictionary) -> Array: return [x.from, x.to])])] = true
			dungeon_shapes[JSON.stringify(a.plan.dungeon.rooms.map(func(r: Dictionary) -> Array: return [r.template, r.center]))] = true
			fingerprints[a.plan.fingerprint] = true
			region_counts.append(regions.size())
			room_counts.append(a.plan.dungeon.rooms.size())
			var roles: Array = []
			for region: Dictionary in regions:
				roles.append_array(region.roles)
				counts[region.landmark] = counts.get(region.landmark, 0) + 1
			check(roles.count("descent") == 1 and roles.count("extraction") == 1 and roles.count("sentinel") == 1, "roles_assigned_" + label)
			check(not a.plan.dungeon.fallback, "dungeon_generated_without_fallback_" + label)
			check(a.plan.world.route[0] == "r0" and a.plan.world.route[-1] == a.plan.world.descent.region, "route_reaches_descent_" + label)
		check(region_shapes.size() >= SEEDS / 2, "seed_varies_regions_" + words[0], region_shapes.size())
		check(dungeon_shapes.size() >= SEEDS / 2, "seed_varies_dungeon_" + words[0], dungeon_shapes.size())
		check(fingerprints.size() == SEEDS, "seed_changes_fingerprint_" + words[0])
		landmark_counts[words[0]] = counts
		tag_sets[words[0]] = identity.tags
		metrics["unique_regions_" + words[0]] = region_shapes.size()
		metrics["unique_dungeons_" + words[0]] = dungeon_shapes.size()
	# Contrasting identities: each address keeps its own semantic tags, and tagged
	# landmarks appear more often where the keywords carry that tag.
	var distinct := {}
	for words: Array in ADDRESSES:
		distinct[JSON.stringify(tag_sets[words[0]])] = true
	check(distinct.size() == ADDRESSES.size(), "addresses_keep_distinct_identity")
	for tag: String in TAG_LANDMARKS:
		var with: Array = []
		var without: Array = []
		for words: Array in ADDRESSES:
			var count: int = landmark_counts[words[0]].get(TAG_LANDMARKS[tag], 0)
			(with if tag in tag_sets[words[0]] else without).append(count)
		if with.is_empty() or without.is_empty():
			continue
		check(_mean(with) > _mean(without), "keyword_tag_%s_favours_%s" % [tag, TAG_LANDMARKS[tag]], [with, without])
	metrics["plans"] = plans
	metrics["generation_ms_mean"] = total_usec / 1000.0 / plans
	metrics["regions_min_max"] = [region_counts.min(), region_counts.max()]
	metrics["dungeon_rooms_min_max"] = [room_counts.min(), room_counts.max()]
	check(region_counts.min() >= 4 and region_counts.max() <= 6, "region_count_bounded")

func _legacy() -> void:
	for words: Array in LEGACY:
		for seed_value in [1, 1001]:
			var generated: Dictionary = Plan.generate(words, seed_value)
			var blueprint: Dictionary = Blueprint.new().generate(words, seed_value).blueprint
			check(generated.ok and generated.plan.blueprint_fingerprint == blueprint.fingerprint and generated.plan.address == blueprint.address,
				"legacy_address_%s_%d" % [words[0], seed_value])
	check(not Plan.generate(["drowned", "drowned", "hollow"], 1).ok, "duplicate_keywords_rejected")
	check(Plan.generate(["unknown", "hollow", "cathedral"], 1).plan.is_empty(), "unknown_keyword_produces_no_plan")

## Each mutation breaks one invariant; the validator must name it.
func _negative_controls() -> void:
	var base: Dictionary = Plan.generate(ADDRESSES[0], 1001).plan
	var cases: Array = []
	var plan := base.duplicate(true)
	var bridge: Dictionary = plan.world.bridges.pop_back()
	if not bridge.loop:
		plan.world.tiles = plan.world.tiles.filter(func(tile: Dictionary) -> bool: return tile.owner != bridge.id)
		cases.append(["regions_disconnected", plan])
	plan = base.duplicate(true)
	var spawn: Array = plan.world.spawn
	plan.world.solids[0].rect = [spawn[0] * 4.0 - 1.0, spawn[1] * 4.0 - 1.0, spawn[0] * 4.0 + 1.0, spawn[1] * 4.0 + 1.0]
	cases.append(["world_solid_on_walkable_floor", plan])
	plan = base.duplicate(true)
	plan.world.extraction = [9999, 9999]
	cases.append(["unreachable_target", plan])
	plan = base.duplicate(true)
	plan.dungeon.rooms[1].rect = plan.dungeon.rooms[0].rect.duplicate()
	cases.append(["dungeon_pieces_overlap", plan])
	plan = base.duplicate(true)
	var corridor: Dictionary = plan.dungeon.corridors[0]
	var step: Vector2i = Validator.DIRS[corridor.dir]
	for x in range(int(corridor.rect[0]), int(corridor.rect[2]) + 1):
		for z in range(int(corridor.rect[1]), int(corridor.rect[3]) + 1):
			plan.dungeon.blocked.append([x + step.x, z + step.y])
	cases.append(["dungeon_door_misaligned", plan])
	plan = base.duplicate(true)
	# Pretend the side cache were the guardian's room: the real route bypasses it.
	plan.dungeon.guardian.room = plan.dungeon.rooms.filter(func(room: Dictionary) -> bool: return room.role == "cache")[0].id
	cases.append(["reward_bypasses_guardian", plan])
	plan = base.duplicate(true)
	plan.dungeon.blocked.append(plan.dungeon.guardian.cell)
	cases.append(["guardian_floor_obstructed", plan])
	plan = base.duplicate(true)
	plan.dungeon.gates.pop_back()
	cases.append(["guardian_gate_count", plan])
	check(Validator.validate(base).is_empty(), "negative_control_base_valid")
	for case: Array in cases:
		var codes: Array = Validator.validate(case[1]).map(func(error: Dictionary) -> String: return error.code)
		check(case[0] in codes, "validator_rejects_" + case[0], codes)

func _physics(words: Array, seed_value: int) -> void:
	var plan: Dictionary = Plan.generate(words, seed_value).plan
	var label := "%s_%d" % [words[0], seed_value]
	var world := Builder.new()
	world.plan = plan
	var started := Time.get_ticks_usec()
	root.add_child(world)
	metrics["build_ms_" + label] = (Time.get_ticks_usec() - started) / 1000.0
	metrics["nodes_" + label] = world.stats()
	await frame(2)
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = Modules.ENVIRONMENT_LAYER
	var bad_floor: Array = []
	var bad_clear: Array = []
	var bad_edges: Array = []
	var open := {}
	for tile: Dictionary in plan.world.tiles:
		open[Plan.key(Plan.cell_of(tile.cell))] = true
	for blocked: String in plan.world.blocked:
		open[blocked] = false
	# The descent is entered only from its approach cell; its posts close the sides.
	var descent_key := Plan.key(Plan.cell_of(plan.world.descent.cell))
	open[descent_key] = false
	for tile: Dictionary in plan.world.tiles:
		var cell := Plan.cell_of(tile.cell)
		if Plan.key(cell) == descent_key:
			continue
		var point := world.world_point(tile.cell)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point + Vector3.DOWN * 4.0, Modules.ENVIRONMENT_LAYER))
		if hit.is_empty() or absf(hit.position.y - point.y) > 0.2:
			bad_floor.append(tile.cell)
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 1.0)
		if not space.intersect_shape(query, 1).is_empty():
			bad_clear.append(tile.cell)
		for step: Vector2i in Validator.STEPS:
			var neighbour := cell + step
			var neighbour_key := Plan.key(neighbour)
			if open.has(neighbour_key) and open[neighbour_key]:
				# Adjacent floor: the capsule fits on the shared edge (no wall between).
				var middle := (point + world.world_point([neighbour.x, neighbour.y])) * 0.5
				query.transform = Transform3D(Basis.IDENTITY, middle + Vector3.UP * 1.0)
				if not space.intersect_shape(query, 1).is_empty():
					bad_clear.append([tile.cell, "edge"])
			elif not open.has(neighbour_key):
				# Floor boundary: a solid parapet stops the player at the rim.
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point + Vector3.UP * 0.6 + Vector3(step.x, 0, step.y) * 2.6, Modules.ENVIRONMENT_LAYER)
				if space.intersect_ray(ray).is_empty():
					bad_edges.append([tile.cell, [step.x, step.y]])
	check(bad_floor.is_empty(), "world_floor_under_every_cell_" + label, bad_floor.slice(0, 6))
	check(bad_clear.is_empty(), "world_cells_and_edges_clear_" + label, bad_clear.slice(0, 6))
	check(bad_edges.is_empty(), "world_rim_walled_" + label, bad_edges.slice(0, 6))
	for solid: Dictionary in plan.world.solids:
		var rect: Array = solid.rect
		var center := Vector3((float(rect[0]) + float(rect[2])) * 0.5, 40.0, (float(rect[1]) + float(rect[3])) * 0.5)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center, center + Vector3.DOWN * 60.0, Modules.ENVIRONMENT_LAYER))
		if hit.is_empty() or hit.position.y < 0.5:
			check(false, "world_solid_built_" + label, solid)
	# Dungeon: floor, clearance, walls on every boundary edge, gates block when closed.
	var d_open := {}
	for cell: Array in plan.dungeon.tiles:
		d_open[Plan.key(Plan.cell_of(cell))] = true
	for cell: Array in plan.dungeon.blocked:
		d_open[Plan.key(Plan.cell_of(cell))] = false
	bad_floor.clear()
	bad_clear.clear()
	bad_edges.clear()
	for value: Array in plan.dungeon.tiles:
		var cell := Plan.cell_of(value)
		if not d_open[Plan.key(cell)]:
			continue
		var point := world.dungeon_point(value)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 3.0, Modules.ENVIRONMENT_LAYER))
		if hit.is_empty() or absf(hit.position.y - point.y) > 0.05:
			bad_floor.append(value)
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 1.0)
		if not space.intersect_shape(query, 1).is_empty():
			bad_clear.append(value)
		for step: Vector2i in Validator.STEPS:
			var neighbour_key := Plan.key(cell + step)
			if d_open.get(neighbour_key, false):
				var middle := point + Vector3(step.x, 0, step.y) * float(plan.dungeon.cell) * 0.5
				query.transform = Transform3D(Basis.IDENTITY, middle + Vector3.UP * 1.0)
				if not space.intersect_shape(query, 1).is_empty():
					bad_clear.append([value, "edge"])
			elif not d_open.has(neighbour_key):
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.UP + Vector3(step.x, 0, step.y) * 1.6, Modules.ENVIRONMENT_LAYER)
				if space.intersect_ray(ray).is_empty():
					bad_edges.append([value, [step.x, step.y]])
	check(bad_floor.is_empty(), "dungeon_floor_under_every_cell_" + label, bad_floor.slice(0, 6))
	check(bad_clear.is_empty(), "dungeon_cells_and_doors_clear_" + label, bad_clear.slice(0, 6))
	check(bad_edges.is_empty(), "dungeon_boundary_walled_" + label, bad_edges.slice(0, 6))
	for gate: Dictionary in plan.dungeon.gates:
		var center: Vector3 = world.dungeon_root.position + Vector3(float(gate.center[0]), 1.0, float(gate.center[1]))
		var across := Vector3(0, 0, 1.5) if gate.axis == "x" else Vector3(1.5, 0, 0)
		var ray := PhysicsRayQueryParameters3D.create(center - across, center + across, Modules.ENVIRONMENT_LAYER)
		world.set_gate(gate.id, true)
		await frame()
		var closed := not space.intersect_ray(ray).is_empty()
		world.set_gate(gate.id, false)
		await frame()
		check(closed and space.intersect_ray(ray).is_empty(), "gate_blocks_only_when_closed_%s_%s" % [gate.id, label])
	if rendered:
		await _map_captures(world, plan, label)
	world.queue_free()
	await frame()

func _map_captures(world: Node3D, plan: Dictionary, label: String) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 600.0
	world.add_child(camera)
	var center := Vector3.ZERO
	for region: Dictionary in plan.world.regions:
		center += Vector3(float(region.center[0]), 0, float(region.center[1])) * float(plan.world.cell)
	center /= plan.world.regions.size()
	camera.size = 240.0
	camera.position = center + Vector3.UP * 220.0
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.current = true
	world.set_area("world")
	await frame(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("map_world_%s.png" % label)) == OK, "capture_world_map_" + label)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0
	camera.position = center + Vector3(-70, 85, 110)
	camera.look_at(center)
	await frame(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("oblique_world_%s.png" % label)) == OK, "capture_world_oblique_" + label)
	var dungeon_center := Vector3.ZERO
	for room: Dictionary in plan.dungeon.rooms:
		dungeon_center += Vector3(float(room.center[0]), 0, float(room.center[1])) * float(plan.dungeon.cell)
	dungeon_center /= plan.dungeon.rooms.size()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 150.0
	camera.position = world.dungeon_root.position + dungeon_center + Vector3.UP * 120.0
	camera.rotation_degrees = Vector3(-90, 0, 0)
	world.set_area("dungeon")
	await frame(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("map_dungeon_%s.png" % label)) == OK, "capture_dungeon_map_" + label)
	camera.queue_free()

static func _mean(values: Array) -> float:
	var total := 0.0
	for value: Variant in values:
		total += float(value)
	return total / maxf(1.0, values.size())
