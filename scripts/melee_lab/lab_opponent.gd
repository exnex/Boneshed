extends "res://scripts/melee_lab/lab_duelist.gd"
## Contained, scripted lab opponent. It sees only what is drawn — the player's phase,
## the chamber its blade is moving to, whether the chamber is reached, and the guard
## side — and only after `ai_reaction_delay` (same principle as the production
## opponent_perception.gd, reimplemented for the lab's directional cues). It never
## reads input, the aim cursor, `released`, or future timing. All choices use one
## seeded stream, so a duel replays identically.
##
## Modes (M cycles): duel · defend (never attacks) · attack (never guards) · dummy
## (holds the guard chosen with G, or none).

const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")
const MODES := ["duel", "defend", "attack", "dummy"]
const DUMMY_GUARDS := ["", "right", "high_right", "high", "high_left", "left", "center"]
const SEED := 20261020

var mode := "duel"
var dummy_guard := ""
var rng := RandomNumberGenerator.new()
var reaction_delay := 0.22
var clock := 0.0
var samples: Array[Dictionary] = []
var seen: Dictionary = {}
var seen_swings := 0
var plan_swing := -1
var guard_sector := "high"
var deflect_try := false
var misread := false
var wrong_sector := "high"
var press_at := -1.0
var linger := 0.0
var cooldown := 0.6
var hold_for := 0.0
var counter_ready := false
var strafe := 1.0
var strafe_time := 0.0
var recent: Array[String] = []
var trace: Array[Dictionary] = []

func _ready() -> void:
	body_color = Color("9a6f66")
	super._ready()
	reset_ai()

func reset_ai(seed_value := SEED) -> void:
	rng.seed = seed_value
	reaction_delay = tuning.get("ai_reaction_delay", 0.22)
	clock = 0.0
	samples.clear()
	seen = {"t": -1.0, "phase": State.Phase.IDLE, "direction": "", "chambered": false, "guarding": false, "guard": "high"}
	seen_swings = 0
	plan_swing = -1
	deflect_try = false
	misread = false
	press_at = -1.0
	linger = 0.0
	cooldown = 0.6
	hold_for = 0.0
	counter_ready = false
	strafe = 1.0
	strafe_time = 0.0
	recent.clear()
	trace.clear()

## What is on screen this tick. Direction is visible once the blade heads for a chamber.
static func capture(foe: CharacterBody3D, at: float) -> Dictionary:
	var s: State = foe.state
	var attacking := s.phase in [State.Phase.WINDUP, State.Phase.SWING]
	return {"t": at, "phase": s.phase, "direction": s.direction if attacking else "",
		"chambered": s.phase == State.Phase.WINDUP and s.chamber_angle() < 0.05,
		"guarding": s.guarding, "guard": s.guard}

func observe(delta: float) -> Dictionary:
	clock += delta
	samples.append(capture(opponent, clock))
	while not samples.is_empty() and clock - samples[0].t >= reaction_delay - 0.0001:
		var view: Dictionary = samples.pop_front()
		if view.phase == State.Phase.WINDUP and seen.phase != State.Phase.WINDUP:
			seen_swings += 1
		seen = view
	return seen

func _log(event: String, detail := {}) -> void:
	var entry := {"t": snappedf(clock, 0.0001), "event": event}
	entry.merge(detail)
	trace.append(entry)

## Felt (not seen) outcome of the player's attack on this opponent.
func note_defended(result: String) -> void:
	if result in ["block", "deflect"] and mode == "duel" and rng.randf() < tuning.ai_counter_chance:
		counter_ready = true
		_log("counter_ready", {"after": result})

func control(delta: float) -> void:
	var view := observe(delta)
	cooldown = maxf(0.0, cooldown - delta)
	_move(delta)
	turn_toward(toward_opponent(), delta)
	if mode == "dummy":
		state.set_guard(dummy_guard != "", dummy_guard)
		return
	var threat: bool = view.phase in [State.Phase.WINDUP, State.Phase.SWING] and view.direction != ""
	if mode != "attack" and threat and not counter_ready:
		_defend(view)
	else:
		_attack(view, delta)

func _defend(view: Dictionary) -> void:
	var correct := Geometry.classify_guard(_arrival(view.direction), 0.0)
	if seen_swings != plan_swing:
		plan_swing = seen_swings
		deflect_try = state.h.can_deflect and rng.randf() < tuning.ai_deflect_attempt
		misread = rng.randf() >= tuning.ai_guard_accuracy
		var options: Array = Geometry.GUARDS.keys() + [Geometry.CENTER_GUARD]
		options.erase(correct)
		wrong_sector = options[rng.randi_range(0, options.size() - 1)]
		press_at = -1.0
		if state.phase == State.Phase.WINDUP and not state.released:
			_log("abort_attack")
		_log("read_swing", {"direction": view.direction, "deflect_try": deflect_try, "misread": misread})
	# Re-read the side every tick: a late redirect is only seen after the delay.
	guard_sector = wrong_sector if misread else correct
	linger = 0.3
	if deflect_try:
		# Timed press: wait until the chamber is seen reached (or the swing is seen).
		if press_at < 0.0 and (view.chambered or view.phase == State.Phase.SWING):
			press_at = clock + rng.randf_range(0.0, 0.08)
		var pressing := press_at >= 0.0 and clock >= press_at
		state.set_guard(pressing, guard_sector)
	else:
		state.set_guard(true, guard_sector)

## Side an attack direction arrives on, in this fighter's own cursor space.
static func _arrival(direction: String) -> Vector2:
	if direction == Geometry.THRUST:
		return Vector2(0.0, -1.0)
	var c := Geometry.chamber_vector(direction)
	return Vector2(-c.x, c.y)

func _attack(view: Dictionary, delta: float) -> void:
	linger = maxf(0.0, linger - delta)
	if state.phase == State.Phase.WINDUP:
		if state.windup_time >= hold_for:
			state.release_attack()
		return
	var hold_guard: bool = mode != "attack" and linger > 0.0 and not counter_ready
	state.set_guard(hold_guard, guard_sector)
	if mode == "defend" or state.phase != State.Phase.IDLE or state.guarding:
		return
	var distance := global_position.distance_to(opponent.global_position)
	if distance > state.h.reach + 0.5 or (cooldown > 0.0 and not counter_ready):
		return
	var direction := _choose_direction(view)
	state.press_attack(direction)
	hold_for = tuning.ai_min_windup + rng.randf() * tuning.ai_hold_max
	cooldown = tuning.ai_attack_interval + rng.randf() * 0.5
	_log("attack", {"direction": direction, "hold": snappedf(hold_for, 0.0001), "counter": counter_ready})
	counter_ready = false

## Prefer a side the visible guard does not cover; never the same cut three times running.
func _choose_direction(view: Dictionary) -> String:
	var options: Array[String] = []
	for direction: String in Geometry.DIRECTIONS:
		if recent.size() >= 2 and recent[-1] == direction and recent[-2] == direction:
			continue
		if view.guarding and rad_to_deg(absf(Geometry.guard_vector(view.guard).angle_to(_arrival(direction)))) <= tuning.block_align_deg:
			continue
		options.append(direction)
	if options.is_empty():
		options.assign(Geometry.DIRECTIONS)
	var direction: String = options[rng.randi_range(0, options.size() - 1)]
	recent.append(direction)
	if recent.size() > 3:
		recent.pop_front()
	return direction

## Hold a spacing just inside reach, strafing on a seeded rhythm.
func _move(delta: float) -> void:
	var toward := toward_opponent()
	var distance := global_position.distance_to(opponent.global_position)
	var ideal: float = state.h.reach * 0.85
	strafe_time -= delta
	if strafe_time <= 0.0:
		strafe = -strafe if rng.randf() < 0.5 else strafe
		strafe_time = rng.randf_range(0.8, 1.8)
	var gap := distance - ideal
	var radial := 0.0 if absf(gap) < 0.2 else clampf(gap * 2.0, -1.0, 1.0)
	var side := toward.cross(Vector3.UP) * strafe * 0.3
	# Footwork at roughly half pace keeps spacing readable instead of lunging through it.
	desired_move = ((toward * radial + side).limit_length(1.0) * 0.55) if mode != "dummy" else Vector3.ZERO
