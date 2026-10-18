extends RefCounted
## Curated primitive poses. Reads combat state; never starts attacks or resolves hits.
## Fighter keeps node references as its public pose-inspection surface for QA.
const Rules = preload("res://scripts/combat/combat_state.gd")

static func build(actor: Fighter) -> void:
	actor.visual = Node3D.new()
	actor.add_child(actor.visual)
	actor.body_material = Fighter.material(actor.body_color)
	actor.torso = Fighter.mesh_part(actor.visual, CapsuleMesh.new(), Vector3(0.0, 1.0, 0.0), Vector3(0.62, 0.7, 0.48), actor.body_material)
	Fighter.mesh_part(actor.visual, SphereMesh.new(), Vector3(0.0, 1.75, 0.0), Vector3(0.38, 0.38, 0.38), Fighter.material(Color("c9c4ae")))
	for side in [-1.0, 1.0]:
		Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3(side * 0.18, 0.35, 0.0), Vector3(0.22, 0.65, 0.25), actor.body_material)
		if side < 0.0:
			Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3(side * 0.43, 1.05, 0.0), Vector3(0.18, 0.6, 0.2), actor.body_material)
	actor.sword_arm = Fighter.mesh_part(actor.visual, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, actor.body_material)
	actor.sword_pivot = Node3D.new()
	actor.sword_pivot.position = Vector3(0.48, 1.1, 0.0)
	actor.visual.add_child(actor.sword_pivot)
	Fighter.mesh_part(actor.sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.85), Vector3(0.07, 0.12, 1.8), Fighter.material(Color("d7dfdb")))
	Fighter.mesh_part(actor.sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.15), Vector3(0.38, 0.1, 0.1), Fighter.material(Color("ad9568")))
	actor.indicator = Fighter.mesh_part(actor, BoxMesh.new(), Vector3.ZERO, Vector3(actor.attack_width, 0.035, actor.attack_range), Fighter.material(Color(1.0, 0.35, 0.1, 0.30), true))
	actor.indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.impact = Node3D.new()
	actor.add_child(actor.impact)
	for i in range(8):
		var spark := Fighter.mesh_part(actor.impact, BoxMesh.new(), Vector3.ZERO, Vector3(0.05, 0.32, 0.05), Fighter.material(Color("76e6e5"), true))
		var angle := i * TAU / 8.0
		spark.position = Vector3(sin(angle), cos(angle), 0.0) * 0.4
		spark.rotation.z = -angle
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.27
	halo_mesh.outer_radius = 0.31
	actor.broken_halo = Fighter.mesh_part(actor, halo_mesh, Vector3(0.0, 2.1, 0.0), Vector3.ONE, Fighter.material(Color("ecbb51"), true))

	actor.marrow_pivot = Node3D.new()
	actor.marrow_pivot.position = Vector3(0.43, 1.35, 0.0)
	actor.visual.add_child(actor.marrow_pivot)
	actor.marrow_bone = Fighter.mesh_part(actor.marrow_pivot, BoxMesh.new(), Vector3.ZERO, Vector3.ONE, Fighter.material(Color("eee0bb"), true))
	actor.marrow_tip = Marker3D.new()
	actor.marrow_pivot.add_child(actor.marrow_tip)
	for side in [-1.0, 1.0]:
		var fork := Fighter.mesh_part(actor.marrow_pivot, BoxMesh.new(), Vector3(side * 0.16, 0.0, -0.3), Vector3(0.08, 0.13, 0.65), Fighter.material(Color("e7bd70"), true))
		fork.rotation.y = side * 0.3
	actor.marrow_pivot.visible = not actor.combat.signature.is_empty()

static func sync(actor: Fighter, delta: float) -> void:
	actor.flash_time = maxf(0.0, actor.flash_time - delta)
	var phase: int = actor.combat.phase
	actor.visual.rotation.z = 0.0
	actor.visual.position.y = 0.0
	actor.torso.rotation = Vector3.ZERO
	actor.sword_pivot.position = Vector3(0.48, 1.1, 0.0)
	actor.sword_pivot.rotation = Vector3.ZERO
	var tint := actor.body_color
	if phase == Rules.Phase.WINDUP:
		var duration := actor.combat.windup_duration()
		var preparation := clampf((duration - actor.combat.remaining) / (duration - actor.combat.commitment_duration), 0.0, 1.0)
		# The blade rises above the silhouette, then settles in a distinct loaded pose.
		var loaded := Vector3(0.42, 2.05 if actor.combat.heavy else 1.8, 0.15)
		var loaded_rotation := Vector3(0.95 if actor.combat.heavy else 0.65, -0.85, -0.15)
		actor.sword_pivot.position = Vector3(0.48, 1.1, 0.0).lerp(loaded, preparation)
		actor.sword_pivot.rotation = Vector3.ZERO.lerp(loaded_rotation, preparation)
		actor.torso.rotation = Vector3(-0.12, -0.25 * preparation, 0.08 * preparation)
		if actor.combat.attack_stage() == "release":
			var release := 1.0 - actor.combat.remaining / actor.combat.release_duration
			actor.sword_pivot.position = loaded.lerp(Vector3(0.15, 1.35, -0.60), release)
			actor.sword_pivot.rotation = loaded_rotation.lerp(Vector3(0.0, -0.12, 0.0), release)
			actor.torso.rotation = actor.torso.rotation.lerp(Vector3(0.12, 0.12, 0.0), release)
	elif phase == Rules.Phase.ACTIVE:
		# First damaging tick already has the blade extended into the forward volume.
		var swing := 1.0 - actor.combat.remaining / actor.combat.active_duration
		actor.sword_pivot.position = Vector3(0.15, 1.35, -0.60)
		actor.sword_pivot.rotation.y = lerpf(-0.12, 0.65, swing)
		actor.torso.rotation = Vector3(0.12, lerpf(0.12, 0.30, swing), 0.0)
	elif phase == Rules.Phase.RECOVERY:
		var recover := clampf(actor.combat.remaining / actor.combat.recovery_duration, 0.0, 1.0)
		actor.sword_pivot.position = Vector3(0.48, 1.1, 0.0).lerp(Vector3(0.15, 1.35, -0.60), recover)
		actor.sword_pivot.rotation.y = 0.65 * recover
		actor.torso.rotation = Vector3(0.12, 0.30, 0.0) * recover
	elif phase == Rules.Phase.BROKEN:
		tint = Color("e3bd51")
		actor.visual.rotation.z = 0.3
	elif phase == Rules.Phase.DEAD:
		actor.visual.rotation.z = PI / 2.0
		actor.visual.position.y = 0.28
	elif phase == Rules.Phase.STAGGER:
		actor.visual.rotation.z = -0.2
	elif phase == Rules.Phase.DODGE:
		actor.visual.rotation.z = 0.35
	else:
		actor.sword_pivot.rotation = Vector3(0.0, -0.4 if actor.combat.guarding else 0.0, -0.8 if actor.combat.guarding else 0.0)
		if actor.combat.guarding:
			actor.sword_pivot.position = Vector3(0.15, 1.6, -0.35)
			actor.sword_pivot.rotation.x = 0.55
			# A re-pressed guard still protects, but the wrists settle before a new tap.
			if actor.combat.guard_age > actor.combat.deflect_window and actor.combat.deflect_ready_in > 0.0:
				actor.sword_pivot.position.y -= 0.12
	if not actor.combat.signature.is_empty():
		actor.sword_pivot.position.x = -absf(actor.sword_pivot.position.x)
		_sync_marrow(actor)
	var shoulder := Vector3(-0.35 if not actor.combat.signature.is_empty() else 0.35, 1.35, 0.0)
	var arm_vector := actor.sword_pivot.position - shoulder
	actor.sword_arm.position = (shoulder + actor.sword_pivot.position) * 0.5
	actor.sword_arm.scale = Vector3(0.18, maxf(0.18, arm_vector.length()), 0.2)
	actor.sword_arm.quaternion = Quaternion(Vector3.UP, arm_vector.normalized())
	if actor.flash_time > 0.0:
		tint = Color("8ff4ee") if actor.last_result == Rules.DEFLECTED else Color("e57968")
	actor.body_material.albedo_color = tint
	actor.impact.visible = actor.flash_time > 0.0 and actor.last_result == Rules.DEFLECTED
	actor.impact.position = actor.facing * 0.9 + Vector3.UP * 1.25
	actor.impact.rotation.y = atan2(-actor.facing.x, -actor.facing.z)
	actor.impact.scale = Vector3.ONE * (1.0 + (0.32 - actor.flash_time) * 2.0)
	actor.broken_halo.visible = phase == Rules.Phase.BROKEN
	actor.indicator.visible = actor.debug_hitboxes and phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE]
	actor.indicator.scale = Vector3(actor.attack_width, 0.035, actor.attack_range)
	actor.indicator.position = actor.facing * actor.attack_range * 0.5 + Vector3.UP * 0.055
	actor.indicator.rotation.y = atan2(-actor.facing.x, -actor.facing.z)
	actor.indicator.material_override.albedo_color = Color(1.0, 0.22, 0.08, 0.48) if phase == Rules.Phase.ACTIVE else Color(1.0, 0.65, 0.18, 0.2)


static func _sync_marrow(actor: Fighter) -> void:
	var state := actor.combat
	actor.marrow_pivot.visible = true
	var length := 0.65
	actor.marrow_pivot.rotation = Vector3.ZERO
	if state.is_signature():
		if state.phase == Rules.Phase.WINDUP:
			# Draw back horizontally: clearly different from the overhead sword raise.
			length = 0.45
			actor.marrow_pivot.rotation.y = -0.55
			if state.attack_stage() == "release":
				var release := 1.0 - state.remaining / state.release_duration
				length = lerpf(0.45, state.signature.reach, release)
				actor.marrow_pivot.rotation.y *= 1.0 - release
		elif state.phase == Rules.Phase.ACTIVE:
			length = state.signature.reach
		elif state.phase == Rules.Phase.RECOVERY:
			length = lerpf(0.65, state.signature.reach, state.remaining / state.recovery_duration)
		# Lower the idle sword so the bone, rather than the blade, owns this silhouette.
		if state.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			actor.sword_pivot.position = Vector3(-0.48, 0.95, 0.0)
			actor.sword_pivot.rotation = Vector3(-0.4, -0.4, 0.0)
	actor.marrow_bone.position.z = -length * 0.5
	actor.marrow_bone.scale = Vector3(0.18, 0.18, length)
	actor.marrow_tip.position = Vector3(0.0, 0.0, -length)
	actor.marrow_bone.material_override.albedo_color = Color("ffd17c") if state.is_signature() and state.phase == Rules.Phase.WINDUP else Color("eee0bb")
