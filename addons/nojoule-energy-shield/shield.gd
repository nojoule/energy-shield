extends MeshInstance3D

@export var animation_curve: Curve
@export var anim_time: float = 4.0

var current_impact: int = 0
const max_impacts: int = 5
var animate: Array[bool]
var elapsed_time: Array[float]
var impact_origins: Array[Vector3]

@onready var material: ShaderMaterial


func _ready() -> void:
	var filled_elapse_time = [0.0]
	filled_elapse_time.resize(max_impacts)
	filled_elapse_time.fill(0.0)
	elapsed_time.assign(filled_elapse_time)
	var filled_animate = [false]
	filled_animate.resize(max_impacts)
	filled_animate.fill(false)
	animate.assign(filled_animate)
	var filled_impact_origins = [Vector3.ZERO]
	filled_impact_origins.resize(max_impacts)
	filled_impact_origins.fill(Vector3.ZERO)
	impact_origins.assign(filled_impact_origins)

	material = get_active_material(0)
	$Area3D.input_event.connect(_on_area_3d_input_event)
	print("connected")
	set_instance_shader_parameter("object_scale", global_transform.basis.get_scale().x)


func set_impact_origin(pos: Vector3):
	animate[current_impact] = true
	elapsed_time[current_impact] = 0.0
	impact_origins[current_impact] = pos
	
	material.set_shader_parameter("_origin_impact", impact_origins)

	var time_impacts = []
	for impact_id in animate.size():
		if animate[impact_id]:
			if elapsed_time[impact_id] < anim_time:
				var normalized_time = elapsed_time[impact_id] / anim_time
				time_impacts.append(animation_curve.sample(normalized_time))
			else:
				time_impacts.append(0.0)
				elapsed_time[impact_id] = 0.0
				animate[impact_id] = false
		else:
			time_impacts.append(0.0)
	material.set_shader_parameter("_time_impact", time_impacts)

	current_impact += 1
	current_impact = current_impact % max_impacts


func _physics_process(delta: float) -> void:
	var any_update = false
	var time_impacts = []
	for impact_id in animate.size():
		if animate[impact_id]:
			any_update = true
			if elapsed_time[impact_id] < anim_time:
				var normalized_time = elapsed_time[impact_id] / anim_time
				time_impacts.append(animation_curve.sample(normalized_time))
				elapsed_time[impact_id] += delta
			else:
				time_impacts.append(0.0)
				elapsed_time[impact_id] = 0.0
				animate[impact_id] = false
		else:
			time_impacts.append(0.0)
	if any_update:
		material.set_shader_parameter("_time_impact", time_impacts)

func _on_area_3d_input_event(
	_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	if is_instance_of(event, InputEventMouseButton) and event.is_pressed():
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			set_impact_origin(event_position)
