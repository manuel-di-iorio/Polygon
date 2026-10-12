// TCP link to the Polygon editor

import net from "node:net";
import { randomUUID } from "node:crypto";

export const BRIDGE_PROTOCOL_VERSION = 1;
export const BRIDGE_HELLO_GAME = "polygon-ai";
export const BRIDGE_HELLO_RELAY = "polygon-mcp-relay";

export class BridgeError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.code = code;
  }
}

// Splits a text stream into complete LF-delimited lines, keeping the tail.
export class LineDecoder {
  constructor(maxBytes = 4 * 1024 * 1024) {
    this.buf = "";
    this.maxBytes = maxBytes;
  }

  push(chunk) {
    this.buf += chunk;

    if (this.buf.length > this.maxBytes) {
      this.buf = "";
      throw new BridgeError("overflow", "incoming frame exceeds size cap");
    }

    const lines = this.buf.split("\n");
    this.buf = lines.pop();
    return lines.filter((l) => l.length > 0);
  }
}

export class BridgeLink {
  constructor({ host = "127.0.0.1", port = 5192, timeoutMs = 10000, helloTimeoutMs = 5000, log = () => {} } = {}) {
    this.host = host;
    this.port = port;
    this.timeoutMs = timeoutMs;
    this.helloTimeoutMs = helloTimeoutMs;
    this.log = log;
    this.server = null;
    this.game = null; // net.Socket of the connected editor, post-hello
    this.decoder = new LineDecoder();
    this.pending = new Map(); // id -> { resolve, reject, timer }
  }

  connected() {
    return this.game !== null && !this.game.destroyed;
  }

  start() {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((sock) => this._onSocket(sock));
      this.server.on("error", (err) => {
        this.log(`tcp listen failed on ${this.host}:${this.port}: ${err.message}`);
        reject(err);
      });
      this.server.listen(this.port, this.host, () => {
        this.log(`listening on ${this.host}:${this.port} (waiting for editor)`);
        resolve();
      });
    });
  }

  async stop() {
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new BridgeError("shutdown", "relay is stopping"));
    }
    this.pending.clear();

    if (this.game) {
      this.game.destroy();
      this.game = null;
    }

    if (this.server) {
      await new Promise((resolve) => this.server.close(resolve));
      this.server = null;
    }
  }

  _onSocket(sock) {
    const peer = `${sock.remoteAddress}:${sock.remotePort}`;
    this.log(`incoming connection from ${peer}`);

    if (this.game) {
      this.log("replacing previous editor connection");
      this.game.destroy();
      this.game = null;
    }

    sock.setEncoding("utf8");
    const decoder = new LineDecoder();
    let helloOk = false;
    const helloTimer = setTimeout(() => {
      if (!helloOk) {
        this.log(`no hello from ${peer}, dropping`);
        sock.destroy();
      }
    }, this.helloTimeoutMs);

    const failPending = (err) => {
      for (const [, p] of this.pending) {
        clearTimeout(p.timer);
        p.reject(err);
      }
      this.pending.clear();
    };

    sock.on("data", (chunk) => {
      let lines;
      try {
        lines = decoder.push(chunk);
      } catch (err) {
        this.log(`framing error from ${peer}: ${err.message}`);
        sock.destroy();
        return;
      }

      for (const line of lines) {
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          this.log(`ignoring malformed JSON from ${peer}`);
          continue;
        }
        this._onMessage(sock, msg, () => helloOk, (v) => { helloOk = v; });
      }
    });

    const onGone = (why) => {
      clearTimeout(helloTimer);
      if (this.game === sock) {
        this.game = null;
        this.log(`editor disconnected (${why})`);
        failPending(new BridgeError("disconnected", "editor disconnected mid-call"));
      }
    };
    sock.on("close", () => onGone("close"));
    sock.on("error", (err) => {
      this.log(`socket error from ${peer}: ${err.message}`);
      onGone("error");
    });
  }

  _onMessage(sock, msg, isHello, setHello) {
    if (msg === null || typeof msg !== "object" || Array.isArray(msg)) return;

    // Pre-hello: only the versioned hello is accepted.
    if (!isHello()) {
      if (msg.hello === BRIDGE_HELLO_GAME) {
        if (msg.v !== BRIDGE_PROTOCOL_VERSION) {
          this.log(`protocol mismatch (game v${msg.v}), dropping`);
          sock.destroy();
          return;
        }
        setHello(true);
        this.game = sock;
        this.log("editor connected (protocol v1)");
        this._write(sock, { v: BRIDGE_PROTOCOL_VERSION, hello: BRIDGE_HELLO_RELAY });
        return;
      }
      return; // ignore anything before hello
    }

    if (this.game !== sock) return; // stale socket after replacement

    if (typeof msg.id !== "string") return;
    const p = this.pending.get(msg.id);
    if (!p) return; // late/unknown response
    this.pending.delete(msg.id);
    clearTimeout(p.timer);

    if (msg.ok === true) {
      p.resolve(msg.result === undefined ? {} : msg.result);
    } else {
      p.reject(BridgeError.fromResponse(msg));
    }
  }

  _write(sock, obj) {
    if (sock.destroyed) return false;
    sock.write(JSON.stringify(obj) + "\n", "utf8");
    return true;
  }

  // Sends one op to the editor and resolves with result (throws BridgeError).
  call(op, params = {}, { timeoutMs = this.timeoutMs } = {}) {
    if (!this.connected()) {
      return Promise.reject(new BridgeError("not_connected", "editor not connected (press the AI button in the editor menu bar)"));
    }

    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new BridgeError("timeout", `no response from editor for op ${op} within ${timeoutMs}ms`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      if (!this._write(this.game, { id, op, params })) {
        this.pending.delete(id);
        clearTimeout(timer);
        reject(new BridgeError("disconnected", "editor socket is gone"));
      }
    });
  }

  static fromResponse(msg) {
    const raw = typeof msg.error === "string" ? msg.error : "unknown bridge error";
    const i = raw.indexOf(":");
    const code = i > 0 ? raw.slice(0, i).trim().replace(/\s+/g, "_") : "bridge_error";
    return new BridgeError(code || "bridge_error", i > 0 ? raw.slice(i + 1).trim() : raw);
  }
}
