extends Node3D
## Presentation of one Adaptive Combat Lab fighter: the showcase's skinned humanoid
## (with the Marrow Arm module when the body has it), the generated object mesh, the
## active feature's telegraph glow and trail, hit popups and an optional debug overlay
## (grip candidates, chosen grips, contact capsules, body capsules).
##
## It reads the rules fighter every frame and never writes to it. The object node's
## local transform is the rules' object transform, so the drawn object, the hands' grip
## targets and the contact capsule are the same rigid placement of one descriptor.

const CharacterBuilder = preload("res://scripts/visual_showcase/character_builder.gd")
const PoseModifier = preload("res://scripts/visual_showcase/pose_modifier.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const AdaptivePose = preload("res://scripts/adaptive_lab/adaptive_pose.gd")
const Mesher = preload("res://scripts/adaptive_lab/object_mesher.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")
const TRAIL_LENGTH := 22

var fighter: RefCounted
var kind := "pilgrim"
var character: Node3D
var skeleton: Skeleton3D
var modifier: PoseModifier
var pose_solver: AdaptivePose
var object_node: Node3D
var canopy: Node3D
var glow: MeshInstance3D
var glow_material: StandardMaterial3D
var trail_mesh := ImmediateMesh.new()
var debug_mesh := ImmediateMesh.new()
var trail: Array = []
var show_debug := false
var show_trail := true
var last_result: Dictionary = {}
var analysis: Dictionary = {}
var triangles := 0
var object_triangles := 0
var _seen_events := 0

func setup(rules_fighter: RefCounted, body_kind: String) -> void:
	fighter = rules_fighter
	kind = body_kind
	for mesh: ImmediateMesh in [trail_mesh, debug_mesh]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.top_level = true
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = mesh == debug_mesh
		instance.material_override = mat
		add_child(instance)
	glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_color = Color(1.0, 0.6, 0.2, 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	glow = MeshInstance3D.new()
	glow.name = "FeatureGlow"
	glow.mesh = sphere
	glow.material_override = glow_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.top_level = true
	add_child(glow)
	rebuild()

## Rebuilds body and object after an equipment or body change.
func rebuild() -> void:
	if character != null:
		character.queue_free()
	if object_node != null:
		object_node.queue_free()
		object_node = null
		canopy = null
	var body: Dictionary = fighter.body
	var builder := CharacterBuilder.new(body.proportions, kind)
	var built := builder.build({"armor": [], "marrow_arm": "marrow_arm" in body.modifications})
	character = built.root
	skeleton = built.skeleton
	triangles = built.triangles
	add_child(character)
	modifier = PoseModifier.new()
	modifier.name = "PoseModifier"
	modifier.active = true
	modifier.influence = 1.0
	skeleton.add_child(modifier)
	pose_solver = AdaptivePose.new(body)
	analysis = Analysis.analyse(fighter.descriptor)
	var mesh := Mesher.build(fighter.descriptor)
	object_node = mesh.node
	canopy = mesh.canopy
	object_triangles = mesh.triangles
	add_child(object_node)
	trail.clear()
	_seen_events = fighter.events.size()
	sync(0.0)

func view() -> Dictionary:
	var inv := Basis(Vector3.UP, fighter.yaw).inverse()
	var a_local: Vector3 = Vector3.ZERO
	if fighter.has_hold():
		a_local = fighter.action.a_local if fighter.state == "attack" else fighter.caps.ready_frame.a_local
	return {"pose": fighter.pose, "hold": fighter.caps.get("hold"), "a_local": a_local, "state": fighter.state,
		"state_time": fighter.state_time, "velocity": inv * (fighter.velocity as Vector3), "dodge_dir": inv * (fighter.dodge_dir as Vector3)}

func sync(delta: float) -> void:
	if fighter == null or pose_solver == null:
		return
	transform = fighter.xform()
	last_result = pose_solver.solve(view(), delta)
	modifier.globals = last_result.bones
	if fighter.has_hold() and not (fighter.pose as Dictionary).is_empty():
		object_node.transform = fighter.pose.object
	else:
		# Unusable for this body: the object lies at the fighter's feet.
		object_node.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.45, 0.06, -0.2))
	if canopy != null:
		Mesher.set_openness(canopy, fighter.openness if fighter.caps.get("guard") != null and fighter.caps.guard.kind == "deploy_cover" else 0.0)
	_sync_glow()
	_sync_trail()
	_draw_debug()
	_popups()

func _sync_glow() -> void:
	var active: bool = fighter.state == "attack" and fighter.pose.get("phase", "") in ["windup", "active"]
	if not active:
		glow.visible = false
		return
	var feature: Dictionary = fighter.action.feature
	var world: Transform3D = fighter.xform() * (fighter.pose.object as Transform3D)
	glow.visible = true
	glow.global_position = world * (feature.pos as Vector3)
	glow.scale = Vector3.ONE * (float(feature.radius) + 0.025)
	var heavy: bool = fighter.action.heavy
	var windup: bool = fighter.pose.phase == "windup"
	var color := Color(1.0, 0.15, 0.08) if heavy else Color(1.0, 0.65, 0.2)
	if not windup:
		color = Color(1.0, 0.95, 0.85)
	color.a = (0.3 + 0.35 * clampf(float(fighter.state_time) / float(fighter.action.windup), 0.0, 1.0)) if windup else 0.45
	glow_material.albedo_color = color

func _sync_trail() -> void:
	trail_mesh.clear_surfaces()
	if fighter.state == "attack" and fighter.pose.get("phase", "") in ["active", "recovery"] and show_trail:
		var world: Transform3D = fighter.xform() * (fighter.pose.object as Transform3D)
		var feature: Dictionary = fighter.action.feature
		var center := world * (feature.pos as Vector3)
		var along: Vector3 = world.basis * (fighter.action.a_local as Vector3)
		var width := maxf(float(feature.radius), 0.05)
		trail.append([center - along * width, center + along * width * 0.3, fighter.pose.phase == "active"])
		if trail.size() > TRAIL_LENGTH:
			trail.pop_front()
	elif not trail.is_empty():
		trail.pop_front()
	if trail.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(trail.size()):
		var alpha := float(i) / trail.size()
		var hot: bool = trail[i][2]
		var c := Color(1.0, 0.9, 0.7, alpha * 0.7) if hot else Color(0.8, 0.8, 0.9, alpha * 0.3)
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(trail[i][0])
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(trail[i][1])
	trail_mesh.surface_end()

func _popups() -> void:
	var events: Array = fighter.events
	if _seen_events > events.size():
		_seen_events = 0
	while _seen_events < events.size():
		var e: Dictionary = events[_seen_events]
		_seen_events += 1
		var text := ""
		var color := Color.WHITE
		match str(e.kind):
			"received":
				var outcome: String = e.detail.outcome
				text = {"hit": "HIT", "punish": "PUNISH", "blocked": "BLOCK", "deflected": "DEFLECT"}.get(outcome, outcome)
				color = {"hit": Color(1, 0.4, 0.3), "punish": Color(1, 0.2, 0.2), "blocked": Color(0.7, 0.8, 1), "deflected": Color(1, 0.9, 0.4)}.get(outcome, Color.WHITE)
			"posture_broken":
				text = "POSTURE BROKEN"
				color = Color(1, 0.75, 0.2)
			"light_unsupported", "heavy_unsupported", "guard_unsupported":
				text = "%s: NOT POSSIBLE" % str(e.kind).get_slice("_", 0).to_upper()
				color = Color(0.7, 0.7, 0.7)
			"evaded":
				text = "EVADED"
				color = Color(0.6, 1, 0.7)
		if text != "":
			_popup(text, color)

func _popup(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 44
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, float(fighter.body.stature) + 0.25, 0.0)
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.5, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)

func _draw_debug() -> void:
	debug_mesh.clear_surfaces()
	if not show_debug:
		return
	var xf: Transform3D = fighter.xform()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var body: Array = fighter.body_capsule()
	_capsule(body[0], body[1], body[2], Color(0.4, 0.6, 1.0, 0.6))
	if fighter.has_hold() and not (fighter.pose as Dictionary).is_empty():
		var world: Transform3D = xf * (fighter.pose.object as Transform3D)
		for g: Dictionary in analysis.grips:
			_cross(world * (g.point as Vector3), 0.012, Color(0.3, 1.0, 0.4, 0.7))
		for hand: String in fighter.caps.hold.grips:
			_cross(world * (fighter.caps.hold.grips[hand] as Vector3), 0.04, Color(0.2, 1.0, 0.2, 1.0))
		for f: Dictionary in analysis.features:
			var cap := Motion.contact_capsule(f, world)
			var c := Color(1, 0.3, 0.2, 0.5) if f.channel != "blunt" else Color(1, 0.8, 0.3, 0.4)
			_capsule(cap[0], cap[1], cap[2], c)
		if fighter.state == "attack":
			var cap: Array = fighter.contact_at(fighter.state_time)
			var hot: bool = fighter.pose.get("phase", "") == "active"
			_capsule(cap[0], cap[1], cap[2], Color(1, 0.1, 0.1, 1.0) if hot else Color(1, 0.6, 0.1, 0.9))
	debug_mesh.surface_end()

func _cross(p: Vector3, s: float, c: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		debug_mesh.surface_set_color(c)
		debug_mesh.surface_add_vertex(p - axis * s)
		debug_mesh.surface_set_color(c)
		debug_mesh.surface_add_vertex(p + axis * s)

func _capsule(a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var axis := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector3.UP
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.BACK).normalized()
	var v := axis.cross(u)
	for i in range(12):
		var t0 := TAU * i / 12.0
		var t1 := TAU * (i + 1) / 12.0
		for center: Vector3 in [a, b]:
			debug_mesh.surface_set_color(c)
			debug_mesh.surface_add_vertex(center + (u * cos(t0) + v * sin(t0)) * r)
			debug_mesh.surface_set_color(c)
			debug_mesh.surface_add_vertex(center + (u * cos(t1) + v * sin(t1)) * r)
		if i % 3 == 0:
			debug_mesh.surface_set_color(c)
			debug_mesh.surface_add_vertex(a + (u * cos(t0) + v * sin(t0)) * r)
			debug_mesh.surface_set_color(c)
			debug_mesh.surface_add_vertex(b + (u * cos(t0) + v * sin(t0)) * r)

## Model-space grip socket of a hand (tests compare it with the rules' grip target).
func grip_socket(hand: String) -> Vector3:
	var socket := "grip_r" if hand == "hand_r" else "grip_l"
	return Rig.socket_global(last_result.bones, socket).origin
