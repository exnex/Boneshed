extends Node3D
## Isolated directional melee lab arena (experimental; not production combat). Launch:
##   bash scripts/tooling/play.sh res://scenes/melee_lab.tscn
## Fixed step order each physics tick: controllers → rules + movement (player, then
## opponent) → contact (player's blade first, then the opponent's). Production scenes,
## rules, AI and input are not referenced.

const Loadout = preload("res://scripts/melee_lab/lab_loadout.gd")
const LabInput = preload("res://scripts/melee_lab/lab_input.gd")
const Player = preload("res://scripts/melee_lab/lab_player.gd")
const Opponent = preload("res://scripts/melee_lab/lab_opponent.gd")
const Solver = preload("res://scripts/melee_lab/contact_solver.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const Hud = preload("res://scripts/melee_lab/lab_hud.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const PLAYER_START := Vector3(0.0, 0.02, 2.2)
const OPPONENT_START := Vector3(0.0, 0.02, -0.4)
const MARKER_SECONDS := 0.9
const DEFAULT_LOADOUT := "balanced"

var tuning: Dictionary = {}
var lab: Dictionary = {}
var player: Player
var opponent: Opponent
var hud: Hud
var flags := {"trails": true, "arcs": true, "debug": false, "labels": true}
var player_loadout := 0 # Index into lab.loadouts; set to DEFAULT_LOADOUT on load.
var opponent_loadout := 0
var clock := 0.0
var events: Array[Dictionary] = []
## Status lifecycle events (buildup, activation, ticks, expiry) for HUD, logs and tests.
var status_events: Array[Dictionary] = []
## Active world condition id ("" = none); its ambient sources reach every fighter.
var world_condition := ""
var markers: Array[Dictionary] = []
## When true, a QA driver steps the arena (`advance`) instead of _physics_process.
var manual_step := false
var ok := false

func _ready() -> void:
	var tuned := Loadout.load_tuning()
	lab = Loadout.load_lab()
	if not tuned.ok or not lab.ok:
		push_error("Melee lab initialization failed: " + JSON.stringify(tuned.errors + lab.errors))
		set_physics_process(false)
		return
	tuning = tuned.values
	for i in range(lab.loadouts.size()):
		if lab.loadouts[i].id == DEFAULT_LOADOUT:
			player_loadout = i
			opponent_loadout = i
	LabInput.install()
	_build_arena()
	player = Player.new()
	player.name = "Player"
	opponent = Opponent.new()
	opponent.name = "Opponent"
	for actor: Node in [player, opponent]:
		actor.tuning = tuning
	_equip(player, "player", player_loadout)
	_equip(opponent, "opponent", opponent_loadout)
	add_child(player)
	add_child(opponent)
	player.opponent = opponent
	opponent.opponent = player
	for actor: Node in [player, opponent]:
		actor.visual.flags = flags
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	hud.arena = self
	canvas.add_child(hud)
	reset_duel()
	ok = true
	if DisplayServer.get_name() != "headless" and "--qa" not in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _equip(actor: Node, role: String, index: int) -> void:
	var resolved := Loadout.resolve(lab, role, lab.loadouts[index].id)
	if not resolved.ok:
		push_error("Melee lab loadout failed: " + JSON.stringify(resolved.errors))
		return
	actor.equip(tuning, resolved)

func set_loadouts(player_id: String, opponent_id: String) -> void:
	for i in range(lab.loadouts.size()):
		if lab.loadouts[i].id == player_id:
			player_loadout = i
		if lab.loadouts[i].id == opponent_id:
			opponent_loadout = i
	_equip(player, "player", player_loadout)
	_equip(opponent, "opponent", opponent_loadout)
	reset_duel()

func reset_duel() -> void:
	player.reset_at(PLAYER_START, OPPONENT_START - PLAYER_START)
	opponent.reset_at(OPPONENT_START, PLAYER_START - OPPONENT_START)
	opponent.reset_ai()
	events.clear()
	status_events.clear()
	clock = 0.0
	for marker: Dictionary in markers:
		marker.node.queue_free()
	markers.clear()

func _physics_process(delta: float) -> void:
	if not manual_step:
		_hotkeys()
		advance(delta)

## One deterministic duel tick.
func advance(delta: float) -> void:
	clock += delta
	player.control(delta)
	opponent.control(delta)
	if world_condition != "":
		var condition := CombatResources.find_world(lab.combat, world_condition)
		for actor: Node in [player, opponent]:
			actor.state.receive_ambient(condition.get("status_sources", []), delta, world_condition)
	player.step(delta)
	opponent.step(delta)
	for pair: Array in [[player, opponent], [opponent, player]]:
		var att: Node = pair[0]
		var def: Node = pair[1]
		var report := Solver.resolve(att.state, att.prev_xform, att.xform(), def.state, def.prev_xform, def.xform())
		if report.result != Solver.NONE:
			_record(att, def, report)
	for actor: Node in [player, opponent]:
		for entry: Dictionary in actor.state.status.drain_events():
			entry.at = snappedf(clock, 0.0001)
			entry.fighter = str(actor.name)
			status_events.append(entry)
			if entry.event != "buildup":
				print(JSON.stringify({"lab_status": _printable(entry)}))

func _record(att: Node, def: Node, report: Dictionary) -> void:
	var entry := report.duplicate()
	entry.at = snappedf(clock, 0.0001)
	entry.attacker = str(att.name)
	entry.defender = str(def.name)
	entry.distance = snappedf(att.global_position.distance_to(def.global_position), 0.001)
	entry.omega = snappedf(att.state.omega, 0.001)
	events.append(entry)
	print(JSON.stringify({"lab_event": _printable(entry)}))
	if def == opponent:
		opponent.note_defended(report.result)
	_marker(report)

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

func _marker(report: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = report.point
	var color: Color = Hud.OUTCOME_COLORS.get(report.result, Color.WHITE)
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	sphere.material_override = mat
	node.add_child(sphere)
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
		marker.node.scale = Vector3.ONE * (1.0 + marker.age * 0.6)
		marker.node.position.y += delta * 0.4
	while not markers.is_empty() and markers[0].age > MARKER_SECONDS:
		markers.pop_front().node.queue_free()

func _hotkeys() -> void:
	if Input.is_action_just_pressed("lab_reset"):
		reset_duel()
	if Input.is_action_just_pressed("lab_help"):
		hud.show_help = not hud.show_help
	if Input.is_action_just_pressed("lab_tuning"):
		hud.show_tuning = not hud.show_tuning
	if Input.is_action_just_pressed("lab_debug"):
		flags.debug = not flags.debug
	if Input.is_action_just_pressed("lab_trails"):
		flags.trails = not flags.trails
	if Input.is_action_just_pressed("lab_arcs"):
		flags.arcs = not flags.arcs
	if Input.is_action_just_pressed("lab_labels"):
		flags.labels = not flags.labels
	if Input.is_action_just_pressed("lab_slow_motion"):
		Engine.time_scale = 0.3 if Engine.time_scale >= 1.0 else 1.0
	var count: int = lab.loadouts.size()
	for step: Array in [["lab_player_weapon_next", 1, true], ["lab_player_weapon_prev", -1, true],
			["lab_opponent_weapon_next", 1, false], ["lab_opponent_weapon_prev", -1, false]]:
		if Input.is_action_just_pressed(step[0]):
			if step[2]:
				player_loadout = posmod(player_loadout + step[1], count)
			else:
				opponent_loadout = posmod(opponent_loadout + step[1], count)
			set_loadouts(lab.loadouts[player_loadout].id, lab.loadouts[opponent_loadout].id)
	if Input.is_action_just_pressed("lab_opponent_mode"):
		opponent.mode = Opponent.MODES[(Opponent.MODES.find(opponent.mode) + 1) % Opponent.MODES.size()]
		opponent.state.set_guard(false)
	if Input.is_action_just_pressed("lab_world_condition"):
		var conditions: Array = lab.combat.get("world_conditions", [])
		world_condition = "" if world_condition != "" or conditions.is_empty() else str(conditions[0].id)
	if Input.is_action_just_pressed("lab_dummy_guard"):
		var guards := Opponent.DUMMY_GUARDS
		opponent.dummy_guard = guards[(guards.find(opponent.dummy_guard) + 1) % guards.size()]

## Seconds from an idle stance to first possible contact for a horizontal cut (HUD).
func contact_estimate(actor: Node) -> float:
	var h: Dictionary = actor.state.h
	var rest := Geometry.rest_pose(tuning)
	var chamber := Geometry.chamber_pose("right_to_left", tuning)
	var windup := maxf(tuning.min_windup, Handling.rest_to_rest(rest.dir.angle_to(chamber.dir), h.accel, h.max_speed))
	return windup + Handling.time_from_rest(Geometry.swing_start(tuning), h.accel, h.max_speed)

func _block(point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = point
	mesh.scale = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	add_child(mesh)
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _build_arena() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("1f2a30")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("a8bcc2")
	world.environment.ambient_light_energy = 0.5
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	_block(Vector3(0.0, -0.3, 0.0), Vector3(18.0, 0.6, 18.0), Color("3e474a"))
	for side: float in [-1.0, 1.0]:
		_block(Vector3(side * 9.0, 0.6, 0.0), Vector3(0.6, 1.2, 18.0), Color("323b3f"))
		_block(Vector3(0.0, 0.6, side * 9.0), Vector3(18.0, 1.2, 0.6), Color("323b3f"))
	# Metre grid to judge reach.
	for i in range(-8, 9):
		for axis: int in [0, 1]:
			var line := MeshInstance3D.new()
			line.mesh = BoxMesh.new()
			line.scale = Vector3(16.0, 0.004, 0.015) if axis == 0 else Vector3(0.015, 0.004, 16.0)
			line.position = Vector3(0.0, 0.003, i) if axis == 0 else Vector3(i, 0.003, 0.0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.6, 0.58, 0.35 if i % 2 else 0.6)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			line.material_override = mat
			add_child(line)
