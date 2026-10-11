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


## Every pattern builds the same from the same seed, whatever ran before: a
## party race needs every device's rooms to match.
func test_patterns_seeded(t) -> void:
	for zone in Zones.ORDER:
		for e in Zones.info(zone).patterns:
			var dumps := []
			for k in 2:
				seed(k * 7919 + 1)
				var r := RoomGen.new(5, zone, 100.0, 0.7, 14.0, true, 11)
				Patterns.make(str(e[0]), r)
				var d := []
				for h in r.hazards:
					d.append([h.id, h.kind, h.lane, snappedf(h.x, 0.001), snappedf(h.y, 0.001)])
				for c in r.pickups:
					d.append([c.kind, c.lane, snappedf(c.x, 0.001), snappedf(c.y, 0.001)])
				for s in r.staff:
					d.append([s.lane, snappedf(float(s.x), 0.001), s.job])
				dumps.append(str(d))
			t.check(dumps[0] == dumps[1], "%s in %s builds only from its seed" % [e[0], zone])


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


## An average bot gets through every pattern early in a run: each pattern
## repeated over 200 m at the difficulty and speed of the first zones.
func test_patterns_fair(t) -> void:
	var seen := {}
	for zone in Zones.ORDER:
		for e in Zones.info(zone).patterns:
			var name := str(e[0])
			if seen.has(name):
				continue
			seen[name] = true
			var d := maxf(0.25, float(e[2]))
			for s in 2:
				var cfg := {"mode": "course", "speed_from": d * 3000.0,
					"def": {"id": "fair", "name": name, "zone": zone, "length": 200.0, "d0": d, "d1": d, "patterns": [name], "seed": hash([name, s, "fair"])},
					"pilots": [{"id": 1, "name": "Bot", "bot": true}]}
				var run := _bot_run(cfg, "average", 60.0)
				var p := run.pilots[0]
				t.check(p.alive() and p.x >= run.finish_x, "an average bot gets through %s at difficulty %.2f (seed %d: crashed at %.0f m by %s)" % [name, d, s, p.x, p.stats.get("killed_by", "-")])


func test_gadgets(t) -> void:
	# The Jammer stops the first seekers.
	var run := Run.new({"mode": "course", "def": {"id": "j", "name": "j", "zone": "lab", "length": 400.0, "d0": 0.5, "d1": 0.5, "patterns": ["seeker_salvo"], "seed": 5},
		"pilots": [{"id": 1, "name": "Bot", "gadgets": ["jammer", "shield"]}]})
	var bot := Autopilot.new("expert", 5)
	var jammed := 0
	while not run.finished and run.time < 60.0:
		run.step({1: bot.think(run, run.pilots[0])})
		for e in run.take_events():
			if e.type == "jammed":
				jammed += 1
	t.check(jammed == Run.JAMS, "the Jammer stops %d seekers (%d)" % [Run.JAMS, jammed])
	# A shield takes one hit.
	run = Run.new({"mode": "endless", "seed": 3, "pilots": [{"id": 1, "name": "P", "gadgets": ["shield"]}]})
	var hits := []
	while run.time < 60.0 and run.pilots[0].alive():
		run.step({1: RunInput.NONE})
		for e in run.take_events():
			if e.type in ["shield", "crash"]:
				hits.append(e.type)
	t.check(hits.size() >= 2 and hits[0] == "shield" and hits[1] == "crash", "a shield takes the first hit and the next one crashes (%s)" % [hits])
