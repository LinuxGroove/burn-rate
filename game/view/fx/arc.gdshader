// A zapper's arc: a thin cylinder (along its local Y, with rings along it)
// bent into crackling lightning in the vertex shader, pinned at both ends.
// Several strands with different seeds make the bolt; `steady` (Reduce
// flashing) slows the crackle to a smooth writhe and stops the flicker.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

global uniform float steady;

uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float strength = 2.5;
// How far the strand wanders, in the cylinder's own radii.
uniform float jitter = 3.0;

instance uniform float dim = 0.0;
instance uniform float power = 1.0;
instance uniform float seed = 0.0;
// The arc's length in metres, so the kinks stay the same size.
instance uniform float span = 3.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	float t = VERTEX.y + 0.5;
	float env = sin(3.14159 * clamp(t, 0.0, 1.0));
	// Crackles: jumps to a new shape twenty times a second (smoothly when steady).
	float clock = mix(floor(TIME * 22.0 + seed * 3.0), TIME * 1.5, steady);
	float k = t * span * 1.6;
	float ox = (noise(k + clock * 7.13 + seed * 31.0) - 0.5) * 2.0 + (noise(k * 2.7 + clock * 3.1 + seed * 7.0) - 0.5) * 0.8;
	float oz = (noise(k + clock * 5.71 + seed * 17.0 + 40.0) - 0.5) * 2.0;
	VERTEX.xz += vec2(ox, oz) * jitter * env;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, 2.0);
	float flick = mix(0.7 + 0.3 * hash(floor(TIME * 30.0) + seed * 9.0), 1.0, steady);
	vec3 c = mix(color.rgb, vec3(1.0), core * 0.7);
	ALBEDO = c * (0.3 + core * 1.5) * flick * strength * power * (1.0 - dim * 0.7);
}
