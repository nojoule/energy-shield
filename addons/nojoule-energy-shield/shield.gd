extends MeshInstance3D

## Relay the body_entered signal from the Area3D to the shield.
signal body_entered(body: Node)

## Relay the body_shape_entered signal from the Area3D to the shield.
signal body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
)

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

# Use an image to store ripple impact positions and elapsed_time.
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

# Last time the _data_image was cleaned of finished animations.
var last_cleanup_exection := 0.0

# The Frequancy of _data_image cleanup in milliseconds.
var data_cleanup_interval := 1500.0


## The material used for the shield, to set the shader parameters. It is
## expected to be the specific energy shield shader.
@onready var material: ShaderMaterial


func _ready() -> void:
	# Initialize the arrays with the default values
	var filled_elapse_time = [0.0]
	filled_elapse_time.resize(1)
	filled_elapse_time.fill(0.0)
	_elapsed_time.assign(filled_elapse_time)

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

	update_material("object_scale", global_transform.basis.get_scale().x)

	update_material("max_impacts", _elapsed_time.size())

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
	# Max image size is: ● MAX_WIDTH = 16777216 ● MAX_HEIGHT = 16777216
	# Could set a variable or lower sane max?
	var color = Color(pos.x, pos.y, pos.z, 0.0)
	if _data_image.get_size() < Vector2i(Image.MAX_WIDTH, Image.MAX_HEIGHT):
		_data_image.crop(_data_image.get_size().x + 1, _data_image.get_size().y)
		_data_image.set_pixel(_data_image.get_size().x - 1, 0, color)
		_elapsed_time.append(0.0)
	else:
		# If max has been reached add impact to beginning of image.
		_data_image.set_pixel(1,0, color)
		_elapsed_time.set(1, 0.0)

	var x_size = _data_image.get_size().x
	var counter := 1
	while counter < x_size:
		if _elapsed_time[counter] < anim_time:
			var old_pixel_value: Color = _data_image.get_pixel(counter, 0)
			var normalized_time: float = _elapsed_time[counter] / anim_time
			var curve_sample: float = animation_curve.sample(normalized_time)
			var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
			_data_image.set_pixel(counter, 0, new_pixel_value)
		counter += 1

	var impact_texture := ImageTexture.new()
	impact_texture = impact_texture.create_from_image(_data_image)

	update_material("_impact_texture", impact_texture)
	update_material("max_impacts", _elapsed_time.size())


func _physics_process(delta: float) -> void:
	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		update_material("_time_generate", _generate_time)
	else:
		if _generating_or_collapsing:
			_collapsed = !_collapsed
			_generating_or_collapsing = false
	
	var x_size = _data_image.get_size().x
	var counter := 1
	while counter < x_size:
		if _elapsed_time[counter] < anim_time:
			var old_pixel_value: Color = _data_image.get_pixel(counter, 0)
			var normalized_time: float = _elapsed_time[counter] / anim_time
			var curve_sample: float = animation_curve.sample(normalized_time)
			var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
			_data_image.set_pixel(counter, 0, new_pixel_value)
			_elapsed_time[counter] += delta
		counter += 1
	
	var impact_texture := ImageTexture.new()
	impact_texture = impact_texture.create_from_image(_data_image)

	update_material("_impact_texture", impact_texture)

	update_material("max_impacts", _elapsed_time.size())

	var current = Time.get_ticks_msec()
	if current - last_cleanup_exection >= data_cleanup_interval:
		last_cleanup_exection = current
		# Simple way of cleaning up data. Could only have this be processed every 10 frames
				# and/or in batches?
		var raw_data: PackedColorArray = _data_image.get_data().to_color_array()
		# Test to see if the arrays are the same length.
		assert(_elapsed_time.size() == raw_data.size(), "Arrays are not the size same size. Something is wrong.")

		# Remove unneeded indexes
		# TODO -- Should a faster method be used here?
		counter = 0
		while counter < raw_data.size() - 1:
			if _elapsed_time[counter] > anim_time:
				raw_data.remove_at(counter)
				_elapsed_time.remove_at(counter)
			else:
				counter += 1
		_data_image.set_data(raw_data.size(), 1, false, Image.FORMAT_RGBAF, raw_data.to_byte_array())


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
