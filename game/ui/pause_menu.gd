class_name PauseMenu
extends Control
## The pause menu over a run: fly on, fly again, the missions, settings, how
## to play, Note this moment (play tests) and back to the title. Party races
## online and on LAN keep flying underneath.

var scene: RunScene
var _col: VBoxContainer
var _side: Control
var _page := "main"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	center.add_child(row)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	_col.custom_minimum_size.x = 420
	row.add_child(_col)
	_side = VBoxContainer.new()
	row.add_child(_side)
	main()


func _clear() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()


func main() -> void:
	_clear()
	_page = "main"
	var networked := scene != null and scene._networked()
	var title := LGUi.label("Menu" if networked else "Paused", "HeaderLarge")
	_col.add_child(title)
	if scene and scene.run:
		_col.add_child(LGUi.label(_where(), "CapsLabel"))
	var resume := LGUi.button("Fly on", close)
	resume.theme_type_variation = "HeroButton"
	_col.add_child(resume)
	_col.add_child(LGPlaytestButton.make(420))
	if not networked:
		_col.add_child(LGUi.button("Fly again", _restart))
	_col.add_child(LGUi.button("Settings", settings))
	_col.add_child(LGUi.button("How to play", _howto))
	var quit := LGUi.button("Back to the title", _quit)
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	if scene and scene.run and not scene.hud.missions.is_empty():
		var card := MissionsCard.new()
		card.live = Missions.snapshot(scene.run, scene.run.pilot(scene.me))
		_side.add_child(card)
	LGUi.focus_first(_col)


func _where() -> String:
	var run := scene.run
	var text := "%s · %s" % [Zones.display_name(run.zone()), GameConfig.meters(run.distance())]
	if run.mode == "course":
		text = "%s · %s" % [Courses.get_def(str(scene.config.get("course", ""))).name, GameConfig.time_text(run.time)]
	return text.to_upper()


func settings() -> void:
	_clear()
	_page = "settings"
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var s := PlaySettings.new()
	s.in_run = true
	_col.add_child(s)
	_col.add_child(LGUi.button("Back", main))
	LGUi.focus_first(_col)


func _howto() -> void:
	visible = false
	var panel := HowToPanel.new()
	get_parent().add_child(panel)
	panel.closed.connect(_on_howto_closed.bind(panel))
	panel.open()


func _on_howto_closed(panel: HowToPanel) -> void:
	panel.queue_free()
	visible = true
	main()


func _restart() -> void:
	scene.restart()


func _quit() -> void:
	scene.quit_to_title()


func close() -> void:
	queue_free()
	if scene:
		scene.on_pause_closed()


## The labels of the buttons on show, for tests.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _col.find_children("", "Button", true, false):
		if (b as Button).visible:
			out.append((b as Button).text)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _page == "main":
			close()
		else:
			main()
