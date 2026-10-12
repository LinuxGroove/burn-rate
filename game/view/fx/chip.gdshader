// Credit chips: polished metal with a glowing rim, and a glint that sweeps
// along the line of chips so a wave of credits shimmers as it comes.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float steady;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.2, 1.0);
uniform float glow = 0.9;

varying vec3 world;
varying vec3 local;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX;
}

void fragment() {
	float sweep = fract(world.x * 0.12 + world.y * 0.08 - TIME * mix(0.9, 0.25, steady));
	float glint = pow(smoothstep(0.0, 0.08, sweep) * smoothstep(0.2, 0.08, sweep), 2.0);
	// The rim (COLOR.r is 1 on the rim, 0 on the faces; COLOR.g the emblem).
	float rim = COLOR.r;
	float emblem = COLOR.g;
	vec3 base = color.rgb * mix(0.85, 1.1, emblem);
	ALBEDO = base * 0.55;
	METALLIC = 0.9;
	ROUGHNESS = mix(0.28, 0.12, emblem);
	float rim_glow = rim * 0.9 + emblem * 0.25;
	EMISSION = color.rgb * (glow * (0.25 + rim_glow) + glint * 1.4);
}
