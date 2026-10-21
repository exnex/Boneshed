extends CharacterBody3D
## A lab duelist body: locomotion, facing and the rules state. The arena calls
## `step` in a fixed order (controllers, rules, movement, contact) so outcomes do not
## depend on node processing order. The body itself never rotates; `xform()` is the
## rules frame (position + facing yaw) used for weapon poses and contact.

const State = preload("res://scripts/melee_lab/duelist_state.gd")
const Handling = preload("res://scripts/melee_lab/weapon_handling.gd")
const Visual = preload("res://scripts/melee_lab/lab_visual.gd")
const CombatResources = preload("res://scripts/melee_lab/combat_resources.gd")
const ENVIRONMENT_LAYER := 1
const FIGHTER_LAYER := 2
const IDLE_TURN_RATE := 14.0 # rad/s outside attacks: effectively immediate, but continuous.
const ACCELERATION := 32.0
const DECELERATION := 70.0

var state: State
var tuning: Dictionary = {}
var weapon: Dictionary = {}
var loadout_label := ""
var loadout_id := ""
var move_speed := 5.5
var desired_move := Vector3.ZERO
var facing := Vector3.FORWARD
var dodge_direction := Vector3.BACK
var opponent: CharacterBody3D
var prev_xform := Transform3D.IDENTITY
var body_color := Color("8fa79a")
var visual: Visual

func _ready() -> void:
	collision_layer = FIGHTER_LAYER
	collision_mask = ENVIRONMENT_LAYER | FIGHTER_LAYER
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	visual = Visual.new()
	visual.actor = self
	add_child(visual)

## `resolved` is LabLoadout.resolve output. Replaces the rules state (fresh duel).
## Stamina, mobility, mitigation, resistances and status sources are derived from the
## equipped weapon and armor by the same function for every fighter.
func equip(lab_tuning: Dictionary, resolved: Dictionary) -> void:
	tuning = lab_tuning
	weapon = resolved.weapon
	loadout_label = resolved.label
	loadout_id = str(resolved.get("id", ""))
	move_speed = resolved.stats.move_speed
	var handling := Handling.derive(weapon, tuning)
	var combat := CombatResources.derive(handling, str(weapon.get("item", "")), resolved.get("armor", []), resolved.get("combat", {}), tuning)
	state = State.new(tuning, handling, resolved.stats, combat)
	if is_instance_valid(visual):
		visual.rebuild()

func yaw() -> float:
	return atan2(-facing.x, -facing.z)

func xform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw()), global_position)

func reset_at(point: Vector3, face: Vector3) -> void:
	state.reset()
	position = point
	velocity = Vector3.ZERO
	desired_move = Vector3.ZERO
	facing = face.normalized()
	prev_xform = Transform3D(Basis(Vector3.UP, yaw()), point)

## Rules frame of the opponent, flattened, or forward if absent.
func toward_opponent() -> Vector3:
	if not is_instance_valid(opponent):
		return facing
	var offset := opponent.global_position - global_position
	offset.y = 0.0
	return offset.normalized() if offset.length_squared() > 0.0001 else facing

func turn_toward(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001 or state.phase in [State.Phase.STAGGER, State.Phase.BROKEN, State.Phase.DEAD]:
		return
	var attacking := state.phase in [State.Phase.WINDUP, State.Phase.SWING, State.Phase.RECOVERY]
	var rate: float = state.h.turn_rate if attacking else IDLE_TURN_RATE
	var current := yaw()
	var target := atan2(-direction.x, -direction.z)
	var turn := clampf(angle_difference(current, target), -rate * delta, rate * delta)
	facing = Vector3.FORWARD.rotated(Vector3.UP, current + turn)

func try_dodge(direction: Vector3) -> bool:
	if not state.dodge():
		return false
	_aim_evasion(direction)
	return true

## Dodge roll (Shift): longer travel and a vulnerable tail; see duelist_state.roll.
func try_roll(direction: Vector3) -> bool:
	if not state.roll():
		return false
	_aim_evasion(direction)
	return true

## Current locomotion speed (m/s) after armor and impairments, before guard scaling.
func current_move_speed() -> float:
	return move_speed * state.move_scale()

func _aim_evasion(direction: Vector3) -> void:
	direction.y = 0.0
	dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else -facing

## Rules tick and locomotion for one physics step. Controllers have already run.
func step(delta: float) -> void:
	prev_xform = xform()
	state.tick(delta)
	var free: bool = state.phase in [State.Phase.IDLE, State.Phase.WINDUP, State.Phase.SWING, State.Phase.RECOVERY, State.Phase.DODGE, State.Phase.ROLL]
	var direction := desired_move.limit_length(1.0) if free else Vector3.ZERO
	var speed: float = current_move_speed() * (tuning.guard_move_scale if state.guarding else 1.0)
	if state.evading():
		direction = dodge_direction
		speed = (tuning.dodge_speed if state.phase == State.Phase.DODGE else tuning.roll_speed) * state.evasion_speed_scale()
	var response := DECELERATION if direction.length_squared() < 0.01 else ACCELERATION
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, response * delta)
	velocity = Vector3(horizontal.x, 0.0 if is_on_floor() else velocity.y - 24.0 * delta, horizontal.y)
	move_and_slide()

func _process(delta: float) -> void:
	if is_instance_valid(visual) and state != null:
		visual.sync(delta)
