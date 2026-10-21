extends "res://scripts/melee_lab/melee_lab.gd"
## Visual quality showcase (experimental, isolated). The directional melee lab arena —
## same rules state, controllers, AI, contact solver, step order, stamina and status —
## with a rigged character presentation, fitted equipment and a ruined crypt. Launch:
##   bash scripts/tooling/play_visual_showcase.sh            (GL Compatibility)
##   bash scripts/tooling/play_visual_showcase.sh --forward  (isolated Forward+ test)
##
## What differs from melee_lab.gd is presentation and selection only:
##   - _build_arena builds the crypt (crypt_builder.gd) and the quality preset;
##   - each duelist's lab_visual is replaced by showcase_visual.gd;
##   - showcase loadouts (data/visual_showcase/showcase.json) combine existing items and
##     lab armor, resolved by the lab adapter (lab_loadout.gd → BuildRules) as usual;
##   - contact reports are forwarded to the visuals for hit reactions and sparks.
## No rule, cost, timing or contact decision is changed or added here.

const ShowcaseVisual = preload("res://scripts/visual_showcase/showcase_visual.gd")
const CryptBuilder = preload("res://scripts/visual_showcase/crypt_builder.gd")
const Quality = preload("res://scripts/visual_showcase/quality.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const SHOWCASE_PATH := "res://data/visual_showcase/showcase.json"
const SHOWCASE_SCHEMA := "boneshed.visual_showcase.v0"
const WEAPON_KEYS := ["light", "medium", "heavy"]
const ARMOR_KEYS := ["none", "cloth", "mail", "plate"]

var showcase: Dictionary = {}
## Current selection per role: {"kind", "weapon", "armor", "marrow_arm"}.
var selection: Dictionary = {}
var quality: Dictionary = {}
var crypt: Dictionary = {}
var notice := ""
var notice_time := 0.0
var legend: Label
var startup_ms := 0
## The scene builds only the duel when false (tests that compare outcomes).
var build_environment := true

func _ready() -> void:
	var started := Time.get_ticks_msec()
	quality = Quality.preset(Quality.requested_preset(), RenderingServer.get_current_rendering_method())
	MaterialLibrary.set_texture_size(int(quality.texture_size), int(quality.environment_texture_size))
	super._ready()
	if not ok:
		return
	for actor: Node in [player, opponent]:
		_swap_visual(actor, "player" if actor == player else "opponent")
	get_viewport().msaa_3d = int(quality.msaa) as Viewport.MSAA
	get_viewport().positional_shadow_atlas_size = int(quality.shadow_atlas)
	hud.show_help = false
	# Presentation default: the real blade's edge glow and trails carry the telegraph;
	# the lab's arcs and text labels stay one key away (Y, U).
	flags.arcs = false
	flags.labels = false
	_build_legend()
	startup_ms = Time.get_ticks_msec() - started
	print(JSON.stringify({"visual_showcase": "ready", "renderer": RenderingServer.get_current_rendering_method(),
		"quality": quality.name, "startup_ms": startup_ms, "texture_generation_ms": MaterialLibrary.generation_ms}))

## melee_lab._ready calls this after loading lab data and before creating fighters, so
## showcase loadouts are appended here and the starting indices point at them.
func _build_arena() -> void:
	var loaded := load_showcase()
	if not loaded.ok:
		push_error("Visual showcase data invalid: " + JSON.stringify(loaded.errors))
		return
	showcase = loaded.data
	for role: String in ["player", "opponent"]:
		selection[role] = (showcase[role] as Dictionary).duplicate()
	for role: String in ["player", "opponent"]:
		var id := _ensure_loadout(selection[role])
		for i in range(lab.loadouts.size()):
			if lab.loadouts[i].id == id:
				if role == "player":
					player_loadout = i
				else:
					opponent_loadout = i
	if build_environment:
		crypt = CryptBuilder.build(self, quality)
	else:
		super._build_arena()

static func load_showcase(path := SHOWCASE_PATH) -> Dictionary:
	var data: Variant = Loadout.read_json(path)
	var errors: Array[String] = []
	if not data is Dictionary or data.get("schema") != SHOWCASE_SCHEMA:
		return {"ok": false, "errors": ["missing or invalid showcase data"]}
	for key: String in ["weapons", "armor", "player", "opponent"]:
		if not data.get(key) is Dictionary:
			errors.append("showcase needs object " + key)
	if errors.is_empty():
		for w: String in WEAPON_KEYS:
			if not data.weapons.get(w) is String:
				errors.append("showcase weapon missing: " + w)
		for a: String in ARMOR_KEYS:
			if not data.armor.get(a) is Array:
				errors.append("showcase armor missing: " + a)
		for role: String in ["player", "opponent"]:
			var r: Dictionary = data[role]
			if not r.get("weapon") in WEAPON_KEYS or not r.get("armor") in ARMOR_KEYS or not r.get("kind") in ["pilgrim", "corrupted"] or not r.get("marrow_arm") is bool:
				errors.append("showcase role invalid: " + role)
	return {"ok": errors.is_empty(), "errors": errors, "data": data}

static func loadout_id(choice: Dictionary) -> String:
	return "showcase.%s.%s%s" % [choice.weapon, choice.armor, ".marrow" if choice.marrow_arm else ""]

## Adds (once) a lab loadout for a showcase selection: existing items and lab armor.
func _ensure_loadout(choice: Dictionary) -> String:
	var id := loadout_id(choice)
	for existing: Dictionary in lab.loadouts:
		if existing.id == id:
			return id
	var equipped := {"hand_r": showcase.weapons[choice.weapon]}
	if choice.marrow_arm:
		equipped["arm_l"] = "item.marrow_arm"
	var armor: Array = showcase.armor[choice.armor].duplicate()
	lab.loadouts.append({"id": id, "label": "%s · %s%s" % [choice.weapon, choice.armor, " · Marrow Arm" if choice.marrow_arm else ""],
		"equipped": equipped, "armor": armor})
	return id

func _swap_visual(actor: Node, role: String) -> void:
	var old: Node3D = actor.visual
	var shared_flags: Dictionary = old.flags
	actor.remove_child(old)
	old.queue_free()
	var visual := ShowcaseVisual.new()
	visual.name = "ShowcaseVisual"
	visual.actor = actor
	visual.flags = shared_flags
	visual.look = {"kind": selection[role].kind, "marrow_arm": selection[role].marrow_arm}
	actor.visual = visual
	actor.add_child(visual)

## Selects a combination for one role. Rejected combinations (the shared build rules,
## e.g. a two-handed weapon beside the handless Marrow Arm) keep the old selection.
func select(role: String, changes: Dictionary) -> bool:
	var choice: Dictionary = (selection[role] as Dictionary).duplicate()
	choice.merge(changes, true)
	var id := _ensure_loadout(choice)
	var resolved := Loadout.resolve(lab, role, id)
	if not resolved.ok:
		notice = "Rejected by build rules: %s" % JSON.stringify(resolved.errors.map(func(e: Variant) -> String: return str(e.get("code", e)) if e is Dictionary else str(e)))
		notice_time = 3.0
		lab.loadouts = lab.loadouts.filter(func(l: Dictionary) -> bool: return l.id != id)
		return false
	selection[role] = choice
	var actor: Node = player if role == "player" else opponent
	(actor.visual as ShowcaseVisual).look = {"kind": choice.kind, "marrow_arm": choice.marrow_arm}
	var ids := [loadout_id(selection.player), loadout_id(selection.opponent)]
	set_loadouts(ids[0], ids[1])
	notice = "%s: %s" % [role, lab.loadouts[player_loadout if role == "player" else opponent_loadout].label]
	notice_time = 2.0
	return true

func _record(att: Node, def: Node, report: Dictionary) -> void:
	super._record(att, def, report)
	for pair: Array in [[att, false, def], [def, true, att]]:
		var visual: Variant = (pair[0] as Node).get("visual")
		if visual is ShowcaseVisual:
			(visual as ShowcaseVisual).on_contact(report, pair[1], pair[2])

## Sparks at the contact point; the lab's outcome text stays behind the labels toggle.
func _marker(report: Dictionary) -> void:
	if flags.labels:
		super._marker(report)
	if crypt.has("fx"):
		crypt.fx.call(report.point, Hud.OUTCOME_COLORS.get(report.result, Color.WHITE), report.result)

func _hotkeys() -> void:
	super._hotkeys()
	for i in range(WEAPON_KEYS.size()):
		if Input.is_physical_key_pressed(KEY_1 + i) and _edge("w%d" % i):
			select("player", {"weapon": WEAPON_KEYS[i]})
		if Input.is_physical_key_pressed(KEY_7 + i) and _edge("ow%d" % i):
			select("opponent", {"weapon": WEAPON_KEYS[i]})
	for i in range(ARMOR_KEYS.size()):
		if Input.is_physical_key_pressed(KEY_4 + i if i < 3 else KEY_0) and _edge("a%d" % i):
			if i < 3:
				select("player", {"armor": ARMOR_KEYS[i + 1]})
			else:
				select("player", {"armor": "none"})
	if Input.is_physical_key_pressed(KEY_O) and _edge("oa"):
		var next: String = ARMOR_KEYS[(ARMOR_KEYS.find(selection.opponent.armor) + 1) % ARMOR_KEYS.size()]
		select("opponent", {"armor": next})
	if Input.is_physical_key_pressed(KEY_K) and _edge("marrow"):
		select("opponent", {"marrow_arm": not selection.opponent.marrow_arm})
	if Input.is_physical_key_pressed(KEY_L) and _edge("legend"):
		legend.visible = not legend.visible

var _held: Dictionary = {}

## Rising edge of a raw key (the lab's input map stays untouched).
func _edge(key: String) -> bool:
	var was: bool = _held.get(key, false)
	_held[key] = true
	return not was

func _process(delta: float) -> void:
	super._process(delta)
	for key: String in _held.keys():
		if not _key_down(key):
			_held.erase(key)
	notice_time = maxf(0.0, notice_time - delta)
	if legend != null:
		legend.text = _legend_text()
	if crypt.has("animate"):
		crypt.animate.call(delta)

func _key_down(key: String) -> bool:
	match key:
		"oa":
			return Input.is_physical_key_pressed(KEY_O)
		"marrow":
			return Input.is_physical_key_pressed(KEY_K)
		"legend":
			return Input.is_physical_key_pressed(KEY_L)
	var index := int(key.right(1))
	if key.begins_with("ow"):
		return Input.is_physical_key_pressed(KEY_7 + index)
	if key.begins_with("w"):
		return Input.is_physical_key_pressed(KEY_1 + index)
	if key.begins_with("a"):
		return Input.is_physical_key_pressed(KEY_4 + index if index < 3 else KEY_0)
	return false

func _build_legend() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	legend = Label.new()
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	legend.position -= Vector2(16, 16)
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	legend.add_theme_constant_override("outline_size", 4)
	legend.modulate = Color(0.9, 0.88, 0.8)
	canvas.add_child(legend)

func _legend_text() -> String:
	var p: Dictionary = selection.player
	var o: Dictionary = selection.opponent
	var lines := [
		"BONESHED — visual showcase (experimental) · %s · %s quality" % [RenderingServer.get_current_rendering_method(), quality.name],
		"Pilgrim: %s · %s     Soul: %s · %s%s" % [p.weapon, p.armor, o.weapon, o.armor, " · Marrow Arm" if o.marrow_arm else ""],
		"Weapon 1/2/3 · Armor 4 cloth 5 mail 6 plate 0 none · Soul weapon 7/8/9 · O soul armor · K Marrow Arm",
		"Lab controls unchanged (F1 help) · R reset · T trails · Y arcs · U labels · F3 hit segments · L hide",
	]
	if notice_time > 0.0:
		lines.append(notice)
	return "\n".join(lines)
