extends Node
## Screenshots of the menus, the HUD's moments and the results:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 tools/menu_shot.tscn -- --page=title --out=/tmp/title.png
## Pages: title, daily, courses, hangar, hangar_suits, hangar_gadgets,
## settings, about, howto, pause, results, results_course, party_hud, tutorial.
## Progress is a made-up pilot (rank 7, some credits and missions), kept in
## user://shot_progress.cfg so the real save is untouched.

var out := "/tmp/menu.png"
var page_name := "title"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--page="):
			page_name = a.trim_prefix("--page=")
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, 0.25)
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	BurnTheme.apply(get_tree().root, 22)
	LGSettings.set_value("player", "name", "Dee", false)
	Progress.save_path = "user://shot_progress.cfg"
	Progress.ghost_dir = "user://shot_ghosts/"
	Progress.reset()
	_fake_progress()
	match page_name:
		"pause", "results", "results_course", "party_hud", "tutorial":
			await _run_page()
		_:
			await _title_page()
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _fake_progress() -> void:
	Progress._cfg.set_value("missions", "done", 22)
	Progress._cfg.set_value("missions", "next", 24)
	Progress._cfg.set_value("missions", "active", ["fly_2000", "near_25", "staff_25"])
	Progress._cfg.set_value("missions", "banked", {"staff_25": 17.0})
	Progress._cfg.set_value("wallet", "credits", 4210)
	Progress._cfg.set_value("best", "lanes_normal", 2906)
	Progress._cfg.set_value("hangar", "gadgets_owned", ["magnet", "shield", "hints"])
	Progress._cfg.set_value("hangar", "gadgets", ["magnet", "hints"])
	Progress._cfg.set_value("hangar", "pack", "k2")
	var medals := ["gold", "silver", "patrol"]
	for i in 3:
		var id := str(Courses.ids()[i])
		Progress._cfg.set_value("courses", id, float(Courses.medal_times(id)[medals[i]]) - 0.1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _title_page() -> void:
	var title: TitleScreen = load(TitleScreen.SCENE).instantiate()
	add_child(title)
	await _frames(2)
	match page_name:
		"daily":
			title.show_daily()
		"courses":
			title.show_courses()
		"hangar":
			title.show_hangar()
		"hangar_suits", "hangar_gadgets":
			title.show_hangar()
			await _frames(2)
			var h: HangarPanel = title.find_children("", "HangarPanel", true, false)[0]
			h.show_tab("suits" if page_name == "hangar_suits" else "gadgets")
		"settings":
			title.show_settings()
		"about":
			title.show_about()
		"howto":
			title.show_howto()
	# Let the backdrop fly a while.
	for i in 240:
		title._backdrop._physics_process(Run.DT)
	await _frames(20)


func _run_page() -> void:
	var config: Dictionary
	match page_name:
		"results_course":
			config = Flights.course("lab_2")
		"party_hud":
			config = Flights.party_couch([0], 3)
		"tutorial":
			config = Flights.tutorial()
		_:
			config = Flights.endless()
			config["seed"] = 77
	config["bots"] = config.get("bots", {})
	config.bots[1] = "expert"
	config["local"] = {}
	config["me"] = 1
	if page_name == "results":
		config.pilots[0]["gadgets"] = ["magnet", "hints"]
	var scene: RunScene = load("res://game/play/run_scene.tscn").instantiate()
	scene.config = config
	add_child(scene)
	await _frames(2)
	var secs: float = {"pause": 26.0, "results": 34.0, "results_course": 90.0, "party_hud": 22.0, "tutorial": 6.0}[page_name]
	for i in int(secs / Run.DT):
		scene._physics_process(Run.DT)
		if scene.over and page_name.begins_with("results"):
			break
	match page_name:
		"pause":
			scene.open_pause()
		"results", "results_course":
			if page_name == "results":
				scene.run.pilot(1).stats["killed_by"] = "seeker"
			var r := scene._finish_run()
			if page_name == "results":
				scene.report["missions"] = [{"text": "Fly 2,000 m", "reward": 80}, {"text": "Get 25 near misses in one run", "reward": 80}]
				scene.report["rank"] = 8
				scene.report["rank_before"] = 7
				scene.report["unlocked"] = [{"name": "Unicorn suit"}]
				scene.report["new_best"] = false
			scene._open_results(r)
			for i in 150:
				scene.results._process(1.0 / 60.0)
	scene.reset_physics_interpolation()
	await _frames(12)
