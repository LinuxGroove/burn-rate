extends Node
## The lobby and transport for every mode: solo, couch party, LAN, online
## rooms and quick match. For now only what a run on this device needs.

## Seats on this device: seat 0 has the keyboard, mouse and any free pad.
var local_seats: Array = [{"pad": LGSeat.ANY_FREE_PAD, "name": "Pilot 1"}]
var _seat_inputs := {}


func seat_input(index: int) -> LGSeat:
	if not _seat_inputs.has(index):
		if index == 0 or index >= local_seats.size():
			_seat_inputs[index] = LGSeat.primary()
		else:
			_seat_inputs[index] = LGSeat.for_pad(index, int(local_seats[index].pad))
	return _seat_inputs[index]


## Starts a run on this device with `config` (see RunScene).
func launch(config: Dictionary) -> void:
	RunScene.next_config = config
	LGScenes.change_scene("res://game/play/run_scene.tscn")
