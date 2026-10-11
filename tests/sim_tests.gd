extends RefCounted
## The run itself: the same seed flies the same way, every pattern builds,
## and bots get through.


func _bot_run(config: Dictionary, skill: String, max_time := 120.0) -> Run:
	var run := Run.new(config)
	var bot := Autopilot.new(skill, int(config.get("seed", 1)))
	var p := run.pilots[0]
	while not run.finished and run.time < max_time:
		run.step({p.id: bot.think(run, p)})
	return run


func test_same_seed_same_run(t) -> void:
	var a := _bot_run({"mode": "endless", "seed": 7}, "average", 40.0)
	var b := _bot_run({"mode": "endless", "seed": 7}, "average", 40.0)
	t.check(is_equal_approx(a.pilots[0].x, b.pilots[0].x) and a.pilots[0].credits == b.pilots[0].credits, "the same seed flies the same way")


func test_every_pattern_builds(t) -> void:
	for zone in Zones.ORDER:
		for e in Zones.info(zone).patterns:
			for lanes in [true, false]:
				var r := RoomGen.new(1, zone, 100.0, 0.6, 14.0, lanes, 3)
				Patterns.make(str(e[0]), r)
				t.check(r.length >= RoomGen.TILE * 4.0, "%s in %s has a length" % [e[0], zone])
				for h in r.hazards:
					t.check(h.lane >= 0 and h.lane < Run.LANES, "%s's hazards are in a lane" % e[0])
					if not lanes:
						t.check(h.lane == 1 or h.kind == "gun_drone", "%s in Classic keeps to the middle lane" % e[0])


func test_expert_flies_far(t) -> void:
	for i in t.games:
		var run := _bot_run({"mode": "endless", "seed": 100 + i}, "expert", 90.0)
		t.check(run.pilots[0].x > 600.0, "an expert bot flies 600 m (seed %d: %.0f m)" % [100 + i, run.pilots[0].x])
