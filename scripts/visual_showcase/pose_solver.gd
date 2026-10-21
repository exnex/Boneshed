extends RefCounted
## Procedural pose for one showcase character, computed from a read-only view of the
## melee lab rules state. Presentation only: nothing here feeds back into rules.
##
## The contract with the contact solver:
##   - The weapon transform is the rules pose (hand, dir) in every phase in which the
##     weapon can take part in contact (idle, windup, swing, recovery, recoil, stagger,
##     broken, dodge) — exactly what the lab draws. The right fist is then placed on
##     it by two-bone IK, so the hand follows the weapon, never the reverse.
##   - Only during ROLL (the solver ignores an evading fighter's weapon) and DEAD may
##     the drawn weapon leave the rules pose, and the roll blends back to it before
##     the roll ends (tested).
##
## Output: model-space bone transforms (frame = rules local frame: origin between the
## feet, forward −Z) plus the weapon transform. `pose_modifier.gd` writes them to the
## Skeleton3D. All smoothing is deterministic given the same `delta` sequence.

const Rig = preload("res://scripts/visual_showcase/humanoid_rig.gd")
const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")

## Fraction of the roll spent tumbling; the rest blends the weapon back to the rules pose.
const ROLL_TUMBLE := 0.78
const GRIP := 0.075 # Wrist → grip centre along the hand (matches humanoid_rig SOCKETS).
const DEATH_FALL := 1.4
## Second hand of a two-handed weapon, behind the primary grip (weapon_builder.gd).
const SECOND_HAND := 0.2

var p: Dictionary
var rest: Dictionary # bone → rest global (model space)
var rest_local: Dictionary # bone → rest local (relative to parent)
var lengths: Dictionary
var marrow_arm := false

# Smoothed state (critically damped / lightly underdamped springs).
var hip_yaw := 0.0
var hip_yaw_v := 0.0
var chest_yaw := 0.0
var chest_yaw_v := 0.0
var pitch := 0.0
var pitch_v := 0.0
var bend := 0.0
var bend_v := 0.0
var crouch := 0.0
var crouch_v := 0.0
var shift := Vector3.ZERO # pelvis horizontal shift
var shift_v := Vector3.ZERO
var impact := Vector3.ZERO # hit reaction vector (x: side, y: down, z: back)
var impact_v := Vector3.ZERO
var head_yaw := 0.0
var head_pitch := 0.0
var gait_phase := 0.0
var gait_weight := 0.0
var edge_axis := Vector3.RIGHT
var off_hand := Vector3.ZERO
var off_hand_ready := false
var dead_time := 0.0
var dead_side := 1.0
var roll_axis := Vector3.RIGHT
var clock := 0.0
## Diagnostics for tests: last frame's IK stretch (≥ 1 means unreachable).
var stretch_r := 1.0
var stretch_l := 1.0
var weapon_free := false
## Two-handed weapons: whether the off hand is on the hilt this frame.
var two_hand_contact := false
var dropped_weapon := Transform3D.IDENTITY

func _init(proportions: Dictionary, with_marrow_arm := false) -> void:
	p = proportions
	marrow_arm = with_marrow_arm
	rest = Rig.rest_globals(p)
	for entry: Array in Rig.BONES:
		var name: String = entry[0]
		var parent: String = entry[1]
		rest_local[name] = rest[name] if parent == "" else (rest[parent] as Transform3D).affine_inverse() * rest[name]
		lengths[name] = Rig.bone_length(p, name)
	var j := Rig.joints(p)
	lengths.arm_upper = (j.upperarm_r as Vector3).distance_to(j.lowerarm_r)
	lengths.arm_lower = (j.lowerarm_r as Vector3).distance_to(j.hand_r)
	lengths.leg_upper = (j.thigh_r as Vector3).distance_to(j.calf_r)
	lengths.leg_lower = (j.calf_r as Vector3).distance_to(j.foot_r)

func reset() -> void:
	for key: String in ["hip_yaw", "hip_yaw_v", "chest_yaw", "chest_yaw_v", "pitch", "pitch_v", "bend", "bend_v", "crouch", "crouch_v",
			"head_yaw", "head_pitch", "gait_phase", "gait_weight", "dead_time"]:
		set(key, 0.0)
	shift = Vector3.ZERO
	shift_v = Vector3.ZERO
	impact = Vector3.ZERO
	impact_v = Vector3.ZERO
	edge_axis = Vector3.RIGHT
	off_hand_ready = false
	weapon_free = false

## Contact feedback (presentation): `direction` is the local push direction (away from
## the blow), `strength` 0..1.
func kick(direction: Vector3, strength: float) -> void:
	impact_v += direction.normalized() * strength * 5.0

static func _spring(x: float, v: float, target: float, freq: float, damping: float, dt: float) -> Vector2:
	var w := TAU * freq
	v += (w * w * (target - x) - 2.0 * damping * w * v) * dt
	x += v * dt
	return Vector2(x, v)

func _spring_v3(x: Vector3, v: Vector3, target: Vector3, freq: float, damping: float, dt: float) -> Array:
	var w := TAU * freq
	v += (w * w * (target - x) - 2.0 * damping * w * v) * dt
	return [x + v * dt, v]

## `view` keys: phase, hand, dir, direction, guarding, guard, two_handed, inertia, omega,
## velocity (local), dodge_dir (local), progress (dodge/roll 0..1), posture (0..1),
## look (local point), released.
func solve(view: Dictionary, delta: float) -> Dictionary:
	var dt := minf(delta, 1.0 / 30.0)
	clock += dt
	var phase: int = view.phase
	var hand: Vector3 = view.hand
	var dir: Vector3 = view.dir
	var inertia: float = view.inertia
	var heavy := clampf((inertia - 1.0) / 6.0, 0.0, 1.0)
	var velocity: Vector3 = view.velocity
	var speed := Vector2(velocity.x, velocity.z).length()
	var posture: float = view.posture

	# --- Targets from the rules pose (the weapon leads; the body follows) -------------
	var lateral := atan2(hand.x, -hand.z) # >0: hand to the right of forward.
	var yaw_target := -0.55 * clampf(lateral, -1.9, 1.9)
	var pitch_target := 0.1 + 0.12 * posture
	var bend_target := 0.18 * clampf(-hand.x / 0.6, -1.0, 1.0)
	var crouch_target := 0.035 + 0.05 * posture
	var shift_target := Vector3.ZERO
	match phase:
		State.Phase.WINDUP:
			pitch_target += -0.12 * clampf((hand.y - 1.35) / 0.5, -1.0, 1.0)
			crouch_target += 0.03
			shift_target = Vector3(0.0, 0.0, 0.04)
		State.Phase.SWING:
			pitch_target += 0.18
			crouch_target += 0.06
			shift_target = Vector3(0.0, 0.0, -0.08)
		State.Phase.RECOVERY:
			pitch_target += 0.1
			crouch_target += 0.05
			shift_target = Vector3(0.0, 0.0, -0.05)
		State.Phase.RECOIL:
			pitch_target -= 0.12
			shift_target = Vector3(0.0, 0.0, 0.06)
		State.Phase.STAGGER:
			pitch_target -= 0.18
			crouch_target += 0.06
		State.Phase.BROKEN:
			pitch_target += 0.45 + 0.05 * sin(clock * 5.0)
			crouch_target += 0.14
			yaw_target *= 0.3
		State.Phase.DODGE:
			var lean: Vector3 = view.dodge_dir
			var s := sin(PI * clampf(view.progress, 0.0, 1.0))
			pitch_target += -lean.z * 0.25 * s
			bend_target += -lean.x * 0.3 * s
			crouch_target += 0.12 * s
			shift_target = Vector3(lean.x, 0.0, lean.z) * 0.12 * s
	if view.guarding:
		crouch_target += 0.04
		pitch_target += 0.05
	# Locomotion lean.
	pitch_target += -velocity.z * 0.03
	bend_target += -velocity.x * 0.03

	# Heavier weapons move the trunk more slowly: follow-through and settle.
	var trunk_freq := lerpf(3.2, 1.7, heavy)
	var hip_freq := trunk_freq * 1.35
	var r := _spring(hip_yaw, hip_yaw_v, yaw_target * 0.45, hip_freq, 0.62, dt)
	hip_yaw = r.x
	hip_yaw_v = r.y
	r = _spring(chest_yaw, chest_yaw_v, yaw_target, trunk_freq, 0.55, dt)
	chest_yaw = r.x
	chest_yaw_v = r.y
	r = _spring(pitch, pitch_v, pitch_target, trunk_freq * 1.2, 0.7, dt)
	pitch = r.x
	pitch_v = r.y
	r = _spring(bend, bend_v, bend_target, trunk_freq * 1.2, 0.7, dt)
	bend = r.x
	bend_v = r.y
	r = _spring(crouch, crouch_v, crouch_target, 3.0, 0.8, dt)
	crouch = r.x
	crouch_v = r.y
	var sv := _spring_v3(shift, shift_v, shift_target, 2.6, 0.75, dt)
	shift = sv[0]
	shift_v = sv[1]
	var iv := _spring_v3(impact, impact_v, Vector3.ZERO, 2.2, 0.45, dt)
	impact = iv[0]
	impact_v = iv[1]

	# --- Gait --------------------------------------------------------------------------
	var stride := clampf(speed * 0.32, 0.25, 0.75)
	gait_phase = fposmod(gait_phase + speed / maxf(stride * 2.0, 0.01) * TAU * dt, TAU)
	gait_weight = move_toward(gait_weight, smoothstep(0.15, 1.2, speed), dt * 4.0)
	var bob := -0.025 * gait_weight * absf(sin(gait_phase))

	# --- Trunk ---------------------------------------------------------------------------
	var g := {}
	var roll_p := -1.0
	if phase == State.Phase.ROLL:
		roll_p = clampf(view.progress, 0.0, 1.0)
		var tuck := sin(PI * minf(roll_p / ROLL_TUMBLE, 1.0))
		crouch = maxf(crouch, 0.42 * tuck)
		pitch = maxf(pitch, 0.9 * tuck)
	if phase == State.Phase.DEAD:
		dead_time += dt
		var buckle := smoothstep(0.0, 0.5, dead_time)
		crouch = maxf(crouch, 0.38 * buckle)
		pitch = lerpf(pitch, 0.7, buckle)
	else:
		dead_time = 0.0
	var pelvis_origin: Vector3 = (rest.pelvis as Transform3D).origin + shift + Vector3(impact.x * 0.08, -crouch + bob, impact.z * 0.08)
	var hips := Basis(Vector3.UP, hip_yaw) * Basis(Vector3.RIGHT, -pitch * 0.25)
	g.pelvis = Transform3D(hips * (rest.pelvis as Transform3D).basis, pelvis_origin)
	var lean_total := Basis(Vector3.UP, chest_yaw - hip_yaw) * Basis(Vector3.RIGHT, -(pitch * 0.75 - impact.z * 0.55)) * Basis(Vector3.BACK, bend + impact.x * 0.3)
	var spine_share := {"spine_01": 0.25, "spine_02": 0.35, "spine_03": 0.4}
	var accumulated := hips
	for bone: String in ["spine_01", "spine_02", "spine_03"]:
		var part := Basis(lean_total.get_rotation_quaternion().slerp(Quaternion.IDENTITY, 1.0 - spine_share[bone]))
		_fk(g, bone, accumulated)
		accumulated = part * accumulated
		g[bone] = Transform3D(accumulated * (rest[bone] as Transform3D).basis, (g[bone] as Transform3D).origin)
	var chest: Basis = accumulated

	# Reach assist: when the grip is beyond the arm, the trunk leans and steps toward it,
	# then turns, and the clavicle protracts — the way a fencer lunges into a thrust or
	# winds across the body for a backhand. Continuous in the hand position, so it never
	# pops; the drawn trunk stays inside the hurt capsule radius (tested).
	var protract := 0.0
	var excess := _wrist_excess(g, chest, hand, dir)
	if excess > 0.0:
		# Lunge: step (≤ 0.16 m, and down for low grips) and lean (≤ 0.5 rad) toward the
		# grip by the smallest fraction that suffices.
		var flat := Vector3(hand.x, 0.0, hand.z)
		var toward := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
		var drop := clampf((_shoulder(g, chest, "r", 0.0).y - hand.y - 0.1) * 2.0, 0.0, 1.0) * 0.18
		var lunge := func(a: float) -> Array:
			var moved := g.duplicate()
			var step := toward * 0.16 * a + Vector3.DOWN * drop * a
			var lean := Basis(Vector3.UP.cross(toward).normalized(), 0.5 * a)
			var pivot := (g.spine_01 as Transform3D).origin + step
			for bone: String in ["pelvis", "spine_01", "spine_02", "spine_03"]:
				var xf: Transform3D = g[bone]
				xf.origin += step
				if bone in ["spine_02", "spine_03"]:
					xf = Transform3D(lean * xf.basis, pivot + lean * (xf.origin - pivot))
				moved[bone] = xf
			return [moved, lean * chest]
		var amount := _bisect(func(a: float) -> float:
			var trial: Array = lunge.call(a)
			return _wrist_excess(trial[0], trial[1], hand, dir), 1.0)
		var applied: Array = lunge.call(amount)
		g = applied[0]
		chest = applied[1]
		excess = _wrist_excess(g, chest, hand, dir)
	if excess > 0.0:
		# Turn whichever way brings the wrist into reach (left for forward and cross-body
		# grips, right for grips wound back on the sword side), by the smallest angle
		# that suffices (bisection), then protract the clavicle if still short.
		var sign := 1.0 if _wrist_excess(g, Basis(Vector3.UP, 0.9) * chest, hand, dir) <= _wrist_excess(g, Basis(Vector3.UP, -0.9) * chest, hand, dir) else -1.0
		var turn := _bisect(func(a: float) -> float: return _wrist_excess(g, Basis(Vector3.UP, a * sign) * chest, hand, dir), 0.9)
		var extra := Basis(Vector3.UP, turn * sign)
		g.spine_03 = Transform3D(extra * (g.spine_03 as Transform3D).basis, (g.spine_03 as Transform3D).origin)
		chest = extra * chest
		if _wrist_excess(g, chest, hand, dir) > 0.0:
			protract = _bisect(func(a: float) -> float: return _wrist_excess(g, chest, hand, dir, a), 0.45)
	pelvis_origin = (g.pelvis as Transform3D).origin

	# Neck and head: look at the opponent, counter-rotating the trunk.
	_fk(g, "neck_01", chest)
	var look: Vector3 = view.look
	var head_pos := (g.neck_01 as Transform3D).origin
	var to_look := look - head_pos
	var want_yaw := clampf(atan2(-to_look.x, -to_look.z) - (chest_yaw), -1.0, 1.0)
	var want_pitch := clampf(atan2(to_look.y, Vector2(to_look.x, to_look.z).length()) + pitch * 0.8, -0.6, 0.5)
	if phase == State.Phase.DEAD or phase == State.Phase.BROKEN:
		want_pitch = 0.5
		want_yaw = 0.0
	head_yaw = lerpf(head_yaw, want_yaw, 1.0 - exp(-10.0 * dt))
	head_pitch = lerpf(head_pitch, want_pitch, 1.0 - exp(-10.0 * dt))
	var neck_basis := Basis(Vector3.UP, head_yaw * 0.4) * chest * Basis(Vector3.RIGHT, head_pitch * 0.3)
	g.neck_01 = Transform3D(neck_basis * (rest.neck_01 as Transform3D).basis, (g.neck_01 as Transform3D).origin)
	_fk(g, "head", Basis(Vector3.UP, head_yaw) * chest)
	var head_basis := Basis(Vector3.UP, head_yaw) * Basis(Vector3.RIGHT, head_pitch * 0.7 + impact.z * 0.4) * Basis(Vector3.BACK, impact.x * 0.4) * chest
	g.head = Transform3D(head_basis * (rest.head as Transform3D).basis, (g.head as Transform3D).origin)

	# --- Weapon ------------------------------------------------------------------------
	_update_edge(view, dir, dt)
	var weapon := Transform3D(_weapon_basis(dir), hand)
	weapon_free = false

	# --- Arms ------------------------------------------------------------------------------
	for side: String in ["l", "r"]:
		var prot := protract if side == "r" else 0.0
		var cl_basis := Basis(Vector3.UP, prot * (1.0 if side == "r" else -1.0)) * chest
		_fk(g, "clavicle_" + side, chest)
		g["clavicle_" + side] = Transform3D(cl_basis * (rest["clavicle_" + side] as Transform3D).basis, (g["clavicle_" + side] as Transform3D).origin)
	var grip_r := hand
	var hand_z := -dir
	var shoulder_r := (g.clavicle_r as Transform3D) * (rest_local.upperarm_r as Transform3D).origin
	stretch_r = _arm_ik(g, "r", grip_r, hand_z, _knuckles(hand_z, grip_r - shoulder_r))
	if view.two_handed:
		# The off hand takes the hilt behind the primary fist. Where the rules pose puts
		# that point beyond the left arm (wide right-side guards and cut endings), the
		# hand reaches toward it and lets go instead of stretching the arm.
		var grip_l := hand - dir * SECOND_HAND
		_fk(g, "upperarm_l", Basis.IDENTITY)
		var shoulder_l := (g.upperarm_l as Transform3D).origin
		var reach_l: float = (lengths.arm_upper + lengths.arm_lower) * 0.985
		var knuckles_l := _knuckles(hand_z, grip_l - shoulder_l)
		var wrist_l := grip_l - knuckles_l * GRIP
		var target_l := grip_l
		if shoulder_l.distance_to(wrist_l) > reach_l:
			target_l = shoulder_l + (wrist_l - shoulder_l).normalized() * reach_l + knuckles_l * GRIP
		two_hand_contact = target_l.distance_to(grip_l) < 0.001
		stretch_l = _arm_ik(g, "l", target_l, hand_z, knuckles_l)
	else:
		var target := _off_hand_target(phase, view, chest, pelvis_origin)
		if not off_hand_ready:
			off_hand = target
			off_hand_ready = true
		off_hand = off_hand.lerp(target, 1.0 - exp(-8.0 * dt))
		var palm := (chest * Vector3(0.3, -0.2, -1.0)).normalized()
		stretch_l = _arm_ik(g, "l", off_hand, palm, (chest * Vector3(0.0, -1.0, -0.3)).normalized())

	# --- Legs ------------------------------------------------------------------------------
	_legs(g, view, phase, speed, velocity, stride, roll_p)

	# --- Whole-body motions: roll tumble and death fall ------------------------------------
	if roll_p >= 0.0:
		var dodge_dir: Vector3 = view.dodge_dir
		var flat := Vector3(dodge_dir.x, 0.0, dodge_dir.z)
		if flat.length_squared() < 0.0001:
			flat = Vector3.BACK
		roll_axis = Vector3.UP.cross(flat.normalized()).normalized()
		var spin := TAU * smoothstep(0.0, ROLL_TUMBLE, roll_p)
		var pivot := Vector3(0.0, 0.42, 0.0)
		var rot := Transform3D(Basis(roll_axis, -spin), Vector3.ZERO)
		var xf := Transform3D.IDENTITY.translated(pivot) * rot * Transform3D.IDENTITY.translated(-pivot)
		var lift := Vector3(0.0, 0.18 * sin(PI * minf(roll_p / ROLL_TUMBLE, 1.0)), 0.0)
		for bone: String in g:
			g[bone] = Transform3D(Basis.IDENTITY, lift) * xf * g[bone]
		# The weapon rides in the fist while tumbling, then returns to the rules pose.
		var in_fist := _grip_xform(g, "r", dir)
		var back := smoothstep(ROLL_TUMBLE, 1.0, roll_p)
		if back < 1.0:
			weapon = _blend_xform(in_fist, weapon, back)
			weapon_free = true
			if back > 0.0:
				# Re-solve the fist onto the blending weapon so hand and weapon stay together.
				stretch_r = 1.0
	if phase == State.Phase.DEAD:
		var fall := smoothstep(0.35, DEATH_FALL, dead_time)
		var axis := Vector3.BACK * dead_side
		var pivot := Vector3(dead_side * 0.15, 0.0, 0.0)
		var xf := Transform3D.IDENTITY.translated(pivot) * Transform3D(Basis(axis, -fall * PI * 0.47), Vector3.ZERO) * Transform3D.IDENTITY.translated(-pivot)
		for bone: String in g:
			g[bone] = xf * g[bone]
		if dead_time <= dt * 1.5:
			dropped_weapon = weapon
		# The weapon slips from the hand and lands flat beside the body.
		var t := smoothstep(0.2, 0.9, dead_time)
		var landed := Transform3D(Basis(Vector3.UP, 0.6 * dead_side) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(dropped_weapon.origin.x + 0.3 * dead_side, 0.03, dropped_weapon.origin.z))
		weapon = _blend_xform(dropped_weapon, landed, t)
		weapon_free = true
	return {"bones": g, "weapon": weapon, "weapon_free": weapon_free}

## Sets `g[bone]` to the bone's rest offset from its (already posed) parent, with basis
## `world_rot * rest basis` (the caller usually overwrites the basis).
func _fk(g: Dictionary, bone: String, world_rot: Basis) -> void:
	var parent: String = Rig.BONES[Rig.bone_index(bone)][1]
	var parent_xf: Transform3D = g[parent]
	var origin := parent_xf * (rest_local[bone] as Transform3D).origin
	g[bone] = Transform3D(world_rot * (rest[bone] as Transform3D).basis, origin)

## How far (m) the wrist target lies beyond the arm's reach (negative when reachable).
## The wrist sits beside the grip (knuckles ⟂ handle), so this is the true IK distance.
func _wrist_excess(g: Dictionary, chest: Basis, hand: Vector3, dir: Vector3, protract := 0.0) -> float:
	var shoulder := _shoulder(g, chest, "r", protract)
	var wrist := hand - _knuckles(-dir, hand - shoulder) * GRIP
	return shoulder.distance_to(wrist) - (lengths.arm_upper + lengths.arm_lower) * 0.985

## Smallest x in [0, limit] with f(x) <= 0 (f decreasing), or limit if none.
static func _bisect(f: Callable, limit: float) -> float:
	if float(f.call(limit)) > 0.0:
		return limit
	var lo := 0.0
	var hi := limit
	for i in range(10):
		var mid := (lo + hi) * 0.5
		if float(f.call(mid)) > 0.0:
			lo = mid
		else:
			hi = mid
	return hi

func _shoulder(g: Dictionary, chest: Basis, side: String, protract: float) -> Vector3:
	var spine: Transform3D = g.spine_03
	var clavicle := spine * (rest_local["clavicle_" + side] as Transform3D).origin
	var cl_basis := Basis(Vector3.UP, protract) * chest * (rest["clavicle_" + side] as Transform3D).basis
	return clavicle + cl_basis * (rest_local["upperarm_" + side] as Transform3D).origin

## Knuckle direction: perpendicular to the handle, in the blade's edge plane, pointing
## away from the shoulder (so the wrist sits between shoulder and grip).
func _knuckles(hand_z: Vector3, from_shoulder: Vector3) -> Vector3:
	var edge := edge_axis - hand_z * edge_axis.dot(hand_z)
	if edge.length() < 0.2:
		edge = from_shoulder - hand_z * from_shoulder.dot(hand_z)
	if edge.length() < 0.001:
		edge = Vector3.DOWN - hand_z * hand_z.y
	edge = edge.normalized()
	var away := from_shoulder - hand_z * from_shoulder.dot(hand_z)
	if away.dot(edge) < 0.0:
		edge = -edge
	# Lean the knuckles toward "away from the shoulder" so wrists bend plausibly.
	var mixed := edge * 0.55 + away.normalized() * 0.45 if away.length() > 0.001 else edge
	mixed = mixed - hand_z * mixed.dot(hand_z)
	return mixed.normalized() if mixed.length() > 0.001 else edge

## Two-bone IK: shoulder → wrist, then the hand so that its grip socket is exactly at
## `grip` with the handle along −hand_z. Returns the stretch factor (1 = reachable).
func _arm_ik(g: Dictionary, side: String, grip: Vector3, hand_z: Vector3, knuckles: Vector3) -> float:
	_fk(g, "upperarm_" + side, Basis.IDENTITY)
	var shoulder := (g["upperarm_" + side] as Transform3D).origin
	var wrist := grip - knuckles * GRIP
	var l1: float = lengths.arm_upper
	var l2: float = lengths.arm_lower
	var x := 1.0 if side == "r" else -1.0
	var pole := shoulder + Vector3(x * 0.45, -1.0, 0.35)
	var solved := two_bone(shoulder, wrist, l1, l2, pole)
	var elbow: Vector3 = solved.mid
	var upper_y := (elbow - shoulder).normalized()
	var lower_y := (wrist - elbow).normalized()
	var hand_basis := _orthonormal(knuckles, hand_z)
	var up_hint := (pole - shoulder).cross(upper_y).normalized() if (pole - shoulder).cross(upper_y).length() > 0.001 else Vector3.BACK
	g["upperarm_" + side] = Transform3D(Rig.basis_from_y(upper_y, upper_y.cross(up_hint)), shoulder)
	g["lowerarm_" + side] = Transform3D(Rig.basis_from_y(lower_y, (hand_basis.z + (g["upperarm_" + side] as Transform3D).basis.z).normalized()), elbow)
	g["hand_" + side] = Transform3D(hand_basis, wrist)
	return solved.stretch

## Basis with +Y = y and +Z as close as possible to z.
static func _orthonormal(y: Vector3, z: Vector3) -> Basis:
	var yy := y.normalized()
	var zz := (z - yy * z.dot(yy)).normalized()
	return Basis(yy.cross(zz), yy, zz)

## Law-of-cosines two-bone solve. Returns {mid, stretch}. When the target is out of
## reach both bones are scaled by `stretch` so the chain still ends on the target.
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
	var mid := root + u * (a * cos_a) + v * (a * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	return {"mid": mid, "stretch": stretch}

func _off_hand_target(phase: int, view: Dictionary, chest: Basis, pelvis: Vector3) -> Vector3:
	var base := Vector3(-0.27, 1.02, -0.1)
	if marrow_arm:
		base = Vector3(-0.34, 1.22, -0.36) + Vector3(0.0, 0.03 * sin(clock * 2.1), 0.0)
	if view.guarding:
		base = Vector3(-0.24, 1.18, -0.24)
	match phase:
		State.Phase.SWING, State.Phase.RECOVERY:
			base = Vector3(-0.32, 1.05, 0.08) if not marrow_arm else Vector3(-0.36, 1.1, 0.02)
		State.Phase.DODGE, State.Phase.ROLL:
			base = Vector3(-0.22, 1.0, -0.2)
		State.Phase.BROKEN, State.Phase.STAGGER:
			base = Vector3(-0.3, 0.95, -0.05)
	var from_pelvis := base - Vector3(0.0, (rest.pelvis as Transform3D).origin.y, 0.0)
	return pelvis + chest * from_pelvis * Vector3(1.0, 1.0, 1.0)

## Blade orientation: the edge lies in the swing plane (or faces the guarded side), so
## the drawn edge leads the cut. Rotation about the handle never changes contact (the
## solver tests a segment), so this is presentation freedom; it is smoothed so it never
## flips.
func _update_edge(view: Dictionary, dir: Vector3, dt: float) -> void:
	var want := Vector3.RIGHT
	var phase: int = view.phase
	var direction: String = view.direction
	if view.guarding:
		want = Geometry.frontal(Geometry.guard_vector(view.guard))
	elif phase in [State.Phase.WINDUP, State.Phase.SWING, State.Phase.RECOVERY] and direction != "" and direction != Geometry.THRUST:
		want = Geometry.frontal(Geometry.chamber_vector(direction))
	want = want - dir * want.dot(dir)
	if want.length() < 0.05:
		want = Vector3.UP.cross(dir)
	want = want.normalized()
	if want.dot(edge_axis) < 0.0:
		want = -want
	var blended := edge_axis.slerp(want, 1.0 - exp(-14.0 * dt)) if edge_axis.angle_to(want) > 0.0001 else want
	edge_axis = (blended - dir * blended.dot(dir)).normalized()

func _weapon_basis(dir: Vector3) -> Basis:
	var z := -dir.normalized()
	var x := edge_axis - z * edge_axis.dot(z)
	if x.length() < 0.001:
		x = Vector3.UP.cross(z)
	x = x.normalized()
	return Basis(x, z.cross(x), z)

func _grip_xform(g: Dictionary, side: String, dir: Vector3) -> Transform3D:
	var hand: Transform3D = g["hand_" + side]
	var grip := hand * Vector3(0.0, GRIP, 0.0)
	var z := hand.basis.z.normalized()
	var x := hand.basis.x.normalized()
	return Transform3D(Basis(x, z.cross(x), z).orthonormalized(), grip)

static func _blend_xform(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	return Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)), a.origin.lerp(b.origin, t))

func _legs(g: Dictionary, view: Dictionary, phase: int, speed: float, velocity: Vector3, stride: float, roll_p: float) -> void:
	var pelvis: Transform3D = g.pelvis
	var move_dir := Vector3(velocity.x, 0.0, velocity.z).normalized() if speed > 0.05 else Vector3.FORWARD
	var hip_turn := Basis(Vector3.UP, hip_yaw * 0.6)
	for side: String in ["l", "r"]:
		var x := -1.0 if side == "l" else 1.0
		# Fighting stance: left foot leads, right foot back, toes slightly out.
		var stance := Vector3(x * 0.13, 0.0, -0.15 if side == "l" else 0.17)
		if view.guarding or phase == State.Phase.BROKEN:
			stance *= Vector3(1.2, 1.0, 1.15)
		var foot := hip_turn * stance + Vector3(shift.x * 0.5, 0.0, shift.z * 0.4)
		var lift := 0.0
		if gait_weight > 0.001:
			var ph := gait_phase + (0.0 if side == "l" else PI)
			var cycle := -move_dir * (stride * 0.5) * cos(ph)
			var walk := Vector3(x * 0.11, 0.0, 0.0) + cycle
			foot = foot.lerp(walk, gait_weight)
			lift = maxf(0.0, sin(ph)) * 0.11 * gait_weight
		if phase == State.Phase.DODGE:
			var s := sin(PI * clampf(view.progress, 0.0, 1.0))
			foot += Vector3(x * 0.08, 0.0, 0.0) * s
		var ankle := Vector3(foot.x, (rest["foot_" + side] as Transform3D).origin.y + lift, foot.z)
		if roll_p >= 0.0:
			var tuck := sin(PI * minf(roll_p / ROLL_TUMBLE, 1.0))
			ankle = ankle.lerp(Vector3(x * 0.12, pelvis.origin.y - 0.35, pelvis.origin.z + 0.12), tuck)
		_fk(g, "thigh_" + side, Basis.IDENTITY)
		var hip := (g["thigh_" + side] as Transform3D).origin
		var toe_dir := (hip_turn * Vector3(x * 0.18, 0.0, -1.0)).normalized()
		var pole := hip + toe_dir + Vector3(0.0, 0.2, 0.0)
		var solved := two_bone(hip, ankle, lengths.leg_upper, lengths.leg_lower, pole)
		var knee: Vector3 = solved.mid
		var thigh_y := (knee - hip).normalized()
		var calf_y := (ankle - knee).normalized()
		g["thigh_" + side] = Transform3D(Rig.basis_from_y(thigh_y, -toe_dir), hip)
		g["calf_" + side] = Transform3D(Rig.basis_from_y(calf_y, -toe_dir), knee)
		# Foot: flat toward the toe (tilted while lifted), ball bone continues to the toe.
		var tilt := lift * 2.5
		var foot_y := (toe_dir * 0.99 + Vector3(0.0, -0.45 + tilt * 0.3, 0.0)).normalized()
		g["foot_" + side] = Transform3D(Rig.basis_from_y(foot_y, Vector3.UP), ankle)
		var ball_origin := ankle + foot_y * float(lengths["foot_" + side])
		var ball_y := (toe_dir + Vector3(0.0, tilt * 0.2, 0.0)).normalized()
		g["ball_" + side] = Transform3D(Rig.basis_from_y(ball_y, Vector3.UP), ball_origin)
