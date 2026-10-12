// A seeker's lock-on reticle: a ring with four ticks that closes in while
// it tracks and turns solid red when it locks. Billboarded; drawn over
// everything nearby so it reads on top of the pilot.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

global uniform float steady;

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.15, 1.0);

// 0 tracking to 1 locked.
instance uniform float lock = 0.0;
instance uniform float spin = 0.0;
instance uniform float dim = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float c = cos(spin);
	float s = sin(spin);
	p = mat2(vec2(c, -s), vec2(s, c)) * p;
	float r = length(p);
	float ring = smoothstep(0.06, 0.0, abs(r - 0.72)) * (lock > 0.99 ? 1.0 : step(0.25, abs(fract(atan(p.y, p.x) / 6.2832 * 4.0 + 0.125) - 0.5)));
	float ticks = 0.0;
	ticks += step(abs(p.x), 0.035) * step(0.45, abs(p.y)) * step(abs(p.y), 0.95);
	ticks += step(abs(p.y), 0.035) * step(0.45, abs(p.x)) * step(abs(p.x), 0.95);
	float dot_c = smoothstep(0.08, 0.0, r) * lock;
	float pulse = mix(0.65 + 0.35 * step(0.5, fract(TIME * 6.0)), 1.0, steady);
	float a = (ring + ticks * 0.9 + dot_c) * mix(0.8, pulse * 1.4, lock);
	vec3 col = mix(vec3(1.0, 0.75, 0.3), color.rgb, lock);
	ALBEDO = col * a * 1.8 * (1.0 - dim * 0.6);
}
