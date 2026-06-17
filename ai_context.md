# AI Context — Pedalboard Puzzle

Knowledge handover for anyone (human or AI) picking up this project. Written 2026-06-12.
Updated 2026-06-16 (multi-slot pedals, 3×2 boards, secret tasks, polaroid preview, UI scaling).
Updated 2026-06-17 (tray filter button offset fix; known-issues list).

## What this is

A **2D drag-and-drop puzzle game** built in **Godot 4.6 (GDScript)**, in the spirit of
"Is This Seat Taken?". The player drags guitar **pedals** onto a row of **slots** on a
pedalboard so that every **rule** for the current stage is satisfied. Rules are
attribute-based (position, adjacency, ordering, counts, grouping) and are **data-driven**
from CSV/JSON config — no code change is needed to author a new puzzle.

The game ships as a **web build** (WASM) served from GitHub Pages out of the `docs/` folder.

- Main scene: `game2d.tscn` → `Game2D.gd` (this is what actually runs).
- Theme/flavor: customers "email" you pedalboard build requests (the mail icon), you fulfill
  the rules, and a results screen rates the build with **1–2 stars**.

## Tech stack & conventions

- **Engine:** Godot 4.6, GL Compatibility renderer (most browser/mobile-friendly). 3D physics
  config (Jolt) lingers in `project.godot` but is unused — the game is fully 2D now.
- **Language:** GDScript only. Tabs for indentation (see `.editorconfig`).
- **Design space:** fixed `1280×720` (`DESIGN` const), stretched with `canvas_items` / `expand`.
  All layout math is in design-space pixels.
- **Input:** mouse-driven, with "Emulate Mouse From Touch" ON so tap-drag works on mobile.
- **Persistence:** `user://save.cfg` stores unlocked stage, per-stage stars, language, music,
  per-stage secret task reveal state.

## Architecture / file map

### Data + logic layer (shared, engine-agnostic, well-isolated)
- **`ItemDB.gd`** — loads pedal specs from a CSV into dictionaries. Aliases whatever the name
  column is called to canonical key `"Name"`. `get_item(name)` lookup.
- **`StageDB.gd`** — loads stages + rules from `config/*stage*.csv` (one row per rule) or falls
  back to `config/stages.json`. The big header comment is the **authoritative spec** for the
  CSV columns and the selector mini-language. Converts 1-based sheet slots to 0-based engine.
  Now parses `Secret` column and `Board` column (or `NxM` from Slots field).
- **`RuleEngine.gd`** — pure, static rule evaluation + live tri-state (PENDING/PASS/FAIL) +
  human-readable `describe()`. Rule types: `position`, `adjacent`, `group_together`, `order`,
  `count`, `no_adjacent_same`. Updated for 2D grid adjacency (`_neighbors()`, 4-connected)
  and multi-slot pedal awareness (`_all_slots_of()`).

### Presentation layer
- **`Game2D.gd`** — ~3400 lines, the whole game: world build, board/slot/piece creation,
  drag handling, wobble/shadow/burst juice, rules tracker UI, mail panel, pedal spec card,
  results screen (with polaroid board preview), stage-select carousel, starting screen,
  settings. Function index is at the top of the file (grep `^func`).
- **`Piece2D.gd`** — holds `size_w`, `size_h`, `occupied_seats` for multi-slot pedals.
- **`Slot2D.gd`** — holds `col`, `row` for grid positioning.
- **`BurstEffect.gd`** — self-freeing "pop" particle ring played when a pedal lands.
- **`DotLeader.gd`** — dotted leader line for the pedal spec sheet rows.

### Legacy / dead code — do not extend
- **`Main.gd`** + `main.tscn` — the original "Seat the Guests" prototype. Not the running scene.
- **`Piece.gd`** / **`Slot.gd`** — old Control-based versions used by `Main.gd`.
- **`Game2D copy.gd`** — a stub/leftover, ignore.

### Config / content (`config/`)
- **`pedalboard game info - Pedals.csv`** — the live item DB (`ITEMS_CSV`). 16 pedals.
  Columns: Pedal Name, **Asset** (filename stem), Brand, Color, Category 1, Category 2,
  **Size** (e.g. "1x1", "2x1", "1x2"), Bypass, Era, Power, Extra, budget.
- **`stages.csv`** — the live stage/rule definitions (one row per rule). Supports `Board`
  column (e.g. "3x2") and `Secret` column (TRUE/FALSE for hidden bonus tasks).
  `stages.json` is the fallback.
- **`stage_mail.csv`** — the customer "email" per stage (sender, subject, body, avatar).
- **`*.translation`** files + `settings_language` (`en` / `pt-br`) — localization.

### Assets (`assets/`)
- **`boards/`** — pedalboard art: `pedalboard.png` (3×1), `pedalboard_3x2.png` (3×2),
  `pedalboard_4.png` (4×1), `pedalboard_5.png` (5×1).
- **`pedals/`** — all 16 pedal art files (mapped by `Asset` CSV column or `PEDAL_PATHS`).
- `background/`, `starting_screen/`, `ui/` (icons, avatar), `fonts/` (Baloo2 family).

Pedal art paths are resolved in order: `Model` CSV column → `Asset` CSV column →
`PEDAL_PATHS` hardcoded dict (fallback for web exports where folder scanning fails).

## How a stage runs (data flow)

1. `_ready()` → `ItemDB.load_csv()` and `StageDB.load_stages()` populate items + stages.
2. `show_stage(idx)` sets up the board grid (cols × rows), instantiates `Piece2D` per item
   with their parsed `Size`, applies the mail, and builds display groups (normal + secret).
3. `_build_display_groups()` bundles rules sharing a `(Stage, Group)` id into one AND group.
   Rules with `secret = true` are isolated into their own group (shown as "??????" until
   completed once).
4. On every drop, `validate()` builds a `ctx = {order, num, db, items, cols, rows}` and
   asks `RuleEngine` for each rule's live state. Normal groups determine win/loss; the
   secret group determines the bonus star. Updates rule tracker and detects completion.
5. Board full + all *normal* tasks pass → `_show_results()` rates the build (1–2 stars)
   and unlocks the next stage.

## Multi-slot pedal system

Pedals with `Size` > 1×1 (e.g. "2x1" Klon, "1x2" Wahwah) occupy multiple grid slots:
- **2x1** extends leftward (+col), visually centred between the two slots
- **1x2** extends upward (+row), visually centred between the two slots

Placement rules:
- `_occupied_seats_for()` computes which seats a piece would occupy from its anchor slot
- `_end_drag()` checks conflicts on ALL occupied seats before placing
- Displaced multi-slot pieces always go to the tray (can't swap into a single slot)
- `_neighbors()` in RuleEngine uses 4-connected grid adjacency for 2D boards

## Secrets & star system

- Stages can have a **secret task** (set `Secret=TRUE` in CSV). Shown as "??????" until
  completed at least once, then the real description is revealed forever (saved per-stage).
- **1 star** = all normal tasks pass + board full
- **2 stars** = 1-star condition + secret task also passes
- Results screen shows "Task complete" and "Secret objective" checkboxes.
- Max 2 star slots in both results and stage select carousel.

## Results board preview (polaroid)

The results screen shows a polaroid-style photo of the finished board:
- Floating overlay at top-right, overlapping the results card
- Random ±3° rotation for a "stuck-on" look
- Thick white border with solid drop shadow (CARD_SHADOW, offset 4,8)
- Appears 1s after the results card slides in (delayed reveal tween)
- Photo content rotates with the border via a Node2D wrapper
- Shadow: offset Panel with `CARD_SHADOW` (black, 0.22 alpha, no blur)

Shadow guideline used throughout the project: **solid offset silhouette, no blur,
`Color(0, 0, 0, 0.20)` (SHADOW_COLOR) or `Color(0, 0, 0, 0.22)` (CARD_SHADOW),
offset `Vector2(4, 8)`**.

## Drawer animation

- Drawer sprite, tray pedals, and filter bar all shift together via `_drawer_offset`
- Closed: offset = -295 (above screen), Open: offset = 0
- `_open_drawer()`: `TRANS_BACK` / `EASE_OUT` / 0.5s
- `_close_drawer(on_closed, duration, ease, trans)`: configurable
- Stage completion close: 1.0s `TRANS_EXPO` `EASE_OUT`
- Filter change close: 0.35s `TRANS_CUBIC` `EASE_IN` → swap → open
- References: `_apply_drawer_offset()`, `_drawer_offset`, `_drawer_tween`, `_drawer_sprite`

## Starting screen buttons

- Play → newest unlocked stage
- Stages button (hidden until progress, purple `#8b7fc7`)
- Settings button
- All styled with `_make_game_button()`

## UI constants (tune here)

All values from `Game2D.gd` constants section:

| Constant | Value | Purpose |
|----------|-------|---------|
| `DESIGN` | `Vector2(1280, 720)` | Design space / virtual resolution |
| `UI_SCALE` | `0.85` | Global pedal/board/slot scale reduction |
| `SEAT_SPACING` | `100.0` | Horizontal gap between slot centres |
| `SEAT_ROW_SPACING` | `140.0` | Vertical gap between row centres on multi-row boards |
| `SEAT_BOTTOM_ROW_Y` | `240.0` | Fixed Y of the bottom row on multi-row boards |
| `SEAT_Y` | `172.0` | Y of the row of seats on single-row boards |
| `TRAY_Y` | `490.0` | Y of the spare-pedal tray |
| `DRAWER_Y` | `425.0` | Drawer sprite centre Y |
| `DRAWER_LEFT` | ~236 | Drawer horizontal left bound |
| `DRAWER_RIGHT` | ~1044 | Drawer horizontal right bound |
| `PEDAL_W` | `104.0` | On-screen width of a pedal |
| `SNAP_DIST` | `92.0` | Drop-to-slot snap threshold |
| `BOARD_PAD` | `70.0` | Board sprite extends past end seats |

## Build & deploy

See **`EXPORT.md`** for the full, authoritative steps. Summary:
- Export target is **Web**, output to **`docs/index.html`** (GitHub Pages serves `/docs` on `main`).
- Must export non-resource files: `*.csv, *.json` (else no levels load).
- Head Include must load `coi-serviceworker.js` (cross-origin isolation; without it you get a
  blank page / "SharedArrayBuffer is not defined"). Keep `coi-serviceworker.js` and `.nojekyll`.
- Re-export = overwrite `docs/index.html`, commit, push. Live at `https://<user>.github.io/<repo>/`.
- Committed `docs/` build (`index.wasm` ~36 MB, `.pck`, etc.) are checked in.

## Authoring content (no code needed)

- **New pedal:** add a row to `config/pedalboard game info - Pedals.csv`; add art to
  `assets/pedals/` with the filename matching the `Asset` column. The `Size` column
  controls how many grid slots it occupies. The `PEDAL_PATHS` dict may need a new entry
  for web export safety.
- **New stage/rule:** add rows to `config/stages.csv`. Read the `StageDB.gd` header comment
  first for the full column spec. Key columns: `Board` for grid layout (e.g. "3x2"),
  `Secret=TRUE` for hidden bonus tasks. Rows with the same `(Stage, Group)` are AND-bundled.
  The `Slots` field can include the layout (e.g. "6 (3x2)") — `StageDB` parses it.

## Gotchas & notes

- **Web file access:** `FileAccess.open` is used directly (not `file_exists`/`DirAccess` scans)
  because directory listing is unreliable in web builds. Keep this pattern for any new loaders.
- **Live rule state is deliberately lenient:** "must sit next to" never goes red prematurely
  (the neighbor might still arrive); prohibitions go red instantly. See `RuleEngine.state()`.
- **Slot indexing:** sheets are 1-based, the engine is 0-based — `StageDB` converts on load.
- **Board grid:** col 0 = rightmost (first in signal chain), row 0 = bottom (row A).
  Multi-slot pieces extend leftward (+col) and upward (+row).
- **Control → Node2D rotation:** In Godot 4, rotating a Control (`Panel`) does NOT reliably
  cascade to Sprite2D children. Always use a `Node2D` wrapper for rotation-heavy structures
  (e.g. the polaroid preview uses a Node2D root whose transform cascades to all child types).
- **`UI_SCALE = 0.85`** — global 15% scale reduction on pedals, boards, and slot markers.
- **`SEAT_ROW_SPACING = 140`**, **`SEAT_BOTTOM_ROW_Y = 240`** — bottom row fixed, top row
  stacks upward.
- **`Game2D.gd` is monolithic** by design. Use the function list at the top to navigate.
- Lots of "juice" constants near the top of `Game2D.gd` — safe to tune for feel.
- **Pedal label z-ordering:** labels are children of `Piece2D`, inheriting the piece's
  `z_index`. Works for tray pedals (behind bg_2) but may have edge cases during drag transitions.

## Quick start for a new contributor

1. Open the project in Godot 4.6; press Play (`game2d.tscn` runs).
2. To change puzzles, edit `config/stages.csv` + `pedalboard game info - Pedals.csv`.
3. To change game feel/UI, work in `Game2D.gd`. To change rule semantics, work in `RuleEngine.gd`.
4. To ship, follow `EXPORT.md` and push `docs/`.

## Quick code reference

| File | Role |
|------|------|
| `Game2D.gd` | ~3400 lines — all game logic |
| `RuleEngine.gd` | Puzzle rule evaluation |
| `StageDB.gd` | CSV/JSON stage loading |
| `ItemDB.gd` | CSV item database |
| `Piece2D.gd` / `Slot2D.gd` | Data holders |

---

## 2026-06-17 — Tray filter button offset fix

### Problem

When transitioning between stages, the tray filter button group (category filter pills above
the drawer) shifted/offset to the right. First stage: centred correctly. Every subsequent
`show_stage()` call: drifted right. Buttons also rendered **above** `bg_2` instead of between
`bg_drawer` and `bg_2`.

### Root causes

1. **No persistent bar reference** — the `HBoxContainer` bar was looked up each time by
   iterating `world_root.get_children()` via `bar_meta("bar")`, risking stale/wrong hits.
2. **Missing z_index** — the bar had no explicit `z_index` (defaulted to 0), putting it
   in front of `bg_2` (z=-19) instead of behind it.
3. **`PRESET_FULL_RECT` under Node2D** — the bar used `set_anchors_and_offsets_preset`
   which resolves against the viewport when the parent is a `Node2D`, causing inconsistent
   sizing on subsequent stage loads.
4. **Overlapping children on rebuild** — old wrappers were `queue_free()`d but not removed
   until end of frame, so the HBoxContainer laid out old + new children together, then
   shifted when the old ones were finally freed.

### What was changed (`Game2D.gd`)

- **Added class var** `tray_filter_bar: HBoxContainer = null` (~line 217) for direct access.
- **`_build_tray_filter()`** — replaced `PRESET_FULL_RECT` with explicit anchors at 0,
  explicit `position`/`size` (`Vector2(600, 50)` at `Vector2(DESIGN.x * 0.5 - 300, 320)`),
  and `z_index = -21`. Stores reference in `tray_filter_bar`.
- **`_setup_tray_filter_buttons()`** — uses `tray_filter_bar` directly. Restructured to
  prepare all button wrappers in a temp array, then show the bar and add children so layout
  recalculates with only the new children.
- **`_clear_stage()`**, **`_apply_drawer_offset()`**, **`_apply_tray_filter()`** — all updated
  to use `tray_filter_bar` directly instead of `bar_meta("bar")`.
- **`bar_meta()` function** — now unused (can be safely deleted in a future cleanup).

### Corrected layer order (z_index)

| Element | z_index |
|---------|---------|
| bg_1 | -22 |
| drawer sprite | -21 |
| filter panel | -21 |
| **filter bar** | **-21** (was 0) |
| bg_2 | -19 |
| board shadow | -11 |
| board sprite | -10 |
| pedals/UI | 0+ |

## Current known issues

1. **Pedal label z-ordering** — Labels are children of Piece2D, inheriting piece z_index.
   Works for tray (behind bg_2) but may have edge cases during drag transitions.

2. **Drawer close on stage complete** — May overlap with results animation timing.

### Follow-up cleanup tasks

- **Remove dead code**: `bar_meta(key: String)` at ~line 2782 is no longer called.
- **`_drawer_group`**: declared at ~line 208 but never used — either remove or implement
  the planned grouping of drawer-related elements.
- **Architecture note**: the filter bar is a `Control` child of `world_root` (`Node2D`).
  The explicit anchor+position workaround is safe, but a future refactor could move the
  bar under a proper Control/CanvasLayer parent.
