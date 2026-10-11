class_name PilotView
extends Node3D
## A pilot as you see them: a person in a flight suit with a prototype on
## their back, its flames, a shadow on the floor of their lane, and whatever
## they're riding. Moved to match its [Pilot] every tick by [RunView].
##
## The pilot faces along the run (+x). Flying leans them into it, a lane
## change banks them, the floor makes them run, and a crash slides them.

const JETPACK := "jetpack"
const FLAME_SHADER := preload("res://game/view/fx/beam.gdshader")
## Where the pack sits on the spine bone (the mockup's numbers).
const PACK_OFFSET := Vector3(0.0, -0.2, -0.12)
const VEHICLES := {"raptor": "ess:Enemy_Raptor", "shell": "ess:Enemy_QuadShell", "eye": "ess:Enemy_EyeDrone", "gunner": "ess:Enemy_GunDrone"}
## How big each vehicle is drawn, and where the pilot sits on it.
const VEHICLE_FIT := {"raptor": [1.0, 1.75], "shell": [0.95, 1.25], "eye": [1.7, 1.5], "gunner": [2.0, 1.5]}

static var _shadow_mat: StandardMaterial3D
static var _pack_mats := {}

var pilot: Pilot
var person: Person
var pack: Node3D
var _flames: Array[MeshInstance3D] = []
var _flame_mat: ShaderMaterial
var _shadow: MeshInstance3D
var _vehicle: Node3D
var _vehicle_kind := ""
var _vehicle_anim: AnimationPlayer
var _lean := 0.0
var _bank := 0.0
var _hurt := 0.0
var _shield: MeshInstance3D
var _last_state := -1
var _was_floor := false


static func make(p: Pilot) -> PilotView:
	var v := PilotView.new()
	v.pilot = p
	v.name = "Pilot%d" % p.id
	v._build()
	return v


func _build() -> void:
	var look: Dictionary = pilot.look.duplicate()
	var spec := pilot.spec
	if not look.has("accent"):
		look["accent"] = spec.color
	person = Person.make("pilot", bool(look.get("female", pilot.id % 2 == 1)), int(look.get("seed", pilot.id * 7919)), look)
	person.rotation.y = PI * 0.5
	add_child(person)
	_add_pack(spec)
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 0.9)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	_shadow.material_override = _shadow_material()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	person.play("Jump")


func _add_pack(spec: Dictionary) -> void:
	if not Kit.has(JETPACK) or person.skeleton == null:
		return
	var bone := person.skeleton.find_bone("spine_03")
	if bone < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = "spine_03"
	person.skeleton.add_child(at)
	# Placed in the body's rest space (facing +z, up +y), then carried by
	# the bone. The skeleton sits under the model's own turn and scale.
	var rest := person.skeleton.get_bone_global_rest(bone)
	var skel := Transform3D()
	var n: Node = person.skeleton
	while n and n != person.model:
		if n is Node3D:
			skel = (n as Node3D).transform * skel
		n = n.get_parent()
	var holder := Node3D.new()
	holder.transform = rest.affine_inverse() * skel.affine_inverse()
	at.add_child(holder)
	pack = Kit.model(holder, JETPACK, skel * rest.origin + PACK_OFFSET, PI)
	_paint_pack(pack, spec)
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("color", spec.flame)
	_flame_mat.set_shader_parameter("crawl", 0.6)
	_flame_mat.set_shader_parameter("strength", 2.6)
	for side in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.07
		c.bottom_radius = 0.015
		c.height = 1.0
		c.radial_segments = 10
		c.rings = 1
		f.mesh = c
		f.material_override = _flame_mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pack.add_child(f)
		f.position = Vector3(0.105 * side, -0.31, -0.15)
		_flames.append(f)
	var glow := OmniLight3D.new()
	glow.light_color = spec.flame
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.shadow_enabled = false
	glow.position = Vector3(0, -0.6, -0.15)
	glow.name = "Glow"
	pack.add_child(glow)


## Paints the pack's trim in the prototype's colour.
static func _paint_pack(root: Node3D, spec: Dictionary) -> void:
	var key := str(spec.name)
	if not _pack_mats.has(key):
		var mats := {}
		var red: ShaderMaterial = load("res://addons/quaternius/materials/MI_Trim_02_Color.tres").duplicate()
		red.set_shader_parameter("Color_Base", spec.color)
		red.set_shader_parameter("Color_Detail", spec.color)
		mats["MI_Trim_02_Red"] = red
		var base: ShaderMaterial = load("res://addons/quaternius/materials/MI_Trim_01.tres").duplicate()
		base.set_shader_parameter("Color_Detail", spec.color)
		base.set_shader_parameter("Emissive_B", spec.flame)
		base.set_shader_parameter("Emissive_C", spec.flame)
		mats["MI_Trim_01"] = base
		var glow := Kit.flat(spec.flame * 0.5, 0.3, spec.flame, 3.0)
		mats["M_Jet_Glow"] = glow
		_pack_mats[key] = mats
	var mats: Dictionary = _pack_mats[key]
	for mi in root.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat else ""
			if mats.has(mname):
				m.set_surface_override_material(s, mats[mname])


static func _shadow_material() -> StandardMaterial3D:
	if _shadow_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.albedo_texture = tex
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.albedo_color = Color.WHITE
	return _shadow_mat


## Matches the pilot this tick.
func sync(run: Run, dt: float) -> void:
	var p := pilot
	position = Vector3(p.x, p.y, RunView.lane_z(p.lane))
	_sync_vehicle()
	var riding := p.vehicle != ""
	var lean_to := 0.0
	var bank_to := (float(p.lane_to) - p.lane) * 0.6
	match p.state:
		Pilot.State.FLY:
			if riding:
				person.play("Driving")
			elif p.on_floor and not p.flying:
				person.play("Sprint", -1.0, clampf(run.speed_now / 11.0, 0.9, 1.6))
				lean_to = 0.1
			else:
				person.play("Jump", -1.0, 0.6)
				lean_to = 0.32 if p.flying else 0.12
		Pilot.State.CRASH:
			if p.y > 0.05:
				person.play("Hit_Knockback")
			else:
				person.play("Slide")
			bank_to = 0.0
		Pilot.State.DONE:
			person.play("LayToIdle")
			bank_to = 0.0
		Pilot.State.OUT:
			person.play("Hit_Knockback")
	_lean = lerpf(_lean, lean_to, 1.0 - exp(-dt * 8.0))
	_bank = lerpf(_bank, bank_to, 1.0 - exp(-dt * 12.0))
	person.rotation = Vector3(-_bank, PI * 0.5, -_lean)
	# Flames grow while fly is held.
	var thrust := 1.0 if p.flying and p.alive() and not riding else (0.18 if p.alive() and not riding else 0.0)
	for f in _flames:
		var len := lerpf(f.scale.y, 0.15 + thrust * (0.75 + 0.15 * sin(run.time * 40.0 + f.position.x * 10.0)), 1.0 - exp(-dt * 20.0))
		f.scale = Vector3(1.0, maxf(len, 0.01), 1.0)
		f.position.y = -0.31 - len * 0.5
		f.visible = len > 0.03
	if pack:
		var glow := pack.get_node_or_null("Glow") as OmniLight3D
		if glow:
			glow.light_energy = 0.3 + thrust * 1.4
	# The shadow stays on the floor of the lane, smaller the higher you are.
	var h := maxf(p.y, 0.0)
	_shadow.position = Vector3(0.0, -p.y + 0.02, 0.0)
	var s := clampf(1.0 - h / 9.0, 0.35, 1.0)
	_shadow.scale = Vector3(s, 1.0, s)
	_hurt = maxf(_hurt - dt * 3.0, 0.0)
	var flash := _hurt if fmod(run.time, 0.12) < 0.06 or p.invuln <= 0.0 else 0.0
	if p.invuln > 0.0 and _hurt <= 0.0:
		flash = 0.35 if fmod(run.time, 0.2) < 0.1 else 0.0
	person.set_instance("hurt", flash)
	_sync_shield(p)


func hurt() -> void:
	_hurt = 1.0


func _sync_vehicle() -> void:
	var kind := pilot.vehicle
	if kind == _vehicle_kind:
		if _vehicle:
			var fit: Array = VEHICLE_FIT[kind]
			person.position = Vector3(0, float(fit[1]), 0)
			if kind == "shell" and pilot.upside:
				_vehicle.rotation.z = PI
				_vehicle.position.y = Run.CEILING - pilot.y
				person.position.y = Run.CEILING - pilot.y - float(fit[1]) - 1.8
			else:
				_vehicle.rotation.z = 0.0
				_vehicle.position.y = 0.0
			if _vehicle_anim:
				var clip := "Run" if _vehicle_anim.has_animation("Run") else "Idle"
				if _vehicle_anim.current_animation != clip:
					_vehicle_anim.play(clip)
		return
	if _vehicle:
		_vehicle.queue_free()
		_vehicle = null
		_vehicle_anim = null
	_vehicle_kind = kind
	person.position = Vector3.ZERO
	if kind == "":
		if pack:
			pack.visible = true
		return
	var fit: Array = VEHICLE_FIT[kind]
	_vehicle = Kit.model(self, VEHICLES[kind], Vector3.ZERO, PI * 0.5, float(fit[0]))
	var players := _vehicle.find_children("", "AnimationPlayer", true, false)
	_vehicle_anim = players[0] if not players.is_empty() else null
	if pack:
		pack.visible = false


func _sync_shield(p: Pilot) -> void:
	var on := p.shield > 0 and p.alive()
	if on and _shield == null:
		_shield = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		_shield.mesh = sm
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		m.set_shader_parameter("color", Color(0.3, 0.7, 1.0))
		m.set_shader_parameter("strength", 0.35)
		m.set_shader_parameter("crawl", 0.2)
		_shield.material_override = m
		_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shield.position = Vector3(0, 0.85, 0)
		_shield.scale = Vector3(0.8, 1.05, 0.8)
		add_child(_shield)
	if _shield:
		_shield.visible = on
