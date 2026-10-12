// Ghosts (Daily Flight and Course ghosts): see-through, glowing at the
// edges, in one colour. Works on skinned bodies and packs alike.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float strength = 0.9;

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float a = 0.12 + pow(rim, 2.2) * 0.9;
	// Faint scan lines, still (they don't flicker).
	float scan = 0.85 + 0.15 * step(0.5, fract(FRAGCOORD.y * 0.25));
	ALBEDO = color.rgb * a * strength * scan;
}
