class_name Seeker
extends Hazard
## A small rocket. Once the run reaches it, a warning shows at the right edge
## in its lane, following the pilot's height; it locks, then the rocket flies
## in at that height. Change lane, or change height late.

const RADIUS := 0.36
const TRACK := 1.0
const LOCK := 0.45
## Metres a second it flies back along the run (it closes faster than that,
## since the pilot is flying the other way).
const SPEED := 13.0
## How far ahead of the pilot it starts.
const START_AHEAD := 22.0

var trigger := 0.0
var t0 := -1.0
var t_launch := -1.0
var launch_x := 0.0
## -1: the lane of whoever it's after, picked when it starts.
var want_lane := -1
## A height chosen by the course, for party races (-1: the target's height).
var fixed_y := -1.0
## Fizzles (the Jammer gadget).
var jammed := false


func _init() -> void:
	super("seeker")
	smashable = true


func step(run, _dt: float) -> void:
	if dead:
		return
	if t0 < 0.0:
		if run.trigger_x >= trigger:
			t0 = run.time
			if want_lane >= 0:
				lane = want_lane
			else:
				lane = run.aim_lane()
			y = run.aim_y() if fixed_y < 0.0 else fixed_y
			state = "track"
		return
	var since: float = run.time - t0
	if since < TRACK:
		state = "track"
		phase = since / (TRACK + LOCK)
		if fixed_y < 0.0:
			# Follows the pilot's height, a little behind.
			y = move_toward(y, run.aim_y(), 9.0 * run.DT)
	elif since < TRACK + LOCK:
		state = "lock"
		phase = since / (TRACK + LOCK)
	else:
		if t_launch < 0.0:
			t_launch = run.time
			launch_x = run.trigger_x + START_AHEAD
			if jammed:
				dead = true
				state = "fizzle"
				return
		state = "fly"
		x = launch_x - SPEED * (run.time - t_launch)
		if x < run.trigger_x - 30.0:
			dead = true


func shapes_at(t: float, run) -> Array:
	if dead or t0 < 0.0:
		return []
	var lx := launch_x
	var tl := t_launch
	if tl < 0.0:
		# Not launched yet: where it will start from, if the run keeps going.
		if run == null or state != "lock":
			return []
		tl = t0 + TRACK + LOCK
		lx = run.trigger_x + run.speed_now * (tl - run.time) + START_AHEAD
		if t < tl:
			return []
	var sx := lx - SPEED * (t - tl)
	return [Hazard.seg(sx - 0.35, y, sx + 0.35, y, RADIUS, float(lane))]


func extent() -> Vector2:
	if t_launch < 0.0:
		return Vector2(trigger, trigger + START_AHEAD)
	return Vector2(x - 0.8, x + 0.8)


func behind(px: float) -> bool:
	return dead or (t_launch >= 0.0 and x < px - 3.0)


func warning() -> Dictionary:
	if state == "track" or state == "lock":
		return {"kind": "seeker", "lane": lane, "y": y, "t": phase, "locked": state == "lock"}
	return {}
