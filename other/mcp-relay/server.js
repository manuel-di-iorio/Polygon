// Polygon MCP relay: stdio MCP server + local TCP bridge to the editor.
// Stdout is reserved for MCP transport. Everything else goes to stderr.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { BridgeLink, BridgeError } from "./bridge.js";
import { auditWalkability } from "./walkability.js";
import { readFile, realpath, stat } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { createHash } from "node:crypto";

const RELAY_VERSION = "1.1.0";
const DEFAULT_PORT = 5192;
const VEC3 = z.array(z.number()).length(3);
const CAPTURE_POSE = {
  position: VEC3.optional(),
  target: VEC3.optional(),
  rotation: VEC3.optional(),
  focus_id: z.string().min(1).optional(),
};
const validCapturePose = (view, allowViewport = false) => {
  if (view.focus_id !== undefined) return view.target === undefined && view.rotation === undefined;
  if (view.position === undefined) return allowViewport && view.target === undefined && view.rotation === undefined;
  return (view.target !== undefined) !== (view.rotation !== undefined);
};

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

async function saveSandboxPath(result) {
  if (result.sandbox_path) return result.sandbox_path;
  if (!process.env.LOCALAPPDATA || typeof result.file !== "string" || path.isAbsolute(result.file) || result.file.split(/[\\/]/).includes("..") || typeof result.requested_path !== "string" || !path.isAbsolute(result.requested_path)) return "";
  let directory = path.dirname(result.requested_path);
  for (let depth = 0; depth < 8; depth++) {
    const name = path.basename(directory);
    try {
      if ((await stat(path.join(directory, `${name}.yyp`))).isFile()) return path.join(process.env.LOCALAPPDATA, name, result.file);
    } catch {}
    const parent = path.dirname(directory);
    if (parent === directory) break;
    directory = parent;
  }
  return "";
}

async function saveResult(result) {
  if (!result.content_md5) return toolResult(result);
  const sandboxPath = await saveSandboxPath(result);
  const matches = [];
  for (const filename of new Set([result.requested_path, sandboxPath])) {
    if (typeof filename !== "string" || !path.isAbsolute(filename)) continue;
    try {
      const text = await readFile(filename, "utf8");
      const hash = createHash("md5").update(text.replace(/\r\n|\r|\n/g, ""), "utf8").digest("hex");
      if (text.length && hash === result.content_md5.toLowerCase()) matches.push(filename);
    } catch {}
  }
  const actual = matches.length === 1 ? matches[0] : "";
  return toolResult({ ...result, sandbox_path: sandboxPath, actual_path: actual, path_verified: !!actual, sandbox_redirected: !!actual && actual !== result.requested_path, matching_paths: matches });
}

async function captureResult(result, includeImages = true) {
  if (!includeImages) return toolResult(result);
  const content = [];
  const skipped = [];
  let encodedBytes = 0;
  const tempRoot = await realpath(os.tmpdir());
  for (const view of result.views ?? [result]) {
    try {
      const filename = await realpath(view.file);
      const relative = path.relative(tempRoot, filename);
      if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || path.extname(filename).toLowerCase() !== ".png") throw new Error("image is not a PNG inside OS temp");
      const info = await stat(filename);
      if (info.size > 8 * 1024 * 1024 || encodedBytes + Math.ceil(info.size / 3) * 4 > 20 * 1024 * 1024) throw new Error("image response size limit");
      const image = await readFile(filename);
      if (!image.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error("invalid PNG signature");
      const data = image.toString("base64");
      encodedBytes += data.length;
      content.push({ type: "image", data, mimeType: "image/png" });
    } catch (error) {
      skipped.push({ name: view.name, reason: error.message });
    }
  }
  return { content: [...toolResult({ ...result, embedded_images: content.length, ...(skipped.length ? { skipped_images: skipped } : {}) }).content, ...content] };
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

  bridgeTool(server, bridge, "poly_get_status",
    "Connection + editor status: whether the Polygon editor is connected, how many nodes are tracked, what is selected, current scene file.",
    {}, "status");

  bridgeTool(server, bridge, "poly_get_scene_hierarchy",
    "List tracked root nodes of the current scene: stable id, kind (instance|light|camera|environment), label, asset key, local transform, world-space bounds (AABB min/max/size/bottom/top), selection/hidden/locked flags. Use bounds.bottom/top to rest objects exactly instead of guessing Y.",
    {}, "hierarchy");

  bridgeTool(server, bridge, "poly_get_selection",
    "Currently selected nodes with id, kind, label and local transform.",
    {}, "selection");

  bridgeTool(server, bridge, "poly_get_assets",
    "Library assets available for poly_create_object: key (use as asset) + model-space bounds (min/max/size) and pivot info (bottom offset, origin base|center|custom). Resting Y = supportTopY - bounds.bottom * scaleY; or just use base_y / on_top_of in create.",
    {}, "assets");

  bridgeTool(server, bridge, "poly_raycast_down",
    "Cast a vertical ray down from (x, from_y, z) and report the first hit: the highest surface (world top Y + node id) at/below from_y. No physics involved (resolved from world AABBs). Returns { found:false } or { found:true, top, id }. Use to find what to rest on, then create with on_top_of or snap with poly_place_on.",
    {
      x: z.number().describe("World X (ray origin)"),
      z: z.number().describe("World Z (ray origin)"),
      from_y: z.number().optional().describe("Ray origin height, default +inf (sky)"),
      ignore: z.string().optional().describe("Node id to exclude (e.g. the node itself)"),
    }, "raycast_down");

  bridgeTool(server, bridge, "poly_get_object_details",
    "Full descriptor of one node by stable id (transform, world-space bounds AABB, asset model-space bounds, light/camera/environment data when present).",
    { id: z.string().describe("Stable node id, e.g. __PolygonEditor__7") }, "details");

  bridgeTool(server, bridge, "poly_select_objects",
    "Replace the editor selection with the given node ids. Locked nodes are skipped and reported.",
    { ids: z.array(z.string()).describe("Stable node ids to select (empty array clears)") }, "select");

  bridgeTool(server, bridge, "poly_focus_object",
    "Move the viewport camera to frame one node.",
    { id: z.string().describe("Stable node id") }, "focus");

  bridgeTool(server, bridge, "poly_set_camera",
    "Move the viewport camera to an exact world position and aim it: either look at a target point or set an absolute orientation (Euler degrees XYZ). One command for framing screenshots from anywhere (e.g. exterior wide shots). Touches no scene content and is not part of undo.",
    {
      position: VEC3.describe("Camera world position [x, y, z]"),
      target: VEC3.optional().describe("Look-at world point [x, y, z] (mutually exclusive with rotation)"),
      rotation: VEC3.optional().describe("Absolute orientation Euler degrees [rx, ry, rz], XYZ order (mutually exclusive with target)"),
    }, "camera", (a) => {
      if (a.target === undefined && a.rotation === undefined) throw new Error("bad_params: one of target/rotation is required");
      if (a.target !== undefined && a.rotation !== undefined) throw new Error("bad_params: use only one of target/rotation");
      return a;
    });

  bridgeTool(server, bridge, "poly_create_object",
    "Spawn a library asset as a new instance. Position is [x,y,z] world units (X/Z always used; Y is the spawn guess unless resting params are given). Rotation is optional Euler degrees [rx,ry,rz] (XYZ order). Scale defaults to [1,1,1]. Optional resting (measured from the real AABB, any pivot): base_y = desired world bottom Y, or on_top_of = support node id + optional gap. Returns the new stable id + final bounds. List valid keys first with poly_get_assets; unknown keys are rejected.",
    {
      asset: z.string().describe("Library asset key, e.g. models/tree.glb"),
      position: VEC3.describe("Spawn position [x, y, z]"),
      rotation: VEC3.optional().describe("Euler degrees [rx, ry, rz], XYZ order"),
      scale: VEC3.optional().describe("Scale [sx, sy, sz], clamped to >= 0.01"),
      label: z.string().optional().describe("Custom instance name (shown in hierarchy, saved to JSON)"),
      base_y: z.number().optional().describe("Desired world bottom Y (mutually exclusive with on_top_of)"),
      on_top_of: z.string().optional().describe("Support node id to rest on (bottom = support top + gap)"),
      gap: z.number().optional().describe("Extra lift above the support top, default 0"),
    }, "create");

  bridgeTool(server, bridge, "poly_set_transform",
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

  bridgeTool(server, bridge, "poly_rename_object",
    "Set a node's custom instance name (1-64 chars, shown in hierarchy, saved to JSON). The stable id never changes. Undoable.",
    { id: z.string(), label: z.string() }, "rename");

  bridgeTool(server, bridge, "poly_delete_objects",
    "Delete nodes by stable id (game camera is protected and rejected). Undoable.",
    { ids: z.array(z.string()).min(1) }, "delete");

  server.registerTool("poly_save_scene", {
    description:
    "Save through the editor's own persistence. Returns file, requested_path, actual_path, path_verified, sandbox_redirected and nodes. Omit name to overwrite; pass name to save-as (sanitized to 64 chars, .json added).",
    inputSchema: { name: z.string().optional() },
  }, async (params) => saveResult(await bridge.call("save", params)));

  bridgeTool(server, bridge, "poly_apply_batch",
    "Validate-then-apply up to 64 ops (create|transform|rename|delete|select|drop_to_ground|place_on) with a single undo entry. Nothing is touched if any op is invalid. NOTE: on_top_of/on must reference an already existing node (same-batch forward refs fail validation like transform does): create supports first, then stack in a second batch.",
    {
      ops: z.array(z.object({
        op: z.enum(["create", "transform", "rename", "delete", "select", "drop_to_ground", "place_on"]),
        params: z.record(z.string(), z.any()).default({}),
      })).min(1).max(64),
    }, "batch");

  bridgeTool(server, bridge, "poly_drop_to_ground",
    "Snap one node so its world bottom (measured AABB, any pivot) rests on ground_y (default 0). Undoable. Use after manual transforms that left objects floating or sunk.",
    {
      id: z.string().describe("Stable node id"),
      ground_y: z.number().optional().describe("World ground Y, default 0"),
    }, "drop_to_ground");

  bridgeTool(server, bridge, "poly_place_on",
    "Rest one node on top of another: bottom = support top + gap, measured from real world AABBs (any pivot). Undoable. X/Z unchanged.",
    {
      id: z.string().describe("Stable node id to move"),
      on: z.string().describe("Support node id"),
      gap: z.number().optional().describe("Extra lift above the support top, default 0"),
    }, "place_on");

  bridgeTool(server, bridge, "poly_set_visible",
    "Show or hide one node in the viewport (slabs, roof, walls: hide occluders for dollhouse views, show them back after). View state only: not saved to JSON, not part of undo. Returns the new visibility.",
    {
      id: z.string().describe("Stable node id"),
      visible: z.boolean().describe("true = show, false = hide"),
    }, "visible");

  bridgeTool(server, bridge, "poly_load_scene",
    "Load a saved scene by name through a chunked loader (progress bar, no freeze). Refuses when the current scene has unsaved changes (save first with poly_save_scene) or another load is running. Returns the node count being loaded; poll poly_get_status until dirty=false.",
    { name: z.string().describe("Saved scene name, e.g. casa") }, "load");

  server.registerTool("poly_take_screenshot", {
    description: "Render an offscreen screenshot without moving or blocking the editor camera. Supply position plus target/rotation, or focus_id with optional position; omit pose to use the current editor view. Clean scene render without overlays, unique PNG path/dimensions and optional MCP image. include_images=false returns paths only; image responses capped at 20 MB.",
    inputSchema: { ...CAPTURE_POSE, hide_ids: z.array(z.string()).max(512).optional(), hide_overlays: z.boolean().optional(), include_images: z.boolean().optional() },
  }, async ({ include_images, ...params }) => {
    if (!validCapturePose(params, true)) throw new Error("bad_params: use position with exactly one of target/rotation, or focus_id without target/rotation");
    return captureResult(await bridge.call("screenshot", params), include_images);
  });

  server.registerTool("poly_capture_views", {
    description: "Render 1-32 named offscreen views without moving/blocking the editor camera. Each view uses position+target/rotation or focus_id with optional position. hide_ids affects only each capture render. Clean scene images without overlays; unique temporary PNG paths, dimensions and optional embedded images.",
    inputSchema: {
      views: z.array(z.object({ name: z.string().min(1).max(64), ...CAPTURE_POSE }).refine((view) => validCapturePose(view), "use position+target/rotation or focus_id")).min(1).max(32),
      hide_ids: z.array(z.string()).max(512).optional(),
      hide_overlays: z.boolean().optional(),
      include_images: z.boolean().optional(),
    },
  }, async ({ include_images, ...params }) => {
    const result = await bridge.call("capture_views", params, { timeoutMs: 10000 + params.views.length * 2000 });
    return captureResult(result, include_images);
  });

  bridgeTool(server, bridge, "poly_audit_overlaps",
    "Report instance pairs whose world AABBs interpenetrate at or beyond min_overlap (default 0.02m), sorted by depth desc with readable labels. Intentional contacts (wall corners, slabs) also appear: narrow the scope with ids or filter them out with ignore.",
    {
      min_overlap: z.number().optional().describe("Minimum penetration depth in meters to report, default 0.02"),
      ids: z.array(z.string()).optional().describe("Limit the check to these node ids"),
      ignore: z.array(z.string()).optional().describe("Node ids to exclude from the check"),
    }, "audit");

  server.registerTool("poly_audit_walkability", {
    description: "Read-only, conservative per-floor AABB/grid audit for a character radius/height: connected regions, isolated areas and named point reachability. Accounts for floor voids and headroom. Not physics/navmesh; stairs do not join levels and assumed-open doorway apertures are estimated. Hidden viewport objects remain geometry.",
    inputSchema: {
      floor_y: z.number().finite(),
      radius: z.number().positive().max(5).optional(),
      height: z.number().positive().max(10).optional(),
      cell_size: z.number().min(0.05).max(1).optional(),
      step_height: z.number().min(0).max(1).optional(),
      floor_tolerance: z.number().min(0).max(0.2).optional(),
      min_area: z.number().min(0).optional(),
      floor_ids: z.array(z.string()).min(1).optional(),
      ignore: z.array(z.string()).optional(),
      assume_open_doors: z.boolean().optional(),
      start: z.object({ x: z.number().finite(), z: z.number().finite() }).optional(),
      probes: z.array(z.object({ name: z.string(), x: z.number().finite(), z: z.number().finite() })).max(128).optional(),
    },
  }, async (params) => {
    const hierarchy = await bridge.call("hierarchy");
    return toolResult(auditWalkability(hierarchy.nodes, params));
  });

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
