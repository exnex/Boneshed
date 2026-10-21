extends SceneTree
## Benchmarks for the visual showcase against the melee lab baseline, in whatever
## renderer the engine was started with. For each scene/preset it plays the same
## seeded AI duel and records, per frame: wall frame time, draw calls, objects,
## primitives; plus node, mesh, light and triangle counts, static memory, video /
## texture / buffer memory, shadow cost (same frames with shadows off) and the CPU cost
## of the pose layer (solver microbenchmark). Run through
## bash scripts/tooling/bench_visual_showcase.sh — on this cloud machine the renderer
## is llvmpipe/lavapipe (CPU software rendering): frame times measure the CPU, not a
## GPU, and must not be read as desktop performance.
##   --evidence-dir=DIR  --cases=lab,low,medium,high  --frames=N

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const PoseSolver = preload("res://scripts/visual_showcase/pose_solver.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const Quality = preload("res://scripts/visual_showcase/quality.gd")
const DT := 1.0 / 60.0
var output := "res://artifacts/visual-showcase-bench"
var cases: Array[String] = ["lab", "low", "medium", "high"]
var frames := 240
var report: Array[Dictionary] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--cases="):
			cases.assign(arg.trim_prefix("--cases=").split(","))
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func run() -> void:
	report.append(solver_bench())
	for name: String in cases:
		report.append(await scene_bench(name))
	var info := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(), "engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(), "cores": OS.get_processor_count(), "frames_per_case": frames}
	var file := FileAccess.open(output.path_join("bench_%s.json" % info.renderer), FileAccess.WRITE)
	file.store_string(JSON.stringify({"machine": info, "results": report}, "\t") + "\n")
	print(JSON.stringify({"suite": "visual_showcase_bench", "summary": true, "machine": info}))
	quit(0)

## CPU cost of one pose solve (both fighters run one each per rendered frame).
func solver_bench() -> Dictionary:
	var tuning: Dictionary = preload("res://scripts/melee_lab/lab_loadout.gd").load_tuning().values
	var handling := {"item": "item.notched_sword", "class": "blade", "two_handed": false, "length": 1.8, "mass": 1.4, "balance": 0.25,
		"inertia": 2.0, "accel": 110.0, "max_speed": 13.0, "brake": 130.0, "reach": 2.35, "thrust_accel": 50.0, "thrust_mass": 3.4,
		"guard_strength": 1.0, "guard_shift": 16.0, "turn_rate": 4.7, "can_guard": true, "can_deflect": true}
	var state := State.new(tuning, handling, {})
	var solver := PoseSolver.new(Rig.PILGRIM)
	var samples := 600
	var started := Time.get_ticks_usec()
	for i in range(samples):
		if i % 120 == 0:
			state.press_attack(["right_to_left", "overhead", "left_to_right", "thrust", "diag_left"][(i / 120) % 5])
		if i % 120 == 50:
			state.release_attack()
		state.tick(DT)
		solver.solve({"phase": state.phase, "hand": state.hand, "dir": state.dir, "direction": state.direction, "guarding": state.guarding,
			"guard": state.guard, "two_handed": false, "inertia": 2.0, "omega": state.omega, "velocity": Vector3.ZERO, "dodge_dir": Vector3.BACK,
			"progress": 0.0, "posture": 0.0, "look": Vector3(0, 1.5, -2.5), "released": state.released}, DT)
	var per_solve := float(Time.get_ticks_usec() - started) / samples
	var line := {"case": "pose_solver_cpu", "us_per_solve": snappedf(per_solve, 0.1), "samples": samples,
		"note": "includes the rules tick; two solves per rendered frame (player + soul)"}
	print(JSON.stringify(line))
	return line

func _count(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		out.meshes += 1
		if mi.mesh != null:
			out.surfaces += mi.mesh.get_surface_count()
			if mi.skin != null:
				out.skinned_meshes += 1
				for s in range(mi.mesh.get_surface_count()):
					out.skinned_vertices += mi.mesh.surface_get_array_len(s)
	if node is Light3D:
		out.lights += 1
		if (node as Light3D).shadow_enabled:
			out.shadowed_lights += 1
	if node is GPUParticles3D or node is CPUParticles3D:
		out.particle_systems += 1
	out.nodes += 1
	for child: Node in node.get_children():
		_count(child, out)

func _frame_stats(count: int, arena: Node) -> Dictionary:
	var times: Array[float] = []
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	var last := Time.get_ticks_usec()
	for i in range(count):
		_drive(arena)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	times.sort()
	var mean := 0.0
	for t: float in times:
		mean += t
	mean /= times.size()
	return {"frame_ms_mean": snappedf(mean, 0.01), "frame_ms_p50": snappedf(times[times.size() / 2], 0.01),
		"frame_ms_p95": snappedf(times[int(times.size() * 0.95)], 0.01), "fps_mean": snappedf(1000.0 / mean, 0.1),
		"draw_calls": roundi(draws / count), "objects": roundi(objects / count), "primitives": roundi(primitives / count)}

## Scripted player input on a fixed rhythm against the soul's seeded AI.
var _tick := 0
func _drive(arena: Node) -> void:
	_tick += 1
	var s: State = arena.player.state
	if _tick % 80 == 10:
		s.press_attack(["right_to_left", "overhead", "left_to_right", "diag_right"][(_tick / 80) % 4])
	if _tick % 80 == 40:
		s.release_attack()

func scene_bench(name: String) -> Dictionary:
	var scene := "res://scenes/melee_lab.tscn" if name == "lab" else "res://scenes/visual_showcase.tscn"
	if name != "lab":
		Quality.override = name
	MaterialLibrary.generation_ms = 0
	var started := Time.get_ticks_msec()
	var arena: Node = load(scene).instantiate()
	root.add_child(arena)
	await process_frame
	var startup := Time.get_ticks_msec() - started
	arena.opponent.mode = "duel"
	arena.opponent.reset_ai()
	_tick = 0
	for i in range(60):
		_drive(arena)
		await process_frame
	var counts := {"nodes": 0, "meshes": 0, "surfaces": 0, "skinned_meshes": 0, "skinned_vertices": 0, "lights": 0, "shadowed_lights": 0, "particle_systems": 0}
	_count(arena, counts)
	var stats := await _frame_stats(frames, arena)
	# Shadow cost: the same duel continued with every shadow switched off.
	var shadowed: Array[Light3D] = []
	_shadowed(arena, shadowed)
	for light: Light3D in shadowed:
		light.shadow_enabled = false
	var no_shadows := await _frame_stats(frames / 2, arena)
	for light: Light3D in shadowed:
		light.shadow_enabled = true
	var line := {"case": name, "scene": scene, "startup_ms": startup, "texture_generation_ms": MaterialLibrary.generation_ms,
		"quality": arena.get("quality").get("name", "lab") if arena.get("quality") != null else "lab",
		"static_memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_memory_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_memory_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_memory_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"counts": counts, "frames": stats, "frames_without_shadows": no_shadows,
		"shadow_cost_ms": snappedf(stats.frame_ms_mean - no_shadows.frame_ms_mean, 0.01)}
	if arena.get("crypt") != null and not (arena.crypt as Dictionary).is_empty():
		line.environment_triangles = arena.crypt.triangles
		line.character_triangles = arena.player.visual.triangles + arena.opponent.visual.triangles
		line.weapon_triangles = arena.player.visual.weapon_triangles + arena.opponent.visual.weapon_triangles
	print(JSON.stringify(line))
	arena.queue_free()
	await process_frame
	await process_frame
	return line

func _shadowed(node: Node, out: Array[Light3D]) -> void:
	if node is Light3D and (node as Light3D).shadow_enabled:
		out.append(node)
	for child: Node in node.get_children():
		_shadowed(child, out)
