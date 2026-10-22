extends RefCounted
## Rules pose → bone transforms for the showcase's 22-bone humanoid rig. Pure maths;
## the presentation applies the result through the showcase PoseModifier.
##
## The upper body turns and leans rigidly about the pelvis exactly as the motion
## library assumes when it checks reach, so the shoulders the IK starts from are the
## shoulders the motion was fitted to. Every gripping hand is solved with two-bone IK
## so its grip socket lands on the hold's generated grip point; free hands rest in a
## guard; a handless replaced limb (Marrow Arm) is posed but grips nothing. Legs keep a
## stance and step with the rules' velocity.

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
## Wrist → grip centre (the rig's grip socket offset).
const GRIP := 0.075
const UPPER := ["spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]

var p: Dictionary
var rest: Dictionary
var rest_local: Dictionary = {}
var lengths: Dictionary = {}
var pivot: Vector3
var handless: Array = []
var gait_phase := 0.0
var gait_weight := 0.0

func _init(body: Dictionary) -> void:
	p = body.proportions
	rest = Rig.rest_globals(p)
	for entry: Array in Rig.BONES:
		var parent: String = entry[1]
		rest_local[entry[0]] = (rest[parent] as Transform3D).affine_inverse() * (rest[entry[0]] as Transform3D) if parent != "" else rest[entry[0]]
	for bone: String in ["upperarm_r", "lowerarm_r", "thigh_r", "calf_r"]:
		lengths[bone.trim_suffix("_r")] = Rig.bone_length(p, bone)
	pivot = (rest.pelvis as Transform3D).origin
	for hand: String in ["hand_r", "hand_l"]:
		if not hand in body.hands:
			handless.append(hand.trim_prefix("hand_"))

## view: {pose (rules pose, fighter frame; may be empty), hold, a_local, state,
## state_time, velocity (fighter frame), dodge_dir (fighter frame)}.
## Returns {bones: {name: Transform3D}, stretch: {side: float}}.
func solve(view: Dictionary, delta: float) -> Dictionary:
	var pose: Dictionary = view.get("pose", {})
	var state: String = view.get("state", "idle")
	var yaw: float = pose.get("yaw", 0.0)
	var lean: float = pose.get("lean", 0.0)
	var crouch := 0.02
	var shift := Vector3.ZERO
	match state:
		"attack", "guard":
			crouch = 0.03
		"dodge":
			var u := clampf(float(view.get("state_time", 0.0)) / 0.42, 0.0, 1.0)
			crouch = 0.03 + 0.12 * sin(u * PI)
			shift = (view.get("dodge_dir", Vector3.ZERO) as Vector3) * 0.06 * sin(u * PI)
			lean += 0.15 * sin(u * PI)
		"stagger", "recoil":
			lean -= 0.22 * exp(-float(view.get("state_time", 0.0)) * 4.0)
		"broken":
			crouch = 0.14
			lean += 0.35
		"dead":
			var u := clampf(float(view.get("state_time", 0.0)) / 0.8, 0.0, 1.0)
			crouch = 0.55 * u
			lean -= 1.2 * u
	var g := {}
	var hip := pivot + Vector3(0.0, -crouch, 0.0) + shift
	var torso := Transform3D(Motion.torso_basis(yaw, lean), hip) * Transform3D(Basis.IDENTITY, -pivot)
	var pelvis_turn := Transform3D(Basis(Vector3.UP, -yaw * 0.35), hip) * Transform3D(Basis.IDENTITY, -pivot)
	g.pelvis = pelvis_turn * (rest.pelvis as Transform3D)
	for bone: String in UPPER:
		g[bone] = torso * (rest[bone] as Transform3D)
	# Keep the eyes on the opponent while the trunk winds and unwinds.
	for entry: Array in [["neck_01", 0.4], ["head", 0.75]]:
		var xf: Transform3D = g[entry[0]]
		g[entry[0]] = Transform3D(Basis(Vector3.UP, yaw * float(entry[1])) * xf.basis, xf.origin)
	var stretch := {}
	var hands: Dictionary = pose.get("hands", {})
	for side: String in ["r", "l"]:
		var hand := "hand_" + side
		if hands.has(hand):
			var obj: Transform3D = pose.object
			var tangent: Vector3 = (view.hold.tangents[hand] as Vector3)
			if tangent.dot(view.get("a_local", tangent)) < 0.0:
				tangent = -tangent
			stretch[side] = _arm_ik(g, side, hands[hand], -(obj.basis * tangent).normalized())
		elif side in handless:
			# The replaced limb hangs slightly forward, ready to brace; it grips nothing.
			var upper: Transform3D = g["upperarm_" + side]
			var swing := Basis(upper.basis.x, -0.35)
			g["upperarm_" + side] = Transform3D(swing * upper.basis, upper.origin)
			for child: String in ["lowerarm_" + side, "hand_" + side]:
				var parent: String = Rig.BONES[Rig.bone_index(child)][1]
				g[child] = (g[parent] as Transform3D) * (rest_local[child] as Transform3D)
		else:
			# A free hand holds a loose guard in front of the chest.
			var x := 0.2 if side == "r" else -0.2
			var target := torso * Vector3(x, pivot.y + 0.22, -0.24)
			stretch[side] = _arm_ik(g, side, target, Vector3(0.0, 1.0, -0.4).normalized())
	_legs(g, view, delta, hip, crouch)
	return {"bones": g, "stretch": stretch}

## Two-bone IK: shoulder → wrist so that the grip socket (wrist + knuckles·GRIP) is at
## `grip` with the handle along −hand_z. Returns the stretch factor (1 = in reach).
func _arm_ik(g: Dictionary, side: String, grip: Vector3, hand_z: Vector3) -> float:
	var shoulder := (g["upperarm_" + side] as Transform3D).origin
	var away := grip - shoulder
	away -= hand_z * away.dot(hand_z)
	if away.length() < 0.001:
		away = Vector3.DOWN - hand_z * hand_z.y
	var knuckles := away.normalized()
	var wrist := grip - knuckles * GRIP
	var x := 1.0 if side == "r" else -1.0
	var torso_basis: Basis = (g.spine_03 as Transform3D).basis
	var pole := shoulder + torso_basis * Vector3(x * 0.5, -0.9, 0.45)
	var solved := two_bone(shoulder, wrist, float(lengths.upperarm), float(lengths.lowerarm), pole)
	var elbow: Vector3 = solved.mid
	var upper_y := (elbow - shoulder).normalized()
	var lower_y := (wrist - elbow).normalized()
	var hand_basis := _orthonormal(knuckles, hand_z)
	g["upperarm_" + side] = Transform3D(Rig.basis_from_y(upper_y, torso_basis.z), shoulder)
	g["lowerarm_" + side] = Transform3D(Rig.basis_from_y(lower_y, hand_basis.z), elbow)
	g["hand_" + side] = Transform3D(hand_basis, wrist)
	return solved.stretch

static func _orthonormal(y: Vector3, z: Vector3) -> Basis:
	var yy := y.normalized()
	var zz := (z - yy * z.dot(yy)).normalized()
	return Basis(yy.cross(zz), yy, zz)

## Law-of-cosines two-bone solve (same maths as the showcase pose solver). Returns
## {mid, stretch}; out of reach, both bones scale by `stretch` to keep the end on target.
static func two_bone(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Dictionary:
	var to_target := target - root
	var d := to_target.length()
	var stretch := 1.0
	if d > (l1 + l2) * 0.9999:
		stretch = d / ((l1 + l2) * 0.9999)
	var a := l1 * stretch
	var b := l2 * stretch
	d = clampf(d, absf(a - b) + 0.0001, a + b)
	var u := to_target.normalized() if to_target.length() > 0.0001 else Vector3.DOWN
	var pole_dir := (pole - root) - u * (pole - root).dot(u)
	if pole_dir.length() < 0.0001:
		pole_dir = Vector3.BACK - u * u.z
	var v := pole_dir.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	return {"mid": root + u * (a * cos_a) + v * (a * sqrt(maxf(0.0, 1.0 - cos_a * cos_a))), "stretch": stretch}

func _legs(g: Dictionary, view: Dictionary, delta: float, hip: Vector3, crouch: float) -> void:
	var velocity: Vector3 = view.get("velocity", Vector3.ZERO)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	gait_weight = move_toward(gait_weight, 1.0 if speed > 0.25 else 0.0, delta * 5.0)
	gait_phase = fmod(gait_phase + delta * speed * 3.2, TAU)
	var dir := velocity.normalized() if speed > 0.01 else Vector3.ZERO
	var state: String = view.get("state", "idle")
	var wide := state in ["attack", "guard", "broken"]
	var stance := {"l": Vector3(-0.13, 0.0, -0.17 if wide else -0.08), "r": Vector3(0.15, 0.0, 0.15 if wide else 0.07)}
	for side: String in ["l", "r"]:
		var phase := gait_phase + (PI if side == "r" else 0.0)
		var foot := (rest["foot_" + side] as Transform3D).origin
		var target: Vector3 = stance[side] + Vector3(0.0, foot.y, 0.0)
		target += dir * 0.2 * sin(phase) * gait_weight
		target.y += maxf(0.0, cos(phase)) * 0.08 * gait_weight
		var hip_joint: Vector3 = (g.pelvis as Transform3D) * (rest_local["thigh_" + side] as Transform3D).origin
		var pole := hip_joint + Vector3(0.0, -0.4, -1.0)
		var solved := two_bone(hip_joint, target, float(lengths.thigh), float(lengths.calf), pole)
		var knee: Vector3 = solved.mid
		g["thigh_" + side] = Transform3D(Rig.basis_from_y((knee - hip_joint).normalized(), Vector3.BACK), hip_joint)
		g["calf_" + side] = Transform3D(Rig.basis_from_y((target - knee).normalized(), Vector3.BACK), knee)
		g["foot_" + side] = Transform3D((rest["foot_" + side] as Transform3D).basis, target)
		g["ball_" + side] = (g["foot_" + side] as Transform3D) * (rest_local["ball_" + side] as Transform3D)
