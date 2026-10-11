class_name Course
extends RefCounted
## The course a run flies: the rooms ahead, made one at a time from the seed
## as the run gets near them. Endless and the Daily Flight loop through the
## tower's zones getting harder; a Course from [Courses] has its own zone,
## patterns and finish; party races start in a zone of the host's choosing.

## Metres in one loop of the tower.
const LOOP := 3300.0
## Where pilots start, in the first room.
const START_X := 6.0

var mode := "endless"
var seed := 1
var lanes := true
var pace := "normal"
var rooms: Array = []
var end_x := 0.0
var finish_x := INF
## Course mode: the course's definition (see Courses).
var def := {}
var _next := 0
var _last_zone := ""
var _last_pattern := ""
var _zone_offset := 0.0
var _script: Array = []
## Speed as if this many metres further on (tools and tests that fly one
## pattern at a time).
var speed_from := 0.0


func _init(config := {}) -> void:
	mode = str(config.get("mode", "endless"))
	seed = int(config.get("seed", 1))
	lanes = bool(config.get("lanes", true))
	pace = str(config.get("pace", "normal"))
	speed_from = float(config.get("speed_from", 0.0))
	if mode == "course":
		def = config.def if config.get("def") is Dictionary else Courses.get_def(str(config.get("course", "")))
		finish_x = float(def.get("length", 1000.0))
		seed = int(def.seed)
	elif mode == "party":
		var z := str(config.get("zone", ""))
		if not z in Zones.ORDER:
			z = Zones.ORDER[absi(seed) % 4]
		_zone_offset = _zone_start(z)
	elif mode == "tutorial":
		_script = ["tut_fly", "tut_climb", "tut_lanes", "tut_burn", "tut_seeker", "tut_crate", "tut_end"]
		finish_x = INF
	if config.has("zone") and mode in ["endless", "daily"]:
		_zone_offset = _zone_start(str(config.zone))


static func _zone_start(zone: String) -> float:
	var at := 0.0
	for z in Zones.ORDER:
		if z == zone:
			return at
		at += float(Zones.info(z).length)
	return 0.0


## The zone at distance x.
func zone_at(x: float) -> String:
	if mode == "course":
		return str(def.get("zone", "lab"))
	var m := fposmod(x + _zone_offset, LOOP)
	for z in Zones.ORDER:
		var len := float(Zones.info(z).length)
		if m < len:
			return z
		m -= len
	return Zones.ORDER[0]


## How hard the course is at distance x (0 to about 1.3).
func difficulty_at(x: float) -> float:
	match mode:
		"course":
			var t := clampf(x / maxf(finish_x, 1.0), 0.0, 1.0)
			return lerpf(float(def.get("d0", 0.2)), float(def.get("d1", 0.6)), t)
		"party":
			return clampf(0.2 + x / 2600.0, 0.0, 1.2)
		"tutorial":
			return 0.0
	return clampf(x / 3000.0, 0.0, 1.0) + maxf(0.0, x - LOOP) / 20000.0


func next_room() -> RoomGen:
	var index := _next
	_next += 1
	var x0 := end_x
	var zone := zone_at(x0 + 1.0)
	var d := difficulty_at(x0)
	var speed := Run.pace_speed(pace, x0 + speed_from)
	var r := RoomGen.new(index, zone, x0, d, speed, lanes, hash([seed, index, "room"]))
	if index == 0:
		_start_room(r)
	elif mode == "tutorial":
		var name: String = _script[mini(index - 1, _script.size() - 1)]
		Patterns.make(name, r)
		if name == "tut_end":
			finish_x = r.x0 + r.length * 0.6
	elif mode == "course" and x0 >= finish_x - 1.0:
		_finish_room(r)
	else:
		var name := ""
		if zone != _last_zone and _last_zone != "":
			r.tags["entry"] = zone
			if _last_zone == "atrium" and zone == "downtown":
				r.tags["window_out"] = true
			elif _last_zone == "downtown":
				r.tags["window_in"] = true
		if mode == "course":
			var list: Array = def.get("patterns", [])
			if not list.is_empty():
				name = str(list[(index - 1) % list.size()])
				if not lanes and name in Patterns.LANES_ONLY:
					name = ""
		if name == "":
			name = Zones.pick(zone, d, lanes, r.rng, _last_pattern)
		Patterns.make(name, r)
		_last_pattern = name
		if r.tags.has("entry"):
			# Nothing right at the door.
			_clear_near_start(r, 6.0)
	if zone == "downtown":
		r.tags["outside"] = true
	_last_zone = zone
	end_x = r.end_x()
	rooms.append(r)
	return r


func _start_room(r: RoomGen) -> void:
	r.pattern = "start"
	r.tags["start"] = true
	r.tags["entry"] = r.zone
	r.fit(44.0 if mode != "party" else 36.0)
	r.credit_line(16.0, 1.2, 1, 6, 1.2, 0.35)
	r.credit_arc(26.0, 3.0, 0 if lanes else 1, 8, 1.5)
	if mode != "party":
		r.worker(3.0, 2, "exec")
		r.worker(12.0, 2, "scientist")
		r.worker(19.0, 0, "scientist")


func _finish_room(r: RoomGen) -> void:
	r.pattern = "finish"
	r.tags["finish"] = true
	r.fit(48.0)
	r.credit_line(4.0, 3.0, 1, 10)


func _clear_near_start(r: RoomGen, metres: float) -> void:
	var keep := []
	for h in r.hazards:
		if h.extent().x > r.x0 + metres:
			keep.append(h)
	r.hazards = keep


## Drops rooms entirely behind x.
func forget_before(x: float) -> void:
	while rooms.size() > 1 and rooms[0].end_x() < x:
		rooms.pop_front()


## The room at x, or null.
func room_at(x: float) -> RoomGen:
	for r in rooms:
		if x >= r.x0 and x < r.end_x():
			return r
	return null
