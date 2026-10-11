class_name Laser
extends Hazard
## A laser across one lane at one height. It charges for a moment once the
## run reaches it, with emitters glowing at both edges of the screen, then
## fires across the whole screen.

const RADIUS := 0.28
## How far either side of where it started the beam reaches.
const REACH_BACK := 24.0
const REACH_AHEAD := 60.0

## The run's x when it starts charging.
var trigger := 0.0
var charge := 1.6
var fire := 0.9
## When it started charging (-1 until then).
var t0 := -1.0
## The run's x when it started.
var at_x := 0.0


func _init() -> void:
	super("laser")


func step(run, _dt: float) -> void:
	if t0 < 0.0:
		if run.trigger_x >= trigger:
			t0 = run.time
			at_x = run.trigger_x
			state = "charge"
		return
	var since: float = run.time - t0
	if since < charge:
		state = "charge"
		phase = since / charge
	elif since < charge + fire:
		state = "fire"
		phase = (since - charge) / fire
	else:
		state = "done"
		dead = true


func shapes_at(t: float, _run) -> Array:
	if t0 < 0.0:
		return []
	var since := t - t0
	if since < charge or since > charge + fire:
		return []
	return [Hazard.seg(at_x - REACH_BACK, y, at_x + REACH_AHEAD, y, RADIUS, float(lane))]


func extent() -> Vector2:
	if t0 < 0.0:
		return Vector2(trigger - 2.0, trigger + 2.0)
	return Vector2(at_x - REACH_BACK, at_x + REACH_AHEAD)


func behind(_px: float) -> bool:
	return dead


func warning() -> Dictionary:
	if state == "charge":
		return {"kind": "laser", "lane": lane, "y": y, "t": phase}
	return {}
