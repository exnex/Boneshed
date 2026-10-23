extends Node3D
## Presentation of one Adaptive Combat Lab fighter: the showcase's skinned humanoid,
## the object mesh (Research Lab import or the v0 comparison generator), the active
## feature's telegraph glow and trail, hit popups and optional debug overlays (grip
## intervals, chosen grips, contact capsules, body capsules, planned contact paths).
##
## It reads the rules fighter every frame and never writes to it. The object node's
## local transform is the rules' object transform, so the drawn object, the hands' grip
## targets and the contact capsule are the same rigid placement of one descriptor.
## Unlocked hinged parts swing in presentation only (the rules give them no contact).

const CharacterBuilder = preload("res://scripts/visual_showcase/character_builder.gd")
const PoseModifier = preload("res://scripts/visual_showcase/pose_modifier.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const MeshKit = preload("res://scripts/visual_showcase/mesh_kit.gd")
const AdaptivePose = preload("res://scripts/adaptive_lab/adaptive_pose.gd")
const Mesher = preload("res://scripts/adaptive_lab/object_mesher.gd")
const LabMesher = preload("res://scripts/adaptive_lab/lab_mesher.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")
const Imp = preload("res://scripts/adaptive_lab/lab_import.gd")
const TRAIL_LENGTH := 22

var fighter: RefCounted
var kind := "pilgrim"
var character: Node3D
var skeleton: Skeleton3D
var modifier: PoseModifier
var pose_solver: AdaptivePose
var object_node: Node3D
var canopy: Node3D
var articulated: Array = []
var hinge_state: Array = []
var glow: MeshInstance3D
var glow_material: StandardMaterial3D
var regen_glow: OmniLight3D
var trail_mesh := ImmediateMesh.new()
var debug_mesh := ImmediateMesh.new()
var path_mesh := ImmediateMesh.new()
var trail: Array = []
var show_debug := false
var show_trail := true
var show_paths := false
var last_result: Dictionary = {}
var analysis: Dictionary = {}
var triangles := 0
var object_triangles := 0
var _seen_events := 0
var _prev_anchor: Dictionary = {}
var _last_regen := 0.0

func setup(rules_fighter: RefCounted, body_kind: String) -> void:
	fighter = rules_fighter
	kind = body_kind
	for mesh: ImmediateMesh in [trail_mesh, debug_mesh, path_mesh]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.top_level = true
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = mesh != trail_mesh
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
	regen_glow = OmniLight3D.new()
	regen_glow.name = "RegenGlow"
	regen_glow.light_color = Color(0.55, 1.0, 0.6)
	regen_glow.omni_range = 1.2
	regen_glow.light_energy = 0.0
	add_child(regen_glow)
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
	var visuals: Array = body.get("visuals", [])
	var builder := CharacterBuilder.new(body.proportions, kind)
	var built := builder.build({"armor": [], "marrow_arm": "handless_bone_limb" in visuals})
	character = built.root
	skeleton = built.skeleton
	triangles = built.triangles
	if "marrow_graft" in visuals:
		triangles += _graft(body.proportions)
	add_child(character)
	modifier = PoseModifier.new()
	modifier.name = "PoseModifier"
	modifier.active = true
	modifier.influence = 1.0
	skeleton.add_child(modifier)
	pose_solver = AdaptivePose.new(body)
	analysis = Solver.analyse(fighter.descriptor)
	var mesh: Dictionary
	if fighter.descriptor.get("schema") == Imp.CONTRACT:
		mesh = LabMesher.build(fighter.descriptor)
	else:
		mesh = Mesher.build(fighter.descriptor)
	object_node = mesh.node
	canopy = mesh.get("canopy")
	articulated = mesh.get("articulated", [])
	hinge_state = []
	for _a: Variant in articulated:
		hinge_state.append({"angle": 0.0, "speed": 0.0})
	_prev_anchor = {}
	object_triangles = mesh.triangles
	add_child(object_node)
	trail.clear()
	_seen_events = fighter.events.size()
	_last_regen = fighter.regenerated
	sync(0.0)

## Marrow graft (illustrative modification): bone ridges and marrow along the left
## forearm, skinned to it. The arm and hand are unchanged.
func _graft(proportions: Dictionary) -> int:
	var j := Rig.joints(proportions)
	var kit := MeshKit.new()
	var low := {Rig.bone_index("lowerarm_l"): 1.0}
	var elbow: Vector3 = j.lowerarm_l
	var wrist: Vector3 = j.hand_l
	var basis := MeshKit.basis_from_y((wrist - elbow).normalized())
	kit.tube("marrow", elbow + basis.x * 0.028, wrist + basis.x * 0.022, 0.018, 0.012, low, 8)
	for k in range(4):
		var at := elbow.lerp(wrist, 0.15 + 0.22 * k)
		kit.tube("bone", at + basis.x * 0.03, at + basis.x * 0.07 + basis.y * 0.025, 0.011, 0.001, low, 5)
	kit.blob("bone", Transform3D(Basis.IDENTITY, elbow + basis.x * 0.025), Vector3(0.03, 0.03, 0.03), low, 8, 5)
	var instance := MeshInstance3D.new()
	instance.name = "Module_marrow_graft"
	instance.mesh = kit.commit()
	instance.skin = skeleton.create_skin_from_rest_transforms()
	instance.skeleton = NodePath("..")
	skeleton.add_child(instance)
	return kit.triangle_count

func view() -> Dictionary:
	var inv := Basis(Vector3.UP, fighter.yaw).inverse()
	var a_local: Vector3 = Vector3.ZERO
	var hold: Variant = fighter.caps.get("hold")
	if fighter.has_hold() and not fighter.unarmed():
		a_local = fighter.action.a_local if fighter.state == "attack" else fighter.caps.ready_frame.a_local
	var out := {"pose": fighter.pose, "hold": hold, "a_local": a_local, "state": fighter.state,
		"state_time": fighter.state_time, "velocity": inv * (fighter.velocity as Vector3), "dodge_dir": inv * (fighter.dodge_dir as Vector3)}
	if fighter.state == "attack":
		out.feet = Motion.feet(fighter.action, fighter.state_time, fighter.spacing_extra)
	return out

func sync(delta: float) -> void:
	if fighter == null or pose_solver == null:
		return
	transform = fighter.xform()
	last_result = pose_solver.solve(view(), delta)
	modifier.globals = last_result.bones
	if fighter.has_hold() and not fighter.unarmed() and not (fighter.pose as Dictionary).is_empty():
		object_node.transform = fighter.pose.object
	else:
		# Not wieldable by this body: the object lies at the fighter's side.
		object_node.transform = Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(-0.8, _ground_offset(), 0.35))
	if canopy != null:
		Mesher.set_openness(canopy, fighter.openness if fighter.caps.get("guard") != null and fighter.caps.guard.kind == "deploy_cover" else 0.0)
	_swing_hinges(delta)
	_sync_glow()
	_sync_trail()
	_draw_debug()
	_draw_paths()
	_popups()
	_regen(delta)

## Height that rests a lying object on the floor (its largest transverse half-size).
func _ground_offset() -> float:
	if fighter.descriptor.get("schema") != Imp.CONTRACT:
		return 0.06
	var best := 0.03
	for p: Dictionary in fighter.descriptor.parts:
		best = maxf(best, maxf((p.radii as Vector2).x, (p.radii as Vector2).y))
	return best

## Presentation-only secondary motion: an unlocked hinge lags the object's motion
## (damped spring toward a sway driven by the anchor's velocity), within its limits.
func _swing_hinges(delta: float) -> void:
	if articulated.is_empty() or delta <= 0.0:
		return
	var world: Transform3D = global_transform * object_node.transform
	for i in range(articulated.size()):
		var a: Dictionary = articulated[i]
		var anchor: Vector3 = world * (a.anchor as Vector3)
		var prev: Vector3 = _prev_anchor.get(i, anchor)
		var velocity := (anchor - prev) / delta
		_prev_anchor[i] = anchor
		var hinge_axis := (world.basis * (a.axis as Vector3)).normalized()
		var lag := velocity.cross(hinge_axis).length() * 0.35
		var limits: Vector2 = a.limits
		var target := clampf(limits.x + lag + 0.2, limits.x, limits.y)
		var st: Dictionary = hinge_state[i]
		st.speed += (-(st.angle - target) * 120.0 - st.speed * 14.0) * delta
		st.angle = clampf(st.angle + st.speed * delta, limits.x, limits.y)
		(a.node as Node3D).transform = Transform3D(Basis(a.axis, st.angle), a.anchor)

func _regen(delta: float) -> void:
	var gained: float = fighter.regenerated - _last_regen
	_last_regen = fighter.regenerated
	var target := 1.4 if gained > 0.0 else 0.0
	regen_glow.light_energy = move_toward(regen_glow.light_energy, target, delta * 4.0)
	if fighter.has_hold() and not (fighter.pose as Dictionary).is_empty() and fighter.pose.hands.has("hand_l"):
		regen_glow.position = (fighter.pose.hands.hand_l as Vector3) + Vector3(0.0, 0.05, 0.0)
	else:
		regen_glow.position = Vector3(-0.3, 1.2, 0.0)

func _active_feature() -> Dictionary:
	var w: int = fighter.pose.get("window", -1)
	if w < 0:
		w = 0
		var windows: Array = fighter.action.get("windows_abs", [])
		for i in range(windows.size()):
			if fighter.state_time >= float(windows[i].t1):
				w = mini(i + 1, windows.size() - 1)
	return Motion.window_feature(fighter.action, w)

func _sync_glow() -> void:
	var active: bool = fighter.state == "attack" and fighter.pose.get("phase", "") in ["windup", "active"]
	if not active:
		glow.visible = false
		return
	var feature := _active_feature()
	var world: Transform3D = fighter.xform() * (fighter.pose.object as Transform3D)
	glow.visible = true
	glow.global_position = world * (feature.pos as Vector3)
	glow.scale = Vector3.ONE * (float(feature.radius) + 0.025)
	var heavy: bool = fighter.action.heavy
	var hot: bool = int(fighter.pose.get("window", -1)) >= 0
	var color := Color(1.0, 0.15, 0.08) if heavy else Color(1.0, 0.65, 0.2)
	if hot:
		color = Color(1.0, 0.95, 0.85)
	color.a = (0.3 + 0.35 * clampf(float(fighter.state_time) / float(fighter.action.windup), 0.0, 1.0)) if not hot else 0.5
	glow_material.albedo_color = color

func _sync_trail() -> void:
	trail_mesh.clear_surfaces()
	if fighter.state == "attack" and fighter.pose.get("phase", "") in ["active", "recovery"] and show_trail:
		var world: Transform3D = fighter.xform() * (fighter.pose.object as Transform3D)
		var feature := _active_feature()
		var center := world * (feature.pos as Vector3)
		var toward: Vector3 = (world * (fighter.caps.hold.center as Vector3) - center)
		var along := toward.normalized() if toward.length() > 0.01 else Vector3.UP
		var width := clampf(float(feature.radius) * 2.0, 0.08, 0.3)
		trail.append([center, center + along * width, int(fighter.pose.get("window", -1)) >= 0])
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
		var c := Color(1.0, 0.9, 0.7, alpha * 0.75) if hot else Color(0.8, 0.8, 0.9, alpha * 0.3)
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
				if e.detail.get("pulled", false):
					text += " · PULLED"
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
	label.font_size = 40
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
	if fighter.has_hold() and not fighter.unarmed() and not (fighter.pose as Dictionary).is_empty():
		var world: Transform3D = xf * (fighter.pose.object as Transform3D)
		for iv: Dictionary in analysis.intervals:
			var c := Color(0.3, 1.0, 0.4, 0.8) if iv.usable else Color(1.0, 0.3, 0.3, 0.8)
			_line(world * (iv.a as Vector3), world * (iv.b as Vector3), c)
		for hand: String in fighter.caps.hold.grips:
			_cross(world * Motion.slid_grip(fighter.caps.hold, hand, fighter.pose.get("slide", 0.0)), 0.04, Color(0.2, 1.0, 0.2, 1.0))
		for f: Dictionary in analysis.features:
			var cap := Motion.contact_capsule(f, world)
			var c := Color(1, 0.3, 0.2, 0.5) if f.channel != "blunt" else (Color(0.6, 0.7, 1.0, 0.4) if f.get("soft", false) else Color(1, 0.8, 0.3, 0.4))
			_capsule(cap[0], cap[1], cap[2], c)
	if fighter.state == "attack":
		var w: int = fighter.pose.get("window", -1)
		var cap: Array = fighter.contact_at(fighter.state_time, maxi(w, 0))
		_capsule(cap[0], cap[1], cap[2], Color(1, 0.1, 0.1, 1.0) if w >= 0 else Color(1, 0.6, 0.1, 0.9))
	debug_mesh.surface_end()

## Planned contact path of the current attack (every window, sampled from the rules)
## — what the rules will test, drawn over what the player sees.
func _draw_paths() -> void:
	path_mesh.clear_surfaces()
	if not show_paths or fighter.state != "attack":
		return
	var windows: Array = fighter.action.windows_abs
	path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for w in range(windows.size()):
		var prev: Variant = null
		for i in range(13):
			var t := lerpf(float(windows[w].t0), float(windows[w].t1), i / 12.0)
			var cap: Array = fighter.contact_at(t, w)
			var p: Vector3 = ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5
			if prev != null:
				_line_on(path_mesh, prev, p, Color(0.2, 0.9, 1.0, 0.9) if w == 0 else Color(1.0, 0.3, 0.9, 0.9))
			prev = p
	path_mesh.surface_end()

func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_line_on(debug_mesh, a, b, c)

func _line_on(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(b)

func _cross(p: Vector3, s: float, c: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(p - axis * s, p + axis * s, c)

func _capsule(a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var axis := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector3.UP
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.BACK).normalized()
	var v := axis.cross(u)
	for i in range(12):
		var t0 := TAU * i / 12.0
		var t1 := TAU * (i + 1) / 12.0
		for center: Vector3 in [a, b]:
			_line(center + (u * cos(t0) + v * sin(t0)) * r, center + (u * cos(t1) + v * sin(t1)) * r, c)
		if i % 3 == 0:
			_line(a + (u * cos(t0) + v * sin(t0)) * r, b + (u * cos(t0) + v * sin(t0)) * r, c)

## Model-space grip socket of a hand (tests compare it with the rules' grip target).
func grip_socket(hand: String) -> Vector3:
	var socket := "grip_r" if hand == "hand_r" else "grip_l"
	return Rig.socket_global(last_result.bones, socket).origin
