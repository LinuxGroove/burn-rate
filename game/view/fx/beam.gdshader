// An energy beam: zapper arcs, lasers and bolts. Drawn on a cylinder or a
// sphere, added on top of what's behind it, with a crawling bright core.
// `steady` (the Reduce flashing setting) stops it flickering.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

global uniform float steady;

uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float strength = 2.5;
// How much the core crawls along the beam (0 for a plain glow).
uniform float crawl = 1.0;
// The glow at the cylinder's edges (0 for a soft halo with no hard rim).
uniform float edge = 0.35;

// Dimmed when it's not in your lane, faded while charging.
instance uniform float dim = 0.0;
instance uniform float power = 1.0;
instance uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	// Brighter at the middle of the cylinder seen side on.
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, 2.5);
	float t = TIME * mix(14.0, 0.0, steady);
	float along = UV.y * 9.0;
	float wiggle = noise(along * 2.0 + t + seed * 13.0) * crawl;
	float flick = mix(0.75 + 0.25 * noise(t * 2.3 + seed * 7.0), 1.0, steady);
	float glow = (edge + core * 1.4 + wiggle * core * 0.8) * flick;
	vec3 c = mix(color.rgb, vec3(1.0), core * 0.55);
	ALBEDO = c * glow * strength * power * (1.0 - dim * 0.7);
}
