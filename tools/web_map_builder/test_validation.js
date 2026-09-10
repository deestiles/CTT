"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = __dirname;
const context = { window: {} };
vm.createContext(context);
for (const file of ["catalog.js", "rules.js"])
  vm.runInContext(fs.readFileSync(path.join(root, file), "utf8"), context, { filename: file });

const C = context.window.CTT;
const catalog = C.createCatalog();
const byId = Object.fromEntries(catalog.map((entry) => [entry.id, entry]));
const item = (id, x, y, turns = 0) => ({ id, cell: { x, y }, turns });

function assertNetwork(name, items) {
  const checked = C.rules.validate(items, byId).result;
  if (checked.lane_mismatches || checked.direction_conflicts || checked.disconnected_roads) {
    throw new Error(`${name} failed: ${JSON.stringify(checked)}`);
  }
  console.log(`PASS ${name}`);
}

assertNetwork("one-way 1-to-2 transition", [
  item("one_way_street_2_lane", 0, -1),
  item("transition_one_way_1_to_2", 0, 0),
  item("one_way_street", 0, 3),
]);

assertNetwork("two-way 1-each to 2-each transition", [
  item("two_way_street_2x2", 0, -1),
  item("transition_two_way_1_to_2", 0, 0),
  item("two_way_street_1x1", 1, 3),
]);

assertNetwork("four-lane main with one-way side T", [
  item("two_way_street_2x2", 0, -1),
  item("t_main_4_side_1", 0, 0),
  item("two_way_street_2x2", 0, 2),
  item("one_way_street", 4, 0, 1),
]);

assertNetwork("two-way four-lane curve", [
  item("curve_two_way_2x2", 0, 0),
  item("two_way_street_2x2", 0, 4),
  item("two_way_street_2x2", 4, 0, 1),
]);

assertNetwork("one-way two-lane curve", [
  item("curve_one_way_2_lane", 0, 0),
  item("one_way_street_2_lane", 0, 2),
  item("one_way_street_2_lane", 2, 0, 3),
]);

// Regression: a junction routes internally, so a one-way arm may flow INTO or
// OUT OF it without a direction conflict. Previously this flagged valid maps
// (e.g. city_map) as "WRONG DIRECTION" at one-way -> compact-T side ports.
function assertNoDirectionConflict(name, items) {
  const c = C.rules.validate(items, byId).result;
  if (c.direction_conflicts)
    throw new Error(`${name} should have no direction conflicts: ${JSON.stringify(c)}`);
  console.log(`PASS ${name}`);
}

// compact-T at (0,0) covers (0,0),(1,0); its E side neighbours cell (2,0).
// turns 3 vs 1 point the one-way's flow into vs out of the junction.
assertNoDirectionConflict("one-way flowing INTO compact-T side", [
  item("compact_t_intersection_1x2", 0, 0),
  item("one_way_street", 2, 0, 3),
]);
assertNoDirectionConflict("one-way flowing OUT OF compact-T side", [
  item("compact_t_intersection_1x2", 0, 0),
  item("one_way_street", 2, 0, 1),
]);
assertNoDirectionConflict("one-way arms on a one-way intersection", [
  item("one_way_intersection", 0, 0),
  item("one_way_street", 0, -1),
  item("one_way_street", 0, 1),
]);

// A real head-on collision between two opposing one-way straights MUST still flag.
(function assertHeadOnStillCaught() {
  const c = C.rules.validate(
    [item("one_way_street", 0, 0, 0), item("one_way_street", 0, 1, 2)],
    byId
  ).result;
  if (!c.direction_conflicts) throw new Error("head-on one-way collision should flag a direction conflict");
  console.log("PASS head-on one-way still flags a conflict");
})();

// Left-hand one-way curve lets a one-way loop run counter-clockwise.
(function ccwLoopWithLeftCurves() {
  const x0 = 0, x1 = 2, y0 = 0, y1 = 2, its = [];
  for (let x = x0 + 1; x < x1; x++) its.push(item("one_way_street", x, y0, 1)); // top, flow W
  for (let x = x0 + 1; x < x1; x++) its.push(item("one_way_street", x, y1, 3)); // bottom, flow E
  for (let y = y0 + 1; y < y1; y++) its.push(item("one_way_street", x0, y, 2)); // left, flow S
  for (let y = y0 + 1; y < y1; y++) its.push(item("one_way_street", x1, y, 0)); // right, flow N
  for (const [cx, cy] of [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]) {
    const it = { id: "curve_one_way_left", cell: { x: cx, y: cy }, turns: 0 };
    its.push(it);
    let best = 0, bv = Infinity;
    for (let t = 0; t < 4; t++) { it.turns = t; const v = C.rules.validate(its, byId).result.issues; if (v < bv) { bv = v; best = t; } }
    it.turns = best;
  }
  const r = C.rules.validate(its, byId).result;
  if (!r.valid) throw new Error("CCW loop with left curves should validate: " + JSON.stringify(r));
  console.log("PASS counter-clockwise one-way loop with left curves validates");
})();

// A road adjacent but with ports that don't line up reports state 4 (not a bare open end).
(function portsDontMeet() {
  const r = C.rules.validate([item("one_way_street", 0, 0, 0), item("curve_one_way", 0, 1, 0)], byId).result;
  if (!(r.misaligned_ports > 0)) throw new Error('expected misaligned_ports > 0: ' + JSON.stringify(r));
  console.log("PASS misaligned-port case detected (ports don't meet)");
})();

// One-way MERGE (2->1): a 2-lane one-way road narrows back to 1 lane.
assertNetwork("one-way 2-to-1 merge", [
  item("one_way_street_2_lane", 0, -1, 2), // 2-lane one-way flowing south into the merge's wide N port
  item("transition_one_way_2_to_1", 0, 0),  // wide N intake -> narrow S output
  item("one_way_street", 0, 3, 2),          // 1-lane one-way continuing south
]);

console.log("WEB_MAP_VALIDATION_TESTS: PASS");
