render_mode shadows_disabled, specular_disabled,
ambient_light_disabled, unshaded

#ifdef SHIELD_BACK
	,cull_front
#else
	#ifdef SHIELD_FRONT
		,cull_back, depth_draw_opaque
	#else
		,cull_disabled, depth_draw_opaque
	#endif
#endif
;

varying smooth vec3 world_pos;
varying smooth float impact_offset;
varying smooth float static_offset;
varying flat vec3 origin_static_world;
varying flat vec3 origin_generate_world;

/** Maximum number of impacts, which can be used to generate impact ripples. */
const int max_impacts = 5;

float easeInEaseOut(float t) {
	return t * t * 3.0 - 2.0 * t * t * t;
}

/**
* Time is expected to be normalized between 0 and 1. Denormalize it to the actual time based on the frequency, desired waves and maximum distance.
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

/**
 * Compute the offset for the vertex position from impacts.
 */
float computeImpactOffset(
	vec3 origin_offset,
	float radius,
	float frequency,
	float waves,
	float fade_waves,
	float amplitude,
	float time
) {
	float impact_distance = length(origin_offset);
	// the wave starts at -sin(-0.5 * PI)
	float wave_position =
		max((time - impact_distance) * frequency, - 0.5 * PI);

	float surface_offset = -sin(wave_position) * amplitude;

	// -sin(-0.5 * PI) is 1.0, but to start with an offset of 0 from the original vertex position, we modify the displacement for the first part of the wave to only displace inward. This prevents the mesh to be inflated by default.
	if (wave_position < 0.5 * PI) {
		surface_offset = surface_offset * 0.5 - 0.5 * amplitude;
	}

	// to have a smooth surface at the origin of the wave, we blend the surface offset near the origin
	if (impact_distance <= PI/frequency) {
		float wave_impact_position = (time) * frequency;
		float blend_surface_offset = -sin(wave_impact_position) * amplitude;
		if (wave_impact_position < 0.5 * PI) {
			blend_surface_offset = blend_surface_offset * 0.5 - 0.5 * amplitude;
		}
		float blend = easeInEaseOut(
			clamp(impact_distance / (PI/frequency), 0.0, 1.0));
		surface_offset = mix(blend_surface_offset, surface_offset, blend);
	}

	// fade out the waves over time after the initial waves are through for the fade_waves
	float current_wave = wave_position / (2.0 * PI);
	float time_fade =
		1.0 - smoothstep(waves, waves + fade_waves, current_wave);

	// fade out the waves over distance
	float distance_fade = smoothstep(radius, 0.0, impact_distance);

	return surface_offset * distance_fade * time_fade;
}

/**
 * Compute the offset for the vertex position from static waves.
 */
float computeStaticOffset(
	vec3 origin_offset,
	float radius,
	float frequency,
	float amplitude,
	float time
) {
	float impact_distance = length(origin_offset);
	float wave_position = (time - impact_distance) * frequency;
	float surface_offset = -sin(wave_position) * amplitude;

	// to have a smooth surface at the origin of the wave, we blend the surface offset near the origin
	if (impact_distance < PI/frequency) {
		float wave_impact_position = (time) * frequency;
		float blend_surface_offset = -sin(wave_impact_position) * amplitude;
		float blend = easeInEaseOut(
			clamp(impact_distance / (PI/frequency), 0.0, 1.0));
		surface_offset = mix(blend_surface_offset, surface_offset, blend);
	}

	// fade out the waves over distance
	float distance_fade = smoothstep(radius, 0.0, impact_distance);

	return surface_offset * distance_fade;
}

/**
 * Compute the fresnel effect based on the normal and view direction.
 */
float computeFresnel(vec3 normal, vec3 view_dir, float intensity) {
	float fresnel = clamp(1.0 - dot(normal, view_dir), 0.0, 1.0);
	fresnel = pow(fresnel, intensity);
	return fresnel;
}

/**
 * Calculate the normal from the tangent of the wave.
 */
vec3 calculateNormalFromTangent(vec3 tangent) {
    vec3 binormal = vec3(0.0, 0.0, 1.0); // Assume z-axis binormal
    vec3 normal = cross(normalize(tangent), binormal);
    return normal;
}

/**
 * Calculate the slope at the current surface position on a sinus wave.
 */
float calculateSlope(
	float time,
	float amplitude,
	float frequency,
	float phase
) {
    return -cos(frequency * time + phase) * frequency * amplitude;
}

/**
 * Adjust the default normal based on the wave direction and current slope of the wave.
 */
vec3 adjustNormal(
	vec3 wave_direction,
	float wave_slope,
	vec3 orig_normal,
	bool backface
) {
	vec3 wave_tangent = vec3(1.0, wave_slope, 0.0);
	vec3 wave_normal = -calculateNormalFromTangent(wave_tangent);
	if (!backface) {
		wave_normal = vec3(-wave_normal.x, wave_normal.y, wave_normal.z);
	}
	vec3 binormal = normalize(cross(orig_normal, wave_direction));
	vec3 surface_tangent = normalize(cross(orig_normal, binormal));
	vec3 wave_adjusted_normal =
		normalize(wave_normal.x * surface_tangent + wave_normal.y * orig_normal);
	return wave_adjusted_normal;
}

/**
 * Adjust the normal based on the wave generated from an impact and check if the effect is active at the position based on the time.
 */
vec3 adjustImpactNormal(
	vec3 origin_offset,
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
	float distance = length(origin_offset);
	float wave_phase = -distance * frequency;
	float current_wave_position =
		max((time - distance) * frequency, - 0.5 * PI);
	float current_wave_count = current_wave_position / (2.0 * PI);

	// check if all impact waves have passed the current fragment position
	if (current_wave_count < waves + fade_waves
			&& (time - distance) * frequency >= - 0.5 * PI) {
		// fade out the waves over time after the initial waves are through for the fade_waves
		float time_fade =
			1.0 - smoothstep(waves, waves + fade_waves, current_wave_count);
		// fade out the waves over distance
		float distance_fade = smoothstep(radius, 0.0, distance);

		// calculate direction and the slope of the wave at the current position
		vec3 wave_direction = normalize(-origin_offset);
		wave_direction =
			normalize((model_view * vec4(wave_direction, 0.0)).xyz);
		float wave_amplitude = amplitude * distance_fade * time_fade;
		float slope = calculateSlope(time, wave_amplitude, frequency, wave_phase);

		// to have a smooth surface at the origin of the wave, we blend the surface offset near the origin
		if (distance < PI/frequency) {
			float blend = easeInEaseOut(
				clamp(distance / (PI/frequency), 0.0, 1.0));
			slope = mix(0.0, slope, blend);
		}

		return adjustNormal(
			wave_direction,
			slope,
			normal,
			backface
		) * wave_amplitude * abs(slope);
	}
	return normal * 0.00001;
}

/**
 * Adjust the normal based on the wave generated from a static effect.
 */
vec3 adjustStaticNormal(
	vec3 origin_offset,
	float radius,
	float frequency,
	float amplitude,
	float time,
	vec3 normal,
	mat4 model_view,
	bool backface
) {
	float distance = length(origin_offset);

	// fade out the waves over distance
	float distance_fade = smoothstep(radius, 0.0, distance);

	// calculate direction and the slope of the wave at the current position
	float wave_phase = -distance * frequency;
	vec3 wave_direction = normalize(-origin_offset);
	wave_direction = normalize((model_view * vec4(wave_direction, 0.0)).xyz);
	float wave_amplitude = amplitude * distance_fade;
	float slope = calculateSlope(time, wave_amplitude, frequency, wave_phase);

	// to have a smooth surface at the origin of the wave, we blend the surface offset near the origin
	if (distance < PI/frequency) {
		float blend = easeInEaseOut(
			clamp(distance / (PI/frequency), 0.0, 1.0));
		slope = mix(0.0, slope, blend);
	}

	return adjustNormal(
		wave_direction,
		slope,
		normal,
		backface
	) * wave_amplitude * abs(slope);
}

float getAffectionStrengthStatic(
	vec3 origin_offset,
	float radius
) {
	float distance = length(origin_offset);
	return smoothstep(radius, 0.0, distance);
}

float getAffectionStrengthImpact(
	vec3 origin_offset,
	float radius,
	float frequency,
	float waves,
	float fade_waves,
	float time
) {
	float distance = length(origin_offset);
	float wave_phase = -distance * frequency;
	float current_wave_position = (time - distance) * frequency;
	float current_wave_count = current_wave_position / (2.0 * PI);

	float time_fade = 1.0 - clamp(
		(time - _start_falloff_visibility) /
		(1.0 - _start_falloff_visibility - _end_falloff_visibility),
		0.0,
		1.0
	);
	float distance_fade = smoothstep(radius * _distance_multiplier_activation, 0.0, distance);

	float norm_distance = clamp(distance/radius, 0.0, 1.0);
	float activate_threshold = clamp(time * _time_multiplier_activation, 0.0, 1.0);

	if (activate_threshold < norm_distance) {
		return 0.0;
	} else if (activate_threshold - _width_time_activation < norm_distance) {
		float activation_fade = smoothstep(activate_threshold, activate_threshold - _width_time_activation, norm_distance);
		return easeInEaseOut(activation_fade) * distance_fade * time_fade;
	} else {
		return distance_fade * time_fade;
	}
}

#ifndef WEB
/**
 * Compute the highlight effect, based on the distance to any object behind the shield-surface.
 */
float computeDepthDifference(
	vec2 screen_uv,
	vec3 vertex,
	mat4 inv_projection,
	float intensity,
	float width
) {
	// calculate a value representing the distance to any object behind the shield
	float depth_offset = width/_intensity_shield * _object_scale;
	float depth_tex = texture(depth_texture, screen_uv).r;
	vec4 proj_depth_pos = vec4(screen_uv * 2.0 - 1.0, depth_tex, 1.0);
	vec4 depth_world_pos = inv_projection * proj_depth_pos;
	depth_world_pos.xyz /= depth_world_pos.w;
	float depth_diff = clamp(
		smoothstep(depth_world_pos.z + depth_offset, depth_world_pos.z, vertex.z),
		0.0,
		1.0
	);

	// apply intensity to the depth difference to create the highlight strength
	depth_diff = pow(depth_diff, intensity);
	return depth_diff;
}
#endif

/**
 * Compute the progression of the shield generation or collapse, normalized between 0.0 and 1.0, based on the distance to the origin and the time.
 */
float computeGenerationProgress(
	vec3 vertex,
	vec3 origin,
	float thickness,
	float size,
	float time
) {
	float impact_distance = length(origin - vertex);
	return clamp(((time * (1.0 + thickness)) * size - impact_distance) / (thickness * size), 0.0, 1.0);
}

void vertex() {
	// world_position of the vertex
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// calculate the vertex displacement from dynamic impact effects
	impact_offset = 0.0;
	for(int i=0;i<max_impacts;++i)
	{
		// transform the generation origin to world space
		vec3 origin_impact = _origin_impact[i];
		if (_relative_origin_impact) {
			origin_impact = (MODEL_MATRIX * vec4(origin_impact, 1.0)).xyz;
		}
		vec3 origin_impact_offset = (origin_impact - world_pos);
		if (_relative_origin_impact) {
			origin_impact_offset = origin_impact_offset / _object_scale;
		}
		if (_time_impact[i] > 0.0 && _time_impact[i] < 1.0) {
			float denormalized_time = denormalizeTime(
				_time_impact[i],
				_frequency_impact,
				_waves_impact + _fade_waves_impact,
				_radius_impact
			);

			impact_offset += computeImpactOffset(
				origin_impact_offset,
				_radius_impact,
				_frequency_impact,
				_waves_impact,
				_fade_waves_impact,
				_amplitude_impact,
				denormalized_time
			);
		}
	}

	// calculate the vertex displacement from the static wave effect
	if (_active_static) {

		// transform the static origin to world space
		if (_relative_origin_static) {
			origin_static_world = (MODEL_MATRIX * vec4(_origin_static, 1.0)).xyz;
		} else {
			origin_static_world = _origin_static;
		}
		vec3 origin_static_offset = (origin_static_world - world_pos);
		if (_relative_origin_static) {
			origin_static_offset = origin_static_offset / _object_scale;
		}
		static_offset = computeStaticOffset(
			origin_static_offset,
			_effect_radius_static,
			_frequency_static,
			_amplitude_static,
			TIME * _speed_static
		);
	} else {
		static_offset = 0.0;
	}

	// transform the generation origin to world space
	if (true) {
		origin_generate_world = (MODEL_MATRIX * vec4(_origin_generate, 1.0)).xyz;
	} else {
		origin_generate_world = _origin_generate;
	}

	VERTEX += NORMAL * (impact_offset + static_offset);
}

void fragment() {
	// discard backfacing fragments when the debug option for showing normals is active
	//if (_show_normals && !FRONT_FACING) discard;

	float effect_visibility = 0.0;

	// calculate the modified normal based on static wave traveling across the shield surface
	vec3 static_normal = vec3(0.0);
	if (_active_static) {
		vec3 origin_static_offset = (origin_static_world - world_pos);
		if (_relative_origin_static) {
			origin_static_offset = origin_static_offset / _object_scale;
		}
		static_normal = adjustStaticNormal(
			origin_static_offset,
			_effect_radius_static,
			_frequency_static,
			_normal_amplitude_static,
			TIME * _speed_static,
			NORMAL,
			VIEW_MATRIX,
			FRONT_FACING
		);
		if (_only_on_wave_visibility) {
			float static_affection = getAffectionStrengthStatic(
				origin_static_offset,
				_effect_radius_static
			);
			effect_visibility = max(effect_visibility, static_affection);
		}
	}

	// calculate the modified normal based on impact waves traveling across the shield surface
	vec3 impact_normal = vec3(0.0);
	for(int i=0;i<max_impacts;++i)
	{
		// transform the generation origin to world space
		vec3 origin_impact = _origin_impact[i];
		vec3 origin_impact_offset = (origin_impact - world_pos);
		if (_relative_origin_impact) {
			origin_impact = (MODEL_MATRIX * vec4(origin_impact, 1.0)).xyz;
			origin_impact_offset = origin_impact_offset / _object_scale;
		}
		if (_time_impact[i] > 0.0 && _time_impact[i] < 1.0) {
			float denormalized_time = denormalizeTime(
				_time_impact[i],
				_frequency_impact,
				_waves_impact + _fade_waves_impact,
				_radius_impact
			);

			impact_normal += adjustImpactNormal(
				origin_impact_offset,
				_radius_impact,
				_frequency_impact,
				_waves_impact,
				_fade_waves_impact,
				_normal_amplitude_impact,
				denormalized_time,
				NORMAL,
				VIEW_MATRIX,
				FRONT_FACING
			);
			if (_only_on_wave_visibility) {
				float impact_affection = getAffectionStrengthImpact(
					origin_impact_offset,
					_radius_impact,
					_frequency_impact,
					_waves_impact,
					_fade_waves_impact,
					_time_impact[i]
				);
				effect_visibility = max(effect_visibility, impact_affection);
			}
		}
	}

	// combine the normals and normalize the result, this is the new surface normal at this fragment
	vec3 new_normal = normalize(static_normal + impact_normal  + 0.001 * NORMAL);
	NORMAL = new_normal;

	// calculate the shield visibility, which determines the color and transparency of the shield.
	float shield_visibility = 0.0;

	shield_visibility = computeFresnel(NORMAL, VIEW, _intensity_shield);

	// apply surface displacement highlight for impacts
	if (_active_impact_offset_hl) {
		float impact_offset_hl = pow(
			-_strength_impact_offset_hl * impact_offset/_amplitude_impact,
			_intensity_impact_offset_hl
		);
		shield_visibility = max(shield_visibility, impact_offset_hl);
	}

	// apply surface displacement highlight for static waves
	if (_active_static_offset_hl) {
		float static_offset_hl = pow(
			-_strength_static_offset_hl * static_offset/_amplitude_static,
			_intensity_static_offset_hl
		);
		shield_visibility = max(shield_visibility, static_offset_hl);
	}

#ifndef WEB
	if (_enable_highlight_intersection) {
		// apply depth difference highlight for objects behind the shield
		float depth_diff = computeDepthDifference(
			SCREEN_UV,
			VERTEX,
			INV_PROJECTION_MATRIX,
			_intensity_shield,
			_width_highlight_intersection
		);
		shield_visibility = max(shield_visibility, depth_diff);
	}
#endif

	// apply border highlighting
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

	// apply shield generation or collapse animation highlight
	float creation_progress = computeGenerationProgress(
		world_pos,
		origin_generate_world,
		_thickness_generate,
		_object_scale * _object_size,
		_time_generate
		//mod(TIME, 1.0 / _object_scale) //see the effect looping
	);
	if (_collapse) {
		if (creation_progress >= 1.0) {
			shield_visibility = 0.0;
		} else {
			float creation_visibility = pow(creation_progress, 5.0);
			shield_visibility = max(shield_visibility, creation_visibility);
		}
	} else {
		if (creation_progress <= 0.0) {
			shield_visibility = 0.0;
		} else {
			float creation_visibility = pow(1.0 - creation_progress, 5.0);
			shield_visibility = max(shield_visibility, creation_visibility);
		}
	}

	// modify value by noise texture to the shield visibility
	shield_visibility = shield_visibility * (texture(
		_noise_texture,
		vec2(UV.x + TIME * _speed_noise.x, UV.y - TIME * _speed_noise.y)
	).r + 0.5);

	// apply quantization for the value
	if (_quantization) {
		float quantization_offset = 1.0;
		shield_visibility = round(shield_visibility * (
			float(_steps_quantization) + quantization_offset))
			/ float(_steps_quantization);
	}

	if (_show_normals) {
		ALBEDO = vec3(
			(NORMAL.x + 1.0)/2.0,
			(NORMAL.y + 1.0)/2.0,
			(NORMAL.z + 1.0)/2.0
		);
		ALPHA = 1.0;
	} else {
		vec3 color = pow(shield_visibility, _intensity_shield)
			* _color_brightness_shield * _color_shield;
		vec3 clamped_color = vec3(
			clamp(color.r, 0.0, 1.0),
			clamp(color.g, 0.0, 1.0),
			clamp(color.b, 0.0, 1.0)
		);

		if (glow_enabled) {
			ALBEDO = clamped_color + glow_strength * (color - clamped_color);
		} else {
			ALBEDO = clamped_color;
		}
		if (!_only_on_wave_visibility) effect_visibility = 1.0;
		else effect_visibility = mix(
			0.0, 1.0, easeInEaseOut(effect_visibility));
		ALPHA = clamp(shield_visibility, 0.0, 1.0) * effect_visibility;
	}
}
