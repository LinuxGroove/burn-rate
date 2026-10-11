class_name GameAudio
extends RefCounted
## The game's sound outside the run's own effects: menu sounds, the music
## and the stingers, with nothing to set up. Every call is static:
##
##   GameAudio.ui("confirm")         a menu sound (see [constant UI])
##   GameAudio.music("title")        "title", "run", "party", or "" for none
##   GameAudio.intensity(3)          the run music's layers: 0 calm, 1 to 5 the Burn
##   GameAudio.party_level(2)        party music: 0 calm, 1 base, 2 lead, 3 everything
##   GameAudio.stinger("finish")     a jingle over the music (see [constant STINGERS])
##   GameAudio.muffle(true)          dull the music (paused, crashed)
##
## The run's music is stems that loop together in one
## [AudioStreamSynchronized]: x1 is drums and bass, the arp comes in at x2,
## the lead at x3 and everything at x5. Layers change on the beat. Music
## plays through the shared add-on's [code]LGAudio[/code] on the Music bus,
## and sounds on the SFX bus, so the audio settings apply; a limiter on the
## SFX bus keeps a busy room from distorting.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const UI_DIR := "res://assets/audio/ui/"
## A stem that's out.
const OFF := -60.0

## Menu sounds: name -> [file under assets/audio, volume dB, pitch jitter].
const UI := {
	"move": ["ui/move", -8.0, 0.04],
	"confirm": ["ui/confirm", -4.0, 0.0],
	"back": ["ui/back", -4.0, 0.0],
	"toggle": ["ui/toggle", -6.0, 0.03],
	"error": ["ui/error", -6.0, 0.0],
	"tick": ["ui/tick", -12.0, 0.05],
	"open": ["ui/open", -6.0, 0.0],
	"close": ["ui/close", -6.0, 0.0],
	"buy": ["sfx/ui_buy", -5.0, 0.0],
	"unlock": ["sfx/ui_unlock", -3.0, 0.0],
	"rank": ["sfx/ui_rank", -3.0, 0.0],
	"start": ["sfx/ui_start", -4.0, 0.0],
	"best": ["sfx/ui_best", -4.0, 0.0],
	"credits": ["sfx/credit_big", -8.0, 0.0],
}

## Jingles over the music, on the Music bus: name -> [sfx file, volume dB].
const STINGERS := {
	"finish": ["finish_stinger", -2.0],
	"round_over": ["round_over", -2.0],
	"run_over": ["run_over", -4.0],
}

## Tracks: their tempo, stems (files in assets/audio/music) and volume.
const TRACKS := {
	"title": {"bpm": 100.0, "stems": ["title"], "db": -1.0},
	"run": {"bpm": 128.0, "stems": ["run_pad", "run_drums", "run_bass", "run_arp", "run_lead", "run_hype"], "db": -2.0},
	"party": {"bpm": 136.0, "stems": ["party_base", "party_lead", "party_hype"], "db": -2.0},
}

## The run's stems (pad, drums, bass, arp, lead, hype) in dB at each level:
## 0 is calm (a run over, or paused), 1 to 5 the Burn.
const RUN_LAYERS := [
	[-2.0, OFF, OFF, -12.0, OFF, OFF],
	[0.0, 0.0, 0.0, OFF, OFF, OFF],
	[0.0, 0.0, 0.0, -6.0, OFF, OFF],
	[0.0, 0.0, 0.0, -3.0, 0.0, OFF],
	[0.0, 0.0, 0.0, 0.0, 0.0, -7.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
]
## Party stems (base, lead, hype): 0 calm, 1 the race, 2 someone's out,
## 3 the last two.
const PARTY_LAYERS := [
	[-14.0, -10.0, OFF],
	[0.0, OFF, OFF],
	[0.0, 0.0, OFF],
	[0.0, 0.0, 0.0],
]

## Loaded sounds by path.
static var _cache := {}
## Paths asked for that don't exist (tests check this stays empty).
static var missing: Array[String] = []
## Stingers started (for tests).
static var stingers_played := 0
static var _track := ""
static var _streams := {}
static var _started_usec := 0
static var _level := -1
static var _tweens := {}
static var _set_up := false
static var _lowpass: AudioEffectLowPassFilter
static var _muffled := false
static var _muffle_tween: Tween


# --- Sounds ---------------------------------------------------------------

## A sound from assets/audio by its short name ("sfx/credit", "ui/move",
## "music/run_drums"). Loops (names ending in _loop, ambiences and music)
## come back looping. Null, and noted in [member missing], when it's not there.
static func stream(short: String) -> AudioStream:
	var path := "res://assets/audio/%s.ogg" % short
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		if not path in missing:
			missing.append(path)
			push_warning("Audio: missing %s" % path)
		return null
	var s: AudioStream = load(path)
	var base := short.get_file()
	if s is AudioStreamOggVorbis and (base.ends_with("_loop") or base.begins_with("amb_") or short.begins_with("music/")):
		(s as AudioStreamOggVorbis).loop = true
	_cache[path] = s
	return s


## A sound effect by name (a file in assets/audio/sfx).
static func sfx(sfx_name: String) -> AudioStream:
	return stream("sfx/" + sfx_name)


## Plays a menu sound (see [constant UI]).
static func ui(ui_name: String) -> void:
	_ensure()
	var u: Array = UI.get(ui_name, [])
	if u.is_empty():
		push_warning("Audio: no UI sound %s" % ui_name)
		return
	var s := stream(str(u[0]))
	if s:
		LGAudio.play_sfx(s, float(u[1]), float(u[2]))


## Gives every menu its sounds: a move when focus moves under the player's
## hand, a confirm (or back) when a button is pressed. main.gd calls it once.
static func hook_menus(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	var vp := tree.root
	if not vp.gui_focus_changed.is_connected(_on_focus_changed):
		vp.gui_focus_changed.connect(_on_focus_changed)


static func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_button_pressed):
		node.pressed.connect(_on_button_pressed.bind(node))


static func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	var text := str(button.get("text")) if "text" in button else ""
	ui("back" if text in ["Back", "Cancel", "Leave"] else ("toggle" if button.toggle_mode else "confirm"))


## Focus set by a screen as it opens is quiet; focus the player moved isn't.
static func _on_focus_changed(_control: Control) -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if Input.is_action_pressed(a):
			ui("move")
			return


## Plays a jingle on the Music bus (see [constant STINGERS]).
static func stinger(stinger_name: String) -> void:
	_ensure()
	var st: Array = STINGERS.get(stinger_name, [])
	var s := sfx(str(st[0])) if not st.is_empty() else null
	var tree := _tree()
	if s == null or tree == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = "Music"
	p.volume_db = float(st[1])
	p.autoplay = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	tree.root.add_child.call_deferred(p)
	stingers_played += 1


# --- Music ----------------------------------------------------------------

## Starts a track ("title", "run", "party"), crossfading from the last one,
## or stops the music with "". Asking for the track that's playing does
## nothing, so a restarted run keeps its music going.
static func music(track: String) -> void:
	_ensure()
	if track == _track:
		return
	_track = track
	_level = -1
	for k in _tweens:
		if _tweens[k] is Tween and (_tweens[k] as Tween).is_valid():
			(_tweens[k] as Tween).kill()
	_tweens.clear()
	if track == "" or not TRACKS.has(track):
		_track = ""
		LGAudio.stop_music()
		return
	var s := _track_stream(track)
	if s == null:
		return
	if track == "run":
		_set_layers(RUN_LAYERS[1], 0.0, 0.0)
		_level = 1
	elif track == "party":
		_set_layers(PARTY_LAYERS[1], 0.0, 0.0)
		_level = 1
	LGAudio.play_music(s, float(TRACKS[track].db))
	_started_usec = Time.get_ticks_usec()


## The track that's playing ("" for none).
static func current_track() -> String:
	return _track


## The run music's layers: 0 calm, 1 to 5 the pilot's Burn. Layers come in
## on the next beat; going down fades slower than coming up.
static func intensity(level: int) -> void:
	if _track != "run":
		return
	level = clampi(level, 0, RUN_LAYERS.size() - 1)
	if level == _level:
		return
	var up := level > _level
	_level = level
	_set_layers(RUN_LAYERS[level], until_beat(), 0.2 if up else 0.9)


## Party music's layers: 0 calm, 1 the race, 2 someone's out, 3 the last two.
static func party_level(level: int) -> void:
	if _track != "party":
		return
	level = clampi(level, 0, PARTY_LAYERS.size() - 1)
	if level == _level:
		return
	var up := level > _level
	_level = level
	_set_layers(PARTY_LAYERS[level], until_beat(), 0.2 if up else 0.9)


## The music's current layer level (-1 when it has none).
static func level() -> int:
	return _level


## A stem's volume in dB right now (for tests), or OFF.
static func stem_db(i: int) -> float:
	var s: AudioStreamSynchronized = _streams.get(_track)
	if s == null or i >= s.stream_count:
		return OFF
	return s.get_sync_stream_volume(i)


## Seconds to the next beat of the playing track.
static func until_beat() -> float:
	if _track == "":
		return 0.0
	var beat := 60.0 / float(TRACKS[_track].bpm)
	var t := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	var left := beat - fmod(t, beat)
	return 0.0 if left > beat - 0.02 else left


## Dulls the music (a low-pass on the Music bus) or brings it back.
static func muffle(on: bool, time := 0.5) -> void:
	_ensure()
	if on == _muffled or _lowpass == null:
		return
	_muffled = on
	var bus := AudioServer.get_bus_index("Music")
	var fx := _effect_index(bus, _lowpass)
	if fx < 0:
		return
	if _muffle_tween and _muffle_tween.is_valid():
		_muffle_tween.kill()
	var tree := _tree()
	if on:
		AudioServer.set_bus_effect_enabled(bus, fx, true)
	if tree == null:
		_lowpass.cutoff_hz = 700.0 if on else 20000.0
		AudioServer.set_bus_effect_enabled(bus, fx, on)
		return
	_muffle_tween = tree.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_muffle_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
	_muffle_tween.tween_property(_lowpass, "cutoff_hz", 700.0 if on else 20000.0, time)
	if not on:
		_muffle_tween.tween_callback(AudioServer.set_bus_effect_enabled.bind(bus, fx, false))


static func is_muffled() -> bool:
	return _muffled


static func _track_stream(track: String) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var stems: Array = TRACKS[track].stems
	var out: AudioStream
	if stems.size() == 1:
		out = stream("music/" + str(stems[0]))
	else:
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = stems.size()
		for i in stems.size():
			var s := stream("music/" + str(stems[i]))
			if s == null:
				return null
			sync.set_sync_stream(i, s)
			sync.set_sync_stream_volume(i, OFF)
		out = sync
	if out:
		_streams[track] = out
	return out


static func _set_layers(dbs: Array, delay: float, fade: float) -> void:
	var s: AudioStreamSynchronized = _streams.get(_track)
	if s == null:
		return
	var tree := _tree()
	for i in mini(dbs.size(), s.stream_count):
		var to := float(dbs[i])
		var old: Tween = _tweens.get(i)
		if old and old.is_valid():
			old.kill()
		var from := s.get_sync_stream_volume(i)
		if is_equal_approx(from, to):
			continue
		if tree == null or (delay <= 0.0 and fade <= 0.0):
			s.set_sync_stream_volume(i, to)
			continue
		var tw := tree.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if delay > 0.0:
			tw.tween_interval(delay)
		# Fade in loudness, not in dB, so a stem coming in from silence isn't
		# stuck inaudible for most of the fade.
		tw.tween_method(_set_stem_linear.bind(s, i), db_to_linear(from), db_to_linear(to), maxf(fade, 0.01))
		_tweens[i] = tw


static func _set_stem_linear(v: float, s: AudioStreamSynchronized, i: int) -> void:
	s.set_sync_stream_volume(i, maxf(linear_to_db(maxf(v, 0.000001)), OFF))


# --- Buses ----------------------------------------------------------------

## Adds the music's muffle and the sounds' limiter to the buses, once.
static func _ensure() -> void:
	if _set_up:
		return
	_set_up = true
	var tree := _tree()
	if tree and not tree.root.tree_exiting.is_connected(clear):
		tree.root.tree_exiting.connect(clear)
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var music_bus := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(music_bus):
		if AudioServer.get_bus_effect(music_bus, i) is AudioEffectLowPassFilter:
			_lowpass = AudioServer.get_bus_effect(music_bus, i)
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(music_bus, _lowpass)
		AudioServer.set_bus_effect_enabled(music_bus, AudioServer.get_bus_effect_count(music_bus) - 1, false)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(sfx_bus):
		if AudioServer.get_bus_effect(sfx_bus, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(sfx_bus, lim)


## Lets go of every loaded sound (when the game quits, so nothing is left
## held at exit).
static func clear() -> void:
	for k in _tweens:
		if _tweens[k] is Tween and (_tweens[k] as Tween).is_valid():
			(_tweens[k] as Tween).kill()
	_tweens.clear()
	if _muffle_tween and _muffle_tween.is_valid():
		_muffle_tween.kill()
	_muffle_tween = null
	_cache.clear()
	_streams.clear()
	_lowpass = null
	_track = ""
	_level = -1
	_muffled = false
	_set_up = false


static func _effect_index(bus: int, fx: AudioEffect) -> int:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == fx:
			return i
	return -1


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
