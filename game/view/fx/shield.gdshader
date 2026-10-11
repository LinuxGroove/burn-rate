// The Shield gadget's bubble round the pilot: clear in the middle, glowing
// at the edge with a faint hex weave. `pop` (0 to 1) bursts it: it swells,
// brightens and fades. Calm with Reduce flashing on.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

global uniform float steady;

uniform vec4 color : source_color = vec4(0.35, 0.75, 1.0, 1.0);

instance uniform float fade = 1.0;
instance uniform float pop = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float hex(vec2 p) {
	p *= vec2(1.0, 1.1547);
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 f = fract(p) - 0.5;
	return smoothstep(0.42, 0.5, max(abs(f.x), abs(f.y) * 0.9 + abs(f.x) * 0.3));
}

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float lat = asin(clamp(local.y, -1.0, 1.0));
	float lon = atan(local.z, local.x);
	float weave = hex(vec2(lon * 3.0, lat * 3.0 + TIME * mix(0.4, 0.0, steady)));
	float a = pow(rim, 2.5) * 0.9 + weave * 0.12 + 0.02;
	a *= 1.0 + pop * 2.0;
	ALBEDO = color.rgb * a * fade;
}
