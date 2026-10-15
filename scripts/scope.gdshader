shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

const vec3 BLACK = vec3(0.0);
const vec2 HALF_UV = vec2(0.5);

uniform bool use_scope_effects = true;
uniform float scope_brightness : hint_range(0.0, 2.0, 0.01) = 1.0;

uniform sampler2D reticle_texture : repeat_disable;
uniform sampler2D scope_texture : source_color, repeat_disable;

uniform float scope_radius = 0.025;
uniform float reticle_depth = 2.0;
uniform float parallax_factor : hint_range(0.0, 0.3, 0.001) = 0.1;
uniform float view_edge_fade_factor : hint_range(0.0, 0.5, 0.001) = 0.05;
uniform float reticle_reference_distance = 0.15;
uniform float reticle_scale_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

group_uniforms Eyebox;
uniform float eyebox_position = 0.15;
uniform float eyebox_tolerance = 0.005;
uniform float eyebox_fade_distance = 0.05;

group_uniforms Scope_Shadow;
uniform float shadow_inner_radius : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float shadow_fade_factor = 0.2;
uniform float shadow_movement_factor : hint_range(0.5, 1.0, 0.01) = 1.0;

varying vec3 lens_view;
varying vec3 view_dir_vertex;
varying float eye_distance_vertex;

void vertex() {
lens_view = (
MODELVIEW_MATRIX * vec4(VERTEX, 1.0)
).xyz - (
MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)
).xyz;

vec3 eye_offset_vec = normalize(-VERTEX);
view_dir_vertex = eye_offset_vec * mat3(TANGENT, -BINORMAL, NORMAL);

eye_distance_vertex = length(
	NODE_POSITION_WORLD - CAMERA_POSITION_WORLD
);

}

void fragment() {
// Outer scope mask
float dist_from_center = length(lens_view);
float inside_scope = step(dist_from_center, scope_radius);

if (inside_scope <= 0.0) {
	discard;
}

// View direction and UV calculations
vec2 view_shift = view_dir_vertex.xy;

vec2 adj_uv = (
	UV - view_shift * (reticle_depth * 2.0) - HALF_UV
) * 0.5 + HALF_UV;

vec2 parallax_uv = mix(adj_uv, UV, parallax_factor);

// Scope texture
vec4 scope_sample = texture(scope_texture, adj_uv);
scope_sample.rgb *= scope_brightness;

// Eyebox, shadow and edge effects
if (use_scope_effects) {
	float delta = eye_distance_vertex - eyebox_position;

	float fade_near = 1.0 - smoothstep(
		-eyebox_tolerance - eyebox_fade_distance,
		-eyebox_tolerance,
		delta
	);

	float fade_far = smoothstep(
		eyebox_tolerance,
		eyebox_tolerance + eyebox_fade_distance,
		delta
	);

	float distance_fade = max(fade_near, fade_far);

	vec2 eye_offset = view_shift / -shadow_movement_factor;
	vec2 shifted_uv = UV - eye_offset;

	float shadow_dist = length(
		(shifted_uv - HALF_UV) * 2.0
	);

	float dynamic_radius = shadow_inner_radius * (
		1.0 - distance_fade
	);

	float shadow_fade = smoothstep(
		dynamic_radius - shadow_fade_factor,
		dynamic_radius,
		shadow_dist
	);

	float edge_dist = length(adj_uv - HALF_UV);

	float edge_fade = smoothstep(
		0.5 - view_edge_fade_factor,
		0.5,
		edge_dist
	);

	float total_fade = max(shadow_fade, edge_fade);

	scope_sample.rgb = mix(
		scope_sample.rgb,
		BLACK,
		total_fade
	);
}

// Reticle
float safe_eye_distance = max(eye_distance_vertex, 0.001);

float reticle_scale = pow(
	reticle_reference_distance / safe_eye_distance,
	reticle_scale_strength
);

vec2 reticle_uv = (
	parallax_uv - HALF_UV
) * reticle_scale + HALF_UV;

vec4 reticle_sample = texture(reticle_texture, reticle_uv);

// Final output
ALPHA = inside_scope;
ALBEDO = mix(
	scope_sample.rgb,
	reticle_sample.rgb,
	reticle_sample.a
);

}