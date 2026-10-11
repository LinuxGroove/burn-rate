// The streets far below: dark blocks, roads lined with orange street
// lights, and the white and red lights of traffic drifting along them.
// `steady` (Reduce flashing) and `traffic` (0 for Calm background) stop
// the traffic.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

global uniform float steady;

uniform float block = 64.0;
uniform float street = 12.0;
uniform float lights = 1.0;
uniform float traffic = 1.0;

varying vec3 lp;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = TIME * traffic * (1.0 - steady);
	vec2 p = lp.xz;
	vec2 cellp = mod(p, block) - block * 0.5;
	vec2 id = floor(p / block);
	vec3 c = vec3(0.012, 0.012, 0.02);
	// Rooftops of the low blocks catch a little glow.
	c += vec3(0.02, 0.015, 0.03) * hash11(id.x * 17.0 + id.y * 3.0);
	float onx = step(block * 0.5 - street * 0.5, abs(cellp.y));
	float onz = step(block * 0.5 - street * 0.5, abs(cellp.x));
	vec3 lamp = vec3(1.0, 0.55, 0.18);
	// Streets running along x and along z.
	float ax = abs(cellp.y) - block * 0.5;
	float az = abs(cellp.x) - block * 0.5;
	float sx = sign(cellp.y);
	float sz = sign(cellp.x);
	float kx = abs(abs(ax) - street * 0.42);
	float kz = abs(abs(az) - street * 0.42);
	float lampx = (1.0 - smoothstep(0.0, 0.7, kx)) * (1.0 - smoothstep(0.0, 1.4, abs(fract(p.x / 16.0) - 0.5) * 16.0)) * onx;
	float lampz = (1.0 - smoothstep(0.0, 0.7, kz)) * (1.0 - smoothstep(0.0, 1.4, abs(fract(p.y / 16.0) - 0.5) * 16.0)) * onz;
	c = mix(c, vec3(0.03, 0.025, 0.03), max(onx, onz));
	c += lamp * (lampx + lampz) * 1.5 * lights;
	// Traffic along x.
	float lane_x = abs(abs(ax) - street * 0.2);
	float dx = sx;
	float px = p.x / 7.0 + dx * t * 0.9;
	float carx = (1.0 - smoothstep(0.0, 0.5, lane_x)) * step(0.6, hash11(floor(px) + id.y * 7.0 + dx)) * (1.0 - smoothstep(0.1, 0.4, abs(fract(px) - 0.5))) * onx;
	float lane_z = abs(abs(az) - street * 0.2);
	float dz = sz;
	float pz = p.y / 7.0 + dz * t * 0.9;
	float carz = (1.0 - smoothstep(0.0, 0.5, lane_z)) * step(0.65, hash11(floor(pz) + id.x * 13.0 + dz)) * (1.0 - smoothstep(0.1, 0.4, abs(fract(pz) - 0.5))) * onz * (1.0 - onx);
	vec3 head = vec3(1.0, 0.95, 0.85);
	vec3 tail = vec3(1.0, 0.1, 0.08);
	c += (dx > 0.0 ? head : tail) * carx * 2.0 * lights;
	c += (dz > 0.0 ? head : tail) * carz * 2.0 * lights;
	ALBEDO = c;
}
