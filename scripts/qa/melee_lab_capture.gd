extends SceneTree
## Rendered evidence for the directional melee lab: scripted clips in the real lab scene
## (llvmpipe under Xvfb). Each clip asserts the contact outcome it is meant to show.
## Run through bash scripts/tooling/test_melee_lab.sh, which also builds contact sheets
## and MP4s. Frames show placeholder presentation; they say nothing about game feel.

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const DT := 1.0 / 60.0
const FRAME_EVERY := 2
var output := "res://artifacts/melee-lab-rendered"
var arena: Node
var observer: Camera3D
var clips: Array[Dictionary] = []
var failed := 0
var evasive_swings := 0 # Same 5 s barrage: the resistant build must manage fewer.

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
	call_deferred("run")

func run() -> void:
	arena = load("res://scenes/melee_lab.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	observer = Camera3D.new()
	observer.fov = 50.0
	arena.add_child(observer)
	arena.hud.show_help = false
	await clip("telegraph_all_directions", "sword", "sword", 330, ["hit"], telegraph)
	await clip("block_aligned", "sword", "sword", 70, ["block"], attack_into_guard.bind("right_to_left", "left", -1))
	await clip("deflect_timed_press", "sword", "sword", 70, ["deflect"], attack_into_guard.bind("right_to_left", "left", 41))
	await clip("wrong_side_guard_hit", "sword", "sword", 70, ["hit"], attack_into_guard.bind("right_to_left", "right", -1))
	await clip("bad_angle_misaligned", "sword", "sword", 70, ["misaligned"], attack_into_guard.bind("overhead", "center", -1))
	await clip("guard_break_heavy_vs_light", "greatsword", "knife", 80, ["guard_break"], attack_into_guard.bind("overhead", "high", -1))
	await clip("thrust_vs_center_guard", "sword", "sword", 60, ["block"], attack_into_guard.bind("thrust", "center", -1))
	await clip("clash_crossing_blades", "sword", "sword", 70, ["clash"], clash)
	await clip("weapon_compare_knife", "knife", "sword", 90, [], combo)
	await clip("weapon_compare_sword", "sword", "sword", 90, [], combo)
	await clip("weapon_compare_greatsword", "greatsword", "sword", 110, [], combo)
	await clip("cancel_guard_and_dodge", "sword", "sword", 100, [], cancels)
	await clip("ai_duel", "sword", "sword", 420, [], duel)
	await clip("player_view_input_aim", "sword", "sword", 90, ["hit"], input_aim, true)
	# Combat resources (experimental): builds, stamina, evasion and statuses.
	await clip("stamina_barrage_evasive", "evasive", "balanced", 300, [], barrage, false, func() -> String:
		evasive_swings = arena.player.state.swing_serial
		return _expect(evasive_swings >= 7, "evasive swings %d" % evasive_swings))
	await clip("stamina_barrage_resistant", "resistant", "balanced", 300, [], barrage, false, func() -> String:
		return _expect(arena.player.state.swing_serial < evasive_swings and arena.player.state.stamina.current < arena.player.state.resources.attack_cost + 25.0,
			"resistant swings %d, stamina %.1f" % [arena.player.state.swing_serial, arena.player.state.stamina.current]))
	await clip("stamina_refused_attack", "resistant", "balanced", 90, [], refused, false, func() -> String:
		return _expect(arena.player.state.stamina.refusals >= 1 and arena.player.state.swing_serial == 0, "refusals %d" % arena.player.state.stamina.refusals))
	await clip("dodge_step_vs_roll", "balanced", "balanced", 150, [], evasions, false, func() -> String:
		var ledger: Array = arena.player.state.stamina.ledger.map(func(e: Dictionary) -> String: return e.action)
		return _expect(ledger == ["dodge", "roll"], str(ledger)))
	await clip("poison_venom_knife_hits", "evasive", "sword", 420, ["hit"], venom, false, func() -> String:
		var o: Node = arena.opponent
		var ticks: int = arena.status_events.filter(func(e: Dictionary) -> bool: return e.fighter == "Opponent" and e.event == "tick").size()
		return _expect(ticks >= 2 and o.state.status_damage_taken > 0.0, "poison ticks %d" % ticks))
	await clip("slow_greatsword_hits", "resistant", "balanced", 380, ["hit"], heavy_hits, false, func() -> String:
		var slowed: bool = arena.status_events.any(func(e: Dictionary) -> bool: return e.fighter == "Opponent" and e.effect == "slow" and e.event == "activated")
		return _expect(slowed, "slow activated %s" % slowed))
	await clip("dodge_avoids_venom", "balanced", "evasive", 110, ["evaded"], dodge_venom, false, func() -> String:
		return _expect(arena.player.state.status.buildup.poison == 0.0, "player poison buildup %.1f" % arena.player.state.status.buildup.poison))
	await clip("block_stops_venom", "balanced", "evasive", 110, ["block"], block_venom, false, func() -> String:
		return _expect(arena.player.state.status.buildup.poison == 0.0, "player poison buildup %.1f" % arena.player.state.status.buildup.poison))
	await clip("ai_duel_evasive_vs_resistant", "evasive", "resistant", 600, [], resource_duel, false, func() -> String:
		return _expect(arena.opponent.state.stamina.refusals == 0 and arena.events.size() > 0, "AI refusals %d, contacts %d" % [arena.opponent.state.stamina.refusals, arena.events.size()]))
	var file := FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(clips, "\t") + "\n")
	print(JSON.stringify({"suite": "melee_lab_rendered", "summary": true, "rendered": clips.size(), "failed": failed,
		"renderer": RenderingServer.get_video_adapter_name()}))
	quit(0 if failed == 0 else 1)

## Runs one clip: configure, then step `ticks` physics frames calling `script(tick)`.
func clip(label: String, player_weapon: String, opponent_weapon: String, ticks: int, expect: Array, script: Callable, player_view := false, verify := Callable()) -> void:
	arena.manual_step = true
	arena.set_loadouts(player_weapon, opponent_weapon)
	arena.player.input_enabled = player_view
	arena.player.accept_uncaptured_motion = true
	arena.opponent.mode = "dummy"
	arena.opponent.dummy_guard = ""
	arena.player.state.max_health = 10000.0
	arena.player.state.health = 10000.0
	arena.flags.debug = label.begins_with("block") or label.begins_with("bad_angle")
	observer.current = not player_view
	arena.player.camera.current = player_view
	arena.world_condition = ""
	_frame_side()
	var dir := output.path_join(label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await script.call(-1)
	arena.manual_step = false
	var frame := 0
	for tick in range(ticks):
		await script.call(tick)
		await physics_frame
		if tick % FRAME_EVERY == 0:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(dir.path_join("frame_%04d.png" % frame)))
			frame += 1
	arena.manual_step = true
	var results: Array = arena.events.map(func(e: Dictionary) -> String: return "%s:%s" % [e.attacker, e.result])
	var outcomes: Array = arena.events.map(func(e: Dictionary) -> String: return e.result)
	var ok := expect.all(func(r: String) -> bool: return r in outcomes)
	var verified := ""
	if verify.is_valid():
		verified = verify.call()
		ok = ok and not verified.begins_with("FAILED")
	failed += int(not ok)
	var record := {"clip": label, "frames": frame, "expected": expect, "events": results, "passed": ok,
		"player_weapon": player_weapon, "opponent_weapon": opponent_weapon}
	if verified != "":
		record.verified = verified
	clips.append(record)
	print(JSON.stringify(record))
	_release_inputs()
	await physics_frame

func _frame_side() -> void:
	observer.global_position = Vector3(4.6, 2.1, 1.0)
	observer.look_at(Vector3(0.0, 1.15, 0.9))

func _release_inputs() -> void:
	for action: String in ["lab_attack", "lab_guard"]:
		var event: InputEventMouseButton = InputMap.action_get_events(action)[0].duplicate()
		event.pressed = false
		Input.parse_input_event(event)

# --- Clip scripts (tick -1 is setup, before stepping starts) -------------------------

func telegraph(tick: int) -> void:
	var o: State = arena.opponent.state
	var order := ["right_to_left", "left_to_right", "overhead", "diag_right", "diag_left", "thrust"]
	if tick >= 0 and tick % 55 == 5:
		o.press_attack(order[mini(order.size() - 1, tick / 55)])
	if o.phase == State.Phase.WINDUP and o.windup_time >= 0.4:
		o.release_attack()

## Player attacks the dummy. `press_tick` >= 0 drops the held guard for one tick and
## presses it again then (a fresh press that opens the deflect window).
func attack_into_guard(tick: int, direction: String, guard: String, press_tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		arena.opponent.dummy_guard = guard
		return
	if tick == 10:
		p.press_attack(direction)
	if tick == 34:
		p.release_attack()
	if press_tick >= 0 and tick == press_tick - 1:
		arena.opponent.dummy_guard = ""
	if press_tick >= 0 and tick == press_tick:
		arena.opponent.dummy_guard = guard

func clash(tick: int) -> void:
	if tick == 10:
		arena.player.state.press_attack("right_to_left")
		arena.opponent.state.press_attack("left_to_right")
	if tick == 30:
		arena.player.state.release_attack()
		arena.opponent.state.release_attack()

## Two flowing cuts into the air: compares preparation, arc speed and recovery.
func combo(tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		return
	if tick == 6:
		p.press_attack("right_to_left")
		p.release_attack()
	if tick > 6 and p.phase in [State.Phase.RECOVERY, State.Phase.IDLE] and p.swing_serial == 1:
		p.press_attack("")
		p.release_attack()

func cancels(tick: int) -> void:
	var p: State = arena.player.state
	if tick == 8:
		p.press_attack("overhead")
	if tick == 22:
		p.set_guard(true, "high") # Fresh guard cancels the windup at once.
	if tick == 45:
		p.set_guard(false)
	if tick == 55:
		p.press_attack("left_to_right")
		p.release_attack()
	if tick == 72:
		arena.player.try_dodge(Vector3.RIGHT) # Dodge cancels mid-swing.

func duel(tick: int) -> void:
	if tick == -1:
		arena.opponent.mode = "duel"
		arena.opponent.reset_ai()
	arena.player.state.set_guard(true, "high")

## Real input events through the player's own camera and HUD cursor.
func input_aim(tick: int) -> void:
	var event: InputEventMouseButton = InputMap.action_get_events("lab_attack")[0].duplicate()
	if tick == 10:
		event.pressed = true
		Input.parse_input_event(event)
	if tick in [12, 13, 14]:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0.0, -25.0)
		Input.parse_input_event(motion)
	if tick == 34:
		event.pressed = false
		Input.parse_input_event(event)

static func _expect(ok: bool, detail: String) -> String:
	return ("ok: " if ok else "FAILED: ") + detail

## Chained cuts into the air as fast as stamina allows: the HUD bar and refusals show
## the build's economy.
func barrage(tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		return
	if p.phase in [State.Phase.IDLE, State.Phase.RECOVERY] and p.buffered == "" and p.stamina.can_afford(p.resources.attack_cost):
		p.press_attack("")
		p.release_attack()

func refused(tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		p.stamina.current = p.resources.attack_cost * 0.5
		p.stamina.since_spend = 0.0
		return
	if tick in [10, 30]:
		p.press_attack("overhead")
		p.release_attack()

## Dodge step to the right, then a dodge roll to the left (same build): distance, cost.
func evasions(tick: int) -> void:
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, -6.0)
		return
	if tick == 10:
		arena.player.try_dodge(Vector3.RIGHT)
	if tick == 80:
		arena.player.try_roll(Vector3.LEFT)

## Venom knife cuts into an unguarded dummy until poison activates and ticks.
func venom(tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, 1.0)
		arena.opponent.state.max_health = 10000.0
		arena.opponent.state.health = 10000.0
		return
	if tick < 200 and not arena.opponent.state.status.is_active("poison") and p.phase in [State.Phase.IDLE, State.Phase.RECOVERY] and p.buffered == "" and p.stamina.can_afford(p.resources.attack_cost):
		p.press_attack("")
		p.release_attack()

func heavy_hits(tick: int) -> void:
	var p: State = arena.player.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, 0.0)
		arena.opponent.state.max_health = 10000.0
		arena.opponent.state.health = 10000.0
		return
	if not arena.opponent.state.status.is_active("slow") and p.phase == State.Phase.IDLE and p.stamina.can_afford(p.resources.attack_cost):
		p.press_attack("overhead")
		p.release_attack()
	if arena.opponent.state.status.is_active("slow"):
		arena.opponent.desired_move = Vector3.LEFT # Walks slowly while impaired.

## The opponent's venom knife cut is dodged: evaded, no buildup.
func dodge_venom(tick: int) -> void:
	var o: State = arena.opponent.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, 1.0)
		return
	if tick == 10:
		o.press_attack("right_to_left")
		o.release_attack()
	if tick == 20:
		arena.player.state.dodge()

func block_venom(tick: int) -> void:
	var o: State = arena.opponent.state
	if tick == -1:
		arena.opponent.position = Vector3(0.0, 0.02, 1.0)
		return
	arena.player.state.set_guard(true, "left")
	if tick == 20:
		o.press_attack("right_to_left")
		o.release_attack()

## AI duel: the resistant opponent against a static guard, paying its own costs.
func resource_duel(tick: int) -> void:
	if tick == -1:
		arena.opponent.mode = "attack"
		arena.opponent.reset_ai()
	arena.player.state.set_guard(true, "high")
