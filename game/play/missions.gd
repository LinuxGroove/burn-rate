class_name Missions
extends RefCounted
## Missions, three at a time: small goals from what a run did (its distance,
## credits, Burn and the pilot's stats). Finish one and the next takes its
## place; every three finished raise your rank, and ranks open the
## prototypes and suits (see [Unlocks]).
##
## A mission is {id, text, stat, target, scope, reward}:
##   stat    what to measure (see [method value])
##   scope   "run": in one run; "total": added up over runs from when it
##           became a mission
##   reward  credits for finishing it
## The list is in order of difficulty. Past its end, harder copies of the
## list's later missions follow, so there's always another rank.

## Missions finished per rank.
const PER_RANK := 3
## Missions on at once.
const SLOTS := 3

## [id, text with %s for the target, stat, target, scope]
const LIST := [
	["fly_500", "Fly %s", "distance", 500, "run"],
	["credits_50", "Collect %s credits in one run", "credits", 50, "run"],
	["staff_3", "Knock over %s staff in one run", "staff", 3, "run"],
	["near_5", "Get %s near misses in one run", "near", 5, "run"],
	["burn_2", "Reach Burn ×%s", "burn", 2, "run"],
	["lanes_15", "Change lane %s times in one run", "lane_changes", 15, "run"],
	["fly_1000", "Fly %s", "distance", 1000, "run"],
	["raptor_1", "Hijack a Raptor", "ride_count_raptor", 1, "run"],
	["thread_1", "Thread a needle", "near_thread", 1, "run"],
	["credits_150", "Collect %s credits in one run", "credits", 150, "run"],
	["razor_1", "Fly a Razor-close miss", "near_razor", 1, "run"],
	["burn_3", "Reach Burn ×%s", "burn", 3, "run"],
	["zappers_5", "Skim past %s zappers in one run", "near_zapper", 5, "run"],
	["raptor_300", "Ride a Raptor %s", "ride_raptor", 300, "run"],
	["smash_3", "Smash %s robots", "smash", 3, "total"],
	["daily_1", "Fly a Daily Flight", "daily_runs", 1, "total"],
	["course_1", "Finish a course", "course_finishes", 1, "total"],
	["fly_1500", "Fly %s", "distance", 1500, "run"],
	["staff_25", "Knock over %s staff", "staff", 25, "total"],
	["seekers_3", "Dodge %s seekers close in one run", "near_seeker", 3, "run"],
	["lasers_3", "Slip past %s lasers in one run", "near_laser", 3, "run"],
	["air_60", "Stay in the air for %s seconds in one run", "air_seconds", 60, "run"],
	["credits_300", "Collect %s credits in one run", "credits", 300, "run"],
	["burn_4", "Reach Burn ×%s", "burn", 4, "run"],
	["thread_3", "Thread %s needles in one run", "near_thread", 3, "run"],
	["fly_2000", "Fly %s", "distance", 2000, "run"],
	["rides_2", "Hijack %s robots in one run", "rides", 2, "run"],
	["near_25", "Get %s near misses in one run", "near", 25, "run"],
	["smash_run_3", "Smash %s robots in one run", "smash", 3, "run"],
	["laser_out", "Get stopped by a laser", "stopped_laser", 1, "total"],
	["total_10k", "Fly %s in total", "distance", 10000, "total"],
	["party_1", "Win a party race", "party_wins", 1, "total"],
	["shell_200", "Ride a Shell %s", "ride_shell", 200, "run"],
	["eye_200", "Ride an Eye %s", "ride_eye", 200, "run"],
	["gunner_200", "Ride a Gunner %s", "ride_gunner", 200, "run"],
	["credits_500", "Collect %s credits in one run", "credits", 500, "run"],
	["gold_1", "Win a Gold medal on a course", "gold_medals", 1, "total"],
	["burn_5", "Reach Burn ×%s", "burn", 5, "run"],
	["razor_10", "Fly %s Razor-close misses in one run", "near_razor", 10, "run"],
	["fly_3000", "Fly %s", "distance", 3000, "run"],
	["staff_10", "Knock over %s staff in one run", "staff", 10, "run"],
	["seeker_out", "Get caught by a seeker", "stopped_seeker", 1, "total"],
	["near_50", "Get %s near misses in one run", "near", 50, "run"],
	["total_credits_5k", "Collect %s credits in total", "credits", 5000, "total"],
	["daily_5", "Fly %s Daily Flights", "daily_runs", 5, "total"],
	["fly_4000", "Fly %s", "distance", 4000, "run"],
	["thread_5", "Thread %s needles in one run", "near_thread", 5, "run"],
	["smash_25", "Smash %s robots", "smash", 25, "total"],
	["courses_10", "Finish %s courses", "course_finishes", 10, "total"],
	["credits_1000", "Collect %s credits in one run", "credits", 1000, "run"],
	["air_180", "Stay in the air for %s seconds in one run", "air_seconds", 180, "run"],
	["total_50k", "Fly %s in total", "distance", 50000, "total"],
	["party_5", "Win %s party races", "party_wins", 5, "total"],
	["fly_5000", "Fly %s", "distance", 5000, "run"],
	["burn_5_twice", "Reach Burn ×5 in %s runs", "burn5_runs", 2, "total"],
]
## Later missions repeat these, with targets that grow each time round.
const REPEAT_FROM := 24

## Ranks' names, a new one every three ranks.
const TITLES := ["Intern", "Test Pilot", "Flight Lead", "Chief Pilot", "Skunkworks", "Moonshot", "Unicorn", "Legend"]

static var _by_id := {}


## Mission number `n` (0 is the first ever).
static func nth(n: int) -> Dictionary:
	if n < LIST.size():
		return _make(LIST[n], 1)
	var span := LIST.size() - REPEAT_FROM
	var k := n - LIST.size()
	var round := 2 + k / span
	return _make(LIST[REPEAT_FROM + k % span], round)


static func _make(e: Array, round: int) -> Dictionary:
	var target := int(e[3])
	var id := str(e[0])
	if round > 1:
		# Burn levels top out at 5; count runs at Burn x5 instead.
		if str(e[2]) == "burn":
			return {"id": "%s_r%d" % [id, round], "text": "Reach Burn ×5 in %s runs", "stat": "burn5_runs", "target": round, "scope": "total", "reward": reward_for(target, round), "round": round}
		target = _round_up(target * (1.0 + 0.5 * (round - 1)))
		id = "%s_r%d" % [id, round]
	return {"id": id, "text": str(e[1]), "stat": str(e[2]), "target": target, "scope": str(e[4]), "reward": reward_for(target, round), "round": round}


static func _round_up(v: float) -> int:
	if v < 20.0:
		return int(ceil(v))
	if v < 200.0:
		return int(ceil(v / 5.0) * 5.0)
	return int(ceil(v / 50.0) * 50.0)


static func reward_for(_target: int, round: int) -> int:
	return 40 + 20 * round


## The mission with this id (searching the list and its repeats).
static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		for i in LIST.size() * 6:
			var m := nth(i)
			_by_id[m.id] = m
	return _by_id.get(id, {})


## Its words: "Fly 1,500 m", "Knock over 3 staff in one run".
static func describe(m: Dictionary) -> String:
	var text := str(m.get("text", ""))
	if not "%s" in text:
		return text
	var stat := str(m.get("stat", ""))
	var target := int(m.get("target", 0))
	var shown := GameConfig.grouped(target)
	if stat == "distance" or stat.begins_with("ride_") and not stat.begins_with("ride_count"):
		shown = "%s m" % GameConfig.grouped(target)
	return text % shown


## How far a run got towards a stat. `snap` is what [method snapshot] or
## RunScene.result() gives: distance, credits, best_burn, mode, stats, and
## after a course, medal; after a party race, won.
static func value(stat: String, snap: Dictionary) -> float:
	var stats: Dictionary = snap.get("stats", {})
	match stat:
		"distance":
			return float(snap.get("distance", 0.0))
		"credits":
			return float(snap.get("credits", 0))
		"burn":
			return float(snap.get("best_burn", 1))
		"burn5_runs":
			return 1.0 if int(snap.get("best_burn", 1)) >= 5 and bool(snap.get("over", false)) else 0.0
		"air_seconds":
			return float(stats.get("air_ticks", 0)) / 60.0
		"daily_runs":
			return 1.0 if str(snap.get("mode", "")) == "daily" and bool(snap.get("over", false)) else 0.0
		"course_finishes":
			return 1.0 if str(snap.get("mode", "")) == "course" and stats.has("finish_time") else 0.0
		"gold_medals":
			return 1.0 if str(snap.get("medal", "")) in ["gold", "patrol"] else 0.0
		"party_wins":
			return 1.0 if bool(snap.get("won", false)) else 0.0
	if stat.begins_with("stopped_"):
		return 1.0 if str(stats.get("killed_by", "")) == stat.trim_prefix("stopped_") else 0.0
	return float(stats.get(stat, 0))


## How far along a mission is: its own run's value, or for totals, what
## earlier runs added (`banked`) plus this run.
static func progress(m: Dictionary, snap: Dictionary, banked := 0.0) -> float:
	var v := value(str(m.stat), snap)
	if str(m.scope) == "total":
		return banked + v
	return v


static func done(m: Dictionary, snap: Dictionary, banked := 0.0) -> bool:
	return progress(m, snap, banked) >= float(m.target)


## "2/3" or "640/1,000 m" for the HUD and menus.
static func progress_text(m: Dictionary, amount: float) -> String:
	var target := int(m.target)
	var got := mini(int(floor(amount)), target)
	if target <= 1:
		return "Done" if got >= 1 else ""
	var stat := str(m.stat)
	if stat == "distance" or stat.begins_with("ride_") and not stat.begins_with("ride_count"):
		return "%s/%s m" % [GameConfig.grouped(got), GameConfig.grouped(target)]
	return "%s/%s" % [GameConfig.grouped(got), GameConfig.grouped(target)]


## What a run looks like to missions right now (for the HUD's live checks).
static func snapshot(run: Run, p: Pilot) -> Dictionary:
	return {
		"mode": run.mode, "distance": p.x, "credits": p.credits, "best_burn": p.best_burn,
		"stats": p.stats, "over": false,
	}


## A rank's name.
static func title(rank: int) -> String:
	return TITLES[mini(rank / 3, TITLES.size() - 1)]
