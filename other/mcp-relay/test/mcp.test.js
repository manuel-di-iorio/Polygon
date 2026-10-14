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
import { mkdtemp, writeFile, rm, readFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import vm from "node:vm";

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

function launch(env = process.env) {
  const child = spawn(process.execPath, [serverJs, "--port", "0"], { stdio: ["pipe", "pipe", "pipe"], env });
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
  const localAppData = await mkdtemp(path.join(os.tmpdir(), "poly-save-root-"));
  const { child, request, notify, connectGame } = launch({ ...process.env, LOCALAPPDATA: localAppData });
  after(async () => { child.kill(); await rm(localAppData, { recursive: true, force: true }); });

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

  it("rejects incomplete or conflicting single capture poses", async () => {
    for (const argumentsValue of [{ position: [1, 2, 3] }, { target: [0, 0, 0] }, { focus_id: "sofa", rotation: [0, 0, 0] }]) {
      const res = await request("tools/call", { name: "poly_take_screenshot", arguments: argumentsValue });
      assert.equal(res.result.isError, true);
      assert.doesNotMatch(JSON.stringify(res), /not_connected/);
    }
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
    let saveMetadata = { file: "scenes/casa.json", requested_path: includedFile, sandbox_path: saveFile, content_md5: createHash("md5").update(savedText).digest("hex"), nodes: 424 };
    const requests = [];
    const socket = await connectGame((message) => {
      requests.push(message);
      if (message.op === "capture_views") return { views: [{ name: "room", file: filename, width: 1, height: 1 }], restored: true };
      if (message.op === "screenshot") return { name: "viewport", file: path.join(dir, "outside.png"), width: 1, height: 1 };
      if (message.op === "save") return saveMetadata;
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
      const shot = await request("tools/call", { name: "poly_take_screenshot", arguments: { position: [1, 2, 3], target: [0, 0, 0], hide_ids: ["roof"] } });
      assert.equal(shot.result.content.length, 1);
      assert.equal(JSON.parse(shot.result.content[0].text).skipped_images.length, 1);
      assert.equal(requests[1].op, "screenshot");
      assert.deepEqual(requests[1].params.position, [1, 2, 3]);
      const focused = await request("tools/call", { name: "poly_capture_views", arguments: { views: [{ name: "sofa", focus_id: "sofa" }], include_images: false } });
      assert.equal(focused.result.isError, undefined);
      assert.equal(requests[2].params.views[0].focus_id, "sofa");
      const save = await request("tools/call", { name: "poly_save_scene", arguments: {} });
      assert.equal(JSON.parse(save.result.content[0].text).sandbox_redirected, true);
      assert.equal(JSON.parse(save.result.content[0].text).actual_path, saveFile);
      assert.equal(JSON.parse(save.result.content[0].text).path_verified, true);
      await writeFile(includedFile, savedText);
      const ambiguous = await request("tools/call", { name: "poly_save_scene", arguments: {} });
      assert.equal(JSON.parse(ambiguous.result.content[0].text).path_verified, false);
      assert.equal(JSON.parse(ambiguous.result.content[0].text).matching_paths.length, 2);
      const projectDirectory = path.join(temporary, "fixture");
      const sandboxFile = path.join(localAppData, "fixture", "scenes", "casa.json");
      await mkdir(projectDirectory, { recursive: true });
      await writeFile(path.join(projectDirectory, "fixture.yyp"), "{}");
      await mkdir(path.dirname(sandboxFile), { recursive: true });
      await writeFile(sandboxFile, savedText);
      saveMetadata = { ...saveMetadata, requested_path: path.join(projectDirectory, "Build", "scenes", "casa.json"), sandbox_path: undefined };
      const gmrtSave = await request("tools/call", { name: "poly_save_scene", arguments: {} });
      assert.equal(JSON.parse(gmrtSave.result.content[0].text).path_verified, true);
      assert.equal(JSON.parse(gmrtSave.result.content[0].text).actual_path, sandboxFile);
      const audit = await request("tools/call", { name: "poly_audit_walkability", arguments: { floor_y: 0, start: { x: 1, z: 1 }, probes: [{ name: "isolated", x: 6, z: 3 }] } });
      assert.equal(JSON.parse(audit.result.content[0].text).probes[0].reachable, false);
    } finally {
      socket.destroy();
      await rm(temporary, { recursive: true, force: true });
    }
  });
});

describe("offscreen GML capture contracts", async () => {
  const source = await readFile(path.join(dir, "../../../scripts/poly_ai/poly_ai.gml"), "utf8");
  const functionSource = (name) => {
    const start = source.indexOf(`function ${name}(`);
    const following = source.indexOf("\nfunction ", start + 1);
    const end = following === -1 ? source.indexOf("\n// Reports", start) : following;
    return source.slice(start, end);
  };
  const makeContext = (failRender = false) => {
    let cameraPositionWrites = 0;
    let rendererCount = 0;
    let saved = false;
    let finished = "pending";
    const component = { enabled: true, getEnabled() { return this.enabled; }, setEnabled(value) { this.enabled = value; }, setScreenRect() {} };
    const editorCamera = { getCameraComponent: () => component, getChildren: () => [], getLocalPosition: () => ({ x: 5, y: 6, z: 7 }), setLocalPosition: () => { cameraPositionWrites++; } };
    const camera = { addComponent() {}, getCameraComponent: () => ({ setEnabled() {}, setScreenRect() {} }) };
    const scene = { createNode: () => camera, update() {} };
    const node = { getChildren: () => [] };
    const animation = { t: 0.5 };
    const editor = { active: true, rt: { cam: editorCamera, scene }, scene_w: 800, scene_h: 600, cam_anim: animation, ai: { capture: undefined } };
    const muted = { enabled: true };
    const context = {
      undefined, current_time: 0, temp_directory: "temp/",
      variable_struct_exists: (value, key) => value !== undefined && Object.hasOwn(value, key),
      is_struct: (value) => value !== undefined && value !== null && typeof value === "object" && !Array.isArray(value),
      is_array: Array.isArray, is_string: (value) => typeof value === "string", array_length: (value) => value.length,
      array_push: (array, value) => array.push(value), string: String, string_copy: (value, start, count) => value.slice(start - 1, start - 1 + count),
      round: Math.round, clamp: (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value)),
      surface_create: () => 1, surface_exists: (value) => value === 1, surface_set_target() {}, surface_reset_target() {}, surface_save: () => { saved = true; },
      surface_get_width: () => 800, surface_get_height: () => 600, draw_clear() {}, c_black: 0, file_exists: () => saved,
      GM3D_Renderer: class { constructor() { rendererCount++; } render() { assert.equal(component.enabled, false); if (failRender) throw new Error("render failure"); } },
      GM3D_CameraComponent: class {}, __poly_ai_state: (value) => value.ai,
      __poly_ai_err: (code, message) => ({ error: true, error_code: code, error_msg: message }), __poly_ai_v_camera: (pose) => Array.isArray(pose.position) && Array.isArray(pose.rotation ?? pose.target) ? undefined : "invalid pose",
      __poly_ai_v_err: (value) => value, __poly_ai_node: () => node, __poly_locked_get: () => false,
      __poly_camera_read: () => ({ enabled: true }), __poly_camera_apply() {}, __poly_ai_transform_of: () => ({ rotation_euler_deg: [0, 0, 0] }),
      __poly_ai_op_camera: (value) => { assert.notEqual(value, editor); assert.equal(value.rt.cam, camera); return {}; },
      __poly_tracked_nodes: () => [], __poly_walk_tree: (value, callback, states) => callback(value, states),
      __poly_walk_mute_node: (value, states) => { states.push({ comp: muted, was: muted.enabled }); muted.enabled = false; },
      __poly_walk_restore: (swapped, states) => { for (const state of states) state.comp.enabled = state.was; },
      __poly_destroy_subtree() {}, __poly_sanitize_scene_name: (value) => value,
      __poly_ai_capture_finish: (value, code = "") => { finished = code; value.ai.capture = undefined; },
    };
    vm.createContext(context);
    for (const name of ["__poly_ai_capture_active", "__poly_ai_capture_pose", "__poly_ai_capture_begin", "__poly_ai_capture_draw"]) vm.runInContext(functionSource(name), context);
    return { context, editor, component, muted, animation, positionWrites: () => cameraPositionWrites, rendererCount: () => rendererCount, finished: () => finished };
  };

  it("returns save metadata without the unavailable GMRT save_directory global", () => {
    const text = '{"version":2,"nodes":[]}';
    const context = {
      variable_struct_exists: (value, key) => Object.hasOwn(value, key),
      is_string: (value) => typeof value === "string",
      string_pos: (value, textValue) => textValue.indexOf(value) + 1,
      string_char_at: (value, index) => value.charAt(index - 1),
      working_directory: "C:/fixture/Build/assets/",
      __poly_save_scene: () => true,
      __poly_read_text_file: () => text,
      __poly_serialize_scene: () => [],
      array_length: (value) => value.length,
      md5_string_utf8: (value) => createHash("md5").update(value).digest("hex"),
    };
    vm.createContext(context);
    vm.runInContext(functionSource("__poly_ai_op_save"), context);
    const result = context.__poly_ai_op_save({ scene_file: "__PolygonEditor__/scenes/casa.json" }, {});
    assert.equal(result.requested_path, "C:/fixture/Build/assets/__PolygonEditor__/scenes/casa.json");
    assert.equal(result.content_md5, createHash("md5").update(text).digest("hex"));
    assert.equal(result.path_verified, false);
  });

  it("renders with a separate camera and leaves editor pose, animation and input untouched", async () => {
    const state = makeContext();
    state.context.__poly_ai_capture_begin(state.editor, "test", { hide_ids: ["roof"] }, true);
    assert.equal(state.muted.enabled, true);
    state.context.__poly_ai_capture_draw(state.editor);
    assert.equal(state.finished(), "");
    assert.equal(state.positionWrites(), 0);
    assert.equal(state.editor.cam_anim, state.animation);
    assert.equal(state.component.enabled, true);
    assert.equal(state.muted.enabled, true);
    const core = await readFile(path.join(dir, "../../../scripts/poly_core/poly_core.gml"), "utf8");
    assert.doesNotMatch(core, /if \(__poly_ai_capture_active\(_ed\)\) return/);
  });

  it("restores render flags even when the offscreen renderer throws", () => {
    const state = makeContext(true);
    state.context.__poly_ai_capture_begin(state.editor, "test", { hide_ids: ["roof"] }, true);
    state.context.__poly_ai_capture_draw(state.editor);
    assert.equal(state.finished(), "failed");
    assert.equal(state.positionWrites(), 0);
    assert.equal(state.component.enabled, true);
    assert.equal(state.muted.enabled, true);
  });

  it("uses a fresh renderer for each batch view instead of reusing camera state", () => {
    const state = makeContext();
    state.context.__poly_ai_capture_begin(state.editor, "batch", { views: [
      { name: "first", position: [1, 2, 3], rotation: [0, 0, 0] },
      { name: "second", position: [4, 2, 1], rotation: [0, 90, 0] },
    ] }, false);
    state.context.__poly_ai_capture_draw(state.editor);
    assert.equal(state.rendererCount(), 1);
    assert.equal(state.finished(), "pending");
    state.context.__poly_ai_capture_draw(state.editor);
    assert.equal(state.rendererCount(), 2);
    assert.equal(state.finished(), "");
    assert.equal(state.positionWrites(), 0);
  });
});
