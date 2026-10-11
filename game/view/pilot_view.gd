class_name PilotView
extends Node3D
## A pilot as you see them: a person in a flight suit with a prototype on
## their back ([PackView]), a shadow on the floor of their lane, whatever
## they're riding, and everything that happens to them: near misses, Burn
## flares, shields, crashes. Moved to match its [Pilot] every tick by
## [RunView], which also hands it the run's events ([method on_event]).
##
## The pilot faces along the run (+x). Thrust leans them into it and the
## flames grow, a lane change banks them, the floor makes them run, a
## landing kicks up dust, and a crash tumbles them, then they slide along
## the floor on their back with the pack coughing smoke.
##
## Ghosts ([method make_ghost]) are see-through, cast no light and throw
## no sparks; the menus place them from recorded samples with [method place].

## Where the pack sits on the spine bone (the mockup's numbers).
const PACK_OFFSET := Vector3(0.0, -0.2, -0.12)
const VEHICLES := {"raptor": "ess:Enemy_Raptor", "shell": "ess:Enemy_QuadShell", "eye": "ess:Enemy_EyeDrone", "gunner": "ess:Enemy_GunDrone"}
## Each vehicle: drawn scale, where the pilot sits on it (height, forward),
## and its clips on the floor, in the air and when its move fires.
const VEHICLE_FIT := {
	"raptor": {"scale": 0.95, "seat": Vector2(1.55, -0.25), "floor": "Run", "air": "Hanging", "move": "Attack"},
	"shell": {"scale": 0.85, "seat": Vector2(1.05, 0.0), "floor": "Run", "air": "Idle", "move": "Charge"},
	"eye": {"scale": 1.55, "seat": Vector2(1.2, 0.0), "floor": "Look", "air": "Idle", "move": "BackFlip"},
	"gunner": {"scale": 1.8, "seat": Vector2(1.15, 0.0), "floor": "Idle", "air": "Idle", "move": "Attack"},
}
## The colours of the Burn levels x1 to x5, for near-miss streaks and flares.
const BURN_COLORS := [Color(1.0, 0.75, 0.3), Color(1.0, 0.6, 0.15), Color(1.0, 0.42, 0.1), Color(1.0, 0.25, 0.35), Color(0.55, 0.65, 1.0)]

static var _shadow_mat: StandardMaterial3D
static var _shield_mat: ShaderMaterial

var pilot: Pilot
var look: Dictionary
var person: Person
var pack: PackView
## Holds the person and the vehicle; turns over for the shell on the ceiling.
var rig: Node3D
var fx: Fx
var detail := 1
var ghost := false

var _shadow: MeshInstance3D
var _vehicle: Node3D
var _vehicle_kind := ""
var _vehicle_anim: AnimationPlayer
var _vehicle_move := 0.0
var _vehicle_in := 1.0
var _lean := 0.0
var _bank := 0.0
var _spin := 0.0
var _flip := 0.0
var _hurt := 0.0
var _shield: MeshInstance3D
var _shield_pop := -1.0
var _land := 0.0
var _kick := 0.0
var _stunned := 0.0
var _celebrate := false
var _crash_t := -1.0
var _scrape := 0.0
var _smoke := 0.0
var _time := 0.0
var _flare := 0.0
var _near_color := Color.WHITE


static func make(p: Pilot, p_detail := 1, p_fx: Fx = null) -> PilotView:
	var v := PilotView.new()
	v.pilot = p
	v.detail = p_detail
	v.fx = p_fx
	v.name = "Pilot%d" % p.id
	v._build()
	return v


## A ghost of a pilot with `look` flying `pack_id`, for Daily Flight and
## Course ghosts. Place it each frame with [method place].
static func make_ghost(p_look: Dictionary, pack_id := "k1") -> PilotView:
	var p := Pilot.new(-1, "Ghost", pack_id)
	p.look = p_look
	var v := PilotView.new()
	v.pilot = p
	v.ghost = true
	v.detail = 0
	v.name = "Ghost"
	v._build()
	return v


## Puts a ghost (or any pilot view without a run) at a recorded moment:
## x along the run, height, lane and whether fly was held.
func place(x: float, y: float, lane: float, flying: bool, dt := 1.0 / 60.0) -> void:
	pilot.lane_to = roundi(lane) if absf(lane - roundf(lane)) > 0.02 else int(lane)
	pilot.x = x
	pilot.y = y
	pilot.lane = lane
	pilot.flying = flying
	pilot.on_floor = y <= 0.01
	sync(null, dt)


func _build() -> void:
	var given: Dictionary = pilot.look
	if given.is_empty():
		given = PilotLooks.random(absi(pilot.id) * 31 + 7) if pilot.bot else PilotLooks.mine()
	look = PilotLooks.resolve(given)
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	person = Person.make("pilot", bool(look.female), int(look.get("seed", absi(pilot.id) * 7919)), look)
	person.rotation.y = PI * 0.5
	rig.add_child(person)
	_add_pack()
	if ghost:
		person.set_ghost()
	else:
		_shadow = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.3, 0.9)
		q.orientation = PlaneMesh.FACE_Y
		_shadow.mesh = q
		_shadow.material_override = _shadow_material()
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shadow)
	person.play("Jump")


func _add_pack() -> void:
	if person.skeleton == null:
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
	pack = PackView.make(pilot.pack, detail, ghost)
	pack.position = skel * rest.origin + PACK_OFFSET
	pack.rotation.y = PI
	holder.add_child(pack)


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


## Matches the pilot this tick. `run` may be null (ghosts placed by menus).
func sync(run: Run, dt: float) -> void:
	_time += dt
	var p := pilot
	position = Vector3(p.x, p.y, RunView.lane_z(p.lane))
	var speed := run.speed_now if run else 10.0
	var riding := p.vehicle != ""
	_sync_vehicle(dt)
	var lean_to := 0.0
	var bank_to := -(float(p.lane_to) - p.lane) * 2.2
	var bob := 0.0
	var heat := clampf((p.burn_level - 1) / 4.0, 0.0, 1.0)
	var thrust := 0.0
	_land = maxf(_land - dt, 0.0)
	_kick = maxf(_kick - dt * 5.0, 0.0)
	_stunned = maxf(_stunned - dt, 0.0)
	_flare = maxf(_flare - dt * 2.5, 0.0)
	match p.state:
		Pilot.State.FLY:
			_crash_t = -1.0
			if riding:
				person.play("Driving")
				lean_to = 0.1
			elif _celebrate:
				person.play("Dance")
				thrust = 0.6
				bob = sin(_time * 5.0) * 0.06
			elif p.stun > 0.0 or _stunned > 0.0:
				if person.current() != "Hit_Knockback":
					person.play("Hit_Knockback", 0.08, 1.0, true)
				lean_to = -0.35
				thrust = 0.2
			elif p.rocket > 0.0:
				# The head start: flat out like a superhero.
				person.play("Swim_Idle", -1.0, 1.4)
				lean_to = 1.25
				thrust = 1.0
				heat = 1.0
			elif p.on_floor and not p.flying:
				if _land > 0.0:
					person.play("Jump_Land", 0.05)
				else:
					person.play("Sprint", 0.12, clampf(speed / 9.5, 0.9, 1.7))
				lean_to = 0.14
			elif p.flying:
				person.play("Jump", 0.15, 0.85)
				lean_to = 0.42 + clampf(p.vy / 30.0, -0.1, 0.15)
				thrust = 1.0
				bob = sin(_time * 7.0) * 0.025
			else:
				# Falling: legs out, leaning back a little as it drops.
				person.play("NinjaJump_Idle", 0.2, 0.8)
				lean_to = 0.18 + clampf(p.vy / 40.0, -0.25, 0.0)
				thrust = 0.0
		Pilot.State.CRASH:
			if _crash_t < 0.0:
				_crash_t = 0.0
			_crash_t += dt
			if p.y > 0.05:
				# Tumbling through the air.
				person.play("Roll", 0.05)
				_spin += dt * 11.0
			else:
				_spin = lerpf(_spin, roundf(_spin / TAU) * TAU, 1.0 - exp(-dt * 14.0))
				if person.current() != "Slide" and person.current() != "Slide_Start":
					person.play("Slide_Start", 0.1)
				elif person.current() == "Slide_Start" and not person.anim.is_playing():
					person.play("Slide", 0.1)
			bank_to = 0.0
		Pilot.State.DONE:
			if person.current() != "LayToIdle":
				person.pose("LayToIdle", 0.0)
			_spin = 0.0
			bank_to = 0.0
		Pilot.State.OUT:
			person.play("Hit_Knockback")
	if person.current() == "Slide_Start" and not person.anim.is_playing():
		person.play("Slide", 0.1)
	if _land > 0.0 and person.current() == "Jump_Land" and not person.anim.is_playing():
		_land = 0.0
	_lean = lerpf(_lean, lean_to - _kick * 0.25, 1.0 - exp(-dt * 7.0))
	_bank = lerpf(_bank, clampf(bank_to, -0.5, 0.5), 1.0 - exp(-dt * 12.0))
	person.rotation = Vector3(_lean + _spin, PI * 0.5, _bank)
	person.position.y = bob + _kick * 0.08
	# The pack.
	if pack:
		pack.visible = not riding
		pack.lit = p.state == Pilot.State.FLY and not riding
		pack.thrust = thrust
		pack.heat = maxf(heat, _flare * 0.8)
		pack.side = float(p.lane_to) - p.lane if absf(float(p.lane_to) - p.lane) > 0.02 else 0.0
		pack.glide = 1.0 if (p.state == Pilot.State.FLY and not p.flying and not p.on_floor and not riding) else 0.0
		pack.step(dt)
	# The shadow stays on the floor of the lane, smaller the higher you are.
	if _shadow:
		var h := maxf(p.y, 0.0)
		_shadow.position = Vector3(0.0, -p.y + 0.02, 0.0)
		var s := clampf(1.0 - h / 9.0, 0.35, 1.0)
		_shadow.scale = Vector3(s, 1.0, s)
	# Hits light the suit up; being untouchable blinks it (softly with
	# Reduce flashing on).
	_hurt = maxf(_hurt - dt * 3.0, 0.0)
	var flash := _hurt
	if p.invuln > 0.0 and p.alive():
		var blink := 0.35 if fmod(_time, 0.2) < 0.1 else 0.0
		flash = maxf(flash, lerpf(blink, 0.18, Fx.steady()))
	if not ghost:
		person.set_instance("hurt", flash)
		person.spin_dizzy(_time)
		if person.is_dizzy() and p.stun <= 0.0 and _stunned <= 0.0:
			person.set_dizzy(false)
	_sync_shield(p, dt)
	_crash_fx(p, dt)


## The pilot's back, where near misses spark and flares burst, in world space.
func pack_point() -> Vector3:
	if pack and pack.is_inside_tree():
		return pack.global_position + Vector3(-0.15, -0.1, 0.0)
	return global_position + Vector3(-0.2, 1.1, 0.0)


func hurt() -> void:
	_hurt = 1.0


## Things that happen to this pilot.
func on_event(e: Dictionary) -> void:
	var p := pilot
	var at := pack_point()
	match str(e.type):
		"near":
			_near(e)
		"burn_lost":
			if pack:
				pack.sputter(0.5)
			_burst("smoke", at, Color(0.5, 0.5, 0.52), 0.5)
		"land":
			_land = 0.35
			var s := clampf(float(e.get("speed", 8.0)) / 14.0, 0.3, 1.0)
			_burst("dust", global_position + Vector3(0, 0.05, 0), Color(0.85, 0.85, 0.9), s, Vector3.RIGHT)
			_burst("dust", global_position + Vector3(0, 0.05, 0), Color(0.85, 0.85, 0.9), s * 0.7, Vector3.LEFT)
		"pulse":
			_kick = 1.0
			if pack:
				pack.kick()
				_burst("ring", at + Vector3(0, -0.45, 0), p.spec.flame, 1.0, Vector3.UP, 0.45)
		"crash":
			hurt()
			_spin = 0.0
			if pack:
				pack.sputter(30.0)
			_burst("sparks", at, Color(1.0, 0.7, 0.3), 1.0, Vector3(-0.5, 1, 0))
			_burst("smoke", at, Color(0.35, 0.35, 0.38), 1.0)
		"stun":
			hurt()
			_stunned = 1.1
			person.set_dizzy(true)
			_burst("sparks", at, Color(1.0, 0.8, 0.4), 0.8, Vector3(-1, 1, 0))
		"shield":
			_shield_pop = 0.0
			_burst("ring", global_position + Vector3(0, 0.85, 0), Color(0.4, 0.8, 1.0), 1.0, Vector3.UP, 1.0)
			_burst("sparkle", global_position + Vector3(0, 0.85, 0), Color(0.5, 0.85, 1.0), 1.0)
		"armour":
			hurt()
			if pack:
				pack.drop_armour()
			_burst("sparks", at, Color(1.0, 0.85, 0.4), 1.0, Vector3(-1, 1, 0))
			_burst("debris", at, Color.WHITE, 0.4, Vector3(-0.3, 1, 0))
		"reboot":
			hurt()
			if pack:
				pack.sputter(0.9)
			_burst("ring", at, Color(0.4, 1.0, 0.7), 1.0, Vector3.UP, 0.8)
			_burst("sparks", at, Color(0.5, 1.0, 0.8), 0.8)
		"vehicle":
			_vehicle_in = 0.0
			_burst("sparkle", global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.3), 1.0)
			_burst("ring", global_position + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.3), 1.0, Vector3.UP, 1.2)
		"vehicle_lost":
			hurt()
			_drop_wreck()
		"jump", "flip", "hop":
			_vehicle_move = 1.0
			if str(e.type) == "flip":
				_burst("sparks", global_position + Vector3(0, 0.1 if not p.upside else 1.4, 0), Color(1.0, 0.8, 0.4), 0.5)
			else:
				_burst("dust", global_position + Vector3(0, 0.05, 0), Color(0.85, 0.85, 0.9), 0.6, Vector3.RIGHT)
		"shot":
			_vehicle_move = 1.0
		"finish", "round_over":
			if str(e.type) == "finish" or int(e.get("winner", -1)) == p.id:
				celebrate()
		"rocket_end":
			_burst("ring", at, p.spec.flame, 1.0, Vector3.RIGHT, 1.2)


## A dance for a finish or a party win.
func celebrate() -> void:
	_celebrate = true
	_burst("sparkle", global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.3), 1.0)


## Near misses: sparks off the pack and streaks behind it, bigger for a
## razor or a thread and hotter the higher the Burn; a flare when the Burn
## goes up a level.
func _near(e: Dictionary) -> void:
	var lvl := clampi(int(e.get("level", pilot.burn_level)), 1, 5)
	var c: Color = BURN_COLORS[lvl - 1]
	var s := 0.45 + 0.13 * lvl
	var at := pack_point()
	match str(e.get("what", "close")):
		"razor":
			_burst("sparks", at, c, minf(s + 0.3, 1.0), Vector3(-1, 0.6, 0))
			_burst("streak", at, c, s, Vector3.LEFT)
		"thread":
			_burst("streak", at + Vector3(0, 0.25, 0), c, s, Vector3.LEFT)
			_burst("streak", at - Vector3(0, 0.25, 0), c, s, Vector3.LEFT)
			_burst("sparks", at, c, s, Vector3(-1, 0.3, 0))
		"skim":
			_burst("streak", at, c.lerp(Color(0.5, 0.9, 1.0), 0.4), s, Vector3.LEFT)
		_:
			_burst("streak", at, c, s * 0.8, Vector3.LEFT)
			_burst("sparks", at, c, s * 0.5, Vector3(-1, 0.5, 0))
	if bool(e.get("up", false)):
		_flare = 1.0
		_burst("ring", at, c, 1.0, Vector3.RIGHT, 1.0 + 0.2 * lvl)
		_burst("sparks", at + Vector3(0, -0.4, 0), c, 1.0, Vector3.DOWN)
		_burst("embers", at, c, 1.0)


func _burst(kind: String, at: Vector3, color: Color, strength := 1.0, dir := Vector3.UP, size := 1.0) -> void:
	if fx and not ghost:
		fx.burst(kind, at, color, strength, dir, size)


## While crashed: sparks where the pack scrapes the floor, and smoke from it.
func _crash_fx(p: Pilot, dt: float) -> void:
	if ghost or fx == null:
		return
	if p.state == Pilot.State.CRASH or p.state == Pilot.State.DONE:
		_smoke -= dt
		if _smoke <= 0.0:
			_smoke = 0.35 if p.state == Pilot.State.CRASH else 0.8
			fx.burst("smoke", pack_point(), Color(0.3, 0.3, 0.33), 0.35 if p.state == Pilot.State.DONE else 0.6)
		if p.state == Pilot.State.CRASH and p.y <= 0.05 and p.slide_speed > 1.0:
			_scrape -= dt
			if _scrape <= 0.0:
				_scrape = 0.08
				fx.burst("sparks", global_position + Vector3(-0.4, 0.15, 0), Color(1.0, 0.7, 0.3), clampf(p.slide_speed / 16.0, 0.3, 1.0), Vector3(-1, 0.8, 0))


func _sync_vehicle(dt: float) -> void:
	var kind := pilot.vehicle
	if kind != _vehicle_kind:
		if _vehicle:
			_vehicle.queue_free()
			_vehicle = null
			_vehicle_anim = null
		_vehicle_kind = kind
		person.position = Vector3.ZERO
		if kind != "":
			var fit: Dictionary = VEHICLE_FIT[kind]
			_vehicle = Kit.model(rig, VEHICLES[kind], Vector3.ZERO, PI * 0.5, float(fit.scale))
			if ghost:
				for mi in _vehicle.find_children("", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = person._ghost_mat
			var players := _vehicle.find_children("", "AnimationPlayer", true, false)
			_vehicle_anim = players[0] if not players.is_empty() else null
	_vehicle_move = maxf(_vehicle_move - dt * 3.0, 0.0)
	_vehicle_in = minf(_vehicle_in + dt * 4.0, 1.0)
	# The shell turns over to walk on the ceiling; the rig turns about the
	# middle of the body, which is where the run keeps it.
	var flip_to := PI if pilot.upside and kind == "shell" else 0.0
	_flip = lerpf(_flip, flip_to, 1.0 - exp(-dt * 16.0))
	if _vehicle == null:
		rig.transform = Transform3D()
		return
	var fit: Dictionary = VEHICLE_FIT[kind]
	var seat: Vector2 = fit.seat
	var mid := 0.8
	rig.transform = Transform3D(Basis(Vector3.RIGHT, _flip), Vector3(0, mid, 0)) * Transform3D(Basis(), Vector3(0, -mid, 0))
	var boing := 1.0 + sin(_vehicle_in * PI) * 0.18 * (1.0 - _vehicle_in)
	_vehicle.scale = Vector3.ONE * float(fit.scale) * boing
	_vehicle.position = Vector3.ZERO
	if kind == "eye" or kind == "gunner":
		# Drones hover: the body sits off the ground.
		_vehicle.position.y = 0.55 + sin(_time * 4.0) * 0.05
	person.position = Vector3(seat.y, seat.x + _vehicle.position.y, 0)
	if _vehicle_anim:
		var clip: String = fit.floor if pilot.on_floor or kind == "shell" else fit.air
		if _vehicle_move > 0.5 and _vehicle_anim.has_animation(str(fit.move)):
			clip = fit.move
		if not _vehicle_anim.has_animation(clip):
			clip = "Idle"
		if _vehicle_anim.current_animation != clip:
			_vehicle_anim.play(clip, 0.1)
		_vehicle_anim.speed_scale = 1.4 if clip == "Run" else 1.0


## The vehicle's lost: it's thrown off with sparks and smoke, and powers down.
func _drop_wreck() -> void:
	if _vehicle == null:
		return
	var wreck := _vehicle
	_vehicle = null
	_vehicle_kind = ""
	var at := wreck.global_transform
	wreck.get_parent().remove_child(wreck)
	var parent := get_parent()
	if parent == null:
		wreck.queue_free()
		return
	parent.add_child(wreck)
	wreck.global_transform = at
	var w := Wreck.new()
	w.name = "Wreck"
	wreck.add_child(w)
	w.start(wreck)
	_burst("sparks", at.origin + Vector3(0, 0.8, 0), Color(1.0, 0.7, 0.3), 1.0)
	_burst("debris", at.origin + Vector3(0, 0.8, 0), Color.WHITE, 0.7)
	_burst("smoke", at.origin + Vector3(0, 0.8, 0), Color(0.3, 0.3, 0.33), 0.8)


func _sync_shield(p: Pilot, dt: float) -> void:
	var on := p.shield > 0 and p.alive()
	if (on or _shield_pop >= 0.0) and _shield == null:
		_shield = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 12
		_shield.mesh = sm
		if _shield_mat == null:
			_shield_mat = ShaderMaterial.new()
			_shield_mat.shader = preload("res://game/view/fx/shield.gdshader")
		_shield.material_override = _shield_mat
		_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shield.position = Vector3(0, 0.85, 0)
		add_child(_shield)
	if _shield == null:
		return
	var pop := 0.0
	if _shield_pop >= 0.0:
		_shield_pop += dt
		pop = _shield_pop / 0.3
		if pop >= 1.0:
			_shield_pop = -1.0
	_shield.visible = on or _shield_pop >= 0.0
	var s := 1.0 + pop * 0.6
	_shield.scale = Vector3(0.85, 1.05, 0.85) * s
	_shield.set_instance_shader_parameter("fade", 1.0 - pop)
	_shield.set_instance_shader_parameter("pop", pop)


## A lost vehicle tumbling away and powering down, then gone.
class Wreck extends Node:
	var body: Node3D
	var anim: AnimationPlayer
	var t := 0.0
	var vel := Vector3(-3.0, 6.0, 0.0)

	func start(b: Node3D) -> void:
		body = b
		var players := b.find_children("", "AnimationPlayer", true, false)
		anim = players[0] if not players.is_empty() else null
		if anim and anim.has_animation("Hit"):
			anim.play("Hit")

	func _process(dt: float) -> void:
		if body == null:
			return
		t += dt
		vel.y -= 22.0 * dt
		body.position += vel * dt
		body.rotation.z += dt * 4.0
		if body.position.y < 0.0:
			body.position.y = 0.0
			vel = Vector3(vel.x * 0.5, absf(vel.y) * 0.3, 0.0)
			if anim and anim.has_animation("TurnOff") and anim.current_animation != "TurnOff":
				anim.play("TurnOff")
		if t > 1.6:
			body.queue_free()
