class_name RunInput
extends RefCounted
## One tick of a pilot's controls: fly held, and a lane step.

## Nothing held.
static var NONE := RunInput.new()

var fly := false
## Fly was held last tick (vehicles act on the press).
var was_fly := false
## A lane step this tick: +1 one lane back (farther), -1 one lane forward
## (nearer), 0 none.
var lane := 0


static func make(p_fly: bool, p_lane := 0, p_was := false) -> RunInput:
	var i := RunInput.new()
	i.fly = p_fly
	i.lane = p_lane
	i.was_fly = p_was
	return i
