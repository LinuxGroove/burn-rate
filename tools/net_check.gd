extends Node
## Plays a short party race between two copies of the game, over the
## local network with "lan" or online through a real game server (for example
## the LinuxGroove game-server Compose setup on localhost). Run both at once,
## each with its own data folder so they don't share settings or an account:
##   XDG_DATA_HOME=/tmp/a godot --headless --path . tools/net_check.tscn -- host /tmp/code [lan]
##   XDG_DATA_HOME=/tmp/b godot --headless --path . tools/net_check.tscn -- join /tmp/code [lan]
## The host can add "rounds=N" for a race of first to N round wins (default 2,
## so the second round's restart is played too). "server=host:port" plays
## online through that server over plain http (a local Compose setup is
## "server=127.0.0.1:7350"); online, the host then checks the server recorded
## the race for both players.
## The guest flies for a moment and the host checks its pilot climbed; both
## see the round end with the same winner, with no desyncs on the guest, and
## both end up back in the lobby. Each prints "NET OK" and exits 0 when its
## side worked.

const TIMEOUT := 40.0
## A round of two idle pilots lasts until one falls out.
const ROUND_TIMEOUT := 150.0

var _role := ""
var _code_file := ""
var _lan := false
var _rounds := 2
var _rounds_seen := {}
var _winner := -1
var _desyncs := 0
var _aim_desyncs := 0
var _snapshots := 0
## RunNet (one a round) -> [desyncs, aim desyncs, snapshots].
var _counts := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "host"
	_code_file = args[1] if args.size() > 1 else "/tmp/burn-rate-net-code"
	_lan = "lan" in args
	for a in args:
		if a.begins_with("rounds="):
			_rounds = maxi(1, int(a.trim_prefix("rounds=")))
		elif a.begins_with("server="):
			var at := a.trim_prefix("server=").split(":")
			LGSettings.set_value("online", "host", at[0], false)
			LGSettings.set_value("online", "port", int(at[1]) if at.size() > 1 else 7350, false)
			LGSettings.set_value("online", "scheme", "http", false)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	# Two copies on one machine would share a device id, and so an account.
	Nakama._device_id = _random_device_id()
	LGSettings.set_value("online", "enabled", true, false)
	LGSettings.set_value("player", "name", "Host" if _role == "host" else "Guest", false)
	Session.local_seats[0].name = Session.player_name()
	Session.status.connect(_on_status)
	Session.party_changed.connect(_on_party_changed)
	# Scene changes would free this node if it stayed the current scene.
	get_tree().current_scene = null
	var ok: bool
	if _role == "host":
		ok = await _host()
	else:
		ok = await _join()
	print("NET %s %s" % ["OK" if ok else "FAILED", _role])
	Session.leave()
	get_tree().quit(0 if ok else 1)


func _host() -> bool:
	if not (Session.host_lan() if _lan else await Session.host_online()):
		return _fail("could not host: %s" % LGOnline.last_error)
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	f.store_string(Session.join_code)
	f.close()
	print("room code ", Session.join_code)
	if not await _until(_two_players):
		return _fail("the guest never arrived")
	Session.set_setting("rounds", _rounds)
	Session.set_setting("bots", 0)
	if not await _until(Session.can_start):
		return _fail("never ready to start: %s" % Session.start_blocker())
	Session.start_match()
	if not await _until(_flying):
		return _fail("the round never started")
	var guest_id := -1
	for p in _scene().run.pilots:
		if p.id != Session.actor_id(1, 0):
			guest_id = p.id
	if guest_id < 0:
		return _fail("no guest pilot in the race")
	var guest_user := "" if _lan else LGOnline.user_id_for_peer(int(_scene().run.pilot(guest_id).id / Session.SEATS_PER_PEER))
	# The guest lets go at first, then flies: its pilot must climb here.
	var lowest := 99.0
	var t := 0.0
	var climbed := false
	while t < TIMEOUT and _scene() != null:
		var y: float = _scene().run.pilot(guest_id).y
		lowest = minf(lowest, y)
		if y > lowest + 1.5:
			climbed = true
			print("the guest's pilot climbed from %.1f m to %.1f m on the host" % [lowest, y])
			break
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	if not climbed:
		return _fail("the guest's controls never reached the host (lowest %.1f m)" % lowest)
	if not await _round_and_lobby():
		return false
	if _lan:
		return true
	await get_tree().create_timer(2.0).timeout
	for user in [LGOnline.session.user_id, guest_user]:
		var ids := [NakamaStorageObjectId.new("%s.stats" % GameConfig.GAME_ID, "stats", user)]
		var res = await LGOnline.client.read_storage_objects_async(LGOnline.session, ids)
		if res.is_exception() or res.objects.is_empty():
			return _fail("no stats on the server for %s after the race" % user)
		var stats: Dictionary = JSON.parse_string(res.objects[0].value)
		print("server stats for the %s: %s" % ["host" if user == LGOnline.session.user_id else "guest", stats])
		if int(stats.get("races", 0)) < 1:
			return _fail("the race report wasn't recorded")
	return true


func _join() -> bool:
	if not _lan:
		if await Session.join_online("QQQQQQ"):
			return _fail("joined a room nobody opened")
		print("an unused code was refused")
		LGOnline.disconnect_online()
	if not await _until(_have_code):
		return _fail("no room code from the host")
	var code := FileAccess.get_file_as_string(_code_file).strip_edges()
	# On the network, join the host's address the way picking a found host
	# does (a join code can name an interface this machine can't reach).
	var lan_port := int(LGSettings.get_value("lan", "port"))
	var joined: bool = Session.join_lan("127.0.0.1", lan_port) if _lan else await Session.join_online(code)
	if not joined:
		return _fail("could not join %s" % code)
	if not await _until(_in_room):
		return _fail("the host never let us in")
	Session.set_ready(true)
	if not await _until(_flying):
		return _fail("the round never started here")
	await get_tree().create_timer(1.5).timeout
	_key(KEY_SPACE, true)
	await get_tree().create_timer(1.5).timeout
	_key(KEY_SPACE, false)
	var me: Pilot = _scene().run.pilot(_scene().me)
	print("the guest's pilot is at %.1f m here" % me.y)
	if not await _round_and_lobby():
		return false
	if _desyncs > 0 or _aim_desyncs > 0:
		return _fail("the guest's course drifted from the host's (%d, aims %d)" % [_desyncs, _aim_desyncs])
	print("%d snapshots, no desyncs" % _snapshots)
	# When the host goes, this copy must leave the room, not wait forever.
	if not await _until(_alone):
		return _fail("still in the room after the host left")
	print("left the room when the host did")
	return true


## Both sides: the round ends with a winner and everyone goes back to the
## lobby after the scoreboard.
func _round_and_lobby() -> bool:
	var t := 0.0
	while t < ROUND_TIMEOUT * (2 * _rounds - 1) and _winner == -1:
		var s := _scene()
		if s != null and s.net != null:
			_counts[s.net.get_instance_id()] = [s.net.desyncs, s.net.aim_desyncs, s.net.snapshots]
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	for c in _counts.values():
		_desyncs += int(c[0])
		_aim_desyncs += int(c[1])
		_snapshots += int(c[2])
	if _winner == -1:
		return _fail("the race never ended")
	print("%s won the race after %d rounds" % [_pilot_name(_winner), _rounds_seen.size()])
	if not await _until(_back_in_lobby):
		return _fail("never went back to the lobby")
	print("back in the lobby")
	if _role == "host":
		# Give the guest a moment to see the lobby before the room closes.
		await get_tree().create_timer(2.0).timeout
	return true


func _on_party_changed() -> void:
	if int(Session.party.get("round_winner", -1)) != -1:
		var r := int(Session.party.get("round", 0))
		if not _rounds_seen.has(r):
			_rounds_seen[r] = true
			print("round %d to %s" % [r, _pilot_name(int(Session.party.round_winner))])
	if int(Session.party.get("winner", -1)) != -1:
		_winner = int(Session.party.winner)


func _on_status(text: String) -> void:
	print("  (%s) %s" % [_role, text])


func _pilot_name(id: int) -> String:
	return str(Session.players.get(id, {}).get("name", "pilot %d" % id))


func _two_players() -> bool:
	return Session.players.size() >= 2


func _have_code() -> bool:
	return FileAccess.file_exists(_code_file) and FileAccess.get_file_as_string(_code_file) != ""


func _in_room() -> bool:
	return Session.players.size() >= 2 and Session.mode != Session.Mode.NONE


func _flying() -> bool:
	var s := _scene()
	return s != null and s.net != null and s.net.phase == RunNet.Phase.FLY


func _back_in_lobby() -> bool:
	var s := get_tree().current_scene
	return not Session.in_match and s != null and s.scene_file_path == Session.LOBBY_SCENE


func _alone() -> bool:
	return Session.mode == Session.Mode.NONE


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _scene() -> RunScene:
	return get_tree().current_scene as RunScene


func _until(cond: Callable) -> bool:
	var t := 0.0
	while not cond.call():
		if t > TIMEOUT:
			return false
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	return true


func _fail(why: String) -> bool:
	printerr("net check (%s): %s" % [_role, why])
	return false


static func _random_device_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
