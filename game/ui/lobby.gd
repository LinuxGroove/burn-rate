extends Node
## The party race's screens: where to fly (this screen, the local network,
## online), the quick match search, and the lobby before a race: who's
## flying with which prototype and suit, pilots joining on another
## controller, the race settings, ready and start.
##
## Menus are driven by the first pilot. Another controller joins with Start
## and steers only its own card: left and right change prototype, X the
## suit, Y the body, B leaves.

const STICK := 0.6
const REPEAT := 0.28
const BG := Color(0.035, 0.04, 0.07)
const ACCENT := Color(1.0, 0.55, 0.15)
const RULE_ROWS := [
	["pace", "Pace", [["calm", "Calm"], ["normal", "Normal"], ["fast", "Fast"]]],
	["lanes", "Lanes", [[true, "Three lanes"], [false, "Classic (one lane)"]]],
	["zone", "Start in", []],
	["rounds", "Race to", [[1, "1 round win"], [2, "2 round wins"], [3, "3 round wins"], [5, "5 round wins"]]],
	["bots", "Bots", [[0, "None"], [1, "1 bot"], [2, "2 bots"], [3, "3 bots"], [4, "4 bots"], [5, "5 bots"], [6, "6 bots"], [7, "7 bots"]]],
	["bot_skill", "Bots fly", [["novice", "Gently"], ["average", "Well"], ["expert", "Like pros"], ["mixed", "Mixed"]]],
]

## "hub", "browse", "search" or "lobby".
var page := ""
var _ui: Control
var _col: VBoxContainer
var _status: Label
var _net_controls: Array = []
var _net_label: Label
var _net_up := true
var _net_check_at := 0
var _online_controls: Array = []
var _hosts_box: VBoxContainer
var _code_edit: LineEdit
var _search_label: Label
var _search_start := 0
var _busy := false

# The lobby page.
var _code: Label
var _roster: VBoxContainer
var _cyclers := {}
var _mine := {}
var _about: Label
var _start: Button
var _ready_button: Button
var _seat_box: HBoxContainer
var _join_hint: Label
var _cards := {}
var _pads := {}


func _ready() -> void:
	LGInput.filter_claimed_pads = true
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bg)
	var glow := TextureRect.new()
	glow.texture = _glow_texture()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(glow)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	# Methods, not lambdas: a lambda stays connected to the autoload after the
	# lobby is freed.
	Session.roster_changed.connect(_refresh)
	Session.settings_changed.connect(_refresh)
	Session.seats_changed.connect(_refresh_seats)
	Session.status.connect(_on_status)
	Session.left.connect(_on_left)
	Session.joined.connect(_on_joined)
	Session.hosts_found.connect(_on_hosts)
	if Session.mode == Session.Mode.NONE:
		show_hub()
	else:
		show_lobby()


func _exit_tree() -> void:
	LGInput.filter_claimed_pads = false
	if Session.mode == Session.Mode.NONE:
		Session.stop_browsing()


## A soft orange glow from the lower left, like the tower's lights at night.
static func _glow_texture() -> Texture2D:
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.15, 1.1)
	g.fill_to = Vector2(0.95, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(ACCENT, 0.22))
	grad.set_color(1, Color(0.1, 0.2, 0.45, 0.0))
	g.gradient = grad
	g.width = 256
	g.height = 256
	return g


func _clear() -> void:
	for c in _ui.get_children():
		_ui.remove_child(c)
		c.queue_free()
	_net_controls = []
	_online_controls = []
	_cyclers = {}
	_mine = {}
	_cards = {}
	_hosts_box = null
	_search_label = null
	_start = null
	_ready_button = null
	_roster = null


func _column(width := 620) -> VBoxContainer:
	_col = LGUi.centered_column(_ui, width)
	_col.add_theme_constant_override("separation", 12)
	return _col


func _header(text: String, hint: String) -> void:
	var h := LGUi.label(text, "HeaderLarge")
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_color_override("font_color", ACCENT)
	_col.add_child(h)
	if hint != "":
		var l := LGUi.label(hint, "HintLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(l)


func _status_line() -> void:
	_status = LGUi.label("", "HintLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_status)


# --- Where to fly -----------------------------------------------------------

func show_hub() -> void:
	page = "hub"
	_clear()
	_column()
	_header("Last One Flying", "Everyone flies the same course and the screen won't wait. Fall off its left edge and you're out. Last pilot flying takes the round.")
	_col.add_child(LGUi.button("On this screen", _couch, 520))
	var host := LGUi.button("Host on this network", _host_lan, 520)
	var join := LGUi.button("Join on this network", show_browse, 520)
	_col.add_child(host)
	_col.add_child(join)
	var quick := LGUi.button("Quick match online", _quick, 520)
	var room := LGUi.button("Host an online room", _host_online, 520)
	_col.add_child(quick)
	_col.add_child(room)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code"
	_code_edit.custom_minimum_size = Vector2(260, 56)
	_code_edit.max_length = 12
	LGUi.gamepad_text_entry(_code_edit, true)
	_code_edit.text_submitted.connect(_on_code_submitted)
	row.add_child(_code_edit)
	var join_code := LGUi.button("Join with code", _join_online, 250)
	row.add_child(join_code)
	_col.add_child(row)
	_col.add_child(LGUi.button("Back", _back, 520))
	_status_line()
	_online_controls = [quick, room, _code_edit, join_code]
	_watch_network([host, join, quick, room, _code_edit, join_code])
	LGUi.focus_first(_col)


func show_browse() -> void:
	page = "browse"
	_clear()
	_column()
	_header("Join on this network", "Races hosted nearby show up here.")
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 8)
	_col.add_child(_hosts_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Join code"
	_code_edit.custom_minimum_size = Vector2(260, 56)
	_code_edit.max_length = 16
	LGUi.gamepad_text_entry(_code_edit, true)
	_code_edit.text_submitted.connect(_on_lan_code_submitted)
	row.add_child(_code_edit)
	var join := LGUi.button("Join with code", _join_lan_code, 250)
	row.add_child(join)
	_col.add_child(row)
	_col.add_child(LGUi.button("Back", show_hub, 520))
	_status_line()
	_watch_network([_code_edit, join])
	_on_hosts([])
	Session.browse_lan()
	LGUi.focus_first(_col)


func _on_hosts(hosts: Array) -> void:
	if _hosts_box == null:
		return
	for c in _hosts_box.get_children():
		_hosts_box.remove_child(c)
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(LGUi.label("Looking for races on this network...", "HintLabel"))
		return
	for h in hosts:
		var full := int(h.get("players", 0)) >= int(h.get("max", GameConfig.MAX_PLAYERS))
		var racing := str(h.get("state", "lobby")) != "lobby"
		var text := "%s  (%d/%d)%s" % [h.get("name", "A race"), int(h.get("players", 0)), int(h.get("max", 8)), "  racing" if racing else ""]
		var b := LGUi.button(text, _join_host.bind(str(h.get("ip", "")), int(h.get("port", 0))), 520)
		b.disabled = full or racing or int(h.get("protocol", 0)) != GameConfig.PROTOCOL
		_hosts_box.add_child(b)


func show_search() -> void:
	page = "search"
	_clear()
	_column()
	_header("Quick match", "If nobody turns up within a minute, you'll race bots instead.")
	_search_label = LGUi.label("Looking for pilots... 0:00", "HeaderMedium")
	_search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_search_label)
	_col.add_child(LGUi.button("Cancel", _cancel_search, 520))
	_status_line()
	_search_start = Time.get_ticks_msec()
	LGUi.focus_first(_col)


func _couch() -> void:
	Session.start_solo()
	_on_joined()


func _host_lan() -> void:
	if _busy:
		return
	if Session.host_lan():
		_on_joined()


func _join_host(ip: String, port: int) -> void:
	if ip != "" and Session.join_lan(ip, port):
		_waiting("Joining...")


func _join_lan_code() -> void:
	if Session.join_lan_code(_code_edit.text):
		_waiting("Joining...")


func _on_lan_code_submitted(_text: String) -> void:
	_join_lan_code()


func _quick() -> void:
	if _busy:
		return
	_busy = true
	show_search()
	var where: String = await Session.quick_match()
	_busy = false
	if not is_inside_tree():
		return
	match where:
		"lobby":
			_on_joined()
		"joining":
			if _search_label:
				_search_label.text = "Found a race. Joining..."
		_:
			var why := _status.text if _status else ""
			show_hub()
			_status.text = why


func _cancel_search() -> void:
	Session.cancel_quick_match()


func _host_online() -> void:
	if _busy:
		return
	_busy = true
	var ok: bool = await Session.host_online()
	_busy = false
	if ok and is_inside_tree():
		_on_joined()


func _join_online() -> void:
	if _busy:
		return
	_busy = true
	var ok: bool = await Session.join_online(_code_edit.text)
	_busy = false
	if ok and is_inside_tree() and page != "lobby":
		_waiting("Joining room %s..." % Session.join_code)


func _on_code_submitted(_text: String) -> void:
	_join_online()


func _waiting(text: String) -> void:
	if _status:
		_status.text = text


func _back() -> void:
	Session.stop_browsing()
	LGScenes.change_scene(Session.TITLE_SCENE)


func _on_joined() -> void:
	if page != "lobby":
		show_lobby()


func _on_left(reason: String) -> void:
	show_hub()
	if reason != "":
		_status.text = reason


func _on_status(text: String) -> void:
	if _status:
		_status.text = text


## Network buttons are off while there's no network, with a line saying so.
func _watch_network(controls: Array) -> void:
	_net_controls = controls
	_net_label = LGUi.label(LGNetwork.OFFLINE_TEXT, "HintLabel")
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_label.add_theme_color_override("font_color", ACCENT)
	_col.add_child(_net_label)
	_col.move_child(_net_label, 1)
	_apply_network(true)


func _apply_network(force: bool) -> void:
	_net_check_at = Time.get_ticks_msec() + 1000
	var up := LGNetwork.is_up()
	if up == _net_up and not force:
		return
	_net_up = up
	_net_label.visible = not up
	var online := LGOnline.is_enabled()
	if up and not online:
		_net_label.text = "Online play is off. Turn it on in Settings to race online."
		_net_label.visible = true
	elif not up:
		_net_label.text = LGNetwork.OFFLINE_TEXT
	for c in _net_controls:
		var on: bool = up and (online or not c in _online_controls)
		if c is BaseButton:
			c.disabled = not on
		elif c is LineEdit:
			c.editable = on
		c.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	var focused := get_viewport().gui_get_focus_owner()
	if not force and (focused == null or focused in _net_controls):
		LGUi.focus_first(_col)


# --- The lobby --------------------------------------------------------------

func show_lobby() -> void:
	page = "lobby"
	_clear()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_ui.add_child(margin)
	LGScreenFit.fill(margin)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	margin.add_child(_col)
	var head := HBoxContainer.new()
	_col.add_child(head)
	var title := LGUi.label(_title_text(), "HeaderLarge")
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_code = LGUi.label("", "HeaderMedium")
	_code.add_theme_color_override("font_color", Color("ffd23f"))
	head.add_child(_code)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	_col.add_child(body)
	_build_pilots(body)
	_build_rules(body)
	_seat_box = HBoxContainer.new()
	_seat_box.add_theme_constant_override("separation", 12)
	_col.add_child(_seat_box)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	_col.add_child(bottom)
	_status = LGUi.label("", "HintLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var leave := LGUi.button("Leave", _leave, 200)
	leave.theme_type_variation = "DangerButton"
	bottom.add_child(leave)
	_ready_button = LGUi.button("Ready", _toggle_ready, 220)
	bottom.add_child(_ready_button)
	_start = LGUi.button("Start the race", _start_race, 300)
	bottom.add_child(_start)
	_refresh()
	_refresh_seats()
	if Session.is_host() and not _start.disabled:
		_start.grab_focus.call_deferred()
	else:
		LGUi.focus_first.call_deferred(_col)


func _build_pilots(body: HBoxContainer) -> void:
	var left := PanelContainer.new()
	left.theme_type_variation = "DarkPanel"
	left.custom_minimum_size.x = 540
	body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left.add_child(scroll)
	var lcol := VBoxContainer.new()
	lcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lcol.add_theme_constant_override("separation", 6)
	scroll.add_child(lcol)
	lcol.add_child(LGUi.label("Pilots", "HeaderMedium"))
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 2)
	lcol.add_child(_roster)
	lcol.add_child(LGUi.label("Your pilot", "HeaderMedium"))
	var seat: Dictionary = Session.local_seats[0]
	_mine["pack"] = LGCycler.make("Prototype", _pack_options(), str(seat.pack), _on_mine.bind("pack"), 500)
	_mine["suit"] = LGCycler.make("Suit", _suit_options(), str(seat.suit), _on_mine.bind("suit"), 500)
	_mine["body"] = LGCycler.make("Pilot", [[0, "Body one"], [1, "Body two"]], int(seat.body), _on_mine.bind("body"), 500)
	for k in ["pack", "suit", "body"]:
		lcol.add_child(_mine[k])
	_join_hint = LGUi.label("", "HintLabel")
	_join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_hint.custom_minimum_size.x = 480
	lcol.add_child(_join_hint)


static func _pack_options() -> Array:
	var out := []
	for id in Packs.ORDER:
		out.append([id, Packs.display_name(id)])
	return out


static func _suit_options() -> Array:
	var out := []
	for id in Session.SUIT_ORDER:
		out.append([id, str(Session.SUITS[id][0])])
	return out


func _build_rules(body: HBoxContainer) -> void:
	var right := PanelContainer.new()
	right.theme_type_variation = "DarkPanel"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(LGUi.label("The race", "HeaderMedium"))
	for row in RULE_ROWS:
		var key: String = row[0]
		var options: Array = row[2]
		if key == "zone":
			options = [["random", "Anywhere"]]
			for z in Session.ZONES:
				options.append([z, Zones.display_name(z)])
		var c := LGCycler.make(row[1], options, Session.settings.get(key), _set_rule.bind(key), 520)
		_cyclers[key] = c
		box.add_child(c)
	_about = LGUi.label("", "HintLabel")
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size.x = 500
	box.add_child(_about)


func _set_rule(value: Variant, key: String) -> void:
	Session.set_setting(key, value)


func _on_mine(value: Variant, key: String) -> void:
	Session.set_seat_value(0, key, value)


func _start_race() -> void:
	Session.start_match()


func _toggle_ready() -> void:
	Session.set_ready(not Session.is_ready())


func _leave() -> void:
	# Session.left brings back the first page.
	if Session.mode == Session.Mode.SOLO:
		Session.leave()
		show_hub()
	else:
		Session.leave("")


func _title_text() -> String:
	if Session.quick:
		return "Quick match"
	match Session.mode:
		Session.Mode.SOLO:
			return "On this screen"
		Session.Mode.LAN_HOST, Session.Mode.ONLINE_HOST:
			return "Your race"
	return "Joined a race"


func _refresh() -> void:
	if page != "lobby" or _roster == null:
		return
	for c in _roster.get_children():
		_roster.remove_child(c)
		c.queue_free()
	var ids: Array = Session.players.keys()
	ids.sort()
	for id in ids:
		_roster.add_child(_roster_row(Session.players[id]))
	var bots := Session.bot_count() if Session.is_host() else _guest_bot_count()
	if bots > 0:
		var l := LGUi.label("+ %d %s, marked as bots" % [bots, "bot" if bots == 1 else "bots"], "HintLabel")
		_roster.add_child(l)
	var host := Session.is_host()
	for key in _cyclers:
		_cyclers[key].set_value(Session.settings.get(key))
		_cyclers[key].set_read_only(not host or (Session.quick and key in ["bots", "zone", "bot_skill"]))
	var pace := str(Session.settings.get("pace", "normal"))
	var zone := str(Session.settings.get("zone", "random"))
	var where := "a zone picked at random" if not zone in Session.ZONES else Zones.display_name(zone)
	_about.text = "The race starts in %s at %s pace. Credits in your lane nudge you forward, a hit stuns you and you drop back, and a pilot right behind another gets a slipstream." % [where, pace.capitalize()]
	_start.visible = host
	_start.disabled = not Session.can_start()
	_ready_button.visible = not host
	_ready_button.text = "Not ready" if Session.is_ready() else "Ready"
	var blocker := Session.start_blocker()
	if Session.quick and Session.quick_seconds_left() > 0.0:
		if Session.mode == Session.Mode.SOLO:
			_status.text = "Nobody else was looking for a race, so it's you and bots."
		elif host:
			_status.text = "Bots fill the empty spots when the countdown ends."
		else:
			_status.text = "The race starts by itself when the countdown ends."
	elif host and blocker != "":
		_status.text = blocker
	elif not host:
		_status.text = "Waiting for the host to start the race." if Session.is_ready() else "Press Ready when you're set."
	else:
		_status.text = ""
	_refresh_code()


func _guest_bot_count() -> int:
	if Session.quick:
		return 0
	return clampi(int(Session.settings.get("bots", 0)), 0, GameConfig.MAX_PLAYERS - Session.players.size())


func _roster_row(p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = Session.SUITS.get(str(p.get("suit", "kestrel")), Session.SUITS["kestrel"])[1]
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var tags := []
	if int(p.peer) == Session.local_id():
		tags.append("you" if int(p.seat) == 0 else "pilot %d" % (int(p.seat) + 1))
	if int(p.peer) == 1 and int(p.seat) == 0 and Session.is_networked():
		tags.append("host")
	elif Session.is_networked() and int(p.seat) == 0 and not Session.quick:
		tags.append("ready" if bool(p.get("ready", false)) else "not ready")
	var name := LGUi.label("%s%s" % [p.name, ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""])
	name.add_theme_font_size_override("font_size", 20)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var pack := LGUi.label(str(Packs.spec(str(p.get("pack", "k1"))).short), "HintLabel")
	pack.add_theme_color_override("font_color", Packs.spec(str(p.get("pack", "k1"))).color)
	row.add_child(pack)
	return row


func _refresh_code() -> void:
	if _code == null:
		return
	if Session.quick:
		var left := ceili(Session.quick_seconds_left())
		_code.text = "Starts in %d s" % left if left > 0 else ""
		return
	match Session.mode:
		Session.Mode.LAN_HOST:
			_code.text = "Join code: %s" % JoinCode.pretty(Session.join_code) if Session.join_code != "" else "No network found"
		Session.Mode.ONLINE_HOST, Session.Mode.ONLINE_CLIENT:
			_code.text = "Room code: %s" % Session.join_code
		_:
			_code.text = ""


# --- Pilots on other controllers ---------------------------------------------

func _refresh_seats() -> void:
	if page != "lobby" or _seat_box == null:
		return
	var seat0: Dictionary = Session.local_seats[0]
	for k in _mine:
		_mine[k].set_value(seat0[k])
	for i in _cards.keys():
		if i >= Session.local_seats.size():
			_cards[i].queue_free()
			_cards.erase(i)
	for i in range(1, Session.local_seats.size()):
		if not _cards.has(i):
			var card := SeatCard.new()
			_seat_box.add_child(card)
			card.setup(i)
			_cards[i] = card
		_cards[i].show_seat(Session.local_seats[i])
	_seat_box.visible = Session.local_seats.size() > 1
	var room := Session.local_seats.size() < GameConfig.MAX_LOCAL
	_join_hint.visible = room
	_join_hint.text = "Flying with friends on this screen? Press Start on another controller." if room else ""


func _process(delta: float) -> void:
	if page == "search" and _search_label:
		var s := (Time.get_ticks_msec() - _search_start) / 1000
		if Session.mode == Session.Mode.NONE:
			_search_label.text = "Looking for pilots... %d:%02d" % [s / 60, s % 60]
		return
	if page in ["hub", "browse"] and Time.get_ticks_msec() >= _net_check_at and _net_label:
		_apply_network(false)
	if page != "lobby":
		return
	if Session.quick:
		_refresh_code()
	var menu_pad := LGInput.menu_pad()
	for pad in Input.get_connected_joypads():
		var state: Dictionary = _pads.get(pad, {"buttons": {}, "repeat": 0.0})
		_pads[pad] = state
		var seat := Session.seat_for_pad(pad)
		if _pressed(pad, state, JOY_BUTTON_START):
			if seat < 0 and pad != menu_pad:
				if Session.add_local_seat(pad) < 0 and Session.local_seats.size() >= GameConfig.MAX_LOCAL:
					_status.text = "Up to %d pilots can share one screen." % GameConfig.MAX_LOCAL
			elif seat < 0 and Session.is_host() and not _start.disabled:
				_start.grab_focus()
		if seat <= 0:
			continue
		if _pressed(pad, state, JOY_BUTTON_B):
			Session.remove_local_seat(seat)
			continue
		var s: Dictionary = Session.local_seats[seat]
		if _pressed(pad, state, JOY_BUTTON_X):
			var i := Session.SUIT_ORDER.find(str(s.suit))
			Session.set_seat_value(seat, "suit", Session.SUIT_ORDER[wrapi(i + 1, 0, Session.SUIT_ORDER.size())])
		if _pressed(pad, state, JOY_BUTTON_Y):
			Session.set_seat_value(seat, "body", 1 - int(s.body))
		var dir := _direction(pad, state, delta)
		if dir != 0:
			var k := Packs.ORDER.find(str(s.pack))
			Session.set_seat_value(seat, "pack", Packs.ORDER[wrapi(k + dir, 0, Packs.ORDER.size())])
	for pad in _pads.keys():
		if not pad in Input.get_connected_joypads():
			_pads.erase(pad)


## True on the frame `button` went down on `pad`.
func _pressed(pad: int, state: Dictionary, button: int) -> bool:
	var down := Input.is_joy_button_pressed(pad, button)
	var was := bool(state.buttons.get(button, false))
	state.buttons[button] = down
	return down and not was


## Left or right on another pilot's d-pad or stick, with key-repeat.
func _direction(pad: int, state: Dictionary, delta: float) -> int:
	var x := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
	var d := 0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT) or x < -STICK:
		d = -1
	elif Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT) or x > STICK:
		d = 1
	if d == 0:
		state.repeat = 0.0
		return 0
	state.repeat = float(state.repeat) - delta
	if float(state.repeat) > 0.0:
		return 0
	state.repeat = REPEAT
	return d


## Another pilot's card: their prototype and suit, and how to change them.
class SeatCard extends PanelContainer:
	var index := 0
	var _swatch: ColorRect
	var _name: Label
	var _what: Label

	func setup(p_index: int) -> void:
		index = p_index
		theme_type_variation = "GlassPanel"
		custom_minimum_size.x = 400
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		add_child(row)
		_swatch = ColorRect.new()
		_swatch.custom_minimum_size = Vector2(16, 70)
		row.add_child(_swatch)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_name = LGUi.label("", "NameLabel")
		col.add_child(_name)
		_what = LGUi.label("")
		col.add_child(_what)
		var seat: Dictionary = Session.local_seats[index]
		var family := LGInput.family_for_joypad(int(seat.pad))
		var help := HBoxContainer.new()
		help.add_theme_constant_override("separation", 12)
		col.add_child(help)
		help.add_child(_glyph_hint(family, [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT], "Prototype"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_X], "Suit"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_Y], "Body"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_B], "Leave"))

	func show_seat(seat: Dictionary) -> void:
		_name.text = str(seat.name)
		_swatch.color = Session.SUITS.get(str(seat.suit), Session.SUITS["kestrel"])[1]
		_what.text = "%s, %s" % [Packs.display_name(str(seat.pack)), str(Session.SUITS.get(str(seat.suit), Session.SUITS["kestrel"])[0]).to_lower()]

	static func _glyph_hint(family: String, buttons: Array, text: String) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		for b in buttons:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(26, 26)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = LGInput.pad_glyph(family, b)
			box.add_child(icon)
		box.add_child(LGUi.label(" " + text, "HintLabel"))
		return box
