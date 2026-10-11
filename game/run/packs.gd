class_name Packs
extends RefCounted
## The six prototype jetpacks Kestrel Lift built, and how each one flies.
## A pack is the same model in its own colours; the numbers here are all
## that changes how it handles.
##
##   thrust   upward acceleration while fly is held (m/s²)
##   gravity  downward acceleration (m/s²)
##   rise     fastest climb (m/s)
##   fall     fastest drop (m/s)
##   lane     seconds to move one lane
##   pulse    > 0: thrust comes in kicks this many seconds apart
##   armour   hits it shrugs off each run (costs the Burn instead)

const ORDER := ["k1", "k2", "k3", "k4", "k5", "k6"]

const SPECS := {
	"k1": {
		"name": "K-1 Steady", "short": "K-1",
		"blurb": "The first one that worked. Smooth climb, honest fall.",
		"thrust": 50.0, "gravity": 30.0, "rise": 9.5, "fall": 13.0, "lane": 0.2,
		"rank": 0, "color": Color(1.0, 0.45, 0.1), "flame": Color(1.0, 0.55, 0.15),
	},
	"k2": {
		"name": "K-2 Kick", "short": "K-2",
		"blurb": "Twice the burners. Shoots up, drops like a stone.",
		"thrust": 72.0, "gravity": 44.0, "rise": 12.5, "fall": 18.0, "lane": 0.2,
		"rank": 3, "color": Color(0.95, 0.2, 0.25), "flame": Color(1.0, 0.3, 0.25),
	},
	"k3": {
		"name": "K-3 Glide", "short": "K-3",
		"blurb": "Fold-out fins. Falls slowly, so you can float over trouble.",
		"thrust": 40.0, "gravity": 17.0, "rise": 8.0, "fall": 6.5, "lane": 0.22,
		"rank": 6, "color": Color(0.2, 0.8, 0.6), "flame": Color(0.35, 1.0, 0.7),
	},
	"k4": {
		"name": "K-4 Pulse", "short": "K-4",
		"blurb": "Fires in kicks while you hold. Tap it to hop, hold it to climb.",
		"thrust": 0.0, "gravity": 28.0, "rise": 11.0, "fall": 14.0, "lane": 0.2, "pulse": 0.16, "kick": 6.2,
		"rank": 10, "color": Color(0.55, 0.35, 1.0), "flame": Color(0.7, 0.5, 1.0),
	},
	"k5": {
		"name": "K-5 Switch", "short": "K-5",
		"blurb": "Side thrusters. Changes lane in half the time.",
		"thrust": 50.0, "gravity": 30.0, "rise": 9.5, "fall": 13.0, "lane": 0.1,
		"rank": 14, "color": Color(0.15, 0.7, 1.0), "flame": Color(0.3, 0.8, 1.0),
	},
	"k6": {
		"name": "K-6 Mule", "short": "K-6",
		"blurb": "Built for cargo. Heavy, strong, and it shrugs off one hit a run.",
		"thrust": 64.0, "gravity": 38.0, "rise": 10.0, "fall": 16.0, "lane": 0.26, "armour": 1,
		"rank": 18, "color": Color(0.95, 0.8, 0.2), "flame": Color(1.0, 0.85, 0.3),
	},
}


static func spec(id: String) -> Dictionary:
	return SPECS.get(id, SPECS["k1"])


static func display_name(id: String) -> String:
	return str(spec(id).name)
