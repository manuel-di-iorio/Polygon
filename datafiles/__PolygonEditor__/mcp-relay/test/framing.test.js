import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { LineDecoder } from "../bridge.js";

describe("LineDecoder", () => {
  it("splits complete lines and keeps the tail", () => {
    const d = new LineDecoder();
    assert.deepEqual(d.push('{"a":1}\n{"b":'), ['{"a":1}']);
    assert.deepEqual(d.push('2}\n{"c":3}\n'), ['{"b":2}', '{"c":3}']);
    assert.deepEqual(d.push(""), []);
  });

  it("ignores empty lines", () => {
    const d = new LineDecoder();
    assert.deepEqual(d.push("\n\n{}\n"), ["{}"]);
  });

  it("resets on overflow", () => {
    const d = new LineDecoder(8);
    assert.throws(() => d.push("123456789"), /overflow/);
    assert.deepEqual(d.push("{}\n"), ["{}"]);
  });
});
