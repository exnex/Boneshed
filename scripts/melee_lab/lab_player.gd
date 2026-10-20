extends "res://scripts/melee_lab/lab_duelist.gd"
## Player controller for the lab. Control scheme ("click, then flick"):
##   LMB press   — start preparing a swing immediately (natural follow-up direction).
##   while held  — mouse moves the aim cursor instead of the camera; flicking past the
##                 deadzone picks the chamber side: right / high-right / up / high-left /
##                 left, or down for a thrust. The blade moves to that chamber at once.
##   LMB release — commit: the swing fires as soon as the chamber is reached
##                 (never earlier than min_windup). A quick tap is a follow-up cut.
##   RMB         — guard; while held the mouse aims the guard (same cursor layout: point
##                 at the side to cover, down = centre vs thrusts). A fresh press opens
##                 the deflect window and cancels any attack.
##   Space       — dodge (cancels everything, brief invulnerability).
## Outside those holds, the mouse orbits the camera as usual, including during the swing
## itself, so the body can turn into (or away from) a released cut.

const Geometry = preload("res://scripts/melee_lab/swing_geometry.gd")

var cursor := Vector2.ZERO
var aim_owner := "" # "attack", "guard" or "" (camera).
var camera_yaw := 0.0
var camera_pitch := -0.28
var locked := true
var input_enabled := true
## QA drives legal mouse events without a captured pointer.
var accept_uncaptured_motion := false
var mouse_sensitivity := 0.003
var camera_pivot: Node3D
var camera: Camera3D

func _ready() -> void:
	body_color = Color("5f8f80")
	super._ready()
	camera_pivot = Node3D.new()
	camera_pivot.top_level = true
	add_child(camera_pivot)
	var spring := SpringArm3D.new()
	spring.spring_length = 4.6
	spring.margin = 0.25
	spring.collision_mask = ENVIRONMENT_LAYER
	camera_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.08
	camera.current = true
	spring.add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or accept_uncaptured_motion):
		move_mouse(event.relative)
	if event.is_action_pressed("lab_lock_on"):
		locked = not locked
	if event.is_action_pressed("lab_release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and not DisplayServer.get_name() == "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Mouse motion goes to the aim cursor while a combat button owns it, else the camera.
func move_mouse(relative: Vector2) -> void:
	if aim_owner != "":
		cursor = (cursor + Vector2(relative.x, -relative.y) * tuning.aim_sensitivity).limit_length(1.0)
	else:
		camera_yaw -= relative.x * mouse_sensitivity
		camera_pitch = clampf(camera_pitch - relative.y * mouse_sensitivity, -0.8, 0.1)

func control(delta: float) -> void:
	if not input_enabled:
		desired_move = Vector3.ZERO
		return
	var move := Input.get_vector("lab_move_left", "lab_move_right", "lab_move_forward", "lab_move_back")
	desired_move = Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, camera_yaw)
	var attack_held := Input.is_action_pressed("lab_attack")
	var guard_held := Input.is_action_pressed("lab_guard")
	if Input.is_action_just_pressed("lab_guard"):
		aim_owner = "guard"
		cursor = Vector2.ZERO
	elif Input.is_action_just_pressed("lab_attack") and not guard_held:
		aim_owner = "attack"
		cursor = Vector2.ZERO
		state.press_attack(Geometry.classify_attack(cursor, tuning.aim_deadzone))
	if aim_owner == "guard" and not guard_held:
		aim_owner = "attack" if attack_held else ""
	if aim_owner == "attack":
		state.aim_attack(Geometry.classify_attack(cursor, tuning.aim_deadzone))
		# Once released (or swinging) the cursor hands the mouse back to the camera.
		if not attack_held:
			state.release_attack()
			aim_owner = ""
		elif state.phase not in [State.Phase.WINDUP, State.Phase.RECOVERY, State.Phase.IDLE]:
			aim_owner = ""
	state.set_guard(guard_held, Geometry.classify_guard(cursor, tuning.aim_deadzone) if aim_owner == "guard" else "")
	if Input.is_action_just_pressed("lab_dodge"):
		if try_dodge(desired_move):
			aim_owner = ""
	if locked and is_instance_valid(opponent):
		turn_toward(toward_opponent(), delta)
		var target_yaw := atan2(-toward_opponent().x, -toward_opponent().z) + 0.18
		camera_yaw += clampf(angle_difference(camera_yaw, target_yaw) * (1.0 - exp(-6.0 * delta)), -3.0 * delta, 3.0 * delta)
	else:
		turn_toward(Vector3.FORWARD.rotated(Vector3.UP, camera_yaw), delta)

func _process(delta: float) -> void:
	super._process(delta)
	if camera_pivot != null:
		camera_pivot.global_position = global_position + Vector3.UP * 1.75 + Vector3(0.75, 0.0, 0.0).rotated(Vector3.UP, camera_yaw)
		camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0.0)

func reset_at(point: Vector3, face: Vector3) -> void:
	super.reset_at(point, face)
	cursor = Vector2.ZERO
	aim_owner = ""
	camera_yaw = yaw()
