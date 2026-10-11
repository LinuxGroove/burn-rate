class_name CityBackdrop
extends Node3D
## The city around the tower at night: a sky with the city's glow on the
## horizon, rows of far towers full of lit windows, the Downtown City
## MegaKit's buildings nearer in, the streets far below and a few aircraft
## lights. It's built once per run and only ever slides: it follows the
## camera at [constant FOLLOW] of its speed, so it drifts past slower than
## its distance alone would make it, and rises or sinks slowly as the run
## goes up or down the tower ([method set_ground]).
##
## Each layer is a strip built once and drawn three times side by side;
## the copies leapfrog off screen as the camera moves. No lights, no
## shadows, a few dozen draws in all.

## How much of the camera's movement the city copies (1 would hold it still
## on screen). Distance makes it slower again.
const FOLLOW := 0.5
## Strip widths: the far towers and the nearer kit buildings.
const FAR_W := 700.0
const MID_W := 360.0
## The sky quad, far behind everything.
const SKY_Z := -385.0
## Where the camera's eye is, roughly, for the sky's horizon.
const EYE_Y := 6.75

const SKY_SHADER := preload("res://game/view/city_sky.gdshader")
const TOWER_SHADER := preload("res://game/view/city_towers.gdshader")
const GROUND_SHADER := preload("res://game/view/city_ground.gdshader")
const NEON_SHADER := preload("res://game/view/city_neon.gdshader")
const INTERIOR := "res://addons/quaternius/downtowncity/materials/T_Lit_interior_1.png"
## The kit's ready-built buildings.
const BUILDINGS := ["city:Building_Large_1", "city:Building_Large_2", "city:Building_Large_3", "city:Building_Medium_1",
	"city:Building_Medium_2", "city:Building_Small_1", "city:Building_Small_2"]
## Neon colours on the towers' crowns and edges.
const NEON := [Color(1.0, 0.2, 0.6), Color(0.2, 0.85, 1.0), Color(0.6, 0.3, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 1.0, 0.7)]

static var tower_mat: ShaderMaterial
static var neon_mat: ShaderMaterial
static var sky_mat: ShaderMaterial
static var ground_mat: ShaderMaterial

var detail := 1
## The city's ground below the tower's floor here (negative), and where it's heading.
var ground := -150.0
var ground_target := -150.0
var _layers := []
var _sky: MeshInstance3D
var _streets: MeshInstance3D
var _planes: Array[Node3D] = []
var _plane_v: Array[float] = []


static func make(p_detail := 1) -> CityBackdrop:
	var c := CityBackdrop.new()
	c.name = "City"
	c.detail = p_detail
	c._build()
	return c


static func _materials() -> void:
	if tower_mat != null:
		return
	tower_mat = ShaderMaterial.new()
	tower_mat.shader = TOWER_SHADER
	tower_mat.set_shader_parameter("interior", load(INTERIOR))
	neon_mat = ShaderMaterial.new()
	neon_mat.shader = NEON_SHADER
	neon_mat.set_shader_parameter("energy", 2.4)
	neon_mat.set_shader_parameter("blink", 1.0)
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("horizon_y", EYE_Y)
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER


func _build() -> void:
	_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# The sky.
	_sky = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1600.0, 700.0)
	_sky.mesh = q
	_sky.material_override = sky_mat
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.position = Vector3(0.0, 100.0, SKY_Z)
	_sky.extra_cull_margin = 400.0
	add_child(_sky)
	# The streets.
	_streets = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 400.0)
	_streets.mesh = pm
	_streets.material_override = ground_mat
	_streets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_streets)
	# The far towers, three rows deep.
	var far := Node3D.new()
	var shapes := Kit.Shapes.new()
	var neon := Kit.Shapes.new()
	var rows := [[-200.0, -240.0, 60.0, 200.0, 16.0, 36.0], [-250.0, -300.0, 90.0, 280.0, 20.0, 44.0], [-310.0, -365.0, 120.0, 380.0, 26.0, 56.0]]
	if detail <= 0:
		rows.remove_at(0)
	for row in rows:
		var x := rng.randf_range(0.0, 30.0)
		while x < FAR_W - 20.0:
			var w := rng.randf_range(float(row[4]), float(row[5]))
			var h := rng.randf_range(float(row[2]), float(row[3]))
			var z := rng.randf_range(float(row[0]), float(row[1]))
			_tower(shapes, neon, rng, Vector3(x + w * 0.5, 0.0, z), w, rng.randf_range(20.0, 45.0), h)
			x += w + rng.randf_range(4.0, 40.0)
	far.add_child(shapes.instance(tower_mat))
	far.add_child(neon.instance(neon_mat))
	_add_layer(far, FAR_W)
	# The kit's buildings, nearer in, with low blocks between.
	var mid := Node3D.new()
	var b := Kit.Batch.new()
	var blocks := Kit.Shapes.new()
	var signs := Kit.Shapes.new()
	for row in [[-75.0, -95.0], [-120.0, -160.0]]:
		var x := rng.randf_range(0.0, 20.0)
		while x < MID_W - 30.0:
			var z := rng.randf_range(float(row[0]), float(row[1]))
			if rng.randf() < 0.7:
				var name: String = BUILDINGS[rng.randi() % BUILDINGS.size()]
				var size := Kit.aabb_size(name)
				b.put(name, Vector3(x + size.x * 0.5, 0.0, z), 0.0)
				x += size.x + rng.randf_range(2.0, 14.0)
			else:
				var w := rng.randf_range(16.0, 30.0)
				var h := rng.randf_range(20.0, 60.0)
				_tower(blocks, signs, rng, Vector3(x + w * 0.5, 0.0, z - 10.0), w, rng.randf_range(16.0, 26.0), h)
				x += w + rng.randf_range(2.0, 10.0)
	b.build(mid)
	mid.add_child(blocks.instance(tower_mat))
	mid.add_child(signs.instance(neon_mat))
	_add_layer(mid, MID_W)
	# Aircraft crossing, far off and slow.
	for i in 3:
		var p := Kit.Shapes.new()
		p.box(Vector3(0, 0, 0), Vector3(2.5, 2.5, 2.5), Color(1.0, 0.15, 0.1, 0.55 + i * 0.1))
		p.box(Vector3(9, 0.5, 0), Vector3(2.0, 2.0, 2.0), Color(1.0, 1.0, 1.0, 0.12 + i * 0.05))
		var n := p.instance(neon_mat)
		n.position = Vector3(rng.randf_range(-500.0, 500.0), rng.randf_range(120.0, 220.0), rng.randf_range(-330.0, -375.0))
		add_child(n)
		_planes.append(n)
		_plane_v.append(rng.randf_range(6.0, 14.0) * (1.0 if i % 2 == 0 else -1.0))


## One tower: a box, maybe a narrower one on top, a lit crown or edges, and
## a mast with a red light.
func _tower(shapes: Kit.Shapes, neon: Kit.Shapes, rng: RandomNumberGenerator, base: Vector3, w: float, d: float, h: float) -> void:
	var seed := rng.randf_range(0.02, 0.98)
	var tint := Color(0.25, 0.3, 0.42).lerp(Color(0.4, 0.33, 0.3), rng.randf())
	tint.a = seed
	var top := h
	if rng.randf() < 0.45 and h > 80.0:
		var h1 := h * rng.randf_range(0.55, 0.8)
		shapes.box(base + Vector3(0, h1 * 0.5, 0), Vector3(w, h1, d), tint)
		var w2 := w * rng.randf_range(0.6, 0.85)
		var d2 := d * rng.randf_range(0.6, 0.9)
		shapes.box(base + Vector3(0, h1 + (h - h1) * 0.5, 0), Vector3(w2, h - h1, d2), tint)
		w = w2
		d = d2
	else:
		shapes.box(base + Vector3(0, h * 0.5, 0), Vector3(w, h, d), tint)
	var nc: Color = NEON[rng.randi() % NEON.size()]
	var roll := rng.randf()
	if roll < 0.4:
		# A lit band round the crown.
		neon.box(base + Vector3(0, top - 1.2, 0), Vector3(w + 0.4, 0.9, d + 0.4), nc)
		if rng.randf() < 0.5:
			neon.box(base + Vector3(0, top - 4.0, 0), Vector3(w + 0.4, 0.5, d + 0.4), nc * 0.7)
	elif roll < 0.6:
		# Lit edges up the corners facing the tower.
		for sx in [-1.0, 1.0]:
			neon.box(base + Vector3(sx * w * 0.5, top * 0.5, d * 0.5), Vector3(0.6, top, 0.6), nc * 0.8)
	if rng.randf() < 0.55:
		var mast := rng.randf_range(8.0, 30.0)
		shapes.box(base + Vector3(0, top + mast * 0.5, 0), Vector3(0.8, mast, 0.8), Color(0.1, 0.1, 0.12, tint.a))
		neon.box(base + Vector3(0, top + mast, 0), Vector3(1.6, 1.6, 1.6), Color(1.0, 0.1, 0.05, rng.randf_range(0.4, 0.95)))


func _add_layer(strip: Node3D, width: float) -> void:
	var copies := []
	copies.append(strip)
	add_child(strip)
	for i in 2:
		var c := strip.duplicate()
		add_child(c)
		copies.append(c)
	_layers.append({"copies": copies, "w": width})


## Where the city's streets are below the tower's floor here: the high
## floors look down a long way, Downtown's rooftops only a little. The city
## eases there over a few seconds.
func set_ground(y: float) -> void:
	ground_target = y


## Dims the whole city for the Calm background setting (1 is full), and
## stills the traffic and blinking lights when it's below 1.
static func set_dim(d: float) -> void:
	_materials()
	tower_mat.set_shader_parameter("lights", 1.15 * d)
	neon_mat.set_shader_parameter("dim", d)
	neon_mat.set_shader_parameter("blink", 1.0 if d >= 1.0 else 0.0)
	sky_mat.set_shader_parameter("dim", lerpf(0.6, 1.0, d))
	ground_mat.set_shader_parameter("lights", d)
	ground_mat.set_shader_parameter("traffic", 1.0 if d >= 1.0 else 0.0)
	for i in ["", "_1", "_2", "_3", "_4"]:
		var m: ShaderMaterial = load("res://addons/quaternius/downtowncity/materials/MI_FakeInterior%s.tres" % i)
		if m:
			m.set_shader_parameter("city_lights", 1.6 * d)


## Follows the camera; call every tick.
func follow(cam_x: float, dt: float) -> void:
	ground = lerpf(ground, ground_target, 1.0 - exp(-dt / 1.6))
	position = Vector3(cam_x * FOLLOW, ground, 0.0)
	var c := cam_x * (1.0 - FOLLOW)
	for l in _layers:
		var w: float = l.w
		var n := floorf(c / w) - 1.0
		for i in 3:
			(l.copies[i] as Node3D).position.x = (n + i) * w - w * 0.5
	_sky.position.x = cam_x * (1.0 - FOLLOW)
	_sky.position.y = 100.0 - ground
	_streets.position = Vector3(snappedf(c, 64.0), 0.0, -190.0)
	for i in _planes.size():
		var p := _planes[i]
		p.position.x += _plane_v[i] * dt
		if absf(p.position.x - c) > 700.0:
			p.position.x = c - signf(_plane_v[i]) * 650.0
