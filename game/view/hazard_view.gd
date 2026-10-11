class_name HazardView
extends Node3D
## How a hazard looks: made for one [Hazard] and moved to match it every
## tick by [RunView]. Zappers are two capacitors with a crackling arc,
## lasers emitters that slide in at the screen's edges and fire across it,
## seekers rockets trailing smoke (with a lock-on reticle while they aim),
## shutters blast doors that slam down, and the drones and walkers Halberd's
## animated robots. The shapes drawn are the ones the run checks, so what
## you see is what hits you. Hazards in your lane are drawn at full
## strength and the others dimmed, with a glowing mark on their lane's floor.
##
## When a hazard dies (smashed, fizzled, fired and done) the view plays its
## end ([method die]) and says when it's [method finished].

const ARC := preload("res://game/view/fx/arc.gdshader")
const BEAM := preload("res://game/view/fx/beam.gdshader")
const FLAME := preload("res://game/view/fx/flame.gdshader")
const RETICLE := preload("res://game/view/fx/reticle.gdshader")
const RIM := preload("res://game/view/fx/rim.gdshader")
const COLORS := {
	"zapper": Color(0.35, 0.8, 1.0),
	"halo": Color(0.35, 0.8, 1.0),
	"laser": Color(1.0, 0.15, 0.2),
	"bolt": Color(0.4, 1.0, 0.45),
	"seeker": Color(1.0, 0.55, 0.1),
	"eye": Color(1.0, 0.25, 0.2),
	"shutter": Color(1.0, 0.6, 0.1),
}
const ROBOTS := {"eye_drone": "ess:Enemy_EyeDrone", "gun_drone": "ess:Enemy_GunDrone", "raptor": "ess:Enemy_Raptor",
	"trilobite": "ess:Enemy_Trilobite", "orb": "ess:Enemy_QuadOrb"}
## Drawn size of each robot: the run's hit box width (walkers) or diameter.
const ROBOT_SCALE := {"eye_drone": 1.25, "gun_drone": 1.45}
## How long each kind's end plays.
const END_TIME := {"seeker": 1.4, "laser": 0.5, "eye_drone": 1.6, "gun_drone": 1.6, "walker": 1.8}

static var _beam_mats := {}
static var _arc_mats := {}
static var _mark_mats := {}
static var _mark_mesh: QuadMesh
static var _cyl: CylinderMesh
static var _strand: CylinderMesh
static var _ball: SphereMesh
static var _quad: QuadMesh
static var _rim_mat: ShaderMaterial
static var _paint := {}

var hazard: Hazard
var fx: Fx
var detail := 1
var _beams: Array[MeshInstance3D] = []
var _marks: Array[MeshInstance3D] = []
var _ends: Array[Node3D] = []
var _strands: Array[MeshInstance3D] = []
var _crackles: Array[GPUParticles3D] = []
var _light: OmniLight3D
var _robot: Node3D
var _robot_meshes: Array = []
var _anim: AnimationPlayer
var _clip := ""
var _door: Node3D
var _beacons: Array[MeshInstance3D] = []
var _rocket: Node3D
var _flame: MeshInstance3D
var _trail: GPUParticles3D
var _reticle: MeshInstance3D
var _arms: Array[MeshInstance3D] = []
var _seed := 0.0
var _time := 0.0
## Seconds since it died, or -1 while it's alive.
var _dying := -1.0
var _end_at := Vector3.ZERO
var _last_x := 0.0
var _slid := 0.0
var _shut := false
var _bolts_seen := 0
var _tick := 0.0
var _edges := Vector2(-9.0, 9.0)


static func make(h: Hazard, p_detail := 1, p_fx: Fx = null) -> HazardView:
	var v := HazardView.new()
	v.hazard = h
	v.detail = p_detail
	v.fx = p_fx
	v.name = "%s%d" % [h.kind, h.id]
	v._seed = float(h.id % 89) * 0.37
	v._build()
	return v


func _build() -> void:
	match hazard.kind:
		"zapper":
			for i in 2:
				_ends.append(_capacitor())
			for i in 3:
				var m := MeshInstance3D.new()
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				m.mesh = _strand_mesh()
				m.material_override = _arc_mat(i)
				m.set_instance_shader_parameter("seed", _seed * 7.0 + i * 3.3)
				add_child(m)
				_strands.append(m)
			if detail > 0:
				for i in 2:
					var c := Fx.emitter("crackle", detail)
					c.set_instance_shader_parameter("tint", COLORS.zapper)
					add_child(c)
					_crackles.append(c)
				_light = _make_light(COLORS.zapper, 0.9, 3.5)
		"walker":
			var w := hazard as Walker
			_add_robot(ROBOTS.get(w.body, "ess:Enemy_Raptor"), w.size.x)
			if w.ceiling:
				_robot.rotation.z = PI
		"eye_drone", "gun_drone":
			_add_robot(ROBOTS[hazard.kind], ROBOT_SCALE[hazard.kind])
		"seeker":
			_build_seeker()
		"shutter":
			_build_shutter()
		"laser":
			for i in 2:
				var e := Kit.model(self, "laser_emitter", Vector3.ZERO, 0.0 if i == 0 else PI)
				_repaint_glow(e, COLORS.laser)
				_ends.append(e)
				var arm := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(0.09, 1.0, 0.09)
				arm.mesh = b
				arm.material_override = Kit.flat(Color(0.1, 0.1, 0.11), 0.5)
				add_child(arm)
				_arms.append(arm)


func _make_light(c: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	add_child(l)
	return l


func _add_robot(model: String, size: float) -> void:
	_robot = Kit.model(self, model, Vector3.ZERO)
	var b := Kit.aabb_of(_robot)
	var s := size / maxf(maxf(b.size.x, b.size.z), 0.1) if hazard.kind == "walker" else size / maxf(b.size.y, 0.1)
	_robot.scale = Vector3.ONE * s
	# They face along the run, towards the pilot coming the other way.
	_robot.rotation.y = -PI * 0.5
	var players := _robot.find_children("", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
	if detail > 0:
		if _rim_mat == null:
			_rim_mat = ShaderMaterial.new()
			_rim_mat.shader = RIM
		for mi in _robot.find_children("", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.material_overlay = _rim_mat
			m.set_instance_shader_parameter("rim_color", COLORS.eye if hazard.kind != "gun_drone" else COLORS.bolt)
			_robot_meshes.append(m)


func _play(clip: String, blend := 0.15) -> void:
	if _anim == null or clip == _clip or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, blend)


## Repaints a model's M_Jet_Glow parts (the kit-sheet glow) in a colour.
static func _repaint_glow(root: Node3D, c: Color) -> void:
	var key := c.to_html()
	if not _paint.has(key):
		_paint[key] = Kit.flat(c * 0.4, 0.3, c, 4.0)
	for mi in root.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			if PackView.surface_name(m.mesh, s) == "M_Jet_Glow":
				m.set_surface_override_material(s, _paint[key])


# --- Each tick -------------------------------------------------------------

## Moves everything to the run's current moment. `my_lane` and `me_x` are
## the local pilot's lane and place along the run (for dimming and the
## reticle); `dt` the time since the last sync.
func sync(run: Run, my_lane: float, me_x := 0.0, dt := 1.0 / 60.0) -> void:
	_time += dt
	_edges = _screen_edges(run, hazard.lane)
	if _dying >= 0.0:
		_sync_end(run, dt)
		return
	var shapes := hazard.shapes_at(run.time, run)
	match hazard.kind:
		"zapper":
			_sync_zapper(shapes, my_lane)
		"laser":
			_sync_laser(run, shapes, my_lane, dt)
		"seeker":
			_sync_seeker(run, shapes, my_lane, me_x, dt)
		"shutter":
			_sync_shutter(run, my_lane)
		"eye_drone":
			_sync_robot(shapes, my_lane)
			_play({"look": "Look", "charge": "Charging", "attack": "Attack"}.get(hazard.state, "Idle"))
			_sync_eye(dt)
		"gun_drone":
			_sync_robot(shapes, my_lane)
			_play({"charge": "Charging", "attack": "Attack"}.get(hazard.state, "Idle"))
			_sync_bolts(run, shapes, my_lane)
		"walker":
			_sync_walker(shapes, my_lane, dt)


## The left and right edges of the screen (x) at a lane's depth.
func _screen_edges(run: Run, lane: float) -> Vector2:
	var vp := get_viewport() if is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		var mid := run.cam_x + 4.5 if run else 0.0
		return Vector2(mid - 9.0, mid + 9.0)
	var d := cam.global_position.z - RunView.lane_z(lane)
	# The camera's fov is vertical; the screen's width is that times its aspect.
	var half := d * tan(deg_to_rad(cam.fov) * 0.5) * vp.get_visible_rect().size.aspect()
	return Vector2(cam.global_position.x - half, cam.global_position.x + half)


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
	var d := b - a
	var len := d.length()
	for i in _strands.size():
		var m := _strands[i]
		var r := 0.03 + 0.012 * i
		m.transform = _along(a, b, r)
		m.set_instance_shader_parameter("dim", dim)
		m.set_instance_shader_parameter("span", len)
		m.set_instance_shader_parameter("power", 1.0 - 0.25 * i)
	# A soft glow round the whole arc.
	_beam(0, a, b, float(s[5]) * 1.1, "halo", dim, 0.22)
	_mark(0, a, b, "zapper", dim)
	for i in _crackles.size():
		_crackles[i].position = a if i == 0 else b
	if _light:
		_light.position = (a + b) * 0.5
		_light.light_energy = 1.1 * (1.0 - dim * 0.6)


func _sync_laser(run: Run, shapes: Array, my_lane: float, dt: float) -> void:
	var l := hazard as Laser
	if l.t0 < 0.0:
		for e in _ends:
			e.visible = false
		for a in _arms:
			a.visible = false
		_hide_beams(0)
		return
	var dim := _dim(l.lane, l.lane, my_lane)
	var since := run.time - l.t0
	# The emitters slide in from beyond the edges in the first moment.
	var slide := clampf(since / 0.35, 0.0, 1.0)
	slide = 1.0 - pow(1.0 - slide, 3.0)
	var inset := lerpf(-1.4, 0.55, slide)
	var xl := _edges.x + inset
	var xr := _edges.y - inset
	var y := l.y
	var lens_l := _point(xl, y, l.lane)
	var lens_r := _point(xr, y, l.lane)
	_place_emitter(0, lens_l, 1.0)
	_place_emitter(1, lens_r, -1.0)
	_mark(0, lens_l, lens_r, "laser", dim)
	var firing := not shapes.is_empty()
	if firing:
		_beam(0, lens_l, lens_r, Laser.RADIUS * 0.8, "laser", dim, 1.0)
		_beam(1, lens_l, lens_r, Laser.RADIUS * 2.2, "laser", dim, 0.3)
		_tick -= dt
		if _tick <= 0.0 and fx and dim < 0.5:
			_tick = 0.09
			fx.burst("sparks", global_transform * lens_l, COLORS.laser, 0.35, Vector3(1, 0.3, 0))
			fx.burst("sparks", global_transform * lens_r, COLORS.laser, 0.35, Vector3(-1, 0.3, 0))
	else:
		# Charging: a thin aiming line that brightens and thickens.
		var ph := l.phase
		_beam(0, lens_l, lens_r, 0.018 + 0.04 * ph * ph, "laser", dim, 0.25 + 0.6 * ph)
		_hide_beams(1)
		_tick -= dt
		if _tick <= 0.0 and fx and ph > 0.3 and dim < 0.5:
			_tick = 0.25 - 0.15 * ph
			fx.burst("sparkle", global_transform * lens_l, COLORS.laser, 0.4)
			fx.burst("sparkle", global_transform * lens_r, COLORS.laser, 0.4)


func _place_emitter(i: int, lens: Vector3, facing: float) -> void:
	var e := _ends[i]
	e.visible = true
	e.position = lens
	var arm := _arms[i]
	arm.visible = true
	var top := Run.CEILING - position.y
	var from := lens.y + 0.15
	arm.position = Vector3(lens.x - facing * 0.33, (from + top) * 0.5, lens.z)
	arm.scale = Vector3(1, maxf(top - from, 0.05), 1)


func _sync_seeker(run: Run, shapes: Array, my_lane: float, me_x: float, dt: float) -> void:
	var sk := hazard as Seeker
	var flying := not shapes.is_empty() and sk.t_launch >= 0.0
	_rocket.visible = flying
	if _trail:
		_trail.emitting = flying
	# The reticle: on the pilot's place in the seeker's lane, at its height.
	var aiming := sk.state == "track" or sk.state == "lock"
	_reticle.visible = aiming
	if aiming:
		var locked := sk.state == "lock"
		var tighten := clampf(sk.phase / (Seeker.TRACK / (Seeker.TRACK + Seeker.LOCK)), 0.0, 1.0)
		_reticle.position = _point(me_x, sk.y + 0.75, sk.lane)
		var sz := lerpf(2.4, 1.15, tighten)
		_reticle.scale = Vector3(sz, sz, sz)
		_reticle.set_instance_shader_parameter("lock", 1.0 if locked else 0.0)
		_reticle.set_instance_shader_parameter("spin", _time * (1.5 if not locked else 0.0))
		_reticle.set_instance_shader_parameter("dim", _dim(sk.lane, sk.lane, my_lane))
	if not flying:
		return
	var s: Array = shapes[0]
	_rocket.position = _point((float(s[1]) + float(s[3])) * 0.5, float(s[2]), float(s[6]))
	_rocket.rotation.z = sin(_time * 9.0) * 0.04
	if _flame:
		var len := 0.9 + 0.2 * sin(_time * 31.0) * (1.0 - Fx.steady())
		_flame.scale = Vector3(1, len, 1)
		_flame.position = Vector3(0.5 + len * 0.5, 0, 0)


func _sync_shutter(run: Run, my_lane: float) -> void:
	var sh := hazard as Shutter
	var bottom := sh._bottom(run.time)
	_door.position = _point(sh.x, bottom, sh.lane)
	_door.visible = bottom < Shutter.TOP - 0.05
	var dim := _dim(sh.lane, sh.lane, my_lane)
	var frame := _point(sh.x, Shutter.TOP, sh.lane)
	if sh.t0 >= 0.0:
		_mark(0, frame - Vector3(0.6, 0, 0), frame + Vector3(0.6, 0, 0), "shutter", dim)
	# Warning lights turn while it closes (glow steadily with Reduce flashing).
	var warn := 1.0 if sh.state == "closing" else (0.4 if sh.state == "shut" else 0.15)
	for i in _beacons.size():
		var bc := _beacons[i]
		var pulse := 0.5 + 0.5 * sin(_time * 12.0 + i * PI)
		bc.set_instance_shader_parameter("power", warn * lerpf(pulse, 0.8, Fx.steady()))
		bc.set_instance_shader_parameter("dim", dim)
	if sh.state == "shut" and not _shut:
		_shut = true
		if fx:
			var foot := global_transform * _point(sh.x, 0.05, sh.lane)
			fx.burst("dust", foot, Color(0.8, 0.8, 0.85), 1.0, Vector3.LEFT)
			fx.burst("dust", foot, Color(0.8, 0.8, 0.85), 1.0, Vector3.RIGHT)
			fx.burst("sparks", foot + Vector3(0, 0.1, 0), Color(1.0, 0.75, 0.35), 0.7)


func _sync_robot(shapes: Array, my_lane: float) -> void:
	if shapes.is_empty():
		return
	var s: Array = shapes[0]
	var lift := 0.5 * (ROBOT_SCALE.get(hazard.kind, 1.0) as float)
	_robot.position = _point(float(s[1]), float(s[2]) - lift, float(s[6]))
	_robot.position.y += sin(_time * 3.0 + _seed) * 0.05
	var p := _point(float(s[1]), 0.0, float(s[6]))
	_mark(0, p - Vector3(0.6, 0, 0), p + Vector3(0.6, 0, 0), "eye", _dim(float(s[6]), float(s[6]), my_lane))
	_rim(_dim(float(s[6]), float(s[6]), my_lane))


## The eye drone's charge (a growing glow at its eye) and dash (streaks).
func _sync_eye(dt: float) -> void:
	if hazard.state == "charge":
		_beam(0, _robot.position + Vector3(-0.55, 0.55, 0), _robot.position + Vector3(-0.55, 0.55, 0), 0.08 + 0.22 * hazard.phase, "eye", 0.0, 0.6 + hazard.phase, true)
	elif hazard.state == "attack":
		_beam(0, _robot.position + Vector3(-0.55, 0.55, 0), _robot.position + Vector3(-0.55, 0.55, 0), 0.3, "eye", 0.0, 1.0, true)
		_tick -= dt
		if _tick <= 0.0 and fx:
			_tick = 0.06
			fx.burst("streak", global_transform * (_robot.position + Vector3(0.4, 0.6, 0)), COLORS.eye, 0.5, Vector3.RIGHT)
	else:
		_hide_beams(0)


func _sync_walker(shapes: Array, my_lane: float, dt: float) -> void:
	if shapes.is_empty():
		return
	var w := hazard as Walker
	var s: Array = shapes[0]
	var x := (float(s[1]) + float(s[3])) * 0.5
	var y := Shutter.TOP if w.ceiling else 0.0
	_robot.position = _point(x, y, w.lane)
	# Face the way it's walking.
	var dx := x - _last_x
	_last_x = x
	if absf(dx) > 0.0005:
		var face := -PI * 0.5 if dx < 0.0 else PI * 0.5
		_robot.rotation.y = lerp_angle(_robot.rotation.y, face, 1.0 - exp(-dt * 10.0))
	_play({"walk": "Walk", "roll": "Run"}.get(w.state, "Idle"))
	var p := _point(x, 0.0, w.lane)
	_mark(0, p - Vector3(w.size.x * 0.5, 0, 0), p + Vector3(w.size.x * 0.5, 0, 0), "eye", _dim(w.lane, w.lane, my_lane))
	_rim(_dim(w.lane, w.lane, my_lane))


func _sync_bolts(run: Run, shapes: Array, my_lane: float) -> void:
	var gd := hazard as GunDrone
	if gd.bolts.size() > _bolts_seen:
		_bolts_seen = gd.bolts.size()
		if fx:
			var muzzle := global_transform * (_robot.position + Vector3(-0.6, 0.5, 0))
			fx.burst("ring", muzzle, COLORS.bolt, 1.0, Vector3.RIGHT, 0.5)
			fx.burst("sparks", muzzle, COLORS.bolt, 0.5, Vector3(0, 0, 1))
	var n := 0
	for i in range(1, shapes.size()):
		var s: Array = shapes[i]
		var p := _point(float(s[1]), float(s[2]), float(s[6]))
		var dim := _dim(float(s[6]), float(s[6]), my_lane)
		_beam(n, p, p, float(s[5]) * 0.8, "bolt", dim, 1.3, true)
		n += 1
		# A trail behind it, back the way it came across the lanes.
		var back := Vector3(0, 0, 1.0 if float(s[6]) < float(gd.lane) else -1.0)
		_beam(n, p, p + back * 1.3, float(s[5]) * 0.45, "bolt", dim, 0.5)
		n += 1
	_hide_beams(n)


func _rim(dim: float) -> void:
	for m in _robot_meshes:
		(m as MeshInstance3D).set_instance_shader_parameter("rim", 1.0 - dim * 0.75)


# --- Endings ----------------------------------------------------------------

## The hazard has died (or gone from the run): play its end.
func die(run: Run) -> void:
	if _dying >= 0.0:
		return
	_dying = 0.0
	_hide_beams(0)
	for m in _strands:
		m.visible = false
	for c in _crackles:
		c.emitting = false
	if _reticle:
		_reticle.visible = false
	var how := hazard.state
	match hazard.kind:
		"seeker":
			if how == "fizzle":
				# Coughs out at the right of the screen and drops.
				_rocket.visible = true
				_end_at = _point(_edges.y - 1.5, hazard.y, hazard.lane)
				_rocket.position = _end_at
				if _trail:
					_trail.emitting = true
				if fx:
					fx.burst("smoke", global_transform * _end_at, Color(0.4, 0.4, 0.42), 0.6)
			else:
				if how == "smashed" and fx and _rocket.visible:
					var at := _rocket.global_position
					fx.burst("sparks", at, COLORS.seeker, 1.0)
					fx.burst("smoke", at, Color(0.3, 0.3, 0.33), 0.8)
					fx.burst("ring", at, COLORS.seeker, 1.0, Vector3.UP, 1.4)
				_rocket.visible = false
				if _trail:
					_trail.emitting = false
		"eye_drone", "gun_drone", "walker":
			if how == "smashed" and _robot:
				_play("Hit", 0.05)
				if fx:
					var at := _robot.global_position + Vector3(0, 0.7, 0)
					fx.burst("sparks", at, Color(1.0, 0.75, 0.35), 1.0)
					fx.burst("debris", at, Color.WHITE, 1.0)
					fx.burst("smoke", at, Color(0.3, 0.3, 0.33), 0.8)
					fx.burst("ring", at, Color(1.0, 0.6, 0.3), 1.0, Vector3.UP, 1.5)
			else:
				_dying = 99.0
		_:
			pass


## True once the end has played and the view can go.
func finished() -> bool:
	if _dying < 0.0:
		return false
	return _dying >= float(END_TIME.get(hazard.kind, 0.0))


func _sync_end(run: Run, dt: float) -> void:
	_dying += dt
	var t := _dying
	match hazard.kind:
		"seeker":
			if hazard.state == "fizzle" and _rocket.visible:
				_rocket.position = _end_at + Vector3(-1.5 * t, -2.6 * t * t, 0)
				_rocket.rotation.z = -t * 2.5
				if _flame:
					_flame.visible = fmod(t, 0.16) < 0.08 or Fx.steady() > 0.5
					_flame.scale = Vector3(0.6, 0.5, 0.6)
				if t > 1.2 and fx and _rocket.visible:
					fx.burst("smoke", _rocket.global_position, Color(0.4, 0.4, 0.42), 0.5)
					fx.burst("sparkle", _rocket.global_position, COLORS.seeker, 0.6)
					_rocket.visible = false
		"laser":
			# The emitters slide back out.
			var k := clampf(t / 0.4, 0.0, 1.0)
			for i in _ends.size():
				_ends[i].position.x += (-1.0 if i == 0 else 1.0) * k * 0.25
				_arms[i].position.x += (-1.0 if i == 0 else 1.0) * k * 0.25
			_hide_beams(0)
		"eye_drone", "gun_drone", "walker":
			if _robot:
				if t > 0.35:
					_play("TurnOff", 0.1)
				# Knocked over and down to the floor.
				var floor_y := -position.y
				if hazard.kind == "walker" and (hazard as Walker).ceiling:
					_robot.position.y = maxf(_robot.position.y - dt * 10.0 * t, floor_y)
				elif hazard.kind != "walker":
					_robot.position.y = maxf(_robot.position.y - dt * 9.0 * t, floor_y)
				_robot.rotation.z = lerpf(_robot.rotation.z, 1.1, 1.0 - exp(-dt * 4.0))
				if fmod(t, 0.3) < dt and fx:
					fx.burst("smoke", _robot.global_position + Vector3(0, 0.6, 0), Color(0.28, 0.28, 0.3), 0.3)
				_rim(1.0)


# --- Pieces -----------------------------------------------------------------

func _build_seeker() -> void:
	_rocket = Node3D.new()
	_rocket.name = "Rocket"
	add_child(_rocket)
	var body := Kit.model(_rocket, "seeker", Vector3.ZERO, 0.0, 1.3)
	_repaint_glow(body, COLORS.eye)
	var paint := _halberd_paint()
	for mi in body.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			if PackView.surface_name(m.mesh, s) == "MI_Trim_02_Red":
				m.set_surface_override_material(s, paint)
	_flame = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.09
	c.bottom_radius = 0.015
	c.height = 1.0
	c.radial_segments = 10
	c.rings = 3
	_flame.mesh = c
	var fm := ShaderMaterial.new()
	fm.shader = FLAME
	fm.set_shader_parameter("color", COLORS.seeker)
	fm.set_shader_parameter("strength", 2.6)
	_flame.material_override = fm
	_flame.rotation.z = PI * 0.5
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rocket.add_child(_flame)
	if detail > 0:
		_trail = Fx.emitter("trail", detail)
		(_trail.process_material as ParticleProcessMaterial).direction = Vector3(1, 0, 0)
		_trail.position = Vector3(0.6, 0, 0)
		_trail.emitting = false
		_rocket.add_child(_trail)
	_reticle = MeshInstance3D.new()
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	_reticle.mesh = _quad
	var rm := ShaderMaterial.new()
	rm.shader = RETICLE
	_reticle.material_override = rm
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.visible = false
	add_child(_reticle)


static func _halberd_paint() -> Material:
	if not _paint.has("halberd"):
		var m: ShaderMaterial = load("res://addons/quaternius/materials/MI_Trim_02_Color.tres").duplicate()
		m.set_shader_parameter("Color_Base", Color(2.0, 1.0, 0.1))
		m.set_shader_parameter("Color_Detail", Color(0.2, 0.2, 0.2))
		_paint["halberd"] = m
	return _paint["halberd"]


func _build_shutter() -> void:
	_door = Node3D.new()
	_door.name = "Door"
	add_child(_door)
	# Two of the kit's metal doors, one above the other, turned to close
	# across the lane and stretched to the room's height.
	var slab := Node3D.new()
	_door.add_child(slab)
	for i in 2:
		Kit.model(slab, "Door_Metal", Vector3(0, i * 4.05, 0))
	_fit(slab, Vector3(Shutter.THICK * 2.0, Shutter.TOP, 2.05), Vector3(0, Shutter.TOP * 0.5, 0), true)
	# A hazard band along its bottom edge.
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(Shutter.THICK * 2.0 + 0.04, 0.22, 2.08)
	band.mesh = bb
	band.material_override = Kit.flat(Color(0.9, 0.55, 0.05), 0.5, COLORS.shutter, 0.6)
	band.position = Vector3(0, 0.11, 0)
	_door.add_child(band)
	# Its housing in the ceiling, with two warning lights.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.0, 0.35, 2.4)
	frame.mesh = fb
	frame.material_override = Kit.flat(Color(0.1, 0.1, 0.11), 0.5)
	frame.position = _point(hazard.x, Shutter.TOP - 0.17, hazard.lane)
	add_child(frame)
	for side in [-1.0, 1.0]:
		var bc := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.2
		sm.is_hemisphere = false
		bc.mesh = sm
		bc.material_override = _beam_mat("shutter")
		bc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bc.position = frame.position + Vector3(-0.55, -0.15, side * 0.9)
		add_child(bc)
		_beacons.append(bc)


## Scales and moves a model so its bounds fill `size` centred on `center`.
static func _fit(n: Node3D, size: Vector3, center: Vector3, turn := false) -> void:
	if turn:
		n.rotation.y = PI * 0.5
	var b := Kit.aabb_of(n)
	var s := Vector3(size.x / maxf(b.size.x, 0.01), size.y / maxf(b.size.y, 0.01), size.z / maxf(b.size.z, 0.01))
	var local := Basis.from_euler(n.rotation)
	# The bounds were measured with the turn applied; scale in that space.
	n.transform = Transform3D(Basis.from_scale(s) * local, Vector3.ZERO)
	var b2 := Kit.aabb_of(n)
	n.position = center - b2.get_center()


## A point in the run (x, y, lane) in this node's space.
func _point(x: float, y: float, lane: float) -> Vector3:
	return Vector3(x, y, RunView.lane_z(lane)) - position


func _dim(la: float, lb: float, my_lane: float) -> float:
	var d := minf(absf(la - my_lane), absf(lb - my_lane))
	if my_lane > minf(la, lb) and my_lane < maxf(la, lb):
		d = 0.0
	return clampf(d - 0.3, 0.0, 1.0)


## A transform for a unit cylinder (along Y, height 1) from a to b, radius r.
static func _along(a: Vector3, b: Vector3, r: float) -> Transform3D:
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var up := d / len
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	return Transform3D(Basis(side * r, up * len, fwd * r), (a + b) * 0.5)


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
	m.transform = _along(a, b, r)


static func _strand_mesh() -> CylinderMesh:
	if _strand == null:
		_strand = CylinderMesh.new()
		_strand.top_radius = 1.0
		_strand.bottom_radius = 1.0
		_strand.height = 1.0
		_strand.radial_segments = 6
		_strand.rings = 28
	return _strand


static func _arc_mat(i: int) -> ShaderMaterial:
	if not _arc_mats.has(i):
		var m := ShaderMaterial.new()
		m.shader = ARC
		m.set_shader_parameter("color", COLORS.zapper.lerp(Color.WHITE, 0.15 * i))
		# In the strand's radii (about 3 cm): it wanders some 25 cm.
		m.set_shader_parameter("jitter", 8.0 - i * 1.5)
		m.set_shader_parameter("strength", 2.8)
		_arc_mats[i] = m
	return _arc_mats[i]


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
		_mark_mats[kind] = mat
	m.material_override = _mark_mats[kind]
	var fa := Vector3(a.x, 0.02 - position.y, a.z)
	var fb := Vector3(b.x, 0.02 - position.y, b.z)
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
		m.shader = BEAM
		var c: Color = COLORS.get(kind, COLORS.zapper)
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("crawl", 1.0 if kind == "zapper" else 0.3)
		if kind == "halo":
			m.set_shader_parameter("edge", 0.0)
			m.set_shader_parameter("crawl", 0.0)
		m.set_shader_parameter("strength", 2.2 if kind != "laser" else 3.0)
		_beam_mats[kind] = m
	return _beam_mats[kind]


## A zapper's end: the capacitor model with its glow in the zapper's colour.
func _capacitor() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var m := Kit.model(n, "zapper_node", Vector3.ZERO, 0.0, 1.0)
	_repaint_glow(m, COLORS.zapper)
	return n


## Points a capacitor's top towards the other end.
func _aim_end(n: Node3D, towards: Vector3) -> void:
	if towards.length() < 0.01:
		return
	var up := towards.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	n.basis = Basis(side, up, side.cross(up))
