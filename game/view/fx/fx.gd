class_name Fx
extends Node3D
## The run's particles: one-shot bursts (sparks, smoke, dust, debris, pickup
## sparkles, rings) from small pools, and the continuous emitters that
## jetpacks, seekers and zappers carry ([method emitter]). Everything is
## GPU particles with a handful of shared materials, coloured per system
## through the `tint` instance uniform, so a burst costs one draw call.
##
## Every particle system joins the "fx_particles" group, which [RunView]
## freezes while the run is paused. Low detail (handhelds) halves the
## particle counts and drops the softest smoke.

const GLOW := preload("res://game/view/fx/glow.gdshader")
const SMOKE := preload("res://game/view/fx/smoke.gdshader")
const GROUP := "fx_particles"

## Each kind: how many particles, how long they live, how they're drawn
## ("dot", "streak", "ring", "star", "smoke" or "chunk"), their size (start,
## end), speed range, spread (degrees around the direction), gravity (m/s²,
## negative falls), damping and how many of the kind can be alive at once.
const KINDS := {
	"sparks": {"amount": 26, "life": 0.5, "draw": "streak", "size": [1.0, 0.3], "speed": [3.5, 10.0], "spread": 70.0, "gravity": -16.0, "damp": 3.0, "pool": 8},
	"embers": {"amount": 14, "life": 0.9, "draw": "dot", "size": [0.12, 0.0], "speed": [0.5, 2.5], "spread": 180.0, "gravity": 2.0, "damp": 1.5, "pool": 4},
	"smoke": {"amount": 9, "life": 1.4, "draw": "smoke", "size": [0.5, 1.6], "speed": [0.4, 1.6], "spread": 180.0, "gravity": 1.2, "damp": 1.8, "pool": 6},
	"dust": {"amount": 10, "life": 0.8, "draw": "smoke", "size": [0.35, 1.1], "speed": [1.5, 3.5], "spread": 80.0, "gravity": 0.3, "damp": 4.0, "pool": 4},
	"debris": {"amount": 12, "life": 1.1, "draw": "chunk", "size": [1.0, 0.8], "speed": [3.0, 7.5], "spread": 55.0, "gravity": -20.0, "damp": 0.5, "pool": 3},
	"sparkle": {"amount": 7, "life": 0.4, "draw": "star", "size": [0.35, 0.0], "speed": [1.0, 3.0], "spread": 180.0, "gravity": 0.0, "damp": 6.0, "pool": 10},
	"ring": {"amount": 1, "life": 0.45, "draw": "ring", "size": [0.4, 2.6], "speed": [0.0, 0.0], "spread": 0.0, "gravity": 0.0, "damp": 0.0, "pool": 6},
	"streak": {"amount": 10, "life": 0.35, "draw": "streak", "size": [1.6, 0.4], "speed": [10.0, 18.0], "spread": 8.0, "gravity": 0.0, "damp": 6.0, "pool": 6},
}

static var _mats := {}
static var _steady := 0.0
static var _steady_frame := -1
static var _meshes := {}

var detail := 1
var _pools := {}
var _next := {}


func setup(p_detail := 1) -> void:
	detail = p_detail


## Fires a burst of `kind` at a world position, in `color`, pointing along
## `dir` (up by default). `strength` scales how many particles (0 to 1+)
## and how fast they go.
func burst(kind: String, pos: Vector3, color := Color.WHITE, strength := 1.0, dir := Vector3.UP, size := 1.0) -> void:
	if not KINDS.has(kind):
		return
	if detail <= 0 and kind == "embers":
		return
	var pool: Array = _pools.get(kind, [])
	var k: Dictionary = KINDS[kind]
	if pool.size() < int(k.pool):
		var p := make(kind, detail)
		add_child(p)
		pool.append(p)
		_pools[kind] = pool
	var i: int = int(_next.get(kind, 0)) % pool.size()
	_next[kind] = i + 1
	var p: GPUParticles3D = pool[i]
	p.global_transform = Transform3D(_basis_up(dir) * Basis.from_scale(Vector3.ONE * size), pos)
	p.amount_ratio = clampf(strength, 0.1, 1.0)
	p.speed_scale = 1.0 if not _frozen else 0.0
	if kind != "debris":
		p.set_instance_shader_parameter("tint", color)
	p.restart()
	p.emitting = true


var _frozen := false


## Stops (or starts again) every particle in the run, for pausing.
func set_frozen(f: bool) -> void:
	if f == _frozen:
		return
	_frozen = f
	if is_inside_tree():
		get_tree().set_group(GROUP, "speed_scale", 0.0 if f else 1.0)


## The Reduce flashing setting (1.0 steady), as the `steady` shader global
## has it, read once a frame.
static func steady() -> float:
	var f := Engine.get_process_frames()
	if f != _steady_frame:
		_steady_frame = f
		_steady = 1.0 if LGSettings.get_value("comfort", "reduce_flashing", false) else 0.0
	return _steady


## A basis whose +Y points along `dir`.
static func _basis_up(dir: Vector3) -> Basis:
	if dir.length() < 0.001:
		return Basis()
	var up := dir.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up))


## A particle system of `kind`: one-shot for bursts. For a continuous
## emitter, see [method emitter].
static func make(kind: String, p_detail := 1) -> GPUParticles3D:
	var k: Dictionary = KINDS[kind]
	var p := GPUParticles3D.new()
	p.name = kind.capitalize()
	p.amount = maxi(1, int(k.amount) / (2 if p_detail <= 0 and int(k.amount) > 2 else 1))
	p.lifetime = float(k.life)
	p.one_shot = true
	p.explosiveness = 0.92 if kind != "streak" else 0.6
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = _process_material(kind)
	_set_draw(p, str(k.draw))
	p.add_to_group(GROUP)
	return p


## A continuous emitter: `kind` is one of "exhaust" (sparks from a nozzle,
## pointing down its -Y), "trail" (smoke behind a rocket), "crackle" (sparks
## at a zapper's end) or "heat" (soft glow puffs).
static func emitter(kind: String, p_detail := 1) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = kind.capitalize()
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	var half := 2 if p_detail <= 0 else 1
	match kind:
		"exhaust":
			p.amount = 20 / half
			p.lifetime = 0.32
			m.spread = 14.0
			m.initial_velocity_min = 5.0
			m.initial_velocity_max = 10.0
			m.gravity = Vector3(0, -6, 0)
			m.damping_min = 3.0
			m.damping_max = 6.0
			m.scale_min = 0.6
			m.scale_max = 1.2
			m.scale_curve = _curve(1.0, 0.2)
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 0.5, 0.2, 0.0))
			_set_draw(p, "streak")
		"trail":
			p.amount = 26 / half
			p.lifetime = 0.9
			m.spread = 12.0
			m.initial_velocity_min = 0.5
			m.initial_velocity_max = 1.5
			m.gravity = Vector3(0, 0.6, 0)
			m.damping_min = 1.0
			m.damping_max = 2.0
			m.scale_min = 0.25
			m.scale_max = 0.4
			m.scale_curve = _curve(0.5, 1.8)
			m.color_ramp = _ramp(Color(0.85, 0.85, 0.85, 0.55), Color(0.5, 0.5, 0.55, 0.0))
			_set_draw(p, "smoke")
		"crackle":
			p.amount = 8 / half
			p.lifetime = 0.35
			p.explosiveness = 0.3
			m.spread = 180.0
			m.initial_velocity_min = 1.5
			m.initial_velocity_max = 4.0
			m.gravity = Vector3(0, -9, 0)
			m.scale_min = 0.25
			m.scale_max = 0.5
			m.scale_curve = _curve(1.0, 0.1)
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
			_set_draw(p, "streak")
		"heat":
			p.amount = 10 / half
			p.lifetime = 0.5
			m.spread = 18.0
			m.initial_velocity_min = 3.0
			m.initial_velocity_max = 5.0
			m.damping_min = 4.0
			m.damping_max = 6.0
			m.scale_min = 0.4
			m.scale_max = 0.7
			m.scale_curve = _curve(0.5, 1.5)
			m.color_ramp = _ramp(Color(1, 0.6, 0.3, 0.35), Color(1, 0.3, 0.1, 0.0))
			_set_draw(p, "dot")
	p.process_material = m
	p.add_to_group(GROUP)
	return p


static func _process_material(kind: String) -> ParticleProcessMaterial:
	var key := "proc/" + kind
	if _mats.has(key):
		return _mats[key]
	var k: Dictionary = KINDS[kind]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = float(k.spread)
	m.initial_velocity_min = float(k.speed[0])
	m.initial_velocity_max = float(k.speed[1])
	m.gravity = Vector3(0, float(k.gravity), 0)
	m.damping_min = float(k.damp) * 0.7
	m.damping_max = float(k.damp)
	var s: Array = k.size
	m.scale_min = float(s[0]) * 0.7
	m.scale_max = float(s[0]) * 1.2
	m.scale_curve = _curve(1.0, float(s[1]) / maxf(float(s[0]), 0.001))
	match kind:
		"smoke":
			m.color_ramp = _ramp(Color(0.42, 0.42, 0.45, 0.75), Color(0.3, 0.3, 0.33, 0.0))
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.3
		"dust":
			m.color_ramp = _ramp(Color(0.75, 0.75, 0.78, 0.6), Color(0.7, 0.7, 0.72, 0.0))
			m.direction = Vector3(1, 0, 0)
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = Vector3(0.3, 0.05, 0.3)
		"debris":
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 1))
			m.angular_velocity_min = -720.0
			m.angular_velocity_max = 720.0
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.particle_flag_rotate_y = false
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.4
			m.scale_min = 0.5
			m.scale_max = 1.6
		"ring":
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
			m.scale_min = 1.0
			m.scale_max = 1.0
			m.scale_curve = _curve(float(s[0]), float(s[1]), true)
		"sparkle":
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.25
		"streak":
			m.color_ramp = _ramp(Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = Vector3(0.3, 0.6, 0.3)
		_:
			m.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 0.6, 0.3, 0))
	_mats[key] = m
	return m


## Sets the draw pass: the mesh and its material for a look.
static func _set_draw(p: GPUParticles3D, draw: String) -> void:
	p.draw_pass_1 = _mesh(draw)
	match draw:
		"streak":
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		"dot", "star", "ring", "smoke":
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
		_:
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED


static func _mesh(draw: String) -> Mesh:
	if _meshes.has(draw):
		return _meshes[draw]
	var mesh: Mesh
	if draw == "chunk":
		var b := BoxMesh.new()
		b.size = Vector3(0.14, 0.09, 0.11)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.16, 0.18)
		m.metallic = 0.7
		m.roughness = 0.4
		m.vertex_color_use_as_albedo = false
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 0.25
		b.material = m
		mesh = b
	else:
		var q := QuadMesh.new()
		match draw:
			"streak":
				q.size = Vector2(0.05, 0.42)
			"dot":
				q.size = Vector2(1.0, 1.0)
			"star":
				q.size = Vector2(1.0, 1.0)
			"ring":
				q.size = Vector2(1.0, 1.0)
			"smoke":
				q.size = Vector2(1.0, 1.0)
		var mat := ShaderMaterial.new()
		if draw == "smoke":
			mat.shader = SMOKE
		else:
			mat.shader = GLOW
			mat.set_shader_parameter("shape", {"dot": 0, "streak": 1, "ring": 2, "star": 3}[draw])
			mat.set_shader_parameter("strength", {"dot": 2.0, "streak": 2.6, "ring": 1.6, "star": 2.4}[draw])
		q.material = mat
		mesh = q
	_meshes[draw] = mesh
	return mesh


static func _curve(a: float, b: float, absolute := false) -> CurveTexture:
	var c := Curve.new()
	if absolute:
		c.max_value = maxf(a, b)
	else:
		c.max_value = maxf(1.0, maxf(a, b))
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
