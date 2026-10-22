extends CanvasLayer
## HUD for the Adaptive Combat Lab: per fighter, what the object is (display label,
## recipe, seed, structural fingerprint), which hold the solver chose, what each input
## does (light chain, heavy, guard) and why missing moves are missing; health and
## posture bars; the recent event log and the controls.

var panels := {}
var bars := {}
var log_label: Label
var help_label: Label
var banner: Label

const HELP := "WASD move · LMB/J light · MMB/F/K heavy · RMB/L hold guard (fresh press = deflect) · Space dodge\n" + \
	"1-5 your object · 6-0 soul's object · V/C next seed (Shift: fresh seed) · B your Marrow Arm · N soul's Marrow Arm\n" + \
	"G swap your label (behaviour must not change) · M soul AI mode · R reset · T trails · F3 grips/contacts · F4 slow-mo · H help"

func _ready() -> void:
	for side: String in ["player", "soul"]:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.035, 0.045, 0.78)
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var hp := _bar(Color(0.75, 0.16, 0.14))
		var posture := _bar(Color(0.95, 0.7, 0.2))
		box.add_child(hp)
		box.add_child(posture)
		var text := Label.new()
		text.add_theme_font_size_override("font_size", 13)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(430, 0)
		box.add_child(text)
		add_child(panel)
		panel.position = Vector2(12, 12) if side == "player" else Vector2(1280 - 454 - 12, 12)
		panels[side] = text
		bars[side] = [hp, posture]
	log_label = Label.new()
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.position = Vector2(12, 520)
	log_label.add_theme_color_override("font_outline_color", Color.BLACK)
	log_label.add_theme_constant_override("outline_size", 6)
	add_child(log_label)
	help_label = Label.new()
	help_label.text = HELP
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	help_label.add_theme_constant_override("outline_size", 6)
	help_label.position = Vector2(12, 652)
	add_child(help_label)
	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 30)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 10)
	banner.position = Vector2(470, 300)
	add_child(banner)

func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(430, 9)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	bar.add_theme_stylebox_override("background", bg)
	return bar

func update_fighter(side: String, title: String, fighter: RefCounted, extra: String) -> void:
	bars[side][0].value = fighter.hp
	bars[side][1].value = fighter.posture
	panels[side].text = "%s\n%s\n%s" % [title, describe(fighter), extra]

static func describe(fighter: RefCounted) -> String:
	var caps: Dictionary = fighter.caps
	var d: Dictionary = fighter.descriptor
	var lines: Array[String] = []
	lines.append("Label (UI only): \"%s\"   recipe %s  seed %d" % [d.label, str(d.recipe).trim_prefix("demo."), int(d.seed)])
	lines.append("structure %s · %.2f kg · %.2f m · body %s%s" % [caps.object_fingerprint, caps.mass, caps.extent, caps.body.id,
		(" + " + ", ".join(caps.body.modifications)) if not (caps.body.modifications as Array).is_empty() else ""])
	if caps.hold == null:
		lines.append("CANNOT WIELD with this body")
	else:
		var hold: Dictionary = caps.hold
		lines.append("hold: %s (%s)" % ["two hands, spread %.2f m" % hold.span if hold.spread else ("two hands, %.2f m" % hold.span if hold.hands.size() == 2 else "one hand"), hold.id])
		var chain: Array[String] = []
		for act: Dictionary in caps.light:
			chain.append("%s%s→%s (%s) %.2fs" % [act.archetype, " rear" if act.rear else "", act.feature.id, act.channel, act.windup])
		lines.append("LIGHT: " + (" | ".join(chain) if not chain.is_empty() else "none"))
		var heavy: Variant = caps.heavy
		lines.append("HEAVY: " + ("%s→%s (%s) %.2fs, %.0f dmg" % [heavy.archetype, heavy.feature.id, heavy.channel, heavy.windup, heavy.damage] if heavy != null else "none"))
		var guard: Variant = caps.guard
		lines.append("GUARD: " + ("%s · arc %.0f° · absorbs %.0f%% · deflect %.0f ms" % [guard.kind, rad_to_deg(guard.arc), guard.absorb * 100.0, guard.deflect * 1000.0] if guard != null else "none"))
	var reasons: Array[String] = []
	for r: Dictionary in caps.rejections:
		if str(r.code).ends_with("_rejected") or str(r.code).begins_with("no_") or r.code in ["object_unusable_for_body", "two_hand_requires_missing_hand"]:
			reasons.append("%s: %s" % [r.code, r.detail])
	if not reasons.is_empty():
		lines.append("not granted → " + "; ".join(reasons.slice(0, 4)))
	return "\n".join(lines)

func set_log(lines: Array[String]) -> void:
	log_label.text = "\n".join(lines)

func set_banner(text: String) -> void:
	banner.text = text
