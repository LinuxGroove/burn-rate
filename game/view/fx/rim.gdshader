// A glowing edge laid over Halberd's robots (as a material overlay), so
// they read against the dark: full in your lane, faint in the others.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

instance uniform vec4 rim_color : source_color = vec4(1.0, 0.35, 0.2, 1.0);
instance uniform float rim = 1.0;

void fragment() {
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	ALBEDO = rim_color.rgb * f * rim * 1.4;
}
