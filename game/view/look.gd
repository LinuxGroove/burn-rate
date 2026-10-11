class_name Look
extends RefCounted
## The game's light and colour: the environment, glow, haze and grade, the
## moonlight, and the city outside ([CityBackdrop]). Each zone has its own
## mood ([constant ZONES]), eased in as the run crosses into it, and the
## pilot's Burn warms the grade slowly as it rises. Nothing here ever
## flashes: every change is eased over a second or more.

## Each zone's mood. ambient: the fill light; fog: the haze's colour (it
## mostly tints the city); glow: bloom strength; exposure; sat: saturation;
## ground: the city's streets below the floor (the tower's height there);
## sky: the city's glow on the horizon; moon: the moonlight's strength (it
## comes from behind, rimming the pilot); fill: a soft light from the
## camera's side, so the pilot reads against the room.
const ZONES := {
	"lab": {"ambient": Color(0.62, 0.8, 1.0), "ambient_e": 0.14, "fog": Color(0.16, 0.22, 0.42), "glow": 0.85,
		"exposure": 1.05, "sat": 1.12, "ground": -150.0, "sky": Color(0.3, 0.2, 0.5), "moon": 0.35, "fill": 0.22},
	"servers": {"ambient": Color(0.3, 0.55, 0.75), "ambient_e": 0.08, "fog": Color(0.05, 0.16, 0.2), "glow": 1.0,
		"exposure": 1.05, "sat": 1.2, "ground": -146.0, "sky": Color(0.12, 0.25, 0.4), "moon": 0.18, "fill": 0.4},
	"bay": {"ambient": Color(0.9, 0.6, 0.38), "ambient_e": 0.1, "fog": Color(0.28, 0.15, 0.1), "glow": 0.95,
		"exposure": 1.05, "sat": 1.15, "ground": -142.0, "sky": Color(0.45, 0.2, 0.18), "moon": 0.2, "fill": 0.32},
	"atrium": {"ambient": Color(0.95, 0.78, 0.55), "ambient_e": 0.12, "fog": Color(0.3, 0.18, 0.3), "glow": 0.95,
		"exposure": 1.0, "sat": 1.15, "ground": -112.0, "sky": Color(0.55, 0.22, 0.4), "moon": 0.3, "fill": 0.26},
	"downtown": {"ambient": Color(0.55, 0.5, 0.95), "ambient_e": 0.18, "fog": Color(0.3, 0.14, 0.34), "glow": 1.1,
		"exposure": 1.1, "sat": 1.25, "ground": -26.0, "sky": Color(0.6, 0.2, 0.45), "moon": 0.55, "fill": 0.3},
	"halberd": {"ambient": Color(0.85, 0.4, 0.42), "ambient_e": 0.07, "fog": Color(0.22, 0.05, 0.08), "glow": 1.0,
		"exposure": 1.0, "sat": 1.15, "ground": -48.0, "sky": Color(0.45, 0.1, 0.18), "moon": 0.15, "fill": 0.4},
}
## Seconds the zone's mood takes to ease in, and the Burn's grade.
const ZONE_EASE := 1.4
const BURN_EASE := 2.5

## Set from the Calm background setting; rooms read it when they build.
static var calm := false

static var _mood := {}
static var _warm := 0.0
static var _warm_drawn := -1.0
static var _calm_checked := -1.0
static var _calm_set := false
static var _fresh := true
static var _lut: GradientTexture1D


## Adds the world's environment, the moonlight and the city under `parent`.
static func build(parent: Node3D) -> WorldEnvironment:
	var detail := RunScene.detail()
	var we := WorldEnvironment.new()
	we.name = "Look"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if detail <= 0 else Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 0.9, 1.0, 0.8, 0.5, 0.0][i] if detail > 0 else [0.0, 1.0, 0.8, 0.6, 0.0, 0.0, 0.0][i])
	# Haze: it starts past the room, so it only softens the city.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 420.0
	env.fog_depth_curve = 1.3
	env.fog_density = 0.85
	env.fog_sky_affect = 0.0
	# The night sky's colours for reflections on metal and glass (the sky
	# itself is drawn by the city).
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.04, 0.05, 0.12)
	sm.sky_horizon_color = Color(0.45, 0.2, 0.42)
	sm.ground_horizon_color = Color(0.35, 0.18, 0.3)
	sm.ground_bottom_color = Color(0.05, 0.04, 0.08)
	sm.sky_curve = 0.12
	sm.ground_curve = 0.06
	sm.sun_angle_max = 0.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if detail <= 0 else Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if detail > 0:
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.1
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.3
	env.adjustment_enabled = true
	_lut = GradientTexture1D.new()
	_lut.width = 64
	_lut.gradient = Gradient.new()
	env.adjustment_color_correction = _lut
	if detail > 0:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.ssao_light_affect = 0.0
	we.environment = env
	parent.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.rotation_degrees = Vector3(-38.0, -150.0, 0.0)
	moon.shadow_enabled = false
	moon.light_specular = 0.6
	parent.add_child(moon)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.rotation_degrees = Vector3(-42.0, 24.0, 0.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.25
	parent.add_child(fill)
	var city := CityBackdrop.make(detail)
	parent.add_child(city)
	RoomView.prewarm(detail)
	_mood = ZONES["lab"].duplicate()
	_fresh = true
	_warm = 0.0
	_warm_drawn = -1.0
	_calm_checked = -1.0
	_calm_set = false
	_apply(we, 1.0)
	return we


## Called every tick with the run, so the look can follow the zone and the
## pilot's Burn.
static func update(we: WorldEnvironment, run: Run, me: int, dt: float) -> void:
	if we == null or run == null:
		return
	var parent := we.get_parent()
	var cam := we.get_viewport().get_camera_3d() if we.is_inside_tree() else null
	var x := cam.global_position.x if cam else run.distance()
	var zone := run.course.zone_at(x + 4.0)
	var target: Dictionary = ZONES.get(zone, ZONES["lab"])
	# The first tick starts in the zone's own look; after that it eases.
	var k := 1.0 if _fresh else 1.0 - exp(-dt / ZONE_EASE)
	for key in target:
		var v = target[key]
		if v is Color:
			_mood[key] = (_mood[key] as Color).lerp(v, k)
		else:
			_mood[key] = lerpf(float(_mood[key]), float(v), k)
	var p := run.pilot(me)
	var burn := 0.0 if p == null else clampf((p.burn_level - 1) / 4.0, 0.0, 1.0)
	_warm = lerpf(_warm, burn, 1.0 - exp(-dt / BURN_EASE))
	# The Calm background setting, checked now and then.
	if _calm_checked < 0.0 or run.time - _calm_checked > 1.0 or run.time < _calm_checked:
		_calm_checked = run.time
		var c := bool(LGSettings.get_value("comfort", "calm_background"))
		if c != calm or not _calm_set:
			calm = c
			_calm_set = true
			CityBackdrop.set_dim(0.45 if calm else 1.0)
			RoomView.set_dim(0.45 if calm else 1.0)
	var city: CityBackdrop = parent.get_node_or_null("City") if parent else null
	if city:
		city.set_ground(float(target.ground))
		if _fresh:
			city.ground = city.ground_target
		city.follow(x, dt)
	_fresh = false
	_apply(we, dt)


static func _apply(we: WorldEnvironment, _dt: float) -> void:
	var env := we.environment
	var m := _mood
	env.ambient_light_color = m.ambient
	env.ambient_light_energy = float(m.ambient_e)
	env.fog_light_color = (m.fog as Color).lerp(Color(0.4, 0.18, 0.1), _warm * 0.4)
	env.glow_intensity = float(m.glow) + _warm * 0.15
	env.tonemap_exposure = float(m.exposure) + _warm * 0.06
	env.adjustment_saturation = float(m.sat) + _warm * 0.12
	env.adjustment_contrast = 1.06
	var moon := we.get_parent().get_node_or_null("Moon") as DirectionalLight3D if we.get_parent() else null
	if moon:
		moon.light_energy = float(m.moon)
	var fill := we.get_parent().get_node_or_null("Fill") as DirectionalLight3D if we.get_parent() else null
	if fill:
		fill.light_energy = float(m.fill)
	if CityBackdrop.sky_mat:
		CityBackdrop.sky_mat.set_shader_parameter("glow", m.sky)
	# The Burn's warmth: lifts reds and lowers blues in the mids, slowly.
	if absf(_warm - _warm_drawn) > 0.01:
		_warm_drawn = _warm
		var g := _lut.gradient
		var w := _warm * 0.6
		var mid := Color(0.5 + 0.05 * w, 0.5 - 0.005 * w, 0.5 - 0.07 * w)
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.0, 0.0, 0.01), mid, Color(1, 1, 1)])
