class_name Zones
extends RefCounted
## The tower's zones, in the order a run passes through them, and the
## patterns each one uses. A run loops through all six, faster each time.

const ORDER := ["lab", "servers", "bay", "atrium", "downtown", "halberd"]

## name: what the HUD calls it; length: metres; vehicles: crates found there;
## patterns: [pattern, weight, lowest difficulty].
const INFO := {
	"lab": {
		"name": "Test Lab", "floor": "Floor 41", "length": 450.0,
		"vehicles": ["raptor"],
		"patterns": [
			["breather", 2.0, 0.0], ["office", 2.0, 0.0], ["zap_gates", 4.0, 0.0], ["zap_flat", 3.0, 0.0],
			["zap_diag", 2.0, 0.1], ["credit_word", 1.0, 0.0], ["zap_slalom", 2.0, 0.05], ["skim_alley", 1.5, 0.05],
			["seeker_salvo", 1.5, 0.15], ["crate_room", 1.0, 0.12], ["zap_spinner", 1.0, 0.2],
		],
	},
	"servers": {
		"name": "Server Hall", "floor": "Floor 40", "length": 550.0,
		"vehicles": ["raptor", "eye"],
		"patterns": [
			["breather", 1.0, 0.0], ["zap_gates", 3.0, 0.0], ["laser_bank", 4.0, 0.0], ["zap_flat", 2.0, 0.0],
			["zap_slalom", 2.0, 0.0], ["thread_needle", 2.0, 0.1], ["seeker_salvo", 2.0, 0.1], ["zap_seeker", 1.5, 0.2],
			["lane_maze", 1.5, 0.2], ["crate_room", 1.0, 0.0], ["zap_bob", 1.5, 0.1],
		],
	},
	"bay": {
		"name": "Robot Bay", "floor": "Floor 39", "length": 550.0,
		"vehicles": ["raptor", "shell", "gunner"],
		"patterns": [
			["breather", 1.0, 0.0], ["walkers", 4.0, 0.0], ["orb_roll", 3.0, 0.0], ["crate_room", 2.5, 0.0],
			["zap_gates", 2.0, 0.0], ["gun_post", 2.0, 0.1], ["shutter_run", 2.0, 0.0], ["zap_cross", 1.5, 0.1],
			["seeker_salvo", 1.0, 0.2],
		],
	},
	"atrium": {
		"name": "The Atrium", "floor": "Floors 30 to 38", "length": 450.0,
		"vehicles": ["eye", "gunner"],
		"patterns": [
			["breather", 1.5, 0.0], ["eye_patrol", 4.0, 0.0], ["zap_spinner", 3.0, 0.0], ["zap_cross", 2.0, 0.0],
			["laser_bank", 2.0, 0.0], ["zap_bob", 2.0, 0.0], ["credit_word", 1.0, 0.0], ["skim_alley", 1.5, 0.0],
			["crate_room", 1.0, 0.0],
		],
	},
	"downtown": {
		"name": "Downtown", "floor": "Over the rooftops", "length": 700.0,
		"vehicles": ["eye", "gunner"],
		"patterns": [
			["breather", 1.5, 0.0], ["zap_gates", 3.0, 0.0], ["zap_flat", 2.0, 0.0], ["seeker_salvo", 3.0, 0.0],
			["eye_patrol", 3.0, 0.0], ["zap_seeker", 2.0, 0.0], ["zap_slalom", 2.0, 0.0], ["zap_diag", 2.0, 0.0],
			["crate_room", 1.0, 0.0],
		],
	},
	"halberd": {
		"name": "Halberd's Floor", "floor": "Floor 12, Halberd Security", "length": 600.0,
		"vehicles": ["raptor", "shell", "gunner"],
		"patterns": [
			["gun_post", 3.0, 0.0], ["walkers", 2.0, 0.0], ["shutter_run", 3.0, 0.0], ["laser_bank", 2.5, 0.0],
			["eye_patrol", 2.0, 0.0], ["thread_needle", 2.0, 0.0], ["lane_maze", 2.0, 0.0], ["orb_roll", 1.5, 0.0],
			["zap_seeker", 2.0, 0.0], ["crate_room", 1.0, 0.0], ["breather", 0.7, 0.0],
		],
	},
}

const VEHICLE_NAMES := {"raptor": "Raptor", "shell": "Shell", "eye": "Eye", "gunner": "Gunner"}


static func info(zone: String) -> Dictionary:
	return INFO.get(zone, INFO["lab"])


static func display_name(zone: String) -> String:
	return str(info(zone).name)


static func vehicles(zone: String) -> Array:
	return info(zone).vehicles


## Picks a pattern for a room in `zone` at difficulty d.
static func pick(zone: String, d: float, lanes: bool, rng: RandomNumberGenerator, avoid := "") -> String:
	var list: Array = info(zone).patterns
	var total := 0.0
	var ok := []
	for e in list:
		var name := str(e[0])
		if float(e[2]) > d or name == avoid:
			continue
		if not lanes and name in Patterns.LANES_ONLY:
			continue
		ok.append(e)
		total += float(e[1])
	if ok.is_empty():
		return "breather"
	var roll := rng.randf() * total
	for e in ok:
		roll -= float(e[1])
		if roll <= 0.0:
			return str(e[0])
	return str(ok[ok.size() - 1][0])
