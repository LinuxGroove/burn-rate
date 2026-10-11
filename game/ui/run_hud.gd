class_name RunHud
extends CanvasLayer
## What's on screen over a run: how far, the credits, the Burn meter, near
## miss call-outs by the pilot, warnings at the right edge for what's coming,
## the zone's name as you enter it, and the end of the run.

const FONT := preload("res://addons/linuxgroove/ui/fonts/Kenney Future.ttf")
const FONT_NARROW := preload("res://addons/linuxgroove/ui/fonts/Kenney Future Narrow.ttf")
## Burn level colours, x1 to x5.
const BURN_COLORS := [Color(0.85, 0.88, 0.95), Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(1.0, 0.25, 0.2), Color(1.0, 0.35, 0.9)]
const NEAR_WORDS := {"close": "CLOSE", "razor": "RAZOR", "skim": "SKIM", "thread": "THREAD"}

var run: Run
var me := 1
var camera: Camera3D
var _distance: Label
var _credits: Label
var _burn: Label
var _burn_bar: ProgressBar
var _banner: Label
var _banner_t := 0.0
var _center: Label
var _warnings: Control
var _popups: Control
var _tip: Label


func setup(p_run: Run, p_me: int, p_camera: Camera3D) -> void:
	run = p_run
	me = p_me
	camera = p_camera
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_warnings = Control.new()
	_warnings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warnings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warnings.draw.connect(_draw_warnings)
	root.add_child(_warnings)
	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popups)
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + side, 28)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	_distance = _label(FONT, 44, Color.WHITE)
	left.add_child(_distance)
	_credits = _label(FONT_NARROW, 26, Color(1.0, 0.8, 0.25))
	left.add_child(_credits)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(right)
	_burn = _label(FONT, 40, BURN_COLORS[0])
	_burn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_burn)
	_burn_bar = ProgressBar.new()
	_burn_bar.custom_minimum_size = Vector2(220, 10)
	_burn_bar.show_percentage = false
	_burn_bar.max_value = 1.0
	right.add_child(_burn_bar)
	_banner = _label(FONT, 34, Color.WHITE)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position.y = 110
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_banner)
	_tip = _label(FONT_NARROW, 28, Color(0.85, 0.95, 1.0))
	_tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.position.y = -90
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_tip)
	_center = _label(FONT, 40, Color.WHITE)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_center)
	_show_zone(run.zone())


func _label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func sync(dt: float) -> void:
	var p := run.pilot(me)
	if p == null:
		return
	_distance.text = "%s m" % GameConfig.grouped(int(p.x))
	_credits.text = "%s credits" % GameConfig.grouped(p.credits)
	var lvl := clampi(p.burn_level, 1, 5)
	_burn.text = "BURN x%d" % lvl
	_burn.add_theme_color_override("font_color", BURN_COLORS[lvl - 1])
	_burn_bar.value = p.burn_progress()
	_burn_bar.modulate = BURN_COLORS[lvl - 1]
	_banner_t -= dt
	_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	_tip.modulate.a = clampf(_tip.modulate.a - dt * 0.15, 0.0, 1.0) if _tip.modulate.a < 1.0 else _tip.modulate.a
	var room := run.course.room_at(p.x)
	if room and room.tip != "" and _tip.text != room.tip:
		_tip.text = room.tip
		_tip.modulate.a = 0.999
	for c in _popups.get_children():
		var age: float = c.get_meta("age", 0.0) + dt
		c.set_meta("age", age)
		c.position.y -= dt * 40.0
		c.modulate.a = clampf(1.4 - age, 0.0, 1.0)
		if age > 1.4:
			c.queue_free()
	_warnings.queue_redraw()


func on_event(e: Dictionary) -> void:
	match str(e.type):
		"room":
			var r := run.course.rooms.back() as RoomGen
			if r and r.tags.has("entry") and not r.tags.has("start"):
				_show_zone(str(r.tags.entry))
		"near":
			if int(e.pilot) == me:
				var word := "%s +%d" % [NEAR_WORDS.get(str(e.what), "CLOSE"), int(e.points)]
				_popup(word, Vector3(float(e.x), float(e.y) + 2.2, RunView.lane_z(run.pilot(me).lane)), BURN_COLORS[clampi(int(e.level), 1, 5) - 1])
				if bool(e.get("up", false)):
					_popup("BURN x%d!" % int(e.level), Vector3(float(e.x) + 1.0, float(e.y) + 3.2, RunView.lane_z(run.pilot(me).lane)), BURN_COLORS[clampi(int(e.level), 1, 5) - 1], 40)
		"burn_lost":
			if int(e.pilot) == me:
				var p := run.pilot(me)
				_popup("Burn lost", Vector3(p.x, p.y + 2.2, RunView.lane_z(p.lane)), Color(0.7, 0.75, 0.85))
		"knock":
			if int(e.pilot) == me:
				var p := run.pilot(me)
				_popup("Sorry!", Vector3(float(e.x), 2.4, RunView.lane_z(float(e.lane))), Color(0.9, 0.95, 1.0), 22)
		"vehicle":
			if int(e.pilot) == me:
				_banner.text = Zones.VEHICLE_NAMES.get(str(e.vehicle), "Ride")
				_banner_t = 2.0
		"shield", "armour", "reboot":
			if int(e.pilot) == me:
				var p := run.pilot(me)
				_popup({"shield": "Shield!", "armour": "Armour!", "reboot": "Reboot!"}[str(e.type)], Vector3(p.x, p.y + 2.4, RunView.lane_z(p.lane)), Color(0.4, 0.8, 1.0), 32)


func _show_zone(zone: String) -> void:
	var info := Zones.info(zone)
	_banner.text = "%s\n%s" % [str(info.name), str(info.get("floor", ""))]
	_banner_t = 3.0


func _popup(text: String, at: Vector3, color: Color, size := 28) -> void:
	if camera == null:
		return
	var l := _label(FONT, size, color)
	l.text = text
	l.position = camera.unproject_position(at) - Vector2(60, 20)
	_popups.add_child(l)


## Warnings at the right edge for what's coming: seekers lock on, lasers
## charge.
func _draw_warnings() -> void:
	if camera == null:
		return
	var w := _warnings.size.x
	for h in run.hazards:
		var warn: Dictionary = h.warning()
		if warn.is_empty():
			continue
		var at := Vector3(camera.position.x + 8.0, float(warn.y) + 0.9, RunView.lane_z(float(warn.lane)))
		var sp := camera.unproject_position(at)
		var x := w - 70.0
		var col := Color(1.0, 0.6, 0.1) if str(warn.kind) == "seeker" else Color(1.0, 0.2, 0.25)
		var blink := 1.0 if bool(warn.get("locked", false)) or bool(LGSettings.get_value("comfort", "reduce_flashing")) else (0.6 + 0.4 * sin(run.time * 18.0))
		col.a = blink
		var r := 26.0
		var pts := PackedVector2Array([Vector2(x - r, sp.y), Vector2(x + r * 0.6, sp.y - r), Vector2(x + r * 0.6, sp.y + r)])
		_warnings.draw_colored_polygon(pts, col)
		_warnings.draw_string(FONT, Vector2(x - 6, sp.y + 10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.1, 0.05, 0.0))


func set_paused(on: bool) -> void:
	_center.text = "Paused\n\nPress Start or Esc to fly on" if on else ""


func show_result(r: Dictionary) -> void:
	var lines := []
	if run.mode == "party":
		var w := run.pilot(int(r.winner))
		lines.append("%s wins!" % (w.name if w else "Nobody"))
	elif run.mode == "course":
		lines.append("Finished in %s" % GameConfig.time_text(float(r.time)))
	else:
		lines.append("%s m" % GameConfig.grouped(int(r.distance)))
	lines.append("%s credits   Best Burn x%d" % [GameConfig.grouped(int(r.credits)), int(r.best_burn)])
	lines.append("")
	lines.append("Restart to fly again")
	_center.text = "\n".join(lines)
