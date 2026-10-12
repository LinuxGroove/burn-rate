// A jetpack's flame: drawn on a cone hanging from the nozzle (UV.y 0 at the
// nozzle, 1 at the tip), added on top of what's behind it. White-hot at the
// nozzle, the pack's colour along the plume, fading to nothing at the tip.
// `heat` (the Burn) makes it hotter, adds shock diamonds and a blue core.
// `steady` (the Reduce flashing setting) calms the flicker.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

global uniform float steady;

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float strength = 2.4;

// 0 to 1: how hard it's firing, and how hot (the Burn level).
instance uniform float power = 1.0;
instance uniform float heat = 0.0;
instance uniform float seed = 0.0;

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
	float t = clamp(UV.y, 0.0, 1.0);
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, 1.6);
	float speed = mix(9.0, 1.5, steady);
	float n = noise(vec2(UV.x * 6.0 + seed * 3.1, t * 5.0 - TIME * speed));
	float n2 = noise(vec2(UV.x * 11.0 - seed, t * 9.0 - TIME * speed * 1.7));
	float turb = mix(n * 0.6 + n2 * 0.4, 0.55, steady * 0.5);
	// Fades along its length, ragged at the tip.
	float len = 1.0 - smoothstep(0.25 + turb * 0.35, 1.0, t);
	float hot = 1.0 - smoothstep(0.0, 0.16 + heat * 0.2, t);
	vec3 c = mix(color.rgb, vec3(1.0, 0.95, 0.85), hot * core);
	// The Burn: a blue-white core and shock diamonds.
	float diamonds = pow(0.5 + 0.5 * cos(t * 34.0 - TIME * mix(2.0, 0.0, steady)), 10.0) * (1.0 - t) * heat;
	c = mix(c, vec3(0.65, 0.85, 1.0), heat * core * hot * 0.7);
	float glow = (0.2 + core * 0.75) * len * (0.75 + turb * 0.5) + diamonds * core * 1.2;
	// The plume reddens and thins as it cools towards the tip.
	c = mix(c, c * vec3(1.0, 0.55, 0.35), smoothstep(0.35, 1.0, t) * (1.0 - heat * 0.5));
	ALBEDO = c * glow * strength * power * (1.0 + heat * 0.6);
}
