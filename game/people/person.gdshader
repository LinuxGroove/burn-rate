// Kestrel Lift's people: flight suits, lab coats, office suits and Halberd's
// uniforms, drawn on Quaternius' Universal Base Characters. Works from the
// rest pose baked by Person.bake (CUSTOM0 the position, CUSTOM1 how much of
// each vertex is head, hand and foot), so it needs no UVs and sticks to a
// moving body. The rest pose is a T-pose facing +z, feet at 0.
//
// Clothes also have a little bulk: boots, gloves, collars, pads and the
// harness push the skin out along its normal, so they stand out from the
// body rather than being painted flat on it.
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
// Flight suits: the harness, pads, boots and gloves.
uniform vec3 trim : source_color = vec3(0.06, 0.06, 0.07);
// Where the hands start along the arms (the female body's are shorter).
uniform float wrist = 0.66;

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

float band(float v, float at, float half_width) {
	return smoothstep(half_width + 0.008, half_width, abs(v - at));
}

// The flight suit's harness straps, pads and boots: 0 to 1 how much each
// point is covered, for both the colour and the bulk.
float harness(vec3 p) {
	float ax = abs(p.x);
	float torso = step(ax, 0.24) * step(p.y, 1.47);
	// Shoulder straps down the chest and back.
	float straps = band(ax, 0.1 - (1.45 - p.y) * 0.03, 0.018) * step(0.98, p.y) * torso;
	// A chest strap, a belt and leg loops.
	float chest = band(p.y, 1.24, 0.016) * torso * step(0.0, p.z);
	float belt = band(p.y, 0.99, 0.024) * torso;
	float loops = band(p.y + ax * 0.25, 0.83, 0.016) * step(0.04, ax) * step(p.y, 0.95);
	return max(max(straps, chest), max(belt, loops));
}

void vertex() {
	rest = CUSTOM0.xyz;
	region = CUSTOM1.xyz;
	vec3 p = rest;
	float ax = abs(p.x);
	float arm = smoothstep(0.24, 0.3, ax) * step(1.2, p.y);
	float bulk = 0.0;
	if (outfit == 0 || outfit == 3) {
		// Boots up the shin, a thicker sole, gloves with gauntlet cuffs.
		float b = smoothstep(0.36, 0.3, p.y) * step(ax, 0.3);
		bulk += b * 0.011 + smoothstep(0.035, 0.0, p.y) * 0.008;
		float g = max(region.y, smoothstep(wrist - 0.09, wrist - 0.07, ax) * arm);
		bulk += g * 0.007;
		// A collar.
		bulk += band(p.y, 1.47, 0.025) * step(ax, 0.12) * (1.0 - region.x * 0.5) * 0.012;
	}
	if (outfit == 0) {
		bulk += harness(p) * 0.008;
		bulk += band(p.y, 0.5, 0.06) * step(0.02, p.z) * step(ax, 0.2) * 0.012;
		// Elbow pads.
		bulk += band(ax, (wrist + 0.2) * 0.5, 0.04) * arm * step(p.z, 0.0) * 0.006;
	}
	VERTEX += NORMAL * bulk;
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
	float gloved = hand;
	float booted = foot;
	vec3 boot_c = boot;
	vec3 glove_c = glove;
	if (outfit == 0) {
		// Flight suit: one colour with accent panels down the sides and
		// arms, a darker yoke, a zip, a harness, knee and elbow pads,
		// gauntlet gloves and tall boots with an accent band.
		c = main_color;
		float side = band(ax, 0.17, 0.02) * step(0.55, p.y) * step(p.y, 1.42);
		float sleeve = band(p.z, 0.0, 0.016) * arm * step(ax, wrist - 0.1);
		float yoke = step(1.33 - ax * 0.25, p.y) * step(ax, 0.26) * step(p.y, 1.5);
		c = mix(c, main_color * 0.62 + accent * 0.06, yoke);
		c = mix(c, accent, max(side, sleeve));
		float zip = band(p.x, 0.0, 0.004) * step(0.0, p.z) * step(0.95, p.y) * step(p.y, 1.46);
		c = mix(c, vec3(0.75), zip * 0.8);
		float patch = step(abs(p.x) - 0.3, 0.035) * step(0.3, abs(p.x)) * band(p.y, 1.47, 0.03) * step(0.0, p.z);
		c = mix(c, accent, patch);
		float pads = band(p.y, 0.5, 0.06) * step(0.02, p.z) * step(ax, 0.2);
		pads = max(pads, band(ax, (wrist + 0.2) * 0.5, 0.04) * arm * step(p.z, 0.0));
		c = mix(c, trim, max(harness(p), pads));
		float buckle = band(p.y, 0.99, 0.024) * band(p.x, 0.0, 0.03) * step(0.0, p.z);
		c = mix(c, vec3(0.7, 0.7, 0.72), buckle);
		float collar = band(p.y, 1.47, 0.025) * step(ax, 0.12);
		c = mix(c, trim, collar * (1.0 - head));
		booted = max(foot, smoothstep(0.36, 0.34, p.y) * step(ax, 0.3));
		boot_c = mix(trim, accent, band(p.y, 0.33, 0.012)) * mix(1.0, 1.6, step(p.y, 0.03));
		gloved = max(hand, smoothstep(wrist - 0.09, wrist - 0.08, ax) * arm);
		glove_c = mix(trim, accent, band(ax, wrist - 0.075, 0.008));
		rough = 0.55;
	} else if (outfit == 1) {
		// Lab coat to the knees over a shirt and trousers.
		float coat = step(0.52, p.y) * (1.0 - head);
		float open_front = smoothstep(0.04, 0.03, ax) * step(p.y, 1.42) * step(0.0, p.z) * step(1.0, p.y);
		c = mix(legs, main_color, coat);
		c = mix(c, shirt, open_front);
		float pocket = smoothstep(0.004, 0.0, abs(p.y - 1.3)) * step(0.06, p.x) * step(p.x, 0.16) * step(0.0, p.z);
		c *= 1.0 - pocket * 0.3;
		float badge = step(abs(p.x + 0.11), 0.03) * band(p.y, 1.3, 0.02) * step(0.0, p.z);
		c = mix(c, accent, badge);
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
		booted = max(foot, smoothstep(0.36, 0.34, p.y) * step(ax, 0.3));
		gloved = max(hand, smoothstep(wrist - 0.09, wrist - 0.08, ax) * arm);
		rough = 0.6;
	} else {
		// Overalls over a shirt.
		c = mix(main_color, shirt, arm + step(1.32, p.y) * 0.85);
		c = mix(c, accent, smoothstep(0.02, 0.012, abs(p.y - 1.0)));
	}
	c *= mix(0.85, 1.05, noise3(p * 8.0));
	c = mix(c, skin, head);
	c = mix(c, glove_c, gloved);
	c = mix(c, boot_c, booted);
	ALBEDO = mix(c, vec3(1.0, 0.9, 0.85), clamp(hurt, 0.0, 1.0) * 0.5) * (1.0 - dim * 0.4);
	ROUGHNESS = mix(rough, 0.35, max(gloved, booted) * step(0.5, float(outfit == 0)));
	SPECULAR = 0.4;
	EMISSION = vec3(1.0, 0.5, 0.3) * clamp(hurt, 0.0, 1.0) * 0.4;
}
