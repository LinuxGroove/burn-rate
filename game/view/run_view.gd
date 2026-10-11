class_name RunView
extends Node3D
## Everything you see of a run: the rooms ahead of it, the hazards, credits,
## crates and staff in them, and the pilots. It only reads the [Run]: rooms
## are built as the run makes them and freed once they're behind, and every
## tick [method sync] moves things to match.
##
## Space: x along the run, y up from the floor, z towards the camera. Lanes
## are 2.2 m apart, the near lane nearest the camera.

const LANE_GAP := 2.2
## Free rooms this far behind the camera's middle.
const FORGET := 34.0
const CREDIT_COLOR := Color(1.0, 0.78, 0.2)
const BIG_COLOR := Color(0.35, 0.95, 1.0)

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
var _rooms_root: Node3D
var _things: Node3D
var _credits: MultiMeshInstance3D
var _bigs: MultiMeshInstance3D
var _spin := 0.0


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
	_credits = _chip_layer(CREDIT_COLOR, 0.32)
	_bigs = _chip_layer(BIG_COLOR, 0.55)
	for p in run.pilots:
		var v := PilotView.make(p)
		pilots[p.id] = v
		add_child(v)
	sync(0.0)
	reset_physics_interpolation()


## A MultiMesh of credit chips: little hexagonal coins that glow.
func _chip_layer(color: Color, radius: float) -> MultiMeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = radius * 0.28
	m.radial_segments = 6
	m.rings = 1
	m.material = Kit.flat(color * 0.6, 0.25, color, 1.6)
	(m.material as StandardMaterial3D).metallic = 0.7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Matches the run's current moment.
func sync(dt: float) -> void:
	_sync_rooms()
	var my := run.pilot(me)
	var my_lane := my.lane if my else 1.0
	_sync_hazards(my_lane)
	_sync_pickups(dt)
	_sync_staff()
	for p in run.pilots:
		var v: PilotView = pilots.get(p.id)
		if v:
			v.sync(run, dt)


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


func _sync_hazards(my_lane: float) -> void:
	var live := {}
	for h in run.hazards:
		if h.dead and h.kind != "gun_drone":
			continue
		live[h.id] = true
		var v: HazardView = hazards.get(h.id)
		if v == null:
			v = HazardView.make(h)
			hazards[h.id] = v
			_things.add_child(v)
			v.sync(run, my_lane)
			v.reset_physics_interpolation()
		else:
			v.sync(run, my_lane)
	for id in hazards.keys():
		if not live.has(id):
			hazards[id].queue_free()
			hazards.erase(id)


func _sync_pickups(dt: float) -> void:
	_spin += dt * 3.0
	var small := []
	var big := []
	var live := {}
	for k in run.pickups:
		if k.taken:
			continue
		if k.kind == "crate":
			live[k.id] = true
			if not crates.has(k.id):
				crates[k.id] = _make_crate(k)
			continue
		(big if k.kind == "big" else small).append(k)
	_fill(_credits.multimesh, small)
	_fill(_bigs.multimesh, big)
	for id in crates.keys():
		if not live.has(id):
			crates[id].queue_free()
			crates.erase(id)


func _fill(mm: MultiMesh, list: Array) -> void:
	if mm.instance_count < list.size():
		mm.instance_count = list.size() + 32
	mm.visible_instance_count = list.size()
	for i in list.size():
		var k: Pickup = list[i]
		var b := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _spin + k.x * 0.4)
		mm.set_instance_transform(i, Transform3D(b, Vector3(k.x, k.y, lane_z(k.lane))))


## A vehicle crate: one of the kit's chests with a glowing marker.
func _make_crate(k: Pickup) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(k.x, k.y - 0.45, lane_z(k.lane))
	_things.add_child(n)
	Kit.model(n, "ess:Prop_Chest", Vector3.ZERO)
	var mark := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.75
	t.outer_radius = 0.85
	mark.mesh = t
	mark.material_override = Kit.flat(Color(1.0, 0.85, 0.2), 0.3, Color(1.0, 0.75, 0.1), 2.5)
	mark.rotation.x = PI * 0.5
	mark.position = Vector3(0, 0.5, 0)
	n.add_child(mark)
	return n


func _sync_staff() -> void:
	var live := {}
	var x := view_x()
	for s in run.staff:
		live[s.id] = true
		var v: Person = staff.get(s.id)
		if v == null:
			v = Person.make(str(s.job), bool(s.female), int(s.seed))
			v.position = Vector3(float(s.x), 0.0, lane_z(float(s.lane)))
			v.rotation.y = -0.35
			_things.add_child(v)
			staff[s.id] = v
		if float(s.knocked) >= 0.0:
			# Knocked flat, then up again.
			var since := run.time - float(s.knocked)
			var down := v.clip_length("Hit_Knockback") * 0.95
			if since < down:
				v.play("Hit_Knockback")
				v.rotation.y = -PI * 0.5
			elif since < down + v.clip_length("LayToIdle") * 0.95:
				v.play("LayToIdle")
			else:
				v.play("Idle")
		else:
			var near := float(s.x) - x < 9.0
			match str(s.mood):
				"cower":
					v.play("Crouch_Idle")
				"phone":
					v.play("Crouch_Idle" if near else "Idle_TalkingPhone")
				"run":
					v.play("Crouch_Idle" if near else "Idle")
				_:
					v.play("Idle_Talking" if not near else "Crouch_Idle")
	for id in staff.keys():
		if not live.has(id):
			staff[id].queue_free()
			staff.erase(id)


## Things that happen: the view's own reactions (the HUD and sounds have
## theirs).
func on_event(e: Dictionary) -> void:
	match str(e.type):
		"crash", "stun", "shield", "armour", "vehicle_lost", "reboot":
			var v: PilotView = pilots.get(int(e.pilot))
			if v:
				v.hurt()
