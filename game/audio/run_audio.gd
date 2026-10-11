class_name RunAudio
extends Node
## The run's sound: the pilot's burners, near misses, hazards, credits,
## crashes and the music that rises with the Burn. Reads the run each tick
## and reacts to its events.

var run: Run
var me := 1


func setup(p_run: Run, p_me: int) -> void:
	run = p_run
	me = p_me


func sync(_dt: float) -> void:
	pass


func on_event(_e: Dictionary) -> void:
	pass
