extends "res://scripts/courtyard.gd"
## Isolated expedition-preview controller. Reuses the courtyard's Fighter, CombatState,
## build adapter, Swordsman AI, DuelProgression, HUD and salvage/equip transactions;
## it only adds exploration lifecycle: one dormant Swordsman per generated site, an
## encounter director that hands the single existing duel progression to whichever
## site the player enters, area transitions, pickups and extraction.
signal extracted(summary: Dictionary)
const Builder = preload("res://scripts/expedition_preview/preview_builder.gd")
const Plan = preload("res://scripts/expedition_preview/expedition_plan.gd")
const Satchel = preload("res://scripts/expedition_preview/prototype_satchel.gd")
const PICKUP_RADIUS := 1.6
const PORTAL_RADIUS := 1.5
const DISCOVERY_RADIUS := 26.0

var plan: Dictionary
var builder: Builder
var satchel := Satchel.new()
var area := "world"
var sites: Array = []
var active_site := -1
var duel_site := 0
var descent_discovered := false
var guardian_released := false
var extraction_time := 0.0
var finished := false
var transitions: Array = []
var objective_label: Label
var _config: Dictionary = Plan.modules().world

func _ready() -> void:
	super._ready()
	if progression == null:
		return
	var canvas := CanvasLayer.new()
	add_child(canvas)
	objective_label = Label.new()
	objective_label.position = Vector2(978, 96)
	objective_label.add_theme_font_size_override("font_size", 15)
	objective_label.add_theme_color_override("font_color", Color("d5dedc"))
	canvas.add_child(objective_label)

func _build_courtyard() -> void:
	builder = Builder.new()
	builder.name = "ExpeditionPreviewWorld"
	builder.plan = plan
	add_child(builder)

func _reset_positions() -> void:
	if sites.is_empty():
		_create_sites()
		player.reset_at(builder.world_point(plan.world.spawn) + Vector3.UP * 0.05)
		player.sync_visual()
		event_text = "Explore. Find the descent, release its guardian, then extract at the beacon."
		event_time = 5.0
		return
	# Only an encounter retry reaches here (see _start_duel); restart beside its site.
	var site: Dictionary = sites[active_site]
	player.reset_at(site.position + Vector3(0, 0.05, 5.0))
	enemy.reset_at(site.position + Vector3.UP * 0.05)
	enemy.enabled = true
	encounter_time = 0.0
	event_text = "The soul turns toward you again."
	event_time = 2.5
	player.sync_visual()
	enemy.sync_visual()

func _create_sites() -> void:
	for site: Dictionary in plan.world.sites:
		sites.append({"id": site.id, "area": "world", "kind": "exterior", "theme": site.theme,
			"position": builder.world_point(site.cell), "cleared": false})
	sites.append({"id": "site.guardian", "area": "dungeon", "kind": "guardian", "theme": "guardian",
		"position": builder.dungeon_point(plan.dungeon.guardian.cell), "cleared": false})
	for i in sites.size():
		var fighter: Fighter = enemy
		if i > 0:
			# Dormant duplicates of the same corrupted swordsman build; the director
			# replaces their state from the shared progression when a duel begins.
			var prepared := progression.adapter.prepare_encounter(progression.builds)
			fighter = Swordsman.new()
			fighter.combat = prepared.states.enemy
			fighter.equipment = prepared.resolved.enemy.equipment
			fighter.move_speed = prepared.configs.enemy.move_speed
			fighter.opponent = player
			add_child(fighter)
		fighter.name = "Soul_" + String(sites[i].id).replace(".", "_")
		fighter.enabled = false
		fighter.reset_at(sites[i].position + Vector3.UP * 0.05)
		fighter.sync_visual()
		sites[i]["enemy"] = fighter
	builder.set_gate("gate.guardian_exit", true)

func _physics_process(delta: float) -> void:
	if finished:
		return
	_direct_encounters()
	_pickups()
	_transitions(delta)
	_extraction(delta)
	if player.global_position.y < -12.0:
		_teleport(builder.world_point(plan.world.spawn) if area == "world" else builder.dungeon_point(plan.dungeon.spawn), 0.0)
	super._physics_process(delta)
	_update_objectives()

func in_duel() -> bool:
	return active_site >= 0 and progression.stage == Progression.Stage.DUEL

func _direct_encounters() -> void:
	if active_site >= 0:
		var site: Dictionary = sites[active_site]
		if progression.stage == Progression.Stage.VICTORY:
			_clear_site(site)
		elif progression.stage == Progression.Stage.DUEL and site.kind == "exterior" and _flat_distance(player.global_position, site.position) > float(_config.leash_radius):
			# Leaving the vigil ends the engagement without healing either fighter.
			enemy.enabled = false
			enemy.position = site.position + Vector3.UP * 0.05
			enemy.velocity = Vector3.ZERO
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
	var fighter: Fighter = site.enemy
	if duel_site != index or progression.stage != Progression.Stage.DUEL:
		# Prototype: each encounter starts from the current build at full health;
		# health carry-over between encounters is not designed yet.
		var prepared := progression.begin(false)
		if not prepared.ok:
			_report_transaction(prepared, "")
			return
		resolved_builds = prepared.resolved
		player.combat = prepared.states.player
		player.equipment = prepared.resolved.player.equipment
		player.move_speed = prepared.configs.player.move_speed
		fighter.combat = prepared.states.enemy
		fighter.equipment = prepared.resolved.enemy.equipment
		fighter.move_speed = prepared.configs.enemy.move_speed
		duel_site = index
	enemy = fighter
	player.opponent = fighter
	fighter.enabled = true
	active_site = index
	if site.kind == "guardian":
		builder.set_gate("gate.guardian_entry", true)
	event_text = "The guardian rises · the way back is sealed." if site.kind == "guardian" else "A corrupted soul of the %s stirs." % String(site.theme).replace("_", " ")
	event_time = 3.0

func _clear_site(site: Dictionary) -> void:
	site.cleared = true
	active_site = -1
	# A released body stays visible but no longer walls off a corridor or room.
	var fighter: Fighter = site.enemy
	fighter.collision_layer = 0
	if site.kind == "guardian":
		guardian_released = true
		builder.set_gate("gate.guardian_entry", false)
		builder.set_gate("gate.guardian_exit", false)
		builder.show_ascent(true)

func _resolve_duel() -> void:
	# The shell can remove this scene before a queued contact flushes; outside an
	# active site no duel exists, so dormant souls can never be struck.
	if not is_inside_tree() or is_queued_for_deletion() or active_site < 0:
		return
	super._resolve_duel()

func _start_duel(next_duel: bool) -> void:
	if next_duel:
		_report_transaction({"ok": false}, "")
		event_text = "No rematch in the expedition preview · seek the next soul"
		return
	if active_site < 0:
		event_text = "R retries a duel in progress · Esc to restart the expedition"
		event_time = 2.5
		return
	super._start_duel(false)

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

func _transitions(delta: float) -> void:
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
	transitions.append({"to": target, "tick": Engine.get_physics_frames()})
	_teleport(point, yaw)
	event_text = "You descend." if target == "dungeon" else "You return to the surface."
	event_time = 2.0

func _teleport(point: Vector3, yaw: float) -> void:
	# A doorway transition, not a reset: health, posture and build state carry over.
	player.position = point + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.locked = false
	player.facing = Vector3.FORWARD.rotated(Vector3.UP, yaw)

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
		for action: String in ["move_forward", "move_back", "move_left", "move_right", "guard"]:
			Input.action_release(action)
		extracted.emit(satchel.summary(progression.builds))

func progression_prompt() -> String:
	var prompt := super.progression_prompt()
	if progression.stage == Progression.Stage.VICTORY and active_site < 0 and prompt.begins_with("MARROW ARM EQUIPPED"):
		prompt = "MARROW ARM EQUIPPED · Q to use Marrow Lunge in your next duel"
	elif progression.stage == Progression.Stage.VICTORY and prompt.begins_with("SOUL RELEASED · R"):
		prompt = ""
	if not prompt.is_empty():
		return prompt
	if extraction_time > 0.0:
		return "EXTRACTING · %.1f s · stay inside the beacon" % maxf(0.0, float(_config.extraction_seconds) - extraction_time)
	return ""

func _update_objectives() -> void:
	if not is_instance_valid(objective_label):
		return
	var relic: Array = plan.loot.filter(func(item: Dictionary) -> bool: return item.kind == "relic")
	var claimed: bool = not relic.is_empty() and satchel.has(relic[0].id)
	var lines := ["EXPEDITION PREVIEW (prototype)",
		"%s Discover the descent" % _mark(descent_discovered),
		"%s Release the guardian" % _mark(guardian_released),
		"%s Claim the reliquary" % _mark(claimed),
		"%s Extract at the beacon" % _mark(finished),
		"Satchel: %d finds (not saved)" % satchel.entries.size(),
		"Area: " + ("dungeon" if area == "dungeon" else "surface")]
	objective_label.text = "\n".join(lines)

static func _mark(done: bool) -> String:
	return "[x]" if done else "[ ]"

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
