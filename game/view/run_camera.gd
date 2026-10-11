class_name RunCamera
extends Camera3D
## The run's camera: beside the building, level, looking in. It only ever
## slides sideways with the run. It never turns, rolls, zooms or shakes
## (some players get motion sick), so speed shows in how fast the tower
## passes, never in the lens.
##
## The lens keeps its width: every screen shape sees the same stretch of the
## course ahead, and taller screens see more above and below.

## Metres of course across the screen at the middle lane.
const WIDTH := 18.0
## Party races show more, so everyone fits.
const PARTY_WIDTH := 22.0
## How far from the middle lane, and how far it looks down.
const DISTANCE := 14.8
const TILT := 12.0
## The middle of the room's height it frames.
const AIM_Y := 3.6
## Where the pilot sits across the screen (0 left edge, 1 right).
const PILOT_AT := 0.27

var run: Run
var me := 1
var width := WIDTH


func setup(p_run: Run, p_me := 1) -> void:
	run = p_run
	me = p_me
	width = PARTY_WIDTH if run.mode == "party" else WIDTH
	keep_aspect = Camera3D.KEEP_WIDTH
	var dist := DISTANCE * width / WIDTH
	fov = rad_to_deg(2.0 * atan(width * 0.5 / dist))
	near = 0.5
	far = 400.0
	rotation_degrees = Vector3(-TILT, 0.0, 0.0)
	position = Vector3(0.0, AIM_Y + dist * tan(deg_to_rad(TILT)), RunView.lane_z(1.0) + dist)
	follow()
	reset_physics_interpolation()


## Moves to match the run; call once a tick.
func follow() -> void:
	position.x = target_x()


func target_x() -> float:
	if run.mode == "party":
		return run.cam_x
	var p := run.pilot(me)
	if p == null:
		return run.distance()
	return p.x + width * (0.5 - PILOT_AT)
