extends SceneTree
## Input-driven playthrough of the shipped scene. No fixture positioning, health,
## reward, AI-disable or combat-state writes. The bot reads timing to choose ordinary
## keyboard/mouse events; this proves reachability, not human skill or game feel.
const Playable = preload("res://scenes/salvage_courtyard.tscn")
const Rules = preload("res://scripts/combat/combat_state.gd")
const Look = preload("res://scripts/characters/presentation/equipment_look.gd")
var arena: Node3D
var output := "res://artifacts/marrow-playthrough"
var held: Dictionary = {}
var trace: Array = []
var captures: Dictionary = {}
var tick := 0
var failed := 0
var negative_visual := false
var negative_equipment := false
var sequence_frames := {"enemy": 0, "player": 0}
var lunge_observed := false
var lunge_defended := false
var inherited_started := false
var inherited_contact := false
var previous_events := {"player": 0, "enemy": 0}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg == "--negative=marrow-visual":
			negative_visual = true
		if arg == "--negative=equipment-side":
			negative_equipment = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = Playable.instantiate()
	root.add_child(arena)
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	failed += int(not condition)
	print(JSON.stringify({"check": label, "passed": condition}))

func input(action: String, pressed: bool) -> void:
	if held.get(action, false) == pressed:
		return
	held[action] = pressed
	var events := InputMap.action_get_events(action)
	var event: InputEvent = events[0].duplicate()
	if event is InputEventKey:
		event.pressed = pressed
	elif event is InputEventMouseButton:
		event.pressed = pressed
	Input.parse_input_event(event)

func frame() -> void:
	await physics_frame
	await process_frame
	tick += 1

func capture(label: String) -> void:
	if captures.has(label):
		return
	captures[label] = tick
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join(label.get_base_dir())))
	paused = true
	arena.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture_" + label)
	paused = false

func run() -> void:
	await frame()
	await capture("01_initial_duel")
	check(Look.disagreements(arena.player).is_empty() and Look.disagreements(arena.enemy).is_empty()
		and arena.enemy.marrow_pivot.position.x < 0.0 and arena.enemy.sword_pivot.position.x > 0.0, "enemy_marrow_left_sword_right_matches_build")
	input("lock_on", true)
	await frame()
	input("lock_on", false)
	for i in range(10000):
		var p: Fighter = arena.player
		var e: Fighter = arena.enemy
		var pc := p.combat
		var ec := e.combat
		var distance := p.position.distance_to(e.position)
		trace.append({"tick": tick, "time": tick / 60.0, "duel": arena.progression.duel_number,
			"stage": arena.progression.stage, "distance": distance,
			"player": state(p), "enemy": state(e), "input": held.duplicate()})
		input("attack", false)
		input("signature", false)
		input("salvage", false)
		input("equip", false)
		input("next_duel", false)
		input("lock_on", false)
		if arena.progression.stage == arena.Progression.Stage.VICTORY:
			input("guard", false)
			input("move_forward", false)
			if not arena.progression.owns("item.marrow_arm"):
				await capture("04_enemy_defeat")
				check(arena.progression.available_rewards().size() == 1, "natural_victory_unlocks_salvage")
				input("salvage", true)
			elif not arena.progression.equipped():
				await capture("05_salvage_acquired")
				check(arena.progression.builds.player.carried == ["item.marrow_arm"] and pc.signature.is_empty(), "input_salvage_is_inventory_not_equipment")
				check(not p.marrow_pivot.visible and p.free_arm.visible and Look.disagreements(p).is_empty(), "carried_marrow_not_attached")
				input("equip", true)
			elif arena.progression.duel_number == 1:
				await capture("06_augmentation_equipped")
				check(not pc.signature.is_empty() and p.marrow_pivot.visible, "input_equip_resolves_signature_and_visual")
				if negative_equipment:
					# Control: draw the bone on the wrong side without touching the build.
					p.look.marrow_side = 1.0
					p.sync_visual()
				check(arena.progression.builds.player.equipped == {"hand_r": "item.notched_sword", "arm_l": "item.marrow_arm"}
					and p.marrow_pivot.position.x < 0.0 and p.sword_pivot.position.x > 0.0 and not p.free_arm.visible
					and Look.disagreements(p).is_empty() and Look.disagreements(e).is_empty(), "equipped_marrow_left_sword_right_matches_build")
				input("next_duel", true)
			else:
				check(inherited_started and inherited_contact, "second_duel_won_with_inherited_power")
				break
		elif arena.progression.stage == arena.Progression.Stage.FALLEN:
			check(false, "bot_survives_duel_" + str(arena.progression.duel_number))
			await capture("unexpected_loss")
			break
		else:
			if not p.locked:
				input("lock_on", true)
			input("move_forward", distance > 1.65 and pc.phase == Rules.Phase.IDLE)
			var lunging := ec.is_signature() and ec.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE]
			if lunging:
				lunge_observed = true
				if ec.phase == Rules.Phase.WINDUP and ec.remaining < 0.5:
					await capture("02_enemy_lunge_telegraph")
			if p.event_serial != previous_events.player:
				if p.last_result == Rules.DEFLECTED and ec.is_signature() and not lunge_defended:
					lunge_defended = true
					await capture("03_player_defends_lunge")
				previous_events.player = p.event_serial
			# Read the visible attack timeline; one fresh guard raise near contact.
			var incoming := ec.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE] and not ec.hit_consumed
			if incoming and ec.remaining <= 0.11 and distance <= e.attack_range + 0.2:
				input("guard", true)
			elif not incoming:
				input("guard", false)
			# Retry the inherited lunge until it connects: the enemy may legally evade one.
			if arena.progression.duel_number >= 2 and not inherited_contact and pc.phase == Rules.Phase.IDLE and not incoming and distance <= 3.1:
				input("guard", false)
				input("signature", true)
				inherited_started = true
			elif pc.phase == Rules.Phase.IDLE and not incoming and ec.phase in [Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.RECOVERY] and ec.remaining > pc.attack_windup + 0.06 and distance <= 2.15:
				input("attack", true)
			if arena.progression.duel_number >= 2 and pc.is_signature():
				if pc.phase == Rules.Phase.ACTIVE:
					if negative_visual:
						p.marrow_bone.scale.z = 0.65
						p.marrow_bone.position.z = -0.325
					var rendered_tip := p.marrow_bone.to_global(Vector3(0.0, 0.0, -0.5))
					var reach := (rendered_tip - p.global_position).dot(p.facing)
					check(absf(reach - pc.signature.reach) < 0.05, "inherited_active_pose_reaches_hit_tip")
					await capture("07_first_inherited_lunge")
				if e.event_serial != previous_events.enemy and e.last_result in [Rules.HIT, Rules.GUARD, "punish", Rules.DEFEATED]:
					inherited_contact = true
			if arena.progression.duel_number >= 2 and inherited_started and pc.phase == Rules.Phase.IDLE and captures.has("07_first_inherited_lunge"):
				await capture("08_second_duel_continues")
		# A 30 fps sequence of the first signature from each wielder. Timing/pose
		# samples are recorded every physics tick, including the captured stages.
		for actor_name: String in ["enemy", "player"]:
			var actor: Fighter = arena.get(actor_name)
			if actor.combat.is_signature() and actor.combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY] and tick % 2 == 0 and sequence_frames[actor_name] < 42:
				await capture(actor_name + "-lunge/frame_%03d" % sequence_frames[actor_name])
				sequence_frames[actor_name] += 1
		previous_events.enemy = e.event_serial
		await frame()
		if i == 9999:
			check(false, "playthrough_completes_before_tick_limit")
	check(lunge_observed and lunge_defended, "enemy_signature_seen_and_defended_with_normal_input")
	check(captures.has_all(["01_initial_duel", "02_enemy_lunge_telegraph", "03_player_defends_lunge", "04_enemy_defeat", "05_salvage_acquired", "06_augmentation_equipped", "07_first_inherited_lunge", "08_second_duel_continues"]), "eight_playable_milestones_captured")
	for action: String in held.keys():
		input(action, false)
	var file := FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(trace, "\t") + "\n")
	var summary := {"summary": true, "failed": failed, "ticks": tick, "captures": captures, "engine": Engine.get_version_info().string,
		"rendered": DisplayServer.get_name() != "headless", "input": "physical keyboard and mouse InputEvents; no combat/progression writes"}
	file = FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t") + "\n")
	print(JSON.stringify(summary))
	arena.free()
	quit(1 if failed else 0)

func state(actor: Fighter) -> Dictionary:
	var c := actor.combat
	return {"health": c.health, "posture": c.posture, "phase": c.phase, "stage": c.attack_stage(),
		"binding": c.attack_binding, "remaining": c.remaining, "event": actor.last_result,
		"bone_tip": [actor.marrow_tip.global_position.x, actor.marrow_tip.global_position.y, actor.marrow_tip.global_position.z],
		"mesh_tip": _mesh_tip(actor)}

func _mesh_tip(actor: Fighter) -> Array:
	var point := actor.marrow_bone.to_global(Vector3(0.0, 0.0, -0.5))
	return [point.x, point.y, point.z]
