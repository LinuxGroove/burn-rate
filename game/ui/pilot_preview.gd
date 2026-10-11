class_name PilotPreview
extends SubViewportContainer
## Your pilot on a turntable in the hangar: the chosen prototype and suit,
## burners lit, turning slowly under a work light.

var _vp: SubViewport
var _stage: Node3D
var _view: PilotView
var _pilot: Pilot
var _run: Run
var _key := ""
var _turn := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.01, 0.022)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.65)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 0.9
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-35, 35, 0)
	_vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = BurnTheme.ORANGE
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	rim.position = Vector3(-1.6, 2.2, -1.8)
	_vp.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = BurnTheme.CYAN
	fill.light_energy = 1.2
	fill.omni_range = 6.0
	fill.position = Vector3(1.8, 1.0, 1.2)
	_vp.add_child(fill)
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.15
	disc.height = 0.08
	disc.radial_segments = 6
	pad.mesh = disc
	pad.material_override = Kit.flat(Color(0.07, 0.08, 0.13), 0.6, BurnTheme.ORANGE, 0.25)
	pad.position = Vector3(0, -0.04, 0)
	_vp.add_child(pad)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.55, 5.6)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	_vp.add_child(cam)
	cam.make_current()
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_run = Run.new({"mode": "endless", "seed": 1})


## Shows a prototype and a look (rebuilt only when they change).
func show_pilot(pack: String, look: Dictionary) -> void:
	if _stage == null:
		await ready
	var key := "%s/%s" % [pack, var_to_str(look)]
	if key == _key:
		return
	_key = key
	if _view:
		_view.queue_free()
	_pilot = Pilot.new(1, "Pilot", pack)
	_pilot.look = look.duplicate()
	_pilot.flying = true
	_pilot.on_floor = false
	_pilot.y = 0.25
	_pilot.lane = 1.0
	_pilot.lane_to = 1
	_view = PilotView.make(_pilot)
	_stage.add_child(_view)


func _process(dt: float) -> void:
	if _view == null:
		return
	_turn += dt * 0.5
	_run.time += dt
	_pilot.x = 0.0
	_view.sync(_run, dt)
	# PilotView puts the pilot in the middle lane; bring it back to the pad.
	_view.position = Vector3(0, 0.25 + sin(_turn * 1.7) * 0.06, 0)
	_view.rotation.y = -0.6 + sin(_turn * 0.6) * 0.9
