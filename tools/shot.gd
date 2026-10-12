extends Node
## One screenshot of a run, fast-forwarded by a bot:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 tools/shot.tscn -- --out=/tmp/shot.png --at=12 [--zone=servers] [--mode=party] [--bot=expert]
## Takes the same shortcuts as `--solo` (see main.gd).

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, 0.25)
	LGTheme.apply(get_tree().root, 22)
	BurnTheme.apply(get_tree().root, 22)
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/shot.png"
	var at := 8.0
	for a in args:
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--at="):
			at = float(a.trim_prefix("--at="))
	var config: Dictionary = load("res://game/main.gd").dev_config(args)
	if not config.has("bots") or not config.bots.has(1):
		var bots: Dictionary = config.get("bots", {})
		bots[1] = "expert"
		config["bots"] = bots
		config["local"] = {}
		config["me"] = 1
	var scene: RunScene = load("res://game/play/run_scene.tscn").instantiate()
	scene.config = config
	add_child(scene)
	await get_tree().process_frame
	scene.paused = true
	var ticks := int(at / Run.DT)
	for i in ticks:
		scene.paused = false
		scene._physics_process(Run.DT)
		scene.paused = true
	if "--close" in args:
		# Close on the pilot, from the side and a little in front.
		var pv: Node3D = scene.view.pilots[1]
		scene.camera.keep_aspect = Camera3D.KEEP_HEIGHT
		scene.camera.fov = 30.0
		scene.camera.position = pv.global_position + Vector3(0.6, 1.2, 4.5)
		scene.camera.look_at(pv.global_position + Vector3(0, 0.9, 0))
		scene.camera.set_process(false)
	scene.reset_physics_interpolation()
	for i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " at ", scene.run.distance(), " m")
	get_tree().quit()
