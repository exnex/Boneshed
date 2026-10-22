extends RefCounted
## Motion synthesis for the Adaptive Combat Lab: a small vocabulary of **authored**
## movement principles (keyed poses for a strike axis, torso turn, lean and footwork)
## fitted procedurally to whatever object and hold the affordance solver chose.
##
## A key says where the hold centre C goes (fighter frame: metres, forward −Z, right
## +X), which world direction D the strike axis points (C → active feature), and how
## much the torso turns and leans. The object's rotation maps its own strike axis onto
## D and its leading surface onto the swing's travel direction (an edge leads a cut, a
## face leads a slam), so the visible object, the hands and the contact feature are all
## one rigid transform of the descriptor. Hands are then placed on the hold's grip
## points by IK (adaptive_pose.gd). When a grip would be out of reach the whole hold is
## pulled toward the shoulders (procedural adaptation), and `validate` rejects motions
## that still cannot reach or would pass the object through the wielder's body.
##
## Pure functions of (action, time, body): the rules sample it for contact, the
## presentation samples it for drawing, so they cannot disagree.

const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")

## Authored archetypes. timing = [windup, active, recovery] seconds for an unloaded light
## version (provisional); step = forward footwork (m); axis = swing rotation axis (null
## for straight-line motions). Keys: [loaded, contact, through], each
## [C one-hand, C two-hand, D, torso yaw (+ turns the right shoulder back), lean].
const ARCHETYPES := {
	"thrust": {"timing": [0.24, 0.1, 0.3], "step": 0.32, "axis": null, "keys": [
		[Vector3(0.3, 1.12, 0.0), Vector3(0.26, 1.1, 0.04), Vector3(-0.08, 0.1, -1.0), 0.4, -0.05],
		[Vector3(0.18, 1.2, -0.5), Vector3(0.22, 1.16, -0.42), Vector3(-0.06, 0.03, -1.0), -0.25, 0.15],
		[Vector3(0.16, 1.2, -0.56), Vector3(0.2, 1.16, -0.48), Vector3(-0.05, 0.02, -1.0), -0.3, 0.18]]},
	"sweep": {"timing": [0.28, 0.12, 0.32], "step": 0.12, "axis": Vector3.UP, "keys": [
		[Vector3(0.38, 1.2, -0.05), Vector3(0.3, 1.15, -0.12), Vector3(1.0, 0.15, 0.3), 0.6, 0.0],
		[Vector3(0.12, 1.15, -0.42), Vector3(0.1, 1.12, -0.38), Vector3(-0.35, -0.04, -1.0), -0.05, 0.12],
		[Vector3(-0.12, 1.1, -0.36), Vector3(-0.1, 1.08, -0.32), Vector3(-1.0, -0.12, -0.15), -0.6, 0.12]]},
	"overhead": {"timing": [0.38, 0.12, 0.4], "step": 0.22, "axis": Vector3.LEFT, "keys": [
		[Vector3(0.22, 1.56, 0.0), Vector3(0.14, 1.5, -0.04), Vector3(0.08, 0.8, 0.55), 0.25, -0.12],
		[Vector3(0.16, 1.24, -0.46), Vector3(0.12, 1.2, -0.42), Vector3(-0.05, -0.08, -1.0), -0.05, 0.25],
		[Vector3(0.16, 0.98, -0.42), Vector3(0.12, 0.98, -0.4), Vector3(-0.05, -0.75, -0.6), -0.1, 0.35]]},
	"alternate": {"timing": [0.2, 0.1, 0.26], "step": 0.08, "axis": Vector3.UP, "keys": [
		[Vector3.ZERO, Vector3(0.14, 1.15, -0.22), Vector3(0.85, 0.3, 0.35), 0.45, 0.0],
		[Vector3.ZERO, Vector3(0.06, 1.12, -0.36), Vector3(-0.45, -0.06, -0.9), -0.05, 0.1],
		[Vector3.ZERO, Vector3(-0.04, 1.1, -0.3), Vector3(-0.95, -0.1, -0.25), -0.45, 0.08]]},
	"shove": {"timing": [0.16, 0.1, 0.26], "step": 0.3, "axis": null, "keys": [
		[Vector3(0.24, 1.1, -0.12), Vector3(0.06, 1.14, -0.3), Vector3(0.15, 0.1, -1.0), 0.15, -0.05],
		[Vector3(0.18, 1.14, -0.5), Vector3(0.04, 1.18, -0.55), Vector3(0.1, 0.05, -1.0), -0.1, 0.2],
		[Vector3(0.18, 1.14, -0.56), Vector3(0.04, 1.18, -0.6), Vector3(0.1, 0.05, -1.0), -0.1, 0.22]]},
}
## Heavy variants reuse the archetype with a deeper load, more footwork and longer timing.
const HEAVY_TIMING := [1.6, 1.1, 1.3]
const HEAVY_LOAD := Vector3(0.0, 0.06, 0.1)
const HEAVY_STEP := 0.25
## Ready poses per hold kind: [C, D, yaw, lean].
const READY := {"one_hand": [Vector3(0.26, 1.02, -0.32), Vector3(0.0, 0.4, -1.0), 0.0, 0.0],
	"two_hand": [Vector3(0.16, 1.06, -0.3), Vector3(-0.2, 0.45, -1.0), 0.1, 0.0]}
## Two-hand shove: the shaft between the hands is presented crosswise.
const SHOVE_CROSS := Vector3(1.0, 0.12, -0.05)
const TORSO_RADIUS := 0.15
const HEAD := Vector3(0.0, 1.66, -0.02)
const HEAD_RADIUS := 0.11
const PENETRATION_LIMIT := 0.035
const REACH_LIMIT := 0.015
## Wrist → grip-centre distance (the showcase rig's grip socket offset).
const WRIST_TO_GRIP := 0.075

static func smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static func slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	a = a.normalized()
	b = b.normalized()
	if a.dot(b) > 0.9999:
		return a
	if a.dot(b) < -0.999:
		# Antiparallel (no authored key pair does this): turn about any perpendicular.
		var axis := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
		return a.rotated(axis, PI * t)
	return Quaternion.IDENTITY.slerp(Quaternion(a, b), t) * a

## Torso rotation about the pelvis (fighter frame).
static func torso_basis(yaw: float, lean: float) -> Basis:
	return Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, -lean)

static func shoulder(body: Dictionary, hand: String, yaw: float, lean: float) -> Vector3:
	var rest: Vector3 = body.shoulder_r if hand == "hand_r" else body.shoulder_l
	var pivot := Vector3(0.0, float(body.pelvis_height), 0.0)
	return pivot + torso_basis(yaw, lean) * (rest - pivot)

## Body-scale: keys are authored for the pilgrim; longer arms reach further.
static func _scaled(c: Vector3, body: Dictionary) -> Vector3:
	var k: float = float(body.arm_length) / 0.56
	return Vector3(c.x * k, float(body.shoulder_height) + (c.y - 1.45), c.z * k)

## Object rotation mapping local frame (a, n) to world (d, r).
static func object_basis(a_local: Vector3, n_local: Vector3, d: Vector3, r: Vector3) -> Basis:
	var a := a_local.normalized()
	var n := (n_local - a * n_local.dot(a)).normalized()
	var dd := d.normalized()
	var rr := r - dd * r.dot(dd)
	if rr.length() < 0.001:
		rr = Vector3.UP - dd * dd.y if absf(dd.y) < 0.95 else Vector3.BACK - dd * dd.z
	rr = rr.normalized()
	var local := Basis(a, n, a.cross(n))
	var world := Basis(dd, rr, dd.cross(rr))
	return world * local.transposed()

## Key poses of an action: [loaded, contact, through] as {c, d, r, yaw, lean}.
static func _keys(action: Dictionary, body: Dictionary) -> Array:
	var arche: Dictionary = ARCHETYPES[action.archetype]
	var two: bool = action.hold.hands.size() == 2
	var mirror: float = -1.0 if action.get("rear", false) else 1.0
	var axis: Variant = arche.axis
	var out: Array = []
	for i in range(3):
		var k: Array = arche.keys[i]
		var c: Vector3 = k[1] if two else k[0]
		c = Vector3(c.x * mirror, c.y, c.z)
		var d: Vector3 = k[2]
		d = Vector3(d.x * mirror, d.y, d.z)
		var yaw: float = float(k[3]) * mirror
		var lean: float = k[4]
		if action.archetype == "shove" and action.hold.get("spread", false):
			d = SHOVE_CROSS
		if action.heavy and i == 0:
			c += HEAVY_LOAD
			yaw *= 1.25
			lean -= 0.05
		var r := Vector3.UP
		if axis != null:
			r = ((axis as Vector3) * mirror).cross(d)
		elif action.archetype == "shove" and action.hold.get("spread", false):
			r = Vector3.FORWARD
		out.append({"c": _scaled(c, body), "d": d, "r": r, "yaw": yaw, "lean": lean})
	return out

## Fitted key pose {basis, c, yaw, lean} for a raw key.
static func _key_pose(hold: Dictionary, a_local: Vector3, n_local: Vector3, k: Dictionary, body: Dictionary) -> Dictionary:
	var fitted := _fit(hold, object_basis(a_local, n_local, k.d, k.r), k.c, k.yaw, k.lean, body)
	return {"basis": (fitted.object as Transform3D).basis, "c": (fitted.object as Transform3D) * (hold.center as Vector3), "yaw": k.yaw, "lean": k.lean}

## Start pose {basis, c, yaw, lean} from a sampled pose dictionary.
static func pose_key(pose: Dictionary, hold: Dictionary) -> Dictionary:
	return {"basis": (pose.object as Transform3D).basis, "c": (pose.object as Transform3D) * (hold.center as Vector3), "yaw": pose.yaw, "lean": pose.lean}

static func _blend(k0: Dictionary, k1: Dictionary, e: float) -> Dictionary:
	var b0: Basis = k0.basis
	var b1: Basis = k1.basis
	var q := b0.get_rotation_quaternion().slerp(b1.get_rotation_quaternion(), e)
	return {"basis": Basis(q), "c": (k0.c as Vector3).lerp(k1.c, e), "yaw": lerpf(k0.yaw, k1.yaw, e), "lean": lerpf(k0.lean, k1.lean, e)}

## Pose for an action at time t (fighter frame). `start` is the pose the action began
## from (pose_key of the previous pose); empty means the hold's ready pose.
static func sample(action: Dictionary, t: float, body: Dictionary, start: Dictionary = {}) -> Dictionary:
	var hold: Dictionary = action.hold
	var ready := pose_key(ready_pose(hold, action.ready_frame, body), hold)
	var first: Dictionary = start if not start.is_empty() else ready
	var raw := _keys(action, body)
	var w: float = action.windup
	var a: float = action.active
	var r: float = action.recovery
	var k0: Dictionary
	var k1: Dictionary
	var e: float
	var phase: String
	if t < w:
		k0 = first
		k1 = _key_pose(hold, action.a_local, action.n_local, raw[0], body)
		e = smooth(t / w)
		phase = "windup"
	elif t < w + a:
		var u := (t - w) / a
		phase = "active"
		var i := 0 if u < 0.5 else 1
		k0 = _key_pose(hold, action.a_local, action.n_local, raw[i], body)
		k1 = _key_pose(hold, action.a_local, action.n_local, raw[i + 1], body)
		e = u * 2.0 - float(i)
	else:
		k0 = _key_pose(hold, action.a_local, action.n_local, raw[2], body)
		k1 = ready
		e = smooth((t - w - a) / r)
		phase = "recovery" if t < w + a + r else "done"
	var k := _blend(k0, k1, e)
	var pose := _fit(hold, k.basis, k.c, k.yaw, k.lean, body)
	var step_total: float = float(ARCHETYPES[action.archetype].step) + (HEAVY_STEP if action.heavy else 0.0)
	pose.phase = phase
	pose.step = step_total * smooth((t - 0.6 * w) / (0.4 * w + a))
	return pose

static func ready_pose(hold: Dictionary, frame: Dictionary, body: Dictionary) -> Dictionary:
	var ready: Array = READY["two_hand" if hold.hands.size() == 2 else "one_hand"]
	var pose := _fit(hold, object_basis(frame.a_local, frame.n_local, ready[1], Vector3.UP), _scaled(ready[0], body), ready[2], ready[3], body)
	pose.phase = "ready"
	return pose

static func guard_pose(guard: Dictionary, body: Dictionary) -> Dictionary:
	var pose := _fit(guard.hold, object_basis(guard.a_local, guard.n_local, guard.d, guard.r), _scaled(guard.c, body), guard.yaw, 0.05, body)
	pose.phase = "guard"
	return pose

## Places the object (rotation `basis`) so the hold centre is at c, then adapts:
## pushes it out of the wielder's torso/head and pulls it toward the shoulders until
## every gripping hand can reach. Reports what could not be resolved.
static func _fit(hold: Dictionary, basis: Basis, c: Vector3, yaw: float, lean: float, body: Dictionary) -> Dictionary:
	var excess := 0.0
	var pen := 0.0
	for i in range(5):
		var shift := Vector3.ZERO
		var push := _penetration(hold, basis, c, yaw, lean, body)
		pen = push.depth
		if pen > 0.0:
			shift += (push.dir as Vector3) * (pen + 0.004)
		excess = 0.0
		var pull := Vector3.ZERO
		for hand: String in hold.hands:
			var target: Vector3 = c + shift + basis * ((hold.grips[hand] as Vector3) - (hold.center as Vector3))
			var s := shoulder(body, hand, yaw, lean)
			var over := s.distance_to(target) - (float(body.arm_length) * 0.97 + WRIST_TO_GRIP)
			if over > 0.0:
				excess = maxf(excess, over)
				pull += (s - target).normalized() * (over + 0.002)
		shift += pull / hold.hands.size()
		if shift == Vector3.ZERO:
			break
		c += shift
	var final := _penetration(hold, basis, c, yaw, lean, body)
	pen = final.depth
	var xf := Transform3D(basis, c - basis * (hold.center as Vector3))
	var hands := {}
	excess = 0.0
	for hand: String in hold.hands:
		hands[hand] = xf * (hold.grips[hand] as Vector3)
		excess = maxf(excess, shoulder(body, hand, yaw, lean).distance_to(hands[hand]) - (float(body.arm_length) * 0.97 + WRIST_TO_GRIP))
	return {"object": xf, "hands": hands, "yaw": yaw, "lean": lean, "phase": "", "step": 0.0, "reach_excess": maxf(0.0, excess),
		"penetration": pen}

## Deepest intrusion of the object's probe points into the torso capsule or head, and
## the horizontal direction that resolves it. Probes within a hand's width of a grip
## are skipped (the arms legitimately bring the grip close to the body).
static func _penetration(hold: Dictionary, basis: Basis, c: Vector3, yaw: float, lean: float, body: Dictionary) -> Dictionary:
	var tb := torso_basis(yaw, lean)
	var pivot := Vector3(0.0, float(body.pelvis_height), 0.0)
	var t0 := pivot + tb * Vector3(0.0, -0.05, 0.0)
	var t1 := pivot + tb * Vector3(0.0, 0.5, 0.0)
	var head := pivot + tb * (HEAD - pivot)
	var center: Vector3 = hold.center
	var worst := 0.0
	var dir := Vector3.FORWARD
	for probe: Array in hold.probes:
		var local: Vector3 = probe[0]
		var near_hand := false
		for hand: String in hold.hands:
			near_hand = near_hand or local.distance_to(hold.grips[hand]) < 0.12
		if near_hand:
			continue
		var w := c + basis * (local - center)
		var radius: float = probe[1]
		var axis_t := clampf((w - t0).dot(t1 - t0) / (t1 - t0).length_squared(), 0.0, 1.0)
		var on_axis := t0.lerp(t1, axis_t)
		var depth := TORSO_RADIUS + radius - w.distance_to(on_axis)
		if depth > worst:
			worst = depth
			dir = _horizontal_away(w - on_axis)
		depth = HEAD_RADIUS + radius - w.distance_to(head)
		if depth > worst:
			worst = depth
			dir = _horizontal_away(w - head)
	return {"depth": worst, "dir": dir}

static func _horizontal_away(v: Vector3) -> Vector3:
	var h := Vector3(v.x, 0.0, v.z)
	return h.normalized() if h.length() > 0.001 else Vector3.FORWARD

## Contact primitive of a feature for an object transform: [segment a, segment b, radius].
static func contact_capsule(feature: Dictionary, xf: Transform3D) -> Array:
	var p: Vector3 = feature.pos
	var h: Vector3 = feature.half_extent
	return [xf * (p - h), xf * (p + h), float(feature.radius)]

## How far the object reaches into the wielder's torso or head in a sampled pose (m).
static func penetration(hold: Dictionary, pose: Dictionary, body: Dictionary) -> float:
	var xf: Transform3D = pose.object
	return _penetration(hold, xf.basis, xf * (hold.center as Vector3), pose.yaw, pose.lean, body).depth

## Samples a whole action: worst reach excess, worst self-penetration, and the
## furthest forward reach of the contact feature during the active window.
static func validate(action: Dictionary, body: Dictionary, start: Dictionary = {}) -> Dictionary:
	var total: float = action.windup + action.active + action.recovery
	var worst_reach := 0.0
	var worst_pen := 0.0
	var reach := 0.0
	var samples := 36
	for i in range(samples + 1):
		var t := total * float(i) / samples
		var pose := sample(action, t, body, start)
		worst_reach = maxf(worst_reach, pose.reach_excess)
		worst_pen = maxf(worst_pen, pose.penetration)
		if pose.phase == "active":
			var cap := contact_capsule(action.feature, pose.object)
			for p: Vector3 in [cap[0], cap[1]]:
				reach = maxf(reach, -p.z + pose.step + float(cap[2]))
	return {"reach_excess": worst_reach, "penetration": worst_pen, "reach": reach,
		"ok": worst_reach <= REACH_LIMIT and worst_pen <= PENETRATION_LIMIT}

## Moves a fraction `e` of the way from one pose toward another (raising a guard,
## settling back to ready, recovering from a stagger), re-fitted to the body.
static func approach(hold: Dictionary, from_pose: Dictionary, to_pose: Dictionary, e: float, body: Dictionary) -> Dictionary:
	var k := _blend(pose_key(from_pose, hold), pose_key(to_pose, hold), clampf(e, 0.0, 1.0))
	var pose := _fit(hold, k.basis, k.c, k.yaw, k.lean, body)
	pose.phase = to_pose.phase
	return pose
