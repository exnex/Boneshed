extends "res://scripts/characters/fighter.gd"
## Deterministic cycle: two basic attacks, then one slower heavy attack.

@export var detection_range := 18.0
@export var preferred_distance := 1.85
@export var attack_interval := 0.65
var enabled := true
var cooldown := 0.8
var attack_number := 0
var ai_state := "WAIT"

func _ready() -> void:
	body_color = Color("9b5265")
	move_speed = 2.7
	combat.attack_windup = 0.62
	combat.recovery_duration = 0.65
	super._ready()

func _physics_process(delta: float) -> void:
	desired_move = Vector3.ZERO
	if enabled and is_instance_valid(opponent) and opponent.combat.phase != Rules.Phase.DEAD and combat.phase != Rules.Phase.DEAD:
		var toward := opponent.global_position - global_position
		toward.y = 0.0
		var distance := toward.length()
		if combat.phase == Rules.Phase.IDLE:
			cooldown = maxf(0.0, cooldown - delta)
			if distance < detection_range:
				facing = toward.normalized()
				if distance > preferred_distance:
					ai_state = "APPROACH"
					desired_move = facing
				elif cooldown <= 0.0:
					attack_number += 1
					combat.attack(attack_number % 3 == 0)
					cooldown = attack_interval
					ai_state = "ATTACK"
				else:
					ai_state = "MEASURE"
			else:
				ai_state = "WAIT"
	else:
		ai_state = "WAIT"
	super._physics_process(delta)

func reset_at(point: Vector3) -> void:
	super.reset_at(point)
	cooldown = 0.8
	attack_number = 0
	ai_state = "WAIT"
	facing = Vector3.BACK
