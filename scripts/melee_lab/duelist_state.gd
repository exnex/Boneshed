extends RefCounted
## Rules state for one lab duelist: directional windup → swing → recovery with
## inertia-limited weapon motion, directional guard with timed deflection, dodge, and
## the reactions applied by the contact solver. Presentation-, input- and AI-free;
## controllers call the press/hold/release methods and `tick`. All values provisional.
##
## Combat resources (experimental): stamina is charged exactly once per action at the
## moment it legally begins — an attack when its windup starts (a buffered attack when
## the buffer turns into a windup), a dodge or roll when it starts. Release events,
## redirects, holding a chamber and holding a guard never charge. A voluntary cancel of
## an *unreleased* windup (fresh guard press, dodge, roll) refunds `feint_refund` of the
## attack's cost; released attacks and interruptions refund nothing. Unaffordable
## actions are refused and recorded (stamina_pool.gd). Status buildup reaches this
## fighter only through `receive_status`, after the contact outcome is known.

const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Stamina = preload("res://scripts/melee_lab/stamina_pool.gd")
const Status = preload("res://scripts/melee_lab/status_effects.gd")
const Resources = preload("res://scripts/melee_lab/combat_resources.gd")

## ROLL is appended so earlier phase indices (logged in evidence) keep their values.
enum Phase { IDLE, WINDUP, SWING, RECOVERY, RECOIL, STAGGER, BROKEN, DODGE, DEAD, ROLL }
const ACTING := [Phase.IDLE, Phase.WINDUP, Phase.SWING, Phase.RECOVERY]
const ARRIVED := 0.0005 # Radians; chamber reached.
const BUFFER_SECONDS := 0.2 # An attack pressed during braking starts when the blade is free.

var t: Dictionary
var h: Dictionary
## Unimpaired handling; `h` is this scaled while a handling impairment is active.
var base_h: Dictionary
var handling_scale := 1.0
## combat_resources.gd derive output: costs, mobility, mitigation, resistances, sources.
var resources: Dictionary
var stamina := Stamina.new()
var status: Status
## Stamina paid for the current attack (0 once it can no longer be refunded).
var attack_paid := 0.0
var action_serial := 0
var roll_elapsed := 0.0
## Periodic status damage taken since reset (for tests and HUD).
var status_damage_taken := 0.0
var max_health := 100.0
var max_posture := 100.0
var deflect_window := 0.16
var posture_recovery_rate := 12.0
var posture_recovery_delay := 1.5
var health := 100.0
var posture := 0.0
var phase: Phase = Phase.IDLE
var remaining := 0.0
var clock := 0.0
## Current attack direction (Geometry.DIRECTIONS) and the last one actually swung.
var direction := ""
var last_swung := ""
var windup_time := 0.0
var released := false
var hold_time := 0.0
## Re-chamber via neutral before moving to a new aimed cut. Prevents the
## shortest-slerp from swinging an opposite-side change behind the fighter.
var rechamber_to_neutral := false
var buffered := ""
var buffer_time := 0.0
var buffer_released := false
## Weapon pose in local space; `prev_*` is the pose at the start of this tick.
var hand := Vector3.ZERO
var dir := Vector3.FORWARD
var prev_hand := Vector3.ZERO
var prev_dir := Vector3.FORWARD
var theta := 0.0
var omega := 0.0
var extension := 0.0
var thrust_speed := 0.0
## A sweep is open while the blade is swinging this tick and has not made contact;
## it stays open for the tick in which the arc ends so the final segment is tested.
var sweep_open := false
var live_value := -1.0
var prev_live_value := -1.0
var move_speed := 0.0 # Repositioning angular speed of the pose mover (rad/s).
var hit_consumed := false
var swing_serial := 0
## Guard.
var guard_input_held := false
var guarding := false
var guard := "high"
var guard_age := 99.0
var deflect_ready_in := 0.0
var guard_delay := 0.0
var dodge_ready_in := 0.0
var since_pressure := 99.0
var last_event := ""

## `combat` is combat_resources.gd derive output; {} derives an unarmoured, status-free
## profile from the same tuning, so every fighter has stamina.
func _init(tuning: Dictionary, handling: Dictionary, stats := {}, combat := {}) -> void:
	t = tuning
	base_h = handling
	h = handling
	for stat: String in ["max_health", "max_posture", "deflect_window", "posture_recovery_rate", "posture_recovery_delay"]:
		if stats.has(stat):
			set(stat, float(stats[stat]))
	resources = combat if not combat.is_empty() else Resources.derive(handling, str(handling.get("item", "")), [], {}, tuning)
	stamina.configure(resources.stamina_max, resources.stamina_regen, resources.stamina_regen_delay, resources.stamina_empty_regen_delay)
	status = Status.new(resources.effects, resources.resistances)
	reset()

func reset() -> void:
	health = max_health
	posture = 0.0
	phase = Phase.IDLE
	remaining = 0.0
	direction = ""
	last_swung = ""
	released = false
	buffered = ""
	guard_input_held = false
	guarding = false
	guard = "high"
	guard_age = 99.0
	deflect_ready_in = 0.0
	guard_delay = 0.0
	dodge_ready_in = 0.0
	since_pressure = 99.0
	hit_consumed = false
	omega = 0.0
	thrust_speed = 0.0
	move_speed = 0.0
	last_event = ""
	stamina.reset()
	status.reset()
	attack_paid = 0.0
	roll_elapsed = 0.0
	status_damage_taken = 0.0
	_set_handling_scale(1.0)
	var rest := Geometry.rest_pose(t)
	hand = rest.hand
	dir = rest.dir
	prev_hand = hand
	prev_dir = dir
	live_value = -1.0
	prev_live_value = -1.0

## --- Controller interface -----------------------------------------------------

## Starts preparing an attack. "" picks the natural follow-up of the last swing.
func press_attack(requested := "") -> bool:
	var chosen: String = requested if requested != "" else Geometry.FOLLOW_UP[last_swung]
	if phase == Phase.RECOVERY or (phase == Phase.IDLE and guard_delay > 0.0):
		buffered = chosen
		buffer_time = BUFFER_SECONDS
		buffer_released = false
		return false
	if phase != Phase.IDLE or guarding:
		return false
	if not _charge_attack():
		return false
	_begin_windup(chosen)
	return true

## Redirects a windup that has not been released (a feint or late change of angle).
func aim_attack(requested: String) -> void:
	if phase == Phase.WINDUP and not released and requested != "" and requested != direction:
		direction = requested
		rechamber_to_neutral = true
	elif buffered != "" and requested != "":
		buffered = requested

func release_attack() -> void:
	if phase == Phase.WINDUP:
		released = true
	elif buffered != "":
		buffer_released = true

## Guard input. A fresh press cancels any attack. Windups cancel instantly; a swing's
## blade must first brake (ω / brake, capped) before the guard pose starts moving.
func set_guard(held: bool, sector := "") -> void:
	var pressed := held and not guard_input_held
	guard_input_held = held
	if sector != "":
		guard = sector
	if pressed:
		buffered = ""
		if phase in [Phase.WINDUP, Phase.SWING, Phase.RECOVERY]:
			var spinning := omega if phase != Phase.WINDUP else 0.0
			guard_delay = minf(spinning / h.brake, t.cancel_brake_cap) if spinning > 0.0 else 0.0
			stamina.refund(pending_refund(), action_serial, clock)
			_cancel_attack()
		var allowed: bool = phase == Phase.IDLE and h.can_guard
		guard_age = 0.0 if allowed and h.can_deflect and deflect_ready_in <= 0.0 else 99.0
		deflect_ready_in = t.deflect_rearm
	guarding = held and phase == Phase.IDLE and h.can_guard
	if not guarding:
		guard_age = 99.0

## Quick dodge step: short, fully invulnerable, cheaper. Cancels any attack.
func dodge() -> bool:
	return _evade(Phase.DODGE, "dodge", resources.dodge_cost, t.dodge_duration, t.dodge_cooldown)

## Dodge roll: travels further and longer, invulnerable only for its first
## `roll_invulnerable` seconds, then a vulnerable tail; costs more.
func roll() -> bool:
	return _evade(Phase.ROLL, "roll", resources.roll_cost, t.roll_duration, t.roll_cooldown)

func _evade(kind: Phase, action: String, cost: float, duration: float, cooldown: float) -> bool:
	if phase not in ACTING or dodge_ready_in > 0.0:
		return false
	# A cancelled unreleased windup's refund counts toward the evasion's cost.
	action_serial += 1
	if not stamina.spend(action, cost, action_serial, clock, pending_refund()):
		return false
	attack_paid = 0.0 # Already folded into the charge above.
	_cancel_attack()
	buffered = ""
	guarding = false
	guard_age = 99.0
	phase = kind
	remaining = duration
	roll_elapsed = 0.0
	dodge_ready_in = cooldown
	return true

## Stamina a voluntary cancel would return now: only an unreleased windup is a feint.
func pending_refund() -> float:
	return attack_paid * t.feint_refund if phase == Phase.WINDUP and not released else 0.0

func _charge_attack() -> bool:
	action_serial += 1
	if not stamina.spend("attack", resources.attack_cost, action_serial, clock):
		return false
	attack_paid = resources.attack_cost
	return true

## --- Queries --------------------------------------------------------------------

func invulnerable() -> bool:
	return phase == Phase.DODGE or (phase == Phase.ROLL and roll_elapsed < t.roll_invulnerable)

func evading() -> bool:
	return phase in [Phase.DODGE, Phase.ROLL]

## Locomotion and evasion speed multipliers from armor and active impairments.
func move_scale() -> float:
	return resources.move_scale * status.move_scale()

func evasion_speed_scale() -> float:
	return resources.evasion_speed_scale * status.move_scale()

## What this fighter may legally do right now, by the same rules for every controller
## (player input, lab AI, a future Echo policy). Costs are this build's real costs.
func legal_actions() -> Dictionary:
	var free := phase in ACTING
	return {
		"attack": phase == Phase.IDLE and not guarding and guard_delay <= 0.0 and stamina.can_afford(resources.attack_cost),
		"attack_cost": resources.attack_cost,
		"dodge": free and dodge_ready_in <= 0.0 and stamina.can_afford(resources.dodge_cost, pending_refund()),
		"dodge_cost": resources.dodge_cost,
		"roll": free and dodge_ready_in <= 0.0 and stamina.can_afford(resources.roll_cost, pending_refund()),
		"roll_cost": resources.roll_cost,
		"guard": h.can_guard and phase in [Phase.IDLE, Phase.WINDUP, Phase.SWING, Phase.RECOVERY],
	}

## This fighter's own condition: exact for itself, never a view of its opponent.
func self_view() -> Dictionary:
	return {"stamina": stamina.current, "stamina_max": stamina.max_stamina, "health": health, "posture": posture,
		"statuses": status.view(), "legal": legal_actions()}

func is_live() -> bool:
	return sweep_open and not hit_consumed and live_value >= 0.0

func pose_at(w: float) -> Dictionary:
	var d := prev_dir.slerp(dir, w) if prev_dir.angle_to(dir) > 1e-5 else dir
	return {"hand": prev_hand.lerp(hand, w), "dir": d.normalized()}

func live_at(w: float) -> bool:
	return sweep_open and not hit_consumed and lerpf(prev_live_value, live_value, w) >= 0.0

## Angular momentum of a swing (kg·m²/s) or linear momentum of a thrust (kg·m/s).
func momentum() -> float:
	if direction == Geometry.THRUST:
		return h.thrust_mass * thrust_speed
	return h.inertia * omega

## Impact strength relative to the reference swing: √(KE / KE_ref) for swings,
## p / p_ref for thrusts.
func impact_ratio() -> float:
	if direction == Geometry.THRUST:
		return momentum() / t.thrust_momentum_ref
	return sqrt(0.5 * h.inertia * omega * omega / t.energy_ref)

func stage() -> String:
	match phase:
		Phase.WINDUP:
			return "released" if released else "aiming"
		Phase.SWING:
			return "live" if live_value >= 0.0 else "accelerating"
	return Phase.keys()[phase].to_lower()

## Seconds of windup left if released now, from the current pose (for HUD/AI estimates).
func chamber_angle() -> float:
	return dir.angle_to(Geometry.chamber_pose(direction, t).dir)

## --- Simulation -----------------------------------------------------------------

func tick(delta: float) -> void:
	clock += delta
	if phase != Phase.DEAD:
		var regen_scale: float = t.stamina_regen_hold_scale if phase == Phase.WINDUP and not released else (t.stamina_regen_guard_scale if guarding else 1.0)
		stamina.tick(delta, regen_scale)
		for due: Dictionary in status.tick(delta):
			take_status_damage(due.damage, due.can_kill)
		_set_handling_scale(status.handling_scale())
	prev_hand = hand
	prev_dir = dir
	prev_live_value = live_value
	guard_age += delta
	deflect_ready_in = maxf(0.0, deflect_ready_in - delta)
	dodge_ready_in = maxf(0.0, dodge_ready_in - delta)
	since_pressure += delta
	buffer_time = maxf(0.0, buffer_time - delta)
	if buffer_time <= 0.0:
		buffered = ""
	var was_swinging := phase == Phase.SWING
	match phase:
		Phase.DEAD:
			sweep_open = false
			return
		Phase.IDLE:
			_tick_idle(delta)
		Phase.WINDUP:
			_tick_windup(delta)
		Phase.SWING:
			_tick_swing(delta)
		_:
			_tick_timed(delta)
	sweep_open = (was_swinging or phase == Phase.SWING) and not hit_consumed
	live_value = _live_value() if sweep_open else -1.0
	if not was_swinging:
		prev_live_value = live_value

func _tick_idle(delta: float) -> void:
	if not guarding and since_pressure > posture_recovery_delay:
		posture = maxf(0.0, posture - posture_recovery_rate * delta)
	if guard_delay > 0.0:
		guard_delay = maxf(0.0, guard_delay - delta)
		omega = 0.0
		return
	if buffered != "" and not guarding:
		var next := buffered
		var was_released := buffer_released
		buffered = ""
		if not _charge_attack():
			return # Refused when the windup would start; recorded by the pool.
		_begin_windup(next)
		released = was_released
		_tick_windup(delta)
		return
	if guarding:
		_shift_toward(Geometry.guard_pose(guard, t), h.guard_shift, delta)
	else:
		_shift_toward(Geometry.rest_pose(t), h.guard_shift * 0.5, delta)

func _tick_windup(delta: float) -> void:
	windup_time += delta
	if not released:
		hold_time += delta
	if rechamber_to_neutral:
		# Retract toward the forward neutral pose before crossing to another side.
		# The alternate direct great-circle route can pass behind the body.
		if _move_bang_bang(Geometry.rest_pose(t), delta):
			rechamber_to_neutral = false
			move_speed = 0.0
		return
	var arrived := _move_bang_bang(Geometry.chamber_pose(direction, t), delta)
	if arrived and windup_time >= t.min_windup and released:
		phase = Phase.SWING
		swing_serial += 1
		hit_consumed = false
		last_swung = direction
		move_speed = 0.0
		if direction == Geometry.THRUST:
			extension = 0.0
			thrust_speed = 0.0
		else:
			theta = Geometry.swing_start(t)
			omega = 0.0

func _tick_swing(delta: float) -> void:
	if direction == Geometry.THRUST:
		thrust_speed = minf(thrust_speed + h.thrust_accel * delta, t.max_thrust_speed)
		extension = minf(t.thrust_extension, extension + thrust_speed * delta)
		var pose := Geometry.thrust_pose(extension, t)
		hand = pose.hand
		dir = pose.dir
		if extension >= t.thrust_extension:
			_enter_recovery(t.thrust_retract + thrust_speed / (h.thrust_accel * t.brake_ratio))
		return
	omega = minf(omega + h.accel * delta, h.max_speed)
	var end := Geometry.swing_end(direction, t)
	theta = maxf(end, theta - omega * delta)
	var pose := Geometry.swing_pose(direction, theta, t)
	hand = pose.hand
	dir = pose.dir
	if theta <= end:
		# A miss carries the blade's full speed into the stop.
		_enter_recovery(t.recovery_base + omega / h.brake)

func _tick_timed(delta: float) -> void:
	remaining -= delta
	if phase == Phase.ROLL:
		roll_elapsed += delta
	if phase == Phase.RECOVERY:
		omega = maxf(0.0, omega - h.brake * delta)
		thrust_speed = maxf(0.0, thrust_speed - h.thrust_accel * t.brake_ratio * delta)
		if direction == Geometry.THRUST:
			_shift_toward(Geometry.thrust_pose(0.0, t), h.guard_shift, delta)
	elif not evading():
		_shift_toward(Geometry.rest_pose(t), h.guard_shift * 0.5, delta)
	if remaining > 0.0:
		return
	if phase == Phase.BROKEN:
		posture = 0.0
	phase = Phase.IDLE
	remaining = 0.0
	omega = 0.0
	thrust_speed = 0.0
	# A guard still held after an action raises again, but cannot deflect.
	guarding = guard_input_held and h.can_guard
	guard_age = 99.0

func _live_value() -> float:
	if direction == Geometry.THRUST:
		return extension - t.thrust_live_extension
	return Geometry.swing_live(t) - theta

func _begin_windup(chosen: String) -> void:
	rechamber_to_neutral = false
	phase = Phase.WINDUP
	direction = chosen
	windup_time = 0.0
	hold_time = 0.0
	released = false
	hit_consumed = false
	move_speed = 0.0
	guard_delay = 0.0
	buffer_released = false

func _enter_recovery(duration: float) -> void:
	phase = Phase.RECOVERY
	remaining = duration
	attack_paid = 0.0

## Ends any attack. Never refunds by itself: voluntary cancels add `pending_refund()`
## before calling this; interruptions (hits, stagger, guard break, death) refund nothing.
func _cancel_attack() -> void:
	rechamber_to_neutral = false
	attack_paid = 0.0
	if phase not in [Phase.WINDUP, Phase.SWING, Phase.RECOVERY]:
		return
	phase = Phase.IDLE
	remaining = 0.0
	released = false
	hit_consumed = true
	omega = 0.0
	thrust_speed = 0.0
	move_speed = 0.0

## Accelerate/brake the pose along the great circle toward `target` (bang-bang under the
## weapon's angular acceleration and speed cap). Returns true once arrived.
func _move_bang_bang(target: Dictionary, delta: float) -> bool:
	var angle := dir.angle_to(target.dir)
	if angle <= ARRIVED:
		dir = target.dir
		hand = hand.move_toward(target.hand, 4.0 * delta)
		move_speed = 0.0
		return hand.distance_to(target.hand) < 0.001
	if move_speed * move_speed / (2.0 * h.accel) >= angle:
		move_speed = maxf(move_speed - h.accel * delta, h.accel * delta)
	else:
		move_speed = minf(move_speed + h.accel * delta, h.max_speed)
	_step_pose(target, move_speed * delta)
	return false

## Constant angular rate shift (guard changes, returning to rest).
func _shift_toward(target: Dictionary, rate: float, delta: float) -> void:
	if dir.angle_to(target.dir) <= ARRIVED:
		dir = target.dir
		hand = hand.move_toward(target.hand, 4.0 * delta)
		return
	_step_pose(target, rate * delta)

func _step_pose(target: Dictionary, step: float) -> void:
	var angle := dir.angle_to(target.dir)
	var fraction := minf(1.0, step / angle)
	var from_dir := dir
	dir = from_dir.slerp(target.dir, fraction).normalized() if angle < PI - 0.01 else _rotate_past_antipode(from_dir, target.dir, step)
	hand = hand.lerp(target.hand, fraction)
	if fraction >= 1.0:
		dir = target.dir

## Slerp is undefined for opposite vectors; rotate about the vertical (or right) axis.
func _rotate_past_antipode(from_dir: Vector3, to_dir: Vector3, step: float) -> Vector3:
	var axis := from_dir.cross(Vector3.UP)
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	return from_dir.rotated(axis.normalized(), minf(step, from_dir.angle_to(to_dir)))

## --- Outcomes applied by the contact solver ---------------------------------------

func snap_pose(pose: Dictionary) -> void:
	hand = pose.hand
	dir = pose.dir

func add_posture(amount: float) -> void:
	posture = minf(max_posture, posture + amount)
	since_pressure = 0.0
	if posture >= max_posture and phase not in [Phase.DEAD, Phase.BROKEN]:
		break_guard()

func break_guard() -> void:
	_cancel_attack()
	phase = Phase.BROKEN
	remaining = t.broken_duration
	guarding = false
	guard_age = 99.0
	posture = max_posture
	last_event = "GUARD BREAK"

## Periodic status damage. `can_kill` false leaves the fighter at 1 health at worst.
func take_status_damage(amount: float, can_kill: bool) -> void:
	var floor_health := 0.0 if can_kill else minf(health, 1.0)
	var dealt := maxf(0.0, minf(amount, health - floor_health))
	status_damage_taken += dealt
	if dealt > 0.0:
		take_damage(dealt)

## Routes a contact's status sources through the outcome table, then resistance and
## buildup (status_effects.gd). An evaded attack or a missing outcome applies nothing,
## whatever the data says. Returns the buildup actually applied per effect.
func receive_status(sources: Array, outcome: String, from: String) -> Dictionary:
	var applied := {}
	if outcome == "evaded" or outcome == "none" or phase == Phase.DEAD:
		return applied
	var scale := float(resources.routing.get(outcome, 0.0))
	if scale <= 0.0:
		return applied
	for source: Dictionary in sources:
		if source.route == "on_hit":
			applied[source.effect] = applied.get(source.effect, 0.0) + status.add_buildup(source.effect, source.buildup * scale, from)
	return applied

## Environmental buildup per second (world conditions). Not avoidable by evading.
func receive_ambient(sources: Array, delta: float, from: String) -> void:
	if phase == Phase.DEAD:
		return
	for source: Dictionary in sources:
		if source.route == "ambient":
			status.add_buildup(source.effect, source.buildup_per_second * delta, from)

func _set_handling_scale(scale: float) -> void:
	if is_equal_approx(scale, handling_scale):
		return
	handling_scale = scale
	if is_equal_approx(scale, 1.0):
		h = base_h
		return
	h = base_h.duplicate()
	for key: String in ["accel", "brake", "guard_shift", "turn_rate", "thrust_accel"]:
		h[key] = base_h[key] * scale

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_cancel_attack()
		phase = Phase.DEAD
		guarding = false
		last_event = "DEFEATED"

func stagger(duration: float) -> void:
	if phase in [Phase.DEAD, Phase.BROKEN]:
		return
	var lockout := remaining if phase == Phase.STAGGER else 0.0
	_cancel_attack()
	buffered = ""
	guarding = false
	guard_age = 99.0
	phase = Phase.STAGGER
	remaining = maxf(lockout, duration)

## The attacker's blade was stopped (blocked, deflected or clashed).
func recoil(duration: float, as_recovery: bool) -> void:
	if phase in [Phase.DEAD, Phase.BROKEN]:
		return
	hit_consumed = true
	omega = 0.0
	thrust_speed = 0.0
	if as_recovery:
		phase = Phase.RECOVERY
	else:
		phase = Phase.RECOIL
	remaining = duration
