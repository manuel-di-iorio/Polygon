# Polygon MCP relay

Local bridge between MCP-compatible AI clients (OpenCode, Claude Code, Codex, ...) and
the Polygon GameMaker 3D editor. The relay speaks **MCP over stdio** to the
AI and **newline-delimited JSON over TCP** to the game
(`scripts/poly_ai/poly_ai.gml`).

```
AI client <--stdio/MCP--> relay --TCP 127.0.0.1:5192--> game (editor open + bridge on)
```

The relay never modifies the scene itself: it forwards validated tool calls
to the editor, which executes mutations through its own undoable functions.
Read-only walkability audits use hierarchy bounds in the relay. Captures read
temporary PNG files, and saves verify candidate files on the OS filesystem.
If the editor is unreachable, tools fail explicitly.

## Requirements

- Node.js 18+ (only to run the relay, not the game).
- A game run with the editor open and the bridge enabled from the AI button
  in the menu bar (default port 5192).

## Install

```bat
cd other\mcp-relay
"C:\Program Files\nodejs\npm.cmd" install
```

## Run / diagnose

```bat
node server.js [--port 5192] [--timeout 10000]
node server.js --check [--port 5192]   :: waits 5s for the editor, exit 0 = connected
npm test
```

Logs go to stderr only; stdout is reserved for MCP transport.

## Connect an AI client

Claude Code:

```bat
claude mcp add poly -- node C:\...\poly\other\mcp-relay\server.js
```

opencode (locale, nel progetto):

```bat
opencode mcp add poly -- "C:\Program Files\nodejs\node.exe" C:\...\poly\other\mcp-relay\server.js
opencode mcp list
```

> Usa il percorso completo di Node 24: il `node` nel PATH potrebbe essere
> una versione vecchia (il relay richiede Node 18+). Verifica con
> `opencode mcp list` → `✓ poly connected`, i tool compaiono come
> `poly_*`.

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.poly]
command = "node"
args = ["C:/.../poly/other/mcp-relay/server.js"]
```

Claude Desktop / Cursor: same command+args in the `mcpServers` JSON block.
No secrets or credentials are involved.

## Tools (23)

Status/inspect: `poly_get_status`, `poly_get_scene_hierarchy`,
`poly_get_selection`, `poly_get_object_details`, `poly_get_assets`,
`poly_raycast_down`, `poly_take_screenshot`, `poly_capture_views`,
`poly_audit_overlaps`, `poly_audit_walkability`.
Edit: `poly_select_objects`, `poly_focus_object`,
`poly_create_object`, `poly_set_transform`, `poly_rename_object`,
`poly_delete_objects`, `poly_save_scene`, `poly_apply_batch`,
`poly_drop_to_ground`, `poly_place_on`, `poly_set_camera`,
`poly_set_visible`, `poly_load_scene`.

Conventions (also in each tool description): nodes are addressed by stable
id (`__PolygonEditor__N`); transforms are **local**;
rotation is Euler **degrees [rx, ry, rz], XYZ order**; mutations are
rejected while an editor dialog/drag owns the scene (`busy` error).

Positioning without guessing Y: read ops report world-space AABBs
(`bounds`: min/max/size/bottom/top) and assets report model-space bounds
plus pivot (`bottom` offset, `origin` base|center|custom). To rest objects
exactly, prefer `poly_create_object` with `base_y` (world bottom Y) or
`on_top_of` (support id) + `gap`, or snap existing nodes with
`poly_drop_to_ground` (`ground_y`, default 0) / `poly_place_on`
(`on` + `gap`). Both are batchable; `on_top_of`/`on` must reference an
already existing node (create supports first, then stack).

## Multiple View Captures

`poly_capture_views` accepts 1-32 named camera poses. Use `position` and
exactly one of `target` or `rotation`, or `focus_id` with optional `position`.
Focus without a position auto-frames the object's world bounds from an
oblique angle. A position with focus aims from that position at the bounds
center. Focus cannot be combined with target/rotation.

Each capture uses an auxiliary camera and a dedicated offscreen surface.
It does not change the editor camera pose or animation, nor suspend editor
input. `hide_ids` mutes meshes only during the capture render, then restores
their actual current states; persistent visibility is never changed.
Incoming bridge operations wait until the capture batch completes.
An enabled-camera swap happens only inside the Draw callback, after the
normal viewport has rendered, and is restored even when rendering fails.

```json
{
  "views": [
    { "name": "exterior", "position": [15, 10, 15], "target": [0, 2, 0] },
    { "name": "upper-floor", "position": [0, 9, 0], "target": [0, 2.6, 0] }
  ],
  "hide_ids": [],
  "hide_overlays": true,
  "include_images": true
}
```

Each view renders one fresh offscreen frame at the current viewport
resolution, independently of the viewport panel being open. Images are raw
scene renders without editor overlays or the viewport's postprocess AA.
`hide_overlays` remains accepted for compatibility but all offscreen views
are clean. Results include `name`, unique `file`, `width`, `height` and
`editor_camera_unchanged: true`; batches also include `restored: true`.
Successful files remain in GameMaker's temporary directory; failed jobs
remove completed images. They no longer rotate through ten filenames.

Images are embedded as MCP image content by default, provided they are PNGs
inside OS temp, at most 8 MB each and at most 20 MB base64 in total.
Skipped images are reported in `skipped_images`, while file descriptors
remain available. Use `include_images: false` for paths only.
`poly_take_screenshot` supports the same image options, `hide_ids`, and
direct `position` + `target`/`rotation` or `focus_id`. With no pose, it renders
the current editor camera's viewpoint offscreen; no preceding set-camera or
focus operation is needed. `poly_get_status.capture_mode` is `offscreen`
after the updated GameMaker scripts have been rebuilt.

## Walkability Audit

`poly_audit_walkability` is a read-only, per-floor XZ grid approximation.
`floor_y` is required; defaults are radius 0.3, height 1.8, cell size 0.1,
step height 0.15 and floor tolerance 0.05 (world units).

```json
{
  "floor_y": 2.6,
  "radius": 0.3,
  "height": 1.8,
  "cell_size": 0.1,
  "start": { "x": 6, "z": -1.5 },
  "probes": [{ "name": "reading-nook", "x": 6, "z": 4.5 }]
}
```

Returns connected `components`, significant `disconnected` regions and
probe states (`walkable`, `blocked`, `unsupported`) with `reachable`.
Without `start`, the largest region is the anchor. An invalid start makes
reachability unknown (`null`). `floor_ids` overrides automatic floor/slab
name detection; `ignore` excludes geometry. Hidden viewport nodes still
count. `min_area` filters disconnected regions (default 0.25).
The grid is limited to 150,000 cells; increase `cell_size` or limit floors
when necessary.

This is not a physics/navmesh guarantee: rotated/concave geometry is
represented by AABBs, floor support is sampled, and stairs do not connect
levels. Door leaves are assumed open by default and doorway openings are
estimated at 70% width / 90% height. Use `assume_open_doors: false` for full
door AABB obstacles. Inspect warnings and confirm important paths in-game.

## Save Path Verification

`poly_save_scene` keeps its original `file` field and adds `nodes`,
`requested_path`, `sandbox_path`, `actual_path`, `path_verified`,
`sandbox_redirected`, `matching_paths` and `content_md5`.
The editor hashes the saved text; the relay reads candidate OS paths and
compares content hashes, ignoring line endings. Only one matching path
sets `path_verified: true`. If neither or both match, `actual_path` is empty
and callers must inspect the candidates instead of assuming a write target.
Verification identifies a matching saved copy, not a filesystem write trace.

GMRT does not expose the legacy `save_directory` global. On Windows the
relay can locate a project-named `.yyp` in up to eight ancestors of the
requested path and check `%LOCALAPPDATA%/<project-name>/<file>` as a sandbox
candidate. If no project is found, that candidate is unknown; verification
does not guess paths for packaged builds or other platforms.

GameMaker can redirect writes from included assets into its save sandbox.
Saving does not synchronize that copy back into Build assets. Copy a verified
file explicitly when the project needs that synchronization.

After updating, rebuild/run the GameMaker project and restart the MCP relay
so both sides expose the new capture operation and save metadata.

## Wire protocol v1 (relay ↔ game)

TCP client = game (`network_connect_raw` to 127.0.0.1:port), one frame per
line: compact JSON + `\n`, UTF-8. Game says
`{ "v": 1, "hello": "poly-ai" }`; relay answers
`{ "v": 1, "hello": "polygon-mcp-relay" }` (either side drops on version
mismatch). Requests `{ "id", "op", "params" }` → responses
`{ "id", "ok": true, "result" }` / `{ "id", "ok": false, "error": "code: msg" }`.
Request ids make retries idempotent (the game caches the last 128 results).
Bump `BRIDGE_PROTOCOL_VERSION` (relay) and the `v` checks (game) together.

## Limits

- One editor instance at a time (a new connection replaces the previous).
- Loopback only; no auth (any local process can connect - by design).
- The game cannot receive while the editor is closed or the bridge is off.
