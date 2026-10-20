extends Control

const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var font: Font = ThemeDB.fallback_font
var show_controls := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func text_at(point: Vector2, value: String, size := 18, color := Color("d9dfd8")) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func bar(point: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(point, Vector2(width, 8)), Color("202b30"))
	draw_rect(Rect2(point, Vector2(width * clampf(ratio, 0.0, 1.0), 8)), color)

func _draw() -> void:
	if not is_instance_valid(arena):
		return
	var width := get_viewport_rect().size.x
	var height := get_viewport_rect().size.y
	var p: Rules = arena.player.combat
	var e: Rules = arena.enemy.combat
	text_at(Vector2(32, 32), "PILGRIM", 14, Color("b3c9bf"))
	text_at(Vector2(32, 53), "%d / %d" % [p.health, p.max_health], 13)
	bar(Vector2(32, 64), 235, p.health / p.max_health, Color("89bbaa"))
	text_at(Vector2(32, 92), "POSTURE", 11, Color("b4a484"))
	bar(Vector2(97, 83), 170, p.posture / p.max_posture, Color("c8a365"))
	text_at(Vector2(width - 302, 32), "CORRUPTED SWORDSMAN", 14, Color("d0b4b5"))
	bar(Vector2(width - 302, 47), 270, e.health / e.max_health, Color("a56672"))
	text_at(Vector2(width - 302, 75), "POSTURE", 11, Color("b4a484"))
	bar(Vector2(width - 237, 66), 205, e.posture / e.max_posture, Color("c8a365"))
	var ability := "Q  ·  MARROW LUNGE" if arena.progression.equipped() else "SWORD  ·  LMB / C"
	text_at(Vector2(32, height - 28), ability, 14, Color("c6b68f"))
	text_at(Vector2(width - 180, height - 28), "F1  controls", 13, Color("9aaba8"))
	if show_controls:
		draw_rect(Rect2(24, height - 126, width - 48, 74), Color(0.025, 0.04, 0.05, 0.94))
		text_at(Vector2(40, height - 99), "WASD move   Mouse orbit   LMB strike   C heavy   RMB guard / tap-deflect   Space dodge", 14)
		text_at(Vector2(40, height - 74), "Wheel zoom   Tab lock   Q equipped ability   R retry   Esc mouse   F3 debug   F1 close", 13, Color("9aaba8"))
	var message: String = arena.progression_prompt()
	if arena.player.debug_hitboxes:
		# The enemy's current intent label makes AI decisions inspectable during playtests.
		text_at(Vector2(32, 121), "DEBUG  ·  " + phase_name(e.phase) + "  ·  AI " + str(arena.enemy.get("ai_state")) + "  ·  " + arena.event_text, 13)
	if arena.progression.stage == arena.Progression.Stage.VICTORY and arena.progression.owns("item.marrow_arm"):
		draw_rect(Rect2(24, 143, 570, 100), Color(0.03, 0.05, 0.06, 0.94))
		text_at(Vector2(40, 169), "MARROW ARM  /  LEFT ARM  /  " + ("EQUIPPED" if arena.progression.equipped() else "ACQUIRED"), 18, Color("ead9ac"))
		text_at(Vector2(40, 194), "Body modification: replaces the left arm. Sword stays right; no left grip.", 15)
		text_at(Vector2(40, 218), "Legacy Q · Marrow Lunge: long, narrow, slow recovery. Standard deflection.", 14, Color("a4b8b7"))
	if message != "":
		var message_width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_rect(Rect2(width * 0.5 - message_width * 0.5 - 20, height - 100, message_width + 40, 36), Color(0.03, 0.05, 0.06, 0.85))
		text_at(Vector2(width * 0.5 - message_width * 0.5, height - 76), message, 16, Color("ead9ac"))

func phase_name(phase: int) -> String:
	return {Rules.Phase.IDLE: "READY", Rules.Phase.WINDUP: "WINDUP", Rules.Phase.ACTIVE: "ACTIVE",
		Rules.Phase.RECOVERY: "RECOVERY", Rules.Phase.STAGGER: "RECOIL", Rules.Phase.BROKEN: "BROKEN",
		Rules.Phase.DODGE: "DODGE", Rules.Phase.DEAD: "DEAD"}.get(phase, "?")
