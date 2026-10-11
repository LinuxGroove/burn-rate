class_name Unlocks
extends RefCounted
## What a pilot can earn: the prototypes (by rank, from [Packs]), suits (some
## by rank, some for credits) and gadgets (for credits, then two at a time in
## a run). Everything is earned in play; nothing is bought with money.

## Gadgets: id -> name, what it does, price in credits.
const GADGETS := {
	"magnet": {"name": "Magnet", "blurb": "Pulls in credits from the lanes around you.", "price": 300},
	"hints": {"name": "Lane hints", "blurb": "Marks the lanes with trouble coming.", "price": 450},
	"shield": {"name": "Shield", "blurb": "Takes one hit for you.", "price": 900},
	"head_start": {"name": "Head start", "blurb": "Rockets you through the first 650 m.", "price": 1200},
	"jammer": {"name": "Seeker jammer", "blurb": "Seekers lose their lock and fizzle.", "price": 1500},
	"reboot": {"name": "Reboot", "blurb": "Gets you up again after a crash, once.", "price": 2000},
}
const GADGET_ORDER := ["magnet", "hints", "shield", "head_start", "jammer", "reboot"]
## Gadgets taken into one run.
const GADGET_SLOTS := 2

## Suits when the people code has none of its own: id -> name, colours, and
## the rank that opens it or its price.
const SUITS := {
	"kestrel": {"name": "Kestrel", "main": Color(0.12, 0.13, 0.19), "accent": Color(1.0, 0.45, 0.1), "rank": 0},
	"night_shift": {"name": "Night Shift", "main": Color(0.07, 0.08, 0.1), "accent": Color(0.2, 0.85, 0.9), "rank": 1},
	"test_range": {"name": "Test Range", "main": Color(0.86, 0.87, 0.9), "accent": Color(1.0, 0.42, 0.08), "price": 400},
	"halberd": {"name": "Halberd Black", "main": Color(0.05, 0.05, 0.06), "accent": Color(1.0, 0.78, 0.0), "rank": 4},
	"seed_round": {"name": "Seed Round", "main": Color(0.12, 0.32, 0.2), "accent": Color(0.95, 0.8, 0.3), "price": 800},
	"unicorn": {"name": "Unicorn", "main": Color(0.3, 0.16, 0.5), "accent": Color(1.0, 0.45, 0.8), "rank": 8},
	"exit": {"name": "Exit Strategy", "main": Color(0.42, 0.44, 0.48), "accent": Color(0.95, 0.15, 0.2), "price": 1200},
	"ipo": {"name": "IPO Gold", "main": Color(0.75, 0.6, 0.25), "accent": Color(0.98, 0.96, 0.9), "rank": 12},
	"neon": {"name": "Neon", "main": Color(0.04, 0.05, 0.1), "accent": Color(0.25, 1.0, 0.6), "price": 2000},
	"board_room": {"name": "Board Room", "main": Color(0.1, 0.13, 0.3), "accent": Color(0.85, 0.12, 0.25), "rank": 16},
}
const SUIT_ORDER := ["kestrel", "night_shift", "test_range", "halberd", "seed_round", "unicorn", "exit", "ipo", "neon", "board_room"]
const LOOKS_PATH := "res://game/people/looks.gd"

static var _suits := {}
static var _suit_order: Array = []


## Every suit: id -> {name, main, accent, rank or price}. Uses the people
## code's presets when it has them (a `presets()` static that returns
## [{id, name, main, accent}, ...]), opening them by rank and price in turn.
static func suits() -> Dictionary:
	if not _suits.is_empty():
		return _suits
	var presets: Array = []
	if ResourceLoader.exists(LOOKS_PATH):
		var s: Script = load(LOOKS_PATH)
		if s and s.can_instantiate() and (s as GDScript).get_script_method_list().any(_is_presets):
			presets = s.call("presets")
	if presets.is_empty():
		_suits = SUITS.duplicate(true)
		_suit_order = SUIT_ORDER.duplicate()
		return _suits
	for i in presets.size():
		var p: Dictionary = presets[i]
		var id := str(p.get("id", "suit_%d" % i))
		var e := {"name": str(p.get("name", id.capitalize())), "main": p.get("main", Color.DIM_GRAY), "accent": p.get("accent", BurnTheme.ORANGE)}
		# Free first, then a rank or a price in turn, rising.
		if i == 0:
			e["rank"] = 0
		elif i % 2 == 1:
			e["rank"] = 1 + i * 2
		else:
			e["price"] = 300 * i
		for k in p:
			if not e.has(k):
				e[k] = p[k]
		_suits[id] = e
		_suit_order.append(id)
	return _suits


static func _is_presets(m: Dictionary) -> bool:
	return str(m.name) == "presets"


static func suit_order() -> Array:
	suits()
	return _suit_order


static func suit(id: String) -> Dictionary:
	var all := suits()
	return all.get(id, all[suit_order()[0]])


static func gadget(id: String) -> Dictionary:
	return GADGETS.get(id, {})


## The rank a prototype opens at.
static func pack_rank(pack: String) -> int:
	return int(Packs.spec(pack).get("rank", 0))


## What opens at exactly this rank: [{kind, id, name}].
static func opened_at(rank: int) -> Array:
	var out := []
	for k in Packs.ORDER:
		if pack_rank(k) == rank:
			out.append({"kind": "pack", "id": k, "name": Packs.display_name(k)})
	for id in suit_order():
		var s: Dictionary = suits()[id]
		if s.has("rank") and int(s.rank) == rank and rank > 0:
			out.append({"kind": "suit", "id": id, "name": "%s suit" % s.name})
	return out


## The next thing a rank will open, for "Rank 6 opens the K-3".
static func next_after(rank: int) -> Dictionary:
	var best := {}
	for r in range(rank + 1, rank + 40):
		var list := opened_at(r)
		if not list.is_empty():
			best = list[0].duplicate()
			best["rank"] = r
			return best
	return best


## A pack's handling as 0-1 bars for the hangar: lift, drop, float, lanes.
static func handling(pack: String) -> Dictionary:
	var s := Packs.spec(pack)
	var rise := float(s.rise)
	var thrust := float(s.thrust)
	if float(s.get("pulse", 0.0)) > 0.0:
		thrust = float(s.kick) / float(s.pulse)
	return {
		"Lift": clampf((thrust - float(s.gravity)) / 40.0 * 0.6 + rise / 14.0 * 0.4, 0.05, 1.0),
		"Drop": clampf(float(s.fall) / 18.0, 0.05, 1.0),
		"Float": clampf(1.0 - float(s.gravity) / 46.0, 0.05, 1.0),
		"Lanes": clampf(0.1 / float(s.lane), 0.05, 1.0),
	}
