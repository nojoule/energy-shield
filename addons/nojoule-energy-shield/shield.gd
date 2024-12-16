extends MeshInstance3D

@export var animation_curve: Curve
@export var anim_time: float = 10.0

var elapsed_time: float = 0.0
var animate: bool = false

@onready var material: ShaderMaterial


func _ready() -> void:
	material = get_active_material(0)
	$Area3D.input_event.connect(_on_area_3d_input_event)
	print("connected")
	set_instance_shader_parameter("object_scale", global_transform.basis.get_scale().x)


func set_impact_origin(pos: Vector3):
	set_instance_shader_parameter("_origin_impact", pos)
	set_instance_shader_parameter("_time_impact", 0.0)
	animate = true
	elapsed_time = 0.0


func _physics_process(delta: float) -> void:
	if animate:
		if elapsed_time < anim_time:
			var normalized_time = elapsed_time / anim_time
			set_instance_shader_parameter("_time_impact", animation_curve.sample(normalized_time))
			elapsed_time += delta
		else:
			set_instance_shader_parameter("_time_impact", 0.0)
			elapsed_time = 0.0
			animate = false


func _on_area_3d_input_event(
	_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	if is_instance_of(event, InputEventMouseButton) and event.is_pressed():
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			set_impact_origin(event_position)
