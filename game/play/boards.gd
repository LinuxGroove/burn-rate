class_name Boards
extends RefCounted
## The online boards and which one a run goes on. The game server writes
## them (game-server's `modules/src/games/burn-rate.ts`) from the runs
## [method Session.report_run] sends it:
##   distance_<pace>          endless with lanes, metres
##   distance_classic_<pace>  endless in Classic, metres
##   daily                    today's Daily Flight, metres
##   course_<id>              a course's time in milliseconds (lowest first)

## The boards the Leaderboards screen offers, by page: [[board, title], ...].
static func endless_boards() -> Array:
	var out := []
	for lanes in [true, false]:
		for pace in ["normal", "calm", "fast"]:
			out.append([board_for_endless(pace, lanes), "%s, %s" % ["Lanes" if lanes else "Classic", pace.capitalize()]])
	return out


static func course_boards() -> Array:
	var out := []
	for id in Courses.ids():
		var d := Courses.get_def(id)
		out.append(["course_" + id, "%s: %s" % [Zones.display_name(str(d.zone)), d.name]])
	return out


static func board_for_endless(pace: String, lanes: bool) -> String:
	return "distance_%s" % pace if lanes else "distance_classic_%s" % pace


## The board and score a finished run goes on: [board, score], or [] for
## runs that don't post (party, tutorial, unfinished courses).
static func entry_for(r: Dictionary) -> Array:
	match str(r.get("mode", "")):
		"endless":
			return [board_for_endless(str(r.get("pace", "normal")), bool(r.get("lanes", true))), int(r.get("distance", 0))]
		"daily":
			if str(r.get("date", "")) != Flights.today():
				return []
			return ["daily", int(r.get("distance", 0))]
		"course":
			var stats: Dictionary = r.get("stats", {})
			if stats.has("finish_time"):
				return ["course_" + str(r.get("course", "")), int(round(float(stats.finish_time) * 1000.0))]
	return []
