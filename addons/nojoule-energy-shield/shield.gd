class_name NJEnergyShield
extends MeshInstance3D

## Relay the body_entered signal from the Area3D to the shield.
signal body_entered(body: Node)

## Relay the body_shape_entered signal from the Area3D to the shield.
signal body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
)

## Signal for impact processing.
signal impact_queu_next()

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
@export var body_entered_impact: bool = false:
	set(i):
		body_entered_impact = i
		if i or body_shape_entered_impact:
			sustained_touch_effects = true
		else:
			sustained_touch_effects = false

## Trigger an impact when a body shape enters the shield.
@export var body_shape_entered_impact: bool = false:
	set(i):
		body_shape_entered_impact = i
		if i or body_entered_impact:
			sustained_touch_effects = true
		else:
			sustained_touch_effects = false

## When an object touches or is touching the shield trigger impacts.
@export var sustained_touch_effects: bool = false

## Incorperate speed in impact calculations.
@export var speed_impact_effect: bool = true

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

# The texture that will use data from _data_image
var _data_texture := ImageTexture.new()

# The current impact index, used to keep track of the impacts and overwrite the
# oldest impact if the maximum number of impacts is reached.
var _current_impact: int = 0

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

# The entry in the _ripple_process_dict that is at the end of the data image or texture.
var _last_entry_key: String = ""

# The frequancy of _data_image cleanup in physcis frames. A random number will be
# added to this to a max of 25% of this value. So not all cleanups happen in the
# same frame.
var data_cleanup_interval := 155

# Each entry being a dictionary with the following Keys: "object", "_elapsed_time", "X_Pixel", "Y_Pixel"
# The first entry is empty and stays that way because the image the data gets stored on
# has to have one pixel at least.
var _ripple_process_dict: Dictionary = {"empty_pixel" : {
		"object": "none",
		"_elapsed_time": 0.0,
		"X_Pixel": Color.BLACK,
		"Y_Pixel": Color.BLACK,
		"X_Index": 0
	}
}

# Current queue number to process.
var _curr_queue: int = 0:
	set(i):
		_curr_queue = i
		impact_queu_next.emit()

# End of the queue of impacts to process.
var _end_of_queue: int = 0

# Objects that are being processed by _impact function.
var objects_to_process: Dictionary = {}

# For use in adding velocity to impact calculations.
var _approx_velocity := Vector3.ZERO

# For calculating _approx_speed
var _last_frame_loc: Vector3 = Vector3(NAN, NAN, NAN)

## The material used for the shield, to set the shader parameters. It is
## expected to be the specific energy shield shader.
@onready var material: ShaderMaterial


func _ready() -> void:
	_last_frame_loc = self.global_position
	
	# Add a random amount to the cleanup interval so all shields don't cleanup
	# in the same frame.
	data_cleanup_interval += randi() % int(250 * 0.25)

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

	update_material("max_impacts", _ripple_process_dict.size())
	_data_texture = _data_texture.create_from_image(_data_image)
	update_material("_impact_texture", _data_texture)

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
func impact(pos: Vector3, object: CollisionObject3D = null, collision_volume: float = 0.0):
	if object == null or not objects_to_process.has(object):
		if object != null:
			objects_to_process[object] = true
		
		var space_in_queue = _end_of_queue
		_end_of_queue += 1
		while space_in_queue != _curr_queue:
			await impact_queu_next

		var impact_pos: Vector3 = pos
		if relative_impact_position:
			impact_pos = to_local(pos)

		var color = Color(impact_pos.x, impact_pos.y, impact_pos.z, 0.0)
		var color_2 = Color.WHITE
		var index: int = -1
		if _data_image.get_size() < Vector2i(impact_max, impact_max):
			_data_image.crop(_data_image.get_width() + 1, _data_image.get_height())
			_data_image.set_pixel(_data_image.get_width() - 1, 0, color)
			_data_image.set_pixel(_data_image.get_width() - 1, 1, color_2)
			index = _data_image.get_width() - 1
		else:
			_data_image.set_pixel(1, 0, color)
			_data_image.set_pixel(1, 1, color_2)
			index = 1
		
		if object != null:
			var self_volume: float = 1.0
			var aabb_size: Vector3 = self.mesh.get_aabb().size

			# This makes some compatibility with changes in scale but it doesn't produce a very
			# visually appealing result. Also parent scales are not taken into account.
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
						vec = aabb.size.abs()
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
					# Parent scales are not taken into account.
					size *= object.scale
					object_volume = size.x * size.y * size.z
			else:
				object_volume = collision_volume
			# They need to be clamped differantly depending on if the shield is a 
			# plane or a sphere.
			var normalized_volume: float = 1.0
			var frequency_multi: float = 1.0
			var amplitude_multi: float = 1.0
			if self.mesh.is_class("PlaneMesh"):
				if size != Vector3.ZERO:
					object_volume = size.z * size.y
				var dividend: float = object_volume / self_volume * self.scale.x
				normalized_volume = remap(dividend, 0.0, 2.0, 0.3, 5.0)
				frequency_multi = clampf(remap(dividend, 0.0, 1.6, 8.5, 2.0), 1.0, 5.5)
				amplitude_multi = clampf(remap(dividend, 0.0, 2.0, 0.05, 2.5), 0.05, 2.5)
			else:
				var dividend: float = object_volume / self_volume * self.scale.x
				normalized_volume = remap(dividend, 0.0, 2.0, 0.2, 7.0)
				frequency_multi = clampf(remap(dividend, 0.0, 2.0, 7.5, 0.01), 0.01, 7.5)
				amplitude_multi = clampf(remap(dividend, 0.0, 2.0, 0.05, 2.5), 0.05, 2.5)

			# Size, force, touch area, if this node is a child of rigidbody could use its
			# linear_velocity and current movement force to change ripple intensity.
			var normalized_force: float = 1.0
			if speed_impact_effect:
				if is_parent_rigid_body and self.get_parent().is_class("RigidBody3D"):
					normalized_force = _get_impact_force(object, self.get_parent())
				elif velocity_parent != null:
					normalized_force = _get_impact_force(object, velocity_parent)
				else:
					normalized_force = _get_impact_force(object)
			
			normalized_force = clampf(remap(normalized_force, 0.0, 1.0, 1.0, 2.0), 1.0, 5.0)
			var x: float = normalized_volume # Relative Size
			var y: float = normalized_force # Force: How to normalize it?
			var z: float = frequency_multi # Ripple frequency
			var a: float = amplitude_multi # Ripple amplitude
			color_2 = Color(x, y, z, a)
			_data_image.set_pixel(index, 1, color_2)
			
			# Shader variables to be affected by these numbers:
				# 1) Radius Impact -- how big the wave is. Min 0.3. Max would between 3.0 and 5.0 (0.1, 5.0)
				# 2) _frequency_impact -- Default 20.0 (150.0, 5)
				# 3) _amplitude_impact -- Default 0.02 (0.001, .05)

		# Create a new texture for the shader to use.
		#_data_texture = _data_texture.create_from_image(_data_image)

		var entry_key: int = int(index)
		
		_ripple_process_dict[entry_key] = {
			"object": object, 
			"_elapsed_time": 0.0, 
			"X_Pixel": color, 
			"Y_Pixel": color_2, 
			"X_Index": index
		}

		# Update shader variables.
		#update_material("_impact_texture", _data_texture)
		#update_material("max_impacts", _ripple_process_dict.size())
		#update_material("_relative_origin_impact", relative_impact_position)
		
		if object != null:
			objects_to_process.erase(object)

		_curr_queue += 1


func get_approx_velocity() -> Vector3:
	return _approx_velocity


func _physics_process(delta: float) -> void:
	# Recording shield's approximate speed for ripple effects.
	# Is this how you would find the velocity?
	_approx_velocity = _last_frame_loc - self.global_position
	_approx_velocity *= delta

	_last_frame_loc = self.global_position

	# update the shield generation or collapse animation
	if _generating_or_collapsing && _generate_time <= 1.0:
		_generate_time += delta
		update_material("_time_generate", _generate_time)
	else:
		if _generating_or_collapsing:
			_collapsed = !_collapsed
			_generating_or_collapsing = false

	# Objects that need to be checked to see if they need a wave effect.
	if sustained_touch_effects:
		var overlapping_bodies_areas: Array = []
		overlapping_bodies_areas.append_array($Area3D.get_overlapping_bodies())
		overlapping_bodies_areas.append_array($Area3D.get_overlapping_areas())
		
		var ripple_keys = _ripple_process_dict.keys()
		for object in overlapping_bodies_areas:
			if not objects_to_process.has(object):
				var found_key: bool = false
				for key in ripple_keys:
					if typeof(key) == TYPE_STRING and key == "empty_pixel":
						continue
					elif typeof(key) == TYPE_INT:
						var entry: Dictionary = _ripple_process_dict[key]
						if entry.get("object") == object and entry["_elapsed_time"] < anim_time:
							found_key = true
							break
				if not found_key:
					_process_object(object)

	# Process each wave.
	var count := 0
	var keys: Array = _ripple_process_dict.keys()
	while count < keys.size():
		var key = keys[count]
		if typeof(key) == TYPE_STRING and key.begins_with("empty_pixel"):
			count += 1
			continue
		else:
			count += 1
			var entry: Dictionary = _ripple_process_dict[key]
			if entry["_elapsed_time"] < anim_time:
				# Process _elapsed_times for each wave.
				var old_pixel_value: Color = _data_image.get_pixel(entry["X_Index"], 0)
				var normalized_time: float = entry["_elapsed_time"] / anim_time
				# If animation is finished see if the body that triggered the wave
				# is still touching the shield.
				# Factor best between 0.1 and up.
				var factor: float = 0.1
				var curve_sample: float = animation_curve.sample(normalized_time)
				if sustained_touch_effects and entry["object"] != null and normalized_time > \
						factor and not entry.has("checked"):
					entry["checked"] = true
					_process_object(entry["object"])
				
				var new_pixel_value: Color = Color(old_pixel_value.r, old_pixel_value.g, old_pixel_value.b, curve_sample)
				_data_image.set_pixel(entry["X_Index"], 0, new_pixel_value)
				entry["_elapsed_time"] += delta
			else:
				# Replace Dictionary Entry with Newest Impact
				var index: int = entry["X_Index"]
				if index < _data_image.get_width() - 1:
					var dict_size: int = _ripple_process_dict.size()
					var image_size: int = _data_image.get_width()
					assert(dict_size == image_size)
					var width: int = _data_image.get_width() - 1
					# Move pixel at the end of the image to the index that is finished animating.
					var last_entry: Dictionary = _ripple_process_dict[width]
					_data_image.set_pixel(index, 0, last_entry["X_Pixel"])
					_data_image.set_pixel(index, 1, last_entry["Y_Pixel"])
					_ripple_process_dict.set(key, last_entry)
					_ripple_process_dict.get(key).set("X_Index", index)
					# Remove newest impact.
					var result = _ripple_process_dict.erase(width)
					assert(result)
					_data_image.crop(_data_image.get_width() - 1, _data_image.get_height())
					keys.remove_at(keys.size() - 1)
				else:
					var result = _ripple_process_dict.erase(key)
					assert(result)
					_data_image.crop(_data_image.get_width() - 1, _data_image.get_height())

	# Simple way of cleaning up data. Runs after "data_cleanup_interval" of physics frames.
	#if Engine.get_physics_frames() % data_cleanup_interval == 0:
		#var removed_dict_entries: int = 0
		#
		#var keys: Array = _ripple_process_dict.keys()
		#
		#for key in keys:
			#if typeof(key) == TYPE_STRING and key != "empty_pixel":
				#pass
			#else:
				#var dict: Dictionary = _ripple_process_dict[key]
				#if dict["_elapsed_time"] > anim_time:
					#removed_dict_entries += 1
					#_ripple_process_dict.erase(key)
		#
		#_data_image.crop(_ripple_process_dict.size(), _data_image.get_height())
		#var x: int = 0
		#for entry in _ripple_process_dict:
			#var sub_dict: Dictionary = _ripple_process_dict[entry]
			#_data_image.set_pixel(x, 0, sub_dict["X_Pixel"])
			#_data_image.set_pixel(x, 1, sub_dict["Y_Pixel"])
			#sub_dict["X_Index"] = x
			#x += 1
		#
		#if removed_dict_entries > 1000:
			#push_warning("Shield.gd -- Removed over 1000 entries.")

	# Create texture for shader.
	_data_texture = _data_texture.create_from_image(_data_image)
	# Update shader variables.
	call_deferred("update_material", "_impact_texture", _data_texture)
	call_deferred("update_material", "max_impacts", _ripple_process_dict.size())
	update_material("_relative_origin_impact", relative_impact_position)


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

	coll_object.collision_layer = past_layers + tmp_impact_layer

	# Find collision points.
	# TODO -- Should the max results be lowered?
	var collide_results: Array = space_state.collide_shape(shape_query)

	coll_object.collision_layer = past_layers

	# Process the points and find the area of intersection (to use with modifing the
	# size of the ripple created) and the center point to be the origin of the ripple.
	if collide_results.size() == 2:
		# If there is only one pair of vectors use the first one as the impact origin.
		impact(collide_results[0], object)
	elif not collide_results.is_empty():
		# Construct an array mesh and use the aabb from the created mesh to find the impact origin.
		var center_point: Vector3 = Vector3.ZERO
		var pos: Vector3 = collide_results[0]
		var neg: Vector3 = collide_results[0]
		
		var count: int = 0
		while count < collide_results.size() - 1:
			if count % 2 == 0:
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
			count += 1
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
		impact(center_point, object, aabb_volume)


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
		impact(body.global_position, body, false)
	body_entered.emit(body)


func _on_area_3d_body_shape_entered(
	body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int
) -> void:
	if body_shape_entered_impact:
		impact(body.global_position, body, false)
	body_shape_entered.emit(body_rid, body, body_shape_index, local_shape_index)


# Load web-optimized shader that defines WEB preprocessor directive
func _load_web_shader() -> void:
	# Check if web shader exists, otherwise create it dynamically
	var web_shader_path = "res://addons/nojoule-energy-shield/shield_web.gdshader"
	if ResourceLoader.exists(web_shader_path):
		var web_shader = load(web_shader_path)
		material.shader = web_shader
		print("Loaded web-optimized shader")


func _get_impact_force(colliding_body: CollisionObject3D, rigid_body: RigidBody3D = null) -> float:
	# In order to calculate this correctly Area's that collide with this would need to have 
	# keep track of their velocity and transmit it to this script when they collide.
	# This script can have code that keeps track of its speed.
	
	# Use parent's linear_velocity and incorperate impact_force
	# Combine forces to get a collision force?
	var final_force := Vector3.ZERO
	var body_force := Vector3.ZERO
	if colliding_body.is_class("RigidBody3D"):
		final_force += colliding_body.linear_velocity
	else:
		if colliding_body.has_method("get_approx_velocity"):
			final_force += colliding_body.get_approx_velocity()
	if rigid_body != null:
		final_force += rigid_body.linear_velocity
	else:
		final_force += _approx_velocity
	var median: float = 0.0
	var size := self.mesh.get_aabb().size
	median = (size.x + size.y + size.z) / 3.0
	
	# TODO -- is there a better way of normalizing the force?
	final_force /= median
	final_force = final_force.clampf(0.0, 2.0)
	#var force_tmp: Vector3 = rigid_body.linear_velocity + impact_force
	# Get length but how to normalized it? What is the max/base value?
	# TODO -- make the ripple between 1.0 to 2.0 times bigger depending on if their is any force behind the impact?
			# This way the force can be estimated even if the collision body isn't controlled by the physics engine.
	#var max_force: float = rigid_body.mass * 1.0 # How to find the max force that can be exerted on the body?
	return final_force.length()
