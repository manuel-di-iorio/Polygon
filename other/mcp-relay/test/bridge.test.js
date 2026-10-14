import { describe, it } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { BridgeLink, BridgeError } from "../bridge.js";

// Minimal stub of the game side: connects, says hello, answers ops.
function stubGame(port, onRequest) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, "127.0.0.1", () => {
      sock.write(JSON.stringify({ v: 1, hello: "poly-ai" }) + "\n");
    });
    let buf = "";
    sock.setEncoding("utf8");
    sock.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop();
      for (const line of lines) {
        if (!line) continue;
        const msg = JSON.parse(line);
        if (msg.hello === "polygon-mcp-relay") continue; // relay hello
        assert.equal(msg.v, undefined);
        onRequest(sock, msg);
      }
    });
    sock.on("error", reject);
    resolve(sock);
  });
}

const respond = (sock, id, result) =>
  sock.write(JSON.stringify({ id, ok: true, result }) + "\n");

describe("BridgeLink", () => {
  it("reports editor errors without crashing or disconnecting the bridge", async () => {
    let markReady;
    const ready = new Promise((resolve) => { markReady = resolve; });
    const bridge = new BridgeLink({ port: 0, log: (message) => {
      if (message === "editor connected (protocol v1)") markReady();
    } });
    await bridge.start();
    const sock = await stubGame(bridge.server.address().port, (socket, message) => {
      if (message.op === "status") respond(socket, message.id, { tracked: 424 });
      else socket.write(JSON.stringify({ id: message.id, ok: false, error: message.params.error }) + "\n");
    });
    try {
      await ready;
      for (const [error, code] of [
        ["failed: could not write scene file", "failed"],
        ["busy: editor dialog open", "busy"],
        [undefined, "bridge_error"],
      ]) {
        await assert.rejects(bridge.call("save", { error }), (failure) => failure instanceof BridgeError && failure.code === code);
        assert.equal(bridge.connected(), true);
        assert.equal(bridge.pending.size, 0);
        assert.deepEqual(await bridge.call("status"), { tracked: 424 });
      }
    } finally {
      sock.destroy();
      await bridge.stop();
    }
  });

  it("roundtrips an op through a stub game", async () => {
    const bridge = new BridgeLink({ port: 0, log: () => {} });
    await bridge.start();
    const port = bridge.server.address().port;
    const sock = await stubGame(port, (s, msg) => {
      assert.equal(msg.op, "status");
      respond(s, msg.id, { tracked: 3 });
    });
    // wait for hello
    await new Promise((r) => {
      const t = setInterval(() => bridge.connected() && (clearInterval(t), r()), 20);
    });
    const res = await bridge.call("status");
    assert.deepEqual(res, { tracked: 3 });
    sock.destroy();
    await bridge.stop();
  });

  it("rejects protocol mismatch hello", async () => {
    const bridge = new BridgeLink({ port: 0, log: () => {} });
    await bridge.start();
    const port = bridge.server.address().port;
    await new Promise((resolve) => {
      const sock = net.connect(port, "127.0.0.1", () => {
        sock.write(JSON.stringify({ v: 999, hello: "poly-ai" }) + "\n");
      });
      sock.on("close", resolve);
    });
    assert.equal(bridge.connected(), false);
    await bridge.stop();
  });

  it("times out with BridgeError when the game stays silent", async () => {
    const bridge = new BridgeLink({ port: 0, log: () => {} });
    await bridge.start();
    const port = bridge.server.address().port;
    const sock = await stubGame(port, () => {}); // never answers
    await new Promise((r) => {
      const t = setInterval(() => bridge.connected() && (clearInterval(t), r()), 20);
    });
    await assert.rejects(bridge.call("status", {}, { timeoutMs: 150 }), (e) => e instanceof BridgeError && e.code === "timeout");
    sock.destroy();
    await bridge.stop();
  });

  it("rejects calls with not_connected when no game", async () => {
    const bridge = new BridgeLink({ port: 0, log: () => {} });
    await bridge.start();
    await assert.rejects(bridge.call("status"), (e) => e instanceof BridgeError && e.code === "not_connected");
    await bridge.stop();
  });

  it("rejects pending calls when the game disconnects", async () => {
    const bridge = new BridgeLink({ port: 0, log: () => {} });
    await bridge.start();
    const port = bridge.server.address().port;
    const sock = await stubGame(port, () => {}); // never answers
    await new Promise((r) => {
      const t = setInterval(() => bridge.connected() && (clearInterval(t), r()), 20);
    });
    const p = bridge.call("status", {}, { timeoutMs: 5000 });
    sock.destroy();
    await assert.rejects(p, (e) => e instanceof BridgeError && e.code === "disconnected");
    await bridge.stop();
  });
});
