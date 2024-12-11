shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled, specular_disabled, ambient_light_disabled, unshaded;
//render_mode alpha_to_coverage; //, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture;

group_uniforms Shield_Color;
uniform vec3 _shield_color : source_color = vec3(0.26, 0.975, 1);
uniform float _shield_color_brightness : hint_range(0.25, 20.0, 0.05) = 15.0;
uniform float _shield_intensity : hint_range(0.25, 5.0, 0.05) = 3.0;

group_uniforms Shield_Transform;
instance uniform float object_scale = 1.0;
//uniform vec3 _rotation = vec3(0.0, 0.0, 0.0);

group_uniforms Impact_Shape;
instance uniform vec3 _impact_origin = vec3(0.0, 1.0, 0.0);
instance uniform float _impact_frequency = 20.0;
instance uniform float _impact_waves = 0.0;
instance uniform float _impact_fade_waves = 2.0;
instance uniform float _impact_amplitude = 0.04;
instance uniform float _impact_radius = 1.0;
instance uniform float _impact_time: hint_range(0.0, 1.0, 0.005) = 0.0;
instance uniform float _impact_normal_amplitude = 0.1;


uniform bool _quantization = true;

group_uniforms BorderHighlight;
uniform bool _hightlight_border = false;
uniform float _highlight_border_intensity = 1.0;
uniform float _highlight_border_percentage: hint_range(0.0, 1.0) = 0.1;

group_uniforms WaveHighlight;
uniform bool _highlight_wave = false;
uniform float _highlight_wave_intensity = 1.0;


varying vec3 world_pos;
varying float impact_ripple;
varying flat float denormalized_time;

// === IMPACT ===

float denormalizeTime(float time, float frequenzy, float waves, float max_distance) {
	return time * (0.5 * PI + 2.0 * PI * waves + max_distance * frequenzy) / frequenzy - 0.5 * PI / frequenzy; //(((max_distance / frequenzy) / 2.0 * PI) + waves);
}

float _ComputeRipple(vec3 vertex, vec3 origin, float radius, float frequency, float waves, float fade_waves, float amplitude, float time) {
	float impact_distance = length(origin - vertex);
	float current_wave_position = max((time - impact_distance) * frequency, - 0.5 * PI);
	float current_surface_offset = -sin(current_wave_position) * amplitude * 0.5 - amplitude * 0.5;
	float current_wave_count = current_wave_position / (2.0 * PI);
	float time_fade = 1.0 - smoothstep(waves, waves + fade_waves, current_wave_count);
	return current_surface_offset * smoothstep(radius, 0.0, impact_distance) * time_fade;
}

// === SHIELD ===

float ComputeFresnel(vec3 norm, vec3 view_dir, float intensity) {
	// dot product between mesh normals and view direction
	float fresnel = clamp(1.0 - dot(norm, view_dir), 0.0, 1.0);
	// modulate fresnel intensity
	fresnel = pow(fresnel, intensity);
	return fresnel;
}

vec3 Rotate(vec3 vert, vec3 speed) {
	// build the 3 rotation matrices
	speed = speed * TIME * 5.0;

	mat4 xrot = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, cos(speed.x), -sin(speed.x), 0.0),
		vec4(0.0, sin(speed.x), cos(speed.x), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));

	mat4 yrot = mat4(
		vec4(cos(speed.y), 0.0, -sin(speed.y), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(sin(speed.y), 0.0, cos(speed.y), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));

	mat4 zrot = mat4(
		vec4(cos(speed.z), -sin(speed.z), 0.0, 0.0),
		vec4(sin(speed.z), cos(speed.z), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));

	return (xrot * yrot * zrot * vec4(vert, 1.0)).xyz;
}

vec3 calculateNormal3D(vec3 tangent) {
    vec3 binormal = vec3(0.0, 0.0, 1.0); // Assume z-axis binormal
    vec3 normal = cross(normalize(tangent), binormal);
    return normal;
}

vec3 calculateWaveNormal(float x, float amplitude, float frequency, float phase) {
    float slope = cos(frequency * x + phase) * frequency * amplitude;
	return calculateNormal3D(normalize(vec3(1.0, -slope, 0.0)));
}

vec3 updateNormal(vec3 position, vec3 origin, float radius, float frequency, float waves, float fade_waves, float amplitude, float time, vec3 normal, mat4 model_view, bool backface) {
	float impact_distance = length(origin - position);
	float current_wave_position = max((time - impact_distance) * frequency, - 0.5 * PI);
	float current_wave_count = current_wave_position / (2.0 * PI);
	float wave_phase = -impact_distance * frequency;
	if (current_wave_count < waves + fade_waves && (time - impact_distance) * frequency >= - 0.5 * PI) {
		float time_fade = 1.0 - smoothstep(waves, waves + fade_waves, current_wave_count);
		float wave_amplitude = amplitude * smoothstep(radius, 0.0, impact_distance) * time_fade;
		vec3 waveNormal = -calculateWaveNormal(time, wave_amplitude, frequency, wave_phase);
		if (!backface) {
			waveNormal = vec3(-waveNormal.x, waveNormal.y, waveNormal.z);
		}
		vec3 impact_to_current = normalize(position - origin);
		impact_to_current = normalize((model_view * vec4(impact_to_current, 0.0)).xyz);

		vec3 wave_normal_binormal = normalize(cross(normal, impact_to_current));
		vec3 wave_tangent = normalize(cross(normal, wave_normal_binormal));
		vec3 wave_adjusted_normal = normalize(waveNormal.x * wave_tangent + waveNormal.y * normal);
		return wave_adjusted_normal;
	}
	return normal;
}



void vertex() {
	// rotate VERTICES in local space
	//VERTEX = Rotate(VERTEX, _rotation);
	// ...and relative NORMALS for the fresnel effect to work
	//NORMAL = Rotate(NORMAL, _rotation);

	// world_position of the vertex
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;


	denormalized_time = denormalizeTime(
		_impact_time,
		_impact_frequency / object_scale,
		_impact_waves + _impact_fade_waves,
		_impact_radius * object_scale
	);

	impact_ripple = _ComputeRipple(
		world_pos,
		_impact_origin,
		_impact_radius * object_scale,
		_impact_frequency / object_scale,
		_impact_waves,
		_impact_fade_waves,
		_impact_amplitude,
		denormalized_time
	);

	VERTEX += NORMAL * impact_ripple;
}

void fragment() {
	NORMAL = updateNormal(
		world_pos,
		_impact_origin,
		_impact_radius * object_scale,
		_impact_frequency / object_scale,
		_impact_waves,
		_impact_fade_waves,
		_impact_normal_amplitude * object_scale,
		denormalized_time,
		NORMAL,
		VIEW_MATRIX,
		FRONT_FACING
	);
	//ALBEDO = vec3((NORMAL.x + 1.0)/2.0, (NORMAL.y + 1.0)/2.0, (NORMAL.z + 1.0)/2.0);

	float f = ComputeFresnel(NORMAL, VIEW, _shield_intensity);

	float n_in2p0 = 0.50000 * object_scale;
	float depth_tex = texture(depth_texture, SCREEN_UV).r;
	vec4 depth_world_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	depth_world_pos.xyz /= depth_world_pos.w;
	float depth_diff = clamp(smoothstep(depth_world_pos.z + n_in2p0, depth_world_pos.z, VERTEX.z), 0.0, 1.0);
	depth_diff = pow(depth_diff, 5.0);
	float shield_visibility = max(f, depth_diff);

	if (_highlight_wave) {
		shield_visibility = max(shield_visibility, -_highlight_wave_intensity * impact_ripple/_impact_amplitude);
	}

	if (_hightlight_border) {
		float border_closeness = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
		float border_visibility = clamp(_highlight_border_percentage - border_closeness * 2.0, 0.0, _highlight_border_percentage) / _highlight_border_percentage;
		border_visibility = pow(border_visibility, _highlight_border_intensity);
		shield_visibility = max(shield_visibility, border_visibility);
	}

	//quantization
	if (_quantization) {
		shield_visibility = round(shield_visibility * (5.0 + 1.0 * object_scale))/5.0;
	}

	ALBEDO = pow(shield_visibility, _shield_intensity) * _shield_color_brightness * _shield_color;
	ALPHA = shield_visibility;
}
