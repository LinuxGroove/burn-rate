class_name RoomGen
extends RefCounted
## One room of the course while it's being made, and the room once it's
## made. A pattern (see [Patterns]) fills it through the helpers below, which
## take x in metres from the room's start; [Course] then hands the hazards,
## pickups and staff to the run, and [RunView] builds the room's walls from
## its zone, length and tags.

## Rooms are whole tiles of the kit's 4 m grid.
const TILE := 4.0

var index := 0
var zone := "lab"
var x0 := 0.0
var length := 32.0
## How hard: 0 at the start of a run, 1 at the end of the first loop.
var d := 0.0
## The run's speed here (m/s), so patterns can space things in seconds.
var speed := 9.0
var lanes := true
var rng := RandomNumberGenerator.new()
## The pattern that made it.
var pattern := ""
## For the view: "entry" (first room of a zone), "window_out", "window_in",
## "finish", "start", "dark", "office".
var tags := {}
## A tip shown when the run reaches the room (the first flight).
var tip := ""

var hazards: Array = []
var pickups: Array = []
var staff: Array = []
## Decoration the pattern asks for: [model, x, lane or -1 for the back wall, y, yaw].
var props: Array = []
var _n := 0


func _init(p_index := 0, p_zone := "lab", p_x0 := 0.0, p_d := 0.0, p_speed := 9.0, p_lanes := true, p_seed := 0) -> void:
	index = p_index
	zone = p_zone
	x0 = p_x0
	d = p_d
	speed = p_speed
	lanes = p_lanes
	rng.seed = p_seed


func end_x() -> float:
	return x0 + length


## Sets the room's length to whole tiles, at least `metres`.
func fit(metres: float) -> void:
	length = maxf(TILE * 4.0, ceilf(metres / TILE) * TILE)


## Metres the run covers in `s` seconds here.
func secs(s: float) -> float:
	return s * speed


## A difficulty-scaled value between easy and hard.
func by_d(easy: float, hard: float) -> float:
	return lerpf(easy, hard, clampf(d, 0.0, 1.0))


func _id() -> int:
	_n += 1
	return index * 1000 + _n


func lane_any() -> int:
	return rng.randi_range(0, 2) if lanes else 1


## The lanes other than `l`, in random order.
func others(l: int) -> Array:
	var out := [0, 1, 2]
	out.erase(l)
	if rng.randf() < 0.5:
		out.reverse()
	return out


func chance(p: float) -> bool:
	return rng.randf() < p


# --- Hazards --------------------------------------------------------------

## A zapper centred at (xm, y): `length` long, `angle` degrees from flat
## (90 stands it up). Options: spin (degrees a second), lane_b (stands across
## two lanes), bob (metres up and down), bob_period.
func zapper(xm: float, y: float, lane: int, length_m: float, angle_deg := 90.0, opts := {}) -> Zapper:
	var z := Zapper.new()
	z.id = _id()
	z.x = x0 + xm
	z.y = y
	z.lane = lane if lanes else 1
	z.half = length_m * 0.5
	z.angle = deg_to_rad(angle_deg)
	z.spin = deg_to_rad(float(opts.get("spin", 0.0)))
	z.lane_b = int(opts.get("lane_b", -1)) if lanes else -1
	z.bob = float(opts.get("bob", 0.0))
	z.bob_period = float(opts.get("bob_period", 2.0))
	# Keep the ends inside the room.
	var e := z.ends_at(0.0)
	var lo := minf(e[0].y, e[1].y) - z.bob
	var hi := maxf(e[0].y, e[1].y) + z.bob
	if z.spin == 0.0:
		if lo < 0.3:
			z.y += 0.3 - lo
		elif hi > Run.CEILING - 0.3:
			z.y -= hi - (Run.CEILING - 0.3)
	else:
		z.y = clampf(z.y, z.half + 0.3, Run.CEILING - z.half - 0.3)
	hazards.append(z)
	return z


## A zapper standing from the floor (or hanging from the ceiling) up to a
## height, so the gap is above (or below) it.
func zapper_floor(xm: float, lane: int, top: float) -> Zapper:
	return zapper(xm, top * 0.5 + 0.15, lane, maxf(top - 0.3, 0.6), 90.0)


func zapper_ceiling(xm: float, lane: int, bottom: float) -> Zapper:
	var len := Run.CEILING - bottom - 0.3
	return zapper(xm, bottom + len * 0.5, lane, maxf(len, 0.6), 90.0)


## A laser that starts charging when the run reaches xm.
func laser(xm: float, y: float, lane: int, charge := 1.6, fire := 0.9) -> Laser:
	var l := Laser.new()
	l.id = _id()
	l.x = x0 + xm
	l.trigger = x0 + xm
	l.y = y
	l.lane = lane if lanes else 1
	l.charge = charge
	l.fire = fire
	hazards.append(l)
	return l


## A seeker that starts its warning when the run reaches xm. lane -1 goes
## after the pilot's lane.
func seeker(xm: float, lane := -1) -> Seeker:
	var s := Seeker.new()
	s.id = _id()
	s.x = x0 + xm
	s.trigger = x0 + xm
	s.want_lane = (lane if lanes else 1) if lane >= 0 else -1
	hazards.append(s)
	return s


func shutter(xm: float, lane: int, lead := 0.85) -> Shutter:
	var s := Shutter.new()
	s.id = _id()
	s.x = x0 + xm
	s.lane = lane if lanes else 1
	s.lead = lead
	hazards.append(s)
	return s


## An eye drone that flies in when the run reaches xm.
func eye(xm: float, lane: int) -> EyeDrone:
	var e := EyeDrone.new()
	e.id = _id()
	e.trigger = x0 + xm
	e.x = x0 + xm + EyeDrone.AHEAD
	e.lane = lane if lanes else 1
	hazards.append(e)
	return e


## A gun drone hanging at (xm, y) in lane 0 or 2, firing across the lanes.
func gun(xm: float, lane: int, y: float, shots := 3) -> GunDrone:
	var g := GunDrone.new()
	g.id = _id()
	g.x = x0 + xm
	g.y = y
	g.lane = lane if lanes else 1
	g.shots = shots
	hazards.append(g)
	return g


## A walking robot pacing either side of xm: raptor or trilobite, on the
## floor or hanging from the ceiling.
func walker(xm: float, lane: int, body := "raptor", ceiling := false, pace := 2.0) -> Walker:
	var w := Walker.new()
	w.id = _id()
	w.x = x0 + xm
	w.lane = lane if lanes else 1
	w.pace = pace
	w.setup(body, ceiling)
	w.y = Run.CEILING - w.size.y if ceiling else 0.0
	hazards.append(w)
	return w


## A QuadOrb that rolls back along its lane once the run reaches xm.
func orb(xm: float, lane: int, roll := 7.0) -> Walker:
	var w := Walker.new()
	w.id = _id()
	w.x = x0 + xm + secs(1.6) + roll * 1.6
	w.lane = lane if lanes else 1
	w.setup("orb")
	w.roll = roll
	w.trigger = x0 + xm
	hazards.append(w)
	return w


# --- Pickups and people ---------------------------------------------------

func credit(xm: float, y: float, lane: int, kind := "credit") -> Pickup:
	var p := Pickup.make(_id(), kind, x0 + xm, clampf(y, 0.5, Run.TOP + 1.2), float(lane if lanes else 1))
	pickups.append(p)
	return p


func big(xm: float, y: float, lane: int) -> Pickup:
	return credit(xm, y, lane, "big")


## A row of credits, rising dy metres each.
func credit_line(xm: float, y: float, lane: int, n: int, step := 1.3, dy := 0.0) -> void:
	for i in n:
		credit(xm + i * step, y + i * dy, lane)


## Credits over a hump `height` tall.
func credit_arc(xm: float, y: float, lane: int, n: int, height := 2.0, step := 1.3) -> void:
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		credit(xm + i * step, y + sin(t * PI) * height, lane)


## Credits in a wave.
func credit_wave(xm: float, y: float, lane: int, n: int, amp := 1.5, step := 1.2, period := 8.0) -> void:
	for i in n:
		credit(xm + i * step, y + sin(i * TAU / period) * amp, lane)


## Credits drawn from rows of text: "#" is a credit, "@" a big chip, the
## first row is the top. Each cell is 0.9 m.
func credit_shape(xm: float, top_y: float, lane: int, rows: Array) -> void:
	for r in rows.size():
		var row: String = rows[r]
		for c in row.length():
			var ch := row[c]
			if ch == "#":
				credit(xm + c * 0.9, top_y - r * 0.9, lane)
			elif ch == "@":
				big(xm + c * 0.9, top_y - r * 0.9, lane)


## A vehicle crate on the floor.
func crate(xm: float, lane: int, vehicle := "raptor") -> Pickup:
	var p := Pickup.make(_id(), "crate", x0 + xm, 0.7, float(lane if lanes else 1))
	p.vehicle = vehicle
	pickups.append(p)
	return p


## A member of staff on the floor. `job` is scientist, guard, exec or tech.
func worker(xm: float, lane: int, job := "scientist") -> void:
	staff.append({
		"id": _id(), "x": x0 + xm, "lane": lane if lanes else rng.randi_range(0, 2),
		"job": job, "female": rng.randf() < 0.5, "seed": rng.randi(), "knocked": -1.0, "by": -1,
		"mood": ["run", "cower", "phone", "idle"][rng.randi() % 4],
	})


func prop(model: String, xm: float, lane := -1, y := 0.0, yaw := 0.0) -> void:
	props.append([model, x0 + xm, lane, y, yaw])
