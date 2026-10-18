extends RefCounted
## Three curated attack poses on an articulated placeholder. Rules own every phase.
## All offsets are cosmetic; neither locomotion nor collision reads this file.
const Rules = preload("res://scripts/combat/combat_state.gd")
const REST := Vector3(0.48, 1.1, 0.0)

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
	sync(actor, 0.0)

static func sync(actor: Fighter, delta: float) -> void:
	actor.flash_time = maxf(0.0, actor.flash_time - delta)
	actor.reaction_time = maxf(0.0, actor.reaction_time - delta)
	var state := actor.combat
	var phase: int = state.phase
	var moving := Vector2(actor.velocity.x, actor.velocity.z).length()
	actor.gait += moving * delta * 2.5
	actor.visual.rotation.x = 0.0
	actor.visual.rotation.z = 0.0
	actor.visual.position = Vector3.ZERO
	actor.torso.rotation = Vector3.ZERO
	actor.torso.position = Vector3(0.0, 1.17, 0.0)
	actor.sword_pivot.position = REST
	actor.sword_pivot.rotation = Vector3(-0.12, -0.18, 0.0)
	var load := 0.0
	var weight := 0.0
	if phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
		var heavy := state.heavy
		var loaded := Vector3(0.4, 2.12, 0.1) if heavy else Vector3(0.68, 1.62, 0.18)
		var loaded_rotation := Vector3(1.28, -0.3, -0.18) if heavy else Vector3(0.24, -1.12, -0.25)
		var contact := Vector3(0.15, 1.35, -0.6)
		var contact_rotation := Vector3(0.0, -0.12, 0.0)
		var finish := Vector3(-0.16, 1.16, -0.58) if heavy else Vector3(-0.16, 1.35, -0.6)
		var finish_rotation := Vector3(-0.03, 0.35, -0.2) if heavy else Vector3(0.0, 0.65, 0.0)
		if phase == Rules.Phase.WINDUP:
			load = smoothstep(0.0, 1.0, clampf((state.windup_duration() - state.remaining) / maxf(0.01, state.windup_duration() - state.commitment_duration), 0.0, 1.0))
			actor.sword_pivot.position = REST.lerp(loaded, load)
			actor.sword_pivot.rotation = Vector3(-0.12, -0.18, 0.0).lerp(loaded_rotation, load)
			actor.torso.rotation = Vector3(0.12, -0.48 if heavy else -0.62, 0.07) * load
			weight = -0.12 * load
			if state.attack_stage() == "release":
				var release := smoothstep(0.0, 1.0, 1.0 - state.remaining / state.release_duration)
				actor.sword_pivot.position = loaded.lerp(contact, release)
				actor.sword_pivot.rotation = loaded_rotation.lerp(contact_rotation, release)
				actor.torso.rotation = actor.torso.rotation.lerp(Vector3(-0.12, 0.18, 0.0), release)
				weight = lerpf(-0.12, 0.08, release)
		elif phase == Rules.Phase.ACTIVE:
			var swing := clampf(1.0 - state.remaining / state.active_duration, 0.0, 1.0)
			actor.sword_pivot.position = contact.lerp(finish, swing)
			actor.sword_pivot.rotation = contact_rotation.lerp(finish_rotation, swing)
			actor.torso.rotation = Vector3(-0.12, lerpf(0.18, 0.55, swing), -0.05 * swing)
			weight = 0.08
		else:
			var recover := smoothstep(0.0, 1.0, clampf(state.remaining / state.recovery_duration, 0.0, 1.0))
			actor.sword_pivot.position = REST.lerp(finish, recover)
			actor.sword_pivot.rotation = Vector3(-0.12, -0.18, 0.0).lerp(finish_rotation, recover)
			actor.torso.rotation = Vector3(-0.12, 0.55, -0.05) * recover
			weight = 0.08 * recover
	elif phase == Rules.Phase.BROKEN:
		# Collapsed knees, bowed head, hanging weapon: sustained vulnerability.
		actor.torso.rotation = Vector3(-0.65, 0.1, 0.12)
		actor.torso.position.y -= 0.25
		actor.sword_pivot.position = Vector3(0.5, 0.65, -0.1)
		actor.sword_pivot.rotation = Vector3(-0.5, 0.6, 0.3)
		weight = 0.22
	elif phase == Rules.Phase.DEAD:
		actor.visual.rotation.z = PI / 2.0
		actor.visual.position.y = 0.28
	elif phase == Rules.Phase.STAGGER:
		var recoil := minf(1.0, state.remaining / 0.18)
		var deflected := actor.reaction_kind == Rules.DEFLECTED
		actor.torso.rotation = Vector3(0.26, -0.45 if deflected else 0.12, -0.12) * recoil
		# Deflection throws the weapon out; a body hit folds the chest back and
		# leaves the sword low. The rule lockout lasts independently of this pose.
		actor.sword_pivot.position = Vector3(0.65, 1.6, 0.15) if deflected else Vector3(0.5, 1.0, 0.1)
		actor.sword_pivot.rotation = Vector3(0.7, -1.0, -0.45) if deflected else Vector3(-0.3, 0.25, 0.15)
		weight = -0.14 * recoil
	elif phase == Rules.Phase.DODGE:
		actor.torso.rotation.x = -0.25
		actor.visual.position.y = -0.12
	elif state.guarding:
		actor.sword_pivot.position = Vector3(0.15, 1.6, -0.35)
		actor.sword_pivot.rotation = Vector3(0.55, -0.4, -0.8)
		actor.torso.rotation = Vector3(-0.1, -0.18, 0.0)
		if state.guard_age > state.deflect_window and state.deflect_ready_in > 0.0:
			actor.sword_pivot.position.y -= 0.12
	elif moving > 0.1:
		var stride_sway := sin(actor.gait) * minf(1.0, moving / 3.0)
		actor.torso.rotation = Vector3(-0.06, stride_sway * 0.07, stride_sway * 0.025)
		actor.sword_pivot.position.y += stride_sway * 0.025
	if actor.reaction_time > 0.0 and state.guarding:
		var kick := sin(actor.reaction_time / 0.32 * PI * 0.5)
		actor.sword_pivot.position.z += 0.16 * kick
		actor.torso.rotation.x += 0.14 * kick
	actor.marrow_pivot.visible = not state.signature.is_empty()
	if actor.marrow_pivot.visible:
		actor.sword_pivot.position.x = -absf(actor.sword_pivot.position.x)
		_sync_marrow(actor)
	_sync_limbs(actor, weight, moving)
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

static func _segment(mesh: MeshInstance3D, start: Vector3, end: Vector3, width: float) -> void:
	var direction := end - start
	mesh.position = (start + end) * 0.5
	mesh.scale = Vector3(width, maxf(0.02, direction.length()), width)
	mesh.quaternion = Quaternion(Vector3.UP, direction.normalized())

static func _sync_limbs(actor: Fighter, weight: float, moving: float) -> void:
	var chest := Basis.from_euler(actor.torso.rotation)
	var origin := actor.torso.position
	actor.head.position = origin + chest * Vector3(0.0, 0.54, 0.0)
	actor.head.rotation = actor.torso.rotation * 0.5
	actor.pelvis.position = Vector3(0.0, 0.82 - absf(weight) * 0.4, weight)
	actor.pelvis.rotation.y = actor.torso.rotation.y * 0.3
	var side := -1.0 if not actor.combat.signature.is_empty() else 1.0
	var shoulder := origin + chest * Vector3(side * 0.32, 0.16, 0.0)
	var hand := actor.sword_pivot.position
	var elbow := shoulder.lerp(hand, 0.5) + Vector3(side * 0.18, -0.19, 0.1)
	_segment(actor.sword_arm, shoulder, elbow, 0.16)
	_segment(actor.forearm, elbow, hand, 0.135)
	var other := origin + chest * Vector3(-side * 0.32, 0.16, 0.0)
	var off_hand := Vector3(-side * 0.44, 1.0, -0.18)
	if actor.combat.heavy or actor.combat.guarding:
		off_hand = hand + actor.sword_pivot.basis * Vector3(0.0, 0.0, 0.12)
	var off_elbow := other.lerp(off_hand, 0.5) + Vector3(-side * 0.18, -0.17, 0.08)
	_segment(actor.free_arm, other, off_elbow, 0.16)
	_segment(actor.free_forearm, off_elbow, off_hand, 0.135)
	actor.free_arm.visible = actor.combat.signature.is_empty()
	actor.free_forearm.visible = actor.combat.signature.is_empty()
	var stride := minf(0.22, moving * 0.055)
	var local_motion := Vector3(actor.velocity.x, 0.0, actor.velocity.z).rotated(Vector3.UP, -actor.visual.rotation.y).normalized()
	for i in range(2):
		var sign_side := -1.0 if i == 0 else 1.0
		var step := sin(actor.gait + i * PI)
		var foot := Vector3(sign_side * 0.23, 0.09, sign_side * 0.16 - weight) + local_motion * step * stride
		foot.y += maxf(0.0, cos(actor.gait + i * PI)) * stride * 0.35
		var hip := actor.pelvis.position + Vector3(sign_side * 0.17, 0.0, 0.0)
		var knee := hip.lerp(foot, 0.5) + Vector3(0.0, 0.0, -0.12 - absf(weight))
		_segment(actor.thighs[i], hip, knee, 0.21)
		_segment(actor.shins[i], knee, foot, 0.17)
		actor.feet[i].position = foot

static func _sync_marrow(actor: Fighter) -> void:
	var state := actor.combat
	var length := 0.65
	actor.marrow_pivot.position = Vector3(0.43, 1.35, 0.0)
	actor.marrow_pivot.rotation = Vector3.ZERO
	if state.is_signature():
		if state.phase == Rules.Phase.WINDUP:
			var draw := smoothstep(0.0, 1.0, (state.windup_duration() - state.remaining) / maxf(0.01, state.windup_duration() - state.commitment_duration))
			length = lerpf(0.65, 0.45, draw)
			actor.marrow_pivot.rotation.y = -0.55 * draw
			actor.marrow_pivot.position.z = 0.18 * draw
			actor.torso.rotation = Vector3(0.08, -0.65, 0.08) * draw
			if state.attack_stage() == "release":
				var release := smoothstep(0.0, 1.0, 1.0 - state.remaining / state.release_duration)
				length = lerpf(0.45, float(state.signature.reach), release)
				actor.marrow_pivot.rotation.y *= 1.0 - release
				actor.marrow_pivot.position.z *= 1.0 - release
				actor.torso.rotation = actor.torso.rotation.lerp(Vector3(-0.2, 0.3, 0.0), release)
		elif state.phase == Rules.Phase.ACTIVE:
			length = float(state.signature.reach)
			actor.torso.rotation = Vector3(-0.2, 0.3, 0.0)
		elif state.phase == Rules.Phase.RECOVERY:
			var recover := smoothstep(0.0, 1.0, state.remaining / state.recovery_duration)
			length = lerpf(0.65, float(state.signature.reach), recover)
			actor.torso.rotation = Vector3(-0.2, 0.3, 0.0) * recover
		elif state.phase == Rules.Phase.STAGGER and actor.reaction_kind == Rules.DEFLECTED:
			length = lerpf(0.65, float(state.signature.reach), actor.reaction_time / 0.32)
			actor.marrow_pivot.rotation.y = -0.3 * (actor.reaction_time / 0.32)
		if state.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			actor.sword_pivot.position = Vector3(-0.48, 0.95, 0.0)
			actor.sword_pivot.rotation = Vector3(-0.4, -0.4, 0.0)
	actor.marrow_bone.position.z = -length * 0.5
	actor.marrow_bone.scale = Vector3(0.18, 0.18, length)
	actor.marrow_tip.position = Vector3(0.0, 0.0, -length)
