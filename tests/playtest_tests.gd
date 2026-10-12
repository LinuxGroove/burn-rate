extends RefCounted
## The play test recorder's note on a controller over a paused game, as on a
## handheld: the note and its on-screen keyboard take the pad, type while
## paused, and close without closing the pause menu behind them.


func test_playtest_note_pad(t) -> void:
	LGInput.extend_ui_actions()
	var dir := "user://test_playtest_pad"
	LGPlaytestPack._remove(dir)
	var p := LGPlaytest.setup(GameConfig.GAME_ID, GameConfig.PLAYTEST)
	p.dir = dir
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	p.begin()
	# The game's screen comes after the recorder in the tree, as it does in play.
	var screen := Node.new()
	t.get_tree().root.add_child(screen)
	var menu := PadPauseMenu.new()
	screen.add_child(menu)
	menu.open()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	var note_button: Button = menu.find_children("*", "LGPlaytestButton", true, false).front()
	note_button.grab_focus()
	await _pad(t, JOY_BUTTON_A)
	var note: LGPlaytestNote = p.find_children("*", "LGPlaytestNote", true, false).front()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	t.check(_focus_in(t, note), "Note this moment opens the note, which takes the pad")
	for i in 8:
		await _pad(t, [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP][i % 4])
	t.check(_focus_in(t, note), "the D-pad only moves round the note")
	for i in 3:
		await _pad(t, JOY_BUTTON_DPAD_UP)
	t.check(t.get_viewport().gui_get_focus_owner() == note.note, "up from the tags reaches the words")
	await _pad(t, JOY_BUTTON_A)
	var kb := OnScreenKeyboard.current()
	t.check(kb != null and _focus_in(t, kb), "A on the words opens the keyboard, which takes the pad")
	await _pad(t, JOY_BUTTON_A)
	await _pad(t, JOY_BUTTON_DPAD_RIGHT)
	await _pad(t, JOY_BUTTON_A)
	t.check(note.note.text == "qw", "the keyboard types while the game is paused")
	for i in 5:
		await _pad(t, JOY_BUTTON_DPAD_DOWN)
	t.check(_focus_in(t, kb), "the D-pad only moves round the keyboard")
	await _pad(t, JOY_BUTTON_B)
	t.check(note.note.text == "q", "B deletes a letter")
	await _pad(t, JOY_BUTTON_START)
	t.check(OnScreenKeyboard.current() == null, "Start closes the keyboard")
	t.check(menu.visible and is_instance_valid(note) and note.is_inside_tree(), "B and Start on the keyboard leave the note and the pause menu open")
	t.check(t.get_viewport().gui_get_focus_owner() == note.note, "the pad is back on the words")
	await _pad(t, JOY_BUTTON_DPAD_DOWN)
	t.check(_focus_in(t, note) and t.get_viewport().gui_get_focus_owner() != note.note, "and goes on down to the tags")
	await _pad(t, JOY_BUTTON_START)
	t.check(is_instance_valid(note) and note.is_inside_tree() and menu.visible, "Start on the note leaves the pause menu open")
	# Focus taken behind the note: the next press brings it back and does nothing else.
	(menu.find_children("*", "Button", true, false).front() as Button).grab_focus()
	await _pad(t, JOY_BUTTON_A)
	t.check(menu.visible and _focus_in(t, note), "a press with focus behind the note comes back to the note")
	note.note.grab_focus()
	await _pad(t, JOY_BUTTON_A)
	await _pad(t, JOY_BUTTON_B)
	await _pad(t, JOY_BUTTON_B)
	t.check(OnScreenKeyboard.current() == null and note.note.text == "", "B with nothing left to delete puts the keyboard away")
	t.check(t.get_viewport().gui_get_focus_owner() == note.note, "back on the words")
	await _pad(t, JOY_BUTTON_A)
	kb = OnScreenKeyboard.current()
	note.cancel_note()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	t.check(not is_instance_valid(kb) and OnScreenKeyboard.current() == null, "the keyboard goes when its note does")
	t.check(menu.visible and t.get_tree().paused and _focus_in(t, menu), "back on the pause menu, still paused")
	note_button.grab_focus()
	await _pad(t, JOY_BUTTON_A)
	note = p.find_children("*", "LGPlaytestNote", true, false).front()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	await _pad(t, JOY_BUTTON_B)
	t.check(not is_instance_valid(note) or not note.is_inside_tree(), "B puts the note away")
	t.check(menu.visible and t.get_tree().paused and _focus_in(t, menu), "and leaves the pause menu open")
	menu.close()
	await t.get_tree().process_frame
	t.check(not t.get_tree().paused, "the game carries on")
	screen.queue_free()
	p._end("quit", {})
	p.queue_free()
	await t.get_tree().process_frame
	LGPlaytestPack._remove(dir)


## Presses and lets go of a button on the first controller.
func _pad(t, button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = down
		Input.parse_input_event(ev)
		await t.get_tree().process_frame
		await t.get_tree().process_frame
	# The input router drops a second press of the same direction this soon.
	await t.get_tree().create_timer(LGInput.NAV_DEBOUNCE_MSEC / 1000.0).timeout


func _focus_in(t, node: Node) -> bool:
	var f: Control = t.get_viewport().gui_get_focus_owner()
	return f != null and is_instance_valid(node) and node.is_ancestor_of(f)


## A pause menu like the game's own: it pauses the game, keeps working
## while paused and closes on B or Start.
class PadPauseMenu extends Control:
	var col := VBoxContainer.new()

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(col)
		col.add_child(LGUi.button("Carry on", close, 440))
		col.add_child(LGPlaytestButton.make(440))

	func open() -> void:
		visible = true
		get_tree().paused = true
		LGUi.focus_first(col)

	func close() -> void:
		visible = false
		get_tree().paused = false

	func _unhandled_input(event: InputEvent) -> void:
		if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
			get_viewport().set_input_as_handled()
			close()
