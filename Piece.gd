extends PanelContainer
class_name Piece

## A draggable guest. Lives inside a Slot (seat or tray slot).

var char_id: String = ""
var main: Node = null

func _get_drag_data(_pos):
	# Build a translucent ghost centered on the cursor as the drag preview.
	var prev := Control.new()
	var ghost := duplicate()
	ghost.modulate = Color(1, 1, 1, 0.85)
	ghost.position = -0.5 * size
	prev.add_child(ghost)
	set_drag_preview(prev)
	return self

# When a piece is dropped onto THIS piece, forward the drop to the slot it sits in
# (so the slots can swap their occupants).
func _can_drop_data(_pos, data):
	return data is Piece

func _drop_data(_pos, data):
	var slot := get_parent()
	if slot and slot.has_method("accept_drop"):
		slot.accept_drop(data)
