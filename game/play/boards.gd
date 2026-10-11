class_name Boards
extends RefCounted
## The online boards a solo run goes on, and posting to them. The boards
## live on the LinuxGroove game server (declared in game-server's
## `modules/src/games/burn-rate.ts`); runs post with `core.score_submit`:
##   distance_<pace>          endless with lanes, metres
##   distance_classic_<pace>  endless in Classic, metres
##   daily                    today's Daily Flight, metres
##   course_<id>              a course's time in milliseconds (lowest first)
## Posting never blocks or fails a run: offline, with online play off, or
## from tests, it does nothing.

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


## Posts a run in the background, if online play is on and there's a
## network. Session can take this over by having `submit_run(result)`.
static func submit(r: Dictionary) -> void:
	if Session.has_method("submit_run"):
		Session.call("submit_run", r)
		return
	var entry := entry_for(r)
	if entry.is_empty() or int(entry[1]) <= 0:
		return
	if DisplayServer.get_name() == "headless" or not LGOnline.is_enabled() or not LGNetwork.is_up():
		return
	_post(entry[0], int(entry[1]))


static func _post(board: String, score: int) -> void:
	if not await LGOnline.connect_async(Progress.pilot_name(), GameConfig.GAME_ID):
		return
	await LGOnline.rpc_async("core.score_submit", {"board": board, "score": score})


## The player's online record on the Leaderboards screen, from the stats
## the server keeps (runs, best distance, party races and wins).
static func record_text(stats: Dictionary) -> String:
	var runs := int(stats.get("runs", 0))
	var races := int(stats.get("races", stats.get("rounds", 0)))
	if runs == 0 and races == 0:
		return "Nothing online yet. Fly a run with online play on to start your record."
	var parts := []
	if runs > 0:
		parts.append(_count(runs, "run", "runs"))
	var best := int(stats.get("best", 0))
	if best > 0:
		parts.append("best %s" % GameConfig.meters(best))
	if races > 0:
		parts.append(_count(races, "party race", "party races"))
		parts.append(_count(int(stats.get("wins", 0)), "win", "wins"))
	return "Your online record: %s." % ", ".join(parts)


static func _count(n: int, one: String, many: String) -> String:
	return "%s %s" % [GameConfig.grouped(n), one if n == 1 else many]
