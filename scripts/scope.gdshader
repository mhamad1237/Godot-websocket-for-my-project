shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

uniform sampler2D reticle_texture : source_color, repeat_disable;
uniform sampler2D scope_texture : source_color, repeat_disable;
uniform float scope_radius = 0.025;
uniform bool scope_enabled = false;
uniform float scope_brightness : hint_range(0.0, 2.0, 0.01) = 0.8;

varying vec3 lens_view;

void vertex() {
	lens_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz
		- (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	if (length(lens_view) > scope_radius) {
		discard;
	}
	if (!scope_enabled) {
		ALBEDO = vec3(0.0);
	} else {
		vec4 scope_sample = texture(scope_texture, UV);
		vec4 reticle_sample = texture(reticle_texture, UV);
		vec3 scope_rgb = scope_sample.rgb * scope_brightness;
		ALBEDO = mix(scope_rgb, reticle_sample.rgb, reticle_sample.a);
	}
}