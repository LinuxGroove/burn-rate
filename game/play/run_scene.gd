class_name RunScene
extends Node3D
## One run on screen: steps the [Run] on the physics tick with this device's
## controls and its bots, and hands what happened to the view, the HUD and
## the sounds. Every mode plays here: endless, the Daily Flight, a Course,
## the first flight and party races (on one screen, or one pilot of an
## online or LAN race, where [RunNet] carries the other pilots), and the
## title's backdrop.
##
## [member config] is what [Session] launched: the run's own config (see
## [Run]) plus "local" (pilot id -> seat index on this device) and "bots"
## (pilot id -> skill) for the pilots this device steers. Extra keys:
##   backdrop   true: no HUD, sound or menus, and a new run when it ends
##   date       the Daily Flight's date
##   ghosts     more ghosts to fly beside you (Ghost objects or their dicts)
##   round, wins, first_to   party races: the round, pilot id -> rounds won,
##              and rounds to win the race

signal finished(result: Dictionary)

## A ghost's look when the pilot view has no ghost style of its own.
const GHOST_FADE := 0.6
## Behind the title, how much further right the pilot sits (screen widths).
const BACKDROP_SHIFT := 0.24

## Set by Session before the scene loads.
static var next_config := {}

var config := {}
var run: Run
var view: RunView
var camera: RunCamera
var hud: RunHud
## Pilot id -> LGSeat for the people on this device.
var seats := {}
## Pilot id -> Autopilot for bots this device runs.
var bots := {}
## The pilot this screen follows.
var me := 1
var paused := false
var over := false
var _was_fly := {}
## Pilot id -> RunInput, filled by RunNet for pilots on other devices.
var remote_inputs := {}
var _env: WorldEnvironment
var audio: RunAudio
var net: RunNet
var backdrop := false
## The ghost this run records (Daily Flight and courses), and the ones it
## flies against: [{ghost, pilot, view}].
var recording: Ghost
var ghosts: Array = []
var pause_menu: PauseMenu
var results: ResultsPanel
## What Progress made of the run, once it's over.
var report := {}
var _layer: CanvasLayer
var _recorded := false
var _end_timer := 0.0
var _backdrop_wait := 0.0


func _ready() -> void:
	if config.is_empty():
		config = next_config if not next_config.is_empty() else {"mode": "endless", "seed": randi()}
	start(config)


## Starts a run (or restarts with a new config).
func start(p_config: Dictionary) -> void:
	config = p_config
	for c in get_children():
		remove_child(c)
		c.queue_free()
	seats.clear()
	bots.clear()
	_was_fly.clear()
	remote_inputs.clear()
	ghosts.clear()
	over = false
	paused = false
	report = {}
	_recorded = false
	_end_timer = 0.0
	pause_menu = null
	results = null
	net = null
	backdrop = bool(config.get("backdrop", false))
	run = Run.new(config)
	var local: Dictionary = config.get("local", {1: 0})
	for id in local:
		seats[int(id)] = Session.seat_input(int(local[id]))
	var bot_list: Dictionary = config.get("bots", {})
	for id in bot_list:
		bots[int(id)] = Autopilot.new(str(bot_list[id]), hash([run.seed, id]))
	me = int(config.get("me", seats.keys()[0] if not seats.is_empty() else run.pilots[0].id))
	_env = Look.build(self)
	view = RunView.new()
	view.name = "View"
	add_child(view)
	view.setup(run, me, detail())
	camera = RunCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.setup(run, me)
	camera.make_current()
	hud = null
	audio = null
	if not backdrop:
		hud = RunHud.new()
		hud.name = "Hud"
		add_child(hud)
		hud.setup(run, me, camera, config)
		audio = RunAudio.new()
		audio.name = "Audio"
		add_child(audio)
		audio.setup(run, me)
		_layer = CanvasLayer.new()
		_layer.name = "Menus"
		_layer.layer = 20
		add_child(_layer)
		_setup_ghosts()
	if bool(config.get("net", false)):
		net = RunNet.new()
		net.name = "Net"
		add_child(net)
		net.setup(self)
	if not backdrop:
		var pv: Node = view.pilots.get(me)
		if pv:
			LGPlaytest.follow(pv)
		LGPlaytest.event("run_start", {"mode": run.mode, "pack": _my_pack(), "pace": run.pace, "lanes": run.lanes_on, "seed": run.seed})


## 0 on handhelds and the Mobile renderer, 1 otherwise.
static func detail() -> int:
	if int(LGSettings.get_value("video", "detail")) <= 0:
		return 0
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return 0
	return 1


func _my_pack() -> String:
	var p := run.pilot(me)
	return p.pack if p else "k1"


func _physics_process(_delta: float) -> void:
	if run == null:
		return
	if backdrop and run.finished:
		_backdrop_wait += Run.DT
		if _backdrop_wait > 2.5:
			_backdrop_wait = 0.0
			var c := config.duplicate()
			c["seed"] = randi()
			c["zone"] = Zones.ORDER[randi() % 4]
			start(c)
		return
	if paused and not _networked():
		return
	var inputs := {}
	for id in seats:
		inputs[id] = _read_seat(id, seats[id]) if not paused else RunInput.NONE
	for id in bots:
		var p := run.pilot(id)
		if p:
			inputs[id] = bots[id].think(run, p)
	if net:
		net.before_step(inputs)
	for id in remote_inputs:
		inputs[id] = remote_inputs[id]
	run.step(inputs)
	if net:
		net.after_step()
	if recording:
		var mine := run.pilot(me)
		if mine and mine.state != Pilot.State.DONE:
			recording.record(mine, run.time)
	view.sync(Run.DT)
	_sync_ghosts(Run.DT)
	camera.follow()
	if backdrop:
		# Behind the title the pilot flies between the logo and the menu.
		camera.position.x -= camera.width * BACKDROP_SHIFT
	Look.update(_env, run, me, Run.DT)
	for e in run.take_events():
		view.on_event(e)
		if hud:
			hud.on_event(e)
		if audio:
			audio.on_event(e)
		_on_event(e)
	if hud:
		hud.sync(Run.DT)
	if audio:
		audio.sync(Run.DT)
	if over and _end_timer > 0.0:
		_end_timer -= Run.DT
		if _end_timer <= 0.0:
			_show_end()


func _networked() -> bool:
	return net != null or bool(config.get("net", false))


func _read_seat(id: int, seat: LGSeat) -> RunInput:
	seat.poll(GameConfig.SEAT_ACTIONS)
	var fly := seat.held("fly")
	var lane := 0
	if seat.just_pressed("lane_back"):
		lane = 1
	elif seat.just_pressed("lane_forward"):
		lane = -1
	var was := bool(_was_fly.get(id, false))
	_was_fly[id] = fly
	return RunInput.make(fly, lane, was)


func _on_event(e: Dictionary) -> void:
	var type := str(e.type)
	match type:
		"run_over", "round_over", "finish":
			if not over:
				over = true
				_end_timer = 0.5 if type != "round_over" else 1.2
				if backdrop:
					_end_timer = 0.0
		"crash":
			_rumble(int(e.pilot), 0.9, 0.6, 0.55)
			if int(e.pilot) == me and not backdrop:
				LGPlaytest.moment("crash", {"kind": str(e.kind), "distance": int(float(e.x)), "zone": run.zone()})
		"stun", "shield", "armour", "vehicle_lost", "reboot":
			_rumble(int(e.pilot), 0.6, 0.4, 0.3)
		"smash", "jump":
			_rumble(int(e.pilot), 0.25, 0.0, 0.12)
		"out":
			_rumble(int(e.pilot), 0.5, 0.5, 0.4)
		"room":
			var r: RoomGen = null
			for room in run.course.rooms:
				if room.index == int(e.room):
					r = room
			if r and r.tags.has("entry") and not backdrop:
				LGPlaytest.event("zone", {"zone": str(r.tags.entry), "x": int(r.x0)})


## Rumble on hits for a pilot steered on this device, when the setting's on.
func _rumble(id: int, weak: float, strong: float, secs: float) -> void:
	if backdrop or not seats.has(id) or not bool(LGSettings.get_value("play", "rumble", true)):
		return
	var seat: LGSeat = seats[id]
	for pad in seat.pads():
		Input.start_joy_vibration(pad, weak, strong, secs)


## What the run came to, for results, missions and boards.
func result() -> Dictionary:
	var p := run.pilot(me)
	return {
		"mode": run.mode, "seed": run.seed, "pace": run.pace, "lanes": run.lanes_on,
		"distance": int(p.x) if p else int(run.distance()), "credits": p.credits if p else 0,
		"best_burn": p.best_burn if p else 1, "time": run.time, "stats": p.stats.duplicate() if p else {},
		"winner": run.winner, "course": str(config.get("course", "")), "pack": p.pack if p else "k1",
		"me": me, "date": str(config.get("date", "")), "place": p.place if p else 0,
	}


## The run's over: bank it, keep the ghost, post the score and show the
## results (or the round's winner).
func _show_end() -> void:
	if backdrop or not is_inside_tree():
		return
	var r := _finish_run()
	finished.emit(r)
	if run.mode == "party":
		_round_over(r)
		return
	_open_results(r)


## Banks the run once: Progress, the ghost, the boards and the play test.
func _finish_run() -> Dictionary:
	var r := result()
	if _recorded:
		return r
	_recorded = true
	if run.mode == "tutorial":
		if run.pilot(me) and run.pilot(me).stats.has("finish_time"):
			LGSettings.set_value("tutorial", "welcomed", true)
	report = Progress.record_run(r)
	var key := Progress.ghost_key(config)
	if key != "" and recording and bool(report.get("new_best", false)):
		recording.distance = float(r.distance)
		Progress.save_ghost(key, recording)
	Boards.submit(r)
	LGPlaytest.moment("run_end", {"mode": run.mode, "distance": r.distance, "credits": r.credits,
		"best_burn": r.best_burn, "time": snappedf(float(r.time), 0.01), "killed_by": str(r.stats.get("killed_by", "")),
		"missions": report.get("missions", []).size(), "rank": int(report.get("rank", 0))})
	return r


func _open_results(r: Dictionary) -> void:
	if results and is_instance_valid(results):
		return
	if pause_menu and is_instance_valid(pause_menu):
		pause_menu.queue_free()
		pause_menu = null
	if hud:
		hud.set_finished(true)
	results = ResultsPanel.new()
	results.scene = self
	_layer.add_child(results)
	results.show_run(r, report)


# --- Party races ------------------------------------------------------------

## A round's done: count the win, then the next round, or the race's result.
func _round_over(r: Dictionary) -> void:
	var wins: Dictionary = config.get("wins", {}).duplicate()
	var w := int(r.get("winner", -1))
	if w >= 0:
		wins[w] = int(wins.get(w, 0)) + 1
	config["wins"] = wins
	var first_to := int(config.get("first_to", 3))
	var champion := -1
	for id in wins:
		if int(wins[id]) >= first_to:
			champion = int(id)
	if hud:
		hud.show_round(w, wins, int(config.get("round", 1)), champion)
	if _networked():
		# The host's Session decides what comes next online and on LAN.
		if Session.has_method("party_round_over"):
			Session.call("party_round_over", self, r)
		return
	if champion >= 0:
		await get_tree().create_timer(2.5).timeout
		if is_inside_tree():
			r["champion"] = champion
			r["wins"] = wins
			_open_results(r)
		return
	await get_tree().create_timer(3.5).timeout
	if is_inside_tree() and over:
		next_round()


## The next round of a party race, with the wins so far.
func next_round() -> void:
	var c := config.duplicate()
	c["seed"] = randi()
	c["round"] = int(c.get("round", 1)) + 1
	c.erase("zone")
	start(c)


# --- Ghosts -----------------------------------------------------------------

func _setup_ghosts() -> void:
	recording = null
	var key := Progress.ghost_key(config)
	if key == "":
		return
	recording = Ghost.new()
	var mine := run.pilot(me)
	if mine:
		recording.name = mine.name
		recording.pack = mine.pack
		recording.look = mine.look
	if not bool(LGSettings.get_value("play", "ghosts", true)):
		return
	var list: Array = []
	var best := Progress.load_ghost(key)
	if best:
		list.append([best, "Your best"])
	for g in config.get("ghosts", []):
		var gh: Ghost = g if g is Ghost else (Ghost.from_dict(g) if g is Dictionary else null)
		if gh and not gh.is_empty():
			list.append([gh, gh.name])
	for e in list.slice(0, 3):
		_add_ghost(e[0], e[1])


func _add_ghost(g: Ghost, tag: String) -> void:
	var p := Pilot.new(-100 - ghosts.size(), tag, g.pack)
	p.look = g.look.duplicate()
	g.pose(p, 0.0)
	var v := PilotView.make(p)
	v.name = "Ghost%d" % ghosts.size()
	if v.has_method("set_ghost"):
		v.call("set_ghost", true)
	else:
		_fade(v)
	view.add_child(v)
	v.sync(run, 0.0)
	v.reset_physics_interpolation()
	ghosts.append({"ghost": g, "pilot": p, "view": v, "tag": tag})
	if hud:
		hud.add_ghost(p, tag, g)


## A stand-in ghost look: see-through, no shadows.
static func _fade(n: Node) -> void:
	for gi in n.find_children("", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.transparency = GHOST_FADE
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in n.find_children("", "Light3D", true, false):
		(l as Light3D).visible = false


func _sync_ghosts(dt: float) -> void:
	for e in ghosts:
		var g: Ghost = e.ghost
		var v: PilotView = e.view
		var shown := g.pose(e.pilot, run.time)
		v.visible = shown
		if shown:
			v.sync(run, dt)
			if not v.has_method("set_ghost"):
				_fade(v)


# --- Menus ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if backdrop:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if results and is_instance_valid(results):
			return
		if pause_menu and is_instance_valid(pause_menu):
			pause_menu.close()
		else:
			open_pause()
	elif event.is_action_pressed("restart") and can_restart():
		get_viewport().set_input_as_handled()
		restart()


func open_pause() -> void:
	if backdrop or (pause_menu and is_instance_valid(pause_menu)):
		return
	paused = true
	if hud:
		hud.set_paused(true)
	pause_menu = PauseMenu.new()
	pause_menu.scene = self
	_layer.add_child(pause_menu)
	LGPlaytest.event("paused_run", {"distance": int(run.distance())})


## Called by the pause menu as it closes.
func on_pause_closed() -> void:
	pause_menu = null
	paused = false
	if hud:
		hud.set_paused(false)
	for id in _was_fly:
		_was_fly[id] = true


## Restarting is instant once you've crashed, from the results, or from the
## pause menu; not mid-flight, where a stray press would end a good run.
func can_restart() -> bool:
	if _networked():
		return false
	if over or paused:
		return true
	var p := run.pilot(me)
	return p != null and p.state != Pilot.State.FLY


## Flies again: the same course for the Daily Flight and courses, a new
## night for endless.
func restart() -> void:
	if run.mode != "party" and not over and run.pilot(me) and run.pilot(me).state != Pilot.State.FLY:
		# Crashed and still sliding: bank what you got first.
		_finish_run()
	var c := config.duplicate()
	if str(c.get("mode", "")) in ["endless", "party"]:
		c["seed"] = randi()
	if str(c.get("mode", "")) == "party":
		c["round"] = 1
		c["wins"] = {}
	# The hangar may have changed since (a new prototype or suit).
	if str(c.get("mode", "")) in ["endless", "tutorial"] and c.has("pilots") and not c.pilots.is_empty():
		var pilots: Array = c.pilots.duplicate(true)
		var first: Dictionary = pilots[0]
		if int(first.get("id", 1)) == 1 and seats.has(1):
			first["look"] = Progress.look()
			if c.mode == "endless":
				first["pack"] = Progress.pack()
				first["gadgets"] = Progress.gadgets()
		c["pilots"] = pilots
	if paused and pause_menu and is_instance_valid(pause_menu):
		pause_menu.queue_free()
	start(c)


## Back to the title (optionally opening one of its pages).
func quit_to_title(page := "") -> void:
	if not _recorded and run and not backdrop and run.mode != "party" and run.time > 3.0:
		_finish_run()
	if Session.has_method("leave") and _networked():
		Session.call("leave")
	TitleScreen.next_page = page
	LGScenes.change_scene(TitleScreen.SCENE)


## Kept for anyone still calling the HUD's old end screen.
func show_result(r: Dictionary) -> void:
	_open_results(r)
