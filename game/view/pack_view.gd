class_name PackView
extends Node3D
## A prototype jetpack as you see it: its model ([code]tools/jetpack.py[/code]
## builds all six), painted in the pack's colour, with its flames, the
## sparks they throw and the glow they cast, and its moving parts: K-3's
## glide fins, K-4's pulse drum, K-5's side thrusters and K-6's armour.
## [PilotView] wears one; menus can show one on its own (a hangar stand).
##
## Drive it each frame with [member thrust], [member heat] (the Burn),
## [member side] and [member glide], then [method step]. One-off moments:
## [method kick] (K-4's pulse), [method drop_armour], [method sputter].
##
## Its own space is the model's: +Y up, the pack sticking out along +Z,
## exhaust going down (-Y).

const FLAME := preload("res://game/view/fx/flame.gdshader")
const GHOST := preload("res://game/view/fx/ghost.gdshader")
## Flame length at idle and at full thrust, in metres, for a size-1 nozzle.
const IDLE_LEN := 0.16
const FULL_LEN := 0.72
## Where the main flames point in the world: down, trailing a little behind.
const TRAIL := Vector3(-0.3, -1.0, 0.0)

static var _paint := {}
static var _flame_mats := {}
static var _cone: CylinderMesh
static var _ghost_mat: ShaderMaterial

var id := "k1"
var spec: Dictionary = {}
var detail := 1
var ghost := false
var model: Node3D
## Each flame: {"node", "size", "dir" (exhaust direction), "side" (0, or -1/+1 for K-5's)}.
var flames: Array = []
var sparks: GPUParticles3D
var light: OmniLight3D
var wings: Array = []
var drum: Node3D
var armour: Node3D

## 0 (idle) to 1 (full): how hard it's firing.
var thrust := 0.0
## 0 to 1: the Burn (x1 to x5).
var heat := 0.0
## -1, 0 or 1: K-5's side thrusters push towards the far (+1) or near lane.
var side := 0.0
## 0 folded to 1 spread: K-3's fins.
var glide := 0.0
## False puts the flames out (crashed, riding a vehicle).
var lit := true

var _power := 0.0
var _kick := 0.0
var _sputter := 0.0
var _drum_angle := 0.0
var _drum_to := 0.0
var _armour_t := -1.0
var _armour_from := Transform3D()
var _time := 0.0
var _glide := 0.0
var _side := 0.0


## A pack by id ("k1" to "k6"). `p_detail` 0 skips the sparks and the
## light; `p_ghost` draws it see-through with no light.
static func make(pack_id: String, p_detail := 1, p_ghost := false) -> PackView:
	var v := PackView.new()
	v.id = pack_id if Packs.SPECS.has(pack_id) else "k1"
	v.spec = Packs.spec(v.id)
	v.detail = p_detail
	v.ghost = p_ghost
	v.name = "Pack"
	v._build()
	return v


static func model_name(pack_id: String) -> String:
	return "jetpack_" + pack_id


func _build() -> void:
	model = Kit.model(self, model_name(id), Vector3.ZERO)
	_paint_model()
	for n in model.find_children("Flame_*", "", true, false):
		_add_flame(n as Node3D, Vector3.DOWN, 0)
	for label in ["Side_L", "Side_R"]:
		var n := model.find_child(label, true, false) as Node3D
		if n:
			_add_flame(n, Vector3.LEFT if label == "Side_L" else Vector3.RIGHT, -1 if label == "Side_L" else 1)
	for label in ["Wing_L", "Wing_R"]:
		var n := model.find_child(label, true, false) as Node3D
		if n:
			wings.append([n, 1.0 if label == "Wing_L" else -1.0])
	drum = model.find_child("Drum", true, false) as Node3D
	armour = model.find_child("Armour", true, false) as Node3D
	if armour:
		_armour_from = armour.transform
	if ghost:
		return
	if detail > 0:
		sparks = Fx.emitter("exhaust", detail)
		sparks.amount_ratio = 0.0
		add_child(sparks)
		_place_sparks()
		light = OmniLight3D.new()
		light.name = "Glow"
		light.light_color = spec.flame
		light.light_energy = 0.0
		light.omni_range = 3.2
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.position = _nozzles_mid() + Vector3(0, -0.5, 0)
		add_child(light)
	step(0.0)


func _nozzles_mid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for f in flames:
		if int(f.side) == 0:
			c += (f.anchor as Vector3)
			n += 1
	return c / maxf(n, 1)


func _place_sparks() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for f in flames:
		if int(f.side) == 0:
			lo = lo.min(f.anchor)
			hi = hi.max(f.anchor)
	if lo.x == INF:
		return
	sparks.position = (lo + hi) * 0.5 + Vector3(0, -0.05, 0)
	var m := sparks.process_material as ParticleProcessMaterial
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(maxf((hi.x - lo.x) * 0.5, 0.02), 0.02, maxf((hi.z - lo.z) * 0.5, 0.02))
	sparks.set_instance_shader_parameter("tint", spec.flame.lerp(Color.WHITE, 0.35))


func _add_flame(at: Node3D, dir: Vector3, p_side: int) -> void:
	if _cone == null:
		_cone = CylinderMesh.new()
		_cone.top_radius = 1.0
		_cone.bottom_radius = 0.2
		_cone.height = 1.0
		_cone.radial_segments = 12
		_cone.rings = 4
	var m := MeshInstance3D.new()
	m.name = "Flame%d" % flames.size()
	m.mesh = _cone
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.material_override = _flame_material()
	m.set_instance_shader_parameter("seed", float(flames.size()) * 1.7 + randf())
	add_child(m)
	# A wider, fainter plume round it, so the flame glows rather than
	# looking like a rod. Low detail does without.
	var g: MeshInstance3D = null
	if detail > 0 and not ghost and p_side == 0:
		g = MeshInstance3D.new()
		g.mesh = _cone
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.material_override = m.material_override
		g.set_instance_shader_parameter("seed", float(flames.size()) * 2.9 + 5.0)
		add_child(g)
	var anchor := _model_space(at)
	flames.append({"node": m, "glow": g, "size": at.scale.x if at.scale.x > 0.01 else 1.0, "dir": dir, "side": p_side, "anchor": anchor})


## A node's position in this view's space.
func _model_space(n: Node3D) -> Vector3:
	var xf := Transform3D()
	var c: Node = n
	while c and c != self:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf.origin


func _flame_material() -> ShaderMaterial:
	var key := id + ("/ghost" if ghost else "")
	if not _flame_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAME
		m.set_shader_parameter("color", spec.flame)
		m.set_shader_parameter("strength", 0.6 if ghost else 1.5)
		_flame_mats[key] = m
	return _flame_mats[key]


## Paints the trim in the pack's colour (or makes it a ghost).
func _paint_model() -> void:
	if ghost:
		if _ghost_mat == null:
			_ghost_mat = ShaderMaterial.new()
			_ghost_mat.shader = GHOST
		for mi in model.find_children("", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _ghost_mat
		return
	var mats := materials(id)
	for mi in model.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mname := surface_name(m.mesh, s)
			if mats.has(mname):
				m.set_surface_override_material(s, mats[mname])


## A mesh surface's material name, as the model named it.
static func surface_name(mesh: Mesh, s: int) -> String:
	var n := ""
	if mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(s)
	if n == "":
		var mat := mesh.surface_get_material(s)
		n = mat.resource_name if mat else ""
	return n


## The pack's painted materials by the model's material names, cached.
static func materials(pack_id: String) -> Dictionary:
	if not _paint.has(pack_id):
		var spec := Packs.spec(pack_id)
		var c: Color = spec.color
		var mats := {}
		var paint: ShaderMaterial = load("res://addons/quaternius/materials/MI_Trim_02_Color.tres").duplicate()
		# The trim sheet is mid grey, so the paint is pushed bright to come out vivid.
		paint.set_shader_parameter("Color_Base", Color(c.r * 2.1, c.g * 2.1, c.b * 2.1))
		paint.set_shader_parameter("Color_Detail", Color(1.6, 1.5, 1.4))
		paint.set_shader_parameter("Roughness", 0.55)
		paint.set_shader_parameter("Metallic", 0.35)
		mats["MI_Trim_02_Red"] = paint
		var base: ShaderMaterial = load("res://addons/quaternius/materials/MI_Trim_01.tres").duplicate()
		base.set_shader_parameter("Color_Base", Color(1.15, 1.15, 1.2))
		base.set_shader_parameter("Color_Detail", c)
		base.set_shader_parameter("Emissive_B", spec.flame)
		base.set_shader_parameter("Emissive_C", spec.flame)
		mats["MI_Trim_01"] = base
		mats["M_Jet_Glow"] = Kit.flat(spec.flame * 0.5, 0.3, spec.flame, 4.0)
		mats["M_Jet_Strap"] = Kit.flat(Color(0.05, 0.05, 0.055), 0.75)
		_paint[pack_id] = mats
	return _paint[pack_id]


## A kick of K-4's drum: the flame jumps and the drum turns a notch.
func kick() -> void:
	_kick = 1.0
	_drum_to += TAU / 6.0


## K-6's armour comes off (its one hit).
func drop_armour() -> void:
	if armour and _armour_t < 0.0:
		_armour_t = 0.0


## The flames cough and stutter for `seconds` (a crash, losing the Burn).
func sputter(seconds := 0.6) -> void:
	_sputter = maxf(_sputter, seconds)


## Moves the flames, sparks, light and moving parts on by dt.
func step(dt: float) -> void:
	_time += dt
	var steady := Fx.steady()
	var want := (0.15 + 0.85 * clampf(thrust, 0.0, 1.0)) if lit else 0.0
	if _sputter > 0.0:
		_sputter = maxf(_sputter - dt, 0.0)
		# Coughs on and off (a soft dim with Reduce flashing on).
		var cough := 0.5 + 0.5 * sin(_time * 37.0) * sin(_time * 13.0)
		want *= lerpf(step_f(cough, 0.45), 0.45, steady)
	_power = lerpf(_power, want, 1.0 - exp(-dt * 18.0))
	_kick = maxf(_kick - dt * 6.0, 0.0)
	_side = lerpf(_side, side, 1.0 - exp(-dt * 16.0))
	# The main flames point down and a little behind in the world, whatever
	# the pilot's lean: that's the way the thrust has to push.
	var aim := Vector3.ZERO
	if is_inside_tree():
		aim = (global_transform.basis.inverse() * TRAIL).normalized()
	for f in flames:
		var m: MeshInstance3D = f.node
		var size: float = f.size
		var p := _power
		if int(f.side) != 0:
			# Side thrusters fire only when pushing the other way.
			p = clampf(-_side * float(f.side), 0.0, 1.0) if lit else 0.0
		var len := (IDLE_LEN + (FULL_LEN - IDLE_LEN) * p + heat * 0.35 * p + _kick * 0.6) * size
		if int(f.side) != 0:
			len = 0.55 * p * size
		var r := 0.065 * size * (1.0 + heat * 0.25 + _kick * 0.35)
		m.visible = len > 0.02
		var d: Vector3 = f.dir
		if int(f.side) == 0 and aim != Vector3.ZERO:
			d = d.lerp(aim, 0.8).normalized()
		var b := Fx._basis_up(-d)
		m.transform = Transform3D(b * Basis.from_scale(Vector3(r, len, r)), (f.anchor as Vector3) + d * len * 0.5)
		m.set_instance_shader_parameter("power", clampf(0.35 + p * 0.75 + _kick * 0.6, 0.0, 1.6))
		m.set_instance_shader_parameter("heat", heat)
		var g: MeshInstance3D = f.glow
		if g:
			var gl := len * 0.8
			g.visible = m.visible
			g.transform = Transform3D(b * Basis.from_scale(Vector3(r * 2.3, gl, r * 2.3)), (f.anchor as Vector3) + d * gl * 0.5)
			g.set_instance_shader_parameter("power", clampf(0.1 + p * 0.25 + _kick * 0.3, 0.0, 0.7))
			g.set_instance_shader_parameter("heat", heat * 0.5)
	if sparks:
		if is_inside_tree():
			sparks.global_basis = Fx._basis_up(-TRAIL.normalized())
		sparks.amount_ratio = clampf((_power - 0.3) * 1.4 + heat * 0.4 + _kick, 0.0, 1.0) if lit else 0.0
		sparks.emitting = sparks.amount_ratio > 0.02
	if light:
		light.light_energy = (0.15 + _power * 1.6 + _kick * 1.2) * (1.0 + heat * 0.5) if lit else 0.0
		light.visible = light.light_energy > 0.02
	# K-3's fins.
	_glide = lerpf(_glide, glide, 1.0 - exp(-dt * 7.0))
	for w in wings:
		(w[0] as Node3D).rotation.z = float(w[1]) * 1.35 * (1.0 - _glide)
	# K-4's drum.
	if drum:
		_drum_angle = lerpf(_drum_angle, _drum_to, 1.0 - exp(-dt * 22.0))
		drum.rotation.y = _drum_angle
	# K-6's armour, flung off.
	if armour and _armour_t >= 0.0:
		_armour_t += dt
		var t := _armour_t
		armour.transform = _armour_from.translated_local(Vector3(0, 1.8 * t - 4.0 * t * t, 1.2 * t)).rotated_local(Vector3.RIGHT, t * 6.0)
		armour.visible = t < 0.9


static func step_f(x: float, edge: float) -> float:
	return 1.0 if x >= edge else 0.0

