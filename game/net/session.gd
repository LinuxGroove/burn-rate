extends Node
## The lobby and transport for every mode (autoload: Session), and the way
## into every run.
##
## Solo runs (endless, the Daily Flight, Courses, the first flight) launch
## straight away with [method launch]. Party races (Last One Flying) go
## through the lobby, and every party race runs the same host-authoritative
## code whatever carries it:
##   SOLO     this device hosts: couch seats on one screen, bots to fill
##   LAN      ENet on the local network, found by LanBeacon or a join code
##   ONLINE   Nakama relay through the shared game server, joined by room
##            code or quick match
## Peer 1 is always the host. Bots exist only on the host, with negative ids.
##
## Each device can bring up to four pilots (couch seats): seat 0 has the
## keyboard, mouse and any free controller, the others a controller each. A
## pilot's id is peer * 4 + seat, so it's the same on every device.
##
## A party race is rounds of Last One Flying until someone has won
## `settings.rounds` of them. [RunNet] runs each round; the host keeps the
## score here (see [member party]) and starts the next round or goes back to
## the lobby.

signal roster_changed
signal settings_changed
signal seats_changed
signal hosts_found(hosts: Array)
signal joined
signal left(reason: String)
signal status(text: String)
## A round of the party race ended, or a new one started (see `party`).
signal party_changed
## Host: a device left during a race (its pilots drop out).
signal peer_left(peer: int)

enum Mode { NONE, SOLO, LAN_HOST, LAN_CLIENT, ONLINE_HOST, ONLINE_CLIENT }

const HELLO_TIMEOUT := 6.0
## Quick match looks this long for other players before racing bots.
const QUICK_SEARCH_SECONDS := 60.0
## Then the first race starts by itself after this long in the lobby.
const QUICK_COUNTDOWN := 15.0
const SEATS_PER_PEER := 4
## Bots' ids count down from here (Run uses -1 for "nobody").
const BOT_ID := -10
## Seconds the scoreboard shows between rounds, and after the last one.
const ROUND_BREAK := 5.0
const FINAL_BREAK := 8.0
const RUN_SCENE := "res://game/play/run_scene.tscn"
const TITLE_SCENE := "res://game/ui/title.tscn"
const LOBBY_SCENE := "res://game/ui/lobby.tscn"

## The lobby's race settings (the host's choice).
const DEFAULT_SETTINGS := {
	"pace": "normal",
	"lanes": true,
	## A zone id from Zones.ORDER, or "random".
	"zone": "random",
	## Round wins that take the race.
	"rounds": 3,
	## Bots in a race (quick match picks its own number).
	"bots": 2,
	## novice, average, expert, or "mixed".
	"bot_skill": "mixed",
}
const ZONES := ["lab", "servers", "bay", "atrium", "downtown", "halberd"]
const BOT_SKILLS := ["novice", "average", "expert"]

## Flight suits: id -> [name, main colour, trim colour].
const SUITS := {
	"kestrel": ["Kestrel orange", Color(0.95, 0.45, 0.12), Color(0.95, 0.93, 0.88)],
	"night": ["Night shift", Color(0.12, 0.14, 0.22), Color(0.3, 0.85, 1.0)],
	"lab": ["Lab white", Color(0.9, 0.92, 0.95), Color(0.2, 0.55, 0.95)],
	"server": ["Server green", Color(0.1, 0.45, 0.3), Color(0.55, 1.0, 0.5)],
	"rooftop": ["Rooftop red", Color(0.75, 0.12, 0.15), Color(1.0, 0.8, 0.25)],
	"violet": ["Pitch violet", Color(0.42, 0.2, 0.75), Color(1.0, 0.55, 0.85)],
	"gold": ["Board gold", Color(0.85, 0.65, 0.15), Color(0.15, 0.12, 0.1)],
	"halberd": ["Borrowed Halberd grey", Color(0.38, 0.4, 0.43), Color(0.95, 0.25, 0.2)],
}
const SUIT_ORDER := ["kestrel", "night", "lab", "server", "rooftop", "violet", "gold", "halberd"]

## The game server's boards, for the Leaderboards screen: [board, label].
## Distances are metres, course times milliseconds (lowest first).
const BOARDS := [
	["daily", "Daily Flight (today)"],
	["distance_normal", "Distance, Normal"],
	["distance_fast", "Distance, Fast"],
	["distance_calm", "Distance, Calm"],
	["distance_classic_normal", "Classic, Normal"],
	["distance_classic_fast", "Classic, Fast"],
	["distance_classic_calm", "Classic, Calm"],
	["wins", "Party races won"],
]

var mode := Mode.NONE
## Actor id -> {"name", "pack", "suit", "body", "peer", "seat", "bot": false}
var players := {}
var settings := DEFAULT_SETTINGS.duplicate()
var join_code := ""
var lan_address := ""
var in_match := false
## The party race in progress: {"round", "target", "wins": {id: n},
## "pilots": [...], "winner": -1 until the race is won, "next_msec"}.
var party := {}
## Host: peers whose run scene is ready for this round.
var loaded_peers := {}
## Online rooms: party races reported, so a retry can't count twice.
var races_reported := 0
## This lobby came from quick match: a countdown starts the first race so
## nobody waits on a stranger.
var quick := false
var _quick_start_msec := 0
var _quick_target := 0
## This device's pilots: [{"pad", "name", "pack", "suit", "body"}]. Seat 0
## is the keyboard player (pad LGSeat.ANY_FREE_PAD).
var local_seats: Array = []

var _beacon: LanBeacon
var _pending_hello := {}
var _seat_inputs := {}
var _break_timer: SceneTreeTimer
var _last_report := ""
## Host: devices whose pilots said they're ready.
var _ready_peers := {}


func _ready() -> void:
	_beacon = LanBeacon.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	_beacon.hosts_changed.connect(_on_beacon_hosts)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	_load_lobby_settings()
	_reset_seats()


func is_host() -> bool:
	return mode in [Mode.SOLO, Mode.LAN_HOST, Mode.ONLINE_HOST, Mode.NONE]


func is_online() -> bool:
	return mode in [Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]


## A race other devices take part in.
func is_networked() -> bool:
	return mode in [Mode.LAN_HOST, Mode.LAN_CLIENT, Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]


func local_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func player_name() -> String:
	var n := str(LGSettings.get_value("player", "name")).strip_edges()
	return n if n != "" else "Pilot"


static func actor_id(peer: int, seat: int) -> int:
	return peer * SEATS_PER_PEER + seat


## A pilot's look for the views (see Person): body and suit colours.
static func look_for(suit: String, body: int, seed := 0) -> Dictionary:
	var s: Array = SUITS.get(suit, SUITS["kestrel"])
	return {"female": body == 1, "main": s[1], "accent": s[2], "seed": seed}


# --- Couch seats ----------------------------------------------------------

## The controls for this device's seat `index`.
func seat_input(index: int) -> LGSeat:
	if not _seat_inputs.has(index):
		if index == 0 or index >= local_seats.size():
			_seat_inputs[index] = LGSeat.primary()
		else:
			_seat_inputs[index] = LGSeat.for_pad(index, int(local_seats[index].pad))
		_seat_inputs[index].deadzone = float(LGSettings.get_value("input", "stick_deadzone"))
	return _seat_inputs[index]


## Adds a pilot on controller `pad`. Returns the new seat index, or -1.
func add_local_seat(pad: int) -> int:
	if local_seats.size() >= GameConfig.MAX_LOCAL or in_match:
		return -1
	for s in local_seats:
		if int(s.pad) == pad:
			return -1
	var index := local_seats.size()
	local_seats.append({
		"pad": pad, "name": "Pilot %d" % (index + 1),
		"pack": Packs.ORDER[index % Packs.ORDER.size()],
		"suit": SUIT_ORDER[(index * 3 + 1) % SUIT_ORDER.size()],
		"body": index % 2,
	})
	LGInput.claim_pad(pad, index)
	_seats_updated()
	return index


func remove_local_seat(index: int) -> void:
	if index <= 0 or index >= local_seats.size() or in_match:
		return
	LGInput.release_pad(int(local_seats[index].pad))
	local_seats.remove_at(index)
	_seats_updated()


## Changes a seat's "pack", "suit", "body" or "name". Seat 0's look is the
## player's own and is remembered in the settings.
func set_seat_value(index: int, key: String, value: Variant) -> void:
	if index < 0 or index >= local_seats.size():
		return
	local_seats[index][key] = value
	if index == 0 and key in ["suit", "body"]:
		LGSettings.set_value("player", key, value)
	if index == 0 and key == "pack":
		LGSettings.set_value("player", "party_pack", value)
	_seats_updated()


func seat_for_pad(pad: int) -> int:
	for i in range(1, local_seats.size()):
		if int(local_seats[i].pad) == pad:
			return i
	return -1


func _reset_seats() -> void:
	for i in range(1, local_seats.size()):
		LGInput.release_pad(int(local_seats[i].pad))
	var pack := str(LGSettings.get_value("player", "party_pack", "k1"))
	local_seats = [{
		"pad": LGSeat.ANY_FREE_PAD, "name": player_name(),
		"pack": pack if Packs.SPECS.has(pack) else "k1",
		"suit": str(LGSettings.get_value("player", "suit", "kestrel")),
		"body": int(LGSettings.get_value("player", "body", 0)),
	}]
	_seat_inputs.clear()


func _seats_updated() -> void:
	_seat_inputs.clear()
	local_seats[0].name = player_name()
	if is_host() and mode != Mode.NONE:
		_apply_seats(1, seat_payload())
	elif mode != Mode.NONE:
		_c_seats.rpc_id(1, seat_payload())
	seats_changed.emit()


## This device's seats as sent in the hello: [[name, pack, suit, body], ...].
func seat_payload() -> Array:
	var out := []
	for s in local_seats:
		out.append([str(s.name), str(s.pack), str(s.suit), int(s.body)])
	return out


## Host: replaces a peer's players with the seats it sent.
func _apply_seats(peer: int, seats: Array) -> void:
	for id in players.keys():
		if int(players[id].peer) == peer:
			players.erase(id)
	for i in mini(seats.size(), GameConfig.MAX_LOCAL):
		if players.size() >= GameConfig.MAX_PLAYERS:
			break
		var s: Array = seats[i] if seats[i] is Array else []
		if s.size() < 4:
			continue
		var pack := str(s[1])
		var suit := str(s[2])
		players[actor_id(peer, i)] = {
			"name": _unique_name(str(s[0]).strip_edges().left(16)),
			"pack": pack if Packs.SPECS.has(pack) else "k1",
			"suit": suit if SUITS.has(suit) else "kestrel",
			"body": clampi(int(s[3]), 0, 1),
			"peer": peer, "seat": i, "bot": false, "ready": peer == 1 or _ready_peers.has(peer),
		}
	_broadcast_roster()


# --- Solo runs ------------------------------------------------------------

## Starts a session on this device alone (solo runs and couch party races).
func start_solo() -> void:
	leave()
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_apply_seats(1, seat_payload())
	joined.emit()
	roster_changed.emit()


## Starts a run on this device with `config` (see RunScene and Run): an
## endless run, the Daily Flight, a Course or the first flight. A party
## config without "net" (the --solo shortcut) becomes a couch party race.
func launch(config: Dictionary) -> void:
	if mode != Mode.SOLO:
		start_solo()
	var c := config.duplicate(true)
	if str(c.get("mode", "")) == "party" and not c.has("net"):
		var bots: Dictionary = c.get("bots", {})
		for d in c.get("pilots", []):
			if bots.has(int(d.id)):
				d["bot"] = true
				d["skill"] = str(bots[int(d.id)])
		_begin_party(c.get("pilots", []))
		c["net"] = true
		c["round"] = 1
		c["target"] = int(party.target)
	in_match = str(c.get("mode", "")) == "party"
	LGInput.filter_claimed_pads = false
	RunScene.next_config = c
	LGScenes.change_scene(RUN_SCENE, _setup_run.bind(c))


func _setup_run(node: Node, config: Dictionary) -> void:
	node.set("config", config)
	if node.has_signal("finished") and not node.is_connected("finished", _on_run_finished):
		node.connect("finished", _on_run_finished)


func _on_run_finished(result: Dictionary) -> void:
	if str(result.get("mode", "")) != "party":
		report_run(result)


## Sends a solo run to the game server for the player's record and the
## boards (fire and forget): endless and Daily Flight distances, course
## times. Only when online play is on and there's a network; bots' runs and
## the first flight don't count. RunScene's `finished` calls it by itself.
func report_run(result: Dictionary) -> void:
	var m := str(result.get("mode", ""))
	if not m in ["endless", "daily", "course"] or bool(result.get("bot", false)):
		return
	if not LGOnline.is_enabled() or not LGNetwork.is_up():
		return
	var payload := run_report_payload(result)
	if payload.is_empty():
		return
	var key := JSON.stringify([payload.mode, payload.seed, payload.distance, payload.time_ms])
	if key == _last_report:
		return
	_last_report = key
	_report_run_async(payload)


## What report_run sends to burn-rate.run_report, or {} when there's nothing
## to send.
static func run_report_payload(result: Dictionary) -> Dictionary:
	var distance := int(result.get("distance", 0))
	var time_ms := int(roundf(float(result.get("time", 0.0)) * 1000.0))
	if distance < 1 or time_ms < 1000:
		return {}
	var payload := {
		"mode": str(result.get("mode", "endless")),
		"pace": str(result.get("pace", "normal")),
		"lanes": bool(result.get("lanes", true)),
		# JSON numbers only hold 53 bits; the server only uses the seed to spot repeats.
		"seed": int(result.get("seed", 0)) & 0xFFFFFFFF,
		"distance": distance,
		"credits": maxi(0, int(result.get("credits", 0))),
		"best_burn": clampi(int(result.get("best_burn", 1)), 1, 5),
		"time_ms": time_ms,
		"pack": str(result.get("pack", "k1")),
	}
	if payload.mode == "course":
		payload["course"] = str(result.get("course", ""))
		var stats: Dictionary = result.get("stats", {})
		if stats.has("finish_time"):
			payload["finish_ms"] = int(roundf(float(stats.finish_time) * 1000.0))
	return payload


func _report_run_async(payload: Dictionary) -> void:
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		return
	await LGOnline.rpc_async("%s.run_report" % GameConfig.GAME_ID, payload)


## The player's online record for the Leaderboards screen, from the stats
## the server keeps.
static func record_text(stats: Dictionary) -> String:
	var runs := int(stats.get("runs", 0))
	var races := int(stats.get("races", 0))
	if runs == 0 and races == 0:
		return "No online runs yet. Fly one with online play on to start your record."
	var lines := []
	if runs > 0:
		lines.append("Your record: %s, %s flown, best %s, %s credits." % [
			_count(runs, "run"), GameConfig.meters(float(stats.get("metres", 0))),
			GameConfig.meters(float(stats.get("best_distance", 0))), GameConfig.grouped(int(stats.get("credits", 0))),
		])
	if races > 0:
		lines.append("Party races: %s, %s won, %s won." % [
			_count(races, "race"), _count(int(stats.get("race_wins", 0)), "race"),
			_count(int(stats.get("round_wins", 0)), "round"),
		])
	return "\n".join(lines)


static func _count(n: int, word: String) -> String:
	return "%s %s%s" % [GameConfig.grouped(n), word, "" if n == 1 else "s"]


# --- Network play ---------------------------------------------------------

## Opens the lobby for a party race on this screen (couch seats and bots).
func open_party() -> void:
	start_solo()
	open_lobby()


func open_lobby() -> void:
	LGScenes.change_scene(LOBBY_SCENE)


func host_lan() -> bool:
	leave()
	var port := int(LGSettings.get_value("lan", "port"))
	var peer := LanNet.create_host(port, GameConfig.MAX_PLAYERS - 1)
	if peer == null:
		status.emit("Couldn't host on port %d. Is another game already hosting?" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_HOST
	lan_address = LanNet.local_address()
	join_code = JoinCode.encode(lan_address, port, port) if lan_address != "" else ""
	_apply_seats(1, seat_payload())
	_beacon.start_advertising(_beacon_info(), int(LGSettings.get_value("lan", "beacon_port")))
	joined.emit()
	roster_changed.emit()
	return true


func browse_lan() -> void:
	_beacon.start_listening(int(LGSettings.get_value("lan", "beacon_port")))


func stop_browsing() -> void:
	if mode == Mode.NONE:
		_beacon.stop()


func join_lan(address: String, port: int) -> bool:
	leave()
	var peer := LanNet.create_client(address, port)
	if peer == null:
		status.emit("Couldn't reach %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_CLIENT
	status.emit("Connecting to %s..." % address)
	return true


func join_lan_code(code: String) -> bool:
	var port := int(LGSettings.get_value("lan", "port"))
	var target := JoinCode.decode(code, port)
	if target.is_empty():
		status.emit("That code doesn't look right.")
		return false
	return join_lan(target.ip, target.port)


func host_online() -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	var code: String = await LGOnline.host_room_async(GameConfig.GAME_ID)
	if code == "":
		status.emit(LGOnline.last_error)
		return false
	# LGOnline already put the bridge's peer on the scene's multiplayer.
	mode = Mode.ONLINE_HOST
	join_code = code
	_apply_seats(1, seat_payload())
	joined.emit()
	roster_changed.emit()
	return true


func join_online(code: String) -> bool:
	if not LGOnline.is_valid_code(code):
		status.emit("Type the room code shown on the host's screen.")
		return false
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	if not await LGOnline.join_room_async(GameConfig.GAME_ID, code):
		var shown := LGOnline.normalize_code(code)
		if LGOnline.last_error == LGOnline.NO_ROOM:
			status.emit("No room with code %s. Check the code with the host." % shown)
		elif LGOnline.last_error.begins_with("room_full"):
			status.emit("Room %s is full." % shown)
		else:
			status.emit("Couldn't join room %s." % shown)
		return false
	# No await between the join and setting the mode: the host may answer at
	# once. connected_to_server has already sent the hello.
	mode = Mode.ONLINE_CLIENT
	join_code = LGOnline.normalize_code(code)
	return true


## Quick match: finds other pilots looking for a race, or races bots if
## nobody turns up in time. Returns "lobby" (go there now), "joining" (wait
## for `joined` or `left`) or "" when it was cancelled or failed.
func quick_match() -> String:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return ""
	quick = true
	status.emit("Looking for pilots...")
	var role: String = await LGOnline.find_match_async(2, GameConfig.MAX_PLAYERS, QUICK_SEARCH_SECONDS)
	match role:
		"host":
			mode = Mode.ONLINE_HOST
			join_code = ""
			_apply_seats(1, seat_payload())
			_begin_quick_countdown()
			joined.emit()
			roster_changed.emit()
			return "lobby"
		"guest":
			mode = Mode.ONLINE_CLIENT
			join_code = ""
			return "joining"
	quick = false
	if LGOnline.last_error == LGOnline.NO_MATCH:
		start_quick_solo()
		status.emit("Nobody else is looking right now, so it's you against bots.")
		return "lobby"
	if LGOnline.last_error != LGOnline.CANCELLED:
		status.emit("Couldn't find a race: %s" % LGOnline.last_error)
	return ""


func cancel_quick_match() -> void:
	LGOnline.cancel_matchmaking()


## Quick match with nobody else around: this device against bots.
func start_quick_solo() -> void:
	start_solo()
	quick = true
	_begin_quick_countdown()


func quick_seconds_left() -> float:
	if _quick_start_msec == 0:
		return 0.0
	return maxf(0.0, (_quick_start_msec - Time.get_ticks_msec()) / 1000.0)


func _begin_quick_countdown() -> void:
	_quick_target = randi_range(GameConfig.QUICK_MATCH_SIZE.x, GameConfig.QUICK_MATCH_SIZE.y)
	settings.zone = "random"
	settings.bot_skill = "mixed"
	_quick_start_msec = Time.get_ticks_msec() + int(QUICK_COUNTDOWN * 1000.0)


func _process(_delta: float) -> void:
	if _quick_start_msec != 0 and is_host() and not in_match and quick_seconds_left() <= 0.0:
		_quick_start_msec = 0
		if LGScenes.is_busy():
			_quick_start_msec = Time.get_ticks_msec()
			return
		start_match()


func leave(reason := "") -> void:
	var was := mode
	get_tree().paused = false
	_beacon.stop()
	if is_online() or LGOnline.bridge:
		LGOnline.leave_room()
	elif multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players.clear()
	join_code = ""
	in_match = false
	party = {}
	loaded_peers.clear()
	races_reported = 0
	quick = false
	_quick_start_msec = 0
	_quick_target = 0
	_pending_hello.clear()
	_ready_peers.clear()
	_break_timer = null
	if was != Mode.NONE:
		left.emit(reason)


# --- Host: the lobby ------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	if not is_host() or not DEFAULT_SETTINGS.has(key):
		return
	settings[key] = value
	_save_lobby_settings()
	_broadcast_roster()


## How many bots the next race gets.
func bot_count() -> int:
	if quick:
		return maxi(0, _quick_target - players.size())
	return clampi(int(settings.get("bots", 0)), 0, GameConfig.MAX_PLAYERS - players.size())


func can_start() -> bool:
	return is_host() and start_blocker() == "" and not in_match


func start_blocker() -> String:
	if players.is_empty():
		return "Waiting for pilots."
	if players.size() + bot_count() < 2:
		return "Last One Flying needs two pilots: add a bot or a friend."
	if not quick:
		for id in players:
			if not bool(players[id].get("ready", true)):
				return "Waiting for %s to be ready." % players[id].name
	return ""


## A guest's pilots are ready (or not) to start.
func set_ready(on: bool) -> void:
	if is_host() or mode == Mode.NONE:
		return
	_c_ready.rpc_id(1, on)


## Whether this device's pilots are marked ready.
func is_ready() -> bool:
	for id in players:
		if int(players[id].peer) == local_id():
			return bool(players[id].get("ready", false))
	return false


## Host: starts a party race: round one for everyone.
func start_match() -> void:
	if not can_start():
		return
	var people := []
	for id in players:
		var p: Dictionary = players[id]
		people.append({
			"id": int(id), "name": p.name, "pack": p.pack, "look": look_for(p.suit, int(p.body), int(id) * 7919),
			"peer": int(p.peer), "seat": int(p.seat), "bot": false,
		})
	people.sort_custom(_by_id)
	people.append_array(make_bots(bot_count(), people, str(settings.get("bot_skill", "mixed"))))
	_begin_party(people)
	_beacon.update_info({"state": "racing"})
	_send_round()


## Bots for a race: names from LGNameMaker, marked as bots, ids from BOT_ID down.
static func make_bots(n: int, people: Array, skill: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var used := []
	for p in people:
		used.append(str(p.name))
	var out := []
	for i in n:
		var bot_name := LGNameMaker.make(used, rng)
		used.append(bot_name)
		var sk: String = skill if skill in BOT_SKILLS else BOT_SKILLS[(i + 1) % BOT_SKILLS.size()]
		out.append({
			"id": BOT_ID - i, "name": bot_name, "pack": Packs.ORDER[rng.randi() % Packs.ORDER.size()],
			"look": look_for(SUIT_ORDER[rng.randi() % SUIT_ORDER.size()], rng.randi() % 2, rng.randi() % 100000),
			"peer": 1, "seat": -1, "bot": true, "skill": sk,
		})
	return out


static func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return int(a.id) < int(b.id)


func _begin_party(pilots: Array) -> void:
	party = {
		"round": 0,
		"target": clampi(int(settings.get("rounds", 3)), 1, 9),
		"wins": {},
		"pilots": pilots.duplicate(true),
		"winner": -1,
		"round_winner": -1,
		"next_msec": 0,
	}
	for p in party.pilots:
		party.wins[int(p.id)] = 0
	in_match = true
	loaded_peers.clear()


## A round's config for every device (before each device adds its own seats
## and bots, see `localize`).
func round_config(seed := 0) -> Dictionary:
	if seed == 0:
		seed = randi() % 1000000 + 1
	var zone := str(settings.get("zone", "random"))
	if not zone in ZONES:
		zone = ZONES[seed % 4]
	return {
		"mode": "party", "seed": seed, "pace": str(settings.get("pace", "normal")),
		"lanes": bool(settings.get("lanes", true)), "zone": zone,
		"pilots": party.get("pilots", []).duplicate(true),
		"net": true, "round": int(party.get("round", 1)), "target": int(party.get("target", 3)),
	}


## This device's version of a round's config: "local" (its own pilots and
## their seats), "bots" (the host's), and "me" (the pilot the screen follows).
func localize(config: Dictionary, peer := -1) -> Dictionary:
	if peer < 0:
		peer = local_id()
	var c := config.duplicate(true)
	var local := {}
	var bots := {}
	for p in c.get("pilots", []):
		if bool(p.get("bot", false)):
			if peer == 1:
				bots[int(p.id)] = str(p.get("skill", "average"))
		elif int(p.get("peer", 1)) == peer:
			local[int(p.id)] = int(p.get("seat", 0))
	c["local"] = local
	c["bots"] = bots
	var me := -1
	for id in local:
		if me == -1 or int(local[id]) < int(local.get(me, 99)):
			me = int(id)
	if me == -1 and not c.get("pilots", []).is_empty():
		me = int(c.pilots[0].id)
	c["me"] = me
	return c


## Host: the next round, for everyone.
func _send_round() -> void:
	party.round = int(party.get("round", 0)) + 1
	party.round_winner = -1
	party.next_msec = 0
	# A device that left takes its pilots with it.
	var keep := []
	for p in party.pilots:
		if bool(p.get("bot", false)) or int(p.peer) == 1 or int(p.peer) in multiplayer.get_peers():
			keep.append(p)
	party.pilots = keep
	var config := round_config()
	loaded_peers.clear()
	for peer_id in multiplayer.get_peers():
		if not _pending_hello.has(peer_id):
			_h_round.rpc_id(peer_id, config, _party_summary())
	_h_round(config, _party_summary())


## Host: RunNet calls this when a round ends with `winner` (a pilot id).
func round_over(winner: int) -> void:
	if not is_host() or party.is_empty():
		return
	party.round_winner = winner
	if party.wins.has(winner):
		party.wins[winner] = int(party.wins[winner]) + 1
	var best := -1
	for id in party.wins:
		if int(party.wins[id]) >= int(party.target) and (best == -1 or int(party.wins[id]) > int(party.wins.get(best, 0))):
			best = int(id)
	party.winner = best
	var wait := FINAL_BREAK if best != -1 else ROUND_BREAK
	party.next_msec = Time.get_ticks_msec() + int(wait * 1000.0)
	for peer_id in multiplayer.get_peers():
		if not _pending_hello.has(peer_id):
			_h_party.rpc_id(peer_id, _party_summary(), wait)
	party_changed.emit()
	if best != -1:
		report_party()
	_break_timer = get_tree().create_timer(wait)
	_break_timer.timeout.connect(_after_break.bind(_break_timer))


func _after_break(timer: SceneTreeTimer) -> void:
	if timer != _break_timer or party.is_empty() or not is_host():
		return
	_break_timer = null
	if int(party.winner) != -1:
		return_to_lobby()
	else:
		_send_round()


## Seconds until the next round (or the lobby), for the scoreboard.
func break_seconds_left() -> float:
	var at := int(party.get("next_msec", 0))
	return maxf(0.0, (at - Time.get_ticks_msec()) / 1000.0) if at > 0 else 0.0


func _party_summary() -> Dictionary:
	return {
		"round": int(party.get("round", 0)), "target": int(party.get("target", 3)),
		"wins": party.get("wins", {}).duplicate(), "winner": int(party.get("winner", -1)),
		"round_winner": int(party.get("round_winner", -1)),
	}


## Host: everyone goes back to the lobby.
func return_to_lobby() -> void:
	if not is_host():
		return
	get_tree().paused = false
	_beacon.update_info({"state": "lobby"})
	for peer_id in multiplayer.get_peers():
		_h_return_to_lobby.rpc_id(peer_id)
	_h_return_to_lobby()


## Leaves a race for the menus (the pause menu's Leave): the host takes
## everyone back to the lobby, a guest leaves the room, and a solo run goes
## back to the title screen.
func quit_race() -> void:
	if is_networked():
		if is_host():
			return_to_lobby()
		else:
			leave("You left the race.")
			LGScenes.change_scene(TITLE_SCENE)
		return
	if in_match and not party.is_empty():
		return_to_lobby()
		return
	in_match = false
	leave()
	LGScenes.change_scene(TITLE_SCENE)


## Host of an online room: reports a finished party race to the game server
## for stats and the wins board. Each device's first seat is its signed-in
## account; bots and couch guests aren't reported.
func report_party() -> void:
	if mode != Mode.ONLINE_HOST or LGOnline.bridge == null or party.is_empty():
		return
	var reported := []
	for p in party.pilots:
		if bool(p.get("bot", false)) or int(p.get("seat", 0)) != 0:
			continue
		var uid := LGOnline.user_id_for_peer(int(p.peer))
		if uid == "":
			continue
		reported.append({
			"user_id": uid,
			"rounds": int(party.round),
			"round_wins": int(party.wins.get(int(p.id), 0)),
			"won": int(p.id) == int(party.winner),
		})
	if reported.is_empty():
		return
	races_reported += 1
	LGOnline.rpc_async("%s.party_report" % GameConfig.GAME_ID, {
		"match_id": LGOnline.bridge.match_id,
		"race": races_reported,
		"rounds": int(party.round),
		"players": reported,
	})


## Every device: its run scene has the round loaded.
func report_loaded() -> void:
	if is_host():
		loaded_peers[1] = true
	else:
		_c_loaded.rpc_id(1, int(party.get("round", 0)))


# --- Network events -------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_hello[id] = Time.get_ticks_msec()
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(_check_hello.bind(id))


func _check_hello(id: int) -> void:
	if _pending_hello.has(id):
		_pending_hello.erase(id)
		_kick(id, "No hello from this game version.")


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	_ready_peers.erase(id)
	if not is_host():
		if id == 1 and is_online():
			leave.call_deferred("The host left the race.")
		return
	var names := []
	for aid in players.keys():
		if int(players[aid].peer) == id:
			names.append(players[aid].name)
			players.erase(aid)
	loaded_peers.erase(id)
	if in_match:
		peer_left.emit(id)
	if names.is_empty():
		return
	_broadcast_roster()
	status.emit("%s left." % " and ".join(names))


func _on_connected_to_server() -> void:
	_send_hello()


func _send_hello() -> void:
	local_seats[0].name = player_name()
	_c_hello.rpc_id(1, GameConfig.version(), GameConfig.PROTOCOL, seat_payload())


func _on_connection_failed() -> void:
	status.emit("Couldn't connect to the host.")
	leave("Couldn't connect to the host.")


func _on_server_disconnected() -> void:
	leave("The host left the race.")


func _on_beacon_hosts(hosts: Array) -> void:
	hosts_found.emit(hosts.filter(_is_our_game))


func _is_our_game(h: Dictionary) -> bool:
	return str(h.get("game", "")) == GameConfig.GAME_ID


## A couch pilot's controller was unplugged: they leave their seat (between
## races; mid-race their pilot just stops flying until it's back).
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or in_match:
		return
	var seat := seat_for_pad(device)
	if seat > 0:
		remove_local_seat(seat)
		status.emit("A controller was disconnected, so Pilot %d left." % (seat + 1))


# --- RPCs -----------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(version: String, protocol: int, seats: Array) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_hello.erase(id)
	if protocol != GameConfig.PROTOCOL:
		_kick(id, "This race runs version %s. Update Burn Rate to fly together." % GameConfig.version())
		return
	if in_match:
		_kick(id, "A race is already under way. Join after it ends.")
		return
	if players.size() >= GameConfig.MAX_PLAYERS:
		_kick(id, "This race is full.")
		return
	_apply_seats(id, seats)
	if _quick_start_msec != 0:
		_h_countdown.rpc_id(id, quick_seconds_left())
	var names := []
	for aid in players:
		if int(players[aid].peer) == id:
			names.append(players[aid].name)
	status.emit("%s joined." % " and ".join(names))
	if version != GameConfig.version():
		status.emit("%s has version %s (you have %s)." % [names[0] if not names.is_empty() else "A pilot", version, GameConfig.version()])


@rpc("any_peer", "reliable")
func _c_seats(seats: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and not in_match and not _pending_hello.has(id) and players.values().any(_peer_is.bind(id)):
		_apply_seats(id, seats)


func _peer_is(p: Dictionary, id: int) -> bool:
	return int(p.peer) == id


@rpc("any_peer", "reliable")
func _c_ready(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or _pending_hello.has(id):
		return
	if on:
		_ready_peers[id] = true
	else:
		_ready_peers.erase(id)
	for aid in players:
		if int(players[aid].peer) == id:
			players[aid].ready = on
	_broadcast_roster()


@rpc("any_peer", "reliable")
func _c_loaded(round_no: int) -> void:
	if is_host() and in_match and round_no == int(party.get("round", -1)):
		loaded_peers[multiplayer.get_remote_sender_id()] = true


@rpc("authority", "reliable")
func _h_roster(p_players: Dictionary, p_settings: Dictionary, p_code: String) -> void:
	var first := players.is_empty()
	players = p_players
	settings = p_settings
	join_code = p_code
	if first:
		joined.emit()
	roster_changed.emit()
	settings_changed.emit()


## Quick match: the first race starts by itself in this many seconds.
@rpc("authority", "reliable")
func _h_countdown(seconds: float) -> void:
	quick = true
	_quick_start_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	roster_changed.emit()


@rpc("authority", "reliable")
func _h_kicked(reason: String) -> void:
	leave(reason)
	LGScenes.change_scene(TITLE_SCENE, _title_message.bind(reason))


func _title_message(node: Node, reason: String) -> void:
	node.set("message", reason)


## A round starts: load it (or restart the run scene with it).
@rpc("authority", "reliable")
func _h_round(config: Dictionary, summary: Dictionary) -> void:
	in_match = true
	_quick_start_msec = 0
	if not is_host():
		party = summary.duplicate(true)
		party["pilots"] = config.get("pilots", []).duplicate(true)
		party["next_msec"] = 0
	party_changed.emit()
	var c := localize(config)
	LGInput.filter_claimed_pads = false
	var scene := get_tree().current_scene
	if scene is RunScene and not LGScenes.is_busy():
		scene.start(c)
	else:
		RunScene.next_config = c
		LGScenes.change_scene(RUN_SCENE, _setup_run.bind(c))


## The score after a round; the next round (or the lobby) in `wait` seconds.
@rpc("authority", "reliable")
func _h_party(summary: Dictionary, wait: float) -> void:
	var pilots: Array = party.get("pilots", [])
	party = summary.duplicate(true)
	party["pilots"] = pilots
	party["next_msec"] = Time.get_ticks_msec() + int(wait * 1000.0)
	party_changed.emit()


@rpc("authority", "reliable")
func _h_return_to_lobby() -> void:
	in_match = false
	party = {}
	_break_timer = null
	loaded_peers.clear()
	LGScenes.change_scene(LOBBY_SCENE)


func _broadcast_roster() -> void:
	if not is_host():
		return
	if mode != Mode.SOLO and mode != Mode.NONE:
		for peer_id in multiplayer.get_peers():
			if not _pending_hello.has(peer_id):
				_h_roster.rpc_id(peer_id, players, settings, join_code)
	_beacon.update_info({"players": players.size()})
	roster_changed.emit()
	settings_changed.emit()


func _kick(id: int, reason: String) -> void:
	_h_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(_disconnect_peer.bind(id))


func _disconnect_peer(id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _unique_name(p_name: String) -> String:
	if p_name == "":
		p_name = "Pilot"
	var names := []
	for p in players.values():
		names.append(p.name)
	var out := p_name
	var n := 2
	while out in names:
		out = "%s %d" % [p_name, n]
		n += 1
	return out


func _beacon_info() -> Dictionary:
	return {
		"game": GameConfig.GAME_ID,
		"version": GameConfig.version(),
		"protocol": GameConfig.PROTOCOL,
		"name": "%s's race" % player_name(),
		"port": int(LGSettings.get_value("lan", "port")),
		"players": players.size(),
		"max": GameConfig.MAX_PLAYERS,
		"state": "lobby",
		"code": join_code,
	}


## The lobby settings are remembered between races.
func _load_lobby_settings() -> void:
	var saved = LGSettings.get_value("lobby", "settings", {})
	if saved is Dictionary:
		for k in saved:
			if settings.has(k):
				settings[k] = saved[k]


func _save_lobby_settings() -> void:
	LGSettings.set_value("lobby", "settings", settings.duplicate())
