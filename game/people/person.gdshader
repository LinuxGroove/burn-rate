// Kestrel Lift's people: flight suits, lab coats, office suits and Halberd's
// uniforms, drawn on Quaternius' Universal Base Characters. Works from the
// rest pose baked by Person.bake (CUSTOM0 the position, CUSTOM1 how much of
// each vertex is head, hand and foot), so it needs no UVs and sticks to a
// moving body.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// 0 flight suit, 1 lab coat, 2 office suit, 3 uniform, 4 overalls.
uniform int outfit = 0;
uniform vec3 main_color : source_color = vec3(0.12, 0.13, 0.16);
uniform vec3 accent : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 shirt : source_color = vec3(0.85, 0.86, 0.9);
uniform vec3 legs : source_color = vec3(0.12, 0.12, 0.14);
uniform vec3 skin : source_color = vec3(0.78, 0.56, 0.44);
uniform vec3 glove : source_color = vec3(0.1, 0.1, 0.11);
uniform vec3 boot : source_color = vec3(0.07, 0.07, 0.08);

// Lit up when hit or knocked, for a moment.
instance uniform float hurt = 0.0;
// Ghosts and far-lane pilots fade a little.
instance uniform float dim = 0.0;

varying vec3 rest;
varying vec3 region;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	rest = CUSTOM0.xyz;
	region = CUSTOM1.xyz;
}

void fragment() {
	vec3 p = rest;
	float head = region.x;
	float hand = region.y;
	float foot = region.z;
	float ax = abs(p.x);
	// Arms stick out sideways in the rest pose.
	float arm = smoothstep(0.24, 0.3, ax) * step(1.2, p.y);
	float upper = step(0.98, p.y);
	vec3 c = legs;
	float rough = 0.8;
	if (outfit == 0) {
		// Flight suit: one colour, accent panels down the sides and arms,
		// a chest harness and knee pads.
		c = main_color;
		float side = smoothstep(0.035, 0.025, abs(ax - 0.17)) * step(0.55, p.y) * step(p.y, 1.42);
		float sleeve = smoothstep(0.03, 0.02, abs(p.z - 0.0)) * arm;
		float harness = smoothstep(0.022, 0.012, abs(p.y - 1.2 + ax * 0.6)) * step(ax, 0.2) * step(0.0, p.z);
		float belt = smoothstep(0.03, 0.02, abs(p.y - 1.0));
		float knee = smoothstep(0.07, 0.05, abs(p.y - 0.5)) * step(0.02, p.z);
		c = mix(c, accent, max(side, sleeve));
		c = mix(c, vec3(0.05, 0.05, 0.06), max(max(harness, belt), knee * 0.8));
		rough = 0.55;
	} else if (outfit == 1) {
		// Lab coat to the knees over a shirt and trousers.
		float coat = step(0.52, p.y) * (1.0 - head);
		float open_front = smoothstep(0.04, 0.03, ax) * step(p.y, 1.42) * step(0.0, p.z) * step(1.0, p.y);
		c = mix(legs, main_color, coat);
		c = mix(c, shirt, open_front);
		float pocket = smoothstep(0.004, 0.0, abs(p.y - 1.3)) * step(0.06, p.x) * step(p.x, 0.16) * step(0.0, p.z);
		c *= 1.0 - pocket * 0.3;
	} else if (outfit == 2) {
		// Office suit: jacket, shirt and tie.
		c = mix(legs, main_color, upper);
		float vneck = step(ax, (1.48 - p.y) * 0.25) * step(1.18, p.y) * step(0.0, p.z);
		float tie = smoothstep(0.022, 0.015, ax) * step(1.08, p.y) * step(0.0, p.z);
		c = mix(c, shirt, vneck);
		c = mix(c, accent, tie * vneck + tie * step(p.y, 1.2) * step(1.08, p.y));
	} else if (outfit == 3) {
		// Halberd Security: dark uniform, a stripe on the arms and a vest.
		c = main_color;
		float stripe = smoothstep(0.025, 0.015, abs(ax - 0.42)) * step(1.3, p.y);
		float vest = upper * step(ax, 0.22) * step(p.y, 1.45);
		c = mix(c, main_color * 0.6, vest);
		c = mix(c, accent, stripe);
		rough = 0.6;
	} else {
		// Overalls over a shirt.
		c = mix(main_color, shirt, arm + step(1.32, p.y) * 0.85);
		c = mix(c, accent, smoothstep(0.02, 0.012, abs(p.y - 1.0)));
	}
	c *= mix(0.85, 1.05, noise3(p * 8.0));
	c = mix(c, skin, head);
	c = mix(c, glove, hand);
	c = mix(c, boot, foot);
	ALBEDO = mix(c, vec3(1.0, 0.9, 0.85), clamp(hurt, 0.0, 1.0) * 0.5) * (1.0 - dim * 0.4);
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	EMISSION = vec3(1.0, 0.5, 0.3) * clamp(hurt, 0.0, 1.0) * 0.4;
}
