class_name CityRoofs
extends RefCounted
## Downtown: the rooftops the run crosses outside, one building's roof per
## room. The floor at y = 0 is the roof; behind the far lane are its
## parapet, air conditioners, water tanks, masts and billboards, then
## taller neighbours with lit windows and, across the street, the Downtown
## City MegaKit's buildings hung with shop signs. The street is
## [constant STREET] below, glowing up between them. Built into a
## [RoomView]'s batches like any other room.

## The street below the roofs (Look eases the city's ground to match).
const STREET := -26.0
## Where the buildings across the street stand.
const ACROSS_Z := -30.0
const CORNICES := ["city:Cornice_Brick_Center", "city:Cornice_WornBrick_Center", "city:Cornice_Marble_Center",
	"city:Cornice_WhiteBrick_Center", "city:Cornice_Metal_Center", "city:Cornice_Trim_Center"]
const FACADES := ["city:Metal_Window", "city:Brick_Inset_Window", "city:Marble_Window", "city:WhiteBrick_Window", "city:WornBrick_WindowTriple"]
const SHOP_SIGNS := ["city:Prop_Sign_JadeGarden", "city:Prop_Sign_Carmines", "city:Prop_Sign_Deli", "city:Prop_Sign_Mays",
	"city:Prop_Sign_Bakery", "city:Prop_Sign_Hannigan"]
## Billboards on the roofs: Kestrel Lift's ads, Halberd's, and the city's.
const ADS := [["KESTREL LIFT", "FLY FURTHER"], ["HALBERD SECURITY", "WE COLLECT"], ["NIGHT NOODLES", "OPEN TILL DAWN"],
	["KESTREL K-1", "THE FUTURE IS UP"], ["VOLT COLA", "STAY WIRED"], ["HALBERD", "YOU ARE SAFE"], ["SKYLINE FM", "98.4"]]
const AD_COLORS := [Color(0.2, 0.9, 1.0), Color(1.0, 0.15, 0.2), Color(1.0, 0.35, 0.75), Color(1.0, 0.75, 0.2), Color(0.5, 1.0, 0.4), Color(0.65, 0.4, 1.0)]

static var _tank_body: CylinderMesh
static var _tank_roof: CylinderMesh
static var _tank_mat: StandardMaterial3D
static var _haze_mat: StandardMaterial3D


static func build(v: RoomView) -> void:
	var r := v.room
	var rng := v.rng
	var length := r.length
	var tiles := v.tiles()
	# The roof itself.
	var deck := rng.randf() < 0.3
	for i in tiles:
		var cx := Kit.TILE * (i + 0.5)
		for zc in [0.0, -4.0]:
			if deck:
				v.floors.put("Platform_Metal", Vector3(cx, 0.0, zc))
			else:
				v.floors.put("city:Roof_4x4", Vector3(cx, 0.2, zc))
	# The roof's edge towards the camera, and its face going down.
	var cornice: String = CORNICES[rng.randi() % CORNICES.size()]
	var facade: String = FACADES[rng.randi() % FACADES.size()]
	for i in int(length / 2.0):
		v.walls.put(cornice, Vector3(1.0 + i * 2.0, -1.0, RoomView.FRONT + 0.4))
	for i in tiles:
		for k in 2:
			v.walls.put(facade, Vector3(Kit.TILE * (i + 0.5), -4.0 - k * 3.0, RoomView.FRONT + 0.25))
	# The parapet at the back, with the cornice of the building next door.
	var brick := Color(0.3, 0.16, 0.12).lerp(Color(0.32, 0.3, 0.28), rng.randf())
	v.flat.box(Vector3(length * 0.5, 0.45, RoomView.BACK - 0.1), Vector3(length, 0.9, 0.3), brick)
	v.flat.box(Vector3(length * 0.5, 0.93, RoomView.BACK - 0.1), Vector3(length, 0.08, 0.4), Color(0.45, 0.43, 0.4))
	v.strip(Vector3(0, 0.02, RoomView.BACK + 0.15), Vector3(length, 0.02, RoomView.BACK + 0.15), 0.05, v.style.accent * 0.5)
	# The roof's clutter, behind the far lane.
	var x := 1.2
	while x < length - 1.5:
		var roll := rng.randf()
		if roll < 0.32:
			var n := rng.randi_range(1, 3)
			for k in n:
				v.walls.put("city:Prop_ACUnit", Vector3(x + k * 1.45, 0.0, RoomView.PROPS_Z + 0.1), 0.0, 1.6)
			x += n * 1.45 + 0.8
		elif roll < 0.45:
			_hut(v, x + 1.5)
			x += 4.0
		elif roll < 0.55:
			v.walls.put("Prop_Vent_Big", Vector3(x + 0.8, 0.02, RoomView.PROPS_Z), 0.0)
			x += 2.2
		elif roll < 0.62:
			_mast(v, x + 0.3)
			x += 1.6
		else:
			x += rng.randf_range(1.2, 3.0)
	# Behind the parapet: a water tank, billboards, a taller neighbour.
	if rng.randf() < 0.6:
		_tank(v, rng.randf_range(4.0, length - 4.0), Vector3(0, rng.randf_range(0.0, 2.0), -8.5))
	var bx := rng.randf_range(2.0, 8.0)
	while bx < length - 8.0:
		if rng.randf() < 0.55:
			_billboard(v, bx, rng.randf_range(7.0, 10.0))
			bx += rng.randf_range(16.0, 26.0)
		else:
			_neighbour(v, bx, rng.randf_range(10.0, 16.0))
			bx += rng.randf_range(14.0, 22.0)
	# Across the street: the kit's buildings with shop signs.
	var ax := rng.randf_range(-4.0, 4.0)
	while ax < length:
		var name: String = CityBackdrop.BUILDINGS[rng.randi() % CityBackdrop.BUILDINGS.size()]
		var size := Kit.aabb_size(name)
		v.walls.put(name, Vector3(ax + size.x * 0.5, STREET, ACROSS_Z))
		if rng.randf() < 0.8:
			var shop: String = SHOP_SIGNS[rng.randi() % SHOP_SIGNS.size()]
			v.walls.put(shop, Vector3(ax + size.x * 0.5, STREET + 4.2, ACROSS_Z + 2.0))
		if rng.randf() < 0.5:
			v.walls.put("city:Prop_Sign_JadeGarden_Vertical", Vector3(ax + rng.randf_range(2.0, size.x - 2.0), STREET + rng.randf_range(10.0, 16.0), ACROSS_Z + 2.4), PI * 0.5, 2.0)
		ax += size.x + rng.randf_range(6.0, 14.0)
	# The street's light, rising between the buildings.
	_haze(v, length)
	# Light on the roof: a warm lamp by the door and the signs' colours.
	var nl := 2 if v.detail >= 1 else 1
	for i in nl:
		var lx := length * (0.25 + 0.5 * i)
		v.add_light(Vector3(lx, 3.0, -3.5), v.style.light if i % 2 == 0 else v.style.light2, float(v.style.energy), 13.0)
	if r.tags.has("window_out"):
		v._tower_face(true)


## A stair hut on the roof: a box with a door and a lamp over it.
static func _hut(v: RoomView, x: float) -> void:
	var c := Color(0.22, 0.2, 0.19)
	v.flat.box(Vector3(x, 1.35, RoomView.BACK + 0.2), Vector3(2.6, 2.7, 1.4), c)
	v.flat.box(Vector3(x, 2.75, RoomView.BACK + 0.2), Vector3(2.8, 0.12, 1.6), Color(0.12, 0.12, 0.12))
	v.flat.box(Vector3(x + 0.4, 1.0, RoomView.BACK + 0.91), Vector3(0.9, 2.0, 0.04), Color(0.1, 0.12, 0.14))
	v.neon.box(Vector3(x + 0.4, 2.2, RoomView.BACK + 0.95), Vector3(0.3, 0.1, 0.08), Color(1.0, 0.75, 0.45))


## A thin radio mast with a slow red light on top.
static func _mast(v: RoomView, x: float) -> void:
	var h := v.rng.randf_range(4.0, 7.0)
	v.flat.box(Vector3(x, h * 0.5, RoomView.BACK + 0.1), Vector3(0.08, h, 0.08), Color(0.15, 0.15, 0.16))
	for k in 3:
		v.flat.box(Vector3(x, h * (0.3 + k * 0.25), RoomView.BACK + 0.1), Vector3(0.6 - k * 0.15, 0.03, 0.03), Color(0.15, 0.15, 0.16))
	v.neon.box(Vector3(x, h + 0.06, RoomView.BACK + 0.1), Vector3(0.14, 0.14, 0.14), Color(1.0, 0.08, 0.05, v.rng.randf_range(0.31, 0.9)))


## A wooden water tank on legs, the city's classic.
static func _tank(v: RoomView, x: float, at: Vector3) -> void:
	if _tank_body == null:
		_tank_body = CylinderMesh.new()
		_tank_body.top_radius = 1.5
		_tank_body.bottom_radius = 1.5
		_tank_body.height = 3.2
		_tank_body.radial_segments = 14
		_tank_body.rings = 1
		_tank_roof = CylinderMesh.new()
		_tank_roof.top_radius = 0.05
		_tank_roof.bottom_radius = 1.65
		_tank_roof.height = 1.1
		_tank_roof.radial_segments = 14
		_tank_roof.rings = 1
		_tank_mat = StandardMaterial3D.new()
		_tank_mat.albedo_color = Color(0.33, 0.22, 0.15)
		_tank_mat.roughness = 0.9
	var base := Vector3(x, at.y, at.z)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			v.flat.box(base + Vector3(dx, 1.4, dz), Vector3(0.14, 2.8, 0.14), Color(0.12, 0.12, 0.12))
	v.flat.box(base + Vector3(0, 2.8, 0), Vector3(2.6, 0.12, 2.6), Color(0.12, 0.12, 0.12))
	for part in [[_tank_body, 4.45], [_tank_roof, 6.6]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = _tank_mat
		mi.position = base + Vector3(0, float(part[1]), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(mi)
	for k in 3:
		v.flat.box(base + Vector3(0, 3.3 + k * 1.1, 0), Vector3(3.08, 0.05, 3.08), Color(0.1, 0.1, 0.1))


## A billboard on a steel frame: a lit panel, a neon border and an ad.
static func _billboard(v: RoomView, x: float, w: float) -> void:
	var rng := v.rng
	var z := -9.0
	var y := rng.randf_range(2.5, 4.5)
	var h := w * 0.36
	var ad: Array = ADS[rng.randi() % ADS.size()]
	var c: Color = AD_COLORS[rng.randi() % AD_COLORS.size()]
	var steel := Color(0.1, 0.1, 0.11)
	for k in 3:
		var px := x + w * (0.15 + 0.35 * k)
		v.flat.box(Vector3(px, (y - 2.0) * 0.5, z - 0.3), Vector3(0.2, y + 2.0, 0.2), steel)
	v.flat.box(Vector3(x + w * 0.5, y + h * 0.5, z - 0.12), Vector3(w, h, 0.2), Color(0.03, 0.03, 0.05))
	v.flat.box(Vector3(x + w * 0.5, y - 0.3, z + 0.3), Vector3(w, 0.06, 0.8), steel)
	# The border, and the panel's glow.
	v.strip(Vector3(x, y, z), Vector3(x + w, y, z), 0.08, c)
	v.strip(Vector3(x, y + h, z), Vector3(x + w, y + h, z), 0.08, c)
	v.strip(Vector3(x, y, z), Vector3(x, y + h, z), 0.08, c)
	v.strip(Vector3(x + w, y, z), Vector3(x + w, y + h, z), 0.08, c)
	v.neon.box(Vector3(x + w * 0.5, y + h * 0.5, z - 0.01), Vector3(w - 0.3, h - 0.3, 0.01), c * 0.12)
	v.glow_text(str(ad[0]), Vector3(x + w * 0.5, y + h * 0.62, z + 0.02), int(w * 13.0), c)
	v.glow_text(str(ad[1]), Vector3(x + w * 0.5, y + h * 0.28, z + 0.02), int(w * 6.5), Color(1, 1, 1) * 0.8)
	if v.detail >= 1:
		v.add_light(Vector3(x + w * 0.5, y + h * 0.5, z + 2.5), c, 1.6, 9.0)


## A taller building next door: a wall of lit windows rising behind the
## parapet, with a fire escape and a cornice.
static func _neighbour(v: RoomView, x: float, w: float) -> void:
	var rng := v.rng
	var facade: String = FACADES[rng.randi() % FACADES.size()]
	var floors := rng.randi_range(2, 4)
	var z := -10.0
	var n := int(w / 4.0)
	for i in n:
		for k in floors + 4:
			v.walls.put(facade, Vector3(x + 2.0 + i * 4.0, 1.0 + (k - 4) * 3.0, z))
	var top := 1.0 + floors * 3.0
	var cornice: String = CORNICES[rng.randi() % CORNICES.size()]
	for i in int(n * 2):
		v.walls.put(cornice, Vector3(x + 1.0 + i * 2.0, top, z))
	if rng.randf() < 0.6:
		var fx := x + 2.0 + 4.0 * rng.randi_range(0, maxi(0, n - 2))
		for k in floors:
			v.walls.put("city:Prop_FireEscape_Center", Vector3(fx + 2.4, 1.0 + k * 3.0 - 3.0, z), 0.0)
		v.walls.put("city:Prop_FireEscape_Top", Vector3(fx + 2.4, top - 3.0, z), 0.0)
	# A sign up the corner.
	if rng.randf() < 0.5:
		var c: Color = AD_COLORS[rng.randi() % AD_COLORS.size()]
		var s := v.glow_text(["HOTEL", "BAR", "OPEN", "DINER", "ARCADE"][rng.randi() % 5], Vector3(x + w - 0.6, top - 3.0, z + 0.6), 160, c)
		s.rotation.z = -PI * 0.5
		if v.detail >= 1:
			v.add_light(Vector3(x + w - 0.6, top - 3.0, z + 2.0), c, 1.2, 7.0)


## A soft glow standing between the roofs and the buildings across the
## street: the street lights far below, lighting the air.
static func _haze(v: RoomView, length: float) -> void:
	if _haze_mat == null:
		_haze_mat = StandardMaterial3D.new()
		_haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_haze_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_haze_mat.vertex_color_use_as_albedo = true
		_haze_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_haze_mat.no_depth_test = false
		_haze_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 1)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		_haze_mat.albedo_texture = gt
	var s := Kit.Shapes.new()
	s.panel(Vector3(length * 0.5, STREET * 0.5 + 2.0, -18.0), length + 0.5, -STREET + 4.0, Color(1.0, 0.55, 0.25) * 0.5)
	var mi := s.instance(_haze_mat)
	v.add_child(mi)
