extends RefCounted
## Motion synthesis for the Adaptive Combat Lab (v2): an **authored vocabulary** of
## reusable attack archetypes, fitted procedurally to whatever object, hold and body
## the affordance solver chose, and shaped by the object's measured physics.
##
## Authoring. An archetype is a short list of keys per phase — windup ("w"), active
## ("a"), recovery ("r") — at normalised times u. A key gives, in the fighter frame
## (metres, forward −Z, right +X):
##   c / c1    where the hold centre goes (two-hand / one-hand),
##   d         where the strike axis points (hold centre → active feature),
##   r         optional: where the leading surface faces (else axis × d for swings),
##   yaw lean roll crouch   upper-body turn (+ = right shoulder back), forward lean,
##             side bend and pelvis drop,
##   root      forward travel of the fighter relative to the action start (m),
##   s         grip slide −1..1: the object slides back/forward through the hands,
##             limited to the room the declared grip intervals leave.
## Missing fields inherit from the previous key. Unarmed archetypes key the fists.
##
## Shaping (`build`), from measured quantities only — heft (inertia and mass against
## the body's limits) and head bias (how far toward the striking end the mass sits):
##   coil: heavier objects wind further back and turn the trunk more;
##   overshoot: a swung heavy head carries past the target (momentum);
##   sag: a heavy head drops low early in the recovery before it is lifted back;
##   tempo: heavy windups ease in slowly and accelerate through contact, light ones
##   snap; drag of a broad surface moving face-first slows the action (solver timing);
##   heavy variants coil deeper, step further and commit longer.
## The result is a list of absolute-time keys stored on the action. `sample` only
## interpolates them, then adapts each pose to the body (object pushed out of the
## torso/head, hold pulled into arm reach), so the rules (contact) and presentation
## (drawing, IK) sample one function of (action, t, body, start pose).
##
## Footwork is derived from the keyed root travel: the lead foot arrives early, the
## rear foot follows late, the pelvis carries the root, so feet stay planted while the
## fighter travels (adaptive_pose.gd places them).

const Analysis = preload("res://scripts/adaptive_lab/object_analysis.gd")

const LEFT := Vector3.LEFT
const RIGHT := Vector3.RIGHT

## timing = [windup, active, recovery] s for an unloaded light version (provisional).
## axis: swing rotation axis (null for straight-line motions, "auto" for a diagonal
## computed from the first windup and last active directions). entry/exit tag where
## the striking end starts and finishes (used for combo flow). windows: contact
## windows as fractions of the active phase with the feature they use.
const ARCHETYPES := {
	"thrust": {"timing": [0.22, 0.1, 0.28], "axis": null, "r": Vector3.UP, "entry": "center", "exit": "center",
		"windows": [[0.15, 1.0, "lead"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.24, 1.12, 0.04), "d": Vector3(-0.06, 0.08, -1.0), "yaw": 0.45, "lean": -0.05, "crouch": 0.04, "s": -1.0, "root": -0.02},
		{"ph": "a", "u": 0.5, "c": Vector3(0.2, 1.17, -0.44), "d": Vector3(-0.04, 0.02, -1.0), "yaw": -0.28, "lean": 0.17, "crouch": 0.06, "s": 1.0, "root": 0.3},
		{"ph": "a", "u": 1.0, "c": Vector3(0.19, 1.17, -0.5), "yaw": -0.32, "lean": 0.2, "root": 0.34},
		{"ph": "r", "u": 0.45, "c": Vector3(0.2, 1.12, -0.32), "d": Vector3(-0.1, 0.2, -1.0), "yaw": -0.1, "lean": 0.08, "s": 0.0}]},
	"lunge": {"timing": [0.36, 0.13, 0.42], "axis": null, "r": Vector3.UP, "entry": "center", "exit": "center",
		"windows": [[0.15, 1.0, "lead"]], "keys": [
		{"ph": "w", "u": 0.55, "c": Vector3(0.26, 1.05, 0.12), "d": Vector3(-0.05, 0.1, -1.0), "yaw": 0.6, "lean": -0.12, "crouch": 0.14, "s": -1.0, "root": -0.06},
		{"ph": "w", "u": 1.0, "c": Vector3(0.27, 1.02, 0.16), "yaw": 0.66, "lean": -0.14, "crouch": 0.17},
		{"ph": "a", "u": 0.55, "c": Vector3(0.18, 1.12, -0.55), "d": Vector3(-0.03, 0.0, -1.0), "yaw": -0.36, "lean": 0.32, "crouch": 0.17, "s": 1.0, "root": 0.62},
		{"ph": "a", "u": 1.0, "c": Vector3(0.17, 1.12, -0.62), "yaw": -0.42, "lean": 0.36, "crouch": 0.18, "root": 0.72},
		{"ph": "r", "u": 0.4, "c": Vector3(0.18, 1.1, -0.45), "lean": 0.25, "crouch": 0.14, "s": 0.4}]},
	"sweep": {"timing": [0.26, 0.13, 0.3], "axis": Vector3.UP, "entry": "right", "exit": "left",
		"windows": [[0.1, 0.92, "lead"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.36, 1.2, 0.0), "d": Vector3(1.0, 0.12, 0.35), "yaw": 0.75, "lean": -0.02, "roll": 0.06, "crouch": 0.07, "root": 0.0},
		{"ph": "a", "u": 0.5, "c": Vector3(0.08, 1.12, -0.42), "d": Vector3(-0.15, -0.03, -1.0), "yaw": 0.0, "lean": 0.12, "roll": 0.0, "crouch": 0.08, "root": 0.14},
		{"ph": "a", "u": 1.0, "c": Vector3(-0.22, 1.08, -0.3), "d": Vector3(-1.0, -0.08, -0.25), "yaw": -0.7, "lean": 0.12, "roll": -0.06, "root": 0.16},
		{"ph": "r", "u": 0.35, "c": Vector3(-0.26, 1.04, -0.14), "d": Vector3(-0.8, -0.2, 0.45), "yaw": -0.85, "crouch": 0.1}]},
	"backhand": {"mirror": "sweep", "entry": "left", "exit": "right"},
	"overhead": {"timing": [0.34, 0.13, 0.36], "axis": LEFT, "entry": "high", "exit": "low",
		"windows": [[0.2, 1.0, "lead"]], "keys": [
		{"ph": "w", "u": 0.5, "c": Vector3(0.16, 1.45, -0.05), "d": Vector3(0.05, 0.85, 0.45), "yaw": 0.25, "lean": -0.14, "root": 0.0},
		{"ph": "w", "u": 1.0, "c": Vector3(0.12, 1.58, 0.02), "d": Vector3(0.0, 0.55, 0.85), "yaw": 0.3, "lean": -0.2, "crouch": -0.01},
		{"ph": "a", "u": 0.5, "c": Vector3(0.1, 1.2, -0.46), "d": Vector3(0.0, -0.1, -1.0), "yaw": 0.0, "lean": 0.3, "crouch": 0.1, "root": 0.22},
		{"ph": "a", "u": 1.0, "c": Vector3(0.1, 0.96, -0.42), "d": Vector3(0.0, -0.7, -0.7), "lean": 0.4, "crouch": 0.17, "root": 0.24},
		{"ph": "r", "u": 0.35, "c": Vector3(0.12, 0.88, -0.36), "d": Vector3(0.0, -0.95, -0.3), "lean": 0.42, "crouch": 0.2}]},
	"rising": {"timing": [0.24, 0.12, 0.3], "axis": RIGHT, "entry": "low", "exit": "high",
		"windows": [[0.15, 0.95, "lead"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.26, 0.92, -0.14), "d": Vector3(0.15, -0.85, -0.45), "yaw": 0.35, "lean": 0.25, "crouch": 0.17, "roll": 0.08, "root": 0.0},
		{"ph": "a", "u": 0.5, "c": Vector3(0.12, 1.18, -0.42), "d": Vector3(0.0, 0.12, -1.0), "yaw": 0.0, "lean": 0.05, "crouch": 0.05, "roll": 0.0, "root": 0.12},
		{"ph": "a", "u": 1.0, "c": Vector3(0.05, 1.45, -0.3), "d": Vector3(-0.05, 0.85, -0.5), "yaw": -0.15, "lean": -0.12, "crouch": 0.0, "root": 0.14},
		{"ph": "r", "u": 0.35, "c": Vector3(0.05, 1.48, -0.22), "d": Vector3(0.0, 1.0, -0.1), "lean": -0.14}]},
	"rear": {"timing": [0.2, 0.11, 0.26], "axis": "auto", "entry": "left", "exit": "right", "rear": true,
		"windows": [[0.15, 0.95, "rear"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(-0.05, 1.1, -0.26), "d": Vector3(0.7, -0.55, 0.45), "yaw": -0.45, "lean": 0.05, "crouch": 0.1, "root": 0.02},
		{"ph": "a", "u": 0.5, "c": Vector3(0.05, 1.15, -0.5), "d": Vector3(0.2, -0.05, -1.0), "yaw": 0.1, "lean": 0.16, "crouch": 0.06, "root": 0.16},
		{"ph": "a", "u": 1.0, "c": Vector3(0.12, 1.25, -0.4), "d": Vector3(-0.45, 0.65, -0.6), "yaw": 0.4, "lean": 0.02, "root": 0.18},
		{"ph": "r", "u": 0.35, "c": Vector3(0.12, 1.25, -0.3), "d": Vector3(-0.6, 0.75, -0.2), "yaw": 0.45}]},
	"bash": {"timing": [0.24, 0.14, 0.32], "axis": null, "r": Vector3.UP, "entry": "center", "exit": "center",
		"windows": [[0.2, 1.0, "lead"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.1, 1.22, 0.06), "d": Vector3(0.0, 0.15, -1.0), "yaw": 0.3, "lean": -0.06, "crouch": 0.1, "root": -0.04},
		{"ph": "a", "u": 0.5, "c": Vector3(0.06, 1.25, -0.48), "d": Vector3(0.0, 0.08, -1.0), "yaw": -0.05, "lean": 0.24, "crouch": 0.08, "root": 0.36},
		{"ph": "a", "u": 1.0, "c": Vector3(0.06, 1.25, -0.54), "lean": 0.27, "root": 0.42},
		{"ph": "r", "u": 0.4, "c": Vector3(0.08, 1.22, -0.35), "lean": 0.12}]},
	"hook": {"timing": [0.3, 0.16, 0.3], "axis": null, "r": Vector3(0.0, -1.0, 0.2), "entry": "center", "exit": "center",
		"windows": [[0.0, 0.9, "hook"]], "keys": [
		{"ph": "w", "u": 0.6, "c": Vector3(0.22, 1.32, -0.22), "d": Vector3(0.15, 0.45, -1.0), "yaw": 0.2, "lean": 0.12, "root": 0.15},
		{"ph": "w", "u": 1.0, "c": Vector3(0.2, 1.36, -0.52), "d": Vector3(0.08, 0.22, -1.0), "yaw": 0.05, "lean": 0.24, "root": 0.28},
		{"ph": "a", "u": 0.5, "c": Vector3(0.18, 1.18, -0.3), "d": Vector3(0.0, -0.08, -1.0), "yaw": -0.15, "lean": 0.0, "crouch": 0.05, "root": 0.14},
		{"ph": "a", "u": 1.0, "c": Vector3(0.2, 1.04, 0.0), "d": Vector3(0.1, -0.35, -0.9), "yaw": -0.25, "lean": -0.2, "crouch": 0.12, "root": 0.02},
		{"ph": "r", "u": 0.4, "c": Vector3(0.2, 1.06, -0.1), "lean": -0.1}]},
	"windmill": {"timing": [0.26, 0.36, 0.34], "axis": LEFT, "entry": "high", "exit": "high", "heavy_only": true,
		"windows": [[0.1, 0.38, "lead"], [0.72, 0.98, "rear"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.12, 1.22, -0.18), "d": Vector3(0.08, 0.75, 0.65), "yaw": 0.3, "lean": -0.08, "root": 0.0},
		{"ph": "a", "u": 0.25, "c": Vector3(0.08, 1.18, -0.4), "d": Vector3(0.04, -0.05, -1.0), "yaw": 0.0, "lean": 0.18, "root": 0.18},
		{"ph": "a", "u": 0.45, "c": Vector3(0.04, 1.12, -0.32), "d": Vector3(0.0, -0.95, -0.3), "yaw": -0.2, "lean": 0.12, "root": 0.22},
		{"ph": "a", "u": 0.65, "c": Vector3(0.02, 1.16, -0.3), "d": Vector3(-0.04, -0.55, 0.85), "yaw": -0.05, "lean": 0.05, "root": 0.24},
		{"ph": "a", "u": 0.85, "c": Vector3(0.06, 1.22, -0.38), "d": Vector3(-0.04, 0.05, 1.0), "yaw": 0.15, "lean": 0.15, "root": 0.32},
		{"ph": "a", "u": 1.0, "c": Vector3(0.08, 1.26, -0.34), "d": Vector3(-0.04, 0.5, 0.85), "yaw": 0.2, "root": 0.34},
		{"ph": "r", "u": 0.5, "c": Vector3(0.12, 1.15, -0.3), "d": Vector3(0.0, 0.9, 0.3), "yaw": 0.1, "lean": 0.0}]},
	"shove": {"timing": [0.16, 0.1, 0.26], "axis": null, "r": Vector3.FORWARD, "entry": "center", "exit": "center", "cross": true,
		"windows": [[0.0, 1.0, "lead"]], "keys": [
		{"ph": "w", "u": 1.0, "c": Vector3(0.06, 1.14, -0.28), "d": Vector3(1.0, 0.12, -0.05), "yaw": 0.15, "lean": -0.05, "crouch": 0.06, "root": -0.03},
		{"ph": "a", "u": 0.5, "c": Vector3(0.04, 1.18, -0.55), "lean": 0.2, "root": 0.3},
		{"ph": "a", "u": 1.0, "c": Vector3(0.04, 1.18, -0.6), "lean": 0.22, "root": 0.34},
		{"ph": "r", "u": 0.4, "c": Vector3(0.06, 1.14, -0.4), "lean": 0.1}]},
	# Unarmed: fists (fl / fr) or the left shoulder strike; no object.
	"jab": {"timing": [0.12, 0.08, 0.2], "unarmed": true, "limb": "hand_l", "entry": "center", "exit": "center",
		"windows": [[0.2, 1.0, "fist"]], "keys": [
		{"ph": "w", "u": 1.0, "fl": Vector3(-0.12, 1.4, -0.2), "fr": Vector3(0.16, 1.42, -0.15), "yaw": -0.12, "root": 0.0},
		{"ph": "a", "u": 0.5, "fl": Vector3(-0.06, 1.42, -0.58), "yaw": 0.25, "lean": 0.1, "root": 0.15},
		{"ph": "a", "u": 1.0, "fl": Vector3(-0.06, 1.42, -0.62), "root": 0.17}]},
	"cross": {"timing": [0.16, 0.08, 0.24], "unarmed": true, "limb": "hand_r", "entry": "center", "exit": "center",
		"windows": [[0.2, 1.0, "fist"]], "keys": [
		{"ph": "w", "u": 1.0, "fr": Vector3(0.2, 1.38, -0.05), "fl": Vector3(-0.14, 1.42, -0.22), "yaw": 0.4, "root": 0.0},
		{"ph": "a", "u": 0.5, "fr": Vector3(0.02, 1.42, -0.6), "yaw": -0.45, "lean": 0.15, "root": 0.2},
		{"ph": "a", "u": 1.0, "fr": Vector3(0.0, 1.42, -0.64), "root": 0.22}]},
	"barge": {"timing": [0.3, 0.14, 0.38], "unarmed": true, "limb": "shoulder_l", "entry": "center", "exit": "center",
		"windows": [[0.15, 1.0, "fist"]], "keys": [
		{"ph": "w", "u": 1.0, "fl": Vector3(-0.08, 1.3, -0.12), "fr": Vector3(0.12, 1.32, -0.1), "yaw": 0.55, "lean": -0.05, "crouch": 0.12, "root": -0.05},
		{"ph": "a", "u": 0.5, "yaw": -0.85, "lean": 0.3, "crouch": 0.1, "root": 0.6},
		{"ph": "a", "u": 1.0, "yaw": -0.9, "lean": 0.32, "root": 0.7},
		{"ph": "r", "u": 0.4, "yaw": -0.4, "lean": 0.15}]},
}
## Ready poses per hold kind: [c, d, yaw, lean].
const READY := {"one_hand": [Vector3(0.26, 1.02, -0.32), Vector3(0.0, 0.4, -1.0), 0.0, 0.0],
	"two_hand": [Vector3(0.16, 1.06, -0.3), Vector3(-0.2, 0.45, -1.0), 0.1, 0.0]}
const FISTS_READY := {"fl": Vector3(-0.14, 1.35, -0.25), "fr": Vector3(0.16, 1.33, -0.2)}
const FISTS_GUARD := {"fl": Vector3(-0.08, 1.5, -0.24), "fr": Vector3(0.1, 1.5, -0.22)}
## One-hand hold centre relative to the two-hand key (the hand sits further out).
const ONE_HAND_OFFSET := Vector3(0.08, 0.03, -0.05)
const TORSO_RADIUS := 0.15
const HEAD := Vector3(0.0, 1.66, -0.02)
const HEAD_RADIUS := 0.11
const PENETRATION_LIMIT := 0.035
const REACH_LIMIT := 0.015
## Wrist → grip-centre distance (the showcase rig's grip socket offset).
const WRIST_TO_GRIP := 0.075
## Footwork: the lead foot runs ahead of the root, the rear foot behind it (s).
const LEAD_FOOT_AHEAD := 0.12
const REAR_FOOT_BEHIND := 0.2
const MAX_STRIDE := 0.3
const STANCE := {"l": Vector3(-0.13, 0.0, -0.17), "r": Vector3(0.15, 0.0, 0.15)}

static func smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static var _mirrored: Dictionary = {}

static func archetype(name: String) -> Dictionary:
	var a: Dictionary = ARCHETYPES[name]
	if a.has("mirror"):
		if _mirrored.has(name):
			return _mirrored[name]
		var base: Dictionary = ARCHETYPES[a.mirror].duplicate(true)
		base.axis = -(base.axis as Vector3)
		base.entry = a.entry
		base.exit = a.exit
		var keys: Array = []
		for k: Dictionary in base.keys:
			var m := k.duplicate()
			for field: String in ["c", "d"]:
				if m.has(field):
					m[field] = Vector3(-(m[field] as Vector3).x, (m[field] as Vector3).y, (m[field] as Vector3).z)
			for field: String in ["yaw", "roll"]:
				if m.has(field):
					m[field] = -float(m[field])
			# A backhand starts from across the body: hands sit left of centre.
			if m.has("c") and k.ph == "w":
				m.c = (m.c as Vector3) + Vector3(0.06, 0.0, -0.04)
			keys.append(m)
		base.keys = keys
		_mirrored[name] = base
		return base
	return a

## Torso rotation about the pelvis (fighter frame).
static func torso_basis(yaw: float, lean: float, roll := 0.0) -> Basis:
	return Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, -lean) * Basis(Vector3.FORWARD, roll)

static func pivot_of(body: Dictionary, crouch: float) -> Vector3:
	return Vector3(0.0, float(body.pelvis_height) - crouch, 0.0)

static func shoulder(body: Dictionary, hand: String, yaw: float, lean: float, roll := 0.0, crouch := 0.0) -> Vector3:
	var rest: Vector3 = body.shoulder_r if hand == "hand_r" else body.shoulder_l
	var rest_pivot := Vector3(0.0, float(body.pelvis_height), 0.0)
	return pivot_of(body, crouch) + torso_basis(yaw, lean, roll) * (rest - rest_pivot)

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

# --- Building shaped keys ------------------------------------------------------------

## Builds the action's absolute-time keys from its archetype, hold, physics shape and
## the body. Stored on the action as `keys`; `sample` interpolates them.
static func build(action: Dictionary, body: Dictionary) -> Array:
	var arche := archetype(action.archetype)
	var w: float = action.windup
	var a: float = action.active
	var r: float = action.recovery
	var heavy: bool = action.heavy
	var heft: float = action.get("heft", 0.0)
	var head: float = action.get("head", 0.0)
	var axis: Variant = arche.get("axis")
	var raw: Array = []
	var prev := {"yaw": 0.0, "lean": 0.0, "roll": 0.0, "crouch": 0.0, "root": 0.0, "s": 0.0}
	for k: Dictionary in arche.keys:
		var m := prev.duplicate()
		m.merge(k, true)
		prev = m
		raw.append(m)
	if axis is String:
		var first: Vector3 = (raw[0].d as Vector3).normalized()
		var last: Vector3 = Vector3.ZERO
		for k: Dictionary in raw:
			if k.ph == "a":
				last = (k.d as Vector3).normalized()
		axis = first.cross(last).normalized()
	var unarmed: bool = arche.get("unarmed", false)
	var coil := 1.0 + 0.5 * heft + (0.3 if heavy else 0.0)
	var overshoot := 0.08 + 0.75 * heft * (0.4 + head) + (0.2 if heavy else 0.0)
	var sag := 0.55 * head * heft
	var out: Array = []
	var phase_len := {"w": w, "a": a, "r": r}
	var phase_start := {"w": 0.0, "a": w, "r": w + a}
	for k: Dictionary in raw:
		var key := k.duplicate()
		key.t = float(phase_start[k.ph]) + float(phase_len[k.ph]) * float(k.u)
		if not unarmed:
			var d: Vector3 = (key.d as Vector3).normalized()
			if k.ph == "w":
				key.yaw = float(key.yaw) * coil
				key.lean = float(key.lean) - (0.05 if heavy else 0.0)
				key.crouch = float(key.crouch) + (0.05 if heavy else 0.0) + 0.04 * heft
				if heavy:
					key.c = (key.c as Vector3) + Vector3(0.0, 0.05, 0.08)
				if axis != null:
					# Wind further back about the swing axis.
					d = d.rotated(axis, -(0.12 * heft + (0.22 if heavy else 0.0)))
			elif k.ph == "a" and float(k.u) >= 0.99 and axis != null and arche.windows.size() == 1:
				d = d.rotated(axis, overshoot * 0.5)
			elif k.ph == "r" and axis != null and arche.windows.size() == 1:
				d = d.rotated(axis, overshoot)
				key.yaw = float(key.yaw) * (1.0 + 0.4 * heft)
			if k.ph == "r":
				# A heavy head sags: tip the strike axis toward the ground.
				var down := Vector3.DOWN - d * Vector3.DOWN.dot(d)
				if down.length() > 0.01 and sag > 0.0:
					d = d.slerp(down.normalized(), clampf(sag, 0.0, 0.8) * 0.6).normalized()
				key.crouch = float(key.crouch) + 0.06 * heft
			key.d = d
			if key.has("r"):
				key.rr = key.r
			elif axis != null:
				key.rr = (axis as Vector3).cross(d)
			else:
				key.rr = arche.get("r", Vector3.UP)
		if heavy and k.ph != "w":
			key.root = float(key.root) * 1.45 + (0.12 if k.ph == "a" else 0.12)
		out.append(key)
	return out

## The active-phase contact windows with absolute times and their feature roles.
static func windows(action: Dictionary) -> Array:
	if action.has("windows_abs"):
		return action.windows_abs
	var arche := archetype(action.archetype)
	var out: Array = []
	for wnd: Array in arche.windows:
		out.append({"t0": float(action.windup) + float(action.active) * float(wnd[0]),
			"t1": float(action.windup) + float(action.active) * float(wnd[1]), "role": wnd[2]})
	return out

## Root travel at time t, from the keys (0 at start, last keyed value through the end).
static func root_at(keys: Array, t: float) -> float:
	var prev_t := 0.0
	var prev_v := 0.0
	for k: Dictionary in keys:
		if t < float(k.t):
			return lerpf(prev_v, float(k.root), smooth((t - prev_t) / maxf(float(k.t) - prev_t, 0.0001)))
		prev_t = k.t
		prev_v = k.root
	return prev_v

## Fighter travel at time t: keyed root plus the rules' spacing adjustment `extra`,
## which ramps in over the late windup and early active phase and then holds.
static func travel(action: Dictionary, t: float, extra: float) -> float:
	var w: float = action.windup
	var a: float = action.active
	var ramp := smooth((t - 0.3 * w) / maxf(0.7 * w + 0.5 * a, 0.001))
	return root_at(action.keys, t) + extra * ramp

## Foot targets (fighter frame, relative to the travelling root) for an action at t.
## The foot on the side of travel leads it, the other trails, so feet stay planted
## while the body moves and step in turn. Lift grows with the foot's speed.
static func feet(action: Dictionary, t: float, extra: float) -> Dictionary:
	var total: float = float(action.windup) + float(action.active) + float(action.recovery)
	var now := travel(action, t, extra)
	var forward := travel(action, total, extra) >= 0.0
	var out := {}
	for side: String in ["l", "r"]:
		# The left foot is the lead foot of the stance.
		var leads := (side == "l") == forward
		var disp := _foot_disp(action, t, extra, leads, total)
		var speed := absf(_foot_disp(action, t + 0.04, extra, leads, total) - disp) / 0.04
		var base: Vector3 = STANCE[side]
		# A stride never opens wider than a lunge the legs can reach.
		out[side] = base + Vector3(0.0, clampf(speed * 0.035, 0.0, 0.09), -clampf(disp - now, -MAX_STRIDE, MAX_STRIDE))
	return out

static func _foot_disp(action: Dictionary, t: float, extra: float, leads: bool, total: float) -> float:
	return travel(action, minf(total, t + LEAD_FOOT_AHEAD), extra) if leads else travel(action, maxf(0.0, t - REAR_FOOT_BEHIND), extra)

# --- Sampling ------------------------------------------------------------------------

## Fitted key pose {basis, c, yaw, lean, roll, crouch, s} of a built key.
static func _key_pose(action: Dictionary, k: Dictionary, body: Dictionary) -> Dictionary:
	var hold: Dictionary = action.hold
	var c: Vector3 = k.c
	if hold.hands.size() == 1:
		c = (k.c1 as Vector3) if k.has("c1") else c + ONE_HAND_OFFSET
	var basis := object_basis(action.a_local, action.n_local, k.d, k.rr)
	return {"basis": basis, "c": _scaled(c, body), "yaw": k.yaw, "lean": k.lean, "roll": k.roll, "crouch": k.crouch,
		"s": clampf(float(k.s), -1.0, 1.0)}

static func pose_key(pose: Dictionary, hold: Dictionary) -> Dictionary:
	var xf: Transform3D = pose.object
	var s: float = pose.get("slide", 0.0)
	return {"basis": xf.basis, "c": xf * slid_center(hold, s), "yaw": pose.yaw, "lean": pose.lean, "roll": pose.get("roll", 0.0),
		"crouch": pose.get("crouch", 0.0), "s": s}

static func _blend(k0: Dictionary, k1: Dictionary, e: float) -> Dictionary:
	var q := (k0.basis as Basis).get_rotation_quaternion().slerp((k1.basis as Basis).get_rotation_quaternion(), e)
	return {"basis": Basis(q), "c": (k0.c as Vector3).lerp(k1.c, e), "yaw": lerpf(k0.yaw, k1.yaw, e), "lean": lerpf(k0.lean, k1.lean, e),
		"roll": lerpf(k0.roll, k1.roll, e), "crouch": lerpf(k0.crouch, k1.crouch, e), "s": lerpf(k0.s, k1.s, e)}

## Phase easing shaped by heft: heavy windups ease slowly, heavy actives accelerate.
static func _ease(phase: String, e: float, heft: float) -> float:
	e = clampf(e, 0.0, 1.0)
	match phase:
		"w":
			var snap := 1.0 - pow(1.0 - e, 2.0)
			return lerpf(snap, smooth(e), clampf(heft * 1.4, 0.0, 1.0))
		"a":
			return pow(e, 1.0 + 0.5 * heft)
	return lerpf(1.0 - pow(1.0 - e, 2.0), smooth(e), clampf(heft, 0.0, 1.0))

static func phase_at(action: Dictionary, t: float) -> String:
	var w: float = action.windup
	var a: float = action.active
	if t < w:
		return "windup"
	if t < w + a:
		return "active"
	return "recovery" if t < w + a + float(action.recovery) else "done"

## Pose for an action at time t (fighter frame, before root travel). `start` is the
## pose_key the action began from; empty means the hold's ready pose.
static func sample(action: Dictionary, t: float, body: Dictionary, start: Dictionary = {}) -> Dictionary:
	if action.get("unarmed", false):
		return _sample_unarmed(action, t, body, start)
	var hold: Dictionary = action.hold
	var keys: Array = action.keys
	var total: float = float(action.windup) + float(action.active) + float(action.recovery)
	var ready: Dictionary = action.ready_key if action.has("ready_key") else pose_key(ready_pose(hold, action.ready_frame, body), hold)
	var prev: Dictionary = start if not start.is_empty() else ready
	var prev_t := 0.0
	var k: Dictionary = {}
	var found := false
	for key: Dictionary in keys:
		if t < float(key.t):
			var k1 := _key_pose(action, key, body)
			var e := _ease(key.ph, (t - prev_t) / maxf(float(key.t) - prev_t, 0.0001), float(action.get("heft", 0.0)))
			k = _blend(prev, k1, e)
			found = true
			break
		prev = _key_pose(action, key, body)
		prev_t = key.t
	if not found:
		k = _blend(prev, ready, _ease("r", (t - prev_t) / maxf(total - prev_t, 0.0001), float(action.get("heft", 0.0))))
	var pose := _fit(hold, k.basis, k.c, k.yaw, k.lean, k.roll, k.crouch, k.s, body)
	pose.phase = phase_at(action, t)
	pose.root = root_at(keys, t)
	pose.window = window_index(action, t)
	return pose

static func window_index(action: Dictionary, t: float) -> int:
	if action.has("windows_abs"):
		var cached: Array = action.windows_abs
		for i in range(cached.size()):
			if t >= float(cached[i].t0) and t <= float(cached[i].t1):
				return i
		return -1
	var list := windows(action)
	for i in range(list.size()):
		if t >= float(list[i].t0) and t <= float(list[i].t1):
			return i
	return -1

static func ready_pose(hold: Dictionary, frame: Dictionary, body: Dictionary) -> Dictionary:
	if hold.get("unarmed", false):
		return _fists_pose(FISTS_READY, 0.0, 0.0, 0.0, body, "ready")
	var ready: Array = READY["two_hand" if hold.hands.size() == 2 else "one_hand"]
	var pose := _fit(hold, object_basis(frame.a_local, frame.n_local, ready[1], Vector3.UP), _scaled(ready[0], body), ready[2], ready[3],
		0.0, 0.02, 0.0, body)
	pose.phase = "ready"
	return pose

static func guard_pose(guard: Dictionary, body: Dictionary) -> Dictionary:
	if guard.hold.get("unarmed", false):
		return _fists_pose(FISTS_GUARD, 0.05, 0.05, 0.0, body, "guard")
	var pose := _fit(guard.hold, object_basis(guard.a_local, guard.n_local, guard.d, guard.r), _scaled(guard.c, body), guard.yaw, 0.05,
		0.0, 0.04, 0.0, body)
	pose.phase = "guard"
	return pose

## Slide offset along the hold axis for slide value s (object moves through the hands).
static func slide_offset(hold: Dictionary, s: float) -> float:
	var room: Vector2 = hold.get("slide_room", Vector2.ZERO)
	return s * (room.y if s > 0.0 else room.x)

## Object-local point that sits at the hold centre's world placement for slide s.
static func slid_center(hold: Dictionary, s: float) -> Vector3:
	return (hold.center as Vector3) - (hold.axis as Vector3) * slide_offset(hold, s)

## Object-local grip point of a hand for slide s (inside its declared interval).
static func slid_grip(hold: Dictionary, hand: String, s: float) -> Vector3:
	return (hold.grips[hand] as Vector3) - (hold.axis as Vector3) * slide_offset(hold, s)

## Places the object (rotation `basis`) so the slid hold centre is at c, then adapts:
## pushes it out of the wielder's torso/head and pulls it toward the shoulders until
## every gripping hand can reach. Reports what could not be resolved.
static func _fit(hold: Dictionary, basis: Basis, c: Vector3, yaw: float, lean: float, roll: float, crouch: float, s: float,
		body: Dictionary) -> Dictionary:
	var excess := 0.0
	var pen := 0.0
	var center := slid_center(hold, s)
	for i in range(8):
		var shift := Vector3.ZERO
		var push := _penetration(hold, basis, center, c, yaw, lean, roll, crouch, body)
		pen = push.depth
		if pen > 0.0:
			shift += (push.dir as Vector3) * (pen + 0.004)
		excess = 0.0
		var pull := Vector3.ZERO
		for hand: String in hold.hands:
			var target: Vector3 = c + shift + basis * (slid_grip(hold, hand, s) - center)
			var sh := shoulder(body, hand, yaw, lean, roll, crouch)
			var over := sh.distance_to(target) - (float(body.arm_length) * 0.97 + WRIST_TO_GRIP)
			if over > 0.0:
				excess = maxf(excess, over)
				pull += (sh - target).normalized() * (over + 0.002)
		shift += pull / maxi(1, hold.hands.size())
		if shift == Vector3.ZERO:
			break
		c += shift
	pen = _penetration(hold, basis, center, c, yaw, lean, roll, crouch, body).depth
	var xf := Transform3D(basis, c - basis * center)
	var hands := {}
	excess = 0.0
	for hand: String in hold.hands:
		hands[hand] = xf * slid_grip(hold, hand, s)
		excess = maxf(excess, shoulder(body, hand, yaw, lean, roll, crouch).distance_to(hands[hand]) - (float(body.arm_length) * 0.97 + WRIST_TO_GRIP))
	return {"object": xf, "hands": hands, "yaw": yaw, "lean": lean, "roll": roll, "crouch": crouch, "slide": s, "phase": "", "root": 0.0,
		"window": -1, "reach_excess": maxf(0.0, excess), "penetration": pen}

## Deepest intrusion of the object's probe points into the torso capsule or head, and
## the horizontal direction that resolves it. Probes within a hand's width of a grip
## are skipped (the arms legitimately bring the grip close to the body).
static func _penetration(hold: Dictionary, basis: Basis, center: Vector3, c: Vector3, yaw: float, lean: float, roll: float, crouch: float,
		body: Dictionary) -> Dictionary:
	var tb := torso_basis(yaw, lean, roll)
	var pivot := pivot_of(body, crouch)
	var rest_pivot := Vector3(0.0, float(body.pelvis_height), 0.0)
	var t0 := pivot + tb * Vector3(0.0, -0.05, 0.0)
	var t1 := pivot + tb * Vector3(0.0, 0.5, 0.0)
	var head := pivot + tb * (HEAD - rest_pivot)
	var worst := 0.0
	var dir := Vector3.FORWARD
	for probe: Array in hold.probes:
		var local: Vector3 = probe[0]
		var near_hand := false
		for hand: String in hold.hands:
			near_hand = near_hand or local.distance_to(hold.grips[hand]) < 0.14
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

# --- Unarmed -------------------------------------------------------------------------

static func _fists_pose(fists: Dictionary, yaw: float, lean: float, crouch: float, body: Dictionary, phase: String) -> Dictionary:
	var hands := {}
	for hand: String in body.hands:
		hands[hand] = _scaled(fists["fr" if hand == "hand_r" else "fl"], body)
	return {"object": Transform3D(Basis.IDENTITY, hands.get("hand_r", Vector3.ZERO)), "hands": hands, "yaw": yaw, "lean": lean, "roll": 0.0,
		"crouch": crouch, "slide": 0.0, "phase": phase, "root": 0.0, "window": -1, "reach_excess": 0.0, "penetration": 0.0, "fists": true}

static func _unarmed_key(k: Dictionary, prev: Dictionary) -> Dictionary:
	var out := prev.duplicate()
	for f: String in ["fl", "fr", "yaw", "lean", "roll", "crouch"]:
		if k.has(f):
			out[f] = k[f]
	return out

static func _sample_unarmed(action: Dictionary, t: float, body: Dictionary, start: Dictionary) -> Dictionary:
	var keys: Array = action.keys
	var total: float = float(action.windup) + float(action.active) + float(action.recovery)
	var ready := {"fl": FISTS_READY.fl, "fr": FISTS_READY.fr, "yaw": 0.0, "lean": 0.0, "roll": 0.0, "crouch": 0.02}
	var prev: Dictionary = ready
	var prev_t := 0.0
	var a: Dictionary = {}
	var found := false
	for key: Dictionary in keys:
		var full := _unarmed_key(key, prev)
		if t < float(key.t):
			var e := smooth((t - prev_t) / maxf(float(key.t) - prev_t, 0.0001))
			a = _lerp_fists(prev, full, e)
			found = true
			break
		prev = full
		prev_t = key.t
	if not found:
		a = _lerp_fists(prev, ready, smooth((t - prev_t) / maxf(total - prev_t, 0.0001)))
	var pose := _fists_pose({"fl": a.fl, "fr": a.fr}, a.yaw, a.lean, a.crouch, body, phase_at(action, t))
	pose.roll = a.roll
	var limb: String = archetype(action.archetype).limb
	var strike: Vector3
	if limb == "shoulder_l":
		strike = shoulder(body, "hand_l", a.yaw, a.lean, a.roll, a.crouch) + Vector3(0.0, -0.05, 0.0)
	else:
		strike = pose.hands.get(limb, Vector3.ZERO)
	pose.object = Transform3D(Basis.IDENTITY, strike)
	pose.root = root_at(keys, t)
	pose.window = window_index(action, t)
	return pose

static func _lerp_fists(a: Dictionary, b: Dictionary, e: float) -> Dictionary:
	var out := {}
	for f: String in ["fl", "fr"]:
		out[f] = (a[f] as Vector3).lerp(b[f], e)
	for f: String in ["yaw", "lean", "roll", "crouch"]:
		out[f] = lerpf(float(a[f]), float(b[f]), e)
	return out

## Unarmed key list (absolute times) — no physics shaping, no object.
static func build_unarmed(action: Dictionary) -> Array:
	var arche := archetype(action.archetype)
	var phase_len := {"w": float(action.windup), "a": float(action.active), "r": float(action.recovery)}
	var phase_start := {"w": 0.0, "a": float(action.windup), "r": float(action.windup) + float(action.active)}
	var out: Array = []
	var root := 0.0
	for k: Dictionary in arche.keys:
		var key := k.duplicate()
		key.t = float(phase_start[k.ph]) + float(phase_len[k.ph]) * float(k.u)
		root = float(k.get("root", root))
		key.root = root
		out.append(key)
	return out

# --- Contact, validation ------------------------------------------------------------

## Contact primitive of a feature for an object transform: [segment a, segment b, radius].
static func contact_capsule(feature: Dictionary, xf: Transform3D) -> Array:
	var p: Vector3 = feature.pos
	var h: Vector3 = feature.half_extent
	return [xf * (p - h), xf * (p + h), float(feature.radius)]

## The feature active in window i of an action.
static func window_feature(action: Dictionary, i: int) -> Dictionary:
	var role: String = archetype(action.archetype).windows[i][2]
	if role == "rear" and action.has("rear_feature"):
		return action.rear_feature
	return action.feature

## How far the object reaches into the wielder's torso or head in a sampled pose (m).
static func penetration(hold: Dictionary, pose: Dictionary, body: Dictionary) -> float:
	var xf: Transform3D = pose.object
	var center := slid_center(hold, pose.get("slide", 0.0))
	return _penetration(hold, xf.basis, center, xf * center, pose.yaw, pose.lean, pose.get("roll", 0.0), pose.get("crouch", 0.0), body).depth

## Samples a whole action: worst reach excess, worst self-penetration, grip slide kept
## inside the intervals, and the furthest forward reach of the contact feature during
## the contact windows without root travel (`reach`) and with it (`reach_root`).
static func validate(action: Dictionary, body: Dictionary, start: Dictionary = {}) -> Dictionary:
	var total: float = float(action.windup) + float(action.active) + float(action.recovery)
	var worst_reach := 0.0
	var worst_pen := 0.0
	var reach := 0.0
	var reach_root := 0.0
	var low := INF
	var high := -INF
	var per_window: Array = []
	for _w: Variant in windows(action):
		per_window.append(0.0)
	var samples := 30
	for i in range(samples + 1):
		var t := total * float(i) / samples
		var pose := sample(action, t, body, start)
		worst_reach = maxf(worst_reach, pose.reach_excess)
		worst_pen = maxf(worst_pen, pose.penetration)
		if int(pose.window) >= 0:
			var cap := contact_capsule(window_feature(action, pose.window), pose.object)
			for p: Vector3 in [cap[0], cap[1]]:
				reach = maxf(reach, -p.z + float(cap[2]))
				per_window[pose.window] = maxf(float(per_window[pose.window]), snappedf(-p.z + float(cap[2]), 0.001))
				reach_root = maxf(reach_root, -p.z + float(pose.root) + float(cap[2]))
				low = minf(low, p.y)
				high = maxf(high, p.y)
	return {"reach_excess": worst_reach, "penetration": worst_pen, "reach": reach, "reach_root": reach_root, "reach_windows": per_window,
		"contact_low": low, "contact_high": high,
		"ok": worst_reach <= REACH_LIMIT and worst_pen <= PENETRATION_LIMIT}

## Moves a fraction `e` of the way from one pose toward another (raising a guard,
## settling back to ready, recovering from a stagger), re-fitted to the body.
static func approach(hold: Dictionary, from_pose: Dictionary, to_pose: Dictionary, e: float, body: Dictionary) -> Dictionary:
	if hold.get("unarmed", false) or from_pose.get("fists", false):
		var out := to_pose.duplicate()
		var hands := {}
		for hand: String in to_pose.hands:
			hands[hand] = (from_pose.hands.get(hand, to_pose.hands[hand]) as Vector3).lerp(to_pose.hands[hand], clampf(e, 0.0, 1.0))
		out.hands = hands
		out.yaw = lerpf(from_pose.yaw, to_pose.yaw, e)
		out.lean = lerpf(from_pose.lean, to_pose.lean, e)
		out.crouch = lerpf(from_pose.get("crouch", 0.0), to_pose.get("crouch", 0.0), e)
		out.roll = lerpf(from_pose.get("roll", 0.0), to_pose.get("roll", 0.0), e)
		return out
	var k := _blend(pose_key(from_pose, hold), pose_key(to_pose, hold), clampf(e, 0.0, 1.0))
	var pose := _fit(hold, k.basis, k.c, k.yaw, k.lean, k.roll, k.crouch, k.s, body)
	pose.phase = to_pose.phase
	return pose
