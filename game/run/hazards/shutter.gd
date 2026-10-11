class_name Shutter
extends Hazard
## A blast door that slams shut across one lane as the run reaches it. Two
## lanes are always left open; a shutter still closing can be slipped under.

const THICK := 0.3
const CLOSE_TIME := 0.5
const TOP := 8.0

## Starts closing when the run is this many seconds away.
var lead := 0.85
var t0 := -1.0


func _init() -> void:
	super("shutter")


func _bottom(t: float) -> float:
	if t0 < 0.0:
		return TOP
	return TOP * (1.0 - clampf((t - t0) / CLOSE_TIME, 0.0, 1.0))


func step(run, _dt: float) -> void:
	if t0 < 0.0:
		var speed: float = maxf(run.speed_now, 1.0)
		if run.trigger_x >= x - lead * speed:
			t0 = run.time
		state = "open"
		return
	phase = clampf((run.time - t0) / CLOSE_TIME, 0.0, 1.0)
	state = "closing" if phase < 1.0 else "shut"


func shapes_at(t: float, run) -> Array:
	var bottom := _bottom(t)
	if t0 < 0.0:
		# Not started yet: plan as if it's shut by the time you get there.
		var speed: float = maxf(run.speed_now, 1.0) if run else 10.0
		var arrive: float = run.time + (x - run.trigger_x) / speed if run else t
		if t >= arrive - lead * 0.5:
			bottom = 0.0
	if bottom >= TOP - 0.05:
		return []
	return [Hazard.box(x - THICK, bottom, x + THICK, TOP, float(lane))]


func extent() -> Vector2:
	return Vector2(x - 0.6, x + 0.6)
