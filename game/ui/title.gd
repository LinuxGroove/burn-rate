class_name TitleScreen
extends Node
## The title: a bot flying the tower behind the logo, and every way in:
## Fly (endless), today's Daily Flight, Courses, Party (on one screen, the
## local network or online), the Hangar, Leaderboards, Settings, How to play,
## About and Quit. The missions and your bank sit beside the menu.

const SCENE := "res://game/ui/title.tscn"
const BG := Color(0.01, 0.015, 0.04)

## The page to open on arrival ("hangar", "courses", "daily", ...), set by
## whoever sends the player here.
static var next_page := ""

## Shown once on arrival, e.g. why a party race ended.
var message := ""

var _backdrop: RunScene
var _ui: Control
var _main: Control
var _menu: VBoxContainer
var _side: VBoxContainer
var _page: Control
var _col: VBoxContainer
var _status: Label
var _main_status: Label
var _about_scroll: ScrollContainer
var _net_controls: Array = []
var _net_label: Label
var _net_up := true
var _net_check_at := 0
var _leaving := false
var _howto: HowToPanel
var page := "main"


func _ready() -> void:
	LGInput.filter_claimed_pads = false
	_backdrop = load("res://game/play/run_scene.tscn").instantiate()
	_backdrop.config = Flights.backdrop()
	add_child(_backdrop)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	_build_main()
	_build_page()
	var version := LGUi.label("v%s" % GameConfig.version(), "HintLabel")
	_ui.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	if Session.has_signal("status"):
		Session.connect("status", _on_status)
	var open := next_page
	next_page = ""
	match open:
		"hangar":
			show_hangar()
		"courses":
			show_courses()
		"daily":
			show_daily()
		"party":
			show_party()
		"leaderboards":
			show_leaderboards()
		_:
			show_main()


func _on_status(text: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = text


# --- Layout -------------------------------------------------------------------

func _build_main() -> void:
	_main = Control.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_main)
	var shade := Shade.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main.add_child(shade)
	var logo := BurnTheme.logo(92)
	_main.add_child(logo)
	RunHud.pin(logo, Control.PRESET_TOP_LEFT, 54, 40)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 12)
	_main.add_child(_side)
	RunHud.pin(_side, Control.PRESET_BOTTOM_LEFT, 54, -40)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = 420
	_main.add_child(right)
	RunHud.pin(right, Control.PRESET_CENTER_RIGHT, -64, 0)
	LGScreenFit.center(right, Vector2(32, 40))
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	right.add_child(_menu)
	_main_status = LGUi.label("", "HintLabel")
	_main_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_status.custom_minimum_size.x = 420
	right.add_child(_main_status)


func _build_page() -> void:
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.visible = false
	_ui.add_child(_page)
	var dim := ColorRect.new()
	dim.color = Color(BG, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(dim)
	_col = LGUi.centered_column(_page, 600)
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	LGScreenFit.center(_col)


func _clear_page() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_about_scroll = null
	_net_controls = []
	_net_label = null
	if _howto and is_instance_valid(_howto):
		_howto.queue_free()
	_howto = null


func _open_page(name: String) -> void:
	page = name
	_clear_page()
	_main.visible = false
	_page.visible = true
	_status = null


func _process(_delta: float) -> void:
	if not _net_controls.is_empty() and Time.get_ticks_msec() >= _net_check_at:
		_apply_network(false)


## Claims the screen for one action that leaves it; false if one is running.
func _claim() -> bool:
	if _leaving or LGScenes.is_busy():
		return false
	_leaving = true
	return true


# --- The main menu ------------------------------------------------------------

func show_main() -> void:
	page = "main"
	_clear_page()
	_page.visible = false
	_main.visible = true
	for c in _menu.get_children():
		_menu.remove_child(c)
		c.queue_free()
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	var fly := LGUi.button("Fly", _fly, 420)
	fly.theme_type_variation = "HeroButton"
	fly.custom_minimum_size.y = 86
	_menu.add_child(fly)
	var daily_best := Progress.daily_best()
	_menu.add_child(LGUi.button("Daily Flight" + ("  ·  %s" % GameConfig.meters(daily_best) if daily_best > 0 else "  ·  NEW"), show_daily, 420))
	_menu.add_child(LGUi.button("Courses", show_courses, 420))
	_menu.add_child(LGUi.button("Party", show_party, 420))
	_menu.add_child(LGUi.button("Hangar", show_hangar, 420))
	_menu.add_child(LGUi.button("Leaderboards", show_leaderboards, 420))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_menu.add_child(grid)
	grid.add_child(_small("Settings", show_settings))
	grid.add_child(_small("How to play", show_howto))
	grid.add_child(_small("About", show_about))
	var quit := _small("Quit", _quit)
	quit.theme_type_variation = "DangerButton"
	grid.add_child(quit)
	var card := MissionsCard.new()
	_side.add_child(card)
	_side.add_child(_bank_line())
	_status = _main_status
	_status.text = message
	message = ""
	BurnTheme.focus(fly)


func _small(text: String, cb: Callable) -> Button:
	var b := LGUi.button(text, cb, 205)
	b.custom_minimum_size = Vector2(205, 50)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _bank_line() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var icon := RunHud.CreditIcon.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	row.add_child(BurnTheme.label(GameConfig.grouped(Progress.credits()), 24, BurnTheme.GOLD, BurnTheme.spaced(BurnTheme.heading(), 2), 5))
	var best := Progress.best_distance(Flights.pace(), Flights.lanes())
	if best > 0:
		row.add_child(BurnTheme.label("BEST %s" % GameConfig.meters(best), 20, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 5))
	row.add_child(BurnTheme.label(Packs.display_name(Progress.pack()).to_upper(), 20, Packs.spec(Progress.pack()).color.lightened(0.2), BurnTheme.spaced(BurnTheme.heading(), 3), 5))
	return row


func _quit() -> void:
	LGScenes.quit()


func _fly() -> void:
	if _claim():
		Session.launch(Flights.endless())


# --- Daily Flight -------------------------------------------------------------

func show_daily() -> void:
	_open_page("daily")
	var date := Flights.today()
	var pack := Flights.daily_pack(date)
	_col.add_child(LGUi.label("Daily Flight", "HeaderMedium"))
	_col.add_child(BurnTheme.label(Flights.date_text(date).to_upper(), 24, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 4), 4))
	var info := LGUi.label("The same flight for everyone today, on the same prototype, with no gadgets. Your best flies beside you as a ghost.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 600
	_col.add_child(info)
	var spec := Packs.spec(pack)
	_col.add_child(BurnTheme.label("TODAY'S PROTOTYPE: %s" % str(spec.name).to_upper(), 22, spec.color.lightened(0.2), BurnTheme.spaced(BurnTheme.heading(), 3), 4))
	var best := Progress.daily_best(date)
	_col.add_child(BurnTheme.label("YOUR BEST TODAY: %s" % (GameConfig.meters(best) if best > 0 else "NOT FLOWN YET"), 22, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 4))
	var go := LGUi.button("Fly today's flight", _fly_daily, 600)
	go.theme_type_variation = "HeroButton"
	_col.add_child(go)
	_col.add_child(LGUi.button("Today's board", _daily_board, 600))
	_col.add_child(LGUi.button("Back", show_main, 600))
	BurnTheme.focus(go)


func _fly_daily() -> void:
	if _claim():
		Session.launch(Flights.daily())


func _daily_board() -> void:
	show_leaderboards("daily")


# --- Courses ------------------------------------------------------------------

func show_courses() -> void:
	_open_page("courses")
	var picker := CoursePicker.new()
	picker.picked.connect(_fly_course)
	picker.closed.connect(show_main)
	_col.add_child(picker)


func _fly_course(id: String) -> void:
	if _claim():
		Session.launch(Flights.course(id))


# --- Party --------------------------------------------------------------------

func show_party() -> void:
	_open_page("party")
	_col.add_child(LGUi.label("Party: Last One Flying", "HeaderMedium"))
	var info := LGUi.label("Everyone flies the same course and the screen follows the leader. Fall off the left edge and you're out. First to three rounds wins.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 600
	_col.add_child(info)
	var couch := LGUi.button("On this screen", _party.bind("couch"), 600)
	couch.theme_type_variation = "HeroButton"
	_col.add_child(couch)
	var lan := LGUi.button("Local network", _party.bind("lan"), 600)
	var online := LGUi.button("Online", _party.bind("online"), 600)
	_col.add_child(lan)
	_col.add_child(online)
	_col.add_child(LGUi.button("Back", show_main, 600))
	_status = LGUi.label("", "HintLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 600
	_col.add_child(_status)
	_watch_network([lan, online], "You're not connected to a network. Connect to Wi-Fi or plug in a network cable to race with others nearby or online.")
	BurnTheme.focus(couch)


## Opens a party lobby: on this screen, the local network or online. The
## lobby itself is Session's (`open_party_lobby(kind)`); without one, a
## race on this screen against bots.
func _party(kind: String) -> void:
	if kind == "online" and not LGOnline.is_enabled():
		_status.text = "Online play is off. Turn it on in Settings."
		return
	if not _claim():
		return
	if Session.has_method("open_party_lobby"):
		Session.call("open_party_lobby", kind)
		return
	if kind == "couch":
		Session.launch(Flights.party_couch([0], 3))
		return
	_leaving = false
	_status.text = "Racing on the network isn't in this build yet."


## Turns `controls` off, with `offline_text` under the page's header, while
## this device has no network, and back on when it has one again.
func _watch_network(controls: Array, offline_text: String) -> void:
	_net_controls = controls
	_net_label = LGUi.label(offline_text, "HintLabel")
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.custom_minimum_size.x = 600
	_net_label.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
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
	for c in _net_controls:
		if c is BaseButton:
			c.disabled = not up
		c.focus_mode = Control.FOCUS_ALL if up else Control.FOCUS_NONE
	var focused := get_viewport().gui_get_focus_owner()
	if not force and (focused == null or focused in _net_controls or up):
		LGUi.focus_first(_col)


# --- Hangar -------------------------------------------------------------------

func show_hangar() -> void:
	_open_page("hangar")
	var h := HangarPanel.new()
	h.closed.connect(show_main)
	_col.add_child(h)


# --- Leaderboards -------------------------------------------------------------

func show_leaderboards(kind := "") -> void:
	_open_page("leaderboards")
	_col.add_child(LGUi.label("Leaderboards", "HeaderMedium"))
	if not LGOnline.is_enabled():
		var info := LGUi.label("The boards live on a LinuxGroove game server. Turn on online play in Settings to see them.", "HintLabel")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 600
		_col.add_child(info)
		_col.add_child(LGUi.button("Settings", show_settings, 600))
		_col.add_child(LGUi.button("Back", show_main, 600))
		LGUi.focus_first(_col)
		return
	if kind == "":
		var a := LGUi.button("Endless", show_leaderboards.bind("endless"), 600)
		_col.add_child(a)
		_col.add_child(LGUi.button("Daily Flight", show_leaderboards.bind("daily"), 600))
		_col.add_child(LGUi.button("Courses", show_leaderboards.bind("courses"), 600))
		_col.add_child(LGUi.button("Back", show_main, 600))
		_status = LGUi.label("", "HintLabel")
		_col.add_child(_status)
		_watch_network([a], LGNetwork.OFFLINE_TEXT)
		LGUi.focus_first(_col)
		return
	var boards: Array = Boards.endless_boards()
	var hint := "Furthest endless runs, by pace, with lanes or in Classic."
	match kind:
		"daily":
			boards = [["daily", "Today's flight"]]
			hint = "Furthest today on %s." % Flights.date_text(Flights.today())
		"courses":
			boards = Boards.course_boards()
			hint = "Fastest times on each course."
	_col.add_child(LGUi.label(hint, "HintLabel"))
	var panel := LGLeaderboardPanel.new()
	panel.setup(GameConfig.GAME_ID, Progress.pilot_name(), boards, Boards.record_text)
	_col.add_child(panel)
	var back := LGUi.button("Back", show_leaderboards.bind(""), 600)
	_col.add_child(back)
	_watch_network([], LGNetwork.OFFLINE_TEXT)
	LGUi.focus_first(_col)


# --- Settings, how to play, about ---------------------------------------------

func show_settings() -> void:
	_open_page("settings")
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(600, 520)
	scroll.follow_focus = true
	_col.add_child(scroll)
	var s := PlaySettings.new()
	scroll.add_child(s)
	_col.add_child(LGUi.button("Back", show_main, 600))
	LGUi.focus_first(scroll)


func show_howto() -> void:
	_open_page("howto")
	_page.visible = false
	_main.visible = false
	_howto = HowToPanel.new()
	_howto.offer_first_flight = true
	_ui.add_child(_howto)
	_howto.closed.connect(_on_howto_closed)
	_howto.first_flight.connect(_first_flight)
	_howto.open()


func _on_howto_closed() -> void:
	show_main()


func _first_flight() -> void:
	if _claim():
		Session.launch(Flights.tutorial())


## Credits. Up and down scroll the page, since Back is the only button.
func show_about() -> void:
	_open_page("about")
	_col.add_child(LGUi.label("About Burn Rate", "HeaderMedium"))
	_about_scroll = ScrollContainer.new()
	_about_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_about_scroll.custom_minimum_size = Vector2(640, 470)
	_col.add_child(_about_scroll)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about_scroll.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = ABOUT_TEXT % GameConfig.version()
	panel.add_child(text)
	var back := LGUi.button("Back", show_main, 600)
	_col.add_child(back)
	BurnTheme.focus(back)


func _input(event: InputEvent) -> void:
	if _about_scroll and is_instance_valid(_about_scroll):
		var step := 0
		if event.is_action_pressed("ui_down", true):
			step = 1
		elif event.is_action_pressed("ui_up", true):
			step = -1
		if step != 0:
			_about_scroll.scroll_vertical += step * 60
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Back from any page (the hangar and courses handle their own).
	if event.is_action_pressed("ui_cancel") and page in ["daily", "party", "leaderboards", "settings", "about"]:
		get_viewport().set_input_as_handled()
		show_main()


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	var root: Node = _menu if page == "main" else _col
	for b in root.find_children("", "Button", true, false):
		if (b as Button).is_visible_in_tree() or not is_inside_tree():
			out.append((b as Button).text)
	return out


const ABOUT_TEXT := """[center][font_size=30][color=#ff7a1a][b]BURN RATE[/b][/color][/font_size]  v%s
A LinuxGroove game

[b]Created by[/b]
Drew VanDine
Kaden VanDine
Ken VanDine

[b]Art[/b]
Quaternius (quaternius.com), CC0. Thank you, Quaternius!
Modular Sci-Fi MegaKit, Sci-Fi Essentials Kit,
Universal Base Characters,
Universal Animation Library 1 and 2

Kenney (kenney.nl), CC0. Thank you, Kenney!
Kenney Fonts, Input Prompts, Interface Sounds

The jetpack was modelled in Blender on the MegaKit's own textures.

[b]Made with[/b]
Godot Engine (godotengine.org), MIT
Nakama Godot client by Heroic Labs, Apache-2.0

Kestrel Lift and Halberd Security are made up.
Nobody was harmed in the testing of these prototypes.

Copyright (c) 2026 The LinuxGroove team
Burn Rate is free software under the MIT license.[/center]"""


## The dark wash behind the menus: heavier on the right, under the menu,
## and at the bottom left, under the missions, so the flight shows between.
class Shade:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c0 := Color(0.01, 0.015, 0.04, 0.0)
		var c1 := Color(0.01, 0.015, 0.04, 0.88)
		var x0 := w - 620.0
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(w, 0), Vector2(w, h), Vector2(x0 - 140, h)]),
			PackedColorArray([c0, c1, c1, c0]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.45), Vector2(w * 0.5, h * 0.45), Vector2(w * 0.5, h), Vector2(0, h)]),
			PackedColorArray([c0, c0, Color(c1, 0.0), Color(c1, 0.75)]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.6, 0), Vector2(w * 0.6, h * 0.35), Vector2(0, h * 0.35)]),
			PackedColorArray([Color(c1, 0.55), Color(c1, 0.0), c0, c0]))
		# A thin orange rule down the menu's edge.
		draw_line(Vector2(x0 + 70, 0), Vector2(x0 - 70, h), Color(BurnTheme.ORANGE, 0.35), 2.0, true)
