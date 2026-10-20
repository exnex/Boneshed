class_name Fighter
extends CharacterBody3D

const Visual = preload("res://scripts/characters/fighter_visual.gd")
const AttackModules = preload("res://scripts/combat/attack_modules.gd")
const Rules = preload("res://scripts/combat/combat_state.gd")
const Look = preload("res://scripts/characters/presentation/equipment_look.gd")
var combat := Rules.new()
var move_speed := 0.0 # Set from the prepared build before entering the scene tree.
@export var acceleration := 32.0
@export var deceleration := 70.0
@export var dodge_speed := 11.0
var attack_range: float:
	get: return float(combat.signature.reach) if combat.is_signature() else AttackModules.SWORD_REACH
var attack_width: float:
	get: return float(combat.signature.width) if combat.is_signature() else AttackModules.SWORD_WIDTH
@export var attack_turn_speed := 270.0 # Degrees/second; provisional, shared steering limit.
var desired_move := Vector3.ZERO
var facing := Vector3.FORWARD
var dodge_direction := Vector3.FORWARD
var opponent: Fighter
var is_player := false
## The resolved build's equipment view (BuildRules `equipment`). Presentation reads
## `look`, derived from it; nothing visual is inferred from abilities.
var equipment: Dictionary = {}:
	set(value):
		equipment = value
		look = Look.describe(value)
var look: Dictionary = Look.describe({})
var body_color := Color("b4c9ba")
var marrow_pivot: Node3D
var marrow_bone: MeshInstance3D
var marrow_tip: Marker3D
var visual: Node3D
var sword_pivot: Node3D
var sword_arm: MeshInstance3D
var torso: MeshInstance3D
var head: MeshInstance3D
var pelvis: MeshInstance3D
var forearm: MeshInstance3D
var free_arm: MeshInstance3D
var free_forearm: MeshInstance3D
var thighs: Array[MeshInstance3D] = []
var shins: Array[MeshInstance3D] = []
var feet: Array[MeshInstance3D] = []
var gait := 0.0
var reaction_kind := ""
var reaction_time := 0.0
var indicator: MeshInstance3D
var body_material: StandardMaterial3D
var impact: Node3D
var broken_halo: MeshInstance3D
var flash_time := 0.0
var event_serial := 0
var last_result := ""
var debug_hitboxes := false

func _ready() -> void:
	collision_layer = AttackModules.FIGHTER_LAYER
	collision_mask = AttackModules.ENVIRONMENT_LAYER | AttackModules.FIGHTER_LAYER
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	Visual.build(self)

func _physics_process(delta: float) -> void:
	combat.tick(delta)
	# Attacking commits the action, not the actor's feet. Keep locomotion through
	# preparation, contact and follow-through; hit reactions still stop movement.
	var movable := combat.phase in [Rules.Phase.IDLE, Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY, Rules.Phase.DODGE]
	var direction := desired_move.limit_length(1.0) if movable else Vector3.ZERO
	var speed := move_speed * (0.45 if combat.guarding else 1.0)
	if combat.phase == Rules.Phase.DODGE:
		direction = dodge_direction
		speed = dodge_speed
	var response := deceleration if direction.length_squared() < 0.01 else acceleration
	# Integrate horizontal velocity as one vector so acceleration does not favor world axes.
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, response * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if facing.length_squared() > 0.01:
		visual.rotation.y = atan2(-facing.x, -facing.z)
	sync_visual(delta)

func try_dodge(direction: Vector3) -> bool:
	if combat.dodge():
		dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else -facing
		# Keep only momentum along the dodge, so a prior run cannot shorten or bend it.
		var along := maxf(0.0, velocity.x * dodge_direction.x + velocity.z * dodge_direction.z)
		velocity.x = dodge_direction.x * along
		velocity.z = dodge_direction.z * along
		return true
	return false

func turn_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	if combat.phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE, Rules.Phase.RECOVERY]:
		var current_yaw := atan2(-facing.x, -facing.z)
		var turn := clampf(angle_difference(current_yaw, target_yaw), -deg_to_rad(attack_turn_speed) * delta, deg_to_rad(attack_turn_speed) * delta)
		facing = Vector3.FORWARD.rotated(Vector3.UP, current_yaw + turn)
	else:
		facing = direction.normalized()

func valid_attack_target(target: Fighter) -> bool:
	# Oriented box in front of the actor, intersected with the target capsule radius.
	# Also reject obstacles using the world's physics query (characters excluded).
	var offset := target.global_position - global_position
	var forward := offset.dot(facing)
	var lateral := absf(offset.dot(facing.cross(Vector3.UP)))
	if forward < 0.0 or forward > attack_range or lateral > attack_width * 0.5 + 0.35 or absf(offset.y) > 1.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP, AttackModules.ENVIRONMENT_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func resolve_attack() -> String:
	if not is_instance_valid(opponent) or combat.phase != Rules.Phase.ACTIVE or combat.hit_consumed:
		return Rules.INVALID
	if not valid_attack_target(opponent):
		return Rules.OUT_OF_RANGE
	var incoming := global_position - opponent.global_position
	incoming.y = 0.0
	var result := opponent.combat.receive(combat, opponent.facing.dot(incoming.normalized()))
	opponent.last_result = result
	opponent.flash_time = 0.32
	opponent.event_serial += 1
	# Presentation gets the resolved outcome; it cannot affect damage or phase time.
	opponent.reaction_kind = result
	opponent.reaction_time = 0.32 if result != Rules.EVADED else 0.0
	opponent.impact.global_position = (global_position + opponent.global_position) * 0.5 + Vector3.UP * 1.3
	if result == Rules.DEFLECTED:
		reaction_kind = Rules.DEFLECTED
		reaction_time = 0.32
	# Hit resolution runs after actor physics; refresh both poses immediately so
	# the first rendered frame agrees with death, deflection, and break state.
	opponent.sync_visual()
	sync_visual()
	return result

func reset_at(point: Vector3, guard_held := false) -> void:
	combat.reset(guard_held)
	position = point
	velocity = Vector3.ZERO
	desired_move = Vector3.ZERO
	dodge_direction = Vector3.FORWARD
	last_result = ""
	event_serial = 0
	flash_time = 0.0
	gait = 0.0
	reaction_kind = ""
	reaction_time = 0.0

func sync_visual(delta := 0.0) -> void:
	Visual.sync(self, delta)

# Compatibility for historical pose instrumentation; runtime callers use sync_visual.
func _update_visual(delta: float) -> void:
	sync_visual(delta)

static func material(color: Color, glow := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 0.45
	return mat

static func mesh_part(parent: Node3D, mesh: Mesh, point: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.scale = size
	instance.material_override = mat
	parent.add_child(instance)
	return instance
