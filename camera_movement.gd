extends Camera3D

var mouse_sensitivity: float = 0.003
var move_speed: float = 3.0
var rotation_x: float = 0.0
var rotation_y: float = 0.0
var mouse_captured: bool = false


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float):
	toggle_mouse_capture()
	if mouse_captured:
		handle_mouse_input(delta)
	handle_movement(delta)


func toggle_mouse_capture():
	if Input.is_action_just_pressed("toggle_mouse_capture"):
		mouse_captured = not mouse_captured
		if mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func handle_mouse_input(_delta: float):
	var mouse_motion = Input.get_last_mouse_velocity()
	rotation_x -= mouse_motion.y * mouse_sensitivity
	rotation_y -= mouse_motion.x * mouse_sensitivity
	rotation_x = clamp(rotation_x, -89, 89)
	rotation_degrees = Vector3(rotation_x, rotation_y, 0)


func handle_movement(delta: float):
	var direction = Vector3()

	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x
	if Input.is_action_pressed("move_up"):
		direction += transform.basis.y
	if Input.is_action_pressed("move_down"):
		direction -= transform.basis.y

	if direction != Vector3.ZERO:
		direction = direction.normalized()

	position += direction * move_speed * delta
