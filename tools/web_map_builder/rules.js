/*
 * rules.js — Faithful port of the game's placement, validation, and spawn-candidate
 * logic from scripts/map_builder/map_builder_test.gd. Operating on a plain model:
 *   item = { id, cell: {x, y}, turns }   turns ∈ 0..3 (quarter turns, clockwise)
 * so that maps produced here validate identically to the in-engine builder.
 */
(function () {
  const { DIRECTIONS, OPPOSITE, PORT_ORDER } = window.CTT;

  const key = (x, y) => x + "," + y;
  const posmod = (a, n) => ((a % n) + n) % n;

  function rotatedFootprint(def, turns) {
    const [w, h] = def.footprint;
    return posmod(turns, 2) === 1 ? { w: h, h: w } : { w, h };
  }

  // _covered_cells_for_turns
  function coveredCells(anchor, def, turns) {
    const { w, h } = rotatedFootprint(def, turns);
    const cells = [];
    for (let x = 0; x < w; x++)
      for (let y = 0; y < h; y++) cells.push({ x: anchor.x + x, y: anchor.y + y });
    return cells;
  }

  // RoadModuleRules.rotated_ports / _rotated_connectors_for
  function rotateDirs(values, turns) {
    return values.map((v) => PORT_ORDER[posmod(PORT_ORDER.indexOf(v) - turns, 4)]);
  }
  function rotatedPorts(rules, turns) { return rotateDirs(rules.ports, turns); }

  function rotatedPortProfile(rules, rotatedPort, turns) {
    const profiles = rules.port_profiles || {};
    for (const [basePort, profile] of Object.entries(profiles)) {
      if (rotateDirs([basePort], turns)[0] === rotatedPort) return profile;
    }
    const total = rules.total_lanes | 0;
    return { incoming: total, outgoing: total, span: total, offset: -1 };
  }

  // Build occupancy (cell -> [item]) and placed (cell -> [def]).
  function buildIndex(items, byId) {
    const occupancy = new Map();
    const placed = new Map();
    for (const it of items) {
      const def = byId[it.id];
      if (!def) continue;
      for (const c of coveredCells(it.cell, def, it.turns)) {
        const k = key(c.x, c.y);
        (occupancy.get(k) || occupancy.set(k, []).get(k)).push(it);
        (placed.get(k) || placed.set(k, []).get(k)).push(def);
      }
    }
    return { occupancy, placed };
  }

  // _port_boundary_cells
  function portBoundaryCells(item, def, direction) {
    const anchor = item.cell;
    const { w, h } = rotatedFootprint(def, item.turns);
    const cells = [];
    if (direction === "N" || direction === "S") {
      const y = direction === "N" ? anchor.y : anchor.y + h - 1;
      for (let x = anchor.x; x < anchor.x + w; x++) cells.push({ x, y });
    } else {
      const x = direction === "W" ? anchor.x : anchor.x + w - 1;
      for (let y = anchor.y; y < anchor.y + h; y++) cells.push({ x, y });
    }
    const profile = rotatedPortProfile(def.module_rules, direction, item.turns);
    const span = Math.max(1, Math.min(cells.length, profile.span || cells.length));
    if (span >= cells.length) return cells;
    const start = Math.max(0, Math.min(cells.length - span,
      profile.offset >= 0 ? profile.offset : Math.floor((cells.length - span) / 2)));
    return cells.slice(start, start + span);
  }

  // _port_lane_count
  function portLaneCount(rules, rotatedPort, turns) {
    if (rules.kind === "intersection_t") {
      const sidePort = ["E", "N", "W", "S"][posmod(turns, 4)];
      if (rotatedPort === sidePort) return 1;
    }
    return rules.total_lanes | 0;
  }

  function isJunction(rules) {
    return !!rules && (rules.kind === "intersection_4" || rules.kind === "intersection_t");
  }

  // _road_ports_compatible
  function roadPortsCompatible(a, aPort, aTurns, b, bPort, bTurns) {
    if (Math.abs((a.lane_width || 0) - (b.lane_width || 0)) >= 1e-4) return false;
    const ap = rotatedPortProfile(a, aPort, aTurns);
    const bp = rotatedPortProfile(b, bPort, bTurns);
    if (ap.span !== bp.span) return false;
    // Junctions route internally: match lane count only. Road-to-road keeps the
    // strict directional handshake so opposing one-way roads still flag head-on.
    if (isJunction(a) || isJunction(b)) return true;
    return ap.outgoing === bp.incoming && ap.incoming === bp.outgoing;
  }

  // _connection_state -> 0 absent, 1 compatible, 2 lane mismatch, 3 direction conflict
  function connectionState(cell, requiredPort, srcRules, srcDef, srcPort, srcTurns, occupancy, byId) {
    const occ = occupancy.get(key(cell.x, cell.y));
    if (!occ) return 0;
    let foundPort = false;
    for (const nb of occ) {
      const def = byId[nb.id];
      if (!def || !def.module_rules) continue;
      const ports = rotatedPorts(def.module_rules, nb.turns);
      if (!ports.includes(requiredPort)) continue;
      foundPort = true;
      if (roadPortsCompatible(srcRules, srcPort, srcTurns, def.module_rules, requiredPort, nb.turns)) return 1;
      // Junctions never have a wrong direction; leftover mismatch there is state 2.
      if (!(isJunction(srcRules) || isJunction(def.module_rules))) {
        const sp = rotatedPortProfile(srcRules, srcPort, srcTurns);
        const np = rotatedPortProfile(def.module_rules, requiredPort, nb.turns);
        if (sp.incoming + sp.outgoing === np.incoming + np.outgoing && sp.span === np.span) return 3;
      }
    }
    return foundPort ? 2 : 0;
  }

  // _footprint_touches_category
  function footprintTouchesCategory(anchor, def, turns, placed, category) {
    const covered = coveredCells(anchor, def, turns);
    const coveredSet = new Set(covered.map((c) => key(c.x, c.y)));
    for (const c of covered) {
      for (const d of Object.values(DIRECTIONS)) {
        const nk = key(c.x + d.x, c.y + d.y);
        if (coveredSet.has(nk)) continue;
        for (const ex of placed.get(nk) || []) if (ex.category === category) return true;
      }
    }
    return false;
  }

  // _can_place — index is built WITHOUT the candidate item.
  function canPlace(anchor, def, turns, index) {
    const { placed } = index;
    for (const c of coveredCells(anchor, def, turns)) {
      const existing = placed.get(key(c.x, c.y)) || [];
      if (def.placement_layer === "surface" || def.placement_layer === "structure") {
        for (const ex of existing) {
          const buildingSidewalkPair =
            (def.category === "Buildings" && ex.category === "Sidewalks") ||
            (def.category === "Sidewalks" && ex.category === "Buildings");
          if (!buildingSidewalkPair) return false;
        }
        continue;
      }
      let hasAllowedBase = def.allowed_base_categories.length === 0;
      for (const ex of existing) {
        if (def.allowed_base_categories.includes(ex.category)) hasAllowedBase = true;
        if (ex.placement_layer === def.placement_layer) return false;
      }
      if (!hasAllowedBase) return false;
    }
    if (
      def.requires_road_edge &&
      !(footprintTouchesCategory(anchor, def, turns, placed, "Roads") ||
        footprintTouchesCategory(anchor, def, turns, placed, "Sidewalks"))
    )
      return false;
    return true;
  }

  // _connected_road_owners (returns item refs)
  function connectedRoadOwners(item, byId, occupancy) {
    const result = [];
    const def = byId[item.id];
    if (!def || !def.module_rules) return result;
    for (const port of rotatedPorts(def.module_rules, item.turns)) {
      for (const ec of portBoundaryCells(item, def, port)) {
        const d = DIRECTIONS[port];
        for (const cand of occupancy.get(key(ec.x + d.x, ec.y + d.y)) || []) {
          const cd = byId[cand.id];
          if (!cd || !cd.module_rules) continue;
          const cports = rotatedPorts(cd.module_rules, cand.turns);
          if (
            cports.includes(OPPOSITE[port]) &&
            roadPortsCompatible(def.module_rules, port, item.turns, cd.module_rules, OPPOSITE[port], cand.turns) &&
            !result.includes(cand)
          )
            result.push(cand);
        }
      }
    }
    return result;
  }

  function largestRoadComponent(roadItems, byId, occupancy) {
    const seen = new Set();
    let largest = new Set();
    for (const seed of roadItems) {
      if (seen.has(seed)) continue;
      const comp = new Set([seed]);
      const queue = [seed];
      seen.add(seed);
      while (queue.length) {
        const it = queue.shift();
        for (const nb of connectedRoadOwners(it, byId, occupancy)) {
          if (!comp.has(nb)) { comp.add(nb); seen.add(nb); queue.push(nb); }
        }
      }
      if (comp.size > largest.size) largest = comp;
    }
    return largest;
  }

  // _fixture_faces_road
  function fixtureFacesRoad(item, byId, occupancy) {
    for (const d of Object.values(DIRECTIONS)) {
      for (const nb of occupancy.get(key(item.cell.x + d.x, item.cell.y + d.y)) || []) {
        const def = byId[nb.id];
        if (def && def.category === "Roads") return true;
      }
    }
    return false;
  }

  // _collect_spawn_candidates
  function collectSpawnCandidates(items, byId, index) {
    const vehicles = [];
    const pedestrians = [];
    for (const it of items) {
      const def = byId[it.id];
      if (!def) continue;
      if (def.module_rules && def.module_rules.kind === "straight") {
        vehicles.push({ cell: [it.cell.x, it.cell.y], turns: it.turns, road_id: def.id });
      } else if (def.id.startsWith("sidewalk")) {
        let blocked = false;
        for (const c of coveredCells(it.cell, def, it.turns)) {
          for (const occ of index.occupancy.get(key(c.x, c.y)) || []) {
            const od = byId[occ.id];
            if (od && ["prop", "character", "structure"].includes(od.placement_layer)) blocked = true;
          }
        }
        if (!blocked) pedestrians.push({ cell: [it.cell.x, it.cell.y], turns: it.turns });
      }
    }
    return { vehicles, pedestrians };
  }

  // _update_validation — returns { result, marks: Map(key -> {reason, severe}) }
  function validate(items, byId) {
    const index = buildIndex(items, byId);
    const { occupancy } = index;
    const marks = new Map();
    const mark = (cell, reason, severe) => {
      const k = key(cell.x, cell.y);
      const prev = marks.get(k);
      if (!prev || (severe && !prev.severe)) marks.set(k, { reason, severe });
    };

    let dangling = 0, incompatible = 0, directionConflicts = 0, fixtureErrors = 0;
    const roadItems = [];
    for (const it of items) {
      const def = byId[it.id];
      if (!def) continue;
      if ((it.id === "street_lamp" || it.id === "traffic_light") && !fixtureFacesRoad(it, byId, occupancy)) {
        fixtureErrors++;
        mark(it.cell, "ROTATE TOWARD ROAD", false);
      }
      if (!def.module_rules) continue;
      roadItems.push(it);
      for (const port of rotatedPorts(def.module_rules, it.turns)) {
        let portConnected = true;
        for (const ec of portBoundaryCells(it, def, port)) {
          const d = DIRECTIONS[port];
          const state = connectionState(
            { x: ec.x + d.x, y: ec.y + d.y }, OPPOSITE[port],
            def.module_rules, def, port, it.turns, occupancy, byId
          );
          if (state === 0) { portConnected = false; mark(ec, "OPEN ROAD END", true); }
          else if (state === 2) { incompatible++; portConnected = false; mark(ec, "LANE MISMATCH", true); }
          else if (state === 3) { directionConflicts++; portConnected = false; mark(ec, "WRONG DIRECTION", true); }
        }
        if (!portConnected) dangling++;
      }
    }

    // disconnected road islands
    const largest = largestRoadComponent(roadItems, byId, occupancy);
    const disconnected = roadItems.length ? roadItems.length - largest.size : 0;
    if (roadItems.length) {
      for (const it of roadItems) {
        if (largest.has(it)) continue;
        // Connectivity is a summary consequence. Mark only the module anchor in
        // amber; exact open/mismatched port cells remain the blocking red cause.
        mark(it.cell, "DISCONNECTED ISLAND", false);
      }
    }

    const spawns = collectSpawnCandidates(items, byId, index);
    const vehicleCount = spawns.vehicles.length;
    const pedestrianCount = spawns.pedestrians.length;
    const spawnErrors = vehicleCount < 2 ? 1 : 0;
    const totalIssues = dangling + incompatible + directionConflicts + disconnected + fixtureErrors + spawnErrors;

    const result = {
      valid: totalIssues === 0,
      issues: totalIssues,
      dangling_ports: dangling,
      lane_mismatches: incompatible,
      direction_conflicts: directionConflicts,
      disconnected_roads: disconnected,
      misoriented_fixtures: fixtureErrors,
      vehicle_spawn_candidates: vehicleCount,
      pedestrian_spawn_candidates: pedestrianCount,
    };
    return { result, marks, spawns, index };
  }

  window.CTT.rules = {
    key, posmod, rotatedFootprint, coveredCells, rotateDirs, rotatedPorts, rotatedPortProfile,
    buildIndex, portBoundaryCells, roadPortsCompatible, connectedRoadOwners,
    canPlace, collectSpawnCandidates, validate,
  };
})();
