class_name Flights
extends RefCounted
## The runs the menus start, as RunScene configs: endless, today's Daily
## Flight, a course, the first flight, a party race on one screen and the
## title's backdrop. Each takes the pilot's prototype, suit and gadgets from
## [Progress] and the pace and lanes from the settings.

const DAILY_PACKS := ["k1", "k2", "k3", "k4", "k5", "k6"]


## Today's date in UTC, as "2026-10-11".
static func today() -> String:
	return Time.get_date_string_from_system(true)


## The Daily Flight's seed for a date: the same for everyone, every build.
static func daily_seed(date: String) -> int:
	# String.hash is djb2, stable across platforms; keep it positive.
	return ("burn-rate/daily/" + date).hash() & 0x7fffffff


## The prototype everyone flies on a date.
static func daily_pack(date: String) -> String:
	var parts := date.split("-")
	var day := 0
	if parts.size() == 3:
		day = int(Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}) / 86400)
	return DAILY_PACKS[posmod(day, DAILY_PACKS.size())]


## "Sunday 11 October".
static func date_text(date: String) -> String:
	var parts := date.split("-")
	if parts.size() != 3:
		return date
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])})
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var days := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var months := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	return "%s %d %s" % [days[int(d.weekday)], int(d.day), months[int(d.month) - 1]]


## The local pilot as a run wants them.
static func me(pack := "", gadgets = null) -> Dictionary:
	return {
		"id": 1, "name": Progress.pilot_name(), "pack": pack if pack != "" else Progress.pack(),
		"look": Progress.look(), "gadgets": Progress.gadgets() if gadgets == null else gadgets,
	}


static func pace() -> String:
	return str(LGSettings.get_value("play", "pace", "normal"))


static func lanes() -> bool:
	return bool(LGSettings.get_value("play", "lanes", true))


static func endless() -> Dictionary:
	return {
		"mode": "endless", "seed": randi(), "pace": pace(), "lanes": lanes(),
		"pilots": [me()], "local": {1: 0},
	}


## Today's flight: the same course, prototype and pace for everyone, no
## gadgets, lanes on.
static func daily(date := "") -> Dictionary:
	if date == "":
		date = today()
	return {
		"mode": "daily", "seed": daily_seed(date), "pace": "normal", "lanes": true, "date": date,
		"pilots": [me(daily_pack(date), [])], "local": {1: 0},
	}


static func course(id: String) -> Dictionary:
	return {
		"mode": "course", "course": id, "seed": int(Courses.get_def(id).seed), "pace": "normal", "lanes": lanes(),
		"pilots": [me("", [])], "local": {1: 0},
	}


## The first flight: a short run of rooms that teach the controls.
static func tutorial() -> Dictionary:
	return {
		"mode": "tutorial", "seed": 1, "pace": "calm", "lanes": true,
		"pilots": [me("k1", [])], "local": {1: 0},
	}


## A party race on this screen: everyone in `seats` (local seat indexes)
## plus bots up to `bots`.
static func party_couch(seats: Array, bots: int, zone := "") -> Dictionary:
	var pilots := []
	var local := {}
	var used := []
	for i in seats.size():
		var id := i + 1
		var n := Progress.pilot_name() if i == 0 else "Pilot %d" % (i + 1)
		used.append(n)
		pilots.append({"id": id, "name": n, "pack": Progress.pack() if i == 0 else Packs.ORDER[i % Packs.ORDER.size()], "look": Progress.look() if i == 0 else {}})
		local[id] = int(seats[i])
	var bot_skills := {}
	for b in bots:
		var id := seats.size() + b + 1
		var n := LGNameMaker.make(used)
		used.append(n)
		pilots.append({"id": id, "name": n, "pack": Packs.ORDER[(id - 1) % Packs.ORDER.size()], "bot": true})
		bot_skills[id] = ["average", "novice", "expert"][b % 3]
	var c := {
		"mode": "party", "seed": randi(), "pace": pace(), "lanes": lanes(),
		"pilots": pilots, "local": local, "bots": bot_skills, "me": 1,
		"round": 1, "wins": {}, "first_to": 3,
	}
	if zone != "":
		c["zone"] = zone
	return c


## Behind the title: an expert bot flying the tower, no HUD.
static func backdrop() -> Dictionary:
	return {
		"mode": "endless", "seed": randi(), "pace": "normal", "lanes": true, "backdrop": true,
		"zone": Zones.ORDER[randi() % 4],
		"pilots": [{"id": 1, "name": "Pilot", "pack": Progress.pack(), "look": Progress.look()}],
		"local": {}, "bots": {1: "expert"}, "me": 1,
	}
