extends RefCounted
## Shared combat rules for every fighter in the Adaptive Combat Lab — the player and
## the corrupted soul run this same class. A controller (keyboard/mouse or AI) only
## supplies an intent {move, light, heavy, guard, dodge}; what an intent does is decided
## by the fighter's capability set (affordance_solver.gd) for its current object and
## body. An intent with no capability does nothing except log why: an object's name or
## a controller can never grant a move.
##
## Timing is rule-owned: the motion library is sampled at rule time, and contact is
## tested with the sampled feature capsule (the same transform the object is drawn
## with). Presentation reads `pose`; it never feeds back.

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
## A buffered chain/heavy starts once this fraction of the recovery has passed.
const CHAIN_FROM := 0.35
const GUARD_BLEND := 0.1
## A fresh guard press only opens a deflect window after this much time unguarded.
const DEFLECT_REARM := 0.2
const BODY_RADIUS := 0.28
const PERSONAL_SPACE := 0.75
## Attack footwork aims to strike with the feature this far inside its maximum reach.
const SPACING_MARGIN := 0.4

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
var hit_done := false
var hyper := false
var guard_since := -10.0
var guard_released := -10.0
var deflect_armed := false
var since_hurt := 10.0
var stagger_for := 0.0
var dodge_dir := Vector3.ZERO
var dodge_time := DODGE_TIME
var pose: Dictionary = {}
var prev_step := 0.0
var openness := 0.0
var events: Array = []

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
	hit_done = false
	hyper = false
	since_hurt = 10.0
	openness = 0.0
	velocity = Vector3.ZERO
	pose = ready_pose()
	prev_step = 0.0

func has_hold() -> bool:
	return caps.get("hold") != null

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
	return float(light[0].get("reach", 1.2)) if not light.is_empty() else 1.0

func log_event(kind: String, detail: Variant = null) -> void:
	events.append({"t": snappedf(clock, 0.001), "who": id, "kind": kind, "detail": detail})
	if events.size() > 64:
		events.pop_front()

## One rules tick. intent: {move: Vector3 (world, xz), light, heavy, dodge: bool
## (pressed this tick), guard: bool (held)}; `target` is the opponent's position.
func step(intent: Dictionary, target: Vector3, dt: float) -> void:
	clock += dt
	state_time += dt
	since_hurt += dt
	if state == "dead":
		return
	_face(target, dt)
	var move: Vector3 = intent.get("move", Vector3.ZERO)
	var guard_held: bool = intent.get("guard", false)
	if guard_held and state != "guard":
		deflect_armed = clock - guard_released >= DEFLECT_REARM
	if not guard_held and state == "guard":
		guard_released = clock
	match state:
		"idle":
			if not _try_start(intent, guard_held):
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

func _mobility() -> float:
	return clampf(1.0 - float(caps.get("mass", 0.0)) * 0.025, 0.7, 1.0)

func _face(target: Vector3, dt: float) -> void:
	var to := target - position
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

func _try_start(intent: Dictionary, guard_held: bool) -> bool:
	if intent.get("dodge", false):
		_start_dodge(intent.get("move", Vector3.ZERO))
		return true
	if intent.get("light", false):
		return _start_attack("light", 0)
	if intent.get("heavy", false):
		return _start_attack("heavy", 0)
	if guard_held:
		if caps.get("guard") == null:
			log_event("guard_unsupported", "no guarding surface or hold for this object and body")
			return false
		_enter("guard")
		guard_since = clock
		return true
	return false

func _start_attack(kind: String, index: int) -> bool:
	var chosen: Variant = null
	if kind == "light":
		var chain: Array = caps.get("light", [])
		if not chain.is_empty():
			chosen = chain[index % chain.size()]
	else:
		chosen = caps.get("heavy")
	if chosen == null:
		log_event("%s_unsupported" % kind, _unsupported_reason(kind))
		return false
	action = chosen
	action_start = Motion.pose_key(pose, caps.hold) if not pose.is_empty() else {}
	chain_index = index
	buffered = ""
	hit_done = false
	hyper = bool(action.heavy)
	attack_serial += 1
	prev_step = 0.0
	_enter("attack")
	log_event("attack", {"input": kind, "index": index, "action": action.id, "archetype": action.archetype, "feature": action.feature.id,
		"channel": action.channel})
	return true

func _unsupported_reason(kind: String) -> String:
	for r: Dictionary in caps.get("rejections", []):
		if r.code == "no_%s_action" % kind or r.code == "object_unusable_for_body":
			return str(r.detail)
	return "no capability"

func _attack_tick(intent: Dictionary, guard_held: bool, dt: float, target: Vector3) -> void:
	var total: float = action.windup + action.active + action.recovery
	pose = Motion.sample(action, state_time, body, action_start)
	# Authored footwork adapts to spacing: step in when the opponent is beyond the
	# striking feature's sweet spot, step back to make room when crowded.
	var spacing := maxf(float(action.get("reach", 1.2)) - SPACING_MARGIN, PERSONAL_SPACE + 0.2)
	var away := Vector3(target.x - position.x, 0.0, target.z - position.z).length()
	var direction := 1.0 if away >= spacing else -1.0
	position += forward() * (float(pose.step) - prev_step) * direction
	prev_step = pose.step
	var in_recovery: bool = state_time >= float(action.windup) + float(action.active)
	if state_time >= action.windup * BUFFER_FROM:
		if intent.get("light", false):
			buffered = "light"
		elif intent.get("heavy", false):
			buffered = "heavy"
	if in_recovery:
		var u: float = (state_time - float(action.windup) - float(action.active)) / float(action.recovery)
		if intent.get("dodge", false):
			_start_dodge(intent.get("move", Vector3.ZERO))
			return
		if u >= CHAIN_FROM and buffered != "":
			var next := buffered
			var index := chain_index + 1 if next == "light" and not action.heavy else 0
			if next == "light" and index >= (caps.light as Array).size():
				index = 0
			if _start_attack(next, index):
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
	dodge_time = DODGE_TIME + float(caps.get("mass", 0.0)) * DODGE_RECOVERY_PER_KG
	_enter("dodge")
	log_event("dodge")

func invulnerable() -> bool:
	return state == "dodge" and state_time >= DODGE_IFRAMES.x and state_time <= DODGE_IFRAMES.y

func in_deflect_window() -> bool:
	return state == "guard" and deflect_armed and caps.get("guard") != null and clock - guard_since <= float(caps.guard.deflect)

## World-space contact capsule of the current action at rule time t.
func contact_at(t: float) -> Array:
	var p := Motion.sample(action, t, body, action_start)
	var cap := Motion.contact_capsule(action.feature, p.object)
	var xf := xform()
	return [xf * (cap[0] as Vector3), xf * (cap[1] as Vector3), cap[2]]

func body_capsule() -> Array:
	return [position + Vector3(0.0, 0.2, 0.0), position + Vector3(0.0, float(body.shoulder_height) + 0.2, 0.0), BODY_RADIUS]

## Resolves the attacker's active window against the defender for this tick. Sweeps
## the feature capsule through `substeps` rule-time samples since the previous tick.
static func resolve(attacker: RefCounted, defender: RefCounted, dt: float, substeps := 4) -> Dictionary:
	if attacker.state != "attack" or attacker.hit_done or defender.state == "dead":
		return {}
	var w: float = attacker.action.windup
	var a: float = attacker.action.active
	var t1: float = attacker.state_time
	var t0 := t1 - dt
	if t1 < w or t0 > w + a:
		return {}
	var bodycap: Array = defender.body_capsule()
	for i in range(1, substeps + 1):
		var t := clampf(lerpf(t0, t1, float(i) / substeps), w, w + a)
		var cap: Array = attacker.contact_at(t)
		var dist := segment_segment(cap[0], cap[1], bodycap[0], bodycap[1])
		if dist <= float(cap[2]) + float(bodycap[2]):
			if defender.invulnerable():
				if not attacker.events.any(func(e: Dictionary) -> bool: return e.kind == "evaded" and e.detail == attacker.attack_serial):
					attacker.log_event("evaded", attacker.attack_serial)
				return {}
			return _apply_hit(attacker, defender, ((cap[0] as Vector3) + (cap[1] as Vector3)) * 0.5, t)
	return {}

static func _apply_hit(attacker: RefCounted, defender: RefCounted, point: Vector3, t: float) -> Dictionary:
	attacker.hit_done = true
	var act: Dictionary = attacker.action
	var damage: float = act.damage
	var posture: float = act.posture
	var to_attacker: Vector3 = attacker.position - defender.position
	to_attacker.y = 0.0
	var angle: float = defender.forward().angle_to(to_attacker.normalized()) if to_attacker.length() > 0.01 else 0.0
	var result := {"attacker": attacker.id, "defender": defender.id, "action": act.id, "feature": act.feature.id, "point": point,
		"rule_time": snappedf(t, 0.0001), "outcome": ""}
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
			defender.hp -= damage * (1.0 - absorb)
			defender.posture = minf(MAX_POSTURE, defender.posture + posture * (1.25 - absorb * 0.6))
			defender.since_hurt = 0.0
			if defender.posture >= MAX_POSTURE:
				_break(defender)
	else:
		result.outcome = "hit"
		if defender.state == "broken":
			damage *= BROKEN_DAMAGE_MULTIPLIER
			result.outcome = "punish"
		defender.hp -= damage
		defender.posture = minf(MAX_POSTURE, defender.posture + posture * 0.5)
		defender.since_hurt = 0.0
		if defender.posture >= MAX_POSTURE and defender.state != "broken":
			_break(defender)
		elif defender.state != "broken" and not (defender.state == "attack" and defender.hyper and defender.pose.get("phase", "") == "windup"):
			defender.stagger_for = STAGGER_HEAVY if act.heavy else STAGGER_LIGHT
			defender._enter("stagger")
	result.damage_taken = snappedf(maxf(0.0, MAX_HP - defender.hp), 0.01)
	if defender.hp <= 0.0:
		defender.hp = 0.0
		defender._enter("dead")
		result.killed = true
	attacker.log_event("contact", result)
	defender.log_event("received", result)
	return result

static func _break(fighter: RefCounted) -> void:
	fighter.posture = MAX_POSTURE
	fighter.stagger_for = BREAK_TIME
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
