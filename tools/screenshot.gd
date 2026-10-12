extends Node
## Screenshots of every zone, the doors between them and party races, as
## JPEGs in folders with a README.md listing them:
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots [group=zones]
##
## Groups: zones, transitions, party, detail (low detail and Calm background).
## An expert bot flies; each shot's seed is one the bot survives to that
## point, found by flying the run headless first. Settings are changed for
## this run only, never saved.

const SIZE := Vector2i(1280, 720)
const GROUPS := ["zones", "transitions", "party", "detail"]
const SEEDS := [7, 11, 23, 31, 42, 57, 64, 77, 88, 99, 101, 123]

var _lines: Array = []
var _scene: RunScene


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0].trim_prefix("--")] = kv[1] if kv.size() > 1 else "1"
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, 0.25)
	LGTheme.apply(get_tree().root, 22)
	# The run is stepped by hand below, outside the physics tick.
	get_tree().physics_interpolation = false
	_settings(1, false)
	var dir := str(args.get("all", "docs/screenshots"))
	var root := dir if dir.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(dir)
	var only := str(args.get("group", ""))
	_lines = ["# Screenshots", "",
		"Every zone of the tower mid-run, the doors between zones, party races and the low detail path, made with:", "",
		"    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s \"-screen 0 1280x720x24\" godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots", "",
		"Add `group=zones` (or transitions, party, detail) for one group; the README is only rewritten by a whole run.", ""]
	for g in GROUPS:
		if only == "" or only == g:
			await call("_" + g, root)
			_lines.append("")
	if only == "":
		var f := FileAccess.open(root.path_join("README.md"), FileAccess.WRITE)
		f.store_string("\n".join(_lines).strip_edges() + "\n")
	_clear()
	get_tree().quit()


func _zones(root: String) -> void:
	_lines.append_array(["## Zones", "", "Each zone a little way in, with the pilot flying an expert bot's line.", ""])
	for z in Zones.ORDER:
		var name := str(Zones.info(z).name)
		await _fly({"zone": z}, 110.0, root, "zones", z, name)
		await _fly({"zone": z}, 260.0, root, "zones", z + "_deeper", name + ", further in")


func _transitions(root: String) -> void:
	_lines.append_array(["## Doors between zones", "",
		"The room where each zone starts, flown into from the zone before: a doorway inside the tower, out through the Atrium's glass onto the rooftops, and in through Halberd's window.", ""])
	for i in Zones.ORDER.size():
		var from: String = Zones.ORDER[i]
		var to: String = Zones.ORDER[(i + 1) % Zones.ORDER.size()]
		var label := "%s to %s" % [Zones.info(from).name, Zones.info(to).name]
		if to in ["downtown", "halberd"]:
			await _fly({"zone": from, "entry": to}, -4.0, root, "transitions", "%s_to_%s" % [from, to], label)
			await _fly({"zone": from, "entry": to}, 5.0, root, "transitions", "%s_to_%s_through" % [from, to], label + ", through the glass")
		else:
			await _fly({"zone": from, "entry": to}, -1.0, root, "transitions", "%s_to_%s" % [from, to], label)


func _party(root: String) -> void:
	_lines.append_array(["## Party races", "", "Four pilots in a party race against bots.", ""])
	for z in ["lab", "bay", "downtown", "halberd"]:
		var cfg := {"mode": "party", "zone": z, "bots": "3"}
		await _fly(cfg, 90.0, root, "party", z, "Party race in %s" % Zones.info(z).name)


func _detail(root: String) -> void:
	_lines.append_array(["## Low detail and Calm background", "",
		"Low detail is what handhelds run (fewer lights, a smaller city, simpler effects). Calm background dims the city and the far wall.", ""])
	for z in Zones.ORDER:
		_settings(0, false)
		await _fly({"zone": z}, 110.0, root, "detail", z + "_low", "%s, low detail" % Zones.info(z).name)
	for z in ["atrium", "downtown"]:
		_settings(1, true)
		await _fly({"zone": z}, 110.0, root, "detail", z + "_calm", "%s, Calm background" % Zones.info(z).name)
	_settings(1, false)


func _settings(detail: int, calm: bool) -> void:
	LGSettings.set_value("video", "detail", detail, false)
	LGSettings.set_value("comfort", "calm_background", calm, false)
	LGSettings.set_value("comfort", "reduce_flashing", false, false)


## Stages a run from [param opts] (as `--solo` takes them), flies it until the
## camera is over [param at] metres and saves a shot. With an "entry" option,
## [param at] counts from the start of the room where that zone begins.
func _fly(opts: Dictionary, at: float, root: String, folder: String, file: String, caption: String) -> void:
	var cfg := _config(opts, at)
	at = float(cfg.get("shot_at", at))
	_clear()
	_scene = load("res://game/play/run_scene.tscn").instantiate()
	_scene.config = cfg
	add_child(_scene)
	await get_tree().process_frame
	_scene.paused = true
	var limit := int(at / 4.0 / Run.DT) + 600
	# Fly without drawing, letting a frame pass now and then so the rooms
	# left behind are really freed.
	RenderingServer.render_loop_enabled = false
	for i in limit:
		if _scene.camera.target_x() >= at or _scene.over:
			break
		_scene.paused = false
		_scene._physics_process(Run.DT)
		_scene.paused = true
		if i % 120 == 119:
			await get_tree().process_frame
	RenderingServer.render_loop_enabled = true
	_scene.reset_physics_interpolation()
	_scene.camera.reset_physics_interpolation()
	# Let the glow and the eased looks settle without the run moving.
	for i in 30:
		Look.update(_scene._env, _scene.run, _scene.me, Run.DT)
		_scene.view.sync(0.0)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(root.path_join(folder))
	var img := get_viewport().get_texture().get_image()
	if img.get_size() != SIZE:
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.save_jpg(root.path_join(folder).path_join(file + ".jpg"), 0.88)
	_lines.append("- [%s](%s/%s.jpg)" % [caption, folder, file])
	print("saved %s/%s at %d m (seed %d), %d draws, %d objects" % [folder, file, int(_scene.camera.target_x()), cfg.seed,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _clear() -> void:
	if _scene:
		remove_child(_scene)
		_scene.free()
		_scene = null


## A run config for these options, with a seed the bot survives to [param at].
func _config(opts: Dictionary, at: float) -> Dictionary:
	var best := {}
	var best_x := -1.0
	for s in SEEDS:
		var args := ["--seed=%d" % s, "--bot=expert"]
		for k in opts:
			if k != "entry":
				args.append("--%s=%s" % [k, opts[k]])
		var cfg: Dictionary = load("res://game/main.gd").dev_config(args)
		cfg["shot_at"] = at
		if opts.has("entry"):
			cfg["shot_at"] = _entry_x(cfg, str(opts.entry)) + at
		var reached := _reach(cfg, cfg.shot_at)
		if reached >= cfg.shot_at:
			return cfg
		if reached > best_x:
			best_x = reached
			best = cfg
	return best


## Where the first room of [param zone] starts on this run's course.
func _entry_x(cfg: Dictionary, zone: String) -> float:
	var course := Course.new(cfg)
	for i in 400:
		var r := course.next_room()
		if r.index > 0 and str(r.tags.get("entry", "")) == zone:
			return r.x0
	return 0.0


## How far the run's camera gets towards [param at] before pilot 1 is out.
func _reach(cfg: Dictionary, at: float) -> float:
	var run := Run.new(cfg)
	var bots := {}
	for id in cfg.get("bots", {}):
		bots[int(id)] = Autopilot.new(str(cfg.bots[id]), hash([run.seed, int(id)]))
	var me := run.pilot(1)
	var lead := RunCamera.WIDTH * (0.5 - RunCamera.PILOT_AT)
	for i in int(at / 4.0 / Run.DT) + 600:
		var inputs := {}
		for id in bots:
			var p := run.pilot(id)
			if p:
				inputs[id] = bots[id].think(run, p)
		run.step(inputs)
		run.take_events()
		if run.mode != "party" and not me.alive():
			return me.x
		if (run.cam_x if run.mode == "party" else me.x) + lead >= at:
			return at
	return me.x
