extends Node
## What the pilot has earned (autoload: Progress): credits, the three
## missions and the rank they raise, the prototypes, suits and gadgets that
## opens or buys, what's in the hangar, bests (per pace, lanes on or off and
## prototype), today's Daily Flight, course times and medals, and lifetime
## totals. Kept in user://progress.cfg; ghosts in user://ghosts/.
##
## Runs report here through [method record_run], which hands back what the
## results screen shows.

const PATH := "user://progress.cfg"
const GHOSTS := "user://ghosts/"

## Tests set this so they don't touch the player's save.
var save_path := PATH
var ghost_dir := GHOSTS
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(save_path)
	_fill_missions()


func save() -> void:
	_cfg.save(save_path)


## Starts again from nothing (tests, and nobody else).
func reset() -> void:
	_cfg = ConfigFile.new()
	_fill_missions()


func _v(section: String, key: String, fallback: Variant) -> Variant:
	return _cfg.get_value(section, key, fallback)


# --- The pilot ------------------------------------------------------------

func pilot_name() -> String:
	var n := str(LGSettings.get_value("player", "name", "")).strip_edges()
	return n if n != "" else "Pilot"


func credits() -> int:
	return int(_v("wallet", "credits", 0))


func add_credits(n: int) -> void:
	_cfg.set_value("wallet", "credits", maxi(0, credits() + n))
	if n > 0:
		_cfg.set_value("wallet", "earned", int(_v("wallet", "earned", 0)) + n)


## The prototype in the hangar.
func pack() -> String:
	var p := str(_v("hangar", "pack", "k1"))
	return p if pack_open(p) else "k1"


func set_pack(p: String) -> void:
	if pack_open(p):
		_cfg.set_value("hangar", "pack", p)
		save()


func pack_open(p: String) -> bool:
	return Packs.SPECS.has(p) and rank() >= Unlocks.pack_rank(p)


func suit() -> String:
	var s := str(_v("hangar", "suit", str(LGSettings.get_value("player", "suit", "kestrel"))))
	return s if suit_open(s) else str(Unlocks.suit_order()[0])


func set_suit(s: String) -> void:
	if suit_open(s):
		_cfg.set_value("hangar", "suit", s)
		LGSettings.set_value("player", "suit", s)
		save()


func suit_open(s: String) -> bool:
	var all := Unlocks.suits()
	if not all.has(s):
		return false
	var e: Dictionary = all[s]
	if e.has("price"):
		return s in suits_bought()
	return rank() >= int(e.get("rank", 0))


func suits_bought() -> Array:
	return _v("hangar", "suits_bought", [])


## Buys a suit with credits; false if it isn't for sale or costs too much.
func buy_suit(s: String) -> bool:
	var e := Unlocks.suit(s)
	if not e.has("price") or s in suits_bought() or credits() < int(e.price):
		return false
	add_credits(-int(e.price))
	var list := suits_bought().duplicate()
	list.append(s)
	_cfg.set_value("hangar", "suits_bought", list)
	save()
	return true


## 0 or 1: which of the two bodies.
func body() -> int:
	return int(_v("hangar", "body", int(LGSettings.get_value("player", "body", 0)))) % 2


func set_body(b: int) -> void:
	_cfg.set_value("hangar", "body", b % 2)
	LGSettings.set_value("player", "body", b % 2)
	save()


## The pilot's look for a run (see Person.make).
## This player's look (see [PilotLooks]).
func look() -> Dictionary:
	return PilotLooks.make(body(), suit())


func gadgets_owned() -> Array:
	return _v("hangar", "gadgets_owned", [])


func owns_gadget(g: String) -> bool:
	return g in gadgets_owned()


func buy_gadget(g: String) -> bool:
	var e := Unlocks.gadget(g)
	if e.is_empty() or owns_gadget(g) or credits() < int(e.price):
		return false
	add_credits(-int(e.price))
	var list := gadgets_owned().duplicate()
	list.append(g)
	_cfg.set_value("hangar", "gadgets_owned", list)
	save()
	return true


## The gadgets taken into endless runs (up to two).
func gadgets() -> Array:
	var out := []
	for g in _v("hangar", "gadgets", []):
		if owns_gadget(str(g)) and out.size() < Unlocks.GADGET_SLOTS:
			out.append(str(g))
	return out


## Takes a gadget along, or leaves it behind; the oldest goes when both
## slots are full. Returns whether it's now taken.
func toggle_gadget(g: String) -> bool:
	if not owns_gadget(g):
		return false
	var list := gadgets()
	if g in list:
		list.erase(g)
	else:
		list.append(g)
		while list.size() > Unlocks.GADGET_SLOTS:
			list.pop_front()
	_cfg.set_value("hangar", "gadgets", list)
	save()
	return g in list


# --- Missions and rank ------------------------------------------------------

## Missions finished, ever.
func missions_done() -> int:
	return int(_v("missions", "done", 0))


func rank() -> int:
	return missions_done() / Missions.PER_RANK


## Missions finished towards the next rank (0 to 2).
func rank_progress() -> int:
	return missions_done() % Missions.PER_RANK


## The three missions on now, each with "banked" (what earlier runs added
## to a total mission).
func missions() -> Array:
	var out := []
	var banked: Dictionary = _v("missions", "banked", {})
	for id in _v("missions", "active", []):
		var m := Missions.by_id(str(id))
		if m.is_empty():
			continue
		m = m.duplicate()
		m["banked"] = float(banked.get(str(id), 0.0))
		out.append(m)
	return out


func _fill_missions() -> void:
	var active: Array = _v("missions", "active", []).duplicate()
	active = active.filter(func(id): return not Missions.by_id(str(id)).is_empty())
	var next := int(_v("missions", "next", 0))
	while active.size() < Missions.SLOTS:
		var m := Missions.nth(next)
		next += 1
		if not m.id in active:
			active.append(m.id)
	_cfg.set_value("missions", "active", active)
	_cfg.set_value("missions", "next", next)


# --- Runs -----------------------------------------------------------------

## Banks a finished run and works out what it earned. `r` is
## RunScene.result(). Returns what the results screen shows:
##   credits, wallet, missions (finished: [{id, text, reward}]), new_missions,
##   rank_before, rank, unlocked [{kind, id, name}], best (previous best),
##   new_best, medal, course_best (previous time), new_course_best, won.
func record_run(r: Dictionary) -> Dictionary:
	var mode := str(r.get("mode", "endless"))
	var rep := {"mode": mode, "credits": 0, "missions": [], "new_missions": [], "unlocked": [],
		"rank_before": rank(), "rank": rank(), "new_best": false, "best": 0, "medal": "", "won": false}
	if mode == "tutorial":
		return rep
	var snap := r.duplicate()
	snap["over"] = true
	snap["won"] = mode == "party" and int(r.get("winner", -1)) == int(r.get("me", 1))
	rep["won"] = snap.won
	var stats: Dictionary = r.get("stats", {})
	# Bests.
	match mode:
		"endless":
			var key := best_key(str(r.get("pace", "normal")), bool(r.get("lanes", true)))
			var pk := key + "_" + str(r.get("pack", "k1"))
			rep["best"] = int(_v("best", key, 0))
			var d := int(r.get("distance", 0))
			if d > int(rep.best):
				_cfg.set_value("best", key, d)
				rep["new_best"] = int(rep.best) > 0 or d > 0
			if d > int(_v("best", pk, 0)):
				_cfg.set_value("best", pk, d)
		"daily":
			var date := str(r.get("date", Flights.today()))
			rep["best"] = daily_best(date)
			var d := int(r.get("distance", 0))
			if d > int(rep.best):
				_cfg.set_value("daily", date, d)
				rep["new_best"] = true
			_cfg.set_value("daily", "last", date)
		"course":
			var id := str(r.get("course", ""))
			if stats.has("finish_time"):
				var t := float(stats.finish_time)
				rep["medal"] = Courses.medal_for(id, t)
				snap["medal"] = rep.medal
				rep["best"] = course_best(id)
				if course_best(id) <= 0.0 or t < course_best(id):
					_cfg.set_value("courses", id, t)
					rep["new_best"] = true
	# Lifetime totals.
	_add_total("runs", 1)
	_add_total("distance", int(r.get("distance", 0)))
	for k in ["staff", "near", "smash", "rides", "near_thread"]:
		_add_total(k, int(stats.get(k, 0)))
	_max_total("best_burn", int(r.get("best_burn", 1)))
	# Credits.
	var got := int(r.get("credits", 0))
	add_credits(got)
	rep["credits"] = got
	_add_total("credits", got)
	# Missions.
	var banked: Dictionary = _v("missions", "banked", {}).duplicate()
	var active: Array = _v("missions", "active", []).duplicate()
	for id in active.duplicate():
		var m := Missions.by_id(str(id))
		var before := float(banked.get(str(id), 0.0))
		if Missions.done(m, snap, before):
			active.erase(id)
			banked.erase(str(id))
			_cfg.set_value("missions", "done", missions_done() + 1)
			add_credits(int(m.reward))
			rep.missions.append({"id": m.id, "text": Missions.describe(m), "reward": int(m.reward)})
		elif str(m.scope) == "total":
			banked[str(id)] = Missions.progress(m, snap, before)
	_cfg.set_value("missions", "active", active)
	_cfg.set_value("missions", "banked", banked)
	var had := active.duplicate()
	_fill_missions()
	for id in _v("missions", "active", []):
		if not id in had:
			rep.new_missions.append(Missions.describe(Missions.by_id(str(id))))
	rep["rank"] = rank()
	for k in range(int(rep.rank_before) + 1, rank() + 1):
		rep.unlocked.append_array(Unlocks.opened_at(k))
	rep["wallet"] = credits()
	save()
	return rep


func _add_total(key: String, n: int) -> void:
	if n != 0:
		_cfg.set_value("totals", key, int(_v("totals", key, 0)) + n)


func _max_total(key: String, n: int) -> void:
	_cfg.set_value("totals", key, maxi(int(_v("totals", key, 0)), n))


## A lifetime total (runs, distance, credits, staff, near, smash, rides).
func total(key: String) -> int:
	return int(_v("totals", key, 0))


# --- Bests ------------------------------------------------------------------

static func best_key(pace: String, lanes: bool) -> String:
	return "%s_%s" % ["lanes" if lanes else "classic", pace]


## The best endless distance at a pace, with lanes or Classic; with `pack`,
## flying that prototype.
func best_distance(pace := "normal", lanes := true, p := "") -> int:
	var key := best_key(pace, lanes)
	if p != "":
		key += "_" + p
	return int(_v("best", key, 0))


func daily_best(date := "") -> int:
	return int(_v("daily", date if date != "" else Flights.today(), 0))


## Best time on a course in seconds, or 0.
func course_best(id: String) -> float:
	return float(_v("courses", id, 0.0))


func course_medal(id: String) -> String:
	var t := course_best(id)
	return Courses.medal_for(id, t) if t > 0.0 else ""


## Medals won in a zone's courses: {"gold": n, ...}.
func medal_count(zone := "") -> Dictionary:
	var out := {"patrol": 0, "gold": 0, "silver": 0, "bronze": 0}
	for id in Courses.ids():
		if zone != "" and str(Courses.get_def(id).zone) != zone:
			continue
		var m := course_medal(id)
		if m != "":
			out[m] += 1
	return out


# --- Ghosts -----------------------------------------------------------------

func ghost_path(key: String) -> String:
	return ghost_dir.path_join(key.replace("/", "_") + ".ghost")


func load_ghost(key: String) -> Ghost:
	return Ghost.load_from(ghost_path(key))


func save_ghost(key: String, g: Ghost) -> void:
	if g and not g.is_empty():
		g.save(ghost_path(key))


## Which ghost a run flies against and keeps: today's Daily Flight, or the
## course. "" for modes without ghosts.
static func ghost_key(config: Dictionary) -> String:
	match str(config.get("mode", "")):
		"daily":
			return "daily_" + str(config.get("date", Flights.today()))
		"course":
			return "course_" + str(config.get("course", ""))
	return ""
