extends MeshInstance3D
## Interactive Energy Shield, working with the energy shield shader.
##
## This script is used to control the energy shield shader, it can be used to
## generate, collapse and impact the shield making it react to outside influences.
##
## @tutorial:             TODO

## The fixed number of Impacts, the shader can handle at a time.
const _MAX_IMPACTS: int = 5

## The curve used to _animate the impacts. The curve should start at 0.0 and end
## at 1.0 and defines the current progressing of the impact throughout the
## object.
@export var animation_curve: Curve

## The time it takes for the impact to _animate from start to finish.
@export var anim_time: float = 4.0

## The origin of the shield, where the shield will be created or _collapsed from
## by default if not provided otherwise in the functions.
@export var shield_origin: Vector3 = Vector3(0.0, 0.5, 0.0)

@export var handle_input_events: bool = true

# The current impact index, used to keep track of the impacts and overwrite the
# oldest impact if the maximum number of impacts is reached.
var _current_impact: int = 0

# The current state of the impacts, if they are currently animating or not.
var _animate: Array[bool]

# The elapsed time of the impacts, used to calculate the current progress of the
# impact animation.
var _elapsed_time: Array[float]

## The origins, or the points of the impacts
var _impact_origin: Array[Vector3]

# The current progression of the shield generation, used to animate the process
# of building up the shield, 0.0 is collapsed, 1.0 is fully generated.
var _generate_time: float = 1.0

# The current state of the shield, if it is collapsed or not.
var _collapsed: bool = false

# Defines if the shield is currently generating or collapsing, to prevent
# multiple actions at the same time.
var _generating_or_collapsing: bool = false

## The material used for the shield, to set the shader parameters. It is
## expected to be the specific energy shield shader.
@onready var material: ShaderMaterial


func _ready() -> void:
	# Initialize the arrays with the default values
	var filled_elapse_time = [0.0]
	filled_elapse_time.resize(_MAX_IMPACTS)
	filled_elapse_time.fill(0.0)
	_elapsed_time.assign(filled_elapse_time)
	var filled_animate = [false]
	filled_animate.resize(_MAX_IMPACTS)
	filled_animate.fill(false)
	_animate.assign(filled_animate)
	var filled_impact_origins = [Vector3.ZERO]
	filled_impact_origins.resize(_MAX_IMPACTS)
	filled_impact_origins.fill(Vector3.ZERO)
	_impact_origin.assign(filled_impact_origins)

	# Get the material and set the initial scale
	material = get_active_material(0)
	material.set_shader_parameter("object_scale", global_transform.basis.get_scale().x)

	# Connect the input event to the shield
	if handle_input_events and $Area3D:
		$Area3D.input_event.connect(_on_area_3d_input_event)


## Generate the shield from the default origin, starting the generation
## animation.
func generate() -> void:
	if _generating_or_collapsing or !_collapsed:
		return
	generate_from(shield_origin)
	material.set_shader_parameter("_relative_origin_create", true)


## Generate the shield from a specific position, starting the generation
## animation with [param pos] as the origin in world space.
func generate_from(pos: Vector3) -> void:
	if _generating_or_collapsing or !_collapsed:
		return
	_generating_or_collapsing = true
	_generate_time = 0.0
	material.set_shader_parameter("_relative_origin_create", false)
	material.set_shader_parameter("_destroy", false)
	material.set_shader_parameter("_origin_create", pos)
	material.set_shader_parameter("_time_create", _generate_time)


## Collapse the shield from the default origin, starting the collapse
## animation.
func collapse() -> void:
	if _generating_or_collapsing or _collapsed:
		return
	generate_from(shield_origin)
	material.set_shader_parameter("_relative_origin_create", true)


## Collapse the shield from a specific position, starting the collapse
## animation with [param pos] as the origin in world space.
func collapse_from(pos: Vector3) -> void:
	if _generating_or_collapsing or _collapsed:
		return
	_generating_or_collapsing = true
	_generate_time = 0.0
	material.set_shader_parameter("_relative_origin_create", false)
	material.set_shader_parameter("_destroy", true)
	material.set_shader_parameter("_origin_create", pos)
	material.set_shader_parameter("_time_create", _generate_time)


## Create an impact at the [param pos] position, starting a new impact
## animation.
func impact(pos: Vector3):
	# setup the next free impact, or overwrite the oldest impact
	_animate[_current_impact] = true
	_elapsed_time[_current_impact] = 0.0
	_impact_origin[_current_impact] = pos

	# update the shader with the new impact origins
	material.set_shader_parameter("_origin_impact", _impact_origin)

	# update the shader with the new impact times
	var time_impacts = []
	for impact_id in _animate.size():
		if _animate[impact_id]:
			if _elapsed_time[impact_id] < anim_time:
				var normalized_time = _elapsed_time[impact_id] / anim_time
				time_impacts.append(animation_curve.sample(normalized_time))
			else:
				time_impacts.append(0.0)
				_elapsed_time[impact_id] = 0.0
				_animate[impact_id] = false
		else:
			time_impacts.append(0.0)
	material.set_shader_parameter("_time_impact", time_impacts)

	# increment the current impact index
	_current_impact += 1
	_current_impact = _current_impact % _MAX_IMPACTS


func _physics_process(delta: float) -> void:
	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		material.set_shader_parameter("_time_create", _generate_time)
	else:
		if _generating_or_collapsing:
			_collapsed = !_collapsed
			_generating_or_collapsing = false

	# update the impact animations if active
	var any_update = false
	var time_impacts = []
	for impact_id in _animate.size():
		if _animate[impact_id]:
			any_update = true
			if _elapsed_time[impact_id] < anim_time:
				var normalized_time = _elapsed_time[impact_id] / anim_time
				time_impacts.append(animation_curve.sample(normalized_time))
				_elapsed_time[impact_id] += delta
			else:
				time_impacts.append(0.0)
				_elapsed_time[impact_id] = 0.0
				_animate[impact_id] = false
		else:
			time_impacts.append(0.0)
	if any_update:
		material.set_shader_parameter("_time_impact", time_impacts)


func _on_area_3d_input_event(
	_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	# event handling for interaction with the shield
	if is_instance_of(event, InputEventMouseButton) and event.is_pressed():
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if !_collapsed:
				impact(event_position)
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if _collapsed:
				generate_from(event_position)
			else:
				collapse_from(event_position)
