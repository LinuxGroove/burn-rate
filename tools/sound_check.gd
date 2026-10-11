extends Node
## Records the sound of a bot's run to a WAV, to check the mix without
## speakers (look at it with a spectrogram, or listen later):
##   godot --headless --path . tools/sound_check.tscn -- --out=/tmp/run.wav --seconds=40 [--mode=party --bots=3] [--pack=k2] [--seed=3]
## Takes the same shortcuts as `--solo` (see main.gd); the run plays in real
## time, since the sound does.

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, 0.25)
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/run.wav"
	var seconds := 30.0
	for a in args:
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--seconds="):
			seconds = float(a.trim_prefix("--seconds="))
	var config: Dictionary = load("res://game/main.gd").dev_config(args)
	if not config.has("bots") or not config.bots.has(1):
		var bots: Dictionary = config.get("bots", {})
		bots[1] = "average"
		config["bots"] = bots
		config["local"] = {}
		config["me"] = 1
	# --no-music or --no-sfx to hear one without the other.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), "--no-music" in args)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), "--no-sfx" in args)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var scene: RunScene = load("res://game/play/run_scene.tscn").instantiate()
	scene.config = config
	add_child(scene)
	await get_tree().create_timer(seconds).timeout
	rec.set_recording_active(false)
	scene.queue_free()
	await get_tree().process_frame
	var wav := rec.get_recording()
	if wav == null:
		printerr("Nothing was recorded (is the audio driver mixing?)")
		get_tree().quit(1)
		return
	wav.save_to_wav(out)
	print("Recorded %.1f s of %s to %s" % [wav.get_length(), str(config.mode), out])
	get_tree().quit()
