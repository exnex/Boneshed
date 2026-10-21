extends "res://scripts/melee_lab/lab_hud.gd"
## Expedition HUD built from the lab HUD's pieces (health / posture / stamina bars with
## cost ticks, status buildup and effects, refusal feedback, aim/guard cursor, outcome
## banner, contact log) plus the expedition's objectives, prompts and salvage card.
## Reads controller and rules state only.

const HELP := [
	"F1 hide help · F2 handling table · F3 hitboxes · T trails · Y arcs · U labels",
	"WASD move · Mouse camera · Tab lock-on · Space dodge step · Shift dodge roll",
	"LMB hold: aim a cut with the mouse, release to swing (tap = follow-up cut)",
	"   flick right/up-right/up/up-left/left = chamber side, down = thrust",
	"RMB hold: guard toward the mouse side (down = centre); fresh press = DEFLECT",
	"Q hold / release: Marrow Lunge once salvaged (F) and equipped (E)",
	"Walk onto finds, the descent and portals · R retry duel · Esc menu",
]

func _draw() -> void:
	if arena == null or arena.player == null:
		return
	var view := get_viewport_rect().size
	var p: State = arena.player.state
	_text(Vector2(18, 28), "DIRECTIONAL EXPEDITION — experimental integration of the melee lab", 17, Color("e9d9a8"))
	_text(Vector2(18, 50), "%s  /  seed %d  ·  %s  ·  Esc menu" % [arena.plan.address, arena.plan.seed, "dungeon" if arena.area == "dungeon" else "surface"], 15)
	_text(Vector2(18, 70), _build_line(arena.player), 14, Color("cfe8dc"))
	_bars(Vector2(18, view.y - 96), 300.0, "You · %s" % State.Phase.keys()[p.phase], p, Color("9fe0c8"))
	var foe: Node = arena.opponent
	if is_instance_valid(foe):
		_bars(Vector2(view.x * 0.5 - 170, 96), 340.0, "%s · %s" % [foe.loadout_label, State.Phase.keys()[foe.state.phase]], foe.state, Color("f0b0a0"))
	_draw_cursor(Vector2(view.x * 0.5, view.y - 105))
	_draw_banner(view)
	if not arena.events.is_empty():
		_draw_log(Vector2(view.x - 330, 300))
	_draw_objectives(Vector2(view.x - 330, 110))
	_draw_prompt(view)
	if arena.progression.owns("item.marrow_arm"):
		_draw_salvage(Vector2(18, view.y - 118))
	if show_help:
		_draw_help_lines(Vector2(18, 110))
	if show_tuning:
		_draw_tuning_rows(Vector2(view.x * 0.5 - 430, 150))

func _draw_objectives(at: Vector2) -> void:
	var lines: Array = arena.objectives()
	draw_rect(Rect2(at - Vector2(8, 18), Vector2(320, lines.size() * 19 + 12)), Color(0, 0, 0, 0.45))
	for i in range(lines.size()):
		_text(at + Vector2(0, i * 19), lines[i], 14, Color("d5dedc"))

func _draw_prompt(view: Vector2) -> void:
	var message: String = arena.progression_prompt()
	if message == "" and arena.event_time > 0.0:
		message = arena.event_text
	if message == "":
		return
	var width := ThemeDB.fallback_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_rect(Rect2(view.x * 0.5 - width * 0.5 - 20, view.y * 0.62, width + 40, 34), Color(0.03, 0.05, 0.06, 0.85))
	_text(Vector2(view.x * 0.5 - width * 0.5, view.y * 0.62 + 23), message, 16, Color("ead9ac"))

func _draw_salvage(at: Vector2) -> void:
	var equipped: bool = arena.progression.equipped()
	var s = arena.player.state
	var line := "MARROW ARM / LEFT ARM / " + ("EQUIPPED" if equipped else "CARRIED · E to equip after a duel")
	if equipped and s.has_signature():
		line += " · Q lunge %.1f stamina, reach %.1f m" % [s.signature_cost, float(s.signature.reach)]
	_text(at, line, 14, Color("ead9ac"))

func _draw_help_lines(at: Vector2) -> void:
	draw_rect(Rect2(at - Vector2(8, 18), Vector2(600, HELP.size() * 19 + 12)), Color(0, 0, 0, 0.45))
	for i in range(HELP.size()):
		_text(at + Vector2(0, i * 19), HELP[i], 14)

## Handling table for the player and the engaged soul (lab F2 layout).
func _draw_tuning_rows(at: Vector2) -> void:
	var rows := ["weapon / build                 inertia accel  reach  guard  atk   dodge roll  mitig"]
	for actor: Node in [arena.player, arena.opponent]:
		if not is_instance_valid(actor):
			continue
		var h: Dictionary = actor.state.h
		var r: Dictionary = actor.state.resources
		rows.append("%-30s %5.2f  %5.0f  %4.2fm  %4.2f  %4.1f  %4.1f  %4.1f  %3d%%" % [actor.loadout_label.left(30), h.inertia, h.accel, h.reach,
			h.guard_strength, r.attack_cost, r.dodge_cost, r.roll_cost, roundi(r.mitigation * 100.0)])
	draw_rect(Rect2(at - Vector2(8, 18), Vector2(760, rows.size() * 19 + 12)), Color(0, 0, 0, 0.6))
	for i in range(rows.size()):
		_text(at + Vector2(0, i * 19), rows[i], 14, Color("e9e2c9"))
