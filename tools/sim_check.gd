extends Node
## Flies bots through runs headless and prints how they did:
##   godot --headless --path . tools/sim_check.tscn -- --skill=average --runs=5 [--mode=endless] [--pace=normal] [--classic] [--pack=k1] [--max=6000]

func _ready() -> void:
	var skill := "average"
	var runs := 3
	var mode := "endless"
	var pace := "normal"
	var lanes := true
	var pack := "k1"
	var max_x := 6000.0
	var course := ""
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skill="): skill = a.trim_prefix("--skill=")
		elif a.begins_with("--runs="): runs = int(a.trim_prefix("--runs="))
		elif a.begins_with("--mode="): mode = a.trim_prefix("--mode=")
		elif a.begins_with("--pace="): pace = a.trim_prefix("--pace=")
		elif a == "--classic": lanes = false
		elif a.begins_with("--pack="): pack = a.trim_prefix("--pack=")
		elif a.begins_with("--max="): max_x = float(a.trim_prefix("--max="))
		elif a.begins_with("--course="): course = a.trim_prefix("--course=")
	var total := 0.0
	var t_start := Time.get_ticks_msec()
	var ticks := 0
	var killers := {}
	for i in runs:
		var cfg := {"mode": mode, "seed": 1000 + i, "pace": pace, "lanes": lanes, "course": course,
			"pilots": [{"id": 1, "name": "Bot", "pack": pack, "bot": true}]}
		var run := Run.new(cfg)
		var bot := Autopilot.new(skill, 77 + i)
		while not run.finished and run.pilots[0].x < max_x:
			var inp := bot.think(run, run.pilots[0])
			run.step({1: inp})
			ticks += 1
			for e in run.take_events():
				if e.type == "crash" and verbose:
					var room := run.course.room_at(e.x)
					print("  crash at %.1f y %.2f vy %.1f lane %.2f->%d by %s in %s (d %.2f) plan %s" % [e.x, e.y, run.pilots[0].vy, e.lane, run.pilots[0].lane_to, e.kind, room.pattern if room else "?", room.d if room else 0.0, bot.plan])
					for h in run.hazards_between(e.x - 3, e.x + 3):
						print("    %s lane %d shapes %s" % [h.kind, h.lane, h.shapes_at(run.time, run)])
		var p := run.pilots[0]
		total += p.x
		var k := str(p.stats.get("killed_by", "-"))
		killers[k] = int(killers.get(k, 0)) + 1
		print("run %d: %s m in %.0f s, credits %d, best burn x%d, near %d, killed by %s, zone %s" % [i, int(p.x), run.time, p.credits, p.best_burn, int(p.stats.get("near", 0)), k, run.zone()])
	var ms := Time.get_ticks_msec() - t_start
	print("average %d m; %d ticks in %d ms (%.0fx real time); killers %s" % [int(total / runs), ticks, ms, ticks / 60.0 / maxf(ms / 1000.0, 0.001), killers])
	get_tree().quit()
