const MAX_CELLS = 150000;

function validBounds(bounds) {
  return bounds?.valid === true && [bounds.min, bounds.max].every((vector) =>
    Array.isArray(vector) && vector.length === 3 && vector.every(Number.isFinite)) &&
    bounds.min.every((value, axis) => value <= bounds.max[axis]);
}

function contains(bounds, horizontal, depth) {
  return horizontal >= bounds.min[0] && horizontal <= bounds.max[0] &&
    depth >= bounds.min[2] && depth <= bounds.max[2];
}

function obstacleDistance(bounds, horizontal, depth) {
  return Math.hypot(Math.max(bounds.min[0] - horizontal, 0, horizontal - bounds.max[0]),
    Math.max(bounds.min[2] - depth, 0, depth - bounds.max[2]));
}

export function auditWalkability(nodes, options = {}) {
  const floorY = options.floor_y ?? 0;
  const radius = options.radius ?? 0.3;
  const height = options.height ?? 1.8;
  const cellSize = options.cell_size ?? 0.1;
  const stepHeight = options.step_height ?? 0.15;
  const tolerance = options.floor_tolerance ?? 0.05;
  if (![floorY, radius, height, cellSize, stepHeight, tolerance].every(Number.isFinite) ||
      radius <= 0 || height <= 0 || cellSize < 0.05 || stepHeight < 0 || stepHeight >= height || tolerance < 0) {
    throw new Error("bad_params: invalid character or grid dimensions");
  }
  if (!Array.isArray(nodes)) throw new Error("bad_scene: hierarchy must contain nodes");
  const nodeIds = new Set(nodes.map((node) => node.id));
  for (const nodeId of [...(options.floor_ids ?? []), ...(options.ignore ?? [])]) {
    if (!nodeIds.has(nodeId)) throw new Error(`not_found: unknown node ${nodeId}`);
  }
  const ignored = new Set(options.ignore ?? []);
  const selectedFloors = options.floor_ids ? new Set(options.floor_ids) : null;
  const instances = nodes.filter((node) => node.kind === "instance" && validBounds(node.bounds) && !ignored.has(node.id));
  const floors = instances.filter((node) => {
    const matches = selectedFloors ? selectedFloors.has(node.id) : /floor|slab/i.test(`${node.assetId ?? ""} ${node.label ?? ""}`);
    return matches && Math.abs(node.bounds.max[1] - floorY) <= tolerance && node.bounds.max[1] - node.bounds.min[1] <= 0.35;
  });
  if (!floors.length) throw new Error("no_floor: no horizontal floor at floor_y; provide floor_ids for unnamed floors");
  const floorIds = new Set(floors.map((node) => node.id));
  const obstacles = [];
  const assumedDoors = [];
  for (const node of instances) {
    const bounds = node.bounds;
    if (floorIds.has(node.id) || bounds.max[1] <= floorY + stepHeight || bounds.min[1] >= floorY + height) continue;
    const doorway = /doorway/i.test(node.assetId ?? "");
    const doorLeaf = /(?:^|[_/])door\.glb$/i.test(node.assetId ?? "") || /door leaf/i.test(node.label ?? "");
    if (options.assume_open_doors !== false && (doorway || doorLeaf)) {
      assumedDoors.push(node.id);
      if (doorway) {
        const axis = bounds.max[0] - bounds.min[0] >= bounds.max[2] - bounds.min[2] ? 0 : 2;
        const span = bounds.max[axis] - bounds.min[axis];
        const openingHeight = (bounds.max[1] - bounds.min[1]) * 0.9;
        if (floorY + height >= bounds.min[1] + openingHeight) {
          obstacles.push(bounds);
        } else {
          const lower = { min: [...bounds.min], max: [...bounds.max] };
          const upper = { min: [...bounds.min], max: [...bounds.max] };
          lower.max[axis] = bounds.min[axis] + span * 0.15;
          upper.min[axis] = bounds.max[axis] - span * 0.15;
          obstacles.push(lower, upper);
        }
      }
      continue;
    }
    obstacles.push(bounds);
  }
  const minimumX = Math.min(...floors.map((node) => node.bounds.min[0]));
  const minimumZ = Math.min(...floors.map((node) => node.bounds.min[2]));
  const maximumX = Math.max(...floors.map((node) => node.bounds.max[0]));
  const maximumZ = Math.max(...floors.map((node) => node.bounds.max[2]));
  const columns = Math.ceil((maximumX - minimumX) / cellSize);
  const rows = Math.ceil((maximumZ - minimumZ) / cellSize);
  const total = columns * rows;
  if (!Number.isSafeInteger(total) || total < 1 || total > MAX_CELLS) throw new Error(`too_large: grid exceeds ${MAX_CELLS} cells; increase cell_size or limit floor_ids`);
  const supported = new Uint8Array(total);
  const free = new Uint8Array(total);
  const components = new Int32Array(total).fill(-1);
  const sampleRadius = radius + cellSize * Math.SQRT1_2;
  const offsets = Array.from({ length: 8 }, (_, index) => [Math.cos(index * Math.PI / 4) * sampleRadius, Math.sin(index * Math.PI / 4) * sampleRadius]);
  const position = (index) => ({ x: minimumX + (index % columns + 0.5) * cellSize, z: minimumZ + (Math.floor(index / columns) + 0.5) * cellSize });
  const supportedAt = (horizontal, depth) => floors.some((node) => contains(node.bounds, horizontal, depth));
  for (let index = 0; index < total; index++) {
    const point = position(index);
    if (!supportedAt(point.x, point.z) || !offsets.every(([offsetX, offsetZ]) => supportedAt(point.x + offsetX, point.z + offsetZ))) continue;
    supported[index] = 1;
    if (obstacles.every((bounds) => obstacleDistance(bounds, point.x, point.z) > sampleRadius)) free[index] = 1;
  }
  const regions = [];
  const queue = new Int32Array(total);
  for (let seed = 0; seed < total; seed++) {
    if (!free[seed] || components[seed] !== -1) continue;
    const regionId = regions.length;
    let front = 0;
    let back = 1;
    queue[0] = seed;
    components[seed] = regionId;
    let sumX = 0;
    let sumZ = 0;
    while (front < back) {
      const index = queue[front++];
      const point = position(index);
      sumX += point.x;
      sumZ += point.z;
      const column = index % columns;
      const neighbours = [column > 0 ? index - 1 : -1, column < columns - 1 ? index + 1 : -1, index - columns, index + columns];
      for (const neighbour of neighbours) {
        if (neighbour < 0 || neighbour >= total || !free[neighbour] || components[neighbour] !== -1) continue;
        components[neighbour] = regionId;
        queue[back++] = neighbour;
      }
    }
    regions.push({ id: regionId, area: Number((back * cellSize ** 2).toFixed(3)), cells: back, representative: position(seed), centroid: { x: sumX / back, z: sumZ / back } });
  }
  const locate = (point) => {
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.z)) throw new Error("bad_params: points require finite x/z");
    const column = Math.floor((point.x - minimumX) / cellSize);
    const row = Math.floor((point.z - minimumZ) / cellSize);
    if (column < 0 || column >= columns || row < 0 || row >= rows) return { state: "unsupported", component: null };
    const index = row * columns + column;
    if (!supported[index]) return { state: "unsupported", component: null };
    if (!free[index]) return { state: "blocked", component: null };
    return { state: "walkable", component: components[index] };
  };
  const largest = [...regions].sort((first, second) => second.cells - first.cells)[0];
  const start = options.start ? { ...options.start, ...locate(options.start) } : null;
  const anchor = start ? start.component : (largest?.id ?? null);
  const probes = (options.probes ?? []).map((point) => {
    const location = locate(point);
    return { ...point, ...location, reachable: anchor === null ? null : location.component === anchor };
  });
  return {
    method: "conservative_aabb_grid", floor_y: floorY, radius, height, cell_size: cellSize,
    floor_ids: [...floorIds], grid_cells: total, walkable_cells: regions.reduce((sum, region) => sum + region.cells, 0),
    components: regions, anchor_component: anchor, start, probes,
    disconnected: regions.filter((region) => region.id !== anchor && region.area >= (options.min_area ?? 0.25)),
    assumed_open_doors: assumedDoors,
    warnings: ["Per-floor XZ approximation, not a physics/navmesh guarantee; stairs do not connect different levels.",
      "AABBs overestimate rotated/concave furniture; floor support is sampled at eight points with grid padding.",
      ...(assumedDoors.length ? ["Door leaves are assumed open; doorway openings are estimated as 70% of width and 90% of height."] : []),
      ...(start && start.state !== "walkable" ? ["Start point is not walkable; probe reachability is unknown."] : []),
      ...(!regions.length ? ["No walkable cells for these character dimensions."] : [])],
  };
}