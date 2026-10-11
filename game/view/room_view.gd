class_name RoomView
extends Node3D
## One room of the tower as you see it: the kit's floor tiles two deep, the
## back wall, the ceiling, the lights, the lines between the lanes and the
## furniture, built from a [RoomGen] and the look of its zone. The front of
## the building is cut away so you see in.
##
## The room's origin is its start; x runs along the run, y up from the floor
## and z towards the camera, with lanes at [method RunView.lane_z].

## Each zone's look: wall pieces for 0–3 m, the band at 3–5 m, the upper wall
## at 5–8 m ("" leaves it open), floor and ceiling tiles, the light's colour,
## the accent on the lane lines, and furniture along the back wall.
const STYLES := {
	"lab": {
		"wall": ["WallWideBand_Straight", "WallWideBand_Straight_TallBand"], "top": "TopPlates_Straight",
		"upper": "WallWindow_Straight", "floor": "Platform_Simple2", "ceiling": "Platform_Simple",
		"light": Color(0.85, 0.94, 1.0), "accent": Color(0.2, 0.85, 1.0), "energy": 2.2,
		"props": ["ess:Prop_Desk_Medium", "ess:Prop_Computer", "ess:Prop_Shelves_WideTall", "ess:Prop_HologramMap1", "ess:Prop_Locker", "ess:Prop_Desk_L"],
	},
	"servers": {
		"wall": ["WallPipe_Straight", "WallBand_Straight"], "top": "TopCables_Straight",
		"upper": "WallBand_Straight", "floor": "Platform_DarkPlates", "ceiling": "Platform_DarkPlates",
		"light": Color(0.45, 0.65, 1.0), "accent": Color(0.3, 1.0, 0.6), "energy": 1.5,
		"props": ["ess:Prop_Shelves_ThinTall", "ess:Prop_Shelves_WideTall", "ess:Prop_Shelves_ThinTall", "ess:Prop_Locker"],
	},
	"bay": {
		"wall": ["WallBand_Straight", "WallPipe_Straight"], "top": "TopSimple_Straight",
		"upper": "WallWideBand_Straight", "floor": "Platform_3Plates", "ceiling": "Platform_Metal2",
		"light": Color(1.0, 0.82, 0.6), "accent": Color(1.0, 0.6, 0.1), "energy": 1.9,
		"props": ["ess:Prop_Crate_Large", "ess:Prop_Crate_Tarp_Large", "ess:Prop_Barrel2_Closed", "ess:Prop_GunRack", "ess:Prop_Crate"],
	},
	"atrium": {
		"wall": ["WallWindow_Straight"], "top": "TopWindow_Straight",
		"upper": "WallWindow_Straight", "floor": "Platform_Padded", "ceiling": "Platform_Simple",
		"light": Color(1.0, 0.92, 0.8), "accent": Color(1.0, 0.8, 0.35), "energy": 1.6,
		"props": ["ess:Prop_Chair", "ess:Prop_Desk_Small", "ess:Prop_Chair"],
	},
	"downtown": {
		"wall": [], "top": "", "upper": "", "floor": "Platform_Metal", "ceiling": "",
		"light": Color(0.7, 0.75, 1.0), "accent": Color(1.0, 0.3, 0.7), "energy": 0.0,
		"props": [],
	},
	"halberd": {
		"wall": ["WallAstra_Straight_Flat", "WallAstra_Straight"], "top": "TopAstra_Straight",
		"upper": "WallAstra_Straight_Flat", "floor": "Platform_RedAccent", "ceiling": "Platform_DarkPlates",
		"light": Color(1.0, 0.78, 0.75), "accent": Color(1.0, 0.15, 0.2), "energy": 1.7,
		"props": ["ess:Prop_Locker", "ess:Prop_GunRack", "ess:Prop_Shelves_WideShort", "ess:Prop_Locker"],
	},
}
const FLOOR_DEPTH := 8.0
const FRONT := 2.0
const BACK := -6.0
## How far apart the ceiling lights are.
const LIGHT_EVERY := 8.0

static var _line_mats := {}
static var _slab_mat: StandardMaterial3D

var room: RoomGen
var style: Dictionary


static func style_of(zone: String) -> Dictionary:
	return STYLES.get(zone, STYLES["lab"])


static func make(r: RoomGen, detail := 1) -> RoomView:
	var v := RoomView.new()
	v.name = "Room%d" % r.index
	v.room = r
	v.style = style_of(r.zone)
	v.position = Vector3(r.x0, 0, 0)
	v._build(detail)
	return v


func _build(detail: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([room.index, room.zone, "look"])
	var tiles := int(round(room.length / Kit.TILE))
	var outside := room.tags.has("outside")
	for i in tiles:
		var cx := Kit.TILE * (i + 0.5)
		for zc in [0.0, -4.0]:
			Kit.model(self, str(style.floor), Vector3(cx, 0, zc))
		if outside:
			continue
		var walls: Array = style.wall
		if not walls.is_empty():
			var w := str(walls[rng.randi() % walls.size()])
			if room.tags.has("window_out") or room.tags.has("window_in"):
				w = "WallWindow_Straight"
			_wall(w, cx, 0.0)
			if str(style.top) != "":
				_wall(str(style.top), cx, 0.0)
			if str(style.upper) != "":
				_wall(str(style.upper), cx, 5.0)
		if str(style.ceiling) != "":
			for zc in [0.0, -4.0]:
				var c := Kit.model(self, str(style.ceiling), Vector3(cx, Run.CEILING, zc))
				c.rotation.x = PI
	_slab()
	_lane_lines()
	if not outside:
		_lights(detail)
		_furniture(rng, tiles)
	for p in room.props:
		var lane := int(p[2])
		var z := BACK + 0.6 if lane < 0 else RunView.lane_z(lane)
		Kit.model(self, str(p[0]), Vector3(float(p[1]) - room.x0, float(p[3]), z), float(p[4]))
	if room.tags.has("entry") and not outside:
		# A pillar at the door between zones, in front of everything.
		Kit.model(self, "Column_Large_Straight", Vector3(0.0, -2.0, FRONT + 1.2))


## A wall piece along the back: the kit's walls stand on a tile's west edge
## facing east, so they're turned to face the camera.
func _wall(piece: String, cx: float, y: float) -> void:
	Kit.model(self, piece, Vector3(cx, y, BACK + 2.0), -PI * 0.5)


## The dark block under the floor, where the HUD sits.
func _slab() -> void:
	if _slab_mat == null:
		_slab_mat = Kit.flat(Color(0.03, 0.03, 0.045), 0.9)
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(room.length, 6.0, FLOOR_DEPTH + 0.1)
	m.mesh = b
	m.material_override = _slab_mat
	m.position = Vector3(room.length * 0.5, -3.02, (FRONT + BACK) * 0.5 + 0.05)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	# A lit edge along the front of the floor.
	var edge := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(room.length, 0.06, 0.06)
	edge.mesh = eb
	edge.material_override = _line_mat(style.accent, 1.6)
	edge.position = Vector3(room.length * 0.5, -0.03, FRONT + 0.03)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)


## Lines on the floor between the lanes, so the depth reads.
func _lane_lines() -> void:
	if not room.lanes:
		return
	for z in [RunView.lane_z(0.5), RunView.lane_z(1.5)]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(room.length, 0.012, 0.07)
		m.mesh = b
		m.material_override = _line_mat(style.accent, 0.8)
		m.position = Vector3(room.length * 0.5, 0.008, z)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)


static func _line_mat(c: Color, energy: float) -> StandardMaterial3D:
	var key := "%s/%s" % [c.to_html(), energy]
	if not _line_mats.has(key):
		_line_mats[key] = Kit.flat(c * 0.4, 0.5, c, energy)
	return _line_mats[key]


func _lights(detail: int) -> void:
	var n := int(room.length / LIGHT_EVERY)
	for i in n:
		var x := LIGHT_EVERY * (i + 0.5)
		Kit.model(self, "Prop_Light_Wide", Vector3(x, Run.CEILING - 0.02, -1.6))
		if detail >= 1 or i % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = style.light
			l.light_energy = float(style.energy)
			l.omni_range = 11.0
			l.omni_attenuation = 1.2
			l.shadow_enabled = false
			l.position = Vector3(x, Run.CEILING - 1.0, -1.2)
			add_child(l)


## Desks, shelves and screens along the back wall, out of every lane.
func _furniture(rng: RandomNumberGenerator, tiles: int) -> void:
	var props: Array = style.props
	if props.is_empty() or room.tags.has("finish"):
		return
	var x := 1.5
	while x < room.length - 1.5:
		if rng.randf() < 0.7:
			var name := str(props[rng.randi() % props.size()])
			Kit.model(self, name, Vector3(x, 0, BACK + 0.75), 0.0)
		x += rng.randf_range(2.6, 4.2)
