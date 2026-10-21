extends SceneTree
## Input-driven end-to-end run of the isolated expedition preview: keyword selection
## -> generated surface -> sentinel duel -> salvage/equip -> descent -> guardian duel
## with the inherited lunge -> reliquary -> ascent -> extraction. The bot reads the
## plan to choose a route (as a player reads the map) and combat timing to choose
## ordinary key/mouse events. It never writes positions, combat state, AI, rewards or
## inventory. Proves reachability of the loop, not human skill, fairness or feel.
const Shell = preload("res://scenes/expedition_preview.tscn")
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
const MOVES := ["move_forward", "move_back", "move_left", "move_right"]
var shell: Node
var e: Node3D
var output := "res://artifacts/expedition-preview-playthrough"
var words: Array = ["drowned", "hollow", "cathedral"]
var seed_value := 1001
var held: Dictionary = {}
var trace: Array = []
var captures: Dictionary = {}
var checks: Array = []
var perf: Dictionary = {}
var tick := 0
var failed := 0
var inherited_started := false
var inherited_contact := false
var duels: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		elif arg.begins_with("--words="):
			words = Array(arg.trim_prefix("--words=").split(","))
		elif arg.begins_with("--seed="):
			seed_value = arg.trim_prefix("--seed=").to_int()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	shell = Shell.instantiate()
	root.add_child(shell)
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	failed += int(not condition)
	checks.append({"check": label, "passed": condition})
	print(JSON.stringify({"check": label, "passed": condition}))

func input(action: String, pressed: bool) -> void:
	if held.get(action, false) == pressed:
		return
	held[action] = pressed
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)

func frame() -> void:
	await physics_frame
	await process_frame
	tick += 1
	if is_instance_valid(e):
		var p: Fighter = e.player
		trace.append({"tick": tick, "area": e.area, "stage": e.progression.stage, "site": e.active_site,
			"position": [snappedf(p.position.x, 0.001), snappedf(p.position.y, 0.001), snappedf(p.position.z, 0.001)],
			"yaw": snappedf(p.yaw, 0.001), "locked": p.locked, "phase": p.combat.phase,
			"health": p.combat.health, "enemy_health": e.enemy.combat.health, "finds": e.satchel.entries.size(),
			"input": held.duplicate()})

func press(action: String) -> void:
	input(action, true)
	await frame()
	input(action, false)
	await frame()

func capture(label: String) -> void:
	if captures.has(label):
		return
	captures[label] = tick
	if DisplayServer.get_name() == "headless":
		return
	paused = true
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)
	paused = false

func run() -> void:
	await frame()
	# Address and seed entered through the shipped selection controls.
	for slot in 3:
		var choice: OptionButton = shell.choices[slot]
		for index in choice.item_count:
			if choice.get_item_text(index).to_lower() == words[slot]:
				choice.select(index)
	shell.replay_check.button_pressed = true
	shell.seed_edit.text = str(seed_value)
	shell._begin_selection()
	e = shell.preview
	check(is_instance_valid(e), "selection_starts_preview")
	if not is_instance_valid(e):
		finish()
		return
	var plan: Dictionary = e.plan
	await frame()
	await frame()
	await capture("01_arrival")
	await sample("surface")
	# 1. The required sentinel guards the route to the descent.
	var outcome := await travel("world", plan.world.sites[0].cell)
	check(e.sites[0].cleared, "sentinel_released_by_duel")
	await press("salvage")
	await press("equip")
	await capture("03_salvage_equipped")
	check(e.progression.equipped(), "salvaged_marrow_arm_equipped_with_keys")
	# 2. One surface find on the way, then the descent.
	var finds_before: int = e.satchel.entries.size()
	var nearest: Dictionary = {}
	for item: Dictionary in plan.loot:
		if item.area == "world" and (nearest.is_empty() or _cell_distance(item.cell) < _cell_distance(nearest.cell)):
			nearest = item
	outcome = await travel("world", nearest.cell)
	check(e.satchel.entries.size() > finds_before, "surface_find_collected_by_walking")
	outcome = await travel("world", plan.world.descent.approach)
	check(e.descent_discovered, "descent_discovered")
	await capture("04_descent")
	outcome = await travel("world", plan.world.descent.cell)
	check(outcome == "transition" and e.area == "dungeon", "descent_enters_dungeon")
	await frame()
	await capture("05_dungeon_entry")
	await sample("dungeon")
	# 3. The guardian holds the only way to the reliquary.
	check(e.builder.gate_closed("gate.guardian_exit"), "vault_sealed_before_guardian")
	outcome = await travel("dungeon", plan.dungeon.guardian.cell)
	check(e.guardian_released, "guardian_released_by_duel")
	check(not e.builder.gate_closed("gate.guardian_exit") and not e.builder.gate_closed("gate.guardian_entry"), "victory_opens_guardian_gates")
	check(inherited_started and inherited_contact, "inherited_marrow_lunge_used_in_guardian_duel")
	await capture("07_guardian_released")
	var relic: Dictionary = plan.loot.filter(func(item: Dictionary) -> bool: return item.kind == "relic")[0]
	outcome = await travel("dungeon", relic.cell)
	check(e.satchel.has(relic.id), "reliquary_claimed")
	await capture("08_reliquary")
	var cache: Dictionary = plan.loot.filter(func(item: Dictionary) -> bool: return item.area == "dungeon" and item.kind != "relic")[0]
	outcome = await travel("dungeon", cache.cell)
	check(e.satchel.has(cache.id), "side_cache_collected")
	outcome = await travel("dungeon", plan.dungeon.ascent_portal)
	check(outcome == "transition" and e.area == "world", "ascent_returns_to_surface")
	# 4. Extraction: stand in the beacon for its full channel.
	outcome = await travel("world", plan.world.extraction)
	for i in 400:
		if e.finished:
			break
		await frame()
	check(e.finished and e.satchel.extracted and shell.summary_panel.visible, "extraction_completes_expedition")
	await capture("09_extracted")
	check(e.satchel.summary(e.progression.builds).finds.size() >= 3, "summary_reports_finds")
	finish()

func finish() -> void:
	for action: String in held.keys():
		input(action, false)
	var file := FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(trace, "\t") + "\n")
	var summary := {"summary": true, "failed": failed, "passed": checks.size() - failed, "ticks": tick,
		"address": " ".join(words), "seed": seed_value, "captures": captures, "duels": duels,
		"fingerprint": e.plan.fingerprint if is_instance_valid(e) else "", "performance": perf,
		"rendered": DisplayServer.get_name() != "headless", "engine": Engine.get_version_info().string,
		"input": "physical keyboard/mouse InputEvents via InputMap; route read from the plan; no state writes"}
	file = FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t") + "\n")
	print(JSON.stringify(summary))
	paused = false
	shell.queue_free()
	await process_frame
	quit(1 if failed else 0)

func sample(label: String) -> void:
	# Idle frame cost in place. llvmpipe and headless numbers do not predict GPU cost.
	for action: String in MOVES:
		input(action, false)
	var times: Array = []
	var process: Array = []
	var physics: Array = []
	var last := Time.get_ticks_usec()
	for i in 90:
		await frame()
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	times.sort()
	perf[label] = {"frame_ms_mean": _mean(times), "frame_ms_p95": times[int(times.size() * 0.95)],
		"process_ms_mean": _mean(process), "physics_ms_mean": _mean(physics),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"scene_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"builder": e.builder.stats(), "generation_ms": shell.generation_ms}

static func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(1.0, values.size())

func _cell_distance(cell: Array) -> float:
	return e.player.global_position.distance_to(e.builder.world_point(cell))

## Walks to a cell in `area`, fighting any duel the director starts on the way.
## Returns "reached", "transition" (area changed) or "stuck".
func travel(area: String, goal: Array) -> String:
	for attempt in 6:
		var result := await walk(area, goal)
		if result == "duel":
			await duel()
			continue
		return result
	return "stuck"

func walk(area: String, goal: Array) -> String:
	var path := route(area, goal)
	if path.is_empty():
		check(false, "route_found_%s_%s" % [area, str(goal)])
		return "stuck"
	for index in path.size():
		var target: Vector3 = e.builder.world_point(path[index]) if area == "world" else e.builder.dungeon_point(path[index])
		var final := index == path.size() - 1
		var reached := false
		var last_position: Vector3 = e.player.global_position
		var still := 0
		var sidestep := 0
		for i in 900:
			if e.in_duel():
				_stop()
				return "duel"
			if e.area != area:
				_stop()
				return "transition"
			var offset: Vector3 = target - e.player.global_position
			offset.y = 0.0
			if offset.length() < (0.45 if final else 1.3):
				reached = true
				break
			# Like a player wiggling off a corner: a brief sidestep when pinned.
			still = still + 1 if e.player.global_position.distance_to(last_position) < 0.01 else 0
			last_position = e.player.global_position
			if still > 15:
				sidestep = 12
				still = 0
			if sidestep > 0:
				sidestep -= 1
				offset = offset.rotated(Vector3.UP, PI * 0.5)
			_steer(offset)
			await frame()
		if not reached:
			_stop()
			check(false, "walk_reaches_%s_%s" % [area, str(path[index])])
			return "stuck"
	_stop()
	return "reached"

func _steer(world_direction: Vector3) -> void:
	# Camera-relative keys: the inverse of Player's yaw rotation of the input vector.
	var local: Vector3 = world_direction.normalized().rotated(Vector3.UP, -e.player.yaw)
	input("move_right", local.x > 0.38)
	input("move_left", local.x < -0.38)
	input("move_back", local.z > 0.38)
	input("move_forward", local.z < -0.38)

func _stop() -> void:
	for action: String in MOVES:
		input(action, false)

## Breadth-first route over the plan's walkable cells, in the bot's own code.
func route(area: String, goal: Array) -> Array:
	var size: float = e.plan.world.cell if area == "world" else e.plan.dungeon.cell
	var origin: Vector3 = Vector3.ZERO if area == "world" else e.builder.dungeon_root.position
	var position: Vector3 = e.player.global_position - origin
	var start := Vector2i(roundi(position.x / size), roundi(position.z / size))
	var open := {}
	if area == "world":
		for tile: Dictionary in e.plan.world.tiles:
			open[Plan.key(Plan.cell_of(tile.cell))] = true
		for blocked: String in e.plan.world.blocked:
			open.erase(blocked)
		open.erase(Plan.key(Plan.cell_of(e.plan.world.descent.cell)))
	else:
		for cell: Array in e.plan.dungeon.tiles:
			open[Plan.key(Plan.cell_of(cell))] = true
		for cell: Array in e.plan.dungeon.blocked:
			open.erase(Plan.key(Plan.cell_of(cell)))
	var target := Plan.cell_of(goal)
	open[Plan.key(target)] = true
	var parent := {Plan.key(start): start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == target:
			var path: Array = []
			var node := current
			while node != start:
				path.push_front([node.x, node.y])
				node = parent[Plan.key(node)]
			path.push_back([target.x, target.y])
			return path
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := current + step
			if open.has(Plan.key(next)) and not parent.has(Plan.key(next)):
				parent[Plan.key(next)] = current
				queue.append(next)
	return []

## Legal-input duel, adapted from the Marrow playthrough bot: deflect near contact,
## punish visible recovery, and use the inherited lunge once it is equipped.
func duel() -> void:
	var site: Dictionary = e.sites[e.active_site]
	var started := tick
	var use_signature: bool = e.progression.equipped()
	await capture("02_sentinel_duel" if site.kind == "exterior" else "06_guardian_duel")
	var previous_enemy_event: int = e.enemy.event_serial
	for i in 9000:
		var p: Fighter = e.player
		var en: Fighter = e.enemy
		var pc: Rules = p.combat
		var ec: Rules = en.combat
		var distance: float = p.global_position.distance_to(en.global_position)
		input("attack", false)
		input("signature", false)
		input("lock_on", false)
		input("move_back", false)
		input("move_left", false)
		input("move_right", false)
		if e.progression.stage == e.Progression.Stage.VICTORY:
			break
		if e.progression.stage == e.Progression.Stage.FALLEN:
			check(false, "bot_survives_" + site.id)
			break
		if not p.locked:
			input("lock_on", true)
		input("move_forward", distance > 1.65 and pc.phase == Rules.Phase.IDLE)
		var incoming := ec.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE] and not ec.hit_consumed
		if incoming and ec.remaining <= 0.11 and distance <= en.attack_range + 0.2:
			input("guard", true)
		elif not incoming:
			input("guard", false)
		if use_signature and not inherited_contact and pc.phase == Rules.Phase.IDLE and not incoming and distance <= 3.1:
			input("guard", false)
			input("signature", true)
			inherited_started = true
		elif pc.phase == Rules.Phase.IDLE and not incoming and ec.phase in [Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.RECOVERY] and ec.remaining > pc.attack_windup + 0.06 and distance <= 2.15:
			input("attack", true)
		if pc.is_signature() and en.event_serial != previous_enemy_event and en.last_result in [Rules.HIT, Rules.GUARD, "punish", Rules.DEFEATED]:
			inherited_contact = true
		previous_enemy_event = en.event_serial
		await frame()
	for action: String in ["attack", "signature", "guard", "move_forward"]:
		input(action, false)
	if e.player.locked:
		await press("lock_on")
	duels.append({"site": site.id, "ticks": tick - started, "won": e.progression.stage == e.Progression.Stage.VICTORY,
		"player_health": e.player.combat.health})
	await frame()
