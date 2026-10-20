extends RefCounted
## Pure pose evaluation for the placeholder fighter: rule state -> curated key pose.
## Reuses the animation lab's phase warp, so key poses land on rule boundaries
## exactly as authored clips would. Reads CombatState; never writes it.
const PhaseWarp = preload("res://scripts/animation_lab/phase_warp.gd")
const Keys = preload("res://scripts/characters/presentation/attack_pose_keys.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")

const MARKERS := {"start": 0.0, "loaded": 1.0, "release": 2.0, "contact": 3.0, "active_end": 4.0, "recovered": 5.0}
const CHANNELS := ["hand", "blade", "torso", "body", "grip", "off"]
const REACTION_SECONDS := 0.32 # Matches Fighter.resolve_attack's presentation timer.
const LOCKOUT_EASE := 0.18 # Stagger eases out over its final seconds, as before.
const BREAK_EASE := 0.35

static func timing_of(state: Rules) -> Dictionary:
	return {"windup": state.windup_duration(), "commitment": state.commitment_duration, "release": state.release_duration,
		"active": state.active_duration, "recovery": state.recovery_duration}

static func binding_of(state: Rules) -> String:
	return "special" if state.is_signature() else ("heavy" if state.heavy else "light")

static func track(binding: String) -> Array:
	return Keys.SPECIAL if binding == "special" else (Keys.HEAVY if binding == "heavy" else Keys.LIGHT)

## Seconds since the current attack began, or -1.0 outside an attack.
static func attack_rule_time(state: Rules) -> float:
	var names := {Rules.Phase.WINDUP: "windup", Rules.Phase.ACTIVE: "active", Rules.Phase.RECOVERY: "recovery"}
	if not names.has(state.phase):
		return -1.0
	return PhaseWarp.rule_time_from_phase(names[state.phase], state.remaining, timing_of(state))

static func clip_time(timing: Dictionary, rule_time: float) -> float:
	return float(PhaseWarp.sample(MARKERS, timing, rule_time).clip_time)

## Pose of `binding` at `rule_time` seconds into an attack with `timing`.
static func attack_pose(binding: String, timing: Dictionary, rule_time: float) -> Dictionary:
	return sample_track(track(binding), clip_time(timing, rule_time))

## Cubic Hermite through the keys. Ordinary keys use centred (Catmull-Rom style)
## tangents so arcs pass through contact with momentum; `hold` keys stop.
static func sample_track(keys: Array, clip: float) -> Dictionary:
	var last := keys.size() - 1
	if clip <= keys[0].t:
		return keys[0].duplicate()
	if clip >= keys[last].t:
		return keys[last].duplicate()
	var i := 0
	while keys[i + 1].t < clip:
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[i + 1]
	var h: float = b.t - a.t
	var s: float = (clip - float(a.t)) / h
	var s2 := s * s
	var s3 := s2 * s
	var h00 := 2.0 * s3 - 3.0 * s2 + 1.0
	var h10 := s3 - 2.0 * s2 + s
	var h01 := -2.0 * s3 + 3.0 * s2
	var h11 := s3 - s2
	var pose := {}
	for channel: String in CHANNELS:
		var m0: Variant = _tangent(keys, i, channel)
		var m1: Variant = _tangent(keys, i + 1, channel)
		pose[channel] = a[channel] * h00 + m0 * (h10 * h) + b[channel] * h01 + m1 * (h11 * h)
	pose.grip = clampf(pose.grip, 0.0, 1.0)
	return pose

static func _tangent(keys: Array, i: int, channel: String) -> Variant:
	var key: Dictionary = keys[i]
	if key.get("hold", false) or i == 0 or i == keys.size() - 1:
		return key[channel] * 0.0
	return (keys[i + 1][channel] - keys[i - 1][channel]) / (keys[i + 1].t - keys[i - 1].t)

static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var pose := {}
	for channel: String in CHANNELS:
		pose[channel] = lerp(a[channel], b[channel], weight)
	return pose

## Exact left/right reflection of a pose: a right-hand sword pose becomes a left-hand
## one, and the right-bone Marrow Lunge track becomes a left-bone one.
static func mirror(pose: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	out.hand = Vector3(-pose.hand.x, pose.hand.y, pose.hand.z)
	out.blade = Vector3(pose.blade.x, -pose.blade.y, -pose.blade.z)
	out.torso = Vector3(pose.torso.x, -pose.torso.y, -pose.torso.z)
	out.off = Vector3(-pose.off.x, pose.off.y, pose.off.z)
	return out

## Base pose for the current rule state, before reaction layers. `weapon_mirrored`
## reflects the right-handed sword tracks for a left-hand weapon; `bone_mirrored`
## reflects the right-bone Marrow Lunge track for a left Marrow Arm. Both come from
## the resolved equipment, never from which abilities exist.
static func base_pose(state: Rules, weapon_mirrored: bool, reaction_kind: String, bone_mirrored := false) -> Dictionary:
	var pose: Dictionary
	var authored_final := false
	match state.phase:
		Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY:
			var binding := binding_of(state)
			pose = attack_pose(binding, timing_of(state), attack_rule_time(state))
			authored_final = binding == "special"
		Rules.Phase.STAGGER:
			var shape: Dictionary = Keys.STAGGER_DEFLECTED if reaction_kind == Rules.DEFLECTED else Keys.STAGGER_HIT
			pose = blend(Keys.REST, shape, smoothstep(0.0, LOCKOUT_EASE, state.remaining))
		Rules.Phase.BROKEN:
			pose = blend(Keys.REST, Keys.BROKEN, smoothstep(0.0, BREAK_EASE, state.remaining))
		Rules.Phase.DODGE:
			# Duck in fast and rise within the rule duration; no exit snap.
			var progress := clampf(1.0 - state.remaining / state.dodge_duration, 0.0, 1.0)
			pose = blend(Keys.REST, Keys.DODGE, smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.65, 1.0, progress)))
		_:
			pose = Keys.GUARD.duplicate() if state.guarding else Keys.REST.duplicate()
	return mirror(pose) if (bone_mirrored if authored_final else weapon_mirrored) else pose

## 1 at impact, a fast damped recoil with one small rebound, exactly 0 at the end.
static func reaction_envelope(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= REACTION_SECONDS:
		return 0.0
	return exp(-elapsed / 0.075) * cos(elapsed * 11.0) * (1.0 - smoothstep(0.2, REACTION_SECONDS, elapsed))

## Additive impact layer. `incoming` is the attacker direction in character space.
## While the actor's own attack runs (a poised heavy), only the body absorbs it;
## the weapon keeps its rule-aligned path.
static func add_reaction(pose: Dictionary, kind: String, elapsed: float, incoming: Vector3, state: Rules) -> Dictionary:
	var k := reaction_envelope(elapsed)
	if k == 0.0 or kind.is_empty():
		return pose
	var lateral := clampf(incoming.x, -1.0, 1.0)
	var attacking := state.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]
	var out := pose.duplicate()
	var torso := Vector3.ZERO
	var body := Vector4.ZERO
	var hand := Vector3.ZERO
	var blade := Vector3.ZERO
	match kind:
		Rules.HIT, "punish", Rules.DEFEATED:
			# Chest snaps away from the cut, knees give, sword arm is flung wide.
			torso = Vector3(0.42, lateral * 0.25, -lateral * 0.18)
			body = Vector4(0.08, 0.12, 0.0, 0.0)
			hand = Vector3(0.1, -0.22, 0.16)
			blade = Vector3(-0.4, 0.2, 0.2)
		Rules.GUARD:
			# Absorbed: blade driven back toward the body, weight sinks.
			torso = Vector3(0.18, lateral * 0.1, 0.0)
			body = Vector4(0.06, 0.08, 0.0, 0.0)
			hand = Vector3(0.0, -0.06, 0.2)
			blade = Vector3(-0.15, 0.0, 0.0)
		Rules.DEFLECTED:
			if state.phase == Rules.Phase.STAGGER or state.phase == Rules.Phase.BROKEN:
				# Deflected attacker: the rebound overshoots the thrown pose.
				torso = Vector3(0.16, -0.2, -0.08)
				body = Vector4(0.0, 0.06, -0.06, 0.04)
				hand = Vector3(0.12, 0.16, 0.14)
				blade = Vector3(0.3, -0.25, 0.0)
			else:
				# Deflecting defender: a crisp, small brace; no loss of ground.
				torso = Vector3(0.08, 0.0, 0.0)
				body = Vector4(0.03, 0.03, 0.0, 0.0)
				hand = Vector3(0.06, 0.04, 0.08)
				blade = Vector3(0.0, -0.2, 0.0)
		_:
			return pose
	out.torso = pose.torso + torso * k
	out.body = pose.body + body * k
	if not attacking:
		out.hand = pose.hand + hand * k
		out.blade = pose.blade + blade * k
	return out

## Elbow/knee position for a two-bone chain of fixed lengths. Unreachable targets
## straighten the chain toward them; the caller decides how to cover the rest.
static func two_bone(root: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3) -> Vector3:
	var offset := target - root
	var distance := offset.length()
	if distance < 0.0001:
		return root + pole.normalized() * upper
	var direction := offset / distance
	var reach := clampf(distance, absf(upper - lower) + 0.001, upper + lower - 0.0001)
	var cos_root := clampf((upper * upper + reach * reach - lower * lower) / (2.0 * upper * reach), -1.0, 1.0)
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = direction.cross(Vector3.RIGHT if absf(direction.x) < 0.9 else Vector3.UP)
	return root + direction * (upper * cos_root) + bend.normalized() * (upper * sqrt(1.0 - cos_root * cos_root))

## Blade base and tip in character space for a pose; used by the trail and tests.
static func blade_points(pose: Dictionary, base := 0.45, tip := 1.75) -> PackedVector3Array:
	var basis := Basis.from_euler(pose.blade)
	return PackedVector3Array([pose.hand + basis * Vector3(0.0, 0.0, -base), pose.hand + basis * Vector3(0.0, 0.0, -tip)])
