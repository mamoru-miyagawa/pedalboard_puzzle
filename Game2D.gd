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

# Starting screen assets.
const START_BG := "res://assets/starting_screen/starting_screen.png"
const START_LOGO := "res://assets/starting_screen/game_logo.png"
const START_ROLL_A := "res://assets/starting_screen/starting_screen_roll_A.png"
const START_ROLL_B := "res://assets/starting_screen/starting_screen_roll_B.png"

# UI assets.
const FONT_DEFAULT := "res://assets/fonts/Baloo2-SemiBold.ttf"
const FONT_BOLD := "res://assets/fonts/Baloo2-Bold.ttf"
const FONT_XBOLD := "res://assets/fonts/Baloo2-ExtraBold.ttf"
const ICON_MAIL := "res://assets/ui/icon_mail.png"
const ICON_MAIL_OPEN := "res://assets/ui/icon_mail_open.png"
const ICON_CLOSE := "res://assets/ui/icon_close.png"
const MAIL_DISPLAY_H := 76.0   # display height of the closed mail icon
# Centre of the mail icon, measured from the top-right corner. Lined up with the
# inbox card's close button so the toggle lives where you'd close the panel.
const MAIL_CENTER := Vector2(-90, 110)
const MAIL_SHADOW_OFFSET := Vector2(3, 6)   # drop shadow under the icon (button feel)
const MAIL_DOT_SIZE := 18.0                 # red notification badge diameter
const MAIL_DOT_COLOR := Color("#e6483d")

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
const INFO_W := 280.0
const INFO_MARGIN := 28.0       # inset from the screen edges
const INFO_BURY := 60.0         # how far the bottom sinks below the screen edge
								# (the warning/barcode footer is filler, so hide it)
const INFO_SLIDE := 30.0        # extra drop so the card hides fully below the edge
const INFO_BASE_H := 380.0      # height without the optional "extra" spec row
const INFO_EXTRA_H := 28.0      # added height when an Extra value is shown
const INFO_SHOWN_LEFT := 28.0   # x when visible
const INFO_HIDDEN_LEFT := -360.0  # x when tucked off-screen left
const INFO_TILT := -3.0         # slight paper-like rotation (degrees)

# Floating task tracker (bottom-centre): progress bar + the immediate next task.
const TRACKER_W := 320.0
const TRACKER_H := 84.0           # card height
const TRACKER_BOTTOM := 14.0      # gap above the screen's bottom edge
const TRACKER_CHECK := 26.0       # checkbox square size
const TRACKER_STEP_DELAY := 0.5   # pause after a task checks off before the next
const TRACKER_BAR_TIME := 0.3     # smooth progress-fill duration
const TRACKER_DONE_BG := Color("#86c98a")   # checkbox fill once a task is done
const TRACKER_FAIL_BG := Color("#d57f7f")   # checkbox fill when a task is failing

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
var mail_root: Control             # holds the icon, its shadow and the notification dot
var mail_btn: TextureButton        # top-right icon that opens / closes the panel
var mail_shadow: TextureRect       # dark silhouette beneath the icon
var mail_dot: Panel                # red notification badge
var mail_tex_closed: Texture2D
var mail_tex_open: Texture2D
var mail_scale := 1.0
var rules_tween: Tween
var mail_shake_tween: Tween
const RULES_TOP := 90
const RULES_BOTTOM := 610
const RULES_WIDTH := 400
const RULES_SHOWN_LEFT := -460    # fully on screen (right edge 24px in)
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
var info_h := INFO_BASE_H      # current card height (grows for the extra row)

# Floating task tracker (bottom-centre).
var tracker_panel: Panel
var tracker_bar: ProgressBar
var tracker_count: Label
var tracker_check: Panel       # the checkbox square
var tracker_check_icon: TextureRect  # tick shown when the task is done
var tracker_desc: Label        # the immediate next task's text
var tracker_acked: Array = []  # bool per task — already shown as checked off
var tracker_prev_states: Array = []  # last per-task RuleEngine states (fail detection)
var tracker_focus := 0         # task index currently displayed
var tracker_anim_tween: Tween
var tracker_shake_tween: Tween
var tracker_hidden_tween: Tween
var tracker_snap_next := false # next sync snaps (no animation) — set on stage load

# Stage-complete results email (modal, in front of everything).
var stage_complete := false
var results_layer: CanvasLayer
var results_root: Control
var results_card: Panel
var results_avatar: TextureRect
var results_sender: Label
var results_email: Label
var results_subject: Label
var results_body: Label
var results_stars: Array = []   # the three rating-star Labels
var results_star_tween: Tween
var results_seq_tween: Tween      # entrance/exit sequence tween
var results_card_content: VBoxContainer
var results_dim: ColorRect       # dim backdrop for smooth fade-in

# Stage intro choreography (dim → ringing mail → email + objective → game).
const INTRO_DIM_ALPHA := 0.55
var intro_active := false
var intro_dim: ColorRect          # dims the board behind the focused elements
var intro_tween: Tween
var hud_margin: Control           # top-left title/buttons block, hidden during intro
var mail_w := 0.0                 # current mail-icon display size (set in _update_mail_icon)
var mail_h := 0.0

var ui_root: Control            # top-level UI control (holds mail icon, tracker, etc.)

# Starting screen.
var start_root: Control
var start_roll_a: Sprite2D
var start_roll_b: Sprite2D
var start_logo: Control

# Settings.
var settings_language := "en"   # "en" or "pt-br"
var settings_music := true
var settings_root: Control
const SAVE_PATH := "user://save.cfg"
const LANG_EN := "en"
const LANG_PT_BR := "pt-br"

# Stage selection.
var stage_stars: Array = []        # per-stage star count (0-3)
var stage_select_root: Control
var stage_select_tiles: Array = []  # [{tile:Control, idx:int}] for snap logic
var stage_select_scroll: ScrollContainer
var stage_snap_tween: Tween
var stage_snap_timer: float = 0.0
var stage_last_scroll: float = 0.0

func _ready() -> void:
	item_db = ItemDB.new()
	if not item_db.load_csv(ITEMS_CSV):
		push_error("Failed to load item CSV — pedals won't appear.")
	stages = StageDB.load_stages()
	if stages.is_empty():
		push_error("Failed to load any stages — objectives won't appear.")
	_load_mail()
	_build_world()
	_build_ui()
	_build_starting_screen()
	_load_progress()
	# Don't show stage 0 yet — the starting screen is shown first.
	# show_stage(0)

# --- Save / Load ----------------------------------------------------------
func _save_progress() -> void:
	var cfg := ConfigFile.new()
	var prev: int = _get_saved_stage()
	var hi: int = max(current_stage, prev)
	cfg.set_value("progress", "highest_stage", hi)
	# Record 3 stars for the just-completed stage.
	if stage_stars.size() <= current_stage:
		stage_stars.resize(current_stage + 1)
	stage_stars[current_stage] = 3
	for i in range(hi + 1):
		cfg.set_value("progress", "stage_%d_stars" % i, stage_stars[i] if i < stage_stars.size() else 0)
	cfg.set_value("settings", "language", settings_language)
	cfg.set_value("settings", "music", settings_music)
	cfg.save(SAVE_PATH)

func _get_saved_stage() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return cfg.get_value("progress", "highest_stage", 0) as int

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	settings_language = cfg.get_value("settings", "language", "en") as String
	settings_music = cfg.get_value("settings", "music", true) as bool
	# Load per-stage stars.
	var hi: int = cfg.get_value("progress", "highest_stage", 0)
	stage_stars.resize(hi + 1)
	for i in range(hi + 1):
		stage_stars[i] = cfg.get_value("progress", "stage_%d_stars" % i, 0) as int

func _save_settings_only() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		# Preserve existing progress keys.
		var st: int = cfg.get_value("progress", "highest_stage", 0)
		cfg.set_value("progress", "highest_stage", st)
		for i in range(st + 1):
			cfg.set_value("progress", "stage_%d_stars" % i, cfg.get_value("progress", "stage_%d_stars" % i, 0) as int)
	cfg.set_value("settings", "language", settings_language)
	cfg.set_value("settings", "music", settings_music)
	cfg.save(SAVE_PATH)

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
	_apply_mail(String(stage.get("id", str(current_stage + 1))))

	# Slots can be fewer than the pedals — the spares wait in the tray.
	var n_items := item_names.size()
	var n_slots := int(stage.get("slots", n_items))

	# Game rule: slot 0 (the "first" in the signal chain) is the RIGHTMOST seat,
	# and the last slot is the leftmost — so mirror the row when placing seats.
	var seat_xs := _row_xs(n_slots)
	for i in range(n_slots):
		seats.append(_make_slot(true, i, Vector2(seat_xs[n_slots - 1 - i], SEAT_Y)))
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
	_reset_tracker()
	stage_complete = false
	# Ensure mail icon and tracker are in their normal positions.
	if mail_root:
		_update_mail_icon()
	if tracker_panel:
		tracker_panel.offset_top = -TRACKER_BOTTOM - TRACKER_H
		tracker_panel.offset_bottom = -TRACKER_BOTTOM
	if results_root:
		results_root.visible = false

	var order := pieces.keys()
	order.shuffle()
	for i in range(min(order.size(), tray_slots.size())):
		_place(pieces[order[i]], tray_slots[i])
	for nm in pieces:
		pieces[nm].prev_pos = pieces[nm].position
	validate()
	# Presentation is driven by the stage intro (_play_stage_intro), not here.

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
	marker.visible = false   # only revealed while a pedal is being dragged
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
	var ui_font = load(FONT_DEFAULT)   # match the rest of the game UI
	if ui_font:
		l.add_theme_font_override("font", ui_font)
		l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
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
			# A press that reaches here is outside the (input-blocking) email card,
			# so a click in empty space dismisses an open email.
			if dragging == null and rules_open:
				_set_rules_open(false)
		elif dragging:
			_end_drag()

func _try_start_drag(screen_pos: Vector2) -> void:
	var piece := _piece_at(screen_pos)
	if piece == null:
		return
	dragging = piece
	drag_from = piece.slot
	drag_offset = piece.position - screen_pos
	_set_slot_markers(true)      # reveal the drop targets while dragging
	if rules_open:
		_set_rules_open(false)   # collapse the email so it's out of the way while sorting
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
	_set_slot_markers(false)     # hide the drop targets again once placed
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

# Show / hide every slot's drop-target marker (seats + tray) — only on while dragging.
func _set_slot_markers(on: bool) -> void:
	for slot in (seats + tray_slots):
		if (slot as Slot2D).marker:
			(slot as Slot2D).marker.visible = on

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
	# Stage selection snap timer.
	if stage_select_root and stage_select_root.visible and stage_select_scroll:
		var sh: float = stage_select_scroll.scroll_horizontal
		if sh != stage_last_scroll:
			stage_last_scroll = sh
			stage_snap_timer = 0.18
		elif stage_snap_timer > 0.0:
			stage_snap_timer -= delta
			if stage_snap_timer <= 0.0:
				_snap_nearest()

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
	var states: Array = []
	for i in range(display_groups.size()):
		var st := _group_state(ctx, display_groups[i]["rules"], board_full)
		states.append(st)
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
	_sync_tracker(states)
	# The results email is the completion UI now (replaces the old win label).
	win_label.visible = false
	var complete := board_full and all_pass
	if complete and not stage_complete:
		stage_complete = true
		_show_results()
	elif not complete:
		stage_complete = false

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

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	var root := ui_root

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

	# Dim overlay used by the stage intro. Behind every UI element (z_index -2) but
	# on the UI layer, so it darkens the board/pedals while the mail + objective pop.
	intro_dim = ColorRect.new()
	intro_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_dim.color = Color(0, 0, 0, 0.0)
	intro_dim.z_index = -2
	intro_dim.visible = false
	intro_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(intro_dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	hud_margin = margin

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

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
	_add_card_shadow(rules_panel, 14, 16, 18)

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

	# Close button (icon) closes the panel.
	var min_btn := TextureButton.new()
	min_btn.texture_normal = load(ICON_CLOSE)
	min_btn.ignore_texture_size = true
	min_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
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

	# Mail button (top-right): toggles the panel. Styled like a raised button — a
	# drop shadow beneath the icon plus a red notification badge. The icon art
	# swaps mail/mail_open with the open state. Sits behind the inbox card.
	mail_tex_closed = load(ICON_MAIL)
	mail_tex_open = load(ICON_MAIL_OPEN)
	if mail_tex_closed:
		mail_scale = MAIL_DISPLAY_H / float(mail_tex_closed.get_height())

	mail_root = Control.new()
	mail_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mail_root.z_index = -1            # the open panel covers the icon
	mail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mail_root)

	# Drop shadow: a dark silhouette of the icon, nudged down-right.
	mail_shadow = TextureRect.new()
	mail_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mail_shadow.offset_left = MAIL_SHADOW_OFFSET.x
	mail_shadow.offset_right = MAIL_SHADOW_OFFSET.x
	mail_shadow.offset_top = MAIL_SHADOW_OFFSET.y
	mail_shadow.offset_bottom = MAIL_SHADOW_OFFSET.y
	mail_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mail_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	mail_shadow.modulate = Color(0, 0, 0, 0.28)
	mail_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mail_root.add_child(mail_shadow)

	mail_btn = TextureButton.new()
	mail_btn.ignore_texture_size = true
	mail_btn.stretch_mode = TextureButton.STRETCH_SCALE
	mail_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mail_btn.pressed.connect(func(): if not intro_active: _set_rules_open(not rules_open))
	mail_root.add_child(mail_btn)

	# Red notification badge, sitting on the icon's bottom-right corner.
	mail_dot = Panel.new()
	mail_dot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mail_dot.offset_left = -MAIL_DOT_SIZE
	mail_dot.offset_top = -MAIL_DOT_SIZE
	mail_dot.offset_right = 0
	mail_dot.offset_bottom = 0
	mail_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = MAIL_DOT_COLOR
	dot_sb.set_corner_radius_all(int(MAIL_DOT_SIZE * 0.5))
	dot_sb.set_border_width_all(2)
	dot_sb.border_color = Color(1, 1, 1, 0.9)   # white ring so it reads as a badge
	mail_dot.add_theme_stylebox_override("panel", dot_sb)
	mail_root.add_child(mail_dot)

	_update_mail_icon()

	_build_pedal_info(root, bold_font)
	_build_tracker(root, bold_font)
	_build_results(bold_font)

# Stage-complete email: cute stars, the order's result text, and the three
# scored rules (Commission / Extras / Budget). Modal, on top of everything.
func _build_results(bold_font) -> void:
	results_layer = CanvasLayer.new()
	results_layer.layer = 5            # in front of the world + all other UI
	add_child(results_layer)

	results_root = Control.new()
	results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_root.visible = false
	var rtheme := Theme.new()
	var dfont = load(FONT_DEFAULT)
	if dfont:
		rtheme.default_font = dfont
		rtheme.default_font_size = 18
	results_root.theme = rtheme
	results_layer.add_child(results_root)

	# Dim backdrop — also blocks input to the game behind while open.
	results_dim = ColorRect.new()
	results_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_dim.color = Color(0, 0, 0, 0.0)
	results_root.add_child(results_dim)

	# Centred email card — starts off-screen to the right, slides in.
	var cw := 620.0
	var ch := 500.0
	results_card = Panel.new()
	results_card.set_anchors_preset(Control.PRESET_CENTER)
	results_card.offset_left = DESIGN.x + 100
	results_card.offset_right = DESIGN.x + 100 + cw
	results_card.offset_top = -ch * 0.5
	results_card.offset_bottom = ch * 0.5
	var win := StyleBoxFlat.new()
	win.bg_color = CARD_BG
	win.set_corner_radius_all(20)
	win.set_border_width_all(3)
	win.border_color = CARD_INK
	results_card.add_theme_stylebox_override("panel", win)
	results_root.add_child(results_card)
	_add_card_shadow(results_card, 10, 14, 20)

	# Window contents, inset by the border so the outline shows all round.
	var card := VBoxContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 3
	card.offset_top = 3
	card.offset_right = -3
	card.offset_bottom = -3
	card.add_theme_constant_override("separation", 0)
	results_card.add_child(card)
	results_card_content = card

	# Browser-style header bar with the traffic-light dots.
	var head := Panel.new()
	head.custom_minimum_size = Vector2(0, 44)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = CARD_HEADER
	hsb.corner_radius_top_left = 17
	hsb.corner_radius_top_right = 17
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
	var head_lbl := Label.new()
	head_lbl.text = "inbox"
	head_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_lbl.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		head_lbl.add_theme_font_override("font", bold_font)
	head_row.add_child(head_lbl)

	# Padded body below the header.
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# (Stars moved to the bottom with the objectives.)

	# Sender row: avatar + name and email on one line, then subject - time.
	var sender := HBoxContainer.new()
	sender.alignment = BoxContainer.ALIGNMENT_BEGIN
	sender.add_theme_constant_override("separation", 12)
	col.add_child(sender)
	results_avatar = TextureRect.new()
	results_avatar.custom_minimum_size = Vector2(52, 52)
	results_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	results_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	results_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sender.add_child(results_avatar)

	var sender_col := VBoxContainer.new()
	sender_col.add_theme_constant_override("separation", 4)
	sender_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sender.add_child(sender_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	sender_col.add_child(name_row)

	results_sender = Label.new()
	results_sender.add_theme_font_size_override("font_size", 22)
	results_sender.add_theme_color_override("font_color", CARD_INK)
	results_sender.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bold_font:
		results_sender.add_theme_font_override("font", bold_font)
	name_row.add_child(results_sender)

	results_email = Label.new()
	results_email.add_theme_font_size_override("font_size", 13)
	results_email.add_theme_color_override("font_color", CARD_INK_SOFT)
	results_email.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(results_email)

	results_subject = Label.new()
	results_subject.add_theme_font_size_override("font_size", 18)
	results_subject.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		results_subject.add_theme_font_override("font", bold_font)
	results_subject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sender_col.add_child(results_subject)

	results_body = Label.new()
	results_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	results_body.add_theme_color_override("font_color", CARD_INK)
	col.add_child(results_body)

	col.add_child(_hline(CARD_DIVIDER, 2))

	# Bottom column: stars above, objectives inline below.
	var bottom_col := VBoxContainer.new()
	bottom_col.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_col.add_theme_constant_override("separation", 14)
	col.add_child(bottom_col)

	# Stars (top part of the bottom column).
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 16)
	results_stars.clear()
	for _i in range(3):
		var s := Label.new()
		s.text = "☆"
		s.add_theme_font_size_override("font_size", 46)
		s.add_theme_color_override("font_color", Color("#f2c14e"))
		star_row.add_child(s)
		results_stars.append(s)
	bottom_col.add_child(star_row)

	# Objectives (single horizontal line) below the stars.
	var rules_box := HBoxContainer.new()
	rules_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rules_box.add_theme_constant_override("separation", 18)
	for rname in ["Commission", "Extras", "Budget"]:
		_results_rule_row(rules_box, String(rname), bold_font)
	bottom_col.add_child(rules_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 24)
	col.add_child(spacer)

	# Round, thick-bordered buttons to match the rest of the UI.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	col.add_child(btn_row)
	var replay := _make_game_button("Replay", CARD_BG, CARD_INK, bold_font)
	replay.pressed.connect(_on_results_replay)
	btn_row.add_child(replay)
	var stages_btn := _make_game_button("Stages", Color("#8b7fc7"), Color.WHITE, bold_font)
	stages_btn.pressed.connect(_on_results_stages)
	btn_row.add_child(stages_btn)
	var next := _make_game_button("Next Stage", PROGRESS_FILL, Color.WHITE, bold_font)
	next.pressed.connect(_on_results_continue)
	btn_row.add_child(next)

# One completed-rule line for the results email: green tick + label.
func _results_rule_row(parent: Control, text: String, bold_font) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	# Keep each rule compact so the parent HBox can center them as a group.
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(row)
	var ic := TextureRect.new()
	ic.texture = load(ICON_PASS)
	ic.custom_minimum_size = Vector2(28, 28)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		l.add_theme_font_override("font", bold_font)
	row.add_child(l)

# A round, thick-bordered button matching the game's card styling.
func _make_game_button(text: String, fill: Color, fg: Color, bold_font) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.add_theme_stylebox_override("normal", _btn_stylebox(fill))
	b.add_theme_stylebox_override("hover", _btn_stylebox(fill.lightened(0.06)))
	b.add_theme_stylebox_override("pressed", _btn_stylebox(fill.darkened(0.08)))
	b.add_theme_stylebox_override("focus", _btn_stylebox(fill))
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, fg)
	if bold_font:
		b.add_theme_font_override("font", bold_font)
	return b

func _btn_stylebox(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(24)     # fully round ends
	sb.set_border_width_all(3)       # thick border, like the cards
	sb.border_color = CARD_INK
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# Texture for a mail record's avatar (same lookup the inbox card uses).
func _avatar_tex(m: Dictionary) -> Texture2D:
	var av_name := String(m.get("avatar", "")).strip_edges()
	var av_path := "res://assets/ui/%s.png" % av_name if av_name != "" else AVATAR
	var t = load(av_path)
	if t == null:
		t = load(AVATAR)
	return t

func _on_results_continue() -> void:
	_close_results()
	_on_next()

func _on_results_replay() -> void:
	_close_results()
	_transition_to_stage(current_stage)   # replay the same stage

func _on_results_stages() -> void:
	_close_results()
	if stage_select_root == null:
		_build_stage_select()
	# Refresh tiles in case progress changed.
	_refresh_stage_tiles()
	stage_select_root.visible = true
	# Snap to the current/latest unlocked stage on open.
	call_deferred("_snap_to_stage", min(_get_saved_stage() + 1, stages.size() - 1))

# Animate the results screen away: dim fades out, card slides right, mail+tracker return.
func _close_results() -> void:
	if results_seq_tween != null and results_seq_tween.is_valid():
		results_seq_tween.kill()

	if results_root == null or not results_root.visible:
		return

	results_seq_tween = create_tween()
	results_seq_tween.set_parallel(true)

	# Fade dim out.
	if results_dim:
		results_seq_tween.tween_property(results_dim, "color:a", 0.0, 0.20).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Card slides right.
	var cw := results_card.offset_right - results_card.offset_left
	var ctr_x := (results_card.offset_left + results_card.offset_right) * 0.5
	results_seq_tween.tween_property(results_card, "offset_left", DESIGN.x + 100.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	results_seq_tween.tween_property(results_card, "offset_right", DESIGN.x + 100.0 + cw, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	results_seq_tween.set_parallel(false)

	# After the card is gone, restore mail icon and tracker, hide the results root.
	results_seq_tween.tween_callback(func():
		# Restore mail icon position.
		if mail_root:
			_update_mail_icon()
		# Restore tracker position.
		if tracker_panel:
			tracker_panel.offset_top = -TRACKER_BOTTOM - TRACKER_H
			tracker_panel.offset_bottom = -TRACKER_BOTTOM
		results_root.visible = false
	)

# --- Stage selection screen -------------------------------------------------
func _build_stage_select() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)

	stage_select_root = Control.new()
	stage_select_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_select_root.visible = false
	layer.add_child(stage_select_root)

	# Full-screen dark background, matching the starting screen.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#363750")
	stage_select_root.add_child(bg)

	var st_bold := load(FONT_BOLD)
	var st_xbold := load(FONT_XBOLD)

	# Title at the top.
	var title := Label.new()
	title.text = "Stage Selection"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	if st_xbold:
		title.add_theme_font_override("font", st_xbold)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = DESIGN.y * -0.5 + 40
	title.offset_bottom = title.offset_top + 64
	stage_select_root.add_child(title)

	# Horizontal scroll area for the stage tiles.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.offset_left = -DESIGN.x * 0.4
	scroll.offset_right = DESIGN.x * 0.4
	scroll.offset_top = -90
	scroll.offset_bottom = 90
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	stage_select_scroll = scroll
	stage_select_root.add_child(scroll)

	stage_select_tiles.clear()
	var tiles_row := HBoxContainer.new()
	tiles_row.add_theme_constant_override("separation", 28)
	tiles_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(tiles_row)

	# Side spacers so the first and last tiles can scroll to centre.
	var pad_w: float = scroll.offset_right - scroll.offset_left
	var tile_w := 140.0
	var side_pad: float = pad_w * 0.5 - tile_w * 0.5
	var lpad := Control.new()
	lpad.custom_minimum_size = Vector2(side_pad, 0)
	tiles_row.add_child(lpad)

	var n_stages: int = stages.size()
	var unlocked: int = _get_saved_stage() + 1   # stage N+1 unlocks after completing N
	for i in range(n_stages):
		var tile_idx := i
		var tile := VBoxContainer.new()
		tile.add_theme_constant_override("separation", 8)
		tile.alignment = BoxContainer.ALIGNMENT_CENTER
		_build_tile_contents(tile, i + 1, tile_idx <= unlocked)
		# Let drags through to the ScrollContainer; clicks land here.
		tile.mouse_filter = Control.MOUSE_FILTER_PASS
		tile.gui_input.connect(_on_tile_gui.bind(tile_idx))
		tiles_row.add_child(tile)
		stage_select_tiles.append({"tile": tile, "idx": tile_idx})

	# Right spacer — mirrors the left one.
	var rpad := Control.new()
	rpad.custom_minimum_size = Vector2(side_pad, 0)
	tiles_row.add_child(rpad)

	# Back button at the bottom.
	var back_btn := _make_game_button("Back", Color("#6a6a8a"), Color.WHITE, st_bold)
	back_btn.custom_minimum_size = Vector2(220, 54)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.set_anchors_preset(Control.PRESET_CENTER)
	back_btn.offset_left = -110
	back_btn.offset_right = 110
	back_btn.offset_top = DESIGN.y * 0.5 - 90
	back_btn.offset_bottom = back_btn.offset_top + 54
	back_btn.pressed.connect(func(): stage_select_root.visible = false)
	stage_select_root.add_child(back_btn)

func _refresh_stage_tiles() -> void:
	if stage_select_root == null:
		return
	var unlocked: int = _get_saved_stage() + 1
	for i in range(stage_select_tiles.size()):
		if i >= stages.size():
			break
		var tile: Control = stage_select_tiles[i]["tile"]
		var idx: int = stage_select_tiles[i]["idx"]
		# Rebuild the tile contents.
		for c in tile.get_children():
			c.queue_free()
		_build_tile_contents(tile, idx + 1, idx <= unlocked)

func _build_tile_contents(tile: Control, stage_num: int, unlocked: bool) -> void:
	var tile_size := 140.0

	var square := Panel.new()
	square.custom_minimum_size = Vector2(tile_size, tile_size)
	var sq_sb := StyleBoxFlat.new()
	if unlocked:
		sq_sb.bg_color = Color("#eae4d3")
		sq_sb.border_color = CARD_BAND
	else:
		sq_sb.bg_color = Color("#4a4868")
		sq_sb.border_color = Color("#5d5b78")
	sq_sb.set_corner_radius_all(16)
	sq_sb.set_border_width_all(3)
	square.add_theme_stylebox_override("panel", sq_sb)
	tile.add_child(square)

	if unlocked:
		var num_label := Label.new()
		num_label.text = str(stage_num)
		num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num_label.add_theme_font_size_override("font_size", 52)
		num_label.add_theme_color_override("font_color", CARD_INK)
		num_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bld := load(FONT_BOLD)
		if bld:
			num_label.add_theme_font_override("font", bld)
		square.add_child(num_label)

		var star_row := HBoxContainer.new()
		star_row.alignment = BoxContainer.ALIGNMENT_CENTER
		star_row.add_theme_constant_override("separation", 3)
		var stars: int = stage_stars[stage_num - 1] if stage_num - 1 < stage_stars.size() else 0
		for _si in range(3):
			var s := Label.new()
			s.text = "★" if _si < stars else "☆"
			s.add_theme_font_size_override("font_size", 18)
			s.add_theme_color_override("font_color", Color("#f2c14e"))
			star_row.add_child(s)
		tile.add_child(star_row)
	else:
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 32)
		lock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		square.add_child(lock_label)

func _on_stage_tile_clicked(idx: int) -> void:
	# If already centred — select it. Otherwise, snap to centre first.
	if _is_tile_centred(idx):
		stage_select_root.visible = false
		_transition_to_stage(idx)
	else:
		_snap_to_stage(idx)

func _on_tile_gui(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_stage_tile_clicked(idx)

func _is_tile_centred(idx: int) -> bool:
	if stage_select_scroll == null:
		return false
	var view_w: float = stage_select_scroll.offset_right - stage_select_scroll.offset_left
	var tile_w := 140.0
	var gap := 28.0
	var left_pad: float = view_w * 0.5 - tile_w * 0.5
	var tile_cx: float = left_pad + float(idx) * (tile_w + gap) + tile_w * 0.5
	var target: float = tile_cx - view_w * 0.5
	return abs(stage_select_scroll.scroll_horizontal - target) < 4.0

func _snap_nearest() -> void:
	if stage_select_scroll == null or stage_select_tiles.is_empty():
		return
	var view_w: float = stage_select_scroll.offset_right - stage_select_scroll.offset_left
	var view_cx: float = stage_select_scroll.scroll_horizontal + view_w * 0.5
	var best_idx := 0
	var best_dist: float = INF
	var tile_w := 140.0
	var gap := 28.0
	var left_pad: float = view_w * 0.5 - tile_w * 0.5
	for i in range(stage_select_tiles.size()):
		var tile_cx: float = left_pad + float(i) * (tile_w + gap) + tile_w * 0.5
		var d: float = abs(tile_cx - view_cx)
		if d < best_dist:
			best_dist = d
			best_idx = i
	_snap_to_stage(best_idx)

func _snap_to_stage(tile_idx: int) -> void:
	if stage_select_scroll == null or tile_idx < 0 or tile_idx >= stage_select_tiles.size():
		return
	var tile_w := 140.0
	var gap := 28.0
	var view_w: float = stage_select_scroll.offset_right - stage_select_scroll.offset_left
	var left_pad: float = view_w * 0.5 - tile_w * 0.5
	var tile_cx: float = left_pad + float(tile_idx) * (tile_w + gap) + tile_w * 0.5
	var target_scroll: float = tile_cx - view_w * 0.5
	if stage_snap_tween and stage_snap_tween.is_valid():
		stage_snap_tween.kill()
	stage_snap_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	stage_snap_tween.tween_property(stage_select_scroll, "scroll_horizontal", target_scroll, 0.22)

# Populate and show the stage-complete email: requester avatar/name + a thank-you
# that reuses the stage's request text, then play the rating-star fill.
# The sequence: mail icon slides right, tracker sinks, dim fades in, card slides in.
func _show_results() -> void:
	if results_root == null:
		return
	_save_progress()
	var sid := String(stages[current_stage].get("id", str(current_stage + 1)))
	var m: Dictionary = mail_by_stage.get(sid, {})
	if results_avatar:
		results_avatar.texture = _avatar_tex(m)
		if results_sender:
			results_sender.text = String(m.get("sender_name", ""))
		if results_email:
			results_email.text = String(m.get("sender_address", ""))
		if results_subject:
			var subj := String(m.get("subject", ""))
			var t := String(m.get("time", ""))
			results_subject.text = subj + (" - " + t if t != "" else "")
		var req := String(m.get("e-mail", ""))
		results_body.text = "Thank you so much — exactly what I wanted!\n\n\"%s\"" % req if req != "" else "Thank you so much — exactly what I wanted!"

	# Pre-set the card size from content before animating.
	call_deferred("_animate_results")

func _animate_results() -> void:
	_layout_results_card_by_content()
	var cw := results_card.offset_right - results_card.offset_left
	var final_left := -cw * 0.5
	var final_right := cw * 0.5
	var slide_dist := DESIGN.x + 100 - final_left   # how far to travel

	if results_seq_tween != null and results_seq_tween.is_valid():
		results_seq_tween.kill()

	results_root.visible = true

	# Phase 1: mail icon slides right, tracker sinks (0.35s).
	if results_seq_tween == null or not results_seq_tween.is_valid():
		results_seq_tween = create_tween()
	results_seq_tween.set_parallel(true)

	# Mail icon — slide off-screen to the right.
	if mail_root:
		var mail_target_x := DESIGN.x + 200.0
		results_seq_tween.tween_property(mail_root, "offset_left", mail_target_x, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		results_seq_tween.tween_property(mail_root, "offset_right", mail_target_x, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		results_seq_tween.tween_property(mail_root, "offset_top", mail_root.offset_top, 0.35)
		results_seq_tween.tween_property(mail_root, "offset_bottom", mail_root.offset_bottom, 0.35)

	# Tracker — slide down off screen.
	if tracker_panel:
		results_seq_tween.tween_property(tracker_panel, "offset_top", DESIGN.y + 50, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		results_seq_tween.tween_property(tracker_panel, "offset_bottom", DESIGN.y + 50 + TRACKER_H, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	results_seq_tween.set_parallel(false)

	# Phase 2: dim the backdrop smoothly (0.3s).
	results_seq_tween.tween_callback(func():
		if results_dim:
			results_dim.color = Color(0, 0, 0, 0.0)
	)
	if results_dim:
		results_seq_tween.tween_property(results_dim, "color:a", 0.45, 0.30).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Phase 3: slide the card in from the right (0.35s).
	results_seq_tween.tween_callback(func():
		results_card.offset_left = DESIGN.x + 100.0
		results_card.offset_right = DESIGN.x + 100.0 + cw
	)
	results_seq_tween.set_parallel(true)
	results_seq_tween.tween_property(results_card, "offset_left", final_left, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	results_seq_tween.tween_property(results_card, "offset_right", final_right, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	results_seq_tween.set_parallel(false)

	# Phase 4: play the star sequence after the card settles.
	results_seq_tween.tween_callback(_play_star_sequence)

# Reset the rating stars to hollow, then fill them one at a time, popping a
# burst of action lines as each lands.
func _play_star_sequence() -> void:
	for s in results_stars:
		s.text = "☆"
		s.scale = Vector2.ONE
	if results_star_tween != null and results_star_tween.is_valid():
		results_star_tween.kill()
	results_star_tween = create_tween()
	results_star_tween.tween_interval(0.5)   # let the window settle first
	for i in range(results_stars.size()):
		results_star_tween.tween_callback(_fill_star.bind(i))
		results_star_tween.tween_interval(0.55)

func _fill_star(idx: int) -> void:
	if idx < 0 or idx >= results_stars.size():
		return
	var s: Label = results_stars[idx]
	s.text = "★"
	# Pop the star.
	s.pivot_offset = s.size * 0.5
	s.scale = Vector2(1.7, 1.7)
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "scale", Vector2.ONE, 0.32)
	# Burst of action lines, tinted gold, centred on the star.
	var burst := BurstEffect.new()
	burst.modulate = Color("#f2c14e")
	burst.scale = Vector2(0.6, 0.6)
	burst.position = s.global_position + s.size * 0.5
	results_root.add_child(burst)

func _layout_results_card_by_content() -> void:
	if results_card == null or results_card_content == null:
		return
	# Measure the combined minimum height of the content, add padding for borders
	var content_min: Vector2 = results_card_content.get_combined_minimum_size()
	# Make the card shorter by default but allow it to grow with content.
	var desired_h: float = float(clamp(content_min.y + 40.0, 260.0, 520.0))
	# Compute half height and assign integer offsets
	var half_h: int = int(desired_h * 0.5)
	results_card.offset_top = -half_h
	results_card.offset_bottom = half_h

# Floating window at the bottom: a progress bar and the immediate next task.
func _build_tracker(root: Control, bold_font) -> void:
	tracker_panel = Panel.new()
	tracker_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tracker_panel.offset_left = -TRACKER_W * 0.5
	tracker_panel.offset_right = TRACKER_W * 0.5
	tracker_panel.offset_bottom = -TRACKER_BOTTOM
	tracker_panel.offset_top = -TRACKER_BOTTOM - TRACKER_H
	tracker_panel.pivot_offset = Vector2(TRACKER_W * 0.5, TRACKER_H * 0.5)  # shake about centre
	var win := StyleBoxFlat.new()
	win.bg_color = CARD_BG
	win.set_corner_radius_all(18)
	win.set_border_width_all(3)
	win.border_color = CARD_INK
	tracker_panel.add_theme_stylebox_override("panel", win)
	root.add_child(tracker_panel)
	_add_card_shadow(tracker_panel, 6, 8, 18)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	tracker_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	margin.add_child(col)

	# Row 1: smooth green progress bar + "x/y".
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	col.add_child(bar_row)

	tracker_bar = ProgressBar.new()
	tracker_bar.show_percentage = false
	tracker_bar.custom_minimum_size = Vector2(0, 11)
	tracker_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = PROGRESS_TRACK
	track.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PROGRESS_FILL
	fill.set_corner_radius_all(7)
	tracker_bar.add_theme_stylebox_override("background", track)
	tracker_bar.add_theme_stylebox_override("fill", fill)
	bar_row.add_child(tracker_bar)

	tracker_count = Label.new()
	tracker_count.add_theme_font_size_override("font_size", 13)
	tracker_count.add_theme_color_override("font_color", CARD_INK_SOFT)
	tracker_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if bold_font:
		tracker_count.add_theme_font_override("font", bold_font)
	bar_row.add_child(tracker_count)

	# Row 2: checkbox + the next task's description.
	var task_row := HBoxContainer.new()
	task_row.add_theme_constant_override("separation", 10)
	col.add_child(task_row)

	tracker_check = Panel.new()
	tracker_check.custom_minimum_size = Vector2(TRACKER_CHECK, TRACKER_CHECK)
	tracker_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tracker_check.pivot_offset = Vector2(TRACKER_CHECK * 0.5, TRACKER_CHECK * 0.5)
	task_row.add_child(tracker_check)

	tracker_check_icon = TextureRect.new()
	tracker_check_icon.texture = load(ICON_PASS)
	tracker_check_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tracker_check_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tracker_check_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tracker_check_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_check.add_child(tracker_check_icon)

	tracker_desc = Label.new()
	tracker_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tracker_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tracker_desc.add_theme_font_size_override("font_size", 14)
	tracker_desc.add_theme_color_override("font_color", CARD_INK)
	task_row.add_child(tracker_desc)

	_tracker_set_box(RuleEngine.STATE_PENDING)
	_ignore_mouse(tracker_panel)   # purely informational — never eat gameplay clicks

# Make a control and all its descendants ignore the mouse (so they don't block drags).
func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse(ch)

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

# --- Floating task tracker --------------------------------------------------
# Snap the tracker to the fresh-stage state: nothing done, showing the first task.
func _reset_tracker() -> void:
	var total := display_groups.size()
	tracker_acked.clear()
	for _i in range(total):
		tracker_acked.append(false)
	tracker_prev_states.clear()
	if tracker_anim_tween != null and tracker_anim_tween.is_valid():
		tracker_anim_tween.kill()
	if tracker_bar:
		tracker_bar.max_value = max(1, total)
		tracker_bar.value = 0
	if tracker_count:
		tracker_count.text = "0/%d" % total
	tracker_focus = 0
	if tracker_desc:
		tracker_desc.text = String(display_groups[0]["desc"]) if total > 0 else ""
	_tracker_set_box(RuleEngine.STATE_PENDING)
	tracker_snap_next = true   # the validate() right after load should not animate

# Reconcile the tracker with the latest per-task states (RuleEngine state ints).
# Newly-passed tasks check off one at a time (each with a happy shake); a task
# that flips to failing shakes negatively and is surfaced — unless we're still
# tracking a work-in-progress task, which we keep on screen.
func _sync_tracker(states: Array) -> void:
	if tracker_panel == null:
		return
	var total := states.size()
	# On stage load, adopt the current state instantly (no auto check-off parade).
	if tracker_snap_next:
		tracker_snap_next = false
		tracker_acked.clear()
		for st in states:
			tracker_acked.append(st == RuleEngine.STATE_PASS)
		if tracker_anim_tween != null and tracker_anim_tween.is_valid():
			tracker_anim_tween.kill()
		tracker_bar.max_value = max(1, total)
		tracker_bar.value = _count_pass(states)
		tracker_count.text = "%d/%d" % [_count_pass(states), total]
		_tracker_show_next(states)
		tracker_prev_states = states.duplicate()
		return

	# A task that was checked off but is no longer passing (pedal removed) reopens.
	for i in range(total):
		if i < tracker_acked.size() and tracker_acked[i] and states[i] != RuleEngine.STATE_PASS:
			tracker_acked[i] = false
	# Tasks that just became passing, in order, not yet checked off.
	var newly_pass: Array = []
	for i in range(total):
		if states[i] == RuleEngine.STATE_PASS and (i >= tracker_acked.size() or not tracker_acked[i]):
			newly_pass.append(i)
	# Did anything flip to failing since last time?
	var had_fail := false
	for i in range(total):
		var was: int = int(tracker_prev_states[i]) if i < tracker_prev_states.size() else RuleEngine.STATE_PENDING
		if states[i] == RuleEngine.STATE_FAIL and was != RuleEngine.STATE_FAIL:
			had_fail = true
	tracker_prev_states = states.duplicate()

	if tracker_anim_tween != null and tracker_anim_tween.is_valid():
		tracker_anim_tween.kill()

	if newly_pass.is_empty():
		_tracker_settle(states, had_fail)
		return

	# Stagger through each freshly completed task, then settle on what's next.
	tracker_bar.max_value = max(1, total)
	var running := _acked_count()
	tracker_anim_tween = create_tween()
	for idx in newly_pass:
		tracker_anim_tween.tween_callback(_tracker_present.bind(idx))
		tracker_anim_tween.tween_callback(_tracker_mark_done.bind(idx))
		running += 1
		tracker_anim_tween.tween_property(tracker_bar, "value", float(running), TRACKER_BAR_TIME)
		tracker_anim_tween.tween_interval(TRACKER_STEP_DELAY)
	tracker_anim_tween.tween_callback(_tracker_settle.bind(states.duplicate(), had_fail))

# Settle the bar/count and decide which task to display (after any check-offs).
func _tracker_settle(states: Array, had_fail: bool) -> void:
	var total := states.size()
	var done := _count_pass(states)
	tracker_count.text = "%d/%d" % [done, total]
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(tracker_bar, "value", float(done), TRACKER_BAR_TIME)

	var cur := tracker_focus
	var cur_wip: bool = cur >= 0 and cur < total and states[cur] == RuleEngine.STATE_PENDING
	if had_fail:
		_tracker_shake(false)   # negative
		if cur_wip:
			_tracker_show_task(cur, RuleEngine.STATE_PENDING)   # keep the WIP task on screen
			return
		var f := _first_state(states, RuleEngine.STATE_FAIL)
		if f != -1:
			_tracker_show_task(f, RuleEngine.STATE_FAIL)        # surface the wrong one
			return
	_tracker_show_next(states)

# Show task `idx` unchecked (used right before it's checked off).
func _tracker_present(idx: int) -> void:
	tracker_focus = idx
	if idx >= 0 and idx < display_groups.size():
		tracker_desc.text = String(display_groups[idx]["desc"])
	_tracker_set_box(RuleEngine.STATE_PENDING)

# Check task `idx` off with a pop + happy shake, and bump the count.
func _tracker_mark_done(idx: int) -> void:
	if idx >= 0 and idx < tracker_acked.size():
		tracker_acked[idx] = true
	_tracker_set_box(RuleEngine.STATE_PASS)
	_tracker_pop()
	_tracker_shake(true)   # positive
	tracker_count.text = "%d/%d" % [_acked_count(), tracker_acked.size()]

# Show a specific task with a given box state.
func _tracker_show_task(idx: int, state: int) -> void:
	tracker_focus = idx
	if idx >= 0 and idx < display_groups.size():
		tracker_desc.text = String(display_groups[idx]["desc"])
	_tracker_set_box(state)

# Advance to the first unfinished task (shown in its own state), or all-done.
func _tracker_show_next(states: Array) -> void:
	var nxt := -1
	for i in range(states.size()):
		if states[i] != RuleEngine.STATE_PASS:
			nxt = i
			break
	if nxt == -1:
		tracker_focus = states.size()
		tracker_desc.text = "All tasks complete!"
		_tracker_set_box(RuleEngine.STATE_PASS)
	else:
		_tracker_show_task(nxt, int(states[nxt]))

# Checkbox look per task state: pending (outline), pass (green tick), fail (red cross).
func _tracker_set_box(state: int) -> void:
	if tracker_check == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	match state:
		RuleEngine.STATE_PASS:
			sb.bg_color = TRACKER_DONE_BG
		RuleEngine.STATE_FAIL:
			sb.bg_color = TRACKER_FAIL_BG
		_:
			sb.bg_color = Color(1, 1, 1, 0.6)
			sb.set_border_width_all(2)
			sb.border_color = CARD_HEADER
	tracker_check.add_theme_stylebox_override("panel", sb)
	if tracker_check_icon:
		var on: bool = state == RuleEngine.STATE_PASS or state == RuleEngine.STATE_FAIL
		tracker_check_icon.texture = status_icons.get(state, null)
		tracker_check_icon.visible = on

func _tracker_pop() -> void:
	if tracker_check == null:
		return
	tracker_check.scale = Vector2(0.6, 0.6)
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tracker_check, "scale", Vector2.ONE, 0.25)

# Shake the whole tracker — a celebratory pop (positive) or a no-no wiggle (negative).
func _tracker_shake(positive: bool) -> void:
	if tracker_panel == null:
		return
	if tracker_shake_tween != null and tracker_shake_tween.is_valid():
		tracker_shake_tween.kill()
	tracker_panel.rotation_degrees = 0.0
	tracker_panel.scale = Vector2.ONE
	if positive:
		tracker_shake_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tracker_shake_tween.tween_property(tracker_panel, "scale", Vector2(1.05, 1.05), 0.10)
		tracker_shake_tween.tween_property(tracker_panel, "scale", Vector2.ONE, 0.18)
	else:
		tracker_shake_tween = create_tween().set_trans(Tween.TRANS_SINE)
		tracker_shake_tween.tween_property(tracker_panel, "rotation_degrees", -5.0, 0.05)
		tracker_shake_tween.tween_property(tracker_panel, "rotation_degrees", 5.0, 0.07)
		tracker_shake_tween.tween_property(tracker_panel, "rotation_degrees", -3.0, 0.06)
		tracker_shake_tween.tween_property(tracker_panel, "rotation_degrees", 0.0, 0.06)

# Slide the tracker off the bottom (while the email is open) or back into view.
func _tracker_set_hidden(hide: bool, instant := false) -> void:
	if tracker_panel == null:
		return
	var shift := TRACKER_H + TRACKER_BOTTOM + 24.0
	var top_target := (-TRACKER_BOTTOM - TRACKER_H) + (shift if hide else 0.0)
	var bottom_target := (-TRACKER_BOTTOM) + (shift if hide else 0.0)
	if tracker_hidden_tween != null and tracker_hidden_tween.is_valid():
		tracker_hidden_tween.kill()
	if instant:
		tracker_panel.offset_top = top_target
		tracker_panel.offset_bottom = bottom_target
		return
	tracker_hidden_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tracker_hidden_tween.tween_property(tracker_panel, "offset_top", top_target, 0.25)
	tracker_hidden_tween.tween_property(tracker_panel, "offset_bottom", bottom_target, 0.25)

func _first_state(states: Array, want: int) -> int:
	for i in range(states.size()):
		if int(states[i]) == want:
			return i
	return -1

func _count_pass(a: Array) -> int:
	var n := 0
	for st in a:
		if st == RuleEngine.STATE_PASS:
			n += 1
	return n

func _acked_count() -> int:
	var n := 0
	for v in tracker_acked:
		if v:
			n += 1
	return n

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

# Swap the mail icon to match the open state, keeping it centred on MAIL_CENTER
# (the inbox card's close button) so the icon stays put as the art changes size.
func _update_mail_icon() -> void:
	if mail_root == null:
		return
	var tex: Texture2D = mail_tex_open if rules_open else mail_tex_closed
	if mail_btn:
		mail_btn.texture_normal = tex
	if mail_shadow:
		mail_shadow.texture = tex
	if tex == null:
		return
	mail_w = tex.get_width() * mail_scale
	mail_h = tex.get_height() * mail_scale
	mail_root.pivot_offset = Vector2(mail_w * 0.5, mail_h * 0.5)   # rotate/scale about centre
	if not intro_active:                # the intro positions the icon itself
		_mail_apply_corner()

# Snap the mail icon to its resting spot (top-right, on MAIL_CENTER).
func _mail_apply_corner() -> void:
	if mail_root == null:
		return
	mail_root.offset_left = MAIL_CENTER.x - mail_w * 0.5
	mail_root.offset_right = MAIL_CENTER.x + mail_w * 0.5
	mail_root.offset_top = MAIL_CENTER.y - mail_h * 0.5
	mail_root.offset_bottom = MAIL_CENTER.y + mail_h * 0.5

# Snap the mail icon to screen centre (anchored TOP_RIGHT, so x is from the right edge).
func _mail_apply_center() -> void:
	if mail_root == null:
		return
	var cx := -DESIGN.x * 0.5
	mail_root.offset_left = cx - mail_w * 0.5
	mail_root.offset_right = cx + mail_w * 0.5
	mail_root.offset_top = DESIGN.y * 0.5 - mail_h * 0.5
	mail_root.offset_bottom = DESIGN.y * 0.5 + mail_h * 0.5

# --- Pedal-info card (spec sheet) -------------------------------------------
func _build_pedal_info(root: Control, bold_font) -> void:
	info_panel = Panel.new()
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# x stays fixed at the shown position; the card slides in vertically from below.
	info_panel.offset_left = INFO_SHOWN_LEFT
	info_panel.offset_right = INFO_SHOWN_LEFT + INFO_W
	info_panel.offset_top = INFO_BURY + INFO_SLIDE
	info_panel.offset_bottom = INFO_BURY + INFO_BASE_H + INFO_SLIDE
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
	_add_card_shadow(info_panel, 16, 20, 18)

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
	info_name.add_theme_font_size_override("font_size", 22)
	info_name.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		info_name.add_theme_font_override("font", bold_font)
	head_col.add_child(info_name)

	var brand_row := HBoxContainer.new()
	head_col.add_child(brand_row)
	info_brand = Label.new()
	info_brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_brand.add_theme_font_size_override("font_size", 13)
	info_brand.add_theme_color_override("font_color", CARD_BAND)
	if bold_font:
		info_brand.add_theme_font_override("font", bold_font)
	brand_row.add_child(info_brand)
	info_cat = Label.new()
	info_cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_cat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_cat.add_theme_font_size_override("font_size", 11)
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
	spec_title.add_theme_font_size_override("font_size", 14)
	spec_title.add_theme_color_override("font_color", CARD_INK)
	if bold_font:
		spec_title.add_theme_font_override("font", bold_font)
	body.add_child(spec_title)
	body.add_child(_hline(CARD_INK, 2))

	var pre_gap := Control.new()
	pre_gap.custom_minimum_size = Vector2(0, 6)
	body.add_child(pre_gap)

	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 3)
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
	warn.add_theme_font_size_override("font_size", 8)
	warn.add_theme_constant_override("line_spacing", 0)   # pull the wrapped lines closer
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
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", CARD_INK_SOFT)
	row.add_child(k)
	var leader := DotLeader.new()
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.size_flags_vertical = Control.SIZE_FILL
	row.add_child(leader)
	var v := Label.new()
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 14)
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
	# Grow for the extra row, then slide up into view.
	info_h = INFO_BASE_H + (INFO_EXTRA_H if extra != "" else 0.0)
	info_panel.pivot_offset = Vector2(INFO_W * 0.5, info_h * 0.5)
	_slide_info(true)

# Slide the spec sheet vertically: up into its resting (buried) spot, or down off
# the bottom edge. x stays fixed at INFO_SHOWN_LEFT.
func _slide_info(show_it: bool) -> void:
	if info_panel == null:
		return
	var top_target := (INFO_BURY - info_h) if show_it else (INFO_BURY + INFO_SLIDE)
	var bottom_target := INFO_BURY if show_it else (INFO_BURY + info_h + INFO_SLIDE)
	if info_tween != null and info_tween.is_valid():
		info_tween.kill()
	info_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	info_tween.tween_property(info_panel, "offset_top", top_target, 0.24)
	info_tween.tween_property(info_panel, "offset_bottom", bottom_target, 0.24)

# Open or close the rules panel. `instant` snaps without animating.
func _set_rules_open(open: bool, instant := false) -> void:
	rules_open = open
	_update_mail_icon()
	# The tracker tucks off-screen while the email is open, and slides back when closed.
	_tracker_set_hidden(open, instant)
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
	_shake_mail()
	# Closing the email during the intro hands off to the actual game.
	if intro_active and not open:
		_finish_intro()

# A quick rotational wobble on the mail icon, for a bit of impact when toggling.
func _shake_mail() -> void:
	if mail_root == null:
		return
	if mail_shake_tween != null and mail_shake_tween.is_valid():
		mail_shake_tween.kill()
	mail_root.rotation_degrees = 0.0
	mail_shake_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	mail_shake_tween.tween_property(mail_root, "rotation_degrees", 9.0, 0.05)
	mail_shake_tween.tween_property(mail_root, "rotation_degrees", -7.0, 0.07)
	mail_shake_tween.tween_property(mail_root, "rotation_degrees", 4.0, 0.06)
	mail_shake_tween.tween_property(mail_root, "rotation_degrees", 0.0, 0.06)

func _on_next() -> void:
	_transition_to_stage(current_stage + 1)

# --- Stage transition + intro ----------------------------------------------
# Fade to white (with a "Stage N / name" title card), swap in the stage
# underneath, fade back, then play the stage intro.
func _transition_to_stage(idx: int) -> void:
	var n_stages := stages.size()
	if n_stages == 0:
		return
	var ci := ((idx % n_stages) + n_stages) % n_stages
	var stage: Dictionary = stages[ci]

	# White overlay on its own top layer so it survives the scene swap underneath.
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 7
	add_child(flash_layer)
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_STOP   # eat input during the transition
	flash_layer.add_child(flash)

	# Title card: "Stage N" (smaller) over the stage name (bigger), dark on white.
	var titles := VBoxContainer.new()
	titles.set_anchors_preset(Control.PRESET_CENTER)
	titles.offset_left = -460
	titles.offset_right = 460
	titles.offset_top = -150
	titles.offset_bottom = 150
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 4)
	titles.modulate = Color(1, 1, 1, 0.0)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.add_child(titles)
	var xbold = load(FONT_XBOLD)
	var num_lbl := Label.new()
	num_lbl.text = "Stage %d" % (ci + 1)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 56)
	num_lbl.add_theme_color_override("font_color", CARD_INK)
	if xbold:
		num_lbl.add_theme_font_override("font", xbold)
	titles.add_child(num_lbl)
	var name_lbl := Label.new()
	name_lbl.text = String(stage.get("name", "Stage %d" % (ci + 1)))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 92)
	name_lbl.add_theme_color_override("font_color", CARD_INK)
	if xbold:
		name_lbl.add_theme_font_override("font", xbold)
	titles.add_child(name_lbl)

	var tw := create_tween()
	# Fade into white.
	tw.tween_property(flash, "color:a", 1.0, 0.90).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Build the stage + set the intro start state while fully white.
	tw.tween_callback(func():
		if start_root:
			start_root.visible = false
		if results_root:
			results_root.visible = false
		show_stage(ci)
		_enter_intro_state())
	# Title in, hold, title out.
	tw.tween_property(titles, "modulate:a", 1.0, 0.40)
	tw.tween_interval(1.5)
	tw.tween_property(titles, "modulate:a", 0.0, 0.30)
	# Slowly reveal the (dimmed) stage.
	tw.tween_property(flash, "color:a", 0.0, 1.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash_layer.queue_free)
	tw.tween_callback(_play_stage_intro)

# Put the stage into its intro start state: dimmed, all UI tucked away, mail icon
# centred and hidden (ready to pop in).
func _enter_intro_state() -> void:
	intro_active = true
	rules_open = false
	if rules_panel:
		rules_panel.offset_left = RULES_HIDDEN_LEFT
		rules_panel.offset_right = RULES_HIDDEN_LEFT + RULES_WIDTH
	_tracker_set_hidden(true, true)
	_update_mail_icon()        # closed-mail texture + sizes (skips repositioning)
	_mail_apply_center()
	if mail_root:
		mail_root.scale = Vector2.ZERO
		mail_root.rotation_degrees = 0.0
	if intro_dim:
		intro_dim.visible = true
		intro_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intro_dim.color = Color(0, 0, 0, INTRO_DIM_ALPHA)
	if hud_margin:
		hud_margin.visible = false

# Pop the mail icon in at centre, ring it like a phone, then open it.
func _play_stage_intro() -> void:
	if mail_root == null:
		_finish_intro()
		return
	if intro_tween != null and intro_tween.is_valid():
		intro_tween.kill()
	intro_tween = create_tween()
	intro_tween.tween_property(mail_root, "scale", Vector2(1.3, 1.3), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro_tween.tween_interval(0.15)
	for _k in range(3):
		intro_tween.tween_property(mail_root, "rotation_degrees", 16.0, 0.05)
		intro_tween.tween_property(mail_root, "rotation_degrees", -16.0, 0.09)
		intro_tween.tween_property(mail_root, "rotation_degrees", 0.0, 0.05)
		intro_tween.tween_interval(0.16)
	intro_tween.tween_callback(_intro_open_mail)

# Fly the icon to its corner, open the email, and raise the objective card.
func _intro_open_mail() -> void:
	rules_open = true
	_update_mail_icon()        # open-mail texture (still skips repositioning)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(mail_root, "scale", Vector2.ONE, 0.40)
	t.tween_property(mail_root, "offset_left", MAIL_CENTER.x - mail_w * 0.5, 0.45)
	t.tween_property(mail_root, "offset_right", MAIL_CENTER.x + mail_w * 0.5, 0.45)
	t.tween_property(mail_root, "offset_top", MAIL_CENTER.y - mail_h * 0.5, 0.45)
	t.tween_property(mail_root, "offset_bottom", MAIL_CENTER.y + mail_h * 0.5, 0.45)
	if rules_panel:
		t.tween_property(rules_panel, "offset_left", float(RULES_SHOWN_LEFT), 0.45)
		t.tween_property(rules_panel, "offset_right", float(RULES_SHOWN_LEFT + RULES_WIDTH), 0.45)
	t.finished.connect(_intro_start_autohide)

# After the email is open, wait 4s then auto-close (unless already closed).
func _intro_start_autohide() -> void:
	if not intro_active:
		return
	var timer := create_tween()
	timer.tween_interval(4.0)
	timer.tween_callback(func():
		if intro_active and rules_open:
			_set_rules_open(false))   # the close hook calls _finish_intro

# Hand off from the intro to normal play: undim, slide the HUD back in. The email
# is already sliding out (the close that triggered this); the mail icon is parked.
func _finish_intro() -> void:
	if not intro_active:
		return
	intro_active = false
	if intro_tween != null and intro_tween.is_valid():
		intro_tween.kill()
	if mail_root:
		mail_root.scale = Vector2.ONE
		_mail_apply_corner()
	if intro_dim:
		intro_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let play resume right away
		var dt := create_tween()
		dt.tween_property(intro_dim, "color:a", 0.0, 0.50).set_ease(Tween.EASE_OUT)
		dt.tween_callback(func(): intro_dim.visible = false)
	if hud_margin:
		hud_margin.visible = true
		hud_margin.modulate = Color(1, 1, 1, 0.0)
		var ht := create_tween()
		ht.tween_property(hud_margin, "modulate:a", 1.0, 0.60).set_ease(Tween.EASE_OUT)

# --- Starting screen --------------------------------------------------------
func _build_starting_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	start_root = Control.new()
	start_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(start_root)

	# Background fill: full-screen colour rect.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#363750")
	start_root.add_child(bg)

	# Roll A (232x232) — place manually. Sits below the cover image.
	var tex_a = load(START_ROLL_A)
	if tex_a:
		start_roll_a = Sprite2D.new()
		start_roll_a.texture = tex_a
		start_roll_a.centered = true
		start_roll_a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		start_roll_a.position = Vector2(DESIGN.x * 0.5 + 375, 280)
		start_root.add_child(start_roll_a)

	# Roll B (171x171) — place manually. Sits below the cover image.
	var tex_b = load(START_ROLL_B)
	if tex_b:
		start_roll_b = Sprite2D.new()
		start_roll_b.texture = tex_b
		start_roll_b.centered = true
		start_roll_b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		start_roll_b.position = Vector2(DESIGN.x * 0.5 + 395, 500)
		start_root.add_child(start_roll_b)

	# starting_screen image — cover-fitted to the design rect. Placed after the
	# rolls so it paints over them (on top).
	var cover_tex = load(START_BG)
	if cover_tex:
		var cover := Sprite2D.new()
		cover.texture = cover_tex
		cover.centered = true
		cover.position = DESIGN * 0.5
		cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var cover_scale: float = max(DESIGN.x / cover_tex.get_width(), DESIGN.y / cover_tex.get_height())
		cover.scale = Vector2(cover_scale, cover_scale)
		start_root.add_child(cover)

	# Infinite slow rotation via tweens.
	# Roll A spins counter-clockwise, Roll B spins clockwise.
	if start_roll_a:
		var t_a := create_tween().set_loops()
		t_a.tween_property(start_roll_a, "rotation", -TAU, 18.0).as_relative()
		t_a.tween_property(start_roll_a, "rotation", -TAU, 18.0).as_relative()
	if start_roll_b:
		var t_b := create_tween().set_loops()
		t_b.tween_property(start_roll_b, "rotation", -TAU, 22.0).as_relative()
		t_b.tween_property(start_roll_b, "rotation", -TAU, 22.0).as_relative()

	# Game logo (2308x1500) — scaled to fit nicely, placed on the left side of screen.
	var logo_tex = load(START_LOGO)
	if logo_tex:
		start_logo = Control.new()
		# Scale so the logo fits within ~500px width.
		var logo_scale: float = 650.0 / logo_tex.get_width()
		var lw: float = logo_tex.get_width() * logo_scale
		var lh: float = logo_tex.get_height() * logo_scale
		# Position: ~10% from left edge, vertically centred.
		start_logo.set_anchors_preset(Control.PRESET_TOP_LEFT)
		start_logo.offset_left = DESIGN.x * 0
		start_logo.offset_right = DESIGN.x * 0.1 + lw
		start_logo.offset_top = DESIGN.y * 0.45 - lh * 0.5
		start_logo.offset_bottom = DESIGN.y * 0.45 + lh * 0.5
		start_root.add_child(start_logo)

		var spr := TextureRect.new()
		spr.texture = logo_tex
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		start_logo.add_child(spr)

		# Drop shadow: copy of the logo texture tinted black, shifted 12px down-right.
		var logo_shadow := TextureRect.new()
		logo_shadow.texture = logo_tex
		logo_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Same size and position as the logo, shifted 12px down-right.
		logo_shadow.set_anchors_preset(Control.PRESET_TOP_LEFT)
		logo_shadow.offset_left = start_logo.offset_left + 12
		logo_shadow.offset_top = start_logo.offset_top + 12
		logo_shadow.offset_right = start_logo.offset_right + 12
		logo_shadow.offset_bottom = start_logo.offset_bottom + 12
		logo_shadow.modulate = Color(0, 0, 0, 0.20)
		logo_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Add shadow to start_root BEFORE the logo so it renders underneath.
		start_root.add_child(logo_shadow)
		start_root.move_child(logo_shadow, start_root.get_child_count() - 2)

	# Buttons — centred at the bottom of the screen.
	var start_bold: Font = load(FONT_BOLD)
	var btn_col := VBoxContainer.new()
	btn_col.set_anchors_preset(Control.PRESET_CENTER)
	btn_col.add_theme_constant_override("separation", 20)
	var btn_w := 220.0
	btn_col.offset_left = -btn_w * 0.5
	btn_col.offset_right = btn_w * 0.5
	# Centre: place at ~78% down the screen. Offsets are relative to screen centre (y=360).
	var btn_centre_y := DESIGN.y * 0.78
	btn_col.offset_top = btn_centre_y - 360 - 60
	btn_col.offset_bottom = btn_centre_y - 360 + 60
	start_root.add_child(btn_col)

	var start_btn := _make_game_button("Play", PROGRESS_FILL, Color.WHITE, start_bold)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.custom_minimum_size = Vector2(220, 60)
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.pressed.connect(_on_start_pressed)
	btn_col.add_child(start_btn)

	var settings_btn := _make_game_button("Settings", Color("#6a6a8a"), Color.WHITE, start_bold)
	settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	settings_btn.custom_minimum_size = Vector2(220, 54)
	settings_btn.pressed.connect(_on_settings_pressed)
	btn_col.add_child(settings_btn)

func _on_start_pressed() -> void:
	# Fade to white (with the stage title), swap in the stage, then play its intro.
	if start_root == null:
		return
	_transition_to_stage(0)

# --- Settings dialog -------------------------------------------------------
func _build_settings() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)

	settings_root = Control.new()
	settings_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_root.visible = false
	layer.add_child(settings_root)

	# Dim backdrop.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_settings_dim_click)
	settings_root.add_child(dim)

	# Card.
	var card_w := 400.0
	var card_h := 320.0
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -card_w * 0.5
	card.offset_right = card_w * 0.5
	card.offset_top = -card_h * 0.5
	card.offset_bottom = card_h * 0.5
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = CARD_BG
	card_sb.set_corner_radius_all(18)
	card_sb.set_border_width_all(3)
	card_sb.border_color = CARD_INK
	card.add_theme_stylebox_override("panel", card_sb)
	settings_root.add_child(card)
	_add_card_shadow(card, 14, 16, 18)

	# Header bar (tan).
	var header := Panel.new()
	header.custom_minimum_size = Vector2(card_w, 52)
	var hdr_sb := StyleBoxFlat.new()
	hdr_sb.bg_color = CARD_HEADER_TAN
	hdr_sb.set_corner_radius_all(18)
	hdr_sb.corner_radius_bottom_left = 0
	hdr_sb.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", hdr_sb)
	card.add_child(header)

	var hdr_row := HBoxContainer.new()
	hdr_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	hdr_row.add_theme_constant_override("margin_left", 16)
	hdr_row.add_theme_constant_override("margin_right", 12)
	hdr_row.add_theme_constant_override("margin_top", 12)
	hdr_row.add_theme_constant_override("margin_bottom", 12)
	hdr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(hdr_row)

	var hdr_label := Label.new()
	hdr_label.text = "Settings"
	hdr_label.add_theme_color_override("font_color", CARD_INK)
	hdr_label.add_theme_font_size_override("font_size", 20)
	hdr_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st_bold := load(FONT_BOLD)
	if st_bold:
		hdr_label.add_theme_font_override("font", st_bold)
	hdr_row.add_child(hdr_label)

	# Close (X) button.
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color", CARD_INK)
	var cb_sb := StyleBoxFlat.new()
	cb_sb.bg_color = Color(0, 0, 0, 0)
	cb_sb.set_corner_radius_all(16)
	close_btn.add_theme_stylebox_override("normal", cb_sb)
	var cb_hover := StyleBoxFlat.new()
	cb_hover.bg_color = Color(0, 0, 0, 0.08)
	cb_hover.set_corner_radius_all(16)
	close_btn.add_theme_stylebox_override("hover", cb_hover)
	close_btn.pressed.connect(_on_settings_close)
	hdr_row.add_child(close_btn)

	# Body.
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_TOP_WIDE)
	body.offset_top = 56
	body.offset_bottom = -16
	body.add_theme_constant_override("margin_left", 28)
	body.add_theme_constant_override("margin_right", 28)
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)

	# --- Language row --------------------------------------------------------
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 10)
	var lang_label := Label.new()
	lang_label.text = "Language"
	lang_label.add_theme_color_override("font_color", CARD_INK)
	lang_label.add_theme_font_size_override("font_size", 18)
	lang_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lang_row.add_child(lang_label)

	var en_btn := _make_settings_toggle("EN")
	en_btn.pressed.connect(_on_lang_en)
	lang_row.add_child(en_btn)

	var pt_btn := _make_settings_toggle("PT-BR")
	pt_btn.pressed.connect(_on_lang_pt)
	lang_row.add_child(pt_btn)
	body.add_child(lang_row)

	_update_lang_toggles(en_btn, pt_btn)

	# --- Divider -------------------------------------------------------------
	body.add_child(_hline(CARD_DIVIDER, 1))

	# --- Music row -----------------------------------------------------------
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	var music_label := Label.new()
	music_label.text = "Music"
	music_label.add_theme_color_override("font_color", CARD_INK)
	music_label.add_theme_font_size_override("font_size", 18)
	music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_row.add_child(music_label)

	var music_cb := CheckBox.new()
	music_cb.button_pressed = settings_music
	music_cb.add_theme_color_override("font_color", CARD_INK)
	music_cb.add_theme_font_size_override("font_size", 16)
	music_cb.toggled.connect(_on_music_toggled)
	music_row.add_child(music_cb)
	body.add_child(music_row)

	# --- Clear progress (debug) -----------------------------------------------
	var clear_btn := Button.new()
	clear_btn.text = "Clear progress"
	clear_btn.add_theme_font_size_override("font_size", 13)
	clear_btn.add_theme_color_override("font_color", CARD_INK_SOFT)
	clear_btn.add_theme_color_override("font_hover_color", Color("#c8554f"))
	var clr_sb := StyleBoxFlat.new()
	clr_sb.bg_color = Color(0, 0, 0, 0)
	clear_btn.add_theme_stylebox_override("normal", clr_sb)
	clear_btn.add_theme_stylebox_override("hover", clr_sb)
	clear_btn.pressed.connect(_on_clear_progress)
	body.add_child(clear_btn)

	# --- Spacer --------------------------------------------------------------
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer2)

	# --- Bottom buttons ------------------------------------------------------
	var bot_row := HBoxContainer.new()
	bot_row.alignment = BoxContainer.ALIGNMENT_END
	var back_btn := _make_settings_button("Back")
	back_btn.pressed.connect(_on_settings_close)
	bot_row.add_child(back_btn)
	body.add_child(bot_row)

func _make_settings_toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(68, 36)
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", CARD_INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#eae4d3")
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = CARD_DIVIDER
	b.add_theme_stylebox_override("normal", sb)
	var sb_pressed := StyleBoxFlat.new()
	sb_pressed.bg_color = CARD_HEADER_TAN
	sb_pressed.set_corner_radius_all(10)
	sb_pressed.set_border_width_all(2)
	sb_pressed.border_color = CARD_BAND
	b.add_theme_stylebox_override("pressed", sb_pressed)
	return b

func _update_lang_toggles(en_btn: Button, pt_btn: Button) -> void:
	en_btn.button_pressed = (settings_language == LANG_EN)
	pt_btn.button_pressed = (settings_language == LANG_PT_BR)

func _make_settings_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", CARD_INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#d9d3c4")
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = CARD_INK
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color("#ccc6b4")
	sb_hover.set_corner_radius_all(12)
	sb_hover.set_border_width_all(2)
	sb_hover.border_color = CARD_INK
	b.add_theme_stylebox_override("hover", sb_hover)
	return b

func _on_settings_close() -> void:
	if settings_root:
		settings_root.visible = false

func _on_settings_dim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_settings_close()

func _on_lang_en() -> void:
	settings_language = LANG_EN
	_save_settings_only()

func _on_lang_pt() -> void:
	settings_language = LANG_PT_BR
	_save_settings_only()

func _on_music_toggled(on: bool) -> void:
	settings_music = on
	_save_settings_only()

func _on_clear_progress() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	stage_stars.clear()
	current_stage = 0
	stage_complete = false
	_on_settings_close()

func _on_settings_pressed() -> void:
	if settings_root == null:
		_build_settings()
	settings_root.visible = true

func _on_reset() -> void:
	dragging = null
	for s in seats:
		(s as Slot2D).occupant = null
	for t in tray_slots:
		(t as Slot2D).occupant = null
	var order := pieces.keys()
	for i in range(order.size()):
		_place(pieces[order[i]], tray_slots[i])
	tracker_snap_next = true   # snap the tracker back rather than animating in reverse
	validate()
