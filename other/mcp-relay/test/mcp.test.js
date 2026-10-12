// End-to-end MCP conformance: spawn the real server over stdio, run the
// handshake, check tool discovery, and verify a tool call without a game
// fails cleanly (never a faked success).
import { describe, it, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const serverJs = path.join(dir, "..", "server.js");

const EXPECTED_TOOLS = [
  "poly_get_status",
  "poly_get_scene_hierarchy",
  "poly_get_selection",
  "poly_get_object_details",
  "poly_get_assets",
  "poly_select_objects",
  "poly_focus_object",
  "poly_create_object",
  "poly_set_transform",
  "poly_rename_object",
  "poly_delete_objects",
  "poly_save_scene",
  "poly_apply_batch",
  "poly_drop_to_ground",
  "poly_place_on",
  "poly_raycast_down",
];

function launch() {
  const child = spawn(process.execPath, [serverJs, "--port", "0"], { stdio: ["pipe", "pipe", "pipe"] });
  let buf = "";
  const waiters = [];
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    buf += chunk;
    pump();
  });
  function pump() {
    const lines = buf.split("\n");
    buf = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      const w = waiters.shift();
      if (w) w(JSON.parse(line));
    }
  }
  let nextId = 1;
  const request = (method, params) => new Promise((resolve, reject) => {
    const id = nextId++;
    const timer = setTimeout(() => reject(new Error(`no response for ${method}`)), 8000);
    waiters.push((msg) => {
      clearTimeout(timer);
      resolve(msg);
    });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
  const notify = (method, params) => {
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
  };
  return { child, request, notify };
}

describe("MCP server", async () => {
  const { child, request, notify } = launch();
  after(() => child.kill());

  it("handshakes (initialize)", async () => {
    const res = await request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "poly-test", version: "0" },
    });
    assert.ok(res.result, `initialize failed: ${JSON.stringify(res)}`);
    assert.ok(res.result.serverInfo);
    notify("notifications/initialized", {});
  });

  it("discovers all tools", async () => {
    const res = await request("tools/list", {});
    const names = res.result.tools.map((t) => t.name).sort();
    assert.deepEqual(names, [...EXPECTED_TOOLS].sort());
    for (const t of res.result.tools) {
      assert.ok(t.description && t.description.length > 10, `empty description: ${t.name}`);
      assert.ok(t.inputSchema, `no schema: ${t.name}`);
    }
  });

  it("reports not_connected instead of faking success", async () => {
    const res = await request("tools/call", { name: "poly_get_status", arguments: {} });
    assert.equal(res.result.isError, true);
    const text = JSON.stringify(res.result.content);
    assert.match(text, /not_connected/);
  });

  it("rejects unknown tools", async () => {
    const res = await request("tools/call", { name: "poly_nope", arguments: {} });
    assert.ok(res.error || res.result?.isError, "expected an error for unknown tool");
  });
});
