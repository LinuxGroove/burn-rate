extends RefCounted
## Party races and the Session without a network: configs for every mode,
## snapshots and controls packed and unpacked, the lobby, and a host's and a
## guest's runs kept in step through RunNet's own messages with a delay (and
## lost messages) between them.

const HOST_PILOT := 4
const GUEST_PILOT := 8


func _people() -> Array:
	return [
		{"id": HOST_PILOT, "name": "Host", "pack": "k1", "look": Session.look_for("kestrel", 0), "peer": 1, "seat": 0, "bot": false},
		{"id": GUEST_PILOT, "name": "Guest", "pack": "k3", "look": Session.look_for("night", 1), "peer": 2, "seat": 0, "bot": false},
	]


func _base_config(seed: int, bots := 1, zone := "lab") -> Dictionary:
	var pilots := _people()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	pilots.append_array(Session.make_bots(bots, pilots, "average", rng))
	return {
		"mode": "party", "seed": seed, "pace": "normal", "lanes": true, "zone": zone,
		"pilots": pilots, "net": true, "round": 1, "target": 3,
	}


func test_configs(t) -> void:
	var base := _base_config(5, 2)
	var hc := Session.localize(base, 1)
	t.check(hc.local == {HOST_PILOT: 0}, "the host flies its own pilot")
	t.check(hc.bots.size() == 2 and hc.bots.has(Session.BOT_ID) and hc.bots.has(Session.BOT_ID - 1), "the host runs the bots")
	t.check(int(hc.me) == HOST_PILOT, "the host's screen follows its pilot")
	var gc := Session.localize(base, 2)
	t.check(gc.local == {GUEST_PILOT: 0} and gc.bots.is_empty() and int(gc.me) == GUEST_PILOT, "a guest flies only its own pilot and runs no bots")
	t.check(gc.pilots == hc.pilots and gc.seed == hc.seed, "every device gets the same pilots and seed")
	var bots := Session.make_bots(5, _people(), "mixed")
	var names := {}
	for b in bots:
		names[b.name] = true
		t.check(bool(b.bot) and int(b.id) <= Session.BOT_ID and str(b.skill) in Session.BOT_SKILLS, "bots are marked as bots with a skill (%s)" % b.name)
	t.check(names.size() == 5 and not names.has("Host"), "bots get different names from LGNameMaker")
	# Couch: four seats on one device.
	var couch := []
	for i in 4:
		couch.append({"id": Session.actor_id(1, i), "name": "P%d" % i, "pack": "k1", "peer": 1, "seat": i, "bot": false})
	var cc := Session.localize({"mode": "party", "seed": 1, "pilots": couch}, 1)
	t.check(cc.local.size() == 4 and int(cc.local[Session.actor_id(1, 3)]) == 3 and int(cc.me) == Session.actor_id(1, 0), "couch pilots map to their seats")
	# A round from the lobby settings.
	var keep: Dictionary = Session.settings.duplicate()
	Session.party = {"round": 2, "target": 3, "pilots": base.pilots}
	Session.settings.zone = "random"
	var rc := Session.round_config(77)
	t.check(rc.mode == "party" and rc.seed == 77 and rc.zone in Session.ZONES and rc.net and rc.round == 2 and rc.pilots.size() == 4, "a round's config has everything a run needs")
	t.check(Run.new(Session.localize(rc, 1)).pilots.size() == 4, "a round's config makes a run")
	Session.party = {}
	Session.settings = keep
	# Solo runs: what goes to the server.
	var payload := Session.run_report_payload({"mode": "endless", "pace": "fast", "lanes": false, "seed": 9, "distance": 1234, "credits": 56, "best_burn": 4, "time": 80.0, "pack": "k2"})
	t.check(payload.distance == 1234 and payload.time_ms == 80000 and payload.pace == "fast" and payload.lanes == false and not payload.has("course"), "an endless run's report")
	var course := Session.run_report_payload({"mode": "course", "course": "lab_1", "distance": 700, "time": 52.5, "stats": {"finish_time": 52.25}})
	t.check(course.course == "lab_1" and course.finish_ms == 52250, "a course's report carries its time")
	t.check(Session.run_report_payload({"mode": "endless", "distance": 0, "time": 3.0}).is_empty(), "nothing to report from a run that went nowhere")
	t.check(Session.record_text({}).begins_with("No online runs yet"), "the record before any runs")
	var rec := Session.record_text({"runs": 3, "metres": 4500, "best_distance": 2100, "credits": 1200, "races": 1, "race_wins": 1, "round_wins": 3})
	t.check("3 runs" in rec and "2,100 m" in rec and "1 race," in rec and "3 rounds won" in rec, "the record reads well: %s" % rec)


func test_session_lobby(t) -> void:
	var keep: Dictionary = Session.settings.duplicate()
	Session.start_solo()
	t.check(Session.mode == Session.Mode.SOLO and Session.players.size() == 1, "this screen's session has its first pilot")
	Session.settings.bots = 0
	t.check(not Session.can_start() and Session.start_blocker() != "", "one pilot alone can't start a race")
	Session.settings.bots = 2
	t.check(Session.can_start() and Session.bot_count() == 2, "bots make a race")
	Session.set_seat_value(0, "pack", "k4")
	t.check(Session.players.values()[0].pack == "k4", "a seat's prototype reaches the roster")
	var lobby: Node = load("res://game/ui/lobby.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(lobby)
	await (Engine.get_main_loop() as SceneTree).process_frame
	t.check(lobby.page == "lobby", "the lobby opens on the race when a session is running")
	t.check(lobby._roster.get_child_count() >= 2, "the roster lists the pilot and the bots")
	t.check(lobby._start.visible and not lobby._start.disabled, "the host can start")
	Session.leave()
	await (Engine.get_main_loop() as SceneTree).process_frame
	t.check(lobby.page == "hub", "leaving goes back to where to fly")
	lobby.queue_free()
	Session.settings = keep
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_codec(t) -> void:
	for fly in [false, true]:
		for lane in [-1, 0, 1]:
			var v := NetCodec.input_from(NetCodec.input_byte(RunInput.make(fly, lane)))
			t.check(v[0] == fly and v[1] == lane, "controls pack into a byte (%s, %d)" % [fly, lane])
	var run := Run.new(_base_config(3, 1))
	var p := run.pilots[1]
	p.ahead = -2.5
	p.y = 3.25
	p.vy = -4.0
	p.lane = 1.5
	p.lane_to = 2
	p.add_burn(8)
	p.credits = 4321
	p.vehicle = "gunner"
	p.stun = 0.7
	p.flying = true
	p.place = 3
	p.state = Pilot.State.OUT
	p.out_at = 12.5
	var packed := NetCodec.pack_pilots(run)
	t.check(packed[0].size() == 3 and packed[1].size() == 3 * NetCodec.N, "a snapshot has every pilot")
	t.check(NetCodec.FIELDS.size() == NetCodec.N, "every field has a name")
	var d := NetCodec.unpack_pilot(packed[1], 1)
	t.check(is_equal_approx(d.ahead, -2.5) and is_equal_approx(d.y, 3.25) and int(d.lane_to) == 2 and int(d.credits) == 4321 and d.fly > 0.5, "a pilot unpacks as packed")
	var q := Pilot.new(p.id, p.name, p.pack)
	NetCodec.apply_common(q, d, 0.2)
	t.check(q.burn_level == p.burn_level and q.credits == 4321 and q.vehicle == "gunner" and q.state == Pilot.State.OUT and q.place == 3, "a snapshot sets what the host decides")
	t.check(is_equal_approx(q.stun, 0.5), "stun carries on from the snapshot's age")
	var e := NetCodec.extrapolate(Packs.spec("k1"), "", 0.0, 0.0, true, NetCodec.COAST_AFTER)
	t.check(e.x > 0.1 and e.y > 0.0, "a pilot holding fly climbs when carried forward")
	var f := Vector2(3.0, 0.0)
	for i in 120:
		f = NetCodec.fly_step(Packs.spec("k1"), "", f.x, f.y, false)
	t.check(f.x == 0.0, "a pilot letting go lands")
	var g := NetCodec.extrapolate(Packs.spec("k1"), "", 3.0, 8.0, true, 60)
	t.check(absf(g.y) < 0.5 and g.x < Run.TOP, "far ahead, a climb eases off")


## Steps a host's and a guest's copy of the same round side by side, with
## RunNet's messages `latency` ticks on the wire and `loss` of the
## unreliable ones lost. Returns what the test checks.
func _loopback(seed: int, latency: int, loss: float, seconds: float, bots_n := 1, guest_idle := false) -> Dictionary:
	var base := _base_config(seed, bots_n)
	var hc := Session.localize(base, 1)
	var gc := Session.localize(base, 2)
	var hrun := Run.new(hc)
	var grun := Run.new(gc)
	var hnet := RunNet.new()
	var gnet := RunNet.new()
	var hrem := {}
	var grem := {}
	hnet.attach(hrun, hc, true, true, hrem)
	gnet.attach(grun, gc, false, true, grem)
	hnet.outbox = []
	gnet.outbox = []
	hnet.test_peers = [2]
	gnet.test_peers = [1]
	hnet.phase = RunNet.Phase.FLY
	gnet.phase = RunNet.Phase.FLY
	var hbot := Autopilot.new("average", 11)
	var gbot := Autopilot.new("average", 22)
	var bots := {}
	for id in hc.bots:
		bots[int(id)] = Autopilot.new(str(hc.bots[id]), hash([seed, id]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wire := []
	var host_y := {}
	var host_other := {}
	var guest_y := {}
	var guest_other := {}
	var frames := int(seconds / Run.DT)
	var after_end := -1
	for frame in frames:
		var hin := {HOST_PILOT: hbot.think(hrun, hrun.pilot(HOST_PILOT))}
		for id in bots:
			hin[id] = bots[id].think(hrun, hrun.pilot(id))
		if hnet.before_step(hin):
			for id in hrem:
				hin[id] = hrem[id]
			hrun.step(hin)
			hnet.after_step()
			host_y[hrun.tick] = hrun.pilot(GUEST_PILOT).y
			host_other[hrun.tick] = hrun.pilot(HOST_PILOT).y
		hrun.take_events()
		var gin := {GUEST_PILOT: RunInput.NONE if guest_idle else gbot.think(grun, grun.pilot(GUEST_PILOT))}
		if gnet.before_step(gin):
			for id in grem:
				gin[id] = grem[id]
			grun.step(gin)
			gnet.after_step()
			guest_y[grun.tick] = grun.pilot(GUEST_PILOT).y
			guest_other[grun.tick] = grun.pilot(HOST_PILOT).y
		grun.take_events()
		for m in hnet.outbox:
			wire.append([frame + latency, gnet, m])
		hnet.outbox.clear()
		for m in gnet.outbox:
			wire.append([frame + latency, hnet, m])
		gnet.outbox.clear()
		var keep := []
		for w in wire:
			if int(w[0]) > frame:
				keep.append(w)
				continue
			var to: RunNet = w[1]
			var method := StringName(w[2][1])
			var args: Array = w[2][2]
			if method in [&"_h_snap", &"_c_inputs"] and rng.randf() < loss:
				continue
			match method:
				&"_h_snap":
					to.receive_snapshot(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
				&"_h_events":
					to.receive_events(args[0], args[1])
				&"_c_inputs":
					to.receive_inputs(2, args[0], args[1])
		wire = keep
		if hrun.finished and after_end < 0:
			after_end = frame + latency * 2 + 30
		if after_end >= 0 and frame >= after_end:
			break
	var own_err := []
	var other_err := []
	for k in host_y:
		if guest_y.has(k):
			own_err.append(absf(float(host_y[k]) - float(guest_y[k])))
		if guest_other.has(k):
			other_err.append(absf(float(host_other[k]) - float(guest_other[k])))
	return {
		"host": hrun, "guest": grun, "gnet": gnet, "hnet": hnet, "own_err": own_err, "other_err": other_err,
		"lead": grun.tick - hrun.tick,
	}


static func _share_over(errs: Array, limit: float) -> float:
	if errs.is_empty():
		return 1.0
	var n := 0
	for e in errs:
		if float(e) > limit:
			n += 1
	return float(n) / errs.size()


static func _mean(errs: Array) -> float:
	var s := 0.0
	for e in errs:
		s += float(e)
	return s / maxf(1.0, errs.size())


func test_party_in_step(t) -> void:
	for c in [[101, 6, 0.0], [202, 12, 0.1], [303, 3, 0.0]]:
		var r := _loopback(c[0], c[1], c[2], 70.0)
		var what := "(seed %d, %d ms, %d%% lost)" % [c[0], int(c[1] * 1000.0 / 60.0), int(c[2] * 100)]
		var gnet: RunNet = r.gnet
		var host: Run = r.host
		var guest: Run = r.guest
		t.check(gnet.desyncs == 0, "the guest's course stays where the host's is %s: %d" % [what, gnet.desyncs])
		t.check(gnet.aim_desyncs == 0, "hazards aim the same on both %s: %d" % [what, gnet.aim_desyncs])
		t.check(gnet.snapshots > 100, "snapshots arrived %s: %d" % [what, gnet.snapshots])
		var own: Array = r.own_err
		t.check(own.size() > 600, "the guest flew its pilot %s" % what)
		# Controls lost on the way reach the host too late for their tick, and
		# the host flies that pilot on a guess until the next ones arrive.
		t.check(_share_over(own, 0.25) < 0.05 + c[1] * 0.015 + c[2] * 1.5, "the guest's own pilot flies as the host's copy does %s: %.1f%% off, mean %.3f m" % [what, _share_over(own, 0.25) * 100.0, _mean(own)])
		t.check(_mean(r.other_err) < 0.25 + c[1] * 0.06 + c[2] * 2.0, "the host's pilot shows near where it is on the guest %s: mean %.2f m" % [what, _mean(r.other_err)])
		t.check(int(r.lead) >= 0 and int(r.lead) <= c[1] * 2 + RunNet.SLACK_HIGH + 8, "the guest runs a little ahead of the host %s: %d ticks" % [what, r.lead])
		if host.finished:
			t.check(guest.finished and guest.winner == host.winner, "both see the same winner %s" % what)
		for p in host.pilots:
			var q := guest.pilot(p.id)
			t.check(q != null and q.state == p.state, "%s is %s on both %s" % [p.name, Pilot.State.keys()[p.state], what])
		printerr("    %s: %d ticks, winner %d, own pilot mean %.3f m, other mean %.2f m, lead %d, %d ticks on guessed controls" % [what, host.tick, host.winner, _mean(own), _mean(r.other_err), r.lead, r.hnet.late_inputs])



func test_party_round_ends(t) -> void:
	# The guest lets go, sinks, falls behind the screen and is out: the host
	# wins the round, and the guest hears so.
	var r := _loopback(404, 6, 0.05, 60.0, 0, true)
	var host: Run = r.host
	var guest: Run = r.guest
	t.check(host.finished and host.winner == HOST_PILOT, "the pilot still flying wins (winner %d)" % host.winner)
	t.check(guest.finished and guest.winner == host.winner, "the guest sees the round end with the same winner")
	t.check(guest.pilot(GUEST_PILOT).state == Pilot.State.OUT and guest.pilot(GUEST_PILOT).place == 2, "the guest's pilot is out in second place on the guest")
	t.check((r.gnet as RunNet).phase == RunNet.Phase.OVER, "the guest's round is over")
