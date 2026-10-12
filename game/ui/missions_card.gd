class_name MissionsCard
extends PanelContainer
## The three missions, your rank and what the next rank opens, for the
## title, the pause menu and the results. `live` (a run's snapshot, see
## Missions.snapshot) shows a run's progress on top of what's banked.

var live := {}
var width := 470.0
var _col: VBoxContainer


func _ready() -> void:
	theme_type_variation = "GlassPanel"
	custom_minimum_size.x = width
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 8)
	add_child(_col)
	refresh()


func refresh() -> void:
	if _col == null:
		return
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var rank := Progress.rank()
	var head := HBoxContainer.new()
	_col.add_child(head)
	var t := BurnTheme.label("MISSIONS", 20, BurnTheme.TEXT, BurnTheme.spaced(BurnTheme.heading(), 4), 4)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(BurnTheme.label("RANK %d · %s" % [rank, Missions.title(rank).to_upper()], 18, BurnTheme.ORANGE, BurnTheme.spaced(BurnTheme.heading(), 3), 4))
	# Three pips: missions done towards the next rank.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	_col.add_child(pips)
	for i in Missions.PER_RANK:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2((width - 60) / Missions.PER_RANK, 6)
		r.color = BurnTheme.ORANGE if i < Progress.rank_progress() else Color(1, 1, 1, 0.14)
		pips.add_child(r)
	for m in Progress.missions():
		var amount := Missions.progress(m, live, float(m.banked)) if not live.is_empty() else float(m.banked)
		var done := amount >= float(m.target)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_col.add_child(row)
		var tick := RunHud.Tick.new()
		tick.on = done
		tick.custom_minimum_size = Vector2(22, 22)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tick)
		var text := BurnTheme.label(Missions.describe(m), 20, BurnTheme.GREEN if done else BurnTheme.TEXT, BurnTheme.narrow(), 3)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = width - 190
		row.add_child(text)
		var prog := BurnTheme.label(Missions.progress_text(m, amount), 18, BurnTheme.ORANGE_HOT, BurnTheme.narrow(), 3)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(prog)
	var next := Unlocks.next_after(rank)
	if not next.is_empty():
		var l := BurnTheme.label("Rank %d opens the %s" % [int(next.rank), str(next.name)], 17, BurnTheme.CYAN, BurnTheme.narrow(), 3)
		_col.add_child(l)
