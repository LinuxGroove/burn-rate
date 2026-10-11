class_name RunScene
extends Node3D
## One run on screen: steps the [Run] on the physics tick with this device's
## controls and its bots, and hands what happened to the view, the HUD and
## the sounds. Every mode plays here: endless, the Daily Flight, a Course,
## the first flight and party races (on one screen, or one pilot of an
## online or LAN race, where [RunNet] carries the other pilots).
##
## [member config] is what [Session] launched: the run's own config (see
## [Run]) plus "local" (pilot id -> seat index on this device) and "bots"
## (pilot id -> skill) for the pilots this device steers.

signal finished(result: Dictionary)

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


func _ready() -> void:
	if config.is_empty():
		config = next_config if not next_config.is_empty() else {"mode": "endless", "seed": randi()}
	start(config)


## Starts a run (or restarts with a new config).
func start(p_config: Dictionary) -> void:
	config = p_config
	for c in get_children():
		c.queue_free()
	seats.clear()
	bots.clear()
	_was_fly.clear()
	over = false
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
	hud = RunHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(run, me, camera)
	audio = RunAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(run, me)
	if bool(config.get("net", false)):
		net = RunNet.new()
		net.name = "Net"
		add_child(net)
		net.setup(self)


## 0 on handhelds and the Mobile renderer, 1 otherwise.
static func detail() -> int:
	if int(LGSettings.get_value("video", "detail")) <= 0:
		return 0
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return 0
	return 1


func _physics_process(_delta: float) -> void:
	if run == null or paused:
		return
	var inputs := {}
	for id in seats:
		inputs[id] = _read_seat(id, seats[id])
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
	view.sync(Run.DT)
	camera.follow()
	Look.update(_env, run, me, Run.DT)
	for e in run.take_events():
		view.on_event(e)
		hud.on_event(e)
		audio.on_event(e)
		_on_event(e)
	hud.sync(Run.DT)
	audio.sync(Run.DT)


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
	match str(e.type):
		"run_over", "round_over", "finish":
			if not over:
				over = true
				_end_later()


func _end_later() -> void:
	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree():
		return
	finished.emit(result())
	hud.show_result(result())


## What the run came to, for results, missions and boards.
func result() -> Dictionary:
	var p := run.pilot(me)
	return {
		"mode": run.mode, "seed": run.seed, "pace": run.pace, "lanes": run.lanes_on,
		"distance": int(p.x) if p else int(run.distance()), "credits": p.credits if p else 0,
		"best_burn": p.best_burn if p else 1, "time": run.time, "stats": p.stats.duplicate() if p else {},
		"winner": run.winner, "course": str(config.get("course", "")), "pack": p.pack if p else "k1",
	}


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		paused = not paused
		hud.set_paused(paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and (over or paused):
		paused = false
		var c := config.duplicate()
		if str(c.get("mode", "")) == "endless":
			c["seed"] = randi()
		start(c)
		get_viewport().set_input_as_handled()
