class_name Zapper
extends Hazard
## Two capacitors with an arc between them. A zapper can fill one lane,
## stand across two (one end in each), spin slowly about its middle, or ride
## up and down. The commonest hazard.

const RADIUS := 0.24

## Half the arc's length.
var half := 1.5
## Angle from flat, in radians (0 lies along the run, PI/2 stands upright).
var angle := PI * 0.5
## Radians a second it turns (0 for still).
var spin := 0.0
## The far end's lane when it stands across two lanes (-1: same lane).
var lane_b := -1
## Rides up and down this far (metres) every `bob_period` seconds.
var bob := 0.0
var bob_period := 2.0


func _init() -> void:
	super("zapper")


## The two ends at run time t.
func ends_at(t: float) -> Array:
	var a := angle + spin * (t - born)
	var cy := y + (bob * sin(TAU * (t - born) / bob_period) if bob > 0.0 else 0.0)
	var d := Vector2(cos(a), sin(a)) * half
	return [Vector2(x, cy) - d, Vector2(x, cy) + d]


func shapes_at(t: float, _run) -> Array:
	var e := ends_at(t)
	var la := float(lane)
	var lb := float(lane_b if lane_b >= 0 else lane)
	return [Hazard.seg(e[0].x, e[0].y, e[1].x, e[1].y, RADIUS, la, lb)]


func extent() -> Vector2:
	var r := half + 0.5 if spin != 0.0 else absf(cos(angle)) * half + 0.5
	return Vector2(x - r, x + r)
