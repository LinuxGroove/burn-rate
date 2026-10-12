class_name RoomView
extends Node3D
## One room of the tower as you see it, built from a [RoomGen] and the look
## of its zone: the floor two tiles deep with the lines between the lanes,
## the back wall and what's behind it, the ceiling and its lights, neon
## trims, and furniture along the back wall, out of every lane. The front of
## the building is cut away so you see in. Downtown is the rooftops outside
## (see [CityRoofs]).
##
## Kit pieces go through a [Kit.Batch] (each distinct mesh is one
## MultiMesh) and glowing strips and plain blocks through [Kit.Shapes] (one
## mesh each), so a room is a few dozen draws and builds without
## instancing scenes.
##
## The room's origin is its start; x runs along the run, y up from the floor
## and z towards the camera, with lanes at [method RunView.lane_z].

## Each zone's colours. accent: neon trims and the kit's lit details;
## accent2: a second neon; light/light2: the ceiling lights, alternating;
## energy: their strength; base: the kit's pale panels; dark: its dark
## ones; lines: the lane lines; floor/floor_alt: floor tiles; gloss: how
## shiny the floor is (0 matte, 1 mirror).
const ZONES := {
	"lab": {"accent": Color(0.15, 0.85, 1.0), "accent2": Color(0.9, 0.97, 1.0), "light": Color(0.82, 0.93, 1.0),
		"light2": Color(0.35, 0.8, 1.0), "energy": 3.2, "base": Color(0.9, 0.93, 0.98), "dark": Color(0.2, 0.23, 0.27),
		"lines": Color(0.2, 0.85, 1.0), "floor": "Platform_Simple2", "floor_alt": "Platform_Simple", "gloss": 0.6},
	"servers": {"accent": Color(0.15, 1.0, 0.6), "accent2": Color(0.2, 0.5, 1.0), "light": Color(0.3, 0.75, 1.0),
		"light2": Color(0.2, 1.0, 0.7), "energy": 2.6, "base": Color(0.32, 0.36, 0.42), "dark": Color(0.1, 0.12, 0.15),
		"lines": Color(0.2, 1.0, 0.65), "floor": "Platform_DarkPlates", "floor_alt": "Platform_Metal2", "gloss": 0.75},
	"bay": {"accent": Color(1.0, 0.5, 0.08), "accent2": Color(1.0, 0.82, 0.2), "light": Color(1.0, 0.62, 0.3),
		"light2": Color(1.0, 0.82, 0.55), "energy": 3.0, "base": Color(0.6, 0.58, 0.55), "dark": Color(0.16, 0.15, 0.14),
		"lines": Color(1.0, 0.7, 0.15), "floor": "Platform_3Plates", "floor_alt": "Platform_Metal", "gloss": 0.45},
	"atrium": {"accent": Color(1.0, 0.72, 0.3), "accent2": Color(1.0, 0.45, 0.55), "light": Color(1.0, 0.82, 0.58),
		"light2": Color(1.0, 0.6, 0.45), "energy": 2.6, "base": Color(0.95, 0.9, 0.82), "dark": Color(0.22, 0.19, 0.16),
		"lines": Color(1.0, 0.78, 0.35), "floor": "Platform_Simple", "floor_alt": "Platform_Window_Wide", "gloss": 0.8},
	"downtown": {"accent": Color(1.0, 0.2, 0.65), "accent2": Color(0.2, 0.9, 1.0), "light": Color(1.0, 0.3, 0.7),
		"light2": Color(0.3, 0.8, 1.0), "energy": 2.4, "base": Color(0.5, 0.5, 0.55), "dark": Color(0.12, 0.12, 0.14),
		"lines": Color(1.0, 0.3, 0.75), "floor": "city:Roof_4x4", "floor_alt": "Platform_Metal", "gloss": 0.55},
	"halberd": {"accent": Color(1.0, 0.1, 0.15), "accent2": Color(0.95, 0.95, 1.0), "light": Color(1.0, 0.25, 0.25),
		"light2": Color(0.8, 0.86, 1.0), "energy": 3.6, "base": Color(0.42, 0.42, 0.45), "dark": Color(0.2, 0.2, 0.22),
		"lines": Color(1.0, 0.2, 0.25), "floor": "Platform_RedAccent", "floor_alt": "Platform_DarkPlates", "gloss": 0.7},
}
## What each zone calls itself on the sign over its door.
const SIGNS := {
	"lab": "KESTREL LIFT  ·  TEST LAB  ·  41", "servers": "SERVER HALL  ·  40", "bay": "ROBOT BAY  ·  39",
	"atrium": "THE ATRIUM", "downtown": "", "halberd": "HALBERD SECURITY  ·  12",
}
const FLOOR_DEPTH := 8.0
const FRONT := 2.0
const BACK := -6.0
## Furniture stands here: behind the far lane, in front of the back wall.
const PROPS_Z := -5.3
## How far apart the ceiling lights are (twice that on low detail).
const LIGHT_EVERY := 8.0
const FONT := "res://addons/linuxgroove/ui/fonts/Kenney Future.ttf"
const NEON_SHADER := preload("res://game/view/city_neon.gdshader")

static var _swaps := {}
static var _neon_mat: ShaderMaterial
static var _flat_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _leaf_mat: StandardMaterial3D
static var _leaf_mesh: SphereMesh
static var _font: Font
static var _rack_meshes: Array = []
static var _warmed := -1

var room: RoomGen
var style: Dictionary
var detail := 1
## The pieces being built (see [method _flush]).
var walls: Kit.Batch
var floors: Kit.Batch
var neon: Kit.Shapes
var flat: Kit.Shapes
var glass: Kit.Shapes
var rng := RandomNumberGenerator.new()
var _leaves: Array[Transform3D] = []
var _lights := 0


static func style_of(zone: String) -> Dictionary:
	return ZONES.get(zone, ZONES["lab"])


static func make(r: RoomGen, p_detail := 1) -> RoomView:
	var v := RoomView.new()
	v.name = "Room%d" % r.index
	v.room = r
	v.detail = p_detail
	v.style = style_of(r.zone)
	v.position = Vector3(r.x0, 0, 0)
	v._build()
	return v


## Builds and drops a few rooms of every zone, doors and windows included,
## so the pieces, recoloured materials and sign lettering they share are
## ready before the run starts and no room costs more than its own build
## when it streams in.
static func prewarm(p_detail := 1) -> void:
	if _warmed == p_detail:
		return
	_warmed = p_detail
	_racks()
	var index := 100000
	for zone in Zones.ORDER:
		var variants := [{}, {"entry": zone}, {}]
		if zone == "downtown":
			variants.append({"entry": zone, "window_out": true})
		elif zone == "halberd":
			variants.append({"entry": zone, "window_in": true})
		for tags in variants:
			index += 1
			var r := RoomGen.new(index, zone, 0.0, 0.5, 10.0, true, index)
			r.fit(40.0)
			r.tags = tags.duplicate()
			if zone == "downtown":
				r.tags["outside"] = true
			var v := make(r, p_detail)
			v.free()


## The material for neon strips, signs and status lights in the rooms.
static func neon_material() -> ShaderMaterial:
	if _neon_mat == null:
		_neon_mat = ShaderMaterial.new()
		_neon_mat.shader = NEON_SHADER
		_neon_mat.set_shader_parameter("energy", 2.8)
		_neon_mat.set_shader_parameter("blink", 1.0)
	return _neon_mat


## The Calm background setting for the rooms (1 is full): their neon dims a
## little and the status lights stop blinking.
static func set_dim(d: float) -> void:
	var m := neon_material()
	m.set_shader_parameter("dim", lerpf(0.7, 1.0, d))
	m.set_shader_parameter("blink", 1.0 if d >= 1.0 else 0.0)


static func _materials() -> void:
	if _flat_mat != null:
		return
	neon_material()
	_flat_mat = StandardMaterial3D.new()
	_flat_mat.vertex_color_use_as_albedo = true
	_flat_mat.roughness = 0.55
	_flat_mat.metallic = 0.3
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.vertex_color_use_as_albedo = true
	_glass_mat.roughness = 0.05
	_glass_mat.metallic_specular = 1.0
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.1, 0.3, 0.14)
	_leaf_mat.roughness = 0.7
	_leaf_mat.rim_enabled = true
	_leaf_mat.rim = 0.4
	_leaf_mesh = SphereMesh.new()
	_leaf_mesh.radius = 0.5
	_leaf_mesh.height = 0.85
	_leaf_mesh.radial_segments = 7
	_leaf_mesh.rings = 4
	_font = load(FONT)


## The kit's materials recoloured for a zone (walls and props), or for its
## floor (glossier), cached.
static func swap_for(zone: String, for_floor := false) -> Dictionary:
	var key := zone + ("/floor" if for_floor else "")
	if _swaps.has(key):
		return _swaps[key]
	var s: Dictionary = style_of(zone)
	var out := {}
	var dir := "res://addons/quaternius/materials/"
	for n in ["MI_Trim_01", "MI_Trim_02", "MI_Trim_03", "MI_Trim_03_Dark", "MI_Trim_02_Floor", "MI_PaddedWall", "MI_Trim_02_Variation", "MI_Trim_02_Color", "MI_Trim_02_NoAccent"]:
		var src: ShaderMaterial = load(dir + n + ".tres")
		if src == null:
			continue
		var m: ShaderMaterial = src.duplicate()
		var accent: Color = s.accent
		m.set_shader_parameter("Color_Detail", accent)
		m.set_shader_parameter("Emissive_A", s.accent2)
		m.set_shader_parameter("Emissive_B", accent)
		m.set_shader_parameter("Emissive_C", accent)
		if n == "MI_Trim_03" or n == "MI_Trim_02_Variation":
			m.set_shader_parameter("Color_Base", s.base)
		elif n == "MI_Trim_03_Dark":
			m.set_shader_parameter("Color_Base", s.dark)
		elif n == "MI_Trim_02" or n == "MI_Trim_02_NoAccent":
			m.set_shader_parameter("Color_Base", (s.base as Color).lerp(Color.WHITE, 0.3))
		if not for_floor and n in ["MI_Trim_01", "MI_Trim_02", "MI_Trim_02_NoAccent", "MI_Trim_02_Variation"]:
			m.set_shader_parameter("Metallic", 0.55)
		if for_floor:
			if n == "MI_Trim_03":
				m.set_shader_parameter("Color_Base", (s.base as Color) * 0.55)
			var g := float(s.gloss)
			m.set_shader_parameter("Roughness", lerpf(1.0, 0.1, g))
			m.set_shader_parameter("Specular", lerpf(0.2, 0.7, g))
			m.set_shader_parameter("Metallic", 0.4)
		out[n] = m
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.65, 0.75, 0.08)
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	out["M_Glass"] = glass
	for n in ["MI_StatScreens_1", "MI_StatScreens_2", "MI_StatScreens_3"]:
		var src: ShaderMaterial = load(dir + n + ".tres")
		if src:
			var m: ShaderMaterial = src.duplicate()
			m.set_shader_parameter("Color_A", s.accent)
			m.set_shader_parameter("Color_B", s.accent2)
			m.set_shader_parameter("Base_Color", s.accent)
			out[n] = m
	for n in ["MI_Hologram", "MI_HologramDesk"]:
		var src: ShaderMaterial = load(dir + n + ".tres")
		if src:
			var m: ShaderMaterial = src.duplicate()
			m.set_shader_parameter("Hologram_Color", s.accent)
			out[n] = m
	# The city kit's shop signs glow at night.
	var signs := StandardMaterial3D.new()
	var tex: Texture2D = load("res://addons/quaternius/downtowncity/materials/T_Shop_Signs_BaseColor.png")
	signs.albedo_texture = tex
	signs.emission_enabled = true
	signs.emission_texture = tex
	signs.emission_energy_multiplier = 1.6
	out["MI_Shop_Signs"] = signs
	_swaps[key] = out
	return out


func _build() -> void:
	_materials()
	rng.seed = hash([room.index, room.zone, "look"])
	walls = Kit.Batch.new()
	walls.swap = swap_for(room.zone)
	walls.swap_key = room.zone
	floors = Kit.Batch.new()
	floors.swap = swap_for(room.zone, true)
	floors.swap_key = room.zone + "/floor"
	neon = Kit.Shapes.new()
	flat = Kit.Shapes.new()
	glass = Kit.Shapes.new()
	var outside := room.tags.has("outside")
	_floor_slab()
	_lane_lines()
	if outside:
		CityRoofs.build(self)
	else:
		match room.zone:
			"servers":
				_servers()
			"bay":
				_bay()
			"atrium":
				_atrium()
			"halberd":
				_halberd()
			_:
				_lab()
		_tags()
		_foreground()
	if room.tags.has("window_in"):
		_tower_face(false)
	for p in room.props:
		var lane := int(p[2])
		var z := PROPS_Z if lane < 0 else RunView.lane_z(lane)
		walls.put(str(p[0]), Vector3(float(p[1]) - room.x0, float(p[3]), z), float(p[4]))
	_flush()


## Builds what's been collected.
func _flush() -> void:
	floors.build(self)
	walls.build(self)
	if not neon.is_empty():
		add_child(neon.instance(_neon_mat))
	if not flat.is_empty():
		add_child(flat.instance(_flat_mat))
	if not glass.is_empty():
		add_child(glass.instance(_glass_mat))
	if not _leaves.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _leaf_mesh
		mm.instance_count = _leaves.size()
		for i in _leaves.size():
			mm.set_instance_transform(i, _leaves[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _leaf_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- Shared ------------------------------------------------------------------

func tiles() -> int:
	return int(round(room.length / Kit.TILE))


## A wall piece along the back: the kit's walls stand on a tile's west edge
## facing east, so they're turned to face the camera.
func wall(piece: String, cx: float, y: float, z := BACK + 2.0) -> void:
	walls.put(piece, Vector3(cx, y, z), -PI * 0.5)


## The floor tiles, two deep, with every `alt_every`th one swapped.
func floor_tiles(piece: String, alt := "", alt_every := 0, y := 0.0) -> void:
	for i in tiles():
		var cx := Kit.TILE * (i + 0.5)
		for zc in [0.0, -4.0]:
			var p := piece
			if alt != "" and alt_every > 0 and (i + int(zc != 0.0)) % alt_every == 0:
				p = alt
			floors.put(p, Vector3(cx, y, zc))


## Flipped floor plates as the ceiling (the kit has none), `depth` tiles deep.
func ceiling(piece: String, depth := 2, y := Run.CEILING) -> void:
	for i in tiles():
		for j in depth:
			walls.add(piece, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(Kit.TILE * (i + 0.5), y, -4.0 * j)))


## A glowing strip from `a` to `b` (along one axis), `t` thick.
func strip(a: Vector3, b: Vector3, t: float, color: Color) -> void:
	var size := (b - a).abs() + Vector3(t, t, t)
	color.a = 1.0
	neon.box((a + b) * 0.5, size, color)


## Ceiling lights: the kit's fittings, a glowing bar under each, and real
## lights alternating two colours (fewer on low detail).
func lights(fitting := "Prop_Light_Wide", y := Run.CEILING - 0.02, z := -1.6, light_y := Run.CEILING - 1.2, energy_scale := 1.0, range := 11.0) -> void:
	var n := maxi(1, int(room.length / LIGHT_EVERY))
	for i in n:
		var x := LIGHT_EVERY * (i + 0.5)
		if fitting != "":
			walls.put(fitting, Vector3(x, y, z))
		var c: Color = style.light if i % 2 == 0 else style.light2
		if detail >= 1 or i % 2 == 0:
			add_light(Vector3(x, light_y, z + 0.4), c, float(style.energy) * energy_scale * (1.0 if detail >= 1 else 1.5), range)


func add_light(pos: Vector3, c: Color, energy: float, range := 11.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.light_specular = 0.8
	l.omni_range = range * 1.15
	l.omni_attenuation = 1.1
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	_lights += 1
	return l


## Text on a wall that glows, like a lit sign.
func glow_text(text: String, pos: Vector3, size := 64, color := Color.WHITE, yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color * 2.2
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


## The dark block under the floor, where the HUD sits, with a lit edge.
func _floor_slab() -> void:
	var front: Color = style.dark
	flat.box(Vector3(room.length * 0.5, -3.02, (FRONT + BACK) * 0.5 + 0.05), Vector3(room.length, 6.0, FLOOR_DEPTH + 0.1), Color(0.02, 0.02, 0.03).lerp(front, 0.2), Basis(), 1 << 4 | 1 << 2)
	strip(Vector3(0, -0.04, FRONT + 0.03), Vector3(room.length, -0.04, FRONT + 0.03), 0.05, style.accent * 0.9)


## Lines on the floor between the lanes, so the depth reads.
func _lane_lines() -> void:
	if not room.lanes:
		return
	var c: Color = style.lines
	for z in [RunView.lane_z(0.5), RunView.lane_z(1.5)]:
		neon.box(Vector3(room.length * 0.5, 0.012, z), Vector3(room.length, 0.012, 0.06), Kit.dimmed(c, 0.55))


## Now and then a pillar right in front of the camera, dark against the
## room, that sweeps past and sells the speed. Never at a zone's door.
func _foreground() -> void:
	if room.tags.has("entry") or room.tags.has("start") or rng.randf() > 0.45:
		return
	var x := rng.randf_range(4.0, room.length - 4.0)
	var z := 6.0
	flat.box(Vector3(x, 4.0, z), Vector3(0.7, 12.0, 0.7), Color(0.015, 0.015, 0.02))
	strip(Vector3(x + 0.36, -2.0, z + 0.2), Vector3(x + 0.36, 10.0, z + 0.2), 0.03, style.accent * 0.6)


## Things the pattern's tags ask for: a door at the start of a zone, rails
## for walkers on the ceiling, frames for shutters, the finish.
func _tags() -> void:
	if room.tags.has("window_in"):
		# In through the window: no doorway, but the zone's sign on the wall.
		glow_text(SIGNS.get(room.zone, ""), Vector3(6.7, 6.0, BACK + 0.25), 48, style.accent)
	elif room.tags.has("entry"):
		_doorway(1.2, SIGNS.get(room.zone, ""))
	if room.tags.has("rails"):
		for lane in 3:
			var z := RunView.lane_z(lane)
			flat.box(Vector3(room.length * 0.5, Run.CEILING - 0.12, z), Vector3(room.length, 0.18, 0.28), Color(0.12, 0.12, 0.13))
			strip(Vector3(0, Run.CEILING - 0.22, z), Vector3(room.length, Run.CEILING - 0.22, z), 0.03, style.accent * 0.5)
	if room.tags.has("finish"):
		_doorway(2.0, "FINISH", Color(1.0, 0.8, 0.25))


## A bulkhead across the room: a post at the back wall, one in the
## foreground (it sweeps past), a lit beam overhead and the zone's sign.
func _doorway(x: float, text: String, c := Color(-1, 0, 0)) -> void:
	var col: Color = style.accent if c.r < 0.0 else c
	flat.box(Vector3(x, 4.0, BACK + 0.3), Vector3(1.2, 8.0, 0.8), Color(0.05, 0.05, 0.06))
	flat.box(Vector3(x, Run.CEILING - 0.35, -2.0), Vector3(1.2, 0.7, 8.6), Color(0.05, 0.05, 0.06))
	flat.box(Vector3(x, 4.0, 6.3), Vector3(0.9, 14.0, 0.9), Color(0.012, 0.012, 0.016))
	strip(Vector3(x + 0.61, 0.0, BACK + 0.72), Vector3(x + 0.61, 8.0, BACK + 0.72), 0.05, col)
	strip(Vector3(x + 0.61, Run.CEILING - 0.72, BACK + 0.7), Vector3(x + 0.61, Run.CEILING - 0.72, FRONT + 0.2), 0.05, col)
	strip(Vector3(x + 0.46, -2.0, 6.76), Vector3(x + 0.46, 10.0, 6.76), 0.04, col * 0.7)
	if text != "":
		glow_text(text, Vector3(x + 5.5, 6.0, BACK + 0.25), 48, col)


## The outside of the next tower where the run flies back in (or of this
## one where it smashes out): a wall of windows across the run at x = 0,
## with the room's opening in it and glass on the floor.
func _tower_face(out: bool) -> void:
	var s := Kit.Shapes.new()
	var f := 1 << 1 if not out else 1 << 0
	var tint := Color(0.3, 0.32, 0.4, 0.83)
	var x := 0.0
	# Above, below and behind the room's opening.
	s.box(Vector3(x, 34.0, -19.0), Vector3(0.4, 52.0, 42.0), tint, Basis(), f)
	s.box(Vector3(x, -14.0, -19.0), Vector3(0.4, 28.0, 42.0), tint, Basis(), f)
	s.box(Vector3(x, 4.0, -23.2), Vector3(0.4, 8.0, 33.6), tint, Basis(), f)
	add_child(s.instance(CityBackdrop.tower_mat))
	# The frame of the opening, and what's left of its glass.
	var side := -0.3 if not out else 0.3
	for y in [0.0, Run.CEILING]:
		flat.box(Vector3(x, y, -2.0), Vector3(0.6, 0.3, 8.6), Color(0.06, 0.06, 0.07))
	flat.box(Vector3(x, 4.0, BACK - 0.15), Vector3(0.6, 8.0, 0.3), Color(0.06, 0.06, 0.07))
	strip(Vector3(x + side, Run.CEILING, BACK), Vector3(x + side, Run.CEILING, FRONT), 0.04, style.accent)
	var g := Color(0.6, 0.85, 1.0, 0.25)
	for i in 7:
		var z := lerpf(BACK + 0.4, FRONT - 0.4, float(i) / 6.0)
		var top := rng.randf_range(0.8, 2.4)
		glass.box(Vector3(x, Run.CEILING - top * 0.5, z), Vector3(0.02, top, 1.1), g, Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)))
		var bot := rng.randf_range(0.3, 1.2)
		glass.box(Vector3(x, bot * 0.5, z), Vector3(0.02, bot, 1.1), g, Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)))
	# Shards across the floor, glinting.
	for i in 26:
		var p := Vector3(rng.randf_range(0.5, 12.0), 0.02, rng.randf_range(BACK + 0.3, FRONT - 0.2))
		glass.box(p, Vector3(rng.randf_range(0.1, 0.4), 0.02, rng.randf_range(0.08, 0.3)), Color(0.75, 0.9, 1.0, 0.5), Basis(Vector3.UP, rng.randf() * TAU))


# --- Test Lab ------------------------------------------------------------------

func _lab() -> void:
	floor_tiles(style.floor)
	ceiling("Platform_Simple")
	var t := tiles()
	for i in t:
		var cx := Kit.TILE * (i + 0.5)
		var r := rng.randf()
		var low := "WallAstra_Straight_Flat" if r < 0.55 else ("WallAstra_Straight" if r < 0.85 else "WallAstra_Straight_Flat_Window")
		wall(low, cx, 0.0)
		wall("TopPlastic_Straight", cx, 0.0)
		wall("WallWindow_Straight", cx, 5.0)
	# Cyan light along the foot of the wall and the top of the panels.
	strip(Vector3(0, 0.05, BACK + 0.12), Vector3(room.length, 0.05, BACK + 0.12), 0.07, style.accent)
	strip(Vector3(0, 3.02, BACK + 0.16), Vector3(room.length, 3.02, BACK + 0.16), 0.05, style.accent * 0.8)
	strip(Vector3(0, 5.0, BACK + 0.2), Vector3(room.length, 5.0, BACK + 0.2), 0.04, style.accent2 * 0.5)
	lights()
	if room.tags.has("start"):
		_lab_lobby()
		return
	if room.tags.has("finish"):
		return
	var x := 1.6
	while x < room.length - 1.6:
		var r := rng.randf()
		if r < 0.22:
			_desk(x)
			x += 3.4
		elif r < 0.36:
			# A test pod, lit from inside.
			walls.put("Prop_Pod_Short", Vector3(x + 0.6, 0.0, PROPS_Z - 0.3), 0.0, 0.62)
			neon.box(Vector3(x + 0.6, 0.06, PROPS_Z - 0.3), Vector3(0.9, 0.05, 0.9), Kit.dimmed(style.accent, 0.8))
			x += 2.4
		elif r < 0.5:
			walls.put("ess:Prop_HologramMap1", Vector3(x + 1.0, 0.75, PROPS_Z), 0.0, 0.55)
			walls.put("ess:Prop_Desk_Small", Vector3(x + 1.0, 0.0, PROPS_Z), 0.0, 0.75)
			x += 3.0
		elif r < 0.62:
			walls.put("ess:Prop_Locker", Vector3(x + 0.5, 0.0, BACK + 0.35))
			walls.put("ess:Prop_Locker", Vector3(x + 1.5, 0.0, BACK + 0.35))
			x += 2.6
		elif r < 0.72:
			_prototype_stand(x + 0.6)
			x += 2.2
		else:
			x += rng.randf_range(1.5, 3.0)


## A desk with a computer and a screen, facing the room.
func _desk(x: float) -> void:
	walls.put("ess:Prop_Desk_Medium", Vector3(x + 1.4, 0.0, PROPS_Z), 0.0, 0.85)
	walls.put("ess:Prop_Screen", Vector3(x + 0.8, 0.8, PROPS_Z - 0.1))
	walls.put("ess:Prop_Screen", Vector3(x + 1.8, 0.8, PROPS_Z - 0.1))
	walls.put("ess:Prop_Chair", Vector3(x + 1.3, 0.0, PROPS_Z + 0.55), PI, 0.8)


## One of the prototypes on its stand under a spotlight.
func _prototype_stand(x: float) -> void:
	flat.box(Vector3(x, 0.45, PROPS_Z), Vector3(0.7, 0.9, 0.7), Color(0.85, 0.88, 0.92))
	neon.box(Vector3(x, 0.91, PROPS_Z), Vector3(0.74, 0.03, 0.74), style.accent)
	walls.put("jetpack", Vector3(x, 1.35, PROPS_Z), 0.4, 1.4)


## Kestrel Lift's lobby: the name on the wall and the prototypes on stands.
func _lab_lobby() -> void:
	glow_text("KESTREL LIFT", Vector3(10.0, 4.1, BACK + 0.25), 150, style.accent)
	glow_text("PROTOTYPE TEST LAB  ·  FLOOR 41", Vector3(10.0, 3.35, BACK + 0.25), 40, style.accent2 * 0.8)
	for i in 6:
		_prototype_stand(22.0 + i * 3.0)
	_desk(1.0)


# --- Server Hall ---------------------------------------------------------------

## Dark aisles of racks behind a glass wall, blinking.
func _servers() -> void:
	floor_tiles(style.floor)
	# The hall goes on behind the glass: floor, ceiling and three rows of racks.
	var t := tiles()
	for i in t:
		var cx := Kit.TILE * (i + 0.5)
		for zc in [-8.0, -12.0, -16.0]:
			floors.put(style.floor_alt, Vector3(cx, 0.0, zc))
		wall("WallWindow_Straight", cx, 5.0)
		# The far end of the hall, dark.
		walls.put("WallBand_Straight", Vector3(cx, 0.0, -16.0), -PI * 0.5)
		walls.put("TopCables_Straight", Vector3(cx, 0.0, -16.0), -PI * 0.5)
	ceiling("Platform_DarkPlates", 2)
	for i in t:
		for zc in [-8.0, -12.0, -16.0]:
			walls.add("Platform_DarkPlates", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(Kit.TILE * (i + 0.5), 5.0, zc)))
	# The glass wall: thin mullions and clear panes.
	var x := 0.0
	while x <= room.length:
		flat.box(Vector3(x, 2.5, BACK), Vector3(0.12, 5.0, 0.12), Color(0.08, 0.09, 0.1))
		x += 2.0
	flat.box(Vector3(room.length * 0.5, 0.06, BACK), Vector3(room.length, 0.12, 0.2), Color(0.08, 0.09, 0.1))
	glass.box(Vector3(room.length * 0.5, 2.5, BACK), Vector3(room.length, 5.0, 0.02), Color(0.4, 0.75, 0.8, 0.07))
	strip(Vector3(0, 0.03, BACK + 0.2), Vector3(room.length, 0.03, BACK + 0.2), 0.06, style.accent)
	strip(Vector3(0, 4.96, BACK + 0.12), Vector3(room.length, 4.96, BACK + 0.12), 0.05, style.accent2 * 0.8)
	for row in [-7.6, -11.0, -14.4]:
		_rack_row(row, row == -7.6)
	# Blue light down the aisles.
	for z in [-9.3, -12.7]:
		strip(Vector3(0, 0.02, z), Vector3(room.length, 0.02, z), 0.08, style.accent2 * 0.7)
		strip(Vector3(0, 4.85, z), Vector3(room.length, 4.85, z), 0.1, style.light * 0.8)
	lights("", 0.0, -1.6, Run.CEILING - 1.0, 1.0)
	# Hanging cables over the lanes.
	for i in t:
		if rng.randf() < 0.5:
			wall("TopCables_Straight_Hanging", Kit.TILE * (i + 0.5), 3.0, -2.0)
	# A few terminals in front of the glass.
	x = 2.0
	while x < room.length - 2.0:
		if rng.randf() < 0.35:
			walls.put("ess:Prop_Computer", Vector3(x, 0.0, PROPS_Z), 0.0)
		x += rng.randf_range(3.0, 6.0)
	if detail >= 1:
		add_light(Vector3(room.length * 0.5, 3.6, -11.0), style.light2, 2.0, 12.0)


## A row of racks along the hall, facing the room, covered in status lights.
func _rack_row(z: float, near: bool) -> void:
	var racks := _racks()
	var x := 0.3
	while x < room.length - 0.9:
		var m: Mesh = racks[rng.randi() % racks.size()]
		walls.add_mesh(m, Transform3D(Basis(), Vector3(x + 0.45, 0.0, z)))
		x += 0.9 + (0.02 if rng.randf() < 0.9 else 1.2)
	if near:
		strip(Vector3(0, 2.7, z + 0.55), Vector3(room.length, 2.7, z + 0.55), 0.03, style.accent * 0.6)


## A few server racks, made once and placed many times: a dark cabinet of
## units, each with a few status lights (blinking ones vary by where the
## rack stands; see city_neon.gdshader).
static func _racks() -> Array:
	if not _rack_meshes.is_empty():
		return _rack_meshes
	_materials()
	var leds := [Color(0.2, 1.0, 0.45), Color(0.25, 0.6, 1.0), Color(1.0, 0.7, 0.15), Color(0.2, 1.0, 0.45), Color(0.3, 0.9, 1.0)]
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for variant in 6:
		var body := Kit.Shapes.new()
		var lit := Kit.Shapes.new()
		var w := 0.9
		var h := r.randf_range(2.3, 2.6)
		body.box(Vector3(0, h * 0.5, 0), Vector3(w - 0.04, h, 1.0), Color(0.05, 0.055, 0.065))
		var y := 0.25
		while y < h - 0.2:
			var uh := r.randf_range(0.12, 0.35)
			body.box(Vector3(0, y + uh * 0.5, 0.5), Vector3(w - 0.14, uh - 0.03, 0.02), Color(0.09, 0.1, 0.12), Basis(), 0b010000)
			for k in r.randi_range(1, 5):
				var c: Color = leds[r.randi() % leds.size()]
				c.a = r.randf_range(0.05, 0.99) if r.randf() < 0.6 else 1.0
				lit.box(Vector3(-w * 0.5 + 0.12 + k * 0.07, y + uh * 0.5, 0.52), Vector3(0.035, 0.025, 0.01), c, Basis(), 0b010000)
			if r.randf() < 0.25:
				lit.box(Vector3(w * 0.12, y + uh * 0.5, 0.515), Vector3(w * 0.4, 0.012, 0.01), Color(0.12, 0.42, 0.6), Basis(), 0b010000)
			y += uh
		var m := ArrayMesh.new()
		body.add_to(m, _flat_mat)
		lit.add_to(m, _neon_mat)
		_rack_meshes.append(m)
	return _rack_meshes


# --- Robot Bay ------------------------------------------------------------------

## Industrial: orange light, hazard stripes, a crane overhead, crates and
## charging pods along the wall.
func _bay() -> void:
	floor_tiles(style.floor, style.floor_alt, 3)
	ceiling("Platform_Metal2")
	var t := tiles()
	for i in t:
		var cx := Kit.TILE * (i + 0.5)
		wall("WallPipe_Straight" if rng.randf() < 0.6 else "WallBand_Straight", cx, 0.0)
		wall("TopCables_Straight", cx, 0.0)
		wall("WallWindow_Straight", cx, 5.0)
	# Hazard stripes at the foot of the wall and along the far lane's edge.
	_stripes(Vector3(0, 0.45, BACK + 0.36), room.length, 0.5, true)
	_stripes(Vector3(0, 0.006, -4.95), room.length, 0.22, false)
	strip(Vector3(0, 3.0, BACK + 0.3), Vector3(room.length, 3.0, BACK + 0.3), 0.06, style.accent)
	# The crane: a gantry along the ceiling, a hook over the back.
	flat.box(Vector3(room.length * 0.5, Run.CEILING - 0.45, -5.0), Vector3(room.length, 0.5, 0.35), Color(0.55, 0.38, 0.08))
	flat.box(Vector3(room.length * 0.5, Run.CEILING - 0.45, -0.8), Vector3(room.length, 0.5, 0.35), Color(0.55, 0.38, 0.08))
	var hx := rng.randf_range(6.0, room.length - 6.0)
	flat.box(Vector3(hx, Run.CEILING - 0.6, -2.9), Vector3(1.0, 0.5, 4.6), Color(0.6, 0.42, 0.08))
	var drop := rng.randf_range(1.0, 2.0)
	flat.box(Vector3(hx, Run.CEILING - 0.85 - drop * 0.5, -5.0), Vector3(0.05, drop, 0.05), Color(0.1, 0.1, 0.1))
	flat.box(Vector3(hx, Run.CEILING - 1.0 - drop, -5.0), Vector3(0.45, 0.4, 0.3), Color(0.5, 0.35, 0.06))
	neon.box(Vector3(hx, Run.CEILING - 0.3, -2.9), Vector3(0.25, 0.2, 0.25), Color(1.0, 0.5, 0.05, 0.6))
	lights("Prop_Light_Small", Run.CEILING - 0.02, -2.9, Run.CEILING - 1.4, 1.1, 12.0)
	var x := 1.2
	while x < room.length - 2.0:
		var r := rng.randf()
		if r < 0.3:
			walls.put("ess:Prop_Crate_Tarp_Large" if rng.randf() < 0.5 else "ess:Prop_Crate_Large", Vector3(x + 1.6, 0.0, PROPS_Z - 0.1), 0.0, 0.7)
			if rng.randf() < 0.5:
				walls.put("Prop_Crate4", Vector3(x + 1.0, 1.05 + 0.4, PROPS_Z - 0.1), rng.randf() * 0.4, 0.75)
			x += 3.6
		elif r < 0.5:
			# A charging pod, glowing.
			walls.put("Prop_Pod", Vector3(x + 0.7, 0.0, PROPS_Z - 0.2), 0.0, 0.6)
			neon.box(Vector3(x + 0.7, 2.5, PROPS_Z - 0.2), Vector3(0.6, 0.04, 0.6), style.accent2)
			x += 2.2
		elif r < 0.66:
			for k in 3:
				walls.put("ess:Prop_Barrel2_Closed", Vector3(x + 0.3 + k * 0.6, 0.0, PROPS_Z + rng.randf_range(-0.2, 0.2)), rng.randf() * TAU)
			x += 2.4
		elif r < 0.78:
			walls.put("ess:Prop_GunRack", Vector3(x + 0.6, 0.0, PROPS_Z))
			x += 1.8
		else:
			x += rng.randf_range(1.5, 3.0)
	# Rotating-beacon housings (steady glow) by the bay doors.
	for k in 2:
		var bx := room.length * (0.25 + 0.5 * k)
		neon.box(Vector3(bx, 4.6, BACK + 0.3), Vector3(0.22, 0.22, 0.22), Color(1.0, 0.45, 0.05, 0.85))


## A strip of yellow and black, on the wall or on the floor.
func _stripes(at: Vector3, length: float, h: float, on_wall: bool) -> void:
	var n := int(length / 0.5)
	for i in n:
		var c := Color(0.85, 0.6, 0.05) if i % 2 == 0 else Color(0.04, 0.04, 0.04)
		var p := at + Vector3(i * 0.5 + 0.25, 0, 0)
		if on_wall:
			flat.box(p, Vector3(0.5, h, 0.03), c, Basis(), 1 << 4)
		else:
			flat.box(p, Vector3(0.5, 0.01, h), c, Basis(), 1 << 2)


# --- The Atrium ------------------------------------------------------------------

## Tall glass with the city filling it, gold light, plants.
func _atrium() -> void:
	floor_tiles(style.floor)
	var t := tiles()
	# Glass from the floor up past the ceiling, gold mullions.
	glass.box(Vector3(room.length * 0.5, 6.0, BACK), Vector3(room.length, 12.0, 0.02), Color(0.7, 0.75, 0.8, 0.05))
	var x := 0.0
	while x <= room.length + 0.01:
		flat.box(Vector3(x, 6.0, BACK), Vector3(0.1, 12.0, 0.16), Color(0.55, 0.42, 0.2))
		x += 2.0
	for y in [0.08, 3.0, 6.0, 9.0]:
		flat.box(Vector3(room.length * 0.5, y, BACK), Vector3(room.length, 0.12, 0.18), Color(0.55, 0.42, 0.2))
	strip(Vector3(0, 0.03, BACK + 0.15), Vector3(room.length, 0.03, BACK + 0.15), 0.06, style.accent)
	# The atrium's upper floors: balconies across the top, lit underneath.
	for y in [9.6]:
		flat.box(Vector3(room.length * 0.5, y, -1.5), Vector3(room.length, 0.5, 9.0), Color(0.12, 0.1, 0.09))
		strip(Vector3(0, y - 0.27, 2.9), Vector3(room.length, y - 0.27, 2.9), 0.05, style.accent * 0.9)
	# Pendant lights: gold globes on long cables.
	var n := maxi(1, int(room.length / 6.0))
	for i in n:
		var px := 6.0 * (i + 0.5)
		var pz := -5.0 if i % 2 == 0 else -2.6
		var py := rng.randf_range(5.6, 6.6)
		flat.box(Vector3(px, (py + 9.4) * 0.5, pz), Vector3(0.02, 9.4 - py, 0.02), Color(0.1, 0.1, 0.1))
		neon.box(Vector3(px, py, pz), Vector3(0.36, 0.36, 0.36), Kit.dimmed(style.accent, 1.1))
		if i % 2 == 0 and (detail >= 1 or i % 4 == 0):
			add_light(Vector3(px, py - 0.5, pz + 1.2), style.light if i % 4 == 0 else style.light2, float(style.energy), 10.0)
	# Planters and plants along the glass.
	x = 1.0
	while x < room.length - 1.5:
		var r := rng.randf()
		if r < 0.45:
			_plant(x + 0.6, rng.randf_range(1.2, 2.6))
			x += 2.2
		elif r < 0.6:
			walls.put("ess:Prop_Chair", Vector3(x + 0.5, 0.0, PROPS_Z), 0.2, 0.85)
			walls.put("ess:Prop_Chair", Vector3(x + 1.5, 0.0, PROPS_Z), -0.2, 0.85)
			x += 2.6
		else:
			x += rng.randf_range(1.2, 2.5)
	# The floors below, seen through the glass floor tiles.
	if t > 2:
		for i in range(1, t, 3):
			floors.put("Platform_Window_Wide", Vector3(Kit.TILE * (i + 0.5), 0.0, 0.0))
			neon.box(Vector3(Kit.TILE * (i + 0.5), -6.0, 0.0), Vector3(3.2, 0.05, 3.2), Kit.dimmed(style.accent2, 0.35))


## A planter with a bushy plant (and sometimes a small tree).
func _plant(x: float, h: float) -> void:
	walls.put("city:Prop_Planter_Single", Vector3(x, 0.0, PROPS_Z - 0.15), 0.0, 0.5)
	var base := Vector3(x, 0.3, PROPS_Z - 0.15)
	if h > 2.0:
		flat.box(base + Vector3(0, h * 0.4, 0), Vector3(0.08, h * 0.8, 0.08), Color(0.2, 0.13, 0.08))
		for k in 7:
			var p := base + Vector3(rng.randf_range(-0.5, 0.5), h * rng.randf_range(0.7, 1.0), rng.randf_range(-0.35, 0.35))
			_leaves.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(0.6, 0.95)), p))
	for k in 6:
		var p := base + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.15, 0.55), rng.randf_range(-0.3, 0.3))
		_leaves.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(0.45, 0.7)), p))


# --- Halberd's floor ------------------------------------------------------------

## Red security: dark walls, barriers, cameras, cold white spots.
func _halberd() -> void:
	floor_tiles(style.floor, style.floor_alt, 2)
	ceiling("Platform_DarkPlates")
	var t := tiles()
	for i in t:
		var cx := Kit.TILE * (i + 0.5)
		var r := rng.randf()
		wall("WallAstra_Straight" if r < 0.5 else "WallAstra_Straight_Flat", cx, 0.0)
		wall("TopPlates_Straight", cx, 0.0)
		wall("WallWindow_Straight" if i % 3 == 1 else "WallBand_Straight", cx, 5.0)
	strip(Vector3(0, 0.04, BACK + 0.3), Vector3(room.length, 0.04, BACK + 0.3), 0.06, style.accent)
	strip(Vector3(0, 2.98, BACK + 0.3), Vector3(room.length, 2.98, BACK + 0.3), 0.04, style.accent * 0.7)
	lights("Prop_Light_Small", Run.CEILING - 0.02, -1.6, Run.CEILING - 1.2, 1.0, 10.0)
	var x := 1.0
	while x < room.length - 1.5:
		var r := rng.randf()
		if r < 0.25:
			walls.put("ess:Prop_Locker", Vector3(x + 0.5, 0.0, BACK + 0.4))
			walls.put("ess:Prop_Locker", Vector3(x + 1.5, 0.0, BACK + 0.4))
			x += 2.4
		elif r < 0.42:
			walls.put("ess:Prop_GunRack", Vector3(x + 0.6, 0.0, PROPS_Z))
			x += 1.8
		elif r < 0.6:
			_barrier(x + 1.0)
			x += 2.6
		elif r < 0.7:
			walls.put("Prop_AccessPoint", Vector3(x + 0.4, 0.2, BACK + 0.4), -PI * 0.5)
			x += 1.4
		else:
			x += rng.randf_range(1.2, 2.6)
	# Cameras watching the room from high on the wall.
	var cx := rng.randf_range(3.0, 8.0)
	while cx < room.length - 2.0:
		_camera(cx)
		cx += rng.randf_range(9.0, 16.0)
	# Vertical red light strips between the panels.
	for i in t + 1:
		strip(Vector3(Kit.TILE * i, 0.3, BACK + 0.45), Vector3(Kit.TILE * i, 2.7, BACK + 0.45), 0.05, style.accent * 0.8)


## A red and white security barrier on two posts.
func _barrier(x: float) -> void:
	for k in 2:
		flat.box(Vector3(x - 0.8 + k * 1.6, 0.5, PROPS_Z), Vector3(0.1, 1.0, 0.1), Color(0.15, 0.15, 0.16))
	for i in 8:
		var c := Color(0.75, 0.06, 0.06) if i % 2 == 0 else Color(0.85, 0.85, 0.85)
		flat.box(Vector3(x - 0.8 + i * 0.2 + 0.1, 0.85, PROPS_Z), Vector3(0.2, 0.16, 0.06), c)
	neon.box(Vector3(x - 0.8, 1.04, PROPS_Z), Vector3(0.08, 0.06, 0.08), Color(1.0, 0.1, 0.1, 0.4))


## A security camera on a bracket, its light blinking slowly.
func _camera(x: float) -> void:
	var y := 6.6
	flat.box(Vector3(x, y, BACK + 0.35), Vector3(0.12, 0.12, 0.6), Color(0.1, 0.1, 0.11))
	var b := Basis(Vector3.UP, 0.35) * Basis(Vector3.RIGHT, -0.35)
	flat.box(Vector3(x, y - 0.15, BACK + 0.75), Vector3(0.28, 0.24, 0.55), Color(0.85, 0.85, 0.88), b)
	flat.box(Vector3(x + 0.06, y - 0.25, BACK + 1.02), Vector3(0.18, 0.16, 0.08), Color(0.03, 0.03, 0.04), b)
	neon.box(Vector3(x - 0.1, y - 0.06, BACK + 0.98), Vector3(0.04, 0.04, 0.04), Color(1.0, 0.08, 0.08, rng.randf_range(0.31, 0.95)))
