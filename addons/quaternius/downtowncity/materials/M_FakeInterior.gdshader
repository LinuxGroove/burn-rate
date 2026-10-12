// The Downtown City MegaKit's fake window interior (interior mapping: a room
// drawn behind the glass that shifts with the view), written out from the
// kit's visual shader for Burn Rate. Changes from the kit's:
// - each window picks lit or dark, which room, its light's colour and its
//   curtains from where the window's middle is in the world, so one model
//   or MultiMesh has every kind of window (the kit picks per model);
// - lit rooms glow (emission), since the city is seen at night;
// - `city_lights` (set on every material by the game) dims them all, for
//   the Calm background setting.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D lit_interior_1 : source_color;
uniform sampler2D lit_interior_2 : source_color;
uniform sampler2D dark_interior : source_color;
uniform sampler2D curtain_texture : source_color, hint_default_black;
uniform float depth : hint_range(0.0, 1.0) = 0.6;
uniform float percentage_lit : hint_range(0.0, 1.0) = 0.42;
uniform float percentage_variations : hint_range(0.0, 1.0) = 0.5;
uniform float light_intensity : hint_range(0.0, 3.0) = 1.0;
// How bright lit windows glow at night.
uniform float city_lights : hint_range(0.0, 4.0) = 1.6;

varying vec3 tangent_view_dir;
varying vec3 world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	vec3 cam = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = VERTEX - cam;
	vec3 bitangent = normalize(cross(TANGENT, NORMAL));
	tangent_view_dir = vec3(dot(v, TANGENT), dot(v, bitangent), dot(v, NORMAL));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The middle of this window in the world, from how the UVs run across
	// it (a window is one quad, UV 0 to 1).
	vec3 dpx = dFdx(world_pos);
	vec3 dpy = dFdy(world_pos);
	vec2 dux = dFdx(UV);
	vec2 duy = dFdy(UV);
	float det = dux.x * duy.y - duy.x * dux.y;
	vec3 centre = world_pos;
	if (abs(det) > 1e-12) {
		vec3 dpdu = (dpx * duy.y - dpy * dux.y) / det;
		vec3 dpdv = (dpy * dux.x - dpx * duy.x) / det;
		centre = world_pos - (UV.x - 0.5) * dpdu - (UV.y - 0.5) * dpdv;
	}
	float r = hash13(floor(centre * 2.0 + 0.5) + vec3(0.13, 0.71, 0.37));
	float r2 = fract(r * 7.31 + 0.29);
	float r3 = fract(r * 13.7 + 0.61);

	float far_frac = depth;
	float depth_scale = 1.0 / (1.0 - far_frac) - 1.0;
	vec3 pos = vec3(UV * 2.0 - 1.0, -1.0);
	vec3 rd = tangent_view_dir;
	rd.z *= -depth_scale;
	vec3 id = 1.0 / rd;
	vec3 k = abs(id) - pos * id;
	float k_min = min(min(k.x, k.y), k.z);
	pos += k_min * rd;
	float interp = pos.z * 0.5 + 0.5;
	float real_z = clamp(interp, 0.0, 1.0) / depth_scale + 1.0;
	interp = 1.0 - (1.0 / real_z);
	interp *= depth_scale + 1.0;
	vec2 iuv = pos.xy * mix(1.0, far_frac, interp) * 0.5 + 0.5;

	float lit = step(1.0 - percentage_lit, r);
	float variation = step(1.0 - percentage_variations, r2);
	vec3 room = mix(texture(lit_interior_1, iuv).rgb, texture(lit_interior_2, iuv).rgb, variation);
	// Offices (cool white), flats (warm), the odd screen-lit room (blue or pink).
	vec3 tint = r3 < 0.45 ? vec3(1.0, 0.86, 0.66) : (r3 < 0.85 ? vec3(0.85, 0.95, 1.1) : (r3 < 0.93 ? vec3(0.5, 0.7, 1.3) : vec3(1.2, 0.55, 1.0)));
	vec3 dark = texture(dark_interior, iuv).rgb;

	float ci = floor(r2 * 4.0);
	vec2 cuv = UV * 0.5 + vec2(mod(ci, 2.0) * 0.5, floor(ci / 2.0) * 0.5);
	vec4 curtain = texture(curtain_texture, cuv);

	vec3 glow = room * tint * light_intensity * lit;
	// Curtains catch the room's light from behind.
	glow = mix(glow, curtain.rgb * tint * lit * 0.8, curtain.a);
	ALBEDO = mix(dark * 0.5, curtain.rgb * 0.3, curtain.a * (1.0 - lit));
	EMISSION = glow * city_lights;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}
