extends "res://scripts/melee_lab/lab_visual.gd"
## Showcase presentation for a melee lab duelist: a rigged, skinned humanoid with
## fitted weapon, armor and (optionally) the Marrow Arm, posed every frame from the
## rules state by pose_solver.gd. Reads rules state only; never decides contact.
##
## The lab overlays (telegraph arcs, trails, debug segment, labels) are inherited and
## behave as in the lab. The lab's whole-blade telegraph colour becomes an edge glow on
## the real blade, with the same colours and the same phase logic.
##
## What it reads: actor.state (phase, hand, dir, direction, guard, handling `h`,
## resources.armor ids, stamina/status for labels), actor.velocity/facing/dodge_direction
## and the opponent's position (head look). `look` (set by the arena) chooses the body
## kind and the Marrow Arm.

const CharacterBuilder = preload("res://scripts/visual_showcase/character_builder.gd")
const WeaponBuilder = preload("res://scripts/visual_showcase/weapon_builder.gd")
const PoseSolver = preload("res://scripts/visual_showcase/pose_solver.gd")
const PoseModifier = preload("res://scripts/visual_showcase/pose_modifier.gd")
const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const MaterialLibrary = preload("res://scripts/visual_showcase/material_library.gd")
const RELEASE_SECONDS := 2.2

## {"kind": "pilgrim" | "corrupted", "marrow_arm": bool}
var look: Dictionary = {"kind": "pilgrim", "marrow_arm": false}
var character: Node3D
var skeleton: Skeleton3D
var modifier: PoseModifier
var solver: PoseSolver
var weapon_node: Node3D
var edge_material: StandardMaterial3D
var status_overlay: StandardMaterial3D
var flash := 0.0
var flash_color := Color.WHITE
var triangles := 0
var weapon_triangles := 0
var built_signature := ""
## Last solved pose (model space), for tests and captures.
var last_pose: Dictionary = {}
var last_view: Dictionary = {}
var emissive_overrides: Array[StandardMaterial3D] = []
var release_particles: CPUParticles3D
var released_for := 0.0

func _ready() -> void:
	root = Node3D.new()
	root.name = "ShowcaseRoot"
	add_child(root)
	weapon_root = Node3D.new()
	weapon_root.name = "WeaponRoot"
	root.add_child(weapon_root)
	# The lab's body/blade references stay valid for inherited helpers.
	body_material = StandardMaterial3D.new()
	blade_material = StandardMaterial3D.new()
	status_overlay = StandardMaterial3D.new()
	status_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	status_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	status_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	status_overlay.albedo_color = Color(0, 0, 0, 0)
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
		instance.top_level = mesh != arc_mesh
		(root if mesh == arc_mesh else self).add_child(instance)
	label = Label3D.new()
	label.position = Vector3(0.0, 2.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.no_depth_test = true
	add_child(label)
	release_particles = _make_release_particles()
	root.add_child(release_particles)
	rebuild()

func _signature() -> String:
	var state = actor.state
	return "%s|%s|%s|%s|%s|%s" % [look.get("kind", "pilgrim"), look.get("marrow_arm", false), state.h.get("item", ""),
		state.h.length, state.h.two_handed, ",".join(state.resources.get("armor", []))]

## Rebuilds the character only when what it wears or holds changed.
func rebuild() -> void:
	if root == null or actor == null or actor.state == null:
		return
	var signature := _signature()
	if signature != built_signature:
		built_signature = signature
		_build_character()
	solver.reset()
	trail.clear()
	released_for = 0.0
	for mat: StandardMaterial3D in emissive_overrides:
		mat.emission_energy_multiplier = mat.get_meta("energy", 1.0)
	sync(0.0)

func _build_character() -> void:
	if character != null:
		character.queue_free()
	for child: Node in weapon_root.get_children():
		child.queue_free()
	var kind: String = look.get("kind", "pilgrim")
	var proportions: Dictionary = Rig.CORRUPTED if kind == "corrupted" else Rig.PILGRIM
	var marrow: bool = look.get("marrow_arm", false)
	var builder := CharacterBuilder.new(proportions, kind)
	var armor: Array = actor.state.resources.get("armor", [])
	var built := builder.build({"armor": armor, "marrow_arm": marrow})
	character = built.root
	skeleton = built.skeleton
	triangles = built.triangles
	root.add_child(character)
	modifier = PoseModifier.new()
	modifier.name = "PoseModifier"
	modifier.active = true
	modifier.influence = 1.0
	skeleton.add_child(modifier)
	solver = PoseSolver.new(proportions, marrow)
	var body: MeshInstance3D = built.layers.get("Body")
	if body != null:
		body.material_overlay = status_overlay
	emissive_overrides.clear()
	if kind == "corrupted":
		for layer: MeshInstance3D in built.layers.values():
			for i in range(layer.mesh.get_surface_count()):
				var mat := layer.mesh.surface_get_material(i) as StandardMaterial3D
				if mat != null and mat.emission_enabled:
					var own := mat.duplicate() as StandardMaterial3D
					own.set_meta("energy", own.emission_energy_multiplier)
					layer.set_surface_override_material(i, own)
					emissive_overrides.append(own)
	var h: Dictionary = actor.state.h
	var weapon := WeaponBuilder.build(str(h.get("item", "")), float(h.length), bool(h.two_handed), kind == "corrupted")
	weapon_node = weapon.node
	edge_material = weapon.edge
	weapon_triangles = weapon.triangles
	weapon_root.add_child(weapon_node)
	blade_material = edge_material

## Rules → drawn pose. Called by lab_duelist._process every frame.
func sync(delta: float) -> void:
	var state = actor.state
	if solver == null or state == null:
		return
	root.rotation = Vector3(0.0, actor.yaw(), 0.0)
	root.position = Vector3.ZERO
	last_view = _view(state)
	var result := solver.solve(last_view, delta)
	last_pose = result
	modifier.globals = result.bones
	weapon_root.transform = result.weapon
	_sync_colors(state)
	_sync_flash(delta)
	_sync_release(state, delta)
	_draw_arc(state)
	_record_trail(state, delta)
	_draw_debug(state)
	_sync_label(state)

func _view(state: RefCounted) -> Dictionary:
	var basis := Basis(Vector3.UP, actor.yaw())
	var to_local := basis.inverse()
	var progress := 0.0
	if state.phase == State.Phase.DODGE:
		progress = 1.0 - state.remaining / maxf(state.t.dodge_duration, 0.001)
	elif state.phase == State.Phase.ROLL:
		progress = state.roll_elapsed / maxf(state.t.roll_duration, 0.001)
	var look_at := Vector3(0.0, 1.5, -3.0)
	var foe: Node3D = actor.get("opponent")
	if is_instance_valid(foe):
		look_at = actor.xform().affine_inverse() * (foe.global_position + Vector3(0.0, 1.45, 0.0))
	return {"phase": state.phase, "hand": state.hand, "dir": state.dir, "direction": state.direction, "guarding": state.guarding,
		"guard": state.guard, "two_handed": state.h.two_handed, "inertia": state.h.inertia, "omega": state.omega,
		"velocity": to_local * actor.velocity, "dodge_dir": to_local * actor.dodge_direction, "progress": clampf(progress, 0.0, 1.0),
		"posture": state.posture / maxf(state.max_posture, 1.0), "look": look_at, "released": state.released}

## Contact feedback from the arena (presentation only).
func on_contact(report: Dictionary, as_defender: bool, other: Node3D) -> void:
	if solver == null:
		return
	var away := actor.global_position - other.global_position
	away.y = 0.0
	var local := Basis(Vector3.UP, actor.yaw()).inverse() * (away.normalized() if away.length() > 0.001 else Vector3.BACK)
	var result: String = report.result
	if as_defender:
		var strength := {"hit": 0.9, "misaligned": 0.7, "guard_break": 1.0, "block": 0.45, "deflect": 0.25, "clash": 0.5, "evaded": 0.0}.get(result, 0.3) as float
		solver.kick(local + Vector3(0.0, 0.0, 0.0), strength)
		if result in ["hit", "misaligned"]:
			flash = 1.0
			flash_color = Color(1.0, 0.25, 0.15)
		if actor.state.phase == State.Phase.DEAD:
			solver.dead_side = 1.0 if local.x >= 0.0 else -1.0
	elif result in ["block", "deflect", "clash", "guard_break"]:
		solver.kick(local, 0.6 if result == "deflect" else 0.35)

func _sync_flash(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 4.0)
	var state = actor.state
	var tint := Color(0, 0, 0, 0)
	if state.status.is_active("poison"):
		tint = Color(0.35, 0.9, 0.25, 0.18)
	if state.status.is_active("slow"):
		tint = Color(0.35, 0.55, 1.0, 0.18)
	if flash > 0.0:
		tint = tint.lerp(Color(flash_color.r, flash_color.g, flash_color.b, 0.45), flash)
	status_overlay.albedo_color = tint

## Edge glow with the lab's telegraph colours and logic (lab_visual._sync_colors).
func _sync_colors(state: RefCounted) -> void:
	if edge_material == null:
		return
	var color := Color("c8d0cc")
	var glow := 0.0
	match state.phase:
		State.Phase.WINDUP:
			color = DIRECTION_COLORS.get(state.direction, Color.ORANGE)
			glow = 0.6 + 1.2 * minf(1.0, state.windup_time / 0.35)
		State.Phase.SWING:
			color = Color("ff4a2e") if state.live_value >= 0.0 and not state.hit_consumed else DIRECTION_COLORS.get(state.direction, Color.ORANGE)
			glow = 2.4
		State.Phase.BROKEN:
			color = Color("b06bff")
			glow = 1.4
	if state.phase == State.Phase.IDLE and state.guarding:
		color = Color("f6e7a6") if state.guard_age <= state.deflect_window else Color("8fc7ff")
		glow = 2.0 if state.guard_age <= state.deflect_window else 0.7
	edge_material.emission = color
	edge_material.emission_energy_multiplier = glow
	edge_material.albedo_color = Color("c8d0cc").lerp(color, minf(glow, 1.0) * 0.6)

func _sync_release(state: RefCounted, delta: float) -> void:
	var dead: bool = state.phase == State.Phase.DEAD
	release_particles.emitting = dead and look.get("kind", "") == "corrupted" and released_for < RELEASE_SECONDS
	if not dead:
		released_for = 0.0
		return
	released_for += delta
	var fade := 1.0 - smoothstep(0.3, RELEASE_SECONDS, released_for)
	for mat: StandardMaterial3D in emissive_overrides:
		mat.emission_energy_multiplier = float(mat.get_meta("energy", 1.0)) * fade

func _make_release_particles() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Release"
	particles.emitting = false
	particles.amount = 48
	particles.lifetime = 1.8
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.3, 0.6, 0.3)
	particles.position = Vector3(0.0, 0.6, 0.0)
	particles.direction = Vector3.UP
	particles.spread = 25.0
	particles.gravity = Vector3(0.0, 0.6, 0.0)
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.9
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.95, 0.9, 0.7)
	quad.material = mat
	particles.mesh = quad
	return particles

## Model-space socket transform of the last solved pose (tests, captures).
func socket(name: String) -> Transform3D:
	return Rig.socket_global(last_pose.get("bones", {}), name)
