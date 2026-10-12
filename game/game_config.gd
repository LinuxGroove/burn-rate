class_name GameConfig
extends RefCounted
## Game-wide constants: identity, player limits, setting defaults and the
## input map.

const GAME_ID := "burn-rate"
const TITLE := "Burn Rate"

## This round's own questions at the end of a play test (LGPlaytest), on top
## of the standard ones, and standard ones that don't fit the game. Change
## them for each round of play testing.
const PLAYTEST := {
	"skip": [],
	"questions": [
		{"id": "one_more", "text": "How often did you want one more run straight away?", "kind": "rating"},
		{"id": "lanes", "text": "How easy was it to tell which lane things were in?", "kind": "rating"},
	],
}
## Bump PROTOCOL whenever network messages change; mismatched builds are told
## to update instead of desyncing.
const PROTOCOL := 2
## Pilots in one party race (bots fill the rest).
const MAX_PLAYERS := 8
const MIN_PLAYERS := 1
## Pilots on one screen: up to four on one device.
const MAX_LOCAL := 4
## Quick match fills the race with bots up to a size in this range.
const QUICK_MATCH_SIZE := Vector2i(4, 6)

const SETTING_DEFAULTS := {
	"online": {
		"enabled": true,
		"host": OnlineServer.HOST,
		"port": OnlineServer.PORT,
		"scheme": OnlineServer.SCHEME,
		"server_key": OnlineServer.SERVER_KEY,
	},
	"tutorial": {
		"welcomed": false,
		"hints": true,
	},
	"player": {
		# The pilot's look: body (0 or 1) and suit colours by index.
		"body": 0,
		"suit": "kestrel",
	},
	"play": {
		# calm, normal or fast.
		"pace": "normal",
		# Lanes off is Classic: one lane and one button.
		"lanes": true,
		"ghosts": true,
		"rumble": true,
	},
	"comfort": {
		# Zappers and lasers glow steadily instead of flickering.
		"reduce_flashing": false,
		# Dims the city and the far wall.
		"calm_background": false,
	},
	"video": {
		# 0 low (handhelds), 1 medium, 2 high.
		"detail": 1,
	},
}


## Every in-game action, with keyboard and controller bindings (see LGInput).
## Each local pilot reads them through their own LGSeat.
const ACTIONS := {
	"fly": ["key:Space", "key:Shift", "mouse:left", "joy:a", "axis:rt+"],
	"lane_back": ["key:Up", "key:W", "joy:lb", "joy:up", "axis:ly-"],
	"lane_forward": ["key:Down", "key:S", "joy:rb", "joy:down", "axis:ly+"],
	"pause": ["key:Escape", "key:P", "joy:start"],
	"restart": ["key:R", "joy:y"],
}
## Actions each seat tracks for just_pressed.
const SEAT_ACTIONS := ["fly", "lane_back", "lane_forward", "restart"]


static func version() -> String:
	return LGVersion.current()


## A distance as "1,284 m".
static func meters(m: float) -> String:
	return "%s m" % grouped(int(floor(m)))


## 12345 as "12,345".
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## A course time as 1:23.45 (or 23.45 under a minute).
static func time_text(t: float) -> String:
	if t <= 0.0 or is_inf(t) or is_nan(t):
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	if m > 0:
		return "%d:%05.2f" % [m, s]
	return "%.2f" % s
