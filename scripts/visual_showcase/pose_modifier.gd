extends SkeletonModifier3D
## Writes the pose solver's model-space bone transforms to the skeleton as local poses
## (the procedural layer of docs/engineering/GODOT_DEVELOPMENT_GUIDE.md §13). Bones are
## visited in hierarchy order, so each parent's posed transform is known first.
## Presentation only; the rules never read the skeleton.

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")

## bone name → model-space Transform3D, set each frame by showcase_visual.gd.
var globals: Dictionary = {}

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or globals.is_empty():
		return
	apply(skeleton, globals)

static func apply(skeleton: Skeleton3D, pose: Dictionary) -> void:
	for entry: Array in Rig.BONES:
		var name: String = entry[0]
		if not pose.has(name):
			continue
		var index := skeleton.find_bone(name)
		var global: Transform3D = pose[name]
		var local := global
		var parent: String = entry[1]
		if parent != "" and pose.has(parent):
			local = (pose[parent] as Transform3D).affine_inverse() * global
		skeleton.set_bone_pose_position(index, local.origin)
		skeleton.set_bone_pose_rotation(index, local.basis.orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_scale(index, Vector3.ONE)
