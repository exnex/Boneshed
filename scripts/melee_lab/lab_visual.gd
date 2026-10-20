extends Node3D
## Lab presentation. Reads rules state only; never decides contact or timing. The
## weapon mesh is placed at the rules pose, so what is drawn is the hit segment.
## Overlays (toggled by the arena through the shared `flags` dictionary):
## telegraph arcs, tip/hand trails, debug capsules and guard segments, intent labels.

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const TRAIL_SECONDS := 0.35
const DIRECTION_COLORS := {"right_to_left": Color("ff8a3d"), "left_to_right": Color("3dd6ff"), "overhead": Color("ffd84a"),
	"diag_right": Color("ff5fa2"), "diag_left": Color("8b7bff"), "thrust": Color("7dff6a")}
const DIRECTION_TEXT := {"right_to_left": "◀ RIGHT→LEFT", "left_to_right": "LEFT→RIGHT ▶", "overhead": "▼ OVERHEAD",
	"diag_right": "◣ HIGH RIGHT", "diag_left": "◢ HIGH LEFT", "thrust": "● THRUST"}

var actor: CharacterBody3D
var flags: Dictionary = {"trails": true, "arcs": true, "debug": false, "labels": true}
var root: Node3D
var weapon_root: Node3D
var blade: MeshInstance3D
var blade_material: StandardMaterial3D
var arms: Array[MeshInstance3D] = []
var body_material: StandardMaterial3D
var arc_mesh := ImmediateMesh.new()
var trail_mesh := ImmediateMesh.new()
var debug_mesh := ImmediateMesh.new()
var label: Label3D
var trail: Array[Dictionary] = []

func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	body_material = _material(actor.body_color)
	_part(CapsuleMesh.new(), Vector3(0.0, 1.05, 0.0), Vector3(0.62, 0.5, 0.46), body_material)
	_part(SphereMesh.new(), Vector3(0.0, 1.75, 0.0), Vector3(0.32, 0.36, 0.32), _material(Color("c2bfae")))
	for side: float in [-1.0, 1.0]:
		_part(BoxMesh.new(), Vector3(side * 0.16, 0.42, 0.0), Vector3(0.18, 0.84, 0.2), body_material)
	for i in range(2):
		arms.append(_part(BoxMesh.new(), Vector3.ZERO, Vector3.ONE, body_material))
	weapon_root = Node3D.new()
	root.add_child(weapon_root)
	blade_material = _material(Color("c8d0cc"), true)
	blade = _part(BoxMesh.new(), Vector3.ZERO, Vector3.ONE, blade_material, weapon_root)
	_part(BoxMesh.new(), Vector3(0.0, 0.0, 0.02), Vector3(0.3, 0.07, 0.07), _material(Color("a68f63")), weapon_root)
	for mesh: ImmediateMesh in [arc_mesh, trail_mesh, debug_mesh]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = mesh == debug_mesh
		instance.material_override = mat
		# Trails and debug shapes are drawn in world space.
		instance.top_level = mesh != arc_mesh
		(root if mesh == arc_mesh else self).add_child(instance)
	label = Label3D.new()
	label.position = Vector3(0.0, 2.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.no_depth_test = true
	add_child(label)
	rebuild()

func rebuild() -> void:
	if blade == null or actor.state == null:
		return
	var length: float = actor.state.h.length
	var staff: bool = actor.state.h["class"] == "staff"
	blade.position = Vector3(0.0, 0.0, -length * 0.5)
	blade.scale = Vector3(0.07 if staff else 0.05, 0.07 if staff else 0.11, length)
	trail.clear()
	sync(0.0)

func sync(delta: float) -> void:
	var state: State = actor.state
	root.rotation = Vector3(0.0, actor.yaw(), 0.0)
	root.position = Vector3.ZERO
	if state.phase == State.Phase.DEAD:
		root.rotation.z = PI / 2.0
		root.position.y = 0.3
	weapon_root.position = state.hand
	weapon_root.basis = _look(state.dir)
	_sync_arms(state)
	_sync_colors(state)
	_draw_arc(state)
	_record_trail(state, delta)
	_draw_debug(state)
	_sync_label(state)

func _look(direction: Vector3) -> Basis:
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	return Basis.looking_at(direction, up)

func _sync_arms(state: State) -> void:
	var grip := state.hand
	var shoulders := [Vector3(0.3, 1.42, 0.0), Vector3(-0.3, 1.42, 0.0)]
	var two_handed: bool = state.h.two_handed
	for i in range(2):
		var target: Vector3 = grip if i == 0 or two_handed else Vector3(-0.42, 0.95, -0.15)
		if i == 1 and two_handed:
			target = grip + state.dir * 0.18
		var start: Vector3 = shoulders[i]
		var offset := target - start
		arms[i].position = (start + target) * 0.5
		arms[i].scale = Vector3(0.13, maxf(0.05, offset.length()), 0.13)
		arms[i].quaternion = Quaternion(Vector3.UP, offset.normalized())

func _sync_colors(state: State) -> void:
	var color := Color("c8d0cc")
	var glow := 0.0
	match state.phase:
		State.Phase.WINDUP:
			color = DIRECTION_COLORS.get(state.direction, Color.ORANGE)
			glow = 0.35 + 0.65 * minf(1.0, state.windup_time / 0.35)
		State.Phase.SWING:
			color = Color("ff4a2e") if state.live_value >= 0.0 and not state.hit_consumed else DIRECTION_COLORS.get(state.direction, Color.ORANGE)
			glow = 1.2
		State.Phase.BROKEN:
			color = Color("b06bff")
			glow = 0.8
	if state.phase == State.Phase.IDLE and state.guarding:
		color = Color("f6e7a6") if state.guard_age <= state.deflect_window else Color("8fc7ff")
		glow = 1.0 if state.guard_age <= state.deflect_window else 0.35
	blade_material.albedo_color = color
	blade_material.emission = color
	blade_material.emission_energy_multiplier = glow

## Telegraph: the coming arc of the tip, drawn from the chamber pose during windup.
func _draw_arc(state: State) -> void:
	arc_mesh.clear_surfaces()
	if not flags.arcs or state.phase not in [State.Phase.WINDUP, State.Phase.SWING] or state.direction == "":
		return
	var color: Color = DIRECTION_COLORS.get(state.direction, Color.WHITE)
	color.a = 0.75 if state.phase == State.Phase.WINDUP else 0.3
	var t := state.t
	var length: float = state.h.length
	arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	if state.direction == Geometry.THRUST:
		for e: float in [0.0, t.thrust_extension]:
			var pose := Geometry.thrust_pose(e, t)
			var tip := Geometry.tip(pose, length)
			arc_mesh.surface_set_color(color)
			arc_mesh.surface_add_vertex(tip + Vector3.UP * 0.06)
			arc_mesh.surface_add_vertex(tip - Vector3.UP * 0.06)
	else:
		var start := Geometry.swing_live(t)
		var end := Geometry.swing_end(state.direction, t)
		var steps := 24
		for i in range(steps + 1):
			var theta := lerpf(start, end, float(i) / steps)
			var pose := Geometry.swing_pose(state.direction, theta, t)
			var c := color
			c.a *= 0.35 + 0.65 * float(i) / steps
			arc_mesh.surface_set_color(c)
			arc_mesh.surface_add_vertex(Geometry.tip(pose, length))
			arc_mesh.surface_add_vertex(pose.hand + pose.dir * length * 0.7)
	arc_mesh.surface_end()

func _record_trail(state: State, delta: float) -> void:
	var xf: Transform3D = actor.xform()
	for point: Dictionary in trail:
		point.age += delta
	while not trail.is_empty() and trail[0].age > TRAIL_SECONDS:
		trail.pop_front()
	if delta > 0.0:
		trail.append({"age": 0.0, "hand": xf * state.hand, "tip": xf * Geometry.tip({"hand": state.hand, "dir": state.dir}, state.h.length),
			"live": state.is_live()})
	trail_mesh.clear_surfaces()
	if not flags.trails or trail.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for point: Dictionary in trail:
		var c := Color("ff4a2e") if point.live else Color("e8e2cf")
		c.a = 0.55 * (1.0 - point.age / TRAIL_SECONDS)
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(point.tip)
		trail_mesh.surface_add_vertex(point.hand.lerp(point.tip, 0.55))
	trail_mesh.surface_end()

## Debug: body capsule axis rings and the weapon segment exactly as contact sees them.
func _draw_debug(state: State) -> void:
	debug_mesh.clear_surfaces()
	if not flags.debug:
		return
	var t := state.t
	var xf: Transform3D = actor.xform()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var body_color := Color(0.4, 1.0, 0.6, 0.8)
	for y: float in [t.body_bottom, (t.body_bottom + t.body_top) * 0.5, t.body_top]:
		for i in range(16):
			for j: int in [i, i + 1]:
				var a := TAU * j / 16.0
				debug_mesh.surface_set_color(body_color)
				debug_mesh.surface_add_vertex(xf * Vector3(cos(a) * t.body_radius, y, sin(a) * t.body_radius))
	for x: float in [-1.0, 1.0]:
		for y: float in [t.body_bottom, t.body_top]:
			debug_mesh.surface_set_color(body_color)
			debug_mesh.surface_add_vertex(xf * Vector3(x * t.body_radius, y, 0.0))
	var seg_color := Color(0.4, 0.7, 1.0) if state.guarding else (Color(1.0, 0.3, 0.2) if state.is_live() else Color(0.8, 0.8, 0.8, 0.6))
	debug_mesh.surface_set_color(seg_color)
	debug_mesh.surface_add_vertex(xf * state.hand)
	debug_mesh.surface_set_color(seg_color)
	debug_mesh.surface_add_vertex(xf * Geometry.tip({"hand": state.hand, "dir": state.dir}, state.h.length))
	debug_mesh.surface_end()

func _sync_label(state: State) -> void:
	var text := ""
	var color := Color.WHITE
	if flags.labels and state.phase in [State.Phase.WINDUP, State.Phase.SWING] and state.direction != "":
		text = DIRECTION_TEXT.get(state.direction, "")
		color = DIRECTION_COLORS.get(state.direction, Color.WHITE)
	elif state.phase == State.Phase.BROKEN:
		text = "GUARD BROKEN"
		color = Color("b06bff")
	elif state.phase == State.Phase.RECOIL:
		text = "RECOIL"
		color = Color("f6e7a6")
	label.text = text
	label.modulate = color

func _part(mesh: Mesh, point: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.scale = size
	instance.material_override = mat
	(parent if parent != null else root).add_child(instance)
	return instance

static func _material(color: Color, glow := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.0
	return mat
