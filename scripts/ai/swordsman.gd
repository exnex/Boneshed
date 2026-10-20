extends "res://scripts/characters/fighter.gd"
## Survival-minded controller for the corrupted swordsman. It reads a delayed view of
## the opponent (ai/opponent_perception.gd) plus its own felt contacts, then issues the
## same intent calls as player input: set_guard, try_dodge, attack, attack_special and
## desired_move. It never writes rule fields. Each perceived swing gets one committed
## answer (guard, evade or backstep); openings after a block, a whiff or a posture
## break may be punished. Every random choice draws from one seeded stream and every
## decision is appended to `trace`. All weights, distances and delays are provisional.

const Perception = preload("res://scripts/ai/opponent_perception.gd")
enum Intent { WAIT, APPROACH, MEASURE, CIRCLE, ATTACK, COUNTER, GUARD, EVADE, BACKSTEP, RETREAT, ATTACK_FOOTWORK }
## Debug labels for the HUD and fixtures; behavior never branches on them.
const LABELS := {Intent.WAIT: "WAIT", Intent.APPROACH: "APPROACH", Intent.MEASURE: "MEASURE",
	Intent.CIRCLE: "CIRCLE", Intent.ATTACK: "ATTACK", Intent.COUNTER: "COUNTER", Intent.GUARD: "GUARD",
	Intent.EVADE: "EVADE", Intent.BACKSTEP: "BACKSTEP", Intent.RETREAT: "RETREAT",
	Intent.ATTACK_FOOTWORK: "ATTACK FOOTWORK"}
enum Answer { NONE, GUARD, EVADE, BACKSTEP }
const ANSWER_NAMES := {Answer.NONE: "none", Answer.GUARD: "guard", Answer.EVADE: "evade", Answer.BACKSTEP: "backstep"}
const TRACE_LIMIT := 800

@export var detection_range := 18.0
@export var preferred_distance := 1.85
@export var attack_interval := 0.65
@export var attack_strafe := 0.45 # Fraction of move speed; provisional visible footwork.
@export_group("Survival AI (provisional)")
@export var reaction_delay := 0.18 # Seconds before any opponent action cue is visible to the AI.
@export var hesitation := 0.06 # Extra per-decision delay, drawn from [0, hesitation].
@export var dodge_lead := 0.14 # Dodge this long before the estimated contact.
@export var max_evade_streak := 2 # Consecutive dodges before another answer is required.
@export var repeat_penalty := 0.5 # Appeal multiplier per consecutive repeat of one answer.
@export var counter_chance := 0.75
@export var trade_margin := 0.05 # Seconds of slack required to win a timing race.
@export var reckless := 2.5 # Recent-swing score above which the opponent is treated as a flurry.
@export var aggression_memory := 4.0 # Score cap; with 0.35/s decay a flurry is forgotten in ~6 s.
@export var patience := 1.5 # Longest wait before attacking into a flurry anyway.
@export var intercept_speed := 1.5 # Visible closing speed (m/s) that makes a timed swing worthwhile.
@export var counter_window := 0.9 # Seconds a counter opportunity stays open.
@export var strained_posture := 0.55 # Posture ratio where blocking becomes a last resort.
@export var recovered_posture := 0.3
@export var retreat_limit := 2.8 # Long enough for posture recovery (1.5 s delay) to start.
@export var retreat_rest := 4.0 # Seconds before another retreat; guarantees re-engagement.
@export var safety_margin := 0.5 # Beyond the opponent's visible reach while retreating.
@export var abort_chance := 0.5 # Cancel an uncommitted windup that would lose the race.
@export var recovery_guard_chance := 0.45 # Guard-cancel recovery against a visible reply.
@export var abort_rest := 2.5 # Seconds between any two cancels into guard.
@export var ai_seed := 20261020
@export_group("")

var enabled := true
var cooldown := 0.8
var attack_number := 0
var ai_state := "WAIT"
var intent: Intent = Intent.WAIT
var defense_enabled := true
var counter_pending := false
var observed_event := 0
var perception := Perception.new()
var rng := RandomNumberGenerator.new()
var trace: Array[Dictionary] = []
var tick_count := 0
var answered_swing := 0
var answer: Answer = Answer.NONE
var answer_at := 0.0
var last_answer: Answer = Answer.NONE
var answer_streak := 0
var counter_heavy := true
var counter_at := 0.0
var counter_until := 0.0
var counter_streak := 0
var counter_in_flight := false
var counters_deflected := 0
var counters_blocked := 0
var ready_since := -1.0
var punished_swing := 0
var punished_break := false
var strafe_sign := 1.0
var strafe_switch_at := 0.0
var retreat_until := -1.0
var next_retreat_at := 0.0
var aborts_ready_at := 0.0
var abort_considered := -1
var hurt_at := -99.0
var aggression := 0.0 # Decaying, capped count of perceived opponent swings.
var seen_swing := 0
var _opponent_events := 0 # Contacts this fighter's own blade made, felt through the weapon.
var range_lunge_rolled := false # One roll per attack-ready window.
var previous_phase: Rules.Phase = Rules.Phase.IDLE

func _ready() -> void:
	body_color = Color("9b5265")
	super._ready()
	_reset_mind()

func _physics_process(delta: float) -> void:
	desired_move = Vector3.ZERO
	tick_count += 1
	var active: bool = enabled and is_instance_valid(opponent) and opponent.combat.phase != Rules.Phase.DEAD and combat.phase != Rules.Phase.DEAD
	if active:
		var seen := perception.observe(opponent, delta)
		_feel(seen)
		_track_opponent(seen, delta)
		var toward := opponent.global_position - global_position
		toward.y = 0.0
		var distance := toward.length()
		if combat.phase == Rules.Phase.IDLE:
			cooldown = maxf(0.0, cooldown - delta)
			if distance < detection_range:
				facing = toward.normalized()
				_idle(seen, toward, distance)
			else:
				combat.set_guard(false)
				_set_intent(Intent.WAIT)
		elif combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			_attack_footwork(seen, toward, distance, delta)
	else:
		_set_intent(Intent.WAIT)
	previous_phase = combat.phase
	if not enabled or combat.phase != Rules.Phase.IDLE or not is_instance_valid(opponent) or opponent.combat.phase == Rules.Phase.DEAD:
		combat.set_guard(false)
	super._physics_process(delta)

func reset_at(point: Vector3, guard_held := false) -> void:
	super.reset_at(point)
	cooldown = 0.8
	attack_number = 0
	counter_pending = false
	observed_event = 0
	_set_intent(Intent.WAIT)
	facing = Vector3.BACK
	_reset_mind()

func _reset_mind() -> void:
	perception.reaction_delay = reaction_delay
	perception.reset()
	rng.seed = ai_seed
	trace.clear()
	tick_count = 0
	answered_swing = 0
	answer = Answer.NONE
	last_answer = Answer.NONE
	answer_streak = 0
	counter_heavy = true
	counter_until = 0.0
	counter_at = 0.0
	counter_streak = 0
	counter_in_flight = false
	counters_deflected = 0
	counters_blocked = 0
	ready_since = -1.0
	punished_swing = 0
	punished_break = false
	strafe_sign = 1.0
	strafe_switch_at = 0.0
	retreat_until = -1.0
	next_retreat_at = 0.0
	aborts_ready_at = 0.0
	abort_considered = -1
	hurt_at = -99.0
	aggression = 0.0
	seen_swing = 0
	_opponent_events = 0
	range_lunge_rolled = false
	previous_phase = Rules.Phase.IDLE

# --- Perception and felt contact ----------------------------------------------

func _feel(seen: Dictionary) -> void:
	var now := perception.clock
	# A swing that ends in recoil without a contact on this fighter was deflected.
	if previous_phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE] and combat.phase == Rules.Phase.STAGGER and event_serial == observed_event:
		if counter_in_flight:
			counters_deflected += 1
		counter_in_flight = false
		_decide("own_attack_deflected", {"counters_deflected": counters_deflected})
	if combat.phase == Rules.Phase.IDLE and previous_phase == Rules.Phase.RECOVERY:
		counter_in_flight = false
	if event_serial == observed_event:
		return
	observed_event = event_serial
	perception.note_contact()
	if last_result == Rules.GUARD and defense_enabled:
		_offer_counter("blocked", seen, global_position.distance_to(opponent.global_position))
	elif last_result in [Rules.HIT, "punish"]:
		hurt_at = now
		counter_pending = false
	_decide("felt_" + last_result, {"health": snappedf(combat.health, 0.01), "posture": snappedf(combat.posture, 0.01)})

func _track_opponent(seen: Dictionary, delta: float) -> void:
	aggression = maxf(0.0, aggression - delta * 0.35)
	if perception.swing != seen_swing:
		seen_swing = perception.swing
		aggression = minf(aggression + 1.0, aggression_memory)
		_decide("saw_windup", {"swing": seen_swing, "binding": seen.binding, "remaining": snappedf(seen.remaining, 0.001), "aggression": snappedf(aggression, 0.01)})
	if seen.phase != Rules.Phase.BROKEN:
		punished_break = false
	# Learn from how our counters fared: landed ones restore confidence.
	if counter_in_flight and opponent.event_serial != _opponent_events:
		match opponent.last_result:
			Rules.GUARD:
				counters_blocked += 1
			Rules.HIT, Rules.DEFEATED, "punish":
				counters_blocked = 0
				counters_deflected = 0
	_opponent_events = opponent.event_serial

func _threatened(seen: Dictionary, distance: float) -> bool:
	if not perception.attacking(seen) or perception.last_contact_at >= perception.swing_started_at:
		return false
	# Bodies are tracked live, so include how fast the attacker is visibly closing.
	var away := (global_position - opponent.global_position) * Vector3(1, 0, 1)
	var closing := maxf(0.0, opponent.velocity.dot(away.normalized())) * minf(perception.contact_in(seen), 0.6)
	return distance <= float(seen.reach) + closing + 0.35

# --- Idle decisions -------------------------------------------------------------

func _idle(seen: Dictionary, toward: Vector3, distance: float) -> void:
	var now := perception.clock
	var threatened := defense_enabled and _threatened(seen, distance)
	if threatened:
		if answered_swing != perception.swing:
			_choose_answer(seen, distance)
		_answer(seen, toward, distance)
		return
	combat.set_guard(false)
	if not defense_enabled:
		_offense(seen, toward, distance, false)
		return
	_look_for_openings(seen, distance)
	if counter_pending and now > counter_until:
		counter_pending = false
		_decide("counter_expired", {})
	if not counter_pending and _retreating(seen, toward, distance):
		return
	_offense(seen, toward, distance, counter_pending)

func _choose_answer(seen: Dictionary, distance: float) -> void:
	answered_swing = perception.swing
	var contact := perception.contact_in(seen)
	var strained := combat.posture / combat.max_posture >= strained_posture
	var hurt := perception.clock - hurt_at < 1.5
	var binding: String = seen.binding
	var weights := {Answer.GUARD: 1.0, Answer.EVADE: {"light": 0.6, "heavy": 1.0, "special": 1.4}.get(binding, 0.6), Answer.BACKSTEP: 0.0}
	if strained:
		weights[Answer.GUARD] *= 0.3
		weights[Answer.EVADE] *= 1.8
	if binding == "special":
		weights[Answer.GUARD] *= 0.5 # The lunge's guard pressure is far above a sword's.
	if hurt:
		weights[Answer.EVADE] *= 1.4
	if aggression >= reckless and not strained:
		# Dodging a flurry only resets it; a block earns the poised counter.
		weights[Answer.EVADE] *= 0.5
	var away := (global_position - opponent.global_position) * Vector3(1, 0, 1)
	var closing := maxf(0.0, opponent.velocity.dot(away.normalized()))
	var travel := move_speed * maxf(0.0, contact - 0.05) - closing * contact
	if distance + travel > float(seen.reach) + 0.2:
		weights[Answer.BACKSTEP] = 0.8
	if combat.dodge_ready_in > maxf(0.0, contact - dodge_lead):
		weights[Answer.EVADE] = 0.0
	# Variety: each repeat of the same answer loses appeal; dodges are capped.
	if last_answer != Answer.NONE:
		weights[last_answer] *= pow(repeat_penalty, answer_streak)
	if last_answer == Answer.EVADE and answer_streak >= max_evade_streak:
		weights[Answer.EVADE] = 0.0
	var total: float = weights.values().reduce(func(sum: float, w: float) -> float: return sum + w, 0.0)
	var roll := rng.randf()
	answer = Answer.GUARD
	if total > 0.0:
		var pick := roll * total
		for option: Answer in [Answer.GUARD, Answer.EVADE, Answer.BACKSTEP]:
			pick -= weights[option]
			if pick < 0.0:
				answer = option
				break
	answer_streak = answer_streak + 1 if answer == last_answer else 1
	last_answer = answer
	answer_at = perception.clock + rng.randf() * hesitation
	_decide("answer_" + ANSWER_NAMES[answer], {"swing": answered_swing, "binding": binding, "contact_in": snappedf(contact, 0.001),
		"distance": snappedf(distance, 0.01), "strained": strained, "roll": snappedf(roll, 0.0001),
		"weights": {"guard": snappedf(weights[Answer.GUARD], 0.001), "evade": snappedf(weights[Answer.EVADE], 0.001), "backstep": snappedf(weights[Answer.BACKSTEP], 0.001)},
		"streak": answer_streak, "at": snappedf(answer_at, 0.001)})

func _answer(seen: Dictionary, toward: Vector3, distance: float) -> void:
	var ready := perception.clock >= answer_at
	match answer:
		Answer.GUARD:
			combat.set_guard(ready, false)
			_set_intent(Intent.GUARD)
		Answer.EVADE:
			combat.set_guard(false)
			_set_intent(Intent.EVADE)
			if ready and perception.contact_in(seen) <= dodge_lead:
				var side := _clear_side(toward)
				var direction := (-toward.normalized() * 0.55 + toward.normalized().cross(Vector3.UP) * side).normalized()
				if try_dodge(direction):
					_decide("dodge", {"swing": answered_swing, "side": side, "contact_in": snappedf(perception.contact_in(seen), 0.001)})
				else:
					# Committed answers do not fall back: a mistimed read is punishable.
					_decide("dodge_unavailable", {"swing": answered_swing})
		Answer.BACKSTEP:
			combat.set_guard(false)
			_set_intent(Intent.BACKSTEP)
			if ready:
				var back := -toward.normalized()
				if _blocked(back, 1.2):
					back = toward.normalized().cross(Vector3.UP) * _clear_side(toward)
				desired_move = back

func _look_for_openings(seen: Dictionary, distance: float) -> void:
	if seen.phase == Rules.Phase.BROKEN and not punished_break:
		punished_break = true
		_offer_counter("broken", seen, distance, true)
	elif seen.phase == Rules.Phase.RECOVERY and perception.swing_missed() and punished_swing != perception.swing and distance <= AttackModules.SWORD_REACH + 1.2:
		punished_swing = perception.swing
		_offer_counter("whiff", seen, distance)

## Which sword attack can win the race against the opponent's quickest reply:
## a light must land first; a heavy must at least reach its poised commitment.
func _race(seen: Dictionary, distance: float) -> Dictionary:
	var approach := maxf(0.0, distance - AttackModules.SWORD_REACH) / maxf(move_speed, 0.1)
	var earliest := perception.earliest_contact(seen) - hesitation - approach - trade_margin
	return {"light": combat.attack_windup <= earliest, "heavy": combat.heavy_windup - combat.commitment_duration <= earliest,
		"slack": snappedf(earliest, 0.001)}

func _offer_counter(reason: String, seen: Dictionary, distance: float, certain := false) -> void:
	var strained := combat.posture / combat.max_posture >= strained_posture
	var race := _race(seen, distance)
	var chance := counter_chance * pow(0.7, counters_deflected) * pow(0.85, counters_blocked) * (0.6 if strained else 1.0)
	if aggression >= reckless:
		chance = maxf(chance, 0.9) # Punishing reckless swings is the point of a counter.
	if certain:
		chance = 1.0
	if not (race.light or race.heavy):
		chance = 0.0
	var roll := rng.randf()
	var go := roll < chance
	if go:
		counter_pending = true
		cooldown = 0.0
		# A broken opponent cannot answer, and heavy poise wins trades against one who
		# keeps swinging; otherwise the faster light is the honest punish.
		counter_heavy = certain or not race.light or (race.heavy and (aggression >= reckless or roll < chance * 0.6))
		counter_at = perception.clock + rng.randf() * hesitation
		counter_until = perception.clock + counter_window
	_decide("counter_" + ("take" if go else "skip"), {"reason": reason, "chance": snappedf(chance, 0.001), "roll": snappedf(roll, 0.0001),
		"heavy": counter_heavy if go else false, "race": race, "opponent_phase": Rules.Phase.keys()[seen.phase]})

func _retreating(seen: Dictionary, toward: Vector3, distance: float) -> bool:
	var now := perception.clock
	var ratio := combat.posture / combat.max_posture
	var exposed: bool = seen.phase in [Rules.Phase.BROKEN, Rules.Phase.STAGGER]
	if retreat_until >= 0.0:
		if ratio <= recovered_posture or now >= retreat_until or exposed:
			retreat_until = -1.0
			next_retreat_at = now + retreat_rest
			_decide("reengage", {"posture": snappedf(ratio, 0.001)})
			return false
	elif now >= next_retreat_at and not exposed and (ratio >= strained_posture or (combat.health / combat.max_health < 0.4 and now - hurt_at < 1.0)):
		retreat_until = now + retreat_limit
		_decide("retreat", {"posture": snappedf(ratio, 0.001), "health": snappedf(combat.health, 0.01)})
	else:
		return false
	var reach := maxf(float(seen.reach), float(seen.signature_reach))
	var radial := toward.normalized()
	var tangent := radial.cross(Vector3.UP) * strafe_sign
	if _blocked(tangent, 1.0):
		strafe_sign = -strafe_sign
		tangent = -tangent
	var back := -radial if distance < reach + safety_margin else Vector3.ZERO
	if back != Vector3.ZERO and _blocked(back, 1.2):
		back = Vector3.ZERO
	desired_move = (back + tangent * 0.6).limit_length(1.0)
	_set_intent(Intent.RETREAT)
	return true

func _offense(seen: Dictionary, toward: Vector3, distance: float, countering: bool) -> void:
	var now := perception.clock
	if cooldown > 0.0 or countering:
		ready_since = -1.0
	var lunge_reach := float(combat.signature.reach) if not combat.signature.is_empty() else 0.0
	if cooldown <= 0.0 and not countering and not range_lunge_rolled and lunge_reach > 0.0 and distance > preferred_distance + 0.6 and distance <= lunge_reach - 0.3 and not perception.attacking(seen):
		# Use the visible bone reach against an opponent holding just outside sword range.
		range_lunge_rolled = true
		var roll := rng.randf()
		_decide("lunge_" + ("take" if roll < 0.4 else "skip"), {"distance": snappedf(distance, 0.01), "roll": snappedf(roll, 0.0001)})
		if roll < 0.4:
			combat.attack_special()
			attack_number += 1
			cooldown = _next_interval()
			range_lunge_rolled = false
			_set_intent(Intent.ATTACK)
			return
	if cooldown <= 0.0 and not countering and distance > preferred_distance and _intercept(seen, distance):
		return
	if distance > preferred_distance and not (countering and distance <= AttackModules.SWORD_REACH):
		_set_intent(Intent.APPROACH)
		desired_move = facing
	elif countering and now >= counter_at:
		combat.attack(counter_heavy)
		counter_pending = false
		counter_in_flight = true
		counter_streak += 1
		attack_number += 1
		cooldown = _next_interval()
		_decide("attack_counter", {"heavy": counter_heavy, "distance": snappedf(distance, 0.01), "streak": counter_streak})
		_set_intent(Intent.COUNTER)
	elif cooldown <= 0.0 and not countering and _hold_back(seen, distance):
		_circle(toward, distance)
	elif cooldown <= 0.0 and not countering:
		attack_number += 1
		var heavy_chance := 0.6 if perception.guard_held_for() > 1.0 else 0.3
		if aggression >= reckless:
			heavy_chance = 1.0 # Only poise survives a flurry.
		var roll := rng.randf()
		var kind := "light"
		if not combat.signature.is_empty() and attack_number % 4 == 1:
			combat.attack_special()
			kind = "special"
		else:
			combat.attack(roll < heavy_chance)
			kind = "heavy" if roll < heavy_chance else "light"
		counter_streak = 0
		range_lunge_rolled = false
		ready_since = -1.0
		cooldown = _next_interval()
		_decide("attack_" + kind, {"distance": snappedf(distance, 0.01), "roll": snappedf(roll, 0.0001), "heavy_chance": heavy_chance})
		_set_intent(Intent.ATTACK)
	elif countering:
		_set_intent(Intent.COUNTER)
	else:
		_circle(toward, distance)

## Meet an opponent who is visibly walking in: start a light swing early enough that
## the blade arrives as they cross into reach, instead of waiting for them to arrive.
func _intercept(seen: Dictionary, distance: float) -> bool:
	if perception.attacking(seen) or seen.phase == Rules.Phase.DODGE:
		return false
	var away := (global_position - opponent.global_position) * Vector3(1, 0, 1)
	var closing := opponent.velocity.dot(away.normalized())
	if closing < intercept_speed:
		return false
	# Both bodies keep moving through the windup: the opponent at its visible speed,
	# this fighter at its approach speed.
	var at_contact := distance - (closing + move_speed) * combat.attack_windup
	if at_contact < 0.9 or at_contact > AttackModules.SWORD_REACH - 0.15:
		return false
	attack_number += 1
	combat.attack(false)
	counter_streak = 0
	range_lunge_rolled = false
	ready_since = -1.0
	cooldown = _next_interval()
	_decide("attack_intercept", {"distance": snappedf(distance, 0.01), "closing": snappedf(closing, 0.01), "at_contact": snappedf(at_contact, 0.01)})
	_set_intent(Intent.ATTACK)
	return true

## Against a flurry, an ordinary windup that loses the race is an invitation to be
## interrupted: wait for a block to earn a counter, but never longer than `patience`.
func _hold_back(seen: Dictionary, distance: float) -> bool:
	if ready_since < 0.0:
		ready_since = perception.clock
	if aggression < reckless or perception.clock - ready_since >= patience:
		return false
	return not _race(seen, distance).heavy

func _circle(toward: Vector3, distance: float) -> void:
	var now := perception.clock
	var radial := toward.normalized()
	if now >= strafe_switch_at:
		strafe_sign = -1.0 if rng.randf() < 0.5 else 1.0
		strafe_switch_at = now + rng.randf_range(1.0, 2.2)
	var tangent := radial.cross(Vector3.UP) * strafe_sign
	if _blocked(tangent, 1.0):
		strafe_sign = -strafe_sign
		tangent = -tangent
	desired_move = (radial * clampf((distance - preferred_distance) * 2.0, -1.0, 1.0) + tangent * 0.5).limit_length(1.0)
	_set_intent(Intent.CIRCLE if desired_move.length_squared() > 0.04 else Intent.MEASURE)

# --- While attacking ------------------------------------------------------------

func _attack_footwork(seen: Dictionary, toward: Vector3, distance: float, delta: float) -> void:
	# An uncommitted windup that would lose the race to an incoming blade, or a
	# recovery that would be caught, may be cancelled into guard: the same fresh-guard
	# cancel the player has. One consideration per stage of each own swing.
	var stage := combat.attack_stage()
	var key := attack_number * 2 + int(stage == "recovery")
	if defense_enabled and stage in ["early", "recovery"] and abort_considered != key and _threatened(seen, distance):
		abort_considered = key
		var poised_before_contact := combat.heavy and stage == "early" and combat.remaining - combat.commitment_duration <= perception.contact_in(seen)
		if perception.clock >= aborts_ready_at and perception.contact_in(seen) < combat.remaining and not poised_before_contact:
			var roll := rng.randf()
			var abort := roll < (abort_chance if stage == "early" else recovery_guard_chance)
			_decide(("abort_" if stage == "early" else "recovery_guard_") + ("take" if abort else "skip"), {"own_remaining": snappedf(combat.remaining, 0.001), "contact_in": snappedf(perception.contact_in(seen), 0.001), "roll": snappedf(roll, 0.0001)})
			if abort:
				aborts_ready_at = perception.clock + abort_rest
				counter_in_flight = false
				combat.set_guard(true, false)
				answered_swing = perception.swing
				answer = Answer.GUARD
				answer_at = perception.clock
				_set_intent(Intent.GUARD)
				return
	# Keep working the distance and circling while swinging, including when
	# already in range. Both the visible body and hit volume follow facing.
	turn_toward(toward, delta)
	var radial := toward.normalized()
	var tangent := radial.cross(Vector3.UP) * (1.0 if attack_number % 2 == 0 else -1.0)
	desired_move = (radial * clampf((distance - preferred_distance) * 2.0, -1.0, 1.0) + tangent * attack_strafe).limit_length(1.0)
	_set_intent(Intent.ATTACK_FOOTWORK)

# --- Helpers --------------------------------------------------------------------

func _next_interval() -> float:
	return attack_interval * rng.randf_range(0.8, 1.6)

func _clear_side(toward: Vector3) -> float:
	var tangent := toward.normalized().cross(Vector3.UP)
	var side := strafe_sign
	if _blocked(tangent * side, 2.2):
		side = -side
	return side

func _blocked(direction: Vector3, length: float) -> bool:
	if not is_inside_tree() or direction.length_squared() < 0.0001:
		return false
	var from := global_position + Vector3.UP * 0.9
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * length, AttackModules.ENVIRONMENT_LAYER)
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _set_intent(value: Intent) -> void:
	intent = value
	ai_state = LABELS[value]

func _decide(kind: String, detail: Dictionary) -> void:
	var entry := {"tick": tick_count, "t": snappedf(perception.clock, 0.001), "decision": kind}
	entry.merge(detail)
	trace.append(entry)
	if trace.size() > TRACE_LIMIT:
		trace.pop_front()
