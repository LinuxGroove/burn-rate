extends RefCounted
## The menus build and show their buttons without a scene change: the
## title's pages, the hangar's tabs, the course picker, the pause menu over a
## run, the results for each kind of run, and the HUD through a whole run.
## Nothing here presses a button that changes the scene or a setting.


func _fresh() -> void:
	Progress.ghost_dir = "user://test_ghosts/"
	Progress.reset()


func _frames(t, n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## A run scene flown by an expert bot in seat 1, as the screenshot tool does.
func _scene(t, config: Dictionary) -> RunScene:
	config["bots"] = config.get("bots", {})
	config.bots[1] = "expert"
	config["local"] = {}
	config["me"] = 1
	var scene: RunScene = load("res://game/play/run_scene.tscn").instantiate()
	scene.config = config
	t.add_child(scene)
	await _frames(t, 2)
	return scene


func _fly(scene: RunScene, secs: float) -> void:
	for i in int(secs / Run.DT):
		scene._physics_process(Run.DT)
		if scene.over:
			break


func _free(t, node: Node) -> void:
	node.queue_free()
	await _frames(t, 2)


func test_title_pages(t) -> void:
	_fresh()
	TitleScreen.next_page = ""
	var title: TitleScreen = load(TitleScreen.SCENE).instantiate()
	t.add_child(title)
	await _frames(t, 3)
	var main := title.button_texts()
	for want in ["Fly", "Courses", "Party", "Hangar", "Leaderboards", "Settings", "How to play", "About", "Quit"]:
		t.check(want in main, "the title has %s" % want)
	t.check(Array(main).any(func(s): return str(s).begins_with("Daily Flight")), "the title has the Daily Flight")
	t.check(str(main[0]) == "Fly", "Fly comes first")
	var quit: Button
	for b in title._menu.find_children("", "Button", true, false):
		if (b as Button).text == "Quit":
			quit = b
	t.check(quit != null and quit.pressed.get_connections().any(func(c): return c.callable.get_method() == "_quit"), "Quit goes through the survey (LGScenes.quit)")
	title.show_daily()
	await _frames(t, 1)
	t.check(str(title.button_texts()[0]) == "Fly today's flight", "the Daily Flight page has a way in")
	t.check("Back" in title.button_texts(), "the Daily Flight page has Back")
	var party: Button = null
	for b in title._menu.find_children("", "Button", true, false):
		if (b as Button).text == "Party":
			party = b
	t.check(party != null and party.pressed.get_connections().any(func(c): return c.callable.get_method() == "open_party"), "Party opens the lobby")
	title.show_settings()
	await _frames(t, 1)
	t.check("Back" in title.button_texts(), "Settings has Back")
	title.show_about()
	await _frames(t, 1)
	t.check("Back" in title.button_texts(), "About has Back")
	title.show_leaderboards()
	await _frames(t, 1)
	t.check("Back" in title.button_texts(), "Leaderboards has Back")
	title.show_hangar()
	await _frames(t, 2)
	t.check(title.page == "hangar", "the hangar opens from the title")
	title.show_courses()
	await _frames(t, 2)
	t.check(title.page == "courses", "the courses open from the title")
	title.show_main()
	await _frames(t, 1)
	t.check("Fly" in title.button_texts(), "back on the main menu")
	t.check(title.ABOUT_TEXT.contains("Drew VanDine") and title.ABOUT_TEXT.contains("The LinuxGroove team"), "About names the makers")
	await _free(t, title)


func test_hangar_tabs(t) -> void:
	_fresh()
	var hangar := HangarPanel.new()
	t.add_child(hangar)
	await _frames(t, 2)
	var texts := hangar.button_texts()
	t.check(texts.size() > 6, "the hangar builds its tabs and tiles")
	t.check(Array(texts).any(func(s): return str(s).contains(str(Packs.spec("k1").name).to_upper().split(" ")[0])), "the first prototype has a tile")
	for tab in ["packs", "suits", "gadgets", "pilot"]:
		hangar.show_tab(tab)
		await _frames(t, 1)
		t.check(hangar.tab == tab and hangar.button_texts().size() > 4, "the %s tab builds" % tab)
	hangar.show_tab("packs")
	hangar._cycle_tab(1)
	t.check(hangar.tab == "suits", "the right shoulder moves to the next tab")
	hangar._cycle_tab(-1)
	hangar._cycle_tab(-1)
	t.check(hangar.tab == "pilot", "the left shoulder wraps round")
	await _free(t, hangar)


func test_course_picker(t) -> void:
	_fresh()
	var picker := CoursePicker.new()
	t.add_child(picker)
	await _frames(t, 2)
	t.check("Back" in picker.button_texts(), "the course picker has Back")
	for z in Zones.ORDER:
		var ids: Array = Courses.in_zone(z)
		if ids.is_empty():
			continue
		picker.show_zone(z)
		await _frames(t, 1)
		var texts := picker.button_texts()
		for id in ids:
			t.check(Array(texts).any(func(s): return str(s).contains(str(Courses.get_def(id).name).to_upper())), "%s has a tile in %s" % [id, z])
	var picked := []
	picker.picked.connect(func(id): picked.append(id))
	picker._pick(Courses.ids()[0])
	t.check(picked == [Courses.ids()[0]], "picking a course says which")
	await _free(t, picker)


func test_pause_menu(t) -> void:
	_fresh()
	var scene := await _scene(t, Flights.endless())
	_fly(scene, 4.0)
	scene.open_pause()
	await _frames(t, 1)
	t.check(scene.paused and scene.pause_menu != null, "the run pauses")
	var texts := scene.pause_menu.button_texts()
	for want in ["Fly on", "Fly again", "Settings", "How to play", "Back to the title"]:
		t.check(want in texts, "the pause menu has %s" % want)
	t.check(scene.can_restart(), "you can fly again from the pause menu")
	var x := scene.run.pilot(1).x
	scene._physics_process(Run.DT)
	t.check(is_equal_approx(scene.run.pilot(1).x, x), "nothing moves while paused")
	scene.pause_menu.settings()
	await _frames(t, 1)
	t.check("Back" in scene.pause_menu.button_texts(), "settings in the pause menu have Back")
	scene.pause_menu.main()
	await _frames(t, 1)
	scene.pause_menu.close()
	await _frames(t, 1)
	t.check(not scene.paused, "Fly on flies on")
	scene.restart()
	await _frames(t, 1)
	t.check(scene.run.time < 0.1 and not scene.over, "Fly again starts a new run")
	await _free(t, scene)


func test_results(t) -> void:
	_fresh()
	var scene := await _scene(t, Flights.endless())
	_fly(scene, 6.0)
	var r := scene._finish_run()
	t.check(r.mode == "endless" and r.has("distance") and r.has("stats"), "a run's result has what Progress needs")
	t.check(Progress.total("runs") == 1, "the run is banked")
	scene._open_results(r)
	await _frames(t, 1)
	var texts := scene.results.button_texts()
	t.check(texts.size() > 0 and texts[0] == "Fly again", "Fly again comes first after a run")
	t.check("Hangar" in texts and "To the title" in texts, "the results lead to the hangar and the title")
	for i in 300:
		scene.results._process(1.0 / 60.0)
	await _free(t, scene)
	var panel := ResultsPanel.new()
	t.add_child(panel)
	var base := {"distance": 120.0, "credits": 4, "best_burn": 1, "time": 40.0, "stats": {"killed_by": "laser"}, "winner": -1, "me": 1, "pack": "k1"}
	var cases := {
		"tutorial": ["Fly for real", "First flight again", "To the title"],
		"party": ["Race again", "To the title"],
	}
	for mode in cases:
		var rr := base.duplicate()
		rr["mode"] = mode
		rr["standings"] = []
		panel.show_run(rr, {})
		t.check(Array(panel.button_texts()) == cases[mode], "%s results: %s" % [mode, panel.button_texts()])
	var course := base.duplicate()
	course["mode"] = "course"
	course["course"] = Courses.ids()[0]
	course["stats"] = {"finish_time": 61.0}
	panel.show_run(course, {"medal": "silver", "best": 61.0, "new_best": true})
	var ct := panel.button_texts()
	t.check(ct[0] == "Fly again" and "Courses" in ct and Array(ct).any(func(s): return str(s).begins_with("Next: ")), "course results offer the next course")
	t.check(ResultsPanel.kill_text("laser") != "" and ResultsPanel.kill_text("nothing at all") != "", "every way to stop has words")
	await _free(t, panel)


func test_hud_through_a_run(t) -> void:
	_fresh()
	for config in [Flights.endless(), Flights.course(Courses.ids()[0]), Flights.tutorial(), Flights.party_couch([0], 3)]:
		var scene := await _scene(t, config)
		_fly(scene, 20.0)
		t.check(scene.hud != null and scene.run.time > 1.0, "%s flies with its HUD" % scene.run.mode)
		scene.hud.set_finished(true)
		await _frames(t, 1)
		await _free(t, scene)


## The window losing focus opens the pause menu (LGFocusPause), unless focus
## comes straight back, the setting is off or the on-screen keyboard is up.
## The run pauses itself; the tree carries on.
func test_focus_pause(t) -> void:
	_fresh()
	var scene := await _scene(t, Flights.endless())
	_fly(scene, 2.0)
	var watcher: LGFocusPause = scene.get_node_or_null("FocusPause")
	t.check(watcher != null, "the run watches for the window losing focus")
	if watcher == null:
		await _free(t, scene)
		return
	# The watcher counts real milliseconds, so wait in real time.
	var grace := LGFocusPause.GRACE_MSEC / 1000.0 + 0.15
	watcher.focus_lost()
	await _frames(t, 1)
	watcher.focus_back()
	await t.get_tree().create_timer(grace, true, false, true).timeout
	t.check(scene.pause_menu == null, "focus coming straight back doesn't open the pause menu")
	watcher.focus_lost()
	await t.get_tree().create_timer(grace, true, false, true).timeout
	t.check(scene.paused and scene.pause_menu != null, "losing focus pauses the run")
	scene.pause_menu.close()
	await _frames(t, 1)
	t.check(not scene.paused and scene.pause_menu == null, "Fly on flies on after losing focus")
	LGSettings.set_value("video", "focus_pause", false, false)
	t.check(not watcher.pause_now() and scene.pause_menu == null, "Pause when switching away can be turned off")
	LGSettings.set_value("video", "focus_pause", true, false)
	var field := LineEdit.new()
	t.add_child(field)
	OnScreenKeyboard.open(field)
	t.check(not watcher.pause_now() and scene.pause_menu == null, "losing focus leaves the on-screen keyboard alone")
	field.queue_free()
	await _free(t, scene)


func test_backdrop_has_no_menus(t) -> void:
	var scene: RunScene = load("res://game/play/run_scene.tscn").instantiate()
	scene.config = Flights.backdrop()
	t.add_child(scene)
	await _frames(t, 2)
	t.check(scene.backdrop and scene.hud == null, "the title's backdrop flies without a HUD")
	for i in 600:
		scene._physics_process(Run.DT)
	t.check(scene.run.time > 5.0 or scene.run.time < 2.0, "the backdrop keeps flying (and starts again when it ends)")
	scene.open_pause()
	t.check(scene.pause_menu == null, "the backdrop never pauses")
	t.check(scene.get_node_or_null("FocusPause") == null, "the backdrop doesn't pause when the window loses focus")
	await _free(t, scene)


func test_settings_and_howto_build(t) -> void:
	var s := PlaySettings.new()
	t.add_child(s)
	await _frames(t, 1)
	var labels := s.find_children("", "LGCycler", true, false).map(func(c): return (c as LGCycler).label_text)
	for want in ["Rumble", "Reduce flashing", "Calm background"]:
		t.check(labels.any(func(x): return str(x).contains(want)), "settings have %s" % want)
	s.queue_free()
	var h := HowToPanel.new()
	t.add_child(h)
	h.offer_first_flight = true
	h.open()
	h.show_page(HowToPanel.pages().size() - 1)
	await _frames(t, 1)
	var bs := h.find_children("", "Button", true, false).map(func(b): return (b as Button).text)
	t.check("First flight" in bs, "how to play offers the first flight")
	h.close()
	await _free(t, h)
