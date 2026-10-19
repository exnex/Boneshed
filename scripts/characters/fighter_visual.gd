extends RefCounted
## Curated key-pose animation on an articulated placeholder. Rules own every phase:
## poses are sampled from rule time (presentation/pose_sampler.gd), reactions are an
## additive layer, and limbs solve fixed-length two-bone chains. All offsets are
## cosmetic; neither locomotion nor collision reads this file.
const Rules = preload("res://scripts/combat/combat_state.gd")
const Sampler = preload("res://scripts/characters/presentation/pose_sampler.gd")
const Fx = preload("res://scripts/characters/presentation/combat_fx.gd")
const ARM_UPPER := 0.4
const ARM_LOWER := 0.4
const LEG_UPPER := 0.42
const LEG_LOWER := 0.42
const FADE_SECONDS := 0.08

static func build(actor: Fighter) -> void:
	actor.visual = Node3D.new()
	actor.add_child(actor.visual)
	actor.body_material = Fighter.material(actor.body_color)
	actor.torso = Fighter.mesh_part(actor.visual, CapsuleMesh.new(), Vector3(0.0, 1.17, 0.0), Vector3(0.62, 0.38, 0.46), actor.body_material)
	actor.head = Fighter.mesh_part(actor.visual, SphereMesh.new(), Vector3(0.0, 1.75, 0.0), Vector3(0.33, 0.38, 0.34), Fighter.material(Color("b6b4a3")))
	actor.pelvis = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3(0.0, 0.85, 0.0), Vector3(0.45, 0.25, 0.32), actor.body_material)
	actor.sword_arm = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material)
	actor.forearm = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material)
	actor.free_arm = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material)
	actor.free_forearm = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material)
	for side: float in [-1.0, 1.0]:
		actor.thighs.append(Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material))
		actor.shins.append(Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material))
		actor.feet.append(Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3(side * 0.21, 0.09, 0.0), Vector3(0.23, 0.16, 0.4), Fighter.material(actor.body_color.darkened(0.3))))
	actor.sword_pivot = Node3D.new()
	actor.visual.add_child(actor.sword_pivot)
	Fighter.mesh_part(actor.sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.85), Vector3(0.055, 0.10, 1.8), Fighter.material(Color("c0c9c5")))
	Fighter.mesh_part(actor.sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.15), Vector3(0.32, 0.09, 0.09), Fighter.material(Color("ad9568")))
	actor.indicator = Fighter.mesh_part(actor, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, Fighter.material(Color(1.0, 0.35, 0.1, 0.3), true))
	actor.indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.impact = Node3D.new()
	actor.add_child(actor.impact)
	for i in range(5):
		var spark := Fighter.mesh_part(actor.impact, BoxMesh.new(), Vector3.ZERO, Vector3(0.025, 0.16, 0.025), Fighter.material(Color("c9b890"), true))
		var angle := i * TAU / 5.0
		spark.position = Vector3(sin(angle), cos(angle), 0.0) * 0.17
		spark.rotation.z = -angle
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.27
	halo_mesh.outer_radius = 0.31
	actor.broken_halo = Fighter.mesh_part(actor, halo_mesh, Vector3(0.0, 2.1, 0.0), Vector3.ONE, Fighter.material(Color("ecbb51"), true))
	actor.marrow_pivot = Node3D.new()
	actor.visual.add_child(actor.marrow_pivot)
	actor.marrow_bone = Fighter.mesh_part(actor.marrow_pivot, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, Fighter.material(Color("c9bea3")))
	actor.marrow_tip = Marker3D.new()
	actor.marrow_pivot.add_child(actor.marrow_tip)
	for side: float in [-1.0, 1.0]:
		var fork := Fighter.mesh_part(actor.marrow_pivot, BoxMesh.new(), Vector3(side * 0.16, 0.0, -0.3), Vector3(0.08, 0.13, 0.65), Fighter.material(Color("b8a587")))
		fork.rotation.y = side * 0.3
	Fx.build(actor)
	sync(actor, 0.0)

static func sync(actor: Fighter, delta: float) -> void:
	actor.flash_time = maxf(0.0, actor.flash_time - delta)
	actor.reaction_time = maxf(0.0, actor.reaction_time - delta)
	var state := actor.combat
	var phase: int = state.phase
	var moving := Vector2(actor.velocity.x, actor.velocity.z).length()
	actor.gait += moving * delta * 2.5
	var mirrored := not state.signature.is_empty()
	var pose := Sampler.base_pose(state, mirrored, actor.reaction_kind)
	if phase == Rules.Phase.IDLE:
		if state.guarding and state.guard_age > state.deflect_window and state.deflect_ready_in > 0.0:
			pose.hand.y -= 0.12
		elif not state.guarding and moving > 0.1:
			var stride_sway := sin(actor.gait) * minf(1.0, moving / 3.0)
			pose.torso = Vector3(-0.06, stride_sway * 0.07, stride_sway * 0.025)
			pose.hand.y += stride_sway * 0.025
	pose = _crossfade(actor, pose, delta)
	# Reactions are an additive layer over whatever the rules say the body is doing.
	var incoming := Vector3.ZERO
	if is_instance_valid(actor.opponent) and actor.opponent != actor:
		incoming = actor.opponent.global_position - actor.global_position
		incoming.y = 0.0
		incoming = incoming.normalized() if incoming.length_squared() > 0.0001 else Vector3.ZERO
	var local_incoming := incoming.rotated(Vector3.UP, -actor.visual.rotation.y)
	pose = Sampler.add_reaction(pose, actor.reaction_kind, Sampler.REACTION_SECONDS - actor.reaction_time, local_incoming, state) if actor.reaction_time > 0.0 else pose
	actor.visual.rotation.x = 0.0
	actor.visual.rotation.z = 0.0
	actor.visual.position = Vector3.ZERO
	if phase == Rules.Phase.DEAD:
		actor.visual.rotation.z = PI / 2.0
		actor.visual.position.y = 0.28
	var crouch: float = pose.body.x
	var lean: float = pose.body.y
	actor.torso.position = Vector3(0.0, 1.17 - crouch, lean * 1.5)
	actor.torso.rotation = pose.torso
	actor.sword_pivot.position = pose.hand
	actor.sword_pivot.rotation = pose.blade
	actor.marrow_pivot.visible = mirrored
	_sync_limbs(actor, pose, moving, mirrored)
	if mirrored:
		_sync_marrow(actor)
	Fx.sync(actor, mirrored, incoming)
	# Localized steel contact, never a whole-body success/failure color code.
	var hit := actor.reaction_time > 0.0 and actor.reaction_kind in [Rules.HIT, "punish", Rules.DEFEATED]
	actor.body_material.albedo_color = actor.body_color.lerp(Color("926b61"), actor.reaction_time * 0.6) if hit else actor.body_color
	actor.impact.visible = actor.flash_time > 0.18 and actor.last_result in [Rules.DEFLECTED, Rules.GUARD]
	actor.impact.rotation.y = atan2(-actor.facing.x, -actor.facing.z)
	actor.impact.scale = Vector3.ONE * (1.0 + (0.32 - actor.flash_time) * 3.0) * (1.0 if actor.last_result == Rules.DEFLECTED else 0.45)
	actor.broken_halo.visible = actor.debug_hitboxes and phase == Rules.Phase.BROKEN
	actor.indicator.visible = actor.debug_hitboxes and phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE]
	actor.indicator.scale = Vector3(actor.attack_width, 0.035, actor.attack_range)
	actor.indicator.position = actor.facing * actor.attack_range * 0.5 + Vector3.UP * 0.055
	actor.indicator.rotation.y = atan2(-actor.facing.x, -actor.facing.z)
	actor.indicator.material_override.albedo_color = Color(1.0, 0.22, 0.08, 0.48) if phase == Rules.Phase.ACTIVE else Color(1.0, 0.65, 0.18, 0.2)

## Short ease when the rules change pose abruptly (guard raise/lower, attack
## cancels, dodge). Attack sections stay exact: they are continuous by authoring,
## and impacts (stagger, break, death) must read on their first frame. Zero-delta
## refreshes, used at hit resolution and by fixtures, always show the exact pose.
static func _crossfade(actor: Fighter, pose: Dictionary, delta: float) -> Dictionary:
	var state := actor.combat
	var key := int(state.phase) * 2 + int(state.guarding)
	var fade: Dictionary = actor.visual.get_meta("pose_fade", {"key": key, "left": 0.0, "from": pose, "shown": pose})
	var eased := state.phase in [Rules.Phase.IDLE, Rules.Phase.DODGE]
	if key != fade.key:
		fade.left = FADE_SECONDS if eased and delta > 0.0 else 0.0
		fade.from = fade.shown
		fade.key = key
	if not eased:
		fade.left = 0.0
	fade.left = maxf(0.0, fade.left - delta)
	var shown := Sampler.blend(fade.from, pose, smoothstep(0.0, 1.0, 1.0 - fade.left / FADE_SECONDS)) if fade.left > 0.0 else pose
	fade.shown = shown
	actor.visual.set_meta("pose_fade", fade)
	return shown

static func _segment(mesh: MeshInstance3D, start: Vector3, end: Vector3, width: float) -> void:
	var direction := end - start
	mesh.position = (start + end) * 0.5
	mesh.scale = Vector3(width, maxf(0.02, direction.length()), width)
	mesh.quaternion = Quaternion(Vector3.UP, direction.normalized())

static func _sync_limbs(actor: Fighter, pose: Dictionary, moving: float, mirrored: bool) -> void:
	var chest := Basis.from_euler(actor.torso.rotation)
	var origin := actor.torso.position
	# The head steadies against the chest so the eyes stay on the opponent.
	actor.head.position = origin + chest * Vector3(0.0, 0.54, 0.0)
	actor.head.rotation = Vector3(actor.torso.rotation.x * 0.5, actor.torso.rotation.y * 0.35, actor.torso.rotation.z * 0.5)
	actor.pelvis.position = Vector3(0.0, 0.82 - pose.body.x, pose.body.y)
	actor.pelvis.rotation = Vector3(0.0, actor.torso.rotation.y * 0.3, 0.0)
	var side := -1.0 if mirrored else 1.0
	var hand := actor.sword_pivot.position
	var shoulder := _reach_shoulder(origin + chest * Vector3(side * 0.32, 0.16, 0.0), hand)
	var elbow := Sampler.two_bone(shoulder, hand, ARM_UPPER, ARM_LOWER, _elbow_pole(side, hand.y - shoulder.y))
	_segment(actor.sword_arm, shoulder, elbow, 0.16)
	_segment(actor.forearm, elbow, hand, 0.135)
	var hilt := hand + actor.sword_pivot.basis * Vector3(0.0, 0.0, 0.12)
	var off_hand: Vector3 = pose.off.lerp(hilt, pose.grip)
	var other := _reach_shoulder(origin + chest * Vector3(-side * 0.32, 0.16, 0.0), off_hand)
	var off_elbow := Sampler.two_bone(other, off_hand, ARM_UPPER, ARM_LOWER, _elbow_pole(-side, off_hand.y - other.y))
	_segment(actor.free_arm, other, off_elbow, 0.16)
	_segment(actor.free_forearm, off_elbow, off_hand, 0.135)
	actor.free_arm.visible = not mirrored
	actor.free_forearm.visible = not mirrored
	var stride := minf(0.22, moving * 0.055)
	var local_motion := Vector3(actor.velocity.x, 0.0, actor.velocity.z).rotated(Vector3.UP, -actor.visual.rotation.y).normalized()
	var hips := Basis(Vector3.UP, actor.pelvis.rotation.y)
	# The lead foot is opposite the sword hand; attacks step it forward and lift it.
	var lead := 1 if mirrored else 0
	for i in range(2):
		var sign_side := -1.0 if i == 0 else 1.0
		var stance := -0.16 if i == lead else 0.16
		var step := sin(actor.gait + i * PI)
		var foot := Vector3(sign_side * 0.23, 0.09, stance) + local_motion * step * stride
		foot.y += maxf(0.0, cos(actor.gait + i * PI)) * stride * 0.35
		if i == lead:
			foot.z -= pose.body.z
			foot.y += pose.body.w
		var hip := actor.pelvis.position + hips * Vector3(sign_side * 0.17, 0.0, 0.0)
		var knee := Sampler.two_bone(hip, foot, LEG_UPPER, LEG_LOWER, Vector3(sign_side * 0.15, 0.0, -1.0))
		_segment(actor.thighs[i], hip, knee, 0.21)
		_segment(actor.shins[i], knee, foot, 0.17)
		actor.feet[i].position = foot

## A shoulder may protract a little toward an out-of-reach hand before the arm stretches.
static func _reach_shoulder(shoulder: Vector3, hand: Vector3) -> Vector3:
	var excess := shoulder.distance_to(hand) - (ARM_UPPER + ARM_LOWER)
	return shoulder.move_toward(hand, clampf(excess, 0.0, 0.12))

## Elbows hang down and out at the hip, and flare forward as the hands rise.
static func _elbow_pole(side: float, hand_height: float) -> Vector3:
	var raised := clampf((hand_height + 0.2) / 0.7, 0.0, 1.0)
	return Vector3(side * 0.7, lerpf(-1.0, 0.15, raised), lerpf(0.45, -0.25, raised))

static func _sync_marrow(actor: Fighter) -> void:
	var state := actor.combat
	var length := 0.65
	# The bone grows from the right shoulder, so it follows the body's coil and lunge.
	var chest := Basis.from_euler(actor.torso.rotation)
	actor.marrow_pivot.position = actor.torso.position + chest * Vector3(0.42, 0.18, 0.0)
	actor.marrow_pivot.rotation = Vector3.ZERO
	# The body lunge moves the root forward; shorten the bone by the same amount so
	# the visible tip still lands exactly on the rule reach.
	var reach := float(state.signature.reach) + actor.marrow_pivot.position.z
	if state.is_signature():
		if state.phase == Rules.Phase.WINDUP:
			var draw := smoothstep(0.0, 1.0, (state.windup_duration() - state.remaining) / maxf(0.01, state.windup_duration() - state.commitment_duration))
			length = lerpf(0.65, 0.45, draw)
			actor.marrow_pivot.rotation.y = -0.55 * draw
			actor.marrow_pivot.position.z += 0.18 * draw
			if state.attack_stage() == "release":
				var release := smoothstep(0.0, 1.0, 1.0 - state.remaining / state.release_duration)
				length = lerpf(0.45, reach, release)
				actor.marrow_pivot.rotation.y *= 1.0 - release
				actor.marrow_pivot.position.z -= 0.18 * draw * release
		elif state.phase == Rules.Phase.ACTIVE:
			length = reach
		elif state.phase == Rules.Phase.RECOVERY:
			var recover := smoothstep(0.0, 1.0, state.remaining / state.recovery_duration)
			length = lerpf(0.65, reach, recover)
		elif state.phase == Rules.Phase.STAGGER and actor.reaction_kind == Rules.DEFLECTED:
			length = lerpf(0.65, reach, actor.reaction_time / 0.32)
			actor.marrow_pivot.rotation.y = -0.3 * (actor.reaction_time / 0.32)
	actor.marrow_bone.position.z = -length * 0.5
	actor.marrow_bone.scale = Vector3(0.18, 0.18, length)
	actor.marrow_tip.position = Vector3(0.0, 0.0, -length)
