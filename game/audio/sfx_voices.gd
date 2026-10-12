class_name SfxVoices
extends Node3D
## The run's one-shot sounds: a fixed set of positional voices on the SFX
## bus, so a busy room never piles up more than the budget. Each sound has a
## priority; when every voice is busy a new sound takes the quietest
## lower-priority one, and no more than [constant MAX_SAME] of one sound play
## at once. Sounds pan with where they are on screen (the camera is the
## listener) but never fade with distance or shift in pitch as they move:
## [RunAudio] sets their loudness itself.

## Voices in the budget.
const SIZE := 18
## Most copies of one sound playing at once.
const MAX_SAME := 3
## The same sound can't start again sooner than this (seconds).
const MIN_GAP := 0.035
## How strongly sounds pan left and right with their place on screen.
const PANNING := 1.6

## Sounds started (for tests).
var played := 0
var _voices: Array[AudioStreamPlayer3D] = []
var _prio: Array[int] = []
var _names: Array[String] = []
var _tags: Array[int] = []
var _clock := 0.0
var _last := {}
## Sounds waiting for their moment: [time, name, pos, db, pitch, prio, tag].
var _pending := []
## Tag -> callable giving the position each tick, for sounds that follow
## something (a seeker flying past).
var _follow := {}


func _ready() -> void:
	for i in SIZE:
		var p := make_player()
		add_child(p)
		_voices.append(p)
		_prio.append(0)
		_names.append("")
		_tags.append(0)


## A positional player set up the way the run's sounds want: no distance
## falloff, no doppler, panned by screen position, on the SFX bus.
static func make_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.panning_strength = PANNING
	p.max_db = 6.0
	return p


## Plays a sound effect at a place in the world. Returns the voice, or null
## when the budget or the gap kept it out. `tag` names what it belongs to,
## so [method stop_tag] and [method follow] can find it.
func play(sfx_name: String, pos: Vector3, db := 0.0, pitch := 1.0, prio := 1, tag := 0) -> AudioStreamPlayer3D:
	var s := GameAudio.sfx(sfx_name)
	if s == null:
		return null
	if _clock - float(_last.get(sfx_name, -1.0)) < MIN_GAP:
		return null
	var i := _pick(sfx_name, prio)
	if i < 0:
		return null
	_last[sfx_name] = _clock
	var p := _voices[i]
	p.stop()
	p.stream = s
	p.position = pos
	p.volume_db = db
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()
	_prio[i] = prio
	_names[i] = sfx_name
	_tags[i] = tag
	played += 1
	return p


## Plays a sound a moment from now.
func play_later(delay: float, sfx_name: String, pos: Vector3, db := 0.0, pitch := 1.0, prio := 1, tag := 0) -> void:
	_pending.append([_clock + delay, sfx_name, pos, db, pitch, prio, tag])


## Stops the sounds with this tag (a laser's charge when it fires).
func stop_tag(tag: int) -> void:
	for i in _voices.size():
		if _tags[i] == tag and _voices[i].playing:
			_voices[i].stop()
			_tags[i] = 0


## Moves this tag's sounds each tick to wherever `where` says (a Callable
## returning a Vector3, or null when the thing is gone).
func follow(tag: int, where: Callable) -> void:
	_follow[tag] = where


## Whether a sound with this tag is still playing.
func has_tag(tag: int) -> bool:
	for i in _voices.size():
		if _tags[i] == tag and _voices[i].playing:
			return true
	return false


func busy() -> int:
	var n := 0
	for p in _voices:
		if p.playing:
			n += 1
	return n


func set_paused(on: bool) -> void:
	for p in _voices:
		p.stream_paused = on


## Advances the clock: starts sounds whose moment has come and moves the
## ones that follow something.
func tick(dt: float) -> void:
	_clock += dt
	if not _pending.is_empty():
		var keep := []
		for e in _pending:
			if float(e[0]) <= _clock:
				play(str(e[1]), e[2], float(e[3]), float(e[4]), int(e[5]), int(e[6]))
			else:
				keep.append(e)
		_pending = keep
	if not _follow.is_empty():
		var gone := []
		for tag in _follow:
			var at: Variant = (_follow[tag] as Callable).call()
			if at == null or not has_tag(int(tag)):
				gone.append(tag)
				continue
			for i in _voices.size():
				if _tags[i] == int(tag):
					_voices[i].position = at
		for tag in gone:
			_follow.erase(tag)


func _pick(sfx_name: String, prio: int) -> int:
	# Too many of this one already: take the oldest of them.
	var same := []
	for i in _voices.size():
		if _voices[i].playing and _names[i] == sfx_name:
			same.append(i)
	if same.size() >= MAX_SAME:
		var oldest: int = same[0]
		for i in same:
			if _voices[i].get_playback_position() > _voices[oldest].get_playback_position():
				oldest = i
		return oldest
	for i in _voices.size():
		if not _voices[i].playing:
			return i
	# Every voice busy: take the lowest priority, the quietest of those.
	var best := -1
	for i in _voices.size():
		if _prio[i] > prio:
			continue
		if best < 0 or _prio[i] < _prio[best] or (_prio[i] == _prio[best] and _voices[i].volume_db < _voices[best].volume_db):
			best = i
	return best
