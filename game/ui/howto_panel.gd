class_name HowToPanel
extends Control
## How to play: a few pages on flying, the lanes, Burn, the robots you can
## ride, what's out to get you, missions and gadgets, party races and the
## controls. Opened from the title and the pause menu; the title's copy can
## also start the first flight again.

signal closed
signal first_flight

const CONTROLS := [
	["fly", "Fly (hold). On a robot: its move"],
	["lane_back", "One lane back (farther)"],
	["lane_forward", "One lane forward (nearer)"],
	["restart", "Fly again (after a crash, or paused)"],
	["pause", "Pause"],
]

## Shows a button for the first flight on the last page.
var offer_first_flight := false

var _title: Label
var _body: Label
var _extra: VBoxContainer
var _count: Label
var _prev: Button
var _next: Button
var _again: Button
var _page := 0


static func pages() -> Array:
	return [
		{"title": "Hold to fly", "body":
			"Hold Fly and the prototype lifts you. Let go and you fall. That's the whole thing: the tower scrolls past at its own speed, and you only choose how high to be.\n\nOne touch of a zapper, a laser, a seeker or a drone and the run's over. You tumble, slide, and the distance counts on while you do."},
		{"title": "Three lanes deep", "body":
			"The tower is three lanes deep: near, middle and far. Lane back and lane forward move you one lane at a time, and only the pilot moves, never the view.\n\nA zapper fills its lane; the credits are often in the next one. Things in your lane are lit full, the others a little dimmer. In Classic, lanes are off and it's one lane and one button."},
		{"title": "Burn", "body":
			"Fly close to danger to build Burn: skim past a zapper in the next lane (SKIM), slip by one close (CLOSE), closer (RAZOR), or change lane through a gap as it closes (THREAD).\n\nBurn goes from x1 to x5 and multiplies every credit you pick up. Touch the floor or get hit and it's gone. Safe runs go far; burning runs pay."},
		{"title": "Ride a robot", "body":
			"Grab a crate to hijack one of Halberd's robots. It takes the next hit for you, and Fly does its move: the Raptor runs and jumps (and stomps drones), the Shell flips between floor and ceiling, the Eye hops, and the Gunner hovers and fires ahead."},
		{"title": "What's out there", "body":
			"Zappers fill a lane, lean across two or turn slowly. Lasers charge across one lane, then fire. Seekers show at the right edge in their lane, lock on to your height, then fire: change lane or height late. Shutters slam across a lane. Drones hover and dash; walkers patrol the floor.\n\nThe staff are harmless. Your exhaust knocks them flat. They get up again."},
		{"title": "Missions and the hangar", "body":
			"You always have three missions. Finish three and your rank goes up; ranks open Kestrel Lift's other five prototypes and new suits.\n\nCredits from every run go in the bank. Spend them in the Hangar on suits and gadgets, and take two gadgets into each run: a magnet, a shield, a head start, a seeker jammer, lane hints or a reboot."},
		{"title": "More ways to fly", "body":
			"The Daily Flight is the same course for everyone, all day, on the day's prototype. Your best of the day flies beside you as a ghost.\n\nCourses are thirty short runs against the clock, five in each zone, with medals. Burn makes you faster, so the gold takes nerve.\n\nParty: Last One Flying. Everyone flies the same course and the screen follows the leader. Fall off the left edge and you're out. First to three rounds wins."},
		{"title": "Controls", "body": "", "controls": true},
	]


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.04, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	panel.custom_minimum_size = Vector2(800, 520)
	center.add_child(panel)
	LGScreenFit.center(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = LGUi.label("", "HeaderMedium")
	col.add_child(_title)
	_body = LGUi.label("")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 740
	_body.add_theme_font_size_override("font_size", 23)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 8)
	scroll.add_child(_extra)
	_count = LGUi.label("", "CapsLabel")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_prev = LGUi.button("Back", _go.bind(-1), 220)
	row.add_child(_prev)
	_again = LGUi.button("First flight", _on_first_flight, 260)
	row.add_child(_again)
	_next = LGUi.button("Next", _go.bind(1), 220)
	row.add_child(_next)


func open() -> void:
	_page = 0
	visible = true
	_show_page()
	BurnTheme.focus(_next)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func show_page(i: int) -> void:
	_page = clampi(i, 0, pages().size() - 1)
	visible = true
	_show_page()


func _go(dir: int) -> void:
	_page += dir
	if _page >= pages().size():
		close()
		return
	_page = maxi(_page, 0)
	_show_page()
	BurnTheme.focus((_prev if dir < 0 and _prev.visible else _next))


func _show_page() -> void:
	var all := pages()
	var page: Dictionary = all[_page]
	_title.text = page.title
	_body.text = page.body
	_body.visible = page.body != ""
	for c in _extra.get_children():
		_extra.remove_child(c)
		c.queue_free()
	var controls: bool = page.get("controls", false)
	(_extra.get_parent() as Control).visible = controls
	if controls:
		for pair in CONTROLS:
			_extra.add_child(ActionPrompt.make(pair[0], pair[1], 40))
	_count.text = "%d / %d" % [_page + 1, all.size()]
	_prev.visible = _page > 0
	_again.visible = offer_first_flight and _page == all.size() - 1
	_next.text = "Done" if _page == all.size() - 1 else "Next"


func _on_first_flight() -> void:
	visible = false
	first_flight.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
