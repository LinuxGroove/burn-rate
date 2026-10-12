class_name PartyBoard
extends CanvasLayer
## Last One Flying's own screens on top of the run: the countdown before a
## round, and the scoreboard after it (who took the round, everyone's round
## wins, when the next round starts), then the race's winner. [RunNet] adds
## one each round; it reads [member Session.party] and the run.

const FONT := preload("res://addons/linuxgroove/ui/fonts/Kenney Future.ttf")
const FONT_NARROW := preload("res://addons/linuxgroove/ui/fonts/Kenney Future Narrow.ttf")
const GOLD := Color(1.0, 0.82, 0.3)
const PIP_OFF := Color(1, 1, 1, 0.18)
## Seconds "Fly!" and the round label stay up after the countdown.
const GO_TIME := 1.2
const ORDINALS := ["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"]

var net: RunNet
var _root: Control
var _count: Label
var _sub: Label
var _panel: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _footer: Label
var _since_go := 0.0


func setup(p_net: RunNet) -> void:
	net = p_net
	layer = 30
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_sub = _label(FONT_NARROW, 34, Color(0.85, 0.95, 1.0))
	center.add_child(_sub)
	_count = _label(FONT, 120, Color.WHITE)
	center.add_child(_count)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DarkPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size.x = 640
	_panel.visible = false
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	_title = _label(FONT, 38, GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	col.add_child(_rows)
	_footer = _label(FONT_NARROW, 24, Color(0.85, 0.9, 1.0, 0.85))
	col.add_child(_footer)
	Session.party_changed.connect(_on_party_changed)
	_on_party_changed()


static func _label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## "Round 2 · first to 3 wins"
func round_text() -> String:
	var target := int(Session.party.get("target", net.config.get("target", 3)))
	return "Round %d   First to %d %s" % [net.round_no(), target, "win" if target == 1 else "wins"]


func _process(delta: float) -> void:
	if net == null:
		return
	match net.phase:
		RunNet.Phase.LOAD:
			_count.text = ""
			_sub.text = "Waiting for everyone..." if net.networked else round_text()
		RunNet.Phase.COUNT:
			_count.text = str(ceili(net.countdown))
			_sub.text = round_text()
			_count.modulate.a = 1.0
			_sub.modulate.a = 1.0
			_since_go = 0.0
		RunNet.Phase.FLY:
			_since_go += delta
			if _since_go < GO_TIME:
				_count.text = "Fly!"
				var a := clampf((GO_TIME - _since_go) / 0.4, 0.0, 1.0)
				_count.modulate.a = a
				_sub.modulate.a = a
			else:
				_count.text = ""
				_sub.text = ""
		RunNet.Phase.OVER:
			_count.text = ""
			_sub.text = ""
	if _panel.visible:
		_footer.text = footer_text()


func _on_party_changed() -> void:
	var party: Dictionary = Session.party
	if party.is_empty() or int(party.get("round_winner", -1)) == -1 or int(party.get("round", 0)) != net.round_no():
		_panel.visible = false
		return
	_title.text = title_text()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for row in standings():
		_rows.add_child(_row(row))
	_footer.text = footer_text()
	_panel.visible = true


## Who took the round, or the race.
func title_text() -> String:
	var party: Dictionary = Session.party
	var w := int(party.get("winner", -1))
	if w != -1:
		return "%s wins the race!" % _name(w)
	return "%s takes round %d" % [_name(int(party.get("round_winner", -1))), net.round_no()]


func footer_text() -> String:
	var left := ceili(Session.break_seconds_left())
	if int(Session.party.get("winner", -1)) != -1:
		return "Back to the lobby in %d" % left if left > 0 else "Back to the lobby..."
	return "Next round in %d" % left if left > 0 else "Next round..."


## Everyone in the race, most round wins first, then this round's places:
## [{"id", "name", "wins", "place", "color", "you", "bot"}].
func standings() -> Array:
	var wins: Dictionary = Session.party.get("wins", {})
	var out := []
	for p in net.run.pilots:
		out.append({
			"id": p.id, "name": p.name, "wins": int(wins.get(p.id, 0)), "place": p.place,
			"color": PilotLooks.resolve(p.look).main if not p.look.is_empty() else Packs.spec(p.pack).color, "you": p.id in net._own, "bot": p.bot,
		})
	out.sort_custom(_better)
	return out


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.wins) != int(b.wins):
		return int(a.wins) > int(b.wins)
	var pa := int(a.place) if int(a.place) > 0 else 99
	var pb := int(b.place) if int(b.place) > 0 else 99
	return pa < pb


func _name(id: int) -> String:
	var p := net.run.pilot(id)
	return p.name if p else "Nobody"


func _row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var swatch := ColorRect.new()
	swatch.color = r.color
	swatch.custom_minimum_size = Vector2(10, 34)
	row.add_child(swatch)
	var tags := []
	if r.you:
		tags.append("you")
	if r.bot:
		tags.append("bot")
	var name := _label(FONT_NARROW, 28, Color.WHITE)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.text = str(r.name) + ("  (%s)" % ", ".join(tags) if not tags.is_empty() else "")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var place := _label(FONT_NARROW, 24, Color(1, 1, 1, 0.7))
	place.text = ORDINALS[int(r.place)] if int(r.place) > 0 and int(r.place) < ORDINALS.size() else ""
	place.custom_minimum_size.x = 60
	row.add_child(place)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	pips.alignment = BoxContainer.ALIGNMENT_END
	pips.custom_minimum_size.x = 130
	var target := int(Session.party.get("target", 3))
	for i in target:
		pips.add_child(_pip(GOLD if i < int(r.wins) else PIP_OFF))
	row.add_child(pips)
	return row


static func _pip(color: Color) -> Control:
	var pip := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	pip.add_theme_stylebox_override("panel", box)
	pip.custom_minimum_size = Vector2(18, 18)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pip
