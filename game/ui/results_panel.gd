class_name ResultsPanel
extends Control
## The end of a run: how far (or how fast), the credits banked, the best
## Burn, the missions finished with a little celebration, a rank up and what
## it opened, and a big Fly again, which has the focus so one press flies
## straight back in. Built by RunScene over the run.

var scene: RunScene
var result := {}
var report := {}
var _col: VBoxContainer
var _buttons: VBoxContainer
var _big: Label
var _target := 0.0
var _shown := 0.0
var _t := 0.0
## Pieces that appear one after another: [time, Control].
var _reveal: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Builds the page for a finished run and what Progress made of it.
func show_run(r: Dictionary, rep: Dictionary) -> void:
	result = r
	report = rep
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.04, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	center.add_child(row)
	LGScreenFit.center(row)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_col.custom_minimum_size.x = 560
	row.add_child(_col)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.custom_minimum_size.x = 380
	row.add_child(_buttons)
	_build_summary()
	_build_buttons()
	_t = 0.0


func _mode() -> String:
	return str(result.get("mode", "endless"))


func _build_summary() -> void:
	var mode := _mode()
	var head := ""
	match mode:
		"daily":
			head = "DAILY FLIGHT · %s" % Flights.date_text(str(result.get("date", Flights.today()))).to_upper()
		"course":
			head = "COURSE · %s" % str(Courses.get_def(str(result.get("course", ""))).name).to_upper()
		"tutorial":
			head = "FIRST FLIGHT"
		"party":
			head = "LAST ONE FLYING"
		_:
			head = "%s · %s" % ["ENDLESS" if bool(result.get("lanes", true)) else "CLASSIC", str(result.get("pace", "normal")).to_upper()]
	_col.add_child(BurnTheme.label(head, 20, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 5), 4))
	var stats: Dictionary = result.get("stats", {})
	_big = BurnTheme.label("", 92, BurnTheme.TEXT, BurnTheme.italic(BurnTheme.heading(), 4), 12)
	_col.add_child(_big)
	var sub := ""
	var sub_color := BurnTheme.DIM.lightened(0.3)
	match mode:
		"course":
			if stats.has("finish_time"):
				_target = float(stats.finish_time)
				var medal := str(report.get("medal", ""))
				sub = (str(Courses.MEDAL_NAMES[medal]).to_upper() + " MEDAL") if medal != "" else "NO MEDAL THIS TIME"
				sub_color = medal_color(medal)
				if bool(report.get("new_best", false)):
					sub += "  ·  NEW BEST"
			else:
				_target = float(result.get("distance", 0))
				sub = "DIDN'T FINISH"
		"party":
			var champ := int(result.get("champion", result.get("winner", -1)))
			var p := scene.run.pilot(champ) if scene and scene.run else null
			_big.text = "%s WINS" % (p.name.to_upper() if p else "NOBODY")
			_big.add_theme_font_size_override("font_size", 64)
			sub = "FIRST TO %d ROUNDS" % int(scene.config.get("first_to", 3)) if scene else ""
		"tutorial":
			_big.text = "YOU'RE OUT"
			_big.add_theme_font_size_override("font_size", 72)
			sub = "THE TOWER'S BELOW. THE PROTOTYPE'S YOURS." if stats.has("finish_time") else "NOT QUITE. TRY IT AGAIN, OR GO STRAIGHT IN."
		_:
			_target = float(result.get("distance", 0))
			if bool(report.get("new_best", false)):
				sub = "NEW BEST!" if mode == "endless" else "TODAY'S BEST!"
				sub_color = BurnTheme.GREEN
			elif int(report.get("best", 0)) > 0:
				sub = "%s %s" % ["BEST" if mode == "endless" else "TODAY'S BEST", GameConfig.meters(int(report.best))]
	var sl := BurnTheme.label(sub, 24, sub_color, BurnTheme.spaced(BurnTheme.heading(), 4), 5)
	_col.add_child(sl)
	var killed := str(stats.get("killed_by", ""))
	if killed != "" and mode in ["endless", "daily", "course"]:
		var by := BurnTheme.label("Stopped by %s." % kill_text(killed), 20, BurnTheme.DIM.lightened(0.3), BurnTheme.narrow(), 3)
		_col.add_child(by)
	if mode == "party":
		_party_table()
		return
	if mode == "tutorial":
		return
	# Credits, Burn, near misses, staff.
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 34)
	_col.add_child(nums)
	nums.add_child(_stat("CREDITS", "+%s" % GameConfig.grouped(int(result.get("credits", 0))), BurnTheme.GOLD))
	var burn := int(result.get("best_burn", 1))
	nums.add_child(_stat("BEST BURN", "×%d" % burn, BurnTheme.burn_color(burn)))
	nums.add_child(_stat("NEAR MISSES", GameConfig.grouped(int(stats.get("near", 0))), BurnTheme.TEXT))
	if int(stats.get("staff", 0)) > 0:
		nums.add_child(_stat("STAFF", GameConfig.grouped(int(stats.get("staff", 0))), BurnTheme.TEXT))
	_add_reveal(0.9, nums)
	# Missions finished in this run.
	var done: Array = report.get("missions", [])
	var at := 1.3
	for m in done:
		var chip := _mission_chip(str(m.text), int(m.reward))
		_col.add_child(chip)
		_add_reveal(at, chip)
		at += 0.45
	if int(report.get("rank", 0)) > int(report.get("rank_before", 0)):
		var rank := int(report.rank)
		var up := PanelContainer.new()
		up.theme_type_variation = "DarkPanel"
		var box := VBoxContainer.new()
		up.add_child(box)
		box.add_child(BurnTheme.label("RANK UP", 20, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 6), 4))
		box.add_child(BurnTheme.label("RANK %d · %s" % [rank, Missions.title(rank).to_upper()], 38, BurnTheme.ORANGE, BurnTheme.italic(BurnTheme.heading(), 3), 8))
		for u in report.get("unlocked", []):
			box.add_child(BurnTheme.label("NEW IN THE HANGAR: %s" % str(u.name).to_upper(), 20, BurnTheme.GREEN, BurnTheme.spaced(BurnTheme.heading(), 2), 4))
		_col.add_child(up)
		_add_reveal(at + 0.2, up)
		at += 0.6
	var bank := BurnTheme.label("In the bank: %s credits" % GameConfig.grouped(int(report.get("wallet", Progress.credits()))), 20, BurnTheme.GOLD, BurnTheme.narrow(), 3)
	_col.add_child(bank)
	_add_reveal(at, bank)
	var new_missions: Array = report.get("new_missions", [])
	if not new_missions.is_empty():
		var nm := BurnTheme.label("New mission%s: %s" % ["" if new_missions.size() == 1 else "s", "; ".join(new_missions)], 18, BurnTheme.CYAN, BurnTheme.narrow(), 3)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size.x = 560
		_col.add_child(nm)
		_add_reveal(at + 0.3, nm)


func _party_table() -> void:
	if scene == null or scene.run == null:
		return
	var wins: Dictionary = result.get("wins", scene.config.get("wins", {}))
	var list := scene.run.pilots.duplicate()
	list.sort_custom(func(a, b): return int(wins.get(a.id, 0)) > int(wins.get(b.id, 0)))
	for p in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var sw := ColorRect.new()
		sw.color = RunHud.party_color(scene.run.pilots.find(p))
		sw.custom_minimum_size = Vector2(10, 30)
		row.add_child(sw)
		var n := BurnTheme.label(p.name.to_upper(), 26, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 2), 4)
		n.custom_minimum_size.x = 300
		row.add_child(n)
		var w := int(wins.get(p.id, 0))
		row.add_child(BurnTheme.label("%d ROUND%s" % [w, "" if w == 1 else "S"], 24, BurnTheme.ORANGE_HOT, BurnTheme.spaced(BurnTheme.heading(), 2), 4))
		_col.add_child(row)


func _stat(caption: String, value: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.add_child(BurnTheme.label(caption, 14, BurnTheme.DIM.lightened(0.25), BurnTheme.spaced(BurnTheme.heading(), 3), 3))
	box.add_child(BurnTheme.label(value, 34, color, BurnTheme.spaced(BurnTheme.heading(), 2), 6))
	return box


func _mission_chip(text: String, reward: int) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "HudPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	chip.add_child(row)
	var t := RunHud.Tick.new()
	t.on = true
	t.custom_minimum_size = Vector2(26, 26)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var l := BurnTheme.label("MISSION DONE: " + text.to_upper(), 19, BurnTheme.GREEN, BurnTheme.spaced(BurnTheme.heading(), 2), 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	row.add_child(l)
	row.add_child(BurnTheme.label("+%d" % reward, 22, BurnTheme.GOLD, BurnTheme.spaced(BurnTheme.heading(), 2), 4))
	return chip


func _add_reveal(at: float, c: Control) -> void:
	c.modulate.a = 0.0
	_reveal.append([at, c])


func _build_buttons() -> void:
	var mode := _mode()
	var first: Button
	match mode:
		"tutorial":
			first = _hero("Fly for real", _fly_endless)
			_buttons.add_child(LGUi.button("First flight again", _again, 380))
			_buttons.add_child(LGUi.button("To the title", _title, 380))
		"course":
			first = _hero("Fly again", _again)
			var next := _next_course()
			if next != "":
				_buttons.add_child(LGUi.button("Next: %s" % Courses.get_def(next).name, _course.bind(next), 380))
			_buttons.add_child(LGUi.button("Courses", _title.bind("courses"), 380))
			_buttons.add_child(LGUi.button("To the title", _title, 380))
		"party":
			first = _hero("Race again", _again)
			_buttons.add_child(LGUi.button("To the title", _title, 380))
		_:
			first = _hero("Fly again", _again)
			_buttons.add_child(LGUi.button("Hangar", _title.bind("hangar"), 380))
			_buttons.add_child(LGUi.button("To the title", _title, 380))
	var hint := ActionPrompt.make("restart", "Fly again any time", 32)
	if mode != "tutorial":
		_buttons.add_child(hint)
	BurnTheme.focus(first)


func _hero(text: String, cb: Callable) -> Button:
	var b := LGUi.button(text, cb, 380)
	b.theme_type_variation = "HeroButton"
	b.custom_minimum_size.y = 84
	_buttons.add_child(b)
	return b


func _next_course() -> String:
	var ids := Courses.ids()
	var i := ids.find(str(result.get("course", "")))
	return str(ids[i + 1]) if i >= 0 and i + 1 < ids.size() else ""


func _again() -> void:
	if scene:
		scene.restart()


func _fly_endless() -> void:
	LGSettings.set_value("tutorial", "welcomed", true)
	if scene:
		scene.start(Flights.endless())


func _course(id: String) -> void:
	if scene:
		scene.start(Flights.course(id))


func _title(page := "") -> void:
	if _mode() == "tutorial":
		LGSettings.set_value("tutorial", "welcomed", true)
	if scene:
		scene.quit_to_title(page)


func _process(dt: float) -> void:
	_t += dt
	if _target > 0.0 and _big:
		_shown = lerpf(0.0, _target, 1.0 - pow(1.0 - clampf(_t / 1.0, 0.0, 1.0), 3.0))
		if _mode() == "course" and result.get("stats", {}).has("finish_time"):
			_big.text = GameConfig.time_text(_shown)
		else:
			_big.text = GameConfig.meters(_shown)
	for e in _reveal:
		var c: Control = e[1]
		if is_instance_valid(c):
			c.modulate.a = clampf((_t - float(e[0])) * 4.0, 0.0, 1.0)


## "a zapper", "a laser".
static func kill_text(kind: String) -> String:
	match kind:
		"zapper":
			return "a zapper"
		"laser":
			return "a laser"
		"seeker":
			return "a seeker"
		"shutter":
			return "a shutter"
		"eye_drone":
			return "an eye drone"
		"gun_drone":
			return "a gun drone"
		"walker":
			return "a walker"
	return "something in the dark"


static func medal_color(medal: String) -> Color:
	match medal:
		"patrol":
			return BurnTheme.ORANGE
		"gold":
			return BurnTheme.GOLD
		"silver":
			return Color("cfd8e8")
		"bronze":
			return Color("d0894a")
	return BurnTheme.DIM


## The labels of the buttons, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _buttons.find_children("", "Button", true, false):
		out.append((b as Button).text)
	return out
