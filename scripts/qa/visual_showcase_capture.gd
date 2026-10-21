extends SceneTree
## Rendered evidence for the visual showcase: before/after pairs (melee lab vs
## showcase, same scripted moments and camera), character and equipment close-ups,
## crypt wide shots, and frame sequences for clips. Run through
## bash scripts/tooling/test_visual_showcase.sh (which encodes MP4s and sheets).
##   --evidence-dir=DIR   output folder
##   --set=compare|stills|clips|hero|all   (default all; hero = a few shots for a
##   second renderer, suffixed with the renderer name)
## Frames come from whatever renderer the engine was started with (llvmpipe here); they
## show presentation, not performance, and say nothing about game feel.

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const DT := 1.0 / 60.0
var output := "res://artifacts/visual-showcase-capture"
var which := "all"
var observer: Camera3D
var arena: Node
var manifest: Array[Dictionary] = []
var failed := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func run() -> void:
	var renderer := RenderingServer.get_current_rendering_method()
	if which in ["compare", "all"]:
		for scene: String in ["res://scenes/melee_lab.tscn", "res://scenes/visual_showcase.tscn"]:
			await compare_set(scene, "before" if scene.contains("melee_lab") else "after")
	if which in ["stills", "all"]:
		await stills()
	if which in ["clips", "all"]:
		await clips()
	if which == "hero":
		await hero(renderer)
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print(JSON.stringify({"suite": "visual_showcase_capture", "summary": true, "images": manifest.size(), "failed": failed,
		"renderer": renderer, "adapter": RenderingServer.get_video_adapter_name()}))
	quit(0 if failed == 0 else 1)

# --- Harness --------------------------------------------------------------------------

func open(scene: String) -> void:
	if arena != null:
		arena.queue_free()
		await process_frame
	arena = load(scene).instantiate()
	arena.manual_step = true
	root.add_child(arena)
	await process_frame
	await process_frame
	arena.hud.visible = false
	if arena.get("legend") != null:
		arena.legend.visible = false
	observer = Camera3D.new()
	observer.fov = 45.0
	observer.near = 0.05
	arena.add_child(observer)
	observer.current = true

func step(ticks: int, each := Callable()) -> void:
	for i in range(ticks):
		if each.is_valid():
			each.call(i)
		arena.advance(DT)
		await process_frame

func aim(from: Vector3, at: Vector3, fov := 45.0) -> void:
	observer.fov = fov
	observer.look_at_from_position(from, at)

func save(name: String, note: String) -> void:
	await process_frame
	await process_frame
	var path := output.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	manifest.append({"image": name + ".png", "note": note, "renderer": RenderingServer.get_current_rendering_method()})

func expect(ok: bool, label: String) -> void:
	if not ok:
		failed += 1
		print(JSON.stringify({"capture_check": label, "passed": false}))

func reset(player_loadout: String, opponent_loadout: String) -> void:
	if arena.has_method("select") and player_loadout.begins_with("showcase"):
		arena.set_loadouts(player_loadout, opponent_loadout)
	else:
		arena.set_loadouts(player_loadout, opponent_loadout)
	arena.opponent.mode = "dummy"
	arena.opponent.dummy_guard = ""

func side_camera() -> void:
	var mid: Vector3 = (arena.player.global_position + arena.opponent.global_position) * 0.5
	aim(mid + Vector3(3.6, 1.55, 0.2), mid + Vector3(0.0, 1.1, 0.0), 50.0)

# --- Before / after ---------------------------------------------------------------------

## The same scripted moments, loadouts and camera in the melee lab (before) and the
## showcase (after). Lab overlays are at each scene's default.
func compare_set(scene: String, tag: String) -> void:
	await open(scene)
	reset("balanced", "balanced")
	await step(30)
	side_camera()
	await save("compare_%s_1_faceoff" % tag, "Idle face-off, sword + mail vs sword + mail (%s)" % tag)
	arena.player.state.press_attack("right_to_left")
	await step(45)
	side_camera()
	await save("compare_%s_2_chamber_right" % tag, "Player holds a right chamber (%s)" % tag)
	arena.player.state.aim_attack("left_to_right")
	await step(40)
	side_camera()
	await save("compare_%s_3_rechamber_left" % tag, "Redirected to the left chamber through neutral (%s)" % tag)
	arena.player.state.release_attack()
	var swinging := func(i: int) -> void: pass
	await step(4)
	while arena.player.state.phase == State.Phase.WINDUP:
		await step(1)
	await step(3)
	side_camera()
	await save("compare_%s_4_swing" % tag, "Mid swing, left to right (%s)" % tag)
	await step(40)
	arena.opponent.dummy_guard = "high"
	arena.player.state.set_guard(true, "left")
	await step(40)
	side_camera()
	await save("compare_%s_5_guards" % tag, "Player guards left, soul guards high (%s)" % tag)
	arena.player.state.set_guard(false)
	await step(20)
	arena.player.try_roll(Vector3.RIGHT)
	await step(14)
	side_camera()
	await save("compare_%s_6_roll" % tag, "Dodge roll, mid tumble (%s)" % tag)
	await step(50)
	arena.opponent.dummy_guard = ""
	arena.reset_duel()
	arena.player.state.press_attack("overhead")
	arena.player.state.release_attack()
	var contact := -1
	for i in range(90):
		await step(1)
		if contact < 0 and not arena.events.is_empty():
			contact = i
			await step(4)
			side_camera()
			await save("compare_%s_7_hit" % tag, "Overhead hit lands: hit reaction (%s)" % tag)
			break
	expect(contact >= 0, "compare_hit_contact_" + tag)
	# Player-view camera (the game camera) for the same face-off.
	arena.reset_duel()
	await step(30)
	arena.player.camera.current = true
	await save("compare_%s_8_player_view" % tag, "Gameplay camera (%s)" % tag)
	observer.current = true

# --- Stills -----------------------------------------------------------------------------

func stills() -> void:
	await open("res://scenes/visual_showcase.tscn")
	reset("showcase.medium.mail", "showcase.medium.cloth.marrow")
	await step(40)
	aim(Vector3(2.4, 2.5, 7.3), Vector3(-0.5, 1.4, -2.0), 60.0)
	await save("crypt_wide_entrance", "Crypt from the entrance arch")
	aim(Vector3(-6.0, 1.6, -7.5), Vector3(1.5, 1.2, 1.0), 60.0)
	await save("crypt_wide_dais", "Crypt from beside the dais toward the entrance")
	aim(Vector3(0.0, 6.8, 5.5), Vector3(0.0, 0.0, -1.5), 60.0)
	await save("crypt_high", "High angle over the duel floor")
	aim(Vector3(-2.4, 1.0, -6.5), Vector3(0.0, 0.7, -10.6), 55.0)
	await save("crypt_detail_dais", "Detail: dais, sarcophagus, braziers, candles, ossuary niches")
	aim(Vector3(5.6, 1.4, -0.5), Vector3(7.8, 2.2, -2.0), 55.0)
	await save("crypt_detail_niche", "Detail: ossuary niche and weathered wall")
	# Characters: one configuration per row, three angles each.
	var configs := [["pilgrim_cloth", {"weapon": "light", "armor": "cloth"}], ["pilgrim_mail", {"weapon": "medium", "armor": "mail"}],
		["pilgrim_plate", {"weapon": "heavy", "armor": "plate"}]]
	for config: Array in configs:
		arena.select("player", config[1])
		await step(40)
		var p: Vector3 = arena.player.global_position
		var f: Vector3 = arena.player.facing
		var r := f.cross(Vector3.UP)
		aim(p + f * 2.4 + r * 0.9 + Vector3(0, 1.25, 0), p + Vector3(0, 1.0, 0), 42.0)
		await save("char_%s_front" % config[0], "Pilgrim %s: three-quarter front" % config[0].trim_prefix("pilgrim_"))
		aim(p - r * 2.5 + Vector3(0, 1.2, 0), p + Vector3(0, 1.0, 0), 42.0)
		await save("char_%s_side" % config[0], "Pilgrim %s: side" % config[0].trim_prefix("pilgrim_"))
		aim(p + f * 0.9 + r * 0.25 + Vector3(0, 1.62, 0), p + Vector3(0, 1.58, 0), 38.0)
		await save("char_%s_head" % config[0], "Pilgrim %s: head close-up" % config[0].trim_prefix("pilgrim_"))
	for config: Array in [["soul_marrow", {"weapon": "medium", "armor": "cloth", "marrow_arm": true}],
			["soul_plate", {"weapon": "light", "armor": "plate", "marrow_arm": true}], ["soul_mail_no_arm", {"weapon": "heavy", "armor": "mail", "marrow_arm": false}]]:
		arena.select("opponent", config[1])
		await step(40)
		var o: Vector3 = arena.opponent.global_position
		var f: Vector3 = arena.opponent.facing
		var r := f.cross(Vector3.UP)
		aim(o + f * 2.5 - r * 0.9 + Vector3(0, 1.3, 0), o + Vector3(0, 1.05, 0), 42.0)
		await save("char_%s_front" % config[0], "Corrupted soul (%s): three-quarter front" % config[0])
		aim(o + f * 0.95 - r * 0.2 + Vector3(0, 1.72, 0), o + Vector3(0, 1.66, 0), 38.0)
		await save("char_%s_head" % config[0], "Corrupted soul (%s): head close-up" % config[0])
	# Weapons in hand with the contact segment overlay (F3): blade and segment coincide.
	arena.select("opponent", {"weapon": "medium", "armor": "cloth", "marrow_arm": true})
	for weapon: String in ["light", "medium", "heavy"]:
		arena.select("player", {"weapon": weapon, "armor": "mail"})
		await step(10)
		arena.player.state.press_attack("right_to_left")
		await step(50)
		arena.flags.debug = true
		await step(1)
		var p: Vector3 = arena.player.global_position
		var f: Vector3 = arena.player.facing
		var r := f.cross(Vector3.UP)
		aim(p + f * 1.6 + r * 1.9 + Vector3(0, 1.7, 0), p + r * 0.4 + Vector3(0, 1.3, 0), 50.0)
		await save("weapon_%s_chamber_segment" % weapon, "%s weapon held at a right chamber; F3 overlay draws the rules contact segment (hand to tip) over the blade" % weapon.capitalize())
		aim(p + f * 0.55 + r * 0.75 + Vector3(0, 1.45, 0), p + r * 0.5 + Vector3(0, 1.32, 0), 40.0)
		await save("weapon_%s_grip_closeup" % weapon, "%s weapon: fist on the grip, segment overlay" % weapon.capitalize())
		arena.flags.debug = false
		arena.player.state.set_guard(true, "high")
		await step(30)
		arena.player.state.set_guard(false)
		await step(30)

## A handful of identical shots to compare renderers (Compatibility vs Forward+).
func hero(renderer: String) -> void:
	await open("res://scenes/visual_showcase.tscn")
	reset("showcase.medium.mail", "showcase.medium.cloth.marrow")
	await step(40)
	aim(Vector3(2.4, 2.5, 7.3), Vector3(-0.5, 1.4, -2.0), 60.0)
	await save("hero_crypt_wide_%s" % renderer, "Crypt from the entrance arch (%s)" % renderer)
	aim(Vector3(-2.4, 1.0, -6.5), Vector3(0.0, 0.7, -10.6), 55.0)
	await save("hero_dais_%s" % renderer, "Dais detail (%s)" % renderer)
	side_camera()
	await save("hero_faceoff_%s" % renderer, "Face-off, side camera (%s)" % renderer)
	arena.player.state.press_attack("overhead")
	await step(40)
	arena.player.state.release_attack()
	while arena.player.state.phase == State.Phase.WINDUP:
		await step(1)
	await step(3)
	side_camera()
	await save("hero_swing_%s" % renderer, "Overhead swing (%s)" % renderer)
	await step(60)
	var o: Vector3 = arena.opponent.global_position
	var f: Vector3 = arena.opponent.facing
	aim(o + f * 2.5 - f.cross(Vector3.UP) * 0.9 + Vector3(0, 1.3, 0), o + Vector3(0, 1.05, 0), 42.0)
	await save("hero_soul_%s" % renderer, "Corrupted soul with the Marrow Arm (%s)" % renderer)

# --- Clips --------------------------------------------------------------------------------

func clip(name: String, ticks: int, script: Callable, camera: Callable, every := 2) -> void:
	var folder := output.path_join("clip_" + name)
	DirAccess.make_dir_recursive_absolute(folder)
	camera.call(0)
	await process_frame
	var frame := 0
	for i in range(ticks):
		script.call(i)
		arena.advance(DT)
		await process_frame
		if i % every == 0:
			camera.call(i)
			root.get_texture().get_image().save_png(folder.path_join("frame_%04d.png" % frame))
			frame += 1
	manifest.append({"clip": name, "frames": frame})

func clips() -> void:
	await open("res://scenes/visual_showcase.tscn")
	reset("showcase.medium.mail", "showcase.medium.cloth.marrow")
	await step(30)
	# 1. Held chamber, flick across through the forward neutral, release.
	await clip("chamber_switch", 200, func(i: int) -> void:
		if i == 10:
			arena.player.state.press_attack("right_to_left")
		if i == 70:
			arena.player.state.aim_attack("left_to_right")
		if i == 120:
			arena.player.state.aim_attack("overhead")
		if i == 160:
			arena.player.state.release_attack(), func(_i: int) -> void: side_camera())
	# 2. Soul attacks; the player raises a fresh guard on the arriving side: deflection.
	arena.reset_duel()
	arena.opponent.mode = "dummy"
	arena.player.reset_at(Vector3(0.0, 0.02, 1.4), Vector3(0.0, 0.0, -1.0))
	var deflected := [false]
	await clip("guard_deflect", 150, func(i: int) -> void:
		if i == 10:
			arena.opponent.state.press_attack("right_to_left")
			arena.opponent.state.release_attack()
		if i == 10:
			arena.player.state.set_guard(true, "left")
			arena.player.state.guard_age = 99.0
		var s: State = arena.opponent.state
		if s.phase == State.Phase.SWING and s.live_value > -0.6 and not deflected[0]:
			arena.player.state.set_guard(false)
			arena.player.state.set_guard(true, "left")
			deflected[0] = true
		if i == 120:
			arena.player.state.set_guard(false), func(_i: int) -> void: side_camera())
	expect(arena.events.any(func(e: Dictionary) -> bool: return e.result in ["deflect", "block"]), "clip_guard_deflect_contact")
	# 3. Weapon mass: the same overhead with the knife, then the greatsword.
	for weapon: String in ["light", "heavy"]:
		arena.select("player", {"weapon": weapon, "armor": "mail"})
		arena.opponent.mode = "dummy"
		arena.opponent.dummy_guard = "high"
		await step(20)
		await clip("weapon_mass_" + weapon, 110, func(i: int) -> void:
			if i == 5:
				arena.player.state.press_attack("overhead")
			if i == 6:
				arena.player.state.release_attack(), func(_i: int) -> void: side_camera())
	# 4. Dodge step and roll.
	arena.select("player", {"weapon": "medium", "armor": "mail"})
	arena.opponent.dummy_guard = ""
	await step(20)
	await clip("dodge_and_roll", 150, func(i: int) -> void:
		if i == 10:
			arena.player.try_dodge(Vector3.RIGHT)
		if i == 70:
			arena.player.try_roll(Vector3.LEFT), func(_i: int) -> void:
			var p: Vector3 = arena.player.global_position
			aim(p + Vector3(0.5, 1.6, 4.2), p + Vector3(0, 0.9, 0), 55.0))
	# 5. Heavy overhead breaks a light guard (posture), then a follow-up hit.
	arena.select("player", {"weapon": "heavy", "armor": "plate"})
	arena.select("opponent", {"weapon": "light", "armor": "cloth", "marrow_arm": true})
	arena.opponent.mode = "dummy"
	arena.opponent.dummy_guard = "high"
	await step(20)
	await clip("guard_break_and_hit", 220, func(i: int) -> void:
		if i == 5:
			arena.player.state.press_attack("overhead")
			arena.player.state.release_attack()
		if i == 100:
			arena.opponent.dummy_guard = ""
			arena.opponent.state.set_guard(false)
			arena.player.state.press_attack("right_to_left")
			arena.player.state.release_attack(), func(_i: int) -> void: side_camera())
	expect(arena.events.any(func(e: Dictionary) -> bool: return e.result == "guard_break"), "clip_guard_break_contact")
	# 6. Release: the final blow, the soul falls and its light leaves it.
	arena.select("player", {"weapon": "medium", "armor": "mail"})
	arena.opponent.dummy_guard = ""
	await step(20)
	arena.opponent.state.health = 5.0
	await clip("death_release", 200, func(i: int) -> void:
		if i == 5:
			arena.player.state.press_attack("diag_right")
			arena.player.state.release_attack(), func(_i: int) -> void:
			var o: Vector3 = arena.opponent.global_position
			aim(o + Vector3(3.0, 1.5, 1.6), o + Vector3(0, 0.6, 0), 50.0))
	expect(arena.opponent.state.phase == State.Phase.DEAD, "clip_release_soul_dead")
	# 7. A seeded AI duel seen from the gameplay camera (soul in duel mode, player bot).
	arena.select("opponent", {"weapon": "medium", "armor": "cloth", "marrow_arm": true})
	arena.reset_duel()
	arena.opponent.mode = "duel"
	arena.opponent.reset_ai()
	await clip("duel_player_camera", 360, func(i: int) -> void:
		var s: State = arena.player.state
		if i % 90 == 20:
			s.press_attack(["right_to_left", "overhead", "left_to_right", "diag_right"][(i / 90) % 4])
		if i % 90 == 45:
			s.release_attack()
		var foe: State = arena.opponent.state
		if foe.phase == State.Phase.WINDUP and s.phase == State.Phase.IDLE and not s.guarding:
			s.set_guard(true, {"right_to_left": "left", "left_to_right": "right", "overhead": "high", "diag_right": "high_left", "diag_left": "high_right", "thrust": "center"}.get(foe.direction, "high"))
		elif foe.phase not in [State.Phase.WINDUP, State.Phase.SWING] and s.guarding:
			s.set_guard(false), func(_i: int) -> void: arena.player.camera.current = true)
	observer.current = true
