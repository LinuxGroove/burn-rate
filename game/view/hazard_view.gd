class_name HazardView
extends Node3D
## How a hazard looks: made for one [Hazard] and moved to match it every
## tick by [RunView]. Zappers are two capacitors and an arc, lasers a beam
## across the screen, seekers small rockets, shutters blast doors, and the
## drones and walkers Halberd's animated robots. The shapes drawn are the
## ones the run checks, so what you see is what hits you.

const BEAM_SHADER := preload("res://game/view/fx/beam.gdshader")
const COLORS := {
	"zapper": Color(0.35, 0.8, 1.0),
	"laser": Color(1.0, 0.15, 0.2),
	"bolt": Color(0.4, 1.0, 0.45),
	"seeker": Color(1.0, 0.55, 0.1),
	"eye": Color(1.0, 0.25, 0.2),
}
const ROBOTS := {"eye_drone": "ess:Enemy_EyeDrone", "gun_drone": "ess:Enemy_GunDrone", "raptor": "ess:Enemy_Raptor",
	"trilobite": "ess:Enemy_Trilobite", "orb": "ess:Enemy_QuadOrb"}

static var _beam_mats := {}
static var _mark_mats := {}
static var _mark_mesh: QuadMesh
static var _cyl: CylinderMesh
static var _ball: SphereMesh
static var _metal: StandardMaterial3D

var hazard: Hazard
var _beams: Array[MeshInstance3D] = []
var _marks: Array[MeshInstance3D] = []
var _ends: Array[Node3D] = []
var _robot: Node3D
var _anim: AnimationPlayer
var _clip := ""
var _door: MeshInstance3D
var _rocket: Node3D
var _seed := 0.0


static func make(h: Hazard) -> HazardView:
	var v := HazardView.new()
	v.hazard = h
	v.name = "%s%d" % [h.kind, h.id]
	v._seed = float(h.id % 89) * 0.37
	v._build()
	return v


func _build() -> void:
	match hazard.kind:
		"zapper":
			for i in 2:
				_ends.append(_capacitor())
		"walker":
			_add_robot(ROBOTS.get((hazard as Walker).body, "ess:Enemy_Raptor"))
			if (hazard as Walker).ceiling:
				_robot.rotation.z = PI
		"eye_drone", "gun_drone":
			_add_robot(ROBOTS[hazard.kind])
		"seeker":
			_rocket = _make_rocket()
			add_child(_rocket)
		"shutter":
			_door = MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(Shutter.THICK * 2.0, Shutter.TOP, 2.0)
			_door.mesh = b
			_door.material_override = Kit.flat(Color(0.22, 0.2, 0.18), 0.5, Color(1.0, 0.5, 0.0), 0.15)
			add_child(_door)
			# The frame it drops from, in the ceiling.
			var frame := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.9, 0.25, 2.2)
			frame.mesh = fb
			frame.material_override = Kit.flat(Color(0.12, 0.12, 0.13), 0.6, Color(1.0, 0.45, 0.0), 0.8)
			frame.position = Vector3(0, Shutter.TOP - 0.12, 0)
			add_child(frame)


func _add_robot(model: String) -> void:
	_robot = Kit.model(self, model, Vector3.ZERO)
	# They face along the run, towards the pilot coming the other way.
	_robot.rotation.y = -PI * 0.5
	var players := _robot.find_children("", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]


func _play(clip: String) -> void:
	if _anim == null or clip == _clip or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, 0.15)


## Moves everything to the run's current moment. `my_lane` is the local
## pilot's lane, so hazards in other lanes can be dimmed.
func sync(run: Run, my_lane: float) -> void:
	var shapes := hazard.shapes_at(run.time, run)
	match hazard.kind:
		"zapper":
			_sync_zapper(shapes, my_lane)
		"laser":
			_sync_laser(run, shapes, my_lane)
		"seeker":
			_sync_seeker(shapes)
		"shutter":
			_sync_shutter(run)
		"eye_drone":
			_sync_robot(shapes)
			_play({"look": "Look", "charge": "Charging", "attack": "Attack"}.get(hazard.state, "Idle"))
		"gun_drone":
			_sync_robot(shapes)
			_play({"charge": "Charging", "attack": "Attack"}.get(hazard.state, "Idle"))
			_sync_bolts(run, shapes, my_lane)
		"walker":
			_sync_walker(shapes)


func _sync_zapper(shapes: Array, my_lane: float) -> void:
	if shapes.is_empty():
		return
	var s: Array = shapes[0]
	var a := _point(float(s[1]), float(s[2]), float(s[6]))
	var b := _point(float(s[3]), float(s[4]), float(s[7]))
	_ends[0].position = a
	_ends[1].position = b
	_aim_end(_ends[0], b - a)
	_aim_end(_ends[1], a - b)
	var dim := _dim(float(s[6]), float(s[7]), my_lane)
	_beam(0, a, b, float(s[5]) * 0.9, "zapper", dim, 1.0)
	_mark(0, a, b, "zapper", dim)


func _sync_laser(run: Run, shapes: Array, my_lane: float) -> void:
	var l := hazard as Laser
	if l.t0 < 0.0:
		_hide_beams(0)
		return
	var x0 := run.trigger_x - 14.0
	var x1 := run.trigger_x + 30.0
	var firing := not shapes.is_empty()
	var dim := _dim(l.lane, l.lane, my_lane)
	_mark(0, _point(x0, 0.0, l.lane), _point(x1, 0.0, l.lane), "laser", dim)
	if firing:
		_beam(0, _point(x0, l.y, l.lane), _point(x1, l.y, l.lane), Laser.RADIUS, "laser", dim, 1.0)
	else:
		# Charging: a thin line that thickens.
		_beam(0, _point(x0, l.y, l.lane), _point(x1, l.y, l.lane), 0.03 + 0.05 * l.phase, "laser", dim, 0.25 + 0.5 * l.phase)


func _sync_seeker(shapes: Array) -> void:
	_rocket.visible = not shapes.is_empty()
	if shapes.is_empty():
		return
	var s: Array = shapes[0]
	_rocket.position = _point((float(s[1]) + float(s[3])) * 0.5, float(s[2]), float(s[6]))


func _sync_shutter(run: Run) -> void:
	var sh := hazard as Shutter
	var bottom := sh._bottom(run.time)
	_door.position = _point(sh.x, bottom + Shutter.TOP * 0.5, sh.lane)
	_door.position.x -= position.x


func _sync_robot(shapes: Array) -> void:
	if shapes.is_empty():
		return
	var s: Array = shapes[0]
	_robot.position = _point(float(s[1]), float(s[2]) - 0.5, float(s[6]))
	var p := _point(float(s[1]), 0.0, float(s[6]))
	_mark(0, p - Vector3(0.6, 0, 0), p + Vector3(0.6, 0, 0), "eye", 0.0)


func _sync_walker(shapes: Array) -> void:
	if shapes.is_empty():
		return
	var w := hazard as Walker
	var s: Array = shapes[0]
	var y := float(s[4]) if w.ceiling else 0.0
	_robot.position = _point((float(s[1]) + float(s[3])) * 0.5, y, w.lane)
	_play({"walk": "Walk", "roll": "Run"}.get(w.state, "Idle"))


func _sync_bolts(run: Run, shapes: Array, my_lane: float) -> void:
	var n := 0
	for i in range(1, shapes.size()):
		var s: Array = shapes[i]
		var p := _point(float(s[1]), float(s[2]), float(s[6]))
		_beam(n, p, p + Vector3(0, 0, 0.01), float(s[5]), "bolt", _dim(float(s[6]), float(s[6]), my_lane), 1.0, true)
		n += 1
	_hide_beams(n)


## A point in the run (x, y, lane) in this node's space.
func _point(x: float, y: float, lane: float) -> Vector3:
	return Vector3(x, y, RunView.lane_z(lane)) - position


func _dim(la: float, lb: float, my_lane: float) -> float:
	var d := minf(absf(la - my_lane), absf(lb - my_lane))
	if my_lane > minf(la, lb) and my_lane < maxf(la, lb):
		d = 0.0
	return clampf(d - 0.3, 0.0, 1.0)


## Shows beam i from a to b (a ball when they meet).
func _beam(i: int, a: Vector3, b: Vector3, r: float, kind: String, dim: float, power: float, ball := false) -> void:
	while _beams.size() <= i:
		var m := MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_beams.append(m)
	var m := _beams[i]
	m.visible = true
	m.material_override = _beam_mat(kind)
	m.set_instance_shader_parameter("dim", dim)
	m.set_instance_shader_parameter("power", power)
	m.set_instance_shader_parameter("seed", _seed + i)
	var d := b - a
	if ball or d.length() < 0.05:
		if _ball == null:
			_ball = SphereMesh.new()
			_ball.radius = 1.0
			_ball.height = 2.0
			_ball.radial_segments = 16
			_ball.rings = 8
		m.mesh = _ball
		m.transform = Transform3D(Basis.from_scale(Vector3.ONE * r), (a + b) * 0.5)
		return
	if _cyl == null:
		_cyl = CylinderMesh.new()
		_cyl.top_radius = 1.0
		_cyl.bottom_radius = 1.0
		_cyl.height = 1.0
		_cyl.radial_segments = 12
		_cyl.rings = 1
	m.mesh = _cyl
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	m.transform = Transform3D(Basis(side * r, up * d.length(), fwd * r), (a + b) * 0.5)


## A glow on the floor of the hazard's lane under it, from a to b (their
## heights are ignored), so you can tell which lane it's in.
func _mark(i: int, a: Vector3, b: Vector3, kind: String, dim: float) -> void:
	while _marks.size() <= i:
		var m := MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_marks.append(m)
	if _mark_mesh == null:
		_mark_mesh = QuadMesh.new()
		_mark_mesh.orientation = PlaneMesh.FACE_Y
		_mark_mesh.size = Vector2(1, 1)
	var m := _marks[i]
	m.mesh = _mark_mesh
	if not _mark_mats.has(kind):
		var g := Gradient.new()
		var c: Color = COLORS.get(kind, COLORS.zapper)
		g.set_color(0, Color(c, 0.9))
		g.set_color(1, Color(c, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		_mark_mats[kind] = mat
	m.material_override = _mark_mats[kind]
	var fa := Vector3(a.x, 0.02, a.z)
	var fb := Vector3(b.x, 0.02, b.z)
	var d := fb - fa
	var len := maxf(d.length(), 0.01) + 1.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3.RIGHT
	var side := Vector3.UP.cross(dir).normalized()
	m.transform = Transform3D(Basis(dir * len, Vector3.UP, side * 0.9), (fa + fb) * 0.5)
	m.transparency = dim * 0.6
	m.visible = true


func _hide_beams(from: int) -> void:
	for i in range(from, _beams.size()):
		_beams[i].visible = false


static func _beam_mat(kind: String) -> ShaderMaterial:
	if not _beam_mats.has(kind):
		var m := ShaderMaterial.new()
		m.shader = BEAM_SHADER
		var c: Color = COLORS.get(kind, COLORS.zapper)
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("crawl", 1.0 if kind == "zapper" else 0.3)
		m.set_shader_parameter("strength", 2.2 if kind != "laser" else 3.0)
		_beam_mats[kind] = m
	return _beam_mats[kind]


## A zapper's end: a metal capacitor with a glowing ring.
func _capacitor() -> Node3D:
	if _metal == null:
		_metal = Kit.flat(Color(0.25, 0.26, 0.3), 0.35)
		_metal.metallic = 0.8
	var n := Node3D.new()
	add_child(n)
	var body := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.2
	c.bottom_radius = 0.26
	c.height = 0.5
	c.radial_segments = 12
	body.mesh = c
	body.material_override = _metal
	body.position = Vector3(0, -0.15, 0)
	n.add_child(body)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.2
	t.outer_radius = 0.3
	ring.mesh = t
	ring.material_override = Kit.flat(COLORS.zapper * 0.4, 0.4, COLORS.zapper, 3.0)
	ring.position = Vector3(0, 0.08, 0)
	n.add_child(ring)
	return n


## Points a capacitor's top towards the other end.
func _aim_end(n: Node3D, towards: Vector3) -> void:
	if towards.length() < 0.01:
		return
	var up := towards.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	n.basis = Basis(side, up, side.cross(up))


## A small rocket pointing back along the run, with its flame.
func _make_rocket() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.16
	c.bottom_radius = 0.16
	c.height = 0.8
	body.mesh = c
	body.material_override = Kit.flat(Color(0.85, 0.85, 0.82), 0.4)
	body.rotation.z = PI * 0.5
	n.add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.3
	nose.mesh = cone
	nose.material_override = Kit.flat(Color(0.9, 0.2, 0.1), 0.4)
	nose.rotation.z = PI * 0.5
	nose.position = Vector3(-0.55, 0, 0)
	n.add_child(nose)
	var flame := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.12
	fc.bottom_radius = 0.0
	fc.height = 0.9
	flame.mesh = fc
	flame.material_override = _beam_mat("seeker")
	flame.rotation.z = PI * 0.5
	flame.position = Vector3(0.85, 0, 0)
	n.add_child(flame)
	return n
