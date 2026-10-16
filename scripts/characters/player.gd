extends "res://scripts/characters/fighter.gd"

@export var mouse_sensitivity := 0.003
@export var camera_distance := 6.0
@export var shoulder_offset := 0.8
var yaw := 0.0
var pitch := -0.28
var locked := false
var camera_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var input_enabled := true

func _ready() -> void:
	is_player = true
	body_color = Color("527f75")
	super._ready()
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(shoulder_offset, 1.6, 0.0)
	add_child(camera_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = camera_distance
	spring.margin = 0.25
	spring.collision_mask = 1
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.2
	spring.shape = camera_shape
	camera_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.current = true
	spring.add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -0.85, 0.25)
	if event.is_action_pressed("lock_on"):
		locked = not locked
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("attack"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if input_enabled:
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		desired_move = Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, yaw)
		if locked and is_instance_valid(opponent) and opponent.combat.phase != Rules.Phase.DEAD:
			var toward := opponent.global_position - global_position
			toward.y = 0.0
			facing = toward.normalized()
			yaw = lerp_angle(yaw, atan2(-facing.x, -facing.z), delta * 8.0)
		elif desired_move.length_squared() > 0.01 and combat.phase == Rules.Phase.IDLE:
			facing = desired_move.normalized()
		combat.set_guard(Input.is_action_pressed("guard"))
		if Input.is_action_just_pressed("attack"):
			combat.attack()
		if Input.is_action_just_pressed("dodge"):
			try_dodge(desired_move)
	camera_pivot.rotation = Vector3(pitch, yaw, 0.0)
	camera_pivot.position = Vector3(shoulder_offset, 1.6, 0.0).rotated(Vector3.UP, yaw)
	super._physics_process(delta)

func reset_at(point: Vector3) -> void:
	super.reset_at(point)
	yaw = 0.0
	pitch = -0.28
	locked = false
	facing = Vector3.FORWARD
