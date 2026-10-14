// End-to-end MCP conformance: spawn the real server over stdio, run the
// handshake, check tool discovery, and verify a tool call without a game
// fails cleanly (never a faked success).
import { describe, it, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";
import os from "node:os";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { createHash } from "node:crypto";

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
  "poly_set_camera",
  "poly_set_visible",
  "poly_load_scene",
  "poly_create_object",
  "poly_set_transform",
  "poly_rename_object",
  "poly_delete_objects",
  "poly_save_scene",
  "poly_apply_batch",
  "poly_drop_to_ground",
  "poly_place_on",
  "poly_take_screenshot",
  "poly_capture_views",
  "poly_audit_overlaps",
  "poly_audit_walkability",
  "poly_raycast_down",
];

function launch() {
  const child = spawn(process.execPath, [serverJs, "--port", "0"], { stdio: ["pipe", "pipe", "pipe"] });
  let logBuffer = "";
  const port = new Promise((resolve) => {
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      logBuffer += chunk;
      const match = logBuffer.match(/listening on 127\.0\.0\.1:(\d+)/);
      if (match) resolve(Number(match[1]));
    });
  });
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
  const connectGame = async (handler) => {
    const gamePort = await port;
    return new Promise((resolve, reject) => {
      const socket = net.connect(gamePort, "127.0.0.1", () => socket.write(JSON.stringify({ v: 1, hello: "poly-ai" }) + "\n"));
      let incoming = "";
      socket.setEncoding("utf8");
      socket.on("error", reject);
      socket.on("data", (chunk) => {
        incoming += chunk;
        const lines = incoming.split("\n");
        incoming = lines.pop();
        for (const line of lines) {
          if (!line) continue;
          const message = JSON.parse(line);
          if (message.hello === "polygon-mcp-relay") resolve(socket);
          else socket.write(JSON.stringify({ id: message.id, ok: true, result: handler(message) }) + "\n");
        }
      });
    });
  };
  return { child, request, notify, connectGame };
}

describe("MCP server", async () => {
  const { child, request, notify, connectGame } = launch();
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

  it("validates capture cameras before forwarding", async () => {
    const res = await request("tools/call", { name: "poly_capture_views", arguments: { views: [{ name: "invalid", position: [0, 2, 3] }] } });
    assert.ok(res.error || res.result?.isError);
    assert.doesNotMatch(JSON.stringify(res), /not_connected/);
  });

  it("rejects empty capture batches", async () => {
    const res = await request("tools/call", { name: "poly_capture_views", arguments: { views: [] } });
    assert.ok(res.error || res.result?.isError);
    assert.doesNotMatch(JSON.stringify(res), /not_connected/);
  });

  it("forwards a valid capture and reports a disconnected editor", async () => {
    const res = await request("tools/call", { name: "poly_capture_views", arguments: { views: [{ name: "room", position: [0, 2, 3], target: [0, 0, 0] }], hide_ids: [], hide_overlays: true } });
    assert.equal(res.result.isError, true);
    assert.match(JSON.stringify(res), /not_connected/);
  });

  it("roundtrips captures, save metadata and reachability through a connected editor", async () => {
    const temporary = await mkdtemp(path.join(os.tmpdir(), "poly-capture-test-"));
    const filename = path.join(temporary, "view.png");
    await writeFile(filename, Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ0kAAAAASUVORK5CYII=", "base64"));
    const saveFile = path.join(temporary, "saved.json");
    const includedFile = path.join(temporary, "included.json");
    const savedText = '{"version":2,"nodes":[]}';
    await writeFile(saveFile, savedText);
    const requests = [];
    const socket = await connectGame((message) => {
      requests.push(message);
      if (message.op === "capture_views") return { views: [{ name: "room", file: filename, width: 1, height: 1 }], restored: true };
      if (message.op === "screenshot") return { name: "viewport", file: path.join(dir, "outside.png"), width: 1, height: 1 };
      if (message.op === "save") return { file: "scenes/casa.json", requested_path: includedFile, sandbox_path: saveFile, content_md5: createHash("md5").update(savedText).digest("hex"), nodes: 424 };
      return { nodes: [
        { id: "floor", kind: "instance", assetId: "floor", bounds: { valid: true, min: [0, -0.2, 0], max: [8, 0, 6] } },
        { id: "wall", kind: "instance", assetId: "wall", bounds: { valid: true, min: [3.9, 0, 0], max: [4.1, 2.6, 6] } },
      ] };
    });
    try {
      const capture = await request("tools/call", { name: "poly_capture_views", arguments: { views: [{ name: "room", position: [0, 2, 3], target: [0, 0, 0] }], hide_ids: ["roof"] } });
      assert.equal(capture.result.isError, undefined);
      assert.equal(capture.result.content[1].type, "image");
      assert.equal(JSON.parse(capture.result.content[0].text).restored, true);
      assert.deepEqual(requests[0].params.hide_ids, ["roof"]);
      const shot = await request("tools/call", { name: "poly_take_screenshot", arguments: {} });
      assert.equal(shot.result.content.length, 1);
      assert.equal(JSON.parse(shot.result.content[0].text).skipped_images.length, 1);
      const save = await request("tools/call", { name: "poly_save_scene", arguments: {} });
      assert.equal(JSON.parse(save.result.content[0].text).sandbox_redirected, true);
      assert.equal(JSON.parse(save.result.content[0].text).actual_path, saveFile);
      assert.equal(JSON.parse(save.result.content[0].text).path_verified, true);
      await writeFile(includedFile, savedText);
      const ambiguous = await request("tools/call", { name: "poly_save_scene", arguments: {} });
      assert.equal(JSON.parse(ambiguous.result.content[0].text).path_verified, false);
      assert.equal(JSON.parse(ambiguous.result.content[0].text).matching_paths.length, 2);
      const audit = await request("tools/call", { name: "poly_audit_walkability", arguments: { floor_y: 0, start: { x: 1, z: 1 }, probes: [{ name: "isolated", x: 6, z: 3 }] } });
      assert.equal(JSON.parse(audit.result.content[0].text).probes[0].reachable, false);
    } finally {
      socket.destroy();
      await rm(temporary, { recursive: true, force: true });
    }
  });
});
