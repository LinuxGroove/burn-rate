class_name Patterns
extends RefCounted
## The hazard layouts rooms are made from. Each pattern is a static function
## that fills a [RoomGen]: it sets the room's length with fit() and places
## hazards, credits, crates and staff with x in metres from the room's start.
## [Zones] lists which patterns each zone uses and how often.
##
## Every pattern must leave a way through for a pilot who flies well, in
## every lane setting it's listed for: tests fly the expert bot through each
## one at full difficulty. Rules of thumb:
##   - a pilot needs a gap of about 2.6 m between zappers to fit through, and
##     3 m or more is fair;
##   - space things that need a big climb or drop at least r.secs(0.75) apart,
##     and lane-forcing things r.secs(0.5);
##   - with lanes off (r.lanes false) every hazard is in lane 1, so a pattern
##     that's listed for Classic must leave a height gap at every point.

## Patterns that need lanes (they're skipped in Classic).
const LANES_ONLY := ["zap_slalom", "zap_cross", "shutter_run", "skim_alley", "thread_needle", "gun_post", "eye_patrol", "orb_roll", "lane_maze"]


static var _script: GDScript


static func make(name: String, r: RoomGen) -> void:
	r.pattern = name
	if _script == null:
		_script = load("res://game/run/patterns.gd")
	if not _has(name):
		push_error("Patterns: no pattern %s" % name)
		breather(r)
		return
	_script.call(name, r)


static func _has(name: String) -> bool:
	for m in _script.get_script_method_list():
		if str(m.name) == name:
			return true
	return false


# --- Calm rooms ------------------------------------------------------------

## Credits and nothing much else: a breath between the hard rooms.
static func breather(r: RoomGen) -> void:
	r.fit(r.secs(2.4))
	var lane := r.lane_any()
	r.credit_wave(4.0, r.rng.randf_range(2.0, 4.0), lane, int((r.length - 8.0) / 1.2), 1.4)
	if r.lanes and r.chance(0.5):
		var other: int = r.others(lane)[0]
		r.credit_line(8.0, r.rng.randf_range(1.0, 5.0), other, 8)
	for i in r.rng.randi_range(0, 2):
		r.worker(r.rng.randf_range(4.0, r.length - 4.0), r.lane_any(), ["scientist", "tech", "exec"][r.rng.randi() % 3])


## Desks and staff, a few low zappers and credits: knock people flat.
static func office(r: RoomGen) -> void:
	r.fit(r.secs(2.6))
	r.tags["office"] = true
	var n := r.rng.randi_range(3, 6)
	for i in n:
		r.worker(r.rng.randf_range(3.0, r.length - 3.0), r.lane_any(), ["scientist", "scientist", "tech", "exec"][r.rng.randi() % 4])
	var x := r.secs(0.9)
	while x < r.length - 4.0:
		var lane := r.lane_any()
		r.zapper(x, r.rng.randf_range(4.8, 6.6), lane, r.rng.randf_range(1.6, 2.4), r.rng.randf_range(0.0, 30.0))
		r.credit_line(x - 2.0, 1.4, lane, 4)
		x += r.secs(r.by_d(1.3, 0.9))


# --- Zappers --------------------------------------------------------------

## Upright zappers with a gap above, below or between, one after another.
static func zap_gates(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 3 + int(r.d * 3.0))
	var space := r.secs(r.by_d(1.15, 0.78))
	r.fit(space * count + 8.0)
	var x := 6.0
	var gap := r.by_d(3.4, 2.75)
	for i in count:
		var lane := r.lane_any()
		var mid := r.rng.randf_range(gap * 0.5 + 0.2, Run.CEILING - gap * 0.5 - 0.3)
		var lo := mid - gap * 0.5
		var hi := mid + gap * 0.5
		if lo > 0.9:
			r.zapper_floor(x, lane, lo)
		if hi < Run.CEILING - 0.9:
			r.zapper_ceiling(x, lane, hi)
		r.credit_line(x - 1.3, mid - 0.4, lane, 3)
		# With lanes, sometimes the next lane is shut at another height.
		if r.lanes and r.d > 0.35 and r.chance(0.45):
			var other: int = r.others(lane)[0]
			if mid > 4.0:
				r.zapper_floor(x + 0.8, other, 4.2)
			else:
				r.zapper_ceiling(x + 0.8, other, 3.6)
		x += space


## Zappers lying flat at different heights.
static func zap_flat(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 4 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.05, 0.72))
	r.fit(space * count + 10.0)
	var x := 7.0
	var last_high := r.chance(0.5)
	for i in count:
		var lane := r.lane_any()
		var high := not last_high if r.chance(0.7) else last_high
		last_high = high
		var y := r.rng.randf_range(4.2, 5.8) if high else r.rng.randf_range(1.7, 2.9)
		var len := r.by_d(3.0, 4.6)
		r.zapper(x, y, lane, len, r.rng.randf_range(-8.0, 8.0))
		# Credits on the safe side.
		r.credit_line(x - len * 0.5, y - 2.0 if high else y + 2.1, lane, int(len / 1.2) + 1)
		x += space


## Zappers leaning across the room at 45 degrees.
static func zap_diag(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 4 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.1, 0.8))
	r.fit(space * count + 8.0)
	var x := 7.0
	for i in count:
		var lane := r.lane_any()
		var up := r.chance(0.5)
		var len := r.by_d(3.4, 4.6)
		var y := r.rng.randf_range(2.2, 5.6)
		r.zapper(x, y, lane, len, 45.0 if up else -45.0)
		x += space
	r.credit_wave(6.0, 3.5, r.lane_any(), int((r.length - 8.0) / 1.5), 2.5, 1.5)


## A long zapper turning slowly, with credits around it.
static func zap_spinner(r: RoomGen) -> void:
	r.fit(r.secs(r.by_d(2.6, 2.0)) + 10.0)
	var x := r.length * 0.5
	var lane := r.lane_any()
	var len := r.by_d(3.4, 4.6)
	var dir := 1.0 if r.chance(0.5) else -1.0
	r.zapper(x, 4.0, lane, len, r.rng.randf_range(0.0, 180.0), {"spin": dir * r.by_d(55.0, 95.0)})
	for i in 12:
		var a := TAU * i / 12.0
		r.credit(x + cos(a) * (len * 0.5 + 1.4), 4.0 + sin(a) * (len * 0.5 + 1.2), lane)
	if r.lanes:
		var other: int = r.others(lane)[0]
		r.credit_line(x - 6.0, 4.0, other, 10)
		if r.d > 0.5:
			r.zapper(x - 4.0, r.rng.randf_range(2.0, 6.0), r.others(lane)[1], 3.2, 90.0, {"spin": -dir * 70.0})


## Zappers riding up and down on rails.
static func zap_bob(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 5)
	var space := r.secs(r.by_d(1.2, 0.85))
	r.fit(space * count + 8.0)
	var x := 7.0
	for i in count:
		var lane := r.lane_any()
		r.zapper(x, 4.0, lane, r.by_d(2.0, 2.8), 0.0 if r.chance(0.6) else 90.0, {"bob": r.by_d(1.4, 2.2), "bob_period": r.rng.randf_range(1.6, 2.6)})
		x += space
	r.credit_line(5.0, 4.0, r.lane_any(), int((r.length - 8.0) / 1.4), 1.4)


## Credits shaped like the Kestrel K, or an arrow, guarded by a zapper.
static func credit_word(r: RoomGen) -> void:
	r.fit(r.secs(2.4) + 6.0)
	var shapes := [
		["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
		["   #   ", "    #  ", "#######", "    #  ", "   #   "],
		[" ### ", "#   #", "# @ #", "#   #", " ### "],
	]
	var lane := r.lane_any()
	r.credit_shape(6.0, 5.6, lane, shapes[r.rng.randi() % shapes.size()])
	r.zapper(r.length - 6.0, r.rng.randf_range(2.0, 6.0), lane, 2.4, 90.0)


# --- Lanes ----------------------------------------------------------------

## Full-height zappers fill two lanes; the open lane moves each time.
static func zap_slalom(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 3 + int(r.d * 3.0))
	var space := r.secs(r.by_d(1.0, 0.62))
	r.fit(space * count + 8.0)
	var x := 7.0
	var open := r.rng.randi_range(0, 2)
	for i in count:
		for l in r.others(open):
			r.zapper(x, 4.0, l, 7.2, 90.0)
		r.credit_line(x - 2.0, r.rng.randf_range(1.0, 5.0), open, 3, 1.0)
		var next := open
		while next == open:
			next = r.rng.randi_range(0, 2)
		# Never ask for the far lane straight from the near one at speed.
		if absi(next - open) == 2 and r.d > 0.6:
			next = 1
		open = next
		x += space


## Zappers standing across two lanes at once, one end in each.
static func zap_cross(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 4 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.1, 0.8))
	r.fit(space * count + 8.0)
	var x := 7.0
	for i in count:
		var la := r.rng.randi_range(0, 1)
		var lb := la + 1
		if r.chance(0.5):
			var t := la
			la = lb
			lb = t
		var y := r.rng.randf_range(2.0, 6.0)
		r.zapper(x, y, la, r.by_d(3.0, 4.2), r.rng.randf_range(20.0, 160.0), {"lane_b": lb})
		var free := 2 if mini(la, lb) == 0 else 0
		r.credit_line(x - 1.5, y, free, 3)
		x += space


## Blast doors slam shut lane by lane.
static func shutter_run(r: RoomGen) -> void:
	var count := r.rng.randi_range(3, 3 + int(r.d * 3.0))
	var space := r.secs(r.by_d(1.0, 0.7))
	r.fit(space * count + 8.0)
	r.tags["doors"] = true
	var x := 7.0
	var open := r.rng.randi_range(0, 2)
	for i in count:
		var shut := r.others(open)
		r.shutter(x, shut[0], r.by_d(1.0, 0.75))
		if r.d > 0.4 and r.chance(0.6):
			r.shutter(x, shut[1], r.by_d(1.0, 0.75))
		r.credit_line(x - 2.5, r.rng.randf_range(1.0, 5.5), open, 3, 1.0)
		var next := r.rng.randi_range(0, 2)
		if absi(next - open) == 2:
			next = 1
		open = next
		x += space


## A zapper line right beside a credit line in the next lane: skim it.
static func skim_alley(r: RoomGen) -> void:
	r.fit(r.secs(r.by_d(2.6, 2.0)) + 8.0)
	var lane := r.rng.randi_range(0, 2)
	var beside: int = 1 if lane != 1 else (0 if r.chance(0.5) else 2)
	var y := r.rng.randf_range(2.0, 5.0)
	var len := r.length - 12.0
	var n := int(len / 4.2)
	for i in n:
		r.zapper(6.0 + i * 4.2 + 2.0, y, beside, 3.8, 0.0)
	r.credit_line(6.0, y, lane, int(len / 1.2), 1.2)
	r.big(r.length - 4.0, y, lane)


## Zappers in all three lanes, each with its gap at a different height.
static func thread_needle(r: RoomGen) -> void:
	var count := r.rng.randi_range(2, 3 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.5, 1.0))
	r.fit(space * count + 8.0)
	var x := 7.0
	var gap := r.by_d(4.0, 2.9)
	# The gaps step one lane across from column to column, so you can hold
	# your height and change lane, or hold your lane and change height.
	var heights := r.shuffled([1.9, 4.0, 6.0])
	for i in count:
		if i > 0:
			if r.rng.randf() < 0.5:
				heights.push_back(heights.pop_front())
			else:
				heights.push_front(heights.pop_back())
		for l in 3:
			var mid: float = clampf(float(heights[l]) + r.rng.randf_range(-0.3, 0.3), gap * 0.5 + 0.3, Run.CEILING - gap * 0.5 - 0.3)
			var lo: float = mid - gap * 0.5
			var hi: float = mid + gap * 0.5
			if lo > 0.9:
				r.zapper_floor(x + l * 0.4, l, lo)
			if hi < Run.CEILING - 0.9:
				r.zapper_ceiling(x + l * 0.4, l, hi)
		r.big(x, float(heights[1]), 1)
		x += space


## A maze of short zappers: weave between lanes.
static func lane_maze(r: RoomGen) -> void:
	var cols := r.rng.randi_range(4, 5 + int(r.d * 3.0))
	var space := r.secs(r.by_d(1.0, 0.55))
	r.fit(space * cols + 8.0)
	var x := 7.0
	var open := r.rng.randi_range(0, 2)
	for i in cols:
		for l in 3:
			if l == open:
				continue
			if r.chance(0.75):
				r.zapper(x, 4.0, l, 7.2, 90.0)
		r.credit(x, 4.0, open)
		if r.chance(0.6):
			open = clampi(open + (1 if r.chance(0.5) else -1), 0, 2)
		x += space


# --- Lasers and seekers ---------------------------------------------------

## Lasers charge and fire across lanes and heights.
static func laser_bank(r: RoomGen) -> void:
	var waves := r.rng.randi_range(2, 3 + int(r.d * 2.0))
	var wave_len := r.secs(r.by_d(2.3, 1.7))
	r.fit(wave_len * waves + 8.0)
	var x := 4.0
	for w in waves:
		var n := 1 + int(r.d * 2.0) + (1 if r.chance(0.3) else 0)
		var used := {}
		for i in n:
			var lane := r.lane_any()
			var y: float = [1.0, 3.6, 6.2][r.rng.randi() % 3]
			var key := "%d/%.1f" % [lane, y]
			if used.has(key):
				continue
			# One lane always keeps a clear band: never three heights in one lane.
			var in_lane := 0
			for k in used:
				if str(k).begins_with("%d/" % lane):
					in_lane += 1
			if in_lane >= 1:
				continue
			used[key] = true
			r.laser(x, y, lane, r.by_d(1.7, 1.25))
		r.credit_line(x + 4.0, r.rng.randf_range(2.0, 5.0), r.lane_any(), 6)
		x += wave_len


## Seekers, one or a salvo, with credits to chase meanwhile.
static func seeker_salvo(r: RoomGen) -> void:
	var n := r.rng.randi_range(1, 1 + int(r.d * 3.0))
	var space := r.secs(r.by_d(1.4, 0.75))
	r.fit(space * n + r.secs(2.0))
	var x := 4.0
	for i in n:
		r.seeker(x, -1 if r.chance(0.7) else r.lane_any())
		x += space
	r.credit_wave(6.0, 3.6, r.lane_any(), int((r.length - 8.0) / 1.3), 2.0, 1.3)


## Zappers and a seeker at once.
static func zap_seeker(r: RoomGen) -> void:
	zap_flat(r)
	r.seeker(r.length * 0.3)
	if r.d > 0.6:
		r.seeker(r.length * 0.65)


# --- Robots -----------------------------------------------------------------

## Halberd's eye drones fly in and dash along the lanes.
static func eye_patrol(r: RoomGen) -> void:
	var n := r.rng.randi_range(1, 2 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.5, 0.9))
	r.fit(space * n + r.secs(2.2))
	var x := 4.0
	for i in n:
		r.eye(x, r.rng.randi_range(0, 2))
		x += space
	r.credit_line(6.0, 2.0, r.lane_any(), int((r.length - 10.0) / 1.4), 1.4)


## A gun drone in the near or far lane fires bolts across the room.
static func gun_post(r: RoomGen) -> void:
	r.fit(r.secs(3.0) + 10.0)
	var lane := 2 if r.chance(0.6) else 0
	r.gun(r.length * 0.55, lane, r.rng.randf_range(3.0, 5.6), 2 + int(r.d * 2.0))
	r.credit_line(4.0, r.rng.randf_range(1.0, 5.0), 1, int(r.length * 0.4 / 1.3))
	if r.d > 0.5:
		r.zapper(r.length * 0.3, r.rng.randf_range(2.0, 6.0), 1, 2.6, 90.0)


## Walkers on the floor and hanging from the ceiling rails, credits between.
static func walkers(r: RoomGen) -> void:
	var n := r.rng.randi_range(2, 3 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.2, 0.85))
	r.fit(space * n + 8.0)
	r.tags["rails"] = true
	var x := 7.0
	for i in n:
		var lane := r.lane_any()
		var ceiling := r.chance(0.4)
		var body := "trilobite" if r.chance(0.4) else "raptor"
		r.walker(x, lane, body, ceiling, r.rng.randf_range(0.8, 2.2))
		r.credit_line(x - 1.5, 4.0 if not ceiling else 1.6, lane, 3)
		x += space


## QuadOrbs roll at you along the floor.
static func orb_roll(r: RoomGen) -> void:
	var n := r.rng.randi_range(2, 3 + int(r.d * 2.0))
	var space := r.secs(r.by_d(1.0, 0.6))
	r.fit(space * n + r.secs(2.5))
	var x := 4.0
	for i in n:
		r.orb(x, r.rng.randi_range(0, 2), r.by_d(3.5, 7.5))
		x += space
	r.credit_arc(8.0, 2.0, r.lane_any(), 10, 2.5)
	if r.d > 0.4:
		r.zapper(r.length * 0.5, 6.4, r.lane_any(), 3.0, 0.0)


## A vehicle crate, with something worth riding it into.
static func crate_room(r: RoomGen) -> void:
	r.fit(r.secs(3.0) + 8.0)
	var lane := r.lane_any()
	var kinds := Zones.vehicles(r.zone)
	r.crate(6.0, lane, kinds[r.rng.randi() % kinds.size()])
	var x := 6.0 + r.secs(1.4)
	while x < r.length - 4.0:
		var l := r.lane_any()
		if r.chance(0.5) and r.zone != "lab":
			r.walker(x, l, "trilobite", false, 0.5)
		else:
			r.zapper(x, r.rng.randf_range(4.5, 6.5), l, 2.4, 0.0)
		r.credit_line(x - 2.0, 2.4, l, 3)
		x += r.secs(1.1)


# --- The first flight -----------------------------------------------------

static func tut_fly(r: RoomGen) -> void:
	r.tip = "Hold [fly] to fly. Let go to fall."
	r.fit(r.secs(4.0))
	r.credit_line(8.0, 1.0, 1, 5, 1.3, 0.7)
	r.credit_line(15.0, 4.5, 1, 10, 1.3)
	r.credit_line(28.0, 4.5, 1, 6, 1.3, -0.6)


static func tut_climb(r: RoomGen) -> void:
	r.tip = "Fly over the zappers, or drop under them."
	r.fit(r.secs(5.0))
	r.zapper_floor(r.secs(1.2), 1, 3.0)
	r.credit_arc(r.secs(1.2) - 3.0, 4.2, 1, 6, 1.0)
	r.zapper_ceiling(r.secs(2.8), 1, 3.6)
	r.credit_line(r.secs(2.8) - 2.0, 1.0, 1, 4)
	r.zapper(r.secs(4.2), 4.0, 1, 3.0, 0.0)


static func tut_lanes(r: RoomGen) -> void:
	r.tip = "[lane_back] and [lane_forward] change lane. Three lanes, near to far."
	r.fit(r.secs(5.5))
	r.zapper(r.secs(1.6), 4.0, 1, 7.2, 90.0)
	r.credit_line(r.secs(1.6) - 3.0, 3.0, 2, 5)
	r.credit_line(r.secs(1.6) - 3.0, 3.0, 0, 5)
	if r.lanes:
		r.zapper(r.secs(3.4), 4.0, 0, 7.2, 90.0)
		r.zapper(r.secs(3.4), 4.0, 2, 7.2, 90.0)
		r.credit_line(r.secs(3.4) - 3.0, 3.0, 1, 5)


static func tut_burn(r: RoomGen) -> void:
	r.tip = "Fly close to danger to build Burn. Burn multiplies your credits. Touch the floor and it's gone."
	r.fit(r.secs(6.0))
	for i in 4:
		r.zapper(r.secs(1.2 + i * 1.1), 2.2, 1 if not r.lanes else 2, 2.6, 0.0)
		r.credit_line(r.secs(1.2 + i * 1.1) - 2.0, 3.4 if not r.lanes else 2.2, 1, 4)


static func tut_seeker(r: RoomGen) -> void:
	r.tip = "A seeker locks on to your height. Move when it locks."
	r.fit(r.secs(5.0))
	r.seeker(r.secs(0.6), 1)
	r.credit_wave(r.secs(0.6), 3.5, 1, 20, 2.0, 1.4)


static func tut_crate(r: RoomGen) -> void:
	r.tip = "Grab a crate to hijack a robot. It takes the next hit for you. Tap [fly] to jump."
	r.fit(r.secs(6.0))
	r.crate(8.0, 1, "raptor")
	r.walker(r.secs(2.6), 1, "trilobite", false, 0.6)
	r.walker(r.secs(4.2), 1, "trilobite", false, 0.6)
	r.credit_line(r.secs(2.0), 3.0, 1, 8)


static func tut_end(r: RoomGen) -> void:
	r.tip = "That's it. The rest is how far you get."
	r.tags["finish"] = true
	r.fit(48.0)
	r.credit_shape(8.0, 5.0, 1, ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"])
