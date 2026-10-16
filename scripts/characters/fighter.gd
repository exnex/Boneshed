class_name Fighter
extends CharacterBody3D

const Rules = preload("res://scripts/combat/combat_state.gd")
var combat := Rules.new()
@export var move_speed := 5.5
@export var acceleration := 32.0
@export var deceleration := 70.0
@export var dodge_speed := 11.0
@export var attack_range := 2.35
@export var attack_width := 1.6
var desired_move := Vector3.ZERO
var facing := Vector3.FORWARD
var dodge_direction := Vector3.FORWARD
var opponent: Fighter
var is_player := false
var body_color := Color("b4c9ba")
var visual: Node3D
var sword_pivot: Node3D
var indicator: MeshInstance3D
var body_material: StandardMaterial3D
var impact: Node3D
var broken_halo: MeshInstance3D
var flash_time := 0.0
var event_serial := 0
var last_result := ""
var debug_hitboxes := true

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	body_material = material(body_color)
	mesh_part(visual, CapsuleMesh.new(), Vector3(0.0, 1.0, 0.0), Vector3(0.62, 0.7, 0.48), body_material)
	mesh_part(visual, SphereMesh.new(), Vector3(0.0, 1.75, 0.0), Vector3(0.38, 0.38, 0.38), material(Color("c9c4ae")))
	for side in [-1.0, 1.0]:
		mesh_part(visual, BoxMesh.new(), Vector3(side * 0.18, 0.35, 0.0), Vector3(0.22, 0.65, 0.25), body_material)
		mesh_part(visual, BoxMesh.new(), Vector3(side * 0.43, 1.05, 0.0), Vector3(0.18, 0.6, 0.2), body_material)
	sword_pivot = Node3D.new()
	sword_pivot.position = Vector3(0.48, 1.1, 0.0)
	visual.add_child(sword_pivot)
	mesh_part(sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.75), Vector3(0.07, 0.12, 1.65), material(Color("d7dfdb"), true))
	mesh_part(sword_pivot, BoxMesh.new(), Vector3(0.0, 0.0, -0.15), Vector3(0.38, 0.1, 0.1), material(Color("ad9568")))
	indicator = mesh_part(self, BoxMesh.new(), Vector3.ZERO, Vector3(attack_width, 0.035, attack_range), material(Color(1.0, 0.35, 0.1, 0.30), true))
	indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact = Node3D.new()
	add_child(impact)
	for i in range(8):
		var spark := mesh_part(impact, BoxMesh.new(), Vector3.ZERO, Vector3(0.05, 0.32, 0.05), material(Color("76e6e5"), true))
		var angle := i * TAU / 8.0
		spark.position = Vector3(sin(angle), cos(angle), 0.0) * 0.4
		spark.rotation.z = -angle
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.27
	halo_mesh.outer_radius = 0.31
	broken_halo = mesh_part(self, halo_mesh, Vector3(0.0, 2.1, 0.0), Vector3.ONE, material(Color("ecbb51"), true))

func _physics_process(delta: float) -> void:
	combat.tick(delta)
	var movable := combat.phase in [Rules.Phase.IDLE, Rules.Phase.DODGE]
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
	_update_visual(delta)

func try_dodge(direction: Vector3) -> bool:
	if combat.dodge():
		dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else -facing
		# Keep only momentum along the dodge, so a prior run cannot shorten or bend it.
		var along := maxf(0.0, velocity.x * dodge_direction.x + velocity.z * dodge_direction.z)
		velocity.x = dodge_direction.x * along
		velocity.z = dodge_direction.z * along
		return true
	return false

func valid_attack_target(target: Fighter) -> bool:
	# Oriented box in front of the actor, intersected with the target capsule radius.
	# Also reject obstacles using the world's physics query (characters excluded).
	var offset := target.global_position - global_position
	var forward := offset.dot(facing)
	var lateral := absf(offset.dot(facing.cross(Vector3.UP)))
	if forward < 0.0 or forward > attack_range or lateral > attack_width * 0.5 + 0.35 or absf(offset.y) > 1.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func resolve_attack() -> String:
	if not is_instance_valid(opponent) or combat.phase != Rules.Phase.ACTIVE or combat.hit_consumed:
		return "invalid"
	if not valid_attack_target(opponent):
		return "out_of_range"
	var result := opponent.combat.receive(combat)
	opponent.last_result = result
	opponent.flash_time = 0.32
	opponent.event_serial += 1
	# Hit resolution runs after actor physics; refresh both poses immediately so
	# the first rendered frame agrees with death, deflection, and break state.
	opponent._update_visual(0.0)
	_update_visual(0.0)
	return result

func reset_at(point: Vector3) -> void:
	combat.reset()
	position = point
	velocity = Vector3.ZERO
	desired_move = Vector3.ZERO
	dodge_direction = Vector3.FORWARD
	last_result = ""
	event_serial = 0
	flash_time = 0.0

func _update_visual(delta: float) -> void:
	flash_time = maxf(0.0, flash_time - delta)
	var phase: int = combat.phase
	visual.rotation.z = 0.0
	visual.position.y = 0.0
	var tint := body_color
	if phase == Rules.Phase.WINDUP:
		sword_pivot.rotation.y = -1.6
		sword_pivot.rotation.z = -0.5
		tint = Color("f2aa53") if combat.heavy else Color("d8b674")
	elif phase == Rules.Phase.ACTIVE:
		sword_pivot.rotation.y = lerpf(-1.6, 1.4, 1.0 - combat.remaining / combat.active_duration)
		sword_pivot.rotation.z = 0.0
	elif phase == Rules.Phase.RECOVERY:
		sword_pivot.rotation.y = 1.2 * combat.remaining / combat.recovery_duration
	elif phase == Rules.Phase.BROKEN:
		tint = Color("e3bd51")
		visual.rotation.z = 0.3
	elif phase == Rules.Phase.DEAD:
		visual.rotation.z = PI / 2.0
		visual.position.y = 0.28
	elif phase == Rules.Phase.STAGGER:
		visual.rotation.z = -0.2
	elif phase == Rules.Phase.DODGE:
		visual.rotation.z = 0.35
	else:
		sword_pivot.rotation = Vector3(0.0, -0.4 if combat.guarding else 0.0, -0.8 if combat.guarding else 0.0)
	if flash_time > 0.0:
		tint = Color("8ff4ee") if last_result == "deflected" else Color("e57968")
	body_material.albedo_color = tint
	impact.visible = flash_time > 0.0 and last_result == "deflected"
	impact.position = facing * 0.9 + Vector3.UP * 1.25
	impact.rotation.y = atan2(-facing.x, -facing.z)
	impact.scale = Vector3.ONE * (1.0 + (0.32 - flash_time) * 2.0)
	broken_halo.visible = phase == Rules.Phase.BROKEN
	indicator.visible = debug_hitboxes and phase in [Rules.Phase.WINDUP, Rules.Phase.ACTIVE]
	indicator.position = facing * attack_range * 0.5 + Vector3.UP * 0.055
	indicator.rotation.y = atan2(-facing.x, -facing.z)
	indicator.material_override.albedo_color = Color(1.0, 0.22, 0.08, 0.48) if phase == Rules.Phase.ACTIVE else Color(1.0, 0.65, 0.18, 0.2)

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
