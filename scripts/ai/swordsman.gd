extends "res://scripts/characters/fighter.gd"
## Deterministic ordinary cycle plus an opening lunge, repeated every four attacks
## when equipped. Block counters keep the heavy; all attacks use shared rules.

@export var detection_range := 18.0
@export var preferred_distance := 1.85
@export var attack_interval := 0.65
@export var attack_strafe := 0.45 # Fraction of move speed; provisional visible footwork.
var enabled := true
var cooldown := 0.8
var attack_number := 0
var ai_state := "WAIT"
var defense_enabled := true
var counter_pending := false
var observed_event := 0

func _ready() -> void:
	body_color = Color("9b5265")
	super._ready()

func _physics_process(delta: float) -> void:
	desired_move = Vector3.ZERO
	if event_serial != observed_event:
		if defense_enabled and last_result == Rules.GUARD:
			counter_pending = true
			cooldown = 0.0
		observed_event = event_serial
	if enabled and is_instance_valid(opponent) and opponent.combat.phase != Rules.Phase.DEAD and combat.phase != Rules.Phase.DEAD:
		var toward := opponent.global_position - global_position
		toward.y = 0.0
		var distance := toward.length()
		if combat.phase == Rules.Phase.IDLE:
			cooldown = maxf(0.0, cooldown - delta)
			if distance < detection_range:
				facing = toward.normalized()
				# Raise early, hold through contact, then answer with the existing heavy.
				# Never defend while recovering/staggered/broken: those remain punishable.
				var threatened: bool = opponent.combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE] and not opponent.combat.hit_consumed and distance <= opponent.attack_range
				combat.set_guard(defense_enabled and threatened, false)
				if defense_enabled and threatened:
					ai_state = "GUARD"
				elif distance > preferred_distance and not (counter_pending and distance <= AttackModules.SWORD_REACH):
					ai_state = "APPROACH"
					desired_move = facing
				elif cooldown <= 0.0:
					attack_number += 1
					if not combat.signature.is_empty() and not counter_pending and attack_number % 4 == 1:
						combat.attack_special()
					else:
						combat.attack(counter_pending or attack_number % 3 == 0)
					counter_pending = false
					cooldown = attack_interval
					ai_state = "ATTACK"
				else:
					ai_state = "MEASURE"
			else:
				combat.set_guard(false)
				ai_state = "WAIT"
		elif combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
			# Keep working the distance and circling while swinging, including when
			# already in range. Both the visible body and hit volume follow facing.
			turn_toward(toward, delta)
			var radial := toward.normalized()
			var tangent := radial.cross(Vector3.UP) * (1.0 if attack_number % 2 == 0 else -1.0)
			desired_move = (radial * clampf((distance - preferred_distance) * 2.0, -1.0, 1.0) + tangent * attack_strafe).limit_length(1.0)
			ai_state = "ATTACK FOOTWORK"
	else:
		ai_state = "WAIT"
	if not enabled or combat.phase != Rules.Phase.IDLE or not is_instance_valid(opponent) or opponent.combat.phase == Rules.Phase.DEAD:
		combat.set_guard(false)
	super._physics_process(delta)

func reset_at(point: Vector3, guard_held := false) -> void:
	super.reset_at(point)
	cooldown = 0.8
	attack_number = 0
	counter_pending = false
	observed_event = 0
	ai_state = "WAIT"
	facing = Vector3.BACK
