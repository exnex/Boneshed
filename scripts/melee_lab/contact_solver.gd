extends RefCounted
## Swept-segment weapon contact and outcome classification for the lab. Pure and
## deterministic: no physics server, no frame-rate dependence beyond the tick size.
##
## Each tick the attacker's blade moves from its previous pose to its current pose
## (a great-circle slerp, exact for swings). The sweep is split into substeps so the
## blade tip advances at most `contact_spacing` metres per substep; since that is less
## than blade + guard radius, a thin guard cannot be tunnelled through. At each substep
## the blade segment is tested against (1) the defender's weapon when it is guarding or
## swinging and (2) the defender's body capsule. The first substep with contact decides;
## if both touch in the same substep the weapon wins (fixed, defender-favouring tie rule).
##
## Outcomes:  deflect · block · misaligned · guard_break · clash · hit · evaded · none

const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const State = preload("res://scripts/melee_lab/duelist_state.gd")
const MAX_SUBSTEPS := 96
const NONE := "none"
const HIT := "hit"
const BLOCK := "block"
const DEFLECT := "deflect"
const MISALIGNED := "misaligned"
const GUARD_BREAK := "guard_break"
const CLASH := "clash"
const EVADED := "evaded"
const OUTCOMES := [HIT, BLOCK, DEFLECT, MISALIGNED, GUARD_BREAK, CLASH, EVADED]

## `prev`/`now` transforms are each fighter's global transform at the start and end of
## the tick. `substeps` false is the negative control (end pose only).
static func resolve(att: State, att_prev: Transform3D, att_now: Transform3D,
		def: State, def_prev: Transform3D, def_now: Transform3D, substeps := true) -> Dictionary:
	if not att.sweep_open or att.hit_consumed or def.phase == State.Phase.DEAD:
		return {"result": NONE}
	var t := att.t
	var tip_from := att_prev * Geometry.tip(att.pose_at(0.0), att.h.length)
	var tip_to := att_now * Geometry.tip(att.pose_at(1.0), att.h.length)
	var count := mini(MAX_SUBSTEPS, maxi(1, ceili(tip_from.distance_to(tip_to) / t.contact_spacing))) if substeps else 1
	var weapon_obstacle := def.guarding or def.is_live()
	var previous_point := Vector3.INF
	for i in range(1, count + 1):
		var w := float(i) / float(count)
		if not att.live_at(w):
			continue
		var att_xf := att_prev.interpolate_with(att_now, w)
		var def_xf := def_prev.interpolate_with(def_now, w)
		var pose := att.pose_at(w)
		var a0: Vector3 = att_xf * pose.hand
		var a1: Vector3 = att_xf * Geometry.tip(pose, att.h.length)
		var weapon_touch := {}
		if weapon_obstacle and def.phase != State.Phase.DODGE:
			var dpose := def.pose_at(w)
			var close := closest_points(a0, a1, def_xf * dpose.hand, def_xf * Geometry.tip(dpose, def.h.length))
			if close.distance <= t.blade_radius + t.guard_radius:
				weapon_touch = close
		var body := closest_points(a0, a1, def_xf * Vector3(0.0, t.body_bottom, 0.0), def_xf * Vector3(0.0, t.body_top, 0.0))
		var body_touch: bool = body.distance <= t.blade_radius + t.body_radius
		if weapon_touch.is_empty() and not body_touch:
			continue
		# Velocity of the touching point on the blade, from the previous substep.
		var contact: Dictionary = weapon_touch if not weapon_touch.is_empty() else body
		var w0 := float(i - 1) / float(count)
		var pose0 := att.pose_at(w0)
		var xf0 := att_prev.interpolate_with(att_now, w0)
		var along: float = contact.s
		previous_point = (xf0 * pose0.hand).lerp(xf0 * Geometry.tip(pose0, att.h.length), along)
		var velocity: Vector3 = contact.point_a - previous_point
		var arrival := arrival_vector(att.direction, velocity, def_xf)
		if not weapon_touch.is_empty():
			# The blade stops where it met the weapon, so the drawn pose matches the contact.
			att.snap_pose(pose)
			if def.is_live():
				def.snap_pose(def.pose_at(w))
			return _weapon_contact(att, def, weapon_touch.point_b, arrival, i, count)
		return _body_contact(att, def, body.point_a, arrival, i, count)
	return {"result": NONE, "substeps": count}

## Side the attack comes from, in the defender's cursor space (x right, y up). Swings:
## opposite of the contact point's frontal velocity. Thrusts: centre.
static func arrival_vector(direction: String, velocity: Vector3, def_xf: Transform3D) -> Vector2:
	if direction == Geometry.THRUST:
		return Vector2(0.0, -1.0)
	var local := def_xf.basis.inverse() * velocity
	var frontal := Vector2(local.x, local.y)
	return -frontal.normalized() if frontal.length() > 1e-6 else Vector2(0.0, 1.0)

static func alignment_deg(def: State, arrival: Vector2) -> float:
	return rad_to_deg(absf(Geometry.guard_vector(def.guard).angle_to(arrival)))

static func _weapon_contact(att: State, def: State, point: Vector3, arrival: Vector2, step: int, count: int) -> Dictionary:
	var t := att.t
	var momentum := att.momentum()
	var report := {"point": point, "arrival": arrival, "momentum": momentum, "substep": step, "substeps": count,
		"direction": att.direction, "guard": def.guard, "damage": 0.0, "posture": 0.0}
	att.hit_consumed = true
	if not def.guarding:
		# Two live blades crossed: both are knocked back.
		def.hit_consumed = true
		att.add_posture(t.clash_posture)
		def.add_posture(t.clash_posture)
		att.recoil(t.clash_recoil, false)
		def.recoil(t.clash_recoil, false)
		report.result = CLASH
		report.alignment = -1.0
		return _finish(att, def, report)
	var alignment := alignment_deg(def, arrival)
	report.alignment = alignment
	var thrust := att.direction == Geometry.THRUST
	var pressure: float = momentum * t.block_posture_per_momentum * (t.thrust_block_scale if thrust else 1.0) / def.h.guard_strength
	if alignment > t.block_align_deg:
		# The guard was touched at a bad angle: the blade slides off into the body.
		var damage: float = _damage(att) * t.misaligned_damage_scale
		def.take_damage(damage)
		def.add_posture(pressure * t.misaligned_posture_scale)
		def.stagger(t.stagger_hit)
		att.recoil(t.block_bounce_base, true)
		report.merge({"result": MISALIGNED, "damage": damage, "posture": pressure * t.misaligned_posture_scale}, true)
		return _finish(att, def, report)
	if def.guard_age <= def.deflect_window and alignment <= t.deflect_align_deg and def.h.can_deflect:
		var cost: float = t.deflect_posture_base + t.deflect_posture_per_momentum * momentum
		att.add_posture(cost)
		att.recoil(t.deflect_recoil_base + t.deflect_recoil_per_momentum * momentum, false)
		def.deflect_ready_in = 0.0 # A correct read earns the next attempt immediately.
		def.guard_age = 99.0 # One deflection per raise.
		def.last_event = "DEFLECT"
		report.merge({"result": DEFLECT, "attacker_posture": cost}, true)
		return _finish(att, def, report)
	report.posture = pressure
	if pressure >= t.guard_overwhelm or def.posture + pressure >= def.max_posture:
		def.break_guard()
		att.recoil(t.block_bounce_base, true)
		report.result = GUARD_BREAK
		return _finish(att, def, report)
	def.add_posture(pressure)
	def.last_event = "BLOCK"
	att.recoil(t.block_bounce_base + t.block_bounce_per_momentum * momentum, true)
	report.result = BLOCK
	return _finish(att, def, report)

static func _body_contact(att: State, def: State, point: Vector3, arrival: Vector2, step: int, count: int) -> Dictionary:
	var t := att.t
	att.hit_consumed = true
	var report := {"point": point, "arrival": arrival, "momentum": att.momentum(), "substep": step, "substeps": count,
		"direction": att.direction, "guard": def.guard, "alignment": -1.0, "guard_bypassed": def.guarding, "damage": 0.0, "posture": 0.0}
	if def.phase == State.Phase.DODGE:
		def.last_event = "EVADED"
		report.result = EVADED
		return _finish(att, def, report)
	var broken := def.phase == State.Phase.BROKEN
	var damage: float = _damage(att) * (t.broken_damage_scale if broken else 1.0)
	var posture: float = t.hit_posture * att.impact_ratio()
	def.take_damage(damage)
	if def.phase != State.Phase.DEAD:
		if not broken:
			def.stagger(t.stagger_hit)
		def.add_posture(posture)
		def.last_event = "HIT"
	report.merge({"result": HIT, "damage": damage, "posture": posture}, true)
	return _finish(att, def, report)

static func _damage(att: State) -> float:
	return (att.t.thrust_damage if att.direction == Geometry.THRUST else att.t.swing_damage) * att.impact_ratio()

static func _finish(att: State, def: State, report: Dictionary) -> Dictionary:
	report.attacker_phase = State.Phase.keys()[att.phase]
	report.defender_phase = State.Phase.keys()[def.phase]
	report.defender_health = def.health
	report.defender_posture = def.posture
	return report

## Closest points between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision
## Detection 5.1.9). Returns {distance, s, t, point_a, point_b}.
static func closest_points(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Dictionary:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var u := 0.0
	if a <= 1e-12 and e <= 1e-12:
		pass
	elif a <= 1e-12:
		u = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			u = (b * s + f) / e
			if u < 0.0:
				u = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif u > 1.0:
				u = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var pa := p1 + d1 * s
	var pb := p2 + d2 * u
	return {"distance": pa.distance_to(pb), "s": s, "t": u, "point_a": pa, "point_b": pb}
