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
@export var impact_max: int = Image.MAX_WIDTH:
	set(input):
		if input < 0 or input > Image.MAX_WIDTH:
			impact_max = Image.MAX_WIDTH
		else:
			impact_max = input


# To automatically assign velocity_parent if the parent is a RigidBody3D.
# This setting is checked before velocity_parent.
@export var is_parent_rigid_body: bool = false


# To have impact ripple's size and intensity incorporate the velocity of the
# parent rigid body.
@export var velocity_parent: RigidBody3D = null


# The layer that _process_object function uses to detect intersection points.
# In order for the function to work properly, this must be set to a layer that
# is not used for anything else.
@export_flags_3d_physics var tmp_impact_layer: int = 128


# Use an image to store ripple impact positions and elapsed_time.
# Y-1 is used for origin of ripple and timing
# Y-2 is used for ripple customization based on the object that triggered the ripple.
var _data_image := Image.create_empty(1,2, false, Image.FORMAT_RGBAF)

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
var data_cleanup_interval := 155

# Objects detected causing an impact. Needs to have a null entry so it is the same size
# as the other arrays needed in wave processing.
var _objects_detected : Array = [null]


# Objest that are being processed by _impact function.
var objects_to_process: Dictionary = {}


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
func impact(pos: Vector3, object: CollisionObject3D = null, collision_volume: float = 0.0, impact_force := Vector3.ZERO):
	if object == null or not objects_to_process.has(object.name):
		if object != null:
			objects_to_process[object.name] = object
		
		# Wait for a few milliseconds so 2 impacts don't process at the same time.
		await get_tree().create_timer(randfn(0.02, 0.05)).timeout
		# In game only process impact right before physics frame. So impact data does not
		# get overriden by processing code in _physcis_process().
		await get_tree().physics_frame

		# Don't process if the object has already in process or if the double_override has
		# been set.
		#if (double_override or not _objects_detected.has(object) or object == null):
		#if true:
		var impact_pos: Vector3 = pos
		if relative_impact_position:
			impact_pos = to_local(pos)

		var color = Color(impact_pos.x, impact_pos.y, impact_pos.z, 0.0)
		var index: int = -1
		if _data_image.get_size() < Vector2i(impact_max, impact_max):
			_data_image.crop(_data_image.get_width() + 1, _data_image.get_height())
			_data_image.set_pixel(_data_image.get_size().x - 1, 0, color)
			var color_2 := Color(1.0, 1.0, 1.0, 1.0)
			_data_image.set_pixel(_data_image.get_size().x - 1, 1, color_2)
			_elapsed_time.append(0.0)
			index = _data_image.get_width() - 1
		else:
			# If max has been reached add impact to beginning of image.
			index = _elapsed_time.max()
			if index != null:
				_data_image.set_pixel(index, 0, color)
				_elapsed_time.set(index, 0.0)
			else:
				push_warning("_elapsed_time.max() returned null. Defaulting to the first entry.")
				_data_image.set_pixel(1, 0, color)
				_elapsed_time.set(1, 0.0)
				index = 1
		
		if object != null:
			var self_volume: float = 1.0
			var aabb_size: Vector3 = self.mesh.get_aabb().size
			# TODO -- If this shield is the child of a node that is scaled to a different
					# value then one how to account for that?
			aabb_size *= self.scale
			if absf(aabb_size.x) > 0.0:
				self_volume *= aabb_size.x
			if absf(aabb_size.y) > 0.0:
				self_volume *= aabb_size.y
			if absf(aabb_size.z) > 0.0:
				self_volume *= aabb_size.z

			var object_volume: float = 0.0
			var size := Vector3.ZERO
			if collision_volume == 0.0:
				var sizes := PackedVector3Array()
				var collision_shapes: Array = []
				var bodies := []
				var owner_ids = object.get_shape_owners()
				for id in owner_ids:
					var shape_count: int = object.shape_owner_get_shape_count(id)
					var curr := 0
					while curr < shape_count:
						collision_shapes.append(object.shape_owner_get_shape(id, curr))
						curr += 1
				if collision_shapes.is_empty():
					push_warning("No Collision Shapes found that are owned by: ", object)
				
				assert(not collision_shapes.is_empty(), "No collision shapes found.")
				
				for col_shape in collision_shapes:
					if col_shape.is_class("SphereShape3D"):
						var radius: float = col_shape.radius * 2.0
						sizes.append(Vector3(radius, radius, radius))
					elif col_shape.is_class("BoxShape3D"):
						sizes.append(col_shape.size)
					else:
						# Else use the collision debug shape's aabb.
						var arraymesh : ArrayMesh = col_shape.get_debug_mesh()
						var aabb: AABB = arraymesh.get_aabb()
						# If the aabb was a sphere size.x would the the radius of the sphere
						var vec := Vector3()
						# AABB position is the origin of the box relative to the host_body.
						#print_debug("AABB position: ", aabb.position, " AABB size: ", aabb.size)
						vec = aabb.size.abs() #aabb.position.abs() + aabb.size.abs()
						#vec2.z = aabb.end.z
						#offsets.append(col_shape.position)
						sizes.append(vec)
					
					if sizes.size() == 1:
						size = sizes[0]
					else:
						for s in sizes:
							# Add offset of the collision shape
							#s += offsets[i]
							#s.x += offsets[i].x
							#s.y += offsets[i].y
							#s.z += offsets[i].z
							# Compare
							if s.x > size.x:
								size.x = s.x
							if s.y > size.y:
								size.y = s.y
							if s.z > size.z:
								size.z = s.z
									#i += 1
					# TODO -- Is this the only scale to account for?
					size *= object.scale
					object_volume = size.x * size.y * size.z
			else:
				object_volume = collision_volume
			# TODO -- Now I have the size differance . . . how to use it?
			#var differance_in_volume: float = self_volume - object_volume
			# TODO -- what is the best max to clamp to?
			# They need to be clamped differantly depending on if the shield is a 
			# plane or a sphere.
			var normalized_volume: float = 0.0
			var frequency_multi: float = 0.0
			var amplitude_multi: float = 0.0
			#print(" Object: ", object, " Object volume: ", object_volume, " Self: ", self_volume, " Dividend: ", object_volume / self_volume * self.scale.x)
			if self.mesh.is_class("PlaneMesh"):
				if size != Vector3.ZERO:
					object_volume = size.z * size.y
				var dividend: float = object_volume / self_volume * 2.0 * self.scale.x
				normalized_volume = remap(dividend, 0.0, 2.0, 0.3, 7.0)
				frequency_multi = clampf(remap(dividend, 0.0, 2.0, 8.5, 0.1), 0.001, 8.5)
				amplitude_multi = clampf(remap(dividend, 0.0, 2.0, 0.02, 10.5), 0.01, 10.5)
			else:
				var dividend: float = object_volume / self_volume * self.scale.x
				normalized_volume = remap(dividend, 0.0, 2.0, 0.2, 7.0)
				frequency_multi = clampf(remap(dividend, 0.0, 2.0, 7.5, 0.01), 0.01, 7.5)
				amplitude_multi = clampf(remap(dividend, 0.0, 2.0, 0.05, 2.5), 0.05, 2.5)
				#amplitude_multi = clampf(remap(dividend, 0.0, 2.0, 0.001, .05), 0.001, 0.05)
			#print("Object volume: ", object_volume, " Self volume: ", self_volume, " Normalized: ", normalized_volume)
			
			# Size, force, touch area, if this node is a child of rigidbody could use its
			# linear_velocity and current movement force to change ripple intensity.
			# TODO -- how to have an area3D based projectile be processed correctly?
				# Create a custome area3D script that approximates speed and passes
				# that data to this when it impacts the shield?
			var normalized_force: float = 1.0
			if is_parent_rigid_body and self.get_parent().is_class("RigidBody3D"):
				normalized_force = _get_impact_force(impact_force, self.get_parent())
			elif velocity_parent != null:
				normalized_force = _get_impact_force(impact_force, velocity_parent)
			else:
				var max_axis: float = 0.0
				match self.mesh.get_aabb().size.max_axis_index():
					Vector3.AXIS_X:
						max_axis = self.mesh.get_aabb().size.x
					Vector3.AXIS_Y:
						max_axis = self.mesh.get_aabb().size.y
					Vector3.AXIS_Z:
						max_axis = self.mesh.get_aabb().size.z
				normalized_force = impact_force.length() / max_axis
			
			
			# What to assign to each channel?
			var x: float = normalized_volume # Scale
			var y: float = normalized_force # Force: How to normalize it?
			var z: float = frequency_multi # Ripple frequency
			var a: float = amplitude_multi # Ripple amplitude
			color = Color(x, y, z, a)
			_data_image.set_pixel(index, 1, color)
			
			# Shader variables to be affected by these numbers:
				# 1) Radius Impact -- how big the wave is. Min 0.3. Max would between 3.0 and 5.0 (0.1, 5.0)
				# 2) _frequency_impact -- Default 20.0 (150.0, 5)
				# 3) _amplitude_impact -- Default 0.02 (0.001, .05)

		# Updating times after each impact seems to create a slight time imbalance.
		# Runs much objects_to_processsmoother without this.
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
		
		if object != null:
			objects_to_process.erase(object.name)


func is_approx_equal_by(float_1: float, float_2: float, variance: float) -> bool:
	var first_float: float = 0.0
	var second_float: float = 0.0
	# If a input float is negative then find the absolute value and double it so 
	# the two float can be subtracted correctly.
	if float_1 < 0:
		first_float = absf(float_1 + float_1)
	else:
		first_float = float_1
	if float_2 < 0:
		second_float = absf(float_2 + float_2)
	else:
		second_float = float_2
	var differance: float = abs(first_float - second_float)
	if differance < variance and differance > -variance:
		return true
	else:
		return false


func _physics_process(delta: float) -> void:
	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		update_material("_time_generate", _generate_time)
	else:
		if _generating_or_collapsing:
			_collapsed = !_collapsed
			_generating_or_collapsing = false

	# Objects that need to be checked to see if they need a ripple effect.
	# TODO -- How to process them?
	#var objects_to_be_processed: Array = []
	for body in $Area3D.get_overlapping_bodies():
		if not _objects_detected.has(body):
			_process_object(body)
			#objects_to_be_processed.append(body)
	for area in $Area3D.get_overlapping_areas():
		if not _objects_detected.has(area):
			_process_object(area)
			#objects_to_be_processed.append(area)
	#if not objects_to_be_processed.is_empty():
		#print(objects_to_be_processed.size())

	# Process _elapsed_times for each wave.
	var counter := 1
	while counter < _elapsed_time.size():
		if _elapsed_time[counter] < anim_time:
			var old_pixel_value: Color = _data_image.get_pixel(counter, 0)
			var normalized_time: float = _elapsed_time[counter] / anim_time
			# If animation is finished see if the body that triggered the wave
			# is still touching the shield.
	
			# Factor best between 0.1 and up.
			# TODO -- should this value be based on shader variables for impact ripple?
			var factor: float = 0.3 #0.2985 # 0.12 * 3.25
			# This is the best value for variance that I've found. Smaller values can miss
			# sometime and result in a missing wave. Bigger values can lead to infinity
			# loops of ever larger amounts of waves.
			var variance: float = 0.003 #0.0017
			var curve_sample: float = animation_curve.sample(normalized_time)
			# Need to use custom equal function so factor can be more precise then 0.1
			if _objects_detected[counter] != null and is_approx_equal_by(curve_sample, factor, variance):
			#if _objects_detected[counter] != null and is_equal_approx(normalized_time, factor):# is_approx_equal_by(normalized_time, factor, variance):
				_process_object(_objects_detected[counter])
			# Process _elapsed_time.
			
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

	# Simple way of cleaning up data. Runs after "data_cleanup_interval" of physics frames.
	if Engine.get_physics_frames() % data_cleanup_interval == 0:
		# Convert the image data into an array that can be processed.
		var raw_data: PackedColorArray = _data_image.get_data().to_color_array()

		# Test to see if the arrays are the same length.
		assert(_elapsed_time.size() * 2 == raw_data.size(), "_elapsed_time and raw_data are not the size 
				same size. Something is wrong." + str(_elapsed_time.size()) + ", " + str(raw_data.size()))
		assert(_objects_detected.size() == _elapsed_time.size(), "_objects_detected and _elapsed_time arrays
				are not the same size. Something is wrong.")

		# Remove entries were the animations have finished.
		# TODO -- Should a faster method be used here?
		counter = 0
		while counter < _elapsed_time.size() - 1:
			if _elapsed_time[counter] > anim_time:
				raw_data.remove_at(_elapsed_time.size() + counter)
				raw_data.remove_at(counter)
				_elapsed_time.remove_at(counter)
				_objects_detected.remove_at(counter)
			else:
				counter += 1
		_data_image.set_data(_elapsed_time.size(), _data_image.get_height(), false, Image.FORMAT_RGBAF, raw_data.to_byte_array())


func _process_object(object: Node3D) -> void:
	var space_state = get_world_3d().direct_space_state
	var start = self.global_position
	var end = object.global_position


	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = $Area3D/CollisionShape3D.shape
	shape_query.transform = $Area3D.global_transform
	shape_query.collide_with_areas = true
	# Use a collision mask to only detect collisions with the target object only.
	shape_query.collision_mask = tmp_impact_layer
	var coll_object: CollisionObject3D = null
	if object.is_class("CollisionObject3D"):
		coll_object = object
	else:
		for child in object.get_children():
			if child.is_class("CollisionObject3D"):
				coll_object = object

	var past_layers: int = coll_object.collision_layer
	assert(coll_object != null)

	coll_object.collision_layer = past_layers + tmp_impact_layer # set_collision_layer_value(tmp_impact_layer, true)

	# Find collision points.
	# TODO -- Should the max results be lowered?
	var collide_results: Array = space_state.collide_shape(shape_query)

	coll_object.collision_layer = past_layers

	# Process the points and find the area of intersection (to use with modifing the
	# size of the ripple created) and the center point to be the origin of the ripple.
	if collide_results.size() == 2:
		# If there is only one pair of vectors use the first one as the impact origin.
		#print("Object: ", object)
		impact(collide_results[0], object)
	elif not collide_results.is_empty():
		# Construct an array mesh and use the aabb from the created mesh to find the impact origin.
		var center_point: Vector3 = Vector3.ZERO
		
		#var vertex_array: PackedVector3Array = []
		
		var pos: Vector3 = collide_results[0]
		var neg: Vector3 = collide_results[0]
		
		var count: int = 0
		while count < collide_results.size() - 1:
			if count % 2 == 0:
#region Way 2
				if collide_results[count].x > pos.x:
					pos.x = collide_results[count].x
				if collide_results[count].x < neg.x:
					neg.x = collide_results[count].x
				if collide_results[count].y > pos.y:
					pos.y = collide_results[count].y
				if collide_results[count].y < neg.y:
					neg.y = collide_results[count].y
				if collide_results[count].z > pos.z:
					pos.z = collide_results[count].z
				if collide_results[count].z < neg.z:
					neg.z = collide_results[count].z
#endregion
				
#region Way 1
				#vertex_array.append(collide_results[count])
#endregion
			count += 1
		
		
#region Way 1
		#var array_mesh := ArrayMesh.new()
		#var arrays = []
		#arrays.resize(Mesh.ARRAY_MAX)
		#arrays[Mesh.ARRAY_VERTEX] = vertex_array
		#
		#array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		#
		#var arr_mesh_aabb: AABB = array_mesh.get_aabb()
		#center_point = arr_mesh_aabb.get_center()
		#var aabb_size: Vector3 = arr_mesh_aabb.size
		#var aabb_volume: float = aabb_size.x * aabb_size.y * aabb_size.z
		#print("")
		#print("Object: ", object, " Center: ", center_point, " AABB size: ", aabb_size, " Volume: ", aabb_volume)
#endregion
		
#region Way 2
		var aabb_size: Vector3 = Vector3.ZERO
		var aabb_volume: float = 1.0
		
		aabb_size.x = pos.x - neg.x
		aabb_size.y = pos.y - neg.y
		aabb_size.z = pos.z - neg.z
		# If the vector is tested against 0.0 it doesn't always work right.
		var min_value: float = 0.000001
		if aabb_size.x > min_value:
			aabb_volume *= aabb_size.x
		if aabb_size.y > min_value:
			aabb_volume *= aabb_size.y
		if aabb_size.z > min_value:
			aabb_volume *= aabb_size.z
		center_point = neg + aabb_size * 0.5
#endregion
		#print("Object: ", object, " Center: ", center_point, " AABB size: ", aabb_size, " Volume: ", aabb_volume)
		#print("")
		impact(center_point, object, aabb_volume)


	## Raycaste to the object from self.
	#var query = PhysicsRayQueryParameters3D.create(start, end)
	##query.collide_with_areas = true
	#for child in self.get_children():
		#if child.is_class("PhysicsBody3D"):
			#query.exclude.append(child)
	#query.hit_from_inside = false
	#var result_1 = space_state.intersect_ray(query)
#
	## Raycaste to self from object.
	#var query_2 = PhysicsRayQueryParameters3D.create(end, start)
	#query_2.collide_with_areas = true
	#query_2.exclude = [object]
	#query_2.hit_from_inside = false
	#var result_2 = space_state.intersect_ray(query_2)
#
	#if result_1 != {} and result_2 != {} and result_1.collider == object \
			#and result_2.collider == $Area3D:
		#var dis_to_1: float = self.global_position.distance_squared_to(result_1.position)
#
		## The distance from the center of self to the boundary of self's collision shape.
		#var dis_to_edge: float = 0.0
		#dis_to_edge = self.global_position.distance_squared_to(result_2.position)
#
		## The distance from the center of detected object's center and the edge of its collision shape.
		#var obj_dis_to_edge: float = object.global_position.distance_squared_to(result_2.position)
		#var differance: float = dis_to_1 - dis_to_edge
#
		## A value below zero means that the object is touching the shield. And if the
		## differance is greater then the negative value of the distance to the objects edge
		## then the object isn't fully inside the shield. 
		#if differance < 0 and differance > -obj_dis_to_edge:
			## Create a new ripple effect.
			#impact(result_2.position, object, true)
	#else:
		#if $Area3D.overlaps_body(object):
			## Find origin for new ripple.
			#var pos := Vector3.ZERO
			#if result_1 != {}:
				#pos = result_1.position
			#else:
				## Default to the detected object's origin?
				#pos = object.global_position
			## Create new ripple.
			#impact(pos, object, true)

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
		var body_force := Vector3.ZERO
		if body.is_class("RigidBody3D"):
			body_force = body.linear_velosity
		impact(body.global_position, body, false, body_force)
	body_entered.emit(body)


func _on_area_3d_body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
) -> void:
	if body_shape_entered_impact:
		var body_force := Vector3.ZERO
		if body.is_class("RigidBody3D"):
			body_force = body.linear_velosity
		impact(body.global_position, body, false, body_force)
	body_shape_entered.emit(body_rid, body, body_shape_index, local_shape_index)


# Load web-optimized shader that defines WEB preprocessor directive
func _load_web_shader() -> void:
	# Check if web shader exists, otherwise create it dynamically
	var web_shader_path = "res://addons/nojoule-energy-shield/shield_web.gdshader"
	if ResourceLoader.exists(web_shader_path):
		var web_shader = load(web_shader_path)
		material.shader = web_shader
		print("Loaded web-optimized shader")


func _get_impact_force(impact_force: Vector3, rigid_body: RigidBody3D) -> float:
	# Use parent's linear_velocity and incorperate impact_force
	# Combine forces to get a collision force?
	var force_tmp: Vector3 = rigid_body.linear_velocity + impact_force
	# Get length but how to normalized it? What is the max/base value?
	var max_force: float = rigid_body.mass * 1.0 # How to find the max force that can be exerted on the body?
	return force_tmp.length() / max_force
