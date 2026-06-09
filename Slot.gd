extends PanelContainer
class_name Slot

## A drop target. Either a seat (is_seat = true, index = seat number)
## or a holding spot in the guest tray.

var index: int = -1
var is_seat: bool = false
var main: Node = null

func get_piece() -> Piece:
	for child in get_children():
		if child is Piece:
			return child
	return null

func _can_drop_data(_pos, data):
	return data is Piece

func _drop_data(_pos, data):
	accept_drop(data)

func accept_drop(piece: Piece) -> void:
	if main:
		main.move_piece(piece, self)
