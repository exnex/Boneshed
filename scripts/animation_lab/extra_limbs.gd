extends RefCounted
## Modular skeletal attachment: adds a lower arm pair to an existing humanoid
## Skeleton3D at runtime, skins simple procedural geometry to the new bones, and builds a
## curated animation module for them by copying a *structurally identical* source chain
## (the authored human arm). This is reuse inside one compatible rig family, not
## universal retargeting: the attack choreography of four arms still has to be authored.

const SIDES := ["l", "r"]
const CHAIN := ["clavicle", "upperarm", "lowerarm", "hand"]
const SUFFIX := "_low"

static func low_name(bone: String) -> String:
	return bone + SUFFIX

## Adds clavicle/upperarm/lowerarm/hand "_low" bones under `parent_bone`, mirroring the
## human arm rests but dropped by `drop` metres. Returns the new bone names.
static func add_lower_arms(skeleton: Skeleton3D, parent_bone: String, drop: float) -> PackedStringArray:
	var names := PackedStringArray()
	var parent := skeleton.find_bone(parent_bone)
	var parent_rest := skeleton.get_bone_global_rest(parent)
	for side in SIDES:
		var previous := parent
		for link in CHAIN:
			var source := skeleton.find_bone("%s_%s" % [link, side])
			var bone := skeleton.add_bone(low_name("%s_%s" % [link, side]))
			skeleton.set_bone_parent(bone, previous)
			if previous == parent:
				var lowered := skeleton.get_bone_global_rest(source)
				lowered.origin.y -= drop
				lowered.origin.z += 0.02
				skeleton.set_bone_rest(bone, parent_rest.affine_inverse() * lowered)
			else:
				skeleton.set_bone_rest(bone, skeleton.get_bone_rest(source))
			skeleton.reset_bone_pose(bone)
			names.append(skeleton.get_bone_name(bone))
			previous = bone
	return names

## Rotation offset that re-expresses a clavicle rotation authored under `from_parent`
## (spine_03) in the frame of `to_parent` (spine_02).
static func parent_offset(skeleton: Skeleton3D, from_parent: String, to_parent: String) -> Quaternion:
	var from_rest := skeleton.get_bone_global_rest(skeleton.find_bone(from_parent)).basis
	var to_rest := skeleton.get_bone_global_rest(skeleton.find_bone(to_parent)).basis
	return (to_rest.inverse() * from_rest).get_rotation_quaternion()

## A held-pose animation module for the lower arms: samples the human arm chain of
## `source` at `time` and writes it onto the "_low" bones. `swap_sides` lets the lower
## pair mirror the upper choreography in a different role.
static func pose_module(source: Animation, skeleton: Skeleton3D, time: float, offset: Quaternion, track_prefix: String) -> Animation:
	var module := Animation.new()
	module.length = 1.0
	module.loop_mode = Animation.LOOP_LINEAR
	for side in SIDES:
		for link in CHAIN:
			var bone := "%s_%s" % [link, side]
			var source_track := source.find_track(NodePath("%s:%s" % [track_prefix, bone]), Animation.TYPE_ROTATION_3D)
			if source_track < 0:
				continue
			var rotation: Quaternion = source.rotation_track_interpolate(source_track, time)
			if link == "clavicle":
				rotation = (offset * rotation).normalized()
			var track := module.add_track(Animation.TYPE_ROTATION_3D)
			module.track_set_path(track, NodePath("%s:%s" % [track_prefix, low_name(bone)]))
			module.rotation_track_insert_key(track, 0.0, rotation)
	return module

## Skinned tapered tubes along each new arm segment, with weights blended across the
## elbow and wrist so the joints bend instead of breaking apart.
static func build_mesh(skeleton: Skeleton3D, bones: PackedStringArray, material: Material) -> MeshInstance3D:
	var skin := Skin.new()
	var bind := {}
	for name in bones:
		bind[name] = skin.get_bind_count()
		skin.add_named_bind(name, skeleton.get_bone_global_rest(skeleton.find_bone(name)).affine_inverse())
	var tool := SurfaceTool.new()
	tool.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	for side in SIDES:
		var upper := low_name("upperarm_" + side)
		var lower := low_name("lowerarm_" + side)
		var hand := low_name("hand_" + side)
		var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone(upper)).origin
		var elbow := skeleton.get_bone_global_rest(skeleton.find_bone(lower)).origin
		var wrist := skeleton.get_bone_global_rest(skeleton.find_bone(hand)).origin
		var fist := wrist + (wrist - elbow).normalized() * 0.11
		var clavicle := skeleton.get_bone_global_rest(skeleton.find_bone(low_name("clavicle_" + side))).origin
		_tube(tool, clavicle, shoulder, 0.055, 0.06, bind[low_name("clavicle_" + side)], bind[upper])
		_tube(tool, shoulder, elbow, 0.06, 0.045, bind[upper], bind[lower])
		_tube(tool, elbow, wrist, 0.045, 0.035, bind[lower], bind[hand])
		_tube(tool, wrist, fist, 0.04, 0.03, bind[hand], bind[hand])
	tool.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "LowerArms"
	instance.mesh = tool.commit()
	instance.skin = skin
	# MeshInstance3D.new() leaves `skeleton` empty (imported meshes get ".."); without it
	# the skin never binds and the limb renders frozen in its rest pose.
	instance.skeleton = NodePath("..")
	return instance

static func _tube(tool: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float, bone_a: int, bone_b: int) -> void:
	const RINGS := 6
	const SIDES_COUNT := 10
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var rings := []
	for ring in RINGS + 1:
		var t := float(ring) / RINGS
		# Blend into the child bone over the final 30% so the joint bends smoothly.
		var w := clampf((t - 0.7) / 0.3, 0.0, 1.0) * 0.5
		var centre := from.lerp(to, t)
		var radius := lerpf(r0, r1, t)
		var verts := []
		for i in SIDES_COUNT:
			var angle := TAU * i / SIDES_COUNT
			verts.append([centre + (side * cos(angle) + up * sin(angle)) * radius, w])
		rings.append(verts)
	for ring in RINGS:
		for i in SIDES_COUNT:
			var j := (i + 1) % SIDES_COUNT
			for vert in [rings[ring][i], rings[ring + 1][j], rings[ring + 1][i], rings[ring][i], rings[ring][j], rings[ring + 1][j]]:
				tool.set_bones(PackedInt32Array([bone_a, bone_b, 0, 0]))
				tool.set_weights(PackedFloat32Array([1.0 - vert[1], vert[1], 0.0, 0.0]))
				tool.add_vertex(vert[0])
