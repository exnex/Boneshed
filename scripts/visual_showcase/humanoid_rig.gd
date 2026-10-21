extends RefCounted
## Reusable humanoid deform skeleton for the visual showcase. One bone hierarchy with
## UE-style names (pelvis, spine_01..03, upperarm_l, …), the naming the animation
## pipeline research recommends for a later Blender/glTF rig and SkeletonProfileHumanoid
## mapping (docs/ANIMATION_PIPELINE.md). Body variants change *proportions* only; bone
## names, order, parents and sockets are identical, so poses, sockets and equipment
## work on every variant.
##
## Rest pose: relaxed A-pose, model space metres, forward −Z, right +X. Every bone's
## local +Y points at its child (its "tail"), which keeps the IK maths simple.

const BONES := [
	["pelvis", ""], ["spine_01", "pelvis"], ["spine_02", "spine_01"], ["spine_03", "spine_02"],
	["neck_01", "spine_03"], ["head", "neck_01"],
	["clavicle_l", "spine_03"], ["upperarm_l", "clavicle_l"], ["lowerarm_l", "upperarm_l"], ["hand_l", "lowerarm_l"],
	["clavicle_r", "spine_03"], ["upperarm_r", "clavicle_r"], ["lowerarm_r", "upperarm_r"], ["hand_r", "lowerarm_r"],
	["thigh_l", "pelvis"], ["calf_l", "thigh_l"], ["foot_l", "calf_l"], ["ball_l", "foot_l"],
	["thigh_r", "pelvis"], ["calf_r", "thigh_r"], ["foot_r", "calf_r"], ["ball_r", "foot_r"],
]
## Bone → the joint its +Y aims at.
const TAILS := {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
	"neck_01": "head", "head": "head_top", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"hand_l": "hand_l_tip", "clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "hand_r_tip",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "ball_l": "toe_l", "thigh_r": "calf_r", "calf_r": "foot_r",
	"foot_r": "ball_r", "ball_r": "toe_r"}

## Sockets: equipment mount points, as (bone, offset in that bone's local frame).
## grip_* is the centre of the closed fist: the weapon handle axis passes through it
## along the hand's local −Z (towards the blade).
const SOCKETS := {
	"grip_r": ["hand_r", Vector3(0.0, 0.075, 0.0)],
	"grip_l": ["hand_l", Vector3(0.0, 0.075, 0.0)],
	"head": ["head", Vector3(0.0, 0.08, 0.0)],
	"chest": ["spine_03", Vector3(0.0, 0.05, 0.0)],
	"back": ["spine_03", Vector3(0.0, 0.04, 0.14)],
	"hip_l": ["pelvis", Vector3(-0.17, 0.0, 0.0)],
	"hip_r": ["pelvis", Vector3(0.17, 0.0, 0.0)],
	"forearm_l": ["lowerarm_l", Vector3(0.0, 0.13, 0.0)],
}

## Proportion presets. Lengths in metres; `stature` scales vertically.
const PILGRIM := {"name": "pilgrim", "stature": 1.0, "shoulder": 0.19, "hip": 0.095, "upperarm": 0.30, "lowerarm": 0.26,
	"hand": 0.09, "thigh": 0.43, "calf": 0.42, "hunch": 0.0, "arm_spread": 0.28, "girth": 1.0, "neck": 1.0}
## Corrupted soul: taller, gaunt, long-armed, hunched forward.
const CORRUPTED := {"name": "corrupted", "stature": 1.03, "shoulder": 0.2, "hip": 0.09, "upperarm": 0.325, "lowerarm": 0.3,
	"hand": 0.10, "thigh": 0.44, "calf": 0.44, "hunch": 0.07, "arm_spread": 0.22, "girth": 0.8, "neck": 0.95}

static func bone_index(name: String) -> int:
	for i in range(BONES.size()):
		if BONES[i][0] == name:
			return i
	return -1

## Model-space joint positions for a proportion preset, including tail-only joints.
static func joints(p: Dictionary) -> Dictionary:
	var k: float = p.stature
	var hunch: float = p.hunch
	var j := {}
	var hip_y: float = (p.calf + p.thigh + 0.09) * 1.0
	j.pelvis = Vector3(0.0, hip_y + 0.04, 0.0)
	j.spine_01 = Vector3(0.0, hip_y + 0.12 * k, 0.0)
	j.spine_02 = Vector3(0.0, hip_y + 0.26 * k, -hunch * 0.4)
	j.spine_03 = Vector3(0.0, hip_y + 0.40 * k, -hunch)
	var shoulder_y: float = hip_y + 0.51 * k
	j.neck_01 = Vector3(0.0, hip_y + 0.585 * k, -hunch * 1.7 - 0.005)
	j.head = Vector3(0.0, j.neck_01.y + 0.09 * k * float(p.neck), j.neck_01.z - hunch * 0.6)
	j.head_top = j.head + Vector3(0.0, 0.2 * k, 0.0)
	for side: Array in [["l", -1.0], ["r", 1.0]]:
		var s: String = side[0]
		var x: float = side[1]
		j["clavicle_" + s] = Vector3(x * 0.025, shoulder_y + 0.015, -hunch - 0.02)
		j["upperarm_" + s] = Vector3(x * float(p.shoulder), shoulder_y, -hunch * 0.8)
		var arm := Vector3(x * float(p.arm_spread), -1.0, 0.0).normalized()
		j["lowerarm_" + s] = j["upperarm_" + s] + arm * float(p.upperarm)
		j["hand_" + s] = j["lowerarm_" + s] + arm * float(p.lowerarm)
		j["hand_" + s + "_tip"] = j["hand_" + s] + arm * float(p.hand)
		j["thigh_" + s] = Vector3(x * float(p.hip), hip_y, 0.0)
		j["calf_" + s] = j["thigh_" + s] + Vector3(0.0, -float(p.thigh), -0.01)
		j["foot_" + s] = j["calf_" + s] + Vector3(0.0, -float(p.calf), 0.01)
		j["ball_" + s] = Vector3(j["foot_" + s].x, 0.025, j["foot_" + s].z - 0.13)
		j["toe_" + s] = j["ball_" + s] + Vector3(0.0, 0.0, -0.07)
	return j

## Model-space rest transform of every bone (origin at its joint, +Y toward its tail).
static func rest_globals(p: Dictionary) -> Dictionary:
	var j := joints(p)
	var out := {}
	for entry: Array in BONES:
		var name: String = entry[0]
		var head: Vector3 = j[name]
		var tail: Vector3 = j[TAILS[name]]
		var hint := Vector3.BACK
		if name.begins_with("foot") or name.begins_with("ball"):
			hint = Vector3.UP
		out[name] = Transform3D(basis_from_y((tail - head).normalized(), hint), head)
	return out

static func basis_from_y(y: Vector3, hint := Vector3.BACK) -> Basis:
	var z := hint - y * hint.dot(y)
	if z.length() < 0.001:
		z = Vector3.UP - y * y.y
	z = z.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()

static func bone_length(p: Dictionary, name: String) -> float:
	var j := joints(p)
	return (j[name] as Vector3).distance_to(j[TAILS[name]])

## Builds the Skeleton3D (rest = pose = A-pose) and its sockets.
static func build_skeleton(p: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var globals := rest_globals(p)
	for entry: Array in BONES:
		var index := skeleton.add_bone(entry[0])
		var parent_name: String = entry[1]
		var local: Transform3D = globals[entry[0]]
		if parent_name != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(parent_name))
			local = (globals[parent_name] as Transform3D).affine_inverse() * local
		skeleton.set_bone_rest(index, local)
		skeleton.set_bone_pose(index, local)
	for socket: String in SOCKETS:
		var attachment := BoneAttachment3D.new()
		attachment.name = "socket_" + socket
		attachment.bone_name = SOCKETS[socket][0]
		skeleton.add_child(attachment)
		var marker := Marker3D.new()
		marker.name = "point"
		marker.position = SOCKETS[socket][1]
		attachment.add_child(marker)
	return skeleton

## Socket transform in model space for a set of bone globals (used by tests and by
## the pose solver, which works in pure maths before the engine applies the pose).
static func socket_global(globals: Dictionary, socket: String) -> Transform3D:
	var bone_xf: Transform3D = globals[SOCKETS[socket][0]]
	return bone_xf * Transform3D(Basis.IDENTITY, SOCKETS[socket][1])
