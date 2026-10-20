extends Control
## Lab HUD: instructions, aim/guard cursor, health and posture, outcome banner, event
## log and the derived handling of both weapons. Reads arena and rules state only.

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const LabInput = preload("res://scripts/melee_lab/lab_input.gd")
const Visual = preload("res://scripts/melee_lab/lab_visual.gd")
const OUTCOME_COLORS := {"deflect": Color("ffe27a"), "block": Color("9fd0ff"), "misaligned": Color("ffa04a"),
	"guard_break": Color("c07bff"), "hit": Color("ff5a4a"), "clash": Color("ffffff"), "evaded": Color("a0a0a0")}
const OUTCOME_TEXT := {"deflect": "DEFLECTION", "block": "BLOCK", "misaligned": "BAD ANGLE", "guard_break": "GUARD BREAK",
	"hit": "HIT", "clash": "CLASH", "evaded": "EVADED"}

var arena: Node
var show_help := true
var show_tuning := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _text(at: Vector2, text: String, size := 16, color := Color.WHITE) -> void:
	draw_string_outline(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _bars(at: Vector2, width: float, who: String, s: State, color: Color) -> void:
	_text(at, who, 15, color)
	draw_rect(Rect2(at + Vector2(0, 6), Vector2(width, 9)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at + Vector2(0, 6), Vector2(width * s.health / s.max_health, 9)), Color("c9483d"))
	draw_rect(Rect2(at + Vector2(0, 19), Vector2(width, 6)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at + Vector2(0, 19), Vector2(width * s.posture / s.max_posture, 6)), Color("e8b04a"))

func _draw() -> void:
	if arena == null or arena.player == null:
		return
	var view := get_viewport_rect().size
	var p: State = arena.player.state
	var o: State = arena.opponent.state
	_text(Vector2(18, 28), "DIRECTIONAL MELEE LAB — experimental, not production combat", 17, Color("e9d9a8"))
	_text(Vector2(18, 50), "You: %s   ·   Opponent: %s   ·   AI mode: %s%s" % [arena.player.loadout_label, arena.opponent.loadout_label,
		arena.opponent.mode, (" (guard %s)" % (arena.opponent.dummy_guard if arena.opponent.dummy_guard != "" else "none")) if arena.opponent.mode == "dummy" else ""], 15)
	_text(Vector2(18, 70), "%s%s" % ["SLOW MOTION ×%.2f   " % Engine.time_scale if Engine.time_scale < 1.0 else "", "lock-on" if arena.player.locked else "free camera"], 14, Color("b8c4c0"))
	_bars(Vector2(18, view.y - 54), 300.0, "You · %s" % State.Phase.keys()[p.phase], p, Color("9fe0c8"))
	_bars(Vector2(view.x * 0.5 - 170, 96), 340.0, "Opponent · %s" % State.Phase.keys()[o.phase], o, Color("f0b0a0"))
	_draw_cursor(Vector2(view.x * 0.5, view.y - 105))
	_draw_banner(view)
	_draw_log(Vector2(view.x - 330, 140))
	if show_help:
		_draw_help(Vector2(18, 110))
	if show_tuning:
		_draw_tuning(Vector2(view.x * 0.5 - 330, 150))

func _draw_cursor(center: Vector2) -> void:
	var player: Node = arena.player
	var radius := 62.0
	draw_circle(center, radius + 6, Color(0, 0, 0, 0.45))
	draw_arc(center, radius * player.tuning.aim_deadzone, 0, TAU, 32, Color(1, 1, 1, 0.25), 1.5)
	draw_arc(center, radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
	var s: State = player.state
	var guarding: bool = player.aim_owner == "guard" or s.guarding
	for direction: String in Geometry.DIRECTIONS:
		var v := Geometry.chamber_vector(direction)
		var tip := center + Vector2(v.x, -v.y) * radius
		var active: bool = (s.phase in [State.Phase.WINDUP, State.Phase.SWING] and s.direction == direction) and not guarding
		var color: Color = Visual.DIRECTION_COLORS[direction] if active else Color(1, 1, 1, 0.35)
		draw_circle(tip, 9.0 if active else 4.0, color)
	if guarding:
		var g := Geometry.guard_vector(s.guard)
		draw_line(center, center + Vector2(g.x, -g.y) * radius, Color("9fd0ff"), 5.0)
	var c: Vector2 = player.cursor
	draw_circle(center + Vector2(c.x, -c.y) * radius, 5.0, Color("ffffff") if player.aim_owner != "" else Color(1, 1, 1, 0.3))
	var caption := "camera"
	if player.aim_owner == "attack":
		caption = "AIM: " + Visual.DIRECTION_TEXT.get(s.direction, "follow-up")
	elif guarding:
		caption = "GUARD: " + s.guard.to_upper() + (" · DEFLECT WINDOW" if s.guard_age <= s.deflect_window else "")
	_text(center + Vector2(-radius - 20, radius + 26), caption, 14)

func _draw_banner(view: Vector2) -> void:
	if arena.events.is_empty():
		return
	var last: Dictionary = arena.events[-1]
	var age: float = arena.clock - last.at
	if age > 1.6:
		return
	var color: Color = OUTCOME_COLORS.get(last.result, Color.WHITE)
	color.a = clampf(1.6 - age, 0.0, 1.0)
	var title := "%s → %s" % [last.attacker, OUTCOME_TEXT.get(last.result, last.result)]
	_text(Vector2(view.x * 0.5 - 160, view.y * 0.27), title, 30, color)
	var detail := "%s · momentum %.1f" % [last.direction.replace("_", " "), last.momentum]
	if last.alignment >= 0.0:
		detail += " · guard %s, %.0f° off" % [last.guard, last.alignment]
	if last.get("guard_bypassed", false):
		detail += " · guard held on the wrong side"
	_text(Vector2(view.x * 0.5 - 160, view.y * 0.27 + 26), detail, 15, Color(1, 1, 1, color.a))

func _draw_log(at: Vector2) -> void:
	_text(at, "Recent contacts", 14, Color("b8c4c0"))
	var shown: Array = arena.events.slice(maxi(0, arena.events.size() - 7))
	for i in range(shown.size()):
		var e: Dictionary = shown[i]
		_text(at + Vector2(0, 20 + i * 18), "%5.1fs %-8s %-11s %s" % [e.at, e.attacker, OUTCOME_TEXT.get(e.result, e.result), e.direction.replace("_", " ")],
			13, OUTCOME_COLORS.get(e.result, Color.WHITE))

func _draw_help(at: Vector2) -> void:
	var lines := [
		"F1 hide help · F2 handling/tuning · F3 hitboxes · F4 slow motion",
		"WASD move · Space dodge · Tab lock-on · R reset · Esc free mouse",
		"LMB hold: aim swing with mouse, release to cut. Tap = follow-up cut",
		"   flick right/up-right/up/up-left/left = chamber side, down = thrust",
		"RMB hold: guard; mouse points at the side to cover (down = centre)",
		"   press just before contact, aligned, to DEFLECT",
		"[ ] your weapon · , . opponent weapon · M AI mode · G dummy guard",
		"T trails · Y telegraph arcs · U intent labels",
	]
	draw_rect(Rect2(at - Vector2(8, 18), Vector2(520, lines.size() * 19 + 12)), Color(0, 0, 0, 0.45))
	for i in range(lines.size()):
		_text(at + Vector2(0, i * 19), lines[i], 14)

func _draw_tuning(at: Vector2) -> void:
	var rows := ["weapon              inertia accel  reach  guard  shift  contact"]
	for actor: Node in [arena.player, arena.opponent]:
		var h: Dictionary = actor.state.h
		rows.append("%-19s %5.2f  %5.0f  %4.2fm  %4.2f  %4.1f  %4.2fs" % [actor.loadout_label.left(19), h.inertia, h.accel, h.reach, h.guard_strength, h.guard_shift, arena.contact_estimate(actor)])
	rows.append("units: kg·m², rad/s², m, ×ref, rad/s, s from rest (est.)")
	rows.append("see data/melee_lab/tuning.json for all %d provisional values" % arena.tuning.size())
	draw_rect(Rect2(at - Vector2(8, 18), Vector2(660, rows.size() * 19 + 12)), Color(0, 0, 0, 0.6))
	for i in range(rows.size()):
		_text(at + Vector2(0, i * 19), rows[i], 14, Color("e9e2c9"))
