shader_type spatial;

uniform sampler2D depth_texture : hint_depth_texture;

group_uniforms General;
/** Use quantization for alpha and color values to get a more pixelated look. */
uniform bool _quantization = true;
/** Quantization steps for the alpha and color values. */
uniform int _steps_quantization : hint_range(1, 20, 1) = 5;


/** The scale of the object, used to adjust the impact radius and frequency, to match the scaling of objects. Using the shield.gd script, the scale is set to the x-axis scale of the global transform automatically. */
uniform float _object_scale = 1.0;
/** Expected to be the maximum diameter of an object. If this is shorter the generation or collapse of the shield might not complete and stop early. */
uniform float _object_size = 1.0;

group_uniforms Visibility;
/** Turning this on makes the shield invisible by default and only visible on impacts. */
uniform bool _only_on_wave_visibility = false;
/** A lower value makes the shield be invisible faster after the impact. */
uniform float _start_falloff_visibility : hint_range(0, 1, 0.05) = 0.5;
/** A higher value makes the shield fading out process end sooner. */
uniform float _end_falloff_visibility : hint_range(0, 1, 0.05) = 0.3;
/** Modifies how fast the shield visibility progresses through the object, based on the distance to the impact origin. */
uniform float _time_multiplier_activation = 2.0;
/** Modifies the activation effect fading out over distance. */
uniform float _distance_multiplier_activation = 1.0;
/** The the width of the fading IN effect on impact makes the activation begin more smoothly. */
uniform float _width_time_activation = 0.2;

group_uniforms Intersection;
/** Enable/Disable the effect of highlighting the intersection of the shield with other objects. */
uniform bool _enable_highlight_intersection = true;
/** The width of the intersection highlight effect. */
uniform float _width_highlight_intersection = 1.0;


group_uniforms Noise;
/** The noise texture used to add some dynamic to the shield color, which affects the color and alpha values of the shield. Should be seamless, to avoid visible seams. */
uniform sampler2D _noise_texture;
/** Defines the rate at which the noise texture is displaced in the x and y direction. */
uniform vec2 _speed_noise = vec2(0.02, 0.02);

group_uniforms Generate_Collapse_Animation;
/** The origin of the shield generation, where the shield will start to generate from. By default, it is expected to be in local space. */
uniform vec3 _origin_generate = vec3(0.0, 0.5, 0.0);
/** The time of the generation or collapse animation, normalized between 0 and 1. */
uniform float _time_generate = 1.0;
/** The border thickness of the generated shield highlighting the just generated shield surface. */
uniform float _thickness_generate = 0.25;
/** By default this animation generates the shield, but if set to true, it will collapse the shield instead. */
uniform bool _collapse = false;

group_uniforms Shield_Color;
/** The base color of the shield, which is modifeid by the brightness and intensity. and varies across the shield surface. */
uniform vec3 _color_shield : source_color = vec3(0.26, 0.975, 1);
/** The brightness of the shield color, which is multiplied with the shield visibility. */
uniform float _color_brightness_shield : hint_range(0.1, 100.0, 0.05) = 15.0;
/** The intensity of the shield, defining how narrow the highlighting is. 0 is spread out, 5 is very narrow. */
uniform float _intensity_shield : hint_range(0.0, 5.0, 0.05) = 3.0;
/** Is glow effect enabled for the shield. */
uniform bool glow_enabled = true;
/** The strength of the glow effect, defining how strong the glow is. */
uniform float glow_strength = 0.1;

group_uniforms Static_Ripple;
/** Activates/deactivates the static ripple effect. Creating a constant repeating ripple effect. */
uniform bool _active_static = true;
/** The origin of the static ripple effect, where the ripple will start from. It is expected to be in local space of the object. */
uniform vec3 _origin_static = vec3(0.0, 0.5, 0.0);
/** The speed of the static ripple effect, which defines how fast the ripple moves. */
uniform float _speed_static = 0.1;
/** The frequency of the static ripple effect, which defines how close the waves are generated. */
uniform float _frequency_static = 80.0;
/** The maximum vertex displacement amplitude of the static ripple effect, which defines the height of the waves. */
uniform float _amplitude_static = 0.002;
/** The amplitude of the static ripple effect used for the normal calculation, which can be different from the displacement amplitude, to exaggerate visual effects based on the normal (fresnel). */
uniform float _normal_amplitude_static = 0.002;
/** The effect radius of the static ripple, which fades out the effect based on the distance from the origin. Increase this value to make the effect visible further away from the origin. */
uniform float _effect_radius_static = 1.2;
/** Activates/deactivates the static offset highlighting effect, which highlights the offset of the shield, based on the vertex displacement from static effects. */
uniform bool _active_static_offset_hl = true;
/** The strength of the static offset highlighting effect, defines how strong the highlighting is. */
uniform float _strength_static_offset_hl = 1.0;
/** The intensity of the static offset highlighting effect, defining how narrow the highlighting is. 0 is spread out, 5 is very narrow. */
uniform float _intensity_static_offset_hl = 5.0;
/** Defines if the coordinates of the origin is relative to the object position or in world space. */
uniform bool _relative_origin_static = true;

group_uniforms Impact_Ripple;
/** List of impact origins, where the impact ripples will start from. It is expected to be in world space. */
uniform vec3[5] _origin_impact;
/** List of impact times, which defines the time of the impact ripples, normalized between 0 and 1. */
uniform float[5] _time_impact;
/** The frequency of the impact ripples, which defines how close the waves are generated. */
uniform float _frequency_impact = 20.0;
/** The number of waves generated by the impact, which won't fade over time, but just by distance. */
uniform float _waves_impact = 0.0;
/** The additional number of waves generated by the impact, were each gets smaller than the previous one. */
uniform float _fade_waves_impact = 2.0;
/** The maximum vertex displacement amplitude of the static ripple effect, which defines the height of the waves. */
uniform float _amplitude_impact = 0.02;
/** The amplitude of the impact ripples used for the normal calculation, which can be different from the displacement amplitude, to exaggerate visual effects based on the normal (fresnel). */
uniform float _normal_amplitude_impact = 0.05;
/** The effect radius of the impact ripples, which fades out the effect based on the distance from the origin. Increase this value to make the effect visible further away from the origin. */
uniform float _radius_impact = 1.0;
/** Activates/deactivates the vertex offset highlighting effect, which highlights the offset of the shield, based on the vertex displacement from impact effects. */
uniform bool _active_impact_offset_hl = true;
/** The strength of the impact offset highlighting effect, defines how strong the highlighting is. */
uniform float _strength_impact_offset_hl = 1.0;
/** The intensity of the impact offset highlighting effect, defining how narrow the highlighting is. 0 is spread out, 5 is very narrow. */
uniform float _intensity_impact_offset_hl = 5.0;
/** Defines if the coordinates of the origin is relative to the object position or in world space. */
uniform bool _relative_origin_impact = false;

group_uniforms Border;
/** Activates/deactivates the border highlighting effect, which highlights the border of the shield, based on the UV coordinates. */
uniform bool _active_border = false;
/** The intensity of the border highlighting effect, defining how narrow the highlighting is. 0 is spread out, 5 is very narrow. */
uniform float _intensity_border: hint_range(0.0, 5.0, 0.05) = 2.0;
/** Thickness of the border in percentage. 1.0 makes the border stretch to the center of the object. 0.0 makes the border disappear. */
uniform float _percentage_border: hint_range(0.0, 1.0) = 0.1;

group_uniforms Debug;
/** @debug Show the normals of the shield, which are used for the normal calculation of the shield. */
uniform bool _show_normals = false;

#define SHIELD_FRONT

#include "shield_base.gdshaderinc"
