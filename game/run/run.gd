class_name Run
extends RefCounted
## One run through the tower, with no nodes: the pilots, the rooms ahead,
## the hazards, credits, crates and staff in them, Burn, hits and crashes.
## It steps at 60 Hz from a seed, so the same seed and inputs always play the
## same way, and tests fly hundreds of runs headless. [RunView] draws it,
## [RunScene] feeds it controls, [Autopilot] flies bots in it.
##
## Coordinates: x along the run (metres, the screen's right), y up from the
## floor (a pilot's feet), and three lanes, 0 near the camera, 1 in the
## middle and 2 far.
##
## Modes (config.mode): "endless", "daily" and "course" are one pilot whose
## distance is the run; "party" is Last One Flying, where the screen moves at
## the run's speed and pilots fall behind it; "tutorial" is the first flight.

const DT := 1.0 / 60.0
const LANES := 3
## Highest a pilot's feet go; the room is 8 m tall.
const TOP := 6.3
const CEILING := 8.0
## Each pace's speed: start, top and how many metres it takes to get there.
const PACES := {
	"calm": {"start": 7.5, "top": 13.0, "ramp": 4000.0},
	"normal": {"start": 9.0, "top": 18.5, "ramp": 3200.0},
	"fast": {"start": 11.0, "top": 23.0, "ramp": 2600.0},
}
## Burn adds this much speed per level above x1.
const BURN_SPEED := 0.035
## Generate rooms this far ahead of the run.
const LOOK_AHEAD := 90.0
## Forget things this far behind.
const KEEP_BEHIND := 40.0
## Head start: metres of rocket and how fast.
const HEAD_START := 650.0
const ROCKET_SPEED := 2.6

## Party races: how far behind the screen's middle a pilot can fall before
## they're out, and how far ahead they can get.
const PARTY_EDGE := 10.0
const PARTY_FRONT := 6.0

## Seekers the Jammer gadget stops in a run.
const JAMS := 3

## Credits are picked up this close (metres, and lanes).
const PICKUP_R := 0.85
const PICKUP_LANE := 0.6
## Magnet gadget reach.
const MAGNET_R := 6.0

var config := {}
var mode := "endless"
var seed := 1
var pace := "normal"
var lanes_on := true
var course: Course
## Whether this copy decides hits, pickups and who's out (host and solo).
## A party guest's copy only moves the course and its own pilots.
var authority := true
## On a guest: its own pilots, whose party stuns it works out at once rather
## than a round trip later (the host's word still wins).
var predict: Array = []

var time := 0.0
var tick := 0
var pilots: Array[Pilot] = []
var hazards: Array = []
## Credits and crates: Pickup objects.
var pickups: Array = []
## Staff on the floor: {"id", "x", "lane", "job", "female", "seed", "knocked": time or -1, "by"}.
var staff: Array = []
## What happened this tick and since the view last took them.
var events: Array = []
## How far along the run things trigger: the pilot (one pilot) or the
## screen (party).
var trigger_x := 0.0
## The screen's middle in party races (the pilot's x otherwise).
var cam_x := 0.0
var speed_now := 9.0
var finished := false
## Party: who won, or -1.
var winner := -1
## Course mode: where the finish is (INF otherwise).
var finish_x := INF

func _init(p_config := {}) -> void:
	config = p_config
	mode = str(config.get("mode", "endless"))
	seed = int(config.get("seed", 1))
	pace = str(config.get("pace", "normal"))
	if not PACES.has(pace):
		pace = "normal"
	lanes_on = bool(config.get("lanes", true))
	course = Course.new(config)
	finish_x = course.finish_x
	cam_x = Course.START_X
	trigger_x = cam_x
	var list: Array = config.get("pilots", [{"id": 1, "name": "Pilot"}])
	for i in list.size():
		var d: Dictionary = list[i]
		var p := Pilot.new(int(d.get("id", i + 1)), str(d.get("name", "Pilot")), str(d.get("pack", "k1")))
		p.bot = bool(d.get("bot", false))
		p.look = d.get("look", {})
		p.lane = 1.0
		p.lane_to = 1
		p.x = Course.START_X
		if mode == "party":
			# Start in a row across the lanes.
			p.lane_to = [1, 0, 2, 1, 0, 2, 1, 0][i % 8] if lanes_on else 1
			p.lane = float(p.lane_to)
			p.ahead = -1.5 * float(i / 3) + (2.0 if i % 3 == 0 else 0.0)
			p.y = 0.0
		var gadgets: Array = d.get("gadgets", [])
		if "shield" in gadgets:
			p.shield = 1
		if "reboot" in gadgets:
			p.reboots = 1
		if "jammer" in gadgets:
			p.jams = JAMS
		if "head_start" in gadgets:
			p.rocket = HEAD_START
		p.stats["gadgets"] = gadgets.duplicate()
		pilots.append(p)
	_stream()


# --- Speed ----------------------------------------------------------------

## The run's speed at distance d, before Burn.
func speed_at(d: float) -> float:
	return pace_speed(pace, d + course.speed_from)


static func pace_speed(p_pace: String, d: float) -> float:
	var pc: Dictionary = PACES.get(p_pace, PACES["normal"])
	var top: float = pc.top
	var start: float = pc.start
	var base := start + (top - start) * (1.0 - exp(-maxf(d, 0.0) / float(pc.ramp)))
	# After the first loop of the tower it keeps creeping up.
	return base + maxf(0.0, d - Course.LOOP) * 0.0004


func pilot(id: int) -> Pilot:
	for p in pilots:
		if p.id == id:
			return p
	return null


## The pilot hazards go after: the one pilot, or the leader in party races.
func target() -> Pilot:
	if mode != "party":
		return pilots[0]
	var best: Pilot = null
	for p in pilots:
		if p.alive() and (best == null or p.x > best.x):
			best = p
	return best if best else pilots[0]


## Party races: aims change this often, so a drone's height drifts
## rather than jitters.
const AIM_EVERY := 1.2


## The height a seeker or drone aims at. Party races have no one pilot to
## follow, so each hazard (key) picks heights from the seed and the clock:
## every device works them out the same, whatever else has happened.
func aim_y(key: int) -> float:
	if mode == "party":
		return lerpf(0.6, TOP - 0.6, _aim_roll(key, 0))
	return target().y


func aim_lane(key: int) -> int:
	if not lanes_on:
		return 1
	if mode == "party":
		return mini(int(_aim_roll(key, 1) * LANES), LANES - 1)
	return target().lane_to


func _aim_roll(key: int, what: int) -> float:
	return float(hash([seed, key, what, int(time / AIM_EVERY)]) & 0xffffff) / float(0x1000000)


## A check on what every hazard is doing, for party races to compare
## between devices.
func aim_check() -> int:
	var h := 0
	for z in hazards:
		if not z.dead:
			h = hash([h, z.id, z.lane, roundi(z.y * 20.0)])
	return h


## A seeker about to launch asks whether the pilot's Jammer stops it.
func use_jam(seeker_id: int) -> bool:
	if mode == "party":
		return false
	var p := target()
	if p.jams <= 0 or not p.alive():
		return false
	p.jams -= 1
	p.add_stat("jammed")
	events.append({"type": "jammed", "pilot": p.id, "hazard": seeker_id})
	return true


func alive_count() -> int:
	var n := 0
	for p in pilots:
		if p.alive():
			n += 1
	return n


## Distance flown by the run (the one pilot's x, or the screen in party).
func distance() -> float:
	return cam_x if mode == "party" else (pilots[0].x if not pilots.is_empty() else 0.0)


func zone() -> String:
	return course.zone_at(trigger_x)


# --- The tick -------------------------------------------------------------

## Moves everything one tick. `inputs` is pilot id -> RunInput; pilots
## without one hold nothing.
func step(inputs: Dictionary) -> void:
	if finished:
		return
	time += DT
	tick += 1
	_advance_trigger()
	_stream()
	for h in hazards:
		h.step(self, DT)
	for p in pilots:
		var inp: RunInput = inputs.get(p.id, RunInput.NONE)
		_step_pilot(p, inp)
	if authority:
		for p in pilots:
			if p.state == Pilot.State.FLY:
				_touch(p)
				_pickups(p)
				_staff(p)
		if mode == "party":
			_party_rules()
		_check_end()
	elif mode == "party":
		for p in pilots:
			if p.id in predict and p.state == Pilot.State.FLY:
				_predict_stun(p)
	_forget_behind()


func _advance_trigger() -> void:
	if mode == "party":
		speed_now = speed_at(cam_x)
		cam_x += speed_now * DT
		trigger_x = cam_x
	else:
		var p := pilots[0]
		trigger_x = p.x
		cam_x = p.x
		speed_now = speed_at(p.x)


## Builds rooms until there's enough course ahead.
func _stream() -> void:
	while course.end_x < trigger_x + LOOK_AHEAD:
		var room := course.next_room()
		for h in room.hazards:
			h.born = time
			hazards.append(h)
		pickups.append_array(room.pickups)
		staff.append_array(room.staff)
		events.append({"type": "room", "room": room.index, "zone": room.zone, "x": room.x0})


func _forget_behind() -> void:
	var back := INF
	for p in pilots:
		if p.state != Pilot.State.OUT:
			back = minf(back, p.x)
	if mode == "party":
		back = minf(back, cam_x - PARTY_EDGE)
	back -= KEEP_BEHIND
	var keep := []
	for h in hazards:
		if not (h.dead and h.extent().y < back + KEEP_BEHIND) and h.extent().y > back:
			keep.append(h)
	hazards = keep
	var kp := []
	for c in pickups:
		if c.x > back and not c.taken:
			kp.append(c)
	pickups = kp
	var ks := []
	for s in staff:
		if float(s.x) > back:
			ks.append(s)
	staff = ks
	course.forget_before(back)


# --- Flying ---------------------------------------------------------------

func _step_pilot(p: Pilot, inp: RunInput) -> void:
	p.since_near += DT
	if p.invuln > 0.0:
		p.invuln = maxf(0.0, p.invuln - DT)
	match p.state:
		Pilot.State.CRASH:
			_step_crash(p)
			return
		Pilot.State.DONE, Pilot.State.OUT:
			if mode == "party" and p.state == Pilot.State.OUT:
				p.x = cam_x + p.ahead
			return
	var held := inp.fly and p.stun <= 0.0
	p.held_for = p.held_for + DT if held else 0.0
	p.flying = held
	# Lanes.
	if lanes_on and inp.lane != 0 and p.stun <= 0.0:
		var to := clampi(p.lane_to + inp.lane, 0, LANES - 1)
		if to != p.lane_to:
			p.lane_to = to
			p.add_stat("lane_changes")
			events.append({"type": "lane", "pilot": p.id, "to": to})
	if not lanes_on:
		p.lane_to = 1
	var lane_time: float = float(p.spec.lane)
	if p.vehicle != "":
		lane_time = 0.24
	p.lane = move_toward(p.lane, float(p.lane_to), DT / lane_time)
	# Height.
	if p.rocket > 0.0:
		_step_rocket(p)
	elif p.vehicle != "":
		_step_vehicle(p, inp)
	else:
		_step_jetpack(p, held)
	# Along the run.
	var speed := speed_now
	if mode != "party":
		speed = speed_at(p.x) * (1.0 + BURN_SPEED * (p.burn_level - 1))
		if p.rocket > 0.0:
			speed *= ROCKET_SPEED
			p.rocket = maxf(0.0, p.rocket - speed * DT)
			if p.rocket <= 0.0:
				p.invuln = 1.0
				events.append({"type": "rocket_end", "pilot": p.id})
		p.x += speed * DT
	else:
		p.x = cam_x + p.ahead
	# Burn goes if you sit on the floor (vehicles don't count).
	if p.on_floor and p.vehicle == "" and p.rocket <= 0.0:
		p.floor_time += DT
		if p.floor_time > Pilot.FLOOR_GRACE and p.burn_points > 0 and authority:
			p.lose_burn()
			events.append({"type": "burn_lost", "pilot": p.id, "why": "floor"})
	else:
		p.floor_time = 0.0
		if p.vehicle == "":
			p.add_stat("air_ticks")
	if p.vehicle != "":
		p.max_stat("ride_" + p.vehicle, p.x - p.vehicle_from)
	if p.stun > 0.0:
		p.stun = maxf(0.0, p.stun - DT)
	p.max_stat("distance", p.x)


func _step_jetpack(p: Pilot, held: bool) -> void:
	var s := p.spec
	var gravity := float(s.gravity)
	if float(s.get("pulse", 0.0)) > 0.0:
		if held:
			p._pulse -= DT
			if p._pulse <= 0.0:
				p.vy = minf(maxf(p.vy, 0.0) + float(s.kick), float(s.rise))
				p._pulse = float(s.pulse)
				events.append({"type": "pulse", "pilot": p.id})
		else:
			p._pulse = 0.0
		p.vy -= gravity * DT
	else:
		var acc := (float(s.thrust) if held else 0.0) - gravity
		p.vy += acc * DT
	p.vy = clampf(p.vy, -float(s.fall), float(s.rise))
	_move_y(p, TOP)


func _move_y(p: Pilot, top: float) -> void:
	p.y += p.vy * DT
	var was_floor := p.on_floor
	p.on_floor = false
	if p.y <= 0.0:
		p.y = 0.0
		if p.vy < 0.0:
			if not was_floor and p.vy < -6.0:
				events.append({"type": "land", "pilot": p.id, "speed": -p.vy})
			p.vy = 0.0
		p.on_floor = true
	elif p.y >= top:
		p.y = top
		p.vy = minf(p.vy, 0.0)


## Head start: a rocket ride at mid height, untouchable.
func _step_rocket(p: Pilot) -> void:
	p.invuln = maxf(p.invuln, 0.2)
	p.y = move_toward(p.y, 3.0, 6.0 * DT)
	p.vy = 0.0
	p.on_floor = false


func _step_vehicle(p: Pilot, inp: RunInput) -> void:
	var pressed := inp.fly and not inp.was_fly
	match p.vehicle:
		"raptor":
			# Runs along the floor. Tap to jump, hold to jump higher.
			if pressed and p.on_floor:
				p.vy = 10.5
				events.append({"type": "jump", "pilot": p.id})
			var g := 34.0
			if inp.fly and p.vy > 0.0 and p.held_for < 0.32:
				g *= 0.45
			p.vy = maxf(p.vy - g * DT, -18.0)
			_move_y(p, TOP - 1.0)
		"shell":
			# Walks on the floor or the ceiling; tap to flip.
			if pressed and (p.on_floor or p.y >= CEILING - 1.6 - 0.01):
				p.upside = not p.upside
				events.append({"type": "flip", "pilot": p.id})
			var want := CEILING - 1.6 if p.upside else 0.0
			p.vy = 18.0 if p.upside else -18.0
			p.y = move_toward(p.y, want, 18.0 * DT)
			p.on_floor = p.y <= 0.0
		"eye":
			# Tap to hop; it drops fast between taps.
			if pressed:
				p.vy = 8.0
				events.append({"type": "hop", "pilot": p.id})
			p.vy = maxf(p.vy - 30.0 * DT, -15.0)
			_move_y(p, TOP)
		"gunner":
			# Hold to hover and fire ahead.
			var acc := (42.0 if inp.fly else 0.0) - 26.0
			p.vy = clampf(p.vy + acc * DT, -11.0, 8.0)
			_move_y(p, TOP)
			p.gun_cool -= DT
			if inp.fly and p.gun_cool <= 0.0:
				p.gun_cool = 0.28
				_gunner_fire(p)


func _gunner_fire(p: Pilot) -> void:
	events.append({"type": "shot", "pilot": p.id, "x": p.x + 1.2, "y": p.y + 1.1, "lane": p.lane_to})
	if not authority:
		return
	var best: Hazard = null
	var best_d := 15.0
	for h in hazards:
		if h.dead or not h.smashable or absf(float(h.lane) - p.lane) > 0.6:
			continue
		var d: float = h.x - p.x
		if d > 0.5 and d < best_d:
			best_d = d
			best = h
	if best:
		_smash(p, best, "shot")


func _step_crash(p: Pilot) -> void:
	p.vy -= 30.0 * DT
	p.y += p.vy * DT
	if p.y <= 0.0:
		p.y = 0.0
		p.vy = -p.vy * 0.3 if p.vy < -3.0 else 0.0
		p.slide_speed = maxf(0.0, p.slide_speed - 7.5 * DT)
	else:
		p.slide_speed *= 0.995
	p.x += p.slide_speed * DT
	p.max_stat("distance", p.x)
	if p.slide_speed <= 0.05 and p.y <= 0.0 and time - p.crashed_at > 1.0:
		p.state = Pilot.State.DONE
		events.append({"type": "done", "pilot": p.id, "distance": p.x})


# --- Hits and near misses -------------------------------------------------

func _touch(p: Pilot) -> void:
	var b := p.body()
	for h in hazards:
		var ext: Vector2 = h.extent()
		if ext.x > p.x + 2.5 or ext.y < p.x - 2.5:
			if p.near.has(h.id) and (h.behind(p.x) or h.dead):
				_award_near(p, h)
			continue
		if h.dead:
			if p.near.has(h.id):
				_award_near(p, h)
			continue
		var rec: Array = p.near.get(h.id, [INF, false, false])
		var touched := false
		for s in h.shapes_at(time, self):
			var c := Hazard.clearance(s, p.x, b.x, b.y, b.z, p.lane)
			var dl := absf(c.y)
			if dl < Hazard.LANE_HIT:
				if c.x < 0.0:
					touched = true
					break
				rec[0] = minf(rec[0], c.x)
			elif dl < Hazard.LANE_SKIM and c.x < 0.0:
				rec[1] = true
				if absf(p.lane - float(p.lane_to)) > 0.05:
					rec[2] = true
		if touched:
			p.near.erase(h.id)
			_hit(p, h)
			if p.state != Pilot.State.FLY:
				return
			b = p.body()
			continue
		if rec[0] < INF or rec[1]:
			p.near[h.id] = rec
		if h.behind(p.x) and p.near.has(h.id):
			_award_near(p, h)


## A guest's guess at a party stun for its own pilot, as [method _hit]
## would decide it: no events, no stats, nothing a shield or vehicle changes.
func _predict_stun(p: Pilot) -> void:
	if p.invuln > 0.0 or p.vehicle != "" or p.shield > 0 or p.armour > 0:
		return
	var b := p.body()
	for h in hazards:
		if h.dead:
			continue
		var ext: Vector2 = h.extent()
		if ext.x > p.x + 2.5 or ext.y < p.x - 2.5:
			continue
		for sh in h.shapes_at(time, self):
			var c := Hazard.clearance(sh, p.x, b.x, b.y, b.z, p.lane)
			if absf(c.y) < Hazard.LANE_HIT and c.x < 0.0:
				p.near.erase(h.id)
				p.stun = 1.1
				p.invuln = 1.8
				p.vy = minf(p.vy, 0.0)
				return


func _award_near(p: Pilot, h: Hazard) -> void:
	var rec: Array = p.near[h.id]
	p.near.erase(h.id)
	if p.state != Pilot.State.FLY:
		return
	var what := ""
	var pts := 0
	if rec[2]:
		what = "thread"
		pts = 2
	elif rec[0] < 0.22:
		what = "razor"
		pts = 2
	elif rec[0] < 0.6:
		what = "close"
		pts = 1
	elif rec[1]:
		what = "skim"
		pts = 1
	if pts == 0:
		return
	var up := p.add_burn(pts)
	p.add_stat("near")
	p.add_stat("near_" + what)
	p.add_stat("near_" + h.kind)
	p.max_stat("burn", p.burn_level)
	if mode == "party":
		p.ahead += 0.25 * pts
	events.append({"type": "near", "pilot": p.id, "what": what, "kind": h.kind, "points": pts, "level": p.burn_level, "up": up, "x": p.x, "y": p.y})


func _hit(p: Pilot, h: Hazard) -> void:
	if p.invuln > 0.0:
		return
	# Vehicles smash the smaller robots by landing on them.
	if p.vehicle in ["raptor", "shell"] and h.smashable and h.kind != "seeker":
		var top: float = p.y
		if p.vehicle == "raptor" and p.vy <= 0.0 and h.y + 0.5 <= top + 1.0:
			_smash(p, h, "stomp")
			p.vy = 9.0
			return
	p.add_stat("hits")
	p.add_stat("hit_" + h.kind)
	var lost := p.lose_burn()
	if p.vehicle != "":
		events.append({"type": "vehicle_lost", "pilot": p.id, "vehicle": p.vehicle, "kind": h.kind, "x": p.x, "y": p.y, "lane": p.lane})
		p.vehicle = ""
		p.upside = false
		p.invuln = 1.3
		p.vy = 8.5
		return
	if p.shield > 0:
		p.shield -= 1
		p.invuln = 1.2
		events.append({"type": "shield", "pilot": p.id, "kind": h.kind})
		return
	if p.armour > 0:
		p.armour -= 1
		p.invuln = 1.2
		events.append({"type": "armour", "pilot": p.id, "kind": h.kind})
		return
	if mode == "party":
		p.stun = 1.1
		p.invuln = 1.8
		p.vy = minf(p.vy, 0.0)
		events.append({"type": "stun", "pilot": p.id, "kind": h.kind, "x": p.x, "y": p.y, "lost_burn": lost})
		return
	if p.reboots > 0:
		p.reboots -= 1
		p.invuln = 2.0
		p.vy = 7.0
		events.append({"type": "reboot", "pilot": p.id, "kind": h.kind})
		return
	p.state = Pilot.State.CRASH
	p.crashed_at = time
	p.slide_speed = speed_at(p.x) * (1.0 + BURN_SPEED * (p.burn_level - 1))
	p.vy = 4.0
	p.flying = false
	p.stats["killed_by"] = h.kind
	events.append({"type": "crash", "pilot": p.id, "kind": h.kind, "x": p.x, "y": p.y, "lane": p.lane})


func _smash(p: Pilot, h: Hazard, how: String) -> void:
	h.dead = true
	h.state = "smashed"
	p.add_stat("smash")
	p.add_stat("smash_" + h.kind)
	var value := 5 * p.burn_level
	p.credits += value
	p.add_burn(1)
	events.append({"type": "smash", "pilot": p.id, "hazard": h.id, "kind": h.kind, "how": how, "x": h.x, "y": h.y, "lane": h.lane, "credits": value})


# --- Credits, crates and staff --------------------------------------------

func _pickups(p: Pilot) -> void:
	var c := p.center()
	var reach := PICKUP_R + (0.35 if p.vehicle != "" else 0.0)
	var magnet: bool = "magnet" in p.stats.get("gadgets", [])
	for k in pickups:
		if k.taken:
			continue
		var dx: float = k.x - c.x
		if dx > MAGNET_R or dx < -2.0:
			continue
		if magnet and k.kind == "credit" and dx < MAGNET_R:
			var to := Vector3(c.x, c.y, p.lane) - Vector3(k.x, k.y, k.lane)
			if to.length() < MAGNET_R:
				var mv := to.normalized() * minf(to.length(), 20.0 * DT)
				k.x += mv.x
				k.y += mv.y
				k.lane += mv.z
				dx = k.x - c.x
		if absf(k.lane - p.lane) > PICKUP_LANE:
			continue
		if Vector2(dx, k.y - c.y).length() > reach:
			continue
		k.taken = true
		k.by = p.id
		match k.kind:
			"credit", "big":
				var v: int = k.value * p.burn_level
				p.credits += v
				p.add_stat("credits", v)
				p.add_stat("pickups")
				if mode == "party":
					p.ahead += 0.35 if k.kind == "credit" else 1.5
				events.append({"type": "credit", "pilot": p.id, "pickup": k.id, "value": v, "big": k.kind == "big", "x": k.x, "y": k.y, "lane": k.lane})
			"crate":
				if p.vehicle != "":
					p.credits += 25
					events.append({"type": "credit", "pilot": p.id, "pickup": k.id, "value": 25, "big": true, "x": k.x, "y": k.y, "lane": k.lane})
				else:
					p.vehicle = k.vehicle
					p.vehicle_from = p.x
					p.upside = false
					p.vy = 0.0
					p.add_stat("rides")
					p.add_stat("ride_count_" + k.vehicle)
					events.append({"type": "vehicle", "pilot": p.id, "pickup": k.id, "vehicle": k.vehicle, "x": k.x, "lane": k.lane})


func _staff(p: Pilot) -> void:
	for s in staff:
		if float(s.knocked) >= 0.0:
			continue
		var dx: float = float(s.x) - p.x
		if dx > 1.6 or dx < -1.6:
			continue
		if absf(float(s.lane) - p.lane) > 0.8:
			continue
		var low := p.y < 2.6 and (p.flying or p.vehicle != "")
		if low or (p.vehicle != "" and p.y < 1.5):
			s.knocked = time
			s.by = p.id
			p.add_stat("staff")
			events.append({"type": "knock", "pilot": p.id, "staff": s.id, "x": s.x, "lane": s.lane})


# --- Party: Last One Flying -----------------------------------------------

func _party_rules() -> void:
	for p in pilots:
		if p.state != Pilot.State.FLY:
			continue
		var drift := 0.0
		if p.stun > 0.0:
			drift -= 3.6
		elif p.on_floor and p.vehicle == "":
			drift -= 0.7
		else:
			drift += 0.22
		# Slipstream: right behind someone in the same lane.
		for o in pilots:
			if o == p or not o.alive():
				continue
			var gap := o.x - p.x
			if gap > 0.6 and gap < 3.5 and absf(o.lane - p.lane) < 0.5 and absf(o.y - p.y) < 1.6:
				drift += 0.9
				p.add_stat("slipstream_ticks")
				break
		p.ahead = minf(p.ahead + drift * DT, PARTY_FRONT)
		p.x = cam_x + p.ahead
		# Bumping: pilots in the same lane push apart along the run (only along
		# it: a guest can't know the others' heights in time to feel a push
		# up or down).
		for o in pilots:
			if o == p or not o.alive():
				continue
			if absf(o.lane - p.lane) < 0.5 and absf(o.x - p.x) < 0.7 and absf(o.y - p.y) < 1.2:
				p.ahead += 0.6 * DT * signf(p.x - o.x if p.x != o.x else float(p.id - o.id))
		if p.ahead < -PARTY_EDGE:
			p.state = Pilot.State.OUT
			p.out_at = time
			p.flying = false
			p.place = alive_count() + 1
			events.append({"type": "out", "pilot": p.id, "place": p.place})


func _check_end() -> void:
	if finished:
		return
	if mode == "party":
		var alive := alive_count()
		if (pilots.size() > 1 and alive <= 1) or alive == 0:
			finished = true
			for p in pilots:
				if p.alive():
					p.place = 1
					winner = p.id
			if winner == -1:
				# Everyone went out together: whoever lasted longest.
				var best: Pilot = null
				for p in pilots:
					if best == null or p.out_at > best.out_at or (p.out_at == best.out_at and p.ahead > best.ahead):
						best = p
				winner = best.id
				best.place = 1
			events.append({"type": "round_over", "winner": winner})
		return
	var p := pilots[0]
	if p.state == Pilot.State.DONE:
		finished = true
		events.append({"type": "run_over", "distance": p.x})
	elif p.x >= finish_x and p.state == Pilot.State.FLY:
		finished = true
		p.stats["finish_time"] = time
		events.append({"type": "finish", "pilot": p.id, "time": time})


## Everything that happened since the last call.
func take_events() -> Array:
	var out := events
	events = []
	return out


## Hazards near x, for views and bots: those whose span touches [x0, x1].
func hazards_between(x0: float, x1: float) -> Array:
	var out := []
	for h in hazards:
		var e: Vector2 = h.extent()
		if e.y >= x0 and e.x <= x1:
			out.append(h)
	return out
