/*
 * catalog.js — Faithful port of the game's placeable catalog and road-module
 * contract so the web builder produces maps the mobile game can load unchanged.
 *
 * Sources of truth (keep in sync if the game changes):
 *   scripts/map_builder/map_builder_catalog.gd
 *   scripts/map_builder/road_module_rules.gd
 *   scripts/map_builder/placeable_definition.gd
 */

const GRID_SIZE = 5.0;   // metres per cell (RoadModuleRules.GRID_SIZE)
const LANE_WIDTH = 5.0;  // metres per lane (RoadModuleRules.LANE_WIDTH)
const SCHEMA_VERSION = 2; // RoadModuleRules.SCHEMA_VERSION

// Direction vectors in cell space. +x = East, +y = South (matches Godot's
// DIRECTIONS constant: N=(0,-1), E=(1,0), S=(0,1), W=(-1,0)).
const DIRECTIONS = {
  N: { x: 0, y: -1 },
  E: { x: 1, y: 0 },
  S: { x: 0, y: 1 },
  W: { x: -1, y: 0 },
};
const OPPOSITE = { N: "S", E: "W", S: "N", W: "E" };
const PORT_ORDER = ["N", "E", "S", "W"];

// RoadModuleRules.for_id — returns null for non-road items.
function moduleRulesForId(id) {
  const R = (kind, fwd, rev, footprint, ports, actions) => {
    const total = fwd + rev;
    return {
      schema_version: SCHEMA_VERSION,
      kind,
      grid_size: GRID_SIZE,
      lane_width: LANE_WIDTH,
      lanes_forward: fwd,
      lanes_reverse: rev,
      total_lanes: total,
      road_width: total * LANE_WIDTH,
      footprint: [footprint[0], footprint[1]],
      ports,
      allowed_actions: actions,
      requires_matching_lane_count: true,
      allows_dead_end: false,
      supports_vehicle_spawn: kind === "straight",
      supports_signal_socket: kind.startsWith("intersection"),
      surface_layer: "road",
    };
  };
  switch (id) {
    case "one_way_street":            return R("straight", 1, 0, [1, 1], ["N", "S"], ["continue", "lane_change"]);
    case "two_way_street_1x1":        return R("straight", 1, 1, [2, 1], ["N", "S"], ["continue"]);
    case "two_way_street_2x2":        return R("straight", 2, 2, [4, 1], ["N", "S"], ["continue", "lane_change"]);
    case "curve_one_way":             return R("curve_90", 1, 0, [1, 1], ["S", "E"], ["turn_right"]);
    case "curve_two_way_1x1":         return R("curve_90", 1, 1, [2, 2], ["S", "E"], ["turn_left", "turn_right"]);
    case "curve_two_way_2x2":         return R("curve_90", 2, 2, [4, 4], ["S", "E"], ["turn_left", "turn_right", "lane_change"]);
    case "one_way_intersection":      return R("intersection_4", 1, 0, [1, 1], ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"]);
    case "compact_t_intersection_1x2":return R("intersection_t", 1, 1, [2, 1], ["N", "E", "S"], ["continue", "turn_left", "turn_right"]);
    case "two_way_intersection_1x1":  return R("intersection_4", 1, 1, [2, 2], ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"]);
    case "two_way_intersection_2x2":  return R("intersection_4", 2, 2, [4, 4], ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right", "lane_change"]);
    default:                          return null;
  }
}

// Mirror of MapBuilderCatalog.create_default(). `footprint` is [w,h].
// layer ∈ surface | structure | prop | vehicle | character.
function createCatalog() {
  const def = (o) => ({
    id: o.id,
    display_name: o.name,
    category: o.category,
    scene_path: o.scene || "",
    footprint: o.footprint || [1, 1],
    connectors: o.connectors || [],
    requires_road_edge: !!o.requires_road_edge,
    corner_pivot: o.corner_pivot !== undefined ? o.corner_pivot : true,
    placement_layer: o.layer || "surface",
    allowed_base_categories: o.base || [],
    traffic_directions: o.traffic || [],
    module_rules: moduleRulesForId(o.id),
  });

  return [
    // ---- Roads (surface) ----
    def({ id: "one_way_street", name: "One-Way Street", category: "Roads", footprint: [1, 1], connectors: ["N", "S"], traffic: ["N"] }),
    def({ id: "two_way_street_1x1", name: "Two-Way: 1 Lane Each Direction", category: "Roads", footprint: [2, 1], connectors: ["N", "S"], traffic: ["N", "S"] }),
    def({ id: "two_way_street_2x2", name: "Two-Way: 2 Lanes Each Direction", category: "Roads", footprint: [4, 1], connectors: ["N", "S"], traffic: ["N", "S"] }),
    def({ id: "curve_one_way", name: "Curve: One-Way", category: "Roads", footprint: [1, 1], connectors: ["S", "E"], traffic: ["S", "E"] }),
    def({ id: "curve_two_way_1x1", name: "Curve: 1 Lane Each Direction", category: "Roads", footprint: [2, 2], connectors: ["S", "E"], traffic: ["S", "E"] }),
    def({ id: "curve_two_way_2x2", name: "Curve: 2 Lanes Each Direction", category: "Roads", footprint: [4, 4], connectors: ["S", "E"], traffic: ["S", "E"] }),
    def({ id: "one_way_intersection", name: "One-Way Intersection", category: "Roads", footprint: [1, 1], connectors: ["N", "E", "S", "W"], traffic: ["N", "E", "S", "W"] }),
    def({ id: "compact_t_intersection_1x2", name: "Intersection: 2 Squares (T)", category: "Roads", footprint: [2, 1], connectors: ["N", "E", "S"], traffic: ["N", "S"] }),
    def({ id: "two_way_intersection_1x1", name: "Intersection: 1 Lane Each Way", category: "Roads", footprint: [2, 2], connectors: ["N", "E", "S", "W"], traffic: ["N", "E", "S", "W"] }),
    def({ id: "two_way_intersection_2x2", name: "Intersection: 2 Lanes Each Way", category: "Roads", footprint: [4, 4], connectors: ["N", "E", "S", "W"], traffic: ["N", "E", "S", "W"] }),
    // ---- Sidewalks (surface) ----
    def({ id: "sidewalk", name: "Sidewalk — Straight", category: "Sidewalks" }),
    def({ id: "sidewalk_corner", name: "Sidewalk — Corner 01", category: "Sidewalks" }),
    def({ id: "sidewalk_corner_02", name: "Sidewalk — Corner 02", category: "Sidewalks" }),
    // ---- Buildings (structure) ----
    def({ id: "shop", name: "Shop Building (2×2)", category: "Buildings", footprint: [2, 2], requires_road_edge: true, layer: "structure" }),
    def({ id: "apartment", name: "Apartment Building (2×2)", category: "Buildings", footprint: [2, 2], requires_road_edge: true, layer: "structure" }),
    // ---- Street Fixtures (prop, layer on sidewalks) ----
    def({ id: "street_lamp", name: "Street Lamp", category: "Street Fixtures", corner_pivot: false, layer: "prop", base: ["Sidewalks"] }),
    def({ id: "traffic_light", name: "Traffic Light", category: "Street Fixtures", corner_pivot: false, layer: "prop", base: ["Sidewalks"] }),
    // ---- Vehicles (layer on roads) ----
    def({ id: "police_car", name: "Police Car", category: "Vehicles", corner_pivot: false, layer: "vehicle", base: ["Roads"] }),
    def({ id: "sedan", name: "Civilian Sedan", category: "Vehicles", corner_pivot: false, layer: "vehicle", base: ["Roads"] }),
    // ---- Pedestrians (layer on sidewalks) ----
    def({ id: "pedestrian", name: "Pedestrian", category: "Pedestrians", corner_pivot: false, layer: "character", base: ["Sidewalks"] }),
  ];
}

// Category display order for the palette (logical grouping).
const CATEGORY_ORDER = ["Roads", "Sidewalks", "Buildings", "Street Fixtures", "Vehicles", "Pedestrians"];

if (typeof window !== "undefined") {
  window.CTT = window.CTT || {};
  Object.assign(window.CTT, {
    GRID_SIZE, LANE_WIDTH, SCHEMA_VERSION, DIRECTIONS, OPPOSITE, PORT_ORDER,
    moduleRulesForId, createCatalog, CATEGORY_ORDER,
  });
}
