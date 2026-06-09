extends Control

## "Seat the guests" puzzle prototype, in the spirit of "Is This Seat Taken?".
## Drag every guest onto a seat so that all of their rules are satisfied.

const NUM_SEATS := 5

# --- Level data -------------------------------------------------------------
# Each guest has an id, display name, colour and a list of rules.
# Rule types: "edge", "not_edge", "adjacent" (target), "not_adjacent" (target).
var characters := [
	{
		"id": "bob", "name": "Bob", "color": Color("#4a90d9"),
		"rules": [{"type": "edge"}],
	},
	{
		"id": "alice", "name": "Alice", "color": Color("#e87fb0"),
		"rules": [{"type": "adjacent", "target": "bob"}, {"type": "not_adjacent", "target": "carol"}],
	},
	{
		"id": "carol", "name": "Carol", "color": Color("#5cb85c"),
		"rules": [{"type": "adjacent", "target": "dave"}],
	},
	{
		"id": "dave", "name": "Dave", "color": Color("#e9963a"),
		"rules": [{"type": "edge"}],
	},
	{
		"id": "eve", "name": "Eve", "color": Color("#9b59b6"),
		"rules": [{"type": "not_edge"}, {"type": "not_adjacent", "target": "dave"}],
	},
]

# --- Runtime state ----------------------------------------------------------
var seats: Array = []          # Slot nodes, ordered left to right
var tray_slots: Array = []     # Slot nodes in the guest tray
var pieces := {}               # id -> Piece
var rule_labels := {}          # id -> Array[Label]
var win_label: Label

func _ready() -> void:
	_build_ui()
	# Drop the guests into the tray in a shuffled order.
	var order := characters.duplicate()
	order.shuffle()
	for i in range(order.size()):
		tray_slots[i].add_child(pieces[order[i].id])
	validate()

# --- UI construction --------------------------------------------------------
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#15151c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 16)
	margin.add_child(root_vb)

	var title := Label.new()
	title.text = "Seat the Guests"
	title.add_theme_font_size_override("font_size", 32)
	root_vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Drag each guest onto a seat so everyone's wish is met."
	subtitle.add_theme_color_override("font_color", Color("#aaaaaa"))
	root_vb.add_child(subtitle)

	# Body: board on the left, rules list on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(body)

	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 14)
	body.add_child(board)

	board.add_child(_section_label("Seats"))

	var seats_center := CenterContainer.new()
	board.add_child(seats_center)
	var seats_box := HBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 12)
	seats_center.add_child(seats_box)
	for i in range(NUM_SEATS):
		var s := _build_slot(true, i)
		seats.append(s)
		seats_box.add_child(s)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	board.add_child(spacer)

	board.add_child(_section_label("Guests"))

	var tray_center := CenterContainer.new()
	board.add_child(tray_center)
	var tray_box := HBoxContainer.new()
	tray_box.add_theme_constant_override("separation", 12)
	tray_center.add_child(tray_box)
	for i in range(characters.size()):
		var t := _build_slot(false, i)
		tray_slots.append(t)
		tray_box.add_child(t)

	# Build the guest pieces (they get parented into the tray in _ready).
	for c in characters:
		pieces[c.id] = _build_piece(c)

	var board_spacer := Control.new()
	board_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_child(board_spacer)

	win_label = Label.new()
	win_label.text = "★  All guests are happy!  ★"
	win_label.add_theme_font_size_override("font_size", 28)
	win_label.add_theme_color_override("font_color", Color("#5cd65c"))
	win_label.visible = false
	board.add_child(win_label)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(120, 40)
	reset_btn.pressed.connect(_on_reset)
	board.add_child(reset_btn)

	# Rules panel.
	var rules_panel := PanelContainer.new()
	rules_panel.custom_minimum_size = Vector2(340, 0)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color("#1e1e28")
	rsb.set_corner_radius_all(10)
	rsb.set_content_margin_all(16)
	rules_panel.add_theme_stylebox_override("panel", rsb)
	body.add_child(rules_panel)

	var rules_vb := VBoxContainer.new()
	rules_vb.add_theme_constant_override("separation", 4)
	rules_panel.add_child(rules_vb)

	var rules_title := Label.new()
	rules_title.text = "Who wants what"
	rules_title.add_theme_font_size_override("font_size", 20)
	rules_vb.add_child(rules_title)

	var rt_spacer := Control.new()
	rt_spacer.custom_minimum_size = Vector2(0, 8)
	rules_vb.add_child(rt_spacer)

	for c in characters:
		var head := Label.new()
		head.text = c.name
		head.add_theme_color_override("font_color", c.color)
		head.add_theme_font_size_override("font_size", 17)
		rules_vb.add_child(head)

		var labels: Array = []
		for r in c.rules:
			var l := Label.new()
			l.text = "    •  " + _rule_text(r)
			rules_vb.add_child(l)
			labels.append(l)
		rule_labels[c.id] = labels

		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		rules_vb.add_child(gap)

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#cccccc"))
	return l

func _build_slot(is_seat: bool, idx: int) -> Slot:
	var s := Slot.new()
	s.is_seat = is_seat
	s.index = idx
	s.main = self
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	s.custom_minimum_size = Vector2(108, 108)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2b2b38") if is_seat else Color("#101016")
	sb.border_color = Color("#4a4a5a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	s.add_theme_stylebox_override("panel", sb)
	return s

func _build_piece(c: Dictionary) -> Piece:
	var p := Piece.new()
	p.char_id = c.id
	p.main = self
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size = Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.color
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = c.name
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 18)
	p.add_child(lbl)
	return p

# --- Piece movement & swapping ---------------------------------------------
func move_piece(piece: Piece, target: Slot) -> void:
	var source := piece.get_parent()
	if source == target:
		return
	var existing := target.get_piece()
	source.remove_child(piece)
	if existing:
		target.remove_child(existing)
	target.add_child(piece)
	if existing:
		source.add_child(existing)
	validate()

func _on_reset() -> void:
	for id in pieces:
		var p: Piece = pieces[id]
		if p.get_parent():
			p.get_parent().remove_child(p)
	for i in range(characters.size()):
		tray_slots[i].add_child(pieces[characters[i].id])
	validate()

# --- Rule evaluation --------------------------------------------------------
func seat_of(id: String) -> int:
	for i in range(seats.size()):
		var p := (seats[i] as Slot).get_piece()
		if p and p.char_id == id:
			return i
	return -1

func eval_rule(id: String, rule: Dictionary) -> bool:
	var s := seat_of(id)
	if s == -1:
		return false  # not seated yet
	match rule.type:
		"edge":
			return s == 0 or s == NUM_SEATS - 1
		"not_edge":
			return s > 0 and s < NUM_SEATS - 1
		"adjacent":
			var t := seat_of(rule.target)
			return t != -1 and abs(s - t) == 1
		"not_adjacent":
			var t2 := seat_of(rule.target)
			if t2 == -1:
				return true
			return abs(s - t2) != 1
	return false

func validate() -> void:
	var all_ok := true
	var seated := 0
	for c in characters:
		var s := seat_of(c.id)
		if s != -1:
			seated += 1
		var labels: Array = rule_labels[c.id]
		for i in range(c.rules.size()):
			var ok := eval_rule(c.id, c.rules[i])
			var col: Color
			if s == -1:
				col = Color("#888888")
			elif ok:
				col = Color("#5cd65c")
			else:
				col = Color("#ff6b6b")
			labels[i].add_theme_color_override("font_color", col)
			if not ok:
				all_ok = false
	win_label.visible = all_ok and seated == NUM_SEATS

func _rule_text(rule: Dictionary) -> String:
	match rule.type:
		"edge":
			return "Wants an end seat"
		"not_edge":
			return "Wants a middle seat"
		"adjacent":
			return "Wants to sit next to %s" % _char_name(rule.target)
		"not_adjacent":
			return "Won't sit next to %s" % _char_name(rule.target)
	return "?"

func _char_name(id: String) -> String:
	for c in characters:
		if c.id == id:
			return c.name
	return id
