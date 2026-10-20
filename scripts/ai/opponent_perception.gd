extends RefCounted
## What a fighter can see of its opponent, delivered after a bounded reaction delay.
## A snapshot holds only rendered cues: rule phase and rule time (the key poses are
## sampled from exactly these, see presentation/pose_sampler.gd), the visible attack
## kind, its frame data and blade/bone reach, guard and dodge stance, and the HUD
## health/posture bars. Frame data (phase lengths, quickest windup) is the same
## public knowledge a practiced player has; it never says what will be pressed next.
## It never holds input, intent (desired_move), hit_consumed, cooldowns or AI state,
## so a controller cannot react to anything before it has been on screen for
## reaction_delay seconds. Spacing reads live positions: bodies are tracked
## continuously, while discrete action onsets are what reaction time governs.

const Rules = preload("res://scripts/combat/combat_state.gd")
const AttackModules = preload("res://scripts/combat/attack_modules.gd")
## The complete snapshot schema. Tests assert nothing else is captured.
const FIELDS := ["t", "phase", "remaining", "binding", "windup", "active", "recovery", "quickest",
	"reach", "signature_reach", "guarding", "posture", "health", "facing"]
const EPSILON := 0.0001

var reaction_delay := 0.18 # Seconds; provisional, roughly a trained human's visual reaction.
var clock := 0.0
## Perceived opponent swings, counted when a new windup becomes visible.
var swing := 0
var swing_started_at := -1.0
var guard_seen_since := -1.0
var last_contact_at := -99.0
var _samples: Array[Dictionary] = []
var _seen: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	clock = 0.0
	swing = 0
	swing_started_at = -1.0
	guard_seen_since = -1.0
	last_contact_at = -99.0
	_samples.clear()
	_seen = unseen()

static func unseen() -> Dictionary:
	return {"t": -1.0, "phase": Rules.Phase.IDLE, "remaining": 0.0, "binding": "none", "windup": 0.0,
		"active": 0.0, "recovery": 0.0, "quickest": 0.34, "reach": AttackModules.SWORD_REACH, "signature_reach": 0.0, "guarding": false, "posture": 0.0,
		"health": 1.0, "facing": Vector3.ZERO}

static func capture(opponent: Fighter, at: float) -> Dictionary:
	var c: Rules = opponent.combat
	var attacking := c.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]
	return {"t": at, "phase": c.phase, "remaining": c.remaining,
		"binding": c.attack_binding if attacking else "none",
		"windup": c.windup_duration() if attacking else 0.0,
		"active": c.active_duration if attacking else 0.0,
		"recovery": c.recovery_duration if attacking else 0.0,
		"quickest": c.attack_windup,
		"reach": opponent.attack_range,
		# The Marrow Arm is visible whenever equipped, not only while lunging.
		"signature_reach": float(c.signature.reach) if not c.signature.is_empty() else 0.0,
		"guarding": c.guarding, "posture": c.posture / c.max_posture, "health": c.health / c.max_health,
		"facing": opponent.facing}

## Record this tick's cues and return the newest snapshot that is old enough to act on.
func observe(opponent: Fighter, delta: float) -> Dictionary:
	clock += delta
	_samples.append(capture(opponent, clock))
	# Deliver every aged sample in order so no visible onset is skipped.
	while not _samples.is_empty() and clock - _samples[0].t >= reaction_delay - EPSILON:
		_deliver(_samples.pop_front())
	return _seen

func seen() -> Dictionary:
	return _seen

## The controller's own felt contact (it was hit, blocked or evaded). Felt, not seen,
## so it is recorded without delay.
func note_contact() -> void:
	last_contact_at = clock

## The newest perceived swing ended without touching this fighter.
func swing_missed() -> bool:
	return swing_started_at >= 0.0 and last_contact_at < swing_started_at

## The perceived blade can still connect: winding up, or active with time left.
func attacking(view: Dictionary) -> bool:
	if view.phase == Rules.Phase.ACTIVE:
		return view.remaining - (clock - view.t) > 0.0
	return view.phase == Rules.Phase.WINDUP

## Estimated seconds until the perceived swing can make contact: the visible windup
## remaining, advanced by the time since it was seen. Zero once the blade is out.
func contact_in(view: Dictionary) -> float:
	if view.phase == Rules.Phase.ACTIVE:
		return 0.0
	if view.phase != Rules.Phase.WINDUP:
		return INF
	return maxf(0.0, view.remaining - (clock - view.t))

## Estimated seconds the opponent stays unable to act (recovery, recoil, broken).
func exposed_for(view: Dictionary) -> float:
	if view.phase not in [Rules.Phase.RECOVERY, Rules.Phase.STAGGER, Rules.Phase.BROKEN]:
		return 0.0
	return maxf(0.0, view.remaining - (clock - view.t))

## Estimated seconds before the opponent could make contact with a fresh swing:
## time until it is free to act again, plus its quickest windup.
func earliest_contact(view: Dictionary) -> float:
	var elapsed: float = clock - view.t
	var free := 0.0
	match view.phase:
		Rules.Phase.WINDUP:
			free = maxf(0.0, view.remaining - elapsed) + view.active + view.recovery
		Rules.Phase.ACTIVE:
			free = maxf(0.0, view.remaining - elapsed) + view.recovery
		Rules.Phase.RECOVERY, Rules.Phase.STAGGER, Rules.Phase.BROKEN, Rules.Phase.DODGE:
			free = maxf(0.0, view.remaining - elapsed)
	return free + float(view.quickest)

## Seconds the opponent has visibly held guard (0 when not guarding).
func guard_held_for() -> float:
	return clock - guard_seen_since if guard_seen_since >= 0.0 else 0.0

func _deliver(view: Dictionary) -> void:
	var previous := _seen
	var new_windup: bool = view.phase == Rules.Phase.WINDUP and (previous.phase != Rules.Phase.WINDUP or view.remaining > previous.remaining + EPSILON)
	if new_windup:
		swing += 1
		swing_started_at = view.t
	if view.guarding and not previous.guarding:
		guard_seen_since = view.t
	elif not view.guarding:
		guard_seen_since = -1.0
	_seen = view
