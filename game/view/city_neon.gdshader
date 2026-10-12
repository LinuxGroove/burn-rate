// Neon: glowing strips, signs, status lights and screens, coloured by the
// mesh's vertex colours (see Kit.Shapes) and bright enough to bloom.
// A vertex colour's alpha below 1 makes that piece blink slowly (status
// lights, aircraft lights), at a rate and phase from the alpha and where
// the copy stands; the Reduce flashing setting (`steady`) holds them on.
// `dim` is set by the game for the Calm background setting.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

global uniform float steady;

uniform float energy = 2.0;
uniform float dim : hint_range(0.0, 1.0) = 1.0;
// 0 for strips that never blink.
uniform float blink = 0.0;

// Copies of one mesh (a MultiMesh of racks) blink out of step by where they stand.
varying float place;

void vertex() {
	place = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.1373, 0.711, 0.2931)));
}

void fragment() {
	float b = 1.0;
	if (blink > 0.0 && COLOR.a < 0.999) {
		float seed = COLOR.a * 113.0;
		float rate = 0.25 + fract(seed * 0.37) * 0.9;
		float ph = fract(TIME * rate * blink + fract(seed * 1.31) + place);
		// Mostly on with a soft dip, or a short blip for the sparse ones.
		float on = COLOR.a < 0.3 ? smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.12, 0.2, ph)) : 0.35 + 0.65 * smoothstep(0.0, 0.15, abs(ph - 0.5) * 2.0);
		b = mix(on, COLOR.a < 0.3 ? 0.6 : 0.85, steady);
	}
	ALBEDO = COLOR.rgb * energy * b * dim;
}
