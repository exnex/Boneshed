extends Control

const Rules = preload("res://scripts/combat/combat_state.gd")
var arena: Node3D
var font: Font = ThemeDB.fallback_font

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
	draw_rect(Rect2(0, 0, width, 124), Color(0.025, 0.04, 0.05, 0.86))
	text_at(Vector2(32, 33), "B O N E S H E D", 24, Color("d9c89d"))
	text_at(Vector2(32, 57), "COURTYARD  /  PROVISIONAL COMBAT STUDY", 12, Color("94a8aa"))
	var p = arena.player.combat
	var e = arena.enemy.combat
	text_at(Vector2(32, 84), "PILGRIM   %03d / 100" % p.health, 14)
	bar(Vector2(32, 93), 290, p.health / p.max_health, Color("89bbaa"))
	bar(Vector2(32, 106), 290, p.posture / p.max_posture, Color("dcb565"))
	text_at(Vector2(width - 386, 35), "THE CORRUPTED SWORDSMAN", 19, Color("dca6a8"))
	text_at(Vector2(width - 386, 60), "%s   /   HP %03d   POSTURE %03d" % [phase_name(e.phase), e.health, e.posture], 14)
	bar(Vector2(width - 386, 76), 352, e.health / e.max_health, Color("b56b7b"))
	bar(Vector2(width - 386, 94), 352, e.posture / e.max_posture, Color("dcb565"))
	text_at(Vector2(width * 0.5 - 70, 41), "SOUL  /  01", 13, Color("8b9b9e"))
	text_at(Vector2(width * 0.5 - 70, 66), "LOCKED" if arena.player.locked else "FREE CAMERA", 13)
	draw_rect(Rect2(0, height - 65, width, 65), Color(0.025, 0.04, 0.05, 0.9))
	text_at(Vector2(32, height - 37), "WASD  move     MOUSE  orbit     LMB  strike     RMB  guard / tap to deflect     SPACE  dodge", 15)
	text_at(Vector2(32, height - 15), "TAB  lock target     R  reset     ESC  release mouse     F3  attack volumes     AMBER  windup  /  RED  active", 13, Color("96a6a7"))
	var message: String = arena.event_text if arena.event_time > 0.0 else ""
	if e.phase == Rules.Phase.DEAD:
		message = "SOUL RELEASED   ·   R to face it again"
	elif p.phase == Rules.Phase.DEAD:
		message = "YOU FELL   ·   R to begin again"
	elif e.phase == Rules.Phase.BROKEN:
		message = "POSTURE BROKEN   ·   STRIKE NOW"
	if message != "":
		var message_width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x
		draw_rect(Rect2(width * 0.5 - message_width * 0.5 - 20, height - 133, message_width + 40, 46), Color(0.03, 0.05, 0.06, 0.85))
		text_at(Vector2(width * 0.5 - message_width * 0.5, height - 102), message, 23, Color("ead9ac"))
	if arena.enemy.combat.phase == Rules.Phase.WINDUP:
		text_at(Vector2(width * 0.5 - 90, 159), "HEAVY · WINDUP" if e.heavy else "SWORD · WINDUP", 18, Color("e3b46c"))

func phase_name(phase: int) -> String:
	return ["READY", "WINDUP", "ACTIVE", "RECOVERY", "RECOIL", "BROKEN", "DODGE", "DEAD"][phase] if phase < 8 else "?"

