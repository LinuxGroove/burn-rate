class_name Pilot
extends RefCounted
## One pilot in a run: where they are, how they're flying, what they're
## riding, their Burn and what they've done. The run moves them (see
## [Run]); views and bots only read them.

enum State { FLY, CRASH, DONE, OUT }

## Burn points needed for each level (x1 to x5).
const BURN_STEPS := [0, 3, 7, 12, 18]
## How long a pilot can touch the floor before their Burn goes.
const FLOOR_GRACE := 0.35
## The pilot's body for hits: a capsule from feet + BODY.x to feet + BODY.y.
const BODY := Vector2(0.25, 1.45)
const BODY_R := 0.3
## Vehicles' bodies, the same way: [from, to, radius].
const VEHICLE_BODY := {
	"raptor": [0.25, 2.3, 0.55],
	"shell": [0.15, 1.5, 0.5],
	"eye": [0.2, 1.8, 0.5],
	"gunner": [0.2, 1.8, 0.5],
}

var id := 1
var name := "Pilot"
var pack := "k1"
var spec: Dictionary = Packs.spec("k1")
var bot := false
## Look: suit colours and body, for views.
var look := {}

var state := State.FLY
var x := 0.0
var y := 0.0
var vy := 0.0
## Where the pilot is between lanes (0 near, 1 mid, 2 far).
var lane := 1.0
var lane_to := 1
var on_floor := true
## Fly held this tick, and for how long.
var flying := false
var held_for := 0.0
var _pulse := 0.0

## "" or the vehicle being ridden: raptor, shell, eye, gunner.
var vehicle := ""
var vehicle_from := 0.0
## Shell: on the ceiling.
var upside := false
## Gunner: seconds to the next shot.
var gun_cool := 0.0

## Seconds left untouchable (after losing a vehicle, a reboot, the head start).
var invuln := 0.0
var shield := 0
var armour := 0
var reboots := 0
## Seekers the Jammer gadget will still stop this run.
var jams := 0
## Head start: metres of rocket left.
var rocket := 0.0

var burn_points := 0
var burn_level := 1
var best_burn := 1
var floor_time := 0.0
## Seconds since the last near miss, for the HUD.
var since_near := 99.0

var credits := 0
## Counters for missions and results.
var stats := {}

## Party races: metres ahead of (or behind) the screen's middle, the time
## left stunned after a hit, and when they went out.
var ahead := 0.0
var stun := 0.0
var out_at := -1.0
var place := 0

## Crash slide.
var slide_speed := 0.0
var crashed_at := -1.0

## Near-miss tracking per hazard: id -> [min clearance in lane, skimmed,
## threaded, last lane difference].
var near := {}


func _init(p_id := 1, p_name := "Pilot", p_pack := "k1") -> void:
	id = p_id
	name = p_name
	set_pack(p_pack)


func set_pack(p_pack: String) -> void:
	pack = p_pack if Packs.SPECS.has(p_pack) else "k1"
	spec = Packs.spec(pack)
	armour = int(spec.get("armour", 0))


func alive() -> bool:
	return state == State.FLY


## The body's capsule for hits: Vector3(from y, to y, radius).
func body() -> Vector3:
	if vehicle != "":
		var b: Array = VEHICLE_BODY[vehicle]
		return Vector3(y + float(b[0]), y + float(b[1]), float(b[2]))
	return Vector3(y + BODY.x, y + BODY.y, BODY_R)


## The middle of the body, for pickups.
func center() -> Vector2:
	var b := body()
	return Vector2(x, (b.x + b.y) * 0.5)


func burn_mult() -> int:
	return burn_level


func add_stat(key: String, n := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n


func max_stat(key: String, v: float) -> void:
	stats[key] = maxf(float(stats.get(key, 0.0)), v)


## Adds Burn points and returns true if the level went up.
func add_burn(points: int) -> bool:
	burn_points += points
	since_near = 0.0
	var lvl := 1
	for i in BURN_STEPS.size():
		if burn_points >= int(BURN_STEPS[i]):
			lvl = i + 1
	var up := lvl > burn_level
	burn_level = lvl
	best_burn = maxi(best_burn, lvl)
	return up


func lose_burn() -> bool:
	var had := burn_points > 0
	burn_points = 0
	burn_level = 1
	return had


## How far into the next Burn level the pilot is, 0 to 1.
func burn_progress() -> float:
	if burn_level >= BURN_STEPS.size():
		return 1.0
	var a := float(BURN_STEPS[burn_level - 1])
	var b := float(BURN_STEPS[burn_level])
	return clampf((burn_points - a) / (b - a), 0.0, 1.0)
