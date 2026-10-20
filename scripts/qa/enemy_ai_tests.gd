extends SceneTree
## Survival-AI checks for the corrupted swordsman. Drives the real courtyard scenes
## with legal player InputEvents (as adversarial_probe.gd does) against scripted
## player styles, then asserts behavior, variety and fairness bounds and writes the
## enemy's deterministic decision traces as evidence. Scripted styles prove reachable
## behavior and bounds; they say nothing about whether combat feels good.
## --negative=omniscient gives the AI zero reaction delay; --negative=spam removes the
## repetition limits. Each must fail its named checks.
## Run: bash scripts/tooling/test_enemy_ai.sh [new-empty-dir]

const Rules = preload("res://scripts/combat/combat_state.gd")
const Perception = preload("res://scripts/ai/opponent_perception.gd")
const SEED := 20261020
var arena: Node3D
var scene_name := ""
var p: Fighter
var e: Fighter
var output := "res://artifacts/enemy-ai"
var negative := ""
var held := {}
var passed := 0
var failed := 0
var results := {}
## Optional per-tick observer (rendered capture); called after each stepped tick.
var tick_hook := Callable()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			output = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--negative="):
			negative = arg.trim_prefix("--negative=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = null) -> void:
	passed += int(ok)
	failed += int(not ok)
	var record := {"check": label, "passed": ok}
	if detail != null:
		record.detail = detail
	print(JSON.stringify(record))

# --- Harness -------------------------------------------------------------------

func load_arena(scene: String) -> void:
	if is_instance_valid(arena):
		release_all()
		await step(1)
		arena.free()
	scene_name = scene
	arena = load("res://scenes/%s.tscn" % scene).instantiate()
	root.add_child(arena)
	p = arena.player
	e = arena.enemy
	await step(3)

func press(action: String, pressed := true) -> void:
	if held.get(action, false) == pressed:
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	held[action] = pressed

func release_all() -> void:
	for action: String in held:
		if held[action]:
			press(action, false)

func step(count := 1) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func configure(seed: int) -> void:
	# Restore shipped tuning before each duel; negatives then change only their knobs.
	var shipped: Fighter = load("res://scripts/ai/swordsman.gd").new()
	for knob: String in ["reaction_delay", "hesitation", "max_evade_streak", "repeat_penalty"]:
		e.set(knob, shipped.get(knob))
	shipped.free()
	e.ai_seed = seed
	if negative == "omniscient":
		e.reaction_delay = 0.0
		e.hesitation = 0.0
	elif negative == "spam":
		e.max_evade_streak = 1000
		e.repeat_penalty = 1.0

func fresh(distance: float, seed: int, enemy_z := 0.0) -> void:
	release_all()
	await step(2)
	configure(seed)
	arena.reset_encounter()
	p.input_enabled = true
	e.enabled = true
	p.position = Vector3(0.0, 0.02, enemy_z + distance)
	e.position = Vector3(0.0, 0.02, enemy_z)
	p.facing = Vector3.FORWARD
	e.facing = Vector3.BACK
	p.yaw = 0.0
	p.locked = true

## Plays one duel with legal input. `policy` is called each tick with the frame.
func duel(label: String, policy: Callable, limit := 2400, distance := 1.85, seed := SEED, save := true, enemy_z := 0.0) -> Dictionary:
	await fresh(distance, seed, enemy_z)
	var frame := 0
	var stats := {"label": label, "seed": seed, "scene": scene_name, "enemy_windups": 0, "enemy_guard_ticks": 0,
		"enemy_dodges": 0, "answers": {}, "max_consecutive_answer": {}, "counters": 0, "player_swings": 0,
		"player_swings_cancelled": 0, "events": {}, "min_distance": 99.0, "max_distance": 0.0, "intents": {}}
	var ticks: Array = [] # Per-tick enemy behavior, for exact divergence comparisons.
	var onsets: Array = [] # Enemy tick at which each player windup began, and whether it struck.
	var guard_raises := 0
	var was_guarding := false
	var last_e: int = Rules.Phase.IDLE
	var last_p: int = Rules.Phase.IDLE
	var seen := {"player": 0, "enemy": 0}
	while frame < limit and e.combat.phase != Rules.Phase.DEAD and p.combat.phase != Rules.Phase.DEAD:
		policy.call(frame)
		await step(1)
		frame += 1
		var ep: int = e.combat.phase
		var pp: int = p.combat.phase
		if ep != last_e:
			stats.enemy_windups += int(ep == Rules.Phase.WINDUP)
			stats.enemy_dodges += int(ep == Rules.Phase.DODGE)
			last_e = ep
		if pp != last_p:
			if pp == Rules.Phase.WINDUP:
				stats.player_swings += 1
				onsets.append({"tick": e.tick_count, "active": false, "distance": snappedf(p.position.distance_to(e.position), 0.01)})
			elif pp == Rules.Phase.ACTIVE and not onsets.is_empty():
				onsets[-1].active = true
			elif last_p == Rules.Phase.WINDUP and pp == Rules.Phase.IDLE:
				stats.player_swings_cancelled += 1
			last_p = pp
		guard_raises += int(e.combat.guarding and not was_guarding)
		was_guarding = e.combat.guarding
		stats.enemy_guard_ticks += int(e.combat.guarding)
		for pair: Array in [[p, "player"], [e, "enemy"]]:
			var actor: Fighter = pair[0]
			if actor.event_serial > seen[pair[1]]:
				var key: String = pair[1] + "_" + actor.last_result
				stats.events[key] = stats.events.get(key, 0) + 1
			seen[pair[1]] = actor.event_serial
		var d := p.position.distance_to(e.position)
		stats.min_distance = minf(stats.min_distance, d)
		stats.max_distance = maxf(stats.max_distance, d)
		stats.intents[e.ai_state] = stats.intents.get(e.ai_state, 0) + 1
		ticks.append([e.tick_count, e.ai_state, e.combat.phase, e.combat.guarding, snappedf(e.position.x, 0.0001), snappedf(e.position.z, 0.0001)])
		if tick_hook.is_valid():
			await tick_hook.call()
	release_all()
	stats.frames = frame
	stats.winner = "player" if e.combat.phase == Rules.Phase.DEAD else ("enemy" if p.combat.phase == Rules.Phase.DEAD else "timeout")
	stats.player_health = p.combat.health
	stats.enemy_health = e.combat.health
	stats.min_distance = snappedf(stats.min_distance, 0.01)
	stats.max_distance = snappedf(stats.max_distance, 0.01)
	stats.guard_raises = guard_raises
	var streak := 0
	var previous := ""
	for entry: Dictionary in e.trace:
		var kind: String = entry.decision
		if kind.begins_with("answer_"):
			var answer := kind.trim_prefix("answer_")
			stats.answers[answer] = stats.answers.get(answer, 0) + 1
			streak = streak + 1 if answer == previous else 1
			previous = answer
			stats.max_consecutive_answer[answer] = maxi(stats.max_consecutive_answer.get(answer, 0), streak)
		stats.counters += int(kind == "attack_counter")
	stats.trace = e.trace.duplicate(true)
	stats.ticks = ticks
	stats.onsets = onsets
	if save:
		save_json("trace_%s.json" % label, stats.trace)
		var summary := stats.duplicate(true)
		for bulky: String in ["trace", "ticks", "onsets"]:
			summary.erase(bulky)
		print(JSON.stringify({"duel": summary}))
		results[label] = summary
	return stats

func save_json(name: String, value: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t") + "\n")

func decisions(stats: Dictionary, prefix: String) -> Array:
	return stats.trace.filter(func(entry: Dictionary) -> bool: return String(entry.decision).begins_with(prefix))

func distance_now() -> float:
	return p.position.distance_to(e.position)

func mash(action: String, frame: int, period := 2) -> void:
	press(action, frame % period == 0)

func chase(distance: float) -> void:
	press("move_forward", distance_now() > distance)

# --- Player styles --------------------------------------------------------------

func masher(frame: int) -> void:
	mash("attack", frame, 2)

func aggressive(frame: int) -> void:
	chase(1.6)
	mash("attack", frame, 5)

func guarding(_frame: int) -> void:
	chase(1.8)
	press("guard", true)

func passive(_frame: int) -> void:
	pass

func retreating(_frame: int) -> void:
	# Kite: stay just outside sword reach, stepping back whenever the enemy closes.
	var d := distance_now()
	press("move_back", d < 2.9)
	press("move_forward", d > 3.6)

func skilled(_frame: int) -> void:
	var ec: Rules = e.combat
	var defend: bool = ec.phase == Rules.Phase.WINDUP and ec.remaining < 0.12 and p.combat.phase == Rules.Phase.IDLE
	press("guard", defend)
	var punish: bool = p.combat.phase == Rules.Phase.IDLE and not defend and ec.phase in [Rules.Phase.BROKEN, Rules.Phase.RECOVERY, Rules.Phase.STAGGER]
	press("attack", punish)
	chase(2.0)

func spacer(frame: int) -> void:
	# Hit and run: close to the edge of reach, swing once, then back away.
	var t := frame % 100
	press("move_forward", t < 45 and distance_now() > 2.25)
	press("attack", t == 45)
	press("move_back", t >= 50 and t < 90)

func feinter(frame: int) -> void:
	# Start a swing, then cancel it with a fresh guard press before contact.
	var t := frame % 70
	chase(1.9)
	press("attack", t == 0)
	press("guard", t >= 10 and t < 30)

func far_swinger(frame: int) -> void:
	# Swings in the air from well outside reach; nothing here threatens the enemy.
	var d := distance_now()
	press("move_back", d < 5.0)
	press("move_forward", d > 6.0)
	mash("attack", frame, 24)

func onset_probe(frame: int) -> void:
	press("attack", frame == 150)

# --- Checks ---------------------------------------------------------------------

func run() -> void:
	await load_arena("courtyard")
	var runs := {}
	for item: Array in [["masher", masher], ["aggressive", aggressive], ["guarding", guarding],
			["passive", passive], ["retreating", retreating], ["skilled", skilled], ["spacer", spacer],
			["feinter", feinter], ["far_swinger", far_swinger]]:
		if item[0] == "far_swinger":
			# Start deep in the courtyard so the player has room to keep backing away.
			runs[item[0]] = await duel(item[0], item[1], 360, 6.0, SEED, true, -10.0)
		else:
			runs[item[0]] = await duel(item[0], item[1])
	style_checks(runs)
	fairness_checks(runs)
	variety_checks(runs)
	await omniscience_checks()
	await determinism_checks()
	await load_arena("salvage_courtyard")
	await reach_checks()
	save_json("results.json", results)
	release_all()
	await step(1)
	arena.free()
	print(JSON.stringify({"suite": "enemy_ai", "summary": true, "passed": passed, "failed": failed, "negative": negative, "engine": Engine.get_version_info().string}))
	quit(1 if failed else 0)

func style_checks(runs: Dictionary) -> void:
	var masher_run: Dictionary = runs.masher
	check(masher_run.winner == "enemy" and masher_run.counters >= 2, "punishes_attack_mashing_with_counters", {"winner": masher_run.winner, "counters": masher_run.counters})
	var aggressive_run: Dictionary = runs.aggressive
	check(aggressive_run.winner == "enemy" and aggressive_run.answers.size() >= 2, "survives_chasing_aggression_with_mixed_answers", {"winner": aggressive_run.winner, "answers": aggressive_run.answers})
	var block_counters := decisions(aggressive_run, "counter_take").filter(func(entry: Dictionary) -> bool: return entry.reason == "blocked")
	check(not block_counters.is_empty(), "counterattacks_after_successful_block")
	var guard_run: Dictionary = runs.guarding
	var heavies := decisions(guard_run, "attack_heavy").size()
	check(guard_run.winner == "enemy" and heavies >= 1 and guard_run.enemy_guard_ticks == 0, "pressures_turtle_with_heavy_and_breaks_it", {"heavies": heavies, "punish": guard_run.events.get("player_punish", 0)})
	var broken_counters := decisions(guard_run, "counter_take").filter(func(entry: Dictionary) -> bool: return entry.reason == "broken")
	check(not broken_counters.is_empty() and broken_counters.all(func(entry: Dictionary) -> bool: return entry.heavy), "punishes_posture_break_with_heavy")
	var passive_run: Dictionary = runs.passive
	check(passive_run.winner == "enemy" and passive_run.answers.is_empty() and passive_run.enemy_dodges == 0 and passive_run.enemy_guard_ticks == 0, "no_phantom_defense_against_passive_player")
	check(passive_run.intents.get("CIRCLE", 0) > 60, "circles_between_attacks_instead_of_standing", passive_run.intents)
	var retreat_run: Dictionary = runs.retreating
	check(retreat_run.enemy_windups >= 3 and retreat_run.min_distance <= 2.0, "reengages_a_kiting_player", {"windups": retreat_run.enemy_windups, "min_distance": retreat_run.min_distance})
	var skilled_run: Dictionary = runs.skilled
	check(skilled_run.winner == "player" and skilled_run.player_health == 100.0, "remains_beatable_by_skilled_legal_play", {"winner": skilled_run.winner, "player_health": skilled_run.player_health})
	var spacer_run: Dictionary = runs.spacer
	var whiffs := decisions(spacer_run, "counter_").filter(func(entry: Dictionary) -> bool: return entry.get("reason", "") == "whiff")
	check(spacer_run.answers.get("backstep", 0) + spacer_run.answers.get("evade", 0) >= 2 and not whiffs.is_empty(), "spaces_out_of_reach_and_reads_whiffs", {"answers": spacer_run.answers, "whiff_offers": whiffs.size()})
	var intercepts := decisions(spacer_run, "attack_intercept")
	check(spacer_run.winner == "enemy" and not intercepts.is_empty(), "intercepts_a_player_walking_into_reach", {"winner": spacer_run.winner, "intercepts": intercepts.size()})
	var far_run: Dictionary = runs.far_swinger
	check(far_run.player_swings >= 5 and far_run.answers.is_empty() and far_run.enemy_dodges == 0, "ignores_swings_from_out_of_reach",
		{"swings": far_run.player_swings, "closest_swing_m": far_run.onsets.reduce(func(m: float, o: Dictionary) -> float: return minf(m, o.distance), 99.0)})
	# Survival movement: posture strain leads to a bounded retreat that always ends.
	var retreats := 0
	var bounded := true
	for run: Dictionary in runs.values():
		var started := -1.0
		for entry: Dictionary in run.trace:
			if entry.decision == "retreat":
				retreats += 1
				started = entry.t
			elif entry.decision == "reengage" and started >= 0.0:
				bounded = bounded and entry.t - started <= e.retreat_limit + 0.05
				started = -1.0
		if started >= 0.0:
			bounded = bounded and run.frames / 60.0 - started <= e.retreat_limit + 0.1
	check(retreats >= 1 and bounded, "posture_strain_retreats_are_bounded_and_reengage", {"retreats": retreats})

func fairness_checks(runs: Dictionary) -> void:
	# Each perceived swing gets at most one committed answer, never before the
	# reaction delay has elapsed since the windup began.
	var earliest := 999
	var single := true
	var dodge_committed := true
	for run: Dictionary in runs.values():
		var answered := {}
		var evade_swings := {}
		for entry: Dictionary in run.trace:
			var kind: String = entry.decision
			if kind.begins_with("answer_"):
				single = single and not answered.has(entry.swing)
				answered[entry.swing] = true
				if kind == "answer_evade":
					evade_swings[entry.swing] = true
				var onset := -1
				for item: Dictionary in run.onsets:
					if item.tick <= entry.tick:
						onset = item.tick
				if onset >= 0:
					earliest = mini(earliest, entry.tick - onset)
			if kind == "dodge":
				dodge_committed = dodge_committed and evade_swings.has(entry.swing)
	check(earliest >= 11 and earliest < 999, "answers_wait_for_reaction_delay", {"earliest_ticks_after_onset": earliest, "required": 11})
	check(single, "one_committed_answer_per_perceived_swing")
	check(dodge_committed, "every_dodge_follows_a_committed_evade_answer")
	# A feint can bait a committed dodge: the AI reads visible windups and cannot
	# know whether the swing will be completed.
	var feint_run: Dictionary = runs.feinter
	var baited := 0
	for entry: Dictionary in feint_run.trace:
		if entry.decision == "dodge" and entry.swing <= feint_run.onsets.size() and not feint_run.onsets[entry.swing - 1].active:
			baited += 1
	check(feint_run.player_swings_cancelled >= 10 and baited >= 1, "feints_can_bait_committed_dodges", {"cancelled": feint_run.player_swings_cancelled, "baited_dodges": baited})

func variety_checks(runs: Dictionary) -> void:
	var longest := 0
	var evade_streak := 0
	var dodges := 0
	var swings := 0
	var counters_without_opening := 0
	for run: Dictionary in runs.values():
		for answer: String in run.max_consecutive_answer:
			longest = maxi(longest, run.max_consecutive_answer[answer])
		evade_streak = maxi(evade_streak, run.max_consecutive_answer.get("evade", 0))
		dodges += run.enemy_dodges
		swings += run.player_swings
		var opened := -99.0
		for entry: Dictionary in run.trace:
			if entry.decision == "counter_take":
				opened = entry.t
			elif entry.decision == "attack_counter":
				counters_without_opening += int(entry.t - opened > e.counter_window + 0.001)
	check(longest <= 3, "no_answer_repeats_more_than_three_times", {"longest": longest})
	check(evade_streak <= 2, "dodge_streak_capped", {"longest_evade_streak": evade_streak})
	check(dodges <= swings * 0.5, "dodges_stay_a_minority_answer", {"dodges": dodges, "player_swings": swings})
	check(counters_without_opening == 0, "counters_only_follow_openings")
	var masher_run: Dictionary = runs.masher
	check(masher_run.answers.size() >= 2 and masher_run.guard_raises <= masher_run.player_swings, "flurry_answers_vary_without_guard_toggling", {"answers": masher_run.answers, "guard_raises": masher_run.guard_raises, "swings": masher_run.player_swings})

func omniscience_checks() -> void:
	# Identical duels except that the player presses attack once at frame 150. Until
	# the reaction delay has passed, the enemy must behave identically tick for tick.
	var base := await duel("onset_control", passive, 260, 1.85, SEED, false)
	var probe := await duel("onset_probe", onset_probe, 260, 1.85, SEED, false)
	var onset: int = probe.onsets[0].tick if not probe.onsets.is_empty() else -1
	var diverged := -1
	for i in range(mini(base.ticks.size(), probe.ticks.size())):
		if base.ticks[i] != probe.ticks[i]:
			diverged = base.ticks[i][0]
			break
	check(onset > 0 and diverged >= onset + 11, "enemy_unchanged_until_windup_is_visible", {"onset_tick": onset, "first_divergent_tick": diverged})
	# The snapshot schema is the whole perception surface; the controller cannot reach input.
	var keys: Array = Perception.capture(p, 0.0).keys()
	keys.sort()
	var expected: Array = Perception.FIELDS.duplicate()
	expected.sort()
	check(keys == expected, "perception_snapshot_is_whitelisted", keys)
	var leaks := []
	for path: String in ["res://scripts/ai/swordsman.gd", "res://scripts/ai/opponent_perception.gd"]:
		# Scan code only; the doc comments name what is deliberately excluded.
		var source := "\n".join(Array(FileAccess.get_file_as_string(path).split("\n")).map(func(line: String) -> String: return line.get_slice("#", 0)))
		for token: String in ["Input.", "InputMap", "opponent.desired_move", "hit_consumed", "opponent.cooldown", "opponent.combat.guard_age", "opponent.combat.deflect_ready_in"]:
			if token in source:
				leaks.append(path.get_file() + ":" + token)
	check(leaks.is_empty(), "controller_reads_no_input_or_hidden_state", leaks)

func determinism_checks() -> void:
	# Each replay starts from a freshly loaded scene, so no physics contact state
	# carries over from an earlier duel.
	await load_arena("courtyard")
	var first := await duel("replay_a", spacer, 1200, 1.85, SEED, false)
	await load_arena("courtyard")
	var second := await duel("replay_b", spacer, 1200, 1.85, SEED, false)
	# Decisions and per-tick states must match exactly. Positions get 1 cm: wall
	# contact in move_and_slide has shown ~0.1 mm run-to-run jitter in one process.
	var same_states: bool = first.ticks.size() == second.ticks.size()
	var drift := 0.0
	for i in range(mini(first.ticks.size(), second.ticks.size())):
		same_states = same_states and first.ticks[i].slice(0, 4) == second.ticks[i].slice(0, 4)
		drift = maxf(drift, Vector2(first.ticks[i][4] - second.ticks[i][4], first.ticks[i][5] - second.ticks[i][5]).length())
	check(JSON.stringify(first.trace) == JSON.stringify(second.trace) and same_states and drift < 0.01, "same_seed_replays_identical_decisions",
		{"decisions": first.trace.size(), "ticks": first.ticks.size(), "max_position_drift_m": snappedf(drift, 0.00001)})
	await load_arena("courtyard")
	var other := await duel("replay_seed_2", spacer, 1200, 1.85, SEED + 1, false)
	check(JSON.stringify(first.trace) != JSON.stringify(other.trace), "different_seed_changes_decisions")
	save_json("replay_trace_seed_%d.json" % SEED, first.trace)
	save_json("replay_trace_seed_%d.json" % (SEED + 1), other.trace)

func reach_checks() -> void:
	# With the Marrow Arm, a player holding just outside sword reach meets the lunge.
	var run := await duel("lunge_vs_kiting", retreating, 2400, 3.2)
	var lunges := decisions(run, "lunge_take").size()
	check(lunges >= 1, "uses_lunge_reach_against_kiting_player", {"lunge_takes": lunges, "skips": decisions(run, "lunge_skip").size()})
