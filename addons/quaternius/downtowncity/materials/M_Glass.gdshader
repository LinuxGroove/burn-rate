// The Downtown City MegaKit's window glass, written out from the kit's
// visual shader: a tinted, shiny, half see-through pane. Burn Rate draws it
// fainter, so the rooms behind the windows show at night.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 Color : source_color = vec4(0.231373, 0.231373, 0.231373, 1.0);
uniform float Opacity = 0.5;
uniform float Metallic = 1.0;
uniform float Roughness = 0.0;
uniform float Specular = 1.0;

void fragment() {
	ALBEDO = Color.rgb;
	ALPHA = Opacity * 0.45;
	METALLIC = Metallic;
	ROUGHNESS = Roughness;
	SPECULAR = Specular;
}
