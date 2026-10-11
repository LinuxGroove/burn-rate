class_name Autopilot
extends RefCounted
## A bot pilot: plays through the same controls a person does (fly held, a
## lane step), seeing only what's on screen, after a reaction time. Party
## bots, the title screen's demo flight and the tests all use it.
##
## Every few ticks it tries a handful of plans (each lane it could move to,
## each height it could hold) a short way ahead against where the hazards
## will be, scores them (hits, Burn, credits, the floor) and follows the best.
## Skill sets how far ahead it looks, how quickly it reacts and how often it
## fumbles.

const SKILLS := {
	"novice": {"horizon": 0.55, "react": 0.42, "every": 7, "fumble": 0.12, "greed": 0.4, "burn": 0.0, "view": 10.5},
	"average": {"horizon": 0.85, "react": 0.27, "every": 5, "fumble": 0.04, "greed": 0.8, "burn": 0.3, "view": 11.5},
	"expert": {"horizon": 1.25, "react": 0.14, "every": 3, "fumble": 0.0, "greed": 1.0, "burn": 0.8, "view": 13.0},
}
## Heights it can aim to hold.
const HEIGHTS := [0.0, 1.4, 2.8, 4.2, 5.6]
const SAMPLE := 3
## Plans can wait this many ticks before changing lane.
const WAIT := 9

var skill := "average"
var p: Dictionary
var rng := RandomNumberGenerator.new()
## The plan it's following: [lane target, height target or -1 / -2 for
## hold / let go, ticks to wait before changing lane].
var plan := [1, 1.4, 0]
var _ticks := 0
var _seen := {}
var _was_fly := false


func _init(p_skill := "average", p_seed := 1) -> void:
	skill = p_skill if SKILLS.has(p_skill) else "average"
	p = SKILLS[skill]
	rng.seed = p_seed


## The controls for this tick.
func think(run: Run, me: Pilot) -> RunInput:
	if not me.alive():
		_was_fly = false
		return RunInput.NONE
	_ticks += 1
	if _ticks >= int(p.every):
		_ticks = 0
		plan = _choose(run, me)
	var lane_step := 0
	if int(plan[2]) > 0:
		plan[2] = int(plan[2]) - 1
	elif run.lanes_on and int(plan[0]) != me.lane_to:
		lane_step = signi(int(plan[0]) - me.lane_to)
	var fly := _fly_for(me, float(plan[1]))
	if me.vehicle != "":
		fly = _vehicle_fly(run, me)
	var inp := RunInput.make(fly, lane_step, _was_fly)
	_was_fly = fly
	return inp


## Whether to hold fly to stay at `target` (-1 hold, -2 let go).
func _fly_for(me: Pilot, target: float) -> bool:
	if target == -1.0:
		return true
	if target == -2.0:
		return false
	return _hold_for(me.y, me.vy, target, me.spec)


static func _hold_for(y: float, vy: float, target: float, spec: Dictionary) -> bool:
	if target <= 0.01:
		return false
	# Where it'd stop if it let go now.
	var g := float(spec.gravity)
	var stop_y := y + (vy * absf(vy) / (2.0 * g) if vy > 0.0 else vy * 0.08)
	return stop_y < target


func _vehicle_fly(run: Run, me: Pilot) -> bool:
	# Jump or hop when something is coming low in its lane; flip the shell
	# when the side it's on is blocked.
	var ahead := run.speed_now * 0.45
	for h in run.hazards_between(me.x + 0.5, me.x + ahead + 2.0):
		if h.dead:
			continue
		for s in h.shapes_at(run.time + 0.25, run):
			var c := Hazard.clearance(s, me.x + run.speed_now * 0.25, me.body().x, me.body().y, me.body().z + 0.3, me.lane)
			if c.x < 0.4 and absf(c.y) < Hazard.LANE_HIT:
				if me.vehicle == "gunner":
					return true
				return not _was_fly
	match me.vehicle:
		"gunner":
			return _hold_for(me.y, me.vy, 3.0, {"gravity": 26.0})
		"eye":
			return me.y < 2.5 and me.vy < 0.0 and not _was_fly
	return false


func _choose(run: Run, me: Pilot) -> Array:
	var lanes := [me.lane_to]
	if run.lanes_on:
		for l in Run.LANES:
			if l != me.lane_to:
				lanes.append(l)
	var targets: Array = HEIGHTS.duplicate()
	targets.append(-1.0)
	targets.append(-2.0)
	if me.vehicle != "":
		targets = [0.0]
	var view_to: float = me.x + float(p.view)
	var hz := []
	for h in run.hazards_between(me.x - 3.0, view_to + 4.0):
		if h.dead:
			continue
		var e: Vector2 = h.extent()
		# Only what's on screen, and only once it's had time to sink in.
		if e.x > view_to and h.warning().is_empty():
			continue
		if not _seen.has(h.id):
			_seen[h.id] = run.time
		if run.time - float(_seen[h.id]) < float(p.react):
			continue
		hz.append(h)
	var credits := []
	for k in run.pickups:
		if not k.taken and k.x > me.x and k.x < view_to:
			credits.append(k)
	# Where the hazards will be at each moment looked at: the same for
	# every plan, since the run moves on at the same speed whatever it does.
	var speed := run.speed_now * (1.0 + Run.BURN_SPEED * (me.burn_level - 1))
	if run.mode == "party":
		speed = run.speed_now
	var steps := int(float(p.horizon) / Run.DT)
	var samples := []
	for i in steps:
		if i % SAMPLE != 0:
			continue
		var t := run.time + (i + 1) * Run.DT
		var x := me.x + speed * (i + 1) * Run.DT
		var shapes := []
		for h in hz:
			var e: Vector2 = h.extent()
			if e.x > x + 2.5 or e.y < x - 2.5:
				continue
			shapes.append_array(h.shapes_at(t, run))
		samples.append(shapes)
	var best := plan
	var best_score := -INF
	var scores := []
	for l in lanes:
		for wait in ([0] if l == me.lane_to else [0, WAIT]):
			for t in targets:
				var sc := _score(run, me, int(l), float(t), int(wait), samples, credits, speed, steps)
				scores.append([sc, [l, t, wait]])
				if sc > best_score:
					best_score = sc
					best = [l, t, wait]
	# Fumbles: now and then a weaker player picks the second-best plan.
	if float(p.fumble) > 0.0 and rng.randf() < float(p.fumble) and scores.size() > 1:
		scores.sort_custom(func(a, b): return a[0] > b[0])
		best = scores[1][1]
	if _seen.size() > 400:
		for k in _seen.keys():
			if run.time - float(_seen[k]) > 20.0:
				_seen.erase(k)
	return best


## How good a plan looks: fly towards height `target` in lane `lane` for
## the horizon.
func _score(run: Run, me: Pilot, lane: int, target: float, wait: int, samples: Array, credits: Array, speed: float, steps: int) -> float:
	var spec := me.spec
	var y := me.y
	var vy := me.vy
	var ln := me.lane
	var x := me.x
	var score := 0.0
	# Looking only every few ticks, so pad the shapes by half the gap
	# between looks.
	var pad := speed * Run.DT * SAMPLE * 0.5 + 0.05
	var lane_pad := Hazard.LANE_HIT + SAMPLE * Run.DT / float(spec.lane) * 0.5 + 0.04
	var lane_time := float(spec.lane)
	var pulse := 0.0
	var taken := {}
	var floor_t := me.floor_time
	var b0 := Pilot.BODY.x
	var b1 := Pilot.BODY.y
	var br := Pilot.BODY_R + 0.04
	if me.vehicle != "":
		var vb: Array = Pilot.VEHICLE_BODY[me.vehicle]
		b0 = float(vb[0])
		b1 = float(vb[1])
		br = float(vb[2])
	for i in steps:
		var hold := false
		if target == -1.0:
			hold = true
		elif target >= 0.0:
			hold = _hold_for(y, vy, target, spec)
		if me.vehicle != "":
			hold = false
		if float(spec.get("pulse", 0.0)) > 0.0:
			if hold:
				pulse -= Run.DT
				if pulse <= 0.0:
					vy = minf(maxf(vy, 0.0) + float(spec.kick), float(spec.rise))
					pulse = float(spec.pulse)
			vy -= float(spec.gravity) * Run.DT
		elif me.vehicle == "":
			vy += ((float(spec.thrust) if hold else 0.0) - float(spec.gravity)) * Run.DT
		else:
			vy -= 30.0 * Run.DT
		vy = clampf(vy, -float(spec.fall), float(spec.rise))
		y += vy * Run.DT
		if y <= 0.0:
			y = 0.0
			vy = maxf(vy, 0.0)
		elif y >= Run.TOP:
			y = Run.TOP
			vy = minf(vy, 0.0)
		if i >= wait:
			ln = move_toward(ln, float(lane), Run.DT / lane_time)
		x += speed * Run.DT
		if i % SAMPLE != 0:
			continue
		var weight := 1.0 - float(i) / float(steps) * 0.5
		for s in samples[i / SAMPLE]:
			var c := Hazard.clearance(s, x, y + b0, y + b1, br + pad, ln)
			var dl := absf(c.y)
			if dl < lane_pad:
				if c.x < 0.0:
					# A hit ends the plan: sooner is worse.
					return score - 1000.0 * weight
				elif c.x < 0.6:
					# Close is Burn for the brave, danger for the rest.
					score += (float(p.burn) * 3.0 - 4.0) * (0.6 - c.x)
			elif dl < Hazard.LANE_SKIM and c.x < 0.0:
				score += float(p.burn) * 1.5
		# Credits along the way.
		for k in credits:
			if taken.has(k.id):
				continue
			if absf(k.x - x) < 0.9 and absf(k.lane - ln) < 0.6 and absf(k.y - (y + 0.85)) < 1.0:
				taken[k.id] = true
				score += float(p.greed) * (3.0 if k.kind == "big" else 1.0) * (6.0 if k.kind == "crate" and me.vehicle == "" else 1.0)
		if y <= 0.0 and me.vehicle == "":
			floor_t += Run.DT * SAMPLE
			if floor_t > Pilot.FLOOR_GRACE and me.burn_points > 0:
				score -= 2.0 + float(p.burn) * me.burn_points
		else:
			floor_t = 0.0
	# Small preferences: stay off the ceiling and floor, don't wander.
	score -= absf(float(lane) - me.lane_to) * 0.3
	if target == Run.TOP or target == -1.0:
		score -= 0.4
	if lane != int(plan[0]) or target != float(plan[1]):
		score -= 0.15
	score -= wait * 0.01
	return score
