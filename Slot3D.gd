extends Area3D
class_name Slot3D

## A 3D slot. Either a seat on the board (is_seat = true) or a tray spot.

var index: int = -1
var is_seat: bool = false
var anchor: Vector3 = Vector3.ZERO   # world position where a piece's origin rests
var occupant = null                  # Piece3D currently here, or null
