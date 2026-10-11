// Polygon MCP relay: stdio MCP server + local TCP bridge to the editor.
// Stdout is reserved for MCP transport. Everything else goes to stderr.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { BridgeLink, BridgeError } from "./bridge.js";

const RELAY_VERSION = "1.1.0";
const DEFAULT_PORT = 5192;
const VEC3 = z.array(z.number()).length(3);

const log = (msg) => console.error(`[polygon-mcp-relay] ${msg}`);

function parseArgs(argv) {
  const out = { port: DEFAULT_PORT, timeoutMs: 10000, check: false };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--port" && i + 1 < argv.length) out.port = Number(argv[++i]);
    else if (argv[i] === "--timeout" && i + 1 < argv.length) out.timeoutMs = Number(argv[++i]);
    else if (argv[i] === "--check") out.check = true;
    else if (argv[i] === "--help" || argv[i] === "-h") out.help = true;
  }
  return out;
}

// Wraps a bridge call as an MCP tool result (throws = tool error).
function toolResult(result) {
  return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
}

function bridgeTool(server, bridge, name, description, schema, op, mapParams = (a) => a) {
  server.registerTool(name, { description, inputSchema: schema }, async (args) => {
    try {
      const result = await bridge.call(op, mapParams(args ?? {}));
      return toolResult(result);
    } catch (err) {
      if (err instanceof BridgeError) throw new Error(`${err.code}: ${err.message}`);
      throw err;
    }
  });
}

async function runCheck(port) {
  // --check: listen briefly and report whether the editor connects.
  const bridge = new BridgeLink({ port, log });
  try {
    await bridge.start();
  } catch {
    console.error(`cannot listen on 127.0.0.1:${port} (port busy or blocked)`);
    process.exit(1);
  }
  log(`waiting 5s for the editor on 127.0.0.1:${port} (press the AI button in the editor menu bar)...`);
  const t0 = Date.now();
  while (Date.now() - t0 < 5000) {
    if (bridge.connected()) {
      log("OK: editor connected (protocol v1)");
      await bridge.stop();
      process.exit(0);
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  console.error("no editor connected within 5s");
  await bridge.stop();
  process.exit(2);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.help) {
    console.error(`usage: node server.js [--port N] [--timeout MS] [--check]`);
    process.exit(0);
  }
  if (!Number.isFinite(args.port) || args.port < 0 || args.port >= 65536) {
    console.error("invalid --port");
    process.exit(1);
  }
  if (args.check) {
    await runCheck(args.port);
    return;
  }

  const bridge = new BridgeLink({ port: args.port, timeoutMs: args.timeoutMs, log });
  try {
    await bridge.start();
  } catch {
    process.exit(1); // reason already logged
  }

  const server = new McpServer({ name: "polygon-mcp-relay", version: RELAY_VERSION });

  bridgeTool(server, bridge, "polygon_get_status",
    "Connection + editor status: whether the Polygon editor is connected, how many nodes are tracked, what is selected, current scene file.",
    {}, "status");

  bridgeTool(server, bridge, "polygon_get_scene_hierarchy",
    "List tracked root nodes of the current scene: stable id, kind (instance|light|camera|environment), label, asset key, local transform, world-space bounds (AABB min/max/size/bottom/top), selection/hidden/locked flags. Use bounds.bottom/top to rest objects exactly instead of guessing Y.",
    {}, "hierarchy");

  bridgeTool(server, bridge, "polygon_get_selection",
    "Currently selected nodes with id, kind, label and local transform.",
    {}, "selection");

  bridgeTool(server, bridge, "polygon_get_assets",
    "Library assets available for polygon_create_object: key (use as asset) + display label + model-space bounds (min/max/size) and pivot info (bottom offset, origin base|center|custom). Resting Y = supportTopY - bounds.bottom * scaleY; or just use base_y / on_top_of in create.",
    {}, "assets");

  bridgeTool(server, bridge, "polygon_raycast_down",
    "Cast a vertical ray down from (x, from_y, z) and report the first hit: the highest surface (world top Y + node id) at/below from_y. No physics involved (resolved from world AABBs). Returns { found:false } or { found:true, top, id }. Use to find what to rest on, then create with on_top_of or snap with polygon_place_on.",
    {
      x: z.number().describe("World X (ray origin)"),
      z: z.number().describe("World Z (ray origin)"),
      from_y: z.number().optional().describe("Ray origin height, default +inf (sky)"),
      ignore: z.string().optional().describe("Node id to exclude (e.g. the node itself)"),
    }, "raycast_down");

  bridgeTool(server, bridge, "polygon_get_object_details",
    "Full descriptor of one node by stable id (transform, world-space bounds AABB, asset model-space bounds, light/camera/environment data when present).",
    { id: z.string().describe("Stable node id, e.g. __PolygonEditor__7") }, "details");

  bridgeTool(server, bridge, "polygon_select_objects",
    "Replace the editor selection with the given node ids. Locked nodes are skipped and reported.",
    { ids: z.array(z.string()).describe("Stable node ids to select (empty array clears)") }, "select");

  bridgeTool(server, bridge, "polygon_focus_object",
    "Move the viewport camera to frame one node.",
    { id: z.string().describe("Stable node id") }, "focus");

  bridgeTool(server, bridge, "polygon_create_object",
    "Spawn a library asset as a new instance. Position is [x,y,z] world units (X/Z always used; Y is the spawn guess unless resting params are given). Rotation is optional Euler degrees [rx,ry,rz] (XYZ order). Scale defaults to [1,1,1]. Optional resting (measured from the real AABB, any pivot): base_y = desired world bottom Y, or on_top_of = support node id + optional gap. Returns the new stable id + final bounds. List valid keys first with polygon_get_assets; unknown keys are rejected.",
    {
      asset: z.string().describe("Library asset key, e.g. models/tree.glb"),
      position: VEC3.describe("Spawn position [x, y, z]"),
      rotation: VEC3.optional().describe("Euler degrees [rx, ry, rz], XYZ order"),
      scale: VEC3.optional().describe("Scale [sx, sy, sz], clamped to >= 0.01"),
      label: z.string().optional().describe("Display label (id stays stable regardless)"),
      base_y: z.number().optional().describe("Desired world bottom Y (mutually exclusive with on_top_of)"),
      on_top_of: z.string().optional().describe("Support node id to rest on (bottom = support top + gap)"),
      gap: z.number().optional().describe("Extra lift above the support top, default 0"),
    }, "create");

  bridgeTool(server, bridge, "polygon_set_transform",
    "Set local position and/or rotation (Euler degrees XYZ) and/or scale of one node. At least one field required. Undoable with Ctrl+Z in the editor.",
    {
      id: z.string().describe("Stable node id"),
      position: VEC3.optional(),
      rotation: VEC3.optional().describe("Euler degrees [rx, ry, rz], XYZ order"),
      scale: VEC3.optional(),
    }, "transform", (a) => {
      if (a.position === undefined && a.rotation === undefined && a.scale === undefined) {
        throw new Error("bad_params: one of position/rotation/scale is required");
      }
      return a;
    });

  bridgeTool(server, bridge, "polygon_rename_object",
    "Change a node's display label (1-64 chars). The stable id never changes. Undoable.",
    { id: z.string(), label: z.string() }, "rename");

  bridgeTool(server, bridge, "polygon_delete_objects",
    "Delete nodes by stable id (game camera is protected and rejected). Undoable.",
    { ids: z.array(z.string()).min(1) }, "delete");

  bridgeTool(server, bridge, "polygon_save_scene",
    "Save through the editor's own persistence. Omit name to overwrite the current file; pass name to save-as (sanitized to 64 chars, .json added).",
    { name: z.string().optional() }, "save");

  bridgeTool(server, bridge, "polygon_apply_batch",
    "Validate-then-apply up to 64 ops (create|transform|rename|delete|select|drop_to_ground|place_on) with a single undo entry. Nothing is touched if any op is invalid. NOTE: on_top_of/on must reference an already existing node (same-batch forward refs fail validation like transform does): create supports first, then stack in a second batch.",
    {
      ops: z.array(z.object({
        op: z.enum(["create", "transform", "rename", "delete", "select", "drop_to_ground", "place_on"]),
        params: z.record(z.string(), z.any()).default({}),
      })).min(1).max(64),
    }, "batch");

  bridgeTool(server, bridge, "polygon_drop_to_ground",
    "Snap one node so its world bottom (measured AABB, any pivot) rests on ground_y (default 0). Undoable. Use after manual transforms that left objects floating or sunk.",
    {
      id: z.string().describe("Stable node id"),
      ground_y: z.number().optional().describe("World ground Y, default 0"),
    }, "drop_to_ground");

  bridgeTool(server, bridge, "polygon_place_on",
    "Rest one node on top of another: bottom = support top + gap, measured from real world AABBs (any pivot). Undoable. X/Z unchanged.",
    {
      id: z.string().describe("Stable node id to move"),
      on: z.string().describe("Support node id"),
      gap: z.number().optional().describe("Extra lift above the support top, default 0"),
    }, "place_on");

  const shutdown = async () => {
    await bridge.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  await server.connect(new StdioServerTransport());
  log(`MCP ready (bridge 127.0.0.1:${args.port})`);
}

main().catch((err) => {
  console.error(`fatal: ${err?.message ?? err}`);
  process.exit(1);
});
