class_name Pickup
extends RefCounted
## A credit chip, a big chip or a vehicle crate in a run.

var id := 0
## "credit", "big" or "crate".
var kind := "credit"
var x := 0.0
var y := 0.0
## A float, since the Magnet pulls credits between lanes.
var lane := 1.0
var value := 1
## Crates: the vehicle inside.
var vehicle := ""
var taken := false
var by := -1


static func make(p_id: int, p_kind: String, px: float, py: float, p_lane: float) -> Pickup:
	var p := Pickup.new()
	p.id = p_id
	p.kind = p_kind
	p.x = px
	p.y = py
	p.lane = p_lane
	p.value = 10 if p_kind == "big" else 1
	return p
