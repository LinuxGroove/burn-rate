extends RefCounted
## Progress, missions, unlocks, the Daily Flight and ghosts: missions finish
## from a run's stats, ranks open the prototypes, credits buy gadgets and
## suits, the Daily seed holds for a date, and ghosts fly back where they
## were recorded. Progress is in memory (the runner points it at a test file).


func _fresh() -> void:
	Progress.ghost_dir = "user://test_ghosts/"
	Progress.reset()


## A finished run as RunScene.result() gives it.
func _result(mode := "endless", distance := 100, stats := {}, extra := {}) -> Dictionary:
	var r := {"mode": mode, "seed": 1, "pace": "normal", "lanes": true, "distance": distance, "credits": int(stats.get("credits", 0)),
		"best_burn": int(stats.get("burn", 1)), "time": 30.0, "stats": stats, "winner": -1, "course": "", "pack": "k1", "me": 1, "date": ""}
	r.merge(extra, true)
	return r


func _set_missions(ids: Array) -> void:
	Progress._cfg.set_value("missions", "active", ids)
	Progress._cfg.set_value("missions", "banked", {})


func test_missions_finish_from_a_run(t) -> void:
	_fresh()
	t.check(Progress.missions().size() == Missions.SLOTS, "there are always three missions")
	_set_missions(["fly_500", "staff_3", "burn_2"])
	var rep := Progress.record_run(_result("endless", 640, {"staff": 1}))
	var done: Array = rep.missions.map(func(m): return str(m.id))
	t.check("fly_500" in done, "flying 640 m finishes Fly 500 m")
	t.check(not "staff_3" in done, "one knocked over isn't three")
	t.check(Progress.missions_done() == 1 and Progress.rank_progress() == 1, "one mission towards the next rank")
	t.check(Progress.missions().size() == Missions.SLOTS and not Progress.missions().any(func(m): return m.id == "fly_500"), "a new mission takes its place")
	t.check(Progress.credits() == int(Missions.by_id("fly_500").reward), "a finished mission pays credits")
	t.check(rep.new_missions.size() == 1, "the results name the new mission")
	rep = Progress.record_run(_result("endless", 90, {"staff": 3}, {"best_burn": 2}))
	done = rep.missions.map(func(m): return str(m.id))
	t.check("staff_3" in done and "burn_2" in done, "two missions in one run")
	t.check(Progress.rank() == 1 and int(rep.rank_before) == 0 and int(rep.rank) == 1, "three missions raise the rank")


func test_total_missions_add_up(t) -> void:
	_fresh()
	_set_missions(["staff_25", "fly_500", "credits_50"])
	Progress.record_run(_result("endless", 50, {"staff": 10}))
	var m: Dictionary = Progress.missions().filter(func(x): return x.id == "staff_25")[0]
	t.check(is_equal_approx(float(m.banked), 10.0), "a total mission banks what a run did")
	var snap := {"stats": {"staff": 14}}
	t.check(not Missions.done(m, snap, float(m.banked)), "24 of 25 isn't done")
	var rep := Progress.record_run(_result("endless", 50, {"staff": 15}))
	t.check(rep.missions.any(func(x): return x.id == "staff_25"), "and the next run finishes it")
	# Live progress for the HUD, from a pilot mid-run.
	var run := Run.new({"mode": "endless", "seed": 3})
	var p := run.pilots[0]
	p.stats["near"] = 6
	var live := Missions.snapshot(run, p)
	t.check(Missions.done(Missions.by_id("near_5"), live), "the HUD sees a mission done mid-run")
	t.check(Missions.progress_text(Missions.by_id("fly_1000"), 640.0) == "640/1,000 m", "progress reads 640/1,000 m")


func test_mission_words(t) -> void:
	t.check(Missions.describe(Missions.by_id("fly_1500")) == "Fly 1,500 m", "Fly 1,500 m")
	t.check(Missions.describe(Missions.by_id("raptor_300")) == "Ride a Raptor 300 m", "Ride a Raptor 300 m")
	t.check(Missions.describe(Missions.by_id("thread_1")) == "Thread a needle", "Thread a needle")
	var ids := {}
	for i in 200:
		var m := Missions.nth(i)
		t.check(not ids.has(m.id), "mission %d has its own id (%s)" % [i, m.id])
		ids[m.id] = true
		t.check(int(m.target) > 0 and Missions.describe(m) != "", "mission %d has words and a target" % i)
	var later := Missions.nth(Missions.LIST.size() + 3)
	t.check(int(later.round) == 2 and not Missions.by_id(later.id).is_empty(), "missions carry on past the list")
	var stopped := _result("endless", 10, {"killed_by": "laser"})
	t.check(Missions.value("stopped_laser", stopped) == 1.0, "getting stopped by a laser counts")


func test_ranks_open_prototypes(t) -> void:
	_fresh()
	t.check(Progress.pack_open("k1") and not Progress.pack_open("k2"), "only the K-1 at first")
	Progress.set_pack("k3")
	t.check(Progress.pack() == "k1", "a locked prototype can't be chosen")
	Progress._cfg.set_value("missions", "done", Missions.PER_RANK * Unlocks.pack_rank("k2") - 1)
	_set_missions(["fly_500", "staff_3", "burn_2"])
	var rep := Progress.record_run(_result("endless", 600))
	t.check(Progress.rank() == Unlocks.pack_rank("k2"), "a mission makes the rank")
	t.check(rep.unlocked.any(func(u): return u.kind == "pack" and u.id == "k2"), "and the results say the K-2 is open")
	t.check(Progress.pack_open("k2"), "the K-2 is open")
	Progress.set_pack("k2")
	t.check(Progress.pack() == "k2", "and goes in the hangar")
	for k in Packs.ORDER:
		t.check(Unlocks.opened_at(Unlocks.pack_rank(k)).any(func(u): return u.id == k), "%s opens at its rank" % k)
	var next := Unlocks.next_after(0)
	t.check(not next.is_empty() and int(next.rank) > 0, "there's always something to rank up for")


func test_credits_buy_gadgets_and_suits(t) -> void:
	_fresh()
	t.check(not Progress.buy_gadget("magnet"), "no credits, no magnet")
	Progress.add_credits(5000)
	t.check(Progress.buy_gadget("magnet") and Progress.owns_gadget("magnet"), "credits buy the magnet")
	t.check(Progress.credits() == 5000 - int(Unlocks.gadget("magnet").price), "and it costs its price")
	Progress.buy_gadget("shield")
	Progress.buy_gadget("hints")
	Progress.toggle_gadget("magnet")
	Progress.toggle_gadget("shield")
	Progress.toggle_gadget("hints")
	t.check(Progress.gadgets().size() == 2 and "hints" in Progress.gadgets() and not "magnet" in Progress.gadgets(), "two gadgets at a time; the oldest goes")
	t.check(Flights.endless().pilots[0].gadgets == Progress.gadgets(), "endless runs take them along")
	t.check(Flights.daily().pilots[0].gadgets.is_empty(), "the Daily Flight leaves them at home")
	var priced := ""
	for id in Unlocks.suit_order():
		if Unlocks.suit(id).has("price"):
			priced = id
			break
	t.check(priced != "" and not Progress.suit_open(priced), "some suits are for sale")
	t.check(Progress.buy_suit(priced) and Progress.suit_open(priced), "credits buy a suit")
	Progress.set_suit(priced)
	t.check(Progress.look().accent == Unlocks.suit(priced).accent, "and the pilot wears it")


func test_bests(t) -> void:
	_fresh()
	var rep := Progress.record_run(_result("endless", 812))
	t.check(rep.new_best and Progress.best_distance("normal", true) == 812, "the first run is the best")
	rep = Progress.record_run(_result("endless", 500))
	t.check(not rep.new_best and int(rep.best) == 812, "a shorter run isn't")
	Progress.record_run(_result("endless", 900, {}, {"lanes": false}))
	t.check(Progress.best_distance("normal", false) == 900 and Progress.best_distance("normal", true) == 812, "Classic keeps its own best")
	t.check(Progress.best_distance("normal", true, "k1") == 812, "and each prototype its own")
	var id := str(Courses.ids()[0])
	var gold := float(Courses.medal_times(id).gold) - 0.5
	rep = Progress.record_run(_result("course", 700, {"finish_time": gold}, {"course": id}))
	t.check(str(rep.medal) in ["gold", "patrol"] and Progress.course_medal(id) == rep.medal, "a fast course wins gold")
	t.check(Missions.value("gold_medals", {"medal": rep.medal}) == 1.0, "gold counts for missions")
	var date := "2026-10-11"
	rep = Progress.record_run(_result("daily", 640, {}, {"date": date}))
	t.check(rep.new_best and Progress.daily_best(date) == 640, "the Daily Flight keeps the day's best")
	t.check(Progress.daily_best("2026-10-12") == 0, "and each day starts again")


func test_daily_is_the_same_for_everyone(t) -> void:
	var date := "2026-10-11"
	t.check(Flights.daily_seed(date) == Flights.daily_seed(date), "the same date, the same seed")
	t.check(Flights.daily_seed(date) != Flights.daily_seed("2026-10-12"), "a new day, a new seed")
	t.check(Flights.daily_seed(date) >= 0, "seeds are positive")
	t.check(Flights.daily_pack(date) == Flights.daily_pack(date) and Packs.SPECS.has(Flights.daily_pack(date)), "the day's prototype holds")
	var packs := {}
	for d in 6:
		packs[Flights.daily_pack("2026-10-%02d" % (11 + d))] = true
	t.check(packs.size() == 6, "six days, six prototypes")
	var a := Run.new(Flights.daily(date))
	var b := Run.new(Flights.daily(date))
	var same := a.course.rooms.size() == b.course.rooms.size()
	for i in mini(a.course.rooms.size(), b.course.rooms.size()):
		same = same and a.course.rooms[i].pattern == b.course.rooms[i].pattern
	t.check(same, "the Daily Flight's rooms are the same every time")
	t.check(Flights.date_text(date) == "Sunday 11 October", "dates read Sunday 11 October")


func test_ghosts(t) -> void:
	_fresh()
	var run := Run.new({"mode": "course", "course": "lab_1", "seed": 1})
	var bot := Autopilot.new("expert", 3)
	var p := run.pilots[0]
	var g := Ghost.new()
	while run.time < 6.0 and not run.finished:
		run.step({p.id: bot.think(run, p)})
		g.record(p, run.time)
	t.check(absi(g.count() - int(run.time * Ghost.RATE)) <= 2, "ghosts sample at 20 Hz")
	var s := g.sample(3.0)
	t.check(not s.is_empty() and float(s.x) > 10.0, "a ghost knows where it was")
	var stand := Pilot.new(-1, "Ghost")
	t.check(g.pose(stand, 2.0) and stand.x > 0.0, "and puts a stand-in there")
	t.check(g.sample(run.time + 5.0).is_empty(), "and stops after its end")
	Progress.save_ghost("test_course", g)
	var back := Progress.load_ghost("test_course")
	t.check(back != null and back.count() == g.count() and is_equal_approx(float(back.sample(3.0).x), float(s.x)), "ghosts save and load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.ghost_path("test_course")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.ghost_dir))
	t.check(Progress.ghost_key({"mode": "daily", "date": "2026-10-11"}) == "daily_2026-10-11", "the Daily Flight's ghost is by date")
	t.check(Progress.ghost_key({"mode": "endless"}) == "", "endless runs keep no ghost")


func test_boards(t) -> void:
	var e := Boards.entry_for(_result("endless", 1234))
	t.check(e == ["distance_normal", 1234], "endless goes on distance_normal")
	e = Boards.entry_for(_result("endless", 50, {}, {"lanes": false, "pace": "calm"}))
	t.check(e[0] == "distance_classic_calm", "Classic has its own boards")
	e = Boards.entry_for(_result("course", 700, {"finish_time": 61.234}, {"course": "lab_1"}))
	t.check(e == ["course_lab_1", 61234], "course times go up in milliseconds")
	t.check(Boards.entry_for(_result("course", 300, {}, {"course": "lab_1"})).is_empty(), "an unfinished course doesn't")
	t.check(Boards.entry_for(_result("daily", 900, {}, {"date": Flights.today()})) == ["daily", 900], "today's flight goes on daily")
	t.check(Boards.entry_for(_result("daily", 900, {}, {"date": "2020-01-01"})).is_empty(), "an old day's flight doesn't")
	t.check(Boards.endless_boards().size() == 6 and Boards.course_boards().size() == Courses.ids().size(), "every board is on the Leaderboards screen")


func test_a_whole_run_banks(t) -> void:
	_fresh()
	var run := Run.new(Flights.endless())
	var bot := Autopilot.new("average", 5)
	var p := run.pilots[0]
	while not run.finished and run.time < 40.0:
		run.step({p.id: bot.think(run, p)})
	var r := {"mode": run.mode, "pace": run.pace, "lanes": run.lanes_on, "distance": int(p.x), "credits": p.credits,
		"best_burn": p.best_burn, "time": run.time, "stats": p.stats, "pack": p.pack, "me": 1}
	var before := Progress.credits()
	var rep := Progress.record_run(r)
	t.check(Progress.credits() >= before + p.credits, "a run's credits go in the bank")
	t.check(Progress.total("runs") == 1 and Progress.total("distance") == int(p.x), "lifetime totals count it")
	t.check(int(rep.wallet) == Progress.credits(), "the results show the bank")
	_fresh()
