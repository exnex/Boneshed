extends SceneTree
## Input-driven end-to-end run of the directional expedition: keyword selection ->
## generated surface -> vigil duel(s) with directional combat -> salvage/equip ->
## surface find -> descent -> dodge step and roll in the dungeon -> guardian duel with
## the inherited Marrow Lunge -> gates -> reliquary + cache -> ascent -> extraction.
##
## Every action is an ordinary InputEvent through the scene's InputMap (WASD, LMB/RMB
## presses, mouse motion for aim, Space, Shift, Q, F, E, R). The bot reads the plan
## to choose a route (as a player reads the map) and only *visible* combat cues to
## choose inputs: the soul's phase and drawn chamber direction, its blade angle and
## speed, its guard side and outcome labels — never its AI trace, hidden timers, RNG
## or stamina. It never writes positions, rules state, AI, rewards or inventory.
## Proves the loop is reachable with the new rules, not human skill, fairness or feel.
const Shell = preload("res://scenes/directional_expedition.tscn")
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const MOVES := ["lab_move_forward", "lab_move_back", "lab_move_left", "lab_move_right"]
const MAX_RETRIES := 3
var shell: Node
var e: Node3D
var output := "res://artifacts/directional-expedition-playthrough"
var words: Array = ["drowned", "hollow", "cathedral"]
var seed_value := 1001
var held: Dictionary = {}
var trace: Array = []
var captures: Dictionary = {}
var checks: Array = []
var perf: Dictionary = {}
var tick := 0
var failed := 0
var duels: Array = []
var ledgers: Array = []
var clip_frames := 0
var clip_dir := ""
var inherited_started := false
var inherited_contact := false
var evasion: Dictionary = {}

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

func rendered() -> bool:
	return DisplayServer.get_name() != "headless"

func check(condition: bool, label: String, detail: Variant = null) -> void:
	failed += int(not condition)
	checks.append({"check": label, "passed": condition, "detail": detail})
	print(JSON.stringify({"check": label, "passed": condition, "detail": detail}))

func input(action: String, pressed: bool) -> void:
	if held.get(action, false) == pressed:
		return
	held[action] = pressed
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	event.pressed = pressed
	Input.parse_input_event(event)

func motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	Input.parse_input_event(event)

func frame() -> void:
	await physics_frame
	await process_frame
	tick += 1
	if clip_frames > 0:
		clip_frames -= 1
		if tick % 2 == 0:
			await _save(clip_dir.path_join("frame_%05d.png" % tick))
	if is_instance_valid(e):
		var p: Node = e.player
		var foe: Node = e.opponent
		trace.append({"tick": tick, "area": e.area, "stage": e.progression.stage, "site": e.active_site,
			"position": [snappedf(p.position.x, 0.001), snappedf(p.position.y, 0.001), snappedf(p.position.z, 0.001)],
			"yaw": snappedf(p.camera_yaw, 0.001), "phase": p.state.phase, "direction": p.state.direction, "guard": p.state.guard,
			"health": snappedf(p.state.health, 0.001), "stamina": snappedf(p.state.stamina.current, 0.001),
			"enemy_phase": foe.state.phase if foe else -1, "enemy_health": snappedf(foe.state.health, 0.001) if foe else -1.0,
			"contacts": e.events.size(), "finds": e.satchel.entries.size(), "input": held.duplicate()})

func press(action: String) -> void:
	input(action, true)
	await frame()
	input(action, false)
	await frame()

func _save(path: String) -> void:
	if not rendered():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func capture(label: String) -> void:
	if captures.has(label):
		return
	captures[label] = tick
	if not rendered():
		return
	paused = true
	e.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)
	paused = false

func run() -> void:
	await frame()
	for slot in 3:
		var choice: OptionButton = shell.choices[slot]
		for index in choice.item_count:
			if choice.get_item_text(index).to_lower() == words[slot]:
				choice.select(index)
	shell.replay_check.button_pressed = true
	shell.seed_edit.text = str(seed_value)
	shell._begin_selection()
	e = shell.session
	check(is_instance_valid(e) and e.ok, "selection_starts_directional_expedition")
	if not is_instance_valid(e) or not e.ok:
		finish()
		return
	# QA receives legal mouse motion without a captured pointer (as the lab QA does).
	e.player.accept_uncaptured_motion = true
	var plan: Dictionary = e.plan
	await frame()
	await frame()
	await capture("01_arrival")
	e.hud.show_help = false
	await sample("surface")
	# 1. Every exterior soul, sentinel first (it guards the route to the descent).
	for i in plan.world.sites.size():
		await travel("world", plan.world.sites[i].cell)
		check(e.sites[i].cleared, "exterior_soul_%d_released_by_directional_duel" % i)
		if i == 0:
			await press("salvage")
			await press("equip")
			await frame()
			await capture("03_salvage_equipped")
			check(e.progression.equipped() and e.player.state.has_signature(), "salvaged_marrow_arm_equipped_grants_lunge")
	# 2. One surface find, then the descent.
	var finds_before: int = e.satchel.entries.size()
	var nearest: Dictionary = {}
	for item: Dictionary in plan.loot:
		if item.area == "world" and (nearest.is_empty() or _cell_distance(item.cell) < _cell_distance(nearest.cell)):
			nearest = item
	await travel("world", nearest.cell)
	check(e.satchel.entries.size() > finds_before, "surface_find_collected_by_walking")
	await travel("world", plan.world.descent.approach)
	check(e.descent_discovered, "descent_discovered")
	await capture("04_descent")
	var outcome := await travel("world", plan.world.descent.cell)
	check(outcome == "transition" and e.area == "dungeon", "descent_enters_dungeon")
	await frame()
	await capture("05_dungeon_entry")
	await sample("dungeon")
	await evade_in_dungeon()
	# 3. The guardian holds the only way to the reliquary.
	check(e.builder.gate_closed("gate.guardian_exit"), "vault_sealed_before_guardian")
	await travel("dungeon", plan.dungeon.guardian.cell)
	check(e.guardian_released, "guardian_released_by_directional_duel")
	check(not e.builder.gate_closed("gate.guardian_exit") and not e.builder.gate_closed("gate.guardian_entry"), "victory_opens_guardian_gates")
	check(inherited_started and inherited_contact, "inherited_marrow_lunge_connects_in_guardian_duel")
	await capture("07_guardian_released")
	var relic: Dictionary = plan.loot.filter(func(item: Dictionary) -> bool: return item.kind == "relic")[0]
	await travel("dungeon", relic.cell)
	check(e.satchel.has(relic.id), "reliquary_claimed")
	await capture("08_reliquary")
	var cache: Dictionary = plan.loot.filter(func(item: Dictionary) -> bool: return item.area == "dungeon" and item.kind != "relic")[0]
	await travel("dungeon", cache.cell)
	check(e.satchel.has(cache.id), "side_cache_collected")
	outcome = await travel("dungeon", plan.dungeon.ascent_portal)
	check(outcome == "transition" and e.area == "world", "ascent_returns_to_surface")
	# 4. Extraction: stand in the beacon for its full channel.
	await travel("world", plan.world.extraction)
	for i in 400:
		if e.finished:
			break
		await frame()
	check(e.finished and e.satchel.extracted and shell.summary_panel.visible, "extraction_completes_expedition")
	await capture("09_extracted")
	check(e.satchel.summary(e.progression.builds).finds.size() >= 3, "summary_reports_finds")
	_check_rules_integrity()
	finish()

## Stamina and contact invariants over the whole run (player and every soul).
func _check_rules_integrity() -> void:
	var duplicate_serials := 0
	var wrong_costs := 0
	for ledger: Dictionary in ledgers:
		var seen := {}
		for entry: Dictionary in ledger.entries:
			if entry.action == "refund":
				continue
			duplicate_serials += int(seen.has(entry.serial))
			seen[entry.serial] = true
			var expected: float = ledger.costs.get(entry.action, -1.0)
			wrong_costs += int(not is_equal_approx(entry.cost, expected))
	check(duplicate_serials == 0, "every_action_charged_once_player_and_souls", {"ledgers": ledgers.size()})
	check(wrong_costs == 0, "every_charge_is_the_builds_derived_cost", wrong_costs)
	var contacts: Array = e.events
	var by_soul := contacts.filter(func(c: Dictionary) -> bool: return c.attacker != "Pilgrim")
	var by_player := contacts.filter(func(c: Dictionary) -> bool: return c.attacker == "Pilgrim")
	check(not by_soul.is_empty() and not by_player.is_empty(), "both_sides_resolved_by_contact_solver", {"player": by_player.size(), "souls": by_soul.size()})
	var outcomes := {}
	for c: Dictionary in contacts:
		outcomes[c.result] = outcomes.get(c.result, 0) + 1
	check(outcomes.get("deflect", 0) > 0 and (outcomes.get("hit", 0) + outcomes.get("misaligned", 0)) > 0, "duels_include_deflections_and_hits", outcomes)

func finish() -> void:
	for action: String in held.keys():
		input(action, false)
	var file := FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(trace, "\t") + "\n")
	var contacts: Array = []
	if is_instance_valid(e):
		for c: Dictionary in e.events:
			contacts.append(e._printable(c))
	file = FileAccess.open(output.path_join("contacts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(contacts, "\t") + "\n")
	var summary := {"summary": true, "failed": failed, "passed": checks.size() - failed, "ticks": tick,
		"address": " ".join(words), "seed": seed_value, "captures": captures, "duels": duels, "evasion": evasion,
		"fingerprint": e.plan.fingerprint if is_instance_valid(e) else "", "performance": perf,
		"contacts": contacts.size(), "status_events": e.status_events.size() if is_instance_valid(e) else 0,
		"rendered": rendered(), "engine": Engine.get_version_info().string,
		"input": "keyboard/mouse InputEvents via InputMap and mouse motion; route read from the plan; visible combat cues only; no state writes"}
	file = FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t") + "\n")
	print(JSON.stringify(summary))
	paused = false
	shell.queue_free()
	await process_frame
	quit(1 if failed else 0)

func sample(label: String) -> void:
	for action: String in MOVES:
		input(action, false)
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in 60:
		await frame()
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	perf[label] = {"frame_ms_median": times[times.size() / 2], "frame_ms_p95": times[int(times.size() * 0.95)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"scene_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}

func _cell_distance(cell: Array) -> float:
	return e.player.global_position.distance_to(e.builder.world_point(cell))

## Dodge step and dodge roll through real keys in the dungeon's first room: each must
## move the body, be charged once, and leave it on the walkable floor.
func evade_in_dungeon() -> void:
	var p: Node = e.player
	await settle_stamina()
	for kind: Array in [["lab_dodge", "dodge", State.Phase.DODGE], ["lab_roll", "roll", State.Phase.ROLL]]:
		var start: Vector3 = p.global_position
		var ledger_size: int = p.state.stamina.ledger.size()
		var stamina_before: float = p.state.stamina.current
		input("lab_move_forward", true)
		await frame()
		input(kind[0], true)
		await frame()
		var seen_phase: bool = p.state.phase == kind[2]
		input(kind[0], false)
		for i in 50:
			await frame()
			seen_phase = seen_phase or p.state.phase == kind[2]
		input("lab_move_forward", false)
		await frame()
		var moved: float = Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
		var charges: Array = p.state.stamina.ledger.slice(ledger_size)
		var cost: float = p.state.resources.dodge_cost if kind[1] == "dodge" else p.state.resources.roll_cost
		evasion[kind[1]] = {"moved": snappedf(moved, 0.001), "charges": charges.size(), "cost": snappedf(cost, 0.001),
			"stamina_before": snappedf(stamina_before, 0.001)}
		check(seen_phase and moved > 1.5, "%s_moves_body_in_dungeon" % kind[1], evasion[kind[1]])
		check(charges.size() == 1 and charges[0].action == kind[1] and is_equal_approx(charges[0].cost, cost), "%s_charged_once_in_dungeon" % kind[1], charges)
		check(_on_dungeon_floor(p.global_position), "%s_stays_on_dungeon_floor" % kind[1], str(p.global_position))
		await settle_stamina()
	await capture("05b_dungeon_evasion")

func settle_stamina() -> void:
	for i in 240:
		if e.player.state.stamina.current >= e.player.state.stamina.max_stamina - 0.01:
			break
		await frame()

func _on_dungeon_floor(point: Vector3) -> bool:
	var size: float = e.plan.dungeon.cell
	var local: Vector3 = point - e.builder.dungeon_root.position
	var cell := Vector2i(roundi(local.x / size), roundi(local.z / size))
	for tile: Array in e.plan.dungeon.tiles:
		if Vector2i(int(tile[0]), int(tile[1])) == cell:
			return absf(local.y) < 0.6
	return false

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

func _steer(world_direction: Vector3, threshold := 0.38) -> void:
	# Camera-relative keys: the inverse of the player's camera-yaw rotation of input.
	var local: Vector3 = world_direction.normalized().rotated(Vector3.UP, -e.player.camera_yaw)
	input("lab_move_right", local.x > threshold)
	input("lab_move_left", local.x < -threshold)
	input("lab_move_back", local.z > threshold)
	input("lab_move_forward", local.z < -threshold)

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

# --- Duel bot: visible cues only --------------------------------------------------

## Cursor-space side an attack arrives on for the defender (mirror of its chamber).
static func arrival_of(direction: String) -> Vector2:
	if direction == Geometry.THRUST:
		return Vector2(0.0, -1.0)
	var c := Geometry.chamber_vector(direction)
	return Vector2(-c.x, c.y)

## Seconds until a visible swing (blade angle and speed) or thrust reaches the guard.
static func time_to_contact(s: State) -> float:
	if s.direction == Geometry.THRUST:
		return 0.0 if s.phase == State.Phase.SWING else 99.0
	if s.phase != State.Phase.SWING:
		return 99.0
	return maxf(0.0, s.theta - deg_to_rad(25.0)) / maxf(s.omega, 1.0)

func duel() -> void:
	var site: Dictionary = e.sites[e.active_site]
	var started := tick
	var use_signature: bool = e.progression.equipped()
	var retries := 0
	clip_dir = output.path_join("clip_" + site.kind)
	if rendered():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(clip_dir))
		clip_frames = 360
	await capture("02_vigil_duel" if site.kind == "exterior" else "06_guardian_duel")
	var guard_since := -1
	var repressed_swing := -1
	var aimed_side := ""
	var attack_state := ""
	var signature_wait := 0
	for i in 12000:
		var p: Node = e.player
		var ps: State = p.state
		if e.progression.stage == e.Progression.Stage.VICTORY:
			break
		if e.progression.stage == e.Progression.Stage.FALLEN:
			_collect_ledgers()
			retries += 1
			_release_combat()
			await frame()
			if retries > MAX_RETRIES:
				break
			await press("lab_reset")
			guard_since = -1
			continue
		var foe: Node = e.opponent
		if foe == null:
			await frame()
			continue
		var es: State = foe.state
		var distance: float = Vector2(p.global_position.x - foe.global_position.x, p.global_position.z - foe.global_position.z).length()
		var threat: bool = es.phase in [State.Phase.WINDUP, State.Phase.SWING] and es.direction != "" and not es.hit_consumed
		var opening: bool = es.phase in [State.Phase.RECOIL, State.Phase.STAGGER, State.Phase.BROKEN] or (es.phase == State.Phase.RECOVERY and not threat)
		# Footwork: hold just inside reach.
		var toward: Vector3 = foe.global_position - p.global_position
		toward.y = 0.0
		var ideal: float = ps.base_h.reach * 0.8
		if distance > ideal + 0.3:
			_steer(toward)
		elif distance < ideal - 0.6:
			_steer(-toward)
		else:
			_stop()
		# 1. The inherited lunge, from beyond sword reach, when nothing is incoming.
		if use_signature and not inherited_contact and attack_state == "" and ps.phase == State.Phase.IDLE and not threat \
				and distance > 2.3 and distance < float(ps.signature.get("reach", 0.0)) - 0.2 and signature_wait <= 0 and ps.legal_actions().signature:
			input("lab_guard", false)
			input("signature", true)
			inherited_started = true
			signature_wait = 150
			attack_state = "signature"
			await frame()
			input("signature", false)
			await frame()
			continue
		signature_wait -= 1
		if attack_state == "signature" and not ps.signature_active:
			attack_state = ""
		if use_signature and not inherited_contact and e.events.any(func(c: Dictionary) -> bool: return c.attacker == "Pilgrim" and c.signature):
			inherited_contact = true
		# 2. Defence: hold the guard on the visible arrival side; re-press just before contact.
		if threat and attack_state == "":
			var side := Geometry.classify_guard(arrival_of(es.direction), 0.0)
			if not held.get("lab_guard", false):
				input("lab_attack", false)
				input("lab_guard", true)
				guard_since = tick
				aimed_side = ""
				await frame()
				continue
			if aimed_side != side:
				var g := Geometry.guard_vector(side)
				motion(Vector2(g.x, -g.y) * 70.0)
				aimed_side = side
			if repressed_swing != es.swing_serial and time_to_contact(es) <= 0.09 and tick - guard_since >= 20:
				repressed_swing = es.swing_serial
				input("lab_guard", false)
				await frame()
				input("lab_guard", true)
				guard_since = tick
				await frame()
				continue
			await frame()
			continue
		# 3. Punish a visible opening: drop the guard, then a quick cut.
		if attack_state == "" and opening and distance <= ps.base_h.reach + 0.2:
			if held.get("lab_guard", false):
				input("lab_guard", false)
				aimed_side = ""
				await frame()
				continue
			if not ps.legal_actions().attack:
				await frame()
				continue
			input("lab_attack", true)
			attack_state = "cut"
			await frame()
			input("lab_attack", false)
			await frame()
			continue
		if attack_state == "cut" and ps.phase not in [State.Phase.WINDUP, State.Phase.SWING]:
			attack_state = ""
		if not threat and held.get("lab_guard", false) and attack_state == "" and es.phase == State.Phase.IDLE and tick - guard_since > 30:
			input("lab_guard", false)
			aimed_side = ""
		await frame()
	_collect_ledgers()
	_release_combat()
	clip_frames = 0
	for k in 3:
		await frame()
	var won: bool = e.progression.stage == e.Progression.Stage.VICTORY
	duels.append({"site": site.id, "kind": site.kind, "variant": site.variant.id, "ticks": tick - started, "won": won, "retries": retries,
		"player_health": snappedf(e.player.state.health, 0.01)})
	check(won and retries <= MAX_RETRIES, "bot_wins_" + site.id, duels[-1])

func _release_combat() -> void:
	for action: String in ["lab_attack", "lab_guard", "signature"] + MOVES:
		input(action, false)

func _collect_ledgers() -> void:
	for actor: Node in [e.player, e.sites[e.duel_site].enemy]:
		var s: State = actor.state
		var costs := {"attack": s.resources.attack_cost, "dodge": s.resources.dodge_cost, "roll": s.resources.roll_cost}
		if s.has_signature():
			costs.signature = s.signature_cost
		ledgers.append({"fighter": str(actor.name), "costs": costs, "entries": s.stamina.ledger.duplicate(true)})
