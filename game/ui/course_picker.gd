class_name CoursePicker
extends VBoxContainer
## The courses, five to a zone: pick a zone, then a course, with your medal,
## best time and the times for each medal. LB and RB flip between zones.

signal picked(id: String)
signal closed

var zone := "lab"
var _zones: HBoxContainer
var _grid: GridContainer
var _detail: VBoxContainer
var _count: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	add_child(head)
	var t := LGUi.label("Courses", "HeaderMedium")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count = BurnTheme.label("", 20, BurnTheme.GOLD, BurnTheme.spaced(BurnTheme.heading(), 3), 4)
	head.add_child(_count)
	_zones = HBoxContainer.new()
	_zones.add_theme_constant_override("separation", 8)
	add_child(_zones)
	for z in Zones.ORDER:
		var b := LGUi.button(Zones.display_name(z), show_zone.bind(z), 150)
		b.theme_type_variation = "TileButton"
		b.name = "Zone_" + z
		b.add_theme_font_size_override("font_size", 16)
		_zones.add_child(b)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	add_child(_grid)
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size.y = 120
	_detail.add_theme_constant_override("separation", 4)
	add_child(_detail)
	add_child(LGUi.button("Back", _close, 220))
	# Open on the first zone with a course still short of gold.
	for z in Zones.ORDER:
		var got := Progress.medal_count(z)
		if int(got.gold) + int(got.patrol) < 5:
			zone = z
			break
	show_zone(zone)


func show_zone(z: String) -> void:
	zone = z
	var all := Progress.medal_count()
	_count.text = "%d GOLD OF 30" % (int(all.gold) + int(all.patrol))
	for b in _zones.get_children():
		(b as Button).add_theme_color_override("font_color", BurnTheme.ORANGE if str(b.name) == "Zone_" + z else BurnTheme.TEXT)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for id in Courses.in_zone(z):
		var d := Courses.get_def(id)
		var best := Progress.course_best(id)
		var medal := Progress.course_medal(id)
		var line := GameConfig.time_text(best) if best > 0.0 else "NEW"
		var b := LGUi.button("%s\n%s" % [str(d.name).to_upper(), line], _pick.bind(id), 168)
		b.theme_type_variation = "TileButton"
		b.custom_minimum_size = Vector2(168, 100)
		b.add_theme_font_size_override("font_size", 13)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		if medal != "":
			var m := MedalDot.new()
			m.color = ResultsPanel.medal_color(medal)
			m.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			m.offset_left = -26
			m.offset_top = 6
			m.offset_right = -6
			m.offset_bottom = 26
			b.add_child(m)
		b.focus_entered.connect(_show_detail.bind(id))
		_grid.add_child(b)
	_show_detail(str(Courses.in_zone(z)[0]))
	var first := LGUi.first_focusable(_grid)
	if first:
		BurnTheme.focus(first)


func _show_detail(id: String) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var d := Courses.get_def(id)
	_detail.add_child(BurnTheme.label("%s · %s" % [str(d.name).to_upper(), GameConfig.meters(float(d.length))], 22, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 4))
	var times := Courses.medal_times(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_detail.add_child(row)
	for m in ["bronze", "silver", "gold", "patrol"]:
		row.add_child(BurnTheme.label("%s %s" % [str(Courses.MEDAL_NAMES[m]).to_upper(), GameConfig.time_text(float(times[m]))], 18, ResultsPanel.medal_color(m), BurnTheme.spaced(BurnTheme.heading(), 2), 4))
	var best := Progress.course_best(id)
	var ghost := FileAccess.file_exists(Progress.ghost_path("course_" + id))
	var note := "Your best: %s%s" % [GameConfig.time_text(best), ". Your ghost flies with you." if ghost else "."] if best > 0.0 else "Burn makes you faster: fly close to earn the gold."
	var nl := BurnTheme.label(note, 18, BurnTheme.CYAN, BurnTheme.narrow(), 3)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 860
	_detail.add_child(nl)


func _pick(id: String) -> void:
	picked.emit(id)


func _close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif shoulder(event) != 0:
		show_zone(Zones.ORDER[posmod(Zones.ORDER.find(zone) + shoulder(event), Zones.ORDER.size())])
		get_viewport().set_input_as_handled()


## -1 for a press of LB, 1 for RB, 0 otherwise.
static func shoulder(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			return -1
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	return 0


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in find_children("", "Button", true, false):
		out.append((b as Button).text)
	return out


## A medal on a course's tile.
class MedalDot:
	extends Control
	var color := Color.GOLD

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, size.x * 0.5, color.darkened(0.3))
		draw_circle(c, size.x * 0.36, color)
