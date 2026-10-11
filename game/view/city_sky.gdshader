// The night sky over the city, drawn on one far quad: deep blue overhead,
// the city's glow along the horizon, a few stars and a thin haze of
// clouds lit from below. It doesn't move or twinkle.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec3 zenith : source_color = vec3(0.01, 0.012, 0.035);
uniform vec3 mid : source_color = vec3(0.035, 0.03, 0.09);
uniform vec3 glow : source_color = vec3(0.45, 0.16, 0.32);
uniform vec3 haze : source_color = vec3(0.12, 0.07, 0.14);
// The horizon's height on the quad, in world metres.
uniform float horizon_y = 0.0;
uniform float stars = 1.0;
uniform float dim : hint_range(0.0, 1.0) = 1.0;

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = (wp.y - horizon_y) / length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float up = clamp(h * 2.2, 0.0, 1.0);
	vec3 c = mix(mid, zenith, smoothstep(0.0, 1.0, up));
	// The city's glow, strongest just above the horizon.
	float g = exp(-max(h, 0.0) * 9.0) * smoothstep(-0.25, 0.0, h);
	c += glow * g;
	// Below the horizon, haze over the far city.
	c = mix(c, haze, 1.0 - smoothstep(-0.08, 0.0, h));
	// Clouds lit from below, faint.
	vec2 cp = wp.xy * vec2(0.0016, 0.006);
	float cl = noise(cp) * 0.6 + noise(cp * 2.7) * 0.4;
	cl = smoothstep(0.55, 0.85, cl) * smoothstep(0.02, 0.12, h) * (1.0 - smoothstep(0.3, 0.7, h));
	c += glow * 0.35 * cl;
	// Stars, sparse and steady.
	vec2 sp = wp.xy * 0.18;
	vec2 cell = floor(sp);
	float r = hash12(cell);
	vec2 at = vec2(hash12(cell + 17.0), hash12(cell + 41.0));
	float s = (1.0 - smoothstep(0.0, 0.12, length(fract(sp) - at))) * step(0.93, r) * smoothstep(0.08, 0.3, h) * (1.0 - cl);
	c += vec3(0.8, 0.85, 1.0) * s * stars * (0.4 + r * 0.6);
	ALBEDO = c * dim;
}
