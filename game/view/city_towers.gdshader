// The city's far towers: plain boxes (see CityBackdrop) whose faces are
// drawn as floors of windows, some lit (warm flats, cool offices, the odd
// coloured one), with whole floors lit late at night. UVs are metres across
// a face; the vertex colour is the tower's tint, its alpha the tower's seed.
// Windows too small to draw blend into their average, so nothing shimmers
// as the city drifts past.
shader_type spatial;
render_mode cull_back, shadows_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D interior : source_color, filter_linear_mipmap, repeat_disable;
// How bright lit windows glow; the game lowers it for Calm background.
uniform float lights = 1.15;
uniform float lit_share = 0.3;

varying vec3 wn;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 tint = COLOR.rgb;
	float seed = COLOR.a * 97.0;
	float face = dot(sign(wn), vec3(1.0, 5.0, 11.0));
	bool office = fract(seed * 0.73) < 0.55;
	vec2 cell = office ? vec2(1.6, 3.8) : vec2(2.6, 3.2);
	vec2 uv = UV / cell;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	vec2 w = fwidth(uv);
	// Window frame within the cell, softened by the pixel's size.
	vec2 lo = office ? vec2(0.06, 0.12) : vec2(0.18, 0.22);
	vec2 hi = office ? vec2(0.94, 0.86) : vec2(0.82, 0.8);
	vec2 aa = max(w, vec2(0.001));
	vec2 m2 = smoothstep(lo - aa, lo + aa, f) * (1.0 - smoothstep(hi - aa, hi + aa, f));
	float win = m2.x * m2.y;
	float area = (hi.x - lo.x) * (hi.y - lo.y);
	float r = hash12(id + vec2(seed * 13.1, face * 7.7));
	float fl = hash12(vec2(id.y + seed * 3.3, face));
	// Some floors lit end to end, the rest scattered.
	float lit = step(1.0 - lit_share, r) * step(0.12, fl) + step(0.9, fl);
	lit = min(lit, 1.0);
	float kind = hash12(id.yx + seed);
	vec3 warm = vec3(1.0, 0.78, 0.5);
	vec3 cool = vec3(0.75, 0.88, 1.0);
	vec3 col = office ? mix(cool, warm, step(0.8, kind)) : mix(warm, cool, step(0.75, kind));
	col = kind > 0.96 ? vec3(0.5, 0.6, 1.4) : (kind < 0.03 ? vec3(1.3, 0.45, 0.9) : col);
	vec3 room = texture(interior, f).rgb * 1.6;
	vec3 e = col * room * lit * win;
	// Far away: the average of the windows, without the pattern.
	float far = smoothstep(0.3, 0.7, max(w.x, w.y));
	vec3 avg = mix(warm, cool, office ? 0.75 : 0.25) * (lit_share + 0.1) * area * 0.75;
	e = mix(e, avg, far);
	float roof = step(0.5, abs(wn.y));
	e *= 1.0 - roof;
	ALBEDO = mix(tint * 0.05, vec3(0.02, 0.03, 0.05), win * (1.0 - far));
	ROUGHNESS = mix(0.8, 0.15, win * (1.0 - far));
	METALLIC = 0.2;
	EMISSION = e * lights;
}
