extends RefCounted
## The views: every prototype builds and paints, every hazard kind draws,
## vehicles swap in and out, and the pilot's looks resolve.


func test_packs_build_and_paint(t) -> void:
	for id in Packs.ORDER:
		for d in [0, 1]:
			var v := PackView.make(id, d)
			t.check(v.model != null, "%s's model loads" % id)
			t.check(not v.flames.is_empty(), "%s has flames" % id)
			var mats := PackView.materials(id)
			var tank: ShaderMaterial = mats.get("MI_Trim_02_Red")
			t.check(tank != null, "%s paints its tanks" % id)
			v.thrust = 1.0
			v.heat = 1.0
			for i in 10:
				v.step(1.0 / 60.0)
			v.free()
	var k3 := PackView.make("k3")
	t.check(k3.wings.size() == 2, "the K-3 has two fins")
	k3.free()
	var k4 := PackView.make("k4")
	t.check(k4.drum != null, "the K-4 has its pulse drum")
	k4.free()
	var k6 := PackView.make("k6")
	t.check(k6.armour != null, "the K-6 has armour to drop")
	k6.free()


func test_looks_resolve(t) -> void:
	for id in PilotLooks.ORDER:
		t.check(PilotLooks.SUITS.has(id), "suit %s is listed" % id)
		for body in PilotLooks.BODIES.size():
			var look := PilotLooks.resolve(PilotLooks.make(body, id))
			t.check(look.has("main") and look.has("female"), "%s on body %d resolves" % [id, body])
	t.check(PilotLooks.resolve(PilotLooks.random(5)).has("main"), "a random look resolves")
	t.check(PilotLooks.resolve({"suit": "nonsense"}).has("main"), "an unknown suit falls back")


func test_every_hazard_draws(t) -> void:
	var root := Node3D.new()
	t.get_tree().root.add_child(root)
	var fx := Fx.new()
	root.add_child(fx)
	var run := Run.new({"mode": "endless", "seed": 3})
	var seen := {}
	for zone in Zones.ORDER:
		for e in Zones.info(zone).patterns:
			var r := RoomGen.new(1, zone, 20.0, 0.8, 14.0, true, 3)
			Patterns.make(str(e[0]), r)
			for h in r.hazards:
				if seen.has(h.kind):
					continue
				seen[h.kind] = true
				for d in [0, 1]:
					var v := HazardView.make(h, d, fx)
					root.add_child(v)
					for i in 30:
						run.time += 1.0 / 60.0
						h.step(run, 1.0 / 60.0)
						v.sync(run, 1.0, h.x - 6.0, 1.0 / 60.0)
					t.check(v.get_child_count() > 0, "%s draws something (detail %d)" % [h.kind, d])
					v.die(run)
					for i in 200:
						v.sync(run, 1.0, h.x - 6.0, 1.0 / 60.0)
					t.check(v.finished(), "%s finishes after it ends" % h.kind)
					v.free()
	for kind in ["zapper", "laser", "seeker", "shutter", "eye_drone", "gun_drone", "walker"]:
		t.check(seen.has(kind), "patterns place a %s" % kind)
	await t.get_tree().process_frame
	root.free()


func test_vehicles_swap(t) -> void:
	var root := Node3D.new()
	t.get_tree().root.add_child(root)
	var fx := Fx.new()
	root.add_child(fx)
	var run := Run.new({"mode": "endless", "seed": 4})
	var p := run.pilots[0]
	var v := PilotView.make(p, 1, fx)
	root.add_child(v)
	for kind in PilotView.VEHICLES:
		p.vehicle = kind
		for i in 5:
			v.sync(run, 1.0 / 60.0)
		t.check(v._vehicle != null and v._vehicle_kind == kind, "the pilot rides a %s" % kind)
		v.on_event({"type": "vehicle_lost", "pilot": p.id})
		p.vehicle = ""
		for i in 5:
			v.sync(run, 1.0 / 60.0)
		t.check(v._vehicle == null, "the %s is gone after it's lost" % kind)
	var g := PilotView.make_ghost(PilotLooks.make(1, "volt"), "k5")
	root.add_child(g)
	g.place(10.0, 3.0, 1.0, true)
	t.check(g.ghost and g.person != null, "a ghost builds and flies")
	await t.get_tree().process_frame
	root.free()


func test_run_view_draws_a_run(t) -> void:
	var root := Node3D.new()
	t.get_tree().root.add_child(root)
	var list := []
	for i in 4:
		list.append({"id": i + 1, "name": "P%d" % i, "pack": Packs.ORDER[i], "bot": i > 0})
	var run := Run.new({"mode": "party", "seed": 9, "pilots": list})
	var view := RunView.new()
	root.add_child(view)
	view.setup(run, run.pilots[0].id, 1)
	var bots := {}
	for p in run.pilots:
		bots[p.id] = Autopilot.new("average", p.id + 9)
	for i in 600:
		var inputs := {}
		for p in run.pilots:
			inputs[p.id] = bots[p.id].think(run, p)
		run.step(inputs)
		for e in run.take_events():
			view.on_event(e)
		view.sync(1.0 / 60.0)
	t.check(view.pilots.size() == run.pilots.size(), "every pilot has a view")
	t.check(not view.rooms.is_empty(), "rooms are drawn")
	await t.get_tree().process_frame
	root.free()
