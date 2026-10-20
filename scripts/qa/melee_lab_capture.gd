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
	var file := FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(clips, "\t") + "\n")
	print(JSON.stringify({"suite": "melee_lab_rendered", "summary": true, "rendered": clips.size(), "failed": failed,
		"renderer": RenderingServer.get_video_adapter_name()}))
	quit(0 if failed == 0 else 1)

## Runs one clip: configure, then step `ticks` physics frames calling `script(tick)`.
func clip(label: String, player_weapon: String, opponent_weapon: String, ticks: int, expect: Array, script: Callable, player_view := false) -> void:
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
	failed += int(not ok)
	var record := {"clip": label, "frames": frame, "expected": expect, "events": results, "passed": ok,
		"player_weapon": player_weapon, "opponent_weapon": opponent_weapon}
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
