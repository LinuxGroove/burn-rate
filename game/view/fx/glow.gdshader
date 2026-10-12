// Glowing particles and flashes, added on top of the scene: sparks (soft
// dots, or streaks when the particles stretch along their velocity), rings
// for shockwaves and star glints for pickups. The colour comes from the
// particle (COLOR, its alpha fading it) times `tint`, an instance uniform,
// so one material serves every colour.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

global uniform float steady;

// 0 dot, 1 streak, 2 ring, 3 star glint.
uniform int shape = 0;
uniform float strength = 2.0;
// Billboarded in the shader rather than by the particles (rings, glints).
uniform bool billboard = false;

instance uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = 0.0;
	if (shape == 0) {
		a = pow(max(1.0 - r, 0.0), 2.0);
	} else if (shape == 1) {
		a = pow(max(1.0 - abs(p.x), 0.0), 2.0) * pow(max(1.0 - abs(p.y), 0.0), 0.7);
	} else if (shape == 2) {
		a = pow(max(1.0 - abs(r - 0.78) * 7.0, 0.0), 1.5) + pow(max(1.0 - r, 0.0), 3.0) * 0.25;
	} else {
		float star = max(max(1.0 - abs(p.x) * 9.0, 0.0) * max(1.0 - abs(p.y), 0.0), max(1.0 - abs(p.y) * 9.0, 0.0) * max(1.0 - abs(p.x), 0.0));
		a = star + pow(max(1.0 - r * 1.6, 0.0), 2.0);
	}
	vec3 c = COLOR.rgb * tint.rgb;
	// Hot centres go white.
	c = mix(c, vec3(1.0), clamp(a - 0.6, 0.0, 1.0) * 0.8);
	ALBEDO = c * a * COLOR.a * tint.a * strength;
}
