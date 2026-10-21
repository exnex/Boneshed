extends Node3D
## Integrated expedition controller (experimental, separately selectable). The
## procedural expedition preview's generated world, dungeon, encounter director,
## guardian gates, pickups, transitions and extraction, played with the directional
## melee lab's combat: every contact, damage, posture, stamina charge and status in
## this scene is decided by the lab rules (duelist_state.gd, contact_solver.gd,
## combat_resources.gd, status_effects.gd). No Fighter, CombatState, Swordsman or
## courtyard adapter exists here, so no fighter carries a second combat model.
##
## Fixed step order each physics tick (as in the lab): director/pickups/transitions →
## player controller → engaged soul controller → player rules + movement → soul rules
## + movement → contact for the player's blade, then the soul's. Dormant souls are
## never controlled, stepped or resolved.
signal extracted(summary: Dictionary)

const Adapter = preload("res://scripts/directional_expedition/directional_adapter.gd")
const Progression = preload("res://scripts/directional_expedition/directional_progression.gd")
const Player = preload("res://scripts/directional_expedition/expedition_player.gd")
const Opponent = preload("res://scripts/directional_expedition/expedition_opponent.gd")
const Hud = preload("res://scripts/directional_expedition/expedition_hud.gd")
const Builder = preload("res://scripts/expedition_preview/preview_builder.gd")
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Satchel = preload("res://scripts/expedition_preview/prototype_satchel.gd")
const Stream = preload("res://scripts/worldgen/seed_stream.gd")
const LabInput = preload("res://scripts/melee_lab/lab_input.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const PICKUP_RADIUS := 1.6
const PORTAL_RADIUS := 1.5
const DISCOVERY_RADIUS := 26.0
const RETRY_DISTANCE := 4.0
const MARKER_SECONDS := 0.9
## Expedition actions beyond the lab's map (added only if absent).
const KEYS := {"salvage": KEY_F, "equip": KEY_E, "signature": KEY_Q}

var plan: Dictionary
var adapter: Adapter
var progression: Progression
var tuning: Dictionary = {}
var builder: Builder
var satchel := Satchel.new()
var player: Player
## The engaged soul, or null while exploring (the HUD and player lock-on read it).
var opponent: Opponent
var hud: Hud
var area := "world"
var sites: Array = []
var active_site := -1
var duel_site := -1
var descent_discovered := false
var guardian_released := false
var extraction_time := 0.0
var finished := false
var transitions: Array = []
var clock := 0.0
## Every resolved contact (lab format) and status lifecycle event, for HUD/logs/tests.
var events: Array[Dictionary] = []
var status_events: Array[Dictionary] = []
var world_condition := ""
var event_text := ""
var event_time := 0.0
var markers: Array[Dictionary] = []
var flags := {"trails": true, "arcs": true, "debug": false, "labels": true}
var ok := false
var _config: Dictionary = Plan.modules().world

func _ready() -> void:
	adapter = Adapter.load_default()
	if not adapter.ok:
		push_error("Directional expedition initialization failed: " + JSON.stringify(adapter.errors))
		set_physics_process(false)
		return
	tuning = adapter.tuning
	progression = Progression.new(adapter)
	var fighter := progression.player_fighter()
	if not fighter.ok:
		push_error("Directional expedition player build failed: " + JSON.stringify(fighter.errors))
		set_physics_process(false)
		return
	_install_input()
	builder = Builder.new()
	builder.name = "ExpeditionWorld"
	builder.plan = plan
	add_child(builder)
	player = Player.new()
	player.name = "Pilgrim"
	player.tuning = tuning
	player.equip(tuning, fighter)
	add_child(player)
	player.visual.flags = flags
	_create_sites()
	player.reset_at(builder.world_point(plan.world.spawn) + Vector3.UP * 0.05, Vector3.FORWARD)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	hud.arena = self
	canvas.add_child(hud)
	event_text = "Explore. Find the descent, release its guardian, then extract at the beacon."
	event_time = 5.0
	ok = true
	if OS.has_feature("web"):
		print("BONESHED_DIRECTIONAL_READY %s %d" % [plan.address, plan.seed])

func _install_input() -> void:
	LabInput.install()
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, event)

func _create_sites() -> void:
	var exterior := 0
	for site: Dictionary in plan.world.sites:
		sites.append({"id": site.id, "area": "world", "kind": "exterior", "theme": site.theme,
			"position": builder.world_point(site.cell), "cleared": false, "variant": adapter.exterior_variant(exterior)})
		exterior += 1
	sites.append({"id": "site.guardian", "area": "dungeon", "kind": "guardian", "theme": "guardian",
		"position": builder.dungeon_point(plan.dungeon.guardian.cell), "cleared": false, "variant": adapter.guardian_variant()})
	var spawn := builder.world_point(plan.world.spawn)
	for site: Dictionary in sites:
		var soul := Opponent.new()
		soul.name = "Soul_" + String(site.id).replace(".", "_")
		soul.tuning = tuning
		var resolved := adapter.resolve_fighter(adapter.enemy_build(site.variant, "expedition." + site.id), site.variant.get("armor", []), str(site.variant.label))
		soul.equip(tuning, resolved)
		add_child(soul)
		soul.visual.flags = flags
		soul.opponent = player
		var face: Vector3 = spawn - site.position if site.area == "world" else Vector3.BACK
		face.y = 0.0
		soul.reset_at(site.position + Vector3.UP * 0.05, face if face.length_squared() > 0.01 else Vector3.BACK)
		soul.post = site.position
		soul.visible = site.area == area
		site["enemy"] = soul
	builder.set_gate("gate.guardian_exit", true)

func _physics_process(delta: float) -> void:
	if finished or not ok:
		return
	clock += delta
	event_time = maxf(0.0, event_time - delta)
	_hotkeys()
	_direct_encounters()
	_pickups()
	_transitions()
	_extraction(delta)
	if player.global_position.y < -12.0:
		var spawn: Vector3 = builder.world_point(plan.world.spawn) if area == "world" else builder.dungeon_point(plan.dungeon.spawn)
		player.teleport(spawn + Vector3.UP * 0.05, player.camera_yaw)
	advance(delta)

func in_duel() -> bool:
	return active_site >= 0 and progression.stage == Progression.Stage.DUEL

## One deterministic tick of the shared combat rules (see the step order above).
func advance(delta: float) -> void:
	var foe: Opponent = sites[active_site].enemy if in_duel() else null
	opponent = foe
	player.opponent = foe
	player.control(delta)
	if foe != null:
		foe.control(delta)
	player.step(delta)
	if foe != null:
		foe.step(delta)
		for pair: Array in [[player, foe], [foe, player]]:
			var att: Node = pair[0]
			var def: Node = pair[1]
			var report := Solver.resolve(att.state, att.prev_xform, att.xform(), def.state, def.prev_xform, def.xform())
			if report.result != Solver.NONE:
				_record(att, def, report)
	for actor: Node in ([player, foe] if foe != null else [player]):
		for entry: Dictionary in actor.state.status.drain_events():
			entry.at = snappedf(clock, 0.0001)
			entry.fighter = str(actor.name)
			status_events.append(entry)
	if foe != null and progression.stage == Progression.Stage.DUEL:
		progression.record_loss(player.state)

func _record(att: Node, def: Node, report: Dictionary) -> void:
	var entry := report.duplicate()
	entry.at = snappedf(clock, 0.0001)
	entry.attacker = str(att.name)
	entry.defender = str(def.name)
	entry.site = sites[duel_site].id
	entry.distance = snappedf(att.global_position.distance_to(def.global_position), 0.001)
	entry.omega = snappedf(att.state.omega, 0.001)
	entry.signature = att.state.signature_active
	events.append(entry)
	print(JSON.stringify({"expedition_contact": _printable(entry)}))
	if def is Opponent:
		def.note_defended(report.result)
	_marker(report)
	if att == player and progression.record_contact(report.result, player.state, def.state):
		_clear_site(sites[active_site])

static func _printable(entry: Dictionary) -> Dictionary:
	var out := {}
	for key: String in entry:
		var value: Variant = entry[key]
		if value is Vector3 or value is Vector2:
			out[key] = str(value)
		elif value is float:
			out[key] = snappedf(value, 0.0001)
		else:
			out[key] = value
	return out

func _hotkeys() -> void:
	if Input.is_action_just_pressed("salvage"):
		var acquired := progression.acquire()
		_report(acquired, "MARROW ARM ACQUIRED · E to equip")
	if Input.is_action_just_pressed("equip"):
		var equipped := progression.equip()
		if equipped.ok:
			# A changed build is a new rules state (as the courtyard equip did).
			player.equip(tuning, equipped.player)
		_report(equipped, "MARROW ARM EQUIPPED · Q to use Marrow Lunge")
	if Input.is_action_just_pressed("lab_reset"):
		retry()
	if Input.is_action_just_pressed("lab_help"):
		hud.show_help = not hud.show_help
	if Input.is_action_just_pressed("lab_tuning"):
		hud.show_tuning = not hud.show_tuning
	for toggle: Array in [["lab_debug", "debug"], ["lab_trails", "trails"], ["lab_arcs", "arcs"], ["lab_labels", "labels"]]:
		if Input.is_action_just_pressed(toggle[0]):
			flags[toggle[1]] = not flags[toggle[1]]

func _report(result: Dictionary, success: String) -> void:
	event_text = success if result.ok else "Action unavailable · finish the duel and follow the prompt"
	event_time = 3.0

func _direct_encounters() -> void:
	if active_site >= 0:
		var site: Dictionary = sites[active_site]
		if progression.stage == Progression.Stage.DUEL and site.kind == "exterior" and _flat_distance(player.global_position, site.position) > float(_config.leash_radius):
			# Leaving the vigil ends the engagement without healing either fighter.
			var soul: Opponent = site.enemy
			soul.position = site.position + Vector3.UP * 0.05
			soul.velocity = Vector3.ZERO
			soul.desired_move = Vector3.ZERO
			soul.state.set_guard(false)
			active_site = -1
			event_text = "The soul returns to its vigil."
			event_time = 2.5
		return
	for i in sites.size():
		var site: Dictionary = sites[i]
		if site.cleared or site.area != area or _flat_distance(player.global_position, site.position) > float(_config.activation_radius):
			continue
		if not progression.available_rewards().is_empty():
			event_text = "Salvage the released soul first · F"
			event_time = 0.5
			return
		_activate(i)
		return

func _activate(index: int) -> void:
	var site: Dictionary = sites[index]
	var soul: Opponent = site.enemy
	if duel_site != index or progression.stage != Progression.Stage.DUEL:
		# Prototype rule (unchanged from the preview): each new encounter starts both
		# fighters from their current builds at full health, stamina and no statuses.
		var prepared := progression.begin(site.id, site.variant)
		if not prepared.ok:
			_report(prepared, "")
			return
		player.equip(tuning, prepared.player)
		soul.equip(tuning, prepared.enemy)
		var toward := player.global_position - soul.global_position
		toward.y = 0.0
		soul.reset_at(soul.global_position, toward if toward.length_squared() > 0.01 else Vector3.BACK)
		soul.reset_ai(_ai_seed(site.id))
		duel_site = index
	active_site = index
	player.locked = true
	if site.kind == "guardian":
		builder.set_gate("gate.guardian_entry", true)
	event_text = "The guardian rises · the way back is sealed." if site.kind == "guardian" else "A corrupted soul of the %s stirs." % String(site.theme).replace("_", " ")
	event_time = 3.0

## One seeded AI stream per site and plan: the same address + seed replays exactly.
func _ai_seed(site_id: String) -> int:
	return Stream.hash32("%s|%s|ai" % [plan.fingerprint, site_id])

func _clear_site(site: Dictionary) -> void:
	site.cleared = true
	active_site = -1
	opponent = null
	player.opponent = null
	# A released body stays visible but no longer walls off a corridor or room.
	var soul: Opponent = site.enemy
	soul.collision_layer = 0
	event_text = "Soul released."
	event_time = 2.0
	if site.kind == "guardian":
		guardian_released = true
		builder.set_gate("gate.guardian_entry", false)
		builder.set_gate("gate.guardian_exit", false)
		builder.show_ascent(true)

## R: retry a duel in progress or a lost duel, from the current builds at full health.
func retry() -> void:
	if active_site < 0:
		event_text = "R retries a duel in progress · Esc to restart the expedition"
		event_time = 2.5
		return
	var site: Dictionary = sites[active_site]
	var away: Vector3 = player.global_position - site.position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.BACK
	duel_site = -1
	_activate(active_site)
	player.teleport(site.position + away * RETRY_DISTANCE + Vector3.UP * 0.05, atan2(away.x, away.z))
	site.enemy.reset_at(site.position + Vector3.UP * 0.05, away)
	event_text = "The soul turns toward you again."
	event_time = 2.5

func _pickups() -> void:
	for item: Dictionary in plan.loot:
		if item.area != area or satchel.has(item.id):
			continue
		var point := builder.world_point(item.cell) if area == "world" else builder.dungeon_point(item.cell)
		if _flat_distance(player.global_position, point) < PICKUP_RADIUS and absf(player.global_position.y - point.y) < 2.0:
			satchel.collect(item.id, item.item)
			builder.take_pickup(item.id)
			event_text = "Recovered " + Satchel.label(item.item)
			event_time = 2.5

func _transitions() -> void:
	if in_duel():
		return
	if area == "world":
		var descent := builder.world_point(plan.world.descent.cell)
		if not descent_discovered and _flat_distance(player.global_position, descent) < DISCOVERY_RADIUS:
			descent_discovered = true
			event_text = "A descent into the dark: the dungeon entrance."
			event_time = 3.0
		if _flat_distance(player.global_position, descent) < PORTAL_RADIUS:
			_enter("dungeon", builder.dungeon_point(plan.dungeon.spawn), _facing_yaw(plan.dungeon.rooms[0].travel))
	else:
		var portals := [plan.dungeon.return_portal]
		if guardian_released:
			portals.append(plan.dungeon.ascent_portal)
		for portal: Array in portals:
			if _flat_distance(player.global_position, builder.dungeon_point(portal)) < PORTAL_RADIUS:
				var descent: Dictionary = plan.world.descent
				_enter("world", builder.world_point(descent.approach), _facing_yaw(Plan.OPPOSITE[descent.facing]))
				return

func _enter(target: String, point: Vector3, yaw: float) -> void:
	area = target
	builder.set_area(target)
	for site: Dictionary in sites:
		site.enemy.visible = site.area == target
	transitions.append({"to": target, "tick": Engine.get_physics_frames()})
	# A doorway transition, not a reset: health, posture, stamina and statuses carry over.
	player.teleport(point + Vector3.UP * 0.05, yaw)
	event_text = "You descend." if target == "dungeon" else "You return to the surface."
	event_time = 2.0

static func _facing_yaw(dir: String) -> float:
	var step: Vector2i = Plan.DIRS[dir]
	return atan2(-float(step.x), -float(step.y))

func _extraction(delta: float) -> void:
	if area != "world" or in_duel():
		extraction_time = 0.0
		return
	if _flat_distance(player.global_position, builder.world_point(plan.world.extraction)) > 3.0:
		extraction_time = 0.0
		return
	extraction_time += delta
	if extraction_time >= float(_config.extraction_seconds):
		finished = true
		satchel.extracted = true
		player.input_enabled = false
		for action: String in LabInput.KEYS.keys() + LabInput.MOUSE.keys() + KEYS.keys():
			Input.action_release(action)
		extracted.emit(satchel.summary(progression.builds))

func progression_prompt() -> String:
	if progression.stage == Progression.Stage.FALLEN:
		return "YOU FELL · R to retry with your current equipment"
	if progression.stage == Progression.Stage.VICTORY:
		if not progression.available_rewards().is_empty():
			return "SOUL RELEASED · F to salvage Marrow Arm"
		if progression.owns("item.marrow_arm") and not progression.equipped():
			return "MARROW ARM ACQUIRED · E to equip"
	if extraction_time > 0.0:
		return "EXTRACTING · %.1f s · stay inside the beacon" % maxf(0.0, float(_config.extraction_seconds) - extraction_time)
	return ""

func objectives() -> Array:
	var relic: Array = plan.loot.filter(func(item: Dictionary) -> bool: return item.kind == "relic")
	var claimed: bool = not relic.is_empty() and satchel.has(relic[0].id)
	return ["DIRECTIONAL EXPEDITION (experimental)",
		"%s Discover the descent" % _mark(descent_discovered),
		"%s Release the guardian" % _mark(guardian_released),
		"%s Claim the reliquary" % _mark(claimed),
		"%s Extract at the beacon" % _mark(finished),
		"Souls released: %d / %d" % [sites.filter(func(site: Dictionary) -> bool: return site.cleared).size(), sites.size()],
		"Satchel: %d finds (not saved)" % satchel.entries.size()]

static func _mark(done: bool) -> String:
	return "[x]" if done else "[ ]"

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _marker(report: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = report.point
	var color: Color = Hud.OUTCOME_COLORS.get(report.result, Color.WHITE)
	var text := Label3D.new()
	text.text = Hud.OUTCOME_TEXT.get(report.result, report.result)
	text.modulate = color
	text.font_size = 48
	text.outline_size = 12
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.position = Vector3(0.0, 0.35, 0.0)
	node.add_child(text)
	markers.append({"node": node, "age": 0.0})

func _process(delta: float) -> void:
	for marker: Dictionary in markers:
		marker.age += delta
		marker.node.position.y += delta * 0.4
	while not markers.is_empty() and markers[0].age > MARKER_SECONDS:
		markers.pop_front().node.queue_free()
