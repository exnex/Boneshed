extends "res://scripts/qa/enemy_ai_tests.gd"
## Rendered evidence for the survival AI. For each clip, a first pass finds the tick of
## a key decision; a second pass replays the identical duel from a fresh scene and
## saves every other frame around it from the player's own camera. A caption names
## the enemy's intent, both phases and the latest decision, so a reviewer can match
## pictures to the trace. Pictures show readability candidates, not feel.
## Run under a display: see scripts/tooling/test_enemy_ai.sh.

const CLIPS := [
	{"name": "block_then_counter", "scene": "courtyard", "style": "aggressive", "trigger": "attack_counter", "before": 40, "after": 56},
	{"name": "evade_then_reset", "scene": "courtyard", "style": "aggressive", "trigger": "dodge", "before": 18, "after": 40},
	{"name": "feint_baits_dodge", "scene": "courtyard", "style": "feinter", "trigger": "dodge", "before": 20, "after": 30},
	{"name": "turtle_break_punish", "scene": "courtyard", "style": "guarding", "trigger": "counter_take", "reason": "broken", "before": 30, "after": 60},
	{"name": "posture_retreat", "scene": "courtyard", "style": "aggressive", "trigger": "retreat", "before": 10, "after": 70},
	{"name": "backstep_out_of_reach", "scene": "courtyard", "style": "masher", "trigger": "answer_backstep", "before": 16, "after": 50},
	{"name": "whiff_read_spacing", "scene": "courtyard", "style": "spacer", "trigger": "counter_", "reason": "whiff", "before": 50, "after": 40},
	{"name": "lunge_from_range", "scene": "salvage_courtyard", "style": "retreating", "trigger": "lunge_take", "distance": 3.2, "before": 16, "after": 70},
]
var caption: Label
var clip_dir := ""
var window := Vector2i(-1, -1)
var saved := 0

func run() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24, 640)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(caption)
	var manifest := []
	for clip: Dictionary in CLIPS:
		var policy := Callable(self, clip.style)
		var distance: float = clip.get("distance", 1.85)
		await load_arena(clip.scene)
		var first := await duel(clip.name + "_find", policy, 2400, distance, SEED, false)
		var trigger := _trigger_tick(first.trace, clip)
		check(trigger > 0, "clip_trigger_found_" + clip.name, {"tick": trigger})
		if trigger <= 0:
			continue
		window = Vector2i(maxi(1, trigger - int(clip.before)), trigger + int(clip.after))
		clip_dir = output.path_join(clip.name)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(clip_dir))
		saved = 0
		await load_arena(clip.scene)
		tick_hook = _capture
		var replay := await duel(clip.name, policy, window.y + 1, distance, SEED, true)
		tick_hook = Callable()
		var replayed := _trigger_tick(replay.trace, clip)
		check(replayed == trigger and saved >= (window.y - window.x) / 2 - 1, "clip_replays_and_renders_" + clip.name, {"trigger": trigger, "replayed": replayed, "frames": saved})
		manifest.append({"clip": clip.name, "style": clip.style, "scene": clip.scene, "trigger": clip.trigger, "trigger_tick": trigger,
			"first_frame_tick": window.x, "frame_every_ticks": 2, "frames": saved})
	save_json("clips.json", manifest)
	release_all()
	await step(1)
	arena.free()
	print(JSON.stringify({"suite": "enemy_ai_capture", "summary": true, "passed": passed, "failed": failed, "rendered": DisplayServer.get_name() != "headless", "engine": Engine.get_version_info().string}))
	quit(1 if failed else 0)

func _trigger_tick(trace: Array, clip: Dictionary) -> int:
	for entry: Dictionary in trace:
		if String(entry.decision).begins_with(clip.trigger) and (not clip.has("reason") or entry.get("reason", "") == clip.reason):
			return entry.tick
	return -1

func _capture() -> void:
	var tick: int = e.tick_count
	if tick < window.x or tick > window.y or (tick - window.x) % 2 != 0:
		return
	var latest := ""
	for i in range(e.trace.size() - 1, -1, -1):
		if not String(e.trace[i].decision).begins_with("saw_"):
			latest = "%s @%d" % [e.trace[i].decision, e.trace[i].tick]
			break
	caption.text = "tick %d   enemy %s · %s   player %s   last decision: %s" % [tick, e.ai_state,
		Rules.Phase.keys()[e.combat.phase], Rules.Phase.keys()[p.combat.phase], latest]
	if DisplayServer.get_name() == "headless":
		saved += 1
		return
	paused = true
	arena.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(clip_dir.path_join("frame_%03d.png" % saved)) == OK:
		saved += 1
	paused = false
