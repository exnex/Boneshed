extends RefCounted
## Shared combat rules for every fighter in the Adaptive Combat Lab — the player and
## the corrupted soul run this same class. A controller (keyboard/mouse or AI) only
## supplies an intent {move, face, light, heavy, guard, dodge}; what an intent does is
## decided by the fighter's capability set (affordance_solver.gd) for its current
## object and body. An intent with no capability does nothing except log why: an
## object's name or a controller can never grant a move.
##
## Timing is rule-owned: the motion library is sampled at rule time, and contact is
## tested with the sampled feature capsule of each contact window (the same transform
## the object is drawn with). Presentation reads `pose`; it never feeds back.
##
## Body modifications act through data only (body_plans.gd `modifiers`): incoming
## damage and posture multipliers, health regeneration. The same code runs for both
## fighters, so a modification has the same benefit and cost on either side.

const Motion = preload("res://scripts/adaptive_lab/motion_library.gd")
const Solver = preload("res://scripts/adaptive_lab/affordance_solver.gd")

## Provisional lab tuning (not balance).
const MAX_HP := 100.0
const MAX_POSTURE := 100.0
const MOVE_SPEED := 3.4
const GUARD_MOVE_SPEED := 1.4
const TURN_RATE := 9.0
const ATTACK_TURN_RATE := 2.5
const DODGE_TIME := 0.42
const DODGE_DISTANCE := 2.4
const DODGE_IFRAMES := Vector2(0.04, 0.3)
const DODGE_RECOVERY_PER_KG := 0.012
const STAGGER_LIGHT := 0.3
const STAGGER_HEAVY := 0.55
const DEFLECTED_RECOIL := 0.5
const BREAK_TIME := 1.5
const BROKEN_DAMAGE_MULTIPLIER := 1.5
const POSTURE_REGEN := 14.0
const POSTURE_REGEN_DELAY := 1.2
## Inputs pressed after this fraction of the windup are remembered for the next step.
const BUFFER_FROM := 0.3
const GUARD_BLEND := 0.1
## A fresh guard press only opens a deflect window after this much time unguarded.
const DEFLECT_REARM := 0.2
const BODY_RADIUS := 0.28
const PERSONAL_SPACE := 0.75
## Footwork aims the contact this far into the target (m) when it can.
const SPACING_BITE := 0.12

var id: String
var body: Dictionary
var descriptor: Dictionary
var caps: Dictionary
var position := Vector3.ZERO
var yaw := 0.0
var velocity := Vector3.ZERO
var hp := MAX_HP
var posture := 0.0
var state := "idle"
var state_time := 0.0
var clock := 0.0
var action: Dictionary = {}
var action_start: Dictionary = {}
var attack_serial := 0
var chain_index := 0
var buffered := ""
## Per contact window: already resolved this attack.
var window_done: Array = []
var hyper := false
var guard_since := -10.0
var guard_released := -10.0
var deflect_armed := false
var since_hurt := 10.0
var stagger_for := 0.0
var dodge_dir := Vector3.ZERO
var dodge_time := DODGE_TIME
var pose: Dictionary = {}
var prev_travel := 0.0
## Spacing adjustment chosen at the start of the current attack (m, signed).
var spacing_extra := 0.0
var attack_start_position := Vector3.ZERO
var closest_approach := INF
var whiff_logged := false
var openness := 0.0
var events: Array = []
var regenerated := 0.0

func _init(fighter_id: String) -> void:
	id = fighter_id

## Equips an object for a body: the capability set is recomputed by the shared solver
## (or taken from `precomputed`, which must come from the same solver).
func equip(object_descriptor: Dictionary, body_descriptor: Dictionary, precomputed: Dictionary = {}) -> void:
	descriptor = object_descriptor
	body = body_descriptor
	caps = precomputed if not precomputed.is_empty() else Solver.solve(descriptor, body)
	reset_state()

func reset_state() -> void:
	hp = MAX_HP
	posture = 0.0
	state = "idle"
	state_time = 0.0
	action = {}
	action_start = {}
	chain_index = 0
	buffered = ""
	window_done = []
	hyper = false
	since_hurt = 10.0
	openness = 0.0
	velocity = Vector3.ZERO
	pose = ready_pose()
	prev_travel = 0.0
	spacing_extra = 0.0
	regenerated = 0.0

func has_hold() -> bool:
	return caps.get("hold") != null

func unarmed() -> bool:
	return caps.get("unarmed", false)

func modifier(key: String, default: float) -> float:
	return float((body.get("modifiers", {}) as Dictionary).get(key, default))

func ready_pose() -> Dictionary:
	if not has_hold():
		return {}
	return Motion.ready_pose(caps.hold, caps.ready_frame, body)

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func xform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), position)

func phase() -> String:
	return str(pose.get("phase", "")) if state == "attack" else state

func light_reach() -> float:
	var light: Array = caps.get("light", [])
	if light.is_empty():
		return 1.0
	return float(light[0].get("reach", 1.0)) + maxf(0.0, float(light[0].get("root_contact", 0.0)))

func log_event(kind: String, detail: Variant = null) -> void:
	events.append({"t": snappedf(clock, 0.001), "who": id, "kind": kind, "detail": detail})
	if events.size() > 64:
		events.pop_front()

## One rules tick. intent: {move: Vector3 (world, xz), face: Vector3 (optional world
## facing; absent = face the opponent), light, heavy, dodge: bool (pressed this
## tick), guard: bool (held)}; `target` is the opponent's position.
func step(intent: Dictionary, target: Vector3, dt: float) -> void:
	clock += dt
	state_time += dt
	since_hurt += dt
	if state == "dead":
		return
	_face(intent.get("face", null), target, dt)
	var move: Vector3 = intent.get("move", Vector3.ZERO)
	var guard_held: bool = intent.get("guard", false)
	if guard_held and state != "guard":
		deflect_armed = clock - guard_released >= DEFLECT_REARM
	if not guard_held and state == "guard":
		guard_released = clock
	match state:
		"idle":
			if not _try_start(intent, guard_held, target):
				_move(move, MOVE_SPEED * _mobility(), dt)
				_settle(ready_pose(), dt, 0.12)
		"guard":
			if intent.get("dodge", false):
				_start_dodge(move)
			elif not guard_held:
				_enter("idle")
			else:
				_move(move, GUARD_MOVE_SPEED, dt)
				openness = minf(1.0, openness + dt / GUARD_BLEND)
				if has_hold() and caps.guard != null:
					_settle(Motion.guard_pose(caps.guard, body), dt, GUARD_BLEND)
		"attack":
			_attack_tick(intent, guard_held, dt, target)
		"dodge":
			var u := clampf(state_time / dodge_time, 0.0, 1.0)
			position += dodge_dir * DODGE_DISTANCE / dodge_time * dt * (1.6 - 1.2 * u)
			_settle(ready_pose(), dt, 0.15)
			if state_time >= dodge_time:
				_enter("idle")
		"stagger", "broken", "recoil":
			_settle(ready_pose(), dt, 0.25)
			if state_time >= stagger_for:
				if state == "broken":
					posture = 0.0
				_enter("idle")
	if state != "guard":
		openness = maxf(0.0, openness - dt / GUARD_BLEND)
	if since_hurt > POSTURE_REGEN_DELAY and state != "broken":
		posture = maxf(0.0, posture - POSTURE_REGEN * (1.5 if state == "guard" else 1.0) * dt)
	var regen := modifier("hp_regen_per_s", 0.0)
	if regen > 0.0 and since_hurt > modifier("hp_regen_delay_s", 0.0) and hp < MAX_HP:
		var gained := minf(MAX_HP - hp, regen * dt)
		hp += gained
		regenerated += gained

func _mobility() -> float:
	return clampf(1.0 - float(caps.get("mass", 0.0)) * 0.025, 0.7, 1.0) if not unarmed() else 1.0

func _face(face: Variant, target: Vector3, dt: float) -> void:
	var to := target - position
	if face is Vector3 and (face as Vector3).length() > 0.01:
		to = face
	to.y = 0.0
	if to.length() < 0.01:
		return
	var desired := atan2(-to.x, -to.z)
	var rate := ATTACK_TURN_RATE if state == "attack" and pose.get("phase", "") != "windup" else TURN_RATE
	yaw += clampf(wrapf(desired - yaw, -PI, PI), -rate * dt, rate * dt)

func _move(move: Vector3, speed: float, dt: float) -> void:
	var m := Vector3(move.x, 0.0, move.z)
	if m.length() > 1.0:
		m = m.normalized()
	velocity = m * speed
	position += velocity * dt

func _settle(target: Dictionary, dt: float, time_constant: float) -> void:
	if target.is_empty():
		pose = {}
		return
	if pose.is_empty():
		pose = target
		return
	pose = Motion.approach(caps.hold, pose, target, 1.0 - exp(-dt / time_constant), body)

func _enter(new_state: String) -> void:
	state = new_state
	state_time = 0.0
	velocity = Vector3.ZERO

func _try_start(intent: Dictionary, guard_held: bool, target: Vector3) -> bool:
	if intent.get("dodge", false):
		_start_dodge(intent.get("move", Vector3.ZERO))
		return true
	if intent.get("light", false):
		return _start_attack("light", 0, target)
	if intent.get("heavy", false):
		return _start_attack("heavy", -1, target)
	if guard_held:
		if caps.get("guard") == null:
			log_event("guard_unsupported", "no guarding surface or hold for this object and body")
			return false
		_enter("guard")
		guard_since = clock
		return true
	return false

## kind "light" with a chain index, or "heavy" with the light step it follows (−1 =
## from neutral; the combo graph's finisher otherwise).
func _start_attack(kind: String, index: int, target: Vector3) -> bool:
	var chosen: Variant = null
	if kind == "light":
		var chain: Array = caps.get("light", [])
		if not chain.is_empty():
			chosen = chain[index % chain.size()]
	else:
		var after: Array = caps.get("heavy_after", [])
		chosen = after[index] if index >= 0 and index < after.size() and after[index] != null else caps.get("heavy")
	if chosen == null:
		log_event("%s_unsupported" % kind, _unsupported_reason(kind))
		return false
	action = chosen
	action_start = Motion.pose_key(pose, caps.hold) if not pose.is_empty() and not unarmed() else {}
	chain_index = index if kind == "light" else 0
	buffered = ""
	window_done = []
	for _w: Variant in action.windows_abs:
		window_done.append(false)
	hyper = bool(action.heavy)
	attack_serial += 1
	prev_travel = 0.0
	closest_approach = INF
	whiff_logged = false
	attack_start_position = position
	spacing_extra = _spacing(target)
	_enter("attack")
	log_event("attack", {"input": kind, "index": index, "action": action.id, "archetype": action.archetype, "feature": action.feature.id,
		"channel": action.channel, "spacing": snappedf(spacing_extra, 0.001), "distance": snappedf(_distance_to(target), 0.001)})
	return true

## Continuous footwork: travel so that the striking feature's furthest reach lands a
## little inside the target, within the action's step limits. (Lab 1 stepped back by
## the whole authored step whenever the target was inside the sweet spot, which made
## close heavies whiff — see docs/ADAPTIVE_COMBAT_LAB.md §6.)
func _spacing(target: Vector3) -> float:
	var dist := _distance_to(target)
	# Every contact window must land: space for the shortest-reaching one.
	var reach: float = action.get("reach", 1.0)
	for r: Variant in action.get("reach_windows", []):
		reach = minf(reach, float(r))
	var root_contact: float = action.get("root_contact", 0.0)
	var wanted := dist - BODY_RADIUS + SPACING_BITE - reach - root_contact
	var max_in := 0.35 + maxf(0.0, root_contact) * 0.8
	var max_out := 0.35 + maxf(0.0, root_contact) * 0.5
	return clampf(wanted, -max_out, max_in)

func _distance_to(target: Vector3) -> float:
	return Vector3(target.x - position.x, 0.0, target.z - position.z).length()

func _unsupported_reason(kind: String) -> String:
	for r: Dictionary in caps.get("rejections", []):
		if r.code == "no_%s_action" % kind or r.code == "object_not_wieldable":
			return str(r.detail)
	return "no capability"

## Chain/heavy buffering opens later, and the recovery can be cancelled later, the
## heavier the object (heft from the solver's physics).
func chain_from() -> float:
	return 0.22 + 0.3 * float(action.get("heft", 0.0))

func dodge_cancel_from() -> float:
	return 0.12 + 0.45 * float(action.get("heft", 0.0))

func _attack_tick(intent: Dictionary, guard_held: bool, dt: float, target: Vector3) -> void:
	var total: float = action.windup + action.active + action.recovery
	pose = Motion.sample(action, state_time, body, action_start)
	var travel := Motion.travel(action, state_time, spacing_extra)
	position += forward() * (travel - prev_travel)
	prev_travel = travel
	var in_recovery: bool = state_time >= float(action.windup) + float(action.active)
	if state_time >= action.windup * BUFFER_FROM:
		if intent.get("light", false):
			buffered = "light"
		elif intent.get("heavy", false):
			buffered = "heavy"
	if in_recovery:
		var u: float = (state_time - float(action.windup) - float(action.active)) / float(action.recovery)
		if not window_done.has(true) and not whiff_logged:
			log_event("whiff", {"serial": attack_serial, "action": action.id, "closest": snappedf(closest_approach, 0.001)})
			whiff_logged = true
		if intent.get("dodge", false) and u >= dodge_cancel_from():
			_start_dodge(intent.get("move", Vector3.ZERO))
			return
		if u >= chain_from() and buffered != "":
			var next := buffered
			var started := false
			if next == "light" and not action.heavy:
				var index := chain_index + 1
				if index >= (caps.light as Array).size():
					index = 0
				started = _start_attack("light", index, target)
			elif next == "heavy" and not action.heavy:
				started = _start_attack("heavy", chain_index, target)
			else:
				started = _start_attack(next, 0 if next == "light" else -1, target)
			if started:
				return
			buffered = ""
		if u >= 0.5 and guard_held and caps.get("guard") != null:
			_enter("guard")
			guard_since = clock
			deflect_armed = false
			return
	if state_time >= total:
		_enter("idle")

func _start_dodge(move: Vector3) -> void:
	var m := Vector3(move.x, 0.0, move.z)
	dodge_dir = m.normalized() if m.length() > 0.1 else -forward()
	dodge_time = DODGE_TIME + (float(caps.get("mass", 0.0)) * DODGE_RECOVERY_PER_KG if not unarmed() else 0.0)
	_enter("dodge")
	log_event("dodge")

func invulnerable() -> bool:
	return state == "dodge" and state_time >= DODGE_IFRAMES.x and state_time <= DODGE_IFRAMES.y

func in_deflect_window() -> bool:
	return state == "guard" and deflect_armed and caps.get("guard") != null and clock - guard_since <= float(caps.guard.deflect)

## World-space contact capsule of contact window `w` of the current action at rule
## time t (the window's feature; the travel at t is applied like the drawn pose).
func contact_at(t: float, w := 0) -> Array:
	var p := Motion.sample(action, t, body, action_start)
	var cap := Motion.contact_capsule(Motion.window_feature(action, w), p.object)
	var xf := Transform3D(Basis(Vector3.UP, yaw), position + forward() * (Motion.travel(action, t, spacing_extra) - prev_travel))
	return [xf * (cap[0] as Vector3), xf * (cap[1] as Vector3), cap[2]]

func body_capsule() -> Array:
	return [position + Vector3(0.0, 0.2, 0.0), position + Vector3(0.0, float(body.shoulder_height) + 0.2, 0.0), BODY_RADIUS]

## Resolves the attacker's contact windows against the defender for this tick. Sweeps
## each window's feature capsule through `substeps` rule-time samples since the
## previous tick.
static func resolve(attacker: RefCounted, defender: RefCounted, dt: float, substeps := 4) -> Dictionary:
	if attacker.state != "attack" or defender.state == "dead":
		return {}
	var t1: float = attacker.state_time
	var t0 := t1 - dt
	var windows: Array = attacker.action.windows_abs
	for w in range(windows.size()):
		if attacker.window_done[w]:
			continue
		var w0: float = windows[w].t0
		var w1: float = windows[w].t1
		if t1 < w0 or t0 > w1:
			continue
		var bodycap: Array = defender.body_capsule()
		for i in range(1, substeps + 1):
			var t := clampf(lerpf(t0, t1, float(i) / substeps), w0, w1)
			var cap: Array = attacker.contact_at(t, w)
			var dist := segment_segment(cap[0], cap[1], bodycap[0], bodycap[1])
			var gap: float = dist - float(cap[2]) - float(bodycap[2])
			attacker.closest_approach = minf(attacker.closest_approach, gap)
			if gap <= 0.0:
				if defender.invulnerable():
					if not attacker.events.any(func(e: Dictionary) -> bool: return e.kind == "evaded" and e.detail == attacker.attack_serial):
						attacker.log_event("evaded", attacker.attack_serial)
					attacker.window_done[w] = true
					return {}
				attacker.window_done[w] = true
				return _apply_hit(attacker, defender, ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5, t, w)
	return {}

static func _apply_hit(attacker: RefCounted, defender: RefCounted, point: Vector3, t: float, w: int) -> Dictionary:
	var act: Dictionary = attacker.action
	var damage: float = act.damage
	var posture: float = act.posture
	var to_attacker: Vector3 = attacker.position - defender.position
	to_attacker.y = 0.0
	var angle: float = defender.forward().angle_to(to_attacker.normalized()) if to_attacker.length() > 0.01 else 0.0
	var feature: Dictionary = Motion.window_feature(act, w)
	var result := {"attacker": attacker.id, "defender": defender.id, "action": act.id, "feature": feature.id, "window": w, "point": point,
		"rule_time": snappedf(t, 0.0001), "outcome": ""}
	var damage_taken_mult: float = defender.modifier("damage_taken_mult", 1.0)
	var posture_taken_mult: float = defender.modifier("posture_taken_mult", 1.0)
	var guard: Variant = defender.caps.get("guard")
	if defender.state == "guard" and guard != null and angle <= float(guard.arc):
		if defender.in_deflect_window():
			result.outcome = "deflected"
			attacker.posture = minf(MAX_POSTURE, attacker.posture + posture * 0.6 + 8.0)
			attacker.since_hurt = 0.0
			attacker.stagger_for = DEFLECTED_RECOIL
			attacker._enter("recoil")
			if attacker.posture >= MAX_POSTURE:
				_break(attacker)
		else:
			result.outcome = "blocked"
			var absorb: float = guard.absorb
			defender.hp -= damage * (1.0 - absorb) * damage_taken_mult
			defender.posture = minf(MAX_POSTURE, defender.posture + posture * (1.25 - absorb * 0.6) * posture_taken_mult)
			defender.since_hurt = 0.0
			if float(act.get("pull", 0.0)) > 0.0:
				_pull(attacker, defender, float(act.pull) * 0.6)
				result.pulled = true
			if defender.posture >= MAX_POSTURE:
				_break(defender)
	else:
		result.outcome = "hit"
		if defender.state == "broken":
			damage *= BROKEN_DAMAGE_MULTIPLIER
			result.outcome = "punish"
		defender.hp -= damage * damage_taken_mult
		defender.posture = minf(MAX_POSTURE, defender.posture + posture * 0.5 * posture_taken_mult)
		defender.since_hurt = 0.0
		if float(act.get("pull", 0.0)) > 0.0:
			_pull(attacker, defender, float(act.pull))
			result.pulled = true
		if defender.posture >= MAX_POSTURE and defender.state != "broken":
			_break(defender)
		elif defender.state != "broken" and not (defender.state == "attack" and defender.hyper and defender.pose.get("phase", "") == "windup"):
			defender.stagger_for = (STAGGER_HEAVY if act.heavy else STAGGER_LIGHT) * defender.modifier("stagger_time_mult", 1.0)
			defender._enter("stagger")
	result.damage_taken = snappedf(maxf(0.0, MAX_HP - defender.hp), 0.01)
	if defender.hp <= 0.0:
		defender.hp = 0.0
		defender._enter("dead")
		result.killed = true
	attacker.log_event("contact", result)
	defender.log_event("received", result)
	return result

## A hook drags the defender toward the attacker (never closer than personal space).
static func _pull(attacker: RefCounted, defender: RefCounted, amount: float) -> void:
	var d: Vector3 = attacker.position - defender.position
	d.y = 0.0
	var dist := d.length()
	if dist < 0.001:
		return
	defender.position += d / dist * minf(amount, maxf(0.0, dist - PERSONAL_SPACE))

static func _break(fighter: RefCounted) -> void:
	fighter.posture = MAX_POSTURE
	fighter.stagger_for = BREAK_TIME * fighter.modifier("stagger_time_mult", 1.0)
	fighter._enter("broken")
	fighter.log_event("posture_broken")

## Keeps two fighters from overlapping.
static func separate(a: RefCounted, b: RefCounted) -> void:
	var d: Vector3 = b.position - a.position
	d.y = 0.0
	var dist := d.length()
	if dist < PERSONAL_SPACE and dist > 0.0001:
		var push := d / dist * (PERSONAL_SPACE - dist) * 0.5
		a.position -= push
		b.position += push

## Closest distance between segments p1-q1 and p2-q2.
static func segment_segment(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
