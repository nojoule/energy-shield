class_name NJEnergyShield
extends MeshInstance3D

## Relay the body_entered signal from the Area3D to the shield.
signal body_entered(body: Node)

## Relay the body_shape_entered signal from the Area3D to the shield.
signal body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
)

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

## To prevent artifacts due to transparency and disabled culling, the shield can
## be split into a front and back part.
@export var split_front_back: bool = false

## Make shield interactable by mouse-clicks.
@export var handle_input_events: bool = true

## Trigger an impact when a body enters the shield.
@export var body_entered_impact: bool = false

## Trigger an impact when a body shape enters the shield.
@export var body_shape_entered_impact: bool = false


## Defines if the coordinates of the origin is relative to the object position
@export var relative_impact_position: bool = false

# Use an image to store positions and elapsed_time.
var _data_image := Image.create_empty(1,1, false, Image.FORMAT_RGBAF)

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


var last_process_exection := 0.0
var interval := 500.0


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

	# Load web-optimized shader if running on web platform or compatibility mode
	var renderer = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	if OS.has_feature("web") or renderer == "gl_compatibility":
		_load_web_shader()

	# Set the split front and back shader if enabled, copying all uniform
	# settings
	if not Engine.is_editor_hint() and split_front_back:
		if material.next_pass:
			var del_mat = material.next_pass
			material.next_pass = null
		set_surface_override_material(0, material.duplicate())
		material = get_active_material(0)
		material.next_pass = material.duplicate()
		if OS.has_feature("web") or renderer == "gl_compatibility":
			var back_shader = load("res://addons/nojoule-energy-shield/shield_web_back.gdshader")
			material.shader = back_shader
			var front_shader = load("res://addons/nojoule-energy-shield/shield_web_front.gdshader")
			material.next_pass.shader = front_shader
		else:
			var back_shader = load("res://addons/nojoule-energy-shield/shield_back.gdshader")
			material.shader = back_shader
			var front_shader = load("res://addons/nojoule-energy-shield/shield_front.gdshader")
			material.next_pass.shader = front_shader

	update_material(
		"object_scale",
		max(
			global_transform.basis.get_scale().x,
			global_transform.basis.get_scale().y,
			global_transform.basis.get_scale().z
		)
	)

	# Connect the input event to the shield
	if handle_input_events and $Area3D:
		$Area3D.input_event.connect(_on_area_3d_input_event)

	# Connect relay signals for area 3d child
	if $Area3D:
		$Area3D.area_entered.connect(_on_area_3d_body_entered)
		$Area3D.body_shape_entered.connect(_on_area_3d_body_shape_entered)


# Update the shader parameter [param name] with the [param value] and make sure
# to update the front and back shader if split is enabled.
func update_material(name: String, value: Variant) -> void:
	material.set_shader_parameter(name, value)
	if not Engine.is_editor_hint() and split_front_back:
		material.next_pass.set_shader_parameter(name, value)


## Generate the shield from the default origin, starting the generation
## animation.
func generate() -> void:
	if _generating_or_collapsing or !_collapsed:
		return
	generate_from(shield_origin)
	update_material("_relative_origin_generate", true)


## Generate the shield from a specific position, starting the generation
## animation with [param pos] as the origin in world space.
func generate_from(pos: Vector3) -> void:
	if _generating_or_collapsing or !_collapsed:
		return
	_generating_or_collapsing = true
	_generate_time = 0.0
	update_material("_relative_origin_generate", false)
	update_material("_collapse", false)
	update_material("_origin_generate", pos)
	update_material("_time_generate", _generate_time)


## Collapse the shield from the default origin, starting the collapse
## animation.
func collapse() -> void:
	if _generating_or_collapsing or _collapsed:
		return
	collapse_from(shield_origin)
	update_material("_relative_origin_generate", true)


## Collapse the shield from a specific position, starting the collapse
## animation with [param pos] as the origin in world space.
func collapse_from(pos: Vector3) -> void:
	if _generating_or_collapsing or _collapsed:
		return
	_generating_or_collapsing = true
	_generate_time = 0.0
	update_material("_relative_origin_generate", false)
	update_material("_collapse", true)
	update_material("_origin_generate", pos)
	update_material("_time_generate", _generate_time)


## Create an impact at the [param pos] position, starting a new impact
## animation.
func impact(pos: Vector3):
	var impact_pos: Vector3 = pos
	if relative_impact_position:
		impact_pos = to_local(pos)
	
	# When resizing texture use crop.
	#_data_image.crop()
	
	# Will need to create a method of cleaning up the image.
	# Create a max of 5,000? Max image size is: 
					#● MAX_WIDTH = 16777216
					#The maximal width allowed for Image resources.
					#● MAX_HEIGHT = 16777216
					#The maximal height allowed for Image resources.

	if _current_impact + 1 > _data_image.get_size().x:
		_data_image.crop(_current_impact + 1, _data_image.get_size().y)
	
	var color = Color(pos.x, pos.y, pos.z, 0.0)
	_data_image.set_pixel(_current_impact, 0, color)
	
	# setup the next free impact, or overwrite the oldest impact
	_animate[_current_impact] = true
	_elapsed_time[_current_impact] = 0.0
	_impact_origin[_current_impact] = impact_pos

	# update the shader with the new impact origins
	update_material("_origin_impact", _impact_origin)
	update_material("_relative_origin_impact", relative_impact_position)

	# update the shader with the new impact times
	var time_impacts = []
	for impact_id in _animate.size():
		if _animate[impact_id]:
			if impact_id + 1 > _data_image.get_size().x:
				_data_image.crop(impact_id + 1, _data_image.get_size().y)
			if _data_image.get_pixel(impact_id, 0).a < anim_time:
				var old_pixel_value: Color = _data_image.get_pixel(impact_id, 0)
				var normalized_time: float = old_pixel_value.a / anim_time
				var curve_sample: float = animation_curve.sample(normalized_time)
				var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
				_data_image.set_pixel(impact_id, 0, new_pixel_value)
			else:
				var old_pixel_value: Color = _data_image.get_pixel(impact_id, 0)
				var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, 0.0)
				_data_image.set_pixel(impact_id, 0, new_pixel_value)
				_animate[impact_id] = false
			
			
			if _elapsed_time[impact_id] < anim_time:
				var normalized_time = _elapsed_time[impact_id] / anim_time
				time_impacts.append(animation_curve.sample(normalized_time))
			else:
				time_impacts.append(0.0)
				_elapsed_time[impact_id] = 0.0
				_animate[impact_id] = false
		else:
			time_impacts.append(0.0)
	update_material("_time_impact", time_impacts)

	var impact_texture := ImageTexture.new()
	impact_texture.create_from_image(_data_image)
	
	#update_material("_impact_texture", impact_texture)
	
	# increment the current impact index
	_current_impact += 1
	_current_impact = _current_impact % _MAX_IMPACTS #_data_image.get_size().x
	
	# Simple way of cleaning up data. Could only have this be processed every 10 frames
			# and/or in batches?
	var raw_data: PackedColorArray = _data_image.get_data().to_color_array()
	
	# Print debug info before trimming finished pixels.
	var current = Time.get_ticks_msec()
	if current - last_process_exection >= interval:
		last_process_exection = current
		#print(self.angular_velocity.length())
		print_debug("Image: ", raw_data)
	
	var counter: int = 0
	while counter < raw_data.size() - 1:
		if raw_data.get(counter).a == 0.0:
			raw_data.remove_at(counter)
		else:
			counter += 1
	_data_image.set_data(raw_data.size(), 1, false, Image.FORMAT_RGBAF, raw_data.to_byte_array())
	


func _physics_process(delta: float) -> void:
	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		update_material("_time_generate", _generate_time)
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
		update_material("_time_impact", time_impacts)

	var new_scale = max(
		global_transform.basis.get_scale().x,
		global_transform.basis.get_scale().y,
		global_transform.basis.get_scale().z
	)
	update_material("_object_scale", new_scale)


func _on_area_3d_input_event(
	_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int
) -> void:
	# event handling for mouse interaction with the shield
	if is_instance_of(event, InputEventMouseButton) and event.is_pressed():
		var shift_pressed = Input.is_key_pressed(KEY_CTRL)
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if not shift_pressed:
				if not _collapsed:
					impact(event_position)
			else:
				if _collapsed:
					generate_from(event_position)
				else:
					collapse_from(event_position)


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body_entered_impact:
		impact(body.global_position)
	body_entered.emit(body)


func _on_area_3d_body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
) -> void:
	if body_shape_entered_impact:
		impact(body.global_position)
	body_shape_entered.emit(body_rid, body, body_shape_index, local_shape_index)


# Load web-optimized shader that defines WEB preprocessor directive
func _load_web_shader() -> void:
	# Check if web shader exists, otherwise create it dynamically
	var web_shader_path = "res://addons/nojoule-energy-shield/shield_web.gdshader"
	if ResourceLoader.exists(web_shader_path):
		var web_shader = load(web_shader_path)
		material.shader = web_shader
		print("Loaded web-optimized shader")
