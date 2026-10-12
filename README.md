# Polygon

**A 3D in-game scene editor for GameMaker, built on GM3D and Dear ImGui.**

<img src="docs/logo_gm.png" width="800px" />

Polygon opens inside your running game (press **F1** in the demo), mirrors the live scene, and lets you place, transform and inspect objects. Scenes are saved to JSON and can be loaded back at runtime with a single call.

<img src="docs/screenshot.png" width="800px" />


## Features

**Editing**
- Drag models from the **Models** panel into the viewport (live drop preview)
- Move / Rotate / Scale gizmos with axis, planar and trackball handles, World or Local space
- Position, rotation and grid snapping (hold **Ctrl** for temporary snap)
- Multi-selection: click, Shift+click, rubber-band rectangle, and depth cycling on repeated clicks
- Duplicate, delete, rename, focus, and **undo/redo**
- Hide / lock objects per node

**Scene content**
- Models (prefabs) with per-asset spawn defaults (rotation, scale, shadows)
- Lights (directional, point), cameras (perspective, ortho) and an environment volume (ambient, fog)
- Prefab overrides with per-field **Revert / Apply**
- Read-only inspection of materials, textures (with sampler state) and animation clips, including a playable animation preview

**Viewport**
- Dockable windows: Hierarchy, Inspector, Models, Scene, Toolbar
- Orientation **ViewCube**, infinite grid, procedural sky
- Selection outline (GPU mask), GPU ID-buffer picking
- Shaded / Unlit draw modes, antialiasing: Off, SSAA, FXAA

**Workflow**
- JSON scene files (versioned format) with save / load / delete dialog
- Unsaved-changes confirmation
- Optional **AI bridge** (MCP relay) to drive the editor from an AI client

---

## Requirements

- GameMaker with **GMRT** package v0.22.4

---

## Installation

1. Import the resources into your project by dragging the `editor.yymps` file into your project.
2. Create `oEditor` in your game using the setup below.

---

## Quick start

Polygon only needs a small **config** struct. It never touches your game instances: it works on its own copy of the scene.

```gml
// oGame / Create
var config = {
  scene: my_scene,          // your live GM3D_Scene (mirrored on enable)
  cam: my_camera_node,      // your gameplay camera node (seeds the editor view)
  on_spawn: my_on_spawn,    // optional: called for every spawned node
  on_close: my_on_close,    // optional: called when the editor closes
  assets: [
    { model: my_model_a, label: "Tree", path: "models/tree.glb" },
    { model: my_model_b, label: "Rock", path: "models/rocks.glb" },
  ],
};

instance_create_layer(0, 0, layer, oEditor, { config });
```

Wire the `oEditor` events:

| Event               | Code                |
|---------------------|---------------------|
| Create              | `polygon_init(config); polygon_enable();` |
| Step                | `polygon_step();`   |
| Draw                | `polygon_draw();`   |
| Draw GUI            | `polygon_draw_ui();`|
| Async Networking    | `polygon_ai_net();` |
| Clean Up            | `polygon_cleanup();`|

Toggle the editor from your game:

```gml
// oGame / Key Press F1
if (!polygon_is_active()) polygon_enable();

// pause your own world while the editor is open
if (!polygon_is_active()) my_game_step();
```

Close it from the editor with **File → Close Editor** (Ctrl+W).

### Adapter fields

| Field      | Description |
|------------|-------------|
| `scene`    | Live scene. On every enable, Polygon imports it (see below). |
| `cam`      | Gameplay camera node, used to seed the editor camera. |
| `assets`   | Array of `{ model, label?, path? }`. `path` is the stable asset id used in scene files. |
| `on_spawn` | `function(wrapperNode, assetKey, model)`. Use it to assign shaders and start animations. Walk the subtree: the model root lives inside the wrapper. |
| `on_close` | Called after the editor closes. |

### How the live scene is imported

Each time the editor opens, the live scene is **copied**, never modified. Root nodes are matched to library assets by model root name, or by exact material set. Lights, cameras and the environment are recreated from their live settings. If the scene has no sun or environment, defaults are created.

---

## Using the editor

### Camera

| Action | Input |
|--------|-------|
| Fly | Hold **Right mouse** + `W A S D`, `Q` / `E` for down / up |
| Fly faster | Hold **Shift** |
| Change fly speed | Mouse wheel while flying |
| Orbit | **Alt + Left mouse** |
| Zoom | Mouse wheel, or **Alt + Right mouse** drag |
| Pan | **Middle mouse** (or drag with the View tool) |
| Focus selection | `F` or double-click in the Hierarchy |
| Reset camera | Home button in the toolbar |
| Snap to axis | Click a cone on the **ViewCube** |

The cursor wraps at window edges during camera and gizmo drags.

### Tools and shortcuts

| Key | Action |
|-----|--------|
| `1` `2` `3` `4` | View, Move, Rotate, Scale |
| `Del` | Delete selection (confirms for multiple objects) |
| `F2` | Rename |
| Arrow keys | Nudge selection on X/Z |
| `Esc` | Cancel the current gesture, otherwise clear selection |
| `Ctrl+S` / `Ctrl+L` / `Ctrl+N` | Save / Load / New |
| `Ctrl+D` | Duplicate |
| `Ctrl+Z` / `Ctrl+Y` (or `Ctrl+Shift+Z`) | Undo / Redo |
| `Ctrl+W` | Close editor |
| `F9` | FPS overlay |

### Selecting and transforming

- **Click** an object to select it. Click again at the same spot to cycle through overlapping objects.
- **Shift+click** toggles an object; drag on empty space for a **rectangle selection** (hold Shift to add).
- With **Move**, hold **Shift** for a screen-space move handle; the squares between axes move on a plane.
- With **Rotate**, the outer ring rotates around the view axis and the inner disc acts as a trackball.
- Hold **Ctrl** while dragging to snap. Configure grid size and axes from the grid combo in the toolbar.
- Scale needs a uniform handle (center) or an axis handle; environment nodes cannot be transformed.

### Panels

- **Models**: filterable list or cards of your library. Drag into the viewport to place. Select one to edit its spawn defaults.
- **Hierarchy**: eye = hide, hand = lock (locked objects cannot be selected). Ctrl+click selects a range, right-click opens the context menu, rubber-band selects rows. The filter button limits types (models, lights, cameras, environment).
- **Inspector**: Transform, Light / Camera / Environment, Shadows, Materials, Animations. Prefab instances show an **Overrides** menu to revert or apply rotation, scale and shadow changes.

### Creating lights, cameras and environment

Use the **Create** menu: Directional Light, Point Light (up to 8 lights), Perspective Camera, Ortho Camera, Environment (one per scene). The camera labeled `MainCamera` is the gameplay camera; otherwise the first enabled one is used.

---

## Saving and loading scenes

Scenes are saved from **File → Save / Save As** into `working_directory/__PolygonEditor__/scenes/<name>.json`. **File → Load** lists saved scenes with search and delete.

Load a scene in your game, without the editor, with:

```gml
// models: struct mapping asset key (the `path` you registered) to its model
var models = {};
models[$ "models/tree.glb"] = my_model_a;
models[$ "models/rocks.glb"] = my_model_b;

var report = polygon_load(my_scene, "__PolygonEditor__/scenes/level1.json", models);
// report = { placed, failed }
```

`polygon_load` spawns instances, lights, cameras and environments, preserving node ids.

---

## Scene file format

```json
{
  "version": 2,
  "seq": 12,
  "nodes": [
    {
      "kind": "instance",
      "id": "__PolygonEditor__3",
      "label": "Tree",
      "asset": "models/tree.glb",
      "position": [0, 0, 0],
      "rotation": [0, 0, 0, 1],
      "scale": [1, 1, 1],
      "flags": { "castShadows": true, "receiveShadows": true }
    }
  ]
}
```

`kind` is one of `instance`, `light`, `camera`, `environment` (the last three carry a `light` / `camera` / `environment` sub-object). Rotation is a quaternion `[x, y, z, w]`. Node ids are stable and are what the AI bridge uses.

---

## AI bridge (optional)

Polygon can connect to a local **MCP relay** (`other/mcp-relay`, Node) so an AI client can inspect and edit the scene.

1. Install [Node.js](https://nodejs.org/en/download/archive/v24.21.0) v24.21
2. On your AI tool (OpenCode, Codex, Claude Code), configure the MCP server 
pointing a the address `127.0.0.1:5192`.

    Note: If your editor does not start the server automatically, then you need to open a terminal (eg. Powershell on Windows), move inside the _mcp-relay_ folder and start it with the command: `$ node index.js`.
3. In the editor, click the **AI** button in the menu bar. The status shows *Connecting*, *Connected* or *Reconnecting*.

No socket is ever opened unless the editor is active and the bridge is on. Only whitelisted operations are accepted (no arbitrary GML):

`status`, `hierarchy`, `selection`, `details`, `assets`, `raycast_down`, `select`, `focus`, `create`, `transform`, `rename`, `delete`, `save`, `batch`, `drop_to_ground`, `place_on`

---

## Project layout

```
objects/oEditor            editor object (event wiring)
scripts/polygon_core       init, frame entry points, state
scripts/polygon_input      hotkeys, gizmo/library/rect/hover steps
scripts/polygon_gizmo*     transform handles and drawing
scripts/polygon_gpu_pick   ID-buffer picking
scripts/polygon_outline    selection outline
scripts/polygon_imgui_*    Hierarchy, Inspector, Models, Scene, toolbar, dock
scripts/polygon_registry   tracked node registry and spawn pipeline
scripts/polygon_serialize  descriptors, validation, save/load
scripts/polygon_ai         AI bridge (TCP client)
scripts/scr_demo           demo world
```

## Troubleshooting

- **No grid or sky:** check that `grid.glb` and `skybox.glb` are in `__PolygonEditor__/models/` in Included Files.
- **Pink / magenta meshes:** a model has no material; Polygon paints it magenta as a fallback. Assign materials in your `on_spawn` hook or fix the model.
- **Library thumbnails missing:** they are rendered once at startup; make sure the models loaded successfully.
- **AI shows "AI Server not available":** start the relay first; the editor gives up after 3 attempts.

---

## Contributing

Bug reports and feature requests: [GitHub Issues](https://github.com/manuel-di-iorio/Polygon/issues) (also reachable from **Help → Report a Bug/Feature Request**).

## License

Released under the MIT License, 2026. Developed by Emmanuel Di Iorio (Xeryan). Third-party assets (e.g. the Kenney models used in the demo) belong to their owners.
