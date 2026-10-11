class_name HangarPanel
extends HBoxContainer
## The hangar: your pilot on a turntable, and four racks beside it:
## prototypes (opened by rank, with each pack's blurb and handling),
## suits (by rank, or bought with credits), gadgets (bought with credits,
## two taken into each run) and the pilot (name and body).

signal closed

const TABS := [["packs", "Prototypes"], ["suits", "Suits"], ["gadgets", "Gadgets"], ["pilot", "Pilot"]]

var tab := "packs"
var _preview: PilotPreview
var _tabs: HBoxContainer
var _body: VBoxContainer
var _detail: VBoxContainer
var _bank: Label
var _status: Label
var _back: Button


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "HudPanel"
	left.add_child(frame)
	_preview = PilotPreview.new()
	_preview.custom_minimum_size = Vector2(360, 450)
	frame.add_child(_preview)
	_bank = BurnTheme.label("", 22, BurnTheme.GOLD, BurnTheme.spaced(BurnTheme.heading(), 2), 4)
	left.add_child(_bank)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = 640
	add_child(right)
	right.add_child(LGUi.label("Hangar", "HeaderMedium"))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	right.add_child(_tabs)
	for t in TABS:
		var b := LGUi.button(t[1], show_tab.bind(t[0]), 150)
		b.theme_type_variation = "TileButton"
		b.name = "Tab_" + t[0]
		_tabs.add_child(b)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	right.add_child(_body)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.custom_minimum_size.y = 110
	right.add_child(_detail)
	_status = _wrap(BurnTheme.label("", 18, BurnTheme.ORANGE_HOT, BurnTheme.narrow(), 3))
	right.add_child(_status)
	_back = LGUi.button("Back", _close, 220)
	right.add_child(_back)
	show_tab(tab)


func _close() -> void:
	closed.emit()


func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()


func show_tab(t: String) -> void:
	tab = t
	_clear()
	_status.text = ""
	_bank.text = "BANK  %s CREDITS" % GameConfig.grouped(Progress.credits())
	for b in _tabs.get_children():
		var on := str(b.name) == "Tab_" + t
		(b as Button).add_theme_color_override("font_color", BurnTheme.ORANGE if on else BurnTheme.TEXT)
	match t:
		"packs":
			_packs()
		"suits":
			_suits()
		"gadgets":
			_gadgets()
		"pilot":
			_pilot()
	_preview.show_pilot(Progress.pack(), Progress.look())
	var first := LGUi.first_focusable(_body)
	if first:
		BurnTheme.focus(first)


# --- Prototypes ---------------------------------------------------------------

func _packs() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for k in Packs.ORDER:
		var s := Packs.spec(k)
		var open := Progress.pack_open(k)
		var parts := str(s.name).to_upper().split(" ", false, 1)
		var text := "%s\n%s\n%s" % [parts[0], parts[1] if parts.size() > 1 else "", "FLYING" if k == Progress.pack() else ("READY" if open else "RANK %d" % int(s.rank))]
		var b := _tile(text, _pick_pack.bind(k), 200, 104)
		b.add_theme_color_override("font_color", BurnTheme.TEXT if open else BurnTheme.DIM)
		if k == Progress.pack():
			b.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
		var stripe := ColorRect.new()
		stripe.color = s.color
		stripe.custom_minimum_size = Vector2(0, 5)
		stripe.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		stripe.offset_top = -7
		stripe.offset_bottom = -2
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stripe)
		b.focus_entered.connect(_pack_detail.bind(k))
		grid.add_child(b)
	_pack_detail(Progress.pack())


func _pack_detail(k: String) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var s := Packs.spec(k)
	_detail.add_child(_wrap(BurnTheme.label(str(s.blurb), 21, BurnTheme.TEXT, BurnTheme.narrow(), 3)))
	var bars := GridContainer.new()
	bars.columns = 4
	bars.add_theme_constant_override("h_separation", 14)
	_detail.add_child(bars)
	var h := Unlocks.handling(k)
	for key in h:
		bars.add_child(BurnTheme.label(str(key).to_upper(), 15, BurnTheme.DIM.lightened(0.3), BurnTheme.spaced(BurnTheme.heading(), 3), 3))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = float(h[key])
		bar.custom_minimum_size = Vector2(180, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", BurnTheme.flat(s.color.lightened(0.15), Color(0, 0, 0, 0), 0))
		bars.add_child(bar)
	var extra := []
	if int(s.get("armour", 0)) > 0:
		extra.append("Shrugs off one hit a run")
	if float(s.get("pulse", 0.0)) > 0.0:
		extra.append("Thrusts in kicks")
	var best := Progress.best_distance(Flights.pace(), Flights.lanes(), k)
	if best > 0:
		extra.append("Your best on it: %s" % GameConfig.meters(best))
	if not Progress.pack_open(k):
		extra.append("Opens at rank %d (you're rank %d)" % [int(s.rank), Progress.rank()])
	if not extra.is_empty():
		_detail.add_child(_wrap(BurnTheme.label(".  ".join(extra) + ".", 18, BurnTheme.CYAN, BurnTheme.narrow(), 3)))
	if Progress.pack_open(k):
		_preview.show_pilot(k, Progress.look())


func _pick_pack(k: String) -> void:
	if not Progress.pack_open(k):
		_status.text = "The %s opens at rank %d. Finish missions to rank up." % [Packs.display_name(k), Unlocks.pack_rank(k)]
		return
	Progress.set_pack(k)
	show_tab("packs")
	_focus_named(Packs.display_name(k).to_upper())


# --- Suits --------------------------------------------------------------------

func _suits() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var all := Unlocks.suits()
	for id in Unlocks.suit_order():
		var s: Dictionary = all[id]
		var open := Progress.suit_open(id)
		var state := "WEARING" if id == Progress.suit() else ("READY" if open else (("%s CR" % GameConfig.grouped(int(s.price))) if s.has("price") else "RANK %d" % int(s.get("rank", 0))))
		var b := _tile("%s\n%s" % [str(s.name).to_upper(), state], _pick_suit.bind(id), 152, 80)
		b.add_theme_font_size_override("font_size", 12)
		var sw := SuitSwatch.new()
		sw.main = s.main
		sw.accent = s.accent
		sw.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		sw.offset_bottom = 14
		b.add_child(sw)
		if id == Progress.suit():
			b.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
		elif not open:
			b.add_theme_color_override("font_color", BurnTheme.DIM)
		b.focus_entered.connect(_suit_detail.bind(id))
		grid.add_child(b)
	_suit_detail(Progress.suit())


func _suit_detail(id: String) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var s := Unlocks.suit(id)
	var text := "%s suit." % s.name
	if not Progress.suit_open(id):
		if s.has("price"):
			text += " %s credits. Press to buy it." % GameConfig.grouped(int(s.price))
		else:
			text += " Opens at rank %d." % int(s.get("rank", 0))
	_detail.add_child(_wrap(BurnTheme.label(text, 21, BurnTheme.TEXT, BurnTheme.narrow(), 3)))
	var look := Progress.look()
	look["main"] = s.main
	look["accent"] = s.accent
	_preview.show_pilot(Progress.pack(), look)


func _pick_suit(id: String) -> void:
	var s := Unlocks.suit(id)
	if not Progress.suit_open(id):
		if s.has("price"):
			if not Progress.buy_suit(id):
				_status.text = "Not enough credits yet: %s more." % GameConfig.grouped(int(s.price) - Progress.credits())
				return
		else:
			_status.text = "The %s suit opens at rank %d." % [s.name, int(s.get("rank", 0))]
			return
	Progress.set_suit(id)
	show_tab("suits")
	_focus_named(str(s.name).to_upper())


# --- Gadgets ------------------------------------------------------------------

func _gadgets() -> void:
	var taken := Progress.gadgets()
	var head := "Take two into each run. Taken: %s." % (", ".join(taken.map(func(g): return Unlocks.gadget(g).name)) if not taken.is_empty() else "none")
	_body.add_child(_wrap(BurnTheme.label(head, 19, BurnTheme.CYAN, BurnTheme.narrow(), 3)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for g in Unlocks.GADGET_ORDER:
		var e: Dictionary = Unlocks.GADGETS[g]
		var state := "TAKEN" if g in taken else ("OWNED" if Progress.owns_gadget(g) else "%s CR" % GameConfig.grouped(int(e.price)))
		var b := _tile("%s   %s" % [str(e.name).to_upper(), state], _pick_gadget.bind(g), 310, 60)
		if g in taken:
			b.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
		elif not Progress.owns_gadget(g):
			b.add_theme_color_override("font_color", BurnTheme.DIM.lightened(0.2))
		b.focus_entered.connect(_gadget_detail.bind(g))
		grid.add_child(b)
	_gadget_detail(str(Unlocks.GADGET_ORDER[0]))


func _gadget_detail(g: String) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var e := Unlocks.gadget(g)
	_detail.add_child(BurnTheme.label(str(e.name).to_upper(), 22, BurnTheme.ORANGE, BurnTheme.spaced(BurnTheme.heading(), 3), 4))
	_detail.add_child(_wrap(BurnTheme.label(str(e.blurb), 21, BurnTheme.TEXT, BurnTheme.narrow(), 3)))
	var how := "Press to take it along, or leave it behind." if Progress.owns_gadget(g) else "%s credits. Press to buy it." % GameConfig.grouped(int(e.price))
	_detail.add_child(BurnTheme.label(how, 18, BurnTheme.DIM.lightened(0.3), BurnTheme.narrow(), 3))
	_detail.add_child(BurnTheme.label("Gadgets stay home on the Daily Flight and courses.", 16, BurnTheme.DIM, BurnTheme.narrow(), 3))


func _pick_gadget(g: String) -> void:
	var e := Unlocks.gadget(g)
	if not Progress.owns_gadget(g):
		if not Progress.buy_gadget(g):
			_status.text = "Not enough credits yet: %s more." % GameConfig.grouped(int(e.price) - Progress.credits())
			return
	Progress.toggle_gadget(g)
	show_tab("gadgets")
	_focus_named(str(e.name).to_upper())


# --- Pilot --------------------------------------------------------------------

func _pilot() -> void:
	_body.add_child(BurnTheme.label("NAME", 16, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 3), 3))
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.placeholder_text = "Your name"
	edit.text = str(LGSettings.get_value("player", "name", ""))
	edit.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(edit)
	edit.text_submitted.connect(_save_name.bind(edit))
	edit.focus_exited.connect(_save_name.bind("", edit))
	_body.add_child(edit)
	_body.add_child(BurnTheme.label("BODY", 16, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 3), 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for b in 2:
		var t := _tile(["PILOT A", "PILOT B"][b] + ("\nCHOSEN" if Progress.body() == b else ""), _pick_body.bind(b), 200, 76)
		if Progress.body() == b:
			t.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
		row.add_child(t)
	_detail.add_child(BurnTheme.label("Your name shows on the boards and in party races.", 18, BurnTheme.DIM.lightened(0.3), BurnTheme.narrow(), 3))


func _save_name(_t: String, edit: LineEdit) -> void:
	if not is_instance_valid(edit):
		return
	var n := edit.text.strip_edges()
	if n != str(LGSettings.get_value("player", "name", "")):
		LGSettings.set_value("player", "name", n)
		if Session.get("local_seats") is Array and not Session.local_seats.is_empty() and n != "":
			Session.local_seats[0]["name"] = n
		_status.text = "Saved." if n != "" else ""


func _pick_body(b: int) -> void:
	Progress.set_body(b)
	show_tab("pilot")


# --- Pieces -------------------------------------------------------------------

func _tile(text: String, cb: Callable, w: int, h: int) -> Button:
	var b := LGUi.button(text, cb, w)
	b.theme_type_variation = "TileButton"
	b.custom_minimum_size = Vector2(w, h)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	return b


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 640
	return l


func _focus_named(prefix: String) -> void:
	for b in _body.find_children("", "Button", true, false):
		if (b as Button).text.begins_with(prefix):
			BurnTheme.focus((b as Button))
			return


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in find_children("", "Button", true, false):
		out.append((b as Button).text)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif CoursePicker.shoulder(event) != 0:
		_cycle_tab(CoursePicker.shoulder(event))
		get_viewport().set_input_as_handled()


## LB and RB flip between the racks.
func _cycle_tab(dir: int) -> void:
	var ids := TABS.map(func(t): return t[0])
	show_tab(ids[posmod(ids.find(tab) + dir, ids.size())])


## A suit's two colours as a strip on its tile.
class SuitSwatch:
	extends Control
	var main := Color.BLACK
	var accent := Color.ORANGE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2(8, 4), Vector2(size.x * 0.6 - 8, size.y - 4)), main)
		draw_rect(Rect2(Vector2(size.x * 0.6, 4), Vector2(size.x * 0.4 - 8, size.y - 4)), accent)
