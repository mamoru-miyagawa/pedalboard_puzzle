extends Node2D
class_name Slot2D

## A 2D slot. Either a seat on the board (is_seat = true) or a tray spot.
## Data only — the visual marker is added as a child by Game2D.

var index: int = -1
var is_seat: bool = false
var anchor: Vector2 = Vector2.ZERO   # screen position where a piece's centre rests
var occupant = null                  # Piece2D currently here, or null

# Visual marker + its two looks, so we can tint it when it's the snap target.
var marker: Panel = null
var sb_normal: StyleBoxFlat = null
var sb_highlight: StyleBoxFlat = null

func set_highlight(on: bool) -> void:
	if marker:
		marker.add_theme_stylebox_override("panel", sb_highlight if on else sb_normal)
