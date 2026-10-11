class_name GunDrone
extends Hazard
## Halberd's gun drone. It hangs at one spot in the far or near lane and
## fires slow bolts straight across the lanes, so the lane you dodge into
## matters.

const RADIUS := 0.6
const BOLT_RADIUS := 0.3
## Lanes a second a bolt crosses.
const BOLT_SPEED := 2.2
const FIRST := 0.4

## Starts firing when the run is this far before it.
var range_before := 16.0
var every := 1.1
var shots := 3
## Bolts already fired: [time, y, from_lane, to_lane].
var bolts := []
var t0 := -1.0


func _init() -> void:
	super("gun_drone")
	smashable = true


func step(run, _dt: float) -> void:
	if dead:
		bolts.clear()
		return
	if t0 < 0.0:
		if run.trigger_x >= x - range_before:
			t0 = run.time
		state = "idle"
		return
	var since: float = run.time - t0
	var next := FIRST + bolts.size() * every
	state = "charge" if bolts.size() < shots and since > next - 0.4 else "idle"
	phase = clampf((since - (next - 0.4)) / 0.4, 0.0, 1.0)
	if bolts.size() < shots and since >= next:
		var to := 0.0 if lane >= 1 else 2.0
		bolts.append([run.time, run.aim_y() + 0.8 if bolts.size() % 2 == 0 else y, float(lane), to])
		state = "attack"


## Where bolt b is at time t: Vector3(x, y, lane), lane < -1 or > 3 when gone.
func bolt_at(b: Array, t: float) -> Vector3:
	var from := float(b[2])
	var to := float(b[3])
	var dir := signf(to - from)
	var l := from + dir * BOLT_SPEED * (t - float(b[0]))
	return Vector3(x - 0.6, float(b[1]), l)


func shapes_at(t: float, _run) -> Array:
	var out := []
	if dead:
		return out
	out.append(Hazard.seg(x, y, x, y, RADIUS, float(lane)))
	for b in bolts:
		var p := bolt_at(b, t)
		if p.z > -0.8 and p.z < 2.8:
			out.append(Hazard.seg(p.x, p.y, p.x, p.y, BOLT_RADIUS, p.z))
	return out


func extent() -> Vector2:
	return Vector2(x - 1.4, x + 1.0)


func behind(px: float) -> bool:
	return x < px - 4.0
