class_name NetCodec
extends RefCounted
## Packs what a party race sends between devices into small arrays, and
## unpacks it again: each device's controls (one byte per pilot per tick) and
## the host's snapshots of every pilot. Pure functions, so tests use them with
## no network.

## Vehicles by number, for snapshots.
const VEHICLES := ["", "raptor", "shell", "eye", "gunner"]
## A snapshot's numbers for each pilot, in this order. x isn't sent: in a
## party race it's always the screen's middle plus `ahead`.
const FIELDS := [
	"ahead", "y", "vy", "lane", "lane_to", "state", "burn_points", "best_burn", "credits",
	"vehicle", "stun", "invuln", "fly", "upside", "place", "shield", "armour", "out_at",
]
const N := 18
## Pilot states a snapshot may set (the host decides crashes only in solo runs).
## Extrapolating a pilot: ticks of their last controls, then how fast their
## climb or fall eases off each tick.
static var COAST_AFTER := 8
static var COAST := 0.85
const STATES := [Pilot.State.FLY, Pilot.State.CRASH, Pilot.State.DONE, Pilot.State.OUT]


## One tick of a pilot's controls as a byte: bit 0 fly, bits 1-2 the lane
## step plus one.
static func input_byte(inp: RunInput) -> int:
	if inp == null:
		return 2
	return (1 if inp.fly else 0) | ((clampi(inp.lane, -1, 1) + 1) << 1)


## [fly, lane] from an input byte.
static func input_from(b: int) -> Array:
	return [(b & 1) == 1, clampi(((b >> 1) & 3) - 1, -1, 1)]


## Every pilot of a run: [ids, values], values N floats per pilot.
static func pack_pilots(run: Run) -> Array:
	var ids := PackedInt64Array()
	var vals := PackedFloat32Array()
	for p in run.pilots:
		ids.append(p.id)
		vals.append_array(pack_pilot(p))
	return [ids, vals]


static func pack_pilot(p: Pilot) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(N)
	a[0] = p.ahead
	a[1] = p.y
	a[2] = p.vy
	a[3] = p.lane
	a[4] = p.lane_to
	a[5] = p.state
	a[6] = p.burn_points
	a[7] = p.best_burn
	a[8] = p.credits
	a[9] = maxi(0, VEHICLES.find(p.vehicle))
	a[10] = p.stun
	a[11] = p.invuln
	a[12] = 1.0 if p.flying else 0.0
	a[13] = 1.0 if p.upside else 0.0
	a[14] = p.place
	a[15] = p.shield
	a[16] = p.armour
	a[17] = p.out_at
	return a


## The i-th pilot's numbers from a snapshot, by name.
static func unpack_pilot(vals: PackedFloat32Array, i: int) -> Dictionary:
	var d := {}
	var at := i * N
	if at + N > vals.size():
		return d
	for k in N:
		d[FIELDS[k]] = vals[at + k]
	return d


## Sets what the host decides about a pilot: their state, Burn, credits,
## vehicle, stun and place. `age` is how many seconds old the snapshot is,
## so timers carry on from where they were.
static func apply_common(p: Pilot, d: Dictionary, age: float) -> void:
	var st := int(d.state)
	if st >= 0 and st < STATES.size():
		p.state = STATES[st]
	if int(d.burn_points) != p.burn_points:
		p.burn_points = int(d.burn_points)
		var lvl := 1
		for i in Pilot.BURN_STEPS.size():
			if p.burn_points >= int(Pilot.BURN_STEPS[i]):
				lvl = i + 1
		p.burn_level = lvl
	p.best_burn = maxi(p.best_burn, int(d.best_burn))
	p.credits = int(d.credits)
	var v := int(d.vehicle)
	p.vehicle = VEHICLES[v] if v >= 0 and v < VEHICLES.size() else ""
	if p.vehicle == "":
		p.upside = false
	p.stun = maxf(0.0, float(d.stun) - age)
	p.invuln = maxf(0.0, float(d.invuln) - age)
	p.place = int(d.place)
	p.shield = int(d.shield)
	p.armour = int(d.armour)
	p.out_at = float(d.out_at)
	if p.state != Pilot.State.FLY:
		p.flying = false


## Moves a height on `ticks` ticks the way the pilot's pack (or vehicle)
## would with fly held or not: Vector2(y, vy). Close enough to ease other
## devices' pilots towards; the host's next snapshot puts it right.
static func extrapolate(spec: Dictionary, vehicle: String, y: float, vy: float, fly: bool, ticks: int) -> Vector2:
	var v := Vector2(y, vy)
	for i in ticks:
		v = advance(spec, vehicle, v.x, v.y, fly, i)
	return v


## One tick of extrapolation, `age` ticks after the last word: the pilot's
## last controls for a few ticks, then their climb or fall easing off, since
## further ahead than that pilots mostly hold their height.
static func advance(spec: Dictionary, vehicle: String, y: float, vy: float, fly: bool, age: int) -> Vector2:
	if age >= COAST_AFTER and vehicle == "":
		vy *= COAST
		return Vector2(clampf(y + vy * Run.DT, 0.0, Run.TOP), vy)
	return fly_step(spec, vehicle, y, vy, fly)


## One tick of height for extrapolation.
static func fly_step(spec: Dictionary, vehicle: String, y: float, vy: float, fly: bool) -> Vector2:
	var dt := Run.DT
	var top := Run.TOP
	match vehicle:
		"":
			var thrust := float(spec.get("thrust", 50.0))
			if float(spec.get("pulse", 0.0)) > 0.0:
				thrust = float(spec.get("kick", 6.0)) / float(spec.pulse)
			vy += ((thrust if fly else 0.0) - float(spec.get("gravity", 30.0))) * dt
			vy = clampf(vy, -float(spec.get("fall", 13.0)), float(spec.get("rise", 9.5)))
		"raptor":
			vy = maxf(vy - 34.0 * dt, -18.0)
			top -= 1.0
		"eye":
			vy = maxf(vy - 30.0 * dt, -15.0)
		"gunner":
			vy = clampf(vy + ((42.0 if fly else 0.0) - 26.0) * dt, -11.0, 8.0)
		"shell":
			return Vector2(y, vy)
	y += vy * dt
	if y <= 0.0:
		y = 0.0
		vy = maxf(vy, 0.0)
	elif y >= top:
		y = top
		vy = minf(vy, 0.0)
	return Vector2(y, vy)
