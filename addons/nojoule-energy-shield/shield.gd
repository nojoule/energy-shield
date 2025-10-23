class_name NJEnergyShield
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

## Defines if the coordinates of the origin is relative to the object position
@export var relative_impact_position: bool = false

## Max number of waves processed at one time. If set below 0 sets itself to 
## technical max of 16777216 waves.
@export var impact_max: int = Image.MAX_HEIGHT:
	set(input):
		if input < 0 or input > Image.MAX_HEIGHT:
			impact_max = Image.MAX_HEIGHT
		else:
			impact_max = input

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

# The frequancy of _data_image cleanup in physcis frames. A random number will be
# added to this to a max of 25% of this value. So not all cleanups happen in the
# same frame.
var data_cleanup_interval := 250

# Current physcis frame. This variable gets incremented in _physcis_process().
var current_physcis_frame_count := 0

# Objects detected causing an impact. Needs to have a null entry so it is the same size
# as the other arrays needed in wave processing.
var _objects_detected : Array = [null]


## The material used for the shield, to set the shader parameters. It is
## expected to be the specific energy shield shader.
@onready var material: ShaderMaterial


func _ready() -> void:
	# Add a random amount to the cleanup interval so all shields don't cleanup
	# in the same frame.
	data_cleanup_interval += randi() % int(250 * 0.25)

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

	update_material(
		"object_scale",
		max(
			global_transform.basis.get_scale().x,
			global_transform.basis.get_scale().y,
			global_transform.basis.get_scale().z
		)
	)

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
func impact(pos: Vector3, object: PhysicsBody3D):
	if not _objects_detected.has(object) or object == null:
		var impact_pos: Vector3 = pos
		if relative_impact_position:
			impact_pos = to_local(pos)

		var color = Color(impact_pos.x, impact_pos.y, impact_pos.z, 0.0)
		if _data_image.get_size() < Vector2i(impact_max, impact_max):
			_data_image.crop(_data_image.get_size().x + 1, _data_image.get_size().y)
			_data_image.set_pixel(_data_image.get_size().x - 1, 0, color)
			_elapsed_time.append(0.0)
		else:
			# If max has been reached add impact to beginning of image.
			var index: int = _elapsed_time.max()
			if index != null:
				_data_image.set_pixel(index,0, color)
				_elapsed_time.set(index, 0.0)
			else:
				push_warning("_elapsed_time.max() returned null. Defaulting to the first entry.")
				_data_image.set_pixel(1, 0, color)
				_elapsed_time.set(1, 0.0)

		# Updating times after each impact seems to create a slight time imbalance.
		# Runs much smoother without this.
		#var x_size = _data_image.get_size().x
		#var counter := 1
		#while counter < x_size:
			#if _elapsed_time[counter] < anim_time:
				#var old_pixel_value: Color = _data_image.get_pixel(counter, 0)
				#var normalized_time: float = _elapsed_time[counter] / anim_time
				#var curve_sample: float = animation_curve.sample(normalized_time)
				#var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
				#_data_image.set_pixel(counter, 0, new_pixel_value)
			#counter += 1

		# Create a new texture for the shader to use.
		var impact_texture := ImageTexture.new()
		impact_texture = impact_texture.create_from_image(_data_image)

		_objects_detected.append(object)

		# Update shader variables.
		update_material("_impact_texture", impact_texture)
		update_material("max_impacts", _elapsed_time.size())
		update_material("_relative_origin_impact", relative_impact_position)


func _physics_process(delta: float) -> void:
	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		update_material("_time_generate", _generate_time)
	else:
		if _generating_or_collapsing:
			_collapsed = !_collapsed
			_generating_or_collapsing = false

	# Process _elapsed_times for each wave.
	var x_size = _data_image.get_size().x
	var counter := 1
	while counter < x_size:
		if _elapsed_time[counter] < anim_time:
			var old_pixel_value: Color = _data_image.get_pixel(counter, 0)
			var normalized_time: float = _elapsed_time[counter] / anim_time
			# If animation is finished see if the body that triggered the wave
			# is still touching the shield.
			if normalized_time > 0.9 and _objects_detected[counter] != null:
				var space_state = get_world_3d().direct_space_state
				var start = self.global_position
				var end = _objects_detected[counter].global_position

				var query = PhysicsRayQueryParameters3D.create(start, end)
				#query.collide_with_areas = true
				query.hit_from_inside = false
				var result_1 = space_state.intersect_ray(query)

				query = PhysicsRayQueryParameters3D.create(end, start)
				query.hit_from_inside = false
				var result_2 = space_state.intersect_ray(query)

				if result_1 != {} and result_2 != {}:
					print_debug("Using raycast data.")
					var dis_to_1: float = self.global_position.distance_squared_to(result_1.position)
					var dis_to_2: float = self.global_position.distance_squared_to(result_2.position)
					var differance: float = dis_to_2 - dis_to_1
					print_debug("Differance: ", differance)
					# Below zero should mean that the object is touching the shield.
					if differance < 0:
						# Update pixel data and reset _elapsed_time.
						_elapsed_time[counter] = 0.0
						var pos: Vector3 = result_2.position - result_1.position
						var new_pixel_value: Color = Color(pos.x, pos.y, pos.z, 0.0)
						_data_image.set_pixel(counter, 0, new_pixel_value)
				else:
					print_debug("Results of raycasts were empty. Using area overlap.")
					if $Area3D.get_overlapping_bodies().has(_objects_detected[counter]):
						# Update pixel data and reset _elapsed_time.
						_elapsed_time[counter] = 0.0
						var pos := Vector3.ZERO
						if result_1 != {}:
							pos = result_1.position
						else:
							# What to do?
							print_debug("What now?")
							pass
						var new_pixel_value: Color = Color(pos.x, pos.y, pos.z, 0.0)
						_data_image.set_pixel(counter, 0, new_pixel_value)
			else:
				var curve_sample: float = animation_curve.sample(normalized_time)
				var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
				_data_image.set_pixel(counter, 0, new_pixel_value)
				_elapsed_time[counter] += delta
		counter += 1

	# Create texture for shader.
	var impact_texture := ImageTexture.new()
	impact_texture = impact_texture.create_from_image(_data_image)

	# Update shader variables.
	update_material("_impact_texture", impact_texture)
	update_material("max_impacts", _elapsed_time.size())

	# Simple way of cleaning up data. Runs after "data_cleanup_interval" physics frames.
	current_physcis_frame_count += 1
	if current_physcis_frame_count % data_cleanup_interval == 0:
		# Convert the image data into an array that can be processed.
		var raw_data: PackedColorArray = _data_image.get_data().to_color_array()

		# Test to see if the arrays are the same length.
		assert(_elapsed_time.size() == raw_data.size(), "_elapsed_time and raw_data are not the size 
				same size. Something is wrong.")
		assert(_objects_detected.size() == _elapsed_time.size(), "_objects_detected and _elapsed_time arrays
				are not the same size. Something is wrong.")

		# Remove entries were the animations have finished.
		# TODO -- Should a faster method be used here?
		counter = 0
		while counter < raw_data.size() - 1:
			if _elapsed_time[counter] > anim_time:
				raw_data.remove_at(counter)
				_elapsed_time.remove_at(counter)
				_objects_detected.remove_at(counter)
			else:
				counter += 1
		_data_image.set_data(raw_data.size(), 1, false, Image.FORMAT_RGBAF, raw_data.to_byte_array())

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
					impact(event_position, null)
			else:
				if _collapsed:
					generate_from(event_position)
				else:
					collapse_from(event_position)


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body_entered_impact:
		impact(body.global_position, body)
	body_entered.emit(body)


func _on_area_3d_body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
) -> void:
	if body_shape_entered_impact:
		impact(body.global_position, body)
	body_shape_entered.emit(body_rid, body, body_shape_index, local_shape_index)


# Load web-optimized shader that defines WEB preprocessor directive
func _load_web_shader() -> void:
	# Check if web shader exists, otherwise create it dynamically
	var web_shader_path = "res://addons/nojoule-energy-shield/shield_web.gdshader"
	if ResourceLoader.exists(web_shader_path):
		var web_shader = load(web_shader_path)
		material.shader = web_shader
		print("Loaded web-optimized shader")
