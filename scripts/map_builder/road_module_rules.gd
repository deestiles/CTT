class_name RoadModuleRules
extends RefCounted

const SCHEMA_VERSION := 2
const GRID_SIZE := 5.0
const LANE_WIDTH := 5.0


static func for_id(module_id: String) -> Dictionary:
	match module_id:
		"one_way_street":
			return _rules("straight", 1, 0, Vector2i(1, 1), ["N", "S"], ["continue", "lane_change"])
		"two_way_street_1x1":
			return _rules("straight", 1, 1, Vector2i(2, 1), ["N", "S"], ["continue"])
		"two_way_street_2x2":
			return _rules("straight", 2, 2, Vector2i(4, 1), ["N", "S"], ["continue", "lane_change"])
		"curve_one_way":
			return _rules("curve_90", 1, 0, Vector2i(1, 1), ["S", "E"], ["turn_right"])
		"curve_two_way_1x1":
			return _rules("curve_90", 1, 1, Vector2i(2, 2), ["S", "E"], ["turn_left", "turn_right"])
		"curve_two_way_2x2":
			return _rules("curve_90", 2, 2, Vector2i(4, 4), ["S", "E"], ["turn_left", "turn_right", "lane_change"])
		"one_way_intersection":
			return _rules("intersection_4", 1, 0, Vector2i(1, 1), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"])
		"compact_t_intersection_1x2":
			# A two-cell-wide, one-cell-deep T. N/S are the two-way through road;
			# E is the side-street opening and follows the module when rotated.
			return _rules("intersection_t", 1, 1, Vector2i(2, 1), ["N", "E", "S"], ["continue", "turn_left", "turn_right"])
		"two_way_intersection_1x1":
			return _rules("intersection_4", 1, 1, Vector2i(2, 2), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"])
		"two_way_intersection_2x2":
			return _rules("intersection_4", 2, 2, Vector2i(4, 4), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right", "lane_change"])
	return {}


static func _rules(kind: String, forward_lanes: int, reverse_lanes: int, footprint: Vector2i, ports: Array, actions: Array) -> Dictionary:
	var total_lanes := forward_lanes + reverse_lanes
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": kind,
		"grid_size": GRID_SIZE,
		"lane_width": LANE_WIDTH,
		"lanes_forward": forward_lanes,
		"lanes_reverse": reverse_lanes,
		"total_lanes": total_lanes,
		"road_width": total_lanes * LANE_WIDTH,
		"footprint": [footprint.x, footprint.y],
		"ports": ports,
		"allowed_actions": actions,
		"requires_matching_lane_count": true,
		"allows_dead_end": false,
		"supports_vehicle_spawn": kind == "straight",
		"supports_signal_socket": kind.begins_with("intersection"),
		"surface_layer": "road",
	}


static func rotated_ports(rules: Dictionary, turns: int) -> Array[String]:
	var directions := ["N", "E", "S", "W"]
	var result: Array[String] = []
	for port in rules.get("ports", []):
		result.append(directions[posmod(directions.find(String(port)) - turns, 4)])
	return result


static func compatible(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("total_lanes", 0)) == int(b.get("total_lanes", 0))
		and is_equal_approx(float(a.get("lane_width", 0.0)), float(b.get("lane_width", 0.0)))
	)
