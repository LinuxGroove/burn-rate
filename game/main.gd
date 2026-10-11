extends Node
## Boots the game: settings, the launch ping, play tests, the input map, the
## theme and the window, then the title screen.
##
## Developer shortcuts (after `--`):
##   --solo                  straight into an endless run
##   --mode=daily|course|tutorial|party   with --solo: the mode
##   --course=lab_1          with --mode=course
##   --zone=servers          start in a zone
##   --pack=k3               fly a prototype
##   --bots=3                party: this many bot pilots
##   --bot=average           let a bot fly your pilot (novice, average, expert)
##   --classic               lanes off
##   --pace=fast             calm, normal or fast
##   --seed=42
##   --title                 the title, even before the first flight

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGLaunchPing.send(GameConfig.GAME_ID)
	LGPlaytest.setup(GameConfig.GAME_ID, GameConfig.PLAYTEST)
	LGInput.register_actions(GameConfig.ACTIONS, float(LGSettings.get_value("input", "stick_deadzone")))
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	BurnTheme.apply(get_tree().root, 22)
	get_window().title = GameConfig.TITLE
	PlaySettings.apply_flashing()
	GameAudio.hook_menus(get_tree())
	var args := OS.get_cmdline_user_args()
	if "--solo" in args:
		Session.launch(dev_config(args))
		return
	# The first time, the first flight comes before the title.
	if not bool(LGSettings.get_value("tutorial", "welcomed", false)) and not "--title" in args:
		Session.launch(Flights.tutorial())
		return
	LGScenes.change_scene(TitleScreen.SCENE)


## A run's config from the developer shortcuts.
static func dev_config(args: Array) -> Dictionary:
	var opts := {}
	for a in args:
		if a.begins_with("--") and "=" in a:
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var mode := str(opts.get("mode", "endless"))
	var pack := str(opts.get("pack", "k1"))
	var config := {
		"mode": mode, "seed": int(opts.get("seed", randi() % 100000)), "pace": str(opts.get("pace", "normal")),
		"lanes": not "--classic" in args,
		"pilots": [{"id": 1, "name": "You", "pack": pack}],
		"local": {1: 0},
	}
	if opts.has("zone"):
		config["zone"] = opts.zone
	if opts.has("course"):
		config["course"] = opts.course
	if opts.has("bot"):
		config["local"] = {}
		config["bots"] = {1: opts.bot}
		config["me"] = 1
	if mode == "party":
		var n := int(opts.get("bots", 3))
		var used := ["You"]
		var bots: Dictionary = config.get("bots", {})
		for i in n:
			var bot_name := LGNameMaker.make(used)
			used.append(bot_name)
			config.pilots.append({"id": 2 + i, "name": bot_name, "pack": Packs.ORDER[(i + 1) % Packs.ORDER.size()], "bot": true})
			bots[2 + i] = ["novice", "average", "expert"][i % 3]
		config["bots"] = bots
	return config
