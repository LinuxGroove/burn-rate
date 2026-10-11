class_name Walker
extends Hazard
## One of Halberd's walking robots: the Raptor and Trilobite pace the floor
## (or hang from the ceiling rails), the QuadOrb rolls at you along its lane.

## What it is: "raptor", "trilobite" or "orb".
var body := "raptor"
var ceiling := false
## Paces from x - pace to x + pace.
var pace := 2.0
var pace_speed := 1.6
## Rolls back along the run at this speed once triggered (orbs).
var roll := 0.0
var trigger := 0.0
var t0 := -1.0
var x0 := 0.0
var size := Vector2(2.0, 1.9)


func _init() -> void:
	super("walker")
	smashable = true


func setup(p_body: String, on_ceiling := false) -> Walker:
	body = p_body
	ceiling = on_ceiling
	match body:
		"raptor":
			size = Vector2(2.4, 2.1)
		"trilobite":
			size = Vector2(2.2, 1.3)
		"orb":
			size = Vector2(1.3, 1.3)
			pace = 0.0
	x0 = x
	return self


func pos_at(t: float, run) -> float:
	if roll > 0.0:
		if t0 < 0.0:
			return x0
		return x0 - roll * (t - t0)
	if pace <= 0.0:
		return x0
	return x0 + pace * sin((t - born) * pace_speed / maxf(pace, 0.1))


func step(run, _dt: float) -> void:
	if dead:
		return
	if roll > 0.0 and t0 < 0.0 and run.trigger_x >= trigger:
		t0 = run.time
	x = pos_at(run.time, run)
	state = "roll" if roll > 0.0 and t0 >= 0.0 else ("walk" if pace > 0.0 else "idle")
	if roll > 0.0 and x < run.trigger_x - 30.0:
		dead = true


func shapes_at(t: float, run) -> Array:
	if dead:
		return []
	var px := pos_at(t, run)
	var hw := size.x * 0.5
	if ceiling:
		return [Hazard.box(px - hw, Shutter.TOP - size.y, px + hw, Shutter.TOP, float(lane))]
	return [Hazard.box(px - hw, 0.0, px + hw, size.y, float(lane))]


func extent() -> Vector2:
	var reach := pace + size.x
	return Vector2(x - reach, x + reach)


func behind(px: float) -> bool:
	return dead or extent().y < px - 3.0
