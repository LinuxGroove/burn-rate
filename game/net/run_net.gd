class_name RunNet
extends Node
## Carries a party race between devices: each device sends its own pilots'
## controls, the host sends what's authoritative (hits, outs, the winner).
## RunScene adds one when the run's config has "net": true.

var scene: RunScene


func setup(p_scene: RunScene) -> void:
	scene = p_scene


## Called by RunScene after this device's inputs are read and before the
## run steps; fills scene.remote_inputs for the other devices' pilots.
func before_step(_local_inputs: Dictionary) -> void:
	pass


## Called by RunScene after the run steps.
func after_step() -> void:
	pass
