// Soft smoke and dust puffs. The particle's COLOR carries the colour and
// its fade; `tint` (an instance uniform) shades the whole system.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(1.0);

varying float pid;

void vertex() {
	pid = float(INSTANCE_ID);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Each puff gets its own lumps from where it is.
	vec2 o = vec2(pid * 0.37, pid * 0.71);
	float n = noise(p * 2.5 + o) * 0.6 + noise(p * 5.0 - o) * 0.4;
	float a = smoothstep(1.0, 0.2, length(p) + (n - 0.5) * 0.6);
	ALBEDO = COLOR.rgb * tint.rgb * (0.8 + n * 0.3);
	ALPHA = a * COLOR.a * tint.a;
}
