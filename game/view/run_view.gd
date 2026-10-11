class_name RunView
extends Node3D
## Everything you see of a run: the rooms ahead of it, the hazards, credits,
## crates and staff in them, the pilots and the effects. It only reads the
## [Run]: rooms are built as the run makes them and freed once they're
## behind, and every tick [method sync] moves things to match; the run's
## events come in through [method on_event].
##
## Space: x along the run, y up from the floor, z towards the camera. Lanes
## are 2.2 m apart, the near lane nearest the camera.

const LANE_GAP := 2.2
## Free rooms this far behind the camera's middle.
const FORGET := 34.0
const CREDIT_COLOR := Color(1.0, 0.72, 0.18)
const BIG_COLOR := Color(0.3, 0.95, 1.0)
const CHIP_SHADER := preload("res://game/view/fx/chip.gdshader")
const GLOW_SHADER := preload("res://game/view/fx/glow.gdshader")
## Staff idles, picked by their seed.
const IDLES := ["Idle", "Idle_Talking", "Idle_FoldArms", "Idle_TalkingPhone"]
## Gunner shots: speed (m/s) and how long they fly.
const SHOT_SPEED := 42.0
const SHOT_LIFE := 0.35

var run: Run
## The pilot this screen follows (dims hazards out of their lane).
var me := 1
## 0 low (handhelds' Mobile renderer), 1 full.
var detail := 1
var rooms := {}
var hazards := {}
var pilots := {}
var staff := {}
var crates := {}
var fx: Fx
var _rooms_root: Node3D
var _things: Node3D
var _credits: MultiMeshInstance3D
var _bigs: MultiMeshInstance3D
var _halos: MultiMeshInstance3D
var _spin := 0.0
var _time := 0.0
var _shots: Array = []
var _since_sync := 0.0
## Hazard views playing their end after the run let go of them.
var _ending := {}


static func lane_z(lane: float) -> float:
	return 0.6 - lane * LANE_GAP


func setup(p_run: Run, p_me := 1, p_detail := 1) -> void:
	run = p_run
	me = p_me
	detail = p_detail
	_rooms_root = Node3D.new()
	_rooms_root.name = "Rooms"
	add_child(_rooms_root)
	_things = Node3D.new()
	_things.name = "Things"
	add_child(_things)
	fx = Fx.new()
	fx.name = "Fx"
	fx.setup(detail)
	add_child(fx)
	_credits = _chip_layer(CREDIT_COLOR, 0.3)
	_bigs = _chip_layer(BIG_COLOR, 0.5)
	_halos = _halo_layer()
	for p in run.pilots:
		var v := PilotView.make(p, detail if p.id == me else mini(detail, 0) if run.pilots.size() > 4 else detail, fx)
		pilots[p.id] = v
		add_child(v)
	sync(0.0)
	reset_physics_interpolation()


## A MultiMesh of credit chips: hexagonal coins with a glowing rim.
func _chip_layer(color: Color, radius: float) -> MultiMeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = CHIP_SHADER
	mat.set_shader_parameter("color", color)
	var mesh := chip_mesh(radius)
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A glowing ring behind each big chip, so they stand out from the rest.
func _halo_layer() -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.9)
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("shape", 2)
	mat.set_shader_parameter("billboard", true)
	mat.set_shader_parameter("strength", 1.1)
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", BIG_COLOR)
	add_child(mi)
	return mi


## A credit chip: a hexagonal coin with a bevelled rim and a raised hexagon
## in the middle of each face. COLOR.r marks the rim and COLOR.g the
## emblem, for the chip shader. It lies in the XY plane, facing +Z.
static func chip_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := radius * 0.13
	var inner := radius * 0.78
	var emblem := radius * 0.45
	var corners := []
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		corners.append(Vector2(cos(a), sin(a)))
	for face: float in [1.0, -1.0]:
		var z: float = half * face
		var n := Vector3(0, 0, face)
		for i in 6:
			var c0: Vector2 = corners[i]
			var c1: Vector2 = corners[(i + 1) % 6]
			# Bevel ring from the rim in to the face.
			_quad(st, Vector3(c0.x * radius, c0.y * radius, z * 0.6), Vector3(c1.x * radius, c1.y * radius, z * 0.6),
				Vector3(c1.x * inner, c1.y * inner, z), Vector3(c0.x * inner, c0.y * inner, z), (n + Vector3(c0.x + c1.x, c0.y + c1.y, 0) * 0.35).normalized(), Color(1, 0, 0), face)
			# The face out to the emblem.
			_quad(st, Vector3(c0.x * inner, c0.y * inner, z), Vector3(c1.x * inner, c1.y * inner, z),
				Vector3(c1.x * emblem, c1.y * emblem, z), Vector3(c0.x * emblem, c0.y * emblem, z), n, Color(0, 0, 0), face)
			# The emblem, raised a little.
			var ze := z + half * 0.35 * face
			_tri(st, Vector3(0, 0, ze), Vector3(c0.x * emblem, c0.y * emblem, ze), Vector3(c1.x * emblem, c1.y * emblem, ze), n, Color(0, 1, 0), face)
			_quad(st, Vector3(c0.x * emblem, c0.y * emblem, z), Vector3(c1.x * emblem, c1.y * emblem, z),
				Vector3(c1.x * emblem, c1.y * emblem, ze), Vector3(c0.x * emblem, c0.y * emblem, ze), Vector3(c0.x + c1.x, c0.y + c1.y, 0).normalized(), Color(0, 1, 0), face)
	# The rim's sides.
	for i in 6:
		var c0: Vector2 = corners[i]
		var c1: Vector2 = corners[(i + 1) % 6]
		var n := Vector3(c0.x + c1.x, c0.y + c1.y, 0).normalized()
		_quad(st, Vector3(c0.x * radius, c0.y * radius, -half * 0.6), Vector3(c1.x * radius, c1.y * radius, -half * 0.6),
			Vector3(c1.x * radius, c1.y * radius, half * 0.6), Vector3(c0.x * radius, c0.y * radius, half * 0.6), n, Color(1, 0, 0), 1.0)
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, face: float) -> void:
	var pts := [a, b, c] if face > 0.0 else [a, c, b]
	for p in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, face: float) -> void:
	_tri(st, a, b, c, n, col, face)
	_tri(st, a, c, d, n, col, face)


## Matches the run's current moment.
func sync(dt: float) -> void:
	_time += dt
	_since_sync = 0.0
	fx.set_frozen(false)
	_sync_rooms()
	var my := run.pilot(me)
	var my_lane := my.lane if my else 1.0
	var my_x := my.x if my else run.cam_x
	_sync_hazards(my_lane, my_x, dt)
	_sync_pickups(dt)
	_sync_crates(dt)
	_sync_staff(dt)
	_sync_shots(dt)
	for p in run.pilots:
		var v: PilotView = pilots.get(p.id)
		if v:
			v.sync(run, dt)


func _process(delta: float) -> void:
	# Nothing synced for a moment: the run is paused, so the particles stop too.
	_since_sync += delta
	if fx and _since_sync > 0.12:
		fx.set_frozen(true)


## The x the screen is looking at, for freeing what's behind.
func view_x() -> float:
	if run.mode == "party":
		return run.cam_x
	var p := run.pilot(me)
	return p.x if p else run.distance()


func _sync_rooms() -> void:
	for r in run.course.rooms:
		if not rooms.has(r.index):
			var v := RoomView.make(r, detail)
			rooms[r.index] = v
			_rooms_root.add_child(v)
	var x := view_x()
	for i in rooms.keys():
		var v: RoomView = rooms[i]
		if v.room.end_x() < x - FORGET:
			v.queue_free()
			rooms.erase(i)


func _sync_hazards(my_lane: float, my_x: float, dt: float) -> void:
	var live := {}
	for h in run.hazards:
		if h.dead:
			continue
		live[h.id] = true
		var v: HazardView = hazards.get(h.id)
		if v == null:
			v = HazardView.make(h, detail, fx)
			hazards[h.id] = v
			_things.add_child(v)
			v.sync(run, my_lane, my_x, dt)
			v.reset_physics_interpolation()
		else:
			v.sync(run, my_lane, my_x, dt)
	for id in hazards.keys():
		if not live.has(id):
			var v: HazardView = hazards[id]
			hazards.erase(id)
			v.die(run)
			_ending[id] = v
	var x := view_x()
	for id in _ending.keys():
		var v: HazardView = _ending[id]
		v.sync(run, my_lane, my_x, dt)
		if v.finished() or v.hazard.extent().y < x - FORGET:
			v.queue_free()
			_ending.erase(id)


func _sync_pickups(dt: float) -> void:
	_spin += dt * 2.6
	var small := []
	var big := []
	for k in run.pickups:
		if k.taken or k.kind == "crate":
			continue
		(big if k.kind == "big" else small).append(k)
	_fill(_credits.multimesh, small, 0.0)
	_fill(_bigs.multimesh, big, 0.4)
	var mm := _halos.multimesh
	if mm.instance_count < big.size():
		mm.instance_count = big.size() + 8
	mm.visible_instance_count = big.size()
	for i in big.size():
		var k: Pickup = big[i]
		var s := 1.0 + 0.12 * sin(_time * 5.0 + k.x)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(k.x, k.y + _bob(k), lane_z(k.lane))))
		mm.set_instance_color(i, Color.WHITE)


func _bob(k: Pickup) -> float:
	return sin(_time * 3.0 + k.x * 0.7) * 0.08


func _fill(mm: MultiMesh, list: Array, wobble: float) -> void:
	if mm.instance_count < list.size():
		mm.instance_count = list.size() + 32
	mm.visible_instance_count = list.size()
	for i in list.size():
		var k: Pickup = list[i]
		# They swing to and fro rather than spin right round, so their faces
		# catch the light and never go edge on.
		var b := Basis(Vector3.UP, sin(_spin + k.x * 0.35) * 0.85).rotated(Vector3.RIGHT, sin(_time * 2.0 + k.x) * wobble)
		mm.set_instance_transform(i, Transform3D(b, Vector3(k.x, k.y + _bob(k), lane_z(k.lane))))


## Vehicle crates: the kit's chest with a beacon and the vehicle's sign over
## it. When taken it bursts open and stays behind, open.
func _sync_crates(dt: float) -> void:
	var live := {}
	for k in run.pickups:
		if k.kind != "crate":
			continue
		live[k.id] = true
		if not crates.has(k.id):
			crates[k.id] = Crate.make(k, _things)
		var c: Crate = crates[k.id]
		c.step(dt, _time)
	var x := view_x()
	for id in crates.keys():
		var c: Crate = crates[id]
		if not live.has(id) and not c.opened:
			c.open(fx)
		if c.opened:
			c.step(dt, _time)
		if c.node.position.x < x - FORGET:
			c.node.queue_free()
			crates.erase(id)


func _sync_staff(dt: float) -> void:
	var live := {}
	var x := view_x()
	for s in run.staff:
		live[s.id] = true
		var v: Person = staff.get(s.id)
		if v == null:
			v = Person.make(str(s.job), bool(s.female), int(s.seed))
			v.position = Vector3(float(s.x), 0.0, lane_z(float(s.lane)))
			v.rotation.y = -0.35 + (int(s.seed) % 5) * 0.12
			v.set_meta("idle", IDLES[int(s.seed) % IDLES.size()] if str(s.mood) != "phone" else "Idle_TalkingPhone")
			_things.add_child(v)
			staff[s.id] = v
		v.spin_dizzy(_time)
		if float(s.knocked) >= 0.0:
			_knocked(v, s, run.time - float(s.knocked))
			continue
		var near := float(s.x) - x < 7.5 and float(s.x) - x > -2.0
		match str(s.mood):
			"cower":
				v.play("Crouch_Idle")
			_:
				v.play("Crouch_Idle" if near else str(v.get_meta("idle")), 0.25)
	for id in staff.keys():
		if not live.has(id):
			staff[id].queue_free()
			staff.erase(id)


## Knocked flat by the exhaust, a moment seeing stars, then up again and
## shaking their head. Slapstick: blown a little way along, never hurt.
func _knocked(v: Person, s: Dictionary, since: float) -> void:
	var fall := v.clip_length("Hit_Knockback") * 0.92
	var lie := fall + 1.3
	var up := lie + v.clip_length("LayToIdle") * 0.95
	var home := Vector3(float(s.x), 0.0, lane_z(float(s.lane)))
	if since < fall:
		if v.current() != "Hit_Knockback":
			v.play("Hit_Knockback", 0.05, 1.0, true)
			v.rotation.y = -PI * 0.5
		v.position = home + Vector3(minf(since / fall, 1.0) * 1.1, 0, 0)
	elif since < lie:
		if v.current() != "LayToIdle" or v.anim.is_playing():
			v.pose("LayToIdle", 0.0)
			v.set_dizzy(true)
	elif since < up:
		if v.current() != "LayToIdle" or not v.anim.is_playing():
			v.play("LayToIdle", 0.1, 1.0, true)
		v.set_dizzy(false)
	else:
		v.set_dizzy(false)
		v.play("Idle_No" if since < up + 2.0 else "Idle", 0.25)


## The gunner's shots: glowing bolts flying ahead along the lane.
func _sync_shots(dt: float) -> void:
	var keep := []
	for s in _shots:
		s.t += dt
		var m: MeshInstance3D = s.node
		if s.t > SHOT_LIFE:
			m.queue_free()
			continue
		m.position.x += SHOT_SPEED * dt
		keep.append(s)
	_shots = keep


func _fire_shot(e: Dictionary) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.07
	c.bottom_radius = 0.07
	c.height = 1.4
	c.radial_segments = 8
	c.rings = 1
	m.mesh = c
	m.material_override = HazardView._beam_mat("bolt")
	m.rotation.z = PI * 0.5
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(float(e.x) + 0.6, float(e.y), lane_z(float(e.lane)))
	_things.add_child(m)
	_shots.append({"node": m, "t": 0.0})
	fx.burst("ring", m.position, HazardView.COLORS.bolt, 1.0, Vector3.RIGHT, 0.45)


## Things that happen: the view's own reactions (the HUD and sounds have
## theirs).
func on_event(e: Dictionary) -> void:
	if e.has("pilot"):
		var v: PilotView = pilots.get(int(e.pilot))
		if v:
			v.on_event(e)
	match str(e.type):
		"credit":
			var big := bool(e.get("big", false))
			var at := Vector3(float(e.x), float(e.y), lane_z(float(e.lane)))
			fx.burst("sparkle", at, BIG_COLOR if big else CREDIT_COLOR, 1.0 if big else 0.55, Vector3.UP, 1.6 if big else 1.0)
			if big:
				fx.burst("ring", at, BIG_COLOR, 1.0, Vector3.UP, 1.0)
		"knock":
			var at := Vector3(float(e.x), 0.1, lane_z(float(e.lane)))
			fx.burst("dust", at, Color(0.85, 0.85, 0.9), 0.8, Vector3.RIGHT)
		"shot":
			_fire_shot(e)
		"round_over":
			var w: PilotView = pilots.get(int(e.get("winner", -1)))
			if w:
				w.celebrate()


## A vehicle crate in the run.
class Crate extends RefCounted:
	var node: Node3D
	var chest: Node3D
	var anim: AnimationPlayer
	var beam: MeshInstance3D
	var opened := false
	var t := 0.0
	var vehicle := ""

	static func make(k: Pickup, parent: Node3D) -> Crate:
		var c := Crate.new()
		c.vehicle = k.vehicle
		c.node = Node3D.new()
		c.node.name = "Crate%d" % k.id
		c.node.position = Vector3(k.x, k.y - 0.45, RunView.lane_z(k.lane))
		parent.add_child(c.node)
		c.chest = Kit.model(c.node, "ess:Prop_Chest", Vector3.ZERO, 0.0, 0.9)
		var players := c.chest.find_children("", "AnimationPlayer", true, false)
		c.anim = players[0] if not players.is_empty() else null
		if c.anim and c.anim.has_animation("Idle_Closed"):
			c.anim.play("Idle_Closed")
		# A glowing ring round it and a beam up from it, in Kestrel orange.
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.95
		t.outer_radius = 1.05
		t.rings = 24
		t.ring_segments = 6
		ring.mesh = t
		ring.material_override = Kit.flat(Color(1.0, 0.85, 0.2), 0.3, Color(1.0, 0.7, 0.1), 3.0)
		ring.position = Vector3(0, 0.05, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(ring)
		c.beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.8
		cyl.height = 2.6
		cyl.radial_segments = 16
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		c.beam.mesh = cyl
		var bm := ShaderMaterial.new()
		bm.shader = preload("res://game/view/fx/beam.gdshader")
		bm.set_shader_parameter("color", Color(1.0, 0.65, 0.15))
		bm.set_shader_parameter("strength", 0.6)
		bm.set_shader_parameter("crawl", 0.0)
		c.beam.material_override = bm
		c.beam.position = Vector3(0, 1.3, 0)
		c.beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(c.beam)
		# The vehicle's sign floating above: a little hologram of the robot.
		var holo := Kit.model(c.node, PilotView.VEHICLES.get(k.vehicle, "ess:Enemy_Raptor"), Vector3(0, 1.9, 0), PI * 0.5, 0.32 if k.vehicle in ["raptor", "shell"] else 0.55)
		var hm := ShaderMaterial.new()
		hm.shader = preload("res://game/view/fx/ghost.gdshader")
		hm.set_shader_parameter("color", Color(1.0, 0.7, 0.2))
		hm.set_shader_parameter("strength", 1.4)
		for mi in holo.find_children("", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = hm
		c.node.set_meta("holo", holo)
		return c

	func step(dt: float, time: float) -> void:
		var holo: Node3D = node.get_meta("holo")
		if opened:
			t += dt
			holo.visible = false
			beam.visible = false
			return
		holo.rotation.y = time * 1.5
		holo.position.y = 1.9 + sin(time * 2.5) * 0.08

	func open(fx: Fx) -> void:
		opened = true
		if anim and anim.has_animation("Open"):
			anim.play("Open")
		if fx:
			var at := node.global_position + Vector3(0, 0.8, 0) if node.is_inside_tree() else node.position
			fx.burst("sparkle", at, Color(1.0, 0.8, 0.3), 1.0, Vector3.UP, 1.5)
			fx.burst("ring", at, Color(1.0, 0.75, 0.2), 1.0, Vector3.UP, 1.4)
			fx.burst("sparks", at, Color(1.0, 0.8, 0.4), 0.6)
