extends Node3D
## One animated swordsman for the animation lab. Presentation only: something else
## (the lab director here, CombatState in a future integration) owns timing and calls
## `drive_action()` with a clip time each step. Forward is -Z like the courtyard actors.
##
## AnimationTree (manual process, advanced explicitly by `step()`):
##   loco (BlendSpace2D) -> loco_rate (TimeScale) -> stance (Blend2, upper body = idle sword arms)
##   -> act (Blend2, action state machine; upper-body filter when `split_lower_body`)
##   -> [limbs (Blend2, lower-arm module) when `extra_arms`] -> flinch (OneShot, ADD) -> output

const ClipLibrary := preload("res://scripts/animation_lab/clip_library.gd")
const ExtraLimbs := preload("res://scripts/animation_lab/extra_limbs.gd")
const ACTIONS := ["slash", "guard", "stagger", "dodge_back"]
const LOCOMOTION := {"idle": Vector2.ZERO, "walk_forward": Vector2(0, 1), "walk_backward": Vector2(0, -1),
	"strafe_left": Vector2(-1, 0), "strafe_right": Vector2(1, 0)}
const TRACK_PREFIX := "Armature/Skeleton3D"

var manifest: Dictionary
var visual: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var weapon: Node3D
var blade_base: Marker3D
var blade_tip: Marker3D
var blade_material: StandardMaterial3D
var grip: Transform3D
var stride_speeds := {}
var action := ""
var action_weight := 0.0
var action_target := 0.0
var action_fade := 0.1
var split_lower_body := false
var extra_arm_bones := PackedStringArray()
var guard_targets := {}
var root_motion_total := Vector3.ZERO
var pending_root_motion := Vector3.ZERO
var action_clip_time := -1.0

## Returns an empty array on success. `options`: split_lower_body (bool), extra_arms (bool),
## tint (Color).
func setup(trial_dir: String, options: Dictionary = {}) -> PackedStringArray:
	var errors := ClipLibrary.verify_trial(trial_dir)
	if not errors.is_empty():
		return errors
	manifest = ClipLibrary.load_json(ClipLibrary.MANIFEST_PATH)
	split_lower_body = options.get("split_lower_body", false)
	visual = ClipLibrary.load_scene(trial_dir, "base")
	var addon := ClipLibrary.load_scene(trial_dir, "addon")
	if visual == null or addon == null:
		return PackedStringArray(["glTF load failed"])
	visual.name = "Visual"
	visual.rotation.y = PI # Model faces +Z; the lab and courtyard use -Z forward.
	add_child(visual)
	skeleton = visual.find_children("*", "Skeleton3D", true, false)[0]
	var mesh: MeshInstance3D = skeleton.find_children("*", "MeshInstance3D", true, false)[0]
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = options.get("tint", Color("b9a58a"))
	body_material.roughness = 0.75
	mesh.material_override = body_material
	if options.get("extra_arms", false):
		extra_arm_bones = ExtraLimbs.add_lower_arms(skeleton, "spine_02", 0.2)
		skeleton.add_child(ExtraLimbs.build_mesh(skeleton, extra_arm_bones, body_material))
	var sources := {"base": ClipLibrary.source_player(visual), "addon": ClipLibrary.source_player(addon)}
	var library := ClipLibrary.build_library(manifest, sources, skeleton)
	if not extra_arm_bones.is_empty():
		var offset := ExtraLimbs.parent_offset(skeleton, "spine_03", "spine_02")
		library.add_animation("lower_arms_guard", ExtraLimbs.pose_module(library.get_animation("guard"), skeleton, 0.3, offset, TRACK_PREFIX))
	sources.base.queue_free() # The tree replaces the imported player.
	addon.free()
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	visual.add_child(tree)
	tree.root_node = NodePath("..")
	tree.add_animation_library("", library)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.root_motion_track = NodePath("%s:%s" % [TRACK_PREFIX, manifest.skeleton.root_bone])
	tree.tree_root = _build_graph()
	tree.active = true
	_attach_weapon()
	if not extra_arm_bones.is_empty():
		_add_lower_arm_ik()
	for clip in LOCOMOTION:
		if clip != "idle":
			stride_speeds[clip] = measure_stride_speed(library.get_animation(clip))
	return PackedStringArray()

func _bone_paths(from_bone: String) -> Array:
	var paths := []
	var root := skeleton.find_bone(from_bone)
	for bone in skeleton.get_bone_count():
		var walk := bone
		while walk >= 0 and walk != root:
			walk = skeleton.get_bone_parent(walk)
		if walk == root:
			paths.append(NodePath("%s:%s" % [TRACK_PREFIX, skeleton.get_bone_name(bone)]))
	return paths

func _clip_node(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node

func _filtered_blend(paths: Array) -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for path in paths:
		blend.set_filter_path(path, true)
	return blend

func _build_graph() -> AnimationNodeBlendTree:
	var graph := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	for clip in LOCOMOTION:
		loco.add_blend_point(_clip_node(clip), LOCOMOTION[clip], -1, clip)
	loco.sync = true
	graph.add_node("loco", loco)
	graph.add_node("loco_rate", AnimationNodeTimeScale.new())
	graph.connect_node("loco_rate", 0, "loco")
	var upper := _bone_paths(manifest.skeleton.upper_body_bones_from)
	graph.add_node("stance_arms", _clip_node("idle"))
	graph.add_node("stance", _filtered_blend(upper))
	graph.connect_node("stance", 0, "loco_rate")
	graph.connect_node("stance", 1, "stance_arms")
	var machine := AnimationNodeStateMachine.new()
	for clip in ACTIONS:
		var state := AnimationNodeBlendTree.new()
		state.add_node("clip", _clip_node(clip))
		state.add_node("seek", AnimationNodeTimeSeek.new())
		state.connect_node("seek", 0, "clip")
		state.connect_node("output", 0, "seek")
		machine.add_node(clip, state)
	for from in ACTIONS:
		for to in ACTIONS:
			if from != to:
				var transition := AnimationNodeStateMachineTransition.new()
				transition.xfade_time = 0.08
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				machine.add_transition(from, to, transition)
	graph.add_node("action", machine)
	var act := _filtered_blend(upper) if split_lower_body else AnimationNodeBlend2.new()
	graph.add_node("act", act)
	graph.connect_node("act", 0, "stance")
	graph.connect_node("act", 1, "action")
	var last := "act"
	if not extra_arm_bones.is_empty():
		var limb_paths := []
		for bone in extra_arm_bones:
			limb_paths.append(NodePath("%s:%s" % [TRACK_PREFIX, bone]))
		graph.add_node("limb_module", _clip_node("lower_arms_guard"))
		graph.add_node("limbs", _filtered_blend(limb_paths))
		graph.connect_node("limbs", 0, last)
		graph.connect_node("limbs", 1, "limb_module")
		last = "limbs"
	var flinch := AnimationNodeOneShot.new()
	flinch.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	flinch.fadein_time = 0.04
	flinch.fadeout_time = 0.12
	graph.add_node("flinch_clip", _clip_node("flinch"))
	graph.add_node("flinch", flinch)
	graph.connect_node("flinch", 0, last)
	graph.connect_node("flinch", 1, "flinch_clip")
	graph.connect_node("output", 0, "flinch")
	return graph

## Procedural layer for the extra limbs: copying the human guard arm in local space puts
## the lower hands beside the hips, because the torso above them plays a different clip.
## A TwoBoneIK3D (Godot 4.6+) pulls each lower hand to a guard target that rides on
## spine_02, so the pair holds a readable guard whatever the upper body does.
func _add_lower_arm_ik() -> void:
	var anchor := BoneAttachment3D.new()
	anchor.name = "LowerGuardAnchor"
	anchor.bone_name = "spine_02"
	skeleton.add_child(anchor)
	var chest_rest := skeleton.get_bone_global_rest(skeleton.find_bone("spine_02"))
	var ik := TwoBoneIK3D.new()
	ik.name = "LowerArmIK"
	skeleton.add_child(ik)
	ik.setting_count = 2
	# Model space (+Z forward, +X = character left): crossed low guard in front of the belly.
	var layout := {"l": [Vector3(0.12, 0.02, 0.36), Vector3(0.75, -0.25, -0.15)], "r": [Vector3(-0.16, 0.08, 0.34), Vector3(-0.75, -0.25, -0.15)]}
	for i in ExtraLimbs.SIDES.size():
		var side: String = ExtraLimbs.SIDES[i]
		var target := Marker3D.new()
		target.name = "GuardTarget_" + side
		target.position = chest_rest.affine_inverse() * (chest_rest.origin + layout[side][0])
		anchor.add_child(target)
		var pole := Marker3D.new()
		pole.name = "GuardPole_" + side
		pole.position = chest_rest.affine_inverse() * (chest_rest.origin + layout[side][1])
		anchor.add_child(pole)
		ik.set_root_bone_name(i, ExtraLimbs.low_name("upperarm_" + side))
		ik.set_middle_bone_name(i, ExtraLimbs.low_name("lowerarm_" + side))
		ik.set_end_bone_name(i, ExtraLimbs.low_name("hand_" + side))
		ik.set_target_node(i, ik.get_path_to(target))
		ik.set_pole_node(i, ik.get_path_to(pole))
		guard_targets[side] = target

func _attach_weapon() -> void:
	var spec: Dictionary = manifest.weapon
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponSocket"
	attachment.bone_name = manifest.skeleton.weapon_bone
	skeleton.add_child(attachment)
	grip = Transform3D(Basis.IDENTITY, Vector3(spec.grip_offset[0], spec.grip_offset[1], spec.grip_offset[2]))
	weapon = Node3D.new()
	weapon.name = "Longsword"
	weapon.transform = grip
	attachment.add_child(weapon)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("c9d2d4")
	steel.metallic = 0.6
	steel.roughness = 0.35
	blade_material = steel
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("4a3426")
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("a8874c")
	var base: float = spec.blade_base
	var tip: float = spec.blade_tip
	_box(Vector3(0.05, 0.012, tip - base), Vector3(0, 0, (base + tip) * 0.5), steel)
	_box(Vector3(0.2, 0.035, 0.03), Vector3(0, 0, base - 0.015), brass)
	_box(Vector3(0.034, 0.034, 0.2), Vector3(0, 0, base - 0.13), leather)
	_box(Vector3(0.05, 0.05, 0.05), Vector3(0, 0, base - 0.25), brass)
	blade_base = Marker3D.new()
	blade_base.position = Vector3(0, 0, base)
	weapon.add_child(blade_base)
	blade_tip = Marker3D.new()
	blade_tip.position = Vector3(0, 0, tip)
	weapon.add_child(blade_tip)

func _box(size: Vector3, position_offset: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = position_offset
	part.material_override = material
	weapon.add_child(part)

## Blade endpoints in world space computed from the skeleton pose (independent of node
## update order), so QA can compare them with the attachment markers.
func blade_points() -> Array:
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(manifest.skeleton.weapon_bone)) * grip
	return [hand * blade_base.position, hand * blade_tip.position]

func set_locomotion(local_velocity: Vector2) -> void:
	# local_velocity: x = strafe right, y = forward, metres per second.
	var speed := local_velocity.length()
	var direction := local_velocity / speed if speed > 0.01 else Vector2.ZERO
	tree.set("parameters/loco/blend_position", direction)
	var stride := _stride_for(direction)
	tree.set("parameters/loco_rate/scale", speed / stride if speed > 0.01 and stride > 0.0 else 1.0)

func _stride_for(direction: Vector2) -> float:
	if direction == Vector2.ZERO:
		return 0.0
	# Weighted by the same axes the blend space uses; good enough for straight lines.
	var forward: float = stride_speeds.walk_forward if direction.y >= 0.0 else stride_speeds.walk_backward
	var side: float = stride_speeds.strafe_right if direction.x >= 0.0 else stride_speeds.strafe_left
	return absf(direction.y) * forward + absf(direction.x) * side

## Starts (or switches to) a rule-driven action clip.
func begin_action(clip: String, fade := 0.08) -> void:
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/action/playback")
	if action.is_empty():
		playback.start(clip, true)
	else:
		playback.travel(clip)
	action = clip
	action_clip_time = -1.0
	action_target = 1.0
	action_fade = fade

func end_action(fade := 0.2) -> void:
	action = ""
	action_target = 0.0
	action_fade = fade

## Places the current action clip at `clip_time` for the next `step()`. For clips whose
## manifest root policy is `root_motion`, the authored root curve is sampled between the
## previous and the new clip time and applied in code (see `step()`).
func drive_action(clip_time: float) -> void:
	if action.is_empty():
		return
	tree.set("parameters/action/%s/seek/seek_request" % action, clip_time)
	if manifest.clips[action].root == "root_motion":
		var clip := tree.get_animation(action)
		var track := clip.find_track(tree.root_motion_track, Animation.TYPE_POSITION_3D)
		var previous: float = action_clip_time if action_clip_time >= 0.0 else clip_time
		pending_root_motion += clip.position_track_interpolate(track, clip_time) - clip.position_track_interpolate(track, previous)
	action_clip_time = clip_time

func flinch() -> void:
	tree.set("parameters/flinch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func set_blade_live(live: bool) -> void:
	blade_material.emission_enabled = live
	blade_material.emission = Color(1.0, 0.25, 0.1)
	blade_material.emission_energy_multiplier = 1.6

## Advances animation by `delta` and applies authored root motion (zero for in-place clips).
func step(delta: float) -> void:
	if action_fade <= 0.0:
		action_weight = action_target
	else:
		action_weight = move_toward(action_weight, action_target, delta / action_fade)
	tree.set("parameters/act/blend_amount", action_weight)
	tree.set("parameters/stance/blend_amount", 1.0)
	if not extra_arm_bones.is_empty():
		tree.set("parameters/limbs/blend_amount", 1.0)
	tree.advance(delta)
	# AnimationMixer.get_root_motion_position() is not used: with a per-frame TimeSeek plus
	# advance(delta) it reported the right magnitude with the opposite sign in 4.7.2
	# (see docs/ANIMATION_PIPELINE.md). The root track still cancels the visual translation.
	var armature := skeleton.get_parent() as Node3D
	var motion: Vector3 = visual.global_basis * armature.transform.basis * pending_root_motion
	pending_root_motion = Vector3.ZERO
	motion.y = 0.0
	root_motion_total += motion
	global_position += motion

## Treadmill speed of an in-place loop: median horizontal speed of whichever ball-of-foot
## joint (the toe-roll pivot) is lowest across one cycle. Code-driven movement must match
## it or feet slide.
func measure_stride_speed(clip: Animation) -> float:
	var player := AnimationPlayer.new()
	visual.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	library.add_animation("probe", clip)
	player.add_animation_library("", library)
	var feet := [skeleton.find_bone("ball_l"), skeleton.find_bone("ball_r")]
	var speeds := []
	var previous := {}
	var samples := 60
	for i in samples + 1:
		player.play("probe")
		player.seek(clip.length * i / samples, true)
		var positions := {}
		for foot in feet:
			positions[foot] = skeleton.get_bone_global_pose(foot).origin
		var planted: int = feet[0] if positions[feet[0]].y < positions[feet[1]].y else feet[1]
		if i > 0:
			var d: Vector3 = positions[planted] - previous[planted]
			speeds.append(Vector2(d.x, d.z).length() / (clip.length / samples))
		previous = positions
	player.free()
	speeds.sort()
	return speeds[speeds.size() / 2]
