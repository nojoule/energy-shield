shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled,
specular_disabled, ambient_light_disabled, unshaded;

uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D noise_texture;
uniform vec2 _speed_noise = vec2(0.05, 0.05);

/**
 *
 */
uniform bool _quantization = true;
uniform int _steps_quantization : hint_range(1, 20, 1) = 5;
instance uniform float object_scale = 1.0;

group_uniforms Create_Destroy;
uniform vec3 _origin_create = vec3(0.0, 0.5, 0.0);
uniform float _time_create = 0.0;
uniform float _speed_create = 1.0;
uniform float _thickness_create = 0.05;
uniform bool _destroy = false;

group_uniforms Shield_Color;
uniform vec3 _color_shield : source_color = vec3(0.26, 0.975, 1);
uniform float _color_brightness_shield : hint_range(0.25, 20.0, 0.05) = 15.0;
uniform float _intensity_shield : hint_range(0.25, 5.0, 0.05) = 3.0;

group_uniforms Static_Ripple;
uniform bool _active_static = true;
uniform vec3 _origin_static = vec3(0.0, 0.5, 0.0);
uniform float _speed_static = 0.1;
uniform float _frequency_static = 80.0;
uniform float _amplitude_static = 0.002;
uniform float _effect_radius_static = 1.2;
uniform float _normal_amplitude_static = 0.002;

group_uniforms Impact_Ripple;
uniform vec3[5] _origin_impact;
uniform float _frequency_impact = 20.0;
uniform float _waves_impact = 0.0;
uniform float _fade_waves_impact = 2.0;
uniform float _amplitude_impact = 0.02;
uniform float _radius_impact = 1.0;
uniform float[5] _time_impact; //: hint_range(0.0, 1.0, 0.005)[];
uniform float _normal_amplitude_impact = 0.05;

group_uniforms BorderHighlight;
uniform bool _active_border = false;
uniform float _intensity_border = 2.0;
uniform float _percentage_border: hint_range(0.0, 1.0) = 0.1;

group_uniforms OffsetHighlight;
uniform bool _active_impact_offset_hl = true;
uniform float _strength_impact_offset_hl = 1.0;
uniform float _intensity_impact_offset_hl = 5.0;
uniform bool _active_static_offset_hl = true;
uniform float _strength_static_offset_hl = 1.0;
uniform float _intensity_static_offset_hl = 5.0;

group_uniforms Debug;
uniform bool _show_normals = false;

varying vec3 world_pos;
varying float impact_offset;
varying float static_offset;
varying flat vec3 origin_static_world;
varying flat vec3 origin_create_world;

const int max_impacts = 5;

/*
* time is expected to be normalized between 0 and 1. Denormalize it to the
* actual time based on the frequency, desired waves and maximum distance.
*/
float denormalizeTime(
	float time,
	float frequency,
	float waves,
	float max_distance
) {
	float length = 0.5 * PI + 2.0 * PI * waves + max_distance * frequency;
	float wave_start_offset = 0.5 * PI;
	return (time * length - wave_start_offset) / frequency;
}

float computeImpactOffset(
	vec3 vertex,
	vec3 origin,
	float radius,
	float frequency,
	float waves,
	float fade_waves,
	float amplitude,
	float time
) {
	float impact_distance = length(origin - vertex);
	float wave_position =
		max((time - impact_distance) * frequency, - 0.5 * PI);
	float surface_offset = -sin(wave_position) * amplitude;

	// offset for the first half of the sin wave to start at 0 offset
	if (wave_position < 0.5 * PI) {
		surface_offset = surface_offset * 0.5 - 0.5 * amplitude;
	}

	float current_wave = wave_position / (2.0 * PI);
	float time_fade =
		1.0 - smoothstep(waves, waves + fade_waves, current_wave);
	float distance_fade = smoothstep(radius, 0.0, impact_distance);
	return surface_offset * distance_fade * time_fade;
}

float computeStaticOffset(
	vec3 vertex,
	vec3 origin,
	float radius,
	float frequency,
	float amplitude,
	float time
) {
	float impact_distance = length(origin - vertex);
	float wave_position = (time - impact_distance) * frequency;
	float surface_offset = -sin(wave_position) * amplitude;
	float distance_fade = smoothstep(radius, 0.0, impact_distance);
	return surface_offset * distance_fade;
}

float computeFresnel(vec3 norm, vec3 view_dir, float intensity) {
	float fresnel = clamp(1.0 - dot(norm, view_dir), 0.0, 1.0);
	fresnel = pow(fresnel, intensity);
	return fresnel;
}

vec3 calculateNormalFromTangent(vec3 tangent) {
    vec3 binormal = vec3(0.0, 0.0, 1.0); // Assume z-axis binormal
    vec3 normal = cross(normalize(tangent), binormal);
    return normal;
}

float calculateSlope(
	float time,
	float amplitude,
	float frequency,
	float phase
) {
    return cos(frequency * time + phase) * frequency * amplitude;
}

vec3 adjustNormal(
	vec3 wave_direction,
	float slope,
	vec3 normal,
	bool backface
) {
	vec3 waveNormal = -calculateNormalFromTangent(normalize(vec3(1.0, -slope, 0.0)));;
	if (!backface) {
		waveNormal = vec3(-waveNormal.x, waveNormal.y, waveNormal.z);
	}
	vec3 wave_normal_binormal = normalize(cross(normal, wave_direction));
	vec3 wave_tangent = normalize(cross(normal, wave_normal_binormal));
	vec3 wave_adjusted_normal =
		normalize(waveNormal.x * wave_tangent + waveNormal.y * normal);
	return wave_adjusted_normal;
}

vec3 adjustImpactNormal(
	vec3 position,
	vec3 origin,
	float radius,
	float frequency,
	float waves,
	float fade_waves,
	float amplitude,
	float time,
	vec3 normal,
	mat4 model_view,
	bool backface
) {
	float distance = length(origin - position);
	float wave_phase = -distance * frequency;
	float current_wave_position =
		max((time - distance) * frequency, - 0.5 * PI);
	float current_wave_count = current_wave_position / (2.0 * PI);
	if (current_wave_count < waves + fade_waves
			&& (time - distance) * frequency >= - 0.5 * PI) {
		float time_fade =
			1.0 - smoothstep(waves, waves + fade_waves, current_wave_count);
		float distance_fade = smoothstep(radius, 0.0, distance);
		vec3 wave_direction = normalize(position - origin);
		wave_direction =
			normalize((model_view * vec4(wave_direction, 0.0)).xyz);
		float wave_amplitude = amplitude * distance_fade * time_fade;
		float slope = calculateSlope(time, wave_amplitude, frequency, wave_phase);
		return adjustNormal(
			wave_direction,
			slope,
			normal,
			backface
		) * wave_amplitude * abs(slope);
	}
	return normal * 0.00001;
}

vec3 adjustStaticNormal(
	vec3 position,
	vec3 origin,
	float radius,
	float frequency,
	float amplitude,
	float time,
	vec3 normal,
	mat4 model_view,
	bool backface
) {
	float distance = length(origin - position);
	float wave_phase = -distance * frequency;
	float distance_fade = smoothstep(radius, 0.0, distance);
	vec3 wave_direction = normalize(position - origin);
	wave_direction = normalize((model_view * vec4(wave_direction, 0.0)).xyz);
	float wave_amplitude = amplitude * distance_fade;
	float slope = calculateSlope(time, wave_amplitude, frequency, wave_phase);
	return adjustNormal(
		wave_direction,
		slope,
		normal,
		backface
	) * wave_amplitude * abs(slope);
}

float computeDepthDifference(
	vec2 screen_uv,
	vec3 vertex,
	mat4 inv_projection,
	float intensity
) {
	float depth_offset = 1.0/_intensity_shield * object_scale;
	float depth_tex = texture(depth_texture, screen_uv).r;
	vec4 proj_depth_pos = vec4(screen_uv * 2.0 - 1.0, depth_tex, 1.0);
	vec4 depth_world_pos = inv_projection * proj_depth_pos;
	depth_world_pos.xyz /= depth_world_pos.w;
	float depth_diff = clamp(
		smoothstep(depth_world_pos.z + depth_offset, depth_world_pos.z, vertex.z),
		0.0,
		1.0
	);
	depth_diff = pow(depth_diff, 5.0);
	return depth_diff;
}

float computeCreated(
	vec3 vertex,
	vec3 origin,
	float thickness,
	float speed,
	float time
) {
	float impact_distance = length(origin - vertex);
	float wave_position = (time * speed - impact_distance) / thickness;
	float current_wave = wave_position / (2.0 * PI);
	return clamp(current_wave, 0.0, 1.0);
}

void vertex() {
	// world_position of the vertex
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	impact_offset = 0.0;
	for(int i=0;i<max_impacts;++i)
	{
		if (_time_impact[i] > 0.0 && _time_impact[i] < 1.0) {
			float denormalized_time = denormalizeTime(
				_time_impact[i],
				_frequency_impact / object_scale,
				_waves_impact + _fade_waves_impact,
				_radius_impact * object_scale
			);

			impact_offset += computeImpactOffset(
				world_pos,
				_origin_impact[i],
				_radius_impact * object_scale,
				_frequency_impact / object_scale,
				_waves_impact,
				_fade_waves_impact,
				_amplitude_impact,
				denormalized_time
			);
		}		
	}
	
	if (_active_static) {
		origin_static_world = (MODEL_MATRIX * vec4(_origin_static, 1.0)).xyz;
		static_offset = computeStaticOffset(
			world_pos,
			origin_static_world,
			_effect_radius_static * object_scale,
			_frequency_static / object_scale,
			_amplitude_static,
			TIME * _speed_static
		);
	} else {
		static_offset = 0.0;
	}

	origin_create_world = (MODEL_MATRIX * vec4(_origin_create, 1.0)).xyz;

	VERTEX += NORMAL * (impact_offset + static_offset);
}

void fragment() {
	if (_show_normals && !FRONT_FACING) discard;

	vec3 static_normal = vec3(0.0);
	if (_active_static) {
		static_normal = adjustStaticNormal(
			world_pos,
			origin_static_world,
			_effect_radius_static * object_scale,
			_frequency_static / object_scale,
			_normal_amplitude_static * object_scale,
			TIME * _speed_static,
			NORMAL,
			VIEW_MATRIX,
			FRONT_FACING
		);
	}

	vec3 impact_normal = vec3(0.0);
	for(int i=0;i<max_impacts;++i)
	{
		if (_time_impact[i] > 0.0 && _time_impact[i] < 1.0) {
			float denormalized_time = denormalizeTime(
				_time_impact[i],
				_frequency_impact / object_scale,
				_waves_impact + _fade_waves_impact,
				_radius_impact * object_scale
			);

			impact_normal += adjustImpactNormal(
				world_pos,
				_origin_impact[i],
				_radius_impact * object_scale,
				_frequency_impact / object_scale,
				_waves_impact,
				_fade_waves_impact,
				_normal_amplitude_impact * object_scale,
				denormalized_time,
				NORMAL,
				VIEW_MATRIX,
				FRONT_FACING
			);
		}
	}

	NORMAL = normalize(static_normal + impact_normal);

	float shield_visibility = computeFresnel(NORMAL, VIEW, _intensity_shield);

	if (_active_impact_offset_hl) {
		float impact_offset_hl = pow(
			-_strength_impact_offset_hl * impact_offset/_amplitude_impact,
			_intensity_impact_offset_hl
		);
		shield_visibility = max(shield_visibility, impact_offset_hl);
	}

	if (_active_static_offset_hl) {
		float static_offset_hl = pow(
			-_strength_static_offset_hl * static_offset/_amplitude_static,
			_intensity_static_offset_hl
		);
		shield_visibility = max(shield_visibility, static_offset_hl);
	}

	float depth_diff =
		computeDepthDifference(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, _intensity_shield);
	shield_visibility = max(shield_visibility, depth_diff);

	if (_active_border) {
		float border_closeness = min(
			min(UV.x, UV.y),
			min(1.0 - UV.x, 1.0 - UV.y)
		);
		float border_visibility = clamp(
			_percentage_border - border_closeness * 2.0,
			0.0,
			_percentage_border
		) / _percentage_border;
		border_visibility = pow(border_visibility, _intensity_border);
		shield_visibility = max(shield_visibility, border_visibility);
	}

	float creation_status = computeCreated(
		world_pos,
		origin_create_world,
		_thickness_create,
		_speed_create,
		TIME - _time_create
		//mod(TIME, 2.0/_speed_create)
	);
	if (_destroy) {
		if (creation_status >= 1.0) {
			shield_visibility = 0.0;
		} else {
			float creation_visibility = pow(creation_status, 5.0);
			shield_visibility = max(shield_visibility, creation_visibility);
		}
	} else {
		if (creation_status <= 0.0) {
			shield_visibility = 0.0;
		} else {
			float creation_visibility = pow(1.0 - creation_status, 5.0);
			shield_visibility = max(shield_visibility, creation_visibility);
		}
	}

	shield_visibility = shield_visibility * (texture(noise_texture, vec2(UV.x + TIME * _speed_noise.x, UV.y - TIME * _speed_noise.y)).r + 0.5);

	//quantizations
	if (_quantization) {
		shield_visibility = round(shield_visibility * (
			float(_steps_quantization) + 1.0 * object_scale))/float(_steps_quantization);
	}

	if (_show_normals) {
		ALBEDO = vec3(
			(NORMAL.x + 1.0)/2.0,
			(NORMAL.y + 1.0)/2.0,
			(NORMAL.z + 1.0)/2.0
		);
		ALPHA = 1.0;
	} else {
		ALBEDO = pow(shield_visibility, _intensity_shield)
			* _color_brightness_shield * _color_shield;
		ALPHA = clamp(shield_visibility, 0.0, 1.0);
	}
}
