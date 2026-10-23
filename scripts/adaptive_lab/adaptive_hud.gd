extends CanvasLayer
## HUD for the Adaptive Combat Lab. The default view is deliberately minimal:
##   bottom-left   your health and posture, one line naming what your object does;
##   top-centre    the soul's health and posture;
##   centre        a lock-on reticle over the target (when locked);
##   bottom-right  one faint hint line.
## Everything developer-facing sits behind explicit toggles and starts hidden:
##   H help · F2 solver/stats panels · F5 combat log (F3 geometry overlay, F6 planned
##   contact paths and T trails are drawn in the world by the actors).

var player_hp: ProgressBar
var player_posture: ProgressBar
var equipment: Label
var soul_hp: ProgressBar
var soul_posture: ProgressBar
var soul_name: Label
var reticle: Label
var hint: Label
var banner: Label
var help_label: Label
var log_label: Label
var stats_panels := {}
var stats_root: Control
var log_root: Control

const HELP := "WASD move (camera-relative) · mouse orbit · wheel zoom · Q/Tab lock-on · Esc free mouse\n" + \
	"LMB/J light (repeat late = combo) · MMB/F/K heavy (after a light = finisher) · RMB/L guard (fresh press = deflect) · Space dodge\n" + \
	"1-6 your Lab object · Shift+1-6 soul's · O your source: Lab import / v0 generator (comparison) · V next v0 seed\n" + \
	"B / N your / soul's marrow graft · G swap your name (behaviour must not change) · M soul AI · R reset\n" + \
	"H help · F2 solver & stats · F3 grips/contacts · F4 slow motion · F5 combat log · F6 planned contact paths · T trails"

func _ready() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Player (bottom-left).
	var player_box := VBoxContainer.new()
	player_box.name = "PlayerBox"
	player_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	player_box.offset_left = 24
	player_box.offset_bottom = -22
	player_box.offset_top = -86
	player_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	player_box.add_theme_constant_override("separation", 4)
	root.add_child(player_box)
	player_hp = _bar(Color(0.78, 0.18, 0.15), Vector2(300, 12))
	player_posture = _bar(Color(0.95, 0.72, 0.22), Vector2(300, 6))
	equipment = _label(15, Color(0.92, 0.9, 0.85))
	player_box.add_child(player_hp)
	player_box.add_child(player_posture)
	player_box.add_child(equipment)
	# Soul (top-centre).
	var soul_box := VBoxContainer.new()
	soul_box.name = "SoulBox"
	soul_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	soul_box.offset_top = 16
	soul_box.offset_left = -170
	soul_box.offset_right = 170
	soul_box.add_theme_constant_override("separation", 3)
	root.add_child(soul_box)
	soul_name = _label(14, Color(0.85, 0.82, 0.78))
	soul_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soul_hp = _bar(Color(0.7, 0.16, 0.2), Vector2(340, 8))
	soul_posture = _bar(Color(0.95, 0.72, 0.22), Vector2(340, 5))
	soul_box.add_child(soul_name)
	soul_box.add_child(soul_hp)
	soul_box.add_child(soul_posture)
	reticle = _label(26, Color(1.0, 0.85, 0.5))
	reticle.text = "( )"
	reticle.visible = false
	root.add_child(reticle)
	hint = _label(13, Color(0.8, 0.8, 0.8, 0.55))
	hint.text = "H help · F2 details"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -170
	hint.offset_top = -34
	root.add_child(hint)
	banner = _label(30, Color.WHITE)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner)
	# Debug layers (hidden by default).
	help_label = _label(13, Color.WHITE)
	help_label.text = HELP
	help_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help_label.offset_left = -560
	help_label.offset_top = -200
	help_label.visible = false
	root.add_child(help_label)
	stats_root = HBoxContainer.new()
	stats_root.name = "Stats"
	stats_root.position = Vector2(12, 60)
	stats_root.visible = false
	root.add_child(stats_root)
	for side: String in ["player", "soul"]:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.035, 0.045, 0.82)
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		var text := _label(12, Color.WHITE)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(430, 0)
		panel.add_child(text)
		stats_root.add_child(panel)
		stats_panels[side] = text
	log_root = PanelContainer.new()
	log_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	log_root.offset_left = -470
	log_root.offset_right = -12
	log_root.visible = false
	root.add_child(log_root)
	log_label = _label(12, Color.WHITE)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_root.add_child(log_label)

func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _bar(color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.7)
	bar.add_theme_stylebox_override("background", bg)
	return bar

func update_fighters(player: RefCounted, soul: RefCounted, soul_title: String) -> void:
	player_hp.value = player.hp
	player_posture.value = player.posture
	soul_hp.value = soul.hp
	soul_posture.value = soul.posture
	soul_name.text = soul_title
	equipment.text = equipment_line(player)
	if stats_root.visible:
		stats_panels.player.text = "YOU — state %s\n%s" % [player.state, describe(player)]
		stats_panels.soul.text = "SOUL — state %s\n%s" % [soul.state, describe(soul)]

## One concise line: what the object is physically and what the inputs do.
static func equipment_line(fighter: RefCounted) -> String:
	var caps: Dictionary = fighter.caps
	var mods: Array = caps.body.modifications
	var graft := "  · graft" if not mods.is_empty() else ""
	if caps.get("unarmed", false):
		return "%.1f kg — cannot be held · bare hands%s" % [caps.mass, graft]
	var hold: Dictionary = caps.hold
	var chain: Array[String] = []
	for act: Dictionary in caps.light:
		chain.append(act.archetype)
	var heavy: String = caps.heavy.archetype if caps.heavy != null else "—"
	return "%.1f kg %s · %s | heavy %s%s" % [caps.mass, "2H" if hold.hands.size() == 2 else "1H", " · ".join(chain), heavy, graft]

func set_reticle(screen: Variant) -> void:
	reticle.visible = screen != null
	if screen != null:
		reticle.position = (screen as Vector2) - Vector2(14, 18)

static func describe(fighter: RefCounted) -> String:
	var caps: Dictionary = fighter.caps
	var d: Dictionary = fighter.descriptor
	var lines: Array[String] = []
	if d.get("schema") == "lab.boneshed.object_export.v1":
		lines.append("Lab import %s · seed %s · assembly %d (provenance only)" % [str(d.id).substr(0, 30), d.seed_text, d.assembly])
		lines.append("name (UI only): \"%s\"" % d.label)
	else:
		lines.append("v0 generator (comparison) %s seed %d · name (UI only): \"%s\"" % [d.recipe, int(d.seed), d.label])
	lines.append("structure %s · %.2f kg · %.2f m · body %s%s" % [caps.object_fingerprint, caps.mass, caps.extent, caps.body.id,
		(" + " + ", ".join(caps.body.modifications)) if not (caps.body.modifications as Array).is_empty() else ""])
	var mods: Dictionary = fighter.body.get("modifiers", {})
	if not mods.is_empty():
		lines.append("modifiers: " + ", ".join(mods.keys().map(func(k: String) -> String: return "%s %.2f" % [k, mods[k]])) + " · regenerated %.1f" % fighter.regenerated)
	var phys: Dictionary = caps.get("physics", {})
	if not phys.is_empty():
		lines.append("physics: inertia %.2f kg·m² · swing load %.2f · heft %.2f · head %.2f" % [phys.inertia, phys.swing_load, phys.heft, phys.head])
	if caps.get("unarmed", false):
		lines.append("NOT WIELDABLE — fighting with the body's own anatomy")
	elif caps.hold != null:
		var hold: Dictionary = caps.hold
		lines.append("hold: %s, slide room %.2f/%.2f m (%s)" % ["two hands %.2f m" % hold.span if hold.hands.size() == 2 else "one hand",
			hold.slide_room.x, hold.slide_room.y, hold.id])
	var chain: Array[String] = []
	for act: Dictionary in caps.light:
		chain.append("%s -> %s (%s) %.2fs" % [act.archetype, act.feature.id, act.channel, act.windup])
	lines.append("LIGHT: " + (" | ".join(chain) if not chain.is_empty() else "none"))
	var heavy: Variant = caps.heavy
	lines.append("HEAVY: " + ("%s -> %s (%s) %.2fs, %.0f dmg" % [heavy.archetype, heavy.feature.id, heavy.channel, heavy.windup, heavy.damage] if heavy != null else "none"))
	var after: Array[String] = []
	for h: Variant in caps.get("heavy_after", []):
		after.append(h.archetype if h != null else "—")
	lines.append("finishers after light 1..n: " + " | ".join(after))
	var guard: Variant = caps.guard
	lines.append("GUARD: " + ("%s · arc %.0f° · absorbs %.0f%% · deflect %.0f ms" % [guard.kind, rad_to_deg(guard.arc), guard.absorb * 100.0, guard.deflect * 1000.0] if guard != null else "none"))
	var reasons: Array[String] = []
	for r: Dictionary in caps.rejections:
		if str(r.code).ends_with("_rejected") or str(r.code).begins_with("no_") or r.code in ["object_not_wieldable", "two_hand_requires_missing_hand"]:
			reasons.append("%s: %s" % [r.code, r.detail])
	if not reasons.is_empty():
		lines.append("not granted  ->  " + "; ".join(reasons.slice(0, 5)))
	return "\n".join(lines)

func set_log(lines: Array[String]) -> void:
	if log_root.visible:
		log_label.text = "\n".join(lines)

func set_banner(text: String) -> void:
	banner.text = text

func toggle(layer: String) -> void:
	match layer:
		"help":
			help_label.visible = not help_label.visible
		"stats":
			stats_root.visible = not stats_root.visible
		"log":
			log_root.visible = not log_root.visible
