import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { auditWalkability } from "../walkability.js";

function node(id, assetId, min, max, hidden = false) {
  return { id, kind: "instance", assetId, hidden, bounds: { valid: true, min, max } };
}

const floor = node("floor", "Structure_Floor.glb", [0, -0.2, 0], [8, 0, 6]);

describe("walkability audit", () => {
  it("includes hidden viewport floors and connects an unobstructed room", () => {
    const result = auditWalkability([{ ...floor, hidden: true }], { start: { x: 1, z: 1 }, probes: [{ name: "corner", x: 7, z: 5 }] });
    assert.equal(result.components.length, 1);
    assert.equal(result.probes[0].reachable, true);
  });
  it("detects an isolated room behind a wall", () => {
    const wall = node("wall", "Structure_Wall.glb", [3.9, 0, 0], [4.1, 2.6, 6]);
    const result = auditWalkability([floor, wall], { start: { x: 1, z: 1 }, probes: [{ name: "other", x: 6, z: 3 }] });
    assert.equal(result.components.length, 2);
    assert.equal(result.probes[0].reachable, false);
    assert.equal(result.disconnected.length, 1);
  });
  it("rejects a corridor narrower than the character", () => {
    const upperWall = node("upper", "wall", [3, 0, 3.2], [4, 2, 6]);
    const lowerWall = node("lower", "wall", [3, 0, 0], [4, 2, 2.8]);
    const result = auditWalkability([floor, upperWall, lowerWall], { start: { x: 1, z: 3 }, probes: [{ x: 6, z: 3 }] });
    assert.equal(result.probes[0].reachable, false);
  });
  it("detects unsupported voids between slabs", () => {
    const left = node("left", "floor", [0, -0.2, 0], [3, 0, 6]);
    const right = node("right", "floor", [5, -0.2, 0], [8, 0, 6]);
    const result = auditWalkability([left, right], { probes: [{ name: "hole", x: 4, z: 3 }] });
    assert.equal(result.components.length, 2);
    assert.equal(result.probes[0].state, "unsupported");
  });
  it("does not introduce seams between adjacent floor slabs", () => {
    const left = node("left", "floor", [0, -0.2, 0], [4, 0, 6]);
    const right = node("right", "floor", [4, -0.2, 0], [8, 0, 6]);
    assert.equal(auditWalkability([left, right]).components.length, 1);
  });
  it("respects headroom and configurable door assumptions", () => {
    const lowCeiling = node("ceiling", "floor", [0, 1.4, 0], [8, 1.6, 6]);
    assert.equal(auditWalkability([floor, lowCeiling]).walkable_cells, 0);
    const doorway = node("doorway", "Structure_Wall_Doorway.glb", [3.9, 0, 0], [4.1, 2.6, 6]);
    assert.equal(auditWalkability([floor, doorway]).components.length, 1);
    assert.equal(auditWalkability([floor, doorway], { assume_open_doors: false }).components.length, 2);
  });
  it("supports upper floors, explicit floor ids and obstacle exclusions", () => {
    const support = node("support", "custom", [0, 2.4, 0], [8, 2.6, 6]);
    const wall = node("wall", "wall", [3.9, 2.6, 0], [4.1, 5.2, 6]);
    const result = auditWalkability([support, wall], { floor_y: 2.6, floor_ids: ["support"], ignore: ["wall"] });
    assert.equal(result.components.length, 1);
  });
  it("reports unknown reachability when start is blocked", () => {
    const box = node("box", "box", [0, 0, 0], [2, 2, 2]);
    const result = auditWalkability([floor, box], { start: { x: 1, z: 1 }, probes: [{ x: 6, z: 3 }] });
    assert.equal(result.start.state, "blocked");
    assert.equal(result.probes[0].reachable, null);
  });
  it("rejects missing floors, invalid dimensions, unknown ids and excessive grids", () => {
    assert.throws(() => auditWalkability([]), /no_floor/);
    assert.throws(() => auditWalkability([floor], { radius: -1 }), /bad_params/);
    assert.throws(() => auditWalkability([floor], { ignore: ["missing"] }), /not_found/);
    const huge = node("huge", "floor", [0, -0.2, 0], [1000, 0, 1000]);
    assert.throws(() => auditWalkability([huge]), /too_large/);
  });
});