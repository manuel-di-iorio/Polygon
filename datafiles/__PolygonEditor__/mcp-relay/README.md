# Polygon MCP relay

Local bridge between MCP-compatible AI clients (OpenCode, Claude Code, Codex, ...) and
the Polygon GameMaker 3D editor. The relay speaks **MCP over stdio** to the
AI and **newline-delimited JSON over TCP** to the game
(`scripts/polygon_ai/polygon_ai.gml`).

```
AI client <--stdio/MCP--> relay --TCP 127.0.0.1:5192--> game (editor open + bridge on)
```

The relay never touches the scene itself: it forwards validated tool calls
to the editor, which executes them through its own functions (undoable with
Ctrl+Z) and replies. If the editor is unreachable, tools fail explicitly —
nothing is ever faked.

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
node --test test\framing.test.js test\bridge.test.js test\mcp.test.js
```

Logs go to stderr only; stdout is reserved for MCP transport.

## Connect an AI client

Claude Code:

```bat
claude mcp add polygon -- node C:\...\polygon\other\mcp-relay\server.js
```

opencode (locale, nel progetto):

```bat
opencode mcp add polygon -- "C:\Program Files\nodejs\node.exe" C:\...\polygon\other\mcp-relay\server.js
opencode mcp list
```

> Usa il percorso completo di Node 24: il `node` nel PATH potrebbe essere
> una versione vecchia (il relay richiede Node 18+). Verifica con
> `opencode mcp list` → `✓ polygon connected`, i tool compaiono come
> `polygon_*`.

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.polygon]
command = "node"
args = ["C:/.../polygon/other/mcp-relay/server.js"]
```

Claude Desktop / Cursor: same command+args in the `mcpServers` JSON block.
No secrets or credentials are involved.

## Tools (16)

Status/inspect: `polygon_get_status`, `polygon_get_scene_hierarchy`,
`polygon_get_selection`, `polygon_get_object_details`, `polygon_get_assets`,
`polygon_raycast_down`.
Edit: `polygon_select_objects`, `polygon_focus_object`,
`polygon_create_object`, `polygon_set_transform`, `polygon_rename_object`,
`polygon_delete_objects`, `polygon_save_scene`, `polygon_apply_batch`,
`polygon_drop_to_ground`, `polygon_place_on`.

Conventions (also in each tool description): nodes are addressed by stable
id (`__PolygonEditor__N`), never by label; transforms are **local**;
rotation is Euler **degrees [rx, ry, rz], XYZ order**; mutations are
rejected while an editor dialog/drag owns the scene (`busy` error).

Positioning without guessing Y: read ops report world-space AABBs
(`bounds`: min/max/size/bottom/top) and assets report model-space bounds
plus pivot (`bottom` offset, `origin` base|center|custom). To rest objects
exactly, prefer `polygon_create_object` with `base_y` (world bottom Y) or
`on_top_of` (support id) + `gap`, or snap existing nodes with
`polygon_drop_to_ground` (`ground_y`, default 0) / `polygon_place_on`
(`on` + `gap`). Both are batchable; `on_top_of`/`on` must reference an
already existing node (create supports first, then stack).

## Wire protocol v1 (relay ↔ game)

TCP client = game (`network_connect_raw` to 127.0.0.1:port), one frame per
line: compact JSON + `\n`, UTF-8. Game says
`{ "v": 1, "hello": "polygon-ai" }`; relay answers
`{ "v": 1, "hello": "polygon-mcp-relay" }` (either side drops on version
mismatch). Requests `{ "id", "op", "params" }` → responses
`{ "id", "ok": true, "result" }` / `{ "id", "ok": false, "error": "code: msg" }`.
Request ids make retries idempotent (the game caches the last 128 results).
Bump `BRIDGE_PROTOCOL_VERSION` (relay) and the `v` checks (game) together.

## Limits

- One editor instance at a time (a new connection replaces the previous).
- Loopback only; no auth (any local process can connect — by design).
- The game cannot receive while the editor is closed or the bridge is off.
