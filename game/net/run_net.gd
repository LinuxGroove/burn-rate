class_name RunNet
extends Node
## One round of a party race (Last One Flying), on one screen or between
## devices. RunScene adds one when the run's config has "net": true.
##
## On every device it holds the run for a countdown and shows the scoreboard
## ([PartyBoard]); on the host it tells [Session] who won the round. Between
## devices the host is the authority:
##   _c_inputs   a device's own pilots' controls, one byte a tick each, tagged
##               with the tick and sent twice with the ones before
##               (unreliable)
##   _c_ping     a guest measures the round trip before the start
##   _h_go       the countdown starts (reliable)
##   _h_snap     every pilot, 20 times a second, with how early this guest's
##               controls are arriving (unreliable)
##   _h_events   what only the host decides: near misses, hits, outs,
##               credits, vehicles, the round's end (reliable)
##
## The course and its hazards come from the seed, so every device runs them
## itself. A guest runs a few ticks ahead of the host, so its controls reach
## the host in time for the same tick: its own pilots fly exactly as the
## host's copies of them do, with no wait for the host. Other pilots are eased
## onto the host's snapshots, carried forward to the guest's moment.

## Ticks between snapshots, and between a guest's control messages.
const SNAP_EVERY := 3
const SEND_EVERY := 2
## Ticks of controls in each message (so a lost one costs nothing).
const SEND_TICKS := 8
## How many ticks early a guest's controls should reach the host.
const SLACK_LOW := 1
const SLACK_HIGH := 7
const SLACK_TARGET := 3
## No slack measured yet.
const NO_SLACK := 99999
const COUNTDOWN := 3.0
## The host starts the countdown once every device has the round, or after
## this long.
const LOAD_WAIT := 12.0
const HISTORY := 240
## Ticks of snapshots after the round ends, so guests settle on the last
## places before their scenes move on to the lobby.
const OVER_SNAPS := 30
## Events only the host decides, which it sends to everyone.
const HOST_EVENTS := [
	"near", "stun", "out", "round_over", "credit", "vehicle", "vehicle_lost", "smash", "knock",
	"shield", "armour", "reboot", "burn_lost", "crash", "done",
]

enum Phase { LOAD, COUNT, FLY, OVER }

var scene: RunScene
var run: Run
var phase := Phase.LOAD
## Other devices take part.
var networked := false
var host := true
## Seconds left on the countdown.
var countdown := 0.0
## Ticks where this guest's course went a different way from the host's
## (should stay 0), and snapshots applied.
var desyncs := 0
var aim_desyncs := 0
var snapshots := 0
## Times a guest flew its own pilot again from the host's word.
var replays := 0
## Host: ticks a guest's pilot flew on guessed controls (theirs came late).
var late_inputs := 0
## Round-trip time to the host in milliseconds (guests).
var rtt_ms := 0.0
var board: PartyBoard
## The config of this round on this device (see Session.localize).
var config := {}
## Pilot id -> RunInput for pilots steered elsewhere (RunScene's own dict).
var remote_inputs := {}
## Tests: messages go here as [peer, method, args] instead of over the
## network, and these are the other devices in the race.
var outbox = null
var test_peers: Array = []

# Host.
var _peer_ids := {}
var _remote := {}
var _queue := {}
var _recv_hi := {}
var _last_fly := {}
var _pending_lane := {}
var _slack := {}
var _ack := {}
var _wait := 0.0
var _round_told := false
## Steps since the round ended (-1 while it runs).
var _over_steps := -1

# Guest.
var _own: Array = []
var _sent := {}
var _hist := {}
var _cam_hist := {}
var _aim_hist := {}
var _targets := {}
var _snap_tick := -1
var _report_slack := NO_SLACK
var _slack_new := false
var _cooldown := 0
var _hold := 0
var _carry := {}
var _remote_fly := {}
var _ping_t := 0.0
## A guest that missed the start: the tick to catch up to.
var _jump_to := 0
var _pings: Array = []


func setup(p_scene: RunScene) -> void:
	scene = p_scene
	attach(scene.run, scene.config, Session.is_host(), Session.is_networked(), scene.remote_inputs)
	# Each round's node gets its own name, the same on every device: the
	# last round's is still in the tree until the end of this frame.
	name = "Net%d" % round_no()
	board = PartyBoard.new()
	board.name = "PartyBoard"
	scene.add_child(board)
	board.setup(self)
	Session.peer_left.connect(_on_peer_left)
	Session.left.connect(_on_left)
	Session.report_loaded()
	if host and not _waiting_for_peers():
		_start_countdown()


## Joins this to a run with no scene, for setup and for tests.
func attach(p_run: Run, p_config: Dictionary, p_host: bool, p_networked: bool, p_remote_inputs: Dictionary) -> void:
	run = p_run
	config = p_config
	host = p_host
	networked = p_networked
	remote_inputs = p_remote_inputs
	run.authority = host
	var by_peer := {}
	for d in config.get("pilots", []):
		if bool(d.get("bot", false)):
			continue
		var peer := int(d.get("peer", 1))
		if not by_peer.has(peer):
			by_peer[peer] = []
		by_peer[peer].append(d)
	for peer in by_peer:
		var list: Array = by_peer[peer]
		list.sort_custom(_by_seat)
		var ids := []
		for d in list:
			ids.append(int(d.id))
		_peer_ids[peer] = ids
		if host and peer != 1:
			for id in ids:
				_remote[id] = peer
				_queue[id] = {}
				_recv_hi[id] = 0
				_last_fly[id] = false
				_pending_lane[id] = 0
	var local: Dictionary = config.get("local", {})
	_own = local.keys()
	_own.sort_custom(_by_local_seat.bind(local))
	for i in _own.size():
		_own[i] = int(_own[i])
	if not host:
		run.predict = _own.duplicate()


static func _by_seat(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("seat", 0)) < int(b.get("seat", 0))


static func _by_local_seat(a, b, local: Dictionary) -> bool:
	return int(local[a]) < int(local[b])


## The round number and the wins needed, for the board.
func round_no() -> int:
	return int(config.get("round", 1))


func _waiting_for_peers() -> bool:
	if not networked or outbox != null:
		return false
	for peer in _race_peers():
		if not Session.loaded_peers.has(peer):
			return true
	return false


## The other devices in this race that are still here.
func _race_peers() -> Array:
	var here: Array = test_peers if outbox != null else Array(multiplayer.get_peers())
	var out := []
	for peer in _peer_ids:
		if int(peer) != 1 and int(peer) in here:
			out.append(int(peer))
	return out


## Sends an RPC to one device (or, in tests, to the outbox).
func _send(peer: int, method: StringName, args: Array) -> void:
	if outbox != null:
		outbox.append([peer, method, args])
		return
	match method:
		&"_h_go":
			_h_go.rpc_id(peer, args[0])
		&"_h_snap":
			_h_snap.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		&"_h_events":
			_h_events.rpc_id(peer, args[0], args[1])
		&"_c_inputs":
			_c_inputs.rpc_id(peer, args[0], args[1])
		&"_c_ping":
			_c_ping.rpc_id(peer, args[0])


func _start_countdown() -> void:
	phase = Phase.COUNT
	countdown = COUNTDOWN
	if host and networked:
		for peer in _race_peers():
			_send(peer, &"_h_go", [COUNTDOWN])


# --- Hooks from RunScene ----------------------------------------------------

## Called by RunScene each tick after this device's controls are read and
## before the run steps. Fills scene.remote_inputs for pilots steered
## elsewhere. Returns false to hold the run this tick (the countdown, or a
## guest that got too far ahead of the host); a guest that fell behind steps
## the run more than once here.
func before_step(inputs: Dictionary) -> bool:
	match phase:
		Phase.LOAD:
			_carry_lanes(inputs)
			if host:
				_wait += Run.DT
				if not _waiting_for_peers() or _wait > LOAD_WAIT:
					_start_countdown()
			else:
				_ping_t -= Run.DT
				if _ping_t <= 0.0 and networked:
					_ping_t = 0.25
					_send(1, &"_c_ping", [Time.get_ticks_msec()])
			return false
		Phase.COUNT:
			_carry_lanes(inputs)
			countdown -= Run.DT
			if countdown > 0.0:
				return false
			phase = Phase.FLY
			countdown = 0.0
	if host:
		_merge_carry(inputs)
		_host_inputs()
		return true
	if _hold > 0:
		_hold -= 1
		_carry_lanes(inputs)
		return false
	_merge_carry(inputs)
	var extra := _extra_ticks()
	for i in extra:
		if run.finished:
			break
		var step_in := {}
		for id in _own:
			var inp: RunInput = inputs.get(id, RunInput.NONE)
			step_in[id] = RunInput.make(inp.fly, inp.lane if i == 0 else 0, inp.was_fly)
		_guest_before(step_in)
		for id in remote_inputs:
			step_in[id] = remote_inputs[id]
		run.step(step_in)
		_guest_after()
	if extra > 0:
		for id in _own:
			var inp: RunInput = inputs.get(id, RunInput.NONE)
			inputs[id] = RunInput.make(inp.fly, 0, inp.fly)
	_guest_before(inputs)
	return true


## Called by RunScene after the run steps.
func after_step() -> void:
	if host:
		_host_after()
	else:
		_guest_after()


## A lane press on a held tick waits for the next tick that runs.
func _carry_lanes(inputs: Dictionary) -> void:
	for id in inputs:
		var inp: RunInput = inputs[id]
		if inp and inp.lane != 0:
			_carry[id] = inp.lane


func _merge_carry(inputs: Dictionary) -> void:
	for id in _carry:
		if inputs.has(id) and inputs[id].lane == 0:
			var inp: RunInput = inputs[id]
			inputs[id] = RunInput.make(inp.fly, int(_carry[id]), inp.was_fly)
	_carry.clear()


# --- Host -------------------------------------------------------------------

## The controls of pilots on other devices for the tick about to run: what
## they sent for it, or more of the same when it hasn't come.
func _host_inputs() -> void:
	var t := run.tick + 1
	for id in _remote:
		var q: Dictionary = _queue[id]
		var fly: bool = _last_fly[id]
		var lane := 0
		if q.has(t):
			var v := NetCodec.input_from(int(q[t]))
			fly = v[0]
			lane = v[1]
		elif run.pilot(id) and run.pilot(id).state == Pilot.State.FLY:
			late_inputs += 1
		for k in q.keys():
			if int(k) <= t:
				q.erase(k)
		if lane == 0 and int(_pending_lane[id]) != 0:
			lane = int(_pending_lane[id])
		_pending_lane[id] = 0
		remote_inputs[id] = RunInput.make(fly, lane, bool(_last_fly[id]))
		_last_fly[id] = fly


func _host_after() -> void:
	var forward := []
	for e in run.events:
		if str(e.get("type", "")) in HOST_EVENTS:
			forward.append(e)
	if networked:
		var peers := _race_peers()
		if not forward.is_empty():
			for peer in peers:
				_send(peer, &"_h_events", [run.tick, forward])
		if _over_steps >= 0:
			_over_steps += 1
		if _over_steps < 0 or (_over_steps <= OVER_SNAPS and _over_steps % SNAP_EVERY == 0):
			if run.tick % SNAP_EVERY == 0 or run.finished:
				_send_snapshots(peers)
	for e in forward:
		if str(e.type) == "round_over" and not _round_told:
			_round_told = true
			_over_steps = 0
			phase = Phase.OVER
			if scene:
				Session.round_over(int(e.winner))


func _send_snapshots(peers: Array) -> void:
	var packed := NetCodec.pack_pilots(run)
	var aim: int = run.aim_check()
	for peer in peers:
		var slack: int = _slack.get(peer, NO_SLACK)
		_slack[peer] = NO_SLACK
		_send(peer, &"_h_snap", [run.tick, run.cam_x, aim, slack, int(_ack.get(peer, 0)), packed[0], packed[1]])


## A device left mid-round: its pilots drop out.
func _on_peer_left(peer: int) -> void:
	if not host or not _peer_ids.has(peer):
		return
	for id in _peer_ids[peer]:
		_remote.erase(id)
		var p := run.pilot(int(id))
		if p and p.state == Pilot.State.FLY and not run.finished:
			p.state = Pilot.State.OUT
			p.out_at = run.time
			p.flying = false
			p.place = run.alive_count() + 1
			run.events.append({"type": "out", "pilot": p.id, "place": p.place, "left": true})
	_peer_ids.erase(peer)


# --- Guest ------------------------------------------------------------------

## Extra ticks to run now to catch up with the host (or none), from how early
## the host says this device's controls arrive.
func _extra_ticks() -> int:
	if _jump_to > run.tick:
		var n := _jump_to - run.tick
		_jump_to = 0
		_cooldown = int(rtt_ms / 1000.0 / Run.DT) + SNAP_EVERY * 2 + 4
		return mini(n, 3600)
	if _cooldown > 0:
		_cooldown -= 1
	if not _slack_new or _cooldown > 0:
		return 0
	_slack_new = false
	var s := _report_slack
	var settle := int(rtt_ms / 1000.0 / Run.DT) + SNAP_EVERY * 2 + 4
	if s < -6:
		_cooldown = settle
		return clampi(SLACK_TARGET - s, 1, 90)
	if s < SLACK_LOW:
		_cooldown = settle
		return SLACK_TARGET - s
	if s > SLACK_HIGH + 10:
		_hold = s - SLACK_TARGET
		_cooldown = settle
	elif s > SLACK_HIGH:
		_hold = 1
		_cooldown = settle
	return 0


## Before a tick runs here: remember and send this device's controls, and
## steer other pilots with what the host last said they were doing.
func _guest_before(inputs: Dictionary) -> void:
	var t := run.tick + 1
	var bytes := PackedByteArray()
	for id in _own:
		bytes.append(NetCodec.input_byte(inputs.get(id, RunInput.NONE)))
	_sent[t] = bytes
	_sent.erase(t - HISTORY)
	for p in run.pilots:
		if p.id in _own:
			continue
		var fly := bool(_remote_fly.get(p.id, false)) and p.stun <= 0.0
		remote_inputs[p.id] = RunInput.make(fly, 0, p.flying)
	if networked and phase != Phase.OVER and t % SEND_EVERY == 0 and not _own.is_empty():
		var first := maxi(1, t - SEND_TICKS + 1)
		var data := PackedByteArray()
		for k in range(first, t + 1):
			var b: PackedByteArray = _sent.get(k, PackedByteArray())
			if b.size() != _own.size():
				b = PackedByteArray()
				b.resize(_own.size())
				b.fill(2)
			data.append_array(b)
		_send(1, &"_c_inputs", [first, data])


## After a tick runs here: remember where this device's pilots were, and
## ease everyone onto the host's latest word.
func _guest_after() -> void:
	var t := run.tick
	var rec := {}
	for id in _own:
		var p := run.pilot(id)
		if p:
			rec[id] = _pilot_record(p)
	_hist[t] = rec
	_cam_hist[t] = run.cam_x
	_aim_hist[t] = run.aim_check()
	_hist.erase(t - HISTORY)
	_cam_hist.erase(t - HISTORY)
	_aim_hist.erase(t - HISTORY)
	for id in _targets:
		var p := run.pilot(int(id))
		if p == null:
			continue
		var g: Dictionary = _targets[id]
		g.ahead = float(g.ahead) + float(g.rate) * Run.DT
		p.ahead = lerpf(p.ahead, float(g.ahead), 0.15)
		if not int(id) in _own:
			var v := NetCodec.advance(p.spec, p.vehicle, float(g.y), float(g.vy), bool(g.fly), int(g.age))
			g.age = int(g.age) + 1
			g.y = v.x
			g.vy = v.y
			p.y = lerpf(p.y, v.x, 0.25)
			p.vy = lerpf(p.vy, v.y, 0.25)
		if p.state != Pilot.State.CRASH:
			p.x = run.cam_x + p.ahead


## A snapshot from the host: where every pilot was at its tick.
func _apply_snapshot(tick: int, cam_x: float, aim: int, ids: PackedInt64Array, vals: PackedFloat32Array) -> void:
	snapshots += 1
	if _cam_hist.has(tick) and absf(float(_cam_hist[tick]) - cam_x) > 0.01:
		desyncs += 1
	if _aim_hist.has(tick) and int(_aim_hist[tick]) != aim:
		aim_desyncs += 1
	var age_ticks := clampi(run.tick - tick, 0, 60)
	var age := age_ticks * Run.DT
	for i in ids.size():
		var id := int(ids[i])
		var p := run.pilot(id)
		var d := NetCodec.unpack_pilot(vals, i)
		if p == null or d.is_empty():
			continue
		var was_lane := p.lane_to
		NetCodec.apply_common(p, d, age)
		var g: Dictionary = _targets.get(id, {})
		var rate := 0.0
		if g.has("tick") and tick > int(g.tick):
			rate = clampf((float(d.ahead) - float(g.raw)) / ((tick - int(g.tick)) * Run.DT), -5.0, 3.0)
			rate = lerpf(float(g.rate), rate, 0.5)
		if p.state != Pilot.State.FLY:
			rate = 0.0
		var fresh := g.is_empty()
		g["tick"] = tick
		g["raw"] = float(d.ahead)
		g["rate"] = rate
		g["ahead"] = float(d.ahead) + rate * age
		if fresh:
			p.ahead = float(g.ahead)
		if id in _own:
			_reconcile(p, tick, d)
		else:
			var fly := float(d.fly) > 0.5
			_remote_fly[id] = fly
			var ext := NetCodec.extrapolate(p.spec, p.vehicle, float(d.y), float(d.vy), fly and p.stun <= 0.0, age_ticks)
			g["y"] = ext.x
			g["vy"] = ext.y
			g["age"] = age_ticks
			g["fly"] = fly
			p.lane_to = int(d.lane_to)
			if fresh or absf(p.y - ext.x) > 2.5:
				p.y = ext.x
				p.vy = ext.y
			if absf(p.lane - float(d.lane)) > 1.2:
				p.lane = float(d.lane)
			if p.lane_to != was_lane:
				run.events.append({"type": "lane", "pilot": id, "to": p.lane_to})
			p.upside = float(d.upside) > 0.5
		_targets[id] = g


## What the guest remembers of its own pilot after each tick, to compare
## with the host's snapshots: [y, vy, lane_to, lane, held_for, pulse timer,
## stun, invuln].
static func _pilot_record(p: Pilot) -> Array:
	return [p.y, p.vy, p.lane_to, p.lane, p.held_for, p._pulse, p.stun, p.invuln]


## Where this device's own pilot went a different way from the host's copy
## (a hit, a bump, controls that came late), flies it again from the host's
## state at that tick with the controls sent since, so it ends up where the
## host will have it.
func _reconcile(p: Pilot, tick: int, d: Dictionary) -> void:
	var rec: Dictionary = _hist.get(tick, {})
	if not rec.has(p.id) or p.state != Pilot.State.FLY:
		return
	var h: Array = rec[p.id]
	if absf(float(d.y) - float(h[0])) < 0.005 and absf(float(d.vy) - float(h[1])) < 0.02 \
			and int(d.lane_to) == int(h[2]) and absf(float(d.lane) - float(h[3])) < 0.01 \
			and absf(float(d.stun) - float(h[6])) < 0.02:
		return
	replays += 1
	var idx := _own.find(p.id)
	var keep_events := run.events.size()
	var keep_near := p.since_near
	var keep_floor := p.floor_time
	var keep_stats := p.stats.duplicate()
	p.y = float(d.y)
	p.vy = float(d.vy)
	p.lane = float(d.lane)
	p.lane_to = int(d.lane_to)
	p.stun = float(d.stun)
	p.invuln = float(d.invuln)
	p.held_for = float(h[4])
	p._pulse = float(h[5])
	p.on_floor = p.y <= 0.0
	var was := false
	var first: PackedByteArray = _sent.get(tick, PackedByteArray())
	if idx >= 0 and idx < first.size():
		was = bool(NetCodec.input_from(first[idx])[0])
	for k in range(tick + 1, run.tick + 1):
		var bytes: PackedByteArray = _sent.get(k, PackedByteArray())
		if idx < 0 or idx >= bytes.size():
			break
		var v := NetCodec.input_from(bytes[idx])
		run._step_pilot(p, RunInput.make(v[0], v[1], was))
		was = v[0]
		if _hist.has(k):
			_hist[k][p.id] = _pilot_record(p)
	# Replaying makes no new events, and counts nothing twice.
	run.events.resize(keep_events)
	p.since_near = keep_near
	p.floor_time = keep_floor
	p.stats = keep_stats
	p.x = run.cam_x + p.ahead


## What the host decided, applied here so the run looks and plays the same.
func _apply_event(e: Dictionary, tick: int) -> void:
	var age := clampi(run.tick - tick, 0, 120) * Run.DT
	var p := run.pilot(int(e.get("pilot", 0))) if e.has("pilot") else null
	match str(e.get("type", "")):
		"stun":
			if p:
				p.stun = maxf(p.stun, 1.1 - age)
				p.invuln = maxf(p.invuln, 1.8 - age)
				p.vy = minf(p.vy, 0.0)
				p.lose_burn()
		"out":
			if p:
				p.state = Pilot.State.OUT
				p.flying = false
				p.place = int(e.get("place", 0))
				p.out_at = run.time - age
		"round_over":
			run.finished = true
			run.winner = int(e.get("winner", -1))
			var w := run.pilot(run.winner)
			if w:
				w.place = 1
			phase = Phase.OVER
		"credit", "vehicle":
			for k in run.pickups:
				if k.id == int(e.get("pickup", -1)):
					k.taken = true
					k.by = int(e.get("pilot", -1))
			if p and str(e.type) == "vehicle" and p.vehicle == "":
				p.vehicle = str(e.get("vehicle", ""))
				p.vehicle_from = p.x
				p.upside = false
		"vehicle_lost":
			if p:
				p.vehicle = ""
				p.upside = false
				p.invuln = maxf(p.invuln, 1.3 - age)
		"smash":
			for h in run.hazards:
				if h.id == int(e.get("hazard", -1)):
					h.dead = true
					h.state = "smashed"
		"knock":
			for s in run.staff:
				if int(s.id) == int(e.get("staff", -1)) and float(s.knocked) < 0.0:
					s.knocked = run.time - age
					s.by = int(e.get("pilot", -1))
		"shield", "armour", "reboot":
			if p:
				p.invuln = maxf(p.invuln, 1.2 - age)
	run.events.append(e)


func _on_left(reason: String) -> void:
	if not networked or not is_inside_tree():
		return
	LGScenes.change_scene(Session.TITLE_SCENE, _title_message.bind(reason))


func _title_message(node: Node, reason: String) -> void:
	node.set("message", reason)


func _unhandled_input(event: InputEvent) -> void:
	# Rounds follow one another by themselves; restarting one here would
	# leave everyone else's behind.
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _c_inputs(first: int, data: PackedByteArray) -> void:
	receive_inputs(multiplayer.get_remote_sender_id(), first, data)


## Host: a device's controls for ticks first, first + 1, ...
func receive_inputs(peer: int, first: int, data: PackedByteArray) -> void:
	if not host or run == null:
		return
	var ids: Array = _peer_ids.get(peer, [])
	if ids.is_empty() or data.size() % ids.size() != 0:
		return
	var n := data.size() / ids.size()
	var last := first + n - 1
	_ack[peer] = maxi(int(_ack.get(peer, 0)), last)
	var slack := last - (run.tick + 1)
	_slack[peer] = mini(int(_slack.get(peer, NO_SLACK)), slack)
	for k in n:
		var t := first + k
		for j in ids.size():
			var id: int = ids[j]
			if not _remote.has(id) or t <= int(_recv_hi[id]):
				continue
			var b := int(data[k * ids.size() + j])
			if t <= run.tick:
				# Too late for its tick: keep at least the lane change.
				var lane: int = NetCodec.input_from(b)[1]
				if lane != 0:
					_pending_lane[id] = lane
			elif t <= run.tick + 600:
				_queue[id][t] = b
	for id in ids:
		if _remote.has(id):
			_recv_hi[id] = maxi(int(_recv_hi[id]), last)


@rpc("any_peer", "call_remote", "unreliable")
func _c_ping(msec: int) -> void:
	if host:
		_h_pong.rpc_id(multiplayer.get_remote_sender_id(), msec)


@rpc("authority", "call_remote", "unreliable")
func _h_pong(msec: int) -> void:
	var rtt := float(Time.get_ticks_msec() - msec)
	_pings.append(rtt)
	if _pings.size() > 7:
		_pings.pop_front()
	var sorted := _pings.duplicate()
	sorted.sort()
	rtt_ms = sorted[sorted.size() / 2]


@rpc("authority", "call_remote", "reliable")
func _h_go(seconds: float) -> void:
	if phase != Phase.LOAD:
		return
	phase = Phase.COUNT
	# Start early by the round trip and a little more, so this device runs
	# just ahead of the host.
	countdown = maxf(0.3, seconds - rtt_ms / 1000.0 - SLACK_TARGET * Run.DT)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _h_snap(tick: int, cam_x: float, aim: int, slack: int, acked: int, ids: PackedInt64Array, vals: PackedFloat32Array) -> void:
	receive_snapshot(tick, cam_x, aim, slack, acked, ids, vals)


## Guest: the host's snapshot of every pilot at `tick`.
func receive_snapshot(tick: int, cam_x: float, aim: int, slack: int, acked: int, ids: PackedInt64Array, vals: PackedFloat32Array) -> void:
	if host or run == null or tick <= _snap_tick:
		return
	_snap_tick = tick
	if acked > 0 and acked <= run.tick:
		# The host had this device's controls up to `acked`: a round trip.
		var r := (run.tick - acked) * Run.DT * 1000.0
		rtt_ms = r if rtt_ms <= 0.0 else lerpf(rtt_ms, r, 0.2)
	if phase == Phase.LOAD or phase == Phase.COUNT:
		# The round started without this device: fly from where it's got to.
		phase = Phase.FLY
		countdown = 0.0
		_jump_to = tick + int(rtt_ms / 1000.0 / Run.DT) + SLACK_TARGET
	if slack != NO_SLACK:
		_report_slack = slack
		_slack_new = true
	_apply_snapshot(tick, cam_x, aim, ids, vals)


@rpc("authority", "call_remote", "reliable")
func _h_events(tick: int, events: Array) -> void:
	receive_events(tick, events)


## Guest: what the host decided at `tick`.
func receive_events(tick: int, events: Array) -> void:
	if host or run == null:
		return
	for e in events:
		if e is Dictionary:
			_apply_event(e, tick)
