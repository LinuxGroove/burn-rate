class_name Kit
extends RefCounted
## The tower's pieces: Quaternius' Modular Sci-Fi MegaKit and Sci-Fi
## Essentials Kit, the Downtown City MegaKit and the game's own models, found
## by name, plus helpers for placing models in code. Rooms are built from
## these by [RoomView]; nothing here has collision, since the run is
## worked out by [Run], not by physics.
##
## Names are the kits' own file names without the extension ("Platform_Simple",
## "WallBand_Straight"). The Essentials Kit's take "ess:" ("ess:Prop_Desk_Medium")
## and the city kit's "city:" ("city:Brick_Plain_3"), since some names are in
## more than one kit.

const MEGAKIT := "res://addons/quaternius/modularscifimegakit"
const ESSENTIALS := "res://addons/quaternius/Sci-FiEssentials"
const CITY := "res://addons/quaternius/downtowncity"
const PEOPLE := "res://assets/people"
const MODELS := "res://assets/models"

## The kit's grid: 4 m tiles. A room is two tiles deep and 8 m tall (a
## 3 m wall, another 3 m wall and a 2 m top piece).
const TILE := 4.0
const HEIGHT := 8.0

static var _paths := {}
static var _scenes := {}
static var _materials := {}


## The file for a model name, or "" if there's none.
static func path(name: String) -> String:
	if _paths.is_empty():
		_index(MEGAKIT, "")
		_index(ESSENTIALS, "ess:")
		_index(CITY, "city:")
		_index(PEOPLE, "")
		_index(MODELS, "")
	return _paths.get(name, "")


static func _index(dir: String, prefix: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		# Exported games list "X.gltf.import" in place of "X.gltf".
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.ends_with(".gltf") or file.ends_with(".glb"):
			var key := prefix + file.get_basename()
			if not _paths.has(key):
				_paths[key] = dir.path_join(file)
	for sub in d.get_directories():
		_index(dir.path_join(sub), prefix)


static func has(name: String) -> bool:
	return path(name) != ""


static func scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var p := path(name)
		if p == "":
			push_error("Kit: no model called %s" % name)
			_scenes[name] = null
		else:
			_scenes[name] = load(p)
	return _scenes[name]


static var _glass_meshes := {}
static var _glass: StandardMaterial3D


## The kit's window glass is tinted nearly opaque; the tower's is clear,
## so the city shows through. Returns the mesh with its glass swapped (the
## same mesh if it has none).
static func clear_glass(mesh: Mesh) -> Mesh:
	if not mesh is ArrayMesh:
		return mesh
	if _glass_meshes.has(mesh):
		return _glass_meshes[mesh]
	var out := mesh
	for s in mesh.get_surface_count():
		if (mesh as ArrayMesh).surface_get_name(s) == "M_Glass":
			if out == mesh:
				out = mesh.duplicate()
			if _glass == null:
				_glass = StandardMaterial3D.new()
				_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_glass.albedo_color = Color(0.55, 0.72, 0.82, 0.1)
				_glass.roughness = 0.04
				_glass.metallic_specular = 0.9
				_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			out.surface_set_material(s, _glass)
	_glass_meshes[mesh] = out
	return out


## Places a model with no collision. `yaw` is in radians.
static func model(parent: Node, name: String, pos: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	var ps := scene(name)
	if ps == null:
		var n := Node3D.new()
		n.position = pos
		parent.add_child(n)
		return n
	var n: Node3D = ps.instantiate()
	_strip_collision(n)
	n.position = pos
	n.rotation.y = yaw
	if scale != 1.0:
		n.scale = Vector3.ONE * scale
	parent.add_child(n)
	return n


## Some kits' models come with collision shapes as static bodies; the run
## doesn't use physics, so those are dropped.
static func _strip_collision(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionObject3D:
			# Keep what's visible under it.
			for m in c.get_children():
				if m is VisualInstance3D or (m is Node3D and m.get_child_count() > 0 and not m is CollisionShape3D):
					c.remove_child(m)
					n.add_child(m)
					m.transform = c.transform * m.transform
			n.remove_child(c)
			c.free()
		else:
			_strip_collision(c)


## The bounds of a node's meshes, in the node's parent's space.
static func aabb_of(n: Node3D) -> AABB:
	var acc := [null]
	_merge_aabb(n, n.transform, acc)
	return acc[0] if acc[0] != null else AABB()


static func _merge_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		var b: AABB = xf * n.mesh.get_aabb()
		acc[0] = b if acc[0] == null else acc[0].merge(b)
	for c in n.get_children():
		if c is Node3D:
			_merge_aabb(c, xf * c.transform, acc)


## A plain coloured material, cached.
static func flat(color: Color, roughness := 0.8, emission := Color.BLACK, energy := 1.0) -> StandardMaterial3D:
	var key := "%s/%s/%s/%s" % [color.to_html(), roughness, emission.to_html(), energy]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		if emission != Color.BLACK:
			m.emission_enabled = true
			m.emission = emission
			m.emission_energy_multiplier = energy
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[key] = m
	return _materials[key]


static var _parts := {}
static var _swapped := {}


## A model's meshes and where they sit in it, cached: [[Mesh, Transform3D], ...].
## Cheaper than [method model] when only the look is needed (see [Batch]).
static func parts(name: String) -> Array:
	if not _parts.has(name):
		var ps := scene(name)
		var out := []
		if ps != null:
			var n: Node3D = ps.instantiate()
			_strip_collision(n)
			for e in meshes_of(n):
				var mi: MeshInstance3D = e[0]
				var mesh: Mesh = mi.mesh
				# Surface overrides (rare in the kits) become the mesh's own.
				for s in mesh.get_surface_count():
					if mi.get_surface_override_material(s) != null:
						mesh = mesh.duplicate()
						for t in mesh.get_surface_count():
							var o := mi.get_surface_override_material(t)
							if o:
								mesh.surface_set_material(t, o)
						break
				out.append([mesh, e[1]])
			n.free()
		_parts[name] = out
	return _parts[name]


static var _sizes := {}


## The size of a model's bounds (from [method parts]), cached.
static func aabb_size(name: String) -> Vector3:
	if not _sizes.has(name):
		var box := AABB()
		var first := true
		for p in parts(name):
			var b: AABB = p[1] * (p[0] as Mesh).get_aabb()
			box = b if first else box.merge(b)
			first = false
		_sizes[name] = box.size
	return _sizes[name]


## A material's name: the kit's file name ("MI_Trim_01") or its own name.
static func material_name(m: Material) -> String:
	if m == null:
		return ""
	if m.resource_path != "":
		return m.resource_path.get_file().get_basename()
	return m.resource_name


## The mesh with the materials named in `swap` (name -> Material) swapped,
## cached under `key` (one key per set of swaps, such as a zone's look).
static func swapped(mesh: Mesh, key: String, swap: Dictionary) -> Mesh:
	if swap.is_empty() or not mesh is ArrayMesh:
		return mesh
	var k := [mesh.get_instance_id(), key]
	if _swapped.has(k):
		return _swapped[k]
	var out := mesh
	for s in mesh.get_surface_count():
		var n := material_name(mesh.surface_get_material(s))
		if swap.has(n):
			if out == mesh:
				out = mesh.duplicate()
			out.surface_set_material(s, swap[n])
	_swapped[k] = out
	return out


## `c` scaled by `k` with its alpha left at 1. Neon reads a vertex colour's
## alpha below 1 as "blink" (see city_neon.gdshader), and `c * k` would
## scale the alpha too.
static func dimmed(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


## Box sides in the order Shapes.box masks them: +x, -x, +y, -y, +z, -z.
const DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]

## Collects kit pieces and builds each distinct mesh as one MultiMesh, so a
## room's dozens of tiles and props are a handful of draw calls and no
## scene instancing:
##   var b := Kit.Batch.new()
##   b.add("Platform_Simple", Transform3D(Basis(), Vector3(2, 0, 0)))
##   b.build(room)
class Batch:
	## Material swaps applied to every piece (see [method Kit.swapped]).
	var swap := {}
	var swap_key := ""
	var _xf := {}
	var _meshes := {}

	func add(name: String, xf: Transform3D) -> void:
		for p in Kit.parts(name):
			var m: Mesh = p[0]
			if not swap.is_empty():
				m = Kit.swapped(m, swap_key, swap)
			add_mesh(m, xf * p[1])

	## A piece at a spot, turned by `yaw` (radians), scaled evenly.
	func put(name: String, pos: Vector3, yaw := 0.0, scale := 1.0) -> void:
		add(name, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos))

	func add_mesh(m: Mesh, xf: Transform3D) -> void:
		var id := m.get_instance_id()
		if not _xf.has(id):
			_xf[id] = []
			_meshes[id] = m
		_xf[id].append(xf)

	func is_empty() -> bool:
		return _xf.is_empty()

	## Adds the batched pieces under `parent`; returns how many draws it made.
	func build(parent: Node3D, shadows := false) -> int:
		var n := 0
		for id in _xf:
			var list: Array = _xf[id]
			var mesh: Mesh = _meshes[id]
			var gi: GeometryInstance3D
			if list.size() == 1:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.transform = list[0]
				gi = mi
			else:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = list.size()
				for i in list.size():
					mm.set_instance_transform(i, list[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				gi = mmi
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(gi)
			n += 1
		_xf.clear()
		_meshes.clear()
		return n


## Boxes and flat quads in one mesh with vertex colours, for the many small
## glowing strips, panels and blocks the tower and the city are dressed in.
##   var s := Kit.Shapes.new()
##   s.box(Vector3(0, 1, 0), Vector3(4, 0.05, 0.05), Color.CYAN)
##   room.add_child(s.instance(material))
class Shapes:
	var _v := PackedVector3Array()
	var _nrm := PackedVector3Array()
	var _uv := PackedVector2Array()
	var _col := PackedColorArray()
	var _idx := PackedInt32Array()

	## A box centred at `c` with sides `size`, turned by `basis`; `faces` is
	## a mask of the sides to draw (+x, -x, +y, -y, +z, -z). UVs run in metres.
	func box(c: Vector3, size: Vector3, color: Color, basis := Basis(), faces := 63) -> void:
		var h := size * 0.5
		for f in 6:
			if not faces & (1 << f):
				continue
			var nrm: Vector3 = Kit.DIRS[f]
			var u: Vector3 = Vector3.UP if absf(nrm.y) < 0.5 else Vector3.BACK
			var v := nrm.cross(u)
			var du := absf(u.dot(h))
			var dv := absf(v.dot(h))
			var o := nrm * absf(nrm.dot(h))
			_quad(c, basis, o, v * dv, u * du, basis * nrm, color, Vector2(dv * 2.0, du * 2.0))

	## A flat panel facing `normal`, `w` wide and `h` tall (UV 0–1 across it).
	func panel(c: Vector3, w: float, h: float, color: Color, basis := Basis()) -> void:
		_quad(c, basis, Vector3.ZERO, Vector3.RIGHT * w * 0.5, Vector3.UP * h * 0.5, basis * Vector3.BACK, color, Vector2(1, 1))

	func _quad(c: Vector3, basis: Basis, o: Vector3, a: Vector3, b: Vector3, nrm: Vector3, color: Color, ext: Vector2) -> void:
		var base := _v.size()
		_v.append(c + basis * (o - a - b))
		_v.append(c + basis * (o + a - b))
		_v.append(c + basis * (o + a + b))
		_v.append(c + basis * (o - a + b))
		_uv.append(Vector2(0, ext.y))
		_uv.append(Vector2(ext.x, ext.y))
		_uv.append(Vector2(ext.x, 0))
		_uv.append(Vector2(0, 0))
		for i in 4:
			_nrm.append(nrm)
			_col.append(color)
		# Godot's front faces wind clockwise seen from the front.
		if (a.cross(b)).dot(basis.inverse() * nrm) > 0.0:
			_idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func is_empty() -> bool:
		return _v.is_empty()

	## Adds what's been drawn to `mesh` as one more surface.
	func add_to(mesh: ArrayMesh, material: Material = null) -> void:
		if is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v
		arrays[Mesh.ARRAY_NORMAL] = _nrm
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		arrays[Mesh.ARRAY_COLOR] = _col
		arrays[Mesh.ARRAY_INDEX] = _idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if material:
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		add_to(m)
		return m

	func instance(material: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh()
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi


## Every mesh under `root` in one list of [mesh, transform relative to root].
static func meshes_of(root: Node3D) -> Array:
	var out := []
	_collect(root, Transform3D(), out)
	return out


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and n.mesh and n.visible:
		out.append([n, xf])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * c.transform, out)
