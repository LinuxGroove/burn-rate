class_name Courses
extends RefCounted
## The thirty hand-picked courses, five in each zone: a fixed length, a
## seed, a list of patterns and a difficulty that rises along it. Courses
## are raced against the clock: Burn makes you faster, so the medal times
## come from how much Burn you keep.

## Burn level you'd average for each medal (worked out from the course).
const MEDAL_BURN := {"bronze": 1.0, "silver": 2.4, "gold": 3.6, "patrol": 4.4}
const MEDALS := ["patrol", "gold", "silver", "bronze"]
const MEDAL_NAMES := {"patrol": "Kestrel", "gold": "Gold", "silver": "Silver", "bronze": "Bronze"}

## [id, name, zone, length, d0, d1, patterns]
const LIST := [
	["lab_1", "First Light", "lab", 700.0, 0.0, 0.25, ["zap_gates", "breather", "zap_flat"]],
	["lab_2", "Coffee Run", "lab", 800.0, 0.1, 0.35, ["office", "zap_flat", "zap_gates"]],
	["lab_3", "Lane Change", "lab", 900.0, 0.15, 0.45, ["zap_slalom", "skim_alley", "zap_gates"]],
	["lab_4", "Close Shave", "lab", 1000.0, 0.25, 0.55, ["skim_alley", "zap_diag", "zap_gates", "zap_slalom"]],
	["lab_5", "Prototype Day", "lab", 1100.0, 0.3, 0.65, ["zap_spinner", "seeker_salvo", "crate_room", "zap_gates"]],
	["servers_1", "Cold Aisle", "servers", 900.0, 0.2, 0.45, ["laser_bank", "zap_gates"]],
	["servers_2", "Hot Aisle", "servers", 1000.0, 0.25, 0.55, ["zap_bob", "laser_bank", "zap_flat"]],
	["servers_3", "Rack and Ruin", "servers", 1000.0, 0.3, 0.6, ["thread_needle", "lane_maze", "zap_gates"]],
	["servers_4", "Packet Loss", "servers", 1100.0, 0.35, 0.7, ["seeker_salvo", "zap_seeker", "laser_bank"]],
	["servers_5", "Overclocked", "servers", 1300.0, 0.45, 0.85, []],
	["bay_1", "Charging Station", "bay", 900.0, 0.25, 0.5, ["walkers", "crate_room", "zap_gates"]],
	["bay_2", "Rolling Stock", "bay", 1000.0, 0.3, 0.6, ["orb_roll", "walkers"]],
	["bay_3", "Lockdown", "bay", 1000.0, 0.35, 0.65, ["shutter_run", "zap_cross", "shutter_run", "walkers"]],
	["bay_4", "Hijack", "bay", 1100.0, 0.4, 0.7, ["crate_room", "gun_post", "walkers"]],
	["bay_5", "Scrap Heap", "bay", 1300.0, 0.5, 0.9, []],
	["atrium_1", "Glass Ceiling", "atrium", 900.0, 0.3, 0.55, ["zap_spinner", "zap_bob"]],
	["atrium_2", "Eyes Up", "atrium", 1000.0, 0.35, 0.65, ["eye_patrol", "breather", "eye_patrol", "zap_cross"]],
	["atrium_3", "Crossfire", "atrium", 1100.0, 0.4, 0.7, ["zap_cross", "laser_bank"]],
	["atrium_4", "Mezzanine", "atrium", 1100.0, 0.45, 0.75, ["skim_alley", "credit_word", "zap_spinner"]],
	["atrium_5", "Open Plan", "atrium", 1300.0, 0.55, 0.95, []],
	["downtown_1", "Rooftops", "downtown", 1000.0, 0.4, 0.65, ["zap_gates", "breather", "zap_flat"]],
	["downtown_2", "Fire Escape", "downtown", 1100.0, 0.45, 0.75, ["zap_diag", "zap_flat", "zap_gates"]],
	["downtown_3", "Air Traffic", "downtown", 1200.0, 0.5, 0.8, ["seeker_salvo", "eye_patrol"]],
	["downtown_4", "Neon Mile", "downtown", 1300.0, 0.55, 0.9, ["zap_slalom", "zap_seeker", "zap_diag"]],
	["downtown_5", "Last Train", "downtown", 1500.0, 0.6, 1.0, []],
	["halberd_1", "Front Desk", "halberd", 1100.0, 0.55, 0.8, ["gun_post", "shutter_run"]],
	["halberd_2", "Armoury", "halberd", 1200.0, 0.6, 0.85, ["walkers", "orb_roll", "gun_post"]],
	["halberd_3", "Firing Range", "halberd", 1300.0, 0.65, 0.95, ["laser_bank", "gun_post", "zap_seeker"]],
	["halberd_4", "Kill Switch", "halberd", 1400.0, 0.7, 1.0, ["thread_needle", "lane_maze", "shutter_run"]],
	["halberd_5", "Everything at Once", "halberd", 1600.0, 0.8, 1.1, []],
]

static var _defs := {}


static func ids() -> Array:
	var out := []
	for e in LIST:
		out.append(e[0])
	return out


static func get_def(id: String) -> Dictionary:
	if _defs.is_empty():
		for e in LIST:
			_defs[e[0]] = {
				"id": e[0], "name": e[1], "zone": e[2], "length": e[3], "d0": e[4], "d1": e[5],
				"patterns": e[6], "seed": hash(["course", e[0]]),
			}
	return _defs.get(id, _defs.get(str(LIST[0][0])))


static func in_zone(zone: String) -> Array:
	var out := []
	for e in LIST:
		if e[2] == zone:
			out.append(e[0])
	return out


## The time to finish a course holding an average Burn level, at a pace.
static func time_for(id: String, burn: float, pace := "normal") -> float:
	var d := get_def(id)
	var t := 0.0
	var x := Course.START_X
	var step := 2.0
	var mult := 1.0 + Run.BURN_SPEED * (burn - 1.0)
	while x < float(d.length):
		t += step / (Run.pace_speed(pace, x) * mult)
		x += step
	return t


## Medal times: {"patrol": s, "gold": s, "silver": s, "bronze": s}.
static func medal_times(id: String, pace := "normal") -> Dictionary:
	var out := {}
	for m in MEDAL_BURN:
		out[m] = snappedf(time_for(id, float(MEDAL_BURN[m]), pace), 0.01)
	# Bronze is for finishing at all.
	out["bronze"] = snappedf(time_for(id, 1.0, pace) + 0.01, 0.01)
	return out


## The best medal a time earns, or "".
static func medal_for(id: String, t: float, pace := "normal") -> String:
	var times := medal_times(id, pace)
	for m in MEDALS:
		if t <= float(times[m]):
			return m
	return ""
