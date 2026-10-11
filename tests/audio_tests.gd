extends RefCounted
## Sound and music: every sound the code names is there and loads, loops
## loop, the music's stems line up, every run event plays without trouble,
## and the music's layers follow the Burn.


func test_sounds_load(t) -> void:
	for n in RunAudio.SOUNDS:
		var s := GameAudio.sfx(str(n))
		t.check(s != null, "sound %s loads" % n)
		if s and (str(n).ends_with("_loop") or str(n).begins_with("amb_")):
			t.check(s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop, "%s loops" % n)
	for k in GameAudio.UI:
		t.check(GameAudio.stream(str(GameAudio.UI[k][0])) != null, "menu sound %s loads" % k)
	for k in GameAudio.STINGERS:
		t.check(GameAudio.sfx(str(GameAudio.STINGERS[k][0])) != null, "stinger %s loads" % k)
	for track in GameAudio.TRACKS:
		var stems: Array = GameAudio.TRACKS[track].stems
		var length := -1.0
		for stem in stems:
			var s := GameAudio.stream("music/" + str(stem))
			t.check(s != null and (s as AudioStreamOggVorbis).loop, "music %s loads and loops" % stem)
			if s == null:
				continue
			if length < 0.0:
				length = s.get_length()
			t.check(absf(s.get_length() - length) < 0.002, "%s is as long as the rest of %s" % [stem, track])
			var bar := 240.0 / float(GameAudio.TRACKS[track].bpm)
			t.check(absf(fmod(s.get_length() + 0.001, bar) - 0.001) < 0.003, "%s is whole bars" % stem)
	t.check(GameAudio.missing.is_empty(), "no sound is missing (%s)" % ", ".join(GameAudio.missing))


## Every kind of run event, as the run would send it.
func _events(run: Run) -> Array:
	var p := run.pilots[0]
	var s: Dictionary = run.staff[0] if not run.staff.is_empty() else {"id": 1}
	var at := {"x": p.x + 3.0, "y": 2.0, "lane": 1}
	return [
		{"type": "room", "room": 9, "zone": "servers", "x": p.x},
		{"type": "lane", "pilot": 1, "to": 2},
		{"type": "pulse", "pilot": 1},
		{"type": "land", "pilot": 1, "speed": 12.0},
		{"type": "near", "pilot": 1, "what": "close", "kind": "zapper", "points": 1, "level": 2, "up": true, "x": p.x, "y": 2.0},
		{"type": "near", "pilot": 1, "what": "razor", "kind": "laser", "points": 2, "level": 3, "up": false, "x": p.x, "y": 2.0},
		{"type": "near", "pilot": 1, "what": "thread", "kind": "seeker", "points": 2, "level": 5, "up": true, "x": p.x, "y": 2.0},
		{"type": "near", "pilot": 1, "what": "skim", "kind": "zapper", "points": 1, "level": 5, "up": false, "x": p.x, "y": 2.0},
		{"type": "burn_lost", "pilot": 1, "why": "floor"},
		{"type": "credit", "pilot": 1, "pickup": 1, "value": 2, "big": false, "x": at.x, "y": at.y, "lane": 1},
		{"type": "credit", "pilot": 1, "pickup": 2, "value": 2, "big": false, "x": at.x, "y": at.y, "lane": 1},
		{"type": "credit", "pilot": 1, "pickup": 3, "value": 20, "big": true, "x": at.x, "y": at.y, "lane": 1},
		{"type": "smash", "pilot": 1, "hazard": 1, "kind": "walker", "how": "stomp", "x": at.x, "y": 1.0, "lane": 1, "credits": 10},
		{"type": "vehicle", "pilot": 1, "pickup": 4, "vehicle": "raptor", "x": at.x, "lane": 1},
		{"type": "jump", "pilot": 1},
		{"type": "flip", "pilot": 1},
		{"type": "hop", "pilot": 1},
		{"type": "shot", "pilot": 1, "x": at.x, "y": 2.0, "lane": 1},
		{"type": "vehicle_lost", "pilot": 1, "vehicle": "raptor", "kind": "zapper", "x": p.x, "y": 1.0, "lane": 1.0},
		{"type": "knock", "pilot": 1, "staff": s.id, "x": at.x, "lane": 0},
		{"type": "shield", "pilot": 1, "kind": "zapper"},
		{"type": "armour", "pilot": 1, "kind": "laser"},
		{"type": "reboot", "pilot": 1, "kind": "seeker"},
		{"type": "stun", "pilot": 1, "kind": "zapper", "x": p.x, "y": 1.0, "lost_burn": true},
		{"type": "out", "pilot": 1, "place": 3},
		{"type": "rocket_end", "pilot": 1},
		{"type": "crash", "pilot": 1, "kind": "zapper", "x": p.x, "y": 2.0, "lane": 1.0},
		{"type": "done", "pilot": 1, "distance": p.x},
		{"type": "finish", "pilot": 1, "time": 60.0},
		{"type": "round_over", "winner": 1},
		{"type": "run_over", "distance": p.x},
	]


func _holder(t) -> Node3D:
	var root := Node3D.new()
	t.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.0, 6.0, 14.0)
	cam.make_current()
	return root


func test_every_event_plays(t) -> void:
	var root := _holder(t)
	var run := Run.new({"mode": "endless", "seed": 5, "pilots": [{"id": 1, "name": "You", "pack": "k5"}]})
	var audio := RunAudio.new()
	root.add_child(audio)
	audio.setup(run, 1)
	var silent := ["room", "done", "finish", "round_over", "run_over"]
	var types := {}
	for e in _events(run):
		var before: int = audio.voices.played
		var waiting: int = audio.voices._pending.size()
		var stingers := GameAudio.stingers_played
		audio.on_event(e)
		audio.sync(0.1)
		types[e.type] = true
		if e.type in ["finish", "round_over", "run_over"]:
			t.check(GameAudio.stingers_played > stingers, "%s plays its stinger" % e.type)
		elif not e.type in silent:
			t.check(audio.voices.played > before or audio.voices._pending.size() > waiting, "%s makes a sound" % e.type)
	for type in ["armour", "burn_lost", "crash", "credit", "done", "finish", "flip", "hop", "jump", "knock", "land",
			"lane", "near", "out", "pulse", "reboot", "rocket_end", "room", "round_over", "run_over", "shield", "shot",
			"smash", "stun", "vehicle", "vehicle_lost"]:
		t.check(types.has(type), "the test covers %s" % type)
	t.check(audio.voices.busy() <= SfxVoices.SIZE, "the voice budget holds")
	t.check(GameAudio.missing.is_empty(), "every event's sound is there")
	root.queue_free()
	await t.get_tree().process_frame


## Flies a run with a bot, feeding the sound everything as the game does.
func _fly(t, config: Dictionary, bots: Dictionary, me: int, seconds: float) -> Dictionary:
	var root := _holder(t)
	var run := Run.new(config)
	var audio := RunAudio.new()
	root.add_child(audio)
	audio.setup(run, me)
	var brains := {}
	for id in bots:
		brains[id] = Autopilot.new(str(bots[id]), hash([run.seed, id]))
	var kinds := {}
	var most := 0
	var loops := 0
	while run.time < seconds and not run.finished:
		var inputs := {}
		for id in brains:
			var p := run.pilot(id)
			if p:
				inputs[id] = brains[id].think(run, p)
		run.step(inputs)
		for e in run.take_events():
			kinds[e.type] = true
			audio.on_event(e)
		audio.sync(Run.DT)
		most = maxi(most, audio.voices.busy())
		var on := 0
		for c in audio.get_children():
			if c is AudioStreamPlayer3D and c.playing:
				on += 1
		loops = maxi(loops, on)
	var out := {"run": run, "kinds": kinds, "most": most, "loops": loops, "played": audio.voices.played}
	root.queue_free()
	await t.get_tree().process_frame
	return out


func test_runs_sound(t) -> void:
	for i in t.games:
		var seed: int = 40 + i
		var solo := {"mode": "endless", "seed": seed, "pilots": [{"id": 1, "name": "You", "pack": Packs.ORDER[i % Packs.ORDER.size()]}]}
		var r: Dictionary = await _fly(t, solo, {1: "average"}, 1, 45.0)
		t.check(int(r.played) > 20, "a run makes sounds (seed %d: %d)" % [seed, r.played])
		t.check(int(r.most) <= SfxVoices.SIZE, "a run keeps to the voice budget")
		var pilots := [{"id": 1, "name": "You", "pack": "k1"}]
		var bots := {1: "average"}
		for k in 3:
			pilots.append({"id": 2 + k, "name": "Bot %d" % k, "pack": Packs.ORDER[k + 1], "bot": true})
			bots[2 + k] = ["novice", "average", "expert"][k]
		var party: Dictionary = await _fly(t, {"mode": "party", "seed": seed, "pilots": pilots}, bots, 1, 40.0)
		t.check(int(party.played) > 10, "a party race makes sounds (seed %d)" % seed)
		t.check(int(party.loops) <= 4 * 2 + RunAudio.HUM_LOOPS + RunAudio.WHIR_LOOPS + RunAudio.ROLL_LOOPS, "a party race keeps its loops in hand")
	t.check(GameAudio.missing.is_empty(), "nothing a run plays is missing")


func test_music_follows_the_burn(t) -> void:
	GameAudio.music("")
	GameAudio.music("run")
	t.check(GameAudio.current_track() == "run", "the run music starts")
	t.check(GameAudio.level() == 1, "the run music starts at x1")
	# Stems: pad, drums, bass, arp, lead, hype.
	t.check(GameAudio.stem_db(1) > -1.0 and GameAudio.stem_db(4) <= GameAudio.OFF + 0.1, "x1 is drums and bass, no lead")
	GameAudio.intensity(5)
	await t.get_tree().create_timer(0.9).timeout
	t.check(GameAudio.stem_db(4) > -1.0 and GameAudio.stem_db(5) > -1.0, "x5 brings in the lead and everything")
	GameAudio.intensity(0)
	await t.get_tree().create_timer(1.6).timeout
	t.check(GameAudio.stem_db(1) <= GameAudio.OFF + 0.1 and GameAudio.stem_db(0) > -6.0, "calm leaves only the pad")
	GameAudio.music("run")
	t.check(GameAudio.level() == 0, "asking again for the playing track changes nothing")
	GameAudio.music("party")
	GameAudio.party_level(3)
	await t.get_tree().create_timer(0.9).timeout
	t.check(GameAudio.stem_db(2) > -1.0, "the last two in a party race get everything")
	GameAudio.music("title")
	t.check(GameAudio.current_track() == "title", "the title music plays")
	GameAudio.ui("confirm")
	GameAudio.ui("move")
	GameAudio.muffle(true, 0.05)
	t.check(GameAudio.is_muffled(), "the music muffles")
	GameAudio.muffle(false, 0.05)
	GameAudio.music("")
	t.check(GameAudio.current_track() == "", "the music stops")
	t.check(GameAudio.missing.is_empty(), "every track is there")
