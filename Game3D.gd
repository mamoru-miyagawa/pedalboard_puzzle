extends Node3D

## Pedalboard puzzle — data driven.
## Items load from a CSV (the design spreadsheet); stages + rules load from JSON.
## Drag each pedal onto a slot so every rule for the stage is satisfied.

const ITEMS_CSV := "res://config/pedalboard game info - Sheet1.csv"

# --- Board layout -----------------------------------------------------------
const SEAT_X := 0.625
const SEAT_Y := 0.25
const TRAY_X := 2.9
const TRAY_Y := 0.0
const SEAT_SPACING := 0.95

const PIECE_FOOT := 1.0
const DRAG_Y := 1.1
const SNAP_DIST := 0.8

const PIXEL_SCALE := 3   # 3D renders at 1/this resolution, then scales up (chunky pixels)

# Pedal name (normalised) -> model path. Used instead of scanning the assets
# folder, because folder scans don't work in exported (web) builds.
# A "Model" column in the items CSV overrides this per item.
const MODEL_PATHS := {
	"BD2": "res://assets/Boss_BD2/Boss_BD2.gltf",
	"SD1": "res://assets/Boss_SD1/boss_sd1_merged.gltf",
	"DD8": "res://assets/Boss_DD8/Boss_DD8.gltf",
	"CE2": "res://assets/Boss_CE2/Boss_CE2.gltf",
	"TR2": "res://assets/Boss_TR2/Boss_TR2.gltf",
}

# Wobble (damped harmonic oscillator on the tilt; only while lifted/dragged).
const WOBBLE_GAIN := 0.06
const WOBBLE_MAX := 0.5
const WOBBLE_STIFF := 80.0
const WOBBLE_DAMP := 7.0
const WOBBLE_KICK := 4.0

# --- Camera (tweak in the Inspector on the Game node, or live while running) -
@export var camera_position := Vector3(1.76, 6.0, 0.0)   # higher Y = more zoomed out
@export var camera_look_at := Vector3(1.76, 0.0, 0.0)    # what it points at
@export_range(20.0, 90.0) var camera_fov := 50.0         # lower = more "zoomed in"/flatter

# --- Lighting (also tweakable in the Inspector / live while running) ---------
@export var sun_rotation_degrees := Vector3(-50, -35, 0)  # the directional light's angle
@export_range(0.0, 3.0) var sun_energy := 0.85
@export_range(0.0, 2.0) var ambient_energy := 0.4
@export var ambient_color := Color("#9a9aae")
@export var floor_tint := Color(0.65, 0.65, 0.65)         # multiplies the rug — lower = darker

# --- Data / runtime state ---------------------------------------------------
var item_db: ItemDB
var stages: Array = []
var current_stage := 0
var stage_rules: Array = []

var seats: Array = []
var tray_slots: Array = []
var pieces := {}                # Name -> Piece3D
var display_groups: Array = []  # [{rules:[...], desc:String}] — AND-bundled for display
var rule_line_labels: Array = []

var world: SubViewport          # low-res viewport the 3D scene renders into
var piece_label_root: Control   # holds the crisp 2D pedal labels
var camera: Camera3D
var sun: DirectionalLight3D
var world_env: Environment
var floor_mat: StandardMaterial3D
var title_label: Label
var win_label: Label
var rules_panel: PanelContainer
var rules_content: VBoxContainer
var rules_shown := true
var rules_hold := true            # keep it open at stage start, ignore hover
var rules_tween: Tween
const RULES_TOP := 20
const RULES_BOTTOM := 540
const RULES_WIDTH := 340
const RULES_SHOWN_LEFT := -364    # fully on screen (right edge 24px in)
const RULES_HIDDEN_LEFT := -28    # tucked away, 28px peeking
const RULES_REVEAL_MARGIN := 80   # how near the right edge reveals it
const RULES_HOLD_SEC := 2.5       # how long it stays open at stage start

var dragging: Piece3D = null
var drag_from: Slot3D = null

func _ready() -> void:
	item_db = ItemDB.new()
	item_db.load_csv(ITEMS_CSV)
	stages = StageDB.load_stages()
	_build_world()
	_build_ui()
	show_stage(0)

# --- World / camera / board -------------------------------------------------
func _build_world() -> void:
	# The 3D scene renders into a low-res SubViewport, scaled up with nearest
	# filtering for a pixel-art look. UI (and pedal labels) stay crisp on top.
	var bg := CanvasLayer.new()
	bg.layer = 0
	add_child(bg)

	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.stretch_shrink = PIXEL_SCALE
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks reach _unhandled_input
	bg.add_child(svc)

	world = SubViewport.new()
	world.own_world_3d = true
	world.transparent_bg = false
	world.msaa_3d = Viewport.MSAA_DISABLED
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(world)

	world_env = Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color("#23232e")
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = world_env
	world.add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	world.add_child(sun)

	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	_apply_camera()

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14.0, 10.5)                 # 4:3, matches bg_1.png (708x531)
	ground.mesh = pm
	ground.position = Vector3(1.76, 0.0, 0.0)     # centred under the camera target
	ground.rotation_degrees = Vector3(0, 90, 0)   # rug's wide side runs horizontally
	floor_mat = StandardMaterial3D.new()
	var bg_tex := load("res://assets/background/bg_1.png")
	if bg_tex:
		floor_mat.albedo_texture = bg_tex
		floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	floor_mat.metallic = 0.0
	floor_mat.roughness = 1.0
	pm.material = floor_mat
	world.add_child(ground)

	_apply_lighting()

	var board_scene := load("res://assets/pedalboard_s.gltf")
	if board_scene:
		world.add_child(board_scene.instantiate())
	else:
		push_warning("pedalboard_s.gltf not found / not imported yet.")

# Applies the exported camera settings (called at build time and every frame,
# so edits in the running game's remote inspector update live).
func _apply_camera() -> void:
	if camera == null or camera_position.is_equal_approx(camera_look_at):
		return
	camera.fov = camera_fov
	camera.position = camera_position
	camera.look_at(camera_look_at, Vector3(-1, 0, 0))

func _apply_lighting() -> void:
	if sun:
		sun.rotation_degrees = sun_rotation_degrees
		sun.light_energy = sun_energy
	if world_env:
		world_env.ambient_light_color = ambient_color
		world_env.ambient_light_energy = ambient_energy
	if floor_mat:
		floor_mat.albedo_color = floor_tint

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

	# Slots can be fewer than the pedals — the spares wait in the tray.
	var n_items := item_names.size()
	var n_slots := int(stage.get("slots", n_items))

	var seat_zs := _slot_zs(n_slots)
	for i in range(n_slots):
		seats.append(_make_slot(true, i, Vector3(SEAT_X, SEAT_Y, seat_zs[i])))
	var tray_zs := _slot_zs(n_items)
	for i in range(n_items):
		tray_slots.append(_make_slot(false, i, Vector3(TRAY_X, TRAY_Y, tray_zs[i])))

	for nm in item_names:
		var item = item_db.get_item(nm)
		if item == null:
			push_warning("Stage item not found in CSV: %s" % nm)
			continue
		pieces[nm] = _make_piece(item)

	_build_display_groups()
	for entry in display_groups:
		var l := Label.new()
		l.text = "•  " + String(entry["desc"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		rules_content.add_child(l)
		rule_line_labels.append(l)

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
		var p: Piece3D = pieces[nm]
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
	rule_line_labels.clear()

func _slot_zs(n: int) -> Array:
	var zs: Array = []
	for i in range(n):
		zs.append((i - (n - 1) * 0.5) * SEAT_SPACING)
	return zs

func _make_slot(is_seat: bool, idx: int, anchor: Vector3) -> Slot3D:
	var slot := Slot3D.new()
	slot.is_seat = is_seat
	slot.index = idx
	slot.anchor = anchor
	slot.position = anchor
	world.add_child(slot)

	var marker := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.04
	marker.mesh = cyl
	marker.position = Vector3(0, 0.03, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.16) if is_seat else Color(0.6, 0.8, 1.0, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	slot.add_child(marker)
	return slot

func _make_piece(item: Dictionary) -> Piece3D:
	var piece := Piece3D.new()
	piece.char_id = item.get("Name", "")
	world.add_child(piece)

	var pivot := Node3D.new()
	piece.add_child(pivot)
	piece.body = pivot

	var model_path := String(item.get("Model", ""))   # optional CSV override
	if model_path == "":
		model_path = _resolve_model(piece.char_id)
	var scene: PackedScene = null
	if model_path != "":
		scene = load(model_path) as PackedScene
	var model: Node3D
	if scene:
		model = scene.instantiate()
	else:
		push_warning("No model resolved for '%s'" % piece.char_id)
		var ph := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 0.8, 1.3)
		ph.mesh = bm
		model = ph
	pivot.add_child(model)

	var raw := _model_aabb(model)
	var horiz: float = max(raw.size.x, raw.size.z)
	if horiz <= 0.0:
		horiz = 1.0
	var s := PIECE_FOOT / horiz
	var basis := Basis().scaled(Vector3(s, s, s))
	var box: AABB = Transform3D(basis, Vector3.ZERO) * raw
	model.transform = Transform3D(basis, Vector3(-box.get_center().x, -box.position.y, -box.get_center().z))
	piece.fitted_height = box.size.y

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = Vector3(0, box.size.y * 0.5, 0)
	piece.add_child(col)

	# Pedal name + Category 1 are drawn as crisp 2D labels on the UI layer
	# (positioned over the pedal each frame in _update_piece_labels).
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
	if camera == null or piece_label_root == null:
		return
	if camera.get_viewport().get_visible_rect().size.x <= 0:
		return
	for nm in pieces:
		var p: Piece3D = pieces[nm]
		var sp := camera.unproject_position(p.global_position) * float(PIXEL_SCALE)
		if p.name_label:
			p.name_label.position = Vector2(sp.x - 70, sp.y + 16)
		if p.cat_label:
			p.cat_label.position = Vector2(sp.x - 70, sp.y + 38)

# Find a .gltf under res://assets whose folder or filename matches the item name.
func _resolve_model(name: String) -> String:
	# Export-safe lookup (no DirAccess folder scan, which fails in web builds).
	return MODEL_PATHS.get(_norm(name), "")

func _norm(s: String) -> String:
	return s.to_upper().replace("-", "").replace("_", "").replace(" ", "")

func _model_aabb(model: Node3D) -> AABB:
	var inv := model.global_transform.affine_inverse()
	var acc := AABB()
	var has := false
	for mi in _mesh_instances(model):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if has:
			acc = acc.merge(box)
		else:
			acc = box
			has = true
	return acc

func _mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_mesh_instances(child))
	return out

# --- Input / dragging -------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag(event.position)
		elif dragging:
			_end_drag()

func _try_start_drag(screen_pos: Vector2) -> void:
	var vp := screen_pos / float(PIXEL_SCALE)   # screen -> low-res viewport space
	var from := camera.project_ray_origin(vp)
	var to := from + camera.project_ray_normal(vp) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not (hit.collider is Piece3D):
		return
	var piece: Piece3D = hit.collider
	dragging = piece
	drag_from = piece.slot
	if piece.slot:
		piece.slot.occupant = null
	piece.slot = null
	piece.wobble_vel += Vector2(-WOBBLE_KICK, 0.0)   # bob when picked up

func _end_drag() -> void:
	var piece := dragging
	dragging = null
	var target := _nearest_slot(piece.global_position)
	if target == null:
		_place(piece, drag_from)
	else:
		var existing: Piece3D = target.occupant
		if existing:
			_place(existing, drag_from)
		_place(piece, target)
	validate()

func _nearest_slot(world_pos: Vector3) -> Slot3D:
	var best: Slot3D = null
	var best_d := SNAP_DIST
	for slot in (seats + tray_slots):
		var s: Slot3D = slot
		var d := Vector2(world_pos.x - s.anchor.x, world_pos.z - s.anchor.z).length()
		if d <= best_d:
			best_d = d
			best = s
	return best

func _place(piece: Piece3D, slot: Slot3D) -> void:
	piece.slot = slot
	slot.occupant = piece
	piece.position = slot.anchor
	# Set it down firmly — no wobble on placement.
	piece.prev_pos = slot.anchor
	piece.wobble = Vector2.ZERO
	piece.wobble_vel = Vector2.ZERO
	if piece.body:
		piece.body.rotation = Vector3.ZERO

# --- Per-frame: follow cursor + wobble --------------------------------------
func _process(delta: float) -> void:
	_apply_camera()
	_apply_lighting()
	_update_drawer()
	_update_piece_labels()
	if delta <= 0.0:
		return
	if dragging:
		_follow_cursor(dragging)
	for nm in pieces:
		_update_wobble(pieces[nm], delta)

func _follow_cursor(piece: Piece3D) -> void:
	var vp := get_viewport().get_mouse_position() / float(PIXEL_SCALE)
	var from := camera.project_ray_origin(vp)
	var dir := camera.project_ray_normal(vp)
	var p = Plane(Vector3.UP, DRAG_Y).intersects_ray(from, dir)
	if p != null:
		piece.position = Vector3(p.x, DRAG_Y, p.z)

func _update_wobble(piece: Piece3D, delta: float) -> void:
	var vel := (piece.position - piece.prev_pos) / delta
	piece.prev_pos = piece.position
	var target := Vector2(
		clamp(vel.z * WOBBLE_GAIN, -WOBBLE_MAX, WOBBLE_MAX),
		clamp(-vel.x * WOBBLE_GAIN, -WOBBLE_MAX, WOBBLE_MAX))
	var accel := (target - piece.wobble) * WOBBLE_STIFF - piece.wobble_vel * WOBBLE_DAMP
	piece.wobble_vel += accel * delta
	piece.wobble += piece.wobble_vel * delta
	if piece.body:
		piece.body.rotation = Vector3(piece.wobble.x, 0.0, piece.wobble.y)

# --- Validation -------------------------------------------------------------
func validate() -> void:
	var order: Array = []
	var seated := 0
	for s in seats:
		var occ = (s as Slot3D).occupant
		if occ:
			order.append(occ.char_id)
			seated += 1
		else:
			order.append("")

	var ctx := {"order": order, "num": seats.size(), "db": item_db, "items": pieces.keys()}
	var board_full := seated == seats.size() and seated > 0
	var all_pass := true
	for i in range(display_groups.size()):
		var st := _group_state(ctx, display_groups[i]["rules"], board_full)
		if i < rule_line_labels.size():
			rule_line_labels[i].add_theme_color_override("font_color", _state_color(st))
		if st != RuleEngine.STATE_PASS:
			all_pass = false

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

func _state_color(st: int) -> Color:
	match st:
		RuleEngine.STATE_PASS:
			return Color("#5cd65c")
		RuleEngine.STATE_FAIL:
			return Color("#ff6b6b")
	return Color("#9aa0aa")  # pending / grey

# --- 2D UI overlay ----------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Holds the crisp 2D pedal labels, behind the rest of the UI.
	piece_label_root = Control.new()
	piece_label_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	piece_label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(piece_label_root)

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
	col.add_child(title_label)

	var instr := Label.new()
	instr.text = "Drag each pedal onto a slot to satisfy every rule."
	instr.add_theme_color_override("font_color", Color("#bbbbbb"))
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

	rules_panel = PanelContainer.new()
	rules_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rules_panel.offset_left = RULES_SHOWN_LEFT
	rules_panel.offset_right = RULES_SHOWN_LEFT + RULES_WIDTH
	rules_panel.offset_top = RULES_TOP
	rules_panel.offset_bottom = RULES_BOTTOM
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.11, 0.11, 0.16, 0.92)
	psb.set_corner_radius_all(10)
	psb.set_content_margin_all(16)
	rules_panel.add_theme_stylebox_override("panel", psb)
	root.add_child(rules_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	rules_panel.add_child(outer)

	var rules_title := Label.new()
	rules_title.text = "Rules"
	rules_title.add_theme_font_size_override("font_size", 20)
	outer.add_child(rules_title)

	rules_content = VBoxContainer.new()
	rules_content.add_theme_constant_override("separation", 6)
	outer.add_child(rules_content)

func _present_rules() -> void:
	# Show the panel at stage start, then let it auto-tuck after a moment.
	rules_hold = true
	rules_shown = true
	if rules_panel:
		rules_panel.offset_left = RULES_SHOWN_LEFT
		rules_panel.offset_right = RULES_SHOWN_LEFT + RULES_WIDTH
	get_tree().create_timer(RULES_HOLD_SEC).timeout.connect(func(): rules_hold = false)

func _update_drawer() -> void:
	if rules_panel == null:
		return
	var want := rules_hold
	if not want:
		var mp := get_viewport().get_mouse_position()
		var screen_w: float = get_viewport().get_visible_rect().size.x
		# Reveal when the cursor nears the right edge, or is over the open panel.
		want = mp.x >= screen_w - RULES_REVEAL_MARGIN or (rules_shown and rules_panel.get_global_rect().has_point(mp))
	if want != rules_shown:
		_slide_rules(want)

func _slide_rules(show_it: bool) -> void:
	rules_shown = show_it
	var target_left := float(RULES_SHOWN_LEFT if show_it else RULES_HIDDEN_LEFT)
	if rules_tween != null and rules_tween.is_valid():
		rules_tween.kill()
	rules_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rules_tween.tween_property(rules_panel, "offset_left", target_left, 0.25)
	rules_tween.tween_property(rules_panel, "offset_right", target_left + RULES_WIDTH, 0.25)

func _on_next() -> void:
	show_stage(current_stage + 1)

func _on_reset() -> void:
	dragging = null
	for s in seats:
		(s as Slot3D).occupant = null
	for t in tray_slots:
		(t as Slot3D).occupant = null
	var order := pieces.keys()
	for i in range(order.size()):
		_place(pieces[order[i]], tray_slots[i])
	validate()
