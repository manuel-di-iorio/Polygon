# Polygon Architecture

A detailed, feature-by-feature description of how the Polygon in-game 3D
scene editor works. Companion to `README.md` (user guide) and
`docs/index.html` (web docs). References are `scripts/<name>/<name>.gml`
plus `function` names; line numbers are omitted on purpose (they drift).

Target reader: a developer who wants to extend, debug, or embed Polygon.

---

## 1. Big picture

Polygon opens **inside the running game** (F1 in the demo) and edits a
**mirror copy** of the live scene. It never touches game instances or the
live scene graph: on every enable it imports the live world into its own
`GM3D_Scene`, and everything (transforms, spawn, undo, save) happens on
the mirror. On close, the game optionally rebuilds its live scene from
editor descriptors (`on_close`).

```
Game world (live_scene, instances)      Editor world (rt.scene, wrappers)
───────────────────────────────         ──────────────────────────────────
oGame creates oEditor ──► poly_create ──► own GM3D_Scene + GM3D_Renderer
F1 ──► poly_enable ──► import_live: adopt live roots as copies
Edit (gizmo, panels, undo) on the mirror
File → Save ──► JSON v1 / PLYB .bin      poly_load (no editor): spawn file
Close ──► on_close ──► game rebuilds live from descriptors
```

Core principles:

- **Wrapper identity**: every tracked root is a wrapper node whose **name
  IS its id** (`__PolygonEditor__N`). All comparison, selection,
  serialization and undo-restore work by name, never by reference
  (GMRT may hand out fresh structs for the same native node).
- **Whole-scene undo**: snapshots, not deltas (one JSON string + selection
  descriptors per entry, cap 100).
- **Cached viewport**: the 3D view renders to a surface and re-renders only
  when something changed (dirty key); overlays compose on top at display
  resolution so they stay sharp under any AA mode.
- **Unified spawn pipeline**: one `__poly_spawn` function serves editor
  placement, import, load, duplicate, paste and AI creation.

---

## 2. Lifecycle and frame flow

Public API (`poly_create`, `poly_enable`, `poly_disable`,
`poly_is_active`, `poly_step`, `poly_draw`, `poly_draw_ui`,
`poly_cleanup`, `poly_ai_net`) is wired to `oEditor` events
(Create / Step / Draw / Draw GUI / Async Networking / Clean Up).

- `poly_create(config)` (`poly_create.gml`): wraps the adapter into `rt`
  (`__poly_create_rt` copies only `scene→live_scene`, `cam`, `assets`,
  `on_create/on_close/on_compose` - never instances), builds the `_ed`
  state, registers library assets, applies `keys` shortcut overrides
  (`__poly_keys_apply`), seeds the view camera.
- `poly_enable/disable` → `__poly_set_active` (`poly_core.gml`):
  flips `active`/`global.poly_active`.
  - Activate: save view sizes → `__poly_import_live` (destroy tracked
    roots, clear registry, adopt every live root, ensure
    camera/sun/env) → grid/sky ensure, mute scene cameras, seed viewcam,
    clear selection+history, `scene_file=""`, snapshot `open_snapshot`.
  - Deactivate: clear drag preview, restore view/background, remove
    grid/sky, restore cameras, park the viewcam, restore shadows/unlit,
    call `rt.on_close()`.
- `poly_step()` (`poly_step.gml`): `__poly_step(dt)` then AI step then
  `__poly_imgui_draw`. `__poly_step` order (`poly_core.gml`):
  1. window/GUI sizes, F9 FPS toggle, `__poly_view_sync`;
  2. lazy `open_snapshot`, chunked-load pump (`load_job`);
  3. input context; modal open (confirm/about/scene dialog) → handle
     Esc and return;
  4. camera owner/key/viewport gates → `__poly_cam_fly` →
     `__poly_cam_anim_step` → grid ensure/follow, sky ensure/sync;
  5. hotkeys → Esc-cancel chain → gizmo drag → library drop → rect
     select → hover/click (early-return chain).
- `poly_draw()` (`poly_draw.gml`): shader warmup once; if active:
  `scene.update(0)`, freeze camera pose, compute `hi_ready`, pump
  thumbnail/material/animation queues; then in strict order:
  GPU-pick → outline capture → main viewport render → AI offscreen
  capture. `poly_draw_ui()`: modal dim + Models drag ghost only.
- `poly_cleanup()`: frees outline/pick/AI/thumbs/materials/anim
  resources, all surfaces and SMAA LUT sprites, restores view,
  background, cameras, unlit mode, grid/sky; clears globals.

`_ed` (editor state, `__poly_create_state`) holds: `rt`, `renderer`,
`cfg` (`keys` binding table from `__poly_keys_defaults`, `snap`,
`gizmo_px`), `active/dirty`, `assets[]`, `sel[]`,
`clipboard`, `reg{}` + `id_seq`, `asset_meta{}`, undo/redo stacks,
`giz{}`, cameras (`viewcam`, `cam_home/anim/orbit/...`), `scene_file`,
`open_snapshot`, `load_job`, snap/grid/sky/show flags, surfaces
(`scene_surf/hi`, `scene_smaa_e/w`), `aa_mode` (default `"smaa"`),
viewport sizes, cube offset, ImGui/window/thumbnail sub-states.

---

## 3. Scene model: wrappers, registry, spawn

`poly_registry.gml`. Invariant: **every tracked root is a wrapper**;
assets are `wrapper → model root`, lights/cameras/environments are a
single wrapper carrying the component.

- Ids: prefix `__PolygonEditor__`; `__poly_wrap_new` (monotonic
  `id_seq++`), `__poly_wrap_claim` (keep wanted id if free, else fresh;
  bumps the counter), `__poly_seq_reseed` (counter above max seen).
  Counter never goes backwards, ids are never reused.
- `reg` maps `id → {id, kind, asset, label, data, hidden, locked, node}`.
  `kind_register` refuses instance entries with empty asset and refuses
  to overwrite a live entry. `reg_clear` keeps `id_seq` monotonic.
- Lookup is by wrapper id (`__poly_registry_find`, `__poly_find_by_id`
  with `scene.getNode` + scan fallback). `__poly_node_same` compares
  names. Root lists skip non-roots, grid, drag preview
  (`__poly_root_tracked/list/pairs`, `__poly_tracked_nodes`).
- Kind resolution (`__poly_kind_of`): registry kind → own component →
  first-child component → `instance`.
- `__poly_spawn(_ed, opt)` is the single pipeline. `_ed` may be the
  editor state or a raw scene (runtime load skips registry/hooks).
  Kinds: `prefab/primitive → instance` (model `spawnInto(wrapper)`,
  child reset to identity so the wrapper owns TRS), `light/camera/
  environment` (component on the wrapper), `chrome` (untracked
  grid/sky). TRS accepts arrays or `x/y/z`, quaternion object/array or
  components. Pre-claimed `opt.id`; flags `skip_hook/skip_register/
  adopt_src`. Editor instance path: magenta fix → global `on_create`
  then per-model `on_create` → register + shadow-flag apply. Prop path:
  `light/camera/env_apply` → register.
- Import (`__poly_track_adopt_auto`): non-roots skipped; component
  nodes become light/camera/env adoptions (live wrapper id preserved);
  other nodes match the library **by model-root name, only on a unique
  candidate** - unmatched/ambiguous live nodes are skipped. Nothing
  starts hidden; scene cameras are muted while editing
  (only the viewcam renders).

`poly_props.gml` owns light/camera/environment data: one schema table
(`__poly_prop_schema`) drives defaults, guarded reads
(`__poly_read_num/vec/col`, `__poly_apply_field` with ignore-ranges),
and apply functions. Details: shadow resolution snapped to powers of
two 256–8192; camera `far > near`; env `fogEnd ≥ fogStart`; single
active shadow-map owner; gamecam = first enabled camera else first.

---

## 4. Cameras and navigation

`poly_camera.gml`. The editor uses its own `viewcam`
(`__editor_camera`), seeded from the gameplay camera on enable/activate
(`__poly_viewcam_seed_from`: copies TRS + camera settings, remembers
home). Tracked scene cameras stay muted while editing.

- Transitions: `__poly_cam_animate` (smoothstep position + slerped
  rotation, default 0.4 s); any manual move cancels the anim.
- Gestures (`__poly_cam_fly`, picked in `__poly_cam_gesture` from the
  `cam_*` bindings, priority orbit → zoom → fly → pan): `Alt+LMB`
  orbit (yaw about world up, then pitch; 0.18°/px), `Alt+RMB` zoom,
  `RMB` fly (`W/S` forward, `A/D` strafe, `E/Q` up, `Shift` ×2, wheel
  adjusts speed with on-screen notice; `Ctrl` reserves WASD for
  hotkeys), `MMB` or View-tool pan (depth-scaled). Orbit/zoom pivot on
  the selection pivot, else a point ahead. Cursor wraps at window edges.
- `F` frames the selection (`__poly_focus_selection`: AABB-union
  center, fit distance from fov/aspect, clamped 1.5–150, orientation
  preserved); double-click in Hierarchy selects + focuses one node;
  ViewCube faces snap orientation keeping distance; Home restores the
  remembered pose.

---

## 5. Selection, gizmo, transform

- Selection (`poly_selection.gml`): `_ed.sel[]`, all membership by id.
  `sel_assign` (reset drag + auto-tool), `sel_toggle` (locked can never
  be added), per-frame epoch lookup set. `scene_anchor` drives
  Ctrl+click range select in Hierarchy. Locking a node removes it from
  the selection; hidden nodes are skipped by tools but still selectable
  in the list.
- Tool gating (`__poly_tool_allowed`): instances everything,
  environment nothing, props never Scale, cameras all, lights Translate
  always / Rotate except point. Single-light selection auto-switches
  the tool (directional→Rotate, point→Translate).
- Gizmo (`poly_gizmo.gml`, drawn in `poly_gizmo_draw.gml`): Translate
  axes + planar quads (+ Shift screen-space square), Rotate rings +
  view-ring + trackball disc, Scale axes + center uniform handle.
  Pivot = average node position, Center = bounds center; World/Local
  axes; pixel-constant handle size. Drag lifecycle: press on hovered
  handle → `__poly_gizmo_begin` (history snapshot + `cmd_begin`,
  start transforms, frozen pivot, drag plane) → per-frame drag →
  release commits **one** undo entry (`gizmo-drag` coalescing);
  Esc restores start transforms.
- Snap: `snap_on` toggle (`` \ `` key), `Ctrl` held = momentary snap
  during drag; position step from grid or custom value, per-axis
  X/Y/Z flags, rotation step `snap_rot`. Arrows nudge on X/Z
  (0.25 or snap step, one undo). `Ctrl+\`` pushes the selection onto
  the grid (one undo).

---

## 6. History (undo/redo)

`poly_history.gml`. Snapshots, not deltas: `{json:
stringify(serialize_scene), sel: [descriptors]}`. `history_commit`
pushes the *before* snapshot (skipped when identical), caps 100, clears
redo, marks dirty. Gizmo drags coalesce through `cmd_open`
(`cmd_begin`/`cmd_commit`); every other op (create, delete, duplicate,
cut, paste, rename, nudge, push-to-grid, inspector edits, AI ops) is
one entry. Undo/redo (`Ctrl+Z`, `Ctrl+Y`/`Ctrl+Shift+Z`) pops, pushes
the current state on the other stack, `rebuild`s, restores selection by
id. History is cleared on activate/new/load/discard. Creation snapshots
*before* `createNode` so empty nodes never leak into undo.

---

## 7. Clipboard, invert, select-all, rename, focus-search

`poly_scene_ops.gml` (+ hotkeys in `poly_input.gml`):

- Copy/Cut/Paste work on **descriptors** (same structs as files), so
  instances, lights, cameras and env all survive: copy stores them (no
  undo); cut deletes in the same undo entry; paste deep-copies them,
  assigns fresh ids, reuses the rebuild placer (unknown models
  skipped), reselects the results, one undo. Also in the Hierarchy
  context menu.
- `Ctrl+I` inverts over tracked roots (locked excluded);
  `Ctrl+A` selects all (locked excluded); `Shift+D` clears.
- `F2` renames the instance label (undoable, empty/unchanged = no-op);
  Hierarchy rows show `label` else `asset #id`.
- `Ctrl+F` focuses the Hierarchy/Models search field, whichever panel
  was focused last frame (`__poly_focus_search`; one-shot focus flag
  consumed at draw).

---

## 8. Persistence: JSON v1 and binary PLYB

`poly_serialize.gml` / `poly_bin.gml` / `poly_files.gml`.

- Descriptors: `instance {kind, id, assetId, transform{position,
  rotation[xyzw], scale}, shadows{cast,receive}?, label?}`,
  `light/camera/environment` with a same-named sub-object
  (`type/color/intensity/range/innerCone/outerCone/enabled/shadow.*`,
  `projection/fovY/orthoWidth/orthoHeight/near/far/enabled`,
  `size/ambient/fogEnabled/fogColor/fogStart/fogEnd/enabled`).
  Strict validation (`__poly_validate_descs` + per-kind validators).
- JSON v1 file: `{version: 1, seq, assets: {key: {type: "model",
  actor?: {object, layer}}}, nodes: [...]}`. Saved with ordered,
  pretty stringify; `seq` keeps editor id counters monotonic across
  save/load.
- PLYB binary (`poly_bin.gml`, header documents the layout): magic
  `PLYB`, u16 version 1, s32 seq, u16 asset table (key + optional actor
  binding), u32 node table (kind byte, strings via `buffer_string`,
  f32 transforms, u8 colors, packed flag bits). Same content as JSON,
  field-by-field binary - never JSON-in-a-buffer. `buffer_save/load`
  with `try/catch`.
- Loading is always chunked (`begin` parses now, `pump` places ~48 nodes/step so the
  `load_job` (`begin` parses now, `pump` places ~48 nodes/step so the
  Load dialog shows progress instead of freezing, `finish` runs the
  shared tail: reseed, ensure camera/sun/env, reset selection, clear
  history). Format auto-detect: `.bin`/magic → binary, else JSON, with
  cross-extension fallback. Rebuild re-claims saved ids, restores
  hidden/locked states, mutes cameras.
- Files live in `working_directory/__PolygonEditor__/scenes/`
  (`poly_files.gml`); names sanitized; dialogs are state
  (`scene_dlg {mode, name, fmt, ...}`); Save prompts only when the
  scene has no file yet; dirty scenes go through the confirm dialog
  (Save / Don't save / Cancel). Delete removes the selected file
  (Load lists `.json`/`.bin` as separate rows).

---

## 9. Runtime loading and actors

`poly_load(scene, file, assets, on_create?, on_finish?)` (`poly_load.gml`) starts
an async job (parse now, spawn ~48/step via `poly_load_step()`); same hooks
and report as the old sync version, companions included.

Actors (`poly_load_internal.gml`): per-model `{object, layer}` bindings
stored in the file's top-level `assets` map spawn a companion instance
via `instance_create_layer(0, 0, layer, obj, {node, poly_id,
poly_asset_id})`. Binding is by object **name** (renames break it; the
Inspector flags unknown objects in red). Kill halves only through
`poly_actor_destroy(id|node)`; `poly_actor_of(node)` finds the
companion. Configured per model in the Inspector Actor section
(object combo + layer, `Instances` default); empty object = no binding.

---

## 10. Viewport rendering

`poly_imgui_viewport.gml` + `poly_draw.gml`.

- Surfaces: `scene_surf` (display size, clamped 160–1920 × 90–1080),
  `scene_hi` (scratch at pass size), `scene_smaa_e/w` (1x SMAA
  edges/weights). Surfaces are never freed while ImGui may reference
  them - a 16-frame graveyard retires them; resizes keep the old
  surface one frame and report "not ready" so the frame falls back to
  direct rendering.
- The view re-renders only when needed (`view_dirty`, gestures,
  selection change, or a cheap numeric snapshot diff); FPS text is
  drawn live in Draw GUI so it never bakes into the surface. Display
  uses integer sizes to avoid resampling.
- **One scale for all offscreen 3D passes** (`__poly_pass_scale`):
  mixed resolutions in one frame invalidate the WebGPU submit, so
  pick, outline mask and hi-res scene all render at the same scale.
- AA modes (`off / fxaa / smaa / ssaa`, default `smaa`):
  - SSAA: hi-res render into `scene_hi`, filtered downsample.
  - FXAA: 1x render + Lottes 3.11 resolve (`shPolygonEditorFXAA`).
  - SMAA 1x: 1x render → edge detect → blend weights (official LUTs
    `datafiles/__PolygonEditor__/smaa/`, baked 1:1 into surfaces,
    source sprites kept alive so queued submits stay valid) →
    neighborhood blend. Shaders are a faithful GLSL ES 1.00 port of
    the reference (bounded loops, no varying arrays).
  - Anything unavailable falls back to direct render + retry next
    frame (`aa_used = "pending"`).
- `__poly_compose_viewport` (`poly_core.gml`) runs on `scene_surf`:
  optional `on_compose(surf, w, h)` dev post-processing first (raw 3D
  only), then outline composite, gizmo, prop overlays, ViewCube,
  rect/selection art and notices - all 2D at display res, hence sharp
  under any AA mode.

---

## 11. Picking and outline

- GPU picking (`poly_gpu_pick.gml`): tracked roots (minus grid,
  preview, viewcam, sky, hidden) are painted with flat ID materials
  (`shPolygonEditorId(+Skin)`, id encoded R/B + G/255, mismatch =
  background) into an offscreen surface at pass scale. Click reads one
  pixel back (with depth cycling: repeated clicks cycle up to 8 deep
  hits); rubber-band reads the full buffer with a strided scan.
  Shift adds/toggles. Runs first in the Draw order so the outline sees
  the post-pick selection.
- Selection outline (`poly_outline.gml`): selected subtrees render
  white (`shPolygonEditorMask(+Skin)`, others muted, shadows off) into
  a mask at pass scale (>150 roots fall back to mass-AABB boxes);
  composited with a Sobel-on-threshold + exponential-glow shader whose
  thickness scales with mask resolution (constant on-screen width).

---

## 12. Grid, sky, and other chrome

`poly_stage.gml`. Grid and sky are `chrome` spawns (untracked, excluded
from pick/outline/serialize):

- Grid: `grid.glb` + procedural shader (`shPolygonEditorGrid`):
  per-pixel lines from world XZ at 1:5:25 pitches, `fwidth` 1px lines,
  per-scale LOD + distance + horizon fades, opaque. The quad (scale 6
  → ±1800 m) is recentered under the camera every frame while lines
  stay world-anchored - feels infinite; the edge dissolves before it
  is ever visible. Step comes live from the toolbar (`u_grid_step`).
- Sky: `skybox.glb` dome following the camera, scaled to stay inside
  the far plane; gradient + sun disk from the first directional light
  (fallback direction); palette shared with the grid fade color.
- Unlit mode swaps all non-chrome materials to a flat shader
  (originals recorded for restore); magenta materials mark models
  missing assignments (`poly_shaders.gml`).

---

## 13. Shader inventory

`shaders/shPolygonEditor*` (GLSL ES: `attribute/varying/texture2D`,
plus GM3D `s*` model shaders):

- Post: `FXAA` (Lottes 3.11), `SMAAEdge` (threshold 0.1 + local
  contrast), `SMAABlend` (16/8 search, corner rounding 25, area+search
  LUTs), `SMAAResolve` (neighborhood blend, clean copy on zero
  weight).
- Scene: `Lit(+Skin/Shadow/Instanced)` (8 dir + 8 point lights, PCF
  shadow atlas, cutout/blend, fog), `Unlit(+Skin/Instanced)`,
  `Magenta(+Skin)` fallback, `Grid`, `Sky`, `Outline`, `Mask(+Skin/
  Instanced)` white, `Id(+Skin/Instanced)` flat id color.
- `poly_shaders.gml` warms editors shaders once and provides the
  central lit/unlit/magenta material sets.

---

## 14. Panels and chrome

ImGui, docked (`poly_imgui.gml` orchestrator,
`poly_imgui_dock.gml` layout: Scene center, Inspector right, Models
bottom, Hierarchy left; dark theme; panel-move lock while gesturing).
Draw order: menu → Models → Hierarchy → Inspector → Scene →
toolbar → FPS → animation preview → modals.

- Menu bar (`poly_imgui_chrome.gml`): brand, File (scene basename +
  New/Save/Save-As/Load/Close with dirty confirms), Create (lights
  cap 8, cameras, singleton env), View (window toggles, grid, reset
  layout), Help (issues link, About), AI bridge status + toggle.
- Toolbar: View/Move/Rotate/Scale, Pivot/Center, World/Local, snap
  toggle + grid/size popup, Unlit/Shaded, Home, AA combo
  (`AA Off/FXAA/SMAA/SSAA`), visibility eye menu (hidden objects,
  sky, outline).
- Hierarchy (`poly_imgui_scene.gml`): scene tree of tracked roots with
  expandable child nodes (not virtualized; roots own selection, child
  rows are display-only), eye/lock buttons, kind icons, filter text +
  kind filters, F2 inline rename, rubber-band select, right-click
  menu (Focus/Rename/Duplicate/Copy/Cut/Paste/Delete), item counter.
- Inspector (`poly_imgui_inspector` + `insp_*`): per-kind sections
  (Transform with mixed-value axis editing and drag-grouped undo;
  Light+Shadow/Camera/Environment; asset Shadows), prefab Overrides
  (per-field Revert/Apply vs spawn defaults), Actor bindings, spawn
  defaults, read-only Materials (slots, sampler state, hex copy) and
  Animations (clip list + floating playable preview).
- Models (`poly_imgui_assets.gml`): Cards/List views, search filter,
  drag-into-viewport placement with live preview node, background-
  click deselect.
- Scene panel: the rendered surface + hover tracking; FPS overlay
  (`F9`); ViewCube (orientation cones, axis snap, draggable).
- Modals: scene save/load (name + format radio on save; search +
  per-file list on load; chunked-load progress bar), new/load/close
  confirms, multi-delete confirm, About.

---

## 15. Input map

`poly_input.gml` (skipped while typing; gestures block hotkeys):

- `Q/W/E/R` tools (suppressed while RMB-flying, they fly instead),
  `Del` delete (multi-confirm), `Shift+D` deselect, `F` focus,
  `` \ `` snap toggle, `Z/X` pivot/orient, `F2` rename, arrows nudge,
  `Esc` cancels topmost state (dialog → confirm → rename → drag →
  viewcube → rect → gizmo-restore → clear selection).
- `Ctrl+S/L/N/W` save/load/new/close, `Ctrl+D` duplicate,
  `Ctrl+C/X/V` copy/cut/paste, `Ctrl+I` invert, `Ctrl+A` select all,
  `Ctrl+F` find (panel search), `Ctrl+Z/Y` (+`Shift+Z`) undo/redo,
  `Ctrl+\`` push to grid.
- All bindings come from `_ed.cfg.keys` (`__poly_keys_defaults`) and are
  remappable via the `keys` field of the `poly_create` config. Each entry is
  an array of element structs `{ key, mouse?, modifier? }`: `key` is the code
  (`vk_*`/`ord("X")` for keys, `mb_*` for mouse), `mouse: true` marks it a
  mouse button, `modifier: true` requires it held (else it is a trigger;
  several triggers = alternatives). The type is explicit, so a mouse button is
  never inferred by its value. `__poly_elem_key/_mouse/_mod` read the elements;
  `__poly_bind_pressed` matches one-shot shortcuts exactly (undeclared
  keyboard modifiers must be up) and `__poly_bind_key` ignores extra modifiers
  for the held camera controls. A bare real is a keyboard-trigger shorthand.
  Actions sharing a base key have distinct names
  (`focus`/`focus_search`, `snap`/`snap_grid`, `redo`/`redo_shift`).
  `__poly_bind_label` renders the same binding as a menu string (e.g.
  `Ctrl+D`); the menu bar, the Hierarchy row context menu and the delete
  confirmation use it so their hints always match the current bindings.
- Mouse: click/shift-click/rect select (viewport), gizmo drag, library
  drag (4px threshold, ground-plane preview, single undo on drop),
  camera orbit/zoom/fly/pan and nudge all driven by the `cam_*` /
  `nudge_*` / `select_add` / `select_range` / `snap_temp` /
  `gizmo_screen` bindings, wheel zoom, infinite cursor wrap
  during camera/gizmo drags.

---

## 16. AI bridge (MCP relay)

Optional local link so an AI client can drive the editor
(`poly_ai.gml`, `poly_ai_net.gml`, `other/mcp-relay/` Node server).

- Transport: editor opens TCP `127.0.0.1:5192`
  (`network_connect_raw_async`), newline-delimited JSON, protocol
  `v:1` hello both ways (`poly-ai` / `polygon-mcp-relay`), `{id, op,
  params}` → `{id, ok, result}` or `{id, ok:false, error: "code:
  msg"}`. Relay maps it to MCP tools (`poly_*`, server.js);
  `bridge.js` handles framing (4 MB cap), hello timeout, pending
  calls with timeouts. Game framing rules: stable ids, local wrapper
  transforms, euler degrees, every mutation history-wrapped, no
  arbitrary GML.
- Editor side: link states off/connecting/reconnecting/linked with
  backoff; 8-op inbox budget per step; idempotent `seen` cache (128);
  validators per op; 23 ops: inspect (status, hierarchy, selection,
  details, assets, raycast, screenshots/captures, audits) and edit
  (select, focus, camera, create with ground resting, transform,
  rename, delete, save, batch of ≤64 with pre-validation and one
  undo, drop/stack, visibility, load with dirty-guard).
- Screenshots/captures render offscreen with a temp camera (editor
  pose untouched), muted scene cameras restored after, PNGs via temp
  dir (size caps, embedded base64). Save round-trips content-md5 and
  sandbox-path verification through the relay.

---

## 17. Conventions cheat-sheet

- Identity = wrapper name (`__PolygonEditor__N`); compare by name.
- `id_seq` monotonic; never reuse ids; reseed after rebuild/paste/load.
- Only wrapper roots are tracked; grid, drag preview, viewcam and the
  gameplay cam are excluded from serialize/selection.
- `en.data` is the source of truth for props; components mirror it.
- Scene cameras muted while editing; max 8 lights.
- Undo = whole-scene JSON snapshots (cap 100); gizmo drags coalesce.
- One offscreen scale per frame for all 3D passes; overlays compose
  after AA at display res.
- Never `surface_free` a live ImGui texture - retire with TTL.
- GLSL ES style shaders (`attribute/varying/texture2D`); extra
  samplers via `shader_get_sampler_index` + `texture_set_stage`.
- Struct-member reads that may be missing must use
  `variable_struct_exists` first (GM throws `ReferenceError`).
- Runtime LUT/sprite textures must outlive their queued submits -
  keep decoded sprites alive, never delete right after blitting.

---

## 18. Packaging (editor.yymps)

`editor.yymps` is the importable Local Asset Package, built by GameMaker's
`ProjectTool` (`other/tools/pack_yymps.ps1`) and wired to `pre-push` through
the checked-in `.githooks/` folder, enabled by `npm install` (root
`package.json` → `prepare`). The package contains the whole **Polygon
Editor** folder (scripts, sprites, shaders) plus the Included Files under
`datafiles/__PolygonEditor__`; the demo datafiles are removed with
`POSTREMOVALS`. Because the `.yymps` zip embeds timestamps, a fresh export
almost always differs byte-for-byte, so freshness is decided by comparing the
entries (name + MD5) - never by file hash or `git status`. The hook never
blocks a push: a rebuild that is stale lands in its own commit for the next
push.
