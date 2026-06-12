# AI Context — Pedalboard Puzzle

Knowledge handover for anyone (human or AI) picking up this project. Written 2026-06-12.
Updated 2026-06-12 (settings, stage select, save system, export hardening).

## What this is

A **2D drag-and-drop puzzle game** built in **Godot 4.6 (GDScript)**, in the spirit of
"Is This Seat Taken?". The player drags guitar **pedals** onto a row of **slots** on a
pedalboard so that every **rule** for the current stage is satisfied. Rules are
attribute-based (position, adjacency, ordering, counts, grouping) and are **data-driven**
from CSV/JSON config — no code change is needed to author a new puzzle.

The game ships as a **web build** (WASM) served from GitHub Pages out of the `docs/` folder.

- Main scene: `game2d.tscn` → `Game2D.gd` (this is what actually runs).
- Theme/flavor: customers "email" you pedalboard build requests (the mail icon), you fulfill
  the rules, and a results screen rates the build with 1–3 stars.

## Tech stack & conventions

- **Engine:** Godot 4.6, GL Compatibility renderer (most browser/mobile-friendly). 3D physics
  config (Jolt) lingers in `project.godot` but is unused — the game is fully 2D now.
- **Language:** GDScript only. Tabs for indentation (see `.editorconfig`).
- **Design space:** fixed `1280×720` (`DESIGN` const), stretched with `canvas_items` / `expand`.
  All layout math is in design-space pixels.
- **Input:** mouse-driven, with "Emulate Mouse From Touch" ON so tap-drag works on mobile.
- **Persistence:** `user://save.cfg` stores unlocked stage, per-stage stars, language, music.

## Architecture / file map

### Data + logic layer (shared, engine-agnostic, well-isolated)
- **`ItemDB.gd`** — loads pedal specs from a CSV into dictionaries. Aliases whatever the name
  column is called to canonical key `"Name"`. `get_item(name)` lookup.
- **`StageDB.gd`** — loads stages + rules from `config/*stage*.csv` (one row per rule) or falls
  back to `config/stages.json`. The big header comment is the **authoritative spec** for the
  CSV columns and the selector mini-language. Converts 1-based sheet slots to 0-based engine.
- **`RuleEngine.gd`** — pure, static rule evaluation + live tri-state (PENDING/PASS/FAIL) +
  human-readable `describe()`. This is the heart of the puzzle logic. Rule types:
  `position`, `adjacent`, `group_together`, `order`, `count`, `no_adjacent_same`.
  Selectors pick items by `all` / `name` / `tag` / `field=value` / `same:field`.

### Presentation layer
- **`Game2D.gd`** — ~3100 lines, the whole game: world build, board/slot/piece creation,
  drag handling, wobble/shadow/burst juice, rules tracker UI, mail panel, pedal spec card,
  results screen, stage-select carousel, starting screen, settings. Function index is at the
  top of the file (grep `^func`). It owns all UI; the data layer above stays unchanged.
- **`Piece2D.gd`** / **`Slot2D.gd`** — thin data holders (a pedal token / a board-or-tray slot).
  Logic lives in `Game2D.gd`; these just hold node refs + state.
- **`BurstEffect.gd`** — self-freeing "pop" particle ring played when a pedal lands.
- **`DotLeader.gd`** — dotted leader line for the pedal spec sheet rows.

### Legacy / dead code — do not extend
- **`Main.gd`** + `main.tscn` — the original "Seat the Guests" prototype (hardcoded guests,
  5 seats). **Not the running scene.** Kept for reference only.
- **`Piece.gd`** / **`Slot.gd`** — old Control-based versions used by `Main.gd`.
- **`Game2D copy.gd`** — a stub/leftover, ignore.
- Mentions of a former `Game3D.gd` (GLTF 3D version) in comments — the project was ported
  3D → 2D (see git history); the data layer was carried over unchanged.

### Config / content (`config/`)
- **`pedalboard game info - Pedals.csv`** — the live item DB (`ITEMS_CSV` in `Game2D.gd`).
  Columns: Pedal Name, Brand, Color, Category 1, Category 2, Size, Bypass, Era, Power, Extra.
- **`stages.csv`** — the live stage/rule definitions (one row per rule; stage-level columns
  only on the first row of each stage). `stages.json` is the fallback.
- **`stage_mail.csv`** — the customer "email" shown per stage (sender, subject, body, avatar).
- **`*.translation`** files + `settings_language` (`en` / `pt-br`) — localization.
- `Sheet1.csv` is an older/simpler item sheet; the Pedals.csv is current.

### Assets (`assets/`)
`pedals/`, `background/`, `starting_screen/`, `ui/` (icons, avatar), `fonts/` (Baloo2 family),
plus reference images. Pedal art is mapped by name via `PEDAL_PATHS` in `Game2D.gd` — **folder
scanning does not work in web exports**, so paths are hardcoded (a `Model` CSV column can
override per item).

## How a stage runs (data flow)

1. `_ready()` → `ItemDB.load_csv()` and `StageDB.load_stages()` populate items + stages.
2. `show_stage(idx)` sets up slots/tray, instantiates `Piece2D` per item, applies the mail.
3. `_build_display_groups()` bundles rules sharing a `(Stage, Group)` id into one AND-requirement
   shown as a single tracker line (green only when ALL its rules pass).
4. On every drop, `validate()` builds a `ctx = {order, num, db, items}` and asks `RuleEngine`
   for each rule's live state, updates the tracker/progress, and detects stage completion.
5. Board full + all rules pass → `_show_results()` rates the build (stars) and unlocks the next.

## Build & deploy

See **`EXPORT.md`** for the full, authoritative steps. Summary:
- Export target is **Web**, output to **`docs/index.html`** (GitHub Pages serves `/docs` on `main`).
- Must export non-resource files: `*.csv, *.json` (else no levels load).
- Head Include must load `coi-serviceworker.js` (cross-origin isolation; without it you get a
  blank page / "SharedArrayBuffer is not defined"). Keep `coi-serviceworker.js` and `.nojekyll`.
- Re-export = overwrite `docs/index.html`, commit, push. Live at `https://<user>.github.io/<repo>/`.
- The committed `docs/` build artifacts (`index.wasm` ~36 MB, `.pck`, etc.) are checked in.

## Authoring content (no code needed)

- **New pedal:** add a row to `config/pedalboard game info - Pedals.csv`; add art + a
  `PEDAL_PATHS` entry (or a `Model` column) so it renders.
- **New stage/rule:** add rows to `config/stages.csv`. Read the `StageDB.gd` header comment
  first — it documents every column, the selector syntax (`all`, `name:`, `tag:`, `field=value`,
  `same:field`), and the count operator word-aliases (use "at most", not `<=`, so Google Sheets
  doesn't treat the cell as a formula). Rows with the same `(Stage, Group)` are AND-bundled.

## Gotchas & notes

- **Web file access:** `FileAccess.open` is used directly (not `file_exists`/`DirAccess` scans)
  because directory listing is unreliable in web builds. Keep this pattern for any new loaders.
- **Live rule state is deliberately lenient:** "must sit next to" never goes red prematurely
  (the neighbor might still arrive); prohibitions go red instantly. See `RuleEngine.state()`.
- **Slot indexing:** sheets are 1-based, the engine is 0-based — `StageDB` converts on load.
- **`Game2D.gd` is monolithic** by design (one file owns all presentation). Use the function
  list at the top to navigate; the data layer is where logic changes usually belong.
- Lots of "juice" constants near the top of `Game2D.gd` (wobble, shadows, burst, slide tweens)
  — safe to tune for feel without touching logic.

## Quick start for a new contributor

1. Open the project in Godot 4.6; press Play (`game2d.tscn` runs).
2. To change puzzles, edit `config/stages.csv` + `pedalboard game info - Pedals.csv`.
3. To change game feel/UI, work in `Game2D.gd`. To change rule semantics, work in `RuleEngine.gd`.
4. To ship, follow `EXPORT.md` and push `docs/`.

## New features added 2026-06-12

### Settings popup (Layer 8)
- `_build_settings()` in Game2D.gd — card-styled modal (cream bg, tan header, drop shadow).
- Language toggle: EN / PT-BR (persisted). Music checkbox.
- "Clear progress" debug button — deletes `user://save.cfg`.

### Save / progress system
- `user://save.cfg` — `_save_progress()` on stage complete, `_load_progress()` on startup.
- Stores `highest_stage`, per-stage `stage_N_stars`, language, music.

### Stage selection screen (Layer 9)
- "Stages" button on results card. Full-screen carousel with snap-to-center scrolling.
- Tiles: unlocked show number + stars; locked show icon. Two-click to select.
- Spacers so edge tiles can center. Unlock: `_get_saved_stage() + 1`.

### Export hardening
- **StageDB**: `_parse_fallback()` — hardcoded JSON for all 3 stages.
- **ItemDB**: `_load_fallback()` — hardcoded dict array with all 5 pedals.
- `_find_csv()` uses `FileAccess.open()` directly (not `file_exists`).
- `_ready()` logs errors to browser console if data fails to load.
