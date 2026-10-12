class_name Hazard
extends RefCounted
## Something in the run that ends it if you touch it: a zapper, a laser, a
## seeker, a shutter, a drone or a walker. Hazards are worked out in the run's
## own coordinates (x along the run, y up from the floor, lanes 0 near, 1 mid
## and 2 far) with no nodes, so the same seed always plays the same way.
##
## Each kind fills [method shapes_at] with simple shapes for a moment in time:
## capsules (a segment with a radius, a circle when both ends meet) and boxes,
## each with the lanes it covers. The run checks pilots against them, and
## bots ask about moments ahead to plan.

enum { SEG, BOX }

## Pilots touch a shape when they're this close to its lane (in lanes).
const LANE_HIT := 0.62
## And skim it from the next lane when this close.
const LANE_SKIM := 1.4

static var _next_id := 1

var id := 0
var kind := ""
## Where it is along the run; most kinds stay near here.
var x := 0.0
var y := 0.0
var lane := 1
## Gone for good: destroyed, fired and finished, or fizzled.
var dead := false
## Vehicles can smash it (drones, walkers, seekers).
var smashable := false
## The run's time when this hazard was made.
var born := 0.0
## Extra state the view reads (what it's doing right now).
var state := ""
## 0 to 1 of the way through its current state, for the view.
var phase := 0.0


func _init(p_kind := "") -> void:
	id = _next_id
	_next_id += 1
	kind = p_kind


## Advances to the run's current moment.
func step(_run, _dt: float) -> void:
	pass


## Shapes it covers at run time `t` (now, or ahead for planning). Each shape
## is [type, ax, ay, bx, by, r, lane_a, lane_b]: a SEG from (ax, ay) to
## (bx, by) with radius r, its lane going from lane_a at a to lane_b at b; or
## a BOX from (ax, ay) to (bx, by) in lanes lane_a to lane_b.
func shapes_at(_t: float, _run) -> Array:
	return []


## The span of the run it covers, for finding it quickly: [x_min, x_max].
func extent() -> Vector2:
	return Vector2(x - 2.0, x + 2.0)


## True once it can't matter to a pilot at `px` any more.
func behind(px: float) -> bool:
	return extent().y < px - 2.0


## Shown at the right edge before it arrives (seekers, lasers).
func warning() -> Dictionary:
	return {}


# --- Geometry -------------------------------------------------------------

## How far a pilot's body (a vertical capsule from y0 to y1 at x with radius
## pr, in lane pl) is from a shape: [clearance in metres (negative when
## touching), lane difference at the closest point].
static func clearance(shape: Array, px: float, y0: float, y1: float, pr: float, pl: float) -> Vector2:
	if int(shape[0]) == BOX:
		var dx := maxf(maxf(float(shape[1]) - px, 0.0), px - float(shape[3]))
		var dy := maxf(maxf(float(shape[2]) - y1, 0.0), y0 - float(shape[4]))
		var la := float(shape[6])
		var lb := float(shape[7])
		var dl := 0.0
		if pl < minf(la, lb):
			dl = pl - minf(la, lb)
		elif pl > maxf(la, lb):
			dl = pl - maxf(la, lb)
		return Vector2(sqrt(dx * dx + dy * dy) - pr, dl)
	# Capsule against the body's vertical segment.
	var ax := float(shape[1])
	var ay := float(shape[2])
	var bx := float(shape[3])
	var by := float(shape[4])
	var res := _seg_seg(ax, ay, bx, by, px, y0, px, y1)
	var lane_here := lerpf(float(shape[6]), float(shape[7]), res.y)
	return Vector2(res.x - float(shape[5]) - pr, pl - lane_here)


## Distance between segments A (a0-a1) and B (b0-b1) in 2D, and how far
## along A the closest point is (0 to 1).
static func _seg_seg(a0x: float, a0y: float, a1x: float, a1y: float, b0x: float, b0y: float, b1x: float, b1y: float) -> Vector2:
	var d1x := a1x - a0x
	var d1y := a1y - a0y
	var d2x := b1x - b0x
	var d2y := b1y - b0y
	var rx := a0x - b0x
	var ry := a0y - b0y
	var a := d1x * d1x + d1y * d1y
	var e := d2x * d2x + d2y * d2y
	var f := d2x * rx + d2y * ry
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return Vector2(sqrt(rx * rx + ry * ry), 0.0)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1x * rx + d1y * ry
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1x * d2x + d1y * d2y
			var denom := a * e - b * b
			if denom > 1e-9:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var cx := a0x + d1x * s - (b0x + d2x * t)
	var cy := a0y + d1y * s - (b0y + d2y * t)
	return Vector2(sqrt(cx * cx + cy * cy), s)


static func seg(ax: float, ay: float, bx: float, by: float, r: float, la: float, lb := -1.0) -> Array:
	return [SEG, ax, ay, bx, by, r, la, la if lb < 0.0 else lb]


static func box(x0: float, y0: float, x1: float, y1: float, la: float, lb := -1.0) -> Array:
	return [BOX, minf(x0, x1), minf(y0, y1), maxf(x0, x1), maxf(y0, y1), 0.0, la, la if lb < 0.0 else lb]
