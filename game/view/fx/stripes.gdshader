// Hazard stripes, yellow and black, for the edge of a blast door: the face
// the camera sees as it slams down. Glows a little so it reads in dark
// rooms, more while it's closing (`warn`).
shader_type spatial;
render_mode cull_back;

uniform vec4 yellow : source_color = vec4(1.0, 0.72, 0.08, 1.0);
uniform vec4 black : source_color = vec4(0.05, 0.05, 0.06, 1.0);
// Stripes per metre, measured on the object so they slide with it.
uniform float density = 1.6;

instance uniform float warn = 0.0;
instance uniform float dim = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	float s = step(0.5, fract((local.x + local.y + local.z) * density));
	vec3 c = mix(black.rgb, yellow.rgb, s);
	ALBEDO = c;
	ROUGHNESS = 0.6;
	METALLIC = 0.2;
	EMISSION = yellow.rgb * s * (0.25 + warn * 0.6) * (1.0 - dim * 0.7);
}
