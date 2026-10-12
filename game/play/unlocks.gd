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

## Suits that open with a rank rather than credits (the rest cost what
## [constant PilotLooks.SUITS] says; a cost of 0 is free from the start).
const SUIT_RANKS := {"night": 2, "moonlight": 6, "chrome": 10}

static var _suits := {}


## Every suit: id -> {name, main, accent, and "rank" or "price"}, in
## [constant PilotLooks.ORDER].
static func suits() -> Dictionary:
	if not _suits.is_empty():
		return _suits
	for id in PilotLooks.ORDER:
		var p: Dictionary = PilotLooks.suit(id)
		var e := {"name": str(p.name), "main": p.main, "accent": p.accent}
		if SUIT_RANKS.has(id):
			e["rank"] = int(SUIT_RANKS[id])
		elif int(p.cost) <= 0:
			e["rank"] = 0
		else:
			e["price"] = int(p.cost)
		_suits[id] = e
	return _suits


static func suit_order() -> Array:
	return PilotLooks.ORDER


static func suit(id: String) -> Dictionary:
	var all := suits()
	return all.get(id, all[PilotLooks.ORDER[0]])


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
