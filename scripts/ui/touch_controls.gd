extends Control
## Input adapter only: no combat timers, damage, or AI decisions live here.
## Each touch index owns one role until release/cancel. Guard stays held while
## its owner is down; camera drags and other fingers never re-press it.

var player: Node3D
var active := false
var contacts: Dictionary = {}
var stick := Vector2.ZERO
var stick_id := -1
var camera_id := -1
var held: Dictionary = {}
var layout: Dictionary = {}
var radius := 60.0
var stick_radius := 110.0
var font: Font = ThemeDB.fallback_font
var last_touch_msec := -1000

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	active = DisplayServer.is_touchscreen_available()
	_layout()
	get_viewport().size_changed.connect(_resized)

func _resized() -> void:
	release_all()
	_layout()

func _layout() -> void:
	var size := get_viewport_rect().size
	radius = size.y * 0.078
	stick_radius = size.y * 0.145
	layout = {
		"stick": Vector2(size.y * 0.22, size.y * 0.75),
		"attack": Vector2(size.x - size.y * 0.12, size.y * 0.68),
		"guard": Vector2(size.x - size.y * 0.30, size.y * 0.76),
		"dodge": Vector2(size.x - size.y * 0.12, size.y * 0.88),
		"lock_on": Vector2(size.x - size.y * 0.12, size.y * 0.40),
		"reset": Vector2(size.y * 0.10, size.y * 0.35)
	}
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		last_touch_msec = Time.get_ticks_msec()
		active = true
		if event.pressed and not event.canceled:
			_begin(event.index, event.position)
		else:
			_end(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		last_touch_msec = Time.get_ticks_msec()
		if contacts.has(event.index):
			var role: String = contacts[event.index]
			if role == "stick":
				_move_stick(event.position)
			elif role == "camera" and player.input_enabled:
				player.rotate_camera(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if active:
			release_all()
			active = false
	elif contacts.is_empty() and Time.get_ticks_msec() - last_touch_msec > 500:
		# Some browsers send compatibility mouse motion with device 0, rather
		# than DEVICE_ID_EMULATION, during/after a touch. It is not a takeover.
		if (event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION) or (event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length_squared() > 0.0):
			active = false
	queue_redraw()

func _begin(index: int, point: Vector2) -> void:
	if contacts.has(index):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var role := "camera"
	for action in ["attack", "guard", "dodge", "lock_on", "reset"]:
		if point.distance_to(layout[action]) <= radius:
			role = action
			break
	if role == "camera" and point.distance_to(layout.stick) <= stick_radius * 1.4 and stick_id == -1:
		role = "stick"
		stick_id = index
		_move_stick(point)
	elif role == "camera":
		if camera_id == -1:
			camera_id = index
		else:
			role = "unused"
	else:
		var count := int(held.get(role, 0))
		held[role] = count + 1
		if count == 0:
			_send(role, true)
	contacts[index] = role

func _end(index: int) -> void:
	if not contacts.has(index):
		return
	var role: String = contacts[index]
	contacts.erase(index)
	if role == "stick":
		stick_id = -1
		stick = Vector2.ZERO
		_movement(Vector2.ZERO)
	elif role == "camera":
		camera_id = -1
	elif held.has(role):
		held[role] -= 1
		if held[role] == 0:
			held.erase(role)
			_send(role, false)

func _move_stick(point: Vector2) -> void:
	stick = ((point - layout.stick) / stick_radius).limit_length(1.0)
	var length := stick.length()
	var value := Vector2.ZERO if length < 0.08 else stick.normalized() * ((length - 0.08) / 0.92)
	# Input.get_vector applies its own radial deadzone; pre-map to preserve analog strength.
	if value.length() > 0.0:
		value = value.normalized() * (0.5 + value.length() * 0.5)
	_movement(value)
	queue_redraw()

func _movement(value: Vector2) -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		var strength := 0.0
		match action:
			"move_left": strength = maxf(0.0, -value.x)
			"move_right": strength = maxf(0.0, value.x)
			"move_forward": strength = maxf(0.0, -value.y)
			"move_back": strength = maxf(0.0, value.y)
		if strength > 0.0:
			Input.action_press(action, strength)
		else:
			Input.action_release(action)

func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func release_all() -> void:
	for index in contacts.keys():
		_end(index)
	stick = Vector2.ZERO
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func _draw() -> void:
	if not active or layout.is_empty():
		return
	var center: Vector2 = layout.stick
	draw_circle(center, stick_radius, Color(0.03, 0.07, 0.08, 0.42))
	draw_arc(center, stick_radius, 0.0, TAU, 48, Color(0.65, 0.78, 0.76, 0.7), 2.0, true)
	draw_circle(center + stick * stick_radius * 0.65, stick_radius * 0.35, Color(0.65, 0.78, 0.76, 0.65))
	var labels := {"attack": "ATTACK", "guard": "GUARD", "dodge": "DODGE", "lock_on": "LOCK", "reset": "RESET"}
	for action in labels:
		var point: Vector2 = layout[action]
		var down := held.has(action)
		var color := Color("dbbf7e") if down or (action == "lock_on" and player.locked) else Color("b4cbc5")
		draw_circle(point, radius, Color(0.05, 0.10, 0.12, 0.78))
		draw_arc(point, radius, 0.0, TAU, 40, color, 3.0 if down else 1.5, true)
		var label: String = labels[action]
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, point + Vector2(-label_width * 0.5, 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
	if get_viewport_rect().size.x < get_viewport_rect().size.y:
		draw_string(font, Vector2(40.0, 190.0), "Rotate your phone to landscape", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("ead9ac"))
