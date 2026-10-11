class_name RunHud
extends CanvasLayer
## What's on screen over a run, in Kestrel Lift's colours: the flight card
## (how far, your best, credits and the Burn meter), the missions, near miss
## call-outs by the pilot, warnings at the right edge for seekers and
## lasers, the zone's name as you enter it, the first flight's tips, the
## lane you're in (with lane hints), your gadgets, ghosts' tags, and in
## party races who's still flying and who's won rounds.
##
## Sized for a 7-inch handheld: nothing that matters is under 18 px at 720p.
## Nothing flashes: warnings pulse gently, and not at all with Reduce
## flashing on.

const NEAR_WORDS := {"close": "CLOSE", "razor": "RAZOR", "skim": "SKIM", "thread": "THREAD"}
const NEAR_SIZE := {"close": 34, "razor": 42, "skim": 30, "thread": 46}
const LANE_NAMES := ["NEAR", "MID", "FAR"]
## Party pilots' colours, in pilot order.
const PARTY_COLORS := [Color("ff8a2a"), Color("4fd8ff"), Color("b47cff"), Color("5dff9a"), Color("ffd84a"), Color("ff6fb5"), Color("ff5050"), Color("7d9bff")]
const KIND_NAMES := {"seeker": "SEEKER", "laser": "LASER"}
## Seconds the missions card stays open at the start of a run.
const MISSIONS_OPEN := 9.0
## Seconds the control hints stay up.
const HINTS_FOR := 9.0
## How far ahead lane hints look (seconds of flight).
const HINT_AHEAD := 1.6

var run: Run
var me := 1
var camera: Camera3D
var config := {}
## Missions on this run, each with "banked" and "done" (finished during it).
var missions: Array = []
var finished_run := false

var _root: Control
var _card: PanelContainer
var _mode_line: Label
var _distance: Label
var _sub: Label
var _credits: Label
var _credit_icon: Control
var _burn: BurnMeter
var _missions_card: PanelContainer
var _mission_rows: Array = []
var _missions_title: Label
var _missions_open := MISSIONS_OPEN
var _toasts: VBoxContainer
var _banner: Control
var _banner_title: Label
var _banner_sub: Label
var _banner_t := 0.0
var _tip_panel: PanelContainer
var _tip: RichTextLabel
var _tip_text := ""
var _tip_t := 0.0
var _hints: HBoxContainer
var _hints_t := HINTS_FOR
var _lanes: LaneMeter
var _gadgets: HBoxContainer
var _gadget_labels := {}
var _overlay: Control
var _paused := false
var _popups: Control
var _center: VBoxContainer
var _restart_hint: Control
var _party_card: PanelContainer
var _party_rows := {}
var _party_title: Label
var _party_top: Label
var _edge: EdgeGlow
## Ghosts on screen: [{pilot, tag, ghost}].
var _ghosts: Array = []
var _credit_punch := 0.0
var _last_credits := 0
var _check_t := 0.0
var _steady := false


func setup(p_run: Run, p_me: int, p_camera: Camera3D, p_config := {}) -> void:
	run = p_run
	me = p_me
	camera = p_camera
	config = p_config
	layer = 5
	_steady = bool(LGSettings.get_value("comfort", "reduce_flashing", false))
	if run.mode != "tutorial" and run.mode != "party" and not bool(config.get("backdrop", false)):
		missions = Progress.missions()
		for m in missions:
			m["done"] = false
	_build()
	_show_zone(run.zone())


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_edge = EdgeGlow.new()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_edge)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)
	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_popups)
	if run.mode == "party":
		_build_party()
	else:
		_build_card()
		_build_missions()
	_build_banner()
	_build_tip()
	_build_bottom()
	_center = VBoxContainer.new()
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	pin(_center, Control.PRESET_CENTER, 0, -40)


## Pins `c` to a corner or edge of its parent at an offset (negative from
## the right or bottom), growing inwards to fit what's in it.
static func pin(c: Control, preset: int, x: float, y: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_right = x
	c.offset_top = y
	c.offset_bottom = y
	var ax := c.anchor_left
	var ay := c.anchor_top
	c.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0.0 else (Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_BOTH)
	c.grow_vertical = Control.GROW_DIRECTION_END if ay == 0.0 else (Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_BOTH)


# --- The flight card (top left) ---------------------------------------------

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme_type_variation = "HudPanel"
	_card.position = Vector2(26, 18)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	_mode_line = BurnTheme.label(_mode_text(), 15, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 3), 3)
	col.add_child(_mode_line)
	_distance = BurnTheme.label("0 m", 52, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 8)
	col.add_child(_distance)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_sub = BurnTheme.label("", 18, BurnTheme.DIM.lightened(0.2), BurnTheme.spaced(BurnTheme.heading(), 2), 4)
	row.add_child(_sub)
	_credit_icon = CreditIcon.new()
	_credit_icon.custom_minimum_size = Vector2(24, 24)
	row.add_child(_credit_icon)
	_credits = BurnTheme.label("0", 24, BurnTheme.GOLD, BurnTheme.spaced(BurnTheme.heading(), 2), 5)
	_credits.pivot_offset = Vector2(0, 14)
	row.add_child(_credits)
	_burn = BurnMeter.new()
	_burn.custom_minimum_size = Vector2(370, 44)
	_burn.steady = _steady
	col.add_child(_burn)


func _mode_text() -> String:
	var pack := Packs.spec(run.pilot(me).pack if run.pilot(me) else "k1")
	match run.mode:
		"daily":
			var date := str(config.get("date", Flights.today()))
			var g := _ghost_count()
			var extra := " · %d GHOST%s" % [g, "" if g == 1 else "S"] if g > 0 else ""
			return ("DAILY FLIGHT · %s · %s%s" % [Flights.date_text(date).to_upper(), str(pack.short), extra])
		"course":
			var d := Courses.get_def(str(config.get("course", "")))
			return "COURSE · %s" % str(d.name).to_upper()
		"tutorial":
			return "FIRST FLIGHT · %s" % str(pack.short)
	return "%s · %s · %s" % ["ENDLESS" if run.lanes_on else "CLASSIC", run.pace.to_upper(), str(pack.short)]


func _ghost_count() -> int:
	return _ghosts.size()


func _build_missions() -> void:
	if missions.is_empty():
		return
	_missions_card = PanelContainer.new()
	_missions_card.theme_type_variation = "HudPanel"
	_missions_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_missions_card)
	pin(_missions_card, Control.PRESET_TOP_RIGHT, -26, 18)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_missions_card.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_missions_title = BurnTheme.label("MISSIONS", 17, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 3)
	_missions_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_missions_title)
	head.add_child(BurnTheme.label("RANK %d" % Progress.rank(), 17, BurnTheme.ORANGE, BurnTheme.spaced(BurnTheme.heading(), 3), 3))
	for m in missions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var box := Tick.new()
		box.custom_minimum_size = Vector2(20, 20)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(box)
		var text := BurnTheme.label(Missions.describe(m).to_upper(), 16, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.narrow(), 2), 3)
		text.custom_minimum_size.x = 300
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var prog := BurnTheme.label("", 16, BurnTheme.ORANGE_HOT, BurnTheme.spaced(BurnTheme.narrow(), 1), 3)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog.custom_minimum_size.x = 92
		row.add_child(prog)
		_mission_rows.append({"row": row, "tick": box, "text": text, "prog": prog})
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(26, 196)
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_refresh_missions()


# --- Party ------------------------------------------------------------------

func _build_party() -> void:
	_party_card = PanelContainer.new()
	_party_card.theme_type_variation = "HudPanel"
	_party_card.position = Vector2(26, 18)
	_party_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_party_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var t := BurnTheme.label("LAST ONE FLYING", 17, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 3)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_party_title = BurnTheme.label("ROUND %d" % int(config.get("round", 1)), 17, BurnTheme.ORANGE, BurnTheme.spaced(BurnTheme.heading(), 3), 3)
	head.add_child(_party_title)
	var wins: Dictionary = config.get("wins", {})
	for i in run.pilots.size():
		var p: Pilot = run.pilots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var sw := ColorRect.new()
		sw.color = party_color(i)
		sw.custom_minimum_size = Vector2(8, 22)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		var n := BurnTheme.label(p.name.to_upper(), 16, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.narrow(), 1), 3)
		n.custom_minimum_size.x = 230
		n.clip_text = true
		row.add_child(n)
		var s := BurnTheme.label("", 16, BurnTheme.DIM.lightened(0.3), BurnTheme.spaced(BurnTheme.narrow(), 2), 3)
		s.custom_minimum_size.x = 120
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(s)
		_party_rows[p.id] = {"name": n, "state": s, "wins": int(wins.get(p.id, wins.get(str(p.id), 0)))}
	_party_top = BurnTheme.label("", 24, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 3), 6)
	_party_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_party_top)
	pin(_party_top, Control.PRESET_CENTER_TOP, 0, 20)


static func party_color(index: int) -> Color:
	return PARTY_COLORS[index % PARTY_COLORS.size()]


func _pilot_index(id: int) -> int:
	for i in run.pilots.size():
		if run.pilots[i].id == id:
			return i
	return 0


# --- Zone banner, tips and the bottom row -----------------------------------

func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_banner as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_banner as VBoxContainer).add_theme_constant_override("separation", -2)
	_root.add_child(_banner)
	pin(_banner, Control.PRESET_CENTER_TOP, 0, 120 if run.mode != "party" else 76)
	_banner_title = BurnTheme.label("", 44, BurnTheme.TEXT, BurnTheme.italic(BurnTheme.heading(), 4), 8)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner_sub = BurnTheme.label("", 18, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 5), 4)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0


func _build_tip() -> void:
	_tip_panel = PanelContainer.new()
	_tip_panel.theme_type_variation = "HudPanel"
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tip_panel)
	pin(_tip_panel, Control.PRESET_CENTER_BOTTOM, 0, -130)
	_tip = RichTextLabel.new()
	_tip.fit_content = true
	_tip.scroll_active = false
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(760, 0)
	_tip.add_theme_font_override("normal_font", BurnTheme.spaced(BurnTheme.narrow(), 1))
	_tip.add_theme_font_size_override("normal_font_size", 26)
	_tip.add_theme_color_override("default_color", BurnTheme.TEXT)
	_tip.add_theme_constant_override("outline_size", 4)
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip)
	_tip_panel.modulate.a = 0.0


func _build_bottom() -> void:
	if run.lanes_on and run.mode != "party":
		_lanes = LaneMeter.new()
		_lanes.custom_minimum_size = Vector2(230, 118)
		_lanes.hints = "hints" in _my_gadgets()
		_root.add_child(_lanes)
		pin(_lanes, Control.PRESET_BOTTOM_LEFT, 26, -22)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 26)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hints)
	pin(_hints, Control.PRESET_CENTER_BOTTOM, 0, -28)
	_hints.add_child(ActionPrompt.make("fly", "HOLD TO FLY", 38))
	if run.lanes_on:
		var lane_row := HBoxContainer.new()
		lane_row.add_theme_constant_override("separation", 2)
		lane_row.add_child(ActionPrompt.make("lane_back", "", 38))
		lane_row.add_child(ActionPrompt.make("lane_forward", "LANE", 38))
		_hints.add_child(lane_row)
	for c in _hints.find_children("", "Label", true, false):
		(c as Label).add_theme_font_override("font", BurnTheme.spaced(BurnTheme.heading(), 3))
		(c as Label).add_theme_font_size_override("font_size", 18)
	if run.mode == "party" and int(config.get("round", 1)) > 1:
		_hints_t = 0.0
	var gl := _my_gadgets()
	if not gl.is_empty():
		_gadgets = HBoxContainer.new()
		_gadgets.add_theme_constant_override("separation", 12)
		_gadgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_gadgets)
		pin(_gadgets, Control.PRESET_BOTTOM_RIGHT, -26, -26)
		for g in gl:
			var chip := PanelContainer.new()
			chip.theme_type_variation = "HudPanel"
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var l := BurnTheme.label(str(Unlocks.gadget(str(g)).get("name", g)).to_upper(), 16, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 3), 3)
			chip.add_child(l)
			_gadgets.add_child(chip)
			_gadget_labels[str(g)] = chip
	_restart_hint = ActionPrompt.make("restart", "FLY AGAIN", 40)
	_restart_hint.visible = false
	_root.add_child(_restart_hint)
	pin(_restart_hint, Control.PRESET_CENTER_BOTTOM, 0, -28)


func _my_gadgets() -> Array:
	var p := run.pilot(me)
	return p.stats.get("gadgets", []) if p else []


# --- Every tick ---------------------------------------------------------------

func sync(dt: float) -> void:
	var p := run.pilot(me)
	if p == null:
		return
	if run.mode == "party":
		_sync_party(dt)
	else:
		_sync_card(p, dt)
	_banner_t -= dt
	_banner.modulate.a = clampf(minf(_banner_t, 3.2 - _banner_t) * 2.5, 0.0, 1.0)
	_sync_tip(p, dt)
	_hints_t -= dt
	_hints.modulate.a = clampf(_hints_t, 0.0, 1.0)
	_hints.visible = _hints.modulate.a > 0.01 and not finished_run and not _paused
	_restart_hint.visible = not finished_run and not _paused and p.state != Pilot.State.FLY and run.mode != "party" and not _hints.visible
	if _lanes:
		_lanes.lane = p.lane
		_lanes.target = p.lane_to
		_lanes.visible = not finished_run and not _paused
		if _lanes.hints and run.tick % 4 == 0:
			_lanes.danger = _lane_danger(p)
		_lanes.queue_redraw()
	if _gadgets:
		_sync_gadgets(p)
	_sync_popups(dt)
	_overlay.queue_redraw()


func _sync_card(p: Pilot, dt: float) -> void:
	if run.mode == "course":
		_distance.text = GameConfig.time_text(run.time) if run.time > 0.0 else "0.00"
		var id := str(config.get("course", ""))
		var times := Courses.medal_times(id)
		var next := ""
		for m in ["bronze", "silver", "gold", "patrol"]:
			if run.time <= float(times[m]):
				next = m
		if next == "":
			_sub.text = "%d m TO GO" % maxi(0, int(run.finish_x - p.x))
		else:
			_sub.text = "%s %s" % [str(Courses.MEDAL_NAMES[next]).to_upper(), GameConfig.time_text(float(times[next]))]
	else:
		_distance.text = GameConfig.meters(p.x)
		var best := _best()
		_sub.text = "BEST %s" % GameConfig.meters(best) if best > 0 else ""
		_sub.visible = best > 0
		if best > 0 and p.x > best:
			_sub.text = "NEW BEST"
			_sub.add_theme_color_override("font_color", BurnTheme.GREEN)
	if p.credits != _last_credits:
		_last_credits = p.credits
		_credit_punch = 1.0
	_credits.text = GameConfig.grouped(p.credits)
	_credit_punch = maxf(0.0, _credit_punch - dt * 6.0)
	_credits.scale = Vector2.ONE * (1.0 + 0.22 * _credit_punch)
	_burn.level = p.burn_level
	_burn.fill = p.burn_progress()
	_burn.pulse = maxf(0.0, _burn.pulse - dt * 2.5)
	_burn.time = run.time
	_burn.queue_redraw()
	if _missions_card:
		_missions_open -= dt
		_check_t -= dt
		if _check_t <= 0.0:
			_check_t = 0.25
			_refresh_missions()
		var want := 1.0 if _missions_open > 0.0 else 0.0
		_missions_card.modulate.a = move_toward(_missions_card.modulate.a, want, dt * 3.0)
		_missions_card.visible = _missions_card.modulate.a > 0.01 and not finished_run and not _paused
		for c in _toasts.get_children():
			var age: float = c.get_meta("age", 0.0) + dt
			c.set_meta("age", age)
			c.modulate.a = clampf(minf(age * 4.0, (4.2 - age) * 2.0), 0.0, 1.0)
			c.position.x = -40.0 * (1.0 - clampf(age * 4.0, 0.0, 1.0))
			if age > 4.2:
				c.queue_free()


func _best() -> int:
	match run.mode:
		"daily":
			return Progress.daily_best(str(config.get("date", "")))
		"endless":
			return Progress.best_distance(run.pace, run.lanes_on)
	return 0


func _refresh_missions() -> void:
	var p := run.pilot(me)
	if p == null:
		return
	var snap := Missions.snapshot(run, p)
	for i in missions.size():
		var m: Dictionary = missions[i]
		var row: Dictionary = _mission_rows[i]
		var amount := Missions.progress(m, snap, float(m.banked))
		var done := amount >= float(m.target)
		(row.prog as Label).text = Missions.progress_text(m, amount)
		(row.tick as Tick).on = done
		(row.tick as Tick).queue_redraw()
		(row.text as Label).add_theme_color_override("font_color", BurnTheme.GREEN if done else BurnTheme.TEXT)
		if done and not bool(m.done):
			m["done"] = true
			_mission_toast(Missions.describe(m))
			_missions_open = maxf(_missions_open, 4.0)
			LGPlaytest.event("mission", {"id": str(m.id), "distance": int(p.x)})


func _mission_toast(text: String) -> void:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "HudPanel"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var t := Tick.new()
	t.on = true
	t.custom_minimum_size = Vector2(22, 22)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	row.add_child(BurnTheme.label("MISSION DONE:  " + text.to_upper(), 18, BurnTheme.GREEN, BurnTheme.spaced(BurnTheme.heading(), 2), 4))
	chip.modulate.a = 0.0
	_toasts.add_child(chip)


func _sync_party(_dt: float) -> void:
	var leader := run.target()
	_party_top.text = "%s · %s" % [Zones.display_name(run.zone()).to_upper(), GameConfig.meters(run.cam_x)]
	var worst := 0.0
	for p in run.pilots:
		var row: Dictionary = _party_rows.get(p.id, {})
		if row.is_empty():
			continue
		var s: Label = row.state
		var wins := int(row.wins)
		if p.state == Pilot.State.OUT:
			s.text = "OUT"
			s.add_theme_color_override("font_color", BurnTheme.DIM)
			(row.name as Label).modulate.a = 0.5
		elif p.ahead < -Run.PARTY_EDGE * 0.55:
			s.text = "AT THE EDGE"
			s.add_theme_color_override("font_color", BurnTheme.RED)
		elif p.stun > 0.0:
			s.text = "STUNNED"
			s.add_theme_color_override("font_color", BurnTheme.GOLD)
		elif p == leader and run.alive_count() > 1:
			s.text = "LEADING" if wins == 0 else "%d WIN%s · LEADING" % [wins, "" if wins == 1 else "S"]
			s.add_theme_color_override("font_color", BurnTheme.ORANGE_HOT)
		else:
			s.text = "%d WIN%s" % [wins, "" if wins == 1 else "S"] if wins > 0 else "FLYING"
			s.add_theme_color_override("font_color", BurnTheme.DIM.lightened(0.3))
		# The red glow at the left edge follows this screen's own pilots.
		if p.alive() and (p.id == me or not p.bot and (config.get("local", {}) as Dictionary).has(p.id)):
			worst = maxf(worst, clampf((-p.ahead - Run.PARTY_EDGE * 0.45) / (Run.PARTY_EDGE * 0.55), 0.0, 1.0))
	_edge.amount = lerpf(_edge.amount, worst, 0.15)
	_edge.queue_redraw()


func _sync_tip(p: Pilot, dt: float) -> void:
	var room := run.course.room_at(p.x)
	var text := room.tip if room else ""
	if text != "" and text != _tip_text:
		_tip_text = text
		_set_tip(text)
		_tip_t = 7.0
	_tip_t -= dt
	var want := 1.0 if _tip_t > 0.0 and not finished_run else 0.0
	_tip_panel.modulate.a = move_toward(_tip_panel.modulate.a, want, dt * 3.0)
	_tip_panel.visible = _tip_panel.modulate.a > 0.01 and not _paused
	if _tip_panel.visible:
		_hints_t = minf(_hints_t, 0.0)


## Fills the tip, with each [action] shown as its button.
func _set_tip(text: String) -> void:
	_tip.clear()
	_tip.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var router := get_node_or_null("/root/LGInput")
	var rest := text
	while true:
		var a := rest.find("[")
		var b := rest.find("]", a + 1) if a >= 0 else -1
		if a < 0 or b < 0:
			_tip.add_text(rest)
			break
		_tip.add_text(rest.substr(0, a))
		var action := rest.substr(a + 1, b - a - 1)
		var tex: Texture2D = router.glyph_for_action(action) if router and InputMap.has_action(action) else null
		if tex:
			_tip.add_image(tex, 36, 36, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		else:
			_tip.push_color(BurnTheme.ORANGE_HOT)
			_tip.add_text(router.label_for_action(action) if router and InputMap.has_action(action) else action)
			_tip.pop()
		rest = rest.substr(b + 1)
	_tip.pop()


func _sync_gadgets(p: Pilot) -> void:
	for g in _gadget_labels:
		var used := false
		match g:
			"shield":
				used = p.shield <= 0
			"reboot":
				used = p.reboots <= 0
			"head_start":
				used = p.rocket <= 0.0
		(_gadget_labels[g] as Control).modulate.a = 0.35 if used else 1.0


## Lanes with something in them over the next moment, for Lane hints.
func _lane_danger(p: Pilot) -> Array:
	var out := [false, false, false]
	var ahead := run.speed_now * HINT_AHEAD
	for h in run.hazards_between(p.x + 1.0, p.x + ahead):
		if h.dead:
			continue
		for s in h.shapes_at(run.time + 0.4, run):
			var la := float(s[6])
			var lb := float(s[7])
			for l in 3:
				if l >= minf(la, lb) - 0.4 and l <= maxf(la, lb) + 0.4:
					out[l] = true
	return out


# --- Call-outs ----------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	match str(e.type):
		"room":
			var r: RoomGen = null
			for room in run.course.rooms:
				if room.index == int(e.room):
					r = room
			if r and r.tags.has("entry") and not r.tags.has("start"):
				_show_zone(str(r.tags.entry))
		"near":
			if int(e.pilot) == me:
				var what := str(e.what)
				var col := BurnTheme.burn_color(int(e.level))
				var at := _pilot_at(run.pilot(me), 2.0)
				_popup(NEAR_WORDS.get(what, "CLOSE"), at, col, NEAR_SIZE.get(what, 32), "+%d" % int(e.points))
				if bool(e.get("up", false)):
					_popup("BURN ×%d" % int(e.level), at + Vector2(40, -64), col, 56, "", 1.6)
					if _burn:
						_burn.pulse = 1.0
		"burn_lost":
			if int(e.pilot) == me:
				_popup("BURN LOST", _pilot_at(run.pilot(me), 1.6), BurnTheme.DIM, 24)
		"knock":
			if int(e.pilot) == me:
				_popup("SORRY!", _world_at(Vector3(float(e.x), 2.6, RunView.lane_z(float(e.lane)))), BurnTheme.TEXT, 20)
		"smash":
			if int(e.pilot) == me:
				_popup("SMASH", _world_at(Vector3(float(e.x), float(e.y) + 1.5, RunView.lane_z(float(e.lane)))), BurnTheme.GOLD, 30, "+%d" % int(e.get("credits", 0)))
		"vehicle":
			if int(e.pilot) == me:
				_banner_title.text = Zones.VEHICLE_NAMES.get(str(e.vehicle), "Ride").to_upper() + "!"
				_banner_sub.text = "IT TAKES THE NEXT HIT"
				_banner_t = 2.4
		"vehicle_lost":
			if int(e.pilot) == me:
				_popup("WRECKED", _pilot_at(run.pilot(me), 2.0), BurnTheme.ORANGE, 30)
		"shield", "armour", "reboot":
			if int(e.pilot) == me:
				_popup({"shield": "SHIELD", "armour": "ARMOUR", "reboot": "REBOOT"}[str(e.type)], _pilot_at(run.pilot(me), 2.2), BurnTheme.CYAN, 36)
		"stun":
			if int(e.pilot) == me:
				_popup("STUNNED", _pilot_at(run.pilot(me), 2.2), BurnTheme.GOLD, 30)
		"out":
			var p := run.pilot(int(e.pilot))
			if p:
				_popup("%s IS OUT" % p.name.to_upper(), Vector2(_root.size.x * 0.5, _root.size.y * 0.32), party_color(_pilot_index(p.id)), 34, "", 1.8)
		"rocket_end":
			if int(e.pilot) == me:
				_popup("OFF YOU GO", _pilot_at(run.pilot(me), 2.0), BurnTheme.ORANGE_HOT, 30)
		"finish":
			if int(e.get("pilot", me)) == me:
				var t := float(e.time)
				var medal := Courses.medal_for(str(config.get("course", "")), t)
				_banner_title.text = "FINISH"
				_banner_sub.text = GameConfig.time_text(t) + ("  ·  " + str(Courses.MEDAL_NAMES[medal]).to_upper() if medal != "" else "")
				_banner_t = 3.0


func _pilot_at(p: Pilot, up: float) -> Vector2:
	if p == null:
		return Vector2(_root.size.x * 0.3, _root.size.y * 0.5)
	return _world_at(Vector3(p.x, p.y + up, RunView.lane_z(p.lane)))


func _world_at(at: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2(_root.size.x * 0.3, _root.size.y * 0.5)
	return camera.unproject_position(at)


func _show_zone(zone: String) -> void:
	var info := Zones.info(zone)
	_banner_title.text = str(info.name).to_upper()
	_banner_sub.text = str(info.get("floor", "")).to_upper()
	_banner_t = 3.2


## A word that pops by the pilot and drifts up.
func _popup(text: String, at: Vector2, color: Color, size := 30, extra := "", life := 1.15) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := BurnTheme.label(text, size, color, BurnTheme.italic(BurnTheme.heading(), 3), maxi(6, size / 5))
	box.add_child(l)
	if extra != "":
		var x := BurnTheme.label(extra, int(size * 0.55), BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 1), 5)
		x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_child(x)
	_popups.add_child(box)
	var s := box.get_combined_minimum_size()
	box.size = s
	box.pivot_offset = s * 0.5
	box.position = at - s * 0.5
	# Several at once stack upwards instead of piling on each other.
	for c in _popups.get_children():
		if c != box and absf(c.position.x - box.position.x) < 120.0 and absf(c.position.y - box.position.y) < s.y:
			box.position.y = c.position.y - s.y
	box.set_meta("age", 0.0)
	box.set_meta("life", life)
	box.scale = Vector2.ONE * 1.45


func _sync_popups(dt: float) -> void:
	for c in _popups.get_children():
		var age: float = c.get_meta("age", 0.0) + dt
		var life: float = c.get_meta("life", 1.15)
		c.set_meta("age", age)
		c.position.y -= dt * 34.0
		var punch := clampf(age / 0.12, 0.0, 1.0)
		c.scale = Vector2.ONE * lerpf(1.45, 1.0, 1.0 - pow(1.0 - punch, 3.0))
		c.modulate.a = clampf((life - age) * 3.0, 0.0, 1.0)
		if age > life:
			c.queue_free()


# --- Warnings and tags (drawn) ------------------------------------------------

func _draw_overlay() -> void:
	if camera == null or finished_run:
		return
	_draw_warnings()
	_draw_ghost_tags()
	if run.mode == "party":
		_draw_name_tags()


## Warnings at the right edge for what's coming: seekers track you, then
## lock; lasers charge. Red in your lane, amber in the others.
func _draw_warnings() -> void:
	var w := _overlay.size.x
	var p := run.pilot(me)
	var my_lane := p.lane_to if p else 1
	var font := BurnTheme.spaced(BurnTheme.heading(), 2)
	var slot := 0
	for h in run.hazards:
		var warn: Dictionary = h.warning()
		if warn.is_empty():
			continue
		var lane := int(warn.lane)
		var mine := lane == my_lane or not run.lanes_on or run.mode == "party"
		var sp := camera.unproject_position(Vector3(camera.position.x + 8.0, float(warn.y) + 0.9, RunView.lane_z(float(lane))))
		var y := clampf(sp.y, 160.0, _overlay.size.y - 120.0)
		var x := w - 52.0
		var col := BurnTheme.RED if mine else BurnTheme.GOLD
		var locked := bool(warn.get("locked", false))
		var pulse := 1.0
		if not _steady and not locked:
			pulse = 0.78 + 0.22 * sin(run.time * 7.0 + slot)
		var r := 25.0
		draw_glow(_overlay, Vector2(x, y), r + 10.0, Color(col, 0.25 * pulse))
		_overlay.draw_circle(Vector2(x, y), r, Color(0.05, 0.03, 0.06, 0.85))
		_overlay.draw_arc(Vector2(x, y), r, 0, TAU, 40, Color(col, pulse), 4.0, true)
		var t := clampf(float(warn.get("t", 0.0)), 0.0, 1.0)
		if locked:
			t = 1.0
		_overlay.draw_arc(Vector2(x, y), r - 7.0, -PI * 0.5, -PI * 0.5 + TAU * t, 32, Color(col, 0.9), 5.0, true)
		_overlay.draw_string(font, Vector2(x - 7, y + 11), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
		var where := "YOUR LANE" if mine and run.lanes_on else ("%s LANE" % LANE_NAMES[clampi(lane, 0, 2)])
		if not run.lanes_on:
			where = "INCOMING"
		var text := "%s · %s" % [KIND_NAMES.get(str(warn.kind), "DANGER"), "LOCKED" if locked else where]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var box := Rect2(x - r - 18 - tw - 24, y - 16, tw + 24, 32)
		_overlay.draw_rect(box, Color(0.04, 0.03, 0.07, 0.82))
		_overlay.draw_rect(Rect2(box.position, Vector2(4, box.size.y)), col)
		_overlay.draw_string(font, Vector2(box.position.x + 14, y + 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col.lightened(0.35))
		slot += 1


static func draw_glow(c: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	for i in 4:
		c.draw_circle(at, r * (1.0 + i * 0.18), Color(col, col.a * (1.0 - i * 0.25)))


func _draw_ghost_tags() -> void:
	var font := BurnTheme.spaced(BurnTheme.heading(), 2)
	var p := run.pilot(me)
	for e in _ghosts:
		var gp: Pilot = e.pilot
		var g: Ghost = e.ghost
		if gp.x == 0.0 and gp.y == 0.0:
			continue
		var tag := "%s · %s" % [str(e.tag).to_upper(), GameConfig.meters(g.distance) if run.mode != "course" else GameConfig.time_text(g.time)]
		var sp := camera.unproject_position(Vector3(gp.x, gp.y + 2.3, RunView.lane_z(gp.lane)))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var col := BurnTheme.CYAN
		if sp.x > _overlay.size.x - 40.0 and p:
			# Ahead, off screen: say how far.
			var ahead := "%s +%s" % [str(e.tag).to_upper(), GameConfig.meters(gp.x - p.x)]
			tw = font.get_string_size(ahead, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var y := clampf(sp.y, 150.0, _overlay.size.y - 160.0)
			var box := Rect2(_overlay.size.x - tw - 120, y - 14, tw + 20, 28)
			_overlay.draw_rect(box, Color(0.02, 0.06, 0.1, 0.8))
			_overlay.draw_rect(box, Color(col, 0.7), false, 2.0)
			_overlay.draw_string(font, box.position + Vector2(10, 20), ahead, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
			continue
		if sp.x < -60.0:
			continue
		var box := Rect2(sp.x - tw * 0.5 - 10, sp.y - 26, tw + 20, 26)
		_overlay.draw_rect(box, Color(0.02, 0.06, 0.1, 0.7))
		_overlay.draw_rect(box, Color(col, 0.6), false, 2.0)
		_overlay.draw_string(font, box.position + Vector2(10, 19), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


func _draw_name_tags() -> void:
	var font := BurnTheme.spaced(BurnTheme.heading(), 2)
	# Pilots flying close together stack their tags instead of covering them.
	var placed: Array[Rect2] = []
	for i in run.pilots.size():
		var p: Pilot = run.pilots[i]
		if p.state == Pilot.State.OUT:
			continue
		var sp := camera.unproject_position(Vector3(p.x, p.y + 2.3, RunView.lane_z(p.lane)))
		var col := party_color(i)
		var text := p.name.to_upper()
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var box := Rect2(sp.x - tw * 0.5 - 10, sp.y - 28, tw + 20, 26)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if other.grow(1.0).intersects(box):
					box.position.y = other.position.y - box.size.y - 3
					moved = true
		placed.append(box)
		_overlay.draw_rect(box, Color(col, 0.92))
		_overlay.draw_string(font, box.position + Vector2(10, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BurnTheme.MIDNIGHT)
		if p.id == me and run.pilots.size() > 1:
			var tip := sp + Vector2(0, 6)
			_overlay.draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -8), tip + Vector2(7, -8), tip]), Color(col, 0.92))


# --- From the scene -----------------------------------------------------------

## A ghost to tag (RunScene adds them).
func add_ghost(p: Pilot, tag: String, g: Ghost) -> void:
	_ghosts.append({"pilot": p, "tag": tag, "ghost": g})
	if _mode_line:
		_mode_line.text = _mode_text()


## Paused: the menu covers the run, so the cards step aside until it closes.
func set_paused(on: bool) -> void:
	if on:
		_hints_t = 0.0
	_paused = on
	for c in [_card, _toasts, _gadgets, _lanes, _party_card, _party_top]:
		if c:
			c.visible = not on and not finished_run
	for c in [_missions_card, _tip_panel, _hints, _restart_hint]:
		if c and on:
			c.visible = false
	_overlay.visible = not on


## The run's over: clear the play-time bits for the results.
func set_finished(on: bool) -> void:
	finished_run = on
	for c in [_card, _missions_card, _toasts, _tip_panel, _hints, _restart_hint, _gadgets, _banner]:
		if c:
			c.visible = not on
	if _lanes:
		_lanes.visible = not on
	_banner_t = 0.0
	_overlay.queue_redraw()


## A party round's winner in the middle of the screen, and the wins so far.
func show_round(winner: int, wins: Dictionary, round: int, champion := -1) -> void:
	for c in _center.get_children():
		c.queue_free()
	var p := run.pilot(winner)
	var name := p.name.to_upper() if p else "NOBODY"
	var col := party_color(_pilot_index(winner)) if p else BurnTheme.TEXT
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(panel)
	var col_box := VBoxContainer.new()
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col_box.add_theme_constant_override("separation", 8)
	panel.add_child(col_box)
	var head := BurnTheme.label("ROUND %d" % round if champion < 0 else "LAST ONE FLYING", 20, BurnTheme.CYAN, BurnTheme.spaced(BurnTheme.heading(), 5), 4)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_box.add_child(head)
	var big := BurnTheme.label(("%s WINS THE RACE" if champion >= 0 else "%s TAKES IT") % name, 46, col, BurnTheme.italic(BurnTheme.heading(), 3), 10)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_box.add_child(big)
	var line := []
	for q in run.pilots:
		line.append("%s %d" % [q.name.to_upper(), int(wins.get(q.id, 0))])
	var sub := BurnTheme.label("   ".join(line), 18, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.narrow(), 2), 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_box.add_child(sub)
	if champion < 0:
		var next := BurnTheme.label("NEXT ROUND COMING UP", 16, BurnTheme.DIM.lightened(0.2), BurnTheme.spaced(BurnTheme.heading(), 4), 3)
		next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_box.add_child(next)
	if _party_card:
		_party_card.visible = true


## Kept for older callers: the results panel shows the end of a run now.
func show_result(_r: Dictionary) -> void:
	set_finished(true)


# --- Drawn pieces -------------------------------------------------------------

## The Burn meter: five slanted segments, x1 to x5, filling towards the next.
class BurnMeter:
	extends Control
	var level := 1
	var fill := 0.0
	var pulse := 0.0
	var time := 0.0
	var steady := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := BurnTheme.italic(BurnTheme.heading(), 2)
		var col := BurnTheme.burn_color(level)
		var label := "BURN ×%d" % level
		var fs := 26 + int(6.0 * pulse)
		draw_string_outline(font, Vector2(0, 33), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(0, 33), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var x0 := 176.0
		var seg := (size.x - x0) / 5.0
		var h := 18.0
		var y := 14.0
		for i in 5:
			var a := x0 + i * seg
			var poly := PackedVector2Array([Vector2(a + 6, y), Vector2(a + seg - 2, y), Vector2(a + seg - 8, y + h), Vector2(a, y + h)])
			draw_colored_polygon(poly, Color(0, 0, 0, 0.5))
			var amount := 1.0 if i < level - 1 else (fill if i == level - 1 and level < 5 else (1.0 if level >= 5 and i == 4 else 0.0))
			if i == level - 1 and level >= 5:
				amount = 1.0
			if amount > 0.0:
				var c := BurnTheme.burn_color(i + 1)
				var w := (seg - 8) * amount
				var fp := PackedVector2Array([Vector2(a + 6, y), Vector2(a + 6 + w, y), Vector2(a + w, y + h), Vector2(a, y + h)])
				draw_colored_polygon(fp, c)
				if i == level - 1:
					var glow := 0.35 + 0.25 * pulse
					draw_colored_polygon(fp, Color(1, 1, 1, glow * 0.4))
			draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(col, 0.55), 1.5, true)


## Which lane you're in (with Lane hints, which lanes have trouble coming).
class LaneMeter:
	extends Control
	var lane := 1.0
	var target := 1
	var hints := false
	var danger := [false, false, false]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := BurnTheme.spaced(BurnTheme.heading(), 3)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.07, 0.62))
		draw_rect(Rect2(Vector2.ZERO, size), Color(BurnTheme.CYAN, 0.16), false, 1.0)
		draw_string(font, Vector2(14, 24), "LANE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BurnTheme.TEXT)
		if hints:
			draw_string(font, Vector2(size.x - 78, 24), "HINTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BurnTheme.CYAN)
		var x0 := 86.0
		var x1 := size.x - 16.0
		for l in 3:
			# Far at the top, near at the bottom, as the lanes sit on screen.
			var y := 44.0 + (2 - l) * 26.0
			var on := target == l
			draw_string(font, Vector2(14, y + 6), ["NEAR", "MID", "FAR"][l], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BurnTheme.TEXT if on else BurnTheme.DIM)
			draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.18), 6.0)
			if hints and danger[l]:
				draw_line(Vector2(x0 + (x1 - x0) * 0.45, y), Vector2(x1, y), Color(BurnTheme.RED, 0.85), 6.0)
		var py := 44.0 + (2.0 - lane) * 26.0
		var px := x0 + 26.0
		draw_line(Vector2(x0, py), Vector2(px, py), BurnTheme.ORANGE, 6.0)
		RunHud.draw_glow(self, Vector2(px, py), 10.0, Color(BurnTheme.ORANGE, 0.25))
		draw_circle(Vector2(px, py), 9.0, BurnTheme.ORANGE_HOT)


## A mission's tick box.
class Tick:
	extends Control
	var on := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		if on:
			draw_rect(r, BurnTheme.GREEN)
			var s := size
			draw_polyline(PackedVector2Array([Vector2(s.x * 0.22, s.y * 0.52), Vector2(s.x * 0.42, s.y * 0.72), Vector2(s.x * 0.8, s.y * 0.28)]), BurnTheme.MIDNIGHT, 3.0, true)
		else:
			draw_rect(r, Color(1, 1, 1, 0.75), false, 2.0)


## A credit chip: a gold hexagon.
class CreditIcon:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.48
		var pts := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in 6:
			var a := PI / 6.0 + i * TAU / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
			inner.append(c + Vector2(cos(a), sin(a)) * r * 0.55)
		draw_colored_polygon(pts, BurnTheme.GOLD)
		draw_colored_polygon(inner, BurnTheme.GOLD.darkened(0.35))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.95, 0.7), 1.5, true)


## A red glow at the left edge as your pilot nears it in a party race.
class EdgeGlow:
	extends Control
	var amount := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if amount <= 0.01:
			return
		var w := 90.0
		var h := size.y
		var cols := PackedColorArray([Color(BurnTheme.RED, 0.55 * amount), Color(BurnTheme.RED, 0.0), Color(BurnTheme.RED, 0.0), Color(BurnTheme.RED, 0.55 * amount)])
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), cols)
