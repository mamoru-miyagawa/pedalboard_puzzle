extends Node2D

## Pedalboard puzzle — 2D, flat-vector port of the data-driven game.
## Items load from a CSV (the design spreadsheet); stages + rules load from JSON/CSV.
## Drag each pedal onto a slot so every rule for the stage is satisfied.
##
## This mirrors the structure of the old Game3D.gd one-for-one, but renders with
## Sprite2D pedals on a 2D canvas instead of GLTF models in a 3D viewport. The
## data layer (ItemDB / StageDB / RuleEngine) is shared and unchanged.

const ITEMS_CSV := "res://config/pedalboard game info - Pedals.csv"

# Pedal name (normalised) -> texture path. Used instead of scanning the assets
# folder, because folder scans don't work in exported (web) builds.
# A "Model" column in the items CSV overrides this per item.
const PEDAL_PATHS := {
	"BD2": "res://assets/pedals/bd_2.png",
	"SD1": "res://assets/pedals/sd_1.png",
	"DD8": "res://assets/pedals/dd_8.png",
	"CE2": "res://assets/pedals/ce_2.png",
	"TR2": "res://assets/pedals/tr_2.png",
}
# Board art per slot count. All boards render at the same scale, derived from
# the 3-slot reference board so they stay sized consistently across stages.
const BOARD_PATHS := {
	3: "res://assets/pedalboard.png",
	4: "res://assets/pedalboard_4.png",
	5: "res://assets/pedalboard_5.png",
}
const BOARD_REF_PATH := "res://assets/pedalboard.png"
const BOARD_REF_SLOTS := 3
const BG_PNG := "res://assets/background/bg.png"

# UI assets.
const FONT_DEFAULT := "res://assets/fonts/Baloo2-SemiBold.ttf"
const FONT_BOLD := "res://assets/fonts/Baloo2-Bold.ttf"
const ICON_MAIL := "res://assets/ui/icon_mail.png"
const ICON_MAIL_OPEN := "res://assets/ui/icon_mail_open.png"
const MAIL_DISPLAY_H := 76.0   # display height of the closed mail icon
const MAIL_MARGIN := 24.0      # inset from the bottom-right corner

const ICON_PASS := "res://assets/ui/icon_pass.png"
const ICON_FAIL := "res://assets/ui/icon_fail.png"
const ICON_PENDING := "res://assets/ui/icon_pending.png"
const AVATAR := "res://assets/ui/avatar.png"

# Per-stage email content for the inbox card.
const MAIL_CSV := "res://config/stage_mail.csv"

# Card palette.
const CARD_BG := Color("#f6efdd")
const CARD_HEADER := Color("#c9b9f2")
const CARD_INK := Color("#3a3a52")
const CARD_INK_SOFT := Color("#8a8aa0")
const CARD_BAND := Color("#8b7fc7")
const CARD_DIVIDER := Color("#d9d0bd")
const FIXIT_BG := Color("#d57f7f")
const PROGRESS_FILL := Color("#86c98a")
const PROGRESS_TRACK := Color("#e4dcc8")
const CARD_SHADOW := Color(0, 0, 0, 0.22)   # solid offset drop shadow for the cards

# Pedal-info card (slides in from the bottom-left while a pedal is held).
const INFO_W := 320.0
const INFO_MARGIN := 28.0       # inset from the screen edges
const INFO_BASE_H := 380.0      # height without the optional "extra" spec row
const INFO_EXTRA_H := 28.0      # added height when an Extra value is shown
const INFO_SHOWN_LEFT := 28.0   # x when visible
const INFO_HIDDEN_LEFT := -360.0  # x when tucked off-screen left
const INFO_TILT := -3.0         # slight paper-like rotation (degrees)

const CARD_HEADER_TAN := Color("#f0ddae")   # spec-sheet header band
const WARNING_TEXT := "WARNING: This product contains chemicals known to the State of California to cause cancer, birth defects, or other reproductive harm if those products expose consumers to such chemicals above certain levels."

# --- Board layout (design-space pixels; canvas_items stretch scales to window) -
const DESIGN := Vector2(1280, 720)
const SEAT_Y := 222.0          # y of the row of seats on the board
const TRAY_Y := 478.0          # y of the spare-pedal tray
const SEAT_SPACING := 132.0    # horizontal gap between slot centres
const PEDAL_W := 104.0         # on-screen width of a pedal (height follows aspect)
const FALLBACK_ASPECT := 1.32  # h/w used before the pedal art is imported
const SNAP_DIST := 92.0        # how close to a slot a drop must land to snap
const BOARD_PAD := 70.0        # board sprite extends this far past the end seats

# Wobble — a damped pendulum sway, driven by horizontal drag velocity.
const WOBBLE_GAIN := 0.0009
const WOBBLE_MAX := 0.32
const WOBBLE_STIFF := 80.0
const WOBBLE_DAMP := 7.0
const WOBBLE_KICK := 6.0
const DRAG_POP := 1.07         # the lifted pedal scales up a touch

# Drop shadow — a dark silhouette beneath the pedals (and the board). The pedal
# shadow is parented to the wobble body, so it moves / sways / pops along.
const SHADOW_COLOR := Color(0, 0, 0, 0.20)
const SHADOW_OFFSET := Vector2(4, 8)        # how far below the pedal centre it sits
const BOARD_SHADOW_OFFSET := Vector2(0, 16) # how far below the board its shadow sits

# Pickup lift — the pedal rises and its shadow sinks, opening a gap for height.
const DRAG_LIFT := Vector2(0, -18)          # how far the pedal rises when picked up
const SHADOW_LIFT_DROP := Vector2(0, 14)    # how far its shadow sinks below the base
const SHADOW_LIFT_SCALE := 1.10             # shadow grows a touch when raised

# Tints for the slot the dragged pedal would snap into.
const SLOT_HL_BG := Color(0.55, 0.85, 1.0, 0.22)
const SLOT_HL_BORDER := Color(0.6, 0.85, 1.0, 0.85)

# Fallback tints (by the CSV "Color" column) used only if the pedal art is missing.
const COLOR_MAP := {
	"white": Color("#e8e8ec"), "yellow": Color("#f1c40f"),
	"blue": Color("#4a90d9"), "green": Color("#5cb85c"),
	"red": Color("#e74c3c"), "black": Color("#33334a"),
}

# --- Data / runtime state ---------------------------------------------------
var item_db: ItemDB
var stages: Array = []
var current_stage := 0
var stage_rules: Array = []

var seats: Array = []
var tray_slots: Array = []
var pieces := {}                # Name -> Piece2D
var display_groups: Array = []  # [{rules:[...], desc:String}] — AND-bundled for display
var rule_rows: Array = []       # [{icon, label, pill}] per display group
var progress_bar: ProgressBar
var progress_label: Label
var status_icons := {}          # RuleEngine.STATE_* -> Texture2D

# Inbox-card email content (sender / subject / body), keyed by stage id.
var mail_avatar: TextureRect
var mail_name: Label
var mail_meta: Label
var mail_subject: Label
var mail_intro: Label
var mail_by_stage := {}

var world_root: Node2D          # holds background, board, slots, pieces
var board_sprite: Sprite2D
var board_shadow: Sprite2D      # silhouette shadow beneath the board
var board_ref_scale := 1.0      # display scale shared by all boards (from the 3-slot ref)
var piece_label_root: Control   # crisp pedal labels, on their own layer
var title_label: Label
var win_label: Label
var rules_panel: Panel
var rules_content: VBoxContainer
var rules_open := true
var mail_btn: TextureButton        # bottom-right icon that opens / closes the panel
var mail_tex_closed: Texture2D
var mail_tex_open: Texture2D
var mail_scale := 1.0
var rules_tween: Tween
const RULES_TOP := 20
const RULES_BOTTOM := 540
const RULES_WIDTH := 340
const RULES_SHOWN_LEFT := -364    # fully on screen (right edge 24px in)
const RULES_HIDDEN_LEFT := 30     # fully off-screen to the right

var dragging: Piece2D = null
var drag_from: Slot2D = null
var drag_offset := Vector2.ZERO
var hover_slot: Slot2D = null     # slot currently highlighted as the snap target

# Pedal-info card (spec sheet).
var info_panel: Panel
var info_name: Label          # title
var info_brand: Label         # "by BRAND" in the header
var info_cat: Label           # "Cat2 - Cat1" in the header
var info_era: Label           # spec: ERA
var info_bypass: Label        # spec: BYPASS
var info_power: Label         # spec: POWER
var info_extra_row: HBoxContainer
var info_extra: Label         # spec: EXTRA (hidden unless present)
var info_tween: Tween

func _ready() -> void:
	item_db = ItemDB.new()
	item_db.load_csv(ITEMS_CSV)
	stages = StageDB.load_stages()
	_load_mail()
	_build_world()
	_build_ui()
	show_stage(0)

# --- World / board ----------------------------------------------------------
func _build_world() -> void:
	var world_layer := CanvasLayer.new()
	world_layer.layer = 0
	add_child(world_layer)

	world_root = Node2D.new()
	world_layer.add_child(world_root)

	# Backdrop image (flat-vector desk scene), cover-fitted to the design rect.
	var bg_tex = load(BG_PNG)
	if bg_tex:
		var bg := Sprite2D.new()
		bg.texture = bg_tex
		bg.centered = true
		bg.position = DESIGN * 0.5
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var cover: float = max(DESIGN.x / bg_tex.get_width(), DESIGN.y / bg_tex.get_height())
		bg.scale = Vector2(cover, cover)
		bg.z_index = -20
		world_root.add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.color = Color("#23232e")
		bg.size = DESIGN
		bg.z_index = -20
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world_root.add_child(bg)

	# Board + its silhouette shadow. Texture and scale are chosen per stage in
	# _set_board (different art for 3 / 4 / 5 slot boards).
	board_shadow = Sprite2D.new()
	board_shadow.centered = true
	board_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	board_shadow.modulate = SHADOW_COLOR
	board_shadow.z_index = -11
	world_root.add_child(board_shadow)

	board_sprite = Sprite2D.new()
	board_sprite.centered = true
	board_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	board_sprite.z_index = -10
	world_root.add_child(board_sprite)

	# All boards display at this scale — the size the 3-slot reference board gets.
	var ref_tex = load(BOARD_REF_PATH)
	if ref_tex:
		var ref_span: float = max(1, BOARD_REF_SLOTS - 1) * SEAT_SPACING + PEDAL_W + BOARD_PAD * 2.0
		board_ref_scale = ref_span / float(ref_tex.get_width())

	# Crisp labels live on a layer above the pedals so the wobble never tilts them.
	var label_layer := CanvasLayer.new()
	label_layer.layer = 1
	add_child(label_layer)
	piece_label_root = Control.new()
	piece_label_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	piece_label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_layer.add_child(piece_label_root)

# --- Stage building ---------------------------------------------------------
func show_stage(idx: int) -> void:
	if stages.is_empty():
		return
	var n_stages := stages.size()
	current_stage = ((idx % n_stages) + n_stages) % n_stages
	var stage: Dictionary = stages[current_stage]
	_clear_stage()

	stage_rules = stage.get("rules", [])
	var item_names: Array = stage.get("items", [])
	title_label.text = stage.get("name", "Stage %d" % (current_stage + 1))
	_apply_mail(String(stage.get("id", str(current_stage + 1))))

	# Slots can be fewer than the pedals — the spares wait in the tray.
	var n_items := item_names.size()
	var n_slots := int(stage.get("slots", n_items))

	var seat_xs := _row_xs(n_slots)
	for i in range(n_slots):
		seats.append(_make_slot(true, i, Vector2(seat_xs[i], SEAT_Y)))
	var tray_xs := _row_xs(n_items)
	for i in range(n_items):
		tray_slots.append(_make_slot(false, i, Vector2(tray_xs[i], TRAY_Y)))

	_set_board(n_slots)

	for nm in item_names:
		var item = item_db.get_item(nm)
		if item == null:
			push_warning("Stage item not found in CSV: %s" % nm)
			continue
		pieces[nm] = _make_piece(item)

	_build_display_groups()
	for i in range(display_groups.size()):
		_add_rule_row(String(display_groups[i]["desc"]), i == 0)

	var order := pieces.keys()
	order.shuffle()
	for i in range(min(order.size(), tray_slots.size())):
		_place(pieces[order[i]], tray_slots[i])
	for nm in pieces:
		pieces[nm].prev_pos = pieces[nm].position
	validate()
	_present_rules()

# Bundle rules that share a Group id into a single AND requirement for display.
func _build_display_groups() -> void:
	display_groups.clear()
	var group_index := {}
	for rule in stage_rules:
		var g := String(rule.get("group", ""))
		if g == "":
			display_groups.append({"rules": [rule], "desc": String(rule.get("desc", ""))})
		elif group_index.has(g):
			var e = display_groups[group_index[g]]
			e["rules"].append(rule)
			if e["desc"] == "" and String(rule.get("desc", "")) != "":
				e["desc"] = String(rule.get("desc", ""))
		else:
			group_index[g] = display_groups.size()
			display_groups.append({"rules": [rule], "desc": String(rule.get("desc", ""))})
	# Auto-describe any entry that has no custom text.
	for e in display_groups:
		if e["desc"] == "":
			var parts := PackedStringArray()
			for r in e["rules"]:
				parts.append(RuleEngine.describe(r))
			e["desc"] = " AND ".join(parts)

func _clear_stage() -> void:
	dragging = null
	drag_from = null
	for s in seats:
		s.queue_free()
	for t in tray_slots:
		t.queue_free()
	for nm in pieces:
		var p: Piece2D = pieces[nm]
		if p.name_label:
			p.name_label.queue_free()
		if p.cat_label:
			p.cat_label.queue_free()
		p.queue_free()
	seats.clear()
	tray_slots.clear()
	pieces.clear()
	display_groups.clear()
	for c in rules_content.get_children():
		c.queue_free()
	rule_rows.clear()

# Evenly spaced, horizontally centred x positions for a row of n slots.
func _row_xs(n: int) -> Array:
	var xs: Array = []
	for i in range(n):
		xs.append(DESIGN.x * 0.5 + (i - (n - 1) * 0.5) * SEAT_SPACING)
	return xs

# Pick the board art for this slot count and place it at the shared scale.
func _set_board(n_slots: int) -> void:
	if board_sprite == null:
		return
	var path: String = BOARD_PATHS.get(n_slots, BOARD_REF_PATH)
	var tex = load(path)
	board_sprite.texture = tex
	board_shadow.texture = tex
	if tex == null:
		return
	var s := board_ref_scale
	if not BOARD_PATHS.has(n_slots):
		# No dedicated board for this count — stretch the reference to the row.
		var span: float = max(1, n_slots - 1) * SEAT_SPACING + PEDAL_W + BOARD_PAD * 2.0
		s = span / float(tex.get_width())
	board_sprite.scale = Vector2(s, s)
	board_sprite.position = Vector2(DESIGN.x * 0.5, SEAT_Y)
	board_shadow.scale = board_sprite.scale
	board_shadow.position = board_sprite.position + BOARD_SHADOW_OFFSET

func _make_slot(is_seat: bool, idx: int, anchor: Vector2) -> Slot2D:
	var slot := Slot2D.new()
	slot.is_seat = is_seat
	slot.index = idx
	slot.anchor = anchor
	slot.position = anchor
	slot.z_index = -5
	world_root.add_child(slot)

	# A subtle rounded pad marking the drop target.
	var marker := Panel.new()
	var w := PEDAL_W + 14.0
	var h := PEDAL_W * FALLBACK_ASPECT + 14.0
	marker.size = Vector2(w, h)
	marker.position = Vector2(-w * 0.5, -h * 0.5)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	if is_seat:
		# Faint light pad on the dark board.
		sb.bg_color = Color(1, 1, 1, 0.05)
		sb.border_color = Color(1, 1, 1, 0.15)
	else:
		# Faint dark outline on the light backdrop (was a heavy dark box).
		sb.bg_color = Color(0, 0, 0, 0.04)
		sb.border_color = Color(0, 0, 0, 0.10)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)

	# Highlight look — applied when this slot is where the drag will land.
	var hb := StyleBoxFlat.new()
	hb.bg_color = SLOT_HL_BG
	hb.border_color = SLOT_HL_BORDER
	hb.set_border_width_all(3)
	hb.set_corner_radius_all(12)

	marker.add_theme_stylebox_override("panel", sb)
	slot.add_child(marker)
	slot.marker = marker
	slot.sb_normal = sb
	slot.sb_highlight = hb
	return slot

func _make_piece(item: Dictionary) -> Piece2D:
	var piece := Piece2D.new()
	piece.char_id = item.get("Name", "")
	world_root.add_child(piece)

	var pivot := Node2D.new()
	piece.add_child(pivot)
	piece.body = pivot

	var tex_path := String(item.get("Model", ""))   # optional CSV override
	if tex_path == "":
		tex_path = _resolve_pedal(piece.char_id)
	var tex: Texture2D = null
	if tex_path != "":
		tex = load(tex_path) as Texture2D

	if tex:
		var s := PEDAL_W / float(tex.get_width())
		var scl := Vector2(s, s)
		piece.display_size = Vector2(tex.get_width(), tex.get_height()) * s

		# Shadow: a dark silhouette of the pedal. Parented to the piece (not the
		# body) so it can separate from the pedal on lift while still tracking it.
		var sh := Sprite2D.new()
		sh.centered = true
		sh.texture = tex
		sh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sh.scale = scl
		sh.modulate = SHADOW_COLOR
		sh.position = SHADOW_OFFSET
		sh.z_index = -1
		piece.add_child(sh)
		piece.shadow = sh
		piece.shadow_base_pos = SHADOW_OFFSET
		piece.shadow_base_scale = scl

		var spr := Sprite2D.new()
		spr.centered = true
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.scale = scl
		pivot.add_child(spr)
	else:
		# Fallback if the art is missing: a flat coloured pill with no texture.
		var h := PEDAL_W * FALLBACK_ASPECT
		piece.display_size = Vector2(PEDAL_W, h)
		var base_pos := -piece.display_size * 0.5

		var sh := Panel.new()
		sh.size = piece.display_size
		sh.pivot_offset = piece.display_size * 0.5   # scale from the centre on lift
		sh.position = base_pos + SHADOW_OFFSET
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh.modulate = SHADOW_COLOR
		sh.z_index = -1
		var shsb := StyleBoxFlat.new()
		shsb.bg_color = Color(0, 0, 0, 1)
		shsb.set_corner_radius_all(14)
		sh.add_theme_stylebox_override("panel", shsb)
		piece.add_child(sh)
		piece.shadow = sh
		piece.shadow_base_pos = base_pos + SHADOW_OFFSET
		piece.shadow_base_scale = Vector2.ONE

		var rect := Panel.new()
		rect.size = piece.display_size
		rect.position = base_pos
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_MAP.get(String(item.get("Color", "")).to_lower(), Color("#566"))
		sb.set_corner_radius_all(14)
		rect.add_theme_stylebox_override("panel", sb)
		pivot.add_child(rect)

	# Pedal name + Category 1 as crisp labels on the label layer, positioned
	# under the pedal each frame in _update_piece_labels.
	piece.name_label = _make_piece_label(piece.char_id, 18, Color.WHITE)
	piece.cat_label = _make_piece_label(String(item.get("Category 1", "")), 13, Color("#c8c8d0"))
	piece_label_root.add_child(piece.name_label)
	piece_label_root.add_child(piece.cat_label)
	return piece

func _make_piece_label(text: String, fsize: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(140, 0)
	l.size = Vector2(140, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l

func _update_piece_labels() -> void:
	if piece_label_root == null:
		return
	for nm in pieces:
		var p: Piece2D = pieces[nm]
		var sp := p.global_position
		var below := p.display_size.y * 0.5
		if p.name_label:
			p.name_label.position = Vector2(sp.x - 70, sp.y + below - 4)
		if p.cat_label:
			p.cat_label.position = Vector2(sp.x - 70, sp.y + below + 18)

# Export-safe lookup (no DirAccess folder scan, which fails in web builds).
func _resolve_pedal(name: String) -> String:
	return PEDAL_PATHS.get(_norm(name), "")

func _norm(s: String) -> String:
	return s.to_upper().replace("-", "").replace("_", "").replace(" ", "")

# --- Input / dragging -------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag(event.position)
		elif dragging:
			_end_drag()

func _try_start_drag(screen_pos: Vector2) -> void:
	var piece := _piece_at(screen_pos)
	if piece == null:
		return
	dragging = piece
	drag_from = piece.slot
	drag_offset = piece.position - screen_pos
	_show_pedal_info(item_db.get_item(piece.char_id))
	if piece.move_tween and piece.move_tween.is_valid():
		piece.move_tween.kill()   # cancel any in-flight glide so the drag wins
	if piece.slot:
		piece.slot.occupant = null
	piece.slot = null
	piece.z_index = 10                       # lift above the others while dragged
	_set_lifted(piece, true)
	piece.wobble_vel += -WOBBLE_KICK         # bob when picked up

# Topmost pedal whose sprite rect contains the point (last child draws on top).
func _piece_at(point: Vector2) -> Piece2D:
	var kids := world_root.get_children()
	kids.reverse()
	for n in kids:
		if n is Piece2D:
			var p: Piece2D = n
			var r := Rect2(p.position - p.display_size * 0.5, p.display_size)
			if r.has_point(point):
				return p
	return null

func _end_drag() -> void:
	var piece := dragging
	dragging = null
	_slide_info(false)
	piece.z_index = 0
	_set_lifted(piece, false)
	if hover_slot:
		hover_slot.set_highlight(false)
		hover_slot = null
	var target := _nearest_slot(piece.position)
	if target == null:
		_place(piece, drag_from)
	else:
		var existing: Piece2D = target.occupant
		if existing:
			_place(existing, drag_from, true)   # glide to the vacated slot
		_place(piece, target)
		if target.is_seat:
			_spawn_burst(target.anchor)   # cute "landed on the board" pop
	validate()

func _spawn_burst(pos: Vector2) -> void:
	var fx := BurstEffect.new()
	fx.position = pos
	fx.z_index = 20                       # above the pedals
	world_root.add_child(fx)

func _nearest_slot(pos: Vector2) -> Slot2D:
	var best: Slot2D = null
	var best_d := SNAP_DIST
	for slot in (seats + tray_slots):
		var s: Slot2D = slot
		var d := pos.distance_to(s.anchor)
		if d <= best_d:
			best_d = d
			best = s
	return best

# Raise / ground a pedal: lift the body up and pop it, while its shadow sinks
# down and grows — the gap between them reads as height.
func _set_lifted(piece: Piece2D, on: bool) -> void:
	if piece.body:
		piece.body.scale = Vector2.ONE * (DRAG_POP if on else 1.0)
		piece.body.position = DRAG_LIFT if on else Vector2.ZERO
	if piece.shadow:
		if on:
			piece.shadow.position = piece.shadow_base_pos + SHADOW_LIFT_DROP
			piece.shadow.scale = piece.shadow_base_scale * SHADOW_LIFT_SCALE
		else:
			piece.shadow.position = piece.shadow_base_pos
			piece.shadow.scale = piece.shadow_base_scale

func _place(piece: Piece2D, slot: Slot2D, animate := false) -> void:
	piece.slot = slot
	slot.occupant = piece
	if piece.move_tween and piece.move_tween.is_valid():
		piece.move_tween.kill()
	if animate:
		# Glide to the slot; the wobble naturally reacts to the slide and settles.
		piece.prev_pos = piece.position
		piece.move_tween = piece.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		piece.move_tween.tween_property(piece, "position", slot.anchor, 0.22)
	else:
		piece.position = slot.anchor
		# Set it down firmly — no wobble on placement.
		piece.prev_pos = slot.anchor
		piece.wobble = 0.0
		piece.wobble_vel = 0.0
		if piece.body:
			piece.body.rotation = 0.0

# --- Per-frame: follow cursor + wobble --------------------------------------
func _process(delta: float) -> void:
	_update_piece_labels()
	if delta <= 0.0:
		return
	if dragging:
		dragging.position = get_global_mouse_position() + drag_offset
		_update_snap_highlight()
	for nm in pieces:
		_update_wobble(pieces[nm], delta)

# Highlight the slot the dragged pedal would snap into, clearing the previous one.
func _update_snap_highlight() -> void:
	var target := _nearest_slot(dragging.position)
	if target == hover_slot:
		return
	if hover_slot:
		hover_slot.set_highlight(false)
	hover_slot = target
	if hover_slot:
		hover_slot.set_highlight(true)

func _update_wobble(piece: Piece2D, delta: float) -> void:
	var vel := (piece.position - piece.prev_pos) / delta
	piece.prev_pos = piece.position
	var target: float = clamp(vel.x * WOBBLE_GAIN, -WOBBLE_MAX, WOBBLE_MAX)
	var accel := (target - piece.wobble) * WOBBLE_STIFF - piece.wobble_vel * WOBBLE_DAMP
	piece.wobble_vel += accel * delta
	piece.wobble += piece.wobble_vel * delta
	if piece.body:
		piece.body.rotation = piece.wobble

# --- Validation -------------------------------------------------------------
func validate() -> void:
	var order: Array = []
	var seated := 0
	for s in seats:
		var occ = (s as Slot2D).occupant
		if occ:
			order.append(occ.char_id)
			seated += 1
		else:
			order.append("")

	var ctx := {"order": order, "num": seats.size(), "db": item_db, "items": pieces.keys()}
	var board_full := seated == seats.size() and seated > 0
	var all_pass := true
	var passed := 0
	for i in range(display_groups.size()):
		var st := _group_state(ctx, display_groups[i]["rules"], board_full)
		if i < rule_rows.size():
			var row: Dictionary = rule_rows[i]
			row["icon"].texture = status_icons.get(st, null)
			row["label"].add_theme_color_override("font_color", _state_color(st))
			row["pill"].visible = st == RuleEngine.STATE_FAIL
		if st == RuleEngine.STATE_PASS:
			passed += 1
		else:
			all_pass = false

	_update_progress(passed, display_groups.size())
	win_label.visible = board_full and all_pass

# Fold a bundle's member states: any red → red, all green → green, else grey.
func _group_state(ctx: Dictionary, rules: Array, board_full: bool) -> int:
	var all_pass := true
	for r in rules:
		var st := RuleEngine.state(ctx, r, board_full)
		if st == RuleEngine.STATE_FAIL:
			return RuleEngine.STATE_FAIL
		if st != RuleEngine.STATE_PASS:
			all_pass = false
	return RuleEngine.STATE_PASS if all_pass else RuleEngine.STATE_PENDING

# Rule-row text colour by state, tuned for the light card.
func _state_color(st: int) -> Color:
	match st:
		RuleEngine.STATE_PASS:
			return Color("#3f9a4f")
		RuleEngine.STATE_FAIL:
			return Color("#c8554f")
	return Color("#9a9ab0")  # pending / grey

# --- 2D UI overlay ----------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Baloo 2 as the UI font; headings use the bold cut (see overrides below).
	var ui_theme := Theme.new()
	var def_font = load(FONT_DEFAULT)
	if def_font:
		ui_theme.default_font = def_font
		ui_theme.default_font_size = 18
	root.theme = ui_theme
	var bold_font = load(FONT_BOLD)

	status_icons = {
		RuleEngine.STATE_PASS: load(ICON_PASS),
		RuleEngine.STATE_FAIL: load(ICON_FAIL),
		RuleEngine.STATE_PENDING: load(ICON_PENDING),
	}

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	title_label = Label.new()
	title_label.text = "Pedalboard"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color("#363750"))  # readable on the light bg
	if bold_font:
		title_label.add_theme_font_override("font", bold_font)
	col.add_child(title_label)

	var instr := Label.new()
	instr.text = "Drag each pedal onto a slot to satisfy every rule."
	instr.add_theme_color_override("font_color", Color("#55566f"))
	col.add_child(instr)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	win_label = Label.new()
	win_label.text = "★  Signal chain complete!  ★"
	win_label.add_theme_font_size_override("font_size", 30)
	win_label.add_theme_color_override("font_color", Color("#5cd65c"))
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_label.visible = false
	if bold_font:
		win_label.add_theme_font_override("font", bold_font)
	col.add_child(win_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(110, 40)
	reset_btn.pressed.connect(_on_reset)
	buttons.add_child(reset_btn)

	var next_btn := Button.new()
	next_btn.text = "Next stage"
	next_btn.custom_minimum_size = Vector2(130, 40)
	next_btn.pressed.connect(_on_next)
	buttons.add_child(next_btn)

	# --- Rules panel, styled as an "inbox" message card --------------------
	rules_panel = Panel.new()
	rules_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rules_panel.offset_left = RULES_HIDDEN_LEFT
	rules_panel.offset_right = RULES_HIDDEN_LEFT + RULES_WIDTH
	rules_panel.offset_top = RULES_TOP
	rules_panel.offset_bottom = RULES_BOTTOM
	var win := StyleBoxFlat.new()
	win.bg_color = CARD_BG
	win.set_corner_radius_all(18)
	win.set_border_width_all(3)
	win.border_color = CARD_INK
	rules_panel.add_theme_stylebox_override("panel", win)
	root.add_child(rules_panel)
	_add_card_shadow(rules_panel, 6, 6, 18)

	# Card content, inset by the border width so the outline shows all round.
	var card := VBoxContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 3
	card.offset_top = 3
	card.offset_right = -3
	card.offset_bottom = -3
	card.add_theme_constant_override("separation", 0)
	rules_panel.add_child(card)

	# Header bar (purple, rounded top to match the window).
	var head := Panel.new()
	head.custom_minimum_size = Vector2(0, 50)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = CARD_HEADER
	hsb.corner_radius_top_left = 15
	hsb.corner_radius_top_right = 15
	head.add_theme_stylebox_override("panel", hsb)
	card.add_child(head)

	var head_row := HBoxContainer.new()
	head_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head_row.offset_left = 16
	head_row.offset_right = -12
	head_row.add_theme_constant_override("separation", 8)
	head.add_child(head_row)

	head_row.add_child(_dot(Color("#e88a8a")))
	head_row.add_child(_dot(Color("#e8c46a")))
	head_row.add_child(_dot(Color("#86c98a")))

	var inbox_lbl := Label.new()
	inbox_lbl.text = "inbox"
	inbox_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inbox_lbl.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		inbox_lbl.add_theme_font_override("font", bold_font)
	head_row.add_child(inbox_lbl)

	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_spacer)

	# Minimize button closes the panel.
	var min_btn := Button.new()
	min_btn.text = "—"
	min_btn.custom_minimum_size = Vector2(30, 30)
	min_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	min_btn.pressed.connect(func(): _set_rules_open(false))
	head_row.add_child(min_btn)

	# Padded body.
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 18)
	body_margin.add_theme_constant_override("margin_right", 18)
	body_margin.add_theme_constant_override("margin_top", 14)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body_margin.add_child(body)

	# Sender row: avatar + name/meta.
	var sender := HBoxContainer.new()
	sender.add_theme_constant_override("separation", 10)
	body.add_child(sender)

	mail_avatar = TextureRect.new()
	mail_avatar.custom_minimum_size = Vector2(46, 46)
	mail_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mail_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mail_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sender.add_child(mail_avatar)

	var sender_col := VBoxContainer.new()
	sender_col.add_theme_constant_override("separation", 0)
	sender_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sender.add_child(sender_col)

	mail_name = Label.new()
	mail_name.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		mail_name.add_theme_font_override("font", bold_font)
	sender_col.add_child(mail_name)

	mail_meta = Label.new()
	mail_meta.add_theme_font_size_override("font_size", 13)
	mail_meta.add_theme_color_override("font_color", CARD_INK_SOFT)
	sender_col.add_child(mail_meta)

	# Subject + body.
	mail_subject = Label.new()
	mail_subject.add_theme_font_size_override("font_size", 22)
	mail_subject.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		mail_subject.add_theme_font_override("font", bold_font)
	body.add_child(mail_subject)

	mail_intro = Label.new()
	mail_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mail_intro.add_theme_color_override("font_color", CARD_INK)
	body.add_child(mail_intro)

	# Rule rows live here (rebuilt per stage in show_stage).
	rules_content = VBoxContainer.new()
	rules_content.add_theme_constant_override("separation", 8)
	rules_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(rules_content)

	# Footer: progress bar + "N / total sorted".
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	body.add_child(footer)

	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 12)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ptrack := StyleBoxFlat.new()
	ptrack.bg_color = PROGRESS_TRACK
	ptrack.set_corner_radius_all(6)
	var pfill := StyleBoxFlat.new()
	pfill.bg_color = PROGRESS_FILL
	pfill.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("background", ptrack)
	progress_bar.add_theme_stylebox_override("fill", pfill)
	footer.add_child(progress_bar)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		progress_label.add_theme_font_override("font", bold_font)
	footer.add_child(progress_label)

	# Mail button (bottom-right): toggles the panel. Its icon swaps mail/mail_open
	# with the open state, bottom-aligned so the taller art grows upward.
	mail_tex_closed = load(ICON_MAIL)
	mail_tex_open = load(ICON_MAIL_OPEN)
	if mail_tex_closed:
		mail_scale = MAIL_DISPLAY_H / float(mail_tex_closed.get_height())
	mail_btn = TextureButton.new()
	mail_btn.ignore_texture_size = true
	mail_btn.stretch_mode = TextureButton.STRETCH_SCALE
	mail_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mail_btn.pressed.connect(func(): _set_rules_open(not rules_open))
	root.add_child(mail_btn)
	_update_mail_icon()

	_build_pedal_info(root, bold_font)

# A small coloured circle for the header's "traffic lights".
func _dot(color: Color) -> Control:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(13, 13)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(7)
	d.add_theme_stylebox_override("panel", sb)
	return d

# A rounded "FIX IT"-style pill.
func _make_pill(text: String) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIXIT_BG
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color.WHITE)
	pill.add_child(l)
	return pill

# One rule line: status icon + description (+ a FIX-IT pill shown when failing).
func _add_rule_row(desc: String, first: bool) -> void:
	if not first:
		var div := Panel.new()
		div.custom_minimum_size = Vector2(0, 1)
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = CARD_DIVIDER
		div.add_theme_stylebox_override("panel", dsb)
		rules_content.add_child(div)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	rules_content.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = desc
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_color_override("font_color", CARD_INK)
	row.add_child(lbl)

	var pill := _make_pill("FIX IT")
	pill.visible = false
	row.add_child(pill)

	rule_rows.append({"icon": icon, "label": lbl, "pill": pill})

func _update_progress(passed: int, total: int) -> void:
	if progress_bar:
		progress_bar.max_value = max(1, total)
		progress_bar.value = passed
	if progress_label:
		progress_label.text = "%d / %d sorted" % [passed, total]

# Load per-stage email content (Stage ID, Sender_name, avatar, sender_address,
# time, subject, e-mail) into mail_by_stage, keyed by stage id.
func _load_mail() -> void:
	var f := FileAccess.open(MAIL_CSV, FileAccess.READ)
	if f == null:
		push_warning("stage_mail.csv not found: %s" % MAIL_CSV)
		return
	var cols: Array = []
	for h in f.get_csv_line():
		cols.append(String(h).strip_edges().to_lower())
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and String(row[0]).strip_edges() == ""):
			continue
		var rec := {}
		for i in range(cols.size()):
			rec[cols[i]] = (String(row[i]).strip_edges() if i < row.size() else "")
		var sid := String(rec.get("stage id", ""))
		if sid != "":
			mail_by_stage[sid] = rec
	f.close()

# Fill the inbox card from the email for this stage id.
func _apply_mail(sid: String) -> void:
	var m: Dictionary = mail_by_stage.get(sid, {})
	var av_name := String(m.get("avatar", "")).strip_edges()
	var av_path := "res://assets/ui/%s.png" % av_name if av_name != "" else AVATAR
	var av_tex = load(av_path)
	if av_tex == null:
		av_tex = load(AVATAR)
	if mail_avatar:
		mail_avatar.texture = av_tex
	if mail_name:
		mail_name.text = String(m.get("sender_name", ""))
	if mail_meta:
		var addr := String(m.get("sender_address", ""))
		var t := String(m.get("time", ""))
		mail_meta.text = addr + (" · " + t if t != "" else "")
	if mail_subject:
		mail_subject.text = String(m.get("subject", ""))
	if mail_intro:
		mail_intro.text = String(m.get("e-mail", ""))

func _present_rules() -> void:
	# Slide the panel in at the start of each stage (snap closed, then animate open).
	_set_rules_open(false, true)
	_set_rules_open(true)

# Swap the mail icon to match the open state, keeping the bottom edge fixed so
# the taller "open" art extends upward from the same baseline.
func _update_mail_icon() -> void:
	if mail_btn == null:
		return
	var tex: Texture2D = mail_tex_open if rules_open else mail_tex_closed
	mail_btn.texture_normal = tex
	if tex == null:
		return
	var w := tex.get_width() * mail_scale
	var h := tex.get_height() * mail_scale
	mail_btn.offset_right = -MAIL_MARGIN
	mail_btn.offset_bottom = -MAIL_MARGIN
	mail_btn.offset_left = -MAIL_MARGIN - w
	mail_btn.offset_top = -MAIL_MARGIN - h

# --- Pedal-info card (spec sheet) -------------------------------------------
func _build_pedal_info(root: Control, bold_font) -> void:
	info_panel = Panel.new()
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info_panel.offset_left = INFO_HIDDEN_LEFT
	info_panel.offset_right = INFO_HIDDEN_LEFT + INFO_W
	info_panel.offset_bottom = -INFO_MARGIN
	info_panel.offset_top = -INFO_MARGIN - INFO_BASE_H
	var win := StyleBoxFlat.new()
	win.bg_color = CARD_BG
	win.set_corner_radius_all(18)
	win.set_border_width_all(3)
	win.border_color = CARD_INK
	info_panel.add_theme_stylebox_override("panel", win)
	# Tilt it a touch so it reads like a sheet of paper (the shadow tilts too).
	info_panel.pivot_offset = Vector2(INFO_W * 0.5, INFO_BASE_H * 0.5)
	info_panel.rotation_degrees = INFO_TILT
	root.add_child(info_panel)
	_add_card_shadow(info_panel, 7, 9, 18)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 3
	outer.offset_top = 3
	outer.offset_right = -3
	outer.offset_bottom = -3
	outer.add_theme_constant_override("separation", 0)
	info_panel.add_child(outer)

	# Header band (tan): title, then "by BRAND" + "Cat2 - Cat1".
	var head := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = CARD_HEADER_TAN
	hsb.corner_radius_top_left = 15
	hsb.corner_radius_top_right = 15
	hsb.content_margin_left = 18
	hsb.content_margin_right = 18
	hsb.content_margin_top = 16
	hsb.content_margin_bottom = 16
	head.add_theme_stylebox_override("panel", hsb)
	outer.add_child(head)

	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 4)
	head.add_child(head_col)

	info_name = Label.new()
	info_name.add_theme_font_size_override("font_size", 26)
	info_name.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		info_name.add_theme_font_override("font", bold_font)
	head_col.add_child(info_name)

	var brand_row := HBoxContainer.new()
	head_col.add_child(brand_row)
	info_brand = Label.new()
	info_brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_brand.add_theme_font_size_override("font_size", 17)
	info_brand.add_theme_color_override("font_color", CARD_BAND)
	if bold_font:
		info_brand.add_theme_font_override("font", bold_font)
	brand_row.add_child(info_brand)
	info_cat = Label.new()
	info_cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_cat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_cat.add_theme_font_size_override("font_size", 15)
	info_cat.add_theme_color_override("font_color", CARD_INK_SOFT)
	if bold_font:
		info_cat.add_theme_font_override("font", bold_font)
	brand_row.add_child(info_cat)

	# Body (cream): spec sheet + fixed warning/barcode.
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 18)
	body_margin.add_theme_constant_override("margin_right", 18)
	body_margin.add_theme_constant_override("margin_top", 14)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	outer.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body_margin.add_child(body)

	var spec_title := Label.new()
	spec_title.text = "Specification sheet"
	spec_title.add_theme_font_size_override("font_size", 18)
	spec_title.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		spec_title.add_theme_font_override("font", bold_font)
	body.add_child(spec_title)
	body.add_child(_hline(CARD_INK, 2))

	var pre_gap := Control.new()
	pre_gap.custom_minimum_size = Vector2(0, 6)
	body.add_child(pre_gap)

	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 7)
	body.add_child(specs)

	info_era = _spec_row(specs, "ERA")
	info_bypass = _spec_row(specs, "BYPASS")
	info_power = _spec_row(specs, "POWER")
	info_extra = _spec_row(specs, "EXTRA")
	info_extra_row = info_extra.get_parent()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

	body.add_child(_hline(CARD_INK, 2))

	# Fixed footer: a (non-dynamic) warning notice + a dummy barcode.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	body.add_child(footer)

	var warn := Label.new()
	warn.text = WARNING_TEXT
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	warn.add_theme_font_size_override("font_size", 10)
	warn.add_theme_color_override("font_color", CARD_INK_SOFT)
	footer.add_child(warn)

	footer.add_child(_make_barcode())

# One "LABEL …… value" spec line; returns the value label so it can be filled later.
func _spec_row(parent: Control, label_text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var k := Label.new()
	k.text = label_text
	k.add_theme_color_override("font_color", CARD_INK_SOFT)
	row.add_child(k)
	var leader := DotLeader.new()
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.size_flags_vertical = Control.SIZE_FILL
	row.add_child(leader)
	var v := Label.new()
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_color_override("font_color", CARD_INK)
	row.add_child(v)
	return v

# A solid (hard-edged) offset drop shadow, added as a child so it follows the
# card's slide and rotation. Sits behind the card via a negative z_index.
func _add_card_shadow(panel: Control, dx: float, dy: float, radius: int) -> void:
	var sh := Panel.new()
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.offset_left = dx
	sh.offset_top = dy
	sh.offset_right = dx
	sh.offset_bottom = dy
	sh.z_index = -1
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_SHADOW
	sb.set_corner_radius_all(radius)
	sh.add_theme_stylebox_override("panel", sb)
	panel.add_child(sh)

# A flat horizontal rule.
func _hline(color: Color, h: int) -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	line.add_theme_stylebox_override("panel", sb)
	return line

# A decorative (non-scannable) barcode: alternating bars from a fixed pattern.
func _make_barcode() -> Control:
	var bc := HBoxContainer.new()
	bc.add_theme_constant_override("separation", 0)
	bc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pattern := [3, 1, 1, 2, 1, 3, 1, 1, 2, 2, 1, 1, 3, 1, 2, 1, 1, 2, 1, 3, 1, 1, 2, 1, 1, 3, 1, 2, 1, 1]
	var black := true
	for w in pattern:
		var bar := ColorRect.new()
		bar.color = CARD_INK if black else Color(0, 0, 0, 0)
		bar.custom_minimum_size = Vector2(float(w) * 1.6, 52)
		bc.add_child(bar)
		black = not black
	return bc

func _era_text(e: String) -> String:
	return "" if e == "" else e.capitalize() + " Build"

func _show_pedal_info(item) -> void:
	if info_panel == null or item == null:
		return
	var c1 := String(item.get("Category 1", ""))
	var c2 := String(item.get("Category 2", ""))
	info_name.text = String(item.get("Name", ""))
	info_brand.text = "by " + String(item.get("Brand", "")).to_upper()
	if c1 != "" and c2 != "":
		info_cat.text = "%s - %s" % [c2.capitalize(), c1.capitalize()]
	else:
		info_cat.text = (c1 + c2).capitalize()
	info_era.text = _era_text(String(item.get("Era", "")))
	info_bypass.text = String(item.get("Bypass", "")).capitalize()
	info_power.text = String(item.get("Power", "")).capitalize()
	var extra := String(item.get("Extra", "")).strip_edges()
	info_extra_row.visible = extra != ""
	info_extra.text = extra.capitalize()
	# Grow for the extra row (bottom is pinned, so the top moves), then slide in.
	var h := INFO_BASE_H + (INFO_EXTRA_H if extra != "" else 0.0)
	info_panel.offset_top = info_panel.offset_bottom - h
	info_panel.pivot_offset = Vector2(INFO_W * 0.5, h * 0.5)
	_slide_info(true)

func _slide_info(show_it: bool) -> void:
	if info_panel == null:
		return
	var target := float(INFO_SHOWN_LEFT if show_it else INFO_HIDDEN_LEFT)
	if info_tween != null and info_tween.is_valid():
		info_tween.kill()
	info_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	info_tween.tween_property(info_panel, "offset_left", target, 0.22)
	info_tween.tween_property(info_panel, "offset_right", target + INFO_W, 0.22)

# Open or close the rules panel. `instant` snaps without animating.
func _set_rules_open(open: bool, instant := false) -> void:
	rules_open = open
	_update_mail_icon()
	if rules_panel == null:
		return
	var target_left := float(RULES_SHOWN_LEFT if open else RULES_HIDDEN_LEFT)
	if rules_tween != null and rules_tween.is_valid():
		rules_tween.kill()
	if instant:
		rules_panel.offset_left = target_left
		rules_panel.offset_right = target_left + RULES_WIDTH
		return
	rules_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rules_tween.tween_property(rules_panel, "offset_left", target_left, 0.25)
	rules_tween.tween_property(rules_panel, "offset_right", target_left + RULES_WIDTH, 0.25)

func _on_next() -> void:
	show_stage(current_stage + 1)

func _on_reset() -> void:
	dragging = null
	for s in seats:
		(s as Slot2D).occupant = null
	for t in tray_slots:
		(t as Slot2D).occupant = null
	var order := pieces.keys()
	for i in range(order.size()):
		_place(pieces[order[i]], tray_slots[i])
	validate()
