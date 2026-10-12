class_name RunAudio
extends Node3D
## The run's sound: the pilot's burners, near misses, hazards, credits,
## crashes and the music that rises with the Burn. Reads the run each tick
## and reacts to its events.
##
## Everything is placed where it is in the run, and the camera is the
## listener, so sounds pan with their place on screen; they never fade with
## distance or bend in pitch as they move. Hazards in your lane are louder
## than the others, and things off the edge of the screen fade out. In
## party races the pilots on this device are loud and everyone else is
## quieter. One-shot sounds go through [SfxVoices], which keeps to a budget.

## Each prototype's burner: its loop, its level (dB) at full thrust, its
## level with fly let go, and its pitch let go and held.
const BURNERS := {
	"k1": {"loop": "burner_k1_loop", "db": -5.0, "idle": -21.0, "pitch": [0.86, 1.0]},
	"k2": {"loop": "burner_k2_loop", "db": -5.0, "idle": -23.0, "pitch": [0.82, 1.05]},
	"k3": {"loop": "burner_k3_loop", "db": -7.0, "idle": -19.0, "pitch": [0.9, 1.0]},
	"k4": {"loop": "burner_k4_loop", "db": -9.0, "idle": -16.0, "pitch": [0.95, 1.0]},
	"k5": {"loop": "burner_k5_loop", "db": -5.0, "idle": -21.0, "pitch": [0.86, 1.02]},
	"k6": {"loop": "burner_k6_loop", "db": -4.0, "idle": -21.0, "pitch": [0.85, 0.98]},
}
## Pilots flown by bots or on other devices are this much quieter.
const OTHERS_DB := -12.0
## Vehicles' motor hum: pitch and level.
const VEHICLES := {"raptor": [0.8, -9.0], "shell": [1.0, -10.0], "eye": [1.3, -11.0], "gunner": [1.12, -10.0]}
## Credits picked up in a row step up this scale (semitones).
const LADDER := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
## Credits closer together than this are in a row (seconds).
const LADDER_GAP := 0.5
## Near misses rise in pitch with the Burn: this much per level.
const NEAR_PITCH := 0.07
const ZONE_AMB := {
	"lab": "amb_lab", "servers": "amb_servers", "bay": "amb_bay",
	"atrium": "amb_atrium", "downtown": "amb_downtown", "halberd": "amb_halberd",
}
const AMB_DB := -22.0
## Loops kept for the loudest hazards of each kind.
const HUM_LOOPS := 3
const WHIR_LOOPS := 2
const ROLL_LOOPS := 1
## Sounds are full within this many metres of the screen's middle and gone
## by FADE_OUT.
const SCREEN_HALF := 11.0
const FADE_OUT := 24.0
## Each lane away from yours is this much quieter.
const LANE_DB := -4.5
## Below this a loop counts as silent and stops.
const SILENT := -60.0
## Priorities in the voice budget.
enum { LOW = 1, HAZARD = 2, REWARD = 3, BIG = 4, CRASH = 5 }

## Every sound effect this plays, for tests.
const SOUNDS := [
	"burner_k1_loop", "burner_k2_loop", "burner_k3_loop", "burner_k4_loop", "burner_k5_loop", "burner_k6_loop",
	"burner_k4_kick", "burner_ignite", "burner_sputter", "thruster_hiss", "lane_swish", "rocket_loop", "rocket_end",
	"land_thump", "footstep_1", "footstep_2", "footstep_3", "footstep_4", "crash_hit", "crash_slide_loop",
	"shield_pop", "armour_clank", "reboot", "stun", "out",
	"zapper_hum_loop", "zapper_crackle_1", "zapper_crackle_2", "zapper_crackle_3", "laser_charge", "laser_fire",
	"seeker_beep", "seeker_lock", "seeker_launch", "seeker_whoosh", "seeker_fizzle",
	"shutter_klaxon", "shutter_slide", "shutter_slam", "drone_whir_loop", "drone_charge", "drone_dash",
	"gun_charge", "gun_bolt", "walker_stomp", "orb_roll_loop", "robot_smash",
	"staff_oof_m1", "staff_oof_m2", "staff_oof_f1", "staff_oof_f2", "staff_thud",
	"near_whoosh", "near_razor", "near_thread", "burn_up", "burn_max", "burn_lost", "credit", "credit_big",
	"crate_open", "vehicle_on", "vehicle_hum_loop", "raptor_step", "raptor_jump", "shell_flip", "eye_hop",
	"gunner_shot", "vehicle_lost",
	"amb_lab", "amb_servers", "amb_bay", "amb_atrium", "amb_downtown", "amb_halberd",
]


## One pilot's continuous sounds.
class PilotSound:
	var burner: AudioStreamPlayer3D
	## The rocket, a vehicle's motor or the crash slide.
	var aux: AudioStreamPlayer3D
	var thrust := 0.0
	var loud := true
	var step_t := 0.0
	var off_for := 1.0
	var was_flying := false


var run: Run
var me := 1
## Pilot ids flown on this device: their sounds are loud.
var locals := {}
var voices: SfxVoices
var _pilots := {}
## Hazard id -> what was heard of it: {"state", "bolts", "beep", "whoosh", "stomp"}.
var _heard := {}
var _hum: Array[AudioStreamPlayer3D] = []
var _hum_ids: Array[int] = []
var _whir: Array[AudioStreamPlayer3D] = []
var _whir_ids: Array[int] = []
var _roll: Array[AudioStreamPlayer3D] = []
var _roll_ids: Array[int] = []
var _amb: Array[AudioStreamPlayer] = []
var _amb_zone := ""
var _amb_on := 0
var _ladder := 0
var _ladder_t := -10.0
var _over := false
## Crashed and sliding: the music is muffled until the run's over.
var _crashed := false
var _paused := false
var _muffled := false
var _rng := RandomNumberGenerator.new()
var _cx := 0.0
var _lane := 1.0


func setup(p_run: Run, p_me: int) -> void:
	run = p_run
	me = p_me
	_rng.seed = hash([run.seed, "audio"])
	locals = {me: true}
	var scene := get_parent()
	if scene and "seats" in scene:
		for id in scene.seats:
			locals[int(id)] = true
	voices = SfxVoices.new()
	voices.name = "Voices"
	add_child(voices)
	for i in HUM_LOOPS:
		_hum.append(_loop_player())
		_hum_ids.append(0)
	for i in WHIR_LOOPS:
		_whir.append(_loop_player())
		_whir_ids.append(0)
	for i in ROLL_LOOPS:
		_roll.append(_loop_player())
		_roll_ids.append(0)
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX"
		a.volume_db = -80.0
		add_child(a)
		_amb.append(a)
	for p in run.pilots:
		var ps := PilotSound.new()
		ps.loud = locals.has(p.id)
		ps.burner = _loop_player()
		ps.aux = _loop_player()
		_pilots[p.id] = ps
	_look()
	_set_zone(run.zone())
	GameAudio.music("party" if run.mode == "party" else "run")
	if run.mode == "party":
		GameAudio.party_level(1)
	else:
		GameAudio.intensity(1)
	GameAudio.muffle(false, 0.3)


func _exit_tree() -> void:
	if _muffled:
		GameAudio.muffle(false, 0.4)


func _process(_delta: float) -> void:
	var scene := get_parent()
	var paused := scene != null and "paused" in scene and bool(scene.paused)
	if paused == _paused:
		return
	_paused = paused
	voices.set_paused(paused)
	for c in get_children():
		if c is AudioStreamPlayer3D or c is AudioStreamPlayer:
			c.stream_paused = paused
	_muffle(paused or _crashed)


## Once a tick, after the run steps.
func sync(dt: float) -> void:
	if run == null:
		return
	_look()
	voices.tick(dt)
	for p in run.pilots:
		_sync_pilot(p, _pilots.get(p.id), dt)
	_sync_hazards(dt)
	_sync_amb(dt)
	_sync_music()


# --- The pilots -----------------------------------------------------------

func _sync_pilot(p: Pilot, ps: PilotSound, dt: float) -> void:
	if ps == null:
		return
	var pos := pilot_pos(p)
	var trim := 0.0 if ps.loud else OTHERS_DB
	var spec: Dictionary = BURNERS.get(p.pack, BURNERS["k1"])
	var held := p.flying and p.state == Pilot.State.FLY
	ps.thrust = move_toward(ps.thrust, 1.0 if held else 0.0, dt / (0.05 if held else 0.14))
	var burner_db := SILENT - 20.0
	var aux_name := ""
	var aux_db := SILENT - 20.0
	var aux_pitch := 1.0
	if p.state == Pilot.State.FLY:
		if p.rocket > 0.0:
			aux_name = "rocket_loop"
			aux_db = -3.0 + trim
		elif p.vehicle != "":
			var v: Array = VEHICLES.get(p.vehicle, [1.0, -10.0])
			aux_name = "vehicle_hum_loop"
			aux_pitch = float(v[0]) * (1.0 + 0.08 * ps.thrust)
			aux_db = float(v[1]) + 3.0 * ps.thrust + trim
			_steps(p, ps, dt, pos, trim, "raptor_step" if p.vehicle == "raptor" else "")
		else:
			var idle := float(spec.idle)
			if p.on_floor and not held:
				idle -= 6.0
			burner_db = lerpf(idle, float(spec.db), ps.thrust) + trim
			_steps(p, ps, dt, pos, trim, "footstep")
			if held and not ps.was_flying and ps.off_for > 0.3 and ps.loud and p.pack != "k4":
				voices.play("burner_ignite", pos, -12.0, 1.0 + _rng.randf_range(-0.05, 0.05), LOW)
	elif p.state == Pilot.State.CRASH and p.y <= 0.05 and p.slide_speed > 0.3:
		aux_name = "crash_slide_loop"
		aux_db = linear_to_db(clampf(p.slide_speed / 14.0, 0.05, 1.0)) - 6.0 + trim
		aux_pitch = 0.8 + p.slide_speed / 40.0
	ps.off_for = 0.0 if held else ps.off_for + dt
	ps.was_flying = held
	var pitch: Array = spec.pitch
	var climb := clampf(p.vy / maxf(float(p.spec.rise), 1.0), -1.0, 1.0)
	var bp := lerpf(float(pitch[0]), float(pitch[1]), ps.thrust) + 0.03 * climb
	_drive(ps.burner, str(spec.loop), pos, burner_db, bp, dt, 14.0)
	_drive(ps.aux, aux_name, pos, aux_db, aux_pitch, dt, 6.0)


## Footsteps (or the Raptor's feet) while running along the floor.
func _steps(p: Pilot, ps: PilotSound, dt: float, pos: Vector3, trim: float, kind: String) -> void:
	if kind == "" or not p.on_floor or p.flying or p.vehicle not in ["", "raptor"]:
		ps.step_t = 0.0
		return
	ps.step_t -= dt
	if ps.step_t > 0.0:
		return
	var speed := maxf(run.speed_now, 4.0)
	if kind == "raptor_step":
		ps.step_t = clampf(5.0 / speed, 0.26, 0.45)
		voices.play("raptor_step", pos, -9.0 + trim, _rng.randf_range(0.92, 1.05), LOW)
	else:
		ps.step_t = clampf(3.0 / speed, 0.16, 0.3)
		voices.play("footstep_%d" % _rng.randi_range(1, 4), pos, -11.0 + trim, _rng.randf_range(0.94, 1.08), LOW)


static func pilot_pos(p: Pilot) -> Vector3:
	return Vector3(p.x, p.y + 1.0, RunView.lane_z(p.lane))


# --- Hazards --------------------------------------------------------------

func _sync_hazards(dt: float) -> void:
	var cx := cam_x()
	var hums := []
	var whirs := []
	var rolls := []
	var seen := {}
	for h in run.hazards:
		var ext: Vector2 = h.extent()
		if ext.y < cx - FADE_OUT - 10.0 or ext.x > cx + FADE_OUT + 30.0:
			continue
		seen[h.id] = true
		var rec: Dictionary = _heard.get(h.id, {})
		if rec.is_empty():
			rec = {"state": "", "bolts": 0, "beep": 0.0, "whoosh": false, "stomp": _rng.randf_range(0.0, 0.5)}
			_heard[h.id] = rec
		var was := str(rec.state)
		var now := str(h.state)
		match h.kind:
			"zapper":
				_zapper(h, dt, hums)
			"laser":
				_laser(h, was, now)
			"seeker":
				_seeker(h, was, now, rec, dt)
			"shutter":
				_shutter(h, was, now)
			"eye_drone":
				_eye(h, was, now, whirs)
			"gun_drone":
				_gun(h, was, now, rec, whirs)
			"walker":
				_walker(h, rec, dt, rolls)
		rec.state = now
	_drive_slots(_hum, _hum_ids, hums, "zapper_hum_loop", dt)
	_drive_slots(_whir, _whir_ids, whirs, "drone_whir_loop", dt)
	_drive_slots(_roll, _roll_ids, rolls, "orb_roll_loop", dt)
	if run.tick % 60 == 0:
		for id in _heard.keys():
			if not seen.has(id):
				_heard.erase(id)


func _zapper(h: Zapper, dt: float, hums: Array) -> void:
	if h.dead:
		return
	var ends: Array = h.ends_at(run.time)
	var mid: Vector2 = (ends[0] + ends[1]) * 0.5
	var lane := float(h.lane) if h.lane_b < 0 else (float(h.lane) + float(h.lane_b)) * 0.5
	var pos := Vector3(mid.x, mid.y, RunView.lane_z(lane))
	var db := place_db(mid.x, lane)
	hums.append([h.id, db - 13.0, pos, 1.0])
	if db > -20.0 and _rng.randf() < dt * 0.7:
		voices.play("zapper_crackle_%d" % _rng.randi_range(1, 3), pos, db - 12.0, _rng.randf_range(0.9, 1.15), LOW, h.id)


func _laser(h: Laser, was: String, now: String) -> void:
	if now == was:
		return
	var lane := float(h.lane)
	var pos := Vector3(cam_x(), h.y, RunView.lane_z(lane))
	if now == "charge":
		voices.play("laser_charge", pos, -6.0 + lane_db(lane), clampf(1.6 / maxf(h.charge, 0.1), 0.6, 1.8), HAZARD, h.id)
		voices.follow(h.id, _mid_pos.bind(h.y, lane))
	elif now == "fire":
		voices.stop_tag(h.id)
		voices.play("laser_fire", pos, -2.0 + lane_db(lane), 1.0, REWARD, h.id)
		voices.follow(h.id, _mid_pos.bind(h.y, lane))


func _seeker(h: Seeker, was: String, now: String, rec: Dictionary, dt: float) -> void:
	var lane := float(h.lane)
	var edge := Vector3(cam_x() + 8.5, h.y, RunView.lane_z(lane))
	if now == "track":
		rec.beep = float(rec.beep) - dt
		if float(rec.beep) <= 0.0:
			var p := clampf(h.phase * (Seeker.TRACK + Seeker.LOCK) / Seeker.TRACK, 0.0, 1.0)
			rec.beep = lerpf(0.3, 0.085, p)
			voices.play("seeker_beep", edge, -9.0 + lane_db(lane) + 3.0 * p, 1.0, HAZARD, h.id)
	if now == was:
		if now == "fly" and not bool(rec.whoosh):
			var target := run.target()
			var closing := Seeker.SPEED + run.speed_now
			if target and h.x - target.x <= 0.55 * closing:
				rec.whoosh = true
				voices.play("seeker_whoosh", Vector3(h.x, h.y, RunView.lane_z(lane)), -3.0 + lane_db(lane), 1.0, REWARD, h.id)
				voices.follow(h.id, _hazard_pos.bind(h))
		return
	match now:
		"lock":
			voices.play("seeker_lock", edge, -7.0 + lane_db(lane), 1.0, HAZARD, h.id)
		"fly":
			voices.play("seeker_launch", edge, -8.0 + lane_db(lane), 1.0, HAZARD)
		"fizzle":
			voices.play("seeker_fizzle", edge, -6.0, 1.0, HAZARD)


func _shutter(h: Shutter, was: String, now: String) -> void:
	if now == was:
		return
	var pos := Vector3(h.x, 4.0, RunView.lane_z(float(h.lane)))
	var db := place_db(h.x, float(h.lane))
	if now == "closing" and db > SILENT:
		voices.play("shutter_klaxon", pos, db - 9.0, 1.0, HAZARD)
		voices.play("shutter_slide", pos, db - 10.0, 1.0, LOW)
	elif now == "shut" and db > SILENT:
		voices.play("shutter_slam", Vector3(h.x, 1.0, pos.z), db - 3.0, _rng.randf_range(0.95, 1.05), REWARD)


func _eye(h: EyeDrone, was: String, now: String, whirs: Array) -> void:
	if h.dead or h.t0 < 0.0:
		return
	var pos := Vector3(h.x, h.y, RunView.lane_z(float(h.lane)))
	var db := place_db(h.x, float(h.lane))
	whirs.append([h.id, db - 12.0, pos, 1.0 if now != "charge" else 1.0 + 0.3 * h.phase])
	if now == was:
		return
	if now == "charge":
		voices.play("drone_charge", pos, db - 8.0, 1.0, HAZARD, h.id)
	elif now == "attack":
		voices.play("drone_dash", pos, db - 4.0, 1.0, HAZARD, h.id)
		voices.follow(h.id, _hazard_pos.bind(h))


func _gun(h: GunDrone, was: String, now: String, rec: Dictionary, whirs: Array) -> void:
	if h.dead:
		return
	var pos := Vector3(h.x, h.y, RunView.lane_z(float(h.lane)))
	var db := place_db(h.x, float(h.lane))
	whirs.append([h.id, db - 14.0, pos, 0.8])
	if now == "charge" and was != "charge":
		voices.play("gun_charge", pos, db - 10.0, 1.0, HAZARD, h.id)
	if h.bolts.size() > int(rec.bolts):
		rec.bolts = h.bolts.size()
		voices.play("gun_bolt", pos, maxf(db, -12.0) - 5.0, _rng.randf_range(0.95, 1.05), HAZARD)


func _walker(h: Walker, rec: Dictionary, dt: float, rolls: Array) -> void:
	if h.dead:
		return
	var y := Shutter.TOP - h.size.y if h.ceiling else 0.0
	var pos := Vector3(h.x, y, RunView.lane_z(float(h.lane)))
	var db := place_db(h.x, float(h.lane))
	if h.state == "roll":
		rolls.append([h.id, db - 6.0, pos, 1.0])
	elif h.state == "walk" and db > -24.0:
		rec.stomp = float(rec.stomp) - dt
		if float(rec.stomp) <= 0.0:
			rec.stomp = 0.85 / maxf(h.pace_speed, 0.5)
			var pitch := 0.85 if h.body == "raptor" else 1.05
			voices.play("walker_stomp", pos, db - 10.0, pitch * _rng.randf_range(0.95, 1.05), LOW, h.id)


## Gives each loop slot one of the loudest candidates ([id, dB, position,
## pitch]), keeping a slot on the same hazard while it stays among them so
## a loop never jumps from one to another.
func _drive_slots(slots: Array[AudioStreamPlayer3D], ids: Array[int], cands: Array, sfx_name: String, dt: float) -> void:
	cands.sort_custom(_louder)
	var top := {}
	for i in mini(cands.size(), slots.size()):
		top[int(cands[i][0])] = cands[i]
	var taken := {}
	for s in slots.size():
		if ids[s] != 0 and top.has(ids[s]):
			var c: Array = top[ids[s]]
			taken[ids[s]] = true
			_drive(slots[s], sfx_name, c[2], float(c[1]) + _end_db(), float(c[3]), dt, 5.0)
		elif ids[s] != 0:
			_drive(slots[s], sfx_name, slots[s].position, SILENT - 20.0, slots[s].pitch_scale, dt, 5.0)
			if not slots[s].playing:
				ids[s] = 0
	for s in slots.size():
		if ids[s] != 0:
			continue
		for id in top:
			if not taken.has(id):
				taken[id] = true
				ids[s] = int(id)
				var c: Array = top[id]
				slots[s].volume_db = SILENT
				_drive(slots[s], sfx_name, c[2], float(c[1]) + _end_db(), float(c[3]), dt, 5.0)
				break


static func _louder(a: Array, b: Array) -> bool:
	return float(a[1]) > float(b[1])


func _hazard_pos(h: Hazard) -> Variant:
	if h.dead and h.state != "attack" and h.state != "fly":
		return null
	return Vector3(h.x, h.y, RunView.lane_z(float(h.lane)))


func _mid_pos(y: float, lane: float) -> Variant:
	return Vector3(cam_x(), y, RunView.lane_z(lane))


# --- Placing sounds -------------------------------------------------------

## Notes where the screen is and which lane you're in, once a tick.
func _look() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		_cx = cam.global_position.x
	elif run.mode == "party":
		_cx = run.cam_x
	else:
		var p := run.pilot(me)
		_cx = (p.x if p else run.distance()) + RunCamera.WIDTH * (0.5 - RunCamera.PILOT_AT)
	var mine := run.pilot(me)
	_lane = mine.lane if mine else 1.0


## The screen's middle along the run.
func cam_x() -> float:
	return _cx


## The lane of the pilot this screen follows.
func my_lane() -> float:
	return _lane


## How much quieter a hazard in this lane is than one in yours.
func lane_db(lane: float) -> float:
	return LANE_DB * absf(lane - my_lane())


## How loud something at x in this lane is: quieter in other lanes, fading
## past the edges of the screen.
func place_db(x: float, lane: float) -> float:
	var dx := absf(x - cam_x())
	if dx >= FADE_OUT:
		return SILENT - 20.0
	var edge := clampf((dx - SCREEN_HALF) / (FADE_OUT - SCREEN_HALF), 0.0, 1.0)
	return -30.0 * edge * edge + lane_db(lane)


## Hazards hush once the run is over.
func _end_db() -> float:
	return -10.0 if _over else 0.0


func _loop_player() -> AudioStreamPlayer3D:
	var p := SfxVoices.make_player()
	p.volume_db = SILENT - 20.0
	add_child(p)
	return p


## Keeps a loop playing at a place, easing its level towards `db` (linear
## amplitude, `speed` per second), and stops it once it's silent.
func _drive(p: AudioStreamPlayer3D, sfx_name: String, pos: Vector3, db: float, pitch: float, dt: float, speed: float) -> void:
	var want_on := sfx_name != "" and db > SILENT
	if want_on:
		var s := GameAudio.sfx(sfx_name)
		if s and p.stream != s:
			p.stream = s
			p.volume_db = SILENT
			p.play(_rng.randf() * maxf(s.get_length() - 0.1, 0.0))
		elif s and not p.playing:
			p.volume_db = SILENT
			p.play(_rng.randf() * maxf(s.get_length() - 0.1, 0.0))
	if not p.playing:
		return
	var to := db_to_linear(db) if want_on else 0.0
	var lin := lerpf(db_to_linear(p.volume_db), to, 1.0 - exp(-dt * speed))
	p.volume_db = linear_to_db(maxf(lin, 0.00001))
	p.position = pos
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	if not want_on and lin <= db_to_linear(SILENT):
		p.stop()


# --- Ambience and music ---------------------------------------------------

func _set_zone(zone: String) -> void:
	if zone == _amb_zone or not ZONE_AMB.has(zone):
		return
	_amb_zone = zone
	_amb_on = 1 - _amb_on
	var a := _amb[_amb_on]
	a.stream = GameAudio.sfx(str(ZONE_AMB[zone]))
	a.volume_db = SILENT
	if a.stream:
		a.play(_rng.randf() * maxf(a.stream.get_length() - 0.1, 0.0))


func _sync_amb(dt: float) -> void:
	for i in _amb.size():
		var a := _amb[i]
		if not a.playing:
			continue
		var to := db_to_linear(AMB_DB + _end_db()) if i == _amb_on else 0.0
		var lin := move_toward(db_to_linear(a.volume_db), to, dt * 0.08)
		a.volume_db = linear_to_db(maxf(lin, 0.00001))
		if i != _amb_on and lin <= 0.0001:
			a.stop()


func _sync_music() -> void:
	if _over:
		return
	if run.mode == "party":
		var alive := run.alive_count()
		var n := run.pilots.size()
		var lvl := 1
		if n > 1 and alive <= 2:
			lvl = 3
		elif alive < n:
			lvl = 2
		GameAudio.party_level(lvl)
		return
	var p := run.pilot(me)
	if p and p.state == Pilot.State.FLY:
		GameAudio.intensity(p.burn_level)


func _muffle(on: bool) -> void:
	if on == _muffled:
		return
	_muffled = on
	GameAudio.muffle(on, 0.35 if on else 1.2)


# --- Events ---------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	if run == null:
		return
	var kind := str(e.get("type", ""))
	var pid := int(e.get("pilot", 0))
	var p := run.pilot(pid) if pid != 0 else null
	var loud := locals.has(pid)
	var trim := 0.0 if loud else OTHERS_DB
	var at := pilot_pos(p) if p else Vector3(cam_x(), 3.0, RunView.lane_z(1.0))
	if e.has("x") and not p:
		at = Vector3(float(e.x), float(e.get("y", 1.0)), RunView.lane_z(float(e.get("lane", 1.0))))
	match kind:
		"room":
			_set_zone(str(e.get("zone", "")))
		"lane":
			if p and p.pack == "k5":
				voices.play("thruster_hiss", at, -8.0 + trim, _rng.randf_range(0.95, 1.08), LOW)
			elif loud:
				voices.play("lane_swish", at, -16.0, _rng.randf_range(0.9, 1.1), LOW)
		"pulse":
			voices.play("burner_k4_kick", at, -4.0 + trim, _rng.randf_range(0.94, 1.06), LOW, 0)
		"land":
			var hard := clampf((float(e.get("speed", 6.0)) - 6.0) / 8.0, 0.0, 1.0)
			voices.play("land_thump", at, -14.0 + 8.0 * hard + trim, _rng.randf_range(0.92, 1.05), LOW)
		"near":
			if loud:
				_near(e, at)
		"burn_lost":
			if loud:
				voices.play("burn_lost", at, -8.0, 1.0, REWARD)
		"credit":
			_credit(e, at, loud)
		"smash":
			var spot := Vector3(float(e.get("x", at.x)), float(e.get("y", 1.0)), RunView.lane_z(float(e.get("lane", 1.0))))
			voices.play("robot_smash", spot, -3.0 + trim, _rng.randf_range(0.95, 1.05), BIG)
			if loud:
				voices.play_later(0.12, "credit", spot, -10.0, pow(2.0, 12.0 / 12.0), REWARD)
		"vehicle":
			voices.play("crate_open", at, -5.0 + trim, 1.0, REWARD)
			voices.play_later(0.15, "vehicle_on", at, -6.0 + trim, 1.0, REWARD)
		"vehicle_lost":
			voices.play("vehicle_lost", at, -2.0 + trim, 1.0, CRASH)
		"jump":
			voices.play("raptor_jump", at, -7.0 + trim, _rng.randf_range(0.95, 1.05), LOW)
		"flip":
			voices.play("shell_flip", at, -7.0 + trim, 1.0, LOW)
		"hop":
			voices.play("eye_hop", at, -8.0 + trim, _rng.randf_range(0.95, 1.08), LOW)
		"shot":
			var shot_at := Vector3(float(e.get("x", at.x)), float(e.get("y", at.y)), RunView.lane_z(float(e.get("lane", 1))))
			voices.play("gunner_shot", shot_at, -9.0 + trim, _rng.randf_range(0.96, 1.04), LOW)
		"knock":
			_knock(e, trim)
		"crash":
			voices.play("crash_hit", at, -1.0 + trim, 1.0, CRASH)
			voices.play("burner_sputter", at, -5.0 + trim, 1.0, CRASH)
			if loud and run.mode != "party":
				_over = true
				_crashed = true
				GameAudio.intensity(0)
				_muffle(true)
		"shield":
			voices.play("shield_pop", at, -3.0 + trim, 1.0, CRASH)
		"armour":
			voices.play("armour_clank", at, -3.0 + trim, 1.0, CRASH)
		"reboot":
			voices.play("reboot", at, -4.0 + trim, 1.0, CRASH)
		"stun":
			voices.play("stun", at, -4.0 + trim, 1.0, CRASH if loud else HAZARD)
		"out":
			voices.play("out", at, -4.0 + (0.0 if loud else -6.0), 1.0, BIG)
		"rocket_end":
			voices.play("rocket_end", at, -5.0 + trim, 1.0, REWARD)
		"done":
			pass
		"finish":
			_end("finish")
		"round_over":
			_end("round_over")
		"run_over":
			_end("run_over")


func _near(e: Dictionary, at: Vector3) -> void:
	var lvl := int(e.get("level", 1))
	var pitch := 1.0 + NEAR_PITCH * (lvl - 1) + _rng.randf_range(-0.02, 0.02)
	match str(e.get("what", "close")):
		"skim":
			voices.play("near_whoosh", at, -10.0, pitch * 0.92, REWARD)
		"close":
			voices.play("near_whoosh", at, -5.0, pitch, REWARD)
		"razor":
			voices.play("near_whoosh", at, -3.0, pitch * 1.04, REWARD)
			voices.play("near_razor", at, -9.0, pitch, REWARD)
		"thread":
			voices.play("near_thread", at, -3.0, pitch, REWARD)
	if bool(e.get("up", false)):
		if lvl >= Pilot.BURN_STEPS.size():
			voices.play("burn_max", at, -2.0, 1.0, BIG)
		else:
			voices.play("burn_up", at, -4.0, pow(2.0, [0, 2, 3, 5][clampi(lvl - 2, 0, 3)] / 12.0), BIG)


func _credit(e: Dictionary, at: Vector3, loud: bool) -> void:
	var spot := Vector3(float(e.get("x", at.x)), float(e.get("y", at.y)), RunView.lane_z(float(e.get("lane", 1.0))))
	if bool(e.get("big", false)):
		voices.play("credit_big", spot, -5.0 if loud else -18.0, 1.0, REWARD)
		return
	if not loud:
		voices.play("credit", spot, -20.0, 1.0, LOW)
		return
	if run.time - _ladder_t < LADDER_GAP:
		_ladder = mini(_ladder + 1, LADDER.size() - 1)
	else:
		_ladder = 0
	_ladder_t = run.time
	voices.play("credit", spot, -9.0, pow(2.0, float(LADDER[_ladder]) / 12.0), REWARD)


func _knock(e: Dictionary, trim: float) -> void:
	var female := false
	for s in run.staff:
		if int(s.id) == int(e.get("staff", -1)):
			female = bool(s.get("female", false))
	var spot := Vector3(float(e.get("x", cam_x())), 1.2, RunView.lane_z(float(e.get("lane", 1))))
	var oof := "staff_oof_%s%d" % ["f" if female else "m", _rng.randi_range(1, 2)]
	voices.play(oof, spot, -10.0 + trim, _rng.randf_range(0.93, 1.07), LOW)
	voices.play_later(0.28, "staff_thud", Vector3(spot.x, 0.2, spot.z), -10.0 + trim, _rng.randf_range(0.95, 1.05), LOW)


func _end(stinger: String) -> void:
	_over = true
	_crashed = false
	if run.mode == "party":
		GameAudio.party_level(0)
	else:
		GameAudio.intensity(0)
	_muffle(false)
	GameAudio.stinger(stinger)
