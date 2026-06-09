# Exporting to the web (playable on GitHub Pages, desktop + mobile)

The 3D scene, config files, and pedal models are all set up to work in a web
build. Follow these steps once; after that, re-exporting + pushing is all it takes.

## 1. One-time: install export templates
Godot editor → **Editor → Manage Export Templates… → Download and Install**
(matches your Godot version).

## 2. One-time: project settings for touch (mobile)
**Project → Project Settings → Input Devices → Pointing**
- Ensure **Emulate Mouse From Touch** is **On** (default). This makes tap-and-drag
  work on phones/tablets, since the game uses mouse input.

## 3. Create the Web export preset
**Project → Export… → Add… → Web**, then set:

- **Export Path:** `docs/index.html`
  (Export into the `docs/` folder — that's what GitHub Pages will serve, and it
  already contains `coi-serviceworker.js` and `.nojekyll`.)

- **Resources tab → "Filters to export non-resource files/folders":**
  ```
  *.csv, *.json
  ```
  Without this, the stages/items config won't be in the build and no level loads.

- **HTML section → Head Include:** paste this so the cross-origin-isolation
  service worker loads (required for the game to run on GitHub Pages):
  ```html
  <script src="coi-serviceworker.js"></script>
  ```

- (Optional) **Progressive Web App → Enable** if you want an "install to home
  screen" experience on mobile.

## 4. Export
With the Web preset selected, click **Export Project**, save as `docs/index.html`.
Overwrite when re-exporting later. (Leave `coi-serviceworker.js` and `.nojekyll`
in `docs/` — don't delete them.)

## 5. Push and enable GitHub Pages
1. Commit the `docs/` folder (and the rest of the project) and push to GitHub.
2. Repo **Settings → Pages → Build and deployment**:
   - **Source:** Deploy from a branch
   - **Branch:** `main`  •  **Folder:** `/docs`
3. Wait ~1 minute. Your game is at
   `https://<your-username>.github.io/<repo-name>/`.

## Notes / gotchas
- **First load may reload itself once** — that's `coi-serviceworker.js` enabling
  cross-origin isolation. Normal. If you see a blank page or a
  "SharedArrayBuffer is not defined" error, the Head Include step was missed.
- **Mobile:** drag works via touch. The rules drawer reveals when the pointer is
  near the right edge — on touch, tap near the right edge to slide it out.
- **Re-exporting:** just repeat step 4 and push. No need to touch settings again.
- The renderer is already **GL Compatibility**, which is the most browser- and
  mobile-friendly choice, so no change needed there.
