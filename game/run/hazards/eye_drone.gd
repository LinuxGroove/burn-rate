class_name EyeDrone
extends Hazard
## Halberd's eye drone. It flies in at the right of the screen, hovers there
## following your height, charges, then dashes back along its lane.

const RADIUS := 0.55
const LOOK := 1.5
const CHARGE := 0.7
const DASH_SPEED := 20.0
## Where it hovers, ahead of the run.
const AHEAD := 10.5

var trigger := 0.0
var t0 := -1.0
var t_dash := -1.0
var dash_x := 0.0
var fixed_y := -1.0


func _init() -> void:
	super("eye_drone")
	smashable = true


func step(run, _dt: float) -> void:
	if dead:
		return
	if t0 < 0.0:
		x = trigger + AHEAD
		if run.trigger_x >= trigger:
			t0 = run.time
			y = run.aim_y() + 0.6 if fixed_y < 0.0 else fixed_y
			state = "look"
		return
	var since: float = run.time - t0
	if since < LOOK + CHARGE:
		# Flies in from beyond the right edge, then keeps pace.
		x = run.trigger_x + AHEAD + maxf(0.0, 1.0 - since / 0.4) * 6.0
		if since < LOOK:
			state = "look"
			phase = since / LOOK
			if fixed_y < 0.0:
				y = move_toward(y, run.aim_y() + 0.6, 2.6 * run.DT)
		else:
			state = "charge"
			phase = (since - LOOK) / CHARGE
		return
	if t_dash < 0.0:
		t_dash = run.time
		dash_x = x
	state = "attack"
	x = dash_x - DASH_SPEED * (run.time - t_dash)
	if x < run.trigger_x - 30.0:
		dead = true


func shapes_at(t: float, run) -> Array:
	if dead or t0 < 0.0:
		return []
	var px := x
	if t_dash >= 0.0:
		px = dash_x - DASH_SPEED * (t - t_dash)
	elif run:
		var dash_at := t0 + LOOK + CHARGE
		var hover_x: float = x + run.speed_now * (minf(t, dash_at) - run.time)
		px = hover_x - DASH_SPEED * maxf(0.0, t - dash_at)
	return [Hazard.seg(px, y, px, y, RADIUS, float(lane))]


func extent() -> Vector2:
	return Vector2(x - 0.8, x + 0.8)


func behind(px: float) -> bool:
	return dead or (t_dash >= 0.0 and x < px - 3.0)
