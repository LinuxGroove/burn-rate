class_name PilotLooks
extends RefCounted
## How a pilot can look: the two bodies, the flight suits and the gear on
## their face. The hangar offers these and saves `player/body` (an index into
## [constant BODIES]) and `player/suit` (a key of [constant SUITS]).
##
## A look is a small Dictionary that travels with the pilot (Run config
## "look", sent as is to other devices): "body", "suit" and optionally
## "skin", "hair" and "style" (indexes into [Person]'s lists). [method
## resolve] fills in the colours for [Person] and [PilotView].

## The bodies, in the order the hangar shows them, with the skin, hair
## colour and hair style a look uses unless it says otherwise.
const BODIES := [
	{"name": "Pilot one", "female": true, "skin": 2, "hair": 1, "style": 0},
	{"name": "Pilot two", "female": false, "skin": 1, "hair": 0, "style": 0},
]

## Flight suits: name, colours (main, accent, trim for the harness and
## boots), the gear on the face ("goggles" or "visor") and its lens colour,
## and a suggested price in credits (0: from the start).
const SUITS := {
	"kestrel": {"name": "Kestrel Test", "main": Color(0.13, 0.14, 0.18), "accent": Color(1.0, 0.45, 0.1), "trim": Color(0.06, 0.06, 0.07), "gear": "goggles", "lens": Color(1.0, 0.6, 0.2), "cost": 0},
	"night": {"name": "Night Shift", "main": Color(0.05, 0.055, 0.07), "accent": Color(0.15, 0.85, 1.0), "trim": Color(0.12, 0.13, 0.15), "gear": "visor", "lens": Color(0.2, 0.85, 1.0), "cost": 400},
	"flare": {"name": "Flare", "main": Color(0.86, 0.87, 0.9), "accent": Color(0.9, 0.12, 0.12), "trim": Color(0.1, 0.1, 0.11), "gear": "goggles", "lens": Color(0.95, 0.3, 0.2), "cost": 600},
	"volt": {"name": "Volt", "main": Color(0.24, 0.11, 0.42), "accent": Color(1.0, 0.85, 0.1), "trim": Color(0.08, 0.06, 0.1), "gear": "visor", "lens": Color(1.0, 0.85, 0.2), "cost": 800},
	"canopy": {"name": "Canopy", "main": Color(0.3, 0.33, 0.19), "accent": Color(0.85, 0.55, 0.25), "trim": Color(0.25, 0.16, 0.09), "gear": "goggles", "lens": Color(0.5, 0.8, 0.5), "cost": 800},
	"moonlight": {"name": "Moonlight", "main": Color(0.1, 0.15, 0.32), "accent": Color(0.82, 0.85, 0.92), "trim": Color(0.05, 0.07, 0.14), "gear": "visor", "lens": Color(0.7, 0.8, 1.0), "cost": 1200},
	"chrome": {"name": "Prototype Chrome", "main": Color(0.62, 0.65, 0.7), "accent": Color(0.2, 0.5, 1.0), "trim": Color(0.15, 0.16, 0.18), "gear": "visor", "lens": Color(0.3, 0.6, 1.0), "cost": 2000},
	"gold": {"name": "Investor Gold", "main": Color(0.8, 0.6, 0.18), "accent": Color(0.08, 0.08, 0.09), "trim": Color(0.12, 0.1, 0.06), "gear": "visor", "lens": Color(1.0, 0.75, 0.3), "cost": 3500},
}
## The order the hangar lists them in.
const ORDER := ["kestrel", "night", "flare", "volt", "canopy", "moonlight", "chrome", "gold"]


static func suit(id: String) -> Dictionary:
	return SUITS.get(id, SUITS["kestrel"])


## A look for a body and suit.
static func make(body := 0, suit_id := "kestrel", extra := {}) -> Dictionary:
	var l := {"body": clampi(body, 0, BODIES.size() - 1), "suit": suit_id if SUITS.has(suit_id) else "kestrel"}
	l.merge(extra, true)
	return l


## This player's look, from their settings.
static func mine() -> Dictionary:
	return make(int(LGSettings.get_value("player", "body", 0)), str(LGSettings.get_value("player", "suit", "kestrel")))


## A varied look for a bot or a guest, the same every time for a seed.
static func random(seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return make(r.randi() % BODIES.size(), ORDER[r.randi() % ORDER.size()], {"skin": r.randi() % 5, "hair": r.randi() % 6, "style": r.randi() % 4})


## The look with everything [Person] needs: "female", "skin", "hair",
## "style", "main", "accent", "trim", "gear" and "lens" (kept if already
## there).
static func resolve(look: Dictionary) -> Dictionary:
	var out := look.duplicate()
	var s := suit(str(look.get("suit", "kestrel")))
	var body: Dictionary = BODIES[clampi(int(look.get("body", 0)), 0, BODIES.size() - 1)]
	if not out.has("female"):
		out["female"] = bool(body.female)
	for k in ["skin", "hair", "style"]:
		if not out.has(k):
			out[k] = body[k]
	for k in ["main", "accent", "trim", "gear", "lens"]:
		if not out.has(k):
			out[k] = s[k]
	return out
