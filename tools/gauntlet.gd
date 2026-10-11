extends Node
## Flies a bot through one pattern at a time and prints how often each one
## crashes it, to find unfair rooms:
##   godot --headless --path . tools/gauntlet.tscn -- --skill=average --seeds=6 [--only=zap_slalom] [--d=0.2,0.6,1.0] [--classic] [--pack=k1]
## Each try is a course of one pattern repeated over 300 m at a fixed
## difficulty, at the speed a run has at that difficulty.

func _ready() -> void:
	var skill := "average"
	var seeds := 6
	var only := ""
	var ds := [0.2, 0.6, 1.0]
	var lanes := true
	var pack := "k1"
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skill="): skill = a.trim_prefix("--skill=")
		elif a.begins_with("--seeds="): seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--only="): only = a.trim_prefix("--only=")
		elif a.begins_with("--d="): ds = Array(a.trim_prefix("--d=").split(",")).map(func(v): return float(v))
		elif a == "--classic": lanes = false
		elif a.begins_with("--pack="): pack = a.trim_prefix("--pack=")
	var seen := {}
	var rows := []
	for zone in Zones.ORDER:
		for e in Zones.info(zone).patterns:
			var name := str(e[0])
			if seen.has(name) or (only != "" and name != only):
				continue
			if not lanes and name in Patterns.LANES_ONLY:
				continue
			seen[name] = true
			var line := "%-14s %-9s" % [name, zone]
			for d in ds:
				var rooms := 0
				var crashes := 0
				for s in seeds:
					var cfg := {"mode": "course", "lanes": lanes, "speed_from": float(d) * 3000.0,
						"def": {"id": "gauntlet", "name": name, "zone": zone, "length": 300.0, "d0": d, "d1": d, "patterns": [name], "seed": hash([name, d, s])},
						"pilots": [{"id": 1, "name": "Bot", "pack": pack, "bot": true}]}
					var run := Run.new(cfg)
					var bot := Autopilot.new(skill, 31 + s)
					var p := run.pilots[0]
					while not run.finished and run.time < 120.0:
						run.step({1: bot.think(run, p)})
						for ev in run.take_events():
							if ev.type == "crash" and verbose:
								var room := run.course.room_at(ev.x)
								print("  %s d%.1f seed %d: crash at %.1f y %.2f vy %.1f lane %.2f->%d by %s (room %d) plan %s" % [name, d, s, ev.x, ev.y, p.vy, ev.lane, p.lane_to, ev.kind, room.index if room else -1, bot.plan])
								for h in run.hazards_between(ev.x - 2.0, ev.x + 14.0):
									print("    %s lane %d %s" % [h.kind, h.lane, h.shapes_at(run.time, run)])
					# Rooms of the pattern passed, and whether it crashed.
					for r in run.course.rooms:
						if r.pattern == name and r.x0 < p.x:
							rooms += 1
					if p.state != Pilot.State.FLY and not (run.finished and p.x >= run.finish_x):
						crashes += 1
				line += "  d%.1f: %d/%d" % [d, crashes, rooms]
			rows.append(line)
			print(line)
	get_tree().quit()
