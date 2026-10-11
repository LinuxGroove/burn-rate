class_name Ghost
extends RefCounted
## A pilot's flight as samples at 20 Hz (where they were, how they were
## flying), to fly beside you again as a ghost: your best Daily Flight of
## the day and your best time on each course. Recorded from the [Pilot]
## every tick by RunScene; a few kilobytes gzipped for a whole run.

const RATE := 20.0
## Floats per sample: time, x, y, lane, flags.
const STRIDE := 5
## Flags.
const FLYING := 1
const FLOOR := 2
const CRASHED := 4
const DONE := 8
## The vehicle's index (in VEHICLES, 1-based) sits above these bits.
const VEHICLE_SHIFT := 4
const VEHICLES := ["raptor", "shell", "eye", "gunner"]

var data := PackedFloat32Array()
## Who flew it, for the tag and the look.
var name := ""
var pack := "k1"
var look := {}
## The run it came from: distance, or a course time.
var distance := 0.0
var time := 0.0
var _next_t := 0.0


## Adds a sample if one is due at run time `t`.
func record(p: Pilot, t: float) -> void:
	if t + 0.0001 < _next_t:
		return
	_next_t = t + 1.0 / RATE
	var flags := 0
	if p.flying:
		flags |= FLYING
	if p.on_floor:
		flags |= FLOOR
	if p.state == Pilot.State.CRASH:
		flags |= CRASHED
	elif p.state == Pilot.State.DONE:
		flags |= DONE
	var v := VEHICLES.find(p.vehicle) + 1
	flags |= v << VEHICLE_SHIFT
	data.append_array(PackedFloat32Array([t, p.x, p.y, p.lane, float(flags)]))
	distance = maxf(distance, p.x)
	time = t


func count() -> int:
	return data.size() / STRIDE


func is_empty() -> bool:
	return data.size() < STRIDE * 2


## Where the ghost was at run time `t`: {x, y, lane, flying, on_floor,
## state ("fly", "crash", "done"), vehicle}, or {} once it's past the end.
func sample(t: float) -> Dictionary:
	var n := count()
	if n == 0:
		return {}
	var last := n - 1
	if t >= data[last * STRIDE] + 1.0:
		return {}
	# Samples are evenly spaced, so jump straight to the right one.
	var i := clampi(int((t - data[0]) * RATE), 0, last)
	while i > 0 and data[i * STRIDE] > t:
		i -= 1
	while i < last and data[(i + 1) * STRIDE] <= t:
		i += 1
	var j := mini(i + 1, last)
	var a := i * STRIDE
	var b := j * STRIDE
	var span := data[b] - data[a]
	var f := clampf((t - data[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var flags := int(data[a + 4])
	var state := "fly"
	if flags & DONE:
		state = "done"
	elif flags & CRASHED:
		state = "crash"
	var vi := flags >> VEHICLE_SHIFT
	return {
		"x": lerpf(data[a + 1], data[b + 1], f),
		"y": lerpf(data[a + 2], data[b + 2], f),
		"lane": lerpf(data[a + 3], data[b + 3], f),
		"flying": bool(flags & FLYING), "on_floor": bool(flags & FLOOR),
		"state": state, "vehicle": VEHICLES[vi - 1] if vi > 0 and vi <= VEHICLES.size() else "",
	}


## Moves a stand-in pilot to the ghost's place at `t`; false once it's done.
func pose(p: Pilot, t: float) -> bool:
	var s := sample(t)
	if s.is_empty():
		return false
	p.x = s.x
	p.y = s.y
	p.lane = s.lane
	p.lane_to = int(round(s.lane))
	p.flying = s.flying
	p.on_floor = s.on_floor
	p.vehicle = s.vehicle
	match str(s.state):
		"crash":
			p.state = Pilot.State.CRASH
		"done":
			p.state = Pilot.State.DONE
		_:
			p.state = Pilot.State.FLY
	return true


func to_dict() -> Dictionary:
	return {"v": 1, "data": data, "name": name, "pack": pack, "look": look, "distance": distance, "time": time}


static func from_dict(d: Dictionary) -> Ghost:
	var g := Ghost.new()
	g.data = d.get("data", PackedFloat32Array())
	g.name = str(d.get("name", ""))
	g.pack = str(d.get("pack", "k1"))
	g.look = d.get("look", {})
	g.distance = float(d.get("distance", 0.0))
	g.time = float(d.get("time", 0.0))
	return g


func save(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return false
	f.store_var(to_dict())
	return true


static func load_from(path: String) -> Ghost:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return null
	var d = f.get_var()
	if not d is Dictionary:
		return null
	var g := from_dict(d)
	return null if g.is_empty() else g
