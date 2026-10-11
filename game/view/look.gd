class_name Look
extends RefCounted
## The game's light and colour: the environment, glow and grading, and the
## moonlight through the windows. Zones and the Burn can shift it (see
## [method update]).


## Adds the world's environment and lights under `parent`.
static func build(parent: Node3D) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "Look"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	we.environment = env
	parent.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.75, 0.82, 1.0)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	moon.shadow_enabled = false
	parent.add_child(moon)
	return we


## Called every tick with the run, so the look can follow the zone and the
## pilot's Burn.
static func update(_we: WorldEnvironment, _run: Run, _me: int, _dt: float) -> void:
	pass
