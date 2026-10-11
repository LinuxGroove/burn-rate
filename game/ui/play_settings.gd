class_name PlaySettings
extends VBoxContainer
## Burn Rate's own settings rows (pace, lanes or Classic, ghosts, rumble,
## tips, Reduce flashing, Calm background and detail), under the shared
## screen and sound rows. Used by the title's Settings and the pause menu.

const PACES := [["calm", "Calm"], ["normal", "Normal"], ["fast", "Fast"]]
const LANES := [[true, "Three lanes"], [false, "Classic (one lane)"]]
const DETAIL := [[0, "Low (handhelds)"], [1, "Medium"], [2, "High"]]
const WIDTH := 560

## Whether to include the shared rows (screen, sound, online, play tests).
var shared := true
## Locks the rows a run in progress can't change (pace and lanes).
var in_run := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_head("Flying")
	var pace := LGCycler.make("Pace", PACES, LGSettings.get_value("play", "pace", "normal"), _store.bind("play", "pace"), WIDTH)
	add_child(pace)
	var lanes := LGCycler.make("Lanes", LANES, LGSettings.get_value("play", "lanes", true), _store.bind("play", "lanes"), WIDTH)
	add_child(lanes)
	if in_run:
		var note := LGUi.label("Pace and lanes change from your next run.", "HintLabel")
		add_child(note)
	_row("Ghosts", SettingsPanel.ON_OFF, "play", "ghosts")
	_row("Rumble", SettingsPanel.ON_OFF, "play", "rumble")
	_row("Tips", SettingsPanel.ON_OFF, "tutorial", "hints")
	_head("Comfort")
	_row("Reduce flashing", SettingsPanel.ON_OFF, "comfort", "reduce_flashing")
	_row("Calm background", SettingsPanel.ON_OFF, "comfort", "calm_background")
	_row("Detail", DETAIL, "video", "detail")
	if shared:
		_head("Screen and sound")
		var panel := SettingsPanel.new()
		add_child(panel)


func _head(text: String) -> void:
	var l := LGUi.label(text.to_upper(), "CapsLabel")
	l.add_theme_constant_override("margin_top", 8)
	add_child(l)


func _row(label: String, options: Array, section: String, key: String) -> void:
	add_child(LGCycler.make(label, options, LGSettings.get_value(section, key), _store.bind(section, key), WIDTH))


static func _store(value: Variant, section: String, key: String) -> void:
	LGSettings.set_value(section, key, value)
	if section == "comfort" and key == "reduce_flashing":
		apply_flashing()


## Sets the global shader uniform zappers and lasers read (1 = steady).
static func apply_flashing() -> void:
	RenderingServer.global_shader_parameter_set("steady", 1.0 if bool(LGSettings.get_value("comfort", "reduce_flashing", false)) else 0.0)
